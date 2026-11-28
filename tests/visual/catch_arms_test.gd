extends "res://tests/visual/harness.gd"
## #246 follow-up: athletes near where a deep pass comes down keep the run clip's arm pump
## until the ball is close (player.gd CATCH_LEAD), then raise their hands and reach. Before
## the fix they ran with both hands up by the face for the whole flight.

const FAR_ETA := 0.55   # s: the ball is still this far out (distance / ball speed); CATCH_LEAD is 0.45

var game
var cam: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.opening_kickoff = false
	game.auto_next = false
	game.auto_replay = false
	game.pov_enabled = false
	game.series.start(0)
	game.set_controlled(game.my_id)
	game.input_override = Vector2.ZERO
	await physics_frame
	_key(KEY_SPACE)
	var world = game.world
	check(world.phase == game.World.Phase.LIVE, "Space snaps")
	for i in 60:   # the WR runs his route
		await physics_frame
	var qb = world.carrier()
	var wr = world.find_role(0, game.Athlete.Role.WR)
	var from := Vector3(qb.position.x, qb.position.y, game.T.RELEASE_HEIGHT)
	game.aim_point = game.Passing.lead_target(from, wr.position, wr.velocity, game.T.PLAYER_PASS_POWER)
	_key(KEY_J)
	check(world.forward_pass_thrown, "J throws the deep lead pass")
	# A camera beside the WR, so heads (and the catch pose) are in view.
	cam = Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	var wr_view = game.views[wr.id]
	var far_frames := 0     # frames with someone set to catch it while the ball is still far out
	var worst := 0.0        # their highest catch weight then
	var reached := 0.0      # highest catch weight once the ball is close
	var shot := false
	while wr_view._pass_in_air():
		cam.global_position = wr_view.global_position + Vector3(4.5, 2.2, 0.0)
		cam.look_at(wr_view.global_position + Vector3.UP)
		cam.make_current()
		await process_frame
		if not wr_view._pass_in_air():
			break
		var speed: float = world.ball.velocity.length()
		var far_out := false
		for v in game.views:
			var eta: float = game.ball_view.global_position.distance_to(v.global_position + Vector3.UP * v.CATCH_HEIGHT) / speed
			if v._catch_wanted and eta > FAR_ETA:
				far_out = true
				worst = maxf(worst, v.pose.catch_weight)
			elif v._catch_wanted:
				reached = maxf(reached, v.pose.catch_weight)
		if far_out:
			far_frames += 1
			# Mid-flight, about 0.65 s out: arms pumping, not up by the face.
			if not shot and far_frames == 6:
				shot = true
				await capture("catch-arms-midflight")
	check(far_frames >= 10, "someone runs under the pass while it is far out (%d frames)" % far_frames)
	check(worst < 0.05, "no catch stance while the ball is > %.2f s out: worst catch weight %.2f" % [FAR_ETA, worst])
	check(reached > 0.8, "hands come up as the ball closes in: catch weight %.2f" % reached)
	finish()

func _key(code: int) -> void:
	var input := InputEventKey.new()
	input.keycode = code
	input.pressed = true
	game._unhandled_key_input(input)
