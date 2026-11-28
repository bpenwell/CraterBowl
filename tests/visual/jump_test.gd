extends "res://tests/visual/harness.gd"
## #379 jump: in live play the real Space key hops the controlled player. Three named
## frames counted from the key press (no wall clock): takeoff (Jump_Start, small lift),
## peak (the rig's looping "Jump" clip, body lifted ~JUMP_HEIGHT) and landing (Jump_Land right after touchdown).
## Real main scene, real key path, real sim; the defense holds still and the player stands
## alone in the backfield. The camera settles before the jump (#124).

const T := preload("res://src/sim/tuning.gd")
const TAKEOFF_FRAME := 5    # of 36 in the air: inside the Jump_Start third
const PEAK_FRAME := 18      # mid-air: the arc's top
const LANDING_FRAME := 39   # touchdown at 36; Jump_Land holds ~11 frames

var game

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.opening_kickoff = false
	game.configure(7)
	game.ai.defense_enabled = false
	game.pov_enabled = false   # follow camera: the passer's POV would hide his own jump
	var w = game.world
	game.series.start(0, 30.0)
	game.set_controlled(game.my_id)
	await _frames(5)
	_key(KEY_SPACE)
	check(w.phase == game.World.Phase.LIVE, "Space snaps")
	var me = w.get_athlete(game.controlled_id)
	me.position = Vector2(40.0, 22.0)   # open backfield, clear of the line and the routes
	me.velocity = Vector2.ZERO
	me.facing = Vector2(0, 1)
	for i in 120:   # the snap reaches the QB first: jump with the ball in hand
		if w.ball.is_held_by(me.id):
			break
		await physics_frame
	check(w.ball.is_held_by(me.id), "QB holds the snap")
	await _settle()
	var nearest := INF
	for a in w.athletes:
		if a.id != me.id:
			nearest = minf(nearest, a.position.distance_to(me.position))
	check(nearest > 4.0, "nobody within 4 yd of the jumper (%.1f yd)" % nearest)
	var view = game.views[me.id]
	var s0: float = me.stamina
	_key(KEY_SPACE)
	check(me.is_jumping(), "Space jumps in live play")
	check(absf(s0 - me.stamina - T.JUMP_STAMINA) < 0.001, "jump costs JUMP_STAMINA")

	await _after(TAKEOFF_FRAME - 1)
	check(me.is_jumping(), "takeoff: in the air")
	check(view._cur == "Jump_Start", "takeoff: Jump_Start clip (%s)" % view._cur)
	check(view.body.position.y > 0.1 and view.body.position.y < 0.6, "takeoff: small lift (%.2f)" % view.body.position.y)
	check(view.anim.current_animation == view._cur, "takeoff: the rig plays %s (%s)" % [view._cur, view.anim.current_animation])
	await capture("jump_takeoff")

	await _after(PEAK_FRAME - TAKEOFF_FRAME - 1)
	check(me.is_jumping(), "peak: in the air")
	check(view._cur == "Jump", "peak: looping Jump clip (%s)" % view._cur)
	check(view.body.position.y > 0.7, "peak: body lifted near JUMP_HEIGHT (%.2f)" % view.body.position.y)
	check(view.anim.current_animation == view._cur, "peak: the rig plays %s (%s)" % [view._cur, view.anim.current_animation])
	await capture("jump_peak")

	await _after(LANDING_FRAME - PEAK_FRAME - 1)
	check(not me.is_jumping(), "landing: back on the ground")
	check(view._cur == "Jump_Land", "landing: Jump_Land clip (%s)" % view._cur)
	check(is_zero_approx(view.body.position.y), "landing: no lift left (%.2f)" % view.body.position.y)
	check(view.anim.current_animation == view._cur, "landing: the rig plays %s (%s)" % [view._cur, view.anim.current_animation])
	await capture("jump_landing")
	finish()

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	game._unhandled_key_input(ev)

## n more frames, then wait for the last one's _process and draw so checks see what renders.
## (capture() itself adds one frame.)
func _after(n: int) -> void:
	await _frames(n)
	await RenderingServer.frame_post_draw

## Run frames until the camera has stopped moving, so captures don't depend on frame counts.
func _settle() -> void:
	var last: Transform3D = game.camera.global_transform
	var still := 0
	for frame in 400:
		await process_frame
		var t: Transform3D = game.camera.global_transform
		still = 0 if t.origin.distance_to(last.origin) > 0.0001 or not t.basis.is_equal_approx(last.basis) else still + 1
		last = t
		if still >= 3:
			print("VISUAL INFO camera settled after %d frames" % frame)
			break

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
