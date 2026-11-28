extends "res://tests/flow/segment.gd"
## #362: A tackled carrier falls, gets up in place and returns to the sim position before the next snap.

var getup_id := -1

func steps() -> Array:
	return [
		[1, func(): main.configure(7); main.auto_next = false; main.auto_replay = false; main.ai.defense_enabled = false; main.series.start(0, 40.0); main.set_controlled(main.my_id)],
		[3, func(): flow._key(KEY_SPACE); check(main.world.phase == main.World.Phase.LIVE, "Space snaps (get-up play)")],
		[29, func(): var c = main.world.carrier(); getup_id = c.id; c.position = Vector2(main.field.width / 2.0, 42.0)],
		[33, func():
			var c = main.world.carrier()
			var lb = main.world.find_role(1, main.Athlete.Role.LB)
			lb.position = c.position + Vector2(0, 1.0)
			lb.facing = Vector2(0, -1)
			check(main.world.tackle(lb.id), "LB dives (get-up play)")],
		[43, func():
			check(main.world.phase == main.World.Phase.DEAD and main.last_whistle == "TACKLE", "tackled (%s)" % main.last_whistle)
			var v = main.views[getup_id]
			check(v.is_falling() and not v.fall.rising(), "the carrier is down")],
		[113, func():
			var v = main.views[getup_id]
			check(v.is_falling() and v.fall.rising(), "about 1 s later he gets up")
			main.set_controlled(getup_id)
			main.pres._update_rings(main.world)
			check(main.pres.ring.position.distance_to(v.ground_position() + Vector3(0, 0.035, 0)) < 0.05, "the ring stays under him while he rises")],
		[201, func():
			var v = main.views[getup_id]
			check(not v.is_falling() and not v.chase_sim, "up and back on his spot")
			check(Vector2(v.position.x - v.target_position().x, v.position.z - v.target_position().z).length() < 0.05, "view on the sim position after the get-up")
			main.next_play()
			check(not v.is_falling() and v.fall._hold == null, "next play: on his feet at the new spot")],
	]
