extends "res://tests/visual/harness.gd"
## #374 / #198: replays animate the block push, the catch reach and the fair-catch signal.
## Each scene is staged on the live world (sim paused), recorded through replay.capture with
## player.gd replay_bits as main.gd does every tick, then the live state is cleared so only the
## recording can drive the pose. The replay pauses at a fixed frame and the blends settle before
## each check and capture, so the shots don't depend on frame timing.

const PlayerNode := preload("res://src/game/player.gd")
const Replay := preload("res://src/sim/replay.gd")
const Ball := preload("res://src/sim/ball.gd")
const SETTLE := 0.75   # s for the pose blends (CARRY_K = 14/s) to finish

var game
var world
var cam: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.opening_kickoff = false
	game.auto_next = false
	game.auto_replay = false
	game.pov_enabled = false
	game.series.start(0)
	game.set_controlled(game.my_id)
	game.input_override = Vector2.ZERO
	cam = Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	await physics_frame
	world = game.world
	await _block_part()
	await _catch_part()
	await _fair_catch_part()
	finish()

## Record `ticks` sim ticks; `step` poses the world before each. Returns the new play index.
func _stage(ticks: int, step: Callable) -> int:
	game.set_physics_process(false)
	var r = game.replay
	var start: int = r.frames.size()
	for t in ticks:
		step.call(t)
		r.capture(world, PlayerNode.replay_bits(world) if r.frame_due() else PackedByteArray())   # as main.gd
	r.plays.append({"start": start, "end": r.frames.size() - 1, "label": "staged"})
	return r.plays.size() - 1

## Replay play `i` at half speed up to `frames` frames in, pause on exactly that frame, settle, aim at `view`.
## `watch` runs every frame while it plays.
func _replay_to(i: int, frames: int, view, offset: Vector3, watch := Callable()) -> void:
	game.replay.clip_play(i, 0.5)
	game.replay_active = true
	game.set_physics_process(true)
	var at: float = float(game.replay.plays[i]["start"] + frames)
	for n in 600:
		_aim(view, offset)
		await process_frame
		if watch.is_valid():
			watch.call()
		if game.replay.time >= at:
			break
	game.replay.paused = true
	game.replay.time = at
	var t := 0.0
	while t < SETTLE:
		_aim(view, offset)
		await process_frame
		t += maxf(root.get_process_delta_time(), 1.0 / 240.0)

func _aim(view, offset: Vector3) -> void:
	var mid: Vector3 = view.global_position + Vector3.UP
	cam.global_position = mid + offset
	cam.look_at(mid)
	cam.make_current()

func _end_replay() -> void:
	game.stop_replay()
	await physics_frame
	await physics_frame   # main's tick after this one: sync()

## A blocker drives a defender back at 2 yd/s, engaged. Live they end unengaged.
func _block_part() -> void:
	var b = world.find_role(0, game.Athlete.Role.OL)
	var d = world.find_role(1, game.Athlete.Role.DL)
	var at := Vector2(world.field.width * 0.15, world.los_y - 25.0)   # open field, clear of the others
	var i := _stage(90, func(t: int) -> void:
		b.engaged_with = d.id
		d.engaged_with = b.id
		b.velocity = Vector2(0.0, 2.0)   # below PUSH_MAX_SPEED: a push
		d.velocity = b.velocity
		b.position = at + Vector2(0.0, 2.0 * t / 60.0)
		d.position = b.position + Vector2(0.0, 1.0))
	b.engaged_with = -1
	d.engaged_with = -1
	var bv = game.views[b.id]
	var dv = game.views[d.id]
	bv.rotation.y = 0.0   # facing up the field, at the defender (the view keeps its facing in a replay)
	dv.rotation.y = PI
	var backpedal := [false]   # the defender, driven back, backpedals while the replay moves
	await _replay_to(i, 25, bv, Vector3(-5.0, 1.2, 1.0), func() -> void:
		backpedal[0] = backpedal[0] or (dv._cur == "Jog_Fwd" and dv.anim.speed_scale < 0.0))
	var far = game.views[world.find_role(0, game.Athlete.Role.QB).id]
	check(bv.replay_flags & Replay.F_PUSH != 0, "the recording has the blocker engaged")
	check(bv.pose.push_weight > 0.9, "replayed blocker pushes with the upper body: %.2f" % bv.pose.push_weight)
	check(dv.pose.push_weight > 0.9, "replayed defender pushes back: %.2f" % dv.pose.push_weight)
	check(far.pose.push_weight < 0.01, "an unengaged view doesn't push: %.2f" % far.pose.push_weight)
	check(backpedal[0], "the defender driven back backpedals in the replay")
	await capture("replay-block-push")
	await _end_replay()
	check(bv.replay_flags == -1, "back live, views take the live athlete again")

