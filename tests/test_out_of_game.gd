extends "res://tests/test_case.gd"
## Out-of-game layer: data migration, menu skip rules, settings, controls/rebinding,
## gamepad mapping, lobby registry (server browser), UPnP helpers, advertiser info.

const Launch := preload("res://src/ui/launch.gd")
const Settings := preload("res://src/ui/settings_store.gd")
const Controls := preload("res://src/ui/controls.gd")
const Registry := preload("res://src/net/lobby_registry.gd")
const PortMapper := preload("res://src/net/port_mapper.gd")
const Advertiser := preload("res://src/net/lobby_advertiser.gd")
const Lobby := preload("res://src/net/lobby.gd")
const Menu := preload("res://src/ui/main_menu.gd")
const GameOverview := preload("res://src/ui/game_overview.gd")

const TMP := "user://test_ooo"

func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		d.remove(f)
	for s in d.get_directories():
		_rm(path.path_join(s))
	DirAccess.remove_absolute(path)

func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)

func test_migrate_copies_real_data_skips_test_artifacts() -> void:
	_rm(TMP)
	var old := ProjectSettings.globalize_path(TMP + "/old")
	var new := ProjectSettings.globalize_path(TMP + "/new")
	_write(old + "/profile.json", "{\"xp\": 900}")
	_write(old + "/leaderboard.json", "{}")
	_write(old + "/test_profile.json", "x")
	_write(old + "/replays/2026-11-25_match.json", "r")
	_write(old + "/test_flow_replays/a.json", "t")
	_write(new + "/leaderboard.json", "NEWER")
	var copied := Launch.migrate(old, new)
	assert_eq(FileAccess.get_file_as_string(new + "/profile.json"), "{\"xp\": 900}", "profile migrated")
	assert_eq(FileAccess.get_file_as_string(new + "/leaderboard.json"), "NEWER", "never overwrites")
	assert_true(FileAccess.file_exists(new + "/replays/2026-11-25_match.json"), "replays migrated")
	assert_true(not FileAccess.file_exists(new + "/test_profile.json"), "test_* files skipped")
	assert_true(not DirAccess.dir_exists_absolute(new + "/test_flow_replays"), "test replay dir skipped")
	assert_eq(copied.size(), 2, "copied count")
	# second run is a no-op (marker), even if the old dir gained files
	_write(old + "/ranked.json", "{}")
	assert_eq(Launch.migrate(old, new).size(), 0, "runs once")
	assert_eq(Launch.migrate(old + "/missing", ProjectSettings.globalize_path(TMP + "/n2")).size(), 0, "no old dir")
	_rm(TMP)

func test_menu_skipped_for_cli_and_headless() -> void:
	assert_true(Launch.should_skip_menu(PackedStringArray(), "headless"), "headless skips")
	assert_true(not Launch.should_skip_menu(PackedStringArray(), "x11"), "plain launch shows menu")
	assert_true(not Launch.should_skip_menu(PackedStringArray(["--settings-file=a.cfg", "--no-migrate"]), "x11"), "menu-only flags")
	assert_true(Launch.should_skip_menu(PackedStringArray(["--host"]), "x11"), "--host skips")
	assert_true(Launch.should_skip_menu(PackedStringArray(["--join=ABCDE-FGHJK"]), "windows"), "--join skips")

