extends RefCounted
## "Crater Bowl": an original lunar stadium built inside a crater. Bowl seating
## with an instanced crowd, LED ribbon boards, light towers, dome arches,
## jumbotrons, crater rim and regolith. Purely visual.

const Mats := preload("res://src/game/art/materials.gd")
const Quality := preload("res://src/game/art/quality.gd")

var root: Node3D
var crowd_mat: ShaderMaterial
var ribbon_mats: Array = []
var jumbo_labels: Array = []
var center := Vector3.ZERO

## Build the stadium around a sim field. Returns self for later updates.
static func build(parent: Node3D, field, team_colors: Array, crowd_density: float = -1.0) -> RefCounted:
	if crowd_density < 0.0:
		crowd_density = {"low": 0.3, "medium": 0.6, "high": 1.0}[Quality.level()]
	var s = load("res://src/game/art/stadium.gd").new()
	s._build(parent, field, team_colors, crowd_density)
	return s

func _build(parent: Node3D, field, team_colors: Array, density: float) -> void:
	root = Node3D.new()
	root.name = "Stadium"
	parent.add_child(root)
	var w: float = field.width
	var Lt: float = field.length + field.endzone_depth * 2.0
	center = Vector3(w / 2.0, 0, -field.length / 2.0)
	var hx := w / 2.0 + 12.0
	var hz := Lt / 2.0 + 10.0
	_ground()
	_crater_rim()
	# Lower bowl, concourse ribbon, upper deck.
	_bowl(hx, hz, 0.0, 0.6, 14, 1.15, 0.62, team_colors, density, "Lower")
	var up_off := 14 * 1.15 + 3.0
	_ribbon(hx + up_off - 1.2, hz + up_off - 1.2, 14 * 0.62 + 0.6, 1.4, "Fascia")
	_bowl(hx + up_off, hz + up_off, 14 * 0.62 + 2.6, 0.0, 12, 1.2, 0.78, team_colors, density, "Upper")
	_ribbon(hx - 0.6, hz - 0.6, 0.0, 1.3, "Wall")
	var outer_x := hx + up_off + 12 * 1.2
	var outer_z := hz + up_off + 12 * 1.2
	_towers(outer_x, outer_z)
	_arches(outer_x, outer_z, Lt)
	_jumbotrons(outer_x, outer_z, team_colors)
	_benches(w, field.length, team_colors)

