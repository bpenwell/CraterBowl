extends "res://tests/test_case.gd"
## C08d + #142: everyone lines up stance-locked. The offense stays set until the
## snap; non-DL defenders break stance with a Space double-tap (one snap action on
## the wire). Neutral-zone clamp shared by host step and client prediction.

const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const P := preload("res://src/net/protocol.gd")
const Predictor := preload("res://src/net/client_predictor.gd")
const T := preload("res://src/sim/tuning.gd")
const AI := preload("res://src/sim/ai.gd")
const DoubleTap := preload("res://src/sim/double_tap.gd")
const DT := 1.0 / 60.0
const R := Athlete.Role

func _match() -> Match:
	var w := World.new()
	var cx := w.field.width / 2.0
	var pairs := [[R.C, 0.0, R.DL, -1.5], [R.QB, 0.0, R.LB, 0.0], [R.WR, -18.0, R.CB, -18.0], [R.WR, 18.0, R.CB, 18.0], [R.RB, 4.0, R.S, -8.0], [R.OL, -2.5, R.DL, 1.5], [R.OL, 2.5, R.S, 8.0]]
	for t in 2:
		for p in pairs:
			w.add_two_way(t, p[0], cx + p[1], p[2], cx + p[3])
	var m := Match.new(w)
	m.start(0, 25.0)
	return m

