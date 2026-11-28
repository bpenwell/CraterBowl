extends "res://tests/visual/harness.gd"
## The football (#159): the ball alone from four sides, and seated in every hand socket
## (QB two-hand hold, carrier's one-arm tuck) on a frozen clip frame. Each cell is its own
## world with fixed lighting and camera; nothing depends on wall-clock time or frame count.

const PlayerView := preload("res://src/game/player.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Presentation := preload("res://src/game/presentation.gd")
const Football := preload("res://src/game/art/football.gd")
## Ball alone: [label, camera direction in ball space (+Z long axis, +Y laces)].
const ALONE := [["laces", Vector3(0.0, 1.0, 0.15)], ["side", Vector3(1.0, 0.05, 0.0)],
	["end", Vector3(0.1, 0.25, 1.0)], ["three-quarter", Vector3(0.7, 0.55, 0.6)]]
## In a socket: [label, two_hand, clip, time, camera direction: +Z in front of the athlete, +X his right].
const HELD := [["QB hold: front", true, "Idle", 0.4, Vector3(0.0, 0.25, 1.0)],
	["QB hold: side", true, "Idle", 0.4, Vector3(1.0, 0.2, 0.25)],
	["carry: front", false, "Sprint", 0.3, Vector3(-0.3, 0.2, 1.0)],
	["carry: side", false, "Sprint", 0.3, Vector3(-1.0, 0.25, 0.2)]]
const CELL := Vector2i(320, 300)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check_mesh()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	root.add_child(grid)
	for a in ALONE:
		var vp := _cell(grid, a[0])
		var ball := Presentation.make_ball()
		vp.add_child(ball)
		_camera(vp, Vector3.ZERO, a[1], 1.0, Vector3.UP if absf(a[1].normalized().y) < 0.95 else Vector3.FORWARD)
	for h in HELD:
		_held(_cell(grid, h[0]), h)
	for frame in 3:
		await process_frame
	await capture("football-sockets")
	finish()

func _check_mesh() -> void:
	var ball := Presentation.make_ball()
	var box := ball.mesh.get_aabb()
	check(ball.scale == Vector3.ONE, "the ball view needs no scale")
	check(box.size.z > 1.6 * box.size.x and absf(box.size.x - box.size.y) < 0.001,
		"long axis Z, round across it: %s" % box.size)
	check(absf(box.size.z - 2.0 * Football.HALF_LENGTH) < 0.001 and absf(box.size.x - 2.0 * Football.RADIUS) < 0.005,
		"built at size (%.2f x %.2f m)" % [box.size.z, box.size.x])
	# Pointed ends: at 90% of the half-length an ellipsoid is still 44% of its width; a football is far thinner.
	check(Football.radius_at(0.9 * Football.HALF_LENGTH) < 0.3 * Football.RADIUS, "the ends come to a point")
	ball.free()

func _held(vp: SubViewport, h: Array) -> void:
	var a = Athlete.new()
	a.id = 0
	a.role = Athlete.Role.QB if h[1] else Athlete.Role.RB
	var v = PlayerView.new()
	v.setup(a, Color(0.95, 0.75, 0.15))
	vp.add_child(v)
	v.set_process(false)   # hold the clip we pick and the pose weight we set
	var ball := Presentation.make_ball()
	vp.add_child(ball)
	v.set_carry(ball, h[1])
	v.pose.weight = 1.0
	v.anim.play(h[2], 0.0)
	v.anim.seek(h[3], true)
	v.anim.pause()
	var sk: Skeleton3D = v.mesh_i.get_parent()
	sk.force_update_all_bone_transforms()
	v.pose.apply(sk)
	sk.force_update_all_bone_transforms()
	var xf: Transform3D = sk.global_transform * v.ball_local(sk)
	ball.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	var c := ball.global_position
	var hr: Vector3 = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_r"))).origin
	var hl: Vector3 = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_l"))).origin
	if h[1]:
		var side: Vector3 = v.global_basis.x.normalized()
		check(signf((hr - c).dot(side)) != signf((hl - c).dot(side)), "%s: a hand on each side of the ball" % h[0])
		for p in [hr, hl]:
			var gap: float = absf((p - c).dot(side)) - Football.RADIUS
			check(gap > 0.0 and gap < 0.06, "%s: wrist %.3f m outside the ball's side" % [h[0], gap])
	else:
		var fore: Vector3 = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("lowerarm_r"))).origin
		# hand_r's origin is the wrist; the palm socket puts the ball's centre ~0.17 m from it.
		check(c.distance_to(hr) < 0.2, "%s: ball in the right palm (%.2f m from the wrist)" % [h[0], c.distance_to(hr)])
		check(absf(ball.global_basis.z.normalized().dot((hr - fore).normalized())) > 0.6, "%s: long axis along the forearm" % h[0])
	var facing: Basis = v.global_basis.orthonormalized()   # the view faces -Z
	_camera(vp, c, facing * Vector3(h[4].x, h[4].y, -h[4].z), 1.0, Vector3.UP)

func _cell(grid: GridContainer, text: String) -> SubViewport:
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
	var label := Label.new()
	label.text = text
	label.position = Vector2(10, 8)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	box.add_child(label)
	return vp

func _camera(vp: SubViewport, target: Vector3, dir: Vector3, dist: float, up: Vector3) -> void:
	var cam := Camera3D.new()
	cam.fov = 35.0
	vp.add_child(cam)
	cam.look_at_from_position(target + dir.normalized() * dist, target, up)
	cam.make_current()
