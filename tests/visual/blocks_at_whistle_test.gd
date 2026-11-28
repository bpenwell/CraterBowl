extends "res://tests/visual/harness.gd"
## #375: the center and rusher stop pushing when the QB steps out of bounds.

const Tick := preload("res://src/sim/tick.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.opening_kickoff = false
	game.configure(5)
	game.auto_next = false
	game.auto_replay = false
	game.pov_enabled = false
	game.ai.offense_enabled = false
	game.ai.defense_enabled = false
	game.series.start(0, 40.0)
	game.set_controlled(game.my_id)
	await physics_frame
	var snap := InputEventKey.new()
	snap.keycode = KEY_SPACE
	snap.pressed = true
	game._unhandled_key_input(snap)
	var world = game.world
	check(world.phase == world.Phase.LIVE, "Space snaps the ball")
	game.set_physics_process(false)
	for i in 35:
		world.step({}, Tick.DT)
	var qb = world.carrier()
	var blocker = world.find_role(0, game.Athlete.Role.C)
	var defender = world.find_role(1, game.Athlete.Role.DL)
	check(qb != null and blocker != null and defender != null, "QB and both linemen are on the field")
	if qb == null or blocker == null or defender == null:
		finish()
		return
	var x: float = world.field.width * 0.5
	blocker.position = Vector2(x, 39.6)
	blocker.facing = Vector2.DOWN
	defender.position = Vector2(x, 40.5)
	defender.facing = Vector2.UP
	world.step({}, Tick.DT)
	check(blocker.engaged_with == defender.id and defender.engaged_with == blocker.id, "linemen engaged during live play")

	var blocker_view = game.views[blocker.id]
	var defender_view = game.views[defender.id]
	blocker_view.rotation.y = 0.0
	defender_view.rotation.y = PI
	game._render()
	var camera := Camera3D.new()
	game.add_child(camera)
	var focus := Vector3(x, 1.0, -40.0)
	camera.look_at_from_position(focus + Vector3(4.6, 0.7, 2.6), focus)
	camera.make_current()
	await _settle()
	await _capture_pose("blocks-at-whistle-live", [blocker_view, defender_view])

	qb.position.x = -0.5
	world.step({}, Tick.DT)
	game._render()
	await _settle()
	check(world.phase == world.Phase.DEAD and game.last_whistle == "OUT OF BOUNDS", "QB stepped out before the line was reset")
	check(blocker.engaged_with == -1 and defender.engaged_with == -1, "both sides released at the whistle")
	check(blocker_view._cur == "Idle" and defender_view._cur == "Idle", "both linemen returned to idle")
	await _capture_pose("blocks-at-whistle-dead", [blocker_view, defender_view])
	finish()

func _capture_pose(name: String, views: Array) -> void:
	for view in views:
		view.anim.seek(0.25, true)
		view.anim.pause()
	await capture(name)

func _settle() -> void:
	for i in 24:
		await process_frame
