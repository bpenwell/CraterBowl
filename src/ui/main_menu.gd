extends Control
## Crater Bowl main menu. Every "start" button calls Launch.start_game(opts) with the
## same keys as the CLI flags (host, join, queue, practice, size, mode, replay...).

const UITheme := preload("res://src/ui/ui_theme.gd")
const Settings := preload("res://src/ui/settings_store.gd")
const Controls := preload("res://src/ui/controls.gd")
const Cosmetics := preload("res://src/sim/cosmetics.gd")
const Leaderboard := preload("res://src/sim/leaderboard.gd")
const Ranked := preload("res://src/sim/ranked.gd")
const Drills := preload("res://src/sim/drills.gd")
const InviteCode := preload("res://src/net/invite_code.gd")
const Browser := preload("res://src/ui/server_browser.gd")
const PortMapper := preload("res://src/net/port_mapper.gd")
const NetSession := preload("res://src/net/net_session.gd")
const Lobby := preload("res://src/ui/lobby_stage.gd")
const Music := preload("res://src/ui/music_player.gd")
const GameOverview := preload("res://src/ui/game_overview.gd")
const QUEUE_HOST_PORT := 24566    # fixed so UPnP can map it before queueing
const SIZES := [3, 5, 7]
const TOP_H := 78
const EDGE := 22               # gap between panels/clusters and the screen edge (no footer since #125)
const BUG_URL := "https://github.com/bpenwell/football-game/issues"
const TABS := [["home", "Home"], ["online", "Online"], ["bots", "Vs bots"], ["practice", "Training"],
	["locker", "Locker room"], ["leaders", "Leaderboard"], ["replays", "Replays"]]
## Home-screen PLAY selector. Keys mirror Launch.start_game options.
const MODES := [
	{"id": "bots5", "label": "5v5 vs bots", "size": 5, "mode": "classic", "hint": "Offline match, bots fill every slot"},
	{"id": "bots3", "label": "3v3 vs bots", "size": 3, "mode": "classic", "hint": "Offline match, bots fill every slot"},
	{"id": "bots7", "label": "7v7 vs bots", "size": 7, "mode": "classic", "hint": "Offline match, bots fill every slot"},
	{"id": "chaos", "label": "Chaosball vs bots", "size": 3, "mode": "chaosball", "hint": "3v3, low gravity"},
	{"id": "quick5", "label": "5v5 quick match", "queue": "casual", "size": 5, "hint": "Online casual matchmaking"},
	{"id": "quick3", "label": "3v3 quick match", "queue": "casual", "size": 3, "hint": "Online casual matchmaking"},
	{"id": "quick7", "label": "7v7 quick match", "queue": "casual", "size": 7, "hint": "Online casual matchmaking"},
	{"id": "ranked5", "label": "5v5 ranked", "queue": "competitive", "size": 5, "hint": "Online ranked matchmaking"},
	{"id": "scrimmage", "label": "Scrimmage practice", "practice": "scrimmage", "hint": "7v7 with bots, no clock"},
]

var launch                    # the Launch autoload (or a stand-in in tests)
var content: VBoxContainer
var content_scroll: ScrollContainer
var lobby
var music
var panel: PanelContainer
var news: Button
var hud_right: HBoxContainer
var level_ring
var play_button: Button
var play_cluster: VBoxContainer
var mode_button: Button
var mode_popup: PopupMenu
var mode_id := "bots5"
var avatar: Button
var profile_name: Label
var profile_sub: Label
var status_label: Label
var toast: PanelContainer      # status messages (#125: was footer text)
var _toast_timer: Timer
var last_game: Button          # Home card that reopens the last match overview
var music_chip: Control
var nav_buttons := {}         # screen id -> Button
var current := ""
var profile := Cosmetics.new()
var profile_path := Cosmetics.DEFAULT_PATH
var leaderboard_path := Leaderboard.DEFAULT_PATH
var ranked_path := Ranked.DEFAULT_PATH
var replay_dir := "user://replays"
var pick_size := 5
var pick_mode := "classic"
var _size_buttons: Array[Button] = []   # current screen's Size row (#83: locked to 3v3 under Chaosball)
var _capture_action := ""     # controls screen: waiting for a key for this action
var _capture_button: Button
var browser: Node
var list_public := true
var host_port := NetSession.DEFAULT_PORT
var party_code := ""
var party_size := 1          # 1 = solo
var _upnp_thread: Thread
var busy := false

func _ready() -> void:
	launch = get_node_or_null("/root/Launch")
	if launch and not launch.menu_visited and launch.should_skip_menu(OS.get_cmdline_user_args(), DisplayServer.get_name()) and not has_meta("force_menu"):
		get_tree().change_scene_to_file.call_deferred(launch.GAME_SCENE)
		return
	build()

func settings() -> Settings:
	return launch.settings

func build() -> void:
	theme = UITheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby = Lobby.new()
	lobby.name = "Lobby"
	lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby.invite_pressed.connect(func(): show_screen("online"))
	add_child(lobby)
	var shade := Shade.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby.add_child(shade)
	lobby.move_child(shade, 1)   # over the 3D view, under the name/invite pins
	profile.load_file(profile_path)
	_build_top_bar()
	_build_news()
	_build_play_cluster()
	_build_level_ring()
	_build_last_game()
	_build_panel()
	_build_music()
	_build_toast()
	_status(launch.last_status)
	launch.last_status = ""
	for m in MODES:
		if m["id"] == settings().home_mode:
			mode_id = m["id"]
	_set_mode(mode_id)
	if settings().player_name == "":
		show_screen("welcome")
	elif not launch.last_match.is_empty():
		show_screen("overview")   # just back from a match: show how it went
		play_button.grab_focus.call_deferred()
	else:
		show_screen("home")
		play_button.grab_focus.call_deferred()

## Anchor a control: anchors (l, t, r, b) in 0..1, pixel offsets (l, t, r, b).
static func _place(c: Control, a: Array, o: Array) -> void:
	c.anchor_left = a[0]
	c.anchor_top = a[1]
	c.anchor_right = a[2]
	c.anchor_bottom = a[3]
	c.offset_left = o[0]
	c.offset_top = o[1]
	c.offset_right = o[2]
	c.offset_bottom = o[3]

