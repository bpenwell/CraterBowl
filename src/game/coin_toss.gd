extends CanvasLayer
## Coin-toss cutscene (#129). Plays while the match is in its TOSS state (the opening
## kickoff; overtime reuses it once #16 lands): both captains walk to midfield with the
## referee, the ref flips the coin, the camera cuts to the result, the crowd roars and the
## winner picks RECEIVE or KICK on two clickable cards (1 / 2 still work; no key hints in
## the copy). The other side sees "<TEAM> IS CHOOSING…". Then a quick dip to black and
## back into the live kickoff.
##
## Presentation only: it reads series.state / toss_winner and never decides anything.
## The sim's TOSS state holds the play clock, opens the choice window at TOSS_REVEAL (when
## this coin lands) and auto-picks receive (bots TOSS_BOT_PICK after the reveal, humans at
## the end of TOSS_WINDOW). Host / offline pin the timeline to series.toss_elapsed();
## online clients run it from when they first see the toss.
## Space / Enter skip once the result shows: the winner takes the default (receive), the
## other side just closes it. Esc stays the pause menu.
##
## The 3D stage (captains, ref, coin) lives under this node; the match's own athletes,
## ball and aim art are hidden while it plays, so only three skinned meshes render.

const Athlete := preload("res://src/sim/athlete.gd")
const PlayerView := preload("res://src/game/player.gd")
const Match := preload("res://src/sim/match.gd")
const C := preload("res://src/ui/ui_theme.gd")
const Mats := preload("res://src/game/art/materials.gd")
const MeshGuard := preload("res://src/game/headless_mesh_guard.gd")

signal closed

## TODO(#132 child): team names / colors come from main (HELIOS / NEBULA) until the team
## roster + logo art lands (src/sim/teams.gd); then show each team's logo on the coin faces,
## the lower third and the choice cards.
const TEAM_NAMES := ["HELIOS", "NEBULA"]

# Timeline, in seconds since the toss started. LAND is the sim's TOSS_REVEAL.
const WALK_END := 1.6           # captains arrive at midfield
const FLIP_AT := 1.85           # the coin leaves the ref's hand
const LAND := Match.TOSS_REVEAL # it lands: cut to the result, the crowd roars
const CARDS_AT := LAND + 0.55   # cut to the winner's captain; the choice appears
const DEADLINE := Match.TOSS_REVEAL + Match.TOSS_WINDOW
const HOLD := 0.45              # decided: the pick stays on screen
const DIP := 0.18               # fade to black
const UNDIP := 0.25             # fade back into the live kickoff
const SYNC_SLACK := 0.15        # host: the timeline may run this far ahead of the sim

const COIN_R := 0.26            # arcade-sized (a real coin would be a pixel)
const COIN_H := 0.05
const HAND := 1.45              # the coin leaves the ref's hand here
const APEX := 4.2
const FLIPS := 7                # half-turns are added so the winner's face lands up
const CAPTAIN_GAP := 1.55       # each captain stops this far from the coin spot
const WALK_FROM := 7.0
const LETTERBOX := 0.075        # fraction of the screen height, top and bottom

var main
var t := 0.0
var frozen := false      # tests: seek() then capture without the clock moving
var outro_t := -1.0      # timeline time the outro started (-1 = still choosing)
var receiver := -1       # team receiving the opening kickoff, once decided
var restored := false    # the match view is back (behind the fade)
var center := Vector3.ZERO
var stage: Node3D
var captains: Array = []
var ref: Node3D
var coin: Node3D
var _roared := false
var _closing := false
var _anim := {}          # view -> clip it is playing (change-driven)
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO

var root: Control
var title: Label
var sub: Label
var lower_third: Control
var cards: Array = []    # [RECEIVE, KICK] panels
var card_row: Control
var waiting: Label
var waiting_box: Control
var timer_bar: ColorRect
var timer_back: ColorRect
var bars: Array = []     # letterbox
var dip: ColorRect
var _hover := -1

func setup(m) -> void:
	main = m

func _ready() -> void:
	layer = 40   # over the match HUD (5), under the post-game show (60) and the Esc menu (90)
	name = "CoinToss"
	var f = main.field
	center = Vector3(f.width / 2.0, 0.0, -f.length / 2.0)
	_build_stage()
	_build_ui()
	_hide_match(true)
	if not main.is_client():
		t = clampf(main.series.toss_elapsed(), 0.0, LAND)
	_apply()

# ------------------------------------------------------------------ public API

