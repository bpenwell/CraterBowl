extends "res://tests/visual/harness.gd"
## #100: a takeaway return is credited to the returner and shows in the post-game stat lines.
## The local player (on defense) picks off a pass and returns it 46 yards, and a bot returns a
## fumble 9 yards; the real match_overview() then opens the lobby's game overview.

const Athlete := preload("res://src/sim/athlete.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var launch = root.get_node("Launch")
	launch.settings.player_name = "Ace"
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.opening_kickoff = false
	game.player_name = "Ace"
	var series = game.series
	series.start(1, 40.0)   # NEBULA has the ball; Ace's HELIOS defends
	game.set_controlled(game.my_id)
	await _refresh()
	var w = game.world
	var me = w.get_athlete(game.my_id)
	var qb = w.find_role(1, Athlete.Role.QB)
	var wr = w.find_role(1, Athlete.Role.WR)
	check(me.team == 0 and w.offense_team == 1, "Ace is on defense")
	# Pick at the NEBULA 52, run back to the 6 (HELIOS returns toward y = 0).
	w.event.emit("snap", {"qb": qb.id})
	w.event.emit("throw", {"by": qb.id})
	w.event.emit("interception", {"by": me.id, "at": Vector2(30, 52), "team": 0})
	w.event.emit("tackle", {"by": wr.id, "carrier": me.id, "spot": Vector2(26, 6), "team": 0})
	# A bot strips the next carrier and returns the fumble from the 33 to the 24.
	var rb = w.find_role(1, Athlete.Role.RB)
	var mate = w.find_role(0, Athlete.Role.LB) if w.find_role(0, Athlete.Role.LB).id != me.id else w.find_role(0, Athlete.Role.S)
	w.event.emit("snap", {"qb": qb.id})
	w.event.emit("handoff", {"to": rb.id})
	w.event.emit("fumble", {"carrier": rb.id, "by": mate.id, "at": Vector2(20, 32)})
	mate.position = Vector2(20, 33)
	w.event.emit("recovery", {"by": mate.id, "team": 0, "turnover": true})
	w.event.emit("tackle", {"by": rb.id, "carrier": mate.id, "spot": Vector2(18, 24), "team": 0})

	var me_line: Dictionary = game.stats.get_line("Ace", game.stats.ROLE[me.role])
	check(is_equal_approx(me_line.get("int_ret_yds", 0.0), 46.0), "Ace credited 46 INT return yards (%s)" % me_line.get("int_ret_yds"))
	check(is_equal_approx(game.stats.total("fr_ret_yds"), 9.0), "bot credited 9 fumble return yards")
	# What the final whistle does in main.gd, then the hand-off to the lobby overview.
	game.summary_lines = game.stats.summary_lines()
	game.potg = game._decorate_potg(game.Potg.pick(game.stats.athletes, series.winner()))
	game.team_totals = game.Potg.team_totals(game.stats.athletes)
	var ov: Dictionary = game.match_overview()
	check(ov["my_lines"].any(func(l): return str(l).contains("46 INT RET YDS")), "Ace's post-game line shows the return: %s" % str(ov["my_lines"]))
	check(ov["potg"].any(func(e): return "   ".join(e["lines"]).contains("46 INT RET YDS")), "players-of-the-game card shows it")
	launch.go_to_menu("", ov)
	for frame in 30:
		await process_frame
	var menu = current_scene
	check(menu != null and menu.scene_file_path == launch.MENU_SCENE and menu.current == "overview", "lobby opens the game overview")
	var view = menu.content.find_child("GameOverview", true, false)
	var shown := []
	if view:
		for l in view.find_children("*", "Label", true, false):
			shown.append(l.text)
	var txt := "\n".join(shown)
	check(txt.contains("46 INT RET YDS"), "overview 'Your game' shows INT return yards")
	check(txt.contains("46 INT RET YDS"), "overview player card shows INT return yards")
	await _refresh()
	await capture("return-yards-overview")
	# Scroll down to "Your game", the local player's own stat line.
	var mine: Control = null
	for l in view.find_children("*", "Label", true, false) if view else []:
		if l.text.contains("46 INT RET YDS"):
			mine = l
	menu.content_scroll.ensure_control_visible(mine)
	await _refresh()
	check(mine != null and menu.content_scroll.get_global_rect().encloses(mine.get_global_rect()), "'Your game' line is on screen")
	await capture("return-yards-your-game")
	finish()

func _refresh() -> void:
	for frame in 5:
		await process_frame
