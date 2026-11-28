extends "res://tests/flow/segment.gd"
## #345: The QB selects Twins Right, snaps and resets for the next down.

var balanced_route_key := 0

func steps() -> Array:
	return [
		[1, func():
			main.opening_kickoff = false
			main.configure(3)
			main.auto_next = false
			main.pov_enabled = false
			main.series.start(0, 30.0)
			main.set_controlled(main.my_id)],
		[6, func():
			flow._key(KEY_Q)
			check(not main.play_picker_open, "Q closes the play picker")
			flow._key(KEY_Q)
			var menu = main.pres.overlay.formation_select
			check(main.play_picker_open and menu.selected == main.World.Formation.BALANCED, "opening the picker shows Balanced")
			balanced_route_key = main.route_art._route_key
			menu.item_selected.emit(main.World.Formation.TWINS_RIGHT)],
		[16, func():
			var w = main.world
			check(main.pres.overlay.formation_select.selected == w.Formation.TWINS_RIGHT, "the QB picker reflects the selected formation")
			var rx = w.receivers_in_order()
			check(rx[0].position.x > w.field.width * 0.5 and rx[1].position.x > rx[0].position.x, "both receivers are set on the right")
			check(main.route_art._route_key != balanced_route_key and main.route_mesh.get_surface_count() > 0, "the picker choice rebuilds route art")
			flow._key(KEY_SPACE)
			check(w.phase == w.Phase.LIVE, "Space snaps from Twins Right")],
		[36, func():
			flow._force_dead_if_live()
			flow._key(KEY_ENTER)
			check(main.world.offensive_formation() == main.World.Formation.BALANCED, "Enter advances to Balanced")],
	]
