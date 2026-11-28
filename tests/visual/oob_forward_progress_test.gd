extends "res://tests/visual/harness.gd"
## #103: a linebacker meets the QB at the sideline and drives him back and out of bounds.
## Out of bounds is spotted at forward progress, like a tackle (#98): the ball goes back up to
## where contact stopped him, x stays where he crossed, and the overlay calls it out. The next
## snap lines up at that spot. Real main scene, real snap key path, real sim whistle.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.opening_kickoff = false
	game.ai.defense_enabled = false
	game.series.start(0, 40.0)
	game.set_controlled(game.my_id)
	await _frames(5)
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	game._unhandled_key_input(ev)
	await _frames(30)
	var c = game.world.carrier()
	check(c != null and c.team == 0, "QB has the snap")
	c.position = Vector2(1.5, 38.0)
	c.velocity = Vector2.ZERO
	var lb = game.world.find_role(1, game.Athlete.Role.LB)
	var lean := Vector2(0.45, 0.6)   # inside-front, 0.75 yd: bodies overlap, he gives ground back and out
	lb.position = c.position + lean
	lb.facing = -lean.normalized()
	var contact_y := INF
	var last_in: Vector2 = c.position
	game.pov_enabled = false
	for i in 90:
		if game.world.phase == game.World.Phase.DEAD:
			break
		last_in = c.position
		lb.position = c.position + lean   # keeps leaning in
		await physics_frame
		if contact_y == INF and lb.position.distance_to(c.position) <= game.T.CONTACT_REACH:
			contact_y = c.position.y
	await _frames(12)
	var spot: Vector2 = game.world.dead_ball_spot
	check(game.world.phase == game.World.Phase.DEAD, "whistled dead")
	check(contact_y - last_in.y > 1.0, "QB driven back %.2f yd before going out" % (contact_y - last_in.y))
	check(spot.x <= 0.0, "spotted where he crossed the sideline (x %.2f)" % spot.x)
	check(absf(spot.y - contact_y) < 0.2, "spot %.2f = forward progress %.2f (went out at %.2f)" % [spot.y, contact_y, last_in.y])
	check(c.position.is_equal_approx(spot), "dead carrier sits at the spot")
	var ov = game.pres.overlay
	check(ov.banner.visible and ov.banner.text == "FORWARD PROGRESS", "banner: %s %s" % [ov.banner.text, ov.banner_sub.text])
	await capture("oob-forward-progress-spot")
	game.next_play()
	await _frames(20)
	check(absf(game.world.los_y - spot.y) < 0.01, "next snap from the forward-progress spot (los %.2f)" % game.world.los_y)
	await capture("oob-forward-progress-next-los")
	finish()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
