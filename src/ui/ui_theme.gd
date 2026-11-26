extends RefCounted
## Crater Bowl UI theme: palette shared with the in-game art direction
## (graphics-overhaul): space black, navy panels, neon cyan accent, orange alerts.

const SPACE := Color("#07080F")
const NAVY := Color("#0E1424")
const PANEL := Color(0.055, 0.078, 0.141, 0.85)
const REGOLITH := Color("#8A8C94")
const CREAM := Color("#FFF4E0")
const CYAN := Color("#5CE1FF")
const ORANGE := Color("#FF6A1F")
const GOLD := Color("#F2BF26")
## Type system (#125): three roles, all SIL OFL (licenses next to the files in assets/fonts).
##   display: Graduate, collegiate block lettering. Wordmark, PLAY, names, jersey numbers.
##   ui:      Teko, broadcast scorebug style. Nav, buttons, headings, HUD. The default.
##   body:    Barlow Semi Condensed. Paragraphs, descriptions, help text.
## Teko and Barlow are rescaled by tools/brand/scale_fonts.py so their capitals match the
## Oswald sizes every layout was tuned for.
const DISPLAY_PATH := "res://assets/fonts/Graduate-Regular.ttf"
const FONT_PATH := "res://assets/fonts/Teko-UI.ttf"
const BODY_PATH := "res://assets/fonts/BarlowSemiCondensed-Medium-UI.ttf"
const BODY_BOLD_PATH := "res://assets/fonts/BarlowSemiCondensed-SemiBold-UI.ttf"
const SLANT := Transform2D(Vector2(1, 0), Vector2(-0.18, 1), Vector2.ZERO)

## UI role (Teko, variable 300-700). Most code calls this.
static func font(weight: int = 600) -> Font:
	var base = load(FONT_PATH)
	if base == null:
		return ThemeDB.fallback_font
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): clampi(weight, 300, 700)}
	v.spacing_glyph = 1
	return v

static func ui_font(weight: int = 600) -> Font:
	return font(weight)

## Display role (Graduate, single weight). slant = the sporty italic used on PLAY and names;
## bold thickens the strokes for big call-to-action text (Graduate has no bold cut).
static func display_font(slant: bool = false, bold: float = 0.0) -> Font:
	var base = load(DISPLAY_PATH)
	if base == null:
		return font(700)
	var v := FontVariation.new()
	v.base_font = base
	if slant:
		v.variation_transform = SLANT
	v.variation_embolden = bold
	return v

## Body role (Barlow Semi Condensed): Medium below 600, SemiBold from 600.
static func body_font(weight: int = 500) -> Font:
	var base = load(BODY_BOLD_PATH if weight >= 600 else BODY_PATH)
	if base == null:
		return font(400)
	return base

