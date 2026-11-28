extends "res://tests/visual/harness.gd"
## The tackled carrier's get-up (tackle_fall.gd). Two real hits through world.tackle(), each in
## a fresh match:
## - dead ball: a linebacker dives on the carrier head-on. He ragdolls down, lies a moment, gets
##   up where he fell (no sliding while he rises), then jogs back onto the sim spot.
## - fumble: a dive from behind that strips him (forced with world._fumble: whether a hit strips
##   is fumble_variety_test's job); he ragdolls and scrambles up while the ball is live.
## Every frame the displayed pelvis (after the ragdoll and pose modifiers) may not jump: the swap
## from physics to the get-up clip and the move of the view root under the body must not show.
## Then the next snap teleports a fallen carrier cleanly.
const Ball := preload("res://src/sim/ball.gd")
const TackleFall := preload("res://src/game/art/tackle_fall.gd")
const JOG_FRAMES := 5
const MAX_PELVIS_STEP := 0.3   # yd per frame (60 fps): faster than any fall the speed cap allows
const MAX_BALL_STEP := 0.15   # yd per frame the held ball may move against the body (hug -> carry)
const MAX_RISE_DRIFT := 0.35   # yd the pelvis may move over the ground while he gets up

var _pelvis := Vector3.ZERO
var _ball := Vector3.ZERO   # the held ball, relative to the pelvis
var _seen_pelvis := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _case("dead", Vector2(0, 1.1), Vector2(0, -1))
	await _case("fumble", Vector2(0, -1.1), Vector2(0, 1))
	finish()

