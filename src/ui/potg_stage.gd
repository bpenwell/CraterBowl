extends Control
## Post-game "Players of the Game" presentation. Shown over the match after the
## final whistle: a dark stage with one lit pad per standout (2-4), the camera
## visits each one while a stat card slides in, then a wide group shot with
## confetti. Emits `finished` at the end (main.gd then returns to the lobby).
## Pure view: fed with Potg.pick() entries decorated by main.gd
## (name, number, look). Space/Enter/click = next, S = skip. Athletes hold the
## idle pose facing the camera (the dance animation turns them away).

const Athlete := preload("res://src/sim/athlete.gd")
const PlayerView := preload("res://src/game/player.gd")
const C := preload("res://src/ui/ui_theme.gd")

signal finished

const INTRO_T := 1.6
const SPOT_T := 3.6
const GROUP_T := 4.5
const PAD_GAP := 2.3
## Display slot for each rank (0 = best): the winner stands in the middle.
const ORDER := {1: [0], 2: [1, 0], 3: [1, 0, 2], 4: [2, 0, 1, 3]}


var entries: Array = []
var info := {}           # score, winner, team_colors, team_names, mode_label
var step := -1           # -1 intro, 0..n-1 spotlight, n group shot, n+1 done
var step_t := 0.0
var viewport: SubViewport
var camera: Camera3D
var views: Array = []
var pad_pos: Array = []  # Vector3 per entry (by rank)
var spots: Array = []    # SpotLight3D per entry
var cards: Array = []    # big spotlight card per entry
var tags: Array = []     # small name tag per entry (group shot)
var header: Label
var sub: Label
var hint: Label
var hint_box: PanelContainer
var confetti: CPUParticles3D
var _cam_pos := Vector3(0, 3.2, 11.0)
var _cam_look := Vector3(0, 1.0, 0)

func setup(potg: Array, match_info: Dictionary) -> void:
	entries = potg.slice(0, 4)
	info = match_info

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not get_parent() is Control:
		# Under a CanvasLayer / the root window nothing sizes us: track the viewport.
		_fit()
		get_viewport().size_changed.connect(_fit)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.own_world_3d = true
	box.add_child(viewport)
	_build_stage()
	_build_ui()
	_enter(-1)

func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if e.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		advance()
	elif e.keycode == KEY_S:
		get_viewport().set_input_as_handled()
		skip()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		advance()

func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size

## Jump to the next beat (intro -> each player -> group -> done).
func advance() -> void:
	_enter(step + 1)

func skip() -> void:
	_enter(entries.size() + 1)

func is_done() -> bool:
	return step > entries.size()

func _process(delta: float) -> void:
	if is_done():
		return
	step_t += delta
	var dur := INTRO_T if step < 0 else (SPOT_T if step < entries.size() else GROUP_T)
	if step_t >= dur:
		advance()
		return
	# Camera: ease toward this beat's framing with a slow push-in.
	var want_pos := Vector3(0, 3.0, 12.5 - step_t * 0.35)
	var want_look := Vector3(0, 1.1, 0)
	if step >= 0 and step < entries.size():
		var p: Vector3 = pad_pos[step]
		# Look right of the athlete so they sit in the left third, clear of the card. Far
		# enough back that the pad's rings stay in frame (#116: they were cut off).
		want_pos = p + Vector3(0.9 - step_t * 0.06, 1.75, 5.9 - step_t * 0.18)
		want_look = p + Vector3(1.3, 0.85, 0)
	elif step >= entries.size():
		want_pos = Vector3(sin(step_t * 0.3) * 0.6, 2.3, 9.2 - step_t * 0.2)
	var k := clampf(delta * 3.2, 0.0, 1.0)
	_cam_pos = _cam_pos.lerp(want_pos, k)
	_cam_look = _cam_look.lerp(want_look, k)
	camera.position = _cam_pos
	camera.look_at(_cam_look)
	for c in cards:
		if c.visible:
			c.modulate.a = minf(1.0, c.modulate.a + delta * 4.0)
			c.position.x = lerpf(c.position.x, size.x * 0.56, k * 1.4)
	for i in tags.size():
		var t: Control = tags[i]
		var at: Vector2 = camera.unproject_position(pad_pos[i] + Vector3(0, -0.05, 0.9))
		t.position = at - Vector2(t.size.x * 0.5, 0)
		if t.visible:
			t.modulate.a = minf(1.0, t.modulate.a + delta * 3.0)

func _enter(s: int) -> void:
	if is_done():
		return
	step = s
	step_t = 0.0
	if is_done():
		finished.emit()
		return
	var n := entries.size()
	var group := step >= n
	header.text = "PLAYERS OF THE GAME" if n > 1 else "PLAYER OF THE GAME"
	sub.visible = step < 0 or group
	for i in n:
		var focus := i == step
		var c: Control = cards[i]
		c.visible = focus
		if focus:
			c.modulate.a = 0.0
			c.position = Vector2(size.x * 0.56 + 140.0, size.y * 0.24)
		(spots[i] as SpotLight3D).light_energy = 14.0 if focus or group else (3.0 if step < 0 else 1.2)
		# During a spotlight only the featured player stands on stage, so the next player
		# never shows through the stat card (#116).
		(views[i] as Node3D).visible = focus or group or step < 0
		tags[i].visible = group
		if group:
			tags[i].modulate.a = 0.0
	confetti.emitting = group
	hint.text = "PRESS SPACE FOR THE NEXT PLAYER  ·  S TO SKIP" if not group else "PRESS SPACE TO CONTINUE"

