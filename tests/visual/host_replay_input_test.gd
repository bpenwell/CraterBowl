extends "res://tests/visual/harness.gd"
## #386: the host's live athlete waits for the replay controls to return to the match.

const Tick := preload("res://src/sim/tick.gd")

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
	game.ai.offense_enabled = false
	game.ai.defense_enabled = false
	game.pov_enabled = false
	game._host_game(30000 + randi() % 20000, {"no_lobby": true})
	check(game.is_server(), "match is hosted")
	if not game.is_server():
		finish()
		return
	game.series.start(0, 40.0)
	_key(game, KEY_SPACE)
	_ticks(game, 24)
	var world = game.world
	var qb = world.carrier()
	check(qb != null, "QB has the first snap")
	if qb == null:
		finish()
		return
	qb.position.x = -0.5
	_ticks(game, 2)
	_key(game, KEY_V)
	_key(game, KEY_SPACE)
	check(game.replay_active and game.replay.paused, "host paused the replay")
	game.next_play()
	check(world.snap(), "the next down started while the clip is paused")
	var receiver = world.find_role(0, game.Athlete.Role.WR)
	game.set_controlled(receiver.id)
	receiver.position = Vector2(10.0, 35.0)
	var at: Vector2 = receiver.position
	var start_tick: int = game.net_tick
	game.input_override = Vector2.RIGHT
	game.sprint_override = true
	_ticks(game, 12)
	check(not receiver.last_sprinting, "sprint stays idle")
	_mouse_shield(true)
	check(Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT), "held the real shield mouse button")
	_ticks(game, 12)
	check(not receiver.blocking, "shield stays idle")
	_mouse_shield(false)
	check(receiver.position.is_equal_approx(at), "host athlete did not move during the replay")
	check(game.net_tick - start_tick == 24 and world.phase == world.Phase.LIVE, "the live world kept ticking")

	_key(game, KEY_V)
	game.set_process(false)
	game._render()
	game.views[receiver.id].interpolate(1.0)
	var focus := Vector3(at.x + 1.0, 0.8, -at.y)
	game.camera.look_at_from_position(focus + Vector3(0.0, 5.0, 7.0), focus)
	await capture("host-replay-input-on-exit")
	_ticks(game, 24)
	check(not game.replay_active and receiver.position.x > at.x + 1.0 and receiver.last_sprinting,
		"the same held movement and sprint work after V exits the clip")
	finish()

func _ticks(game, count: int) -> void:
	for i in count:
		game._physics_process(Tick.DT)

func _key(game, code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_key_input(event)

func _mouse_shield(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
