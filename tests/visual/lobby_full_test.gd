extends "res://tests/visual/harness.gd"
## #54: a joiner turned away from a full 3v3 lobby sees why; a host over capacity
## sees why a smaller format was refused.

const NetSession := preload("res://src/net/net_session.gd")
const Lobby := preload("res://src/net/lobby.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var port := 28000 + randi() % 2000
	# A bare host whose 3v3 lobby already seats 6 players.
	var host = NetSession.new()
	host.name = "FullHost"
	root.add_child(host)
	check(host.host(port, func(_p): return -1, func(_p): pass) == OK, "host listening on %d" % port)
	var lobby := Lobby.new()
	lobby.settings["size"] = 3
	for id in 6:
		lobby.add(id + 1, "Player %d" % (id + 1))
	host.lobby = lobby
	host.lobby_mode = true

	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._join_game("127.0.0.1", port, {})
	for frame in 600:
		await process_frame
		if game.net.refused_reason != "":
			break
	await _refresh()
	check(game.net.refused_reason.contains("Lobby full"), "joiner refused with a reason: %s" % game.net.refused_reason)
	check(game.in_lobby() and game.hud.visible and game.hud.text.contains("COULDN'T JOIN") and game.hud.text.contains("Lobby full: this 3v3 match has 6 seats"), "refused joiner's screen shows why")
	check(lobby.players.size() == 6, "host lobby still 6/6")
	await capture("lobby-full-joiner-refused")
	game.queue_free()
	host.queue_free()
	await _refresh()

	# A host whose 5v5 lobby holds 7 tries to switch to 3v3 (key 3).
	var h = preload("res://scenes/main.tscn").instantiate()
	root.add_child(h)
	current_scene = h
	h.match_size = 5
	h._host_game(port + 1, {"size": 5})
	for id in 6:
		h.lobby.add(100 + id, ["Ace", "Blitz", "Cleats", "Dash", "Edge", "Flex"][id])
	var e := InputEventKey.new()
	e.keycode = KEY_3
	e.pressed = true
	h._unhandled_key_input(e)
	await _refresh()
	check(h.lobby.settings["size"] == 5, "3v3 refused with 7 players present")
	check(h.hud.text.contains("Can't switch to 3v3") and h.hud.text.contains("7 of 10 players"), "host lobby shows the seat count and why")
	await capture("lobby-host-shrink-refused")
	finish()

func _refresh() -> void:
	for frame in 10:
		await process_frame
