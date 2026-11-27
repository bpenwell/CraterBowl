extends "res://tests/test_case.gd"
## B09 kickoffs + returns, C02 coin toss / punts / field goals / PATs / blocks.

const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const AI := preload("res://src/sim/ai.gd")
const Passing := preload("res://src/sim/passing.gd")
const P := preload("res://src/net/protocol.gd")
const T := preload("res://src/sim/tuning.gd")
const Stats := preload("res://src/sim/stats.gd")
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

func _match(los: float = 25.0) -> Match:
	var w := _world()
	var m := Match.new(w)
	m.start(0, los)
	_listen(w)
	return m

## A live kickoff with team `kicking` kicking (team 1 - kicking receives).
func _kickoff_match(kicking: int = 0) -> Match:
	var m := _match()
	m.score = [7, 0]
	m.last_result = {"type": "touchdown", "team": kicking}
	m.state = Match.State.TRY
	m.downs.offense_team = kicking
	m.world.set_offense(kicking)
	m.last_result = {"type": "field_goal", "good": true, "team": kicking}
	m.next_play()   # good PAT -> kickoff by `kicking`
	return m

func _steps(w, n: int, inputs: Dictionary = {}) -> void:
	for i in n:
		w.step(inputs, DT)
		if w.phase == World.Phase.DEAD:
			return

func _run_until_dead(w, max_steps: int = 900) -> void:
	_steps(w, max_steps)

## Where the kicked ball comes down through catch height.
func _landing(w) -> Vector2:
	var b = w.ball
	var t := Passing.time_to_height(b.velocity, b.position.z, T.CATCH_HEIGHT, w.gravity())
	return Vector2(b.position.x + b.velocity.x * t, b.position.y + b.velocity.y * t)

## Clear everyone except the named athletes far out of the play (no accidental blocks/catches).
func _park_all_but(w, keep: Array) -> void:
	for a in w.athletes:
		if not keep.has(a.id):
			a.position = Vector2(-1.5 if a.team == 0 else w.field.width + 1.5, a.position.y)

# --- Coin toss --------------------------------------------------------------

func test_coin_toss_default_receive_then_choice() -> void:
	var m := Match.new(_world())
	m.start_match(0)
	assert_eq(m.toss_winner, 0, "seed 0: home wins the toss")
	assert_eq(m.state, Match.State.TOSS, "waiting on the winner's choice")
	assert_eq(m.world.offense_team, 1, "default: winner receives, away kicks")
	assert_eq(m.world.kick_play, "kickoff")
	assert_true(m.world.kick_locked, "kickoff locked until the toss is decided")
	assert_true(not m.world.snap(), "no kick before the choice")
	assert_true(not m.choose_toss(1, "kick"), "loser can't choose")
	assert_true(m.choose_toss(0, "kick"), "winner chooses to kick")
	assert_eq(m.state, Match.State.KICKOFF)
	assert_eq(m.world.offense_team, 0, "winner kicks")
	assert_eq(m.opening_receiver, 1)
	assert_true(not m.world.kick_locked, "unlocked")
	assert_true(not m.choose_toss(0, "receive"), "choice is final")

func test_coin_toss_times_out_to_receive() -> void:
	var m := Match.new(_world())
	m.start_match(1)
	assert_eq(m.toss_winner, 1)
	# #129: the window opens when the coin lands (TOSS_REVEAL), so the winner gets all of it.
	for i in int((Match.TOSS_WINDOW + 0.2) / DT):
		m.tick(DT)
	assert_eq(m.state, Match.State.TOSS, "still choosing: the window runs from the reveal")
	while m.toss_elapsed() < Match.TOSS_REVEAL + Match.TOSS_WINDOW - 0.1:
		m.tick(DT)
	assert_eq(m.state, Match.State.TOSS, "still choosing 0.1 s before the window ends")
	for i in int(0.2 / DT):
		m.tick(DT)
	assert_eq(m.state, Match.State.KICKOFF, "window over")
	assert_eq(m.toss_choice, "receive")
	assert_eq(m.world.offense_team, 0, "home kicks to the toss winner")
	assert_eq(m.world.phase, World.Phase.PRESNAP, "still presnap (no accidental kick)")

