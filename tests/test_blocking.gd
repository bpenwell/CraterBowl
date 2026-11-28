extends "res://tests/test_case.gd"

const World := preload("res://src/sim/world.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const AI := preload("res://src/sim/ai.gd")
const T := preload("res://src/sim/tuning.gd")
const DT := 1.0 / 60.0

var events: Array = []

func _setup(extra: Array) -> World:
	events.clear()
	var w := World.new()
	w.add_athlete(0, Athlete.Role.C, Vector2(26, 20))
	w.add_athlete(0, Athlete.Role.QB, Vector2(26, 15))
	for e in extra:
		w.add_athlete(e[0], e[1], e[2])
	w.setup_formation(25.0)
	for i in extra.size():
		w.athletes[2 + i].position = extra[i][2]
	w.event.connect(func(n, d): events.append(n))
	w.snap()
	return w

func _run(w, inputs: Dictionary, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		w.step(inputs, DT)

func test_bodies_separate() -> void:
	var w := _setup([[0, Athlete.Role.WR, Vector2(10, 30)], [1, Athlete.Role.CB, Vector2(10.2, 30)]])
	_run(w, {}, 0.1)
	assert_true(w.athletes[2].position.distance_to(w.athletes[3].position) >= 0.9 - 0.001, "separated")

func test_grounded_ignored() -> void:
	var w := _setup([[0, Athlete.Role.WR, Vector2(10, 30)], [1, Athlete.Role.CB, Vector2(10.2, 30)]])
	w.athletes[3].recover_t = 1.0
	_run(w, {}, 0.1)
	assert_true(w.athletes[2].position.distance_to(w.athletes[3].position) < 0.5, "no collision while grounded")

func test_ol_engages_and_slows_dl() -> void:
	# Free DL baseline
	var w1 := _setup([[1, Athlete.Role.DL, Vector2(40, 26)]])
	var free_dl: Athlete = w1.athletes[2]
	var y0 := free_dl.position.y
	_run(w1, {free_dl.id: {"dir": Vector2(0, -1), "sprint": true}}, 1.0)
	var free_gain := y0 - free_dl.position.y
	# Blocked DL
	var w2 := _setup([[0, Athlete.Role.OL, Vector2(40, 24.6)], [1, Athlete.Role.DL, Vector2(40, 25.5)]])
	var ol: Athlete = w2.athletes[2]
	var dl: Athlete = w2.athletes[3]
	ol.facing = Vector2(0, 1)
	var y1 := dl.position.y
	_run(w2, {dl.id: {"dir": Vector2(0, -1), "sprint": true}}, 1.0)
	assert_true(events.has("block"), "engaged")
	var blocked_gain := y1 - dl.position.y
	assert_true(blocked_gain < free_gain * 0.5, "blocked gain %f << free %f" % [blocked_gain, free_gain])

func test_block_sheds_then_immunity() -> void:
	var w := _setup([[0, Athlete.Role.OL, Vector2(40, 24.6)], [1, Athlete.Role.DL, Vector2(40, 25.5)]])
	var ol: Athlete = w.athletes[2]
	var dl: Athlete = w.athletes[3]
	ol.facing = Vector2(0, 1)
	_run(w, {}, 0.05)
	assert_eq(dl.engaged_with, ol.id, "engaged")
	_run(w, {}, T.BLOCK_HOLD)
	assert_true(events.has("shed"), "shed after hold")
	assert_true(dl.engaged_with < 0 or dl.engage_t < 0.2, "released")
	assert_true(dl.immune_t > 0.0 or dl.engaged_with < 0, "immune window")
	_run(w, {}, 0.05)
	assert_eq(dl.engaged_with, -1, "no instant re-engage")

func test_carrier_cannot_block() -> void:
	var w := _setup([[1, Athlete.Role.DL, Vector2(26, 20.8)]])
	_run(w, {}, 0.5)  # QB has ball at y=20, DL right in front
	var qb := w.find_role(0, Athlete.Role.QB)
	qb.facing = Vector2(0, 1)
	_run(w, {}, 0.1)
	assert_true(qb.engaged_with < 0, "carrier never engages")

func _time_to_sack(protect: bool) -> float:
	var extra := [[1, Athlete.Role.DL, Vector2(24.5, 25.5)], [1, Athlete.Role.DL, Vector2(27.5, 25.5)]]
	if protect:
		extra += [[0, Athlete.Role.OL, Vector2(23.5, 24.5)], [0, Athlete.Role.OL, Vector2(28.5, 24.5)]]
	var w := _setup(extra)
	if not protect:
		w.athletes.erase(w.find_role(0, Athlete.Role.C))  # no C either
		for i in w.athletes.size(): w.athletes[i].id = i
		w.ball.hold(w.find_role(0, Athlete.Role.QB).id)
	var ai := AI.new()
	var t := 0.0
	var qb := w.find_role(0, Athlete.Role.QB)
	while t < 10.0:
		w.step(ai.think(w, [qb.id]), DT)
		t += DT
		if events.has("tackle"):
			return t
	return t

func test_protection_delays_sack() -> void:
	var unprotected := _time_to_sack(false)
	var protected := _time_to_sack(true)
	assert_true(protected > unprotected + 0.75, "protected %f vs unprotected %f" % [protected, unprotected])

func test_beaten_blocker_cooldown() -> void:
	var w := _setup([[0, Athlete.Role.OL, Vector2(40, 24.6)], [1, Athlete.Role.DL, Vector2(40, 25.5)]])
	var ol: Athlete = w.athletes[2]
	ol.facing = Vector2(0, 1)
	_run(w, {}, T.BLOCK_HOLD + 0.1)
	assert_true(events.has("shed"), "shed")
	_run(w, {}, T.BLOCK_IMMUNITY + 0.1)  # defender immunity over, blocker still beaten
	assert_eq(ol.engaged_with, -1, "beaten blocker can't immediately re-engage")

func test_receivers_dont_block_during_pass_play() -> void:
	var w := _setup([[0, Athlete.Role.WR, Vector2(10, 24)], [1, Athlete.Role.CB, Vector2(10, 25.5)]])
	var wr: Athlete = w.athletes[2]
	_run(w, {wr.id: {"dir": Vector2(0, 1)}}, 0.6)  # QB holds ball behind LOS
	assert_eq(wr.engaged_with, -1, "WR on route doesn't engage")

func test_ai_route_runner_avoids_defender_in_lane() -> void:
	var w := _setup([[0, Athlete.Role.WR, Vector2(10, 24)], [1, Athlete.Role.CB, Vector2(10, 27)]])
	var ai := AI.new()
	ai.defense_enabled = false
	var wr: Athlete = w.athletes[2]
	for i in 120:
		w.step(ai.think(w, [w.find_role(0, Athlete.Role.QB).id]), DT)
	assert_true(wr.position.y > 32.0, "WR got past the CB (y=%f)" % wr.position.y)

# #62: human vs bot input is an explicit flag, not the presence of a "block" key.
func _engage_setup() -> World:
	var w := _setup([[0, Athlete.Role.OL, Vector2(40, 24.6)], [1, Athlete.Role.DL, Vector2(40, 25.5)]])
	w.athletes[2].facing = Vector2(0, 1)
	return w

func test_is_human_input_flag() -> void:
	assert_true(World.is_human_input({World.HUMAN: true}), "flagged input is human")
	assert_true(World.is_human_input({World.HUMAN: true, "dir": Vector2.ZERO}), "no block key, still human")
	assert_true(not World.is_human_input({}), "empty input is a bot")
	assert_true(not World.is_human_input({"dir": Vector2.ZERO, "block": false}), "block key alone is not human")

func test_human_without_block_key_does_not_auto_engage() -> void:
	var w := _engage_setup()
	var ol: Athlete = w.athletes[2]
	var dl: Athlete = w.athletes[3]
	_run(w, {ol.id: {World.HUMAN: true, "dir": Vector2.ZERO}}, 0.1)
	assert_eq(dl.engaged_with, -1, "human OL blocks only with the shield held")

func test_human_without_block_key_releases_engagement() -> void:
	var w := _engage_setup()
	var ol: Athlete = w.athletes[2]
	var dl: Athlete = w.athletes[3]
	_run(w, {}, 0.05)
	assert_eq(dl.engaged_with, ol.id, "bot OL engaged")
	w.step({ol.id: {World.HUMAN: true}}, DT)
	assert_eq(dl.engaged_with, -1, "human taking over without the shield releases the block")

func test_bot_input_with_block_key_stays_bot() -> void:
	var w := _engage_setup()
	var ol: Athlete = w.athletes[2]
	var dl: Athlete = w.athletes[3]
	_run(w, {ol.id: {"dir": Vector2.ZERO, "sprint": false, "block": false}}, 0.05)
	assert_eq(dl.engaged_with, ol.id, "bot with a block key still auto-engages")
	_run(w, {ol.id: {"dir": Vector2.ZERO, "sprint": false, "block": false}}, 0.05)
	assert_eq(dl.engaged_with, ol.id, "bot with block=false is not released like a human")

## Face to face: a blocker behind or beside a defender running the same way never locks
## on (the pair used to slide downfield together with arms out); one ahead of his path does.
func test_no_block_from_behind_or_running_alongside() -> void:
	for case in [["behind", Vector2(40, 24.4), false], ["alongside", Vector2(40.9, 25.5), false], ["ahead", Vector2(40, 26.4), true]]:
		var w := _setup([[0, Athlete.Role.OL, case[1]], [1, Athlete.Role.DL, Vector2(40, 25.5)]])
		var ol: Athlete = w.athletes[2]
		var dl: Athlete = w.athletes[3]
		ol.facing = (dl.position - ol.position).normalized()   # the blocker always faces him
		dl.velocity = Vector2(0, 6.0)   # the defender runs upfield
		w._step_blocks(_prev(w), {}, DT)   # the engagement rule alone, no movement
		assert_eq(dl.engaged_with >= 0, case[2], "%s: engaged %s" % [case[0], dl.engaged_with])

func _prev(w) -> Array:
	var out := []
	for a in w.athletes:
		out.append(a.position)
	return out

func test_blocks_end_before_out_of_bounds_whistle() -> void:
	var w := _engage_setup()
	var blocker: Athlete = w.athletes[2]
	var defender: Athlete = w.athletes[3]
	var blocker_start := blocker.position
	var defender_start := defender.position
	_run(w, {}, 0.4)
	assert_eq(blocker.engaged_with, defender.id, "block was active")
	assert_eq(defender.engaged_with, blocker.id, "defender was engaged")
	w.event.connect(func(name, _data):
		if name == "whistle":
			assert_eq(blocker.engaged_with, -1, "blocker released before the whistle")
			assert_eq(defender.engaged_with, -1, "defender released before the whistle")
			assert_eq(defender.engage_t, 0.0, "elapsed hold cleared before the whistle")
	)
	var carrier := w.carrier()
	assert_true(carrier != null, "QB has the snap")
	if carrier == null:
		return
	carrier.position.x = -0.5
	w.step({}, DT)
	assert_eq(w.phase, World.Phase.DEAD, "carrier stepped out")
	assert_true(events.has("whistle"), "whistle emitted")
	assert_true(not events.has("shed"), "a dead ball doesn't award a shed")
	_run(w, {}, 0.1)
	assert_eq(blocker.engaged_with, -1, "no engagements form between plays")
	w.setup_formation(25.0)
	blocker.position = blocker_start
	blocker.facing = Vector2.DOWN
	defender.position = defender_start
	w.snap()
	w.step({}, DT)
	assert_eq(blocker.engaged_with, defender.id, "the next live snap can form a block")

func test_blocks_end_on_incomplete_pass() -> void:
	var w := _engage_setup()
	_run(w, {}, 0.4)
	var blocker: Athlete = w.athletes[2]
	var defender: Athlete = w.athletes[3]
	assert_eq(blocker.engaged_with, defender.id, "block was active")
	var carrier := w.carrier()
	assert_true(carrier != null, "QB has the snap")
	if carrier == null:
		return
	assert_true(w.throw(carrier.id, Vector2(12, 35), 0.5), "forward pass released")
	w.ball.position.z = 0.01
	w.ball.velocity.z = -1.0
	w.step({}, DT)
	assert_true(events.has("incomplete"), "pass hit the ground")
	assert_eq(w.phase, World.Phase.DEAD, "incomplete pass ended the play")
	assert_eq(blocker.engaged_with, -1, "blocker released on the incomplete")
	assert_eq(defender.engaged_with, -1, "defender released on the incomplete")
