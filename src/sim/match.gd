extends RefCounted
## Match flow layer: World (one play) + Downs (series) + score. Clock comes in A09.

const World := preload("res://src/sim/world.gd")
const Downs := preload("res://src/sim/downs.gd")
const Clock := preload("res://src/sim/clock.gd")
const Penalties := preload("res://src/sim/penalties.gd")

const T := preload("res://src/sim/tuning.gd")

const TD_POINTS := 6
const SAFETY_POINTS := 2
const FG_POINTS := 3
const TRY_DIST := {1: 15.0, 2: 10.0}  # 1 pt = PAT kick snapped from the 15, 2 pts = scrimmage from the 10
const KICKOFF_FRACTION := 0.25        # kickoff touchback: receive at 25% of the field (own 25 on 100 yd)
const KICKOFF_SPOT_FRACTION := 0.35   # kick off from your own 35
const SAFETY_KICK_FRACTION := 0.2     # free kick after a safety: from your own 20
const PUNT_TOUCHBACK_FRACTION := 0.2  # punt touchback / missed FG minimum: own 20
const KICKOFF_OOB_FRACTION := 0.4     # kickoff out of bounds: receive at own 40
const TOSS_REVEAL := 3.0              # #129: the coin is in the air this long (the cutscene's flip); then the result shows
const TOSS_WINDOW := 5.0              # seconds the toss winner has, from the reveal, to choose before receive is assumed
const TOSS_BOT_PICK := 1.2            # #129: a bot winner "thinks" this long after the reveal, then receives
const TOSS_OUTRO := 0.9               # #129: after the pick the cutscene shows it and fades back; the play clock waits

enum State { SCRIMMAGE, TRY, KICKOFF, TOSS }

signal match_event(name: String, data: Dictionary)

var world: World
var downs := Downs.new()
var clock := Clock.new()
var opening_receiver := 0
var score := [0, 0]
var max_deficit := [0, 0]   # worst trailing margin each team faced
var state: State = State.SCRIMMAGE
var try_points := 1
var last_result := {}
var last_outcome := {}
var _possession_changed := false
var toss_winner := -1
var toss_choice := ""    # "receive" / "kick" once decided
var _kick_fraction := KICKOFF_SPOT_FRACTION
var _toss_t := 0.0
var _toss_bot := false   # the toss winner has no humans: it picks receive TOSS_BOT_PICK after the reveal
var _toss_hold := 0.0    # seconds the kickoff's play clock still waits for the cutscene's outro

func _init(w: World) -> void:
	world = w
	downs.goal = w.field.length
	world.event.connect(_on_world_event)

func goal() -> float:
	return world.field.length

func try_los(points: int) -> float:
	return goal() - TRY_DIST[points]

func kickoff_los() -> float:
	return roundf(goal() * KICKOFF_FRACTION)

func start(offense: int = 0, los: float = -1.0) -> void:
	downs.goal = goal()
	if los < 0.0:
		los = kickoff_los()
	state = State.SCRIMMAGE
	opening_receiver = offense
	_toss_hold = 0.0
	clock.timeout_limit = Clock.SMALL_MATCH_TIMEOUTS if world.athletes.size() == 6 else Clock.TIMEOUTS_PER_HALF
	clock.reset()
	world.last_offensive_calls = ["", ""]
	world.last_defensive_calls = ["", ""]
	downs.reset(offense, los)
	world.set_offense(offense)
	_setup_formation()

## Coin toss (B09/C02): deterministic from `seed`. The coin is in the air for TOSS_REVEAL
## seconds (the #129 cutscene), then the winner has TOSS_WINDOW seconds to choose kick or
## receive (choose_toss); no answer = receive. A bot winner receives TOSS_BOT_PICK after
## the reveal. The play clock is held for the whole toss (tick), so the cutscene never eats it.
func start_match(seed: int, winner_has_humans: bool = true) -> void:
	start(0)
	toss_winner = posmod(seed, 2)
	toss_choice = ""
	_toss_t = 0.0
	_toss_bot = not winner_has_humans
	opening_receiver = toss_winner
	_kickoff(toss_winner)
	state = State.TOSS
	world.set_offense(downs.offense_team)
	_setup_formation()
	match_event.emit("toss", {"winner": toss_winner})