## #129: the kickoff's play clock waits out the cutscene's outro after the pick, then runs.
func test_coin_toss_outro_holds_the_kickoff_clock() -> void:
	var m := Match.new(_world())
	m.start_match(0)
	while m.toss_elapsed() < Match.TOSS_REVEAL + 1.0:
		m.tick(DT)
	assert_true(m.choose_toss(0, "kick"), "winner kicks")
	for i in int((Match.TOSS_OUTRO - 0.05) / DT):
		m.tick(DT)
	assert_near(m.clock.play_clock, m.clock.PLAY_CLOCK, 0.001, "held through the outro")
	for i in int(0.3 / DT):
		m.tick(DT)
	assert_true(m.clock.play_clock < m.clock.PLAY_CLOCK - 0.1, "then it runs (%.2f)" % m.clock.play_clock)
	m.start(0)
	m.tick(DT)
	assert_true(m.clock.play_clock < m.clock.PLAY_CLOCK, "a fresh series has no leftover hold")

## The cutscene's timeline matches the sim: the coin lands on the reveal and the outro
## (pick, dip, fade back) fits inside the sim's clock hold.
func test_coin_toss_cutscene_fits_the_sim_timing() -> void:
	var CT := preload("res://src/game/coin_toss.gd")
	assert_eq(CT.LAND, Match.TOSS_REVEAL, "coin lands on the reveal")
	assert_true(CT.HOLD + CT.DIP + CT.UNDIP <= Match.TOSS_OUTRO, "outro fits the clock hold")
	assert_true(CT.FLIP_AT < CT.LAND and CT.WALK_END < CT.FLIP_AT, "walk, flip, land in order")

## #129: a bot winner waits for the coin to land (the cutscene's reveal), "thinks" for
## TOSS_BOT_PICK, then receives. The play clock never runs while it does.
func test_bot_toss_winner_receives_after_the_reveal() -> void:
	var m := Match.new(_world())
	m.start_match(1, false)
	assert_eq(m.state, Match.State.TOSS, "coin in the air: nobody has chosen yet")
	while m.toss_elapsed() < Match.TOSS_REVEAL + Match.TOSS_BOT_PICK - 0.05:
		m.tick(DT)
	assert_eq(m.state, Match.State.TOSS, "bot still choosing just before TOSS_BOT_PICK")
	assert_near(m.clock.play_clock, m.clock.PLAY_CLOCK, 0.001, "play clock held through the toss")
	for i in int(0.1 / DT):
		m.tick(DT)
	assert_eq(m.state, Match.State.KICKOFF)
	assert_eq(m.toss_choice, "receive", "bots receive")
	assert_eq(m.opening_receiver, 1)
	# 2nd half: the other team receives.
	m.clock.quarter = 2
	m.clock.remaining = 0.0
	m.world.phase = World.Phase.DEAD
	m.last_result = {"type": "touchback", "spot": 105.0}
	m.world.kicked = true
	var out := m.next_play()
	assert_eq(out["outcome"], "halftime")
	assert_eq(out["receiving"], 0, "toss loser receives the 2nd half")

# --- Kickoffs + returns (B09) ----------------------------------------------

func test_kickoff_alignment() -> void:
	var m := _kickoff_match(0)
	var w := m.world
	assert_eq(m.state, Match.State.KICKOFF)
	assert_near(w.los_y, 35.0, 0.001, "kick from own 35")
	var k := w.kicker()
	assert_true(w.ball.is_held_by(k.id), "kicker has the ball on the tee")
	for a in w.athletes:
		if a.team == 0:
			assert_true(a.position.y < w.los_y, "coverage behind the ball")
		else:
			assert_true(a.position.y >= w.los_y + 10.0, "return team 10+ yd off (%s at %.1f)" % [a.id, a.position.y])
	var deep := 0
	for a in w.athletes:
		if a.team == 1 and absf(a.position.y - 90.0) < 0.01:
			deep += 1
	assert_eq(deep, 2, "two deep returners at their own 10")

