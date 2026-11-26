extends "res://tests/visual/harness.gd"
## #81: malformed welcome packets cannot replace a client's athlete assignment.

const NetSession := preload("res://src/net/net_session.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._ensure_net()
	game.net.mode = NetSession.Mode.CLIENT
	var assignments: Array[int] = []
	game.net.welcomed.connect(func(aid: int): assignments.append(aid))
	game.net._on_packet(1, var_to_bytes({"k": "welcome", "aid": 1}))
	check(assignments == [1] and game.net.host_size == 7 and game.net.host_mode == "classic",
		"legacy welcome uses classic 7v7 defaults")
	for fields in [{"aid": []}, {"aid": -1}, {"aid": 6}, {"size": true}, {"mode": 5}]:
		var packet := {"k": "welcome", "aid": 2, "size": 3, "mode": "chaosball"}
		packet.merge(fields, true)
		game.net._on_packet(1, var_to_bytes(packet))
	check(assignments == [1] and game.net.my_athlete == 1
		and game.net.host_size == 7 and game.net.host_mode == "classic",
		"malformed welcomes leave the prior assignment and configuration intact")
	game.net._on_packet(1, var_to_bytes({"k": "welcome", "aid": 2, "size": 3, "mode": "chaosball"}))
	check(assignments == [1, 2] and game.net.my_athlete == 2
		and game.net.host_size == 3 and game.net.host_mode == "chaosball",
		"next valid welcome can change the assignment")
	# Render the received assignment using the same configuration choices as the real client.
	game.configure(game.net.host_size, "", game.net.host_mode)
	game.my_id = game.net.my_athlete
	game.set_controlled(game.my_id)
	game.set_physics_process(false)  # The receive fixture has no live host for outgoing input.
	await capture("client-after-valid-welcome")
	finish()
