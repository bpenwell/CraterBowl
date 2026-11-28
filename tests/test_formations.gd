extends "res://tests/test_case.gd"

const World := preload("res://src/sim/world.gd")
const Roster := preload("res://src/sim/roster.gd")
const Match := preload("res://src/sim/match.gd")
const Protocol := preload("res://src/net/protocol.gd")

func _match(size: int, offense := 0, ruleset := "classic") -> Match:
	var world := World.new()
	Roster.new().build(world, size)
	world.set_ruleset(ruleset)
	var match_state := Match.new(world)
	match_state.start(offense, 25.0)
	return match_state

func test_twins_moves_two_wideouts_and_preserves_routes_for_every_size() -> void:
	for size in [3, 5, 7]:
		var m := _match(size, 1)
		var w := m.world
		var qb := w.find_role(1, w.Athlete.Role.QB)
		var before := w.athletes.map(func(a): return a.position)
		var routes := w.route_of.duplicate()
		var call := w.play_name
		assert_eq(w.offensive_formation(), World.Formation.BALANCED, "default formation")
		assert_true(Protocol.apply_action(m, qb.id, {"a": "formation", "f": World.Formation.TWINS_RIGHT}), "QB can select Twins Right")
		assert_eq(w.offensive_formation(), World.Formation.TWINS_RIGHT, "formation follows the lineup")
		var receivers := w.receivers_in_order()
		assert_true(receivers[0].position.x > w.field.width * 0.5 and receivers[1].position.x > receivers[0].position.x,
			"both wideouts have separate spots on the right in %dv%d" % [size, size])
		assert_eq(w.route_of, routes, "route assignments stay attached to their athletes")
		assert_eq(w.play_name, call, "the current call is retained")
		for a in w.athletes:
			assert_eq(a.position.y, before[a.id].y, "everyone keeps their depth")
			assert_true(a.set_lock, "everyone remains set")
			if a != receivers[0] and a != receivers[1]:
				assert_eq(a.position, before[a.id], "no other athlete is repositioned")
		assert_true(Protocol.apply_action(m, qb.id, {"a": "formation", "f": World.Formation.BALANCED}))
		assert_eq(w.athletes.map(func(a): return a.position), before, "Balanced restores the complete lineup")

func test_formation_requires_classic_offensive_qb_before_a_scrimmage_snap() -> void:
	var m := _match(5)
	var w := m.world
	var qb := w.find_role(0, w.Athlete.Role.QB)
	var req := {"a": "formation", "f": World.Formation.TWINS_RIGHT}
	for a in w.athletes:
		if a != qb:
			assert_true(not Protocol.apply_action(m, a.id, req), "non-QB or defense cannot change alignment")
	for bad in [-1, 2, 1.0, true, "Twins Right", []]:
		assert_true(Protocol.sanitize_action({"a": "formation", "f": bad}).is_empty(), "reject invalid preset")
	assert_true(m.call_kick("punt"))
	assert_true(not Protocol.apply_action(m, qb.id, req), "the kicker's lineup is locked")
	assert_true(m.call_kick(""))
	assert_true(Protocol.apply_action(m, qb.id, req))
	assert_true(w.snap(), "Twins Right can snap")
	assert_true(not Protocol.apply_action(m, qb.id, {"a": "formation", "f": World.Formation.BALANCED}), "live formation is locked")
	w.phase = World.Phase.DEAD
	m.last_result = {"type": "incomplete"}
	m.next_play()
	assert_eq(w.offensive_formation(), World.Formation.BALANCED, "next down restores Balanced")
	var chaos := _match(3, 0, "chaosball")
	assert_true(not Protocol.apply_action(chaos, chaos.world.find_role(0, w.Athlete.Role.QB).id, req), "Chaosball uses its own lineup")