func test_kickoff_caught_returned_and_tackled() -> void:
	var m := _kickoff_match(0)
	var w := m.world
	var k := w.kicker()
	assert_true(w.kick(k.id, Vector2(w.field.width / 2.0, 100.0), 0.75), "kick")
	assert_eq(w.phase, World.Phase.LIVE, "kick starts the play")
	assert_true(events.has("snap"), "kickoff brackets the play (replay/stats)")
	var ret := w.returner()
	_park_all_but(w, [ret.id])
	ret.position = _landing(w)
	_steps(w, 300)
	assert_true(events.has("kick_catch"), "returner fielded it")
	assert_true(w.ball.is_held_by(ret.id), "returner has it")
	# Run it back to the 30 (kicking frame 70), get tackled there.
	ret.position = Vector2(20, 70)
	var cov := w.find_role(0, R.WR)
	cov.position = ret.position + Vector2(0, -0.9)
	cov.facing = Vector2(0, 1)
	w.tackle(cov.id)
	_steps(w, 30)
	assert_true(events.has("tackle"), "returner tackled")
	var out := m.next_play()
	assert_eq(out["outcome"], "kickoff_return")
	assert_eq(w.offense_team, 1, "return team's ball")
	assert_near(w.los_y, 30.0, 0.5, "at the spot (own 30)")
	assert_eq(m.downs.down, 1)
	assert_eq(m.state, Match.State.SCRIMMAGE)

func test_kickoff_touchback() -> void:
	var m := _kickoff_match(0)
	var w := m.world
	_park_all_but(w, [])
	w.kick(w.kicker().id, Vector2(w.field.width / 2.0, 100.0), 1.0)
	_run_until_dead(w)
	assert_true(events.has("touchback"), "deep kick into the end zone")
	var out := m.next_play()
	assert_eq(out["outcome"], "touchback")
	assert_eq(w.offense_team, 1)
	assert_near(w.los_y, 25.0, 0.01, "kickoff touchback at the 25")

func test_kickoff_fielded_in_end_zone_is_touchback() -> void:
	var m := _kickoff_match(0)
	var w := m.world
	w.kicker().position.y = 45.0   # long kick so it comes down past the goal line
	w.ball.hold(w.kicker().id)
	w.kick(w.kicker().id, Vector2(w.field.width / 2.0, 100.0), 1.0)
	var ret := w.returner()
	_park_all_but(w, [ret.id])
	ret.position = _landing(w)
	assert_true(ret.position.y > 100.0, "lands in the end zone (%.1f)" % ret.position.y)
	_run_until_dead(w)
	assert_true(events.has("touchback"), "caught in the end zone = touchback")
	m.next_play()
	assert_near(w.los_y, 25.0, 0.01)

func test_kickoff_out_of_bounds() -> void:
	var m := _kickoff_match(0)
	var w := m.world
	_park_all_but(w, [])
	w.kick(w.kicker().id, Vector2(w.field.width + 40.0, 60.0), 0.6)
	_run_until_dead(w)
	assert_true(events.has("kick_out_of_bounds"), "kick out of bounds (%s)" % str(events))
	var out := m.next_play()
	assert_eq(w.offense_team, 1)
	assert_near(w.los_y, 40.0, 0.01, "kickoff OOB: ball at the receiving 40 (%s)" % out["outcome"])

func test_kicking_team_recovery_is_downed_without_onside_mutator() -> void:
	var m := _kickoff_match(0)
	var w := m.world
	assert_true(not w.onside, "onside off by default")
	w.kick(w.kicker().id, Vector2(w.field.width / 2.0, 100.0), 0.0)
	var gunner := w.find_role(0, R.WR)
	_park_all_but(w, [gunner.id])
	for i in 400:
		w.step({}, DT)
		if events.has("kick_land") and w.ball.state == w.ball.State.LOOSE:
			gunner.position = Vector2(w.ball.position.x, w.ball.position.y) + Vector2(0.3, 0)
		if w.phase == World.Phase.DEAD:
			break
	assert_true(events.has("kick_downed") and not events.has("recovery"), "downed, not recovered (%s)" % str(events))
	m.next_play()
	assert_eq(w.offense_team, 1, "receiving team's ball")

func test_unfielded_kickoff_downed_by_kicking_team_short_of_onside() -> void:
	var m := _kickoff_match(0)
	var w := m.world
	_park_all_but(w, [])
	w.kick(w.kicker().id, Vector2(w.field.width / 2.0, 100.0), 0.0)
	_run_until_dead(w)
	assert_true(events.has("kick_downed"), "rolled dead (%s)" % str(events))
	m.next_play()
	assert_eq(w.offense_team, 1, "receiving team's ball where it died")

