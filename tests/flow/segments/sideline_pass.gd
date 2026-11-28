extends "res://tests/flow/segment.gd"
## #338: Real passes can be caught by a receiver standing just inside the sideline.

func steps() -> Array:
	return [
		[1, func():
			main.opening_kickoff = false
			main.configure(3)
			main.auto_next = false
			main.pov_enabled = false
			main.ai.defense_enabled = false
			main.ai.offense_enabled = false],
		[4, func():
			var receiver = _sideline_pass(0.55)
			check(main.world.ball.is_held_by(receiver.id) and main.world.phase == main.World.Phase.LIVE, "feet inside the sideline complete the catch")],
		[81, func():
			_sideline_pass(-0.55)
			check(main.world.phase == main.World.Phase.DEAD and main.world.ball.holder_id < 0 and main.last_whistle == "INCOMPLETE",
				"the same throw is incomplete with feet outside")],
		[82, func():
			flow._key(KEY_ENTER)
			check(main.series.downs.down == 2 and is_equal_approx(main.world.los_y, 25.0), "sideline incompletion spends a down at the original spot")],
	]
func _sideline_pass(receiver_x: float):
	main.series.start(0, 25.0)
	main.set_controlled(main.my_id)
	flow._key(KEY_SPACE)
	var w = main.world
	check(w.ball.is_held_by(main.my_id), "Space snaps the sideline pass")
	for a in w.athletes:
		a.position = Vector2(24.0, 25.0 + 2.0 * a.id)
	w.carrier().position = Vector2(5.0, 20.0)
	main.aim_point = Vector2(-0.75, 38.0)
	flow._key(KEY_J)
	for i in 100:
		if w.ball.position.x < -0.2 or w.phase == w.Phase.DEAD:
			break
		w.step({}, 1.0 / w.Tick.HZ)
	check(w.forward_pass_thrown and w.ball.position.x < 0.0 and w.ball.state == w.Ball.State.IN_FLIGHT,
		"the real J pass is still in the air beyond the sideline")
	var receiver = w.find_role(0, main.Athlete.Role.WR)
	receiver.position = Vector2(receiver_x, w.ball.position.y)
	w.step({}, 1.0 / w.Tick.HZ)
	return receiver
