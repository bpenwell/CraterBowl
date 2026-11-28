extends "res://tests/test_case.gd"

const Code := preload("res://src/net/invite_code.gd")
const Lobby := preload("res://src/net/lobby.gd")
const Clock := preload("res://src/sim/clock.gd")

func test_code_round_trip() -> void:
	for pair in [["127.0.0.1", 24565], ["203.0.113.7", 65535], ["10.0.0.1", 1]]:
		var c := Code.encode(pair[0], pair[1])
		assert_eq(c.length(), 11, "XXXXX-XXXXX (%s)" % c)
		var d := Code.decode(c)
		assert_eq(d.get("ip", ""), pair[0], "ip")
		assert_eq(d.get("port", 0), pair[1], "port")
	assert_true(Code.looks_like_code(Code.encode("127.0.0.1", 24565)), "detects a code")
	assert_true(not Code.looks_like_code("127.0.0.1"), "IP is not a code")

func test_code_rejects_garbage() -> void:
	assert_eq(Code.decode("hello"), {}, "too short")
	assert_eq(Code.decode("UUUUU-UUUUU"), {}, "U not in alphabet")
	assert_eq(Code.encode("999.1.1.1", 80), "", "bad ip")
	assert_eq(Code.encode("1.2.3.4", 0), "", "bad port")

func test_code_forgiving_letters() -> void:
	var c := Code.encode("127.0.0.1", 24565)
	var sloppy := c.to_lower().replace("0", "o").replace("1", "l")
	assert_eq(Code.decode(sloppy).get("port", 0), 24565, "o/l read as 0/1")

func test_lobby_ready_flow() -> void:
	var l := Lobby.new()
	l.add(1, "Host")
	assert_true(not l.all_ready(), "needs 2 players")
	l.add(42, "Friend")
	l.toggle_ready(1)
	assert_true(not l.all_ready(), "friend not ready")
	l.toggle_ready(42)
	assert_true(l.all_ready())
	assert_true(l.start())
	assert_eq(l.phase, Lobby.Phase.IN_GAME)
	assert_true(not l.set_ready(42, false), "no changes in game")
	l.remove(42)
	assert_eq(l.players.size(), 1)

func test_settings_host_only_and_validated() -> void:
	var l := Lobby.new()
	l.add(1)
	l.add(7)
	assert_true(not l.set_setting(7, "size", 3), "non-host rejected")
	assert_true(l.set_setting(1, "size", 3))
	assert_eq(l.settings["size"], 3)
	assert_true(not l.set_setting(1, "size", 4), "invalid size")
	assert_true(not l.set_setting(1, "quarter_minutes", 99), "invalid quarter length")
	l.toggle_ready(7)
	l.set_setting(1, "quarter_minutes", 2)
	assert_true(not l.players[7]["ready"], "settings change clears ready")

func test_pass_marker_defaults_on_and_round_trips_the_host_choice() -> void:
	var l := Lobby.new()
	l.add(1)
	l.add(7)
	assert_true(l.settings["pass_marker"], "pass marker is on by default")
	assert_true(not l.set_setting(7, "pass_marker", false), "joiner cannot change the option")
	assert_true(not l.set_setting(1, "pass_marker", 0), "requires a boolean")
	assert_true(l.set_setting(1, "pass_marker", false))
	assert_true(l.summary().contains("Pass marker off"), "setting is shown in the lobby")
	var client := Lobby.new()
	client.from_dict(bytes_to_var(var_to_bytes(l.to_dict())))
	assert_eq(client.settings["pass_marker"], false, "host can turn the marker off for clients")
	client.from_dict({"settings": {"pass_marker": "off"}})
	assert_eq(client.settings["pass_marker"], true, "malformed option falls back to on")
	client.from_dict({"settings": {}})
	assert_eq(client.settings["pass_marker"], true, "missing option defaults on")
	l.phase = Lobby.Phase.IN_GAME
	assert_true(not l.set_setting(1, "pass_marker", true), "setting stays locked during the match")

func test_lobby_serialization() -> void:
	var l := Lobby.new()
	l.code = "ABCDE-FGHJK"
	l.add(1, "Host")
	l.add(5, "Pal")
	l.set_setting(1, "size", 5)
	var m := Lobby.new()
	m.from_dict(bytes_to_var(var_to_bytes(l.to_dict())))
	assert_eq(m.settings["size"], 5)
	assert_eq(m.code, "ABCDE-FGHJK")
	assert_eq(m.players.size(), 2)