## Which side are we on? (the local player's team)
func my_team() -> int:
	var me = main.world.get_athlete(main.my_id)
	return me.team if me else 0

func winner() -> int:
	return clampi(int(main.series.toss_winner), 0, 1)

func i_won() -> bool:
	return winner() == my_team()

func revealed() -> bool:
	return t >= LAND

func choosing() -> bool:
	return outro_t < 0.0 and t >= CARDS_AT and i_won()

## Tests: jump the timeline to `at` (seconds since the toss) and hold it there.
func seek(at: float) -> void:
	frozen = true
	t = at
	_apply()

## Key presses while the cutscene is up. Returns true when the key is consumed: only the
## toss keys (1 / 2) reach main's normal handler, so nothing else fires behind the scene.
func key(code: int) -> bool:
	if code in [KEY_1, KEY_2]:
		return false
	if code in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		skip()
	return true

## Skip once the result shows. The winner takes the default (receive); the other side
## closes it locally and watches the field (the HUD pill keeps saying who is choosing).
func skip() -> bool:
	if not revealed() or restored:
		return false
	if outro_t < 0.0 and main.series.state == Match.State.TOSS and i_won():
		pick("receive")
	if outro_t < 0.0:
		outro_t = t - HOLD   # straight to the fade
	elif t - outro_t < HOLD:
		outro_t = t - HOLD
	_apply()
	return true

## A card was clicked (or a test picks): send the real toss action.
func pick(choice: String) -> bool:
	if outro_t >= 0.0 or not i_won() or not revealed():
		return false
	return main.do_action({"a": "toss", "c": choice})

## Headless (#179): flush pending render-instance updates while our meshes are still alive,
## so freeing the stage (quit mid-toss, rebuilt match) doesn't hit dead meshes.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and MeshGuard.needed():
		RenderingServer.free_rid(RenderingServer.instance_create())

## Close at once (match rebuilt, toss abandoned, decided before the coin landed).
func close_now() -> void:
	if _closing:
		return
	_closing = true
	_restore()
	set_process(false)
	queue_free()
	closed.emit()

func card_rect(i: int) -> Rect2:
	return (cards[i] as Control).get_global_rect()

## Every string the cutscene shows (tests: no key hints anywhere).
func all_text() -> String:
	var out := []
	for n in _walk(root):
		if n is Label and n.is_visible_in_tree():
			out.append(n.text)
	return " | ".join(out)

# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if main == null or not is_instance_valid(main):
		return
	if not frozen:
		t += delta
		if not main.is_client() and main.series.state == Match.State.TOSS:
			var sim_t: float = main.series.toss_elapsed()
			t = clampf(t, sim_t - SYNC_SLACK, sim_t + SYNC_SLACK)
	_apply()

func _apply() -> void:
	var s = main.series
	if outro_t < 0.0 and s.state != Match.State.TOSS:
		if s.state != Match.State.KICKOFF or t < LAND:
			# Restarted (tests, rebuilt match) or decided before the coin landed: nothing to show.
			close_now()
			return
		receiver = 1 - int(main.world.offense_team)   # the kicking team is the kickoff's offense
		outro_t = t
	if outro_t >= 0.0:
		var e := t - outro_t
		if e >= HOLD + DIP + UNDIP:
			close_now()
			return
		if e >= HOLD + DIP and not restored:
			_restore()
	if not restored:
		_hide_match(false)
		_pose_stage()
		_pose_camera()
		if t >= LAND and not _roared:
			_roar()
	_update_ui()

## Crowd roar on the reveal: excitement spike + fireworks over the stands. No match audio
## exists yet (#22), so the crowd stinger itself waits for #38.
func _roar() -> void:
	_roared = true
	if main.pres:
		main.pres.excite = 1.0
		main.pres._fireworks()

# ------------------------------------------------------------------ the match behind it

## Hide what would clutter the midfield shot. Root-level toggles once (on start), the
## per-frame ones every frame because main / presentation set them each frame.
func _hide_match(start: bool) -> void:
	if start:
		main.athlete_root.visible = false
		main.ball_view.visible = false
		main.los_marker.visible = false
		if main.pres:
			main.pres.overlay.visible = false
	main.fd_marker.visible = false
	main.reticle.visible = false
	for d in main.arc_dots:
		d.visible = false
	if main.pres:
		main.pres.ring.visible = false
		if main.pres.barrier:
			main.pres.barrier.visible = false

