extends "res://tests/visual/harness.gd"
## #387: the F dive is head-first. The Roll launch, belly-down and arms ahead, then lying prone
## (Swim_Fwd held), then a push-up to his feet. Before, it was a feet-first slide that got up
## through LayToIdle, which starts face-up. Every frame from the dive to back on his feet is
## measured: the chest never faces the sky.

const LAUNCH_FRAME := 12    # frames after F: in the air
const PRONE_FRAME := 45     # on the turf, 0.4 s into the 1 s recovery
const GETUP_FRAME := 72     # pushing up (GETUP_AT s of recovery left)
const END_FRAME := 100      # back on his feet

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
	check(world.phase == game.World.Phase.LIVE, "Space snaps")
	var wr = world.find_role(0, game.Athlete.Role.WR)
	game.set_controlled(wr.id)
	wr.facing = Vector2(1, 0)   # across the field: the camera sees him from the side
	var view = game.views[wr.id]
	var sk: Skeleton3D = view._skel
	cam = Camera3D.new()
	cam.fov = 45.0
	root.add_child(cam)
	# Godot restores the clip pose after the modifiers run: read the bones as they are drawn.
	var got := {}
	var grab := func() -> void:
		for b in ["pelvis", "spine_03", "Head", "hand_r", "hand_l"]:
			got[b] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b))
	view.pose.modification_processed.connect(grab)
	_key(KEY_F)
	check(wr.is_diving(), "F dives")
	var start := Vector3(wr.position.x, 0.0, -wr.position.y)   # the sim spot: the view may not have caught up yet
	var heading := Vector3(1, 0, 0)
	var worst_up := -1.0     # highest the chest front ever points (y of its unit vector)
	var worst_at := -1
	for frame in END_FRAME + 1:
		cam.global_position = start + Vector3(2.4, 1.4, 6.0)
		cam.look_at(start + Vector3(2.4, 0.4, 0.0))
		cam.make_current()
		got.clear()
		await process_frame
		if got.is_empty():
			continue
		var up: float = (got.spine_03.basis.z.normalized()).y
		if up > worst_up:
			worst_up = up
			worst_at = frame
		match frame:
			LAUNCH_FRAME:
				check(view.anim.assigned_animation == view.DIVE_CLIP, "launch plays %s (%s)" % [view.DIVE_CLIP, view.anim.assigned_animation])
				check(up < -0.4, "in the air belly-down: chest front y %.2f" % up)
				await capture("dive-launch")
			PRONE_FRAME:
				check(wr.is_grounded() and view.anim.assigned_animation == view.PRONE_CLIP, "lying prone (%s)" % view.anim.assigned_animation)
				var pelvis_y: float = got.pelvis.origin.y
				check(pelvis_y < 0.4 and pelvis_y > 0.05, "pelvis low on the turf, not under it: %.2f m" % pelvis_y)
				check(up < -0.6, "face-down: chest front y %.2f" % up)
				var ahead := minf((got.hand_r.origin - got.Head.origin).dot(heading), (got.hand_l.origin - got.Head.origin).dot(heading))
				check(ahead > 0.0, "both hands ahead of the head: %.2f m" % ahead)
				var lowest := minf(minf(got.hand_r.origin.y, got.hand_l.origin.y), got.Head.origin.y)
				check(lowest > -0.05, "hands and head on the turf, not through it: %.2f m" % lowest)
				await capture("dive-prone")
			GETUP_FRAME:
				check(view.anim.assigned_animation == view.GETUP_CLIP, "pushes up through %s (%s)" % [view.GETUP_CLIP, view.anim.assigned_animation])
				await capture("dive-getup")
	check(not wr.is_grounded() and got.has("pelvis") and got.pelvis.origin.y > 0.7, "back on his feet")
	check(worst_up < 0.3, "the chest never faces the sky from the dive to standing: worst y %.2f at frame %d" % [worst_up, worst_at])
	view.pose.modification_processed.disconnect(grab)
	finish()

func _key(code: int) -> void:
	var input := InputEventKey.new()
	input.keycode = code
	input.pressed = true
	game._unhandled_key_input(input)
