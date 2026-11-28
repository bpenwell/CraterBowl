extends SceneTree
## Host the normal net smoke scenario, then give the joiner's team one possession
## so the client can exercise a handoff as the quarterback.

var main
var saw_live := false
var threw_opening_pass := false
var presnap_time := 0.0
var prepared_handoff := false
var set_quarters := false
var reported_ids := false
var replay_start_tick := -1
var replay_start_frame := 0
var replay_start_position := Vector2.ZERO

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)

func _physics_process(dt: float) -> bool:
	if prepared_handoff or not main.is_server():
		return false
	if main.in_lobby():
		if not set_quarters:
			_key(KEY_Q)   # #130: no-op now (halves are gone); the client checks the lobby stayed quarters
			_key(KEY_H)   # 2.5 -> 3-min quarters
			_key(KEY_I)   # #108: disable the pass landing marker in the hosted match
			set_quarters = true
		return false
	if not reported_ids:   # match started: the joiner's install id came in through the lobby (#102)
		reported_ids = true
		for peer in main.peer_installs:
			print("NET host got install id %s" % main.peer_installs[peer])
	if main.world.phase == main.World.Phase.LIVE:
		saw_live = true
		if not threw_opening_pass and main.world.ball.is_held_by(main.my_id):
			_throw_opening_pass()
	if saw_live and main.world.phase == main.World.Phase.DEAD and replay_start_tick < 0:
		_key(KEY_V)
		_key(KEY_SPACE)
		assert(main.replay_active and main.replay.paused, "host paused the instant replay")
		replay_start_tick = main.net_tick
		replay_start_frame = main.replay.frames.size()
		replay_start_position = main.world.get_athlete(main.controlled_id).position
		main.input_override = Vector2.RIGHT
		main.sprint_override = true
	if replay_start_tick >= 0 and main.net_tick == replay_start_tick + 12:
		assert(main.replay.frames.size() - replay_start_frame == 12 / main.Replay.FRAME_EVERY,
			"host recorded all six frames while the real client was connected")
		var local_athlete = main.world.get_athlete(main.controlled_id)
		assert(local_athlete.position.is_equal_approx(replay_start_position), "host movement was neutral while recording")
		main.input_override = null
		main.sprint_override = null
		_key(KEY_V)
	if saw_live and main.world.phase == main.World.Phase.PRESNAP:
		presnap_time += dt
		if presnap_time >= 2.0:
			main.series.start(1)
			main.ai.defense_enabled = false
			prepared_handoff = true
			main.world.event.connect(_finish_after_handoff)
	return false

## Give the real client a pass with pressure and no receiver near the aim point.
func _offer_grounding_throw() -> void:
	const Tick := preload("res://src/sim/tick.gd")
	main.series.start(1, 42.0)
	var world = main.world
	var qb = world.find_role(1, main.Athlete.Role.QB)
	world.start_live_with(qb.id)
	qb.position = Vector2(26.0, 37.0)
	world.find_role(0, main.Athlete.Role.LB).position = qb.position + Vector2(2.0, 0.0)
	world.step({}, 1.0 / Tick.HZ)
	for frame in 120:
		if world.forward_pass_thrown:
			break
		await physics_frame

func _throw_opening_pass() -> void:
	threw_opening_pass = true
	var world = main.world
	var qb = world.carrier()
	var tipper = world.find_role(1, main.Athlete.Role.LB)
	for a in world.athletes:
		a.position = Vector2(30.0, 25.0 + 3.0 * a.id)
		a.velocity = Vector2.ZERO
	qb.position = Vector2(12.0, world.los_y - 5.0)
	tipper.position = qb.position + Vector2(0.0, 4.25)
	world.throw(qb.id, qb.position + Vector2(0.0, 6.0), main.T.PLAYER_PASS_POWER)

func _finish_after_handoff(event: String, _data: Dictionary) -> void:
	if event != "handoff":
		return
	main.world.event.disconnect(_finish_after_handoff)
	# Let the joiner observe the handoff before setting up the final score.
	await create_timer(0.5).timeout
	_send_contested_interception()
	await _send_sideline_results()
	await _show_dead_ball_drop()
	_record_retreated_keeper()
	await create_timer(0.45).timeout
	await _offer_grounding_throw()
	main.stats.award_stats.clear()
	_record_pass_before_seat_replacement()
	_record_run_before_seat_replacement()
	_record_fumbled_keeper()
	main.series.start(0, 95.0)
	main.world.event.emit("snap", {"qb": main.my_id})
	main.world.event.emit("touchdown", {"carrier": main.my_id, "spot": Vector2(26, 100), "team": 0, "points": 6})
	main.series.score = [6, 0]
	main.series.clock.half = 2
	main.series.clock.quarter = 4
	main.series.clock.remaining = 0.0
	main.world.phase = main.World.Phase.DEAD
	main.series.last_result = {"type": "incomplete"}
	main.next_play()

## Resolve the live sim race against a receiver and let its event reach the client.
func _send_contested_interception() -> void:
	main.series.start(0, 25.0)
	var w = main.world
	var qb = w.find_role(0, main.Athlete.Role.QB)
	for a in w.athletes:
		a.position = Vector2(4.0, 22.0 + 3.0 * a.id)
	qb.position = Vector2(20.0, 20.0)
	w.find_role(0, main.Athlete.Role.WR).position = Vector2(20.95, 40.0)
	w.find_role(1, main.Athlete.Role.CB).position = Vector2(20.0, 40.0)
	w.start_live_with(qb.id)
	assert(w.throw(qb.id, Vector2(20.0, 40.0), main.T.PLAYER_PASS_POWER))
	for tick in 90:
		if w.ball.state != w.Ball.State.IN_FLIGHT:
			break
		w.step({}, 1.0 / w.Tick.HZ)