func _bar_style(top_edge: bool) -> StyleBoxFlat:
	var s := UITheme.box(Color(UITheme.SPACE, 0.86), Color(UITheme.CYAN, 0.22), 0, 0)
	if top_edge:
		s.border_width_top = 1
	else:
		s.border_width_bottom = 1
	s.content_margin_left = 28
	s.content_margin_right = 28
	return s

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.add_theme_stylebox_override("panel", _bar_style(false))
	_place(bar, [0, 0, 1, 0], [0, 0, 0, TOP_H])
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	bar.add_child(h)
	var logo := TextureRect.new()
	logo.texture = UITheme.svg_texture("res://assets/brand/icon.svg", 0.25)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(46, 46)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(logo)
	h.add_child(_gap(18))
	for t in TABS:
		var b := Button.new()
		b.text = t[1].to_upper()
		b.add_theme_font_size_override("font_size", 20)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var id: String = t[0]
		b.pressed.connect(func(): show_screen(id))
		h.add_child(b)
		nav_buttons[id] = b
		_style_tab(b, false)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(fill)
	# Profile chip: avatar initial (opens the locker room), name, level + rating.
	avatar = Button.new()
	avatar.name = "Avatar"
	avatar.custom_minimum_size = Vector2(46, 46)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.tooltip_text = "Locker room"
	avatar.add_theme_font_size_override("font_size", 20)
	for st in ["normal", "hover", "pressed", "focus"]:
		var ring := UITheme.box(Color(UITheme.NAVY, 0.9) if st == "normal" else Color(UITheme.CYAN, 0.25), UITheme.CYAN, 2, 23)
		ring.content_margin_left = 0
		ring.content_margin_right = 0
		avatar.add_theme_stylebox_override(st, ring)
	avatar.pressed.connect(func(): show_screen("locker"))
	h.add_child(avatar)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", -4)
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(who)
	profile_name = Label.new()
	profile_name.add_theme_font_override("font", UITheme.font(700))
	profile_name.add_theme_font_size_override("font_size", 21)
	who.add_child(profile_name)
	profile_sub = Label.new()
	profile_sub.add_theme_font_size_override("font_size", 13)
	profile_sub.add_theme_color_override("font_color", UITheme.REGOLITH)
	who.add_child(profile_sub)
	h.add_child(_gap(18))
	var gear := Button.new()
	gear.name = "Settings"
	gear.tooltip_text = "Settings"
	gear.custom_minimum_size = Vector2(44, 44)
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_tab(gear, false)
	gear.draw.connect(func(): _draw_gear(gear))
	gear.pressed.connect(func(): show_screen("settings"))
	h.add_child(gear)
	nav_buttons["settings"] = gear

func _build_news() -> void:
	news = Button.new()
	news.name = "News"
	news.focus_mode = Control.FOCUS_NONE
	news.tooltip_text = "Play ranked"
	var card := UITheme.box(Color(UITheme.NAVY, 0.985), Color(UITheme.CYAN, 0.4), 1, 10)
	card.shadow_color = Color(UITheme.CYAN, 0.18)
	card.shadow_size = 14
	news.add_theme_stylebox_override("normal", card)
	var hov := card.duplicate()
	hov.border_color = UITheme.CYAN
	news.add_theme_stylebox_override("hover", hov)
	news.add_theme_stylebox_override("pressed", hov)
	_place(news, [0, 0, 0, 0], [36, TOP_H + 24, 36 + 380, TOP_H + 24 + 200])
	news.pressed.connect(func(): show_screen("online"))
	add_child(news)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 18
	v.offset_right = -18
	v.offset_top = 14
	v.offset_bottom = -14
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	news.add_child(v)
	var art := TextureRect.new()
	art.texture = UITheme.svg_texture("res://assets/brand/logo_wide.svg", 0.5)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(art)
	var sid := Ranked.season_id(Time.get_unix_time_from_system())
	var t := Label.new()
	t.text = "RANKED SEASON %d · Q%d" % [sid / 4, sid % 4 + 1]
	t.add_theme_font_override("font", Lobby.italic_font(700))
	t.add_theme_font_size_override("font_size", 24)
	v.add_child(t)
	var s := Label.new()
	s.text = "QUEUE RANKED TO PLACE · REWARDS AT SEASON END"
	s.add_theme_font_size_override("font_size", 13)
	s.add_theme_color_override("font_color", UITheme.CYAN)
	v.add_child(s)

