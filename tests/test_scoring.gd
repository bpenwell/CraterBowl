extends "res://tests/test_case.gd"

const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const T := preload("res://src/sim/tuning.gd")
const DT := 1.0 / 60.0
const R := Athlete.Role

var events: Array = []

func _match(los: float = 25.0) -> Match:
	events.clear()
	var w := World.new()
	var cx := w.field.width / 2.0
	var pairs := [[R.C, 0.0, R.DL, -1.5], [R.QB, 0.0, R.LB, 0.0], [R.WR, -18.0, R.CB, -18.0], [R.WR, 18.0, R.CB, 18.0], [R.RB, 4.0, R.S, -8.0], [R.OL, -2.5, R.DL, 1.5], [R.OL, 2.5, R.S, 8.0]]
	for t in 2:
		for p in pairs:
			w.add_two_way(t, p[0], cx + p[1], p[2], cx + p[3])
	var m := Match.new(w)
	m.start(0, los)
	w.event.connect(func(n, _d): events.append(n))
	return m

func _snap_and_wait(w) -> void:
	w.snap()
	for i in 30: w.step({}, DT)

## Teleport the carrier and step once so the World evaluates it.
func _carrier_to(w, y: float) -> void:
	var c = w.carrier()
	c.position = Vector2(26, y)
	w.step({}, DT)

func test_run_into_endzone_is_td() -> void:
	var m := _match(95.0)
	var w := m.world
	_snap_and_wait(w)
	_carrier_to(w, 100.5)
	assert_true(events.has("touchdown"), "touchdown event")
	assert_eq(w.phase, World.Phase.DEAD, "dead")
	var out := m.next_play()
	assert_eq(m.score[0], 6, "+6")
	assert_eq(out["outcome"], "try", "try next")
	assert_near(w.los_y, 85.0, 0.001, "PAT snapped from the 15")
	assert_eq(w.kick_play, "fg", "1-pt try is a kick")

func test_catch_in_endzone_is_td() -> void:
	var m := _match(80.0)
	var w := m.world
	_snap_and_wait(w)
	var wr := w.find_role(0, R.WR)
	wr.position = Vector2(26, 104)
	w.ball.hold(wr.id)  # simulate catch in end zone
	w.step({}, DT)
	assert_true(events.has("touchdown"), "TD on end-zone catch")

func test_safety() -> void:
	var m := _match(3.0)
	var w := m.world
	_snap_and_wait(w)
	var c = w.carrier()
	c.position = Vector2(26, -2.0)
	var lb := w.find_role(1, R.LB)
	lb.position = c.position + Vector2(0, 0.95)
	lb.facing = Vector2(0, -1)
	w.tackle(lb.id)
	for i in 30: w.step({}, DT)
	assert_true(events.has("tackle"), "tackled in end zone")
	var out := m.next_play()
	assert_eq(m.score[1], 2, "+2 defense")
	assert_eq(out["outcome"], "kickoff")
	assert_eq(out["receiving"], 1, "safety: scoring team receives")
	assert_eq(w.offense_team, 0, "safety: free kick by the team scored on")
	assert_near(w.los_y, 20.0, 0.001, "free kick from the 20")

func _score_td(m) -> void:
	var w = m.world
	_snap_and_wait(w)
	_carrier_to(w, 101.0)
	m.next_play()

func test_one_point_try_good() -> void:
	var m := _match(95.0)
	_score_td(m)
	_snap_and_wait(m.world)
	_carrier_to(m.world, 101.0)
	var out := m.next_play()
	assert_eq(m.score[0], 7, "6 + 1")
	assert_eq(out["try"], "good")
	assert_eq(out["receiving"], 1, "kickoff to other team")
	assert_eq(m.world.offense_team, 0, "scoring team kicks off")
	assert_near(m.world.los_y, 35.0)
	assert_eq(m.world.kick_play, "kickoff")

func test_two_point_try_choice() -> void:
	var m := _match(95.0)
	_score_td(m)
	assert_true(m.choose_try(2), "choose 2")
	assert_near(m.world.los_y, 90.0, 0.001, "from the 10")
	_snap_and_wait(m.world)
	_carrier_to(m.world, 101.0)
	m.next_play()
	assert_eq(m.score[0], 8, "6 + 2")

func test_failed_try() -> void:
	var m := _match(95.0)
	_score_td(m)
	_snap_and_wait(m.world)
	m.last_result = {"type": "incomplete"}
	var out := m.next_play()
	assert_eq(m.score[0], 6, "no try points")
	assert_eq(out["try"], "no_good")
	assert_eq(out["receiving"], 1, "kickoff to the other team")

## #103: met at his own 0.8 and driven back through the end zone and out of bounds. Forward
## progress puts the spot in the field of play, so the next snap is from the 1, not a safety. Stepping out
## of the end zone untouched is still a safety.
func _oob_from_end_zone(driven: bool) -> Match:
	var m := _match(3.0)
	var w := m.world
	_snap_and_wait(w)
	var c = w.carrier()
	c.position = Vector2(1.2, 0.8)
	var lb := w.find_role(1, R.LB)
	var dir := Vector2(-sin(0.5), -cos(0.5))
	lb.position = c.position - dir * 1.6 if driven else Vector2(40, 40)
	for i in 180:
		var inputs := {lb.id: {"dir": dir, "sprint": true}} if driven else {c.id: {"dir": Vector2(-1, -1).normalized()}}
		w.step(inputs, DT)
		if w.phase == World.Phase.DEAD:
			break
	assert_true(events.has("out_of_bounds"), "out of bounds: %s" % str(events))
	return m

func test_forward_progress_out_of_end_zone_is_not_a_safety() -> void:
	var m := _oob_from_end_zone(true)
	assert_true(m.world.dead_ball_spot.y > 0.0, "spot in the field of play (%.2f)" % m.world.dead_ball_spot.y)
	var out := m.next_play()
	assert_eq(m.score[1], 0, "no safety")
	assert_true(out.get("outcome", "") != "kickoff", "no free kick: %s" % str(out))
	assert_near(m.world.los_y, 1.0, 0.001, "next snap from the 1 (spot clamped)")

func test_untouched_out_of_end_zone_is_still_a_safety() -> void:
	var m := _oob_from_end_zone(false)
	assert_true(m.world.dead_ball_spot.y < 0.0, "went out behind the goal line")
	m.next_play()
	assert_eq(m.score[1], 2, "+2 defense")
