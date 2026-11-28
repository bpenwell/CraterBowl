extends "res://tests/test_case.gd"
## #189 (D08a, part of #69): fair catch. Signal window, dead ball at the catch, the
## kickoff 25-yard rule, muffs stay live with no advance, signaler protection, the
## bot rule and the snapshot field.

const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const AI := preload("res://src/sim/ai.gd")
const Passing := preload("res://src/sim/passing.gd")
const P := preload("res://src/net/protocol.gd")
const T := preload("res://src/sim/tuning.gd")
const DT := 1.0 / 60.0
const R := Athlete.Role

var events: Array = []
var ev_data := {}

func _world() -> World:
	var w := World.new()
	var cx := w.field.width / 2.0
	var pairs := [[R.C, 0.0, R.DL, -1.5], [R.QB, 0.0, R.LB, 0.0], [R.WR, -18.0, R.CB, -18.0], [R.WR, 18.0, R.CB, 18.0], [R.RB, 4.0, R.S, -8.0], [R.OL, -2.5, R.DL, 1.5], [R.OL, 2.5, R.S, 8.0]]
	for t in 2:
		for p in pairs:
			w.add_two_way(t, p[0], cx + p[1], p[2], cx + p[3])
	return w

func _listen(w) -> void:
	events.clear()
	ev_data = {}
	w.event.connect(func(n, d): events.append(n); ev_data[n] = d)

func _steps(w, n: int, inputs: Dictionary = {}) -> void:
	for i in n:
		w.step(inputs, DT)
		if w.phase == World.Phase.DEAD:
			return

func _landing(w) -> Vector2:
	var b = w.ball
	var t := Passing.time_to_height(b.velocity, b.position.z, T.CATCH_HEIGHT, w.gravity())
	return Vector2(b.position.x + b.velocity.x * t, b.position.y + b.velocity.y * t)

func _park_all_but(w, keep: Array) -> void:
	for a in w.athletes:
		if not keep.has(a.id):
			a.position = Vector2(-1.5 if a.team == 0 else w.field.width + 1.5, a.position.y)

## Team 0 punts on 4th down from `los`; returns the match with the punt in the air.
func _punt_in_air(los: float = 30.0, target_y: float = 70.0, park := true) -> Match:
	var w := _world()
	var m := Match.new(w)
	m.start(0, los)
	_listen(w)
	m.downs.reset(0, los)
	m.downs.down = 4
	m._setup_formation()
	m.call_kick("punt")
	w.snap()
	_steps(w, 30)
	if park:
		_park_all_but(w, [w.find_role(0, R.C).id, w.kicker().id, w.returner().id])
	assert_true(w.kick(w.kicker().id, Vector2(w.field.width / 2.0, target_y), 0.7), "punt away")
	return m

## Team 0 kicks off (after a good PAT); the kick is in the air toward `target_y`.
func _kickoff_in_air(target_y: float, power: float) -> Match:
	var w := _world()
	var m := Match.new(w)
	m.start(0, 25.0)
	_listen(w)
	m.state = Match.State.TRY
	m.last_result = {"type": "field_goal", "good": true, "team": 0}
	m.next_play()   # good PAT -> team 0 kicks off from its 35
	_park_all_but(w, [w.returner().id])
	assert_true(w.kick(w.kicker().id, Vector2(w.field.width / 2.0, target_y), power), "kickoff away")
	return m

func test_punt_fair_catch_is_dead_at_the_catch() -> void:
	var m := _punt_in_air()
	var w := m.world
	var ret := w.returner()
	ret.position = _landing(w)
	assert_true(P.apply_action(m, ret.id, {"a": "snap"}), "Snap key signals a fair catch while the punt is in the air")
	assert_eq(w.fair_catch_id, ret.id)
	assert_true(events.has("fair_catch_signal"), "signal event")
	_steps(w, 400)
	assert_eq(w.phase, World.Phase.DEAD, "the catch ends the play")
	assert_true(events.has("fair_catch") and not events.has("kick_catch"), "fair catch, no return (%s)" % str(events))
	assert_eq(w.ball.holder_id, ret.id, "returner holds the caught (dead) ball")
	var spot: float = w.dead_ball_spot.y
	assert_near(spot, ret.position.y, 0.01, "dead at the catch spot")
	var out := m.next_play()
	assert_eq(out["outcome"], "fair_catch")
	assert_eq(w.offense_team, 1, "return team's ball")
	assert_near(w.los_y, 100.0 - spot, 0.01, "punt: ball at the catch spot")
	assert_eq(m.downs.down, 1)

func test_kickoff_fair_catch_inside_the_25_comes_out_to_the_25() -> void:
	var m := _kickoff_in_air(100.0, 0.75)
	var w := m.world
	var ret := w.returner()
	ret.position = _landing(w)
	assert_true(ret.position.y > 75.0 and ret.position.y < 100.0, "comes down inside the receiving 25 (%.1f)" % ret.position.y)
	assert_true(w.signal_fair_catch(ret.id), "signal")
	_steps(w, 400)
	assert_true(events.has("fair_catch"), "fair catch (%s)" % str(events))
	var out := m.next_play()
	assert_eq(out["outcome"], "fair_catch")
	assert_eq(w.offense_team, 1)
	assert_near(w.los_y, 25.0, 0.01, "kickoff fair catch short of the 25 is spotted at the 25")
	assert_eq(m.state, Match.State.SCRIMMAGE)

