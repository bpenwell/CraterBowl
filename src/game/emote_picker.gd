extends PanelContainer
## Taunt picker: mouse wheel scrolls a short vertical list (selected row centered,
## neighbours fading out), G / middle click performs it. Fades away when idle.

const Emotes := preload("res://src/sim/emotes.gd")
const VISIBLE_ROWS := 5
const SHOW_TIME := 2.5

var index := 0
var show_t := 0.0
var _rows: Array = []
var _title: Label

func _ready() -> void:
	name = "EmotePicker"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.14, 0.78)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_title = Label.new()
	_title.text = "TAUNTS  ·  SCROLL TO PICK, T TO PERFORM"
	_title.add_theme_font_size_override("font_size", 11)
	_title.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0, 0.8))
	box.add_child(_title)
	for i in VISIBLE_ROWS:
		var l := Label.new()
		l.custom_minimum_size = Vector2(150, 0)
		box.add_child(l)
		_rows.append(l)
	modulate.a = 0.0
	_refresh()

func selected() -> String:
	return Emotes.id_at(index)

func scroll(step: int) -> void:
	index = posmod(index + step, Emotes.LIST.size())
	reveal()

func reveal() -> void:
	show_t = SHOW_TIME
	_refresh()

func _refresh() -> void:
	if _rows.is_empty():
		return
	var mid := VISIBLE_ROWS / 2
	for i in VISIBLE_ROWS:
		var off := i - mid
		var l: Label = _rows[i]
		var id := Emotes.id_at(index + off)
		l.text = ("▶ " if off == 0 else "   ") + Emotes.display_name(id).to_upper()
		l.add_theme_font_size_override("font_size", 17 if off == 0 else 13)
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if off == 0 else Color(1, 1, 1, 0.75 - 0.25 * absi(off)))

func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	position = Vector2(vp.x - size.x - 18.0, (vp.y - size.y) * 0.5)
	show_t = maxf(0.0, show_t - delta)
	modulate.a = clampf(show_t / 0.4, 0.0, 1.0)
