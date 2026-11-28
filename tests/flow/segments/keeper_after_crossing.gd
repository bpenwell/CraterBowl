extends "res://tests/flow/segment.gd"
## #312: The throw control stays locked after a keeper retreats across the line.

func steps() -> Array:
	return [
		[1, func():
			main.configure(7)
			main.auto_next = false
			main.pov_enabled = true
			main.ai.defense_enabled = false
			main.series.start(0, 35.0)
			flow._key(KEY_SPACE)],
		[31, func():
			var qb = main.world.get_athlete(main.my_id)
			check(main.world.ball.is_held_by(qb.id), "keeper receives the real snap")
			qb.position = Vector2(6.0, main.world.los_y + 2.0)],
		[33, func():
			var qb = main.world.get_athlete(main.my_id)
			check(main.world.ball_crossed_los, "keeper crosses the line of scrimmage")
			qb.position.y = main.world.los_y - 3.0],
		[35, func():
			flow._key(KEY_J)
			check(main.world.ball.is_held_by(main.my_id) and not main.charging and not main.pov_active(),
				"J cannot charge or throw a pass after the keeper retreats")],
	]
