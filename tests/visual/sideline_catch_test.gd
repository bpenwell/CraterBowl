extends "res://tests/visual/harness.gd"
## #338: mirror the landing position of the receiver across a fixed sideline pass.

const Tick := preload("res://src/sim/tick.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.opening_kickoff = false
	game.configure(3)
	game.auto_next = false
	game.pov_enabled = false
	game.set_physics_process(false)
	await process_frame
	game.set_process(false)
	game.pres.set_process(false)
	await _capture_catch(game, 0.55, "sideline-feet-in")
	await _capture_catch(game, -0.55, "sideline-feet-out")
	finish()

func _capture_catch(game, receiver_x: float, key: String) -> void:
	game.series.start(0, 25.0)
	game.set_controlled(game.my_id)
	var w = game.world
	_key(game, KEY_SPACE)
	check(w.ball.is_held_by(game.my_id), "Space gives the QB the ball")
	for a in w.athletes:
		a.position = Vector2(24.0, 25.0 + 2.0 * a.id)
	w.carrier().position = Vector2(5.0, 20.0)
	game.aim_point = Vector2(-0.75, 38.0)
	_key(game, KEY_J)
	for i in 100:
		if w.ball.position.x < -0.2 or w.phase == w.Phase.DEAD:
			break
		w.step({}, 1.0 / Tick.HZ)
	check(w.ball.state == w.Ball.State.IN_FLIGHT and w.ball.position.x < 0.0,
		"J pass is still in flight outside the sideline")
	var receiver = w.find_role(0, game.Athlete.Role.WR)
	var contact_y: float = w.ball.position.y
	receiver.position = Vector2(receiver_x, contact_y)
	w.step({}, 1.0 / Tick.HZ)
	if receiver_x > 0.0:
		check(w.ball.is_held_by(receiver.id) and w.phase == w.Phase.LIVE, "in-bounds feet give the receiver possession")
	else:
		check(w.ball.holder_id < 0 and game.last_whistle == "INCOMPLETE", "out-of-bounds feet are ruled incomplete")
	game._render()
	for view in game.views:
		view.interpolate(1.0)
	game.pres._update_ball(0.0, w)
	game.pres.overlay.refresh(game, 0.1)
	game.camera.position = Vector3(-4.8, 3.2, -contact_y - 4.5)
	game.camera.look_at(Vector3(0.0, 0.85, -contact_y))
	await capture(key)

func _key(game, code: int) -> void:
	var input := InputEventKey.new()
	input.keycode = code
	input.pressed = true
	game._unhandled_key_input(input)