## Rounded-rectangle (superellipse) contour, offset outward by d.
static func _contour(hx: float, hz: float, d: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var e := 2.0 / 5.0
	for i in n:
		var t := TAU * float(i) / float(n)
		var c := cos(t)
		var s := sin(t)
		pts.append(Vector2(signf(c) * pow(absf(c), e) * (hx + d), signf(s) * pow(absf(s), e) * (hz + d)))
	return pts

func _mesh_node(name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = mat
	root.add_child(mi)
	return mi

## Stepped seating bowl + crowd instances on each tread.
func _bowl(hx: float, hz: float, base_h: float, start_d: float, rows: int, tread: float, riser: float,
		team_colors: Array, density: float, tag: String) -> void:
	var N := 160
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var people: Array = []   # [pos, yaw, color]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tag) + int(hx * 10.0)
	for r in rows:
		var d0 := start_d + r * tread
		var h := base_h + 1.0 + r * riser
		var inner := _contour(hx, hz, d0, N)
		var outer := _contour(hx, hz, d0 + tread, N)
		var seat := Color(0.16, 0.19, 0.3) if r % 2 == 0 else Color(0.13, 0.16, 0.26)
		for i in N:
			var j := (i + 1) % N
			var a := Vector3(inner[i].x, h, inner[i].y)
			var b := Vector3(inner[j].x, h, inner[j].y)
			var c := Vector3(outer[j].x, h, outer[j].y)
			var dd := Vector3(outer[i].x, h, outer[i].y)
			_quad(st, a, b, c, dd, seat)                       # tread
			var lo := h - riser
			_quad(st, Vector3(a.x, lo, a.z), Vector3(b.x, lo, b.z), b, a, Color(0.3, 0.32, 0.38))  # riser
		# Crowd along this row, spaced by arc length with aisles.
		var mid := _contour(hx, hz, d0 + tread * 0.5, 720)
		var acc := 0.0
		for i in mid.size():
			var p0 := mid[i]
			var p1 := mid[(i + 1) % mid.size()]
			var seg := p0.distance_to(p1)
			acc += seg
			if acc < 0.85:
				continue
			acc = 0.0
			if fmod(float(i), 60.0) < 2.0 or rng.randf() > 0.9 * density:
				continue   # aisles + empty seats
			var dir := (p1 - p0).normalized()
			var yaw := atan2(-dir.y, dir.x) + PI   # face the field (inward)
			var home_side := p0.x < 0.0   # home fans fill the near sideline, visitors the far one
			var tc: Color = team_colors[0 if (home_side == (rng.randf() < 0.75)) else 1]
			var col := tc if rng.randf() < 0.55 else Color.from_hsv(rng.randf(), rng.randf_range(0.1, 0.5), rng.randf_range(0.25, 0.9))
			people.append([Vector3(p0.x, h, p0.y), yaw, col, rng.randf()])
	var mesh := st.commit()
	var bowl := _mesh_node("Bowl" + tag, mesh, _vertex_color_mat())
	bowl.position = center
	if not people.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _person_mesh()
		mm.instance_count = people.size()
		for k in people.size():
			var pp: Array = people[k]
			var sc := 0.85 + float(pp[3]) * 0.3
			var basis := Basis(Vector3.UP, float(pp[1])).scaled(Vector3(sc, sc, sc))
			mm.set_instance_transform(k, Transform3D(basis, pp[0]))
			mm.set_instance_color(k, pp[2])
			mm.set_instance_custom_data(k, Color(float(pp[3]), rng.randf(), 0, 0))
		if crowd_mat == null:
			crowd_mat = Mats.shader("res://src/game/art/crowd.gdshader")
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Crowd" + tag
		mmi.multimesh = mm
		mmi.material_override = crowd_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.position = center
		root.add_child(mmi)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var nrm := (b - a).cross(d - a).normalized()
	if nrm.y < -0.01 or (absf(nrm.y) < 0.01 and Vector2(nrm.x, nrm.z).dot(Vector2(a.x, a.z)) > 0.0):
		nrm = -nrm
	st.set_color(col)
	st.set_normal(nrm)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)

static func _vertex_color_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = load("res://assets/textures/concrete/Concrete034_1K-JPG_Color.jpg")
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/concrete/Concrete034_1K-JPG_NormalGL.jpg")
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

static func _person_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_into(st, Vector3(0, 0.45, 0), Vector3(0.46, 0.62, 0.3))
	_box_into(st, Vector3(0, 0.92, 0), Vector3(0.24, 0.26, 0.24))
	st.generate_normals()
	return st.commit()

static func _box_into(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var v := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	for f in faces:
		for idx in [f[0], f[1], f[2], f[0], f[2], f[3]]:
			st.add_vertex(c + v[idx])

## Vertical LED ribbon board following a contour.
func _ribbon(hx: float, hz: float, base_h: float, height: float, tag: String) -> void:
	var pts := _contour(hx, hz, 0.0, 160)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u := 0.0
	for i in pts.size():
		var p0 := pts[i]
		var p1 := pts[(i + 1) % pts.size()]
		var u1 := u + p0.distance_to(p1)
		var a := Vector3(p0.x, base_h, p0.y)
		var b := Vector3(p1.x, base_h, p1.y)
		var nrm := -Vector3(p0.x + p1.x, 0, p0.y + p1.y).normalized()
		for vv in [[a, u, 0.0], [b, u1, 0.0], [b + Vector3.UP * height, u1, 1.0], [a, u, 0.0], [b + Vector3.UP * height, u1, 1.0], [a + Vector3.UP * height, u, 1.0]]:
			st.set_normal(nrm)
			st.set_uv(Vector2(vv[1], vv[2]))
			st.add_vertex(vv[0])
		u = u1
	var m := Mats.shader("res://src/game/art/ribbon.gdshader")
	m.set_shader_parameter("height", height)
	ribbon_mats.append(m)
	_mesh_node("Ribbon" + tag, st.commit(), m).position = center

func _towers(ox: float, oz: float) -> void:
	var col_mat := Mats.brushed(Color(0.75, 0.78, 0.85))
	var lamp := Mats.shader("res://src/game/art/lamp.gdshader")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 0.0, 1.0]:
			var p := center + Vector3(sx * (ox + 4.0), 0, sz * (oz * 0.62))
			var h := 52.0 if sz != 0.0 else 44.0
			var mast := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.6
			c.bottom_radius = 1.4
			c.height = h
			c.radial_segments = 8
			mast.mesh = c
			mast.material_override = col_mat
			mast.position = p + Vector3(0, h / 2.0, 0)
			mast.name = "TowerMast"
			root.add_child(mast)
			var head := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(10, 6, 0.5)
			head.mesh = b
			head.material_override = lamp
			head.name = "TowerLamps"
			root.add_child(head)
			head.position = p + Vector3(0, h + 2.0, 0)
			head.look_at(center + Vector3(0, 0, 0), Vector3.UP)
			head.rotate_object_local(Vector3.UP, PI)
			if not (Quality.level() == "high" and sz == 0.0):
				continue
			var light := OmniLight3D.new()
			light.position = p + Vector3(0, h, 0) + (center - p).normalized() * 6.0
			light.omni_range = 140.0
			light.omni_attenuation = 0.6
			light.light_energy = 0.55 if sz != 0.0 else 0.35
			light.light_color = Color(1.0, 0.96, 0.88)
			light.shadow_enabled = false
			light.name = "TowerLight"
			root.add_child(light)

## Dome trusses: half-buried tori read as arches over the bowl.
func _arches(ox: float, oz: float, Lt: float) -> void:
	var rim := Mats.emissive(Color(0.36, 0.88, 1.0), 2.4)
	var steel := Mats.brushed(Color(0.55, 0.58, 0.66))
	var R := ox + 6.0
	for k in 5:
		var z := lerpf(-oz * 0.75, oz * 0.75, float(k) / 4.0)
		for pair in [[R, R - 0.9, steel, "ArchSteel"], [R - 0.9, R - 1.15, rim, "ArchGlow"]]:
			var t := TorusMesh.new()
			t.outer_radius = pair[0]
			t.inner_radius = pair[1]
			t.rings = 96
			t.ring_segments = 6
			var mi := _mesh_node(pair[3], t, pair[2])
			mi.position = center + Vector3(0, -6.0, z)
			mi.rotation = Vector3(PI / 2.0, 0, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _jumbotrons(ox: float, oz: float, team_colors: Array) -> void:
	for sz in [-1.0, 1.0]:
		var p := center + Vector3(0, 0, sz * (oz + 8.0))
		var frame := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(34, 15, 1.2)
		frame.mesh = b
		frame.material_override = Mats.metal(Color(0.12, 0.13, 0.17))
		frame.position = p + Vector3(0, 30, 0)
		frame.name = "Jumbotron"
		root.add_child(frame)
		var screen := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(32, 13)
		screen.mesh = q
		screen.material_override = Mats.shader("res://src/game/art/screen.gdshader")
		screen.position = Vector3(0, 0, -sz * 0.65)
		screen.rotation.y = 0.0 if sz > 0.0 else PI
		screen.rotation.y += PI
		frame.add_child(screen)
		for leg in [-12.0, 12.0]:
			var l := MeshInstance3D.new()
			var lc := BoxMesh.new()
			lc.size = Vector3(1.2, 23, 1.2)
			l.mesh = lc
			l.material_override = Mats.metal(Color(0.3, 0.32, 0.38))
			l.position = p + Vector3(leg, 11.5, 0)
			root.add_child(l)
		var lab := Label3D.new()
		lab.font = Mats.ui_font(700)   # scoreboard text reads like the scorebug (Teko), #125
		lab.font_size = 160
		lab.pixel_size = 0.022
		lab.outline_size = 0
		lab.modulate = Color(1, 1, 1)
		lab.position = Vector3(0, -2.6, -sz * 0.75)
		lab.rotation.y = PI if sz > 0.0 else 0.0
		lab.text = "CRATER BOWL"
		lab.name = "JumboText"
		frame.add_child(lab)
		jumbo_labels.append(lab)
		var logo_tex: Texture2D = load("res://assets/brand/logo_wide.svg")
		if logo_tex:
			var logo := Sprite3D.new()
			logo.name = "JumboLogo"
			logo.texture = logo_tex
			logo.pixel_size = 15.0 / maxf(logo_tex.get_width(), 1.0)
			logo.double_sided = false
			logo.shaded = false
			logo.position = Vector3(0, 3.4, -sz * 0.75)
			logo.rotation.y = lab.rotation.y
			logo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # the screen frame already casts
			frame.add_child(logo)

func _benches(w: float, L: float, team_colors: Array) -> void:
	for i in 2:
		var x := -7.5 if i == 0 else w + 7.5
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(1.2, 0.8, L * 0.4)
		mi.mesh = b
		mi.material_override = Mats.cloth((team_colors[i] as Color).darkened(0.35))
		mi.position = Vector3(x, 0.4, -L / 2.0)
		mi.name = "Bench"
		root.add_child(mi)

func _ground() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	pm.subdivide_width = 0
	var rm := Mats.shader("res://src/game/art/regolith.gdshader")
	rm.set_shader_parameter("diff", load("res://assets/textures/regolith/moon_01_diff_1k.jpg"))
	rm.set_shader_parameter("nrm", load("res://assets/textures/regolith/moon_01_nor_gl_1k.jpg"))
	var mi := _mesh_node("Regolith", pm, rm)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # flat ground never casts
	mi.position = center + Vector3(0, -0.06, 0)

## Jagged crater rim on the horizon.
func _crater_rim() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 140
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.9
	var r_in := 360.0
	var r_out := 520.0
	for i in n:
		var t0 := TAU * float(i) / n
		var t1 := TAU * float(i + 1) / n
		var h0 := 38.0 + noise.get_noise_1d(float(i)) * 30.0 + noise.get_noise_1d(float(i) * 3.1) * 10.0
		var h1 := 38.0 + noise.get_noise_1d(float(i + 1)) * 30.0 + noise.get_noise_1d(float(i + 1) * 3.1) * 10.0
		var a := Vector3(cos(t0) * r_in, -2, sin(t0) * r_in)
		var b := Vector3(cos(t1) * r_in, -2, sin(t1) * r_in)
		var ta := Vector3(cos(t0) * (r_in + 70), h0, sin(t0) * (r_in + 70))
		var tb := Vector3(cos(t1) * (r_in + 70), h1, sin(t1) * (r_in + 70))
		var c := Vector3(cos(t0) * r_out, h0 * 0.6, sin(t0) * r_out)
		var d := Vector3(cos(t1) * r_out, h1 * 0.6, sin(t1) * r_out)
		for tri in [[a, ta, b], [b, ta, tb], [ta, c, tb], [tb, c, d]]:
			var nrm: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			for v in tri:
				st.set_normal(nrm)
				st.add_vertex(v)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.62, 0.66)
	m.albedo_texture = load("res://assets/textures/regolith/moon_01_diff_1k.jpg")
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.02, 0.02, 0.02)
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_node("CraterRim", st.commit(), m).position = center

