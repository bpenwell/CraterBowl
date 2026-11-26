extends Node3D
## Runtime presentation for a match: football model + spiral + trail, landing
## marker, controlled-player ring/chevron, sideline chains, tackle dust,
## touchdown fireworks, camera shake, crowd excitement, jumbotron, overlay.
## Runs as a child of main (after main's _process). Reads state; owns no rules.

const RC := preload("res://src/game/render_cache.gd")
const Mats := preload("res://src/game/art/materials.gd")
const Stadium := preload("res://src/game/art/stadium.gd")
const Overlay := preload("res://src/game/overlay.gd")
const LosBarrier := preload("res://src/game/art/los_barrier.gd")
const FieldArt := preload("res://src/game/art/field_art.gd")
const TRAIL_LEN := 22

var main: Node3D
var stadium: RefCounted
var overlay: Overlay
var ring: MeshInstance3D
var chevron: MeshInstance3D
const CHEVRON_COLOR := Color(0.36, 0.88, 1.0, 0.9)
## Camera distance (m) where the chevron starts fading / is gone: close cameras (third
## person, QB POV) already show who you are, and the marker would sit in the aim line.
const CHEVRON_FADE := Vector2(9.0, 5.0)
var carrier_glow: MeshInstance3D
var landing: MeshInstance3D
var trail_mesh := ImmediateMesh.new()
var trail: MeshInstance3D
var trail_pts: Array = []
var chains: Node3D
var down_box: Label3D
var stick_a: Node3D
var stick_b: Node3D
var excite := 0.0
var shake := 0.0
var spin := 0.0
var _last_score := [0, 0]
var barrier: LosBarrier
var _ends_behind := 0    # #89: end painted behind the offense (FieldArt.orient_ends)
var _period := 0         # #89: SWITCH ENDS banner on period change

func _ready() -> void:
	main = get_parent()
	name = "Presentation"
	ring = _ground_quad("PlayerRing", 2.2, "res://src/game/art/ring.gdshader")
	carrier_glow = _ground_quad("CarrierGlow", 1.8, "res://src/game/art/ring.gdshader")
	(carrier_glow.material_override as ShaderMaterial).set_shader_parameter("color", Color(1.0, 0.8, 0.3, 0.7))
	(carrier_glow.material_override as ShaderMaterial).set_shader_parameter("dashes", 0.0)
	landing = _ground_quad("LandingMarker", 2.0, "res://src/game/art/ring.gdshader")
	(landing.material_override as ShaderMaterial).set_shader_parameter("color", Color(1.0, 0.95, 0.4, 0.85))
	(landing.material_override as ShaderMaterial).set_shader_parameter("pulse", 1.0)
	chevron = MeshInstance3D.new()
	chevron.name = "Chevron"
	var pm := PrismMesh.new()
	pm.size = Vector3(0.32, 0.28, 0.08)
	chevron.mesh = pm
	chevron.rotation.z = PI
	# Unshaded + alpha (#116): emissive 2.5 bloomed to a white triangle in the QB's aim
	# line. Flat cyan reads as "you", and _update_rings fades it when the camera is close.
	chevron.material_override = Mats.flat(CHEVRON_COLOR)
	chevron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(chevron)
	trail = MeshInstance3D.new()
	trail.name = "BallTrail"
	trail.mesh = trail_mesh
	var tm := Mats.flat(Color(1, 1, 1, 1))
	tm.vertex_color_use_as_albedo = true
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	trail.material_override = tm
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail)
	overlay = Overlay.new()
	add_child(overlay)

## Rebuild per-field art (called from main.configure after the field exists).
func rebuild(field_root: Node3D) -> void:
	stadium = Stadium.build(field_root, main.field, main.TEAM_COLORS)
	chains = _build_chains(field_root)
	if barrier and is_instance_valid(barrier):
		barrier.queue_free()
	barrier = LosBarrier.new()
	barrier.setup(main.field.width)
	add_child(barrier)
	_last_score = [0, 0]
	_ends_behind = 0   # FieldArt.build paints HELIOS behind the offense
	_period = 0

func _ground_quad(n: String, size: float, shader: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = Mats.shader(shader)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

## Football: prolate leather spheroid with laces and end stripes.
static func make_ball() -> MeshInstance3D:
	var ball := MeshInstance3D.new()
	ball.name = "Ball"
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	sm.radial_segments = 16
	sm.rings = 10
	ball.mesh = sm
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.5, 0.24, 0.1)
	leather.roughness = 0.55
	leather.rim_enabled = true
	leather.rim = 0.3
	ball.material_override = leather
	ball.scale = Vector3(1, 1, 1.75)
	var white := Mats.cloth(Color(0.97, 0.97, 0.95))
	var laces := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.03, 0.025, 0.11)
	laces.mesh = lb
	laces.material_override = white
	laces.position = Vector3(0, 0.148, 0)
	ball.add_child(laces)
	for z in [-0.085, 0.085]:
		var band := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.105
		tm.outer_radius = 0.125
		band.mesh = tm
		band.material_override = white
		band.position.z = z
		band.rotation.x = PI / 2.0
		band.scale = Vector3(1, 0.35, 1)
		ball.add_child(band)
	return ball

