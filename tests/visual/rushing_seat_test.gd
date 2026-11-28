extends "res://tests/visual/harness.gd"
## #293: replacing the quarterback during a keeper leaves the carry with the original player.

const REPLACEMENT := 99
const Tick := preload("res://src/sim/tick.gd")
const DT := 1.0 / Tick.HZ

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
	game.profile_path = "user://test_rushing_credit_profile.json"
	game.leaderboard_path = "user://test_rushing_credit_leaderboard.json"
	game.replay_dir = "user://test_rushing_credit_replays"
	game.series.start(0, 75.0)
	var world = game.world
	var qb = world.find_role(0, game.Athlete.Role.QB)
	var back = world.find_role(0, game.Athlete.Role.RB)
	var snap := InputEventKey.new()
	snap.keycode = KEY_SPACE
	snap.pressed = true
	game._unhandled_key_input(snap)
	check(world.phase == game.World.Phase.LIVE, "Space starts the keeper")
	while world.snap_in_flight():
		world.step({}, DT)
	check(world.carrier() == qb, "QB holds the snap")

	game.lobby.add(REPLACEMENT, "Morgan")
	check(game.roster.claim(game.LOCAL_PLAYER, game.roster.slot_of_athlete(back.id)), "runner takes another seat")
	game.my_id = back.id
	game.set_controlled(back.id)
	check(game.roster.claim(REPLACEMENT, game.roster.slot_of_athlete(qb.id)), "replacement takes the QB seat")
	qb.position = Vector2(-0.5, 95.0)
	world.step({}, DT)
	check(world.phase == game.World.Phase.DEAD, "QB runs out of bounds")
	check(game.stats.player_summary(REPLACEMENT).is_empty(), "replacement has no rushing line")

	game.series.score = [3, 0]
	game.series.clock.quarter = 4
	game.series.clock.remaining = 0.0
	game.next_play()
	check(game.profile.xp == 152, "original runner earns XP for 20 rushing yards")

	var launch = root.get_node("Launch")
	launch.settings_path = "user://test_rushing_credit_settings.cfg"
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

	var runner: Control = menu.content.find_child("Potg0", true, false)
	check(runner != null, "the QB gets a postgame card")
	if runner != null:
		var labels: Array = runner.find_children("*", "Label", true, false).map(func(label): return label.text)
		check(labels.has("RILEY  ·  QB  ·  HELIOS") and labels.has("1 CAR  20 YDS"), "the postgame card names the original runner")
		await _capture_control(menu.content_scroll, runner, "runner-card")

	var labels: Array = menu.content.find_children("*", "Label", true, false).map(func(label): return label.text)
	check(labels.has("QB: 1 car 20yd 0TD"), "Your game shows the original runner's QB line")
	var earned_xp: Label = null
	for label in menu.content.find_children("*", "Label", true, false):
		if label.text.begins_with("XP +"):
			earned_xp = label
			break
	check(earned_xp != null and earned_xp.text.begins_with("XP +152"), "overview shows XP for the carry")
	if earned_xp != null:
		await _capture_control(menu.content_scroll, earned_xp, "rushing-summary")
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
