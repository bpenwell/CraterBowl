extends Control
## Home-screen lobby: a dark locker-room stage with the player's own athlete
## (real rigged model + equipped cosmetics) on a lit pad in the middle, bot
## teammates either side and empty "invite" pads on the wings. 3D renders into
## a SubViewport; names and invite buttons are 2D, pinned to the pads each frame.

const Athlete := preload("res://src/sim/athlete.gd")
const PlayerView := preload("res://src/game/player.gd")
const C := preload("res://src/ui/ui_theme.gd")

## Jersey color for the lobby squad (matches the cyan away team in-game).
const SQUAD_COLOR := Color(0.3, 0.8, 0.95)
## x, z, role (player.gd ROLE_NAMES index), kind
const SLOTS := [[-3.5, -1.9, -1, "invite"], [-1.95, -0.7, 2, "bot"], [0.0, 0.55, 0, "you"],
	[1.95, -0.7, 3, "bot"], [3.5, -1.9, -1, "invite"]]
const HERO_Z := 0.55
const PANEL_SHIFT := 1.0    # camera h_offset when a side panel covers the right half
const PANEL_LEFT := 0.46    # where the menu's side panel starts (main_menu.gd _build_panel anchor)

signal invite_pressed


var viewport: SubViewport
var camera: Camera3D
var hero               # the player's athlete view (player.gd)
var overlay: Control
var _right_slots: Array[Node3D] = []   # slots right of the hero: hidden under an open side panel (#125)
var _pins := []        # [Control, Vector3 world anchor]
var _shift := 0.0
var _shift_to := 0.0
var _t := 0.0
var _beam: MeshInstance3D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.own_world_3d = true
	box.add_child(viewport)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	_build_stage(viewport)

## Show the player's name and cosmetics on the hero athlete.
func set_player(player_name: String, look: Dictionary) -> void:
	for p in _pins:
		if p[0].has_meta("hero_name"):
			p[0].text = player_name.to_upper()
	if hero and hero.is_inside_tree():
		hero.apply_look(look)

## Slide the squad left so a right-hand panel doesn't cover the hero.
func set_panel_open(open: bool) -> void:
	_shift_to = PANEL_SHIFT if open else 0.0
	# The panel is opaque, but it is shorter than the screen when its content is short: hide the
	# teammate and pads behind it so no half-covered player shows under its bottom edge.
	for n in _right_slots:
		n.visible = not open

func _process(delta: float) -> void:
	_t += delta
	_shift = move_toward(_shift, _shift_to, delta * 14.0)
	if camera:
		camera.h_offset = _shift
		camera.position.x = sin(_t * 0.25) * 0.1   # slow drift keeps the scene alive
	if _beam:
		(_beam.material_override as StandardMaterial3D).albedo_color.a = 0.07 + 0.015 * sin(_t * 1.7)
	if camera == null or not camera.is_inside_tree():
		return
	for p in _pins:
		var ctl: Control = p[0]
		var at: Vector2 = camera.unproject_position(p[1])
		ctl.position = at - ctl.size * Vector2(0.5, 0.0 if p[2] else 0.5)
		var in_view := Rect2(Vector2.ZERO, size).encloses(ctl.get_rect())
		# A side panel covers the right of the screen from PANEL_LEFT: pins under it would ghost
		# through the panel or sit on its edge (#125), so they hide while it's open.
		var clear_of_panel := _shift_to == 0.0 or ctl.get_rect().end.x < size.x * PANEL_LEFT - 8.0
		ctl.visible = in_view and clear_of_panel and not camera.is_position_behind(p[1])

