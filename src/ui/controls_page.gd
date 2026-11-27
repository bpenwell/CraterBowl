extends VBoxContainer
## Pause -> Controls page (#134): three tabs (Keyboard, Gamepad, More), each a row of short
## sections with key-cap chips. Data and bound-key lookup live in controls.gd (Controls.page);
## this only draws it. The Gamepad tab opens by default only when a pad is connected.

const Controls := preload("res://src/ui/controls.gd")
const UITheme := preload("res://src/ui/ui_theme.gd")
const TABS := [["keyboard", "Keyboard & mouse"], ["gamepad", "Gamepad"], ["more", "More"]]

var pages := {}     # tab id -> HBoxContainer
var buttons := {}   # tab id -> tab Button
var _holder: Control

## bindings: the player's saved rebinds; pad: a gamepad is connected.
func _init(bindings: Dictionary = {}, pad: bool = false) -> void:
	name = "ControlsHelp"
	add_theme_constant_override("separation", 10)
	var tabs := HBoxContainer.new()
	tabs.name = "ControlsTabs"
	tabs.add_theme_constant_override("separation", 6)
	add_child(tabs)
	var group := ButtonGroup.new()
	_holder = VBoxContainer.new()
	_holder.name = "ControlsPages"
	add_child(_holder)
	for t in TABS:
		var b := Button.new()
		b.name = "Tab_" + t[0]
		b.text = str(t[1]).to_upper()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		var id: String = t[0]
		b.pressed.connect(func(): show_tab(id))
		tabs.add_child(b)
		buttons[id] = b
		var p := _page(Controls.page(id, bindings))
		p.name = "Page_" + id
		_holder.add_child(p)
		pages[id] = p
	show_tab("gamepad" if pad else "keyboard")

func current_tab() -> String:
	for id in pages:
		if pages[id].visible:
			return id
	return ""

func show_tab(id: String) -> void:
	for t in pages:
		pages[t].visible = t == id
		buttons[t].set_pressed_no_signal(t == id)
	_fit.call_deferred()

## Line up each section's labels after its widest chips, and keep the panel the same size on
## every tab so the pause buttons don't jump. Needs the theme (fonts), so runs once in the tree.
func _fit() -> void:
	if not is_inside_tree():
		return
	var size := Vector2.ZERO
	for id in pages:
		for col in pages[id].get_children():
			var keys: Array = col.find_children("Keys", "HBoxContainer", true, false)
			var w := 0.0
			for k in keys:
				k.custom_minimum_size.x = 0.0
				w = maxf(w, k.get_combined_minimum_size().x)
			for k in keys:
				k.custom_minimum_size.x = w
		size = size.max(pages[id].get_combined_minimum_size())
	_holder.custom_minimum_size = size

func _page(sections: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	for section in sections:
		var col := VBoxContainer.new()
		col.name = "Section_" + str(section[0]).replace(" ", "_")
		col.add_theme_constant_override("separation", 6)
		col.add_child(UITheme.heading(section[0], 18, UITheme.CYAN))
		for r in section[1]:
			col.add_child(_row(r))
		row.add_child(col)
	return row

func _row(r: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = "Row_" + str(r["label"]).validate_node_name().replace(" ", "_").replace("/", "")
	h.add_theme_constant_override("separation", 12)
	h.tooltip_text = r["tip"]
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var keys := HBoxContainer.new()
	keys.name = "Keys"
	keys.add_theme_constant_override("separation", 4)
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in r["keys"]:
		keys.add_child(UITheme.key_cap(k))
	if r["note"] != "":
		var n := Label.new()
		n.text = r["note"]
		n.add_theme_font_size_override("font_size", 16)
		n.add_theme_color_override("font_color", UITheme.REGOLITH)
		keys.add_child(n)
	h.add_child(keys)
	var l := Label.new()
	l.name = "Label"
	l.text = r["label"]
	l.add_theme_font_override("font", UITheme.body_font(600))
	l.add_theme_font_size_override("font_size", 17)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h

## Shown rows on a tab as {label: [chip texts]} (tests).
func rows(id: String) -> Dictionary:
	var out := {}
	for h in pages[id].find_children("Row_*", "HBoxContainer", true, false):
		var keys := []
		for c in h.get_node("Keys").get_children():
			if c is PanelContainer:
				keys.append(c.get_node("Key").text)
		out[h.get_node("Label").text] = keys
	return out
