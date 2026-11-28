extends "res://tests/visual/harness.gd"
## #341: a deflected ball ends the play in the air and rests on the turf during the dead-ball hold.

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
	game.series.start(0, 40.0)
	game.set_controlled(game.my_id)
	await process_frame
	_key(game, KEY_SPACE)
	var world = game.world
	for a in world.athletes:
		a.position = Vector2(25.0, 40.0 + a.id * 2.0)
	var qb = world.carrier()
	check(qb != null and qb.id == game.my_id, "Space snaps to the QB")
	qb.position = Vector2(12.0, 35.0)
	world.find_role(1, game.Athlete.Role.CB).position = Vector2(13.0, 45.0)
	game.aim_point = Vector2(12.0, 50.0)
	_key(game, KEY_J)
	for i in 40:
		world.step({}, 1.0 / Tick.HZ)
	check(game.last_whistle == "BREAKUP" and world.ball.holder_id < 0 and world.phase == game.World.Phase.DEAD,
		"the throw ends in a breakup with no carrier")
	var contact: Vector3 = world.ball.position
	check(contact.z > 0.3, "the sim ball died above the turf")
	game.set_process(false)
	game.pres.set_process(false)
	game._render()
	for view in game.views:
		view.interpolate(1.0)
	var visual_contact := Vector3(contact.x, contact.z, -contact.y)
	for i in Tick.HZ:
		# Main normally refreshes the interpolated position before Presentation updates per frame.
		game.ball_view.position = visual_contact
		game.pres._update_ball(1.0 / Tick.HZ, world)
	game.pres.overlay.refresh(game, 1.0)
	game.camera.position = Vector3(contact.x - 3.0, 2.8, -contact.y + 5.0)
	game.camera.look_at(Vector3(contact.x, 0.85, -contact.y))
	var resting := Vector3(contact.x, game.pres.Football.RADIUS, -contact.y)
	check(game.ball_view.position.is_equal_approx(resting), "the view rests on the turf at contact")
	check(game.pres.overlay.status_l.text == "PASS BROKEN UP", "the breakup ruling remains visible")
	await capture("breakup-ball-on-turf")
	finish()

func _key(game, code: int) -> void:
	var input := InputEventKey.new()
	input.keycode = code
	input.pressed = true
	game._unhandled_key_input(input)
