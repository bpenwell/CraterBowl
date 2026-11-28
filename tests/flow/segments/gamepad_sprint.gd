extends "res://tests/flow/segment.gd"
## #404: Switch between LT and L3 without interrupting the athlete's sprint.

var previous_scene: Node

func setup() -> void:
	main.configure(7)
	main.pov_enabled = false
	main.opening_kickoff = false
	main.ai.defense_enabled = false
	main.series.start(0, 40.0)
	main.set_controlled(main.my_id)
	previous_scene = main.get_tree().current_scene
	main.get_tree().current_scene = main   # Launch translates gamepad input in the match scene

func steps() -> Array:
	return [
		[3, func(): flow._key(KEY_SPACE)],
		[29, func(): _axis(JOY_AXIS_LEFT_Y, -1.0); _axis(JOY_AXIS_TRIGGER_LEFT, 0.9)],
		[31, func(): _check_sprint(true, "LT starts sprint")],
		[33, func(): _l3(true)],
		[35, func(): _l3(false)],
		[37, func(): _check_sprint(true, "releasing L3 leaves LT sprinting")],
		[39, func(): _axis(JOY_AXIS_TRIGGER_LEFT, 0.0)],
		[41, func(): _check_sprint(false, "releasing LT last ends sprint")],
		[43, func(): _l3(true)],
		[45, func(): _check_sprint(true, "L3 starts sprint")],
		[47, func(): _axis(JOY_AXIS_TRIGGER_LEFT, 0.9)],
		[49, func(): _axis(JOY_AXIS_TRIGGER_LEFT, 0.0)],
		[51, func(): _check_sprint(true, "releasing LT leaves L3 sprinting")],
		[53, func(): _l3(false)],
		[55, _finish],
	]

func _check_sprint(expected: bool, message: String) -> void:
	var athlete = main.world.get_athlete(main.controlled_id)
	check(athlete.last_sprinting == expected, message)

func _finish() -> void:
	_check_sprint(false, "releasing L3 last ends sprint")
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	main.get_tree().current_scene = previous_scene

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
