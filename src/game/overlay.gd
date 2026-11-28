extends CanvasLayer
## Broadcast-style match overlay: scorebug, play clock, status line, play-call
## picker, movement meters, hold-to-view scoreboard, and event banners.
## Reads main's state each frame. Text/debug HUD (main.hud) is kept for lobby,
## search and the final summary.

const Mats := preload("res://src/game/art/materials.gd")
const UITheme := preload("res://src/ui/ui_theme.gd")
const T := preload("res://src/sim/tuning.gd")
const Routes := preload("res://src/sim/routes.gd")
const World := preload("res://src/sim/world.gd")
const DefensivePlaybook := preload("res://src/sim/defensive_playbook.gd")
const Penalties := preload("res://src/sim/penalties.gd")
## Picker buttons, built once (#169): the longest list either side shows. Offense with a run
## back: passes + runs + Repeat last/Flip play; defense: calls + Repeat last.
var PICKER_POOL := maxi(Routes.PLAY_NAMES.size() + Routes.RUN_NAMES.size() + 2, DefensivePlaybook.CALLS.size() + 1)
const Teams := preload("res://src/sim/teams.gd")
const TeamLogos := preload("res://src/game/art/team_logos.gd")
## The two teams on the bug (#233): team 0 = HELIOS, team 1 = NEBULA until the team picker
## (#234) calls set_teams(). Names/codes come from src/sim/teams.gd, not literals.
var team_ids: Array = Teams.DEFAULT_IDS.duplicate()
var TEAM_NAMES: Array = [Teams.default_team(0)["name"], Teams.default_team(1)["name"]]
var TEAM_ABBR: Array = [Teams.default_team(0)["code"], Teams.default_team(1)["code"]]
var team_logo: Array[TextureRect] = []    # scorebug logo per team
var board_logo: Array[TextureRect] = []   # hold-Tab scoreboard logo per team
var _abbr_l: Array[Label] = []
## Logo sizes: the bug's team row is 34 px tall; the Tab board is a big centered card.
const BUG_LOGO := 34.0
const BOARD_LOGO := 88.0
const NAVY := Color(0.055, 0.078, 0.14, 0.9)
const ACCENT := Color(0.36, 0.88, 1.0)
const ALERT := Color(1.0, 0.42, 0.12)
## Fixed scorebug width (#116): reserving the play-clock cell keeps the bug from jumping
## and re-centering at the snap and the whistle. Content wider than this still grows it.
const BUG_W := 744.0   # fits every state in Teko (#125 Slice A; was 600 with Rajdhani), +2 × (34 px logo + 8 px gap) for the team logos (#233)
## Bottom HUD stack (#116): scorebug flush to the bottom, the movement meters beside it and
## the status pill on its top-left edge, so nothing floats over the controlled player.
const BUG_BOTTOM := 14.0
const STACK_GAP := 8.0

var root: Control
var bug: PanelContainer
var team_score: Array = []   # Label per team
var team_tab: Array = []     # ColorRect per team
var poss: Array = []         # possession pip per team
var timeout_pips: Array[Label] = []
var clock_l: Label
var down_l: Label
var play_clock_l: Label
var play_clock_div: ColorRect
var status_l: Label
var status_pill: PanelContainer
## #253: penalty line, from the flag until the next snap (above the status pill, right-aligned).
const FLAG_YELLOW := Color(1.0, 0.84, 0.12)
var flag_pill: PanelContainer
var flag_l: Label
var mode_l: Label
var spot_l: Label
var field_strip: Control
var field_marks := Vector2(-1, -1)
var picker: PanelContainer
var picker_title: Label
var coaching_text: Label
var picker_grid: GridContainer
var route_select: OptionButton
var formation_select: OptionButton
var picker_side := -1
var picker_calls: Array = []
var _picker_main   # set on refresh; pooled buttons call its do_action
var scoreboard: PanelContainer
var scoreboard_label: Label
var me_panel: PanelContainer
var stamina_bar: ProgressBar
var stamina_fill: StyleBoxFlat
var move_circles: Array[Control] = []
var move_charge := 2.0
var banner: Label
var banner_sub: Label
var banner_t := 0.0
var _prev := {}
## HUD text/state refresh rate. Nothing on the scorebug changes faster than ~10 Hz, and
## rebuilding a dozen strings + label layouts every render frame cost ~1 ms/frame
## (docs/optimization/LOG.md). Animated bits (throw bar, banner) still run per frame.
const TEXT_HZ := 20.0
var _text_t := 0.0
var _was_pre_game := true
## Dead-ball summary (#116): what the last play did, from the world events.
var _play := {}