## Seconds since the toss started (host / offline; clients don't run the toss timer).
func toss_elapsed() -> float:
	return _toss_t

func choose_toss(team: int, choice: String) -> bool:
	if state != State.TOSS or team != toss_winner or not choice in ["receive", "kick"] or world.phase != World.Phase.PRESNAP:
		return false
	toss_choice = choice
	_toss_hold = TOSS_OUTRO
	opening_receiver = toss_winner if choice == "receive" else 1 - toss_winner
	_kickoff(opening_receiver)
	if downs.offense_team != world.offense_team:
		world.set_offense(downs.offense_team)
	_setup_formation()
	match_event.emit("toss_choice", {"team": team, "choice": choice, "receiving": opening_receiver})
	return true

func kickoff_spot() -> float:
	return roundf(goal() * _kick_fraction)

func _setup_formation() -> void:
	if state == State.KICKOFF or state == State.TOSS:
		world.setup_kickoff(downs.los)
		world.kick_locked = state == State.TOSS
		return
	world.setup_formation(downs.los)
	if not world.is_chaos():
		if downs.distance() <= 3.0:
			world.call_play("Slants")
		elif downs.distance() >= 15.0 and goal() - downs.los >= 25.0:
			world.call_play("Deep Shot")
		else:
			world.call_play("Mesh")
	if state == State.TRY and try_points == 1:
		world.call_kick("fg")
	world.call_defense(World.DefensivePlaybook.suggest(downs.down, downs.distance(),
		goal() - downs.los, clock.half_remaining()))

func _on_world_event(n: String, d: Dictionary) -> void:
	match n:
		"snap":
			_possession_changed = false
			clock.running_between_plays = false
		"interception":
			_possession_changed = true
		"recovery":
			_possession_changed = _possession_changed or d.get("turnover", false)
		"tackle", "out_of_bounds":
			var spot: float = d["spot"].y
			var team: int = d.get("team", world.offense_team)
			last_result = {"type": n, "spot": spot, "team": team}
			clock.running_between_plays = n == "tackle" and _clock_runs_after_tackle(spot, team)
		"incomplete":
			clock.running_between_plays = false
			last_result = {"type": "incomplete", "team": d.get("team", world.offense_team),
				"spot": (d.get("at", Vector2(0, downs.los)) as Vector2).y}
		"touchdown":
			clock.running_between_plays = false
			last_result = {"type": "touchdown", "team": d.get("team", world.offense_team), "points": d.get("points", TD_POINTS)}
		"explode":
			clock.running_between_plays = false
			last_result = {"type": "explode", "spot": d["spot"].y, "team": d.get("team", world.offense_team)}
		"field_goal":
			last_result = {"type": "field_goal", "good": d["good"], "team": world.offense_team}
		"touchback", "kick_out_of_bounds", "kick_downed", "fair_catch":
			last_result = {"type": n, "spot": d["spot"].y, "team": world.offense_team}

func _clock_runs_after_tackle(spot: float, team: int) -> bool:
	return state == State.SCRIMMAGE and not world.is_chaos() and not clock.expired() \
		and not _possession_changed and team == downs.offense_team \
		and spot >= 0.0 and spot < downs.first_down_y and downs.down < 4

func call_timeout(team: int) -> bool:
	if world.phase == World.Phase.LIVE or not clock.spend_timeout(team):
		return false
	if world.phase == World.Phase.PRESNAP:
		clock.new_play()
	match_event.emit("timeout", {"team": team, "remaining": clock.timeouts[team]})
	return true

## During try presnap: choose 1 (from the 3) or 2 (from the 10).
func choose_try(points: int) -> bool:
	if state != State.TRY or world.phase != World.Phase.PRESNAP or not TRY_DIST.has(points):
		return false
	try_points = points
	downs.los = try_los(points)
	_setup_formation()
	return true

