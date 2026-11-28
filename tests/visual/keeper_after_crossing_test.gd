extends "res://tests/visual/harness.gd"
## #312: the passing arc and passer view stay off after the keeper runs across the line.

const Tick := preload("res://src/sim/tick.gd")
const DT := 1.0 / Tick.HZ

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	game.toss_seed = 0
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	await process_frame

	game.pov_enabled = true
	game.series.start(0, 35.0)
	_key(game, KEY_SPACE)
	var world = game.world
	while world.snap_in_flight():
		world.step({}, DT)
	var qb = world.get_athlete(game.my_id)
	qb.position = Vector2(6.0, world.los_y - 3.0)
	world.step({}, DT)
	game._update_aim()
	game._update_arc()
	check(game.pov_active() and game.reticle.visible, "keeper starts with a passing preview")
	game.pov_w = 1.0
	game._render()
	game._update_camera(4.0)
	await capture("keeper-before-crossing")

	qb.position.y = world.los_y + 2.0
	world.step({}, DT)
	qb.position.y = world.los_y - 3.0
	world.step({}, DT)
	game._render()
	game._update_aim()
	game._update_arc()
	check(world.ball_crossed_los and world.ball.is_held_by(qb.id), "the keeper retains the ball behind the line")
	check(not game.pov_active() and not game.reticle.visible and not game.arc_dots[0].visible,
		"the retreated runner has no first-person passing preview")
	_key(game, KEY_J)
	check(not game.charging and world.ball.is_held_by(qb.id), "throw control leaves the keeper running")

	game.pov_w = 1.0 if game.pov_active() else 0.0
	game._update_camera(4.0)
	game._update_fov(4.0)
	await capture("keeper-retreated")
	finish()

func _key(game, code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_key_input(event)
