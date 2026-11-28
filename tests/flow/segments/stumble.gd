extends "res://tests/flow/segment.gd"
## #389 stumble: the human QB, snapped with the real Space key, sprints across a defender who
## dove across his path and missed. Crossing the body on the turf is a STUMBLE: the event names
## the QB and the diver, the next tick is at most 0.45 x sprint, the view leans, and the sprint
## comes back once the stumble runs out. The play goes on.

const T := preload("res://src/sim/tuning.gd")
const Athlete := preload("res://src/sim/athlete.gd")

var stumbles: Array = []
var lb = null
var qb = null
var lane := Vector2.ZERO
var stumble_frame := -1
var min_after := INF
var max_lean := 0.0
var back_to_sprint := false

func setup() -> void:
	main.configure(7)
	main.ai.offense_enabled = false
	main.ai.defense_enabled = false
	main.series.start(0, 40.0)
	main.set_controlled(main.my_id)
	main.world.event.connect(func(n, d): if n == "stumble": stumbles.append(d))

func steps() -> Array:
	var out := [
		[2, func():
			flow._key(KEY_SPACE)
			check(main.world.phase == main.World.Phase.LIVE, "stumble: Space snaps")],
		[3, func():
			var w = main.world
			lane = Vector2(w.field.width * 0.5, w.los_y + 14.0)   # open field past the line
			lb = w.find_role(1, Athlete.Role.LB)
			# The LB dives across the lane and misses; by frame 45 he's lying in it (down to ~84).
			lb.position = lane - Vector2(T.DIVE_SPEED * T.DIVE_TIME, 0.0)
			lb.velocity = Vector2.ZERO
			lb.facing = Vector2(1, 0)
			check(w.tackle(lb.id), "stumble: the LB dives")],
		[30, func():
			qb = main.world.carrier()
			check(qb != null and qb.id == main.controlled_id, "stumble: the human QB holds the snap")],
		[45, func():
			check(lb.is_grounded() and lb.speed() < 0.01, "stumble: the diver lies still on the turf")
			qb.position = lb.position - Vector2(0.0, 3.5)   # past the line: no dropback slowdown
			main.input_override = Vector2(0, 1)
			main.sprint_override = true],
		[110, func():
			check(stumbles.size() == 1, "stumble: one stumble event (%d)" % stumbles.size())
			if stumbles.size() == 1:
				var d: Dictionary = stumbles[0]
				check(d["id"] == qb.id and d["by"] == lb.id, "stumble: the QB tripped over the diver")
				check(d["tier"] == Athlete.Stumble.STUMBLE, "stumble: square at a sprint is a STUMBLE")
			check(min_after <= T.STUMBLE_FLOOR * T.SPRINT_SPEED + 0.001, "stumble: slowed to <= 0.45 x sprint the tick after (%.2f)" % min_after)
			check(max_lean > 0.8, "stumble: the view leans (%.2f)" % max_lean)
			check(back_to_sprint, "stumble: full sprint again after the stumble")
			check(main.world.phase == main.World.Phase.LIVE, "stumble: the play goes on")
			main.input_override = null
			main.sprint_override = null
			flow._force_dead_if_live()],
	]
	for f in range(46, 110):
		out.append([f, _watch])
	return out

## Per frame (one sim tick at --fixed-fps 60): the first tick after the stumble, the lean, the recovery.
func _watch() -> void:
	if stumble_frame < 0 and not stumbles.is_empty():
		stumble_frame = flow.frame
		return
	if stumble_frame < 0:
		return
	if flow.frame == stumble_frame + 1:
		min_after = qb.speed()
	var v = main.views[qb.id]
	max_lean = maxf(max_lean, v.stumble.weight if v.stumble else 0.0)
	if flow.frame > stumble_frame + roundi(T.STUMBLE_TIME * 60.0) + 2 and qb.speed() >= T.SPRINT_SPEED - 0.001:
		back_to_sprint = true
