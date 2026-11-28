extends "res://tests/visual/harness.gd"
## A touchdown celebration (1.5 s) plays out before the automatic highlight replay cuts in, and
## the next play waits for both. The replay used to cut in 1.0 s after the whistle, ~0.7 s
## into the dance (#450).

const MAX_FRAMES := 600

var game

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.opening_kickoff = false
	game.auto_next = true
	game.auto_replay = true
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
	for i in 120:
		qb = world.carrier()
		if qb != null:
			break
		await physics_frame
	check(qb != null, "the QB holds the snap")
	if qb == null:
		finish()
		return
	game.looks[qb.id] = {"celebration": "dance"}   # his equipped TD celebration
	qb.position = Vector2(26.0, world.field.length - 1.0)
	game.input_override = Vector2(0, 1)   # run it in
	var view = game.views[qb.id]
	var scored := -1
	var celebrated := 0     # frames of celebration seen
	var cut := 0            # frames the replay was on while the celebration still played
	var replay_after := -1  # frame the replay started
	var shot := false
	for frame in MAX_FRAMES:
		await physics_frame
		await process_frame
		if scored < 0 and world.phase == world.Phase.DEAD:
			scored = frame
			game.input_override = Vector2.ZERO
		if scored < 0:
			continue
		if view.celebrate_t > 0.0:
			celebrated += 1
			if game.replay_active:
				cut += 1
			elif not shot and view.celebrate_t < 0.3:
				shot = true
				var cam := Camera3D.new()
				root.add_child(cam)
				cam.global_position = view.global_position + Vector3(3.5, 1.6, 2.5)
				cam.look_at(view.global_position + Vector3.UP * 1.0)
				cam.make_current()
				await capture("td-celebration-finishes")
				cam.queue_free()
		if game.replay_active and replay_after < 0:
			replay_after = frame
			break
	check(scored >= 0 and game.last_whistle.contains("TOUCHDOWN"), "touchdown (%s)" % game.last_whistle)
	check(celebrated > 80, "the celebration plays (%d frames)" % celebrated)
	check(cut == 0, "the replay doesn't cut in on it (%d frames under the replay)" % cut)
	check(replay_after > 0, "the highlight replay still plays, after it")
	finish()

func _key(code: int) -> void:
	var input := InputEventKey.new()
	input.keycode = code
	input.pressed = true
	game._unhandled_key_input(input)