## lb_at: the diver's offset from the carrier; lb_face: the way he dives.
func _case(kind: String, lb_at: Vector2, lb_face: Vector2) -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.auto_replay = false
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
	check(c != null and c.team == 0, "%s: QB has the snap" % kind)
	game.set_controlled(c.id)
	game.pov_enabled = false
	var cx: float = game.world.field.width / 2.0
	var lb = game.world.find_role(1, game.Athlete.Role.LB)
	var y := 44.0
	for i in JOG_FRAMES:
		y += game.T.RUN_SPEED / 60.0
		c.position = Vector2(cx, y)
		c.velocity = Vector2(0, game.T.RUN_SPEED)
		c.facing = Vector2(0, 1)
		c.last_sprinting = false
		c.stamina = 1.0
		lb.position = c.position + lb_at
		lb.facing = lb_face
		await physics_frame
	var v = game.views[c.id]
	var sk: Skeleton3D = v._skel
	sk.skeleton_updated.connect(func():
		_pelvis = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("pelvis")).origin
		_ball = game.ball_view.global_position - _pelvis   # pinned just before this (player.gd _pin_ball)
		_seen_pelvis = true)
	var seen := []
	game.world.event.connect(func(n, _d): seen.append(n))
	check(game.world.tackle(lb.id), "%s: LB dives" % kind)
	if kind == "fumble":
		game.world._fumble(c, lb)
	for i in 20:
		await physics_frame
		if seen.has("fumble") or seen.has("tackle"):
			break
	check(seen.has("fumble" if kind == "fumble" else "tackle"), "%s: the hit is a %s (%s)" % [kind, kind, seen])
	check(v.is_falling(), "%s: the carrier goes down" % kind)

	# Down, then up where he fell, then back onto the sim spot.
	var last := Vector3.INF
	var max_step := 0.0
	var last_ball := Vector3.INF
	var max_ball := 0.0
	var lie := Vector3.INF
	var max_drift := 0.0
	var ring_off := 0.0
	var shadow_off := 0.0
	var rise_at := -1
	var down_shot := false
	var rise_shot := false
	for f in 360:
		await process_frame
		if not _seen_pelvis:
			continue
		if last != Vector3.INF:
			max_step = maxf(max_step, _pelvis.distance_to(last))
		last = _pelvis
		if rise_at >= 0 and v.ball_node != null:   # from the get-up on: the hug lets go into the carry
			if last_ball != Vector3.INF:
				max_ball = maxf(max_ball, _ball.distance_to(last_ball))
			last_ball = _ball
		var flat := Vector3(_pelvis.x, 0.0, _pelvis.z)
		if v.is_falling() and not v.fall.rising():
			ring_off = maxf(ring_off, Vector3(game.pres.ring.position.x, 0.0, game.pres.ring.position.z).distance_to(flat))
			shadow_off = maxf(shadow_off, Vector3(v._shadow.global_position.x, 0.0, v._shadow.global_position.z).distance_to(flat))
		if v.is_falling() and v.fall.rising():
			if rise_at < 0:
				rise_at = f
				lie = flat
			max_drift = maxf(max_drift, flat.distance_to(lie))
		if kind == "dead" and not down_shot and rise_at < 0 and f >= 50:
			down_shot = true
			_close_up(v)
			await capture("tackle-getup-down")
		if not rise_shot and rise_at >= 0 and f - rise_at >= (28 if kind == "dead" else 18):
			rise_shot = true
			_close_up(v)
			await capture("tackle-getup-rising" if kind == "dead" else "fumble-getup-rising")
		if rise_at >= 0 and not v.is_falling() and not v.chase_sim:
			break
	var rise_s := float(rise_at) / 60.0
	var want := TackleFall.RISE_FUMBLE if kind == "fumble" else TackleFall.RISE_DEAD
	check(rise_at >= 0 and absf(rise_s - want) < 0.25, "%s: gets up %.2f s after the hit (want ~%.2f)" % [kind, rise_s, want])
	check(max_step < MAX_PELVIS_STEP, "%s: no pop, pelvis moves at most %.3f yd/frame (< %.2f)" % [kind, max_step, MAX_PELVIS_STEP])
	if kind == "dead":
		check(max_ball > 0.0 and max_ball < MAX_BALL_STEP, "dead: ball eases from the hug into the carry, at most %.3f yd/frame (< %.2f)" % [max_ball, MAX_BALL_STEP])
	check(max_drift < MAX_RISE_DRIFT, "%s: rises where he fell, pelvis drifts %.2f yd (< %.2f)" % [kind, max_drift, MAX_RISE_DRIFT])
	check(ring_off < 0.35 and shadow_off < 0.35, "%s: ring %.2f / shadow %.2f yd from the body while down" % [kind, ring_off, shadow_off])
	check(not v.is_falling() and not v.chase_sim, "%s: up and done" % kind)
	var head := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
	check(head.y - v.global_position.y > 1.3, "%s: upright, head %.2f yd up" % [kind, head.y - v.global_position.y])
	var gap: float = Vector2(v.position.x - v.target_position().x, v.position.z - v.target_position().z).length()
	check(gap < 0.05, "%s: view back on the sim position (%.3f yd off)" % [kind, gap])
	if kind == "dead":
		_close_up(v)
		await capture("tackle-getup-up")
		# Down again, then the next snap: the teleport stops the fall at once, no leftovers.
		v.tackled(Vector3(0, 0, -6), Vector3.ZERO, v.global_position + Vector3.UP * 0.55)
		await _frames(30)
		check(v.is_falling(), "dead: down again before the next snap")
		game.next_play()
		await _frames(3)
		check(not v.is_falling() and not v.chase_sim and v.fall._hold == null and v.fall._sim == null, "dead: next snap stands him up at once")
		check(v.position.distance_to(v.target_position()) < 0.05, "dead: snapped onto the new spot")
	game.queue_free()
	await _frames(2)
	_seen_pelvis = false

## A camera beside the body (the game camera is too far back to see the pose).
func _close_up(v) -> void:
	var cam := Camera3D.new()
	cam.fov = 45
	v.get_parent().add_child(cam)
	var at: Vector3 = v.ground_position()
	cam.global_position = at + Vector3(3.2, 1.6, 1.8)
	cam.look_at(at + Vector3(0, 0.5, 0))
	cam.make_current()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