func test_onside_recovery() -> void:
	var m := _kickoff_match(0)
	var w := m.world
	w.onside = true   # C27 mutator; off by default
	var k := w.kicker()
	w.kick(k.id, Vector2(w.field.width / 2.0, 100.0), 0.0)
	var gunner := w.find_role(0, R.WR)
	_park_all_but(w, [gunner.id])
	var landed := false
	for i in 400:
		w.step({}, DT)
		if events.has("kick_land") and not landed:
			landed = true
		if landed and w.ball.state == w.ball.State.LOOSE:
			var bp := Vector2(w.ball.position.x, w.ball.position.y)
			gunner.position = bp + Vector2(0.3, 0)
		if events.has("recovery") or w.phase == World.Phase.DEAD:
			break
	assert_true(events.has("recovery") and ev_data["recovery"].get("onside", false), "kicking team recovers the onside kick (%s)" % str(events))
	assert_true(w.ball.is_held_by(gunner.id))

func test_kickoff_return_touchdown() -> void:
	var m := _kickoff_match(0)
	var w := m.world
	var stats := Stats.new()
	stats.attach(w, func(_aid): return "Ace")
	w.kick(w.kicker().id, Vector2(w.field.width / 2.0, 100.0), 0.75)
	var ret := w.returner()
	_park_all_but(w, [ret.id])
	ret.position = _landing(w)
	_steps(w, 300)
	ret.position = Vector2(20, -0.5)
	_steps(w, 2)
	assert_true(events.has("touchdown"), "return TD")
	_assert_return_touchdown(stats, ret)
	var out := m.next_play()
	assert_eq(m.score[1], 6, "return team +6")
	assert_eq(out["outcome"], "try")
	assert_eq(w.offense_team, 1, "returners kick the PAT")

# --- Punts ------------------------------------------------------------------

func _fourth_down(m, los: float) -> void:
	m.downs.reset(0, los)
	m.downs.down = 4
	m._setup_formation()

func test_punt_call_and_alignment() -> void:
	var m := _match(30.0)
	var w := m.world
	_fourth_down(m, 30.0)
	assert_true(m.call_kick("punt"), "offense calls a punt")
	assert_near(w.kicker().position.y, 20.0, 0.01, "punter 10 yd deep")
	assert_true(w.returner().position.y >= 60.0, "returner deep (%.1f)" % w.returner().position.y)
	assert_true(m.call_kick(""), "can call it off")
	assert_eq(w.kick_play, "")
	m.state = Match.State.TRY
	assert_true(not m.call_kick("punt"), "no punts on a try")

func test_punt_lands_rolls_downed() -> void:
	var m := _match(30.0)
	var w := m.world
	_fourth_down(m, 30.0)
	m.call_kick("punt")
	_park_all_but(w, [w.find_role(0, R.C).id, w.kicker().id])
	w.snap()
	_steps(w, 30)
	var k := w.kicker()
	assert_true(w.ball.is_held_by(k.id), "punter has the snap")
	assert_true(w.kick(k.id, Vector2(w.field.width / 2.0, 80.0), 0.7), "punt")
	assert_true(not w.throw(k.id, Vector2(20, 50), 0.5), "no throw after a kick")
	_run_until_dead(w)
	assert_true(events.has("kick_land"), "landed")
	assert_true(events.has("kick_downed"), "rolled dead")
	var spot: float = w.dead_ball_spot.y
	var out := m.next_play()
	assert_eq(out["outcome"], "punt")
	assert_eq(w.offense_team, 1, "possession changes")
	assert_near(w.los_y, 100.0 - spot, 0.01, "at the spot it died")
	assert_eq(m.downs.down, 1)

func test_punt_touchback_at_the_20() -> void:
	var m := _match(55.0)
	var w := m.world
	_fourth_down(m, 55.0)
	m.call_kick("punt")
	_park_all_but(w, [w.find_role(0, R.C).id, w.kicker().id])
	w.snap()
	_steps(w, 30)
	w.kick(w.kicker().id, Vector2(w.field.width / 2.0, 100.0), 1.0)
	_run_until_dead(w)
	assert_true(events.has("touchback"), "into the end zone (%s)" % str(events))
	m.next_play()
	assert_near(w.los_y, 20.0, 0.01, "punt touchback at the 20")

