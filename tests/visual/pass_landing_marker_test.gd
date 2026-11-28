extends "res://tests/visual/harness.gd"
## #108: the same airborne pass, photographed with and without the host's marker.

const Tick := preload("res://src/sim/tick.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.opening_kickoff = false
	game.configure(5)
	game.pov_enabled = false
	game.set_physics_process(false)
	game.series.start(0, 35.0)
	game.set_controlled(game.my_id)
	await process_frame
	game.set_process(false)
	game.pres.set_process(false)
	var w = game.world
	var qb = w.get_athlete(game.my_id)
	for a in w.athletes:
		a.position = Vector2(4.0, 10.0 + a.id * 3.0)
	qb.position = Vector2(24.0, 30.0)
	w.start_live_with(qb.id)
	game.aim_point = Vector2(26.0, 66.0)
	var j := InputEventKey.new()
	j.keycode = KEY_J
	j.pressed = true
	game._unhandled_key_input(j)
	check(w.forward_pass_thrown, "J releases the pass")
	for i in 25:
		w.step({}, 1.0 / Tick.HZ)
	check(w.ball.state == w.Ball.State.IN_FLIGHT, "pass is still in flight")

	game.my_id = w.find_role(0, game.Athlete.Role.WR).id
	game.set_controlled(game.my_id)
	game._render()
	for view in game.views:
		view.interpolate(1.0)
	game.pres._update_ball(0.0, w)
	game.pres.overlay.refresh(game, 0.1)
	check(game.pres.landing.visible, "an eligible receiver sees the marker")
	var landing: Vector3 = game.pres.landing.position
	game.camera.position = landing + Vector3(-8.0, 13.0, 17.0)
	game.camera.look_at(landing)
	await capture("pass-landing-on")

	check(game.lobby.set_setting(1, "pass_marker", false), "host can disable the cue")
	game.pres._update_ball(0.0, w)
	check(not game.pres.landing.visible, "the same pass has no marker with the option off")
	await capture("pass-landing-off")

	# The ENet smoke test checks the actual host key and mirrored setting. Freeze just the lobby
	# presentation here with a local server actor so the compare uses the same invite text.
	game.net = game.NetSession.new()
	game.add_child(game.net)
	game.net.mode = game.net.Mode.SERVER
	game.net.lobby_mode = true
	game.lobby.code = "TEST0-LOBBY"
	game.lobby.add(1, "Host")
	game.lobby.add(2, "Receiver")
	game._process(0.0)
	game.pres.overlay.refresh(game, 0.1)
	check(game.hud.visible and game.hud.text.contains("Pass marker off") and game.hud.text.contains("[I] pass marker"),
		"the host's lobby describes the option and its current value")
	await capture("pass-landing-lobby-off")
	finish()
