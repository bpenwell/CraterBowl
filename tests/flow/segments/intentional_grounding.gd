extends "res://tests/flow/segment.gd"
## #254: A pressured throw flags grounding and Enter enforces the release spot.

func steps() -> Array:
	return [
		[1, func():
			main.opening_kickoff = false
			main.configure(7)
			main.auto_next = false
			main.pov_enabled = false
			main.ai.defense_enabled = false
			main.series.start(0, 40.0)
			flow._key(KEY_SPACE)],
		[41, func():
			var qb = main.world.get_athlete(main.my_id)
			qb.position = Vector2(26.0, 35.0)
			main.world.find_role(1, main.Athlete.Role.LB).position = qb.position + Vector2(2.0, 0.0)
			main.aim_point = Vector2(4.0, 20.0)
			flow._key(KEY_J)
			check(main.pres.overlay.flag_l.text == "FLAG · INTENTIONAL GROUNDING · OFFENSE", "J flags the pressured throw")],
		[201, func():
			check(main.world.phase == main.World.Phase.DEAD, "grounding throw finishes live play")
			flow._key(KEY_ENTER)
			check(main.series.downs.los == 35.0 and main.series.downs.down == 2,
				"Enter enforces the passer's spot and spends the down")
			check(main.pres.overlay.flag_l.text.ends_with("SPOT FOUL · LOSS OF DOWN"), "HUD explains the grounding ruling")],
	]
