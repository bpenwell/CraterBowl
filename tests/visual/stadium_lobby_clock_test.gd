extends "res://tests/visual/harness.gd"
## #75: private lobby screens stay in lobby mode until the host starts the match.

const NetSession := preload("res://src/net/net_session.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var port := 30000 + (Time.get_ticks_usec() + OS.get_process_id() * 7) % 20000
	game._host_game(port, {"advertise": "127.0.0.1"})
	check(game.is_server() and game.in_lobby(), "private match lobby is open")
	check(game.lobby.set_setting(game.LOCAL_PLAYER, "quarters", true), "host selects quarters")
	check(game.lobby.set_setting(game.LOCAL_PLAYER, "quarter_minutes", 3), "host selects three-minute quarters")
	await _refresh()
	_check_screens(game, "PRIVATE MATCH LOBBY")
	await capture("stadium-screen-private-lobby")

	var client := NetSession.new()
	root.add_child(client)
	check(client.join("127.0.0.1", port) == OK, "second player connects")
	for frame in 180:
		if game.lobby.players.size() == 2:
			break
		await physics_frame
	if game.lobby.players.size() != 2:
		check(false, "second player arrived in the lobby")
		finish()
		return
	for id in game.lobby.players:
		game.lobby.set_ready(id, true)
	game._start_from_lobby()
	await _refresh()
	check(not game.in_lobby(), "host started the match")
	_check_screens(game, "HELIOS 0   NEBULA 0\nQ1 3:00")
	await capture("stadium-screen-quarter-clock")
	finish()

func _check_screens(game, expected: String) -> void:
	var screens: Array = game.pres.stadium.jumbo_labels
	check(not screens.is_empty(), "stadium has screens")
	for screen in screens:
		check(screen.text == expected, "stadium screen displays " + expected.replace("\n", " / "))

func _refresh() -> void:
	for frame in 5:
		await process_frame
