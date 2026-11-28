extends Node3D
## Runtime presentation for a match: football model + spiral + trail, landing
## marker, controlled-player ground ring, sideline chains, tackle dust,
## touchdown fireworks, camera shake, crowd excitement, jumbotron, overlay.
## Runs as a child of main (after main's _process). Reads state; owns no rules.

const RC := preload("res://src/game/render_cache.gd")
const Mats := preload("res://src/game/art/materials.gd")
const Stadium := preload("res://src/game/art/stadium.gd")
const Football := preload("res://src/game/art/football.gd")
const Overlay := preload("res://src/game/overlay.gd")
const LosBarrier := preload("res://src/game/art/los_barrier.gd")
const FieldArt := preload("res://src/game/art/field_art.gd")
const KickArt := preload("res://src/game/kick_art.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Passing := preload("res://src/sim/passing.gd")
const TRAIL_LEN := 22

var main: Node3D
var stadium: RefCounted
var overlay: Overlay
var ring: MeshInstance3D
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
var _dead_ball_start_y := -1.0
var _dead_ball_fall_time := 0.0
var _carrier = null   # view carrying the ball (player.gd), for the carry pose
var _last_score := [0, 0]
var barrier: LosBarrier
var _pass_thrower := -1
var kick_art: KickArt    # #68: kick power meter + kickoff tee
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
	kick_art = KickArt.new()
	add_child(kick_art)
	overlay = Overlay.new()
	add_child(overlay)

## Rebuild per-field art (called from main.configure after the field exists).
func rebuild(field_root: Node3D) -> void:
	_pass_thrower = -1
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
	_dead_ball_start_y = -1.0

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

## Football: pointed leather spheroid with seams, laces and end stripes (art/football.gd, #159).
static func make_ball() -> MeshInstance3D:
	var ball := MeshInstance3D.new()
	ball.name = "Ball"
	ball.mesh = Football.mesh()
	ball.material_override = Football.material()
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
				if d.has("carrier"):
					_tackle_fall(id, int(d.get("by", -1)))
				else:
					main.views[id].hit()
		"touchdown":
			excite = 1.0
			shake = maxf(shake, 0.25)
			_fireworks()
		"interception", "fumble":
			excite = maxf(excite, 0.7)
			shake = maxf(shake, 0.2)
			var c := int(d.get("carrier", -1))
			if n == "fumble" and c >= 0 and c < main.views.size():
				_tackle_fall(c, int(d.get("by", -1)), true)   # stripped: down hard, then scrambles up
		"catch":
			excite = maxf(excite, 0.35)
		"snap":
			_pass_thrower = -1
		"throw":
			_pass_thrower = int(d.get("by", -1))
			if _pass_thrower >= 0 and _pass_thrower < main.views.size():
				main.views[_pass_thrower].throw_release()
		"breakup":
			_dust(_athlete_pos(int(d.get("by", -1))), 8)
	overlay.on_event(n, d)

## A tackled carrier's fall (tackle_fall.gd), from the collision: the tackler hits him at
## CONTACT_HEIGHT on the side he came from, with an impulse of TACKLE_MASS times their closing
## velocity. Every tackle is a dive (world.gd), which wraps the thighs.
const TACKLE_MASS := 18.0   # the carrier's ragdoll weighs 82; tuned so a hit reads from the game camera
const CONTACT_HEIGHT := 0.55   # yd

func _tackle_fall(carrier: int, by: int, fumble := false) -> void:
	var run := _sim_velocity(carrier)
	if fumble:   # the sim already slowed him (world.gd _fumble): use how he was moving into the hit
		run = main.views[carrier]._vel
		run.y = 0.0
	var at: Vector3 = main.views[carrier].global_position
	var impulse := Vector3.ZERO   # no tackler (the carrier's own dive): he just goes down
	var side := -run.normalized()
	if main.world.get_athlete(by) != null:
		impulse = (_sim_velocity(by) - run) * TACKLE_MASS
		side = main.views[by].global_position - at
		side.y = 0.0
		side = side.normalized()
	main.views[carrier].tackled(run, impulse, at + Vector3.UP * CONTACT_HEIGHT + side * 0.2, fumble)

## The sim stops everyone at the whistle, before this event: fall back to how the view was
## actually moving (smoothed over the last frames, so it holds the speed at contact).
func _sim_velocity(id: int) -> Vector3:
	var a = main.world.get_athlete(id)
	var v := Vector3(a.velocity.x, 0.0, -a.velocity.y) if a != null else Vector3.ZERO
	if v.length() < 0.5 and id >= 0 and id < main.views.size():
		v = main.views[id]._vel
		v.y = 0.0
	return v

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
		# Bound to p, not a lambda capturing p: freeing the scene drops the connection (#250).
		get_tree().create_timer(0.25 * i).timeout.connect(p.set_emitting.bind(true))
		get_tree().create_timer(3.5).timeout.connect(p.queue_free)

# --- per frame --------------------------------------------------------------

func _process(delta: float) -> void:
	if main == null or main.world == null or main.views.is_empty():
		return
	var w = main.world
	kick_art.update(main, w)   # before the ball: a kickoff ball stands on the tee
	if not main.replay_active:
		_update_ball(delta, w)
	else:
		_set_carrier(null, false)   # replays don't record the holder: the ball flies free
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
			overlay.show_banner("SWITCH ENDS", s.clock.label().get_slice(" ", 0), overlay.ACCENT, 2.4)
		_period = period

## Hand the ball view to the athlete carrying it (null: nobody), so its arm tucks it.
func _set_carrier(view, two_hand: bool) -> void:
	if _carrier != view and _carrier != null and is_instance_valid(_carrier):
		_carrier.set_carry(null)
	_carrier = view
	if view != null:
		view.set_carry(main.ball_view, two_hand)

func _update_ball(delta: float, w) -> void:
	var bv: Node3D = main.ball_view
	if bv == null:
		return
	var b = w.ball
	var st := int(b.state)
	var unheld_dead_ball: bool = st == 3 and b.holder_id < 0
	if not unheld_dead_ball:
		_dead_ball_start_y = -1.0
	var held_view = main.views[b.holder_id] if st in [0, 3] and b.holder_id >= 0 and b.holder_id < main.views.size() else null
	if held_view != null and held_view.is_celebrating():
		held_view = null
	if held_view != null and KickArt.ball_on_tee(w):   # #68: on the tee, not in his hand
		held_view = null   # so the kicker's arm lets go of it below
		bv.global_transform = kick_art.ball_transform()
		spin = 0.0
		st = -1   # placed; only the trail bookkeeping below still runs
	var holder = w.get_athlete(b.holder_id) if held_view != null else null
	_set_carrier(held_view, holder != null and holder.role == Athlete.Role.QB and w.can_throw(b.holder_id))
	if held_view != null:
		# Seated in the carrier's palm; the view re-pins it after its skeleton updates (#244).
		bv.global_transform = held_view.ball_transform()
		spin = 0.0
	elif st == 1:   # in flight: point along velocity, spiral
		var v := Vector3(b.velocity.x, b.velocity.z, -b.velocity.y)
		if v.length() > 0.5:
			var t := Transform3D(Basis.looking_at(v.normalized(), Vector3.UP), bv.global_position)
			spin += delta * 28.0
			t.basis = t.basis.rotated(v.normalized(), spin)
			bv.global_transform = t
	elif st == 2:   # loose: rolls about its long axis and slews, lying on the turf (#159)
		spin += delta * 9.0
		bv.basis = Basis(Vector3.UP, spin * 0.7) * Basis(Vector3.BACK, spin)
		bv.position.y = maxf(bv.position.y, Football.RADIUS)   # the sim's ball centre is at z 0 on the ground
	elif st == 3:
		bv.basis = Basis()
		if unheld_dead_ball:
			# Physics keeps the contact point for the ruling. On clients, the first
			# rendered height may still come from the interpolated pass flight.
			if _dead_ball_start_y < 0.0:
				_dead_ball_start_y = maxf(bv.position.y, Football.RADIUS)
				_dead_ball_fall_time = 0.0
			_dead_ball_fall_time += delta
			var fall: float = 0.5 * w.gravity() * _dead_ball_fall_time * _dead_ball_fall_time
			bv.position.y = _dead_ball_start_y - fall
		bv.position.y = maxf(bv.position.y, Football.RADIUS)
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
	landing.visible = st == 1 and (not w.forward_pass_thrown or _can_see_pass_marker(w))
	if landing.visible:
		var p := Passing.ground_landing(b.position, b.velocity, w.gravity())
		landing.position = Vector3(p.x, 0.04, -p.y)

func _can_see_pass_marker(w) -> bool:
	# The reliable throw event identifies the passer to clients. A snapshot can arrive first.
	var viewer = w.get_athlete(main.my_id)
	return main.lobby.settings["pass_marker"] and _pass_thrower >= 0 and viewer != null \
		and viewer.id != _pass_thrower and w.is_eligible_receiver(viewer)

var _ring_team := -1

func _update_rings(w) -> void:
	var pv: Node3D = main.player
	ring.visible = pv != null
	if pv:
		ring.position = pv.ground_position() + Vector3(0, 0.035, 0)   # under the body, also while he's down
		var tc: Color = main.TEAM_COLORS[pv.athlete.team]
		if pv.athlete.team != _ring_team:
			_ring_team = pv.athlete.team
			(ring.material_override as ShaderMaterial).set_shader_parameter("color", Color(tc.r, tc.g, tc.b, 0.9))
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
