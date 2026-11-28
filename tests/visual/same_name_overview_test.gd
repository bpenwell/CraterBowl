extends "res://tests/visual/harness.gd"
## #200: two players named Ann finish a match with different stat lines. The lobby's
## "Your game" panel shows only the local Ann's own lines, never the other Ann's.

const Athlete := preload("res://src/sim/athlete.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var launch = root.get_node("Launch")
	launch.settings_path = "user://test_same_name_overview_settings.cfg"   # never leak the name into later cases
	launch.settings.player_name = "Ann"
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.opening_kickoff = false
	await process_frame
	game.player_name = "Ann"
	game.profile = game.Cosmetics.new()
	game.profile_path = "user://test_same_name_overview_profile.json"
	game.leaderboard_path = "user://test_same_name_overview_leaderboard.json"
	game.replay_dir = "user://test_same_name_overview_replays"
	game.lobby.players[99] = {"name": "Ann", "ready": true}
	var rival: int = game.roster.auto_assign_team(99, 1)
	check(rival >= 0 and game.owner_name(rival) == game.owner_name(game.my_id), "opponents share the name Ann")
	var w = game.world
	var me = w.get_athlete(game.my_id)
	var series = game.series
	series.start(0, 40.0)   # HELIOS (local Ann) has the ball
	var wr = w.find_role(0, Athlete.Role.WR)   # offensive roles exist once HELIOS has the ball
	check(wr != null and me.role == Athlete.Role.QB, "local Ann is HELIOS's QB with a receiver to throw to")
	# Local Ann completes one of two passes for 12 yards; the other Ann tackles and breaks one up.
	w.event.emit("snap", {"qb": me.id})
	w.event.emit("throw", {"by": me.id})
	w.event.emit("catch", {"by": wr.id})
	w.event.emit("tackle", {"by": rival, "carrier": wr.id, "spot": Vector2(26, 52), "team": 0})
	w.event.emit("snap", {"qb": me.id})
	w.event.emit("throw", {"by": me.id})
	w.event.emit("breakup", {"by": rival})
	# Local Ann keeps it in from the 5 on the last play, then the final whistle (real path).
	series.start(0, 95.0)
	w.event.emit("snap", {"qb": me.id})
	w.event.emit("touchdown", {"carrier": me.id, "spot": Vector2(26, 100), "team": 0, "points": 6})
	series.score = [6, 0]
	series.clock.quarter = 4
	series.clock.remaining = 0.0
	w.phase = game.World.Phase.DEAD
	series.last_result = {"type": "incomplete"}
	game.next_play()
	var rival_pos: String = game.stats.ROLE.get(w.get_athlete(rival).role, "?")
	print("summary (name-keyed): %s" % str(game.summary_lines))
	check(game.summary_lines.any(func(l): return str(l).begins_with("Ann %s:" % rival_pos) and str(l).contains("tkl")),
		"the name-keyed summary keeps the other Ann's %s line" % rival_pos)

	var ov: Dictionary = game.match_overview()
	var mine: Array = ov["my_lines"]
	print("my_lines: %s" % str(mine))
	check(mine.size() == 1 and str(mine[0]).begins_with("QB: 1/2 12yd 0TD 0INT | 1 car 5yd 1TD"),
		"Your game holds only local Ann's QB line: %s" % str(mine))
	check(not mine.any(func(l): return str(l).contains("tkl") or str(l).contains("pbu")),
		"none of the other Ann's tackle or breakup is in Your game")

	launch.go_to_menu("", ov)
	for frame in 5:
		await process_frame
	var menu = current_scene
	check(menu != null and menu.scene_file_path == launch.MENU_SCENE and menu.current == "overview", "lobby opens the game overview")
	var view = menu.content.find_child("GameOverview", true, false) if menu else null
	var line: Label = null
	var leaked := false
	for l in view.find_children("*", "Label", true, false) if view else []:
		if l.text.begins_with("QB: "):
			line = l
		if l.text.contains("tkl") or l.text.contains("pbu"):
			leaked = true
	check(line != null and line.text.contains("1/2 12yd"), "Your game shows local Ann's passing line")
	check(not leaked, "the overview shows no line with the other Ann's tackle or breakup")
	if line != null:
		menu.content_scroll.ensure_control_visible(line)
	await process_frame
	await process_frame
	# Freeze the lobby's motion and music so the capture is reproducible.
	menu.lobby.set_process(false)
	menu.lobby._t = 0.0
	menu.lobby._shift = menu.lobby._shift_to
	menu.lobby._process(0.0)
	for animation in menu.lobby.find_children("*", "AnimationPlayer", true, false):
		if animation.is_playing():
			animation.seek(0.0, true)
			animation.pause()
	menu.music.set_process(false)
	menu.music.player.stop()
	menu.music._process(0.0)
	await capture("same-name-your-game")
	finish()