func _build_play_cluster() -> void:
	var v := VBoxContainer.new()
	play_cluster = v
	v.name = "PlayCluster"
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_END
	_place(v, [0, 1, 0, 1], [36, -EDGE - 290, 36 + 390, -EDGE])
	add_child(v)
	mode_button = Button.new()
	mode_button.name = "ModeButton"
	mode_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	mode_button.custom_minimum_size = Vector2(0, 52)
	mode_button.add_theme_font_size_override("font_size", 20)
	mode_button.add_theme_stylebox_override("normal", UITheme.box(Color(UITheme.SPACE, 0.85), Color(UITheme.CREAM, 0.25), 1, 6))
	mode_button.pressed.connect(_open_mode_menu)
	v.add_child(mode_button)
	# The shortcut lives on the control it triggers (#125), not in a separate legend.
	var change := HBoxContainer.new()
	change.add_theme_constant_override("separation", 8)
	change.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	change.offset_left = -150
	change.offset_right = -14
	change.offset_top = -13
	change.offset_bottom = 13
	change.alignment = BoxContainer.ALIGNMENT_END
	change.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_button.add_child(change)
	var cl := Label.new()
	cl.text = "CHANGE"
	cl.add_theme_font_size_override("font_size", 15)
	cl.add_theme_color_override("font_color", Color(UITheme.CREAM, 0.7))
	change.add_child(cl)
	change.add_child(_keycap("TAB"))
	mode_popup = PopupMenu.new()
	mode_popup.add_theme_font_size_override("font_size", 19)
	for i in MODES.size():
		mode_popup.add_item(caps(str(MODES[i]["label"])), i)
	mode_popup.id_pressed.connect(func(i): _set_mode(MODES[i]["id"]))
	add_child(mode_popup)
	play_button = Button.new()
	play_button.name = "PlayButton"
	play_button.text = "PLAY"
	play_button.custom_minimum_size = Vector2(0, 96)
	play_button.add_theme_font_override("font", UITheme.display_font(true, 0.8))
	play_button.add_theme_font_size_override("font_size", 58)
	for st in ["normal", "hover", "pressed", "focus"]:
		var c: Color = {"normal": UITheme.CYAN, "hover": UITheme.CYAN.lightened(0.25), "pressed": UITheme.CYAN.darkened(0.2), "focus": Color(0, 0, 0, 0)}[st]
		var sb := UITheme.box(c, UITheme.CREAM if st == "focus" else c.lightened(0.35), 3 if st == "focus" else 1, 8)
		sb.skew = Vector2(0.16, 0)
		if st != "focus":
			sb.shadow_color = Color(UITheme.CYAN, 0.45 if st == "hover" else 0.3)
			sb.shadow_size = 22
		play_button.add_theme_stylebox_override(st, sb)
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		play_button.add_theme_color_override(fc, UITheme.SPACE)
	play_button.pressed.connect(play_selected)
	v.add_child(play_button)
	var enter := _keycap("ENTER", true)
	enter.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	enter.offset_left = -92
	enter.offset_right = -26
	enter.offset_top = -13
	enter.offset_bottom = 13
	play_button.add_child(enter)

func _build_level_ring() -> void:
	hud_right = HBoxContainer.new()
	hud_right.name = "LevelHud"
	hud_right.alignment = BoxContainer.ALIGNMENT_END
	_place(hud_right, [1, 1, 1, 1], [-236, -EDGE - 66 - 188, -36, -EDGE - 66])
	add_child(hud_right)
	level_ring = LevelRing.new()
	level_ring.custom_minimum_size = Vector2(160, 188)
	hud_right.add_child(level_ring)

## A key shown as a small keycap: "ENTER", "TAB". dark = for use on the cyan PLAY button.
func _keycap(t: String, dark: bool = false) -> Label:
	var cap := Label.new()
	cap.text = t
	cap.name = "Key" + t.capitalize()
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.custom_minimum_size = Vector2(48, 0)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_theme_font_size_override("font_size", 13)
	var col := UITheme.SPACE if dark else UITheme.CREAM
	cap.add_theme_color_override("font_color", Color(col, 0.75))
	var sb := UITheme.box(Color(col, 0.1), Color(col, 0.45), 1, 4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	cap.add_theme_stylebox_override("normal", sb)
	return cap

## Home card above the mode chip: reopens the last match's overview (#125: was a footer link).
func _build_last_game() -> void:
	last_game = Button.new()
	last_game.name = "LastGame"
	last_game.focus_mode = Control.FOCUS_NONE
	last_game.alignment = HORIZONTAL_ALIGNMENT_LEFT
	last_game.add_theme_font_size_override("font_size", 18)
	var card := UITheme.box(Color(UITheme.NAVY, 0.985), Color(UITheme.CYAN, 0.3), 1, 8)
	last_game.add_theme_stylebox_override("normal", card)
	var hov := card.duplicate()
	hov.border_color = UITheme.CYAN
	last_game.add_theme_stylebox_override("hover", hov)
	last_game.add_theme_stylebox_override("pressed", hov)
	last_game.custom_minimum_size = Vector2(0, 44)
	last_game.pressed.connect(func(): show_screen("overview"))
	play_cluster.add_child(last_game)
	play_cluster.move_child(last_game, 0)   # above the mode chip; clear of the lobby's invite pins
	_refresh_last_game()

func _refresh_last_game() -> void:
	var ov: Dictionary = launch.last_match
	last_game.visible = false
	if ov.is_empty():
		return
	var sc: Array = ov.get("score", [0, 0])
	var me := int(ov.get("my_team", -1))
	var a := int(sc[me]) if me in [0, 1] else int(sc[0])
	var b := int(sc[1 - me]) if me in [0, 1] else int(sc[1])
	last_game.text = "LAST GAME  ·  %s %d–%d  ·  VIEW" % [GameOverview.result_text(ov), a, b]
	last_game.visible = true

## Now-playing chip, bottom-right of Home (#125: was the right end of the footer).
func _build_music() -> void:
	music = Music.new()
	music.name = "Music"
	music.volume = settings().music_volume
	add_child(music)
	music_chip = music.build_widget()
	_place(music_chip, [1, 1, 1, 1], [-36 - 330, -EDGE - 44, -36, -EDGE])
	add_child(music_chip)

## Status messages ("Host disconnected", bad name...) as a toast under the top bar that fades
## out after a few seconds (#125: was orange text squeezed into the footer).
func _build_toast() -> void:
	toast = PanelContainer.new()
	toast.name = "Toast"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UITheme.box(Color(UITheme.SPACE, 0.97), UITheme.ORANGE, 1, 8)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	toast.add_theme_stylebox_override("panel", sb)
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.offset_top = TOP_H + 12
	add_child(toast)
	status_label = Label.new()
	status_label.name = "Status"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", UITheme.CREAM)
	status_label.add_theme_font_override("font", UITheme.body_font(600))
	status_label.add_theme_font_size_override("font_size", 17)
	toast.add_child(status_label)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 6.0
	_toast_timer.timeout.connect(func(): toast.visible = false)
	add_child(_toast_timer)
	toast.visible = false

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "Panel"
	var ps := UITheme.box(Color(UITheme.SPACE, 0.975), Color(UITheme.CYAN, 0.3), 1, 10)
	ps.content_margin_left = 28
	ps.content_margin_right = 28
	ps.content_margin_top = 20
	ps.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", ps)
	_place(panel, [0.46, 0, 1, 1], [0, TOP_H + 22, -32, -EDGE])
	add_child(panel)
	content_scroll = ScrollContainer.new()
	content_scroll.name = "PanelScroll"
	content_scroll.follow_focus = true
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED   # rows wrap, never scroll sideways
	panel.add_child(content_scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	# Gutter so buttons and tables don't run into the scrollbar (#125).
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 14)
	content_scroll.add_child(gutter)
	gutter.add_child(content)
	content.minimum_size_changed.connect(_fit_panel, CONNECT_DEFERRED)
	resized.connect(_fit_panel, CONNECT_DEFERRED)

## Shrink the panel to its content so short screens aren't mostly empty; long ones scroll (#125).
func _fit_panel() -> void:
	if panel == null or not panel.visible:
		return
	var ps := panel.get_theme_stylebox("panel")
	var need := content.get_combined_minimum_size().y + ps.get_minimum_size().y + 4
	var top := TOP_H + 22.0
	var room := size.y - top - EDGE
	panel.anchor_bottom = 0.0
	panel.offset_top = top
	panel.offset_bottom = top + clampf(need, 160.0, room)

func _gap(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## Tabs are flat text; the selected one is a filled cyan pill.
## Uppercase for buttons and chips, but match sizes keep a lowercase v ("5v5"), the way the
## scorebug writes them (#125: menus mixed "5V5" and "3v3").
static func caps(t: String) -> String:
	var re := RegEx.create_from_string("(\\d)V(\\d)")
	return re.sub(t.to_upper(), "$1v$2", true)

func _style_tab(b: Button, selected: bool) -> void:
	var clear := UITheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6)
	var pill := UITheme.box(UITheme.CYAN, UITheme.CYAN.lightened(0.3), 1, 6)
	pill.shadow_color = Color(UITheme.CYAN, 0.35)
	pill.shadow_size = 10
	var hover := UITheme.box(Color(UITheme.CYAN, 0.12), Color(0, 0, 0, 0), 0, 6)
	b.add_theme_stylebox_override("normal", pill if selected else clear)
	b.add_theme_stylebox_override("hover", pill if selected else hover)
	b.add_theme_stylebox_override("pressed", pill)
	b.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), Color(UITheme.CYAN, 0.8), 1, 6))
	var fc := UITheme.SPACE if selected else Color(UITheme.CREAM, 0.88)
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", UITheme.SPACE if selected else UITheme.CYAN)
	b.add_theme_color_override("font_focus_color", UITheme.SPACE if selected else UITheme.CYAN)
	b.add_theme_color_override("font_pressed_color", UITheme.SPACE)
	b.set_meta("selected", selected)