func test_kickoff_fair_catch_past_the_25_keeps_the_catch_spot() -> void:
	var m := _kickoff_in_air(62.0, 0.4)
	var w := m.world
	var ret := w.returner()
	ret.position = _landing(w)
	assert_true(ret.position.y < 75.0, "comes down past the receiving 25 (%.1f)" % ret.position.y)
	assert_true(w.signal_fair_catch(ret.id), "signal")
	_steps(w, 400)
	assert_true(events.has("fair_catch"), "fair catch (%s)" % str(events))
	var spot: float = w.dead_ball_spot.y
	m.next_play()
	assert_near(w.los_y, 100.0 - spot, 0.01, "kickoff fair catch past the 25: at the catch spot")

func test_fair_catch_in_the_end_zone_is_a_touchback() -> void:
	var m := _punt_in_air(55.0, 100.0)
	var w := m.world
	w.ball.velocity = World.kick_velocity("punt", w.kick_spot, Vector2(w.field.width / 2.0, 104.0), 1.0)
	var ret := w.returner()
	ret.position = _landing(w)
	assert_true(ret.position.y > 100.0, "comes down in the end zone (%.1f)" % ret.position.y)
	assert_true(w.signal_fair_catch(ret.id), "signal")
	_steps(w, 400)
	assert_true(events.has("touchback") and not events.has("fair_catch"), "touchback (%s)" % str(events))
	m.next_play()
	assert_near(w.los_y, 20.0, 0.01, "punt touchback at the 20")

func test_signal_window() -> void:
	var w := _world()
	var m := Match.new(w)
	m.start(0, 30.0)
	m.downs.down = 4
	var ret := w.returner()
	assert_true(not w.signal_fair_catch(ret.id), "no signal before the snap")
	m.call_kick("punt")
	w.snap()
	_steps(w, 30)
	assert_true(not w.signal_fair_catch(ret.id), "no signal before the kick")
	w.kick(w.kicker().id, Vector2(w.field.width / 2.0, 70.0), 0.7)
	var cover := w.find_role(0, R.WR)
	assert_true(not w.signal_fair_catch(cover.id), "kicking team can't signal")
	P.apply_action(m, cover.id, {"a": "snap"})   # live play: the kicking team's Space jumps (#379)
	assert_eq(w.fair_catch_id, -1, "kicking team's Snap key never signals a fair catch")
	assert_true(w.signal_fair_catch(ret.id), "returner signals while it is in the air")
	var mate := w.find_role(1, R.CB)
	assert_true(not w.signal_fair_catch(mate.id), "one signal per kick")
	assert_true(not w.signal_fair_catch(ret.id), "no double signal")
	# Field goals have no fair catch.
	var g := _world()
	var fm := Match.new(g)
	fm.start(0, 80.0)
	fm.downs.down = 4
	fm.call_kick("fg")
	g.snap()
	_steps(g, 30)
	g.kick(g.kicker().id, Vector2(g.field.width / 2.0, g.field.posts_y()), 0.8)
	assert_true(not g.signal_fair_catch(g.returner().id), "no fair catch on a field goal")

func test_no_signal_after_the_ball_lands() -> void:
	var m := _punt_in_air()
	var w := m.world
	var ret := w.returner()
	ret.position = Vector2(2.0, ret.position.y)   # nowhere near it
	for i in 400:
		w.step({}, DT)
		if events.has("kick_land"):
			break
	assert_true(events.has("kick_land"), "landed")
	assert_true(not w.signal_fair_catch(ret.id), "too late once it hits the ground")

func test_muffed_fair_catch_stays_live_and_is_dead_at_recovery() -> void:
	var m := _punt_in_air()
	var w := m.world
	var ret := w.returner()
	assert_true(w.signal_fair_catch(ret.id), "signal")
	ret.position = Vector2(2.0, ret.position.y)   # misses it: the ball reaches the ground
	for i in 400:
		w.step({}, DT)
		if events.has("kick_land"):
			break
	assert_true(events.has("kick_land"), "landed")
	assert_eq(w.phase, World.Phase.LIVE, "a muffed fair catch stays live")
	assert_true(not events.has("whistle"), "no whistle on the landing")
	# The returner scoops it up once it settles: no advance after a signal.
	for i in 400:
		var bp := Vector2(w.ball.position.x, w.ball.position.y)
		if w.ball.position.z <= T.RECOVER_MAX_HEIGHT:
			ret.position = bp
		w.step({}, DT)
		if w.phase == World.Phase.DEAD:
			break
	assert_true(events.has("kick_downed") and not events.has("fair_catch") and not events.has("kick_catch"), "recovered, dead at the spot (%s)" % str(events))
	assert_eq(ev_data["kick_downed"].get("by", -1), ret.id)
	var spot: float = w.dead_ball_spot.y
	var out := m.next_play()
	assert_eq(out["outcome"], "punt")
	assert_eq(w.offense_team, 1)
	assert_near(w.los_y, 100.0 - spot, 0.01, "return team's ball at the recovery spot")