func _award(team: int, pts: int, why: String) -> void:
	score[team] += pts
	for t in 2:
		max_deficit[t] = maxi(max_deficit[t], score[1 - t] - score[t])
	match_event.emit("score", {"team": team, "points": pts, "why": why, "score": score.duplicate()})

## Next play is a kickoff to `receiving` (a live play). Chaosball skips kicks:
## the receiving team just gets the ball at its own 25.
func _kickoff(receiving: int, fraction: float = KICKOFF_SPOT_FRACTION) -> Dictionary:
	if world.is_chaos():
		state = State.SCRIMMAGE
		downs.reset(receiving, kickoff_los())
		return {"outcome": "kickoff", "los": downs.los, "offense": receiving}
	state = State.KICKOFF
	_kick_fraction = fraction
	downs.reset(1 - receiving, kickoff_spot())
	return {"outcome": "kickoff", "los": downs.los, "offense": 1 - receiving, "receiving": receiving}

## Presnap kick call by the offense on a scrimmage down ("", "punt", "fg").
func call_kick(kind: String) -> bool:
	if state != State.SCRIMMAGE:
		return false
	return world.call_kick(kind)

## Resolve a play in which the ball was kicked and not run back for a score.
## Returns {} when the normal rules apply (returns, blocked kicks, fumbles).
func _kick_next(r: Dictionary, off: int) -> Dictionary:
	var def := 1 - off
	var kind := world.kick_play
	match r["type"]:
		"field_goal":
			if r["good"]:
				_award(off, FG_POINTS, "field_goal")
				var out := _kickoff(def)
				out["field_goal"] = "good"
				return out
			# Miss: defense takes over at the spot of the kick, or its own 20.
			var at := maxf(goal() - world.kick_spot.y, roundf(goal() * PUNT_TOUCHBACK_FRACTION))
			downs.reset(def, clampf(at, 1.0, goal() - 1.0))
			return {"outcome": "missed_field_goal", "los": downs.los, "offense": def}
		"touchback":
			var tb := kickoff_los() if kind == "kickoff" else roundf(goal() * PUNT_TOUCHBACK_FRACTION)
			downs.reset(def, tb)
			return {"outcome": "touchback", "los": downs.los, "offense": def}
		"fair_catch":
			# Ball at the catch; a kickoff fair-caught short of the 25 comes out to the 25 (#189).
			var at := goal() - float(r["spot"])
			if kind == "kickoff":
				at = maxf(at, kickoff_los())
			downs.reset(def, clampf(at, 1.0, goal() - 1.0))
			return {"outcome": "fair_catch", "los": downs.los, "offense": def}
		"kick_out_of_bounds", "kick_downed":
			var at := goal() - float(r["spot"])
			if r["type"] == "kick_out_of_bounds" and kind == "kickoff":
				at = roundf(goal() * KICKOFF_OOB_FRACTION)
			downs.reset(def, clampf(at, 1.0, goal() - 1.0))
			return {"outcome": "punt" if kind == "punt" else ("kickoff_return" if kind == "kickoff" else r["type"]), "los": downs.los, "offense": def}
	if r.get("team", off) == def and r["type"] in ["tackle", "out_of_bounds"]:
		# Return team downed: ball at the spot (own end zone = touchback).
		var spot := goal() - float(r["spot"])
		if spot <= 0.0:
			spot = kickoff_los() if kind == "kickoff" else roundf(goal() * PUNT_TOUCHBACK_FRACTION)
		downs.reset(def, clampf(spot, 1.0, goal() - 1.0))
		return {"outcome": "kickoff_return" if kind == "kickoff" else "punt_return", "los": downs.los, "offense": def}
	return {}

