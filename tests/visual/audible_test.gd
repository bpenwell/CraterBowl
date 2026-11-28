extends "res://tests/visual/harness.gd"
## #346: pick a second call through the offense UI, then check the teammate's routes.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.opening_kickoff = false
	game.configure(3)
	game.auto_next = false
	game.set_physics_process(false)
	game.set_process(false)
	game.series.start(0, 25.0)
	game.set_controlled(game.my_id)
	game._render()
	for view in game.views:
		view.interpolate(1.0)
		view.set_process(false)
		view.anim.pause()
	var center: float = game.world.field.width / 2.0
	game.camera.global_position = Vector3(center, 24, -11)
	game.camera.look_at(Vector3(center, 0, -38))

	var overlay = game.pres.overlay
	overlay._refresh_picker(game, false)
	await process_frame
	await process_frame
	var slants := _card(overlay, "Slants")
	var flood := _card(overlay, "Flood")
	check(slants != null and flood != null, "the offense picker has Slants and Flood")
	if slants == null or flood == null:
		finish()
		return
	_click(slants)
	overlay._refresh_picker(game, false)
	game._render()
	check(game.world.play_name == "Slants" and slants.button_pressed, "click selects Slants")
	var original_routes: Dictionary = game.world.route_of.duplicate()
	var original_art: int = game.route_art._route_key
	check(game.route_mesh.get_surface_count() > 0, "Slants draw the original routes")
	await capture("first-call")

	_click(flood)
	overlay._refresh_picker(game, false)
	game._render()
	check(game.world.play_name == "Flood" and flood.button_pressed and not slants.button_pressed, "second click audibles to Flood")
	var updated_routes: Dictionary = game.world.route_of.duplicate()
	check(updated_routes != original_routes and game.route_art._route_key != original_art, "the audible redraws the routes")

	var qb: int = game.my_id
	var receiver = game.world.find_role(0, game.Athlete.Role.WR)
	game.my_id = receiver.id
	game.set_controlled(receiver.id)
	overlay._refresh_picker(game, false)
	game._render()
	check(flood.button_pressed and overlay.route_select.visible, "the teammate sees the call and their assignment")
	check(game.world.route_of == updated_routes and game.route_mesh.get_surface_count() > 0,
		"the teammate sees the updated routes")
	await capture("teammate-audible")

	game.my_id = qb
	game.set_controlled(qb)
	var snap := InputEventKey.new()
	snap.keycode = KEY_SPACE
	snap.pressed = true
	game._unhandled_key_input(snap)
	slants.pressed.emit()  # a queued press from the old picker still goes through the live guard
	overlay._refresh_picker(game, false)
	game._render()
	check(game.world.phase == game.World.Phase.LIVE and game.world.play_name == "Flood", "the audible is locked when Space snaps")
	check(not overlay.picker.visible and game.route_mesh.get_surface_count() == 0, "the live view hides the picker and routes")
	await capture("after-snap")
	finish()

func _card(overlay, text: String) -> Button:
	for button in overlay.picker_grid.get_children():
		if button.visible and button.text == text:
			return button
	return null

func _click(button: Button) -> void:
	var at := button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		root.push_input(event)