# ---------------------------------------------------------------- 3D stage
func _team_color(t: int) -> Color:
	var cols: Array = info.get("team_colors", [C.GOLD, C.CYAN])
	return cols[clampi(t, 0, cols.size() - 1)]

func _build_stage() -> void:
	var root := Node3D.new()
	viewport.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#04050A")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#2A3550")
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color("#0B1630")
	env.fog_density = 0.025
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	camera = Camera3D.new()
	camera.fov = 40.0
	root.add_child(camera)
	camera.position = _cam_pos
	camera.look_at(_cam_look)

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#090D18")
	floor_mat.metallic = 0.6
	floor_mat.roughness = 0.2
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(50, 30)
	fl.mesh = pm
	fl.material_override = floor_mat
	root.add_child(fl)
	_build_backdrop(root)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.2
	sun.rotation_degrees = Vector3(-45, 15, 0)
	root.add_child(sun)

	var n := entries.size()
	var slots: Array = ORDER.get(n, ORDER[4])
	for i in n:
		var e: Dictionary = entries[i]
		var slot: int = slots[i]
		var x := (slot - (n - 1) / 2.0) * PAD_GAP
		var top := i == 0
		var at := Vector3(x, 0.32 if top else 0.0, -absf(x) * 0.18)
		pad_pos.append(at)
		var col := _team_color(int(e.get("team", 0)))
		_podium(root, at, col, top)
		var a := Athlete.new()
		a.id = int(e.get("id", i))
		a.team = int(e.get("team", 0))
		a.role = maxi(0, PlayerView.ROLE_NAMES.find(str(e.get("pos", "WR"))))
		a.position = Vector2(at.x, -at.z)   # spawn on the pad: a later move reads as running and turns them
		var v = PlayerView.new()
		v.setup(a, col, null, a.team != int(info.get("local_team", 0)))
		root.add_child(v)
		v.position.y = at.y
		v.rotation.y = PI - x * 0.08   # face the camera, angled in
		var lk: Dictionary = e.get("look", {}) if e.get("look") is Dictionary else {}
		v.apply_look(lk.merged({"number": int(e.get("number", (a.id % 90) + 10))}, true))
		views.append(v)
		var sp := SpotLight3D.new()
		sp.position = at + Vector3(0, 7.0, 2.0)
		sp.light_color = Color(1, 0.97, 0.92).lerp(col, 0.25)
		sp.spot_range = 12.0
		sp.spot_angle = 16.0
		sp.shadow_enabled = top
		root.add_child(sp)
		sp.look_at(at)
		spots.append(sp)
		var rim := OmniLight3D.new()
		rim.position = at + Vector3(0, 2.2, -1.6)
		rim.light_color = col
		rim.light_energy = 1.8
		rim.omni_range = 4.0
		root.add_child(rim)
	confetti = CPUParticles3D.new()
	confetti.amount = 160
	confetti.lifetime = 3.5
	confetti.emitting = false
	confetti.position = Vector3(0, 7.5, 0)
	confetti.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	confetti.emission_box_extents = Vector3(6, 0.2, 2)
	confetti.direction = Vector3(0, -1, 0)
	confetti.spread = 25.0
	confetti.initial_velocity_min = 0.5
	confetti.initial_velocity_max = 1.5
	confetti.gravity = Vector3(0, -1.6, 0)
	confetti.angular_velocity_min = -360
	confetti.angular_velocity_max = 360
	var qm := QuadMesh.new()
	qm.size = Vector2(0.07, 0.12)
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.vertex_color_use_as_albedo = true
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.material = cm
	confetti.mesh = qm
	var grad := Gradient.new()
	grad.set_color(0, _team_color(int(info.get("winner", 0)) if int(info.get("winner", -1)) >= 0 else 0))
	grad.set_color(1, C.CREAM)
	confetti.color_initial_ramp = grad
	root.add_child(confetti)

## Lit pad (raised podium for the top pick): glossy disc + glowing team-colored rings.
func _podium(root: Node3D, at: Vector3, col: Color, top: bool) -> void:
	var r := 0.95 if top else 0.75
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = col.lightened(0.5)
	glow.emission_enabled = true
	glow.emission = col
	glow.emission_energy_multiplier = 2.6 if top else 1.6
	if top:
		var base := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = r + 0.1
		cy.bottom_radius = r + 0.25
		cy.height = at.y
		base.mesh = cy
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color("#141B2E")
		bm.metallic = 0.5
		bm.roughness = 0.3
		base.material_override = bm
		base.position = Vector3(at.x, at.y / 2.0, at.z)
		root.add_child(base)
	for k in (2 if top else 1):
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		var rr := r * (1.0 + k * 0.3)
		tm.inner_radius = rr - 0.035
		tm.outer_radius = rr
		tm.rings = 64
		ring.mesh = tm
		ring.material_override = glow
		ring.position = at + Vector3(0, 0.02, 0)
		root.add_child(ring)