func _restore() -> void:
	if restored:
		return
	restored = true
	if not is_instance_valid(main):
		return
	if main.athlete_root:
		main.athlete_root.visible = true
	main.ball_view.visible = true
	if main.los_marker and is_instance_valid(main.los_marker):
		main.los_marker.visible = true
	if main.pres:
		main.pres.overlay.visible = true
	if main.camera:
		main.camera.fov = main.CAMERA_FOV
	if stage:
		stage.visible = false

# ------------------------------------------------------------------ 3D stage

func _build_stage() -> void:
	stage = Node3D.new()
	stage.name = "CoinTossStage"
	add_child(stage)
	var my := my_team()
	for team in 2:
		var qb = main.world.find_role(team, Athlete.Role.QB)
		var a := Athlete.new()
		a.id = qb.id if qb else team
		a.team = team
		a.role = Athlete.Role.QB
		var v = PlayerView.new()
		v.name = "Captain%d" % team
		v.setup(a, main.TEAM_COLORS[team], null, team != my)
		stage.add_child(v)
		v.set_process(false)   # posed and animated from the timeline, not from sim velocity
		var look: Dictionary = main.views[a.id].look if qb and a.id < main.views.size() else {}
		if not look.is_empty():
			v.apply_look(look)
		captains.append(v)
	var ra := Athlete.new()
	ra.id = 99
	ra.team = 0   # dark trousers
	ref = PlayerView.new()
	ref.name = "Referee"
	ref.setup(ra, Color(0.94, 0.94, 0.92), null, false)
	stage.add_child(ref)
	ref.set_process(false)
	ref._open_gear.visible = false     # no pads or helmet: a ref, not a player
	ref._open_helmet.visible = false
	ref.number_front.visible = false
	ref.number_back.visible = false
	ref.position = center + Vector3(1.05, 0, 0)
	ref.rotation.y = atan2(1.0, 0.0)   # faces the sideline camera (-x)
	coin = _build_coin()
	stage.add_child(coin)

## A big brass coin: HELIOS face on top, NEBULA underneath, each in its team color.
func _build_coin() -> Node3D:
	var n := Node3D.new()
	n.name = "Coin"
	var body := MeshInstance3D.new()
	body.mesh = _disc(COIN_R, COIN_H)
	body.material_override = Mats.metal(Color(0.86, 0.68, 0.32))
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	n.add_child(body)
	for team in 2:
		var up := 1.0 if team == 0 else -1.0
		var face := MeshInstance3D.new()
		face.mesh = _disc(COIN_R * 0.82, 0.004)
		face.material_override = Mats.emissive(main.TEAM_COLORS[team], 0.7)
		face.position.y = up * (COIN_H * 0.5 + 0.002)
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(face)
		var l := Label3D.new()
		l.text = TEAM_NAMES[team].left(1)
		l.font = Mats.number_font()
		l.font_size = 96
		l.pixel_size = 0.0042
		l.outline_size = 0
		l.modulate = Color(0.08, 0.08, 0.12)
		l.position.y = up * (COIN_H * 0.5 + 0.006)
		l.rotation.x = -PI / 2.0 * up
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(l)
	return n

## Coin meshes: smoother than RenderCache's 12-segment cylinder (it fills the close-up),
## built once and kept, so a freed cutscene never frees them (headless #179 noise).
static var _discs := {}
static func _disc(r: float, h: float) -> CylinderMesh:
	var k := "%.3f:%.3f" % [r, h]
	if not _discs.has(k):
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = h
		m.radial_segments = 28
		m.rings = 1
		_discs[k] = m
	return _discs[k]

static func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)

func _side(team: int) -> float:
	return -1.0 if team == 0 else 1.0   # HELIOS on screen left (as in the lower third)

func _captain_pos(team: int, at: float) -> Vector3:
	var k := _ease_out(at / WALK_END)
	var from := center + Vector3(-2.2, 0, _side(team) * WALK_FROM)
	var to := center + Vector3(-0.15, 0, _side(team) * CAPTAIN_GAP)
	return from.lerp(to, k)

