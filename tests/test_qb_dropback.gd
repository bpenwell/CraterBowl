extends "res://tests/test_case.gd"

const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Protocol := preload("res://src/net/protocol.gd")
const Predictor := preload("res://src/net/client_predictor.gd")
const T := preload("res://src/sim/tuning.gd")
const DT := 1.0 / 60.0

func _match(team := 0) -> Match:
	var world := World.new()
	world.add_athlete(team, Athlete.Role.QB, Vector2(25.0, 0.0))
	world.add_athlete(team, Athlete.Role.RB, Vector2(32.0, 0.0))
	world.add_athlete(1 - team, Athlete.Role.QB, Vector2(10.0, 0.0))
	var match_state := Match.new(world)
	match_state.start(team, 40.0)
	return match_state

func _sprint(world: World, athlete: Athlete) -> void:
	world.step({athlete.id: {"dir": Vector2.RIGHT, "sprint": true}}, DT)

func test_dropback_ramps_to_floor_for_either_offense() -> void:
	for team in [0, 1]:
		var world := _match(team).world
		var qb := world.get_athlete(0)
		assert_true(world.snap(), "snap to attacking QB")
		for sample in [[13.0, 1.0], [14.0, 1.0], [17.0, 0.825], [20.0, 0.65], [24.0, 0.65], [12.0, 1.0]]:
			qb.position = Vector2(25.0, world.los_y - sample[0])
			var x0 := qb.position.x
			_sprint(world, qb)
			var expected: float = T.SPRINT_SPEED * sample[1]
			assert_near(qb.speed(), expected, 0.001, "team %d, depth %.1f" % [team, sample[0]])
			assert_near(qb.position.x - x0, expected * DT, 0.001, "movement uses scaled velocity")

func test_dropback_excludes_other_athletes_and_released_ball() -> void:
	var world := _match().world
	var qb := world.get_athlete(0)
	var back := world.get_athlete(1)
	var opponent := world.get_athlete(2)
	assert_true(world.snap(), "snap")
	qb.position.y = world.los_y - 22.0
	back.position = qb.position + Vector2(1.0, 0.0)
	opponent.position.y = qb.position.y
	_sprint(world, opponent)
	assert_near(opponent.speed(), T.SPRINT_SPEED, 0.001, "different team's QB")
	assert_true(world.handoff(qb.id), "handoff in the backfield")
	_sprint(world, back)
	assert_near(back.speed(), T.SPRINT_SPEED, 0.001, "running back holds ball")
	_sprint(world, qb)
	assert_near(qb.speed(), T.SPRINT_SPEED, 0.001, "QB after handoff")
	world.setup_formation(40.0)
	assert_true(world.snap(), "next snap")
	qb.position.y = world.los_y - 22.0
	assert_true(world.throw(qb.id, Vector2(25.0, 50.0), 0.75), "forward pass")
	_sprint(world, qb)
	assert_near(qb.speed(), T.SPRINT_SPEED, 0.001, "QB after throw")

func test_dropback_excludes_kicks_chaosball_and_free_practice() -> void:
	var world := _match().world
	var qb := world.get_athlete(0)
	assert_true(world.call_kick("punt") and world.snap(), "punt snap")
	qb.position.y = world.los_y - 22.0
	_sprint(world, qb)
	assert_near(qb.speed(), T.SPRINT_SPEED, 0.001, "punter before kick")
	world.set_ruleset("chaosball")
	world.setup_formation(40.0)
	assert_true(world.snap(), "chaosball snap")
	qb.position.y = world.los_y - 22.0
	_sprint(world, qb)
	assert_near(qb.speed(), T.SPRINT_SPEED, 0.001, "Chaosball QB")
	world.set_ruleset("classic")
	world.setup_formation(40.0)
	world.start_live_with(qb.id)
	world.los_y = world.field.length + world.field.endzone_depth + 10.0
	_sprint(world, qb)
	assert_near(qb.speed(), T.SPRINT_SPEED, 0.001, "free practice uses a virtual line")

func test_dash_dive_and_predicted_run_use_dropback_scale() -> void:
	var host := _match()
	var world := host.world
	var qb := world.get_athlete(0)
	assert_true(world.snap(), "snap")
	qb.position.y = world.los_y - 22.0
	var client := _match()
	Protocol.apply_snapshot(client, Protocol.encode_snapshot(host, 1))
	var predicted := client.world.get_athlete(qb.id)
	var predictor := Predictor.new()
	predictor.record(Vector2.RIGHT, true, DT)
	predictor.reconcile(predicted, 0, client.world)
	_sprint(world, qb)
	assert_near(predicted.speed(), T.SPRINT_SPEED * 0.65, 0.001, "predicted sprint speed")
	assert_near(predicted.position.distance_to(qb.position), 0.0, 0.001, "prediction agrees with authority")
	assert_true(world.evade(qb.id, false, Vector2.RIGHT), "dash")
	_sprint(world, qb)
	assert_near(qb.speed(), T.DASH_SPEED * 0.65, 0.001, "dash scales at depth")
	qb.move_t = 0.0
	assert_true(world.tackle(qb.id), "dive")
	_sprint(world, qb)
	assert_near(qb.speed(), T.DIVE_SPEED * 0.65, 0.001, "dive scales at depth")
