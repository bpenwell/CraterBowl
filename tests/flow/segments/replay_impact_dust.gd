extends "res://tests/flow/segment.gd"
## #438: live impact dust stays out of replay, then live contacts can emit again.

var linebacker_id := -1

func setup() -> void:
	main.configure(7)
	main.auto_next = false
	main.auto_replay = false
	main.opening_kickoff = false
	main.ai.defense_enabled = false
	main.series.start(0, 40.0)
	main.set_controlled(main.my_id)

func steps() -> Array:
	return [
		[3, func(): flow._key(KEY_SPACE)],
		[33, _tackle],
		[50, _pause_replay],
		[52, func(): check(_visible_dust() == 0, "paused replay hides the live tackle dust")],
		[54, _impact_during_replay],
		[56, _exit_and_impact],
		[58, func(): check(_visible_dust() > 0, "new live dust is visible after leaving replay")],
	]

func _tackle() -> void:
	var carrier = main.world.carrier()
	check(carrier != null, "Space snaps to the carrier")
	if carrier == null:
		return
	var linebacker = main.world.find_role(1, main.Athlete.Role.LB)
	linebacker_id = linebacker.id
	linebacker.position = carrier.position + Vector2(0, 1.0)
	linebacker.facing = Vector2(0, -1)
	check(main.world.tackle(linebacker_id), "linebacker tackles the carrier")

func _dust() -> Array[Node]:
	return main.pres.find_children("*", "CPUParticles3D", true, false)

func _visible_dust() -> int:
	var count := 0
	for particle in _dust():
		if particle.is_visible_in_tree():
			count += 1
	return count

func _pause_replay() -> void:
	check(main.world.phase == main.World.Phase.DEAD and _visible_dust() > 0, "the live tackle produces dust")
	flow._key(KEY_V)
	flow._key(KEY_SPACE)
	check(main.replay_active and main.replay.paused, "V and Space pause the earlier recording")

func _impact_during_replay() -> void:
	var count := _dust().size()
	main._on_world_event("breakup", {"by": linebacker_id})
	check(_dust().size() == count, "a live breakup does not emit dust during replay")

func _exit_and_impact() -> void:
	flow._key(KEY_V)
	check(not main.replay_active, "V returns to live")
	var count := _dust().size()
	main._on_world_event("breakup", {"by": linebacker_id})
	check(_dust().size() == count + 1, "the next live breakup emits dust")
