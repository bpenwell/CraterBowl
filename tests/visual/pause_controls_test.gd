extends "res://tests/visual/harness.gd"
## #134: Pause -> Controls is three short sections per tab (Keyboard & mouse, Gamepad, More) with
## key-cap chips, the player's bound keys, no footer wall, and it fits 1280x720 on every tab.
## #138 keys still checked: R dash, T timeout, C taunt, Q/E spin, F dive, Enter next play.

const Controls := preload("res://src/ui/controls.gd")

var launch

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.opening_kickoff = false
	game.series.start(0, 30.0)
	game.set_controlled(game.my_id)
	launch = root.get_node("/root/Launch")
	launch.settings.bindings = {}
	launch.pad_connected_override = false
	for i in 3:
		await process_frame

	# No pad: Keyboard & mouse tab, Move / Ball / Game sections, Gridiron default keys.
	var help = await _open()
	check(help.current_tab() == "keyboard", "no pad: keyboard tab opens (%s)" % help.current_tab())
	check(not help.pages["gamepad"].visible, "no pad: gamepad section hidden")
	var kb: Node = help.pages["keyboard"]
	for s in ["Move", "Ball", "Game"]:
		check(kb.get_node_or_null("Section_" + s) != null, "section %s present" % s)
	var shown: Dictionary = help.rows("keyboard")
	var want := {"Dash": ["R"], "Timeout": ["T"], "Taunt": ["C"], "Next play": ["ENTER"], "Spin": ["Q", "E"],
		"Dive / tackle": ["F"], "Handoff": ["G"], "Move": ["W", "A", "S", "D"], "Sprint": ["SHIFT"],
		"Snap": ["SPACE"], "Scoreboard": ["TAB"], "Replay": ["V"],
		"Throw": ["L-CLICK", "J"], "Block": ["R-CLICK"], "Aim / look": ["MOUSE"], "Jump": ["SPACE"], "Zoom": ["WHEEL"]}
	for label in want:
		check(shown.get(label, []) == want[label], "%s shows %s (%s)" % [label, want[label], shown.get(label, "missing")])
	for label in shown:
		check(label.find("(") < 0, "short label without parentheses: %s" % label)
	check(help.find_child("ControlsNotes", true, false) == null, "no footer wall of notes")
	_every_action_listed(help, {})
	_fits(help, "keyboard")
	await capture("pause-controls-gridiron")

	# More: the rarely-used keys (1/2, lob, kick call, pre-snap uses).
	help.buttons["more"].pressed.emit()
	await _settle()
	check(help.current_tab() == "more", "More tab opens")
	var more: Dictionary = help.rows("more")
	check(more.get("Extra point", []) == ["1"] and more.get("Two-point try", []) == ["2"] and more.get("Lob", []) == ["CTRL"],
		"More lists 1 / 2 / Ctrl (%s)" % str(more))
	_fits(help, "more")
	await capture("pause-controls-more")
	launch._close_overlay()

	# Pad connected + rebinds: Gamepad tab opens first; keyboard tab shows the rebound keys.
	launch.pad_connected_override = true
	launch.settings.bindings = Controls.rebind(Controls.rebind({}, "dash", KEY_X), "taunt", KEY_Z)
	await process_frame
	help = await _open()
	check(help.current_tab() == "gamepad" and help.pages["gamepad"].visible, "pad: gamepad section shown by default")
	var pad: Dictionary = help.rows("gamepad")
	check(pad.get("Throw", []) == ["RT"] and pad.get("Snap", []) == ["A"] and pad.get("Sprint", []) == ["LT", "L3"],
		"gamepad rows name pad inputs (%s)" % str(pad))
	_fits(help, "gamepad")
	await capture("pause-controls-gamepad")
	help.buttons["keyboard"].pressed.emit()
	await _settle()
	shown = help.rows("keyboard")
	check(shown.get("Dash", []) == ["X"] and shown.get("Taunt", []) == ["Z"], "rebinds shown: dash X, taunt Z (%s, %s)"
		% [shown.get("Dash"), shown.get("Taunt")])
	_every_action_listed(help, launch.settings.bindings)
	launch._close_overlay()
	launch.settings.bindings = {}
	launch.pad_connected_override = null
	finish()

func _open():
	launch.open_overlay()
	await process_frame
	launch._overlay.find_child("ControlsButton", true, false).pressed.emit()
	await _settle()
	return launch._overlay.find_child("ControlsHelp", true, false)

func _settle() -> void:
	for i in 3:
		await process_frame

## Every rebindable action appears on the Keyboard or More tab with its bound key.
func _every_action_listed(help, bindings: Dictionary) -> void:
	var chips := {}
	for id in ["keyboard", "more"]:
		var r: Dictionary = help.rows(id)
		for label in r:
			for k in r[label]:
				chips[k] = true
	for a in Controls.ACTIONS:
		var k := Controls.key_name(Controls.key_for(a[0], bindings)).to_upper()
		check(chips.has(k), "%s listed with its key %s" % [a[0], k])

## The whole pause panel sits inside 1280x720 with no scroll container.
func _fits(help, tab: String) -> void:
	var panel: Control = help.get_parent().get_parent()
	var rect := panel.get_global_rect()
	var screen := root.get_visible_rect()
	check(screen.encloses(rect), "%s tab fits on screen: %s in %s" % [tab, rect, screen.size])
	check(launch._overlay.find_children("*", "ScrollContainer", true, false).is_empty(), "%s tab: no scrolling" % tab)