## Crowd excitement 0..1 (touchdowns, big plays).
var _excite := -1.0

func set_excitement(v: float) -> void:
	# Called every frame; pushing unchanged shader params still dirties the materials.
	if absf(v - _excite) < 0.002:
		return
	_excite = v
	if crowd_mat:
		crowd_mat.set_shader_parameter("excite", v)
	for m in ribbon_mats:
		m.set_shader_parameter("excite", v)

func set_scoreboard(text: String) -> void:
	for l in jumbo_labels:
		if l.text != text:
			l.text = text

## Build the lunar night environment + lights (once per scene).
static func build_environment(parent: Node3D) -> void:
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-52, -38, 0)
	key.light_color = Color(1.0, 0.96, 0.9)
	key.light_energy = 1.15
	key.shadow_enabled = Quality.at_least("medium")
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if not Quality.at_least("high") else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	key.directional_shadow_max_distance = 70.0
	key.shadow_blur = 1.5
	parent.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-35, 140, 0)
	fill.light_color = Color(0.55, 0.7, 1.0)   # earthshine
	fill.light_energy = 0.35
	parent.add_child(fill)
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	var sky := Sky.new()
	var skym := Mats.shader("res://src/game/art/sky.gdshader")
	skym.set_shader_parameter("panorama", load("res://assets/sky/skybox-space-galaxy.png"))
	sky.sky_material = skym
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.48, 0.64)
	e.ambient_light_energy = 0.55
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.tonemap_white = 6.0
	e.glow_enabled = Quality.at_least("medium")
	e.glow_intensity = 0.7
	e.glow_strength = 0.9
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.1
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.ssao_enabled = Quality.level() == "high" and RenderingServer.get_rendering_device() != null
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.6
	e.fog_enabled = Quality.at_least("medium")
	e.fog_light_color = Color(0.05, 0.06, 0.1)
	e.fog_density = 0.0016
	e.fog_sky_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	e.adjustment_contrast = 1.05
	env.environment = e
	parent.add_child(env)
