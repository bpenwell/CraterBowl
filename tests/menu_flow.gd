extends SceneTree
## Out-of-game flow through the real menu scene + Launch autoload + an in-process
## matchmaker: first-run name, server browser, every launch path, public hosting,
## leave to menu, rebinding via real key events, gamepad, Esc overlay.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/menu_flow.gd -- --settings-file=user://test_menu_settings.cfg

const MMServer := preload("res://src/net/mm_server.gd")
const MMClient := preload("res://src/net/mm_client.gd")
# Random per run (override: MENU_MM_PORT): fixed ports made parallel smoke runs from different
# sessions/worktrees collide ("matchmaker up" failed). Same pattern as net_test.sh / mm_test.sh.
var MM_PORT := int(OS.get_environment("MENU_MM_PORT")) if OS.get_environment("MENU_MM_PORT") != "" else 26000 + (Time.get_ticks_usec() + OS.get_process_id() * 7) % 1800 * 2
var HOST_PORT := MM_PORT + 1

class MenuWithFailedMapping extends "res://src/ui/main_menu.gd":
	func _open_port_async(_port: int, cb: Callable) -> Thread:
		var worker := Thread.new()
		worker.start(func(): cb.call_deferred({"ok": false, "error": "No UPnP router found"}))
		return worker

class Rec:
	var opts := {}
	var real
	var settings:
		get: return real.settings
	func start_game(o: Dictionary) -> void: opts = o
	func save_settings() -> void: real.save_settings()
	func version() -> String: return real.version()

var launch
var menu
var mms
var fake_host
var rec := Rec.new()
var frame := 0
var ok := true
var steps: Array = []

func check(cond: bool, msg: String) -> void:
	print(("  MENU OK   " if cond else "  MENU FAIL ") + msg)
	if not cond:
		ok = false

func _btn(root_node: Node, text: String) -> Button:
	for n in root_node.find_children("*", "Button", true, false):
		if n.text.to_upper() == text.to_upper():
			return n
	return null

## #83: the Size row's state as "<pressed size>/<enabled|disabled>", e.g. "7/enabled".
func _size_row(root_node: Node) -> String:
	var on := []
	var enabled := 0
	for s in [3, 5, 7]:
		var b := _btn(root_node, "%dv%d" % [s, s])
		if b == null:
			return "missing %dv%d" % [s, s]
		if b.button_pressed:
			on.append(s)
		if not b.disabled:
			enabled += 1
	return "%s/%s" % [",".join(on), "enabled" if enabled == 3 else ("disabled" if enabled == 0 else "mixed")]

func _key(code: int, pressed: bool = true) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	root.push_input(ev)

func _initialize() -> void:
	steps = [[1, _setup]]

## #217: freeing an in-tree Label3D (or its parent) right after a render-instance update
## must not log the dummy renderer's `Parameter "m" is null`; smoke.sh fails on that line.
## Launch's HeadlessMeshGuard flushes the update while the Label3D's own mesh is alive.
func _add_label3ds() -> void:
	check(launch.get_children().any(func(c): return c.get_script() == launch.HeadlessMeshGuard), "headless mesh guard running")
	var field := Node3D.new()
	field.name = "LabelField217"
	root.add_child(field)
	for i in 3:
		var l := Label3D.new()
		l.text = "YD %d" % i
		field.add_child(l)

## Each free runs a frame after the labels' last update: a Label3D builds its mesh deferred.
func _free_in_tree_label3d() -> void:
	var field := root.get_node("LabelField217")
	field.get_child(0).free()
	for l in field.get_children():   # re-enter the world: queues a fresh instance update
		field.remove_child(l)
		field.add_child(l)

func _free_label3d_parent() -> void:
	root.get_node("LabelField217").queue_free()