## A pass drops onto a standing receiver's chest over 1 s. Live the ball ends back at the snap.
func _catch_part() -> void:
	var wr = world.find_role(0, game.Athlete.Role.WR)
	var at := Vector2(world.field.width * 0.5, world.los_y + 20.0)
	var chest := Vector3(at.x, at.y, PlayerNode.CATCH_HEIGHT)
	var from := chest + Vector3(0.0, -15.0, 0.8)
	var acc := Vector3(0.0, 0.0, -world.gravity())
	var v0 := (chest - from - 0.5 * acc) / 1.0   # lands on the chest after 1 s
	var ball = world.ball
	var keep_state = ball.state
	var keep_pos: Vector3 = ball.position
	var keep_vel: Vector3 = ball.velocity
	var i := _stage(60, func(t: int) -> void:
		var s := t / 60.0
		wr.position = at
		ball.state = Ball.State.IN_FLIGHT
		ball.position = from + v0 * s + 0.5 * acc * s * s
		ball.velocity = v0 + acc * s)
	ball.state = keep_state
	ball.position = keep_pos
	ball.velocity = keep_vel
	var wv = game.views[wr.id]
	wv.rotation.y = PI   # facing the throw (the view keeps its facing in a replay)
	await _replay_to(i, 27, wv, Vector3(-4.0, 1.0, -3.0))   # 0.9 s: the ball 1.5 yd out
	var qb = game.views[world.find_role(0, game.Athlete.Role.QB).id]
	check(wv.replay_flags & Replay.F_CATCH != 0, "the recording has the receiver reaching")
	check(wv.pose.catch_weight > 0.9, "replayed receiver raises his hands: %.2f" % wv.pose.catch_weight)
	check(wv.pose.catch_reach > 0.5, "and reaches for the ball: %.2f" % wv.pose.catch_reach)
	check(qb.pose.catch_weight < 0.01, "nobody else reaches: %.2f" % qb.pose.catch_weight)
	await capture("replay-catch-reach")
	await _end_replay()

## A returner stands under a kick signalling a fair catch. Live the signal is cleared.
func _fair_catch_part() -> void:
	var ret = world.find_role(1, game.Athlete.Role.S)
	var at := Vector2(world.field.width * 0.6, world.los_y + 30.0)
	var keep_phase = world.phase
	var i := _stage(60, func(_t: int) -> void:
		ret.position = at
		world.phase = game.World.Phase.LIVE
		world.fair_catch_id = ret.id)
	world.phase = keep_phase
	world.fair_catch_id = -1
	var rv = game.views[ret.id]
	await _replay_to(i, 15, rv, Vector3(-4.0, 1.5, -4.0))
	check(rv.fair_catch_shown and rv.fair_catch_label != null and rv.fair_catch_label.visible,
		"replayed returner shows the FAIR CATCH label")
	check(rv._cur == "Pistol_Aim_Up", "and the raised arm: %s" % rv._cur)
	await capture("replay-fair-catch")
	await _end_replay()
	await process_frame
	await process_frame   # process_frame fires before the views' _process
	check(not rv.fair_catch_shown and (rv.fair_catch_label == null or not rv.fair_catch_label.visible), "back live, the signal is gone")