func test_punt_return_tackled() -> void:
	var m := _match(30.0)
	var w := m.world
	_fourth_down(m, 30.0)
	m.call_kick("punt")
	w.snap()
	_steps(w, 30)
	var ret := w.returner()
	_park_all_but(w, [w.find_role(0, R.C).id, w.kicker().id, ret.id])
	w.kick(w.kicker().id, Vector2(w.field.width / 2.0, 70.0), 0.7)
	ret.position = _landing(w)
	_steps(w, 400)
	assert_true(events.has("kick_catch"), "punt fielded")
	ret.position = Vector2(20, 60)
	var cov := w.find_role(0, R.WR)
	cov.position = ret.position + Vector2(0, -0.9)
	cov.facing = Vector2(0, 1)
	w.tackle(cov.id)
	_steps(w, 30)
	var out := m.next_play()
	assert_eq(out["outcome"], "punt_return")
	assert_near(w.los_y, 40.0, 0.5, "return team at its 40")

func test_punt_return_touchdown() -> void:
	var m := _match(30.0)
	var w := m.world
	var stats := Stats.new()
	stats.attach(w, func(_aid): return "Ace")
	_fourth_down(m, 30.0)
	m.call_kick("punt")
	w.snap()
	_steps(w, 30)
	var ret := w.returner()
	_park_all_but(w, [w.find_role(0, R.C).id, w.kicker().id, ret.id])
	assert_true(w.kick(w.kicker().id, Vector2(w.field.width / 2.0, 70.0), 0.7))
	ret.position = _landing(w)
	_steps(w, 400)
	assert_true(w.ball.is_held_by(ret.id), "returner fields the punt")
	ret.position = Vector2(20, -0.5)
	_steps(w, 2)
	assert_true(events.has("touchdown"))
	_assert_return_touchdown(stats, ret)
	m.next_play()
	assert_eq(m.score[1], 6)

func _assert_return_touchdown(stats: Stats, ret: Athlete) -> void:
	var line: Dictionary = stats.athletes.get(ret.id, {})
	assert_eq(line.get("ret_td", 0.0), 1.0)
	assert_eq(line.get("def_td", 0.0), 0.0)
	assert_eq(line.get("pts", 0.0), 6.0)
	assert_true(stats.summary_lines().any(func(s): return s.ends_with("1 ret TD")))

func test_takeaway_touchdown_on_an_unkicked_punt_is_defensive() -> void:
	var m := _match(30.0)
	var w := m.world
	var stats := Stats.new()
	stats.attach(w, func(_aid): return "Ace")
	_fourth_down(m, 30.0)
	m.call_kick("punt")
	w.snap()
	_steps(w, 30)
	var defender := w.returner()
	assert_true(not w.kicked, "the punt hasn't been kicked")
	w.ball.hold(defender.id)
	defender.position = Vector2(20, -0.5)
	_steps(w, 2)
	var line: Dictionary = stats.athletes.get(defender.id, {})
	assert_eq(line.get("ret_td", 0.0), 0.0)
	assert_eq(line.get("def_td", 0.0), 1.0)

func test_fake_punt_plays_normal_downs() -> void:
	var m := _match(30.0)
	var w := m.world
	_fourth_down(m, 30.0)
	m.call_kick("punt")
	w.snap()
	_steps(w, 30)
	var c = w.carrier()
	c.position = Vector2(20, 45)
	var lb := w.find_role(1, R.LB)
	lb.position = c.position + Vector2(0, 0.9)
	lb.facing = Vector2(0, -1)
	w.tackle(lb.id)
	_steps(w, 30)
	var out := m.next_play()
	assert_eq(out["outcome"], "first_down", "fake punt run for a first down")
	assert_eq(w.offense_team, 0)

# --- Field goals + PATs ----------------------------------------------------

func _fg(m, los: float) -> void:
	_fourth_down(m, los)
	m.call_kick("fg")
	_park_all_but(m.world, [m.world.find_role(0, R.C).id, m.world.kicker().id])
	m.world.snap()
	_steps(m.world, 30)