## Back wall: dark panels with two glowing strips and a huge faint title.
func _build_backdrop(root: Node3D) -> void:
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(50, 12, 0.3)
	wall.mesh = wm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#0B1020")
	mat.metallic = 0.4
	mat.roughness = 0.5
	wall.material_override = mat
	wall.position = Vector3(0, 6, -5.5)
	root.add_child(wall)
	var strip := StandardMaterial3D.new()
	strip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip.albedo_color = Color(0.8, 0.95, 1.0)
	strip.emission_enabled = true
	strip.emission = C.CYAN
	strip.emission_energy_multiplier = 1.4
	for y in [0.6, 4.6]:
		var s := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(40, 0.04, 0.04)
		s.mesh = sb
		s.material_override = strip
		s.position = Vector3(0, y, -5.3)
		root.add_child(s)
	var title := Label3D.new()
	title.text = "CRATER BOWL"
	title.font = C.font(700)
	title.font_size = 220
	title.pixel_size = 0.01
	title.modulate = Color(C.CYAN, 0.08)
	title.outline_size = 0
	title.position = Vector3(0, 2.6, -5.3)
	root.add_child(title)

# ---------------------------------------------------------------- 2D overlay
static func italic_font(weight: int) -> Font:
	var f = C.font(weight)
	if f is FontVariation:
		f.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.18, 1), Vector2.ZERO)
	return f

func _label(t: String, sz: int, col: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", font if font else C.font(600))
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_ui() -> void:
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_top = 30
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	header = _label("PLAYERS OF THE GAME", 46, C.GOLD, italic_font(700))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(header)
	var sc: Array = info.get("score", [0, 0])
	var names: Array = info.get("team_names", ["HOME", "AWAY"])
	sub = _label("FINAL  ·  %s %d  –  %d %s" % [names[0], sc[0], sc[1], names[1]], 22, Color(C.CREAM, 0.85))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(sub)
	# Backed pill in the bottom-right corner: readable, and off the pedestal rings.
	hint_box = PanelContainer.new()
	var hs := C.box(Color(C.SPACE, 0.85), Color(C.CYAN, 0.3), 1, 6)
	hs.content_margin_top = 4
	hs.content_margin_bottom = 4
	hint_box.add_theme_stylebox_override("panel", hs)
	hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_box.offset_right = -20
	hint_box.offset_bottom = -18
	add_child(hint_box)
	hint = _label("", 16, Color(C.CREAM, 0.95))
	hint_box.add_child(hint)
	for i in entries.size():
		cards.append(_card(entries[i], i))
		tags.append(_tag(entries[i], i))

func _team_name(e: Dictionary) -> String:
	var names: Array = info.get("team_names", ["HOME", "AWAY"])
	return str(names[clampi(int(e.get("team", 0)), 0, names.size() - 1)])

## Big spotlight card: rank title, name, number/position/team, stat lines.
func _card(e: Dictionary, rank: int) -> Control:
	var col := _team_color(int(e.get("team", 0)))
	var p := PanelContainer.new()
	p.name = "Card%d" % rank
	var st := C.box(Color(C.SPACE, 0.95), Color(col, 0.7), 0, 4)
	st.border_width_left = 6
	st.content_margin_left = 26
	st.content_margin_right = 30
	st.content_margin_top = 18
	st.content_margin_bottom = 20
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(420, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	v.add_child(_label(str(e.get("title", "")), 18, C.GOLD if rank == 0 else col))
	var nm := _label(str(e.get("name", "")).to_upper(), 52, C.CREAM, italic_font(700))
	nm.name = "Name"
	v.add_child(nm)
	v.add_child(_label("#%d  ·  %s  ·  %s" % [int(e.get("number", 0)), str(e.get("pos", "")), _team_name(e)], 18, Color(C.CREAM, 0.7)))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	for s in e.get("lines", []):
		v.add_child(_label(str(s), 26, col.lightened(0.35)))
	p.visible = false
	add_child(p)
	return p

## Small tag pinned under each athlete in the group shot.
func _tag(e: Dictionary, rank: int) -> Control:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.custom_minimum_size = Vector2(220, 0)
	v.add_theme_constant_override("separation", 0)
	var t := _label(str(e.get("name", "")).to_upper(), 26 if rank == 0 else 22, C.CREAM, italic_font(700))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var lines: Array = e.get("lines", [])
	var s := _label(str(lines[0]) if not lines.is_empty() else str(e.get("pos", "")), 15, _team_color(int(e.get("team", 0))).lightened(0.3))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.visible = false
	add_child(v)
	return v