func test_clock_quarter_length() -> void:
	var c := Clock.new()
	c.quarter_length = 120.0
	c.reset()
	assert_near(c.remaining, 120.0)
	c.start_next_half()
	assert_near(c.remaining, 120.0)

func test_mode_setting() -> void:
	var l := Lobby.new()
	l.add(1)
	assert_true(l.set_setting(1, "mode", "chaosball"))
	assert_eq(l.settings["size"], 3, "chaosball forces 3v3")
	assert_true(not l.set_setting(1, "mode", "dodgeball"), "invalid mode")
	var m := Lobby.new()
	m.from_dict(l.to_dict())
	assert_eq(m.settings["mode"], "chaosball")

## #130: every lobby plays quarters; the host picks only their length.
func test_lobby_always_plays_quarters_and_reads_legacy_halves_as_quarters() -> void:
	var lobby := Lobby.new()
	assert_true(lobby.settings["quarters"], "default format is quarters")
	assert_near(lobby.settings["quarter_minutes"], 2.5, 0.001, "default 2.5-min quarters = the old 10-minute game")
	assert_true(lobby.summary().contains("2.5-min quarters"), lobby.summary())
	lobby.add(1, "Host")
	lobby.add(2, "Client")
	lobby.set_ready(2, true)
	assert_true(not lobby.set_setting(2, "quarter_minutes", 3), "only host sets the length")
	assert_true(not lobby.set_setting(1, "quarters", false), "halves can't be selected")
	assert_true(not lobby.set_setting(1, "half_minutes", 5), "half length is not a setting")
	assert_true(not lobby.set_setting(1, "quarter_minutes", 9), "duration requires a supported value")
	assert_true(not lobby.set_setting(1, "quarter_minutes", "3"), "duration is a number")
	assert_true(lobby.set_setting(1, "quarter_minutes", 3))
	assert_true(not lobby.players[2]["ready"], "players re-ready after changes")
	var client := Lobby.new()
	client.from_dict(bytes_to_var(var_to_bytes(lobby.to_dict())))
	assert_true(client.settings["quarters"])
	assert_eq(client.settings["quarter_minutes"], 3.0)
	assert_true(client.summary().contains("3-min quarters"), client.summary())
	for legacy in [{"half_minutes": 5}, {"quarters": false, "half_minutes": 8, "quarter_minutes": 2}]:
		client.from_dict({"settings": legacy})   # a pre-#130 host's halves lobby
		assert_true(client.settings["quarters"], "legacy %s reads as quarters" % str(legacy))
		assert_true(not client.summary().contains("halves"), client.summary())
	assert_eq(client.settings["quarter_minutes"], 2.0)

func test_capacity_is_both_teams_slots() -> void:
	var l := Lobby.new()
	assert_eq(l.capacity(3), 6)
	assert_eq(l.capacity(5), 10)
	assert_eq(l.capacity(7), 14)
	l.settings["size"] = 3
	for id in 5:
		l.add(id + 1)
	assert_true(not l.is_full(), "5 of 6")
	l.add(6)
	assert_true(l.is_full(), "6 of 6")
	assert_true(l.full_reason().contains("Lobby full") and l.full_reason().contains("3v3"), l.full_reason())
	assert_true(l.summary().contains("6/6 players"), l.summary())

func test_shrinking_below_present_players_is_refused_with_notice() -> void:
	var l := Lobby.new()
	l.settings["size"] = 5
	for id in 7:
		l.add(id + 1)
	assert_true(not l.set_setting(1, "size", 3), "7 players can't fit 3v3")
	assert_eq(l.settings["size"], 5)
	assert_true(l.notice.contains("7 players") and l.notice.contains("6 seats"), l.notice)
	assert_true(not l.set_setting(1, "mode", "chaosball"), "Chaosball is 3v3 too")
	assert_eq(l.settings["mode"], "classic")
	assert_true(l.notice.contains("Chaosball"), l.notice)
	assert_true(l.set_setting(1, "size", 7), "growing is always fine")
	assert_eq(l.notice, "", "accepted change clears the notice")
	l.remove(7)
	assert_true(l.set_setting(1, "mode", "chaosball"), "6 players fit Chaosball")
	assert_eq(l.settings["size"], 3)