func _draw_gear(b: Button) -> void:
	var c := b.size / 2.0
	var col := UITheme.SPACE if b.get_meta("selected", false) else (UITheme.CYAN if b.is_hovered() else UITheme.CREAM)
	for i in 8:
		var d := Vector2.from_angle(TAU * i / 8.0)
		b.draw_line(c + d * 7.0, c + d * 12.0, col, 4.0)
	b.draw_arc(c, 8.0, 0, TAU, 24, col, 4.0, true)
	b.draw_arc(c, 3.0, 0, TAU, 12, col, 2.0, true)

## ------------------------------------------------------------------ home
func _mode() -> Dictionary:
	for m in MODES:
		if m["id"] == mode_id:
			return m
	return MODES[0]

func _set_mode(id: String) -> void:
	mode_id = id
	var m := _mode()
	mode_button.text = "   " + caps(str(m["label"]))
	mode_button.tooltip_text = str(m.get("hint", ""))
	if settings().home_mode != id:
		settings().home_mode = id
		launch.save_settings()

func cycle_mode(step: int = 1) -> void:
	var i := 0
	for k in MODES.size():
		if MODES[k]["id"] == mode_id:
			i = k
	_set_mode(MODES[(i + step + MODES.size()) % MODES.size()]["id"])

func _open_mode_menu() -> void:
	var r := mode_button.get_global_rect()
	mode_popup.reset_size()
	mode_popup.popup(Rect2i(Vector2i(r.position.x, r.position.y - mode_popup.size.y - 6), Vector2i(r.size.x, 0)))

## The big PLAY button: launch whatever the mode selector says.
func play_selected() -> void:
	var m := _mode()
	if m.has("queue"):
		pick_size = int(m["size"])
		_queue(str(m["queue"]))
	elif m.has("practice"):
		launch.start_game({"practice": str(m["practice"])})
	else:
		launch.start_game({"size": str(m["size"]), "mode": str(m["mode"])})

func _refresh_profile() -> void:
	profile.load_file(profile_path)
	var n: String = settings().player_name
	profile_name.text = (n if n != "" else "Rookie").to_upper()
	avatar.text = (n.left(1) if n != "" else "?").to_upper()
	profile_sub.text = _rating_line().to_upper() if n != "" else "NEW PLAYER"
	level_ring.level = profile.level()
	level_ring.xp = profile.xp % Cosmetics.XP_PER_LEVEL
	level_ring.need = Cosmetics.XP_PER_LEVEL
	level_ring.queue_redraw()
	lobby.set_player(n if n != "" else "Rookie", profile.equipped)

## ------------------------------------------------------------------ screens
func show_screen(id: String) -> void:
	if id == current:
		return
	current = id
	if browser:
		browser.queue_free()
		browser = null
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	for k in nav_buttons:
		_style_tab(nav_buttons[k], k == id)
		nav_buttons[k].queue_redraw()
	var home := id == "home"
	panel.visible = not home
	news.visible = home
	hud_right.visible = home
	music.set_widget_shown(home)
	_refresh_last_game()
	last_game.visible = last_game.visible and home
	# One launch button on screen (#125): side panels have their own (KICK OFF, QUICK MATCH...).
	play_cluster.visible = home
	lobby.set_panel_open(not home)
	_refresh_profile()
	if not home:
		content.add_theme_constant_override("separation", 8 if id == "online" else 12)
		call("_screen_" + id)
		content_scroll.scroll_vertical = 0
		content_scroll.scroll_horizontal = 0
		_fit_panel.call_deferred()