## Advance clocks; auto-snap when the play clock expires. `snapper` (-> bool) replaces
## world.snap() for that snap, so a bot offense snaps its own way on the shown clock (#136).
func tick(dt: float, snapper := Callable()) -> void:
	if state == State.TOSS:
		_toss_t += dt
		if _toss_t >= TOSS_REVEAL + (TOSS_BOT_PICK if _toss_bot else TOSS_WINDOW):
			choose_toss(toss_winner, "receive")
	var live := world.phase == World.Phase.LIVE
	# The toss runs on TOSS_WINDOW, not the play clock, so the kickoff gets all 20 s (#136),
	# and that clock starts only once the cutscene has faded back to the field (#129).
	var held := _toss_hold > 0.0
	_toss_hold = maxf(0.0, _toss_hold - dt)
	var presnap := world.phase == World.Phase.PRESNAP and state != State.TOSS and not held
	var was_running := clock.running_between_plays
	var snap_now := clock.tick(dt, live and state != State.TRY, presnap)
	if not live and clock.take_warning():
		if presnap:
			clock.new_play()
		match_event.emit("clock_warning", {"half": clock.half})
		return
	if presnap and was_running and clock.expired():
		if not _advance_expired_period():
			_line_up_next_play()
		return
	if snap_now and (bool(snapper.call()) if snapper.is_valid() else world.snap()):
		match_event.emit("auto_snap", {})

## #136: the play clock is the one countdown to the next snap. A bot-run offense huddles
## `seconds` and then snaps when this clock hits 0, so what the HUD shows is when the
## ball goes. Call every presnap tick while the offense is bot-run (idempotent).
func huddle(seconds: float) -> void:
	if world.phase == World.Phase.PRESNAP and state != State.TOSS and not clock.final:
		clock.play_clock = minf(clock.play_clock, seconds)

## Whole seconds the HUD shows on the play clock, or -1 while it governs no snap (live
## or dead ball, coin toss, FINAL). Only synced state goes in, so host and clients agree.
## The 1 ms slack keeps the float32 snapshot copy from landing on the other second.
func play_clock_shown() -> int:
	if clock.final or world.phase != World.Phase.PRESNAP or state == State.TOSS:
		return -1
	return int(ceil(maxf(0.0, clock.play_clock - 0.001)))

## C04c (#89): teams switch the goal they attack every period (each quarter, or at
## halftime). End 0 is the HELIOS-painted end, which team 0
## defends in the first period. Derived from the synced clock, so clients agree.
func ends_switched() -> bool:
	return clock.period() % 2 == 1

## The end (0 = HELIOS paint, 1 = NEBULA paint) `team` defends this period.
func defended_end(team: int) -> int:
	return team ^ (1 if ends_switched() else 0)

func is_final() -> bool:
	return clock.final

func winner() -> int:
	if score[0] == score[1]:
		return -1
	return 0 if score[0] > score[1] else 1

## Chaosball: one live play per possession. TD scores; anything else hands the
## ball to the team that didn't end the play with it, at the spot.
func _chaos_next(r: Dictionary, holder_team: int, off: int) -> Dictionary:
	if r["type"] == "touchdown":
		_award(holder_team, int(r.get("points", TD_POINTS)), "touchdown")
		return _kickoff(1 - holder_team)
	var new_off := 1 - holder_team
	var spot: float = r.get("spot", downs.los)
	var los := spot if new_off == off else goal() - spot
	downs.reset(new_off, clampf(los, 1.0, goal() - 1.0))
	return {"outcome": "turnover", "los": downs.los, "offense": new_off}

