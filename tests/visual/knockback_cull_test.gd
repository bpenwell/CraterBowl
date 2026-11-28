extends "res://tests/visual/harness.gd"
## #173: the rig draws under both uniforms while a close camera follows the hit pose.

const PlayerView := preload("res://src/game/player.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const CELL := Vector2i(320, 360)
const POSES := [["Idle", 0.4], ["Sprint", 0.25], ["u2/Slide_Start", 0.3], ["u2/Slide", 0.4],
	["u2/Idle_No", 0.6], ["u2/Idle_TalkingPhone", 0.8], ["Dance", 0.7], ["u2/Hit_Knockback", 0.3]]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _capture_uniform(false, "knockback-local")
	await _capture_uniform(true, "knockback-opponent")
	finish()

func _capture_uniform(opponent: bool, capture_name: String) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	root.add_child(grid)
	var skins: Array[MeshInstance3D] = []
	for i in POSES.size():
		skins.append(_cell(grid, i, opponent))
	await process_frame
	await process_frame
	await _render()
	await capture(capture_name)
	var frame := root.get_texture().get_image()
	skins.front().hide()
	skins.back().hide()
	await _render()
	var hidden := root.get_texture().get_image()
	var idle_cell := Rect2i(Vector2i.ZERO, CELL)
	var hit_cell := Rect2i(Vector2i(3 * CELL.x, CELL.y), CELL)
	check(frame.get_region(idle_cell).get_data() != hidden.get_region(idle_cell).get_data(),
		"%s uniform body draws in idle" % capture_name)
	check(frame.get_region(hit_cell).get_data() != hidden.get_region(hit_cell).get_data(),
		"%s uniform body draws in knockback" % capture_name)
	grid.queue_free()
	await process_frame

func _cell(grid: GridContainer, index: int, opponent: bool) -> MeshInstance3D:
	var box := SubViewportContainer.new()
	box.custom_minimum_size = CELL
	box.stretch = true
	grid.add_child(box)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = CELL
	box.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.10, 0.11, 0.14)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.64, 0.7)
	environment.ambient_light_energy = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	viewport.add_child(sun)

	var athlete := Athlete.new()
	athlete.id = index
	athlete.role = Athlete.Role.WR
	var view := PlayerView.new()
	view.setup(athlete, Color(0.78, 0.16, 0.18), null, opponent)
	viewport.add_child(view)
	view.set_process(false)
	var pose: Array = POSES[index]
	view.anim.play(pose[0], 0.0)
	view.anim.seek(pose[1], true)
	view.anim.pause()
	var skeleton := view.mesh_i.get_parent() as Skeleton3D
	skeleton.force_update_all_bone_transforms()
	var head := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Head"))
	head = head.orthonormalized()
	var target := head * Vector3(0, 0.12, 0.01)
	var camera := Camera3D.new()
	camera.fov = 32.0
	viewport.add_child(camera)
	var offset := head.basis * Vector3(1.0, 0.08, 0.02).normalized() * 0.95
	camera.look_at_from_position(target + offset, target, head.basis.y)
	camera.make_current()
	var label := Label.new()
	label.text = "Knockback" if index == POSES.size() - 1 else str(pose[0]).get_file()
	label.position = Vector2(10, 8)
	label.add_theme_font_size_override("font_size", 18)
	box.add_child(label)
	return view._opponent_mesh if opponent else view.mesh_i

func _render() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
