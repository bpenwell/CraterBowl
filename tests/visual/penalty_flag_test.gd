extends "res://tests/visual/harness.gd"
## #253: illegal man downfield. A guard is 7 yd past the line when the QB throws (real J key
## path): the flag is thrown at once, Enter walks it off 10 yd and replays the down, and the
## HUD shows the ruling in the yellow flag line above the scorebug until the next snap.
## Reads the new fields with get() so before_after.sh can photograph the same moment on a base
## without the pipeline (its checks fail there, as expected).

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.opening_kickoff = false
	game.pov_enabled = false
	game.ai.defense_enabled = false
	game.series.start(0, 40.0)
	game.set_controlled(game.my_id)
	await _frames(5)
	_key(game, KEY_SPACE)
	await _frames(30)
	var w = game.world
	check(w.ball.is_held_by(game.controlled_id), "QB has the snap")
	var ol = w.find_role(0, game.Athlete.Role.OL)
	ol.position = Vector2(ol.position.x, w.los_y + 7.0)
	game.aim_point = Vector2(3.0, w.los_y + 18.0)
	_key(game, KEY_J)
	var ov = game.pres.overlay
	check(w.get("flags") is Array and w.get("flags").size() == 1, "flag thrown on the release")
	check(ov.banner.text == "FLAG" and _flag_text(ov) == "FLAG · ILLEGAL MAN DOWNFIELD · OFFENSE", "flag shown: %s / %s" % [ov.banner.text, _flag_text(ov)])
	for i in 300:
		if w.phase == w.Phase.DEAD:
			break
		await physics_frame
	check(w.phase == w.Phase.DEAD, "play over")
	_key(game, KEY_ENTER)
	check(absf(game.series.downs.los - 30.0) < 0.001 and game.series.downs.down == 1, "10 yd back, down replayed")
	await _frames(150)   # banners faded, camera settled on the new line
	check(ov.get("flag_pill") != null and ov.flag_pill.visible and _flag_text(ov) == "FLAG · ILLEGAL MAN DOWNFIELD · OFFENSE · 10 YD · REPLAY 1ST DOWN", "ruling: %s" % _flag_text(ov))
	await capture("penalty-flag-ruling")
	finish()

func _flag_text(ov) -> String:
	return ov.flag_l.text if ov.get("flag_l") != null else "(no flag line)"

func _key(game, code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	game._unhandled_key_input(ev)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
