extends "res://tests/visual/harness.gd"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.opening_kickoff = false
	game.toss_cutscene = false   # these captures are about the HUD; the #129 cutscene has coin_toss_test.gd
	var series = game.series
	series.start(0, 30.0)
	game.set_controlled(game.my_id)
	series.downs.apply({"type": "tackle", "spot": 34.0})
	series._setup_formation()
	series.clock.quarter = 4
	series.clock.remaining = 125.0
	check(series.clock.spend_timeout(0), "Helios can spend a timeout")
	series.clock.play_clock = 12.0
	var overlay = game.pres.overlay
	await _refresh()
	check(overlay.bug.is_visible_in_tree(), "match shows the scorebug")
	check(overlay.poss[0].modulate.a == 1.0 and overlay.poss[1].modulate.a == 0.0, "Helios possession is marked")
	check(overlay.clock_l.text == "Q4 2:05" and overlay.play_clock_l.text == "PLAY :12", "period, game time and play clock")
	check(overlay.timeout_pips[0].text == "●●○" and overlay.timeout_pips[1].text == "●●●", "both teams' timeouts")
	check(overlay.down_l.text == "2ND & 6" and overlay.spot_l.text == "HEL 34", "down, distance and named territory")
	check(overlay.mode_l.text == "" and not overlay.mode_l.visible, "no mode line in a match (#131: it is on the Tab board)")
	check(overlay.field_strip.is_visible_in_tree() and overlay.field_marks.is_equal_approx(Vector2(0.34, 0.4)), "field strip tracks LOS and line to gain")
	check(root.get_visible_rect().encloses(overlay.bug.get_global_rect()), "scorebug fits the viewport")
	check(not overlay.bug.get_global_rect().intersects(overlay.me_panel.get_global_rect()), "scorebug clears the movement meter")
	await capture("scorebug-scrimmage")

	series.start_match(0, false)
	series.choose_toss(series.toss_winner, "receive")   # #129: bots pick after the coin lands; skip ahead
	await _refresh()
	check(overlay.down_l.text == "" and not overlay.field_strip.visible, "kickoffs: no KICKOFF chip (#131) and no line-to-gain strip")
	await capture("scorebug-kickoff")

	series.start(1)
	series.last_result = {"type": "touchdown", "team": 1, "points": 6}
	series.next_play()
	await _refresh()
	check(overlay.down_l.text == "TRY FOR 1" and not overlay.field_strip.visible, "tries hide the line-to-gain strip")
	await capture("scorebug-try")
	finish()

func _refresh() -> void:
	for frame in 5:
		await process_frame
