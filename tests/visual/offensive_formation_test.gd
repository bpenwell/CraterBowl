extends "res://tests/visual/harness.gd"
## #345: open the formation popup and select Twins Right in the QB's picker.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.opening_kickoff = false
	game.configure(5)
	game.auto_next = false
	game.pov_enabled = false
	game.set_physics_process(false)
	game.series.start(0, 30.0)
	game.set_controlled(game.my_id)
	await process_frame
	game.set_process(false)
	var ov = game.pres.overlay
	var menu: OptionButton = ov.get("formation_select") if "formation_select" in ov else null
	_settle(game)
	await process_frame
	check(menu != null and menu.is_visible_in_tree() and menu.selected == 0, "QB starts with Balanced selected")
	await capture("formation-balanced")
	if menu != null:
		_click(menu.get_global_rect().get_center())
		await process_frame
		var popup := menu.get_popup()
		check(popup.visible, "clicking the formation picker opens its popup")
		if popup.visible:
			var second_row := Vector2(popup.position) + Vector2(popup.size) * Vector2(0.5, 0.74)
			_click(second_row)
			await process_frame
		check(not popup.visible, "confirming Twins Right closes the popup")
		_settle(game)
		var w = game.world
		var wideouts = w.receivers_in_order()
		check(menu.selected == 1 and wideouts[0].position.x > w.field.width * 0.5 and wideouts[1].position.x > wideouts[0].position.x,
			"both wideouts line up on the right and the picker shows the choice")
		check(game.route_mesh.get_surface_count() > 0, "route art is visible from the selected lineup")
	await capture("formation-twins-right")
	finish()

func _settle(game) -> void:
	game._render()
	for view in game.views:
		view.interpolate(1.0)
	game.camera.position = Vector3(20.0, 17.0, -12.0)
	game.camera.look_at(Vector3(20.0, 0.0, -37.0))
	game.pres.overlay.refresh(game, 0.1)

func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		root.push_input(ev)
