extends "res://tests/visual/harness.gd"
## #202: the postgame overview attributes the completed pass to the original thrower.

const REPLACEMENT := 99

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	game.toss_seed = 0
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	await process_frame
	game.player_name = "Riley"
	game.profile = game.Cosmetics.new()
	game.profile.achievements.append("first_win")
	game.profile_path = "user://test_passing_credit_profile.json"
	game.leaderboard_path = "user://test_passing_credit_leaderboard.json"
	game.replay_dir = "user://test_passing_credit_replays"
	game.series.start(0, 75.0)
	var world = game.world
	var qb = world.find_role(0, game.Athlete.Role.QB)
	var receiver = world.find_role(0, game.Athlete.Role.WR)
	var back = world.find_role(0, game.Athlete.Role.RB)
	world.event.emit("snap", {"qb": qb.id})
	world.event.emit("throw", {"by": qb.id})

	# Move the original player to another seat to show their award at the final whistle.
	game.lobby.add(REPLACEMENT, "Morgan")
	check(game.roster.claim(game.LOCAL_PLAYER, game.roster.slot_of_athlete(back.id)), "thrower takes another seat")
	game.my_id = back.id
	game.set_controlled(back.id)
	check(game.roster.claim(REPLACEMENT, game.roster.slot_of_athlete(qb.id)), "replacement takes the QB seat")
	check(game.owner_name(qb.id) == "Morgan", "replacement owns the QB when the pass is caught")
	world.event.emit("catch", {"by": receiver.id})
	world.event.emit("out_of_bounds", {"carrier": receiver.id, "spot": Vector2(0, 95), "team": 0})
	game.series.score = [3, 0]
	game.series.clock.quarter = 4
	game.series.clock.remaining = 0.0
	world.phase = game.World.Phase.DEAD
	game.next_play()
	check(game.profile.xp == 152, "thrower earns the XP for 20 passing yards")

	var launch = root.get_node("Launch")
	launch.settings_path = "user://test_passing_credit_settings.cfg"
	launch.settings.player_name = "Riley"
	launch.go_to_menu("", game.match_overview())
	for frame in 5:
		await process_frame
	var menu = current_scene
	check(menu != null and menu.scene_file_path == launch.MENU_SCENE, "lobby opens the postgame overview")
	if menu == null or menu.scene_file_path != launch.MENU_SCENE:
		finish()
		return
	_freeze_lobby(menu)

	var passer: Control = menu.content.find_child("Potg1", true, false)
	check(passer != null, "the QB gets a postgame card")
	if passer != null:
		var labels: Array = passer.find_children("*", "Label", true, false).map(func(label): return label.text)
		check(labels.has("RILEY  ·  QB  ·  HELIOS") and labels.has("1/1  20 YDS"), "top passer card names the thrower")
		await _capture_control(menu.content_scroll, passer, "top-passer")

	var personal_line: Label = null
	var earned_xp: Label = null
	for label in menu.content.find_children("*", "Label", true, false):
		if label.text.begins_with("QB:"):
			personal_line = label
		if label.text.begins_with("XP +"):
			earned_xp = label
	check(personal_line != null and personal_line.text == "QB: 1/1 20yd 0TD 0INT", "personal summary shows the full pass")
	check(earned_xp != null and earned_xp.text.begins_with("XP +152"), "overview shows the XP for those yards")
	if earned_xp != null:
		await _capture_control(menu.content_scroll, earned_xp, "passing-summary")
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
