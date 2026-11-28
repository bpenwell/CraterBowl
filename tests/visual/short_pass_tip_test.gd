extends "res://tests/visual/harness.gd"
## #337: a short defensive tip ends the down without a pick or return.

const Tick := preload("res://src/sim/tick.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.opening_kickoff = false
	game.configure(3)
	game.auto_next = false
	game.auto_replay = false
	game.pov_enabled = false
	game.set_physics_process(false)
	game.series.start(0, 40.0)
	game.set_controlled(game.my_id)
	await process_frame
	_key(game, KEY_SPACE)
	var world = game.world
	check(world.phase == game.World.Phase.LIVE and world.ball.is_held_by(game.my_id), "Space snaps")
	for a in world.athletes:
		a.position = Vector2(25.0, 40.0 + a.id * 2.0)
	var qb = world.carrier()
	qb.position = Vector2(12.0, 35.0)
	world.find_role(1, game.Athlete.Role.CB).position = qb.position + Vector2(0.0, 4.25)
	game.aim_point = qb.position + Vector2(0.0, 6.0)
	_key(game, KEY_J)
	check(world.forward_pass_thrown, "J releases the short pass")
	# Simulate exactly 20 ticks without bot motion or a running clock.
	for tick in 20:
		world.step({}, 1.0 / Tick.HZ)
	game._render()
	for view in game.views:
		view.interpolate(1.0)
	game.camera_follow = game.player.global_position
	game.cam_yaw = game._camera_target_yaw()
	game._update_camera(1.0 / Tick.HZ)
	await process_frame
	check(world.phase == game.World.Phase.DEAD and world.possession_team() == 0, "tip ends the down without a takeaway")
	check(game.pres.overlay.status_l.text == "PASS BROKEN UP", "HUD reads PASS BROKEN UP")
	await capture("short-pass-tip")
	finish()

func _key(game, code: int) -> void:
	var input := InputEventKey.new()
	input.keycode = code
	input.pressed = true
	game._unhandled_key_input(input)
