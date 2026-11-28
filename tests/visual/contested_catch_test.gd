extends "res://tests/visual/harness.gd"
## #339: the same pass can be won by either athlete, while a tight contest breaks it up.

const Tick := preload("res://src/sim/tick.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.opening_kickoff = false
	game.configure(3)
	game.pov_enabled = false
	game.set_physics_process(false)
	await process_frame
	game.set_process(false)
	game.pres.set_process(false)
	await _show_result(game, 0.0, 0.95, 0, "contest-receiver")
	await _show_result(game, -0.5, 0.5, -1, "contest-breakup")
	await _show_result(game, 0.95, 0.0, 1, "contest-interception")
	finish()

func _show_result(game, receiver_x: float, defender_x: float, winner: int, caption: String) -> void:
	game.series.start(0, 25.0)
	game.set_controlled(game.my_id)
	_key(game, KEY_SPACE)
	var w = game.world
	for a in w.athletes:
		a.position = Vector2(4.0, 22.0 + 3.0 * a.id)
	var qb = w.carrier()
	check(qb != null and qb.id == game.my_id, "Space gives the QB the ball")
	qb.position = Vector2(15.0, 20.0)
	var receiver = w.find_role(0, game.Athlete.Role.WR)
	var defender = w.find_role(1, game.Athlete.Role.CB)
	receiver.position = Vector2(15.0 + receiver_x, 40.0)
	defender.position = Vector2(15.0 + defender_x, 40.0)
	game.aim_point = Vector2(15.0, 40.0)
	_key(game, KEY_J)
	for tick in 90:
		if w.ball.state != w.Ball.State.IN_FLIGHT:
			break
		w.step({}, 1.0 / Tick.HZ)
	match winner:
		0: check(w.ball.is_held_by(receiver.id), "receiver square to the pass wins")
		1: check(w.ball.is_held_by(defender.id) and w.possession_team() == 1, "defender square to the pass wins")
		_: check(w.phase == w.Phase.DEAD and game.last_whistle == "BREAKUP", "the tight contest is a breakup")
	game._render()
	for view in game.views:
		view.interpolate(1.0)
	game.pres._update_ball(0.0, w)
	game.pres.overlay.refresh(game, 0.1)
	game.camera.position = Vector3(11.8, 3.6, -35.0)
	game.camera.look_at(Vector3(15.1, 1.0, -40.0))
	await capture(caption)

func _key(game, code: int) -> void:
	var input := InputEventKey.new()
	input.keycode = code
	input.pressed = true
	game._unhandled_key_input(input)