# ---------------------------------------------------------------- scene
func _build_stage(vp: SubViewport) -> void:
	var root := Node3D.new()
	vp.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#05060B")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#3A4A6A")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color("#0B1630")
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	camera = Camera3D.new()
	camera.fov = 38.0
	camera.position = Vector3(0, 1.8, HERO_Z + 5.1)
	root.add_child(camera)
	camera.look_at(Vector3(0, 0.98, HERO_Z))

	# Floor: dark gloss so the pads and strips reflect as soft highlights.
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#0A0E1A")
	floor_mat.metallic = 0.6
	floor_mat.roughness = 0.22
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 24)
	fl.mesh = pm
	fl.material_override = floor_mat
	root.add_child(fl)

	_build_lockers(root)

	# Key light from above the hero, soft fills from the sides, cyan rim from behind.
	var key := SpotLight3D.new()
	key.position = Vector3(0, 7.5, 2.4)
	key.light_energy = 6.0
	key.spot_range = 14.0
	key.spot_angle = 24.0
	key.light_color = Color("#E8F6FF")
	key.shadow_enabled = true
	root.add_child(key)
	key.look_at(Vector3(0, 0, 0.55))
	for sx in [-1.0, 1.0]:
		var fill := OmniLight3D.new()
		fill.position = Vector3(sx * 3.4, 2.6, 2.2)
		fill.light_color = Color("#7FB8FF")
		fill.light_energy = 1.1
		fill.omni_range = 6.0
		root.add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 2.4, -2.2)
	rim.light_color = C.CYAN
	rim.light_energy = 2.2
	rim.omni_range = 5.5
	root.add_child(rim)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.25
	sun.rotation_degrees = Vector3(-50, 20, 0)
	root.add_child(sun)

	# Fake volumetric beam over the hero.
	_beam = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.25
	cone.bottom_radius = 1.9
	cone.height = 7.0
	cone.cap_top = false
	cone.cap_bottom = false
	_beam.mesh = cone
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(0.75, 0.9, 1.0, 0.07)
	_beam.material_override = bm
	_beam.position = Vector3(0, 3.5, 0.55)
	root.add_child(_beam)

	var i := 0
	for s in SLOTS:
		var at := Vector3(s[0], 0, s[1])
		var big: bool = s[3] == "you"
		var slot := Node3D.new()   # one node per slot so a side panel can hide the right-hand ones
		root.add_child(slot)
		if at.x > 0.5:
			_right_slots.append(slot)
		_pad(slot, at, 0.95 if big else 0.62, big)
		match s[3]:
			"you", "bot":
				var a := Athlete.new()
				a.id = 3 + i * 5
				a.role = s[2]
				a.position = Vector2(at.x, -at.z)
				var v = PlayerView.new()
				v.setup(a, SQUAD_COLOR)
				slot.add_child(v)
				v.rotation.y = PI + (0.0 if big else -signf(at.x) * 0.25)   # face the camera, angled in
				if big:
					hero = v
				if big:
					var nm := _name_label("YOU", 34, 1.0)
					nm.set_meta("hero_name", true)
					_pin(nm, at + Vector3(0, 0, 0.5), true)
			"invite":
				_pin(_invite_button(), at + Vector3(0, 0.55, 0), false)
		i += 1

## Glowing ring pad with a faint inner disc and tick marks.
func _pad(root: Node3D, at: Vector3, r: float, big: bool) -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.85, 0.97, 1.0)
	glow.emission_enabled = true
	glow.emission = C.CYAN
	glow.emission_energy_multiplier = 2.4 if big else 1.4
	for k in (3 if big else 1):
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		var rr := r * (1.0 + k * 0.32)
		tm.inner_radius = rr - (0.035 if k == 0 else 0.015)
		tm.outer_radius = rr
		tm.rings = 64
		ring.mesh = tm
		ring.material_override = glow
		ring.position = at + Vector3(0, 0.02, 0)
		root.add_child(ring)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = r
	dm.bottom_radius = r
	dm.height = 0.02
	disc.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(C.CYAN, 0.12 if big else 0.07)
	disc.material_override = dmat
	disc.position = at + Vector3(0, 0.01, 0)
	root.add_child(disc)
	if big:
		var tick := BoxMesh.new()
		tick.size = Vector3(0.03, 0.01, 0.22)
		for t in 48:
			var ang := TAU * t / 48.0
			var m := MeshInstance3D.new()
			m.mesh = tick
			m.material_override = glow
			m.position = at + Vector3(cos(ang), 0, sin(ang)) * (r * 1.84) + Vector3(0, 0.02, 0)
			m.rotation.y = -ang + PI / 2
			root.add_child(m)

