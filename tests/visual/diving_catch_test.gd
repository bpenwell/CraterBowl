extends "res://tests/visual/harness.gd"
## #360: render the same catch approach on foot and during the live dive move.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.opening_kickoff = false
	game.configure(3)
	game.auto_next = false
	game.pov_enabled = false
	game.set_physics_process(false)
	game.set_process(false)
	game.series.start(0, 25.0)
	game.set_controlled(game.my_id)
	_key(game, KEY_SPACE)
	var world = game.world
	var qb = world.carrier()
	check(qb != null, "Space snaps to the QB")
	if qb == null:
		finish()
		return
	var receiver = world.find_role(0, game.Athlete.Role.WR)
	for athlete in world.athletes:
		athlete.position = Vector2(25.0, 60.0 + athlete.id * 2.0)
	qb.position = Vector2(10, 20)
	receiver.position = Vector2(10, 36)
	receiver.facing = Vector2(0, 1)
	game.aim_point = receiver.position
	_key(game, KEY_J)
	check(world.forward_pass_thrown, "J releases a live pass")
	# Freeze the scene at a real descending pass, within the catch-stance lead window.
	world.ball.velocity = Vector3(0.0, 12.0, -3.0)
	world.ball.position = Vector3(10.0, 36.65, 1.0)
	game.set_controlled(receiver.id)
	game._render()
	for view in game.views:
		view.interpolate(1.0)
	var player = game.views[receiver.id]
	game.camera.global_position = player.global_position + Vector3(3.5, 1.9, -2.3)
	game.camera.look_at(player.global_position + Vector3(0, 0.85, -0.25))
	for frame in 24:
		await process_frame
	check(player.pose.catch_weight > 0.9 and player.pose.catch_reach > 0.9, "standing receiver reaches for the pass")
	player.anim.seek(0.35, true)
	player.anim.pause()
	await capture("standing-catch")

	receiver.recover_t = 1.0
	for frame in 24:
		await process_frame
	check(player.pose.catch_weight == 0.0, "grounded athlete does not reach")
	receiver.recover_t = 0.0

	world.ball.position.y = 58.0
	game._render()
	_key(game, KEY_F)
	check(receiver.is_diving(), "F starts the receiver dive")
	for frame in 24:
		await process_frame
	check(player.pose.catch_weight == 0.0, "diving away from the pass does not start the reach")

	world.ball.position.y = 36.65
	game._render()
	for frame in 24:
		await process_frame
	check(player.anim.assigned_animation == "u2/Slide_Start", "the dive plays the slide clip")
	check(player.pose.catch_weight > 0.9 and player.pose.catch_reach > 0.9, "diving receiver reaches for the pass")
	player.anim.seek(0.26, true)
	player.anim.pause()
	await capture("diving-catch")
	check(world._try_catch() and world.carrier() == receiver and receiver.is_diving(), "the receiver catches the pass while diving")
	await capture("diving-catch-secured")
	check(player.ball_node == game.ball_view, "the caught ball follows the receiver's hand")
	finish()

func _key(game, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_key_input(event)