func _run(w, inputs: Dictionary, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		w.step(inputs, DT)

func test_everyone_lines_up_locked() -> void:
	var w := _match().world
	for a in w.athletes:
		assert_true(a.set_lock, "athlete %d lines up set" % a.id)

func test_locked_defender_holds_spot_but_turns() -> void:
	var w := _match().world
	var lb := w.find_role(1, R.LB)
	var start := lb.position
	_run(w, {lb.id: {"dir": Vector2(1, 0), "sprint": true}}, 1.0)
	assert_true(lb.position.distance_to(start) < 0.01, "locked LB didn't move")
	assert_near(lb.facing.x, 1.0, 0.001, "but faces the input")

## #142: no offensive athlete translates pre-snap, human or bot, but each turns.
func test_offense_frozen_until_snap() -> void:
	for human in [true, false]:
		var w := _match().world
		var inputs := {}
		var start := {}
		for a in w.athletes:
			if a.team == w.offense_team:
				inputs[a.id] = {"dir": Vector2(1, 0), "sprint": true, World.HUMAN: human}
				start[a.id] = a.position
		_run(w, inputs, 1.0)
		for id in start:
			var a := w.get_athlete(id)
			assert_true(a.position.distance_to(start[id]) < 0.001, "offense %d (%s) held pre-snap (human=%s)" % [id, a.role, human])
			assert_near(a.facing.x, 1.0, 0.001, "offense %d still turns to face" % id)
		assert_true(w.snap(), "snap")
		var wr := w.find_role(0, R.WR)
		var x0 := wr.position.x
		_run(w, inputs, 0.5)
		assert_true(wr.position.x - x0 > 2.0, "offense moves once the ball is snapped")

func test_offense_cannot_break_stance() -> void:
	var w := _match().world
	for a in w.athletes:
		if a.team == w.offense_team:
			assert_true(not w.can_break_stance(a), "offense %s can't break stance" % a.role)
			assert_true(not w.break_stance(a.id) and a.set_lock, "offense %s stays set" % a.role)

func test_bots_hold_offense_presnap() -> void:
	var m := _match()
	var w := m.world
	var ai := AI.new()
	var start := []
	for a in w.athletes:
		start.append(a.position)
	for i in 60:   # under AI_SNAP_DELAY: bots call a play but haven't snapped
		ai.presnap_tick(w, [], DT)
		w.step(ai.think(w, []), DT)
	assert_eq(w.phase, World.Phase.PRESNAP, "still pre-snap")
	for a in w.athletes:
		if a.team == w.offense_team:
			assert_true(a.position.distance_to(start[a.id]) < 0.001, "bot %s held" % a.role)

func test_kickoff_coverage_waits_for_the_kick() -> void:
	var w := _match().world
	w.setup_kickoff(30.0)
	var k := w.kicker()
	var cover: Athlete = null
	for a in w.athletes:
		if a.team == w.offense_team and a != k:
			cover = a
			break
	var y0 := cover.position.y
	_run(w, {cover.id: {"dir": Vector2(0, 1), World.HUMAN: true}}, 0.5)
	assert_near(cover.position.y, y0, 0.001, "coverage held before the kick")
	assert_true(w.kick(k.id, Vector2(w.field.width / 2.0, w.field.length), 0.8), "kick off")
	_run(w, {cover.id: {"dir": Vector2(0, 1), World.HUMAN: true}}, 0.5)
	assert_true(cover.position.y - y0 > 2.0, "coverage runs once the ball is kicked")

func test_break_stance_rules() -> void:
	var w := _match().world
	for role in [R.LB, R.CB, R.S]:
		var a := w.find_role(1, role)
		assert_true(w.break_stance(a.id), "%s can break stance" % role)
		assert_true(not a.set_lock, "unlocked")
		assert_true(not w.break_stance(a.id), "already unlocked -> false")
	var dl := w.find_role(1, R.DL)
	assert_true(not w.break_stance(dl.id), "DL holds stance")
	assert_true(dl.set_lock, "DL still locked")
	assert_true(not w.break_stance(w.find_role(0, R.WR).id), "offense can't break stance")
	assert_true(not w.can_break_stance(dl), "DL never offered a stance break")

func test_break_stance_only_presnap() -> void:
	var m := _match()
	var w := m.world
	var cb := w.find_role(1, R.CB)
	assert_true(w.snap(), "snap")
	assert_true(not w.break_stance(cb.id), "no break_stance in LIVE")

func test_roaming_defender_moves_but_stops_at_line() -> void:
	var w := _match().world
	var lb := w.find_role(1, R.LB)
	w.break_stance(lb.id)
	var x0 := lb.position.x
	_run(w, {lb.id: {"dir": Vector2(1, 0)}}, 0.5)
	assert_true(lb.position.x - x0 > 1.0, "unlocked LB roams")
	for i in 120:
		w.step({lb.id: {"dir": Vector2(0, -1), "sprint": true}}, DT)
		assert_true(lb.position.y >= w.los_y + T.NEUTRAL_ZONE_HALF - 0.0001, "never past neutral zone")
	assert_near(lb.position.y, w.los_y + T.NEUTRAL_ZONE_HALF, 0.001, "pressed against the line")

func test_enforce_reports_contact() -> void:
	var w := _match().world
	var lb := w.find_role(1, R.LB)
	lb.position.y = w.los_y
	lb.velocity = Vector2(0, -3)
	assert_true(w.enforce_neutral_zone(lb), "pushing into the line is a contact")
	assert_true(not w.enforce_neutral_zone(lb), "standing at the line is not")

func test_snap_clears_and_next_play_relocks() -> void:
	var m := _match()
	var w := m.world
	w.snap()
	for a in w.athletes:
		assert_true(not a.set_lock, "LIVE: no locks")
	w.setup_formation(30.0)
	assert_true(w.find_role(1, R.CB).set_lock, "next play re-locks the defense")

func test_protocol_snap_routes_by_side() -> void:
	var m := _match()
	var w := m.world
	var s := w.find_role(1, R.S)
	assert_true(P.apply_action(m, s.id, {"a": "snap"}), "defense Space -> break stance")
	assert_eq(w.phase, World.Phase.PRESNAP, "ball not snapped")
	assert_true(not s.set_lock, "S roaming")
	assert_true(P.apply_action(m, w.find_role(0, R.QB).id, {"a": "snap"}), "offense Space -> snap")
	assert_eq(w.phase, World.Phase.LIVE, "snapped")

func test_snapshot_carries_lock() -> void:
	var a := _match()
	a.world.break_stance(a.world.find_role(1, R.CB).id)
	var b := _match()
	for ath in b.world.athletes:
		ath.set_lock = not ath.set_lock   # scramble so the decode must set it
	P.apply_snapshot(b, bytes_to_var(var_to_bytes(P.encode_snapshot(a, 1))))
	for i in a.world.athletes.size():
		assert_eq(b.world.athletes[i].set_lock, a.world.athletes[i].set_lock, "lock %d" % i)

func test_prediction_obeys_lock_and_clamp() -> void:
	var w := _match().world
	var lb := w.find_role(1, R.LB)
	var start := lb.position
	var pred := Predictor.new()
	for i in 30:
		pred.record(Vector2(0, -1), true, DT)
		w.predict_step(lb, Vector2(0, -1), true, DT)
	assert_true(lb.position.distance_to(start) < 0.01, "predicted locked LB stays put")
	w.break_stance(lb.id)
	for i in 120:
		pred.record(Vector2(0, -1), true, DT)
		w.predict_step(lb, Vector2(0, -1), true, DT)
	assert_true(lb.position.y >= w.los_y + T.NEUTRAL_ZONE_HALF - 0.0001, "prediction clamps")
	# Reconcile from an old authoritative spot: replays must clamp too.
	lb.position = start
	lb.velocity = Vector2.ZERO
	pred.reconcile(lb, 10, w)
	assert_true(lb.position.y >= w.los_y + T.NEUTRAL_ZONE_HALF - 0.0001, "reconcile replay clamps")

## #142: client prediction applies the same offense lock as the host step.
func test_prediction_holds_offense_like_host() -> void:
	var host := _match().world
	var client := _match().world
	var hw := host.find_role(0, R.WR)
	var cw := client.find_role(0, R.WR)
	for i in 60:
		host.step({hw.id: {"dir": Vector2(1, 1).normalized(), "sprint": true, World.HUMAN: true}}, DT)
		client.predict_step(cw, Vector2(1, 1).normalized(), true, DT)
	assert_true(cw.position.distance_to(hw.position) < 0.0001, "predicted WR = host WR")
	assert_true(cw.facing.distance_to(hw.facing) < 0.0001, "predicted facing = host facing")
	assert_true(cw.position.distance_to(Vector2(cw.home_x, client.los_y - 1.0)) < 0.001, "both held on the line")

## #142: one Space press does nothing for a set defender; two inside the window break stance.
func test_double_tap_window() -> void:
	var tap := DoubleTap.new()
	assert_true(not tap.press(10.0), "first press alone does nothing")
	assert_true(tap.press(10.0 + T.STANCE_DOUBLE_TAP - 0.01), "second press inside the window")
	assert_true(not tap.press(10.5), "the pair was consumed: a third press starts over")
	assert_true(not tap.press(10.5 + T.STANCE_DOUBLE_TAP + 0.01), "too slow: no double-tap")
	assert_true(tap.press(10.5 + T.STANCE_DOUBLE_TAP + 0.2), "but that press opens a new window")
	tap.press(20.0)
	tap.reset()
	assert_true(not tap.press(20.1), "reset forgets a pending press")

## The double-tap feeds the unchanged one-action protocol: one press = no action
## sent; the completing press sends one snap, which the host turns into break_stance.
func test_double_tap_drives_one_break_stance() -> void:
	var m := _match()
	var w := m.world
	var cb := w.find_role(1, R.CB)
	var tap := DoubleTap.new()
	var sent := 0
	for t in [1.0, 1.2]:
		if w.can_break_stance(cb) and not tap.press(t):
			continue
		sent += 1
		assert_true(P.apply_action(m, cb.id, {"a": "snap"}), "host breaks stance")
	assert_eq(sent, 1, "one action for the double-tap")
	assert_true(not cb.set_lock and w.phase == World.Phase.PRESNAP, "CB roaming, ball not snapped")

## #183: a set defender's prompt carries the "<key> ×2 TO ROAM" hint only when main
## passes a key (set, non-DL, not roamed yet); DL, roaming and no-key prompts never do.
func test_presnap_prompt_roam_hint() -> void:
	var Main = load("res://src/game/main.gd")
	var w := _match().world
	var lb := w.find_role(1, R.LB)
	assert_eq(Main.presnap_defense_prompt(lb, "SPACE"), "PRE-SNAP: SET  ·  SPACE ×2 TO ROAM", "set LB: hint with the key")
	assert_eq(Main.presnap_defense_prompt(lb, "B"), "PRE-SNAP: SET  ·  B ×2 TO ROAM", "names whatever key it is given")
	assert_eq(Main.presnap_defense_prompt(lb), "PRE-SNAP: SET", "no key (already roamed): plain SET")
	assert_eq(Main.presnap_defense_prompt(w.find_role(1, R.DL), "SPACE"), "PRE-SNAP (hold your stance)", "DL never gets it")
	w.break_stance(lb.id)
	assert_eq(Main.presnap_defense_prompt(lb, "SPACE"), "PRE-SNAP: ROAMING", "roaming: no hint")
	assert_eq(Main.presnap_defense_prompt(null, "SPACE"), "PRE-SNAP", "no athlete")
