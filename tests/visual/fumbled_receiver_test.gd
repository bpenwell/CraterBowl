extends "res://tests/visual/harness.gd"
## #355: the game overview keeps passing and receiving yards when the defense recovers.

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
	game.pov_enabled = false
	game.series.start(0, 25.0)
	var w = game.world
	var qb = w.find_role(0, game.Athlete.Role.QB)
	var receiver = w.find_role(0, game.Athlete.Role.WR)
	var defender = w.find_role(1, game.Athlete.Role.LB)
	_key(game, KEY_SPACE)
	while w.snap_in_flight():
		w.step({}, DT)
	check(w.carrier() == qb, "Space snaps to the QB")

	for athlete in w.athletes:
		athlete.position = Vector2(24.0, 60.0 + athlete.id * 2.0)
	qb.position = Vector2(5.0, 20.0)
	var catch_spot := Vector2(5.0, 33.0)
	receiver.position = catch_spot
	game.aim_point = catch_spot
	_key(game, KEY_J)
	check(w.forward_pass_thrown, "J throws the ball")
	w.ball.position = Vector3(catch_spot.x, catch_spot.y, 1.0)
	check(w._try_catch() and w.carrier() == receiver, "the receiver catches the pass")
	receiver.position.y = 37.0
	defender.position = receiver.position
	w._fumble(receiver, defender)
	w.ball.position.z = 0.0
	w._step_loose(0.0)
	check(w.carrier() == defender, "defense recovers")
	defender.position = Vector2(-0.5, 32.0)
	w.step({}, DT)
	check(w.phase == game.World.Phase.DEAD, "return ends out of bounds")

	game.series.score = [3, 0]
	game.series.clock.quarter = 4
	game.series.clock.remaining = 0.0
	game.next_play()
	var overview: Dictionary = game.match_overview()
	check(overview["my_lines"] == ["QB: 1/1 12yd 0TD 0INT"], "the local QB keeps one completion for 12 yards")
	check(game.stats.get_line("Bot", "WR").get("rec_yds") == 12.0, "the WR keeps 12 receiving yards")

	launch.go_to_menu("", overview)
	for frame in 5:
		await process_frame
	var menu = current_scene
	if menu == null or menu.scene_file_path != launch.MENU_SCENE or menu.current != "overview":
		check(false, "lobby opens the game overview")
		finish()
		return
	var panel: Control = menu.content.find_child("GameOverview", true, false)
	var labels: Array = panel.find_children("*", "Label", true, false)
	check(labels.any(func(label): return label.text == "QB: 1/1 12yd 0TD 0INT"),
		"Your game displays the completed pass and its yards")
	var receiving_line: Label = null
	for label in labels:
		if label.text.begins_with("1 REC  "):
			receiving_line = label
			break
	check(receiving_line != null and receiving_line.text == "1 REC  12 YDS",
		"the receiver's postgame card displays the catch and its yards")
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
	if receiving_line != null:
		menu.content_scroll.ensure_control_visible(receiving_line)
		await capture("fumbled-receiver-card")
	menu.content_scroll.scroll_vertical = int(menu.content_scroll.get_v_scroll_bar().max_value)
	await capture("fumbled-receiver-your-game")
	finish()

func _key(game, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_key_input(event)
