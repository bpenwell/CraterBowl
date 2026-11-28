extends "res://tests/test_case.gd"
## Stumbles (#389): running into a diving or lying opponent costs speed for a moment.
## Rule and numbers: docs/features/movement.md "Stumbles".

const World := preload("res://src/sim/world.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Replay := preload("res://src/sim/replay.gd")
const Match := preload("res://src/sim/match.gd")
const Roster := preload("res://src/sim/roster.gd")
const AI := preload("res://src/sim/ai.gd")
const T := preload("res://src/sim/tuning.gd")
const R := Athlete.Role
const S := Athlete.Stumble
const DT := 1.0 / 60.0
const CX := 26.0
const SPRINT_UP := {0: {"dir": Vector2(0, 1), "sprint": true}}
const RUN_UP := {0: {"dir": Vector2(0, 1)}}

var events: Array = []

## id 0: the carrier (team 0); id 1: a teammate; ids 2-3: opponents. All far apart until placed.
func _world(carrier_at: Vector2) -> World:
	events.clear()
	var w := World.new()
	w.add_athlete(0, R.WR, carrier_at)
	w.add_athlete(0, R.WR, Vector2(CX - 20.0, 10.0))
	w.add_athlete(1, R.CB, Vector2(CX + 20.0, 10.0))
	w.add_athlete(1, R.S, Vector2(CX + 22.0, 10.0))
	w.event.connect(func(n, d): events.append([n, d]))
	w.start_live_with(0)
	return w

## A body on the turf (a missed diver), lying along `facing`.
func _lie(a: Athlete, at: Vector2, facing: Vector2) -> void:
	a.position = at
	a.facing = facing
	a.velocity = Vector2.ZERO
	a.recover_t = T.DIVE_RECOVER

func _stumbles() -> Array:
	return events.filter(func(e): return e[0] == "stumble").map(func(e): return e[1])

func _names() -> Array:
	return events.map(func(e): return e[0])

func _run(w: World, inputs: Dictionary, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		w.step(inputs, DT)

## Step until the first stumble event (false if none within `max_ticks`).
func _until_stumble(w: World, inputs: Dictionary, max_ticks := 90) -> bool:
	for i in max_ticks:
		w.step(inputs, DT)
		if not _stumbles().is_empty():
			return true
	return false

## Ticks (after the stumble tick) until the carrier is back to `full` speed.
func _ticks_to_full(w: World, inputs: Dictionary, full: float) -> int:
	var c := w.get_athlete(0)
	var ticks := 0
	while c.speed() < full - 0.001 and ticks < 120:
		w.step(inputs, DT)
		ticks += 1
	return ticks

func test_tiers_and_speed_curve() -> void:
	assert_eq(World.trip_tier(0.24), S.NONE, "light contact: nothing")
	assert_eq(World.trip_tier(T.BOBBLE_SEVERITY), S.BOBBLE, "bobble from 0.25")
	assert_eq(World.trip_tier(0.59), S.BOBBLE, "bobble below 0.6")
	assert_eq(World.trip_tier(T.STUMBLE_SEVERITY), S.STUMBLE, "stumble from 0.6")
	assert_eq(World.trip_tier(1.4), S.STUMBLE, "TRIP (falls) waits for phase 3 (#391): still a stumble")
	var a := Athlete.new()
	assert_eq(a.stumble_mult(), 1.0, "no stumble: full speed")
	a.trip(S.STUMBLE)
	assert_near(a.stumble_mult(), T.STUMBLE_FLOOR, 0.0001, "starts at the floor")
	a.stumble_t = T.STUMBLE_TIME * 0.5
	assert_near(a.stumble_mult(), lerpf(T.STUMBLE_FLOOR, 1.0, 0.5), 0.0001, "halfway back at half time")
	a.trip(S.BOBBLE)
	assert_near(a.stumble_t, T.BOBBLE_TIME, 0.0001, "bobble length")
	assert_near(a.stumble_mult(), T.BOBBLE_FLOOR, 0.0001, "bobble floor")
	assert_true(not a.stumble_locked(), "a bobble never locks moves")

## Accept 1: a sprint square across a lying opponent is a STUMBLE: <= 0.45 x sprint speed on the
## next tick, full sprint again 0.6 s + 1 tick after the trip. Plant check: drop the multiplier.
func test_sprint_square_over_body_stumbles() -> void:
	var w := _world(Vector2(CX, 48.0))
	var c := w.get_athlete(0)
	_lie(w.get_athlete(2), Vector2(CX, 50.0), Vector2(1, 0))
	assert_true(_until_stumble(w, SPRINT_UP), "tripped over the body")
	var st: Dictionary = _stumbles()[0]
	assert_eq(st["tier"], S.STUMBLE, "square at a sprint: STUMBLE")
	assert_eq(st["id"], 0, "the carrier stumbles")
	assert_eq(st["by"], 2, "over the lying opponent")
	w.step(SPRINT_UP, DT)
	assert_true(c.speed() <= T.STUMBLE_FLOOR * T.SPRINT_SPEED + 0.001, "next tick at most 0.45 x sprint (%.2f)" % c.speed())
	assert_true(not c.last_sprinting, "no sprint while stumbling")
	var ticks := 1 + _ticks_to_full(w, SPRINT_UP, T.SPRINT_SPEED)
	var budget := roundi(T.STUMBLE_TIME / DT) + 1
	assert_true(ticks <= budget, "full sprint within 0.6 s + 1 tick (%d ticks)" % ticks)
	assert_true(ticks >= budget - 1, "not before the stumble runs out (%d ticks)" % ticks)
	assert_eq(_stumbles().size(), 1, "one stumble")
	assert_eq(w.phase, World.Phase.LIVE, "a stumble never ends the play")

## Accept 2: running along a lying body at run speed is only a BOBBLE (x0.75 for 0.25 s).
func test_run_along_body_bobbles() -> void:
	var w := _world(Vector2(CX, 48.0))
	var c := w.get_athlete(0)
	_lie(w.get_athlete(2), Vector2(CX, 50.0), Vector2(0, 1))
	assert_true(_until_stumble(w, RUN_UP), "clipped the body")
	assert_eq(_stumbles()[0]["tier"], S.BOBBLE, "along the body at run speed: BOBBLE")
	w.step(RUN_UP, DT)
	assert_near(c.speed(), T.BOBBLE_FLOOR * T.RUN_SPEED, 0.01, "next tick at 0.75 x run")
	var ticks := 1 + _ticks_to_full(w, RUN_UP, T.RUN_SPEED)
	assert_true(ticks <= roundi(T.BOBBLE_TIME / DT) + 1, "full speed within 0.25 s + 1 tick (%d)" % ticks)

## Accept 3: slower than 4 yd/s, spinning, jumping, or a teammate's body: no stumble.
func test_no_stumble_slow_spin_jump_or_teammate() -> void:
	var w := _world(Vector2(CX, 48.0))
	_lie(w.get_athlete(2), Vector2(CX, 50.0), Vector2(1, 0))
	_run(w, {0: {"dir": Vector2(0, 0.55)}}, 1.0)   # 3.85 yd/s: walking around the pile
	assert_true(w.get_athlete(0).position.y > 50.5, "walked over the body")
	assert_eq(_stumbles().size(), 0, "below TRIP_MIN_SPEED: no stumble")

	w = _world(Vector2(CX, 49.0))
	_lie(w.get_athlete(2), Vector2(CX, 50.0), Vector2(1, 0))
	w.step(RUN_UP, DT)
	assert_true(w.spin(0, 1) or w.evade(0, true, Vector2(0, 1)), "spin starts")
	_run(w, RUN_UP, T.SPIN_TIME + 0.05)
	assert_true(w.get_athlete(0).position.y > 50.75, "spun past the body")
	assert_eq(_stumbles().size(), 0, "spinning: immune")

	w = _world(Vector2(CX, 48.5))
	_lie(w.get_athlete(2), Vector2(CX, 50.0), Vector2(1, 0))
	w.step(SPRINT_UP, DT)
	assert_true(w.jump(0), "jump")
	_run(w, SPRINT_UP, T.JUMP_TIME - 0.05)
	assert_true(w.get_athlete(0).position.y > 50.75, "hurdled the body")
	assert_eq(_stumbles().size(), 0, "airborne: immune")

	w = _world(Vector2(CX, 48.0))
	_lie(w.get_athlete(1), Vector2(CX, 50.0), Vector2(1, 0))
	_run(w, SPRINT_UP, 0.5)
	assert_eq(_stumbles().size(), 0, "a teammate's body: no stumble (opponents only)")

## Accept 4: a dive that misses the carrier by a hair (d = 1.2) clips his ankles; at d = 0.9
## it's a tackle (or a strip), never a stumble.
func test_ankle_tap_and_tackle_reach() -> void:
	var w := _world(Vector2(CX, 48.0))
	var d := w.get_athlete(2)
	d.position = Vector2(CX + 1.2, 48.0)
	d.facing = Vector2(0, 1)
	assert_true(d.start_dive(), "diver in the air")
	w.step(SPRINT_UP, DT)
	assert_eq(_stumbles().size(), 1, "ankle tap")
	assert_eq(_stumbles()[0]["tier"], S.BOBBLE, "glancing at a fresh sprint: BOBBLE")
	assert_eq(_stumbles()[0]["by"], 2, "by the diver")
	assert_eq(w.phase, World.Phase.LIVE, "the play goes on")

	w = _world(Vector2(CX, 48.0))
	d = w.get_athlete(2)
	d.position = Vector2(CX + 0.9, 48.0)
	d.facing = Vector2(0, 1)
	assert_true(d.start_dive(), "diver in the air")
	w.step(SPRINT_UP, DT)
	assert_true(_names().has("tackle") or _names().has("fumble"), "in reach: a tackle (%s)" % str(_names()))
	assert_eq(_stumbles().size(), 0, "never a stumble in tackle reach")

## Accept 5: one stumble per pile. Two bodies hit in the same tick give one event at the worst
## tier; a second body within the 0.5 s immunity is ignored.
func test_two_bodies_one_stumble() -> void:
	var w := _world(Vector2(CX, 48.0))
	_lie(w.get_athlete(2), Vector2(CX - 0.3, 50.0), Vector2(0, 1))   # along: bobble alone
	_lie(w.get_athlete(3), Vector2(CX + 0.3, 50.0), Vector2(1, 0))   # square: stumble
	assert_true(_until_stumble(w, SPRINT_UP), "tripped")
	_run(w, SPRINT_UP, 0.8)
	assert_eq(_stumbles().size(), 1, "same tick: one event")
	assert_eq(_stumbles()[0]["tier"], S.STUMBLE, "the worst contact wins")
	assert_eq(_stumbles()[0]["by"], 3, "by the square body")

	w = _world(Vector2(CX, 48.0))
	_lie(w.get_athlete(2), Vector2(CX, 50.0), Vector2(1, 0))
	_lie(w.get_athlete(3), Vector2(CX, 50.4), Vector2(1, 0))
	_run(w, SPRINT_UP, 0.8)
	assert_true(w.get_athlete(0).position.y > 51.2, "crossed both")
	assert_eq(_stumbles().size(), 1, "two bodies within 0.5 s: one stumble")

## A bobble-grade contact in the last moments of a stumble (immunity over) never downgrades it.
func test_lighter_contact_never_downgrades_a_stumble() -> void:
	var w := _world(Vector2(CX, 49.0))
	var c := w.get_athlete(0)
	_lie(w.get_athlete(2), Vector2(CX, 50.0), Vector2(0, 1))   # along: a bobble on its own
	c.trip(S.STUMBLE)
	c.stumble_t = 0.1
	c.trip_immune_t = 0.0
	_run(w, RUN_UP, 4 * DT)
	assert_true(w.get_athlete(0).position.distance_to(Vector2(CX - 0.0, 50.0)) <= T.TRIP_REACH, "on the body while still stumbling")
	assert_eq(_stumbles().size(), 0, "no bobble event over a stumble")
	assert_eq(c.stumble_tier, S.STUMBLE, "still a stumble (no sprint)")
	_run(w, RUN_UP, 0.2)
	assert_true(c.stumble_tier != S.STUMBLE, "the stumble runs out on time")
	assert_true(_stumbles().size() <= 1, "a fresh bobble may follow once it's over")

## Accept 6: a STUMBLE cancels a dash and locks spin/dash/dive/jump for STUMBLE_LOCK.
func test_stumble_cancels_dash_and_locks_moves() -> void:
	var w := _world(Vector2(CX, 48.4))
	var c := w.get_athlete(0)
	_lie(w.get_athlete(2), Vector2(CX, 50.0), Vector2(1, 0))
	w.step(RUN_UP, DT)
	assert_true(w.evade(0, false, Vector2(0, 1)), "dash")
	assert_true(_until_stumble(w, RUN_UP, 20), "dashed into the body")
	assert_eq(_stumbles()[0]["tier"], S.STUMBLE, "dash speed: STUMBLE (a TRIP after #391)")
	assert_eq(c.move_t, 0.0, "the dash is cancelled")
	w.step(RUN_UP, DT)
	assert_true(c.speed() <= T.STUMBLE_FLOOR * T.RUN_SPEED + 0.001, "slowed, not dashing (%.2f)" % c.speed())
	assert_true(not w.spin(0, 1), "no spin in the lock")
	assert_true(not w.evade(0, false, Vector2(0, 1)), "no dash in the lock")
	assert_true(not w.jump(0), "no jump in the lock")
	assert_true(not w.tackle(0), "no dive in the lock")
	var lock_ticks := roundi(T.STUMBLE_LOCK / DT)
	_run(w, RUN_UP, (lock_ticks - 2) * DT)   # 1 tick in already
	assert_true(c.stumble_locked(), "still locked just before 0.2 s")
	_run(w, RUN_UP, 2 * DT)
	assert_true(not c.stumble_locked(), "unlocked after 0.2 s")
	assert_true(w.jump(0), "moves are back")

## A stumble starts from the tick it's decided: the trip state and its countdown are on the
## athlete, recorded in replay frames (Accept 9's sim half; the pose is tests/visual/stumble_test.gd).
func test_replay_frames_carry_the_stumble() -> void:
	var w := _world(Vector2(CX, 48.0))
	_lie(w.get_athlete(2), Vector2(CX, 50.0), Vector2(1, 0))
	var rec := Replay.new()
	var seen := {}
	for i in 60:
		w.step(SPRINT_UP, DT)
		rec.capture(w)
	for f in rec.frames:
		var st := Replay.stumble_of(int(f[Replay.HEADER + 2]))
		if st[0] != S.NONE:
			seen[roundi(st[1] * 60.0)] = st[0]
	assert_true(not seen.is_empty(), "stumble frames recorded")
	for k in seen:
		assert_eq(seen[k], S.STUMBLE, "tier in the frame")
	assert_true(seen.keys().max() >= roundi(T.STUMBLE_TIME / DT) - 2, "starts near the full length (%d)" % seen.keys().max())
	assert_eq(Replay.stumble_of(Replay.stumble_bits(S.BOBBLE, 0.1)), [S.BOBBLE, 6.0 / 60.0], "bits round-trip")
	assert_eq(Replay.stumble_of(Replay.F_PUSH | Replay.F_DIVING), [S.NONE, 0.0], "other bits are not a stumble")

## Bots dive a lot, so a bot game must hit the rule (else the determinism test never covers it).
func test_bot_game_has_stumbles() -> void:
	var w := World.new()
	Roster.new().build(w, 7)
	var m := Match.new(w)
	m.start(0, 25.0)
	var ai := AI.new()
	var n := [0]
	w.event.connect(func(name, _d): if name == "stumble": n[0] += 1)
	var dead_t := 0.0
	for i in 60 * 60:
		m.tick(DT)
		ai.presnap_tick(w, [], DT, m.downs.down, m.downs.distance())
		w.step(ai.think(w, []), DT)
		if w.phase == World.Phase.DEAD:
			dead_t += DT
			if dead_t > 0.5:
				m.next_play()
				dead_t = 0.0
	assert_true(n[0] > 0, "bots stumble in a minute of play (%d)" % n[0])