func test_field_goal_good() -> void:
	var m := _match(80.0)
	var w := m.world
	_fg(m, 80.0)
	var k := w.kicker()
	var dist := w.field.posts_y() - k.position.y
	var p := World.kick_power_for("fg", dist + 6.0, T.CROSSBAR_HEIGHT + 2.0, w.gravity())
	assert_true(w.kick(k.id, Vector2(w.field.width / 2.0, w.field.posts_y()), p), "kick")
	_run_until_dead(w)
	assert_true(events.has("field_goal") and ev_data["field_goal"]["good"], "through the uprights")
	var out := m.next_play()
	assert_eq(m.score[0], 3, "+3")
	assert_eq(out["outcome"], "kickoff")
	assert_eq(w.offense_team, 0, "scoring team kicks off")

func test_field_goal_wide() -> void:
	var m := _match(88.0)
	var w := m.world
	_fg(m, 88.0)
	var k := w.kicker()
	w.kick(k.id, Vector2(w.field.width / 2.0 + 8.0, w.field.posts_y()), 0.8)
	_run_until_dead(w)
	assert_true(events.has("field_goal") and not ev_data["field_goal"]["good"], "wide")
	var out := m.next_play()
	assert_eq(m.score[0], 0)
	assert_eq(out["outcome"], "missed_field_goal")
	assert_eq(w.offense_team, 1)
	assert_near(w.los_y, 20.0, 0.01, "kick spot inside the 20 -> defense at its 20")

func test_field_goal_short_ball_at_kick_spot() -> void:
	var m := _match(55.0)
	var w := m.world
	_fg(m, 55.0)
	var k := w.kicker()
	var kick_y: float = k.position.y
	w.kick(k.id, Vector2(w.field.width / 2.0, w.field.posts_y()), 0.2)
	_run_until_dead(w)
	assert_true(events.has("field_goal") and not ev_data["field_goal"]["good"], "short")
	m.next_play()
	assert_eq(w.offense_team, 1)
	assert_near(w.los_y, 100.0 - kick_y, 0.01, "defense takes over at the spot of the kick")

func test_crossbar_too_low() -> void:
	var m := _match(85.0)
	var w := m.world
	_fg(m, 85.0)
	var k := w.kicker()
	# Line drive: barely enough to reach the posts, under the crossbar.
	var dist := w.field.posts_y() - k.position.y
	var p := World.kick_power_for("fg", dist + 0.5, 0.5, w.gravity())
	w.kick(k.id, Vector2(w.field.width / 2.0, w.field.posts_y()), p)
	_run_until_dead(w)
	assert_true(events.has("field_goal") and not ev_data["field_goal"]["good"], "under the bar is no good")

func test_pat_kick_good_and_no_good() -> void:
	for good in [true, false]:
		var m := _match(95.0)
		var w := m.world
		w.snap()
		_steps(w, 30)
		w.carrier().position = Vector2(26, 101)
		_steps(w, 2)
		m.next_play()
		assert_eq(m.state, Match.State.TRY)
		assert_eq(w.kick_play, "fg", "PAT kick is the default try")
		_park_all_but(w, [w.find_role(0, R.C).id, w.kicker().id])
		w.snap()
		_steps(w, 30)
		var k := w.kicker()
		var dist := w.field.posts_y() - k.position.y
		var p := World.kick_power_for("fg", dist + 6.0, T.CROSSBAR_HEIGHT + 2.0, w.gravity())
		w.kick(k.id, Vector2(w.field.width / 2.0 + (0.0 if good else 9.0), w.field.posts_y()), p)
		_run_until_dead(w)
		var out := m.next_play()
		assert_eq(m.score[0], 7 if good else 6, "PAT %s" % ("good" if good else "missed"))
		assert_eq(out["try"], "good" if good else "no_good")
		assert_eq(m.state, Match.State.KICKOFF)

func test_two_point_choice_is_scrimmage() -> void:
	var m := _match(95.0)
	var w := m.world
	w.snap()
	_steps(w, 30)
	w.carrier().position = Vector2(26, 101)
	_steps(w, 2)
	m.next_play()
	assert_true(m.choose_try(2))
	assert_eq(w.kick_play, "", "2-pt try is a scrimmage play")
	assert_true(m.choose_try(1))
	assert_eq(w.kick_play, "fg", "back to the kick")

