extends "res://tests/visual/harness.gd"
## #323: a lost keeper fumble still shows the carry and its yards in Your game.

const DT := 1.0 / preload("res://src/sim/tick.gd").HZ

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var launch = root.get_node("Launch")
	launch.settings.player_name = "Riley"
	var game = preload("res://scenes/main.tscn").instantiate()
	game.toss_seed = 0
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.auto_next = false
	game.series.start(0, 25.0)
	var world = game.world
	var qb = world.find_role(0, game.Athlete.Role.QB)
	var defender = world.find_role(1, game.Athlete.Role.LB)
	var snap := InputEventKey.new()
	snap.keycode = KEY_SPACE
	snap.pressed = true
	game._unhandled_key_input(snap)
	while world.snap_in_flight():
		world.step({}, DT)
	check(world.carrier() == qb, "Space snaps to the quarterback")

	qb.position = Vector2(5.0, 37.0)
	defender.position = qb.position
	world._fumble(qb, defender)
	world.ball.position.z = 0.0
	world._step_loose(0.0)
	check(world.carrier() == defender, "defense recovers the fumble")
	defender.position = Vector2(-0.5, 32.0)
	world.step({}, DT)
	check(world.phase == game.World.Phase.DEAD, "defender runs out of bounds")

	game.series.score = [3, 0]
	game.series.clock.quarter = 4
	game.series.clock.remaining = 0.0
	game.next_play()
	var overview: Dictionary = game.match_overview()
	check(overview["my_lines"] == ["QB: 1 car 12yd 0TD"], "final summary gives the QB one 12-yard carry")

	launch.go_to_menu("", overview)
	for frame in 5:
		await process_frame
	var menu = current_scene
	check(menu != null and menu.scene_file_path == launch.MENU_SCENE and menu.current == "overview", "lobby opens the game overview")
	if menu == null or menu.scene_file_path != launch.MENU_SCENE or menu.current != "overview":
		finish()
		return
	var panel: Control = menu.content.find_child("GameOverview", true, false)
	var labels: Array = panel.find_children("*", "Label", true, false).map(func(label): return label.text)
	check(labels.has("QB: 1 car 12yd 0TD"), "Your game shows the keeper line")
	await process_frame
	menu.content_scroll.scroll_vertical = int(menu.content_scroll.get_v_scroll_bar().max_value)
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
	await capture("fumbled-keeper-your-game")
	finish()
