extends "res://tests/test_case.gd"
## Jump (#379): Space / A in live play. A committed hop with a chained-jump stamina cost
## that raises the pass catch ceiling while airborne.

const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Ball := preload("res://src/sim/ball.gd")
const P := preload("res://src/net/protocol.gd")
const T := preload("res://src/sim/tuning.gd")
const DT := 1.0 / 60.0

func _match() -> Match:
	var w := World.new()
	var cx := w.field.width / 2.0
	for t in 2:
		w.add_two_way(t, Athlete.Role.QB, cx, Athlete.Role.LB, cx)
		w.add_two_way(t, Athlete.Role.C, cx, Athlete.Role.DL, cx)
		w.add_two_way(t, Athlete.Role.WR, cx + 12.0, Athlete.Role.CB, cx + 12.0)
	var m := Match.new(w)
	m.start(0, 25.0)
	return m

func _live() -> World:
	var w := _match().world
	w.snap()
	_run(w, {}, 0.5)
	return w

func _run(w, inputs: Dictionary, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		w.step(inputs, DT)

func _wr(w) -> Athlete:
	return w.find_role(0, Athlete.Role.WR)

func test_jump_arc_and_committed_velocity() -> void:
	var w := _live()
	var wr := _wr(w)
	w.find_role(1, Athlete.Role.CB).position.x = 3.0   # out of the way: no collision pushes
	var up := {wr.id: {"dir": Vector2(0, 1)}}
	_run(w, up, 0.3)
	var v0 := wr.velocity
	assert_true(w.jump(wr.id), "jump starts in live play")
	assert_true(wr.is_jumping(), "airborne")
	var left := {wr.id: {"dir": Vector2(-1, 0)}}   # steering is ignored in the air
	var peak := 0.0
	var p0 := wr.position
	var steps := int(round(T.JUMP_TIME / DT)) - 1
	for i in int(round(T.JUMP_TIME / DT)) - 1:
		w.step(left, DT)
		peak = maxf(peak, wr.jump_height())
		assert_true(wr.is_jumping(), "still airborne at step %d" % i)
	assert_true(absf(peak - T.JUMP_HEIGHT) < 0.02, "peaks at JUMP_HEIGHT (%.3f)" % peak)
	assert_eq(wr.velocity, v0, "takeoff velocity kept, no steering")
	assert_true(v0.length() > 1.0, "was running at takeoff")
	assert_true(wr.position.distance_to(p0 + v0 * steps * DT) < 0.01, "carried along the takeoff velocity")
	w.step(left, DT)
	assert_true(not wr.is_jumping(), "lands after JUMP_TIME")
	assert_eq(wr.jump_height(), 0.0, "feet on the ground")
	w.step(left, DT)
	assert_true(wr.velocity.x < 0.0, "steers again right after landing")

func test_jump_refused_when_busy() -> void:
	var m := _match()
	var w := m.world
	var wr := _wr(w)
	assert_true(not w.jump(wr.id), "no jump before the snap")
	w.snap()
	_run(w, {}, 0.5)
	assert_true(w.jump(wr.id), "first jump")
	assert_true(not w.jump(wr.id), "no jump while airborne")
	assert_true(not w.tackle(wr.id), "no dive while airborne")
	assert_true(not w.evade(wr.id, false, Vector2(0, 1)), "no dash while airborne")
	_run(w, {}, T.JUMP_TIME + T.JUMP_CHAIN_WINDOW + 0.1)
	assert_true(w.tackle(wr.id), "dive")
	assert_true(not w.jump(wr.id), "no jump while diving")
	_run(w, {}, T.DIVE_TIME + 0.05)
	assert_true(wr.is_grounded() and not w.jump(wr.id), "no jump while grounded")
	_run(w, {}, T.DIVE_RECOVER + 0.05)
	assert_true(w.evade(wr.id, false, Vector2(0, 1)) and not w.jump(wr.id), "no jump mid-dash")
	_run(w, {}, T.DASH_TIME + 0.05)
	wr.engaged_with = 99
	assert_true(not w.jump(wr.id), "no jump while engaged in a block")
	wr.engaged_with = -1
	assert_true(w.jump(wr.id), "jump once free")

func test_chained_jumps_drain_stamina() -> void:
	var w := _live()
	var wr := _wr(w)
	wr.stamina = 1.0
	assert_true(w.jump(wr.id), "jump")
	assert_true(absf(wr.stamina - (1.0 - T.JUMP_STAMINA)) < 1e-5, "a single jump costs JUMP_STAMINA")
	_run(w, {}, T.JUMP_TIME + DT)
	assert_true(not wr.is_jumping(), "landed")
	var s := wr.stamina
	assert_true(w.jump(wr.id), "chained jump")
	assert_true(absf(wr.stamina - (s - T.JUMP_CHAIN_STAMINA)) < 1e-5, "a chained jump costs JUMP_CHAIN_STAMINA")
	_run(w, {}, T.JUMP_TIME + T.JUMP_CHAIN_WINDOW + DT)
	s = wr.stamina
	assert_true(w.jump(wr.id), "jump after the window")
	assert_true(absf(wr.stamina - (s - T.JUMP_STAMINA)) < 1e-5, "back to JUMP_STAMINA after the window")
	_run(w, {}, T.JUMP_TIME + DT)
	wr.stamina = T.JUMP_CHAIN_STAMINA - 0.01
	assert_true(not w.jump(wr.id), "too tired for a chained jump")
	assert_true(not wr.is_jumping(), "nothing happens")

func _ball_over(w, wr: Athlete, z: float) -> void:
	var qb: Athlete = w.find_role(0, Athlete.Role.QB)
	w.ball.state = Ball.State.IN_FLIGHT
	w.ball.holder_id = -1
	w.ball.position = Vector3(wr.position.x, wr.position.y, z)
	w.ball.velocity = Vector3(0, 0, -1)
	w.forward_pass_thrown = true
	w.last_thrower_id = qb.id
	w.throw_origin = wr.position + Vector2(0, -20)

func test_jump_high_points_a_pass() -> void:
	var w := _live()
	var wr := _wr(w)
	var z := T.CATCH_MAX_HEIGHT + T.JUMP_HEIGHT * 0.5
	_ball_over(w, wr, z)
	assert_true(not w._try_catch(), "standing receiver can't reach a ball at %.2f" % z)
	assert_eq(w.catch_ceiling(wr), T.CATCH_MAX_HEIGHT, "standing ceiling")
	w.ball.hold(-1)
	assert_true(w.jump(wr.id), "jump")
	_run(w, {}, T.JUMP_TIME * 0.5)
	_ball_over(w, wr, z)
	assert_true(w.catch_ceiling(wr) > z, "jumping ceiling above the ball")
	assert_true(w._try_catch(), "jumping receiver high-points it")
	assert_true(w.ball.is_held_by(wr.id), "caught by the jumper")

func test_jump_in_snapshot() -> void:
	var a := _match()
	a.world.snap()
	_run(a.world, {}, 0.5)
	var wr := _wr(a.world)
	assert_true(a.world.jump(wr.id), "jump")
	_run(a.world, {}, 0.2)
	var b := _match()
	P.apply_snapshot(b, P.encode_snapshot(a, 1))
	var bw: Athlete = b.world.get_athlete(wr.id)
	assert_true(bw.is_jumping(), "client sees the jump")
	assert_true(absf(bw.jump_t - wr.jump_t) < 0.001, "jump clock round-trips (%.3f vs %.3f)" % [bw.jump_t, wr.jump_t])
	_run(a.world, {}, T.JUMP_TIME)
	P.apply_snapshot(b, P.encode_snapshot(a, 2))
	assert_true(not bw.is_jumping(), "client sees the landing")

func test_space_routes_to_jump_in_live_play() -> void:
	var m := _match()
	var w := m.world
	var wr := _wr(w)
	assert_true(not P.apply_action(m, wr.id, {"a": "snap"}) or not wr.is_jumping(), "pre-snap Space never jumps")
	w.snap()
	_run(w, {}, 0.5)
	assert_true(P.apply_action(m, wr.id, {"a": "snap"}), "live Space is accepted")
	assert_true(wr.is_jumping(), "and jumps")

func test_whistle_lands_an_airborne_carrier() -> void:
	var w := _live()
	var qb: Athlete = w.find_role(0, Athlete.Role.QB)
	_run(w, {}, 0.5)
	assert_true(w.ball.is_held_by(qb.id), "QB holds the snap")
	assert_true(w.jump(qb.id), "carrier jumps")
	assert_true(w.handoff_receiver(qb.id) == null, "no handoff in the air")
	w._whistle("out_of_bounds", {"by": -1, "carrier": qb.id, "team": qb.team})
	_run(w, {}, 0.1)
	assert_true(not qb.is_jumping(), "whistled dead mid-air: lands at the spot")
	assert_eq(qb.jump_height(), 0.0, "feet on the ground")
