extends "res://tests/test_case.gd"

## #250: freeing the match scene within 3.5 s of touchdown fireworks (leave to the menu, or
## the coin-toss roar's fireworks right before a test frees main) must not log engine errors.
## The SceneTree timers outlive the scene, so this needs real frames: run
## tests/fireworks_free.gd in a headless child and fail on any error it prints.
func test_fireworks_survive_freeing_the_match_scene() -> void:
	var out := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--fixed-fps", "60", "-s", "res://tests/fireworks_free.gd"], out, true)
	var log: String = "".join(out)
	assert_eq(code, 0, "fireworks_free.gd exit code")
	assert_true(log.contains("FIREWORKS FREE DONE"), "ran past every fireworks timer")
	assert_true(not log.contains("FIREWORKS FAIL"), "fireworks checks: " + _lines(log, "FIREWORKS"))
	assert_true(not log.contains("ERROR:") and not log.contains("SCRIPT ERROR"),
		"no engine errors after freeing the match scene: " + _lines(log, "ERROR"))

func test_unheld_dead_ball_falls_at_render_rate() -> void:
	var main = preload("res://scenes/main.tscn").instantiate()
	var world = main.World.new()
	main.ball_view = MeshInstance3D.new()
	var presentation = preload("res://src/game/presentation.gd").new()
	presentation.main = main
	presentation.landing = MeshInstance3D.new()
	var contact := Vector3(12.0, 40.0, 1.8)
	world.ball.position = contact
	world.ball.state = world.Ball.State.DEAD
	world.phase = world.Phase.DEAD
	var rendered_contact := Vector3(contact.x, contact.z, -contact.y)
	main.ball_view.position = rendered_contact
	presentation._update_ball(0.0, world)
	assert_eq(main.ball_view.position, rendered_contact, "the fall starts at the contact height")
	main.ball_view.position = rendered_contact
	presentation._update_ball(0.25, world)
	assert_true(main.ball_view.position.y < contact.z and main.ball_view.position.y > presentation.Football.RADIUS,
		"the falling ball is between contact and the turf")
	main.ball_view.position = rendered_contact
	presentation._update_ball(0.75, world)
	assert_near(main.ball_view.position.y, presentation.Football.RADIUS, 0.001, "the ball rests on the turf")
	assert_eq(world.ball.position, contact, "presentation leaves the contact position intact")
	assert_eq(world.ball.state, world.Ball.State.DEAD, "the ball is still dead")
	# A kickoff/next down clears the fall before the next elevated dead ball.
	world.ball.state = world.Ball.State.HELD
	presentation._update_ball(0.0, world)
	world.ball.state = world.Ball.State.DEAD
	main.ball_view.position = rendered_contact
	presentation._update_ball(0.0, world)
	assert_eq(main.ball_view.position, rendered_contact, "next down starts its own fall")
	presentation.landing.free()
	presentation.free()
	main.ball_view.free()
	main.free()

func _lines(log: String, key: String) -> String:
	return " | ".join(Array(log.split("\n")).filter(func(l): return l.contains(key)))
