extends "res://tests/test_case.gd"
## #253: penalty flag pipeline (record -> enforce -> ruling) and the blocking zone.

const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Roster := preload("res://src/sim/roster.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const AI := preload("res://src/sim/ai.gd")
const Penalties := preload("res://src/sim/penalties.gd")
const T := preload("res://src/sim/tuning.gd")
const DT := 1.0 / 60.0
const R := Athlete.Role

## A 7v7 (or `size`) match, snapped, with the QB holding the ball and everyone else idle.
func _live(los := 40.0, size := 7) -> Match:
	var w := World.new()
	Roster.new().build(w, size)
	var m := Match.new(w)
	m.start(0, los)
	assert_true(w.snap(), "snap")
	for i in 30:
		w.step({}, DT)
	var qb := w.find_role(0, R.QB)
	assert_true(w.ball.is_held_by(qb.id), "QB has the snap")
	qb.position = Vector2(w.field.width / 2.0, los - 5.0)
	# Defenders out of the way so nothing intercepts or hits anyone.
	for a in w.athletes:
		if a.team == 1:
			a.position = Vector2(2.0 + a.id, los + 40.0)
	return m

func _pass(m: Match, depth := 20.0) -> void:
	var w := m.world
	var qb := w.find_role(0, R.QB)
	assert_true(w.throw(qb.id, Vector2(qb.position.x + 6.0, w.los_y + depth), 0.75), "forward pass")

func _finish(m: Match) -> void:
	var w := m.world
	for i in 400:
		if w.phase == World.Phase.DEAD:
			return
		w.step({}, DT)
	assert_true(w.phase == World.Phase.DEAD, "play ended")

func _events(m: Match) -> Array:
	var got := []
	m.match_event.connect(func(n, d): if n == "penalty": got.append(d))
	return got

# --- the foul ----------------------------------------------------------------

func test_lineman_past_five_yards_at_the_throw_draws_a_flag() -> void:
	for role in [R.C, R.OL]:
		var m := _live()
		var w := m.world
		var lineman := w.find_role(0, role)
		lineman.position.y = w.los_y + 5.1
		var flagged := []
		w.event.connect(func(n, d): if n == "flag": flagged.append(d))
		_pass(m)
		assert_eq(w.flags.size(), 1, "role %d past the zone: one flag" % role)
		assert_eq(flagged.size(), 1, "flag event for the HUD")
		var p: Dictionary = w.flags[0]
		assert_eq(p["type"], Penalties.ILLEGAL_MAN_DOWNFIELD, "type")
		assert_eq(p["team"], 0, "against the offense")
		assert_true(p["offense"], "offensive foul")
		assert_near(p["spot"], 40.0, 0.001, "enforced from the line of scrimmage")
		assert_near(p["yards"], T.BLOCK_ZONE_PENALTY_YARDS, 0.001, "10 yards")
		assert_true(p["replay"] and not p["loss_of_down"], "replay the down")
		assert_eq(p["player"], lineman.id, "names the lineman")

func test_exactly_five_yards_is_legal() -> void:
	var m := _live()
	var w := m.world
	w.find_role(0, R.C).position.y = w.los_y + 5.0
	for ol in w.athletes.filter(func(a): return a.team == 0 and a.role == R.OL):
		ol.position.y = w.los_y + 4.9
	_pass(m)
	assert_true(w.flags.is_empty(), "exactly 5 yd past the line is inside the zone")

func test_eligible_players_downfield_never_foul() -> void:
	# Owner (#253): eligibility is the catch resolver's: C/OL are ineligible, everyone else may roam.
	var m := _live()
	var w := m.world
	for a in w.athletes:
		if a.team == 0 and (a.role == R.WR or a.role == R.RB):
			a.position.y = w.los_y + 12.0
			assert_true(w.is_eligible_receiver(a), "WR/RB eligible")
		elif a.team == 0 and (a.role == R.C or a.role == R.OL):
			assert_true(not w.is_eligible_receiver(a), "C/OL ineligible")
	_pass(m)
	assert_true(w.flags.is_empty(), "receivers and backs downfield are legal")
	# 3v3 has no linemen at all.
	var small := _live(40.0, 3)
	for a in small.world.athletes:
		if a.team == 0 and a.role != R.QB:
			a.position.y = small.world.los_y + 12.0
	_pass(small)
	assert_true(small.world.flags.is_empty(), "3v3: nobody to flag")

func test_throw_before_the_lineman_crosses_is_legal_after_is_a_foul() -> void:
	var m := _live()
	var w := m.world
	var c := w.find_role(0, R.C)
	c.position.y = w.los_y + 3.0
	_pass(m)
	c.position.y = w.los_y + 9.0   # releases downfield once the ball is out
	w.step({}, DT)
	assert_true(w.flags.is_empty(), "ball thrown before he crossed: legal")
	assert_true(not w.blocking_zone_active(), "zone lifts on the pass")
	var m2 := _live()
	var c2 := m2.world.find_role(0, R.C)
	c2.position.y = m2.world.los_y + 3.0
	m2.world.step({}, DT)
	c2.position.y = m2.world.los_y + 9.0   # crosses first, then the throw
	m2.world.step({}, DT)
	_pass(m2)
	assert_eq(m2.world.flags.size(), 1, "ball thrown after he crossed: flag")

func test_run_lifts_the_zone_but_a_handoff_does_not() -> void:
	# The QB carries it past the line: a run. The zone stays lifted and passing stays closed
	# if he retreats behind the line (#312).
	var m := _live()
	var w := m.world
	var qb := w.find_role(0, R.QB)
	var ol := w.find_role(0, R.OL)
	qb.position.y = w.los_y + 1.0
	w.step({}, DT)
	assert_true(w.ball_crossed_los and not w.blocking_zone_active(), "run: zone lifted")
	ol.position.y = w.los_y + 9.0
	qb.position.y = w.los_y - 1.0
	w.step({}, DT)
	assert_true(not w.blocking_zone_active(), "retreat keeps the zone lifted")
	assert_true(not w.throw(qb.id, Vector2(qb.position.x, w.los_y + 15.0), 0.7),
		"the retreated keeper cannot pass")
	assert_true(w.flags.is_empty(), "no blocking-zone flag after a run")
	# A handoff behind the line is not a run: a halfback pass with a lineman downfield is a foul.
	var m2 := _live()
	var w2 := m2.world
	var qb2 := w2.find_role(0, R.QB)
	var back := w2.find_role(0, R.RB)
	back.position = qb2.position + Vector2(1.0, 0.0)
	assert_true(w2.handoff(qb2.id), "handoff")
	assert_true(w2.blocking_zone_active(), "zone still on after a handoff behind the line")
	w2.find_role(0, R.OL).position.y = w2.los_y + 8.0
	assert_true(w2.throw(back.id, Vector2(back.position.x, w2.los_y + 15.0), 0.7), "halfback pass")
	assert_eq(w2.flags.size(), 1, "halfback pass with a lineman downfield: flag")

func test_pass_landing_behind_the_line_is_exempt() -> void:
	var m := _live()
	var w := m.world
	var qb := w.find_role(0, R.QB)
	w.find_role(0, R.OL).position.y = w.los_y + 9.0
	assert_true(w.throw(qb.id, Vector2(qb.position.x + 8.0, w.los_y - 2.0), 0.6), "screen pass")
	assert_true(w.flags.is_empty(), "a pass that doesn't cross the line can't be illegal man downfield")

func test_kick_plays_and_chaosball_have_no_zone() -> void:
	var m := _live()
	m.world.set_ruleset("chaosball")
	m.world.find_role(0, R.OL).position.y = m.world.los_y + 9.0
	assert_true(not m.world.blocking_zone_active(), "chaosball")
	m.world.set_ruleset("classic")
	m.world.kick_play = "punt"
	assert_true(not m.world.blocking_zone_active(), "punt")

# --- enforcement -------------------------------------------------------------

func test_flag_is_enforced_ten_yards_and_the_down_is_replayed() -> void:
	var m := _live()
	var w := m.world
	m.downs.down = 3
	w.find_role(0, R.OL).position.y = w.los_y + 6.0
	var got := _events(m)
	_pass(m)
	_finish(m)
	var line_to_gain := m.downs.first_down_y
	var out := m.next_play()
	assert_eq(out["outcome"], "replay_down", "outcome")
	assert_near(m.downs.los, 30.0, 0.001, "back 10 from the previous spot")
	assert_eq(m.downs.down, 3, "same down")
	assert_near(m.downs.first_down_y, line_to_gain, 0.001, "line to gain unchanged")
	assert_near(w.los_y, 30.0, 0.001, "lined up at the new spot")
	assert_true(w.flags.is_empty(), "flag consumed")
	assert_eq(got.size(), 1, "one penalty event")
	assert_eq(got[0]["ruling"], "FLAG · ILLEGAL MAN DOWNFIELD · OFFENSE · 10 YD · REPLAY 3RD DOWN", "HUD ruling")
	assert_true(not got[0]["declined"], "accepted")

func test_completed_pass_and_touchdown_are_wiped_out() -> void:
	var m := _live()
	m.world.find_role(0, R.OL).position.y = m.world.los_y + 6.0
	_pass(m)
	m.world.phase = World.Phase.DEAD
	m.last_result = {"type": "touchdown", "team": 0, "points": 6}
	var out := m.next_play()
	assert_eq(out["outcome"], "replay_down", "TD comes back")
	assert_eq(m.score[0], 0, "no points")
	assert_near(m.downs.los, 30.0, 0.001, "replayed from 10 back")
	assert_true(not m.clock.running_between_plays, "clock stopped")

func test_half_the_distance_near_own_goal() -> void:
	var m := _live(12.0)
	var got := _events(m)
	m.world.find_role(0, R.OL).position.y = m.world.los_y + 6.0
	_pass(m)
	_finish(m)
	m.next_play()
	assert_near(m.downs.los, 6.0, 0.001, "10 yd from the 12 is more than half: half the distance")
	assert_eq(got[0]["ruling"], "FLAG · ILLEGAL MAN DOWNFIELD · OFFENSE · 6 YD, HALF THE DISTANCE · REPLAY 1ST DOWN", "ruling")

func test_enforce_spots_and_clamps() -> void:
	var Downs := preload("res://src/sim/downs.gd")
	var d := Downs.new()
	d.reset(0, 2.0)
	var p := Penalties.make(Penalties.ILLEGAL_MAN_DOWNFIELD, 0, true, 2.0, 10.0)
	var r := Penalties.enforce(d, p)
	assert_near(d.los, 1.0, 0.001, "half the distance from the 2 = the 1")
	assert_true(r["half_distance"], "flagged as half the distance")
	d.reset(0, 21.0)
	r = Penalties.enforce(d, Penalties.make(Penalties.ILLEGAL_MAN_DOWNFIELD, 0, true, 21.0, 10.0))
	assert_near(d.los, 11.0, 0.001, "21 -> 11 is exactly under half: full 10")
	assert_true(not r["half_distance"], "full yardage")
	# Shared path for later fouls (#254): loss of down; defensive fouls move forward.
	d.reset(0, 40.0)
	d.down = 4
	r = Penalties.enforce(d, Penalties.make("intentional_grounding", 0, true, 40.0, 0.0, -1, false, true))
	assert_true(r["turnover_on_downs"], "loss of down on 4th = turnover on downs")
	assert_eq(d.offense_team, 1, "ball changes hands")
	d.reset(0, 40.0)
	r = Penalties.enforce(d, Penalties.make("defensive_test", 1, false, 40.0, 15.0))
	assert_true(r["first_down"] and is_equal_approx(d.los, 55.0), "defensive foul past the line to gain: first down")

func test_defense_keeps_a_better_result() -> void:
	var m := _live()
	var got := _events(m)
	m.world.find_role(0, R.OL).position.y = m.world.los_y + 6.0
	_pass(m)
	m.world.phase = World.Phase.DEAD
	m.last_result = {"type": "tackle", "spot": 60.0, "team": 1}   # intercepted and returned
	var out := m.next_play()
	assert_eq(out["outcome"], "turnover", "the interception stands")
	assert_eq(m.downs.offense_team, 1, "defense has the ball")
	assert_true(got[0]["declined"], "declined")
	assert_eq(got[0]["ruling"], "FLAG · ILLEGAL MAN DOWNFIELD · OFFENSE · DECLINED", "declined ruling")
	var D := preload("res://src/sim/downs.gd")
	var d := D.new()
	d.reset(0, 40.0)
	d.down = 4
	assert_true(Penalties.defense_declines({"type": "incomplete", "team": 0}, d, false), "4th-down incompletion: turnover on downs")
	assert_true(not Penalties.defense_declines({"type": "tackle", "spot": 52.0, "team": 0}, d, false), "4th-down conversion: enforce")
	d.down = 2
	assert_true(Penalties.defense_declines({"type": "tackle", "spot": -1.0, "team": 0}, d, false), "safety stands")
	assert_true(not Penalties.defense_declines({"type": "incomplete", "team": 0}, d, false), "2nd-down incompletion: enforce")
	assert_true(Penalties.defense_declines({"type": "incomplete", "team": 0}, d, true), "failed try stands")
	assert_true(not Penalties.defense_declines({"type": "touchdown", "team": 0}, d, true), "try good: enforce")

func test_ruling_text() -> void:
	var p := Penalties.make(Penalties.ILLEGAL_MAN_DOWNFIELD, 0, true, 40.0, 10.0)
	assert_eq(Penalties.ruling(p), "FLAG · ILLEGAL MAN DOWNFIELD · OFFENSE", "flag thrown, play on")
	assert_eq(Penalties.ruling(p, {"yards": 10.0, "down": 2}), "FLAG · ILLEGAL MAN DOWNFIELD · OFFENSE · 10 YD · REPLAY 2ND DOWN", "enforced")
	assert_eq(Penalties.ruling(p, {"yards": 4.5, "half_distance": true, "try": true}), "FLAG · ILLEGAL MAN DOWNFIELD · OFFENSE · 4.5 YD, HALF THE DISTANCE · REPLAY TRY", "try, half distance")

# --- bots --------------------------------------------------------------------

## A rusher parked 7 yd downfield pulls a protecting bot lineman toward him; the bot stops
## at the zone's edge instead of following him past 5 yd. Then a run lifts the zone.
func test_bot_linemen_respect_the_zone_until_a_pass_or_run() -> void:
	var m := _live()
	var w := m.world
	var ai := AI.new()
	ai.defense_enabled = false
	var qb := w.find_role(0, R.QB)
	var c := w.find_role(0, R.C)
	var dl := w.find_role(1, R.DL)
	c.position.y = w.los_y + 1.0
	dl.position = Vector2(c.position.x, w.los_y + 7.0)
	var deepest := -INF
	for i in 240:
		var inputs := ai.think(w, [qb.id])
		w.step(inputs, DT)
		for a in w.athletes:
			if a.team == 0 and not w.is_eligible_receiver(a):
				deepest = maxf(deepest, a.position.y - w.los_y)
	assert_true(deepest <= T.BLOCK_ZONE_DEPTH, "bot linemen stayed inside the zone (deepest %.2f yd)" % deepest)
	assert_true(deepest > 2.0, "the lineman did go after the rusher (%.2f yd)" % deepest)
	_pass(m)
	assert_true(w.flags.is_empty(), "no flag on the throw")
	# After a run the zone is off and the bot follows his man downfield.
	var m2 := _live()
	var w2 := m2.world
	var c2 := w2.find_role(0, R.C)
	var qb2 := w2.find_role(0, R.QB)
	c2.position.y = w2.los_y + 1.0
	w2.find_role(1, R.DL).position = Vector2(c2.position.x, w2.los_y + 7.0)
	qb2.position = Vector2(2.0, w2.los_y + 1.0)   # scrambled past the line, out of everyone's way
	var deepest2 := -INF
	for i in 240:
		w2.step(ai.think(w2, [qb2.id]), DT)
		deepest2 = maxf(deepest2, c2.position.y - w2.los_y)
	assert_true(not w2.blocking_zone_active(), "zone lifted by the run")
	assert_true(deepest2 > T.BLOCK_ZONE_DEPTH, "after a run the center may block downfield (%.2f yd)" % deepest2)

## Bot vs bot: a run of full plays never throws a blocking-zone flag.
func test_bot_offense_never_draws_the_flag() -> void:
	var w := World.new()
	Roster.new().build(w)
	var m := Match.new(w)
	m.start(0, 30.0)
	var ai := AI.new()
	var flags := []
	w.event.connect(func(n, d): if n == "flag": flags.append(d))
	var plays := 0
	for f in 60 * 90:
		if w.phase == World.Phase.PRESNAP:
			w.snap()
		elif w.phase == World.Phase.DEAD:
			m.next_play()
			plays += 1
			if m.is_final():
				break
		w.step(ai.think(w, []), DT)
	assert_true(plays >= 8, "ran %d plays" % plays)
	assert_eq(flags.size(), 0, "bots never flagged")
