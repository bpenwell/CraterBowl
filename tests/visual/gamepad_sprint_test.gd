extends "res://tests/visual/harness.gd"
## #404: the athlete keeps sprinting with LT after releasing the left-stick button.

var game

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(404)
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.auto_replay = false
	game.opening_kickoff = false
	game.ai.defense_enabled = false
	game.pov_enabled = false
	game.series.start(0, 40.0)
	game.set_controlled(game.my_id)
	await _frames(3)
	var snap := InputEventKey.new()
	snap.keycode = KEY_SPACE
	snap.pressed = true
	game._unhandled_key_input(snap)
	await _frames(26)
	_axis(JOY_AXIS_LEFT_Y, -1.0)
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.9)
	_l3(true)
	await _frames(3)
	var runner = game.world.get_athlete(game.controlled_id)
	check(runner.last_sprinting, "the athlete sprints with both controls held")
	var start: Vector3 = game.player.target_position()
	_l3(false)
	await _frames(19)
	check(runner.last_sprinting, "the athlete keeps sprinting after L3 release")
	check(runner.speed() >= game.T.SPRINT_SPEED - 0.01, "the athlete keeps sprint speed on LT")
	game.set_physics_process(false)
	game.set_process(false)
	game.camera.fov = 46.0
	game.camera.look_at_from_position(start + Vector3(-6, 4, 4), start + Vector3(0, 0.8, -2), Vector3.UP)
	await capture("sprint-after-l3-release")
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	finish()

func _frames(count: int) -> void:
	for frame in count:
		await physics_frame

func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _l3(down: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_LEFT_STICK
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()