func _ready() -> void:
	layer = 5
	root = Control.new()
	root.name = "Overlay"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_scorebug()
	_build_picker()
	_build_me()
	_build_banner()
	_build_scoreboard()

# --- builders ---------------------------------------------------------------

static func _box(bg: Color, radius: int = 6, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

func _label(size: int, c: Color = Color.WHITE, weight: int = 700) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = Mats.ui_font(weight)
	ls.font_size = size
	ls.font_color = c
	ls.outline_size = 0
	ls.shadow_size = 3
	ls.shadow_color = Color(0, 0, 0, 0.45)
	ls.shadow_offset = Vector2(1, 2)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_scorebug() -> void:
	bug = PanelContainer.new()
	bug.name = "Scorebug"
	bug.add_theme_stylebox_override("panel", _box(NAVY, 8, Color(1, 1, 1, 0.08), 1))
	bug.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bug.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bug.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bug.custom_minimum_size.x = BUG_W
	bug.position.y = -BUG_BOTTOM
	root.add_child(bug)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	bug.add_child(rows)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	rows.add_child(row)
	for t in 2:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		var tab := ColorRect.new()
		tab.custom_minimum_size = Vector2(6, 34)
		cell.add_child(tab)
		team_tab.append(tab)
		var logo := TeamLogos.rect(team_ids[t], BUG_LOGO)
		logo.name = "TeamLogo%d" % t
		cell.add_child(logo)
		team_logo.append(logo)
		var team_label := VBoxContainer.new()
		team_label.alignment = BoxContainer.ALIGNMENT_CENTER
		team_label.add_theme_constant_override("separation", 0)
		var name_l := _label(22, Color(0.92, 0.95, 1.0), 700)
		name_l.text = TEAM_ABBR[t]
		_abbr_l.append(name_l)
		team_label.add_child(name_l)
		var pips := _label(11, Color(0.85, 0.92, 1.0), 700)
		timeout_pips.append(pips)
		team_label.add_child(pips)
		cell.add_child(team_label)
		var sc := _label(30, Color.WHITE, 800)
		sc.custom_minimum_size.x = 34
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(sc)
		team_score.append(sc)
		var pip := _label(16, Color(1.0, 0.8, 0.3), 800)
		pip.text = "◆"
		pip.custom_minimum_size.x = 14
		cell.add_child(pip)
		poss.append(pip)
		row.add_child(cell)
		if t == 0:
			row.add_child(_divider())
	row.add_child(_divider())
	clock_l = _label(22, Color.WHITE, 700)
	clock_l.custom_minimum_size.x = 70
	clock_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(clock_l)
	row.add_child(_divider())
	# Down & distance takes the slack, so the bug keeps one width whether or not the play
	# clock is up; the clock cell and its divider hide together (no empty cell, no stray rule).
	down_l = _label(22, Color(1.0, 0.86, 0.35), 700)
	down_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	down_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(down_l)
	play_clock_div = _divider()
	row.add_child(play_clock_div)
	play_clock_l = _label(22, ACCENT, 800)
	play_clock_l.custom_minimum_size.x = 84
	play_clock_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(play_clock_l)
	var details := HBoxContainer.new()
	details.alignment = BoxContainer.ALIGNMENT_CENTER
	details.add_theme_constant_override("separation", 16)
	rows.add_child(details)
	mode_l = _label(15, ACCENT)
	details.add_child(mode_l)
	spot_l = _label(15)
	details.add_child(spot_l)
	field_strip = Control.new()
	field_strip.custom_minimum_size = Vector2(128, 20)
	field_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_strip.draw.connect(_draw_field_strip)
	details.add_child(field_strip)
	# Hold the row's height when all three hide (the coin toss, #131) so the bug doesn't jump.
	details.custom_minimum_size.y = maxf(spot_l.get_combined_minimum_size().y, field_strip.custom_minimum_size.y)
	# Status pill: a small backed tab on the scorebug's top-left edge, off the player.
	status_pill = PanelContainer.new()
	status_pill.name = "StatusPill"
	var ps := _box(NAVY, 6, Color(ACCENT, 0.35), 1)
	ps.content_margin_top = 2
	ps.content_margin_bottom = 2
	status_pill.add_theme_stylebox_override("panel", ps)
	status_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_pill.visible = false
	root.add_child(status_pill)
	status_l = _label(17, Color(0.95, 0.97, 1.0), 700)
	status_pill.add_child(status_l)
	flag_pill = PanelContainer.new()
	flag_pill.name = "FlagPill"
	var fs := _box(FLAG_YELLOW, 6, Color(0.03, 0.04, 0.1, 0.6), 1)
	fs.content_margin_top = 2
	fs.content_margin_bottom = 2
	flag_pill.add_theme_stylebox_override("panel", fs)
	flag_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flag_pill.visible = false
	root.add_child(flag_pill)
	flag_l = _label(18, Color(0.06, 0.06, 0.1), 800)
	flag_l.label_settings.shadow_size = 0
	flag_pill.add_child(flag_l)

func _divider() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(1, 1, 1, 0.14)
	d.custom_minimum_size = Vector2(1, 30)
	return d

func _build_picker() -> void:
	picker = PanelContainer.new()
	picker.name = "PlayPicker"
	var pst := _box(NAVY, 8, ACCENT.darkened(0.5), 1)
	pst.content_margin_left = 12
	pst.content_margin_right = 12
	pst.content_margin_top = 10
	pst.content_margin_bottom = 12
	picker.add_theme_stylebox_override("panel", pst)
	# Menu theme (fonts, button states, selected call) instead of Godot's default widgets.
	picker.theme = _picker_theme()
	# Pinned top-right, over the sky: the old center-right spot covered the near receiver.
	picker.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	picker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	picker.grow_vertical = Control.GROW_DIRECTION_END
	picker.position = Vector2(-16, 16)
	root.add_child(picker)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	picker.add_child(column)
	picker_title = _label(17, ACCENT)
	column.add_child(picker_title)
	coaching_text = _label(16)
	column.add_child(coaching_text)
	formation_select = OptionButton.new()
	formation_select.focus_mode = Control.FOCUS_NONE
	for formation in World.FORMATION_NAMES:
		formation_select.add_item("Formation · " + formation)
	formation_select.item_selected.connect(func(index: int):
		if _picker_main != null:
			_picker_main.do_action({"a": "formation", "f": index}))
	formation_select.hide()
	column.add_child(formation_select)
	picker_grid = GridContainer.new()
	picker_grid.columns = 2
	picker_grid.add_theme_constant_override("h_separation", 6)
	picker_grid.add_theme_constant_override("v_separation", 6)
	column.add_child(picker_grid)
	# Built up front so the node count never changes mid-match (perf.sh's leak check, #169).
	for i in PICKER_POOL:
		_add_picker_button()
	route_select = OptionButton.new()
	route_select.focus_mode = Control.FOCUS_NONE
	column.add_child(route_select)

func _add_picker_button() -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.visible = false
	b.pressed.connect(func():
		if _picker_main != null and b.has_meta("action"):
			_picker_main.do_action(b.get_meta("action")))
	picker_grid.add_child(b)

## UITheme's menu look, compacted for the in-game picker.
static func _picker_theme() -> Theme:
	var t: Theme = UITheme.build()
	t.default_font_size = 17
	for cls in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var sb: StyleBoxFlat = (t.get_stylebox(state, cls) as StyleBoxFlat).duplicate()
			sb.content_margin_left = 12
			sb.content_margin_right = 12
			sb.content_margin_top = 3
			sb.content_margin_bottom = 3
			t.set_stylebox(state, cls, sb)
	# The current call reads as selected: solid cyan with dark text.
	var on := UITheme.box(UITheme.CYAN, UITheme.CYAN, 2)
	on.content_margin_top = 3
	on.content_margin_bottom = 3
	on.content_margin_left = 12
	on.content_margin_right = 12
	t.set_stylebox("pressed", "Button", on)
	t.set_color("font_pressed_color", "Button", UITheme.SPACE)
	t.set_color("font_hover_pressed_color", "Button", UITheme.SPACE)
	return t

func _build_me() -> void:
	me_panel = PanelContainer.new()
	me_panel.name = "MovementMeters"
	me_panel.add_theme_stylebox_override("panel", _box(NAVY, 8, Color(1, 1, 1, 0.08), 1))
	# Beside the scorebug (left), not stacked above it on the player's ring. Placed in
	# _layout_stack once the bug has its size.
	me_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	root.add_child(me_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	me_panel.add_child(row)
	stamina_bar = ProgressBar.new()
	stamina_bar.show_percentage = false
	stamina_bar.custom_minimum_size = Vector2(175, 10)
	stamina_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stamina_bar.max_value = 1.0
	stamina_bar.add_theme_stylebox_override("background", _box(Color(1, 1, 1, 0.15), 4))
	stamina_fill = _box(ACCENT, 4)
	stamina_fill.content_margin_top = 0
	stamina_fill.content_margin_bottom = 0
	stamina_bar.add_theme_stylebox_override("fill", stamina_fill)
	row.add_child(stamina_bar)
	for i in 2:
		var circle := Control.new()
		circle.custom_minimum_size = Vector2(21, 21)
		circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		circle.draw.connect(_draw_move_circle.bind(circle, i))
		row.add_child(circle)
		move_circles.append(circle)

func _draw_move_circle(circle: Control, index: int) -> void:
	var center := circle.size * 0.5
	var fraction := clampf(move_charge - index, 0.0, 1.0)
	circle.draw_circle(center, 8.0, Color(1, 1, 1, 0.12), true, -1.0, true)
	circle.draw_arc(center, 8.0, -PI / 2.0, TAU - PI / 2.0, 32, Color(1, 1, 1, 0.25), 2.0, true)
	if fraction > 0.0:
		circle.draw_arc(center, 8.0, -PI / 2.0, fraction * TAU - PI / 2.0, 32, ACCENT, 4.0, true)

func _build_scoreboard() -> void:
	scoreboard = PanelContainer.new()
	scoreboard.name = "Scoreboard"
	scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard.add_theme_stylebox_override("panel", _box(NAVY, 10, ACCENT.darkened(0.5), 1))
	scoreboard.set_anchors_preset(Control.PRESET_CENTER)
	scoreboard.grow_horizontal = Control.GROW_DIRECTION_BOTH
	scoreboard.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(scoreboard)
	# Logos flank the text (#233): team 0's on the left, beside its name and score.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	scoreboard.add_child(row)
	scoreboard_label = _label(23)
	scoreboard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	scoreboard_label.custom_minimum_size = Vector2(440, 0)
	for t in 2:
		var logo := TeamLogos.rect(team_ids[t], BOARD_LOGO)
		logo.name = "BoardLogo%d" % t
		board_logo.append(logo)
	row.add_child(board_logo[0])
	row.add_child(scoreboard_label)
	row.add_child(board_logo[1])
	scoreboard.hide()

## Show teams `ids` (two Teams ids) on the scorebug and Tab board. The team picker (#234)
## calls this; until then every match is the default HELIOS vs NEBULA. Unknown ids keep the
## side's current team.
func set_teams(ids: Array) -> void:
	for t in 2:
		var team := Teams.team(str(ids[t])) if t < ids.size() else {}
		if team.is_empty():
			continue
		team_ids[t] = team["id"]
		TEAM_NAMES[t] = team["name"]
		TEAM_ABBR[t] = team["code"]
		if t < _abbr_l.size():
			_abbr_l[t].text = team["code"]
			team_logo[t].texture = TeamLogos.logo(team["id"])
			board_logo[t].texture = TeamLogos.logo(team["id"])

func _build_banner() -> void:
	banner = _label(84, Color.WHITE, 800)
	banner.label_settings.outline_size = 14
	banner.label_settings.outline_color = Color(0.03, 0.04, 0.1, 0.85)
	banner.label_settings.shadow_size = 12
	banner.label_settings.shadow_color = Color(0, 0, 0, 0.35)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.position.y = -150
	banner.visible = false
	root.add_child(banner)
	banner_sub = _label(30, ACCENT, 800)
	# Outlined like the banner: subtitles land on goalposts and field paint.
	banner_sub.label_settings.outline_size = 8
	banner_sub.label_settings.outline_color = Color(0.03, 0.04, 0.1, 0.9)
	banner_sub.set_anchors_preset(Control.PRESET_CENTER)
	banner_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.position.y = -55
	banner_sub.visible = false
	root.add_child(banner_sub)

# --- events -----------------------------------------------------------------

func show_banner(text: String, sub: String = "", c: Color = Color.WHITE, dur: float = 2.2) -> void:
	banner.text = text
	banner.label_settings.font_color = c
	banner_sub.text = sub
	banner_t = dur
	banner.visible = true
	banner_sub.visible = sub != ""

func on_event(n: String, d: Dictionary) -> void:
	match n:
		"touchdown":
			var t := int(d.get("team", 0))
			show_banner("TOUCHDOWN", TEAM_NAMES[t] if t >= 0 and t < 2 else "", Color(1.0, 0.86, 0.3), 3.0)
		"interception": show_banner("INTERCEPTION", "", ALERT)
		"fumble": show_banner("FUMBLE", "", ALERT)
		"tackle", "out_of_bounds":
			var credit := float(d.get("progress", 0.0))
			if credit >= T.FORWARD_PROGRESS_BANNER:
				show_banner("FORWARD PROGRESS", "+%d YD" % maxi(1, roundi(credit)), ACCENT, 1.6)
		"recovery": show_banner("RECOVERED", "TURNOVER" if d.get("turnover", false) else "", ACCENT)
		"explode": show_banner("BALL EXPLODED", "", ALERT, 1.6)
		"clock_warning": show_banner("ONE-MINUTE WARNING", "", ACCENT)
		"timeout":
			var team: int = d["team"]
			show_banner("TIMEOUT", TEAM_NAMES[team], ACCENT)
		"snap":
			if banner.text in ["TIMEOUT", "ONE-MINUTE WARNING"]:
				banner_t = 0.0
			flag_pill.visible = false
		"flag":
			show_banner("FLAG", Penalties.name_of(d), FLAG_YELLOW, 1.8)
			_show_flag(Penalties.ruling(d))
		"penalty":
			_show_flag(str(d.get("ruling", "")))
	_track_play(n, d)

func _show_flag(text: String) -> void:
	flag_l.text = text
	flag_pill.visible = text != ""

## Remember what the current play did, for the dead-ball summary.
func _track_play(n: String, d: Dictionary) -> void:
	var w = _last_world
	match n:
		"snap":
			_play = {"los": w.los_y if w else 0.0, "off": w.offense_team if w else 0,
				"qb": int(d.get("qb", -1)), "kick": w.kick_play if w else "", "pass": false, "tags": []}
		"throw":
			_play["pass"] = true
		"interception":
			_play["tags"] = ["INTERCEPTION"]
		"recovery":
			if d.get("turnover", false):
				_play["tags"] = ["FUMBLE LOST"]
		"tackle", "out_of_bounds":
			_play["end"] = n
			_play["carrier"] = int(d.get("carrier", -1))
			_play["team"] = int(d.get("team", -1))
			_play["spot"] = d.get("spot", null)

# --- per frame --------------------------------------------------------------

var _last_world

func refresh(main, delta: float) -> void:
	var s = main.series
	var w = main.world
	if _last_world != w:
		_last_world = w
		_text_t = 0.0
	var pre_game: bool = main.in_lobby()   # queued + warming up on the training ground still shows the overlay
	var final: bool = s != null and s.is_final()
	root.visible = not pre_game
	# The detailed text HUD stays for lobby/search/final summary only.
	if main.hud:
		main.hud.visible = pre_game or final
		if main.hud.label_settings == null:
			var ls := LabelSettings.new()
			ls.font = Mats.ui_font(600)
			ls.font_size = 20
			ls.outline_size = 6
			ls.outline_color = Color(0.02, 0.03, 0.08, 0.9)
			main.hud.label_settings = ls
	if pre_game or s == null:
		_was_pre_game = true
		return
	_refresh_picker(main, final)
	scoreboard.visible = main.scoreboard_held
	_animate_banner(delta)
	_text_t -= delta
	if _text_t > 0.0 and not _was_pre_game:
		return
	_text_t = 1.0 / TEXT_HZ
	_was_pre_game = false
	for t in 2:
		(team_tab[t] as ColorRect).color = main.TEAM_COLORS[t]
		(team_score[t] as Label).text = str(s.score[t])
		(poss[t] as Label).modulate.a = 1.0 if w.possession_team() == t and not final else 0.0
		timeout_pips[t].visible = main.drill == null
		timeout_pips[t].text = "●".repeat(s.clock.timeouts[t]) + "○".repeat(s.clock.timeout_limit - s.clock.timeouts[t])
	clock_l.text = "FINAL" if final else ("" if main.drill != null else s.clock.label())
	down_l.text = _down_text(main)
	var pc: int = s.play_clock_shown()   # #136: the value the snap obeys, or -1 = hidden
	var clock_up: bool = pc >= 0 and main.drill == null
	play_clock_l.text = "PLAY :%02d" % pc if clock_up else ""
	play_clock_l.visible = clock_up
	play_clock_div.visible = clock_up
	play_clock_l.label_settings.font_color = ALERT if pc <= 5 and _my_snap(main) else ACCENT
	mode_l.text = _hud_title(main)
	mode_l.visible = mode_l.text != ""
	_refresh_field_position(main, final)
	status_l.text = _status_text(main)
	status_pill.visible = status_l.text != ""
	_refresh_me(main)
	me_panel.visible = not final
	bug.visible = true
	_layout_stack()
	if scoreboard.visible:
		# #131: mode/size lives here, on the hold-to-view board, not on the live HUD.
		scoreboard_label.text = "%s\n%s     %d – %d     %s\n%s     ·     %s\n%s possession" % [
			_mode_text(main) if main.drill == null else _hud_title(main),
			TEAM_NAMES[0], s.score[0], s.score[1], TEAM_NAMES[1], clock_l.text,
			_down_text(main, true), TEAM_NAMES[w.possession_team()]]
	# First down detection (same offense, down reset, chains moved).
	var key := [w.offense_team, s.downs.down, snappedf(s.downs.first_down_y, 0.1)]
	if not _prev.is_empty() and _prev["k"][0] == key[0] and key[1] == 1 and _prev["k"][1] > 1 and int(s.state) == 0:
		show_banner("FIRST DOWN", "", Color(1.0, 0.86, 0.35), 1.4)
	elif not _prev.is_empty() and _prev["k"][0] != key[0] and _prev["k"][1] == 4 and _prev.get("score", []) == s.score and not final:
		show_banner("TURNOVER ON DOWNS", "", ALERT, 1.8)
	_prev = {"k": key, "score": s.score.duplicate()}

## Banner animation: punch in, hold, fade (every frame).
func _animate_banner(delta: float) -> void:
	if banner_t > 0.0:
		banner_t = maxf(0.0, banner_t - delta)
		var age := 3.0 - banner_t
		var a := clampf(banner_t * 2.5, 0.0, 1.0)
		var sc := 1.0 + maxf(0.0, 0.35 - age * 1.6) if banner_t > 0.0 else 1.0
		banner.pivot_offset = banner.size * 0.5
		banner.scale = Vector2(sc, sc)
		banner.modulate.a = a
		banner_sub.modulate.a = a
	else:
		banner.visible = false
		banner_sub.visible = false

## `board` = the Tab scoreboard. The live scorebug drops the KICKOFF / COIN TOSS phase
## words (#131): the cell is down & distance only, and kickoffs/tosses have none.
func _down_text(main, board := false) -> String:
	var s = main.series
	if main.drill != null:
		return main.drill.label()
	if int(s.state) == 1:
		return "TRY FOR %d" % s.try_points
	if int(s.state) == 2:
		return "KICKOFF" if board else ""
	if int(s.state) == 3:
		return "COIN TOSS" if board else ""
	if main.world.is_chaos():
		return "STREAK %d  ·  TD %d" % [main.world.streak, main.world.streak_points()]
	var lab: String = s.downs.label()
	var at := lab.find(" at ")
	return (lab.substr(0, at) if at > 0 else lab).to_upper()

func _refresh_field_position(main, final: bool) -> void:
	var s = main.series
	var d = s.downs
	var show_spot: bool = not final and main.drill == null and s.state != main.Match.State.TOSS
	spot_l.visible = show_spot
	field_strip.visible = show_spot and s.state == main.Match.State.SCRIMMAGE and not main.world.is_chaos()
	if not show_spot:
		return
	var yard := roundi(d.los)
	var length := roundi(d.goal)
	var territory: int = d.offense_team if yard * 2 < length else 1 - d.offense_team
	spot_l.text = "MIDFIELD" if yard * 2 == length else "%s %d" % [TEAM_ABBR[territory], mini(yard, length - yard)]
	if field_strip.visible:
		var marks := Vector2(d.los, d.first_down_y) / float(d.goal)
		if marks != field_marks:
			field_marks = marks
			field_strip.queue_redraw()

func _draw_field_strip() -> void:
	var width := field_strip.size.x
	var mid := field_strip.size.y * 0.5
	field_strip.draw_rect(Rect2(0, mid - 6, width, 12), Color(0.14, 0.25, 0.22))
	for i in range(1, 10):
		var x := width * i / 10.0
		field_strip.draw_line(Vector2(x, mid - 4), Vector2(x, mid + 4), Color(1, 1, 1, 0.28))
	var start := clampf(width * field_marks.x, 1, width - 1)
	var gain := clampf(width * field_marks.y, 1, width - 1)
	field_strip.draw_line(Vector2(start, mid - 7), Vector2(start, mid + 7), ACCENT, 2)
	field_strip.draw_line(Vector2(gain, mid - 7), Vector2(gain, mid + 7), Color(1.0, 0.86, 0.35), 2)

## Match mode and size ("7v7 CLASSIC  ·  RANKED"): the Tab scoreboard's header line (#131).
func _mode_text(main) -> String:
	var m := "CHAOSBALL" if main.match_mode == "chaosball" else "CLASSIC"
	var t := "%dv%d %s" % [main.match_size, main.match_size, m]
	if main.ranked_match:
		t += "  ·  RANKED"
	return t

## The live HUD's title line (#131): training/practice titles and the queue search only.
## A match shows none; its mode/size is on the Tab scoreboard (_mode_text).
func _hud_title(main) -> String:
	var t := ""
	if main.drill != null:
		t = main.drill.title() if _training(main) else "PRACTICE"
	if main.searching():
		t = main.queue_text() + ("  ·  " + t if t != "" else "")
	return t

## #168: the play clock turns ALERT red only when the snap is yours to make (your team has
## the ball). Against bots it counts their 5 s huddle, so it would be red the whole presnap.
func _my_snap(main) -> bool:
	var me = main.world.get_athlete(main.my_id)
	return me != null and main.world.offense_team == me.team

func _training(main) -> bool:
	return main.drill != null and main.Drills.is_training(main.drill.kind)

## Drill banners: [title, sub, kind] (good / miss / up / info).
func show_drill_banner(b: Array) -> void:
	var c: Color = {"good": Color(0.45, 1.0, 0.6), "miss": ALERT, "up": Color(1.0, 0.86, 0.35)}.get(b[2], ACCENT)
	show_banner(str(b[0]), str(b[1]), c, 1.6)

func _status_text(main) -> String:
	var w = main.world
	var s = main.series
	if s.is_final():
		return ""
	if _training(main):
		return main.drill.status(w)
	match int(w.phase):
		0:
			var mine: bool = w.offense_team == w.get_athlete(main.my_id).team
			if int(s.state) == 3:
				# #131: no key hints on the toss (1 receive / 2 kick live in the controls list;
				# no answer = receive). The coin-toss cutscene (#129) will own this moment.
				var won: bool = s.toss_winner == w.get_athlete(main.my_id).team
				return "YOU WON THE TOSS" if won else "%s IS CHOOSING" % TEAM_NAMES[clampi(s.toss_winner, 0, 1)]
			# #131: the kicker keeps the J / click hint (the only place a new player learns to
			# kick; #68's meter shows power, not the key); the return team gets no narration.
			if w.kick_play == "kickoff":
				return "PRESS J OR CLICK TO KICK" if mine else ""
			if w.kick_play != "" and mine:
				return ("PUNT" if w.kick_play == "punt" else "FIELD GOAL") + "  ·  PRESS K TO CHANGE"
			# #183: a set defender is told how to roam until they've done it once this session.
			var roam_key: String = main.roam_hint_key()
			return "" if roam_key == "" else main.presnap_defense_prompt(w.get_athlete(main.my_id), roam_key)
		1:
			if main.world.is_chaos():
				return "PASS CLOCK %.1f" % maxf(0.0, main.T.PASS_CLOCK - w.hold_t)
			if w.kick_in_air():
				return fair_catch_prompt(w, main.controlled_id)
			return "MEET THE BACK" if w.handoff_receiver(main.my_id) == null and w.is_run_play() and w.ball.is_held_by(main.my_id) else ""
		_:
			return whistle_summary(main.last_whistle, main.world)

## Kick in the air (#189): tell the return team about the fair catch.
static func fair_catch_prompt(w, my_id: int) -> String:
	if w.fair_catch_id == my_id:
		return "FAIR CATCH SIGNALED  ·  CATCH IT TO END THE PLAY"
	if w.fair_catch_id >= 0:
		return "FAIR CATCH SIGNALED"
	return "PRESS SPACE FOR A FAIR CATCH" if w.can_signal_fair_catch(my_id) else ""

func _refresh_picker(main, final: bool) -> void:
	var w = main.world
	var training := _training(main)
	coaching_text.visible = training
	picker_grid.visible = not training
	if training:
		picker.visible = not main.scoreboard_held
		var card: Array = main.drill.card()
		picker_title.text = card[0]
		coaching_text.text = card[1]
		route_select.hide()
		formation_select.hide()
		return
	picker.visible = not final and w.phase == w.Phase.PRESNAP and w.kick_play != "kickoff" and main.play_picker_open and not main.scoreboard_held and not main.replay_active
	if not picker.visible:
		return
	var athlete = w.get_athlete(main.my_id)
	formation_select.visible = w.can_choose_formation(athlete)
	if formation_select.visible:
		var formation: int = w.offensive_formation()
		if formation_select.selected != formation:
			formation_select.select(formation)
	var side := 0 if athlete.team == w.offense_team else 1
	var offense := side == 0
	var calls: Array = w.available_plays() if offense else w.DefensivePlaybook.CALLS.keys()
	_picker_main = main
	if picker_side != side or picker_calls != calls:
		picker_side = side
		picker_calls = calls
		# Reuse one pool of buttons, relabelled per side: rebuilding on every possession change
		# churned nodes and tripped perf.sh's object-growth leak check (#169).
		var entries: Array = []   # [text, action, toggle]
		for call in calls:
			entries.append([call if offense else w.DefensivePlaybook.CALLS[call].name,
				{"a": "play" if offense else "defense", "p": call}, true])
		for action in ([["Repeat last", "recall_call"], ["Flip play", "flip_play"]] if offense else [["Repeat last", "recall_call"]]):
			entries.append([action[0], {"a": action[1]}, false])
		while picker_grid.get_child_count() < entries.size():   # safety net; PICKER_POOL covers every list
			_add_picker_button()
		for i in picker_grid.get_child_count():
			var b: Button = picker_grid.get_child(i)
			b.visible = i < entries.size()
			if b.visible:
				b.text = entries[i][0]
				b.set_meta("action", entries[i][1])
				b.toggle_mode = entries[i][2]
				b.set_pressed_no_signal(false)
		if route_select.item_count == 0:
			for route in main.Routes.ROUTE_NAMES:
				route_select.add_item(route)
			route_select.item_selected.connect(func(index: int): main.do_action({"a": "route", "r": route_select.get_item_text(index)}))
	var called: String = w.play_name if offense else w.defensive_call
	picker_title.text = "Call an offensive play" if offense else "Call a defense"
	for i in calls.size():
		picker_grid.get_child(i).set_pressed_no_signal(calls[i] == called)
	route_select.visible = offense and w.route_of.has(main.my_id)
	if route_select.visible:
		route_select.select(main.Routes.ROUTE_NAMES.find(w.route_of[main.my_id]))

func _refresh_me(main) -> void:
	var a = main.player.athlete
	stamina_bar.value = a.stamina
	var low: bool = a.sprint_locked or a.stamina < 0.25
	stamina_fill.bg_color = ALERT if low else ACCENT.lerp(Color(0.4, 1.0, 0.55), a.stamina)
	if not is_equal_approx(move_charge, a.move_charge):
		move_charge = a.move_charge
		for circle in move_circles:
			circle.queue_redraw()

## Short player-facing dead-ball line ("TACKLED · +3", "SACK · -5", "INCOMPLETE") instead
## of the raw whistle code (#116). Offense attacks +y, so yards = spot - line of scrimmage.
func whistle_summary(code: String, w) -> String:
	if code == "":
		return ""
	var tags: Array = _play.get("tags", [])
	if not tags.is_empty():
		return str(tags[0])
	match code:
		"INCOMPLETE", "BREAKUP":
			return "INCOMPLETE" if code == "INCOMPLETE" else "PASS BROKEN UP"
		"EXPLODE":
			return "BALL EXPLODED"
		"TOUCHBACK":
			return "TOUCHBACK"
		"DOWNED":
			return "KICK DOWNED"
		"FIELD GOAL GOOD":
			return "FIELD GOAL IS GOOD"
		"FIELD GOAL NO GOOD":
			return "FIELD GOAL MISSED"
	var label: String = {"TACKLE": "TACKLED", "OUT OF BOUNDS": "OUT OF BOUNDS"}.get(code, code)
	var spot = _play.get("spot", null)
	var scrimmage: bool = str(_play.get("kick", "")) == "" and _play.has("los")
	if code not in ["TACKLE", "OUT OF BOUNDS"] or not scrimmage or not spot is Vector2 or int(_play.get("team", -1)) != int(_play.get("off", -2)):
		return label
	var y: float = spot.y
	if w != null:
		y = clampf(y, w.field.goal_line_a(), w.field.goal_line_b())
	var yd := roundi(y - float(_play["los"]))
	if code == "TACKLE" and yd < 0 and not _play.get("pass", false) and int(_play.get("carrier", -1)) == int(_play.get("qb", -2)):
		label = "SACK"
	return "%s  ·  %s" % [label, "NO GAIN" if yd == 0 else ("%+d" % yd)]

## Bottom stack: scorebug centered on the bottom edge, movement meters to its left with
## their bottoms lined up, status pill on its top-left corner.
func _layout_stack() -> void:
	var vp := root.size
	var br := bug.get_rect()
	var bug_left := (vp.x - br.size.x) * 0.5
	var bug_top := vp.y - BUG_BOTTOM - br.size.y
	var ms := me_panel.get_combined_minimum_size()
	me_panel.size = ms
	me_panel.position = Vector2(bug_left - STACK_GAP - ms.x, vp.y - BUG_BOTTOM - ms.y - (br.size.y - ms.y) * 0.5)
	var pm := status_pill.get_combined_minimum_size()
	status_pill.size = pm
	status_pill.position = Vector2(bug_left, bug_top - 4.0 - pm.y)
	if flag_pill.visible:
		var fm := flag_pill.get_combined_minimum_size()
		flag_pill.size = fm
		flag_pill.position = Vector2(bug_left + br.size.x - fm.x, bug_top - 4.0 - pm.y - 6.0 - fm.y)