# --- Blocks -----------------------------------------------------------------

func test_blocked_kick_is_live_scoop_and_score() -> void:
	var m := _match(70.0)
	var w := m.world
	_fourth_down(m, 70.0)
	m.call_kick("fg")
	w.snap()
	_steps(w, 30)
	var k := w.kicker()
	var dl := w.find_role(1, R.DL)
	_park_all_but(w, [k.id, dl.id])
	dl.position = k.position + Vector2(0, 1.5)
	w.kick(k.id, Vector2(w.field.width / 2.0, w.field.posts_y()), 0.8)
	for i in 10:
		w.step({}, DT)
		if events.has("kick_blocked"):
			break
	k.position = Vector2(-1.5, k.position.y)   # kicker out of the scrum
	assert_true(events.has("kick_blocked"), "blocked (%s)" % str(events))
	assert_eq(w.ball.state, w.ball.State.LOOSE, "blocked kick is a live ball")
	# Defender scoops it.
	for i in 120:
		var bp := Vector2(w.ball.position.x, w.ball.position.y)
		dl.position = bp
		w.step({}, DT)
		if w.ball.state == w.ball.State.HELD:
			break
	assert_true(w.ball.is_held_by(dl.id), "defense recovers the block")
	dl.position = Vector2(20, -0.5)
	_steps(w, 2)
	assert_true(events.has("touchdown"), "scoop and score")
	m.next_play()
	assert_eq(m.score[1], 6)

func test_blocked_punt_recovered_by_kicking_team_short_is_turnover_on_downs() -> void:
	var m := _match(30.0)
	var w := m.world
	_fourth_down(m, 30.0)
	m.call_kick("punt")
	w.snap()
	_steps(w, 30)
	var k := w.kicker()
	var dl := w.find_role(1, R.DL)
	_park_all_but(w, [k.id, dl.id])
	dl.position = k.position + Vector2(0, 1.5)
	w.kick(k.id, Vector2(w.field.width / 2.0, 70.0), 0.8)
	_steps(w, 3)
	assert_true(events.has("kick_blocked"))
	dl.position = Vector2(-1.5, dl.position.y)
	for i in 200:
		k.position = Vector2(w.ball.position.x, w.ball.position.y)
		w.step({}, DT)
		if w.ball.state == w.ball.State.HELD:
			break
	assert_true(w.ball.is_held_by(k.id), "punter falls on it")
	var lb := w.find_role(1, R.LB)
	lb.position = k.position + Vector2(0, 0.9)
	lb.facing = Vector2(0, -1)
	w.tackle(lb.id)
	_steps(w, 30)
	var out := m.next_play()
	assert_eq(out["outcome"], "turnover_on_downs")
	assert_eq(w.offense_team, 1)

# --- Bots -------------------------------------------------------------------

func test_fourth_down_call_rule() -> void:
	assert_eq(AI.fourth_down_call(75.0, 100.0, 10.0, 6.0), "fg", "opp 25: FG (42 yd)")
	assert_eq(AI.fourth_down_call(30.0, 100.0, 10.0, 6.0), "punt", "own 30: punt")
	assert_eq(AI.fourth_down_call(55.0, 100.0, 10.0, 1.0), "", "4th & 1 at opp 45: go")
	assert_eq(AI.fourth_down_call(55.0, 100.0, 10.0, 5.0), "punt", "4th & 5 at opp 45: punt")

func test_bot_punts_on_fourth_down() -> void:
	var m := _match(30.0)
	var w := m.world
	_fourth_down(m, 30.0)
	var ai := AI.new()
	for i in 400:
		m.tick(DT)
		ai.presnap_tick(w, [], DT, m.downs.down, m.downs.distance())
		w.step(ai.think(w, []), DT)
		if events.has("kick"):
			break
	assert_eq(w.kick_play, "punt", "bot called a punt")
	assert_true(events.has("kick") and not events.has("throw"), "bot punted (%s)" % str(events))

