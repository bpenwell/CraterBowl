extends "res://tests/test_case.gd"
## #67: kicking stats. FG made/att + long, PATs (XP), punt average, kick and punt return
## yards, through real kicks in the sim (same setups as test_kicking.gd).

const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Stats := preload("res://src/sim/stats.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const AI := preload("res://src/sim/ai.gd")
const Passing := preload("res://src/sim/passing.gd")
const T := preload("res://src/sim/tuning.gd")
const DT := 1.0 / 60.0
const R := Athlete.Role

var events: Array = []
var ev_data := {}
var owners := {}

func _world() -> World:
	var w := World.new()
	var cx := w.field.width / 2.0
	var pairs := [[R.C, 0.0, R.DL, -1.5], [R.QB, 0.0, R.LB, 0.0], [R.WR, -18.0, R.CB, -18.0], [R.WR, 18.0, R.CB, 18.0], [R.RB, 4.0, R.S, -8.0], [R.OL, -2.5, R.DL, 1.5], [R.OL, 2.5, R.S, 8.0]]
	for t in 2:
		for p in pairs:
			w.add_two_way(t, p[0], cx + p[1], p[2], cx + p[3])
	return w

## A match at `los` with stats attached (and told about the match, so PATs read as XP).
func _setup(los: float = 25.0) -> Array:
	events.clear()
	ev_data = {}
	owners = {}
	var w := _world()
	var m := Match.new(w)
	m.start(0, los)
	w.event.connect(func(n, d): events.append(n); ev_data[n] = d)
	var s := Stats.new()
	s.attach(w, func(aid): return owners.get(aid, "Bot"), m)
	return [m, s]

func _steps(w, n: int) -> void:
	for i in n:
		w.step({}, DT)
		if w.phase == World.Phase.DEAD:
			return

func _landing(w) -> Vector2:
	var b = w.ball
	var t := Passing.time_to_height(b.velocity, b.position.z, T.CATCH_HEIGHT, w.gravity())
	return Vector2(b.position.x + b.velocity.x * t, b.position.y + b.velocity.y * t)

func _park_all_but(w, keep: Array) -> void:
	for a in w.athletes:
		if not keep.has(a.id):
			a.position = Vector2(-1.5 if a.team == 0 else w.field.width + 1.5, a.position.y)

func _fourth_down(m, los: float, kind: String) -> void:
	events.clear()
	m.downs.reset(0, los)
	m.downs.down = 4
	m._setup_formation()
	m.call_kick(kind)

## Line up a field goal at `los`, snap, and kick at `x_off` from the middle of the posts.
## Returns the kick distance (kick spot to the posts).
func _kick_fg(m, los: float, x_off: float = 0.0) -> float:
	var w = m.world
	_fourth_down(m, los, "fg")
	_park_all_but(w, [w.find_role(0, R.C).id, w.kicker().id])
	w.snap()
	_steps(w, 30)
	var k = w.kicker()
	var dist: float = w.field.posts_y() - k.position.y
	var p := World.kick_power_for("fg", dist + 6.0, T.CROSSBAR_HEIGHT + 2.0, w.gravity())
	w.kick(k.id, Vector2(w.field.width / 2.0 + x_off, w.field.posts_y()), p)
	_steps(w, 900)
	return dist

func _tackle(w, carrier, at: Vector2) -> void:
	carrier.position = at
	var cov = w.find_role(0, R.WR)
	cov.position = at + Vector2(0, -0.9)
	cov.facing = Vector2(0, 1)
	w.tackle(cov.id)
	_steps(w, 30)

func test_field_goals_made_attempted_and_long() -> void:
	var r := _setup()
	var m: Match = r[0]
	var s: Stats = r[1]
	var w := m.world
	owners[w.kicker().id] = "Kay"
	var d1 := _kick_fg(m, 80.0)
	assert_true(ev_data["field_goal"]["good"], "short FG good")
	var d2 := _kick_fg(m, 68.0)
	assert_true(ev_data["field_goal"]["good"], "longer FG good")
	_kick_fg(m, 88.0, 8.0)
	assert_true(not ev_data["field_goal"]["good"], "wide")
	var l := s.get_line("Kay", "QB")
	assert_eq(int(l["fg_att"]), 3, "three attempts")
	assert_eq(int(l["fg_made"]), 2, "two made")
	assert_true(d2 > d1, "second kick is the longer one")
	assert_near(l["fg_long"], roundf(d2), 0.001, "long = the longest make (%.1f)" % d2)
	assert_eq(int(l["xp_att"]), 0, "scrimmage kicks aren't PATs")
	assert_near(s.athletes[w.kicker().id]["fg_long"], roundf(d2), 0.001, "per-athlete line too")
	assert_true(s.summary_lines().any(func(x): return x.begins_with("Kay QB:") and x.contains("2/3 FG long %d" % roundi(d2))),
		"post-game line: %s" % str(s.summary_lines()))

func test_blocked_field_goal_is_a_miss() -> void:
	var r := _setup()
	var m: Match = r[0]
	var s: Stats = r[1]
	var w := m.world
	_fourth_down(m, 70.0, "fg")
	w.snap()
	_steps(w, 30)
	var k := w.kicker()
	var dl := w.find_role(1, R.DL)
	_park_all_but(w, [k.id, dl.id])
	dl.position = k.position + Vector2(0, 1.5)
	w.kick(k.id, Vector2(w.field.width / 2.0, w.field.posts_y()), 0.8)
	_steps(w, 5)
	assert_true(events.has("kick_blocked"), "blocked (%s)" % str(events))
	assert_eq(int(s.total("fg_att")), 1, "blocked kick is an attempt")
	assert_eq(int(s.total("fg_made")), 0)
	assert_near(s.total("fg_long"), 0.0, 0.001, "no long without a make")
	assert_true(s.summary_lines().any(func(x): return x.contains("0/1 FG") and not x.contains("long")), str(s.summary_lines()))

func test_pat_counts_as_xp_not_field_goal() -> void:
	var r := _setup(95.0)
	var m: Match = r[0]
	var s: Stats = r[1]
	var w := m.world
	w.snap()
	_steps(w, 30)
	w.carrier().position = Vector2(26, 101)
	_steps(w, 2)
	m.next_play()
	assert_eq(m.state, Match.State.TRY)
	_park_all_but(w, [w.find_role(0, R.C).id, w.kicker().id])
	w.snap()
	_steps(w, 30)
	var k := w.kicker()
	var dist := w.field.posts_y() - k.position.y
	w.kick(k.id, Vector2(w.field.width / 2.0, w.field.posts_y()), World.kick_power_for("fg", dist + 6.0, T.CROSSBAR_HEIGHT + 2.0, w.gravity()))
	_steps(w, 900)
	assert_true(ev_data["field_goal"]["good"], "PAT good")
	assert_eq(int(s.total("xp_att")), 1)
	assert_eq(int(s.total("xp_made")), 1)
	assert_eq(int(s.total("fg_att")), 0, "a PAT isn't a field goal attempt")
	assert_near(s.total("fg_long"), 0.0, 0.001)
	assert_true(s.summary_lines().any(func(x): return x.contains("1/1 XP")), str(s.summary_lines()))

func test_punt_average_downed_touchback_blocked() -> void:
	var r := _setup()
	var m: Match = r[0]
	var s: Stats = r[1]
	var w := m.world
	owners[w.kicker().id] = "Kay"
	# 1: from the 30, rolls dead.
	_fourth_down(m, 30.0, "punt")
	_park_all_but(w, [w.find_role(0, R.C).id, w.kicker().id])
	w.snap()
	_steps(w, 30)
	w.kick(w.kicker().id, Vector2(w.field.width / 2.0, 80.0), 0.7)
	_steps(w, 900)
	assert_true(events.has("kick_downed"), "rolled dead (%s)" % str(events))
	var p1: float = w.dead_ball_spot.y - 30.0
	assert_near(s.get_line("Kay", "QB")["punt_yds"], p1, 0.001, "LOS to where it died")
	# 2: from the 55 into the end zone: yards run to the goal line (45).
	_fourth_down(m, 55.0, "punt")
	_park_all_but(w, [w.find_role(0, R.C).id, w.kicker().id])
	w.snap()
	_steps(w, 30)
	w.kick(w.kicker().id, Vector2(w.field.width / 2.0, 100.0), 1.0)
	_steps(w, 900)
	assert_true(events.has("touchback"), "touchback (%s)" % str(events))
	var l := s.get_line("Kay", "QB")
	assert_eq(int(l["punts"]), 2)
	assert_near(l["punt_yds"], p1 + 45.0, 0.001, "touchback punt = 45 yd")
	var avg := (p1 + 45.0) / 2.0
	assert_true(s.summary_lines().any(func(x): return x.contains("2 punt %.1f avg" % avg)), "avg %.1f: %s" % [avg, str(s.summary_lines())])
	# 3: blocked: a punt for 0 yards.
	_fourth_down(m, 30.0, "punt")
	w.snap()
	_steps(w, 30)
	var k := w.kicker()
	var dl := w.find_role(1, R.DL)
	_park_all_but(w, [k.id, dl.id])
	dl.position = k.position + Vector2(0, 1.5)
	w.kick(k.id, Vector2(w.field.width / 2.0, 70.0), 0.8)
	_steps(w, 3)
	assert_true(events.has("kick_blocked"))
	_steps(w, 120)
	l = s.get_line("Kay", "QB")
	assert_eq(int(l["punts"]), 3, "blocked punt counts")
	assert_near(l["punt_yds"], p1 + 45.0, 0.001, "for 0 yards")

func test_kickoff_return_yards() -> void:
	var r := _setup()
	var m: Match = r[0]
	var s: Stats = r[1]
	var w := m.world
	# PAT good -> team 0 kicks off (as test_kicking.gd's _kickoff_match).
	m.state = Match.State.TRY
	m.last_result = {"type": "field_goal", "good": true, "team": 0}
	m.next_play()
	events.clear()
	var ret := w.returner()
	owners[ret.id] = "Ret"
	assert_true(w.kick(w.kicker().id, Vector2(w.field.width / 2.0, 100.0), 0.75), "kickoff")
	_park_all_but(w, [ret.id])
	ret.position = _landing(w)
	_steps(w, 300)
	assert_true(events.has("kick_catch"), "fielded")
	var caught: float = ev_data["kick_catch"]["at"].y
	_tackle(w, ret, Vector2(20, 70))
	assert_true(events.has("tackle"))
	var l := s.get_line("Ret", "S")
	assert_eq(int(l["kr"]), 1)
	assert_near(l["kr_yds"], caught - 70.0, 0.001, "caught at %.1f, down at 70, toward his goal" % caught)
	assert_eq(int(l["pr"]), 0)
	assert_eq(int(l["car"]), 0, "a return isn't a rush")
	assert_near(s.total("punts"), 0.0, 0.001, "a kickoff isn't a punt")
	assert_true(s.summary_lines().any(func(x): return x.begins_with("Ret S:") and x.contains("1 kick ret %dyd" % roundi(caught - 70.0))),
		str(s.summary_lines()))

func test_punt_return_yards() -> void:
	var r := _setup()
	var m: Match = r[0]
	var s: Stats = r[1]
	var w := m.world
	_fourth_down(m, 30.0, "punt")
	w.snap()
	_steps(w, 30)
	var ret := w.returner()
	_park_all_but(w, [w.find_role(0, R.C).id, w.kicker().id, ret.id])
	w.kick(w.kicker().id, Vector2(w.field.width / 2.0, 70.0), 0.7)
	ret.position = _landing(w)
	_steps(w, 400)
	assert_true(events.has("kick_catch"), "punt fielded")
	var caught: float = ev_data["kick_catch"]["at"].y
	_tackle(w, ret, Vector2(20, 60))
	var l := s.get_line("Bot", "S")
	assert_eq(int(l["pr"]), 1)
	assert_near(l["pr_yds"], caught - 60.0, 0.001, "caught at %.1f, down at 60" % caught)
	assert_near(s.get_line("Bot", "QB")["punt_yds"], caught - 30.0, 0.001, "punt measured to the catch")
	assert_true(s.summary_lines().any(func(x): return x.contains("1 punt ret %dyd" % roundi(caught - 60.0))), str(s.summary_lines()))

## A full bot match: every field goal and PAT on the scoreboard shows up in the kick stats.
func test_bot_match_kicking_stats_match_the_scoreboard() -> void:
	var m := Match.new(_world())
	var w := m.world
	m.clock.quarter_length = 75.0   # quarters only since #130: the same 5-minute match
	m.start_match(3, false)
	var s := Stats.new()
	s.attach(w, func(_aid): return "Bot", m)
	var kicks := {}
	w.event.connect(func(n, d): if n == "kick": kicks[d["kind"]] = kicks.get(d["kind"], 0) + 1)
	var board := {"fg": 0, "xp": 0}   # lambdas capture locals by value: count into a dictionary
	m.match_event.connect(func(n, d):
		if n == "score" and d["why"] == "field_goal": board["fg"] += int(d["points"])
		if n == "score" and d["why"] == "try" and int(d["points"]) == 1: board["xp"] += 1)
	var ai := AI.new()
	var dead_t := 0.0
	for i in int(600.0 / DT):
		m.tick(DT)
		ai.presnap_tick(w, [], DT, m.downs.down, m.downs.distance())
		w.step(ai.think(w, []), DT)
		if w.phase == World.Phase.DEAD:
			dead_t += DT
			if dead_t > 0.5:
				m.next_play()
				dead_t = 0.0
				if m.is_final():
					break
	print("    kicking stats: FG %d/%d long %d, XP %d/%d, punts %d (%d yd), KR %d (%d yd), PR %d (%d yd)" % [
		s.total("fg_made"), s.total("fg_att"), s.total("fg_long"), s.total("xp_made"), s.total("xp_att"),
		s.total("punts"), s.total("punt_yds"), s.total("kr"), s.total("kr_yds"), s.total("pr"), s.total("pr_yds")])
	assert_true(m.is_final(), "game finished")
	assert_eq(int(s.total("fg_made")) * 3, board["fg"], "FG makes x3 = FG points on the board")
	assert_eq(int(s.total("xp_made")), board["xp"], "XP makes = 1-point tries on the board")
	assert_eq(int(s.total("fg_att") + s.total("xp_att")), kicks.get("fg", 0), "every FG-type kick is an FG or XP attempt")
	assert_eq(int(s.total("punts")), kicks.get("punt", 0), "every punt counted")
	assert_true(s.total("kr") <= kicks.get("kickoff", 0), "at most one kick return per kickoff")
	assert_true(kicks.get("kickoff", 0) >= 1, "kickoffs happened")

## Career lines keep best-of fields as a max across matches (#171), and sum the rest.
func test_leaderboard_keeps_longest_field_goal() -> void:
	var Leaderboard := preload("res://src/sim/leaderboard.gd")
	var lb = Leaderboard.new()
	lb.record_match({"Kay|QB": {"fg_made": 2.0, "fg_att": 3.0, "fg_long": 47.0, "max_td_pts": 7.0}})
	lb.record_match({"Kay|QB": {"fg_made": 1.0, "fg_att": 1.0, "fg_long": 31.0, "max_td_pts": 6.0}})
	var c: Dictionary = lb.careers["Kay|QB"]
	assert_near(c["fg_long"], 47.0, 0.001, "career long is the best, not 78")
	assert_near(c["max_td_pts"], 7.0, 0.001, "max_td_pts too, not 13")
	assert_near(c["fg_made"], 3.0, 0.001, "counts still sum")
	assert_near(c["fg_att"], 4.0, 0.001)

## The players-of-the-game card shows a kicker's and a returner's special-teams line.
func test_potg_card_shows_kicking() -> void:
	var Potg := preload("res://src/sim/potg.gd")
	var kicker := {"team": 0, "pos": "QB", "owner": "Kay", "fg_made": 3.0, "fg_att": 4.0, "fg_long": 51.0}
	var ret := {"team": 1, "pos": "S", "owner": "Bot", "kr": 3.0, "kr_yds": 96.0, "pr": 1.0, "pr_yds": 12.0}
	assert_true(Potg.stat_lines(kicker).has("3/4 FG  LONG 51"), str(Potg.stat_lines(kicker)))
	assert_eq(Potg.category(kicker), "SPECIAL TEAMS STANDOUT")
	assert_near(Potg.impact(kicker), 9.0, 0.001, "an FG is worth 3")
	var rl := Potg.stat_lines(ret)
	assert_true(rl.has("96 KR YDS") and rl.has("12 PR YDS"), str(rl))
	var picks := Potg.pick({1: kicker, 2: ret}, 0)
	assert_eq(int(picks[0]["id"]), 1, "three field goals outrank 108 return yards")
