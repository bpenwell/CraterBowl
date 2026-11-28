extends "res://tests/visual/harness.gd"
## #172: a kick return touchdown has its own postgame card and summary line.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	game.toss_seed = 0
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	await process_frame
	game.player_name = "Ace"
	game.profile = game.Cosmetics.new()
	game.profile_path = "user://test_return_td_profile.json"
	game.leaderboard_path = "user://test_return_td_leaderboard.json"
	game.replay_dir = "user://test_return_td_replays"
	game.series.start_match(0, false)
	game.series.choose_toss(game.series.toss_winner, "receive")   # #129: skip the coin-toss cutscene
	game.series.score[1] = 7
	var world = game.world
	var kicker = world.kicker()
	var returner = world.returner()
	game.roster.claim(game.LOCAL_PLAYER, game.roster.slot_of_athlete(returner.id))
	game.my_id = returner.id
	game.set_controlled(returner.id)
	check(world.kick(kicker.id, Vector2(world.field.width / 2.0, 90.0), 0.75), "opponent kicks off")
	world.ball.hold(returner.id)
	returner.position = Vector2(world.field.width / 2.0, -0.5)
	world.step({}, 1.0 / 60.0)
	game.next_play()
	check(game.series.score == [6, 7], "return adds six to the correct team")
	game.series.last_result = {"type": "field_goal", "good": false, "team": 0}
	game.next_play()

	# A stronger passing line gives the returner a category title on the second card.
	game.stats.athletes[kicker.id] = {"team": 1, "pos": "QB", "owner": "Bot", "att": 10,
		"comp": 7, "pass_yds": 200, "pass_td": 1}
	game.series.clock.quarter = 4
	game.series.clock.remaining = 0.0
	game.series.last_result = {"type": "incomplete"}
	world.phase = game.World.Phase.DEAD
	game.next_play()
	check(game.team_totals[0]["td"] == 1, "team box score counts the return touchdown")
	check(game.profile.achievements == ["first_td"], "return unlocks First Touchdown")

	var launch = root.get_node("Launch")
	launch.settings_path = "user://test_return_td_settings.cfg"   # never leak the name into later cases
	launch.settings.player_name = "Ace"
	launch.go_to_menu("", game.match_overview())
	for frame in 5:
		await process_frame
	var menu = current_scene
	check(menu != null and menu.scene_file_path == launch.MENU_SCENE, "lobby opens the game overview")
	if menu == null or menu.scene_file_path != launch.MENU_SCENE:
		finish()
		return
	_freeze_lobby(menu)
	var card: Control = menu.content.find_child("Potg1", true, false)
	var card_text: Array = []
	if card != null:
		card_text = card.find_children("*", "Label", true, false).map(func(label): return label.text)
	check(card_text.has("SPECIAL TEAMS STANDOUT") and card_text.has("1 RET TD"),
		"second card labels the score as a special-teams return")
	if card != null:
		await _capture_control(menu.content_scroll, card, "return-card")
	var summary: Label = null
	var return_td_shown := false
	for label in menu.content.find_children("*", "Label", true, false):
		if label.text.begins_with("ACHIEVEMENTS:"):
			summary = label
		if label.text.ends_with("1 ret TD"):
			return_td_shown = true
	check(return_td_shown, "your game shows the return touchdown")
	check(summary != null and summary.text == "ACHIEVEMENTS: First Touchdown",
		"your game shows First Touchdown")
	if summary != null:
		await _capture_control(menu.content_scroll, summary, "return-summary")
	finish()

func _capture_control(scroll: ScrollContainer, control: Control, name: String) -> void:
	scroll.ensure_control_visible(control)
	await process_frame
	await process_frame
	await capture(name)

func _freeze_lobby(menu) -> void:
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
