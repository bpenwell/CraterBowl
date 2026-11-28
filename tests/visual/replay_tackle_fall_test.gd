extends "res://tests/visual/harness.gd"
## #376: the first paused replay frame after a tackle uses the recorded carrier pose.

var game

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(376)
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.auto_replay = false
	game.opening_kickoff = false
	game.ai.defense_enabled = false
	game.series.start(0, 40.0)
	game.set_controlled(game.my_id)
	await _frames(3)
	_key(KEY_SPACE)
	await _frames(26)
	var carrier = game.world.carrier()
	check(carrier != null, "Space snaps to the carrier")
	if carrier == null:
		finish()
		return
	carrier.position.y += 1.5
	await _frames(4)
	var linebacker = game.world.find_role(1, game.Athlete.Role.LB)
	linebacker.position = carrier.position + Vector2(0, 1.0)
	linebacker.facing = Vector2(0, -1)
	check(game.world.tackle(linebacker.id), "linebacker dives at the carrier")
	await _frames(26)
	var view = game.views[carrier.id]
	check(view.is_falling(), "the carrier is still in the live fall")
	_key(KEY_V)
	_key(KEY_SPACE)
	await _frames(3)
	var sample: Dictionary = game.replay.sample()
	check(game.replay_active and game.replay.paused and not sample.is_empty(), "V and Space pause the tackle replay")
	if not sample.is_empty():
		var recorded: Vector2 = sample["pos"][carrier.id]
		var at := Vector3(recorded.x, 0.0, -recorded.y)
		check(not view.is_falling(), "the live fall releases the replayed carrier")
		check(view.position.distance_to(at) < 0.05, "the carrier moves to the recorded position")
		game.set_process(false)
		game.camera.look_at_from_position(at + Vector3(-3, 3, 5), at + Vector3.UP, Vector3.UP)
		await capture("paused-replay-after-tackle")
	finish()

func _frames(count: int) -> void:
	for frame in count:
		await physics_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_key_input(event)
