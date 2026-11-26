extends "res://tests/visual/harness.gd"
## #116 in-game polish: fixed-width scorebug, player-facing dead-ball line in a pill on the
## scorebug's edge (not the raw whistle code over the player), themed play picker pinned
## top-right, movement meters beside the scorebug.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.opening_kickoff = false
	var series = game.series
	series.start(0, 30.0)
	game.set_controlled(game.my_id)
	series._setup_formation()
	game.play_picker_open = true
	var overlay = game.pres.overlay
	var w = game.world
	await _refresh()
	var vp: Rect2 = root.get_visible_rect()
	var presnap_w: float = overlay.bug.size.x
	check(overlay.play_clock_l.visible and overlay.play_clock_l.text.begins_with("PLAY :"), "presnap shows the play clock")
	check(overlay.picker.visible and overlay.picker.theme != null, "picker uses the menu theme")
	var b: Button = overlay.picker_grid.get_child(0)
	check(b.get_theme_font("font") != ThemeDB.fallback_font and b.get_theme_font("font") == overlay.picker.theme.default_font, "picker buttons use the theme font, not Godot's default")
	var pr: Rect2 = overlay.picker.get_global_rect()
	check(pr.end.x <= vp.end.x and pr.position.y >= 0.0 and pr.end.y < vp.size.y * 0.45, "picker pinned in the top-right, off the field (%s)" % pr)
	check(not overlay.me_panel.get_global_rect().intersects(overlay.bug.get_global_rect()) and overlay.me_panel.get_global_rect().end.x <= overlay.bug.get_global_rect().position.x, "movement meters sit beside the scorebug")
	await capture("hud-presnap")

	# The snap: the play clock cell goes away but the bug keeps its width.
	overlay.on_event("snap", {"qb": game.my_id})
	w.phase = w.Phase.LIVE
	await _refresh()
	check(not overlay.play_clock_l.visible and not overlay.play_clock_div.visible, "live play hides the play clock cell and its divider")
	check(is_equal_approx(overlay.bug.size.x, presnap_w), "scorebug width is the same live and presnap (%.0f vs %.0f)" % [overlay.bug.size.x, presnap_w])

	# Whistle: QB dropped 5 yd behind the line without a throw = a sack.
	var los: float = w.los_y
	overlay.on_event("tackle", {"carrier": game.my_id, "team": w.offense_team, "spot": Vector2(10.0, los - 5.0)})
	game.last_whistle = "TACKLE"
	w.phase = w.Phase.DEAD
	await _refresh()
	check(overlay.status_l.text != game.last_whistle, "dead ball is not the raw whistle code (%s)" % overlay.status_l.text)
	check(overlay.status_l.text == "SACK  ·  -5", "dead ball summary reads SACK · -5 (%s)" % overlay.status_l.text)
	check(is_equal_approx(overlay.bug.size.x, presnap_w), "scorebug width unchanged at the whistle")
	var sp: Rect2 = overlay.status_pill.get_global_rect()
	check(overlay.status_pill.visible and sp.end.y <= overlay.bug.get_global_rect().position.y and not sp.intersects(overlay.bug.get_global_rect()), "status pill sits on top of the scorebug, not over it")
	await capture("hud-whistle")

	check(overlay.whistle_summary("INCOMPLETE", w) == "INCOMPLETE", "incomplete pass")
	overlay.on_event("snap", {"qb": game.my_id})
	overlay.on_event("tackle", {"carrier": game.my_id + 1, "team": w.offense_team, "spot": Vector2(10.0, los + 3.2)})
	check(overlay.whistle_summary("TACKLE", w) == "TACKLED  ·  +3", "run tackled for a gain (%s)" % overlay.whistle_summary("TACKLE", w))
	finish()

func _refresh() -> void:
	for frame in 5:
		await process_frame
