extends "res://tests/visual/harness.gd"
## AI arms follow-up to #246: athletes ran with both hands out in two more cases.
## 1. Replays: views move along the recording, but player.gd picked clips from the live
##    athlete, frozen at the whistle. A block still engaged then played Push (arms out) for
##    the whole replay while the athlete ran his route; a tackled athlete slid on his back.
##    Now a replayed view uses the recorded flags (player.gd replay_flags) and its motion.
## 2. Live: an engaged blocker and defender moving at sprint pace together played the Push
##    clip, sprinting with both hands stuck out. Now the push is an upper-body layer
##    (athlete_pose.gd) over the leg clip, and only below PUSH_MAX_SPEED.

const LOCOMOTION := ["Idle", "Jog_Fwd", "Sprint"]

var game
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
	var world = game.world
	# A real pass play to replay: snap, let the routes develop, throw deep.
	_key(KEY_SPACE)
	check(world.phase == game.World.Phase.LIVE, "Space snaps")
	for i in 60:
		await physics_frame
	var qb = world.carrier()
	var wr = world.find_role(0, game.Athlete.Role.WR)
	var from := Vector3(qb.position.x, qb.position.y, game.T.RELEASE_HEIGHT)
	game.aim_point = game.Passing.lead_target(from, wr.position, wr.velocity, game.T.PLAYER_PASS_POWER)
	_key(KEY_J)
	check(world.forward_pass_thrown, "J throws the deep pass")
	for i in 600:
		if world.phase == game.World.Phase.DEAD:
			break
		await physics_frame
	check(world.phase == game.World.Phase.DEAD, "the play ends")
	await _replay_part(world, wr.id)
	await _block_speed_part(world)
	finish()

## Replay the play with the live athletes left in states that put the arms out: every one
## engaged in a block, some lying on the turf, one celebrating. Moving replay views must run.
func _replay_part(world, follow: int) -> void:
	_key(KEY_V)
	check(game.replay_active, "V starts the instant replay")
	var n: int = world.athletes.size()
	for a in world.athletes:
		a.engaged_with = (a.id + 1) % n
		if a.id % 3 == 0:
			a.recover_t = 100.0   # tackled: lying on the turf in the live sim
	game.views[follow].celebrate("flip")
	var view = game.views[follow]
	var moving := 0    # view-frames checked: a replay view running with no recorded dive or fall
	var bad := []      # "id:clip" of moving views in a clip that isn't running
	var max_catch := 0.0   # catch pose on a view whose recording never reaches for the ball in this play (#374)
	var reached := {}
	var clip: Dictionary = game.replay.plays[game.replay.current_play()]
	for fi in range(clip["start"], clip["end"]):
		var fr: PackedFloat32Array = game.replay.frames[fi]
		for id in game.replay.athlete_count():
			if int(fr[game.Replay.HEADER + id * game.Replay.PER_ATHLETE + 2]) & game.Replay.F_CATCH:
				reached[id] = true
	var flourish := 0.0
	var shot := false
	while game.replay_active:
		cam.global_position = view.global_position + Vector3(4.5, 2.0, 0.0)
		cam.look_at(view.global_position + Vector3.UP)
		cam.make_current()
		await process_frame
		var rec: Array = game.replay.sample().get("flags", [])   # recorded flags (replay.gd F_*)
		for v in game.views:
			if not reached.has(v.athlete.id):
				max_catch = maxf(max_catch, v.pose.catch_weight)
			if rec.size() <= v.athlete.id or rec[v.athlete.id] & 3 != 0 or Vector2(v._vel.x, v._vel.z).length() < 3.0:
				continue
			moving += 1
			if v._cur not in LOCOMOTION and bad.size() < 8:
				bad.append("%d:%s" % [v.athlete.id, v._cur])
		flourish = maxf(flourish, view.body.rotation.length() + view.body.position.length())
		if not shot and rec.size() > follow and rec[follow] & 3 == 0 and Vector2(view._vel.x, view._vel.z).length() > 3.5:   # half-speed replay
			shot = true
			await capture("replay-arms-running")
	check(moving > 200, "replay views run with no recorded dive or fall (%d view-frames)" % moving)
	check(bad.is_empty(), "they run with the arm pump, not the live block / turf clips: %s" % [bad])
	check(max_catch < 0.01, "no catch pose from the live sim in a replay: %.2f" % max_catch)
	check(flourish < 0.01, "a live celebration doesn't flip a replayed runner: %.2f" % flourish)
	check(shot, "captured the receiver running in the replay")
	for a in world.athletes:
		a.engaged_with = -1
		a.recover_t = 0.0
	await physics_frame
	await physics_frame   # main's tick after this one: sync()
	check(game.views[follow].replay_flags == -1, "back live, views take the live athlete again")

