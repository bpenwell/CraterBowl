extends "res://tests/visual/harness.gd"
## #389 stumble: a QB sprinting across a defender who dove and missed stumbles. Real main
## scene and sim: the LB dives across the lane and lies there; the QB sprints over him.
## Captures, counted in sim ticks from the stumble (one per frame at --fixed-fps 60), seen from
## the side where the lean reads best:
## - stumble-onset: 0.1 s in, the peak of the lean (upper body pitched, free arm out).
## - stumble-recover: 0.45 s in, nearly back in the run.
## - stumble-replay: the same 0.1 s moment rebuilt from the recording's flags alone (the live
##   athlete is long upright by then), via the real V instant replay (half speed), paused on that frame.

const T := preload("res://src/sim/tuning.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Replay := preload("res://src/sim/replay.gd")
const ONSET_TICK := 6     # 0.1 s: the lean's peak (stumble_pose.gd PEAK_T)
const RECOVER_TICK := 27  # 0.45 s
const SIDE := Vector3(-4.5, 0.4, 0.6)   # camera offset in the QB's frame (forward -Z): his left, a bit behind

var game
var world
var cam: Camera3D
var stumbles: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.auto_replay = false
	game.opening_kickoff = false
	game.toss_cutscene = false
	game.configure(7)
	game.pov_enabled = false
	game.ai.offense_enabled = false
	game.ai.defense_enabled = false
	game.series.start(0, 40.0)
	game.set_controlled(game.my_id)
	world = game.world
	world.event.connect(func(n, d): if n == "stumble": stumbles.append(d))
	cam = Camera3D.new()
	cam.fov = 45.0
	root.add_child(cam)
	await _ticks(5)
	_key(KEY_SPACE)
	check(world.phase == game.World.Phase.LIVE, "Space snaps")
	var lane := Vector2(world.field.width * 0.5, world.los_y + 14.0)   # open field past the line
	var lb = world.find_role(1, Athlete.Role.LB)
	lb.position = lane - Vector2(T.DIVE_SPEED * T.DIVE_TIME, 0.0)
	lb.velocity = Vector2.ZERO
	lb.facing = Vector2(1, 0)
	check(world.tackle(lb.id), "the LB dives across the lane")
	await _ticks(40)
	var qb = world.carrier()
	check(qb != null and qb.id == game.controlled_id, "the human QB holds the snap")
	check(lb.is_grounded() and lb.speed() < 0.01, "the diver missed and lies in the lane")
	qb.position = lb.position - Vector2(0.0, 3.5)
	game.input_override = Vector2(0, 1)
	game.sprint_override = true
	var view = game.views[qb.id]
	for i in 60:
		_aim(view)
		await physics_frame
		if not stumbles.is_empty():
			break
	check(stumbles.size() == 1 and stumbles[0]["id"] == qb.id and stumbles[0]["tier"] == Athlete.Stumble.STUMBLE,
		"sprinting square over the diver: one STUMBLE (%s)" % str(stumbles))

	await _ticks(ONSET_TICK - 1)   # capture() renders one more tick
	check(qb.speed() < T.STUMBLE_FLOOR * T.SPRINT_SPEED + 0.6, "onset: slowed (%.2f yd/s)" % qb.speed())
	check(view.stumble.weight > 0.9, "onset: full lean (%.2f)" % view.stumble.weight)
	check(view.stumble.anim_scale() < 0.7, "onset: the run clip slows (x%.2f)" % view.stumble.anim_scale())
	await capture("stumble-onset")

	await _ticks(RECOVER_TICK - ONSET_TICK - 1)
	check(view.stumble.weight > 0.02 and view.stumble.weight < 0.3, "recover: easing back (%.2f)" % view.stumble.weight)
	await capture("stumble-recover")

	await _ticks(40)
	check(not qb.is_stumbling() and view.stumble.weight == 0.0 and not view.stumble.active, "upright again: the layer is off")
	game.input_override = null
	game.sprint_override = null
	qb.position.x = -0.5   # step out: a real whistle ends the play for the instant replay
	await _ticks(3)
	check(world.phase == game.World.Phase.DEAD, "QB stepped out")
	await _replay_part(qb, view)
	finish()

## V replays the play; pause on the frame 0.1 s into the stumble, from its recorded bits.
func _replay_part(qb, view) -> void:
	var r = game.replay
	var i: int = r.last_play_index()
	var p: Dictionary = r.plays[i]
	var at := -1
	var best := 99
	for f in range(int(p["start"]), int(p["end"]) + 1):
		var st := Replay.stumble_of(int(r.frames[f][Replay.HEADER + qb.id * Replay.PER_ATHLETE + 2]))
		if st[0] == Athlete.Stumble.STUMBLE:
			var off := absi(roundi((Athlete.stumble_time(st[0]) - st[1]) * 60.0) - ONSET_TICK)
			if off < best:
				best = off
				at = f
	check(at >= 0 and best <= 1, "the recording has the stumble (frame %d, %d ticks off)" % [at, best])
	_key(KEY_V)
	check(game.replay_active, "V starts the instant replay")
	for n in 600:
		_aim(view)
		await process_frame
		if r.time >= at:
			break
	# Pause on the frame and capture at once: the lean comes from the frame's bits and needs no
	# settling, while the view still runs (a settled pause drops to the Idle clip, as live never does).
	r.paused = true
	r.time = float(at)
	_aim(view)
	await process_frame
	check(view.replay_flags >= 0 and qb.stumble_t == 0.0, "the pose comes from the recording, not the live athlete")
	check(view.stumble.weight > 0.9, "replay: full lean from the flags alone (%.2f)" % view.stumble.weight)
	await capture("stumble-replay")
	_key(KEY_V)

func _aim(view) -> void:
	var mid: Vector3 = view.global_position + Vector3.UP
	cam.global_position = mid + Basis(Vector3.UP, view.global_rotation.y) * SIDE   # his left, whatever his facing
	cam.look_at(mid)
	cam.make_current()

## n sim ticks (frames at --fixed-fps 60), the camera following the QB.
func _ticks(n: int) -> void:
	for i in n:
		if game.controlled_id >= 0 and game.views.size() > game.controlled_id:
			_aim(game.views[game.controlled_id])
		await physics_frame

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	game._unhandled_key_input(ev)