static func box(bg: Color, border: Color, width: int = 2, radius: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font(600)
	t.default_font_size = 20
	var normal := box(PANEL, Color(CYAN, 0.25))
	var hover := box(Color(NAVY.lightened(0.12), 0.95), CYAN)
	var pressed := box(Color(CYAN, 0.25), CYAN)
	var disabled := box(Color(PANEL, 0.5), Color(REGOLITH, 0.2))
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("focus", cls, box(Color(0, 0, 0, 0), CYAN, 2))
		t.set_stylebox("disabled", cls, disabled)
		t.set_color("font_color", cls, CREAM)
		t.set_color("font_hover_color", cls, CYAN)
		t.set_color("font_focus_color", cls, CYAN)
		t.set_color("font_pressed_color", cls, CREAM)
		t.set_color("font_disabled_color", cls, Color(REGOLITH, 0.6))
	t.set_stylebox("normal", "LineEdit", box(Color(SPACE, 0.9), Color(CYAN, 0.4)))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), CYAN))
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_color("font_placeholder_color", "LineEdit", Color(REGOLITH, 0.8))
	t.set_color("caret_color", "LineEdit", CYAN)
	t.set_color("font_color", "Label", CREAM)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, Color(CYAN, 0.18), 1, 10))
	t.set_stylebox("panel", "PopupMenu", box(NAVY, CYAN, 1, 4))
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", CYAN)
	t.set_stylebox("panel", "ItemList", box(Color(SPACE, 0.7), Color(CYAN, 0.2)))
	t.set_color("font_color", "ItemList", CREAM)
	t.set_color("font_selected_color", "ItemList", SPACE)
	t.set_stylebox("selected", "ItemList", box(CYAN, CYAN, 0, 3))
	t.set_stylebox("selected_focus", "ItemList", box(CYAN, CYAN, 0, 3))
	t.set_color("default_color", "RichTextLabel", CREAM)
	t.set_font("normal_font", "RichTextLabel", body_font())
	t.set_font("bold_font", "RichTextLabel", body_font(600))
	t.set_font("mono_font", "RichTextLabel", ThemeDB.fallback_font)
	_style_default_widgets(t)
	t.set_stylebox("slider", "HSlider", box(Color(SPACE, 0.9), Color(CYAN, 0.3), 1, 3))
	t.set_stylebox("grabber_area", "HSlider", box(Color(CYAN, 0.6), CYAN, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(CYAN, CYAN, 0, 3))
	return t

## Widgets that still showed Godot's default grey theme (#125): scrollbars, toggles, dropdown
## arrows, SpinBox arrows, read-only fields. Icons are SVG strings rasterized at load.
static func _style_default_widgets(t: Theme) -> void:
	for cls in ["VScrollBar", "HScrollBar"]:
		var track := box(Color(SPACE, 0.6), Color(0, 0, 0, 0), 0, 4)
		track.set_content_margin_all(3)
		t.set_stylebox("scroll", cls, track)
		t.set_stylebox("scroll_focus", cls, track)
		for st in [["grabber", 0.35], ["grabber_highlight", 0.6], ["grabber_pressed", 0.85]]:
			var g := box(Color(CYAN, st[1]), Color(0, 0, 0, 0), 0, 4)
			g.set_content_margin_all(3)
			t.set_stylebox(st[0], cls, g)
	# Toggle rows read as a label with a switch, not as another text field.
	var clear := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6)
	clear.content_margin_left = 0   # line up with the other settings rows' labels
	t.set_stylebox("normal", "CheckButton", clear)
	t.set_font("font", "CheckButton", body_font())
	t.set_font_size("font_size", "CheckButton", 18)
	t.set_stylebox("hover", "CheckButton", box(Color(CYAN, 0.08), Color(0, 0, 0, 0), 0, 6))
	t.set_stylebox("pressed", "CheckButton", clear)
	t.set_stylebox("hover_pressed", "CheckButton", box(Color(CYAN, 0.08), Color(0, 0, 0, 0), 0, 6))
	t.set_color("font_pressed_color", "CheckButton", CREAM)
	t.set_color("font_hover_pressed_color", "CheckButton", CYAN)
	t.set_icon("checked", "CheckButton", _svg_icon(_switch_svg(true, CYAN)))
	t.set_icon("unchecked", "CheckButton", _svg_icon(_switch_svg(false, CREAM)))
	t.set_icon("checked_disabled", "CheckButton", _svg_icon(_switch_svg(true, REGOLITH)))
	t.set_icon("unchecked_disabled", "CheckButton", _svg_icon(_switch_svg(false, REGOLITH)))
	var chevron := _svg_icon('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14"><path d="M3 5l4 4 4-4" fill="none" stroke="#%s" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>' % CYAN.to_html(false))
	t.set_icon("arrow", "OptionButton", chevron)
	t.set_constant("arrow_margin", "OptionButton", 10)
	t.set_icon("updown", "SpinBox", _svg_icon('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="22"><path d="M3 8l4-4 4 4M3 14l4 4 4-4" fill="none" stroke="#%s" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>' % CYAN.to_html(false)))
	t.set_stylebox("read_only", "LineEdit", box(Color(SPACE, 0.5), Color(REGOLITH, 0.35)))
	t.set_color("font_uneditable_color", "LineEdit", Color(CREAM, 0.6))

static func _switch_svg(on: bool, col: Color) -> String:
	var c := col.to_html(false)
	var track := '<rect x="1" y="1" width="38" height="20" rx="10" fill="#%s" fill-opacity="%s" stroke="#%s" stroke-opacity="0.6" stroke-width="1.5"/>' % [c, "0.35" if on else "0.08", c]
	var knob := '<circle cx="%d" cy="11" r="7" fill="#%s"/>' % [29 if on else 11, c]
	return '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="22">%s%s</svg>' % [track, knob]

static func _svg_icon(svg: String) -> Texture2D:
	var img := Image.new()
	if img.load_svg_from_string(svg, 1.0) != OK:
		return null
	return ImageTexture.create_from_image(img)

## Rasterize an SVG at runtime (crisp at any scale, no import step needed).
## Exported builds only contain the imported texture, so fall back to load().
static func svg_texture(path: String, scale: float = 1.0) -> Texture2D:
	var src := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var img := Image.new()
	if src != "" and img.load_svg_from_string(src, scale) == OK:
		return ImageTexture.create_from_image(img)
	return load(path) as Texture2D

static func heading(text: String, size: int = 34, color: Color = CREAM) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", font(700))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