func _setup() -> void:
	launch = root.get_node("Launch")
	rec.real = launch
	check(launch.settings_path == "user://test_menu_settings.cfg", "test settings file in use")
	launch.settings = launch.SettingsStore.new()   # fresh: no name yet
	launch.settings.matchmaker = "127.0.0.1:%d" % MM_PORT
	launch.settings.upnp = false                  # never touch a real router from tests
	mms = MMServer.new()
	mms.name = "TestMM"
	root.add_child(mms)
	check(mms.start(MM_PORT) == OK, "matchmaker up")
	menu = load("res://scenes/menu.tscn").instantiate()
	menu.set_script(MenuWithFailedMapping)
	menu.set_meta("force_menu", true)
	menu.profile_path = "user://test_menu_profile.json"
	menu.leaderboard_path = "user://test_menu_lb.json"
	menu.ranked_path = "user://test_menu_ranked.json"
	menu.replay_dir = "user://test_menu_replays"
	menu.host_port = HOST_PORT
	root.add_child(menu)
	current_scene = menu
	steps += [
		[2, _add_label3ds],
		[3, _free_in_tree_label3d],
		[3, func(): check(menu.current == "welcome", "first run asks for a name")],
		[4, _free_label3d_parent],
		[4, func():
			menu.content.find_child("NameEdit", true, false).text = "x"
			_btn(menu.content, "Continue").pressed.emit()
			check(menu.current == "welcome" and menu.status_label.text.find("2-16") >= 0, "bad name rejected")],
		[5, func():
			menu.content.find_child("NameEdit", true, false).text = "Ace"
			_btn(menu.content, "Continue").pressed.emit()
			check(menu.current == "home" and not menu.panel.visible, "name accepted -> home lobby")
			check(menu.lobby.hero != null, "lobby shows the player's athlete")
			menu.launch = rec
			menu.cycle_mode()
			check(menu.mode_id == "bots3" and launch.settings.home_mode == "bots3", "TAB cycles + remembers mode")
			menu._set_mode("chaos")
			menu.play_button.pressed.emit()
			check(rec.opts == {"size": "3", "mode": "chaosball"}, "PLAY launches selected mode %s" % str(rec.opts))
			menu._set_mode("scrimmage")
			menu.play_selected()
			check(rec.opts == {"practice": "scrimmage"}, "PLAY practice mode")
			menu._set_mode("bots5")
			menu.launch = launch
			menu.show_screen("online")
			check(menu.panel.visible and menu.current == "online", "online tab opens the side panel")
			check(launch.settings.player_name == "Ace" and FileAccess.file_exists("user://test_menu_settings.cfg"), "name saved")],
		[6, func():
			fake_host = MMClient.new()
			root.add_child(fake_host)
			fake_host.connected.connect(func(): fake_host.register_lobby({"code": "AAAAA-BBBBB", "name": "Zed's match", "size": 5, "players": 3}))
			fake_host.open("127.0.0.1", MM_PORT)],
		[300, func():
			var b = menu.browser
			check(b != null and b.state == "online", "browser connected to matchmaker")
			check(b != null and b.last_list.size() == 1 and b.last_list[0]["name"] == "Zed's match", "browser lists the public lobby")
			menu.launch = rec
			var j := _btn(b, "Join")
			check(j != null, "join button shown")
			if j: j.pressed.emit()
			check(rec.opts == {"join": "AAAAA-BBBBB"}, "browser join -> join by code %s" % str(rec.opts))],
		[301, func():
			var code: LineEdit = menu.content.find_child("JoinCode", true, false)
			code.text = "nope"
			_btn(menu.content, "Join").pressed.emit()
			check(menu.status_label.text.find("invite code") >= 0, "bad code rejected")
			var real_code: String = preload("res://src/net/invite_code.gd").encode("10.0.0.5", 24565)
			code.text = "  " + real_code.to_lower() + " "
			rec.opts = {}
			_btn(menu.content, "Join").pressed.emit()
			check(rec.opts == {"join": real_code}, "manual join normalizes code %s" % str(rec.opts))
			_btn(menu.content, "Quick match").pressed.emit()
			check(rec.opts.get("queue") == "casual" and rec.opts.get("mm") == "127.0.0.1:%d" % MM_PORT and rec.opts.get("host-port") == "24566", "quick match -> casual queue %s" % str(rec.opts))
			_btn(menu.content, "Ranked").pressed.emit()
			check(rec.opts.get("queue") == "competitive", "ranked -> competitive queue")
			var ps: OptionButton = menu.content.find_child("PartySize", true, false)
			ps.select(2)
			ps.item_selected.emit(2)
			var pc: LineEdit = menu.content.find_child("PartyCode", true, false)
			check(pc.text.length() == 5 and pc.editable, "party gets a code")
			pc.text = "abc12"
			pc.text_changed.emit("abc12")
			_btn(menu.content, "Chaosball (3v3, low-g)").pressed.emit()
			_btn(menu.content, "Quick match").pressed.emit()
			check(rec.opts.get("party") == "ABC12:3" and rec.opts.get("mode") == "chaosball" and rec.opts.get("size") == "3",
				"party + chaosball queue %s" % str(rec.opts))
			menu.pick_mode = "classic"
			menu.party_size = 1],
		[302, func():
			menu.show_screen("practice")
			_btn(menu.content, "Tackling").pressed.emit()
			check(rec.opts == {"practice": "tackling"}, "practice launch")
			menu.show_screen("bots")
			_btn(menu.content, "3v3").pressed.emit()
			_btn(menu.content, "Chaosball (3v3, low-g)").pressed.emit()
			_btn(menu.content, "Kick off").pressed.emit()
			check(rec.opts == {"size": "3", "mode": "chaosball"}, "vs bots launch %s" % str(rec.opts))
			for s in ["locker", "leaders", "replays", "settings"]:
				menu.show_screen(s)
				check(menu.current == s and menu.content.get_child_count() > 1, "%s screen builds" % s)],
		[303, func():
			menu.launch = launch
			_btn(menu.content, "Snap / hike")
			var mode: OptionButton = menu.content.find_child("DisplayMode", true, false)
			check(mode.item_count == 3 and mode.get_item_text(mode.selected) == "Borderless fullscreen",
				"three display modes with borderless fullscreen selected by default")
			for i in [1, 2, 0]:
				mode.select(i)
				mode.item_selected.emit(i)
				var saved = launch.SettingsStore.new()
				saved.load_file(launch.settings_path)
				check(saved.display_mode == ["borderless", "exclusive", "windowed"][i],
					"display preference saved for " + mode.get_item_text(i))
			var bind: Button = menu.content.find_child("Bind_snap", true, false)
			bind.pressed.emit()
			_key(KEY_K)],
		[306, func():
			check(launch.settings.bindings.get("snap") == KEY_K, "rebind through real key press")
			check(launch._xlate.get(KEY_K) == KEY_SPACE, "translation live")
			menu.show_screen("online")
			menu.pick_size = 3
			menu.pick_mode = "classic"   # earlier steps picked Chaosball; this host covers classic size
			menu.list_public = true
			launch.settings.upnp = true
			menu.host_match()],
		[420, func():
			var g = current_scene
			check(g != null and g.scene_file_path == launch.GAME_SCENE, "host -> game scene")
			check(g.is_server() and g.lobby.code != "", "hosting a lobby (%s)" % g.lobby.code)
			check(g.hud.text.contains("No UPnP router found") and g.hud.text.contains("UDP port %d" % HOST_PORT),
				"host lobby shows the UPnP failure and custom UDP port")
			check(g.match_size == 3 and g.lobby.settings.get("size") == 3, "size from menu")
			check(g.lobby.settings.get("mode") == "classic", "classic pick hosts a classic lobby")
			check(g.player_name == "Ace", "name from settings")
			check(g.get_node_or_null("Advertiser") != null, "public lobby advertiser attached")],
		[800, func():
			var l: Array = mms.registry.listing(mms._now())
			var mine := l.filter(func(e): return e["name"] == "Ace's match")
			check(mine.size() == 1 and mine[0]["code"] == current_scene.lobby.code and mine[0]["size"] == 3, "public lobby registered %s" % str(mine))
			launch.go_to_menu("Left match")],
		[830, func():
			check(current_scene != null and current_scene.scene_file_path == launch.MENU_SCENE, "leave -> back at menu")
			check(current_scene.current == "home" and launch.last_match.is_empty(), "leaving mid-match shows no overview")
			launch.go_to_menu("", {"score": [21, 14], "winner": 0, "my_team": 0, "team_names": ["HELIOS", "NEBULA"],
				"mode": "classic", "size": 5, "me": "Ace", "my_lines": ["QB: 12/18 160yd 2TD 0INT"], "xp": "XP +120 (Level 2)",
				"teams": [{"pass_yds": 160, "rush_yds": 40, "td": 3}, {"pass_yds": 90, "rush_yds": 70, "td": 2}],
				"potg": [{"id": 1, "team": 0, "pos": "QB", "name": "Ace", "number": 12, "title": "PLAYER OF THE GAME", "lines": ["12/18  160 YDS  2 TD"]},
					{"id": 9, "team": 1, "pos": "LB", "name": "CPU", "number": 44, "title": "DEFENSIVE STANDOUT", "lines": ["7 TKL  1 SACK"]}]})],
		[860, func():
			var m = current_scene
			check(m.current == "overview" and m.panel.visible, "post-game return opens the game overview")
			var ov = m.content.find_child("GameOverview", true, false)
			check(ov != null and ov.find_child("Potg1", true, false) != null and ov.find_child("BoxScore", true, false) != null, "overview lists players of the game + team stats")
			check((ov.find_child("Result", true, false) as Label).text == "VICTORY", "overview headline from your side")
			check(_btn(m, "Last game") != null, "footer can reopen the last game")
			_btn(m.content, "Close").pressed.emit()
			check(m.current == "home", "close overview -> lobby home")],
		[900, func():
			check(mms.registry.listing(mms._now()).filter(func(e): return e["name"] == "Ace's match").is_empty(), "lobby unlisted after leaving")
			launch.start_game({"practice": "passing"})],
		[960, func():
			var g = current_scene
			check(g.drill != null and g.drill.kind == "passing", "practice via Launch")
			check(g.world.phase == g.World.Phase.PRESNAP, "presnap")
			_key(KEY_SPACE)],
		[962, func():
			var g = current_scene
			check(g.world.phase == g.World.Phase.PRESNAP, "old Space key disabled after rebind")
			_key(KEY_K)],
		[964, func():
			var g = current_scene
			check(g.world.phase != g.World.Phase.PRESNAP, "rebound K snaps the ball (real input path)")
			_key(KEY_K, false)
			var m := InputEventJoypadMotion.new()
			m.axis = JOY_AXIS_LEFT_X
			m.axis_value = 1.0
			root.push_input(m)],
		[966, func():
			check(Input.is_key_pressed(KEY_D) and current_scene.read_input().x > 0.0, "gamepad stick moves the player")
			var m := InputEventJoypadMotion.new()
			m.axis = JOY_AXIS_LEFT_X
			m.axis_value = 0.0
			root.push_input(m)
			_key(KEY_ESCAPE)],
		[968, func():
			check(launch._overlay != null and paused, "Esc opens pause overlay (offline pauses)")
			check(not Input.is_key_pressed(KEY_D), "stick released")
			var button = launch._overlay.find_child("ControlsButton", true, false)
			button.pressed.emit()
			var help = launch._overlay.find_child("ControlsHelp", true, false)
			var notes = help.get_node("ControlsNotes")
			var bindings = help.get_node("ControlsBindings")
			check(help.visible and notes.text.contains("right click: block")
				and bindings.get_children().any(func(label): return label.text == "Show scoreboard (hold)"),
				"pause Controls lists the gameplay bindings")
			button.pressed.emit()
			check(not help.visible, "Controls toggles the existing help")
			_key(KEY_ESCAPE)],
		[970, func():
			check(launch._overlay == null and not paused, "Esc closes overlay")
			launch.go_to_menu()],
		[1000, func():
			# #74: Chaosball picked under Online must carry into a private host lobby.
			var m = current_scene
			m.host_port = HOST_PORT
			launch.settings.upnp = false
			m.list_public = false
			m.pick_size = 7
			m.pick_mode = "classic"
			m.show_screen("online")
			check(_size_row(m.content) == "7/enabled", "online Size row shows the 7v7 pick under Classic: %s" % _size_row(m.content))
			_btn(m.content, "Chaosball (3v3, low-g)").pressed.emit()
			check(m.pick_mode == "chaosball", "online Rules picker selects Chaosball")
			check(_size_row(m.content) == "3/disabled", "#83 Chaosball locks the Size row to 3v3: %s" % _size_row(m.content))
			_btn(m.content, "Classic").pressed.emit()
			check(_size_row(m.content) == "7/enabled" and m.pick_size == 7, "#83 back to Classic restores 7v7: %s" % _size_row(m.content))
			_btn(m.content, "Chaosball (3v3, low-g)").pressed.emit()
			m.show_screen("bots")
			check(_size_row(m.content) == "3/disabled", "#83 VS Bots Size row opens locked under Chaosball: %s" % _size_row(m.content))
			_btn(m.content, "Classic").pressed.emit()
			check(_size_row(m.content) == "7/enabled", "#83 VS Bots Classic restores 7v7: %s" % _size_row(m.content))
			_btn(m.content, "Chaosball (3v3, low-g)").pressed.emit()
			m.show_screen("online")
			m.host_match()],
		[1100, func():
			var g = current_scene
			check(g != null and g.scene_file_path == launch.GAME_SCENE and g.is_server() and g.in_lobby(), "chaosball host -> private lobby")
			check(g.lobby.settings.get("mode") == "chaosball" and g.lobby.settings.get("size") == 3,
				"private lobby keeps the menu's Chaosball 3v3 %s" % str(g.lobby.settings))
			check(g.hud.text.contains("Chaosball 3v3"), "lobby HUD shows Chaosball 3v3")
			launch.go_to_menu()],
	]

func _physics_process(_dt: float) -> bool:
	frame += 1
	while not steps.is_empty() and frame >= steps[0][0]:
		var s = steps.pop_front()
		s[1].call()
	if steps.is_empty() or frame > 1400:
		for f in ["test_menu_settings.cfg"]:
			DirAccess.remove_absolute("user://" + f)
		print("MENU FLOW %s" % ("PASS" if ok and steps.is_empty() else "FAIL"))
		quit(0 if ok and steps.is_empty() else 1)
	return false