## Apply the last play's result and line up for the next snap.
func next_play() -> Dictionary:
	if clock.final:
		return {"outcome": "final"}
	if last_result.is_empty():
		last_result = {"type": "incomplete"}
	var r := last_result
	last_result = {}
	var off := downs.offense_team
	var def := 1 - off
	var r_team: int = r.get("team", off)
	# #253: a flag from this down. The defense keeps a better result, else it is enforced.
	var flag: Dictionary = {} if world.flags.is_empty() or world.is_chaos() else world.flags[0]
	world.flags = []
	var enforce_flag := not flag.is_empty() and not Penalties.defense_declines(r, downs, state == State.TRY, flag)
	if not flag.is_empty() and not enforce_flag:
		match_event.emit("penalty", {"penalty": flag, "declined": true, "ruling": Penalties.ruling(flag, {"declined": true})})
	var kick_out := {}
	if not enforce_flag and world.kicked and not world.is_chaos() and state != State.TRY and r["type"] != "touchdown":
		kick_out = _kick_next(r, off)
	if enforce_flag:
		last_outcome = _enforce_penalty(flag)
	elif world.is_chaos():
		last_outcome = _chaos_next(r, r_team, off)
	elif state == State.TRY:
		if (r["type"] == "touchdown" and r_team == off) or (r["type"] == "field_goal" and r["good"]):
			_award(off, try_points, "try")
			last_outcome = _kickoff(def)
			last_outcome["try"] = "good"
		else:
			last_outcome = _kickoff(def)
			last_outcome["try"] = "no_good"
	elif not kick_out.is_empty():
		last_outcome = kick_out
	elif r["type"] == "touchdown":
		var why := "touchdown" if r_team == off else ("return_touchdown" if world.kicked else "defensive_touchdown")
		_award(r_team, TD_POINTS, why)
		downs.offense_team = r_team   # the scoring team attempts the try
		state = State.TRY
		try_points = 1
		downs.down = 1
		downs.los = try_los(1)
		downs.first_down_y = goal()
		last_outcome = {"outcome": "try", "los": downs.los}
	elif r["type"] != "incomplete" and r_team != off:
		# Takeaway: new offense from the mirrored spot; downed in own end zone -> touchback.
		var spot := goal() - float(r["spot"])
		if spot <= 0.0:
			spot = kickoff_los()
		downs.reset(r_team, clampf(spot, 1.0, goal() - 1.0))
		last_outcome = {"outcome": "turnover", "los": downs.los, "offense": r_team}
	elif r["type"] != "incomplete" and r.get("spot", 1.0) < 0.0:
		_award(def, SAFETY_POINTS, "safety")
		last_outcome = _kickoff(def, SAFETY_KICK_FRACTION)
		last_outcome["safety"] = true
	else:
		if state == State.KICKOFF:
			state = State.SCRIMMAGE   # onside recovery: kicking team keeps it
		last_outcome = downs.apply(r)
	if state == State.KICKOFF and last_outcome.get("outcome", "") != "kickoff":
		state = State.SCRIMMAGE
	# The period ends once the clock is out and no try is pending.
	if clock.expired() and state != State.TRY and _advance_expired_period():
		return last_outcome
	_line_up_next_play()
	return last_outcome

## #253: walk off an accepted flag (Penalties.enforce is the one path) and tell the HUD.
func _enforce_penalty(flag: Dictionary) -> Dictionary:
	var res := Penalties.enforce(downs, flag)
	res["try"] = state == State.TRY
	clock.running_between_plays = false
	var ruling := Penalties.ruling(flag, res)
	match_event.emit("penalty", {"penalty": flag, "declined": false, "result": res, "ruling": ruling})
	var outcome := "replay_down"
	if res["turnover_on_downs"]:
		outcome = "turnover_on_downs"
	elif flag.get("loss_of_down", false) and state != State.TRY:
		outcome = "next_down"
	return {"outcome": outcome, "los": downs.los, "down": downs.down, "offense": downs.offense_team,
		"penalty": flag, "ruling": ruling}

## Returns true when there is no next play.
func _advance_expired_period() -> bool:
	if clock.advance_midhalf_quarter():
		last_outcome = {"outcome": "quarter", "quarter": clock.quarter, "los": downs.los, "offense": downs.offense_team, "switch_ends": true}
		return false
	if clock.half < Clock.HALVES:
		clock.start_next_half()
		last_outcome = _kickoff(1 - opening_receiver)
		last_outcome["outcome"] = "halftime"
		last_outcome["switch_ends"] = true
		return false
	clock.final = true
	clock.running_between_plays = false
	world.phase = World.Phase.DEAD
	last_outcome = {"outcome": "final", "score": score.duplicate(), "winner": winner()}
	match_event.emit("final", last_outcome)
	return true

func _line_up_next_play() -> void:
	clock.new_play()
	if downs.offense_team != world.offense_team:
		world.set_offense(downs.offense_team)
	_setup_formation()
	match_event.emit(last_outcome["outcome"], last_outcome)