## Last match: result, players of the game, team stats, your line (src/ui/game_overview.gd).
func _screen_overview() -> void:
	var ov: Dictionary = launch.last_match
	if ov.is_empty():
		_text("No finished match yet this session.")
		return
	GameOverview.build(content, ov)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	content.add_child(h)
	_button("Play again", play_selected, h).name = "PlayAgain"
	var rp := str(ov.get("replay", ""))
	if rp != "" and FileAccess.file_exists(rp):
		_button("Watch replay", func(): launch.start_game({"replay": rp}), h)
	_button("Close", func(): show_screen("home"), h).name = "CloseOverview"

## Esc on Home, or Quit in Settings (#125: Quit was a footer link that exited immediately).
func _screen_quit() -> void:
	content.add_child(UITheme.heading("Quit Crater Bowl?"))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	content.add_child(h)
	_button("Quit", func(): get_tree().quit(), h).name = "ConfirmQuit"
	var stay := _button("Keep playing", func(): show_screen("home"), h)
	stay.grab_focus.call_deferred()

func _screen_welcome() -> void:
	content.add_child(UITheme.heading("Welcome to the Crater", 40, UITheme.CYAN))
	_text("Pick a name. It shows on scoreboards, leaderboards and your ranked rating. You can change it in Settings.")
	var name_edit := _line("Your name", "")
	name_edit.name = "NameEdit"
	var go := _button("Continue", func():
		var n := Settings.clean_name(name_edit.text)
		if n == "":
			_status("Names need 2-16 characters (and can't be You/Bot/Host).")
			return
		settings().player_name = n
		launch.save_settings()
		current = ""
		show_screen("home")
		play_button.grab_focus.call_deferred())
	name_edit.text_submitted.connect(func(_t): go.pressed.emit())
	name_edit.grab_focus.call_deferred()

func _screen_online() -> void:
	content.add_child(UITheme.heading("Play online"))
	content.add_child(UITheme.heading("Matchmaking", 22, UITheme.CYAN))
	_mode_picker()
	_size_picker(false)
	_party_row()
	var q := HBoxContainer.new()
	q.add_theme_constant_override("separation", 10)
	content.add_child(q)
	_button("Quick match", func(): _queue("casual"), q)
	_button("Ranked", func(): _queue("competitive"), q)
	content.add_child(UITheme.heading("Private match", 22, UITheme.CYAN))
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 10)
	content.add_child(host_row)
	var pub := CheckButton.new()
	pub.text = "List publicly in the match browser"
	pub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pub.button_pressed = list_public
	pub.toggled.connect(func(v): list_public = v)
	host_row.add_child(pub)
	_button("Host a match", func(): host_match(), host_row)
	var j := HBoxContainer.new()
	j.add_theme_constant_override("separation", 10)
	content.add_child(j)
	var code := _line("Invite code, like 7KQ2M-9XD4T, or an IP address", "", j)
	code.name = "JoinCode"
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var join := _button("Join", func(): _join(code.text), j)
	code.text_submitted.connect(func(_t): join.pressed.emit())
	content.add_child(UITheme.heading("Open matches", 22, UITheme.CYAN))
	browser = Browser.new()
	browser.name = "Browser"
	browser.setup(self, settings().matchmaker)
	content.add_child(browser)

func _screen_bots() -> void:
	content.add_child(UITheme.heading("Play vs bots"))
	_text("A full match offline. Bots fill every other slot.")
	_size_picker(true)
	_mode_picker()
	_button("Kick off", func(): launch.start_game({"size": str(pick_size), "mode": pick_mode}))

func _screen_practice() -> void:
	content.add_child(UITheme.heading("Training"))
	var desc := {"hub": "Free-roam field with a portal to each station. It's also where you wait while queued online.",
		"blocking": "You're the center. Keep the QB clean against up to 3 rushers.",
		"field": "Throw at 1/2/3-point targets and run a timed 40-yard dash.",
		"catching": "Jugs drill: a new route every rep, tighter coverage as you streak. Race to 15 catches.",
		"passing": "You're the QB. Hit receivers running the playbook.",
		"tackling": "You're the linebacker. Bring down a live runner.",
		"scrimmage": "Full 7v7 with bots. No clock, no pressure."}
	var names := {"hub": "Training ground", "field": "Practice field"}
	var order: Array = ["hub"] + Drills.STATIONS + ["passing", "tackling", "scrimmage"]
	for i in order.size():
		var k: String = order[i]
		if i == 4:
			content.add_child(UITheme.heading("Classic drills", 18, UITheme.CYAN))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		content.add_child(h)
		var b := _button(names.get(k, k.capitalize()), func(): launch.start_game({"practice": k}), h)
		b.custom_minimum_size = Vector2(190, 0)
		_text(desc.get(k, ""), h).size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _screen_locker() -> void:
	content.add_child(UITheme.heading("Locker room"))
	profile.load_file(profile_path)
	var lvl := profile.level()
	_text("Level %d  ·  %d XP  (%d to next level). Earn XP by playing matches; cosmetics never affect gameplay."
		% [lvl, profile.xp, Cosmetics.XP_PER_LEVEL - profile.xp % Cosmetics.XP_PER_LEVEL])
	for slot in ["trim", "helmet", "celebration", "badge"]:
		var h := HBoxContainer.new()
		content.add_child(h)
		var l := _text(slot.capitalize(), h)
		l.custom_minimum_size = Vector2(160, 0)
		var ob := OptionButton.new()
		ob.name = "Slot_" + slot
		ob.custom_minimum_size = Vector2(260, 0)
		var ids := []
		for id in Cosmetics.CATALOG.get(slot, {}).keys() + (profile.season_rewards if slot == "badge" else []):
			var ok := profile.is_unlocked(slot, id)
			var nm: String = Cosmetics.CATALOG.get(slot, {}).get(id, {}).get("name", str(id))
			var need := int(Cosmetics.CATALOG.get(slot, {}).get(id, {}).get("level", 0))
			ob.add_item(nm if ok else "%s  (level %d)" % [nm, need])
			ob.set_item_disabled(ob.item_count - 1, not ok)
			ids.append(id)
			if profile.equipped.get(slot) == id:
				ob.select(ob.item_count - 1)
		ob.item_selected.connect(func(i): _equip(slot, ids[i]))
		h.add_child(ob)
	var h2 := HBoxContainer.new()
	content.add_child(h2)
	var l2 := _text("Number", h2)
	l2.custom_minimum_size = Vector2(160, 0)
	var sb := SpinBox.new()
	sb.min_value = 0
	sb.max_value = 99
	sb.value = int(profile.equipped.get("number", 1))
	sb.value_changed.connect(func(v): _equip("number", int(v)))
	h2.add_child(sb)

