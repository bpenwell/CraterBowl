extends "res://tests/visual/harness.gd"
## #361: a receiver at the top of a jump reaches for a pass above a standing catch, and the
## sim lets him catch it there. The scene is frozen (no physics) at a fixed jump time, so the
## capture is the same every run.

const T := preload("res://src/sim/tuning.gd")

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
	receiver.facing = Vector2(0, -1)   # facing the QB, the pass coming at him
	game.aim_point = receiver.position
	_key(game, KEY_J)
	check(world.forward_pass_thrown, "J releases a live pass")
	game.set_controlled(receiver.id)
	_key(game, KEY_SPACE)
	check(receiver.is_jumping(), "Space jumps")
	receiver.jump_t = T.JUMP_TIME * 0.5   # the top of the jump
	# A descending pass over a standing receiver's reach, inside the jumper's, a yard to his
	# side: measured from a standing chest it would still be 2.3 yd off and only part reached.
	var high: float = T.CATCH_MAX_HEIGHT + T.JUMP_HEIGHT * 0.9
	world.ball.position = Vector3(11.0, 36.3, high)
	world.ball.velocity = Vector3(0.0, 12.0, -3.0)
	game._render()
	for view in game.views:
		view.interpolate(1.0)
	var player = game.views[receiver.id]
	var sk: Skeleton3D = player._skel
	game.camera.global_position = player.global_position + Vector3(3.6, 2.4, -2.6)
	game.camera.look_at(player.global_position + Vector3(0, 1.9, 0.2))
	for frame in 30:
		player.jump_pose.vis_t = receiver.jump_t   # hold the view's jump clock at the top (the sim is frozen)
		await process_frame
	check(player.body.position.y > T.JUMP_HEIGHT * 0.9, "the body is at the top of the jump: %.2f" % player.body.position.y)
	check(player.pose.catch_weight > 0.9 and player.pose.catch_reach > 0.95, "the jumper fully reaches for the pass (weight %.2f, reach %.2f)" % [player.pose.catch_weight, player.pose.catch_reach])
	# Godot restores the clip pose after the modifiers run: read the hands as they are drawn.
	var got := {}
	var grab := func() -> void:
		for b in ["upperarm_r", "hand_r", "upperarm_l", "hand_l"]:
			got[b] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin
	player.pose.modification_processed.connect(grab, CONNECT_ONE_SHOT)
	player.anim.seek(0.2, true)
	player.anim.pause()
	player.jump_pose.vis_t = receiver.jump_t
	await process_frame
	player.jump_pose.vis_t = receiver.jump_t
	await process_frame
	var ball: Vector3 = game.ball_view.global_position
	var aim := -1.0   # the better arm: shoulder-to-hand against shoulder-to-ball
	if got.size() == 4:
		for side in ["_r", "_l"]:
			var u: Vector3 = got["upperarm" + side]
			aim = maxf(aim, (got["hand" + side] - u).normalized().dot((ball - u).normalized()))
	check(aim > 0.95, "an arm reaches straight at the ball (cos %.2f)" % aim)
	await capture("jump-catch")
	check(world._try_catch() and world.carrier() == receiver, "the sim lets the jumper catch it %.1f yd up" % high)
	finish()

func _key(game, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_key_input(event)
