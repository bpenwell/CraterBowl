extends "res://tests/visual/harness.gd"
## #426: a scorer who is down (dove into the end zone) gets up before he celebrates. He used
## to pop off the turf straight into the dance. Captures keyed to sim state, not frame counts.

const MAX_FRAMES := 240

var game
var cam: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.opening_kickoff = false
	game.auto_next = false
	game.auto_replay = false
	game.pov_enabled = false
	game.ai.defense_enabled = false
	game.ai.offense_enabled = false
	game.series.start(0)
	game.set_controlled(game.my_id)
	game.input_override = Vector2.ZERO
	await physics_frame
	_key(KEY_SPACE)
	var world = game.world
	var wr = world.find_role(0, game.Athlete.Role.WR)
	game.set_controlled(wr.id)
	wr.facing = Vector2(1, 0)
	var view = game.views[wr.id]
	cam = Camera3D.new()
	cam.fov = 45.0
	root.add_child(cam)
	_key(KEY_F)
	check(wr.is_diving(), "F dives")
	view.celebrate("dance")   # as main.gd does on the touchdown event
	var down_shot := false
	var danced := false
	var danced_down := 0   # frames dancing while down
	for frame in MAX_FRAMES:
		await physics_frame
		cam.global_position = view.global_position + Vector3(0.0, 1.6, 4.8)
		cam.look_at(view.global_position + Vector3.UP * 0.6)
		cam.make_current()
		await process_frame
		var down: bool = wr.is_diving() or wr.is_grounded() or view.is_falling()
		if down:
			if view._cur == "Dance":
				danced_down += 1
			if not down_shot and wr.is_grounded() and wr.recover_t < 0.6:
				down_shot = true
				check(view.celebrate_t == 1.5, "the celebration waits: %.2f s left" % view.celebrate_t)
				await capture("celebrate-waits-while-down")
		elif view._cur == "Dance" and view.celebrate_t < 1.2:
			danced = true
			await capture("celebrate-after-getup")
			break
	check(danced_down == 0, "no dance while down: %d frames" % danced_down)
	check(down_shot and danced, "down first, then the dance (down %s, danced %s)" % [down_shot, danced])
	finish()

func _key(code: int) -> void:
	var input := InputEventKey.new()
	input.keycode = code
	input.pressed = true
	game._unhandled_key_input(input)
