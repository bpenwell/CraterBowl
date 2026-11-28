extends "res://tests/flow/segment.gd"
## #339: The better-positioned defender takes a contested deep pass.

func steps() -> Array:
	return [
		[1, func():
			main.opening_kickoff = false
			main.configure(3)
			main.auto_next = false
			main.pov_enabled = false
			main.ai.defense_enabled = false
			main.ai.offense_enabled = false
			main.series.start(0, 25.0)
			main.set_controlled(main.my_id)],
		[4, func():
			flow._key(KEY_SPACE)
			var w = main.world
			check(w.ball.is_held_by(main.my_id), "Space snaps the contested pass")
			for a in w.athletes:
				a.position = Vector2(4.0, 22.0 + 3.0 * a.id)
			w.carrier().position = Vector2(15.0, 20.0)
			w.find_role(0, main.Athlete.Role.WR).position = Vector2(15.95, 40.0)
			w.find_role(1, main.Athlete.Role.CB).position = Vector2(15.0, 40.0)
			main.aim_point = Vector2(15.0, 40.0)
			flow._key(KEY_J)
			check(w.forward_pass_thrown, "J throws into the contest")
			# Resolve this pass with fixed positions before bots can chase the ball.
			for tick in 90:
				if w.ball.state != w.Ball.State.IN_FLIGHT:
					break
				w.step({}, 1.0 / w.Tick.HZ)],
		[9, func():
			var w = main.world
			var cb = w.find_role(1, main.Athlete.Role.CB)
			check(w.ball.is_held_by(cb.id) and w.possession_team() == 1 and w.phase == w.Phase.LIVE,
				"the defender wins a live interception (holder %d, phase %d, ruling %s)" % [w.ball.holder_id, w.phase, main.last_whistle])
			check(main.pres.overlay.banner.visible and main.pres.overlay.banner.text == "INTERCEPTION", "the HUD shows the winning defensive catch (%s)" % main.pres.overlay.banner.text)],
	]