## Coin position and flip angle at timeline time `at`.
func _coin_state(at: float) -> Array:
	var from := center + Vector3(0.8, HAND, 0.12)
	var to := center + Vector3(0.15, COIN_H * 0.5, 0.0)
	if at < FLIP_AT:
		return [from, 0.0]
	var dur := LAND - FLIP_AT
	var u := clampf((at - FLIP_AT) / dur, 0.0, 1.0)
	# Ballistic arc through APEX that starts at the hand and ends on the turf at LAND.
	var h0 := HAND
	var h1 := to.y
	var a := APEX - h0
	var b := APEX - h1
	var up_t := dur * sqrt(a) / (sqrt(a) + sqrt(b))   # time to the apex
	var tau := u * dur
	var y := 0.0
	if tau <= up_t:
		var k := tau / up_t
		y = h0 + a * (1.0 - (1.0 - k) * (1.0 - k))
	else:
		var k := (tau - up_t) / (dur - up_t)
		y = APEX - b * k * k
	var p := from.lerp(to, u)
	p.y = y
	var total := PI * (2.0 * FLIPS + (0.0 if winner() == 0 else 1.0))
	return [p, total * _ease_out(u * 1.08)]

func _pose_stage() -> void:
	var walking := t < WALK_END
	for team in 2:
		var v: Node3D = captains[team]
		v.position = _captain_pos(team, t)
		if walking:
			var d := _captain_pos(team, t + 0.05) - _captain_pos(team, t)
			v.rotation.y = atan2(-d.x, -d.z)
			_clip(v, "Jog_Fwd", 0.85)
		else:
			# Face the coin spot, then (after the reveal) the winner squares up to the camera.
			var look := center + Vector3(0.6, 0, 0)
			var face := atan2(-(look - v.position).x, -(look - v.position).z)
			if t >= CARDS_AT and team == winner():
				face = lerp_angle(face, atan2(1.0, 0.0), clampf((t - CARDS_AT) * 4.0, 0.0, 1.0))
			v.rotation.y = face
			if t < LAND:
				_clip(v, "Idle")
			elif team == winner():
				_clip(v, "Jump" if t < LAND + 0.75 else ("u2/Idle_Rail_Call" if t < LAND + 2.6 else "Idle"))
				# Hop with the jump clip: the celebration reads from the sideline.
				v.body.position.y = absf(sin((t - LAND) * 7.5)) * 0.35 if t < LAND + 0.75 else 0.0
			else:
				_clip(v, "u2/Idle_No" if t < LAND + 1.4 else "u2/Idle_FoldArms")
	_clip(ref, "Pistol_Aim_Up" if t >= FLIP_AT - 0.25 and t < FLIP_AT + 0.45 else "Idle")
	var cs := _coin_state(t)
	coin.position = cs[0]
	coin.rotation = Vector3(cs[1], 0, 0)

func _clip(v: Node3D, clip: String, speed: float = 1.0) -> void:
	if _anim.get(v) == clip or v.anim == null or not v.anim.has_animation(clip):
		return
	_anim[v] = clip
	v.anim.speed_scale = speed
	v.anim.play(clip, 0.2)

# ------------------------------------------------------------------ camera

func _pose_camera() -> void:
	var cam: Camera3D = main.camera
	if cam == null:
		return
	var pos: Vector3
	var look: Vector3
	var fov := 42.0
	var coin_p: Vector3 = _coin_state(t)[0]
	if t < FLIP_AT:
		# Wide from the sideline, pushing in as the captains arrive.
		var k := _ease_out(t / FLIP_AT)
		pos = center + Vector3(-15.0, 3.6, 3.2).lerp(Vector3(-7.4, 1.9, 0.9), k)
		look = center + Vector3(0.3, 1.05, 0.0)
	elif t < LAND:
		# Track the coin from a low angle: the ref's raised hands, then the coin alone
		# against the dome at its apex, then back down past the captains.
		var k := (t - FLIP_AT) / (LAND - FLIP_AT)
		pos = center + Vector3(-4.6, 0.9, 0.9).lerp(Vector3(-4.2, 0.85, 0.7), k)
		look = coin_p.lerp(center + Vector3(0.3, 1.2, 0.0), 0.45)
		fov = 46.0
	elif t < CARDS_AT:
		# Cut to the result: the coin on the turf, winner's face up.
		pos = coin_p + Vector3(-0.85, 1.25, 0.25)
		look = coin_p + Vector3(0.05, 0.0, 0.0)
		fov = 40.0
	else:
		# The winner's captain from a low angle, the stands behind; slow push.
		var w: Node3D = captains[winner()]
		var k := clampf((t - CARDS_AT) / 4.0, 0.0, 1.0)
		var side := _side(winner())
		pos = w.position + Vector3(-4.8 + k * 0.6, 1.45, -side * 1.6)
		look = w.position + Vector3(0.0, 1.0, -side * 2.3)   # winner high and to the side, clear of the cards
		fov = 44.0
	# Crowd roar: a short, decaying shake on the reveal (deterministic in t, so captures repeat).
	var since := t - LAND
	if since >= 0.0 and since < 0.6:
		var a := (0.6 - since) * 0.05
		pos += Vector3(0, sin(since * 71.0) * a, cos(since * 53.0) * a)
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(look)

