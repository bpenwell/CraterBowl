extends "res://tests/test_case.gd"

const World := preload("res://src/sim/world.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Ball := preload("res://src/sim/ball.gd")
const Passing := preload("res://src/sim/passing.gd")
const T := preload("res://src/sim/tuning.gd")
const DT := 1.0 / 120.0

var events: Array = []

func _world() -> World:
	var w := World.new()
	w.add_athlete(0, Athlete.Role.C, Vector2(26, 20))
	w.add_athlete(0, Athlete.Role.QB, Vector2(26, 15))
	w.setup_formation(25.0)
	w.event.connect(func(n, d): events.append(n))
	w.snap()
	_run(w, {}, 0.5)
	return w

func _run(w, inputs: Dictionary, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		w.step(inputs, DT)

## Simulate ball until it descends through catch height; return xy there.
func _crossing(w) -> Vector2:
	var prev: Vector3 = w.ball.position
	for i in 2000:
		w.step({}, DT)
		var p: Vector3 = w.ball.position
		if w.ball.velocity.z < 0 and p.z <= T.CATCH_HEIGHT and prev.z > T.CATCH_HEIGHT:
			return Vector2(p.x, p.y)
		prev = p
	return Vector2(INF, INF)

func test_stationary_throw_hits_target() -> void:
	var w := _world()
	var qb := w.find_role(0, Athlete.Role.QB)
	var target := Vector2(40, 45)
	assert_true(w.throw(qb.id, target, 0.8), "throw accepted")
	var hit := _crossing(w)
	assert_true(hit.distance_to(target) < 0.5, "within 0.5yd, got %s" % str(hit))

func test_weak_throw_falls_short() -> void:
	var w := _world()
	var qb := w.find_role(0, Athlete.Role.QB)
	var target := Vector2(qb.position.x, qb.position.y + 60.0)
	w.throw(qb.id, target, 0.0)
	_run(w, {}, 5.0)
	assert_eq(w.phase, World.Phase.DEAD, "ball landed")
	assert_true(w.ball.position.y < target.y - 20.0, "fell well short")

func test_more_power_is_faster() -> void:
	var from := Vector3(26, 20, T.RELEASE_HEIGHT)
	var tgt := Vector2(26, 40)
	var t_lo := Passing.time_to_height(Passing.solve_velocity(from, tgt, 0.4), from.z, T.CATCH_HEIGHT)
	var t_hi := Passing.time_to_height(Passing.solve_velocity(from, tgt, 1.0), from.z, T.CATCH_HEIGHT)
	assert_true(t_hi < t_lo, "power 1.0 flight %f < 0.4 flight %f" % [t_hi, t_lo])

func test_throw_on_run_offsets() -> void:
	var w := _world()
	var qb := w.find_role(0, Athlete.Role.QB)
	_run(w, {qb.id: {"dir": Vector2(1, 0)}}, 1.0)  # running right
	var target := Vector2(qb.position.x, qb.position.y + 20.0)
	w.throw(qb.id, target, 0.8)
	var hit := _crossing(w)
	assert_true(hit.x > target.x + 1.0, "drifts with QB motion: %s vs %s" % [str(hit), str(target)])

func test_throw_rejections() -> void:
	var w := World.new()
	var c := w.add_athlete(0, Athlete.Role.C, Vector2(26, 20))
	var qb := w.add_athlete(0, Athlete.Role.QB, Vector2(26, 15))
	w.setup_formation(25.0)
	assert_true(not w.throw(c.id, Vector2(26, 40), 1.0), "no throw presnap")
	w.snap()
	_run(w, {}, 0.5)
	assert_true(not w.throw(c.id, Vector2(26, 40), 1.0), "non-holder can't throw")
	_run(w, {qb.id: {"dir": Vector2(0, 1), "sprint": true}}, 2.0)
	assert_true(qb.position.y > w.los_y, "QB past LOS")
	assert_true(not w.throw(qb.id, Vector2(26, 60), 1.0), "no throw past LOS")

func test_one_forward_pass() -> void:
	var w := _world()
	var qb := w.find_role(0, Athlete.Role.QB)
	assert_true(w.throw(qb.id, Vector2(26, 30), 0.5))
	w.ball.hold(qb.id)  # simulate ball coming back
	assert_true(not w.throw(qb.id, Vector2(26, 30), 0.5), "second forward pass rejected")

func test_in_flight_ground_marker_matches_the_pass_landing() -> void:
	var w := _world()
	var qb := w.find_role(0, Athlete.Role.QB)
	assert_true(w.throw(qb.id, Vector2(40.0, 49.0), 0.8), "real pass released")
	var at_release := Passing.ground_landing(w.ball.position, w.ball.velocity, w.gravity())
	_run(w, {}, 0.4)
	assert_eq(w.ball.state, Ball.State.IN_FLIGHT, "second sample is in flight")
	var in_flight := Passing.ground_landing(w.ball.position, w.ball.velocity, w.gravity())
	_run(w, {}, 5.0)
	var landed := Vector2(w.ball.position.x, w.ball.position.y)
	assert_true(at_release.distance_to(landed) <= 0.5, "first estimate matches the actual drop")
	assert_true(in_flight.distance_to(landed) <= 0.5, "in-flight estimate matches the actual drop")

func test_ground_is_incomplete() -> void:
	events.clear()
	var w := _world()
	var qb := w.find_role(0, Athlete.Role.QB)
	w.throw(qb.id, Vector2(45, 35), 0.6)  # away from the C (who could catch it)
	_run(w, {}, 6.0)
	assert_eq(w.phase, World.Phase.DEAD, "dead")
	assert_eq(w.ball.state, Ball.State.DEAD, "ball dead")
	assert_true(events.has("incomplete"), "incomplete event")

func test_lead_target_hits_moving_receiver() -> void:
	var from := Vector3(26, 20, T.RELEASE_HEIGHT)
	var rx := Vector2(10, 30)
	var vel := Vector2(0, 8)
	var tgt := Passing.lead_target(from, rx, vel, 0.8)
	var v := Passing.solve_velocity(from, tgt, 0.8)
	var t := Passing.time_to_height(v, from.z, T.CATCH_HEIGHT)
	var rx_at := rx + vel * t
	var ball_at := Vector2(from.x, from.y) + Vector2(v.x, v.y) * t
	assert_true(rx_at.distance_to(ball_at) < 1.0, "lead within 1yd: %f" % rx_at.distance_to(ball_at))

func test_lob_hits_target_and_hangs_longer() -> void:
	var from := Vector3(26, 20, T.RELEASE_HEIGHT)
	var tgt := Vector2(26, 32)
	var vf := Passing.solve_velocity(from, tgt, 0.6)
	var vl := Passing.solve_velocity(from, tgt, 0.6, T.GRAVITY, true)
	var tf := Passing.time_to_height(vf, from.z, T.CATCH_HEIGHT)
	var tl := Passing.time_to_height(vl, from.z, T.CATCH_HEIGHT)
	assert_true(tl > tf * 1.5, "lob hangs longer (%.2f vs %.2f)" % [tl, tf])
	var land := Vector2(from.x, from.y) + Vector2(vl.x, vl.y) * tl
	assert_true(land.distance_to(tgt) < 0.3, "lob lands on target (%s)" % str(land))