func test_settings_roundtrip_and_validation() -> void:
	var path := TMP + "_settings.cfg"
	var s := Settings.new()
	s.player_name = "Ace"
	assert_eq(s.display_mode, "borderless", "fullscreen by default")
	s.display_mode = "windowed"
	s.render_scale = 0.75
	s.max_fps = 144
	s.master_volume = 0.3
	s.matchmaker = "mm.example.net:24600"
	s.upnp = false
	s.bindings = {"snap": KEY_K}
	assert_true(s.save(path), "saved")
	var t := Settings.new()
	t.load_file(path)
	assert_eq([t.player_name, t.display_mode, t.render_scale, t.max_fps, t.master_volume, t.matchmaker, t.upnp, t.bindings],
		["Ace", "windowed", 0.75, 144, 0.3, "mm.example.net:24600", false, {"snap": KEY_K}], "roundtrip")
	# corrupt values are clamped / defaulted
	var cf := ConfigFile.new()
	cf.set_value("video", "fullscreen", false)  # saved by older releases
	cf.save(path)
	var legacy := Settings.new()
	legacy.load_file(path)
	assert_eq(legacy.display_mode, "borderless", "legacy settings get the new default")
	cf.set_value("video", "display_mode", "invalid")
	cf.set_value("video", "render_scale", 9.0)
	cf.set_value("video", "max_fps", 77)
	cf.set_value("online", "matchmaker", "  ")
	cf.set_value("controls", "bindings", "junk")
	cf.save(path)
	var u := Settings.new()
	u.load_file(path)
	assert_eq([u.render_scale, u.max_fps, u.matchmaker, u.bindings], [1.0, 0, Settings.DEFAULT_MM, {}], "sanitized")
	assert_eq(u.display_mode, "borderless", "invalid display mode falls back")
	DirAccess.remove_absolute(path)
	assert_eq(Settings.clean_name("  Ben|ny  "), "Benny", "strips separator")
	assert_eq(Settings.clean_name("x"), "", "too short")
	assert_eq(Settings.clean_name("Bot"), "", "reserved")
	assert_eq(Settings.clean_name("ABCDEFGHIJKLMNOPQRSTU"), "ABCDEFGHIJKLMNOP", "16 max")
	assert_eq(Settings.split_address("mm.x.net:25000", 1), ["mm.x.net", 25000], "host:port")
	assert_eq(Settings.split_address("10.0.0.2", 24600), ["10.0.0.2", 24600], "default port")

func test_controls_rebind_moves_and_swaps() -> void:
	var b := Controls.rebind({}, "snap", KEY_K)
	assert_eq(b, {"snap": KEY_K}, "rebind to free key")
	var tr := Controls.translation(b)
	assert_eq(tr.get(KEY_K), KEY_SPACE, "K acts as snap")
	assert_eq(tr.get(KEY_SPACE), KEY_NONE, "old key disabled (moved, not duplicated)")
	# rebinding to a key in use swaps
	var c := Controls.rebind({}, "snap", KEY_F)
	assert_eq(Controls.key_for("snap", c), KEY_F, "snap on F")
	assert_eq(Controls.key_for("tackle", c), KEY_SPACE, "tackle (dive) took Space")
	var tc := Controls.translation(c)
	assert_eq([tc.get(KEY_F), tc.get(KEY_SPACE)], [KEY_SPACE, KEY_F], "swap translation")
	# swapping back restores defaults (no leftover overrides)
	assert_eq(Controls.rebind(c, "snap", KEY_SPACE), {}, "back to defaults")
	assert_eq(Controls.translation({}), {}, "defaults translate nothing")
	assert_eq(Controls.action_for_key(KEY_TAB, {}), "scoreboard", "lookup")

func test_gamepad_mapping() -> void:
	assert_eq(Controls.default_key(Controls.PAD_BUTTONS[JOY_BUTTON_A]), KEY_SPACE, "A snaps")
	assert_eq(Controls.default_key(Controls.PAD_TRIGGERS[JOY_AXIS_TRIGGER_RIGHT]), KEY_J, "RT throws")
	var k := Controls.stick_keys(Vector2(0.9, -0.8))
	assert_true(k[KEY_D] and k[KEY_W] and not k[KEY_A] and not k[KEY_S], "up-right")
	var z := Controls.stick_keys(Vector2(0.2, 0.1))
	assert_true(not (z[KEY_W] or z[KEY_A] or z[KEY_S] or z[KEY_D]), "deadzone")
	var snap_line: Array = Array(Controls.help_text({"snap": KEY_K}).split("\n")).filter(
		func(l): return l.strip_edges().begins_with("Snap"))
	assert_true(not snap_line.is_empty() and snap_line[0].ends_with(" K"), "help shows bound key: %s" % str(snap_line))

