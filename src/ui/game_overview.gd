extends RefCounted
## Lobby "Game overview": the last match's result, players of the game, team box
## score and your own line/XP. Built into the menu's side panel from the plain
## dictionary main.gd hands to Launch (match_overview()). Pure view builder.

const C := preload("res://src/ui/ui_theme.gd")
const TEAM_COLORS := [Color(0.95, 0.75, 0.15), Color(0.3, 0.8, 0.95)]
const BOX_ROWS := [["pass_yds", "PASS YDS"], ["rush_yds", "RUSH YDS"], ["td", "TOUCHDOWNS"],
	["turnovers", "INT THROWN"], ["sack", "SACKS"], ["tkl", "TACKLES"]]

## Headline from your side: VICTORY / DEFEAT / TIE (FINAL when you had no team).
static func result_text(ov: Dictionary) -> String:
	var w := int(ov.get("winner", -1))
	if w < 0:
		return "TIE GAME"
	return "VICTORY" if w == int(ov.get("my_team", -1)) else "DEFEAT"

static func mode_text(ov: Dictionary) -> String:
	var m := "CHAOSBALL" if ov.get("mode", "") == "chaosball" else "CLASSIC"
	var t := "%dv%d %s" % [int(ov.get("size", 0)), int(ov.get("size", 0)), m]
	if ov.get("ranked", false):
		t += "  ·  RANKED"
	elif ov.get("online", false):
		t += "  ·  ONLINE"
	return t

static func _label(t: String, sz: int, col: Color, weight: int = 600) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", C.font(weight))
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Fill `box` with the overview. Returns the root container (named "GameOverview").
static func build(box: Container, ov: Dictionary) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.name = "GameOverview"
	root.add_theme_constant_override("separation", 12)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(root)
	var names: Array = ov.get("team_names", ["HOME", "AWAY"])
	var sc: Array = ov.get("score", [0, 0])
	var res := result_text(ov)
	root.add_child(_label("GAME OVERVIEW  ·  " + mode_text(ov), 16, Color(C.CREAM, 0.65)))
	var head := _label(res, 44, C.GOLD if res == "VICTORY" else (C.ORANGE if res == "DEFEAT" else C.CREAM), 700)
	head.name = "Result"
	root.add_child(head)
	root.add_child(_scoreline(names, sc, int(ov.get("my_team", -1))))

	var potg: Array = ov.get("potg", [])
	if not potg.is_empty():
		root.add_child(_section("Players of the game"))
		for i in potg.size():
			root.add_child(_potg_row(potg[i], i, names))

	var teams: Array = ov.get("teams", [])
	if teams.size() == 2:
		root.add_child(_section("Team stats"))
		root.add_child(_box_score(names, teams))

	root.add_child(_section("Your game"))
	var mine: Array = ov.get("my_lines", [])
	if mine.is_empty():
		root.add_child(_label("No stats recorded for you this game.", 17, Color(C.CREAM, 0.7), 400))
	for l in mine:
		root.add_child(_label(str(l), 17, C.CREAM, 400))
	for k in ["xp", "achievements", "rating", "ranks"]:
		var t := str(ov.get(k, ""))
		if t != "":
			root.add_child(_label(("YOUR RANKS: " + t) if k == "ranks" else t, 17, C.CYAN if k != "achievements" else C.GOLD, 600))
	return root

static func _section(t: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	v.add_child(gap)
	v.add_child(C.heading(t, 20, C.CYAN))
	var rule := ColorRect.new()
	rule.color = Color(C.CYAN, 0.25)
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)
	return v

static func _scoreline(names: Array, sc: Array, my_team: int) -> Control:
	var h := HBoxContainer.new()
	h.name = "Score"
	h.add_theme_constant_override("separation", 14)
	for t in 2:
		if t == 1:
			h.add_child(_label("–", 30, Color(C.CREAM, 0.5)))
		var chip := ColorRect.new()
		chip.color = TEAM_COLORS[t]
		chip.custom_minimum_size = Vector2(6, 34)
		var nm := _label("%s%s" % [names[t], " (YOU)" if t == my_team else ""], 22, Color(C.CREAM, 0.9))
		var n := _label(str(sc[t]), 36, C.CREAM, 700)
		if t == 0:
			for c in [chip, nm, n]:
				h.add_child(c)
		else:
			for c in [n, nm, chip]:
				h.add_child(c)
	return h

static func _potg_row(e: Dictionary, rank: int, names: Array) -> Control:
	var col: Color = TEAM_COLORS[clampi(int(e.get("team", 0)), 0, 1)]
	var p := PanelContainer.new()
	p.name = "Potg%d" % rank
	var st := C.box(Color(C.NAVY, 0.7), Color(col, 0.8), 0, 4)
	st.border_width_left = 4
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	var num := _label("#%d" % int(e.get("number", 0)), 28, col, 700)
	num.custom_minimum_size = Vector2(58, 0)
	h.add_child(num)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(_label(str(e.get("title", "")), 13, C.GOLD if rank == 0 else Color(C.CREAM, 0.6)))
	v.add_child(_label("%s  ·  %s  ·  %s" % [str(e.get("name", "")).to_upper(), e.get("pos", ""),
		names[clampi(int(e.get("team", 0)), 0, 1)]], 20, C.CREAM, 700))
	var lines: Array = e.get("lines", [])
	if not lines.is_empty():
		var s := _label("   ".join(lines.slice(0, 2)), 15, col.lightened(0.35), 500)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(s)
	return p

static func _box_score(names: Array, teams: Array) -> Control:
	var g := GridContainer.new()
	g.name = "BoxScore"
	g.columns = 3
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 2)
	g.add_child(_label("", 15, C.CREAM))
	for t in 2:
		var l := _label(str(names[t]), 15, TEAM_COLORS[t], 700)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.custom_minimum_size = Vector2(90, 0)
		g.add_child(l)
	for r in BOX_ROWS:
		var nm := _label(r[1], 16, Color(C.CREAM, 0.7), 500)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(nm)
		for t in 2:
			var a := int(teams[t].get(r[0], 0))
			var b := int(teams[1 - t].get(r[0], 0))
			var better := a > b if r[0] != "turnovers" else a < b
			var l := _label(str(a), 18, C.CREAM if better else Color(C.CREAM, 0.6), 700 if better else 500)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			g.add_child(l)
	return g
