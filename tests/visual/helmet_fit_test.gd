extends "res://tests/visual/harness.gd"
## Close-ups of the helmet on the head across the clips that move the head most (#158).
## One athlete per cell, each in its own world, paused on a fixed frame of a clip, with a
## camera fixed to the Head bone. Nothing depends on wall-clock time or frame count.

const PlayerView := preload("res://src/game/player.gd")
const Athlete := preload("res://src/sim/athlete.gd")
## [label, clip, time (s)]: idle (menus, POTG), run, dive (#387 launch), down (prone after it), taunts, celebrations, hit.
const POSES := [["idle / POTG", "Idle", 0.4], ["sprint", "Sprint", 0.25],
	["dive", "Roll", 0.25], ["down", "Swim_Fwd", 0.5],
	["taunt: nope", "u2/Idle_No", 0.6], ["taunt: phone", "u2/Idle_TalkingPhone", 0.8],
	["dance", "Dance", 0.7], ["hit", "u2/Hit_Knockback", 0.3]]
const CELL := Vector2i(320, 360)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Camera direction in Head-bone space (+Z = face, +Y = crown).
	await _sheet("helmet-fit-front", Vector3(0.55, 0.12, 1.0), false)
	await _sheet("helmet-fit-back", Vector3(0.6, 0.25, -1.0), false)
	await _sheet("helmet-fit-profile", Vector3(1.0, 0.08, 0.02), false)
	await _sheet("helmet-fit-opponent", Vector3(0.55, 0.12, 1.0), true)
	finish()

func _sheet(capture_name: String, cam_dir: Vector3, opponent: bool) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	root.add_child(grid)
	for i in POSES.size():
		_cell(grid, i, cam_dir, opponent)
	for frame in 3:
		await process_frame
	await capture(capture_name)
	grid.queue_free()
	await process_frame

func _cell(grid: GridContainer, i: int, cam_dir: Vector3, opponent: bool) -> void:
	var box := SubViewportContainer.new()
	box.custom_minimum_size = CELL
	box.stretch = true
	grid.add_child(box)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = CELL
	box.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.7)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	vp.add_child(sun)

	var a = Athlete.new()
	a.id = i
	a.role = 2   # WR: neutral build
	var v = PlayerView.new()
	v.setup(a, Color(0.78, 0.16, 0.18), null, opponent)
	vp.add_child(v)
	v.set_process(false)   # hold the clip we pick; no view-side animation choice
	# The knockback clip carries the body outside its rest-pose cull box, so a head-on
	# close-up loses it (#173). Widen the box here so the cell shows the fit.
	v.mesh_i.extra_cull_margin = 3.0
	v._opponent_mesh.extra_cull_margin = 3.0
	var pose: Array = POSES[i]
	v.anim.play(pose[1], 0.0)
	v.anim.seek(pose[2], true)
	v.anim.pause()
	var skel: Skeleton3D = v.mesh_i.get_parent()
	skel.force_update_all_bone_transforms()
	var head := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Head"))
	head = head.orthonormalized()
	var target := head * Vector3(0, 0.12, 0.01)
	var cam := Camera3D.new()
	cam.fov = 32.0
	vp.add_child(cam)
	cam.look_at_from_position(target + head.basis * cam_dir.normalized() * 0.95, target, head.basis.y)
	cam.make_current()

	if not opponent:
		var helmet: MeshInstance3D = v._open_helmet
		var ba := helmet.get_parent()
		while ba != null and not ba is BoneAttachment3D:
			ba = ba.get_parent()
		check(ba != null and ba.bone_name == "Head", "%s: helmet follows the Head bone" % pose[0])
		check(helmet.is_visible_in_tree(), "%s: local helmet is drawn" % pose[0])
	else:
		check(not v._open_helmet.is_visible_in_tree(), "%s: opponent hides the open helmet" % pose[0])

	var label := Label.new()
	label.text = pose[0]
	label.position = Vector2(10, 8)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	box.add_child(label)
