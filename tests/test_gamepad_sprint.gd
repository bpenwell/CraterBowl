extends "res://tests/test_case.gd"
## #404: Gamepad state is idempotent across repeated trigger and button events.

class MatchLaunch extends "res://src/ui/launch.gd":
	func in_game() -> bool:
		return true

func test_duplicate_pad_samples_keep_the_other_sprint_control_held() -> void:
	var launch := MatchLaunch.new()
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_LEFT
	trigger.axis_value = 0.9
	_send(launch, trigger)
	_send(launch, trigger)
	assert_true(Input.is_key_pressed(KEY_SHIFT), "repeated LT press keeps sprint held")
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_LEFT_STICK
	button.pressed = true
	_send(launch, button)
	trigger.axis_value = 0.0
	_send(launch, trigger)
	_send(launch, trigger)
	assert_true(Input.is_key_pressed(KEY_SHIFT), "repeated LT release leaves L3 held")
	button.pressed = false
	_send(launch, button)
	assert_true(not Input.is_key_pressed(KEY_SHIFT), "sprint releases once the last control is up")
	launch.free()

func _send(launch: MatchLaunch, event: InputEvent) -> void:
	launch._input(event)
	Input.flush_buffered_events()