func _screen_leaders() -> void:
	content.add_child(UITheme.heading("Leaderboard"))
	var lb := Leaderboard.new()
	lb.load_file(leaderboard_path)
	var rk := Ranked.new()
	rk.load_file(ranked_path)
	var pos: Array = lb.positions()
	if pos.is_empty():
		_text("No matches recorded yet. Finish a match to get on the board.")
		return
	var ob := OptionButton.new()
	for p in pos:
		ob.add_item(p)
	content.add_child(ob)
	var table := RichTextLabel.new()
	table.name = "Table"
	table.fit_content = true
	table.custom_minimum_size = Vector2(0, 300)
	content.add_child(table)
	var fill := func(i):
		table.clear()
		table.push_mono()
		table.add_text(lb.table_text(pos[i], 20))
		table.pop()
	ob.item_selected.connect(fill)
	fill.call(0)

func _screen_replays() -> void:
	content.add_child(UITheme.heading("Replays"))
	var files := list_replays(replay_dir)
	if files.is_empty():
		_text("No saved replays yet. Every finished match is saved here automatically.")
		return
	_text("Space pause · , . step · ← → previous / next play · H highlights · [ ] speed · C camera · V exit")
	for f in files.slice(0, 30):
		_button(f.get_file().get_basename().replace("_", " "), func(): launch.start_game({"replay": f}))

static func list_replays(dir_path: String) -> Array:
	var out := []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if not f.begins_with("test_"):
			out.append(dir_path.path_join(f))
	out.sort()
	out.reverse()   # newest first (timestamped names)
	return out

func _screen_settings() -> void:
	var s := settings()
	content.add_child(UITheme.heading("Settings"))
	content.add_child(UITheme.heading("Player", 22, UITheme.CYAN))
	var ne := _line("Name", s.player_name)
	ne.name = "NameEdit"
	ne.text_submitted.connect(func(t): _set_name(t))
	ne.focus_exited.connect(func(): _set_name(ne.text))
	content.add_child(UITheme.heading("Video", 22, UITheme.CYAN))
	var display_row := HBoxContainer.new()
	content.add_child(display_row)
	_text("Display mode", display_row).custom_minimum_size.x = 200
	var mode := OptionButton.new()
	mode.name = "DisplayMode"
	var modes := Settings.DISPLAY_MODES.keys()
	for id in modes:
		mode.add_item(Settings.DISPLAY_MODES[id]["label"])
	mode.select(modes.find(s.display_mode))
	mode.item_selected.connect(func(i):
		s.display_mode = modes[i]
		launch.save_settings())
	display_row.add_child(mode)
	_check("V-Sync", s.vsync, func(v): s.vsync = v; launch.save_settings())
	_slider("3D resolution", s.render_scale, 0.5, 1.0, 0.05, func(v): s.render_scale = v; launch.save_settings())
	var fh := HBoxContainer.new()
	content.add_child(fh)
	_text("Frame cap", fh).custom_minimum_size = Vector2(200, 0)
	var fps := OptionButton.new()
	for c in Settings.FPS_CAPS:
		fps.add_item("Unlimited" if c == 0 else str(c))
	fps.select(Settings.FPS_CAPS.find(s.max_fps))
	fps.item_selected.connect(func(i): s.max_fps = Settings.FPS_CAPS[i]; launch.save_settings())
	fh.add_child(fps)
	content.add_child(UITheme.heading("Audio", 22, UITheme.CYAN))
	_slider("Master volume", s.master_volume, 0.0, 1.0, 0.05, func(v): s.master_volume = v; launch.save_settings())
	_slider("Menu music", s.music_volume, 0.0, 1.0, 0.05, func(v): s.music_volume = v; music.set_volume(v); launch.save_settings())
	if music.widget_wanted():
		var mh := HBoxContainer.new()
		mh.add_theme_constant_override("separation", 10)
		content.add_child(mh)
		_text("Now playing", mh).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_button("Previous", music.prev, mh)
		_button("Pause", music.toggle_pause, mh)
		_button("Next", music.next, mh)
	content.add_child(UITheme.heading("Online", 22, UITheme.CYAN))
	var mm := _line("Matchmaker address", s.matchmaker)
	mm.text_submitted.connect(func(t): s.matchmaker = t.strip_edges(); launch.save_settings(); _status("Matchmaker set"))
	mm.focus_exited.connect(func(): s.matchmaker = mm.text.strip_edges(); launch.save_settings())
	_check("Open my router port automatically when hosting (UPnP)", s.upnp, func(v): s.upnp = v; launch.save_settings())
	content.add_child(UITheme.heading("Controls", 22, UITheme.CYAN))
	_text("Click an action, then press a key. Gamepads work automatically. Pressing a key that's already used swaps the two actions.")
	for a in Controls.ACTIONS:
		var h := HBoxContainer.new()
		content.add_child(h)
		_text(a[1], h).custom_minimum_size = Vector2(260, 0)
		var b := Button.new()
		b.name = "Bind_" + a[0]
		b.custom_minimum_size = Vector2(160, 0)
		b.text = Controls.key_name(Controls.key_for(a[0], s.bindings))
		var act: String = a[0]
		b.pressed.connect(func(): _capture_action = act; _capture_button = b; b.text = "PRESS A KEY…")
		h.add_child(b)
	_button("Reset controls to defaults", func():
		s.bindings = {}
		launch.save_settings()
		current = ""
		show_screen("settings"))
	content.add_child(UITheme.heading("Music credits", 22, UITheme.CYAN))
	for t in Music.load_playlist():
		_text(str(t.get("credit", "%s - %s" % [t.get("artist", ""), t.get("title", "")]))).add_theme_font_size_override("font_size", 14)
	content.add_child(UITheme.heading("Font credits", 22, UITheme.CYAN))
	_text("Graduate, Teko and Barlow Semi Condensed, from Google Fonts. SIL Open Font License 1.1.").add_theme_font_size_override("font_size", 14)
	# About: build, bug reports and quit live here (#125: were footer links).
	content.add_child(UITheme.heading("About", 22, UITheme.CYAN))
	_text("Crater Bowl  ·  build v%s" % launch.version())
	var ah := HBoxContainer.new()
	ah.add_theme_constant_override("separation", 10)
	content.add_child(ah)
	_button("Report a bug", func(): OS.shell_open(BUG_URL), ah)
	_button("Quit game", func(): show_screen("quit"), ah).name = "QuitGame"

