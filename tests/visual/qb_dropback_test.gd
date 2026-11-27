extends "res://tests/visual/harness.gd"
## #252: real snap and keyboard input for a one-second QB sprint at two depths.

const DT := 1.0 / 60.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.auto_next = false
	game.opening_kickoff = false
	game.pov_enabled = false
	game.ai.defense_enabled = false
	game.series.start(0, 40.0)
	game.set_controlled(game.my_id)
	game.cam_yaw = 0.0
	var snap := InputEventKey.new()
	snap.keycode = KEY_SPACE
	snap.pressed = true
	game._unhandled_key_input(snap)
	for i in 30:
		game._physics_process(DT)
	var qb = game.world.carrier()
	if qb == null or qb.id != game.controlled_id:
		check(false, "human QB received the snap")
		finish()
		return
	check(true, "human QB received the snap")
	var label := _evidence_label()

	var pocket := _retreat(game, qb, 4.0)
	check(absf(pocket - 9.5) < 0.01, "pocket sprint travels %.2f yd (expected 9.50)" % pocket)
	label.text = "POCKET DROPBACK\nHeld S + Shift for 1 s from 4 yd behind the line\nRetreated %.2f yd" % pocket
	await _settle(game)
	await capture("pocket")

	var deep := _retreat(game, qb, 14.0)
	check(deep > 7.0 and deep < 8.0, "deep sprint travels %.2f yd (expected 7–8)" % deep)
	check(absf(qb.speed() - 6.175) < 0.01, "deep sprint reaches the 6.18 yd/s floor")
	label.text = "DEEP DROPBACK\nHeld S + Shift for 1 s from 14 yd behind the line\nRetreated %.2f yd, ending at %.2f yd/s" % [deep, qb.speed()]
	await _settle(game)
	await capture("deep")
	finish()

func _retreat(game, qb, depth: float) -> float:
	var start_y: float = game.world.los_y - depth
	qb.position.y = start_y
	qb.stamina = 1.0
	_hold(KEY_S, true)
	_hold(KEY_SHIFT, true)
	for i in 60:
		game._physics_process(DT)
	_hold(KEY_S, false)
	_hold(KEY_SHIFT, false)
	return start_y - qb.position.y

func _hold(code: int, pressed: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = pressed
	Input.parse_input_event(key)
	Input.flush_buffered_events()

func _settle(game) -> void:
	game._render()
	for view in game.views:
		view.interpolate(1.0)
	for i in 6:
		await process_frame
	game.cam_yaw = game._camera_target_yaw()
	game.camera_follow = game.player.global_position
	game._update_camera(DT)

func _evidence_label() -> Label:
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var label := Label.new()
	label.position = Vector2(32, 124)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)
	return label
