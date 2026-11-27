extends "res://tests/visual/harness.gd"
## #131 in-match HUD declutter (and #168, the play clock's alarm colour). 5v5 classic, sim
## frozen (physics off) so every capture is exact state with the camera settled:
## - QB POV pre-snap: no mode line under the scorebug, no LOFT readout beside the crosshair
## - Tab held: the scoreboard's top line is the mode and size
## - coin toss you won: no phase word in the down cell, no key hints in the pill
## - kickoff as the kicker (J / click hint kept) and as the return team (no pill)
## - bot huddle at 5 s on defense: play clock not red; your own offense at 4 s: red

var game
var overlay

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.auto_replay = false
	game.opening_kickoff = false
	game.toss_cutscene = false   # these captures are about the HUD; the #129 cutscene has coin_toss_test.gd
	game.configure(5)
	game.ai.defense_enabled = false
	game.set_physics_process(false)
	overlay = game.pres.overlay
	var series = game.series
	var mine: int = game.world.get_athlete(game.my_id).team

	# QB POV, your ball, pre-snap.
	series.start(mine, 30.0)
	game.set_controlled(game.my_id)
	game.play_picker_open = false
	await _settle_pov()
	check(game.pov_active() and game.crosshair.visible, "QB is in the POV camera with the crosshair up")
	check(overlay.bug.is_visible_in_tree(), "scorebug is up")
	check(overlay.mode_l.text == "" and not overlay.mode_l.visible, "live HUD has no mode line (%s)" % overlay.mode_l.text)
	check(overlay.down_l.text == "1ST & 10", "down cell is down & distance (%s)" % overlay.down_l.text)
	var loft_px: int = await _crosshair_text_pixels()
	check(loft_px < 6, "no LOFT text drawn beside the crosshair (%d crosshair-yellow px)" % loft_px)
	var bug_h: float = overlay.bug.size.y
	await capture("hud-declutter-qb-pov")

	# Hold Tab: the mode and size live on the scoreboard.
	game.scoreboard_held = true
	await _refresh()
	var board: String = overlay.scoreboard_label.text
	check(overlay.scoreboard.is_visible_in_tree(), "Tab shows the scoreboard")
	check(board.begins_with("5v5 CLASSIC\n"), "Tab scoreboard leads with the mode and size (%s)" % board.get_slice("\n", 0))
	await capture("hud-declutter-tab-board")
	game.scoreboard_held = false

	# Play clock alarm (#168): red only on your own snap.
	series.clock.play_clock = 4.0
	await _refresh()
	check(series.play_clock_shown() == 4 and overlay.play_clock_l.label_settings.font_color == overlay.ALERT,
		"your offense at :04 reads red")
	series.start(1 - mine, 30.0)
	game.set_controlled(game.my_id)
	series.clock.play_clock = 4.0   # what their 5 s huddle reads a second in
	await _refresh()
	check(series.play_clock_shown() == 4, "bots' clock at :04 (%d)" % series.play_clock_shown())
	check(overlay.play_clock_l.label_settings.font_color == overlay.ACCENT, "bot huddle on defense is not red (%s)" % overlay.play_clock_l.text)

	# Coin toss you won: minimal prompt, no key hints, no COIN TOSS in the scorebug.
	series.start_match(mine, true)
	game.set_controlled(game.my_id)
	await _refresh()
	check(series.state == series.State.TOSS, "toss pending")
	check(overlay.down_l.text == "", "no COIN TOSS in the scorebug (%s)" % overlay.down_l.text)
	check(overlay.status_l.text == "YOU WON THE TOSS" and overlay.status_pill.visible, "toss pill without key hints (%s)" % overlay.status_l.text)
	check(not overlay.mode_l.visible, "no mode line during the toss")
	check(is_equal_approx(overlay.bug.size.y, bug_h), "scorebug keeps its height with the details row empty (%.0f vs %.0f)" % [overlay.bug.size.y, bug_h])
	game.scoreboard_held = true
	await _refresh()
	check(overlay.scoreboard_label.text.contains("COIN TOSS"), "Tab board still names the toss")
	game.scoreboard_held = false
	await _refresh()
	await capture("hud-declutter-coin-toss")

	# Kickoff, you kick: no KICKOFF chip; the kick hint stays (only place you learn J / click).
	series.start_match(1 - mine, false)
	series.choose_toss(series.toss_winner, "receive")   # #129: bots pick after the coin lands; skip ahead
	game.set_controlled(game.my_id)
	await _refresh()
	check(series.state == series.State.KICKOFF and game.world.offense_team == mine, "your kickoff")
	check(overlay.down_l.text == "", "no KICKOFF in the scorebug (%s)" % overlay.down_l.text)
	check(overlay.status_l.text == "PRESS J OR CLICK TO KICK", "kicker keeps the kick hint (%s)" % overlay.status_l.text)
	await capture("hud-declutter-kickoff-kicker")

	# Kickoff, you return: nothing to do yet, so no pill.
	series.start_match(mine, false)
	series.choose_toss(series.toss_winner, "receive")
	game.set_controlled(game.my_id)
	await _refresh()
	check(series.state == series.State.KICKOFF and game.world.offense_team != mine, "their kickoff")
	check(overlay.down_l.text == "" and overlay.status_l.text == "" and not overlay.status_pill.visible,
		"return team: no KICKOFF chip, no RETURN narration (%s | %s)" % [overlay.down_l.text, overlay.status_l.text])
	await capture("hud-declutter-kickoff-return")
	finish()

## Pixels in the crosshair's yellow (1.0, 0.9, 0.35) where the LOFT label used to be drawn
## (right of and below the centre: c + (22, 30) baseline, 16 px font).
func _crosshair_text_pixels() -> int:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var c: Vector2 = game.crosshair.get_global_rect().get_center()
	var n := 0
	for y in range(int(c.y) + 14, int(c.y) + 36):
		for x in range(int(c.x) + 20, int(c.x) + 100):
			var p := image.get_pixel(x, y)
			if p.r > 0.85 and p.g > 0.72 and p.b < 0.55 and p.r - p.b > 0.4:
				n += 1
	return n

## Run frames until the POV blend is done and the camera has stopped.
func _settle_pov() -> void:
	var last: Vector3 = game.camera.global_position
	for frame in 240:
		await process_frame
		var still: bool = game.camera.global_position.distance_to(last) < 0.0001
		last = game.camera.global_position
		if game.pov_w >= 1.0 and still:
			break
	await _refresh()

## Sim frozen: let the overlay text (10-20 Hz) and layout settle.
func _refresh() -> void:
	for frame in 30:
		await process_frame
