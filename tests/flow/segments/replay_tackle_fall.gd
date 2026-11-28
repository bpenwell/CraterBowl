extends "res://tests/flow/segment.gd"
## #376: rewind during a tackle fall, receive live impacts during playback, then resume live.

var carrier_id := -1
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
		[29, _move_carrier],
		[33, _tackle],
		[43, _pause_replay],
		[45, _check_replay_pose],
		[50, _deliver_live_impacts],
		[52, _return_to_live],
	]

func _move_carrier() -> void:
	var carrier = main.world.carrier()
	check(carrier != null, "Space snaps to the carrier")
	if carrier == null:
		return
	carrier_id = carrier.id
	carrier.position.y += 1.5

func _tackle() -> void:
	if carrier_id < 0:
		return
	var carrier = main.world.get_athlete(carrier_id)
	var linebacker = main.world.find_role(1, main.Athlete.Role.LB)
	linebacker_id = linebacker.id
	linebacker.position = carrier.position + Vector2(0, 1.0)
	linebacker.facing = Vector2(0, -1)
	check(main.world.tackle(linebacker_id), "linebacker dives at the carrier")

func _pause_replay() -> void:
	if carrier_id < 0:
		return
	check(main.world.phase == main.World.Phase.DEAD and main.views[carrier_id].is_falling(),
		"the play ends on a tackle with the view still falling")
	flow._key(KEY_V)
	flow._key(KEY_SPACE)
	check(main.replay_active and main.replay.paused, "V and Space open and pause the tackle replay")

func recorded_position() -> Vector3:
	var sample: Dictionary = main.replay.sample()
	if carrier_id < 0 or sample.is_empty():
		return Vector3.INF
	var at: Vector2 = sample["pos"][carrier_id]
	return Vector3(at.x, 0.0, -at.y)

func _check_replay_pose() -> void:
	var recorded := recorded_position()
	check(recorded.is_finite(), "the replay contains the carrier position")
	if not recorded.is_finite():
		return
	var view = main.views[carrier_id]
	check(not view.is_falling(), "the live fall releases the replayed carrier")
	check(view.position.distance_to(recorded) < 0.05, "the carrier moves to the recorded position")

func _deliver_live_impacts() -> void:
	if carrier_id < 0 or not main.replay_active:
		return
	for event in ["tackle", "fumble"]:
		main._on_world_event(event, {"carrier": carrier_id, "by": linebacker_id})
		check(not main.views[carrier_id].is_falling(), "a live %s leaves the replay pose in control" % event)

func _return_to_live() -> void:
	flow._key(KEY_V)
	check(not main.replay_active, "V returns to the live view")
	if carrier_id >= 0:
		main._on_world_event("fumble", {"carrier": carrier_id, "by": linebacker_id})
		check(main.views[carrier_id].is_falling(), "an impact just after replay starts a live fall")
