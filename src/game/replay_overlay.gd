extends CanvasLayer
## B04 replay overlay: broadcast-style REPLAY bug, play summary, clip progress,
## camera name and transport hints. Visuals only; reads main each frame. Runs after
## the match overlay (process_priority) so it can hide live-only widgets during replays
## while the scorebug stays up, like a TV replay.

const Mats := preload("res://src/game/art/materials.gd")
const NAVY := Color(0.055, 0.078, 0.14, 0.9)
const ACCENT := Color(0.36, 0.88, 1.0)
const REC := Color(1.0, 0.26, 0.22)
const GOLD := Color(1.0, 0.86, 0.3)
## Live-only match-overlay widgets hidden during a replay (missing names are skipped).
const LIVE_WIDGETS := ["card", "picker", "coaching_text", "me_panel", "hints", "throw_panel", "mode_l", "status_pill"]

var main
var root: Control
var badge_l: Label
var dot: ColorRect
var speed_l: Label
var cam_l: Label
var ctx_l: Label
var summary_l: Label
var bar: ProgressBar
var bar_fill: StyleBoxFlat
## Key hints: a backed bar of [key] action pairs above the scorebug (#116).
var hint_bar: PanelContainer
var hint_row: HBoxContainer
var _hint_keys := ""
var _blink := 0.0
var _hidden: Array = []   # match-overlay widgets hidden during the replay, restored after

func _init(m = null) -> void:
	main = m

func _ready() -> void:
	layer = 6
	process_priority = 100
	root = Control.new()
	root.name = "ReplayOverlay"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	add_child(root)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(NAVY, 8, REC, 2))
	panel.position = Vector2(18, 14)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	dot = ColorRect.new()
	dot.color = REC
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	badge_l = _label(26, Color.WHITE, 800)
	row.add_child(badge_l)
	speed_l = _label(18, GOLD, 800)
	speed_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(speed_l)
	cam_l = _label(14, ACCENT, 700)
	cam_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cam_l)
	summary_l = _label(22, Color.WHITE, 800)
	col.add_child(summary_l)
	ctx_l = _label(14, Color(0.8, 0.86, 1.0, 0.85), 600)
	col.add_child(ctx_l)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.custom_minimum_size = Vector2(420, 6)
	bar.add_theme_stylebox_override("background", _box(Color(1, 1, 1, 0.15), 3))
	bar_fill = _box(REC, 3)
	bar.add_theme_stylebox_override("fill", bar_fill)
	col.add_child(bar)
	hint_bar = PanelContainer.new()
	hint_bar.name = "ReplayHints"
	var hb := _box(NAVY, 6, Color(1, 1, 1, 0.08), 1)
	hb.content_margin_top = 4
	hb.content_margin_bottom = 4
	hint_bar.add_theme_stylebox_override("panel", hb)
	hint_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint_bar)
	hint_row = HBoxContainer.new()
	hint_row.add_theme_constant_override("separation", 16)
	hint_bar.add_child(hint_row)

static func _box(bg: Color, radius: int = 6, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 8
	return s

func _label(size: int, c: Color, weight: int) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = Mats.ui_font(weight)
	ls.font_size = size
	ls.font_color = c
	ls.shadow_size = 3
	ls.shadow_color = Color(0, 0, 0, 0.45)
	ls.shadow_offset = Vector2(1, 2)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _process(delta: float) -> void:
	if main == null:
		return
	var on: bool = main.replay_active
	root.visible = on
	if not on:
		for n in _hidden:
			if is_instance_valid(n):
				n.visible = true
		_hidden = []
		return
	# Live-only widgets from the match overlay make no sense over a replay.
	if main.hud:
		main.hud.visible = false
	if main.pres and main.pres.overlay:
		var o = main.pres.overlay
		# Looked up by name: the match overlay is owned (and reworked) by other sessions.
		for wname in LIVE_WIDGETS:
			var n = o.get(wname)
			if n is CanvasItem and n.visible:
				n.visible = false
				_hidden.append(n)
		var st = o.get("status_l")
		if st is Label:
			st.text = ""
	var r = main.replay
	var p: int = r.current_play()
	var play: Dictionary = r.plays[p] if p < r.plays.size() else {}
	badge_l.text = "HIGHLIGHT REEL" if main.replay_reel else ("HIGHLIGHT" if main.replay_auto else "REPLAY")
	var spd := "%sx" % str(r.speed)
	if r.paused:
		spd = "PAUSED"
	elif r.effective_speed() < r.speed:
		spd = "SLOW-MO"
	speed_l.text = spd
	cam_l.text = "%s VIEW" % str(main.REPLAY_CAMS[main.replay_cam]).to_upper()
	var summary := str(play.get("summary", ""))
	summary_l.text = (summary if summary != "" else str(play.get("label", ""))).to_upper()
	var ctx := "PLAY %d" % (p + 1)
	if str(play.get("context", "")) != "":
		ctx += "  ·  " + str(play["context"]).to_upper()
	var hs: int = r.highlights().size()
	if hs > 0:
		ctx += "  ·  %d HIGHLIGHT%s" % [hs, "" if hs == 1 else "S"]
	ctx_l.text = ctx
	bar.value = r.progress()
	_blink += delta
	dot.modulate.a = 1.0 if r.paused or fmod(_blink, 1.0) < 0.6 else 0.2
	var leave := ["V", "Exit"] if main.replay_viewer else (["V / Enter", "Skip"] if main.replay_auto or main.replay_reel else ["V / Enter", "Back to game"])
	_set_hints([leave, ["Space", "Pause"], [", .", "Step"], ["← →", "Prev / next play"], ["H", "Highlights"], ["[ ]", "Speed"], ["C", "Camera"]])
	_place_hints()

## Rebuild the hint bar only when the key set changes.
func _set_hints(pairs: Array) -> void:
	var key := str(pairs)
	if key == _hint_keys:
		return
	_hint_keys = key
	for c in hint_row.get_children():
		hint_row.remove_child(c)
		c.queue_free()
	for pair in pairs:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		var cap := PanelContainer.new()
		var cs := _box(Color(1, 1, 1, 0.1), 4, Color(1, 1, 1, 0.35), 1)
		cs.content_margin_left = 6
		cs.content_margin_right = 6
		cs.content_margin_top = 0
		cs.content_margin_bottom = 1
		cap.add_theme_stylebox_override("panel", cs)
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var k := _label(13, Color.WHITE, 800)
		k.label_settings.shadow_size = 0
		k.text = str(pair[0]).to_upper()
		cap.add_child(k)
		cell.add_child(cap)
		var a := _label(14, Color(0.85, 0.9, 1.0), 600)
		a.label_settings.shadow_size = 0
		a.text = str(pair[1])
		a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(a)
		hint_row.add_child(cell)

## Center the bar a few px above the scorebug (or the bottom edge if there is none).
func _place_hints() -> void:
	var size := hint_bar.get_combined_minimum_size()
	hint_bar.size = size
	var bottom := root.size.y - 14.0
	var o = main.pres.overlay if main.pres else null
	if o != null and o.get("bug") is Control and o.bug.is_visible_in_tree():
		bottom = o.bug.get_global_rect().position.y - 8.0
	hint_bar.position = Vector2((root.size.x - size.x) * 0.5, bottom - size.y)
