extends "res://tests/visual/harness.gd"
## #438: a paused earlier frame has no dust from the live tackle.

var game

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(438)
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
	await _frames(30)
	var carrier = game.world.carrier()
	check(carrier != null, "Space snaps to the carrier")
	if carrier == null:
		finish()
		return
	var linebacker = game.world.find_role(1, game.Athlete.Role.LB)
	linebacker.position = carrier.position + Vector2(0, 1.0)
	linebacker.facing = Vector2(0, -1)
	check(game.world.tackle(linebacker.id), "linebacker tackles the carrier")
	await _frames(22)
	check(game.world.phase == game.World.Phase.DEAD and _dust_visible(), "live tackle dust is visible")
	_key(KEY_V)
	_key(KEY_SPACE)
	await _frames(3)
	check(game.replay_active and game.replay.paused, "V and Space pause the earlier recording")
	check(not _dust_visible(), "the paused frame hides live impact dust")
	var at: Vector3 = game.views[carrier.id].target_position()
	game.set_process(false)
	game.camera.fov = 45.0
	game.camera.look_at_from_position(at + Vector3(-4, 3, 6), at + Vector3.UP, Vector3.UP)
	await capture("paused-replay-impact-dust")
	finish()

func _dust_visible() -> bool:
	for particle in game.pres.find_children("*", "CPUParticles3D", true, false):
		if particle.is_visible_in_tree():
			return true
	return false

func _frames(count: int) -> void:
	for frame in count:
		await physics_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_key_input(event)
