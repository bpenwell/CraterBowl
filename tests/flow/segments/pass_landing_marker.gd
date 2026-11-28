extends "res://tests/flow/segment.gd"
## #108: The landing marker is restricted to eligible viewers and can be disabled by the host.

func steps() -> Array:
	return [
		[1, func():
			main.opening_kickoff = false
			main.configure(7)
			main.auto_next = false
			main.pov_enabled = false
			main.ai.defense_enabled = false
			main.ai.offense_enabled = false
			main.series.start(0, 40.0)
			main.set_controlled(main.my_id)],
		[3, func(): flow._key(KEY_SPACE)],
		[41, func():
			var w = main.world
			for a in w.athletes:
				a.position = Vector2(4.0, 10.0 + a.id * 3.0)
			w.carrier().position = Vector2(26.0, 32.0)
			main.aim_point = Vector2(33.0, 72.0)
			flow._key(KEY_J)
			check(w.forward_pass_thrown, "J releases the pass for the landing cue")],
		[51, func():
			check(not main.pres.landing.visible, "passer sees no marker for their own pass")
			main.my_id = main.world.find_role(0, main.Athlete.Role.WR).id
			main.set_controlled(main.my_id)],
		[61, func():
			check(main.pres.landing.visible, "eligible receiver sees the in-flight pass marker")
			main.my_id = main.world.find_role(0, main.Athlete.Role.C).id
			main.set_controlled(main.my_id)],
		[71, func():
			check(not main.pres.landing.visible, "ineligible offensive lineman sees no pass marker")
			main.my_id = main.world.find_role(1, main.Athlete.Role.CB).id
			main.set_controlled(main.my_id)],
		[79, func():
			check(main.pres.landing.visible, "defender sees the in-flight pass marker")
			check(main.lobby.set_setting(1, "pass_marker", false), "host turns the match option off")],
		[85, func():
			check(main.world.ball.state == main.world.Ball.State.IN_FLIGHT and not main.pres.landing.visible,
				"host option hides the marker while the pass remains in flight")
			main.lobby.set_setting(1, "pass_marker", true)
			main.my_id = main.world.find_role(0, main.Athlete.Role.QB).id
			main.set_controlled(main.my_id)],
	]