## Back wall of lockers: dark cabinets, glowing shelf strips, helmets on top shelf.
func _build_lockers(root: Node3D) -> void:
	var cab_mat := StandardMaterial3D.new()
	cab_mat.albedo_color = Color("#0D1222")
	cab_mat.metallic = 0.4
	cab_mat.roughness = 0.5
	var strip := StandardMaterial3D.new()
	strip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip.albedo_color = Color(0.8, 0.95, 1.0)
	strip.emission_enabled = true
	strip.emission = C.CYAN
	strip.emission_energy_multiplier = 1.6
	var helmet_mat := StandardMaterial3D.new()
	helmet_mat.albedo_color = SQUAD_COLOR.darkened(0.35)
	helmet_mat.metallic = 0.3
	helmet_mat.roughness = 0.15
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(40, 9, 0.3)
	wall.mesh = wm
	wall.material_override = cab_mat
	wall.position = Vector3(0, 4.5, -6.0)
	root.add_child(wall)
	var cab := BoxMesh.new()
	cab.size = Vector3(1.7, 4.2, 0.9)
	var bar := BoxMesh.new()
	bar.size = Vector3(1.4, 0.035, 0.05)
	var dome := SphereMesh.new()
	dome.radius = 0.26
	dome.height = 0.48
	for k in range(-7, 8):
		var x := k * 1.85
		if absf(x) < 1.0:
			continue   # leave the centre open behind the hero (beam + rim light)
		var z := -5.2 + absf(x) * 0.08
		var c := MeshInstance3D.new()
		c.mesh = cab
		c.material_override = cab_mat
		c.position = Vector3(x, 2.1, z)
		root.add_child(c)
		for y in [3.75, 2.55, 0.95]:
			var s := MeshInstance3D.new()
			s.mesh = bar
			s.material_override = strip
			s.position = Vector3(x, y, z + 0.47)
			root.add_child(s)
		var h := MeshInstance3D.new()
		h.mesh = dome
		h.material_override = helmet_mat
		h.position = Vector3(x, 3.05, z + 0.25)
		root.add_child(h)
	# Header strip across the top of the lockers.
	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(30, 0.05, 0.05)
	head.mesh = hb
	head.material_override = strip
	head.position = Vector3(0, 4.45, -4.7)
	root.add_child(head)

# ---------------------------------------------------------------- 2D pins
func _pin(ctl: Control, world: Vector3, top_anchor: bool) -> void:
	overlay.add_child(ctl)
	_pins.append([ctl, world, top_anchor])

func _name_label(t: String, sz: int, alpha: float) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", C.display_font(true))
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(C.CREAM, alpha))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size = Vector2(240, 0)
	return l

func _invite_button() -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	v.custom_minimum_size = Vector2(90, 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := Button.new()
	b.name = "Invite"
	b.text = "+"
	b.tooltip_text = "Host or join a match with friends"
	b.custom_minimum_size = Vector2(56, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 30)
	var ring := C.box(Color(C.SPACE, 0.55), Color(C.CREAM, 0.85), 2, 28)
	ring.content_margin_top = 0
	ring.content_margin_bottom = 4
	b.add_theme_stylebox_override("normal", ring)
	b.add_theme_stylebox_override("hover", C.box(Color(C.CYAN, 0.25), C.CYAN, 2, 28))
	b.add_theme_stylebox_override("pressed", C.box(Color(C.CYAN, 0.4), C.CYAN, 2, 28))
	b.add_theme_stylebox_override("focus", C.box(Color(0, 0, 0, 0), C.CYAN, 2, 28))
	b.pressed.connect(func(): invite_pressed.emit())
	v.add_child(b)
	var l := Label.new()
	l.text = "INVITE"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(C.CREAM, 0.8))
	v.add_child(l)
	return v

## The UI font slanted a little: the sporty italic used for names and headers.
static func italic_font(weight: int) -> Font:
	var f = C.font(weight)
	if f is FontVariation:
		f.variation_transform = C.SLANT
	return f
