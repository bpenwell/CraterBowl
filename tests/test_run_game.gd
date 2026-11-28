extends "res://tests/test_case.gd"

const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Roster := preload("res://src/sim/roster.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const AI := preload("res://src/sim/ai.gd")
const Stats := preload("res://src/sim/stats.gd")
const Protocol := preload("res://src/net/protocol.gd")
const T := preload("res://src/sim/tuning.gd")
const R := Athlete.Role
const DT := 1.0 / 60.0

func _match(size: int = 7) -> Match:
	var world := World.new()
	Roster.new().build(world, size)
	var m := Match.new(world)
	m.start()
	return m

func _receive_snap(w: World) -> void:
	w.snap()
	for i in 30:
		w.step({}, DT)

func test_handoff_requires_live_qb_and_adjacent_back_behind_line() -> void:
	var m := _match()
	var w := m.world
	var qb := w.find_role(0, R.QB)
	var back := w.find_role(0, R.RB)
	var opponent := w.find_role(1, R.LB)
	assert_true(not w.handoff(qb.id), "presnap handoff rejected")
	_receive_snap(w)
	assert_true(not w.handoff(qb.id), "out-of-reach back rejected")
	back.position = qb.position + Vector2.RIGHT
	assert_true(not Protocol.apply_action(m, opponent.id, {"a": "handoff"}), "opponent cannot initiate a handoff")
	assert_true(not w.handoff(back.id), "back cannot take the ball by initiating a handoff")
	back.recover_t = 1.0
	assert_true(not w.handoff(qb.id), "downed back rejected")
	back.recover_t = 0.0
	qb.position.y = w.los_y + 0.1
	back.position.y = w.los_y - 0.1
	assert_true(not w.handoff(qb.id), "QB beyond the line cannot hand off")
	qb.position.y = w.los_y - 0.1
	back.position.y = w.los_y + 0.1
	assert_true(not w.handoff(qb.id), "back must also be behind the line")
	back.position.y = qb.position.y
	w.forward_pass_thrown = true
	assert_true(not w.handoff(qb.id), "handoff after a pass rejected")
	w.forward_pass_thrown = false
	assert_true(Protocol.apply_action(m, qb.id, {"a": "handoff", "to": opponent.id}), "authority chooses the adjacent back")
	assert_eq(w.carrier(), back, "ball belongs to the back")
	assert_eq(w.ball.position, Vector3(back.position.x, back.position.y, T.BALL_CARRY_HEIGHT))
	assert_eq(w.phase, World.Phase.LIVE)

func test_handoff_cooldown_elapses_in_live_play_and_resets_at_formation() -> void:
	var w := _match().world
	var qb := w.find_role(0, R.QB)
	var back := w.find_role(0, R.RB)
	_receive_snap(w)
	back.position = qb.position + Vector2.RIGHT
	assert_true(w.handoff(qb.id))
	w.ball.hold(qb.id)  # Simulate the QB regaining the ball during the play.
	assert_true(not w.handoff(qb.id), "cooldown blocks a second exchange even with possession")
	for i in int(ceil(T.HANDOFF_COOLDOWN / DT)) + 1:
		w.step({}, DT)
	assert_true(w.handoff(qb.id), "new exchange is legal once the cooldown elapses")
	w.setup_formation(w.los_y)
	assert_near(w.handoff_cooldown, 0.0)

func test_run_calls_have_distinct_mirrored_paths_and_blocking_targets() -> void:
	var m := _match()
	var w := m.world
	var back := w.find_role(0, R.RB)
	var qb := w.find_role(0, R.QB)
	assert_true(Protocol.apply_action(m, qb.id, {"a": "play", "p": "Inside Zone"}))
	var inside: Vector2 = w.run_path()[1]
	assert_true(w.call_play("Outside Sweep"))
	var outside: Vector2 = w.run_path()[1]
	assert_true(outside.x > inside.x + 5.0, "sweep attacks wider than the zone")
	assert_true(w.flip_play())
	assert_near(w.run_path()[1].x, w.field.width - outside.x)
	assert_true(not w.set_route(back.id, "GO"), "a hot route cannot replace the run assignment")
	var blocks := w.run_block_assignments()
	var defenders := {}
	for id in blocks:
		assert_true(w.get_athlete(id).role in [R.C, R.OL])
		assert_eq(w.get_athlete(blocks[id]).team, 1)
		defenders[blocks[id]] = true
	assert_eq(blocks.size(), 3, "all three linemen get work in 7v7")
	assert_eq(defenders.size(), blocks.size(), "each lineman has a distinct target")
	w.snap()
	assert_eq(w.run_blocks, blocks)
	assert_eq(w.route_paths[back.id], w.run_path())
	var copy := _match()
	Protocol.apply_snapshot(copy, Protocol.encode_snapshot(m, 42))
	assert_eq(copy.world.play_name, "Outside Sweep")
	assert_true(copy.world.run_flipped)
	assert_eq(copy.world.run_path(), w.run_path())

func test_run_calls_require_a_back_in_classic() -> void:
	var small := _match(3)
	var w := small.world
	assert_true(not w.available_plays().has("Inside Zone"))
	assert_true(not w.call_play("Outside Sweep"))
	var m := _match(5)
	assert_true(m.world.available_plays().has("Inside Zone"))
	m.world.set_ruleset("chaosball")
	assert_true(not m.world.call_play("Inside Zone"))
	_receive_snap(m.world)
	var qb := m.world.find_role(0, R.QB)
	m.world.find_role(0, R.RB).position = qb.position + Vector2.RIGHT
	assert_true(not m.world.handoff(qb.id), "Chaosball retains its passing rules")

func test_crossing_los_keeps_run_live_and_whistle_credits_the_back() -> void:
	var w := _match().world
	var stats := Stats.new()
	stats.attach(w, func(_aid): return "Test")
	var qb := w.find_role(0, R.QB)
	var back := w.find_role(0, R.RB)
	_receive_snap(w)
	back.position = qb.position + Vector2.RIGHT
	assert_true(w.handoff(qb.id))
	back.position.y = w.los_y + 7.5
	w.step({}, DT)
	assert_eq(w.phase, World.Phase.LIVE, "crossing the line is legal")
	assert_eq(w.carrier(), back)
	back.position.x = -0.5
	w.step({}, DT)
	assert_eq(w.phase, World.Phase.DEAD)
	assert_eq(stats.total("att"), 0)
	assert_near(stats.get_line("Test", "RB").get("car", 0), 1)
	assert_near(stats.get_line("Test", "RB").get("rush_yds", 0), 7.5)

func test_fumbled_handoff_run_still_credits_the_carry_once() -> void:
	var w := _match().world
	var stats := Stats.new()
	stats.attach(w, func(_aid): return "Test")
	var qb := w.find_role(0, R.QB)
	var back := w.find_role(0, R.RB)
	_receive_snap(w)
	back.position = qb.position + Vector2.RIGHT
	assert_true(w.handoff(qb.id))
	back.position.y = w.los_y + 4.0
	w._fumble(back, w.find_role(1, R.LB))
	w.ball.hold(back.id)
	back.position = Vector2(-0.5, w.los_y + 5.0)
	w.step({}, DT)
	assert_near(stats.get_line("Test", "RB").get("car", 0), 1)
	assert_near(stats.get_line("Test", "RB").get("rush_yds", 0), 4)

func _retreat_after_crossing(w: World, runner: Athlete) -> void:
	runner.position = Vector2(6.0, w.los_y + 2.0)
	w.step({}, DT)
	runner.position.y = w.los_y - 3.0
	w.step({}, DT)

func test_keeper_cannot_pass_after_crossing_and_retreating() -> void:
	var m := _match()
	var w := m.world
	_receive_snap(w)
	var qb := w.find_role(0, R.QB)
	assert_true(w.can_throw(qb.id))
	_retreat_after_crossing(w, qb)
	assert_true(w.ball_crossed_los and qb.position.y < w.los_y and w.ball.is_held_by(qb.id))

	assert_true(not w.can_throw(qb.id))
	assert_true(not w.throw_dir(qb.id, Vector2.DOWN, 20.0, 0.8), "POV pass rejected")
	assert_true(not Protocol.apply_action(m, qb.id, {"a": "throw", "t": Vector2(13, 46), "p": 0.8}),
		"host rejects the retreated runner's pass")
	assert_true(w.ball.is_held_by(qb.id) and not w.forward_pass_thrown, "play continues as a run")

	m.start(0, 36.0)
	_receive_snap(w)
	assert_true(not w.ball_crossed_los and w.can_throw(qb.id), "the next snap opens passing again")

func test_handoff_runner_cannot_pass_after_crossing_and_retreating() -> void:
	var w := _match().world
	_receive_snap(w)
	var qb := w.find_role(0, R.QB)
	var back := w.find_role(0, R.RB)
	back.position = qb.position + Vector2.RIGHT
	assert_true(w.handoff(qb.id) and w.can_throw(back.id), "back can pass before crossing")
	_retreat_after_crossing(w, back)
	assert_true(w.ball_crossed_los and back.position.y < w.los_y)
	assert_true(not w.throw(back.id, Vector2(13, 46), 0.8), "handoff runner cannot pass after crossing")
	assert_true(w.ball.is_held_by(back.id))

func test_chaosball_still_allows_a_pass_after_crossing_and_retreating() -> void:
	var w := _match(3).world
	w.set_ruleset("chaosball")
	_receive_snap(w)
	var qb := w.find_role(0, R.QB)
	_retreat_after_crossing(w, qb)
	assert_true(w.ball_crossed_los)
	assert_true(w.throw(qb.id, Vector2(13, 46), 0.8), "Chaosball still permits the throw")

func test_bots_execute_both_run_paths_and_engage_assigned_defenders() -> void:
	var furthest_x := {}
	for play in ["Inside Zone", "Outside Sweep"]:
		var w := _match().world
		var bots := AI.new()
		bots.defense_enabled = false
		var back := w.find_role(0, R.RB)
		var events := {"blocks": 0, "handoffs": 0}
		var on_event := func(name, data):
			if name == "handoff":
				events.handoffs += 1
			if name == "block" and w.run_blocks.get(data.blocker) == data.defender:
				events.blocks += 1
		w.event.connect(on_event)
		w.call_play(play)
		w.snap()
		var widest := 0.0
		for i in 150:
			w.step(bots.think(w, []), DT)
			if w.carrier() == back:
				widest = maxf(widest, back.position.x - w.field.width / 2.0)
		w.event.disconnect(on_event)
		furthest_x[play] = widest
		assert_eq(events.handoffs, 1, "%s gets one exchange" % play)
		assert_true(events.blocks > 0, "%s bots made an assigned block" % play)
		assert_true(back.position.y > w.los_y, "%s crossed the line" % play)
	assert_true(furthest_x["Outside Sweep"] > furthest_x["Inside Zone"] + 5.0, "bot follows the wider lane")

func test_two_minute_bot_game_uses_passes_and_handoffs() -> void:
	var m := _match()
	var w := m.world
	m.clock.quarter_length = 30.0   # two-minute game
	m.start()
	var bots := AI.new()
	var events := {"handoff": 0, "throw": 0}
	var calls := {}
	var on_event := func(name, _data):
		if name == "snap":
			calls[w.play_name] = calls.get(w.play_name, 0) + 1
		elif events.has(name):
			events[name] += 1
	w.event.connect(on_event)
	for i in int(400.0 / DT):
		m.tick(DT)
		bots.presnap_tick(w, [], DT, m.downs.down, m.downs.distance())
		w.step(bots.think(w, []), DT)
		if w.phase == World.Phase.DEAD:
			m.next_play()
			if m.is_final():
				break
	w.event.disconnect(on_event)
	assert_true(m.is_final(), "a 60-second half on each side reaches the final whistle")
	assert_true(calls.has("Inside Zone") and calls.has("Outside Sweep"), "both run plays called: %s" % str(calls))
	assert_true(events.handoff > 0 and events.throw > events.handoff, "mixed offense: %s" % str(events))
	assert_true(m.score[0] >= 0 and m.score[1] >= 0 and m.score[0] + m.score[1] <= 70, "score stays bounded: %s" % str(m.score))
	print("    two-minute bot game: %s, %s" % [str(m.score), str(events)])
