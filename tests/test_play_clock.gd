extends "res://tests/test_case.gd"
## #136: one authoritative play clock. The HUD value (Match.play_clock_shown) is the
## countdown the snap obeys, for bot offenses, kickoffs, the coin toss and online clients.

const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Clock := preload("res://src/sim/clock.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const AI := preload("res://src/sim/ai.gd")
const P := preload("res://src/net/protocol.gd")
const T := preload("res://src/sim/tuning.gd")
const DT := 1.0 / 60.0
const R := Athlete.Role

var snaps: Array = []        # play clock at each world "snap" event
var auto_snaps := 0

func _match() -> Match:
	var w := World.new()
	var cx := w.field.width / 2.0
	var pairs := [[R.C, 0.0, R.DL, -1.5], [R.QB, 0.0, R.LB, 0.0], [R.WR, -18.0, R.CB, -18.0], [R.WR, 18.0, R.CB, 18.0], [R.RB, 4.0, R.S, -8.0], [R.OL, -2.5, R.DL, 1.5], [R.OL, 2.5, R.S, 8.0]]
	for t in 2:
		for p in pairs:
			w.add_two_way(t, p[0], cx + p[1], p[2], cx + p[3])
	var m := Match.new(w)
	m.start(0, 25.0)
	snaps.clear()
	auto_snaps = 0
	var clock := m.clock   # not m: a lambda holding m from w's signal is a leak cycle
	w.event.connect(func(n, _d): if n == "snap": snaps.append(clock.play_clock))
	m.match_event.connect(func(n, _d): if n == "auto_snap": auto_snaps += 1)
	return m

## One host tick in main.gd's order: clocks (+ clock snap), bot huddle, bot play call, step.
func _host_tick(m: Match, ai: AI, humans: Array) -> void:
	var w := m.world
	m.tick(DT, func(): return ai.snap(w) if AI.offense_is_bot(w, humans) else w.snap())
	if AI.offense_is_bot(w, humans):
		m.huddle(AI.huddle_seconds(w, T.HUDDLE_SECONDS))
	ai.snaps_on_clock = true
	ai.presnap_tick(w, humans, DT, m.downs.down, m.downs.distance(), T.HUDDLE_SECONDS)
	w.step(ai.think(w, humans), DT)

## Ticks until the ball is live; returns the HUD values shown on each presnap tick.
func _run_to_snap(m: Match, ai: AI, humans: Array, max_s := 30.0) -> Array:
	var shown := []
	for i in int(max_s / DT):
		if m.world.phase != World.Phase.PRESNAP:
			break
		_host_tick(m, ai, humans)
		if m.world.phase == World.Phase.PRESNAP:
			shown.append(m.play_clock_shown())
	return shown

func _human_on(m: Match, team: int) -> Array:
	for a in m.world.athletes:
		if a.team == team:
			return [a.id]
	return []

## Line up a kickoff with team `kicking` kicking, as next_play() would.
func _line_up_kickoff(m: Match, kicking: int) -> void:
	m.last_outcome = m._kickoff(1 - kicking)
	m._line_up_next_play()

func _human_on_defense(m: Match) -> Array:
	return [m.world.find_role(1 - m.world.offense_team, R.LB).id]

func test_bot_offense_snaps_when_the_shown_clock_hits_zero() -> void:
	var m := _match()
	var ai := AI.new()
	var humans := _human_on_defense(m)
	m.tick(DT)   # a little of the 20 s gone, as when the huddle starts mid-presnap
	var shown := _run_to_snap(m, ai, humans)
	assert_eq(m.world.phase, World.Phase.LIVE, "bot offense snapped")
	assert_eq(snaps.size(), 1, "one snap")
	assert_true(snaps[0] <= 0.0, "snapped only once the play clock ran out (%.3f left)" % snaps[0])
	assert_eq(auto_snaps, 1, "the play clock snapped it, not a private bot timer")
	assert_eq(shown[0], int(T.HUDDLE_SECONDS), "HUD shows the bot huddle from the first tick (%d)" % shown[0])
	assert_true(shown.max() <= int(T.HUDDLE_SECONDS) and shown.min() >= 0, "never shows more time than the snap waits")
	assert_true(shown.back() <= 1, "last value shown before the snap is :01 or :00 (%d)" % shown.back())
	assert_near(shown.size() * DT, T.HUDDLE_SECONDS, 2.0 * DT, "same huddle length as before (%.2f s)" % (shown.size() * DT))

func test_human_offense_keeps_the_full_play_clock_and_auto_snaps_at_zero() -> void:
	var m := _match()
	var ai := AI.new()
	var shown := _run_to_snap(m, ai, [m.world.find_role(0, R.QB).id])
	assert_eq(shown[0], int(Clock.PLAY_CLOCK), "full 20 s for a human offense")
	assert_true(snaps[0] <= 0.0 and auto_snaps == 1, "AFK human offense auto-snaps at 0")

func test_human_snap_may_beat_the_clock() -> void:
	var m := _match()
	var ai := AI.new()
	for i in 60:
		_host_tick(m, ai, [m.world.find_role(0, R.QB).id])
	assert_true(m.world.snap(), "user snap")
	assert_true(snaps[0] > 0.0 and auto_snaps == 0, "a user snap is the one early start")

func test_bot_kickoff_waits_for_the_shown_clock() -> void:
	var m := _match()
	_line_up_kickoff(m, 1)   # team 1 (bots) kicks to the human team 0
	var ai := AI.new()
	var shown := _run_to_snap(m, ai, _human_on(m, 0))
	assert_eq(m.world.kick_play, "kickoff")
	assert_true(m.world.kicked, "bots kicked off")
	assert_true(snaps[0] <= 0.0 and auto_snaps == 1, "kicked when the clock ran out (%.3f)" % snaps[0])
	assert_eq(shown[0], int(ceil(T.AI_SNAP_DELAY)), "kickoff huddle shown (%d)" % shown[0])

func test_bot_kickoff_keeps_its_depth_variety() -> void:
	var powers := []
	for k in 3:
		var m := _match()
		_line_up_kickoff(m, 1)
		var ai := AI.new()
		ai._calls = k
		_run_to_snap(m, ai, _human_on(m, 0))
		powers.append(snappedf(m.world.ball.velocity.length(), 0.01))
	assert_true(powers[0] != powers[1] and powers[1] != powers[2], "bot kickoffs still vary (%s)" % str(powers))

func test_coin_toss_hides_and_holds_the_play_clock() -> void:
	var m := _match()
	m.start_match(1, true)   # team 1 wins; humans on the winning side choose
	var ai := AI.new()
	var humans := _human_on(m, 1)
	assert_eq(m.play_clock_shown(), -1, "toss: no play clock shown")
	for i in int(3.0 / DT):
		_host_tick(m, ai, humans)
	assert_eq(m.state, Match.State.TOSS)
	assert_eq(m.play_clock_shown(), -1, "still hidden during the toss")
	assert_near(m.clock.play_clock, Clock.PLAY_CLOCK, 0.001, "play clock doesn't run during the toss")
	assert_true(m.choose_toss(1, "receive"), "winner receives: team 0 (bots) kicks")
	assert_eq(m.play_clock_shown(), int(Clock.PLAY_CLOCK), "fresh play clock for the kickoff")
	var shown := _run_to_snap(m, ai, humans)
	assert_true(m.world.kicked and snaps[0] <= 0.0, "bot kickoff after the toss waits for its clock (%.3f)" % snaps[0])
	# #129: the clock waits out the cutscene's outro (TOSS_OUTRO), then the bots' huddle runs.
	assert_near(shown.size() * DT, T.AI_SNAP_DELAY + Match.TOSS_OUTRO, 2.0 * DT, "not instantly after the choice (%.2f s)" % (shown.size() * DT))
	var held := shown.slice(0, int(Match.TOSS_OUTRO / DT) - 1)
	assert_true(held.all(func(v): return v == held[0]), "the shown clock doesn't move during the outro (%s)" % str(held.slice(0, 6)))

func test_timeout_gives_the_bot_offense_a_fresh_huddle() -> void:
	var m := _match()
	var ai := AI.new()
	var humans := _human_on_defense(m)
	for i in int(4.0 / DT):
		_host_tick(m, ai, humans)
	assert_true(m.call_timeout(0), "defense timeout")
	_host_tick(m, ai, humans)
	assert_eq(m.play_clock_shown(), int(T.HUDDLE_SECONDS), "huddle restarts after the timeout")
	_run_to_snap(m, ai, humans)
	assert_true(snaps[0] <= 0.0, "snap still waits for the shown clock")

func test_play_clock_hidden_outside_presnap() -> void:
	var m := _match()
	assert_eq(m.play_clock_shown(), int(Clock.PLAY_CLOCK), "presnap: shown")
	m.world.snap()
	assert_eq(m.play_clock_shown(), -1, "live: hidden")
	m.world.phase = World.Phase.DEAD
	assert_eq(m.play_clock_shown(), -1, "dead ball: hidden")
	m.world.phase = World.Phase.PRESNAP
	m.clock.final = true
	assert_eq(m.play_clock_shown(), -1, "final: hidden")

func test_bots_never_snap_on_a_private_timer_in_a_match() -> void:
	var m := _match()
	var ai := AI.new()
	ai.snaps_on_clock = true
	for i in int(10.0 / DT):
		ai.presnap_tick(m.world, [], DT, 1, 10.0, T.AI_SNAP_DELAY)
	assert_eq(m.world.phase, World.Phase.PRESNAP, "only the play clock snaps for the bots")

func test_client_shows_the_host_value_every_tick() -> void:
	var host := _match()
	var client := _match()
	var ai := AI.new()
	host.start_match(0, true)
	var humans := _human_on(host, 0)
	var phases := {}
	for i in int(12.0 / DT):
		if host.state == Match.State.TOSS and i == int(2.0 / DT):
			host.choose_toss(0, "kick")   # human team 0 kicks: 20 s clock, auto-kick at 0
		if host.world.phase == World.Phase.DEAD:
			break
		_host_tick(host, ai, humans)
		P.apply_snapshot(client, P.encode_snapshot(host, i, {}))
		phases[host.play_clock_shown() >= 0] = true
		if client.play_clock_shown() != host.play_clock_shown():
			assert_eq(client.play_clock_shown(), host.play_clock_shown(), "tick %d: client shows host's play clock" % i)
			return
	assert_true(phases.has(true) and phases.has(false), "covered shown and hidden states")
	# Second-by-second countdown through float32 transport: every value matches.
	host.start(0, 25.0)
	for i in int(Clock.PLAY_CLOCK / DT) - 2:
		host.tick(DT)
		P.apply_snapshot(client, P.encode_snapshot(host, i, {}))
		if client.play_clock_shown() != host.play_clock_shown():
			assert_eq(client.play_clock_shown(), host.play_clock_shown(), "countdown tick %d (%.6f)" % [i, host.clock.play_clock])
			return