func _build_chains(root: Node3D) -> Node3D:
	var n := Node3D.new()
	n.name = "Chains"
	root.add_child(n)
	var orange := Mats.emissive(Color(1.0, 0.42, 0.08), 0.9)
	var pole := Mats.cloth(Color(0.1, 0.1, 0.12))
	stick_a = _stick(n, pole, orange)
	_sign(stick_a, "LOS")
	stick_b = _stick(n, pole, orange)
	_sign(stick_b, "1ST")
	var box := _stick(n, pole, orange)
	box.name = "DownBox"
	down_box = _sign(box, "")
	return n

func _sign(parent: Node3D, text: String) -> Label3D:
	var sign := Label3D.new()
	sign.text = text
	sign.font = Mats.number_font()
	sign.font_size = 72
	sign.pixel_size = 0.004
	sign.position = Vector3(-0.085, 2.55, 0)
	sign.rotation.y = -PI / 2.0
	sign.outline_size = 8
	sign.modulate = Color(1.0, 0.96, 0.82)
	parent.add_child(sign)
	return sign

func _stick(parent: Node3D, pole_mat: Material, top_mat: Material) -> Node3D:
	var s := Node3D.new()
	parent.add_child(s)
	var p := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.05
	c.bottom_radius = 0.05
	c.height = 2.55
	p.mesh = c
	p.material_override = pole_mat
	p.position.y = c.height * 0.5
	s.add_child(p)
	var t := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.16, 0.44, 0.65)
	t.mesh = b
	t.material_override = top_mat
	t.position.y = 2.55
	s.add_child(t)
	_crew_member(s)
	return s

func _crew_member(parent: Node3D) -> void:
	var uniform := Mats.cloth(Color(0.98, 0.52, 0.08))
	var trousers := Mats.cloth(Color(0.12, 0.15, 0.2))
	var skin := Mats.cloth(Color(0.57, 0.34, 0.22))
	var shoes := Mats.cloth(Color(0.06, 0.07, 0.09))
	var reflective := Mats.cloth(Color(0.92, 0.95, 0.8))
	var crew := Node3D.new()
	crew.name = "ChainCrew"
	crew.position.x = 0.5
	parent.add_child(crew)
	# Only the torso casts: 13 casters per crew member blew the shadow budget (each caster is
	# redrawn per shadow split) and the limbs' shadows are invisible at the sideline.
	_crew_part(crew, Vector3(0, 1.24, 0), Vector3(0.31, 0.53, 0.47), uniform).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_crew_part(crew, Vector3(-0.005, 1.16, 0), Vector3(0.32, 0.055, 0.48), reflective)
	_crew_part(crew, Vector3(0, 1.63, 0), Vector3(0.24, 0.28, 0.26), skin)
	_crew_part(crew, Vector3(0, 1.78, 0), Vector3(0.27, 0.11, 0.29), shoes)
	_crew_part(crew, Vector3(-0.12, 1.75, 0), Vector3(0.25, 0.04, 0.25), shoes)
	for side in [-1, 1]:
		_crew_part(crew, Vector3(0, 0.52, side * 0.12), Vector3(0.2, 0.94, 0.19), trousers)
		_crew_part(crew, Vector3(-0.05, 0.08, side * 0.12), Vector3(0.32, 0.13, 0.2), shoes)
		_crew_part(crew, Vector3(-0.05, 1.29, side * 0.27), Vector3(0.19, 0.25, 0.17), uniform)
		var grip := _crew_part(crew, Vector3(-0.29, 1.28 + side * 0.11, side * 0.14),
			Vector3(0.46, 0.115, 0.12), skin)
		grip.rotation.z = -side * 0.35
		grip.rotation.y = -side * 0.48

