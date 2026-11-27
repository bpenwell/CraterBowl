extends "res://tests/visual/harness.gd"
## #136: the scorebug's play clock is the countdown the snap obeys. Runs the real scene's
## physics for a fixed number of 60 Hz ticks, then freezes it for the capture:
## - bot offense 2.5 s into its huddle (you on defense): PLAY :03, and it snaps when that hits 0
## - coin toss 2.5 s in: no play clock (the toss has its own window; the kickoff gets all 20 s)

const TICKS := 150   # 2.5 s of presnap at 60 Hz (mid-second: no rounding edge)

var game
var snap_clock := INF

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
	var series = game.series
	var overlay = game.pres.overlay
	var mine: int = game.world.get_athlete(game.my_id).team
	game.world.event.connect(func(n, _d): if n == "snap": snap_clock = series.clock.play_clock)

	# Bot offense vs you on defense.
	series.start(1 - mine, 30.0)
	game.set_controlled(game.my_id)
	await _ticks(TICKS)
	game.set_physics_process(false)
	await _refresh()
	var shown := _shown(series)
	check(game.world.phase == game.World.Phase.PRESNAP, "bots still huddling")
	check(shown == 3 and overlay.play_clock_l.text == "PLAY :03",
		"scorebug counts the bots' 5 s huddle (%s, %d)" % [overlay.play_clock_l.text, shown])
	check(overlay.play_clock_l.label_settings.font_color == overlay.ACCENT, "the bots' huddle is not the red alarm (#168)")
	await capture("play-clock-bot-huddle")
	game.set_physics_process(true)
	await _ticks(4 * 60)
	check(game.world.phase != game.World.Phase.PRESNAP, "bots snapped")
	check(snap_clock <= 0.0, "they snapped when the shown clock ran out (%.2f s left)" % snap_clock)

	# Coin toss: you won and haven't chosen yet.
	game.toss_seed = mine
	game.opening_kickoff = true
	series.start_match(mine, true)
	game.set_controlled(game.my_id)
	await _ticks(TICKS)
	game.set_physics_process(false)
	await _refresh()
	check(series.state == series.State.TOSS, "toss pending")
	check(_shown(series) == -1 and overlay.play_clock_l.text == "",
		"no play clock during the toss (%s)" % overlay.play_clock_l.text)
	check(absf(series.clock.play_clock - series.clock.PLAY_CLOCK) < 0.001, "play clock held for the kickoff")
	await capture("play-clock-coin-toss")
	finish()

## Match.play_clock_shown(), guarded so before_after.sh can run this test on an older base.
func _shown(series) -> int:
	return series.play_clock_shown() if series.has_method("play_clock_shown") else -99

func _ticks(n: int) -> void:
	for i in n:
		await physics_frame

## Physics is frozen here: let the overlay text (10-20 Hz) and camera easing settle.
func _refresh() -> void:
	for frame in 30:
		await process_frame
