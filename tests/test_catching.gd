extends "res://tests/test_case.gd"

const World := preload("res://src/sim/world.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Ball := preload("res://src/sim/ball.gd")
const Passing := preload("res://src/sim/passing.gd")
const T := preload("res://src/sim/tuning.gd")
const DT := 1.0 / 60.0

var events: Array = []
var catches: Array = []

func _setup(extra: Array) -> World:
	events.clear()
	catches.clear()
	var w := World.new()
	w.add_athlete(0, Athlete.Role.C, Vector2(26, 20))
	w.add_athlete(0, Athlete.Role.QB, Vector2(26, 15))
	for e in extra:
		w.add_athlete(e[0], e[1], e[2])
	w.setup_formation(25.0)
	# setup_formation moves y; restore requested positions for test control
	for i in extra.size():
		w.athletes[2 + i].position = extra[i][2]
	w.event.connect(func(n, d):
		events.append(n)
		if n == "catch": catches.append(d["by"]))
	w.snap()
	_run(w, {}, 0.5)
	return w

func _run(w, inputs: Dictionary, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		w.step(inputs, DT)
		if w.phase == World.Phase.DEAD:
			return

func _qb(w) -> Athlete:
	return w.find_role(0, Athlete.Role.QB)

func test_lead_pass_caught_by_running_wr() -> void:
	var w := _setup([[0, Athlete.Role.WR, Vector2(10, 24)]])
	var wr: Athlete = w.athletes[2]
	var go := {wr.id: {"dir": Vector2(0, 1)}}
	_run(w, go, 1.0)  # WR at speed
	var qb := _qb(w)
	var from := Vector3(qb.position.x, qb.position.y, T.RELEASE_HEIGHT)
	var tgt := Passing.lead_target(from, wr.position, wr.velocity, 0.8)
	assert_true(w.throw(qb.id, tgt, 0.8), "throw")
	_run(w, go, 4.0)
	assert_true(events.has("catch"), "caught: %s" % str(events))
	assert_true(w.ball.is_held_by(wr.id), "WR holds")
	assert_eq(w.phase, World.Phase.LIVE, "play continues")

func test_uncatchable_pass_incomplete() -> void:
	var w := _setup([[0, Athlete.Role.WR, Vector2(5, 24)]])
	w.throw(_qb(w).id, Vector2(48, 40), 0.7)
	_run(w, {}, 5.0)
	assert_true(events.has("incomplete") and not events.has("catch"), "incomplete")

func test_thrower_cannot_catch_own_pass() -> void:
	var w := _setup([])
	var qb := _qb(w)
	w.throw(qb.id, qb.position + Vector2(0, 0.5), 0.0)
	_run(w, {}, 3.0)
	assert_true(not catches.has(qb.id), "thrower never catches own pass")

func test_high_ball_sails_over() -> void:
	# Receiver right under the midpoint of a long arc: ball is far above window there.
	var w := _setup([[0, Athlete.Role.WR, Vector2(26, 40)]])
	w.throw(_qb(w).id, Vector2(26, 62), 0.75)
	_run(w, {}, 6.0)
	assert_true(not events.has("catch"), "sailed over: %s" % str(events))

func test_contested_ball_broken_up() -> void:
	var w := _setup([[0, Athlete.Role.WR, Vector2(26, 40)], [1, Athlete.Role.CB, Vector2(26.3, 40)]])
	w.throw(_qb(w).id, Vector2(26.1, 40), 0.8)
	_run(w, {}, 4.0)
	assert_true(events.has("breakup"), "breakup: %s" % str(events))
	assert_true(not events.has("catch"), "no catch")
	assert_eq(w.phase, World.Phase.DEAD, "dead")

func _catch_at_left_sideline(receiver_x: float) -> World:
	var w := _setup([[0, Athlete.Role.WR, Vector2(12.0, 26.0)]])
	var qb := _qb(w)
	qb.position = Vector2(5.0, 20.0)
	assert_true(w.throw(qb.id, Vector2(-0.75, 38.0), 0.8), "pass heads across the sideline")
	for i in 200:
		if w.ball.position.x < -0.2 or w.phase == World.Phase.DEAD:
			break
		w.step({}, DT)
	assert_true(w.ball.position.x < 0.0 and w.ball.state == Ball.State.IN_FLIGHT, "ball is across the line in flight")
	w.athletes[2].position = Vector2(receiver_x, w.ball.position.y)
	w.step({}, DT)
	return w

func test_ball_outside_sideline_can_be_caught_with_feet_in_bounds() -> void:
	var w := _catch_at_left_sideline(0.55)
	assert_true(events.has("catch") and w.ball.is_held_by(w.athletes[2].id), "an in-bounds receiver completes the catch")
	assert_eq(w.phase, World.Phase.LIVE, "the receiver can run after the catch")

func test_same_sideline_pass_is_incomplete_with_feet_out_of_bounds() -> void:
	var w := _catch_at_left_sideline(-0.55)
	assert_true(events.has("caught_out_of_bounds") and events.has("incomplete"), "receiver standing outside is incomplete")
	assert_true(not events.has("catch") and w.ball.holder_id == -1, "no possession")
	assert_eq(w.phase, World.Phase.DEAD)

## Sample at a fixed horizontal distance after a real release, so a tick crossing
## the five-yard boundary cannot move a case from one side to the other.
func _short_pass_contact(distance: float, side: int, receiver_offset := 0.0, ruleset := "classic") -> World:
	var w := _setup([[side, Athlete.Role.WR if side == 0 else Athlete.Role.CB, Vector2(12, 20)]])
	w.set_ruleset(ruleset)
	var qb := _qb(w)
	var at := qb.position + Vector2(distance, 0.0)
	w.athletes[2].position = at + Vector2(0.0, receiver_offset)
	assert_true(w.throw(qb.id, at, 0.8), "pass released")
	w.ball.position = Vector3(at.x, at.y - DT, T.CATCH_HEIGHT)
	w.ball.velocity = Vector3(0.0, 1.0, 0.0)
	w.step({}, DT)
	return w

func test_defender_bats_pass_at_five_yards() -> void:
	var w := _short_pass_contact(5.0, 1)
	assert_true(events.has("breakup") and events.has("incomplete"), "short defensive touch breaks up the pass")
	assert_true(not events.has("interception"), "no takeaway")
	assert_eq(w.phase, World.Phase.DEAD)
	assert_eq(w.possession_team(), 0)

func test_defender_can_tip_at_normal_reach() -> void:
	var w := _short_pass_contact(4.0, 1, 1.0)
	assert_true(events.has("breakup") and w.phase == World.Phase.DEAD, "short tip uses normal defender reach")

func test_defender_can_intercept_just_beyond_five_yards() -> void:
	var w := _short_pass_contact(5.01, 1)
	assert_true(events.has("interception") and w.ball.is_held_by(w.athletes[2].id), "clean pick beyond the tip window")
	assert_eq(w.possession_team(), 1)

func test_short_pass_keeps_release_clearance_and_offensive_catches() -> void:
	var close := _short_pass_contact(2.49, 1)
	assert_eq(close.ball.state, Ball.State.IN_FLIGHT, "defender cannot tip the pass within release clearance")
	var short_pass := _short_pass_contact(4.0, 0)
	assert_true(events.has("catch") and short_pass.ball.is_held_by(short_pass.athletes[2].id), "receiver can catch a short pass")

func test_chaos_short_defensive_catch_still_swings_possession() -> void:
	var w := _short_pass_contact(4.0, 1, 0.0, "chaosball")
	assert_true(events.has("interception") and w.ball.is_held_by(w.athletes[2].id), "Chaosball has no short-pass tip rule")
	assert_eq(w.phase, World.Phase.LIVE)
	assert_eq(w.possession_team(), 1)

## Start at the first contested sample, with the pass still closing on both athletes.
func _timed_contest(receiver_x: float, defender_x: float, catch_y := 40.0, closing_gap := 0.7) -> World:
	var w := _setup([[0, Athlete.Role.WR, Vector2(8, 20)], [1, Athlete.Role.CB, Vector2(45, 20)]])
	var qb := _qb(w)
	qb.position = Vector2(26.0, 20.0)
	w.athletes[0].position.x = 3.0
	w.athletes[2].position = Vector2(26.0 + receiver_x, catch_y)
	w.athletes[3].position = Vector2(26.0 + defender_x, catch_y)
	assert_true(w.throw(qb.id, Vector2(26, catch_y), 0.8))
	w.ball.position = Vector3(26.0, catch_y - closing_gap - 12.0 * DT, T.CATCH_HEIGHT)
	w.ball.velocity = Vector3(0.0, 12.0, 0.0)
	w.step({}, DT)
	return w

func test_contest_waits_for_a_clear_winner_at_closest_contact() -> void:
	for direction in [-1.0, 1.0]:
		var receiving := _timed_contest(0.0, direction * 0.95, 40.0, 1.15)
		assert_eq(receiving.ball.state, Ball.State.IN_FLIGHT, "the joint reach alone can't end the play")
		_run(receiving, {}, 0.25)
		assert_true(events.has("catch") and receiving.ball.is_held_by(receiving.athletes[2].id), "receiver wins down the middle")
		var defending := _timed_contest(direction * 0.95, 0.0)
		assert_eq(defending.ball.state, Ball.State.IN_FLIGHT, "defender waits for clean contact")
		_run(defending, {}, 0.25)
		assert_true(events.has("interception") and defending.ball.is_held_by(defending.athletes[3].id), "defender wins from the better spot")

func test_timed_contest_tie_and_short_tip_are_breakups() -> void:
	var tied := _timed_contest(-0.5, 0.5)
	assert_eq(tied.ball.state, Ball.State.IN_FLIGHT, "a deep tie reaches its closest sample")
	_run(tied, {}, 0.25)
	assert_true(events.has("breakup") and not events.has("catch") and not events.has("interception"), "neither player wins the tie")
	var short_tip := _timed_contest(0.95, 0.0, 24.0)
	assert_eq(short_tip.phase, World.Phase.DEAD, "the short tip ends on first contact")
	assert_true(events.has("breakup") and not events.has("interception"), "short tip never turns into a pick")

func test_out_of_bounds_catch_incomplete() -> void:
	var w := _setup([[0, Athlete.Role.WR, Vector2(-1.0, 40)]])
	w.throw(_qb(w).id, Vector2(-1.0, 40), 0.9)
	_run(w, {}, 4.0)
	assert_true(events.has("caught_out_of_bounds"), "oob: %s" % str(events))
	assert_true(not events.has("catch"), "no catch")

func test_center_is_ineligible() -> void:
	var w := _setup([])
	var c := w.find_role(0, Athlete.Role.C)
	assert_true(not w.is_eligible_receiver(c), "C ineligible")
	w.throw(_qb(w).id, c.position, 0.8)
	_run(w, {}, 4.0)
	assert_true(not catches.has(c.id), "C never catches")


func test_oob_catch_in_match_is_plain_incomplete() -> void:
	# Regression: the catch-OOB event used to share the runner-OOB name and crashed Match (no spot).
	var w := World.new()
	var m := preload("res://src/sim/match.gd").new(w)
	w.add_athlete(0, Athlete.Role.C, Vector2(26, 20))
	w.add_athlete(0, Athlete.Role.QB, Vector2(26, 15))
	var wr := w.add_athlete(0, Athlete.Role.WR, Vector2(-1.0, 40))
	m.start(0, 25.0)
	wr.position = Vector2(-1.0, 40)
	w.snap()
	for i in 30: w.step({}, DT)
	w.throw(w.find_role(0, Athlete.Role.QB).id, Vector2(-1.0, 40), 0.9)
	for i in 240:
		w.step({}, DT)
		if w.phase == World.Phase.DEAD: break
	var out = m.next_play()
	assert_eq(out["outcome"], "next_down", "incomplete -> next down")
	assert_eq(m.downs.down, 2)