# ------------------------------------------------------------------ 2D overlay

static func _italic(weight: int) -> Font:
	var f = C.font(weight)
	if f is FontVariation:
		f.variation_transform = C.SLANT
	return f

func _label(text: String, size: int, col: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font else C.font(600))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08, 0.9))
	l.add_theme_constant_override("outline_size", maxi(4, size / 7))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _build_ui() -> void:
	root = Control.new()
	root.name = "CoinTossUI"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # no click reaches the match behind it
	add_child(root)
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color(0.0, 0.0, 0.02)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.anchor_right = 1.0
		b.anchor_top = 0.0 if top else 1.0
		b.anchor_bottom = 0.0 if top else 1.0
		root.add_child(b)
		bars.append(b)

	# Lower third while the captains walk out: who's playing.
	var lt := PanelContainer.new()
	var ls := C.box(Color(C.SPACE, 0.88), Color(C.CYAN, 0.35), 0, 4)
	ls.border_width_left = 5
	ls.content_margin_left = 18
	ls.content_margin_right = 22
	ls.content_margin_top = 8
	ls.content_margin_bottom = 10
	lt.add_theme_stylebox_override("panel", ls)
	lt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lt.anchor_top = 1.0
	lt.anchor_bottom = 1.0
	lt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lt.offset_left = 48
	lt.offset_top = -84
	lt.offset_bottom = -84
	root.add_child(lt)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", -6)
	lt.add_child(lv)
	var head := _label("COIN TOSS  ·  CAPTAINS TO MIDFIELD", 20, C.CYAN)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lv.add_child(head)
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 14)
	lv.add_child(teams)
	for team in 2:
		if team == 1:
			teams.add_child(_label("VS", 26, Color(C.CREAM, 0.6)))
		var chip := ColorRect.new()
		chip.color = main.TEAM_COLORS[team]
		chip.custom_minimum_size = Vector2(8, 34)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		teams.add_child(chip)
		teams.add_child(_label(TEAM_NAMES[team], 44, C.CREAM, _italic(700)))
	lower_third = lt

	title = _label("", 84, C.CREAM, _italic(700))
	title.name = "Title"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.offset_top = 62
	title.pivot_offset = Vector2(0, 50)
	root.add_child(title)
	sub = _label("", 38, C.CREAM, _italic(700))
	sub.name = "Sub"
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.offset_top = 176
	root.add_child(sub)

	card_row = HBoxContainer.new()
	card_row.name = "Choices"
	card_row.add_theme_constant_override("separation", 28)
	card_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	card_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card_row.offset_bottom = -96
	card_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card_row)
	cards.append(_card("RECEIVE", "Your offense gets the ball first.", 0))
	cards.append(_card("KICK", "Defense first. Ball after halftime.", 1))

	waiting_box = PanelContainer.new()
	waiting_box.add_theme_stylebox_override("panel", C.box(Color(C.SPACE, 0.88), Color(C.CYAN, 0.3), 1, 6))
	waiting_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	waiting_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	waiting_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	waiting_box.offset_bottom = -110
	waiting_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(waiting_box)
	waiting = _label("", 40, C.CREAM, _italic(700))
	waiting.name = "Waiting"
	waiting_box.add_child(waiting)

	timer_back = ColorRect.new()
	timer_back.color = Color(C.SPACE, 0.75)
	timer_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_back.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	timer_back.offset_left = -300
	timer_back.offset_right = 300
	timer_back.offset_top = -78
	timer_back.offset_bottom = -72
	root.add_child(timer_back)
	timer_bar = ColorRect.new()
	timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_bar.size = Vector2(600, 6)
	timer_back.add_child(timer_bar)

	dip = ColorRect.new()
	dip.color = Color(0, 0, 0, 0)
	dip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dip.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dip)

