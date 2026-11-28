extends "res://tests/visual/harness.gd"
## #68: you kick. On the kickoff the ball stands on a tee in front of you and a stepped power
## meter stands beside you, lit to the power the aim distance asks for; on a punt the meter
## is back (no tee). Real main scene, real aim path (camera heading + aim distance), real sim.
## The kickoff is set up through the toss (start_match + choose_toss "kick") and waits out the
## toss outro's kick lock, so it doesn't depend on kicking right after start_match (#285).

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	game.toss_cutscene = false
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.ai.defense_enabled = false
	await _frames(2)
	var series = game.series
	var w = game.world
	var mine: int = w.get_athlete(game.my_id).team
	series.start_match(mine, true)   # seed = my team: we win the toss
	check(series.choose_toss(mine, "kick"), "we pick KICK")
	var k = w.kicker()
	check(k != null and k.team == mine and w.ball.is_held_by(k.id), "our kicker has the kickoff ball")
	game.set_controlled(k.id)
	game.cam_yaw = 0.0
	game.aim_distance = 48.0
	for i in 120:   # the toss outro holds the kick (TOSS_OUTRO); the camera settles meanwhile
		await physics_frame
		if not w.kick_locked and i >= 90:
			break
	# get(): before_after.sh also runs this case on a base without the meter; it still captures.
	var ka = game.pres.get("kick_art")
	check(ka != null, "presentation has the kick art")
	check(game.can_kick(), "you can kick off")
	if ka != null:
		check(ka.meter.visible and ka.lit == ka.steps_for(game.kick_power()), "meter: %d/%d steps for power %.2f" % [ka.lit, ka.STEPS, game.kick_power()])
		check(ka.lit >= 6 and ka.lit < ka.STEPS, "a deep kickoff lights most of the meter, not all (%d)" % ka.lit)
		check(ka.tee.visible and game.ball_view.global_position.distance_to(ka.tee.global_position) < 0.5, "ball on the tee")
	check(game.views[k.id].ball_node == null, "not in the kicker's hand")
	await capture("kick-meter-kickoff")

	# 4th down: our punt. The punter takes the snap and the meter comes back without the tee.
	series.start(mine, 30.0)
	series.downs.down = 4
	check(series.call_kick("punt"), "punt called")
	var p = w.kicker()
	game.set_controlled(p.id)
	game.cam_yaw = 0.0
	game.aim_distance = 36.0
	await _frames(5)
	check(w.snap(), "snap")
	for i in 120:
		await physics_frame
		if w.ball.is_held_by(p.id):
			break
	await _frames(40)   # camera settles on the punter
	check(game.can_kick(), "punter can kick")
	if ka != null:
		check(ka.meter.visible and ka.lit == ka.steps_for(game.kick_power()), "punt meter: %d steps for power %.2f" % [ka.lit, game.kick_power()])
		check(not ka.tee.visible, "no tee on a punt")
	await capture("kick-meter-punt")
	finish()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
