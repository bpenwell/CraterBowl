extends "res://tests/visual/harness.gd"
## #435: a bot defender jumps for a pass thrown over his head and gets a hand on it at the peak.
## Real main scene and AI: the defense holds still while the camera settles, then a bot CB stands
## 6 yd in front of the passer and the pass leaves at the height that clears a standing catch.
## Frames are counted from the throw (no wall clock); the camera settles first (#124).

const T := preload("res://src/sim/tuning.gd")
const PEAK_FRAME := 18   # JUMP_TIME / 2 at 60 Hz: the ball arrives as the jump tops out

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
	game.pov_enabled = false   # follow camera, so the defender in front of the passer is in frame
	var w = game.world
	game.series.start(0, 30.0)
	game.set_controlled(game.my_id)
	await _frames(5)
	_key(KEY_SPACE)
	check(w.phase == game.World.Phase.LIVE, "Space snaps")
	var me = w.get_athlete(game.controlled_id)
	for i in 120:
		if w.ball.is_held_by(me.id):
			break
		await physics_frame
	check(w.ball.is_held_by(me.id), "QB holds the snap")
	me.position = Vector2(40.0, 22.0)
	me.velocity = Vector2.ZERO
	me.facing = Vector2(0, 1)
	var cb = w.find_role(1, game.Athlete.Role.CB)
	cb.position = me.position + Vector2(0.0, 6.0)
	cb.velocity = Vector2.ZERO
	cb.facing = Vector2(0, -1)
	await _settle()
	check(cb.id != game.controlled_id and not game.roster.humans().has(cb.id), "the CB is a bot")

	# The pass: from the passer over the CB, reaching him at 3.0 yd in JUMP_TIME / 2.
	var t := T.JUMP_TIME * 0.5
	var z := 3.0
	cb.position = me.position + Vector2(0.0, 6.0)
	cb.velocity = Vector2.ZERO
	w.ball.hold(-1)
	w.ball.state = w.ball.State.IN_FLIGHT
	w.ball.position = Vector3(me.position.x, me.position.y, T.RELEASE_HEIGHT)
	w.ball.velocity = Vector3(0, 6.0 / t, (z - T.RELEASE_HEIGHT + 0.5 * w.gravity() * t * t) / t)
	w.forward_pass_thrown = true
	w.last_thrower_id = me.id
	w.throw_origin = me.position
	check(z > T.CATCH_MAX_HEIGHT, "the pass clears a standing catch (%.1f > %.1f yd)" % [z, T.CATCH_MAX_HEIGHT])
	game.ai.defense_enabled = true
	await _frames(2)   # the AI's next tick runs after this script's physics_frame signal
	check(cb.is_jumping(), "the bot CB jumps as the pass leaves")
	await _frames(PEAK_FRAME - 2)
	await RenderingServer.frame_post_draw
	check(cb.is_jumping() and cb.jump_height() > T.JUMP_HEIGHT * 0.9, "CB near the top of his jump (%.2f yd)" % cb.jump_height())
	check(w.ball.state != w.ball.State.IN_FLIGHT, "the jumping CB gets a hand on it (ball state %d)" % w.ball.state)
	await capture("bot-jump-contest")
	finish()

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	game._unhandled_key_input(ev)

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
