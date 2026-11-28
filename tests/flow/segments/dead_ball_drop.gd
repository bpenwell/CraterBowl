extends "res://tests/flow/segment.gd"
## #341: A tipped pass falls after the whistle at the original contact spot.

var broken_pass_clock := -1.0

func steps() -> Array:
	return [
		[1, func():
			main.opening_kickoff = false
			main.configure(3)
			main.auto_next = false
			main.pov_enabled = false
			main.ai.defense_enabled = false
			main.ai.offense_enabled = false
			main.series.start(0, 40.0)
			main.set_controlled(main.my_id)],
		[3, func():
			flow._key(KEY_SPACE)
			var w = main.world
			check(w.ball.is_held_by(main.my_id) and w.phase == main.World.Phase.LIVE, "Space snaps the breakup play")
			for a in w.athletes:
				a.position = Vector2(25.0, 40.0 + a.id * 2.0)
			var qb = w.carrier()
			qb.position = Vector2(12.0, 35.0)
			w.find_role(1, main.Athlete.Role.CB).position = Vector2(13.0, 45.0)
			main.aim_point = Vector2(12.0, 50.0)
			flow._key(KEY_J)
			check(w.forward_pass_thrown, "J releases the pass toward the defender")],
		[40, func():
			var w = main.world
			check(w.phase == main.World.Phase.DEAD and main.last_whistle == "BREAKUP", "defender breaks up the pass in the air")
			broken_pass_clock = main.series.clock.remaining
			var y: float = main.ball_view.position.y
			check(y > main.pres.Football.RADIUS and y < w.ball.position.z, "the dead ball is visibly falling (%.2f)" % y)],
		[101, func():
			var w = main.world
			var spot_view := Vector3(w.ball.position.x, main.pres.Football.RADIUS, -w.ball.position.y)
			check(main.ball_view.position.is_equal_approx(spot_view), "the dead ball settles at the contact spot")
			flow._check_ball_lying()
			check(w.ball.position.z > 0.3 and w.ball.holder_id == -1, "sim retains an unheld dead ball at contact")
			check(main.series.clock.remaining == broken_pass_clock, "the clock stays stopped during the visual fall")],
		[113, func():
			flow._key(KEY_ENTER)
			var d = main.series.downs
			check(d.offense_team == 0 and is_equal_approx(d.los, 40.0) and d.down == 2, "breakup spends the down at the original line")],
	]
