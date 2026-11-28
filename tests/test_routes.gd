extends "res://tests/test_case.gd"

const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Roster := preload("res://src/sim/roster.gd")
const Routes := preload("res://src/sim/routes.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const AI := preload("res://src/sim/ai.gd")
const P := preload("res://src/net/protocol.gd")
const DT := 1.0 / 60.0
const R := Athlete.Role

func _match() -> Match:
	var w := World.new()
	Roster.new().build(w)
	var m := Match.new(w)
	m.start(0, 25.0)
	return m

func test_mirroring() -> void:
	var left := Routes.path_for("SLANT", Vector2(8, 24), 53.33)
	var right := Routes.path_for("SLANT", Vector2(45, 24), 53.33)
	assert_true(left[-1].x > 8.0, "left slant goes inside (+x)")
	assert_true(right[-1].x < 45.0, "right slant goes inside (-x)")
	var out := Routes.path_for("OUT", Vector2(12, 24), 53.33)
	assert_true(out[-1].x < 12.0, "out goes to sideline")

func test_play_assigns_eligible_only() -> void:
	var m := _match()
	var w := m.world
	assert_true(w.call_play("Slants"))
	assert_eq(w.route_of.size(), 3, "three receivers")
	for id in w.route_of:
		var r = w.get_athlete(id).role
		assert_true(r == R.WR or r == R.RB, "eligible only (role %d)" % r)
	assert_true(not w.call_play("Hail Mary 9000"), "unknown play")

func test_ai_runs_slant() -> void:
	var m := _match()
	var w := m.world
	w.call_play("Slants")
	var wr = w.receivers_in_order()[0]   # left WR
	var start: Vector2 = wr.position
	w.snap()
	var ai := AI.new()
	ai.defense_enabled = false
	for i in 90:
		w.step(ai.think(w, []), DT)
	assert_true(wr.position.y > w.los_y + 3.0, "advanced past LOS")
	assert_true(wr.position.x > start.x + 2.0, "broke inside (dx %.1f)" % (wr.position.x - start.x))

func test_actions_authority() -> void:
	var m := _match()
	var w := m.world
	var lb := w.find_role(1, R.LB)
	var qb := w.find_role(0, R.QB)
	assert_true(not P.apply_action(m, lb.id, {"a": "play", "p": "Mesh"}), "defense can't call plays")
	assert_true(P.apply_action(m, qb.id, {"a": "play", "p": "Mesh"}), "offense calls play")
	assert_eq(w.play_name, "Mesh")
	var wr = w.receivers_in_order()[1]
	assert_true(P.apply_action(m, wr.id, {"a": "route", "r": "POST"}), "receiver picks own route")
	assert_eq(w.route_of[wr.id], "POST")
	assert_true(not P.apply_action(m, qb.id, {"a": "route", "r": "GO"}), "QB can't take a route")
	assert_true(not P.apply_action(m, lb.id, {"a": "route", "r": "GO"}), "defender can't take a route")
	w.snap()
	assert_true(not P.apply_action(m, qb.id, {"a": "play", "p": "Slants"}), "no play call while live")

func test_presnap_audible_replaces_the_replicated_call_and_locks_at_the_snap() -> void:
	var host := _match()
	var w := host.world
	var qb := w.find_role(0, R.QB)
	var receiver: Athlete = w.receivers_in_order()[0]
	assert_true(P.apply_action(host, qb.id, {"a": "play", "p": "Slants"}))
	assert_eq(w.route_of[receiver.id], "SLANT")
	assert_true(P.apply_action(host, qb.id, {"a": "play", "p": "Flood"}))
	assert_eq(w.route_of[receiver.id], "CORNER")

	var client := _match()
	P.apply_snapshot(client, bytes_to_var(var_to_bytes(P.encode_snapshot(host, 1))))
	assert_eq(client.world.play_name, "Flood")
	assert_eq(client.world.route_of, w.route_of, "teammate receives the new route assignments")

	assert_true(w.snap())
	assert_true(not P.apply_action(host, qb.id, {"a": "play", "p": "Slants"}), "live call rejected")
	assert_eq(w.play_name, "Flood")
	assert_eq(w.route_of[receiver.id], "CORNER")

func test_snapshot_carries_routes() -> void:
	var a := _match()
	a.world.call_play("Flood")
	var b := _match()
	P.apply_snapshot(b, bytes_to_var(var_to_bytes(P.encode_snapshot(a, 1))))
	assert_eq(b.world.play_name, "Flood")
	assert_eq(b.world.route_of, a.world.route_of, "routes match")
