extends "res://tests/visual/harness.gd"
## #133: the scorebug's timeout indicators are drawn bars, not "●○" text. One bar per timeout
## the match allows; available bars are lit in the team color, used bars are hollow and dim.
## Captures 3/3, 2/3 and 0/3 for both teams, checks the pixels under each bar, that the bug
## keeps its fixed width, and that drills hide the indicators.
## Base-tolerant: before_after.sh carries this file to origin/main (text pips) to photograph
## the "before"; there the meter checks fail but the captures still run.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.opening_kickoff = false
	game.toss_cutscene = false
	var series = game.series
	series.start(0, 30.0)
	game.set_controlled(game.my_id)
	series.downs.apply({"type": "tackle", "spot": 34.0})
	series._setup_formation()
	series.clock.quarter = 1   # no SWITCH ENDS banner over the bug
	series.clock.remaining = 125.0
	series.clock.play_clock = 12.0
	var overlay = game.pres.overlay
	check(series.clock.timeout_limit == 3, "5v5 match allows three timeouts a half")
	var meters = overlay.get("timeout_meters")
	check(meters is Array and meters.size() == 2, "overlay has a timeout meter per team")
	if not meters is Array:
		meters = []

	await _refresh(meters)
	if meters.size() == 2:
		var font: Font = overlay._abbr_l[0].label_settings.font
		var size: int = overlay._abbr_l[0].label_settings.font_size
		for team in overlay.Teams.ROSTER:
			var code_w := font.get_string_size(team["code"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			check(meters[0].get_combined_minimum_size().x <= code_w, "meter footprint (%d px) is no wider than the %s code (%d px): the bug never grows" % [meters[0].get_combined_minimum_size().x, team["code"], code_w])
	check(_glyph_pips(overlay.bug).is_empty(), "no ●/○ text pips on the scorebug %s" % [_glyph_pips(overlay.bug)])
	await _state(game, overlay, meters, 3, "timeouts-3-3")

	for t in 2:
		check(series.clock.spend_timeout(t), "team %d spends a timeout" % t)
	await _settle(meters, true)
	await _state(game, overlay, meters, 2, "timeouts-2-3")

	for t in 2:
		series.clock.spend_timeout(t)
		series.clock.spend_timeout(t)
	series.score = [21, 35]   # two-digit scores: the bars run under the score's left edge
	await _settle(meters, true)
	await _state(game, overlay, meters, 0, "timeouts-0-3")

	series.clock.reset()   # halftime refills: no pulse for a gain
	await _refresh(meters)
	check(meters.all(func(m): return not m.pulsing() and m.left == 3), "refilled timeouts light up without a pulse")

	game.start_practice("passing")
	await _refresh(meters)
	check(game.drill != null and meters.all(func(m): return not m.is_visible_in_tree()), "drills hide the timeout meters")
	finish()

## Assert both teams show `left` of 3, sample each bar's pixels, then capture.
func _state(game, overlay, meters: Array, left: int, name: String) -> void:
	check(is_equal_approx(overlay.bug.size.x, overlay.BUG_W), "scorebug keeps its fixed %d px width at %d/3 (%.1f)" % [overlay.BUG_W, left, overlay.bug.size.x])
	await capture(name)
	if meters.size() != 2:
		return
	var img := root.get_texture().get_image()
	var bug_rect: Rect2 = overlay.bug.get_global_rect()
	for t in 2:
		var m = meters[t]
		var team_color: Color = game.TEAM_COLORS[t]
		check(m.is_visible_in_tree() and m.limit == 3 and m.left == left, "team %d meter shows %d of 3 (%d/%d)" % [t, left, m.left, m.limit])
		check(bug_rect.encloses(m.get_global_rect()), "team %d meter sits inside the scorebug" % t)
		for i in 3:
			var r: Rect2 = m.bar_rect(i)
			check(r.size.x >= 14.0 and r.size.y >= 7.0, "bar %d is at least 14×7 px (the old 11 px glyph was a ~7 px dot)" % i)
			var g := Rect2(m.get_global_rect().position + r.position, r.size)
			check(bug_rect.encloses(g), "team %d bar %d is inside the scorebug" % [t, i])
			check(not g.intersects(overlay.poss[t].get_global_rect()) and not g.intersects(overlay.team_logo[t].get_global_rect()), "team %d bar %d clears the logo and possession mark" % [t, i])
			check(g.position.y >= overlay._abbr_l[t].get_global_rect().end.y - 4.0, "team %d bar %d sits under the team code" % [t, i])
			var c := img.get_pixelv(Vector2i(m.get_global_rect().position + r.get_center()))
			var lit: bool = i < left
			check(m.is_available(i) == lit, "team %d bar %d is %s" % [t, i, "available" if lit else "used"])
			if lit:
				check(_dist(c, team_color) < 0.12, "team %d bar %d is lit in the team color (%s vs %s)" % [t, i, c, team_color])
			else:
				check(c.v < 0.35 and _dist(c, team_color) > 0.5, "team %d bar %d is hollow/dim (%s)" % [t, i, c])

func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

## Labels under `node` still drawing timeout glyphs.
func _glyph_pips(node: Node) -> Array:
	var out := []
	for c in node.find_children("*", "Label", true, false):
		if c.text.contains("●") or c.text.contains("○"):
			out.append(c.text)
	return out

## Let the overlay tick, then wait out any pulse so the capture is the settled state.
func _settle(meters: Array, expect_pulse: bool) -> void:
	for frame in 5:
		await process_frame
	if meters.size() == 2:
		check(meters.all(func(m): return m.pulsing()) == expect_pulse, "spending a timeout pulses its bar")
	await _refresh(meters)

func _refresh(meters: Array) -> void:
	for frame in 5:
		await process_frame
	var guard := 0
	while meters.size() == 2 and meters.any(func(m): return m.pulsing()) and guard < 300:
		guard += 1
		await process_frame