func _card(word: String, blurb: String, i: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Card" + word.capitalize()
	p.custom_minimum_size = Vector2(320, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pick(["receive", "kick"][i]))
	p.mouse_entered.connect(func(): _hover = i)
	p.mouse_exited.connect(func(): if _hover == i: _hover = -1)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var w := _label(word, 56, C.CREAM, _italic(700))
	w.name = "Word"
	v.add_child(w)
	var b := _label(blurb, 18, Color(C.CREAM, 0.78), C.body_font(500))
	b.add_theme_constant_override("outline_size", 0)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(280, 0)
	v.add_child(b)
	card_row.add_child(p)
	return p

func _card_style(i: int, picked: int) -> void:
	var col: Color = main.TEAM_COLORS[winner()]
	var hot := i == picked or (picked < 0 and i == _hover)
	var st := C.box(Color(C.SPACE, 0.94 if hot else 0.86), col if hot else Color(col, 0.45), 3 if hot else 2, 8)
	st.border_width_top = 6
	st.content_margin_left = 22
	st.content_margin_right = 22
	st.content_margin_top = 10
	st.content_margin_bottom = 16
	if hot:
		st.shadow_color = Color(col, 0.45)
		st.shadow_size = 14
	(cards[i] as PanelContainer).add_theme_stylebox_override("panel", st)

func _update_ui() -> void:
	var vh: float = root.size.y if root.size.y > 0.0 else 720.0
	var in_k := clampf(t / 0.35, 0.0, 1.0)
	var out_k := 0.0
	if outro_t >= 0.0:
		out_k = clampf((t - outro_t - HOLD) / DIP, 0.0, 1.0)
	for i in 2:
		var b: ColorRect = bars[i]
		var h := vh * LETTERBOX * in_k * (1.0 - out_k)
		b.offset_top = 0.0 if i == 0 else -h
		b.offset_bottom = h if i == 0 else 0.0
	lower_third.visible = t < FLIP_AT + 0.25
	lower_third.modulate.a = clampf(t / 0.4, 0.0, 1.0) * clampf((FLIP_AT + 0.25 - t) / 0.25, 0.0, 1.0)
	var wname: String = TEAM_NAMES[winner()]
	var wcol: Color = main.TEAM_COLORS[winner()]
	var shown := revealed() and not restored
	title.visible = shown
	sub.visible = shown
	if shown:
		title.text = "YOU WON THE TOSS" if i_won() else "%s WINS THE TOSS" % wname
		title.add_theme_color_override("font_color", wcol.lerp(C.CREAM, 0.35))
		var pop := clampf((t - LAND) / 0.18, 0.0, 1.0)
		title.modulate.a = pop
		title.scale = Vector2.ONE * lerpf(1.35, 1.0, _ease_out(pop))
		title.pivot_offset = Vector2(title.size.x * 0.5, title.size.y * 0.5)
		sub.text = ""
		if receiver >= 0:
			var rname: String = TEAM_NAMES[receiver]
			sub.text = ("%s WILL RECEIVE" % rname) if receiver == winner() else ("%s WILL KICK" % wname)
	var decided := receiver >= 0
	var pick_i := -1 if not decided else (0 if receiver == winner() else 1)
	card_row.visible = shown and i_won() and (t >= CARDS_AT or decided)
	if card_row.visible:
		var k := clampf((t - CARDS_AT) / 0.25, 0.0, 1.0) if not decided else 1.0
		card_row.modulate.a = k
		for i in 2:
			_card_style(i, pick_i)
			(cards[i] as Control).modulate.a = 1.0 if not decided or i == pick_i else 0.35
	# The other side waits; once decided, the sub line under the title says what happened.
	waiting_box.visible = shown and not i_won() and not decided and t >= LAND + 0.35
	waiting.text = "%s IS CHOOSING…" % wname
	# The choice window: drains from the reveal to the sim's deadline (receive if it runs out).
	var bar_on := shown and not decided and t >= CARDS_AT
	timer_back.visible = bar_on
	if bar_on:
		var left := clampf((DEADLINE - t) / (DEADLINE - LAND), 0.0, 1.0)
		timer_bar.size = Vector2(600.0 * left, 6.0)
		timer_bar.color = wcol
	var a := 0.0
	if outro_t >= 0.0:
		var e := t - outro_t
		if e < HOLD:
			a = 0.0
		elif e < HOLD + DIP:
			a = (e - HOLD) / DIP
		else:
			a = 1.0 - clampf((e - HOLD - DIP) / UNDIP, 0.0, 1.0)
	dip.color.a = a
	# Once the match view is back, only the fade remains: clicks go to the match again.
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE if restored else Control.MOUSE_FILTER_STOP
	for b in bars:
		b.visible = not restored

func _walk(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