## An engaged pair moving together: jog legs and Push arms while they grind, the plain run at sprint pace.
## The sim is paused and the pair is moved by hand, so the speed is exact.
func _block_speed_part(world) -> void:
	game.set_physics_process(false)
	var b = world.find_role(0, game.Athlete.Role.OL)
	var d = world.find_role(1, game.Athlete.Role.DL)
	b.position = Vector2(world.field.width * 0.15, world.los_y - 25.0)   # open field, clear of the others
	d.position = b.position + Vector2(0.0, 1.0)
	var bv = game.views[b.id]
	var fast_clip := await _drive(b, d, 9.0, 45, "block-at-speed-arms")
	var fast_push: float = bv.pose.push_weight
	var slow_clip := await _drive(b, d, 3.0, 45, "block-push-upper-body")
	var slow_push: float = bv.pose.push_weight
	check(fast_clip == "Sprint" and fast_push < 0.05, "an engaged pair at 9 yd/s sprints, arms pumping: %s, push %.2f" % [fast_clip, fast_push])
	check(slow_clip == "Jog_Fwd", "an engaged pair at 3 yd/s jogs (legs): %s" % slow_clip)
	check(slow_push > 0.9, "and pushes with the upper body: push %.2f" % slow_push)
	var dv = game.views[d.id]
	var fwd_b := Vector2(-sin(bv.rotation.y), -cos(bv.rotation.y))   # view forward (x, -z) in world
	var fwd_d := Vector2(-sin(dv.rotation.y), -cos(dv.rotation.y))
	check(fwd_b.dot(fwd_d) < -0.9, "the pair face each other while pushing: %.2f" % fwd_b.dot(fwd_d))
	check(dv._cur == "Jog_Fwd" and dv.anim.speed_scale < 0.0, "the defender driven back backpedals: %s at %.2f" % [dv._cur, dv.anim.speed_scale])
	check(bv.PUSH_MAX_SPEED > 2.0 and bv.PUSH_MAX_SPEED < 9.0, "PUSH_MAX_SPEED between the two")
	game.set_physics_process(true)

## Move blocker b and defender d up the field at `speed` for `frames` ticks, engaged.
## Returns the blocker's clip at the end; captures `shot` there if given.
func _drive(b, d, speed: float, frames: int, shot: String) -> String:
	var bv = game.views[b.id]
	for i in frames:
		for a in [b, d]:
			a.engaged_with = d.id if a == b else b.id
			a.velocity = Vector2(0.0, speed)
			a.position += a.velocity / 60.0
		game._render()
		var mid: Vector3 = bv.global_position + Vector3(0.0, 1.0, -0.5)   # between blocker and defender
		cam.global_position = mid + Vector3(-5.0, 1.2, 1.0)
		cam.look_at(mid)
		cam.make_current()
		await physics_frame
	if shot != "":
		await capture(shot)
	return bv._cur

func _key(code: int) -> void:
	var input := InputEventKey.new()
	input.keycode = code
	input.pressed = true
	game._unhandled_key_input(input)
