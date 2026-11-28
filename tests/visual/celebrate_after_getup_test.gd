extends "res://tests/visual/harness.gd"
## #426: the carrier dives across the goal line. The sim holds a dead ball's holder where he
## lies for the whole dead ball, and the view used to pop him off the turf straight into the
## dance. Now he gets up (LayToIdle) first, then celebrates. Captures keyed to clip state.

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
	var qb = null
	for i in 120:   # the snap reaches the QB
		qb = world.carrier()
		if qb != null:
			break
		await physics_frame
	check(qb != null, "the QB holds the snap")
	if qb == null:
		finish()
		return
	game.set_controlled(qb.id)
	qb.position = Vector2(26.0, world.field.length - 1.5)
	qb.facing = Vector2(0, 1)
	var view = game.views[qb.id]
	cam = Camera3D.new()
	cam.fov = 45.0
	root.add_child(cam)
	_key(KEY_F)
	check(qb.is_diving(), "F dives at the goal line")
	var scored := false
	var got_up := 0        # frames of the get-up clip before the dance
	var danced_early := 0  # frames dancing before any get-up
	var danced := false
	for frame in MAX_FRAMES:
		await physics_frame
		cam.global_position = view.global_position + Vector3(4.8, 1.6, 0.0)
		cam.look_at(view.global_position + Vector3.UP * 0.6)
		cam.make_current()
		await process_frame
		if not scored and world.phase == world.Phase.DEAD:
			scored = true
			view.celebrate("dance")   # as main.gd does on the touchdown event, with a Dance celebration
			check(qb.is_diving() or qb.is_grounded(), "down in the end zone at the whistle")
		if not scored:
			continue
		if view._cur == "u2/LayToIdle":
			got_up += 1
			if got_up == 12:
				await capture("celebrate-getting-up")
		elif view._cur == "Dance":
			if got_up == 0:
				danced_early += 1
			elif view.celebrate_t < 1.2:
				danced = true
				await capture("celebrate-after-getup")
				break
	check(scored, "touchdown")
	check(danced_early == 0, "no dance before he gets up: %d frames" % danced_early)
	check(got_up > 20, "he gets up first: %d frames of LayToIdle" % got_up)
	check(danced, "then he dances")
	finish()

func _key(code: int) -> void:
	var input := InputEventKey.new()
	input.keycode = code
	input.pressed = true
	game._unhandled_key_input(input)
