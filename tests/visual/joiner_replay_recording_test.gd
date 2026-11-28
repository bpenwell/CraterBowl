extends "res://tests/visual/harness.gd"
## #384: a real loopback joiner can replay a down that ran while its earlier clip was paused.

const NetSession := preload("res://src/net/net_session.gd")
const Protocol := preload("res://src/net/protocol.gd")
const Replay := preload("res://src/sim/replay.gd")
const Tick := preload("res://src/sim/tick.gd")

var game
var hosted_match
var host := NetSession.new()
var tick := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.opening_kickoff = false
	game.configure(3)
	game.pov_enabled = false
	var world = game.World.new()
	game.Roster.new().build(world, 3)
	hosted_match = game.Match.new(world)
	hosted_match.start(0, 25.0)
	root.add_child(host)
	host.match_size = 3
	var port := 30000 + randi() % 20000
	var result := host.host(port, func(_peer): return 3, func(_peer): pass)
	check(result == OK, "loopback host bound its port")
	if result != OK:
		finish()
		return
	world.event.connect(host.broadcast_event)
	game._join_game("127.0.0.1", port, {})
	for frame in 120:
		if game.net.my_athlete >= 0:
			break
		await process_frame
	check(game.net.my_athlete == 3, "real client joined the host")
	if game.net.my_athlete != 3:
		finish()
		return
	await _advance(4)

	check(world.snap(), "first down snapped")
	await _advance(24)
	var qb = world.carrier()
	if qb == null:
		check(false, "first snap reached its QB")
		finish()
		return
	qb.position.x = -0.5
	await _advance(6)
	check(game.world.phase == world.Phase.DEAD, "joiner received the first dead-ball state")
	_key(KEY_V)
	check(game.replay_active and not game.replay.last_play().is_empty(), "V opens the first hosted play on the joiner")
	if not game.replay_active:
		# Keep testing the capture branch on a base that cannot open the first clip.
		game.replay.play_range(0, game.replay.frames.size() - 1)
		game.replay_active = true
	_key(KEY_SPACE)
	var clip_cursor: float = game.replay.time
	var frames_before: int = game.replay.frames.size()
	var input_seq: int = game.predictor.seq

	hosted_match.next_play()
	await _advance(4)
	check(world.snap(), "next down snapped during the paused clip")
	await _advance(2)
	qb = world.carrier()
	if qb == null:
		check(false, "second snap reached its QB")
		finish()
		return
	qb.position = Vector2(10.0, 45.0)
	await _advance(24)
	qb.position.x = -0.5
	await _advance(6)
	check(game.replay.frames.size() - frames_before == 36 / Replay.FRAME_EVERY, "joiner records at the normal rate during playback")
	check(game.replay.paused and game.replay.time == clip_cursor and game.predictor.seq == input_seq,
		"the clip cursor and outgoing movement sequence stay paused")
	check(game.replay.last_play_index() == 1 and game.replay.last_play().get("end", 0) > game.replay.last_play().get("start", 0),
		"second down has its own recorded range")
	_key(KEY_V)
	_key(KEY_V)
	check(game.replay_active and game.replay.current_play() == 1, "V opens the second down once it finishes")
	if game.replay_active:
		_key(KEY_PERIOD)
		game.replay.step_frames(9)
		check(is_equal_approx(game.replay.sample()["ball"].y, 45.0), "the second clip shows the actual position received from the host")
		game._render_replay()
		game._render_replay()
		game._replay_cam_cut = true
		game._replay_camera(Tick.DT)
	else:
		game._render()
	await capture("joiner-replay-recording-second-down")
	finish()

func _advance(count: int) -> void:
	for i in count:
		tick += 1
		hosted_match.world.step({}, Tick.DT)
		if tick % Replay.FRAME_EVERY == 0:
			host.broadcast_snapshot(Protocol.encode_snapshot(hosted_match, tick))
		await process_frame
		game._physics_process(Tick.DT)

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	game._unhandled_key_input(ev)