func test_registry_lists_validates_expires() -> void:
	var r := Registry.new()
	assert_true(r.register(1, {"code": "AAAAA-BBBBB", "name": "Ann's match", "size": 5, "players": 2}, 0.0), "valid")
	assert_true(not r.register(2, {"code": "x", "size": 5}, 0.0), "bad code rejected")
	assert_true(not r.register(3, {"code": "CCCCC-DDDDD", "size": 4}, 0.0), "bad size rejected")
	r.register(4, {"code": "EEEEE-FFFFF", "size": 3, "players": 6, "mode": "chaosball"}, 0.0)
	r.register(5, {"code": "GGGGG-HHHHH", "size": 7, "players": 9, "in_game": true}, 0.0)
	r.register(6, {"code": "JJJJJ-KKKKK", "size": 7, "players": 4, "mode": "evil"}, 0.0)
	var l := r.listing(1.0)
	assert_eq(l.map(func(e): return e["code"]), ["JJJJJ-KKKKK", "AAAAA-BBBBB", "EEEEE-FFFFF", "GGGGG-HHHHH"],
		"open+fullest first, full next, in-progress last")
	assert_eq(l[0]["mode"], "classic", "unknown mode sanitized")
	assert_true(not l[0].has("seen"), "internal fields hidden")
	r.register(1, {"code": "AAAAA-BBBBB", "size": 5, "players": 3}, 15.0)   # refresh
	assert_eq(r.listing(Registry.TTL + 5.0).size(), 1, "stale lobbies expire, refreshed stays")
	r.remove(1)
	assert_eq(r.listing(0.0).size(), 0, "removed")

func test_public_ip_detection() -> void:
	for ip in ["8.8.8.8", "73.12.1.200", "172.32.0.1"]:
		assert_true(PortMapper.is_public_ipv4(ip), ip + " public")
	for ip in ["10.1.2.3", "192.168.1.5", "172.16.4.4", "100.64.0.9", "127.0.0.1", "169.254.1.1", "", "1.2.3"]:
		assert_true(not PortMapper.is_public_ipv4(ip), ip + " not public")

class FakeGame extends Node:
	var lobby

func test_advertiser_reports_lobby() -> void:
	var g := FakeGame.new()
	assert_eq(Advertiser.lobby_info(g, "T"), null, "no lobby yet")
	g.lobby = Lobby.new()
	g.lobby.code = "AAAAA-BBBBB"
	g.lobby.settings["size"] = 5
	g.lobby.add(1, "Ann")
	g.lobby.add(2, "Ben")
	var info = Advertiser.lobby_info(g, "Ann's match")
	assert_eq([info["code"], info["size"], info["players"], info["in_game"], info["name"]],
		["AAAAA-BBBBB", 5, 2, false, "Ann's match"], "info")
	g.lobby.phase = Lobby.Phase.IN_GAME
	assert_true(Advertiser.lobby_info(g, "x")["in_game"], "in game")
	g.free()

func test_replay_listing_newest_first_skips_tests() -> void:
	_rm(TMP + "_rp")
	for f in ["2026-11-20_a.json", "2026-11-25_b.json", "test_x.json"]:
		_write(TMP + "_rp/" + f, "{}")
	var l := Menu.list_replays(TMP + "_rp")
	assert_eq(l.map(func(p): return p.get_file()), ["2026-11-25_b.json", "2026-11-20_a.json"], "order")
	_rm(TMP + "_rp")

func test_game_overview_box_score_keeps_readable_team_columns() -> void:
	var panel := VBoxContainer.new()
	var overview := GameOverview.build(panel, {
		"team_names": ["HELIOS", "NEBULA"],
		"teams": [{"rush_yds": 40}, {"rush_yds": 70}],
	})
	var grid := overview.find_child("BoxScore", true, false) as GridContainer
	assert_true(grid != null, "the overview includes the team stats grid")
	if grid != null:
		var inset := grid.get_parent() as MarginContainer
		assert_true(inset != null and inset.get_theme_constant("margin_right") >= 8,
			"team stats leave a gutter next to the scrollbar")
		assert_eq(grid.columns, 3, "stat name plus two team columns")
		assert_eq(grid.get_child_count(), 21, "headers and six rows")
		for team in 2:
			var header := grid.get_child(team + 1) as Label
			var rush_yards := grid.get_child(team + 7) as Label
			assert_eq(header.text, ["HELIOS", "NEBULA"][team])
			assert_eq(rush_yards.text, ["40", "70"][team])
			assert_eq(header.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT)
			assert_eq(rush_yards.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT)
	panel.free()