func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	if _capture_action == "":
		if e.keycode == KEY_ESCAPE and current not in ["home", "welcome"]:
			get_viewport().set_input_as_handled()
			show_screen("home")
		elif e.keycode == KEY_ESCAPE and current == "home":
			get_viewport().set_input_as_handled()
			show_screen("quit")
		elif current == "home" and e.keycode == KEY_TAB:
			get_viewport().set_input_as_handled()
			cycle_mode(-1 if e.shift_pressed else 1)
		elif current == "home" and e.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			get_viewport().set_input_as_handled()
			play_selected()
		return
	get_viewport().set_input_as_handled()
	var act := _capture_action
	_capture_action = ""
	if e.keycode != KEY_ESCAPE:
		capture_binding(act, e.keycode)
	current = ""
	show_screen("settings")

## Rebind (tests call this directly too).
func capture_binding(action: String, key: int) -> void:
	settings().bindings = Controls.rebind(settings().bindings, action, key)
	launch.save_settings()

## ------------------------------------------------------------------ actions
func _queue(mode: String) -> void:
	_with_port(QUEUE_HOST_PORT, func(port_options):
		var o := queue_options(mode)
		o.merge(port_options)
		launch.start_game(o))

## Options for a queue launch (party: everyone enters the same code + size).
func queue_options(mode: String) -> Dictionary:
	var o := {"queue": mode, "mm": settings().matchmaker, "size": str(3 if pick_mode == "chaosball" else pick_size),
		"host-port": str(QUEUE_HOST_PORT)}
	if pick_mode == "chaosball":
		o["mode"] = "chaosball"
	var code := party_code.strip_edges().to_upper()
	if party_size >= 2 and code != "":
		o["party"] = "%s:%d" % [code, party_size]
	return o

static func new_party_code() -> String:
	const A := "ABCDEFGHJKMNPQRSTVWXYZ23456789"
	var s := ""
	for i in 5:
		s += A[randi() % A.length()]
	return s

func _party_row() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	content.add_child(h)
	_text("Party", h).custom_minimum_size = Vector2(120, 0)
	var size_ob := OptionButton.new()
	size_ob.name = "PartySize"
	for n in range(1, 8):
		size_ob.add_item("Solo" if n == 1 else "%d friends" % n)
	size_ob.select(party_size - 1)
	h.add_child(size_ob)
	var code := _line("Party code", party_code, h)
	code.name = "PartyCode"
	code.custom_minimum_size = Vector2(150, 0)
	code.max_length = 8
	code.editable = party_size >= 2
	code.visible = party_size >= 2   # hidden for Solo instead of a dead field (#125)
	code.text_changed.connect(func(t): party_code = t)
	var gen := _button("New code", func():
		party_code = new_party_code()
		code.text = party_code, h)
	gen.disabled = party_size < 2
	gen.visible = party_size >= 2
	var hint := _text("Everyone in the party picks the same size + code, then queues.")
	hint.add_theme_color_override("font_color", Color(UITheme.REGOLITH, 0.9))
	hint.visible = party_size >= 2
	size_ob.item_selected.connect(func(i):
		party_size = i + 1
		code.editable = party_size >= 2
		code.visible = party_size >= 2
		gen.disabled = party_size < 2
		gen.visible = party_size >= 2
		hint.visible = party_size >= 2
		if party_size >= 2 and party_code == "":
			party_code = new_party_code()
			code.text = party_code)

func host_match() -> void:
	_with_port(host_port, func(port_options):
		var o := {"host": true, "size": str(pick_size), "mode": pick_mode}
		if host_port != NetSession.DEFAULT_PORT:
			o["port"] = str(host_port)
		o.merge(port_options)
		if list_public:
			o["public"] = true
		launch.start_game(o))

## Open the router port with UPnP (if enabled), then pass the launch options to cb.
## Without UPnP the invite code carries the LAN address (works on LAN / manual forward).
func _with_port(port: int, cb: Callable) -> void:
	if busy:
		return
	if not settings().upnp:
		cb.call({})
		return
	busy = true
	_status("Opening port %d on your router…" % port)
	_upnp_thread = _open_port_async(port, func(res):
		busy = false
		_upnp_thread.wait_to_finish()
		if res.get("ok", false):
			_status("Port %d open · public address %s" % [port, res["ip"]])
			cb.call({"advertise": str(res["ip"])})
		else:
			var notice := "%s.\nFor remote play, forward UDP port %d to this PC." % [res.get("error", "UPnP failed"), port]
			cb.call({"port-mapping-notice": notice}))

func _open_port_async(port: int, cb: Callable) -> Thread:
	return PortMapper.open_port_async(port, cb)

