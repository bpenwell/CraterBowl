extends "res://tests/visual/harness.gd"
## #254: flag the rushed throw and show the spot and loss of down in the scorebug.

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
	game.auto_next = false
	game.pov_enabled = false
	game.play_picker_open = false
	game.series.start(0, 40.0)
	game.set_controlled(game.my_id)
	_key(game, KEY_SPACE)
	var world = game.world
	while world.snap_in_flight():
		world.step({}, DT)
	var qb = world.get_athlete(game.my_id)
	check(world.ball.is_held_by(qb.id), "QB receives the snap through Space")
	qb.position = Vector2(26.0, 35.0)
	world.find_role(1, game.Athlete.Role.LB).position = qb.position + Vector2(2.0, 0.0)
	game.aim_point = Vector2(4.0, 20.0)
	_key(game, KEY_J)
	var overlay = game.pres.overlay
	check(world.flags.size() == 1 and overlay.flag_l.text == "FLAG · INTENTIONAL GROUNDING · OFFENSE",
		"J throws away under pressure and shows the grounding flag")
	game._render()
	game._update_camera(4.0)
	await capture("grounding-flag")

	for frame in 240:
		if world.phase == game.World.Phase.DEAD:
			break
		world.step({}, DT)
	check(world.phase == game.World.Phase.DEAD, "play ends")
	_key(game, KEY_ENTER)
	check(game.series.downs.down == 2 and game.series.downs.los == 35.0, "Enter spends the down at the release spot")
	check(overlay.flag_l.text.ends_with("SPOT FOUL · LOSS OF DOWN"), "HUD shows the enforced grounding ruling")
	game.play_picker_open = false
	overlay.banner_t = 0.0
	overlay.refresh(game, 1.0)
	check(overlay.down_l.text == "2ND & 15" and overlay.spot_l.text == "HEL 35",
		"scorebug shows the new spot and down")
	game._render()
	game._update_camera(4.0)
	await capture("grounding-ruling")
	finish()

func _key(game, code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_key_input(event)
