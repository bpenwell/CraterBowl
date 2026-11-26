extends "res://tests/visual/harness.gd"
## #125 Slice A: the three font roles resolve to their files (never Godot's fallback font) and
## no menu control still uses the removed Oswald/Rajdhani faces.

const UITheme := preload("res://src/ui/ui_theme.gd")
const Mats := preload("res://src/game/art/materials.gd")

func _initialize() -> void:
	_run.call_deferred()

## The font file behind a Font (FontVariation -> base_font -> FontFile).
func _file(f: Font) -> String:
	while f is FontVariation:
		f = (f as FontVariation).base_font
	return f.resource_path if f else ""

func _run() -> void:
	check(_file(UITheme.font()).ends_with("Teko-UI.ttf"), "UI role is Teko (%s)" % _file(UITheme.font()))
	check(_file(UITheme.display_font()).ends_with("Graduate-Regular.ttf"), "display role is Graduate")
	check(_file(UITheme.body_font()).ends_with("BarlowSemiCondensed-Medium-UI.ttf")
		and _file(UITheme.body_font(600)).ends_with("BarlowSemiCondensed-SemiBold-UI.ttf"), "body role is Barlow Semi Condensed")
	check(_file(Mats.number_font()).ends_with("Graduate-Regular.ttf"), "jersey/yard numbers use Graduate")
	check(_file(Mats.ui_font(700)).ends_with("Teko-UI.ttf"), "3D/HUD labels use Teko")
	var fb := ThemeDB.fallback_font
	for f in [UITheme.font(), UITheme.display_font(), UITheme.body_font(), Mats.ui_font(600)]:
		check(f != fb, "role never falls back to Godot's default font")

	var launch = get_root().get_node("Launch")
	launch.settings_path = "user://test_typeface_settings.cfg"
	launch.settings.player_name = "Ace"
	var menu = preload("res://scenes/menu.tscn").instantiate()
	menu.set_meta("force_menu", true)
	root.add_child(menu)
	current_scene = menu
	for i in 10:
		await process_frame
	check(_file(menu.theme.default_font).ends_with("Teko-UI.ttf"), "menu theme default is the UI role")
	check(_file(menu.play_button.get_theme_font("font")).ends_with("Graduate-Regular.ttf"), "PLAY button is set in Graduate")
	var old := menu.find_children("*", "Control", true, false).filter(func(c):
		var p := _file(c.get_theme_font("font"))
		return p.contains("Oswald") or p.contains("Rajdhani"))
	check(old.is_empty(), "no menu control uses Oswald/Rajdhani (%d found)" % old.size())
	menu.show_screen("practice")
	for i in 40:
		await process_frame
	await capture("typeface-training-panel")
	menu.show_screen("home")
	for i in 40:
		await process_frame
	await capture("typeface-home")
	finish()
