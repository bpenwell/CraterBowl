extends "res://tests/visual/harness.gd"
## #381: a second down played during a hosted instant replay appears in the saved match.

const Tick := preload("res://src/sim/tick.gd")
const Replay := preload("res://src/sim/replay.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.opening_kickoff = false
	game.configure(3)
	game.auto_next = false
	game.pov_enabled = false
	game.ai.offense_enabled = false
	game.ai.defense_enabled = false
	game.replay_dir = "user://test_replay_recording"
	game._host_game(30000 + randi() % 20000, {"no_lobby": true})
	check(game.is_server(), "match is hosted")
	if not game.is_server():
		finish()
		return
	game.series.start(0, 25.0)
	game.set_controlled(game.my_id)
	_key(game, KEY_SPACE)
	_tick(game, 24)
	var world = game.world
	var qb = world.carrier()
	check(qb != null, "Space snapped the first play")
	if qb == null:
		finish()
		return
	qb.position.x = -0.5
	_tick(game, 2)
	_key(game, KEY_V)
	_key(game, KEY_SPACE)
	check(game.replay_active and game.replay.paused, "host paused the first instant replay")
	var clip_stop: float = game.replay.stop_at
	var clip_time: float = game.replay.time
	var first_frame: int = game.replay.frames.size()
	var first_tick: int = game.net_tick

	game.next_play()
	check(world.snap(), "another down snaps while the host watches")
	_tick(game, 2)
	qb = world.carrier()
	check(qb != null, "QB took the second snap")
	if qb == null:
		finish()
		return
	qb.position = Vector2(10.0, 45.0)
	_tick(game, 22)
	qb.position.x = -0.5
	_tick(game, 2)
	check(game.net_tick - first_tick == 26, "host stepped through the whole second play")
	check(game.replay.frames.size() - first_frame == 26 / Replay.FRAME_EVERY, "recorded frames at the normal rate")
	check(game.replay_active and game.replay.time == clip_time and game.replay.stop_at == clip_stop,
		"recording did not advance the paused clip or change its end")

	game.series.clock.half = 2
	game.series.clock.quarter = 4
	game.series.clock.remaining = 0.0
	game.next_play()
	check(game.series.is_final() and not game.saved_replay.is_empty(), "final saved the hosted match")
	check(game.open_replay(game.saved_replay), "opened the saved recording")
	if not game.replay_viewer or game.replay.plays.size() < 2:
		finish()
		return
	var play: Dictionary = game.replay.plays[1]
	check(play["start"] == first_frame and play["end"] > play["start"], "second down has a playable range on disk")
	_key(game, KEY_RIGHT)
	_key(game, KEY_PERIOD)
	var sample: Dictionary = game.replay.sample()
	check(game.replay.current_play() == 1 and sample.get("phase") == world.Phase.LIVE,
		"viewer seeks to a live frame of the second down")
	check((sample.get("ball", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(10.0, 45.0, game.T.BALL_CARRY_HEIGHT)),
		"saved frame shows the second play's ball position")
	var saved_frames: int = game.replay.frames.size()
	var last_live_tick: int = game.net_tick
	_tick(game, 4)
	check(game.net_tick == last_live_tick and game.replay.frames.size() == saved_frames,
		"saved viewer does not step or record the hosted world")
	game._render_replay()
	game._render_replay()
	game._replay_cam_cut = true
	game._replay_camera(Tick.DT)
	await capture("host-replay-recording-second-down")
	finish()

func _tick(game, count: int) -> void:
	for i in count:
		game._physics_process(Tick.DT)

func _key(game, code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	game._unhandled_key_input(ev)