## Same airborne pass, opposite rulings based on where the receiver stands.
func _send_sideline_results() -> void:
	var w = main.world
	for receiver_x in [0.55, -0.55]:
		main.series.start(0, 25.0)
		var qb = w.find_role(0, main.Athlete.Role.QB)
		for a in w.athletes:
			a.position = Vector2(32.0, 26.0 + 2.0 * a.id)
		qb.position = Vector2(5.0, 20.0)
		w.start_live_with(qb.id)
		assert(w.throw(qb.id, Vector2(-0.75, 38.0), 0.8))
		for tick in 100:
			if w.ball.position.x < -0.2 or w.phase == w.Phase.DEAD:
				break
			w.step({}, 1.0 / w.Tick.HZ)
		w.find_role(0, main.Athlete.Role.WR).position = Vector2(receiver_x, w.ball.position.y)
		w.step({}, 1.0 / w.Tick.HZ)
		await create_timer(0.25).timeout

## Broadcast an elevated breakup and leave the dead-ball hold on screen for the client.
func _show_dead_ball_drop() -> void:
	main.series.start(0, 40.0)
	var w = main.world
	var qb = w.find_role(0, main.Athlete.Role.QB)
	for a in w.athletes:
		a.position = Vector2(30.0, 25.0 + 3.0 * a.id)
	qb.position = Vector2(12.0, 35.0)
	w.find_role(1, main.Athlete.Role.CB).position = Vector2(13.0, 45.0)
	w.start_live_with(qb.id)
	assert(w.throw(qb.id, Vector2(12.0, 50.0), main.T.PLAYER_PASS_POWER))
	var saved_auto_next: bool = main.auto_next
	main.auto_next = false
	await create_timer(1.6).timeout
	main.auto_next = saved_auto_next

## Let the real client observe the host's crossing state after it has retreated.
func _record_retreated_keeper() -> void:
	main.series.start(1, 37.0)
	var world = main.world
	var qb = world.find_role(1, main.Athlete.Role.QB)
	world.start_live_with(qb.id)
	qb.position = Vector2(6.0, world.los_y + 2.0)
	world.step({}, 1.0 / world.Tick.HZ)
	qb.position.y = world.los_y - 3.0
	world.step({}, 1.0 / world.Tick.HZ)

## Give the real client the QB seat between another player's throw and catch.
func _record_pass_before_seat_replacement() -> void:
	main.series.start(1, 25.0)
	var world = main.world
	var qb = world.find_role(1, main.Athlete.Role.QB)
	var receiver = world.find_role(1, main.Athlete.Role.WR)
	var slot: int = main.roster.slot_of_athlete(qb.id)
	var replacement: int = main.roster.slots[slot]["owner"]
	var original := 99
	assert(replacement > 1 and replacement != original)
	main.roster.release(replacement)
	main.roster.claim(original, slot)
	world.event.emit("snap", {"qb": qb.id})
	world.event.emit("throw", {"by": qb.id})
	main.roster.release(original)
	main.roster.claim(replacement, slot)
	world.event.emit("catch", {"by": receiver.id})
	var defender = world.find_role(0, main.Athlete.Role.LB)
	receiver.position = Vector2(5.0, 45.0)
	defender.position = receiver.position
	world._fumble(receiver, defender)
	world.ball.position.z = 0.0
	world._step_loose(0.0)
	world.event.emit("out_of_bounds", {"carrier": defender.id, "spot": Vector2(0, 50), "team": 0})

## Replace the keeper after the snap, then leave the field for a 10-yard gain.
func _record_run_before_seat_replacement() -> void:
	main.series.start(1, 25.0)
	var world = main.world
	var qb = world.find_role(1, main.Athlete.Role.QB)
	var slot: int = main.roster.slot_of_athlete(qb.id)
	var replacement: int = main.roster.slots[slot]["owner"]
	var original := 99
	main.roster.release(replacement)
	main.roster.claim(original, slot)
	world.snap()
	while world.snap_in_flight():
		world.step({}, 1.0 / world.Tick.HZ)
	main.roster.release(original)
	main.roster.claim(replacement, slot)
	qb.position = Vector2(-0.5, 35.0)
	world.step({}, 1.0 / world.Tick.HZ)

## The current QB earns this carry even though the defense recovers.
func _record_fumbled_keeper() -> void:
	main.series.start(1, 25.0)
	var world = main.world
	var qb = world.find_role(1, main.Athlete.Role.QB)
	var defender = world.find_role(0, main.Athlete.Role.LB)
	world.snap()
	while world.snap_in_flight():
		world.step({}, 1.0 / world.Tick.HZ)
	qb.position = Vector2(5.0, world.los_y + 7.0)
	defender.position = qb.position
	world._fumble(qb, defender)
	world.ball.position.z = 0.0
	world._step_loose(0.0)
	defender.position.x = -0.5
	world.step({}, 1.0 / world.Tick.HZ)

func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	main._unhandled_key_input(event)