func test_bot_kicks_field_goal_and_pat() -> void:
	var m := _match(80.0)
	var w := m.world
	_fourth_down(m, 80.0)
	var ai := AI.new()
	ai.defense_enabled = false
	for i in 600:
		m.tick(DT)
		ai.presnap_tick(w, [], DT, m.downs.down, m.downs.distance())
		w.step(ai.think(w, []), DT)
		if w.phase == World.Phase.DEAD:
			break
	assert_true(events.has("field_goal") and ev_data["field_goal"]["good"], "bot FG good (%s)" % str(events))

func test_full_bot_game_with_kicking() -> void:
	var m := Match.new(_world())
	var w := m.world
	m.clock.quarter_length = 75.0   # 5-minute game
	m.start_match(3, false)
	_listen(w)
	var ai := AI.new()
	var ev := {}
	w.event.connect(func(n, _d): ev[n] = ev.get(n, 0) + 1)
	var plays := 0
	var dead_t := 0.0
	var play_t := 0.0
	var longest := 0.0
	var kinds := {}
	m.match_event.connect(func(n, _d): kinds[n] = kinds.get(n, 0) + 1)
	for i in int(600.0 / DT):
		m.tick(DT)
		ai.presnap_tick(w, [], DT, m.downs.down, m.downs.distance())
		w.step(ai.think(w, []), DT)
		if w.phase == World.Phase.LIVE:
			play_t += DT
			longest = maxf(longest, play_t)
		elif w.phase == World.Phase.DEAD:
			dead_t += DT
			if dead_t > 0.5:
				m.next_play()
				plays += 1
				dead_t = 0.0
				play_t = 0.0
				if m.is_final():
					break
	print("    kicking bot game: %d plays, score %s, kicks %d, outcomes %s" % [plays, str(m.score), ev.get("kick", 0), str(kinds)])
	assert_true(m.is_final(), "game finished")
	assert_true(longest < 25.0, "no stuck play (%.1f s)" % longest)
	assert_true(ev.get("kick", 0) >= 3, "kicks happened (%d)" % ev.get("kick", 0))
	assert_true(kinds.get("kickoff", 0) + kinds.get("kickoff_return", 0) + kinds.get("touchback", 0) >= 1, "kickoffs resolved")
	assert_true(m.score[0] + m.score[1] <= 120, "sane score %s" % str(m.score))

# --- Network ----------------------------------------------------------------

func test_protocol_kick_actions() -> void:
	assert_eq(P.sanitize_action({"a": "kick", "t": Vector2(1, 2), "p": 3.0}), {"a": "kick", "t": Vector2(1, 2), "p": 1.0})
	assert_true(P.sanitize_action({"a": "kick", "t": Vector2(INF, 2), "p": 0.5}).is_empty(), "non-finite target dropped")
	assert_eq(P.sanitize_action({"a": "kick_call", "k": "punt"}), {"a": "kick_call", "k": "punt"})
	assert_true(P.sanitize_action({"a": "kick_call", "k": "kickoff"}).is_empty(), "can't call a kickoff")
	assert_eq(P.sanitize_action({"a": "toss", "c": "kick"}), {"a": "toss", "c": "kick"})
	assert_true(P.sanitize_action({"a": "toss", "c": "defer"}).is_empty())
	var m := Match.new(_world())
	m.start_match(0)
	var away := m.world.find_role(1, R.QB)   # away (toss loser, kicking by default) can't choose
	assert_true(not P.apply_action(m, away.id, {"a": "toss", "c": "kick"}))
	var home: Athlete = m.world.athletes[0]   # home is on the return side until it chooses
	assert_eq(home.team, 0)
	assert_true(P.apply_action(m, home.id, {"a": "toss", "c": "kick"}), "home chooses via the wire")
	var qb0 := m.world.find_role(0, R.QB)
	assert_true(P.apply_action(m, qb0.id, {"a": "kick", "t": Vector2(26, 100), "p": 0.8}), "kicker kicks via the wire")
	var b := Match.new(_world())
	b.start(0)
	P.apply_snapshot(b, P.encode_snapshot(m, 1))
	assert_eq(b.world.kick_play, "kickoff", "snapshot carries the kick call")
	assert_true(b.world.kicked)
	assert_eq(b.toss_winner, 0)
	assert_eq(b.state, Match.State.KICKOFF)