func _join(target: String) -> void:
	target = target.strip_edges()
	if target == "":
		_status("Enter an invite code or IP address.")
		return
	if not InviteCode.looks_like_code(target) and not target.is_valid_ip_address():
		_status("That doesn't look like an invite code (10 letters and numbers, like 7KQ2M-9XD4T) or an IP address.")
		return
	launch.start_game({"join": target.to_upper() if InviteCode.looks_like_code(target) else target})

func _equip(slot: String, id) -> void:
	if profile.equip(slot, id):
		profile.save(profile_path)

func _set_name(t: String) -> void:
	var n := Settings.clean_name(t)
	if n == "":
		_status("Names need 2-16 characters.")
		return
	if n != settings().player_name:
		settings().player_name = n
		launch.save_settings()
		_status("Name saved")

func _rating_line() -> String:
	var rk := Ranked.new()
	rk.load_file(ranked_path)
	return rk.label(settings().player_name)

## ------------------------------------------------------------------ widgets
func _status(t: String) -> void:
	status_label.text = t
	toast.visible = t != ""
	toast.reset_size()
	toast.offset_left = -toast.size.x / 2.0
	toast.offset_right = toast.size.x / 2.0
	if t != "":
		_toast_timer.start()

func _text(t: String, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if parent == null:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_override("font", UITheme.body_font())
	l.add_theme_font_size_override("font_size", 18)
	(parent if parent else content).add_child(l)
	return l

func _button(t: String, cb: Callable, parent: Node = null) -> Button:
	var b := Button.new()
	b.text = caps(t)
	b.pressed.connect(cb)
	(parent if parent else content).add_child(b)
	return b

func _line(placeholder: String, value: String, parent: Node = null) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = value
	e.custom_minimum_size = Vector2(320, 0)
	(parent if parent else content).add_child(e)
	return e

func _check(t: String, value: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = t
	c.button_pressed = value
	c.toggled.connect(cb)
	content.add_child(c)
	return c

func _slider(t: String, value: float, lo: float, hi: float, step: float, cb: Callable) -> HSlider:
	var h := HBoxContainer.new()
	content.add_child(h)
	_text(t, h).custom_minimum_size = Vector2(200, 0)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(260, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(cb)
	h.add_child(s)
	return s

func _size_picker(include_label: bool) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	content.add_child(h)
	_text("Team size" if include_label else "Size", h).custom_minimum_size = Vector2(120, 0)
	var group := ButtonGroup.new()
	_size_buttons.clear()
	for s in SIZES:
		var b := Button.new()
		b.text = "%dv%d" % [s, s]
		b.toggle_mode = true
		b.button_group = group
		b.set_meta("size", s)
		b.pressed.connect(func(): pick_size = s)
		h.add_child(b)
		_size_buttons.append(b)
	_sync_size_picker()

## Chaosball is always 3v3: show 3v3 and lock the row. pick_size is left alone, so
## switching back to Classic restores the earlier pick (#83).
func _sync_size_picker() -> void:
	var chaos := pick_mode == "chaosball"
	for b in _size_buttons:
		if not is_instance_valid(b):
			continue
		var s: int = b.get_meta("size")
		b.button_pressed = s == (3 if chaos else pick_size)
		b.disabled = chaos
		# The theme's disabled box hides "pressed": keep the forced 3v3 reading as the pick, dimmed.
		if chaos and s == 3:
			b.add_theme_stylebox_override("disabled", UITheme.box(Color(UITheme.CYAN, 0.15), Color(UITheme.CYAN, 0.55)))
			b.add_theme_color_override("font_disabled_color", Color(UITheme.CREAM, 0.75))
		else:
			b.remove_theme_stylebox_override("disabled")
			b.remove_theme_color_override("font_disabled_color")
		b.tooltip_text = "Chaosball is always 3v3" if chaos else ""

func _mode_picker() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	content.add_child(h)
	_text("Rules", h).custom_minimum_size = Vector2(120, 0)
	var group := ButtonGroup.new()
	for m in [["classic", "Classic"], ["chaosball", "Chaosball (3v3, low-g)"]]:
		var b := Button.new()
		b.text = caps(m[1])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = m[0] == pick_mode
		var id: String = m[0]
		b.pressed.connect(func():
			pick_mode = id
			_sync_size_picker())
		h.add_child(b)

## Top/bottom darkening so the bars and HUD read over the 3D lobby.
class Shade extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var s := size
		var dark := Color(0.0, 0.0, 0.02, 0.75)
		var clear := Color(0.0, 0.0, 0.02, 0.0)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, 190), Vector2(0, 190)]),
			PackedColorArray([dark, dark, clear, clear]))
		var y := s.y - 300.0
		draw_polygon(PackedVector2Array([Vector2(0, y), Vector2(s.x, y), Vector2(s.x, s.y), Vector2(0, s.y)]),
			PackedColorArray([clear, clear, dark, dark]))
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

## Level badge: XP progress arc around the level number.
class LevelRing extends Control:
	const C := preload("res://src/ui/ui_theme.gd")
	var level := 1
	var xp := 0
	var need := 500
	func _draw() -> void:
		var r := minf(size.x, size.y - 30.0) / 2.0 - 8.0
		var c := Vector2(size.x / 2.0, r + 8.0)
		draw_circle(c, r, Color(C.SPACE, 0.7))
		draw_arc(c, r, 0, TAU, 64, Color(C.CREAM, 0.12), 9.0, true)
		var f := clampf(float(xp) / maxf(need, 1), 0.0, 1.0)
		if f > 0.0:
			draw_arc(c, r, -PI / 2, -PI / 2 + TAU * f, 64, C.CYAN, 9.0, true)
		var small := C.font(600)
		var big := C.font(700)
		draw_string(small, c + Vector2(-r, -r * 0.3), "LEVEL", HORIZONTAL_ALIGNMENT_CENTER, r * 2, 16, Color(C.CREAM, 0.75))
		draw_string(big, c + Vector2(-r, r * 0.42), str(level), HORIZONTAL_ALIGNMENT_CENTER, r * 2, 58, C.CREAM)
		draw_string(small, Vector2(0, size.y - 4), "XP  %d / %d" % [xp, need], HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, C.CYAN)
