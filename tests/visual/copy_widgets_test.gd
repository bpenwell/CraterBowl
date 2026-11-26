extends "res://tests/visual/harness.gd"
## #125 Slice C: menu text reads like player copy (no [Key] shorthand, no "5V5", no raw
## placeholders), and widgets that used Godot's default grey theme are styled.

const UITheme := preload("res://src/ui/ui_theme.gd")
const Lobby := preload("res://src/net/lobby.gd")
const Stats := preload("res://src/sim/stats.gd")

## Patterns that read as developer shorthand on a player-facing screen.
var BAD := [
	[RegEx.create_from_string("\\[[A-Za-z0-9/ ]+\\]"), "[Key] shorthand"],
	[RegEx.create_from_string("\\dV\\d"), "uppercase V in a match size"],
	[RegEx.create_from_string("XXXXX"), "raw placeholder"],
	[RegEx.create_from_string("\\d+yd\\b"), "yd shorthand"],
	[RegEx.create_from_string("127\\.0\\.0\\.1"), "raw address"],
]

func _initialize() -> void:
	_run.call_deferred()

func _texts(n: Node) -> Array:
	var out := []
	for c in n.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree():
			continue
		if c is LineEdit:   # what the player typed is theirs; only our placeholder is copy
			out.append(str(c.placeholder_text))
		elif c is Label or c is Button:
			out.append(str(c.text))
	return out

func _scan(menu, screen: String) -> void:
	var hits := []
	for t in _texts(menu):
		for b in BAD:
			if b[0].search(t) != null:
				hits.append("%s: '%s'" % [b[1], t])
	check(hits.is_empty(), "%s: no developer shorthand %s" % [screen, str(hits)])

func _run() -> void:
	var theme: Theme = UITheme.build()
	for item in [["checked", "CheckButton"], ["unchecked", "CheckButton"], ["arrow", "OptionButton"], ["updown", "SpinBox"]]:
		check(theme.has_icon(item[0], item[1]) and theme.get_icon(item[0], item[1]) != null, "themed %s icon for %s" % item)
	for item in [["grabber", "VScrollBar"], ["scroll", "VScrollBar"], ["read_only", "LineEdit"]]:
		check(theme.has_stylebox(item[0], item[1]), "themed %s style for %s" % item)

	var l := Lobby.new()
	check(not l.summary().contains("|") and not l.full_reason().contains("seats %d" % l.capacity()), "lobby summary/full reason read as sentences (%s)" % l.summary())
	check(Stats.new().summary_lines().is_empty(), "empty stats give no placeholder lines")

	var launch = get_root().get_node("Launch")
	launch.settings_path = "user://test_copy_widgets_settings.cfg"
	launch.settings.player_name = "Ace"
	launch.settings.matchmaker = "127.0.0.1:1"   # nothing listens: the offline message must stay player-facing
	var menu = preload("res://scenes/menu.tscn").instantiate()
	menu.set_meta("force_menu", true)
	menu.profile_path = "user://test_copy_widgets_profile.json"
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.show_screen("home")
	await process_frame
	check(menu.mode_button.text.strip_edges() == "5v5 VS BOTS", "mode chip keeps a lowercase v (%s)" % menu.mode_button.text.strip_edges())
	for screen in ["home", "bots", "practice", "locker", "leaders", "replays", "settings"]:
		menu.show_screen(screen)
		await process_frame
		_scan(menu, screen)

	menu.show_screen("online")
	for i in 240:   # let the browser give up on the dead matchmaker
		await process_frame
		if menu.browser and menu.browser.state == "offline":
			break
	await process_frame
	_scan(menu, "online")
	check(menu.content.find_child("PartyCode", true, false).visible == false, "Solo hides the party code field instead of showing a dead one")
	var public: CheckButton = menu.content.find_children("*", "CheckButton", true, false)[0]
	check(public.get_theme_icon("checked") == menu.theme.get_icon("checked", "CheckButton"), "toggle uses the themed switch")
	for i in 30:
		await process_frame
	await capture("online-themed-widgets")
	menu.show_screen("settings")
	for i in 30:
		await process_frame
	await capture("settings-themed-widgets")
	menu.show_screen("locker")
	for i in 30:
		await process_frame
	await capture("locker-themed-widgets")
	finish()
