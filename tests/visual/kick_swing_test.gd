extends "res://tests/visual/harness.gd"
## #424: the kicker swings his right leg through the ball. There's no kick clip in the UAL
## packs, so athlete_pose.gd swings it procedurally from the kick event. Before, the kickoff
## ball left the tee while the kicker stood in Idle. Captures keyed to the swing phase.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	game.toss_cutscene = false
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.ai.defense_enabled = false
	for i in 2:
		await physics_frame
	var series = game.series
	var w = game.world
	var mine: int = w.get_athlete(game.my_id).team
	series.start_match(mine, true)   # seed = my team: we win the toss
	check(series.choose_toss(mine, "kick"), "we pick KICK")
	var k = w.kicker()
	check(k != null and w.ball.is_held_by(k.id), "our kicker has the kickoff ball")
	game.set_controlled(k.id)
	game.cam_yaw = 0.0
	game.aim_distance = 48.0
	for i in 120:   # the toss outro holds the kick (TOSS_OUTRO)
		await physics_frame
		if not w.kick_locked and i >= 90:
			break
	var view = game.views[k.id]
	var sk: Skeleton3D = view._skel
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.global_position = view.global_position + Vector3(4.2, 1.2, 0.6)
	cam.look_at(view.global_position + Vector3(0.0, 0.7, -0.4))
	cam.make_current()
	# Godot restores the clip pose after the modifiers run: read the feet as they are drawn.
	var got := {}
	var grab := func() -> void:
		for b in ["foot_r", "foot_l", "thigh_r"]:
			got[b] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin
	view.pose.modification_processed.connect(grab)
	game.kick_ball()
	check(w.kicked, "the kick goes")
	check(view.kick_t >= 0.0, "the kick event starts the swing")
	var fwd := Vector3(-sin(view.rotation.y), 0.0, -cos(view.rotation.y))   # the kicker's facing
	var contact := false
	var follow := false
	var best := -INF   # how far ahead of the hip the right foot gets
	for i in 60:
		got.clear()
		await process_frame
		if got.is_empty():
			continue
		var p: float = view.pose.kick_phase
		best = maxf(best, (got.foot_r - got.thigh_r).dot(fwd))
		if not contact and p >= 0.2:
			contact = true
			check((got.foot_r - got.thigh_r).dot(fwd) > 0.35 and got.foot_r.y > got.foot_l.y + 0.25,
				"contact: the right foot is out in front and up (ahead %.2f, above the left foot %.2f)" % [(got.foot_r - got.thigh_r).dot(fwd), got.foot_r.y - got.foot_l.y])
			await capture("kick-swing-contact")
		elif contact and not follow and p >= 0.4:
			follow = true
			await capture("kick-swing-follow-through")
		elif follow and p < 0.0:
			break
	check(contact and follow, "the swing plays through (contact %s, follow-through %s)" % [contact, follow])
	check(view.pose.kick_phase < 0.0, "and ends")
	view.pose.modification_processed.disconnect(grab)
	finish()
