extends "res://tests/flow/segment.gd"
## #360: A receiver dives with F and catches the live pass without leaving the dive.

func steps() -> Array:
	return [
		[1, func():
			main.configure(3)
			main.auto_next = false
			main.pov_enabled = false
			main.ai.defense_enabled = false
			main.ai.offense_enabled = false
			main.series.start(0, 25.0)
			main.set_controlled(main.my_id)],
		[3, _catch_during_dive],
	]

func _catch_during_dive() -> void:
	flow._key(KEY_SPACE)
	var w = main.world
	var qb = w.carrier()
	check(qb != null, "Space snaps to the QB before a dive catch")
	if qb == null:
		return
	var receiver = w.find_role(0, main.Athlete.Role.WR)
	for athlete in w.athletes:
		athlete.position = Vector2(25.0, 60.0 + athlete.id * 2.0)
	qb.position = Vector2(10.0, 20.0)
	receiver.position = Vector2(10.0, 36.0)
	main.aim_point = receiver.position
	flow._key(KEY_J)
	check(w.forward_pass_thrown, "J throws toward the receiver")
	main.set_controlled(receiver.id)
	flow._key(KEY_F)
	check(receiver.is_diving(), "F starts a live receiver dive")
	w.ball.position = Vector3(receiver.position.x, receiver.position.y + 0.5, 1.0)
	check(w._try_catch() and w.carrier() == receiver and receiver.is_diving(), "receiver takes the pass during the active dive")
