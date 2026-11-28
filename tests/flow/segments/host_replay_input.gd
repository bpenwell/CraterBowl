extends "res://tests/flow/segment.gd"
## #386: V and Space leave the hosted world ticking with neutral local input.

var standing_at := Vector2.ZERO
var watch_tick := 0

func setup() -> void:
	main.configure(3)
	main.ai.offense_enabled = false
	main.ai.defense_enabled = false
	main._host_game(30000 + randi() % 20000, {"no_lobby": true})
	check(main.is_server(), "replay input fixture is hosting")

func steps() -> Array:
	return [
		[2, func(): flow._key(KEY_SPACE)],
		[25, func():
			var qb = main.world.carrier()
			check(qb != null, "Space snapped to the host QB")
			if qb != null:
				qb.position.x = -0.5],
		[28, func():
			flow._key(KEY_V)
			flow._key(KEY_SPACE)
			check(main.replay_active and main.replay.paused, "host paused the instant replay")
			main.next_play()
			check(main.world.snap(), "next down starts during the clip")
			standing_at = main.world.get_athlete(main.controlled_id).position
			watch_tick = main.net_tick
			main.input_override = Vector2.RIGHT
			main.sprint_override = true],
		[48, func():
			var qb = main.world.get_athlete(main.controlled_id)
			check(main.net_tick > watch_tick and main.world.phase == main.World.Phase.LIVE, "the host advances the live down")
			check(qb.position.is_equal_approx(standing_at) and not qb.last_sprinting, "movement and sprint stay idle during replay")
			flow._key(KEY_V)],
		[70, func():
			var qb = main.world.get_athlete(main.controlled_id)
			check(not main.replay_active and qb.position.x > standing_at.x + 1.0, "held movement resumes after exiting replay")
			main.input_override = null
			main.sprint_override = null
			if main.net != null:
				main.net.peer.close()
				main.net.queue_free()
				main.net = null],
	]
