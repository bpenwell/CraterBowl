extends "res://tests/visual/harness.gd"
## #125 Slice B: Home shows each action once. No footer, keycaps on the controls they trigger,
## one launch button while a side panel is open, level only on the ring, status as a toast,
## last game as a Home card, Esc on Home asks before quitting.

func _initialize() -> void:
	_run.call_deferred()

## Visible Buttons under `root_node` whose text matches (case-insensitive).
func _visible_buttons(root_node: Node, text: String) -> Array:
	return root_node.find_children("*", "Button", true, false).filter(
		func(b): return b.is_visible_in_tree() and b.text.strip_edges().to_upper() == text.to_upper())

func _visible_labels_containing(root_node: Node, needle: String) -> Array:
	return root_node.find_children("*", "Label", true, false).filter(
		func(l): return l.is_visible_in_tree() and l.text.to_upper().contains(needle.to_upper()))

func _run() -> void:
	var launch = get_root().get_node("Launch")
	launch.settings_path = "user://test_home_layout_settings.cfg"
	launch.settings.player_name = "Ace"
	launch.last_match = {"score": [14, 21], "winner": 1, "my_team": 1, "team_names": ["HELIOS", "NEBULA"],
		"mode": "classic", "size": 5, "me": "Ace"}
	var menu = preload("res://scenes/menu.tscn").instantiate()
	menu.set_meta("force_menu", true)
	menu.profile_path = "user://test_home_layout_profile.json"
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.show_screen("home")
	for i in 10:
		await process_frame

	check(menu.find_child("Footer", true, false) == null, "no footer bar")
	check(_visible_buttons(menu, "Replays").size() == 1, "REPLAYS appears once on Home (top nav)")
	check(_visible_buttons(menu, "Controls").is_empty() and _visible_buttons(menu, "Quit").is_empty(),
		"Controls/Quit are not on Home (they live in Settings)")
	check(_visible_labels_containing(menu, "CHANGE MODE").is_empty(), "no free-floating ENTER/TAB hint")
	check(menu.play_button.find_child("KeyEnter", true, false) != null and menu.mode_button.find_child("KeyTab", true, false) != null,
		"shortcuts shown as keycaps on PLAY and CHANGE")
	check(menu.nav_buttons["home"].text == "HOME", "nav tab reads HOME, not a second PLAY")
	check(not menu.profile_sub.text.contains("LV"), "profile chip shows rank only; level lives on the ring")
	check(menu.level_ring.level == 1, "new players are Level 1")
	check(menu.last_game.is_visible_in_tree() and menu.last_game.text.contains("VICTORY 21–14"),
		"last game card on Home with your score first (%s)" % menu.last_game.text)
	var chip: Control = menu.music.widget
	check(chip == null or chip.is_visible_in_tree(), "now-playing chip on Home")
	await capture("home-consolidated")

	menu.show_screen("bots")
	for i in 40:
		await process_frame
	check(not menu.play_cluster.is_visible_in_tree(), "side panel open: Home PLAY + mode chip hidden")
	check(_visible_buttons(menu, "Kick off").size() == 1 and _visible_buttons(menu, "Play").is_empty(),
		"exactly one launch button on the VS BOTS screen")
	check(chip == null or not chip.is_visible_in_tree(), "now-playing chip hidden under panels")
	check(menu.panel.size.y < 400.0, "short panel fits its content (%.0f px tall)" % menu.panel.size.y)
	var pins_under_panel: Array = menu.lobby._pins.filter(func(p): return p[0].visible and p[0].get_rect().end.x > menu.panel.global_position.x)
	check(pins_under_panel.is_empty(), "no lobby pins under the open panel")
	check(menu.lobby._right_slots.all(func(n): return not n.visible), "teammates behind the panel are hidden")
	await capture("bots-panel-one-launch")

	menu.show_screen("leaders")
	await process_frame
	check(_visible_labels_containing(menu.content, "RANKED:").is_empty(), "leaderboard doesn't repeat the profile chip's rank")
	check(menu.content.get_child(0).text == "LEADERBOARD", "panel heading matches the nav label")

	menu.show_screen("home")
	await process_frame
	menu._status("Host disconnected")
	await process_frame
	check(menu.toast.is_visible_in_tree() and menu.status_label.text == "Host disconnected", "status shows as a toast")
	await capture("home-status-toast")
	menu._toast_timer.timeout.emit()
	check(not menu.toast.visible, "toast hides when its timer runs out")

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	await process_frame
	check(menu.current == "quit" and menu.content.find_child("ConfirmQuit", true, false) != null, "Esc on Home asks before quitting")
	for i in 40:   # let the lobby camera finish easing so the capture is reproducible
		await process_frame
	await capture("quit-confirm")
	root.push_input(esc)
	await process_frame
	check(menu.current == "home", "Esc again goes back home")

	menu.show_screen("settings")
	await process_frame
	check(menu.content.find_child("QuitGame", true, false) != null and not _visible_labels_containing(menu.content, "BUILD V").is_empty(),
		"Settings > About has build, report a bug, quit")
	launch.last_match = {}
	finish()