func _crew_part(parent: Node3D, at: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = RC.sphere(0.5, 1.0, 12, 6)   # shared (was one SphereMesh per part)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.material_override = material
	part.scale = dimensions
	part.position = at
	parent.add_child(part)
	return part

# --- events -----------------------------------------------------------------

func on_event(n: String, d: Dictionary) -> void:
	if not is_inside_tree():
		return
	match n:
		"tackle", "sack":
			var id: int = d.get("carrier", d.get("by", -1))
			var at := _athlete_pos(id)
			_dust(at, 22)
			shake = maxf(shake, 0.35)
			if id >= 0 and id < main.views.size():
				main.views[id].hit()
		"touchdown":
			excite = 1.0
			shake = maxf(shake, 0.25)
			_fireworks()
		"interception", "fumble":
			excite = maxf(excite, 0.7)
			shake = maxf(shake, 0.2)
		"catch":
			excite = maxf(excite, 0.35)
		"throw":
			var by := int(d.get("by", -1))
			if by >= 0 and by < main.views.size():
				main.views[by].throw_release()
		"breakup":
			_dust(_athlete_pos(int(d.get("by", -1))), 8)
	overlay.on_event(n, d)

func _athlete_pos(id: int) -> Vector3:
	if id >= 0 and id < main.views.size():
		return main.views[id].global_position
	var b = main.world.ball.position
	return Vector3(b.x, 0, -b.y)

func _dust(at: Vector3, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -2.5, 0)   # low lunar gravity: dust hangs
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.6
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var m := Mats.flat(Color(0.75, 0.72, 0.68, 0.55))
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	var g := Gradient.new()
	g.set_color(0, Color(0.8, 0.78, 0.74, 0.6))
	g.set_color(1, Color(0.8, 0.78, 0.74, 0.0))
	p.color_ramp = g
	p.position = at + Vector3(0, 0.3, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)

func _fireworks() -> void:
	var f = main.field
	for i in 6:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.amount = 60
		p.lifetime = 1.6
		p.explosiveness = 1.0
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = 6.0
		p.initial_velocity_max = 10.0
		p.gravity = Vector3(0, -3.0, 0)
		p.scale_amount_min = 0.15
		p.scale_amount_max = 0.3
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 4
		sm.rings = 2
		p.mesh = sm
		var c: Color = main.TEAM_COLORS[i % 2] if i < 4 else Color(1, 1, 1)
		p.material_override = Mats.emissive(c, 4.0)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		p.color_ramp = g
		var side := -1.0 if i % 2 == 0 else 1.0
		p.position = Vector3(f.width * 0.5 + side * (f.width * 0.5 + 14.0), 22.0 + (i % 3) * 5.0, -f.length * (0.2 + 0.3 * float(i / 2)))
		add_child(p)
		get_tree().create_timer(0.25 * i).timeout.connect(func(): if is_instance_valid(p): p.emitting = true)
		get_tree().create_timer(3.5).timeout.connect(p.queue_free)

# --- per frame --------------------------------------------------------------

func _process(delta: float) -> void:
	if main == null or main.world == null or main.views.is_empty():
		return
	var w = main.world
	if not main.replay_active:
		_update_ball(delta, w)
	_update_rings(w)
	_update_chains()
	if barrier:
		barrier.update(w, delta, main.my_id)
	excite = maxf(0.0, excite - delta * 0.18)
	if stadium:
		stadium.set_excitement(excite)
		var s = main.series
		if s:
			if (main.is_server() or main.is_client()) and main.in_lobby():
				stadium.set_scoreboard("PRIVATE MATCH LOBBY")
			else:
				stadium.set_scoreboard("HELIOS %d   NEBULA %d\n%s" % [s.score[0], s.score[1], s.clock.label()])
			if s.score[0] != _last_score[0] or s.score[1] != _last_score[1]:
				_last_score = [s.score[0], s.score[1]]
			_update_ends(s, w)
	# Camera shake (main already placed the camera this frame).
	if shake > 0.0 and main.camera:
		shake = maxf(0.0, shake - delta)
		var a := shake * shake * 1.2
		main.camera.position += Vector3(randf_range(-a, a), randf_range(-a, a), 0)
	overlay.refresh(main, delta)

## #89: switch ends each period; the end zones re-orient whenever the offense or
## the period changes (change-driven, no per-frame shader pushes).
func _update_ends(s, w) -> void:
	var behind: int = s.defended_end(w.offense_team)
	if behind != _ends_behind:
		_ends_behind = behind
		FieldArt.orient_ends(main.field_root, behind, main.TEAM_COLORS)
	var period: int = s.clock.period()
	if period != _period:
		if period > _period and not s.is_final() and main.drill == null:
			overlay.show_banner("SWITCH ENDS", "START OF " + s.clock.label().get_slice(" ", 0), overlay.ACCENT, 2.4)
		_period = period

func _update_ball(delta: float, w) -> void:
	var bv: Node3D = main.ball_view
	if bv == null:
		return
	var b = w.ball
	var st := int(b.state)
	var held_view = main.views[b.holder_id] if st in [0, 3] and b.holder_id >= 0 and b.holder_id < main.views.size() else null
	if held_view != null and not held_view.is_celebrating():
		bv.scale = Vector3.ONE
		bv.global_position = held_view.hand_position() + held_view.global_transform.basis.z * 0.08
		bv.global_rotation = Vector3(-0.5, held_view.global_rotation.y, 0)
		spin = 0.0
	elif st == 1:   # in flight: point along velocity, spiral
		var v := Vector3(b.velocity.x, b.velocity.z, -b.velocity.y)
		if v.length() > 0.5:
			var t := Transform3D(Basis.looking_at(v.normalized(), Vector3.UP), bv.global_position)
			spin += delta * 28.0
			t.basis = t.basis.rotated(v.normalized(), spin)
			bv.global_transform = t.scaled_local(Vector3(1, 1, 1.75))
	elif st == 2:   # loose: tumble
		bv.scale = Vector3.ONE
		spin += delta * 9.0
		bv.rotation = Vector3(spin, spin * 0.7, 0)
	# Trail while airborne. (Skip the GPU re-upload when there's no trail at all.)
	if trail_pts.is_empty() and st != 1:
		if trail_mesh.get_surface_count() > 0:
			trail_mesh.clear_surfaces()
		landing.visible = false
		return
	trail_mesh.clear_surfaces()
	if st == 1:
		trail_pts.push_front(bv.global_position)
		if trail_pts.size() > TRAIL_LEN:
			trail_pts.pop_back()
	elif not trail_pts.is_empty():
		trail_pts.pop_back()
	if trail_pts.size() >= 2 and main.camera:
		trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in trail_pts.size():
			var p: Vector3 = trail_pts[i]
			var nxt: Vector3 = trail_pts[mini(i + 1, trail_pts.size() - 1)]
			var dir: Vector3 = (p - nxt) if i < trail_pts.size() - 1 else (trail_pts[i - 1] - p)
			var side: Vector3 = dir.cross(main.camera.global_position - p).normalized()
			var f := 1.0 - float(i) / trail_pts.size()
			var wdt := 0.12 * f
			trail_mesh.surface_set_color(Color(1.0, 0.95, 0.75, 0.55 * f))
			trail_mesh.surface_add_vertex(p + side * wdt)
			trail_mesh.surface_set_color(Color(1.0, 0.95, 0.75, 0.55 * f))
			trail_mesh.surface_add_vertex(p - side * wdt)
		trail_mesh.surface_end()
	# Predicted landing spot for passes in flight.
	landing.visible = false
	if st == 1:
		var g: float = w.gravity()
		var vz: float = b.velocity.z
		var z: float = b.position.z
		var disc := vz * vz + 2.0 * g * z
		if g > 0.0 and disc >= 0.0:
			var t := (vz + sqrt(disc)) / g
			var p := Vector2(b.position.x, b.position.y) + Vector2(b.velocity.x, b.velocity.y) * t
			landing.position = Vector3(p.x, 0.04, -p.y)
			landing.visible = true

var _ring_team := -1

func _update_rings(w) -> void:
	var pv: Node3D = main.player
	ring.visible = pv != null
	if pv:
		ring.position = Vector3(pv.global_position.x, 0.035, pv.global_position.z)
		var tc: Color = main.TEAM_COLORS[pv.athlete.team]
		if pv.athlete.team != _ring_team:
			_ring_team = pv.athlete.team
			(ring.material_override as ShaderMaterial).set_shader_parameter("color", Color(tc.r, tc.g, tc.b, 0.9))
		chevron.position = pv.global_position + Vector3(0, 2.45 + sin(Time.get_ticks_msec() * 0.005) * 0.08, 0)
		chevron.rotation.y += 0.04
		var cam: Camera3D = main.camera
		var dist := cam.global_position.distance_to(chevron.position) if cam else 99.0
		var a := clampf(inverse_lerp(CHEVRON_FADE.y, CHEVRON_FADE.x, dist), 0.0, 1.0)
		chevron.visible = a > 0.01
		(chevron.material_override as StandardMaterial3D).albedo_color.a = CHEVRON_COLOR.a * a
	var b = w.ball
	var hv = main.views[b.holder_id] if int(b.state) == 0 and b.holder_id >= 0 and b.holder_id < main.views.size() else null
	carrier_glow.visible = hv != null and hv != pv and int(w.phase) == 1
	if carrier_glow.visible:
		carrier_glow.position = Vector3(hv.global_position.x, 0.03, hv.global_position.z)

func _update_chains() -> void:
	var s = main.series
	if chains == null or s == null or not is_instance_valid(chains):
		return
	var x: float = main.field.width + 4.5
	stick_a.position = Vector3(x, 0, -s.downs.los)
	stick_b.position = Vector3(x, 0, -s.downs.first_down_y)
	stick_b.visible = not s.downs.is_goal_to_go()
	var box: Node3D = down_box.get_parent()
	box.position = Vector3(x + 2.3, 0, -s.downs.los)
	down_box.text = str(s.downs.down)
