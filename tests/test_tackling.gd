extends "res://tests/test_case.gd"

const World := preload("res://src/sim/world.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const AI := preload("res://src/sim/ai.gd")
const T := preload("res://src/sim/tuning.gd")
const DT := 1.0 / 60.0

var events: Array = []
var carrier_at_whistle := Vector2.INF

## C, QB (holds ball after snap), plus extras placed at given positions after formation.
func _setup(extra: Array) -> World:
	events.clear()
	var w := World.new()
	w.add_athlete(0, Athlete.Role.C, Vector2(26, 20))
	w.add_athlete(0, Athlete.Role.QB, Vector2(26, 15))
	for e in extra:
		w.add_athlete(e[0], e[1], e[2])
	w.setup_formation(25.0)
	for i in extra.size():
		w.athletes[2 + i].position = extra[i][2]
	var qb: Athlete = w.find_role(0, Athlete.Role.QB)  # capture athlete, not world (avoids ref cycle)
	w.event.connect(func(n, d):
		events.append(n)
		if n == "tackle" and d["carrier"] == qb.id: carrier_at_whistle = qb.position)
	w.snap()
	_run(w, {}, 0.5)
	return w

func _run(w, inputs: Dictionary, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		w.step(inputs, DT)

func _qb(w) -> Athlete:
	return w.find_role(0, Athlete.Role.QB)

func test_dive_tackles_carrier() -> void:
	var w := _setup([[1, Athlete.Role.LB, Vector2(26, 22)]])  # QB at y=20
	var lb: Athlete = w.athletes[2]
	lb.facing = Vector2(0, -1)
	assert_true(w.tackle(lb.id), "dive started")
	_run(w, {}, 0.4)
	assert_true(events.has("tackle"), "tackle: %s" % str(events))
	assert_eq(w.phase, World.Phase.DEAD, "dead")
	assert_true(w.dead_ball_spot.distance_to(carrier_at_whistle) < 0.01, "spot at carrier when whistled")

func test_missed_dive_grounds_defender() -> void:
	var w := _setup([[1, Athlete.Role.LB, Vector2(40, 22)]])
	var lb: Athlete = w.athletes[2]
	lb.facing = Vector2(1, 0)  # dive away
	w.tackle(lb.id)
	_run(w, {}, 0.4)
	assert_true(not events.has("tackle"), "no tackle")
	assert_true(lb.is_grounded(), "on the ground")
	_run(w, {}, 0.3)  # let dive momentum slide out
	var p := lb.position
	_run(w, {lb.id: {"dir": Vector2(-1, 0)}}, 0.5)  # still within 1.0s recovery
	assert_true(lb.position.distance_to(p) < 0.05, "input ignored while grounded")
	_run(w, {lb.id: {"dir": Vector2(-1, 0)}}, 1.0)
	assert_true(lb.position.x < p.x - 1.0, "recovers and moves")

func test_offense_cannot_tackle() -> void:
	var w := _setup([[0, Athlete.Role.WR, Vector2(26, 21)]])
	var wr: Athlete = w.athletes[2]
	wr.facing = Vector2(0, -1)
	w.tackle(wr.id)
	_run(w, {}, 0.4)
	assert_true(not events.has("tackle"), "teammate dive is not a tackle")

func test_no_redive_while_diving_or_grounded() -> void:
	var w := _setup([[1, Athlete.Role.LB, Vector2(45, 22)]])
	var lb: Athlete = w.athletes[2]
	lb.facing = Vector2(1, 0)
	assert_true(w.tackle(lb.id))
	assert_true(not w.tackle(lb.id), "no re-dive while diving")
	_run(w, {}, 0.4)
	assert_true(not w.tackle(lb.id), "no dive while grounded")

func test_carrier_out_of_bounds() -> void:
	var w := _setup([])
	var qb := _qb(w)
	_run(w, {qb.id: {"dir": Vector2(-1, 0), "sprint": true}}, 4.0)
	assert_true(events.has("out_of_bounds"), "oob: %s" % str(events))
	assert_eq(w.phase, World.Phase.DEAD, "dead")

func test_sack_behind_los() -> void:
	var w := _setup([[1, Athlete.Role.DL, Vector2(26, 21.5)]])
	var dl: Athlete = w.athletes[2]
	dl.facing = Vector2(0, -1)
	w.tackle(dl.id)
	_run(w, {}, 0.4)
	assert_true(events.has("tackle"), "sack")
	assert_true(w.dead_ball_spot.y < w.los_y, "behind LOS")

func test_ai_pursues_and_tackles() -> void:
	var w := _setup([[1, Athlete.Role.LB, Vector2(10, 40)]])
	var ai := AI.new()
	var qb := _qb(w)
	for i in 600:
		w.step(ai.think(w, [qb.id]), DT)
		if w.phase == World.Phase.DEAD:
			break
	assert_true(events.has("tackle"), "AI tackled: %s" % str(events))

# --- Forward progress (C06a, #98) ---------------------------------------------

var whistle_data := {}

func _fp_setup(extra: Array) -> World:
	var w := _setup(extra)
	whistle_data = {}
	w.event.connect(func(n, d): if n == "tackle": whistle_data = d)
	return w

## Defender meets the stationary QB head-on and drives him back before diving.
func _drive_back(w: World, push_s: float) -> Dictionary:
	var qb := _qb(w)
	var lb: Athlete = w.athletes[2]
	lb.position = qb.position + Vector2(0, 1.6)
	lb.facing = Vector2(0, -1)
	var contact_y := INF
	for i in int(round(push_s / DT)):
		w.step({lb.id: {"dir": Vector2(0, -1), "sprint": true}}, DT)
		if contact_y == INF and lb.position.distance_to(qb.position) <= T.CONTACT_REACH:
			contact_y = qb.position.y
	var driven_y := qb.position.y
	assert_true(w.tackle(lb.id), "dive starts")
	_run(w, {}, 0.2)
	return {"contact_y": contact_y, "driven_y": driven_y}

func test_driven_back_carrier_spotted_at_forward_progress() -> void:
	var w := _fp_setup([[1, Athlete.Role.LB, Vector2(40, 30)]])
	var r := _drive_back(w, 0.8)
	assert_true(r["contact_y"] - r["driven_y"] > 1.0, "the QB was driven back more than a yard (%s)" % str(r))
	assert_eq(w.phase, World.Phase.DEAD, "tackled")
	assert_near(w.dead_ball_spot.y, r["contact_y"], 0.15, "spot = furthest forward point in contact, not where he was driven to")
	assert_near(float(whistle_data.get("progress", -1.0)), r["contact_y"] - r["driven_y"], 0.2, "whistle reports the yards credited")
	assert_eq(_qb(w).position, w.dead_ball_spot, "the dead carrier sits at the spot")

func test_forward_progress_is_deterministic() -> void:
	var spots := []
	for i in 2:
		var w := _fp_setup([[1, Athlete.Role.LB, Vector2(40, 30)]])
		_drive_back(w, 0.8)
		spots.append(w.dead_ball_spot)
	assert_eq(spots[0], spots[1], "same inputs, same spot")

func test_retreating_in_contact_is_not_credited() -> void:
	# QB drifts back with a rusher draped on him (touching, not pushing): sacked where he is.
	var w := _fp_setup([[1, Athlete.Role.LB, Vector2(40, 30)]])
	var qb := _qb(w)
	var lb: Athlete = w.athletes[2]
	lb.position = qb.position + Vector2(0, 0.95)
	lb.facing = Vector2(0, -1)
	var start_y := qb.position.y
	_run(w, {qb.id: {"dir": Vector2(0, -1)}, lb.id: {"dir": Vector2(0, -1)}}, 0.6)
	assert_true(start_y - qb.position.y > 2.0, "QB retreated (%.2f)" % (start_y - qb.position.y))
	assert_true(lb.position.distance_to(qb.position) <= T.CONTACT_REACH, "still in contact")
	qb.facing = Vector2(0, 1)   # backpedalling, facing the rusher: head-on hit (no rear-strip roll, #99)
	w.tackle(lb.id)
	_run(w, {}, 0.2)
	assert_eq(w.phase, World.Phase.DEAD, "sacked")
	assert_true(float(whistle_data.get("progress", 1.0)) < 0.15, "no credit for yards he gave up on his own (%s)" % str(whistle_data.get("progress")))
	assert_true(w.dead_ball_spot.y < start_y - 2.0, "spotted where he retreated to")

func test_progress_window_resets_after_contact_breaks() -> void:
	var w := _fp_setup([[1, Athlete.Role.LB, Vector2(40, 30)]])
	var qb := _qb(w)
	var lb: Athlete = w.athletes[2]
	var contact_y := qb.position.y
	lb.position = qb.position + Vector2(0, 0.95)   # brief contact: window opens at contact_y
	w.step({}, DT)
	lb.position = Vector2(45, contact_y)           # contact breaks
	_run(w, {qb.id: {"dir": Vector2(0, -1)}}, T.FORWARD_PROGRESS_GRACE + 0.3)
	assert_true(contact_y - qb.position.y > 1.5, "QB retreated after breaking contact")
	# A second defender is pushed into him and drives him back half a yard, then dives.
	lb.position = qb.position + Vector2(0, 0.95)
	lb.facing = Vector2(0, -1)
	var touch_y := qb.position.y
	_run(w, {lb.id: {"dir": Vector2(0, -1), "sprint": true}}, 0.2)
	qb.facing = Vector2(0, 1)   # facing the defender: head-on hit (no rear-strip roll, #99)
	w.tackle(lb.id)
	_run(w, {}, 0.2)
	assert_eq(w.phase, World.Phase.DEAD, "tackled")
	assert_true(w.dead_ball_spot.y < contact_y - 1.0, "the old contact point isn't credited after the window closed")
	assert_true(w.dead_ball_spot.y <= touch_y + 0.05, "spot is no further than the new contact point")

func test_return_team_forward_progress_mirrors() -> void:
	# A defender with the ball attacks -y; an offensive player drives him back toward +y.
	var w := _fp_setup([[1, Athlete.Role.CB, Vector2(40, 40)], [0, Athlete.Role.WR, Vector2(10, 10)]])
	var cb: Athlete = w.athletes[2]
	var wr: Athlete = w.athletes[3]
	cb.position = Vector2(40, 40)
	w.ball.hold(cb.id)
	wr.position = Vector2(40, 38.4)
	wr.facing = Vector2(0, 1)
	var contact_y := INF
	for i in 48:
		w.step({wr.id: {"dir": Vector2(0, 1), "sprint": true}}, DT)
		if contact_y == INF and wr.position.distance_to(cb.position) <= T.CONTACT_REACH:
			contact_y = cb.position.y
	assert_true(cb.position.y - contact_y > 1.0, "CB driven back toward his own goal (+y)")
	var events_seen := []
	w.event.connect(func(n, d): if n == "tackle": events_seen.append(d))
	w.tackle(wr.id)
	_run(w, {}, 0.2)
	assert_eq(events_seen.size(), 1, "tackled")
	assert_near(w.dead_ball_spot.y, contact_y, 0.15, "spot = his furthest progress toward -y")

# --- Forward progress out of bounds (#103) ---------------------------------------

var oob_data := {}

func _oob_setup() -> World:
	var w := _setup([[1, Athlete.Role.LB, Vector2(40, 30)]])
	oob_data = {}
	w.event.connect(func(n, d): if n == "out_of_bounds": oob_data = d)
	return w

## Defender comes from the inside-front at `ang` rad off straight-on and drives the QB (standing
## `start`) back and over the left sideline. Returns where contact began and where he crossed.
func _drive_out(w: World, start: Vector2, ang: float = 0.5) -> Dictionary:
	var qb := _qb(w)
	var lb: Athlete = w.athletes[2]
	qb.position = start
	var dir := Vector2(-sin(ang), -cos(ang))
	lb.position = start - dir * 1.6
	lb.facing = dir
	var contact_y := INF
	var cross := Vector2.INF
	for i in 120:
		var before := qb.position
		w.step({lb.id: {"dir": dir, "sprint": true}}, DT)
		if contact_y == INF and lb.position.distance_to(qb.position) <= T.CONTACT_REACH:
			contact_y = qb.position.y
		if w.phase == World.Phase.DEAD:
			cross = before   # his last position in bounds (he crossed this frame)
			break
	return {"contact_y": contact_y, "cross": cross}

func test_driven_out_of_bounds_spotted_at_forward_progress() -> void:
	var w := _oob_setup()
	var r := _drive_out(w, Vector2(1.2, 20.0))
	var spot: Vector2 = oob_data.get("spot", Vector2.INF)
	assert_eq(w.phase, World.Phase.DEAD, "whistled dead")
	assert_true(events.has("out_of_bounds"), "out of bounds, not a tackle: %s" % str(events))
	assert_true(r["contact_y"] - r["cross"].y > 1.5, "driven back over a yard and a half before going out (%s)" % str(r))
	assert_near(spot.y, r["contact_y"], 0.15, "spot = furthest forward point in contact, not where he went out")
	assert_eq(w.dead_ball_spot, spot, "whistle spot is the dead-ball spot")
	assert_true(spot.x <= 0.0 and spot.x > -0.3, "x stays where he crossed the sideline (%.3f)" % spot.x)
	assert_near(float(oob_data.get("progress", -1.0)), r["contact_y"] - r["cross"].y, 0.2, "whistle reports the yards credited")
	assert_eq(_qb(w).position, spot, "the dead carrier sits at the spot")

func test_untouched_step_out_is_spotted_at_crossing() -> void:
	# Backpedalling diagonally out of bounds with nobody near: no credit for the yards he gave up.
	var w := _oob_setup()
	var qb := _qb(w)
	qb.position = Vector2(2.0, 20.0)
	var last_in := qb.position
	for i in 240:
		last_in = qb.position
		w.step({qb.id: {"dir": Vector2(-1, -1).normalized()}}, DT)
		if w.phase == World.Phase.DEAD:
			break
	var spot: Vector2 = oob_data.get("spot", Vector2.INF)
	assert_true(events.has("out_of_bounds"), "stepped out: %s" % str(events))
	assert_true(spot.y < 19.0, "spotted behind where he started (%.2f)" % spot.y)
	assert_eq(spot, qb.position, "spot = where he crossed")
	assert_true(spot.distance_to(last_in) < 0.2, "one step past his last in-bounds point")
	assert_near(float(oob_data.get("progress", 0.0)), 0.0, 0.0001, "no forward-progress credit")

func test_oob_after_contact_window_expired_is_not_credited() -> void:
	# Driven back, contact breaks, he jogs a bit, then steps out on his own after the grace window.
	var w := _oob_setup()
	var qb := _qb(w)
	var lb: Athlete = w.athletes[2]
	qb.position = Vector2(3.0, 20.0)
	lb.position = qb.position + Vector2(0, 1.6)
	lb.facing = Vector2(0, -1)
	var contact_y := INF
	for i in 48:
		w.step({lb.id: {"dir": Vector2(0, -1), "sprint": true}}, DT)
		if contact_y == INF and lb.position.distance_to(qb.position) <= T.CONTACT_REACH:
			contact_y = qb.position.y
	assert_true(contact_y - qb.position.y > 1.0, "driven back first (%.2f)" % (contact_y - qb.position.y))
	lb.position = Vector2(40, 40)   # contact breaks
	_run(w, {}, T.FORWARD_PROGRESS_GRACE + 0.1)
	var y_out := qb.position.y
	for i in 240:
		w.step({qb.id: {"dir": Vector2(-1, 0)}}, DT)
		if w.phase == World.Phase.DEAD:
			break
	var spot: Vector2 = oob_data.get("spot", Vector2.INF)
	assert_true(events.has("out_of_bounds"), "stepped out: %s" % str(events))
	assert_near(spot.y, y_out, 0.05, "spotted where he went out, not at the old contact point")
	assert_near(float(oob_data.get("progress", 0.0)), 0.0, 0.0001, "window closed: no credit")

func test_forward_progress_out_of_own_end_zone_is_not_a_safety_spot() -> void:
	# Met at his own 0.8, driven back into the end zone and out the side: forward progress was in
	# the field of play, so the spot is too (Match scores a safety only for a spot behind the goal line).
	var w := _oob_setup()
	var r := _drive_out(w, Vector2(1.2, 0.8))
	var spot: Vector2 = oob_data.get("spot", Vector2.INF)
	assert_true(r["cross"].y < 0.0, "he went out inside his own end zone (%.2f)" % r["cross"].y)
	assert_near(spot.y, 0.8, 0.15, "spotted at his forward progress")
	assert_true(spot.y > 0.0, "in the field of play: no safety")

func test_forward_progress_out_of_bounds_is_deterministic() -> void:
	var spots := []
	for i in 2:
		var w := _oob_setup()
		_drive_out(w, Vector2(1.2, 20.0))
		spots.append(w.dead_ball_spot)
	assert_eq(spots[0], spots[1], "same inputs, same spot")