func test_teammate_catch_after_a_signal_has_no_return() -> void:
	var m := _punt_in_air()
	var w := m.world
	var ret := w.returner()
	assert_true(w.signal_fair_catch(ret.id), "signal")
	ret.position = Vector2(2.0, ret.position.y)
	var mate := w.find_role(1, R.CB)
	mate.position = _landing(w)
	_steps(w, 400)
	assert_true(events.has("kick_downed") and not events.has("fair_catch") and not events.has("kick_catch"), "dead where the teammate caught it (%s)" % str(events))
	assert_near(w.dead_ball_spot.y, mate.position.y, 0.01)

func test_signaling_returner_cannot_be_blocked() -> void:
	for signal_it in [false, true]:
		var m := _punt_in_air()
		var w := m.world
		var ret := w.returner()
		ret.position = _landing(w)
		var ol := w.find_role(0, R.OL)
		ol.position = ret.position + Vector2(0, -0.8)
		ol.facing = Vector2(0, 1)
		if signal_it:
			w.signal_fair_catch(ret.id)
		w.step({}, DT)
		if signal_it:
			assert_eq(ret.engaged_with, -1, "nobody blocks the signaling returner")
		else:
			assert_eq(ret.engaged_with, ol.id, "control: without a signal the coverage man engages him")

func test_blocked_kick_clears_the_signal() -> void:
	var m := _punt_in_air()
	var w := m.world
	w.signal_fair_catch(w.returner().id)
	var rusher := w.find_role(1, R.DL)
	rusher.position = Vector2(w.ball.position.x, w.ball.position.y)
	w.step({}, DT)
	assert_true(events.has("kick_blocked"), "blocked (%s)" % str(events))
	assert_eq(w.fair_catch_id, -1, "the signal doesn't carry over to a blocked kick")

func test_bot_returner_fair_catches_only_under_pressure() -> void:
	for pressure in [false, true]:
		var m := _punt_in_air()
		var w := m.world
		var ret := w.returner()
		ret.position = _landing(w)
		var cover := w.find_role(0, R.WR)
		cover.position = _landing(w) + Vector2(3.0, -2.0) if pressure else Vector2(-1.5, 10.0)
		var ai := AI.new()
		ai.offense_enabled = false   # coverage holds still: the rule, not the race, is under test
		for i in 400:
			w.step(ai.think(w, []), DT)
			if w.phase == World.Phase.DEAD or events.has("kick_catch"):
				break
		if pressure:
			assert_true(events.has("fair_catch_signal") and events.has("fair_catch"), "covered bot fair-catches (%s)" % str(events))
		else:
			assert_true(not events.has("fair_catch_signal") and events.has("kick_catch"), "uncovered bot returns it (%s)" % str(events))

func test_bot_rule_waits_for_the_ball_to_come_down() -> void:
	var m := _punt_in_air()
	var w := m.world
	var land := _landing(w)
	w.find_role(0, R.WR).position = land
	assert_true(w.ball.velocity.z > 0.0, "still rising")
	assert_true(not AI.wants_fair_catch(w, land), "no signal on the way up")
	for i in 300:
		if w.ball.velocity.z < 0.0:
			break
		w.step({}, DT)
	assert_true(w.ball.velocity.z < 0.0 and w.kick_in_air(), "coming down")
	assert_true(AI.wants_fair_catch(w, land), "signal once it comes down with coverage there")

func test_human_returner_is_never_auto_signaled() -> void:
	var m := _punt_in_air()
	var w := m.world
	var ret := w.returner()
	ret.position = _landing(w)
	w.find_role(0, R.WR).position = _landing(w)
	var ai := AI.new()
	ai.offense_enabled = false
	for i in 400:
		var inputs := ai.think(w, [ret.id])
		inputs[ret.id] = {World.HUMAN: true}
		w.step(inputs, DT)
		if w.phase == World.Phase.DEAD or events.has("kick_catch"):
			break
	assert_true(not events.has("fair_catch_signal"), "only the human decides (%s)" % str(events))

func test_snapshot_carries_the_signal() -> void:
	var m := _punt_in_air()
	var w := m.world
	var ret := w.returner()
	w.signal_fair_catch(ret.id)
	var snap := P.encode_snapshot(m, 1)
	assert_true(P.valid_snapshot(snap, w.athletes.size()), "valid")
	var b := Match.new(_world())
	b.start(0)
	P.apply_snapshot(b, snap)
	assert_eq(b.world.fair_catch_id, ret.id, "client sees who signaled")
	assert_true(b.world.kick_in_air(), "client knows the kick is in the air")
	snap["fc"] = w.athletes.size()
	assert_true(not P.valid_snapshot(snap, w.athletes.size()), "out-of-range signaler rejected")
	snap["fc"] = "x"
	assert_true(not P.valid_snapshot(snap, w.athletes.size()), "non-int signaler rejected")
