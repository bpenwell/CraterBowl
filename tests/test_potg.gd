extends "res://tests/test_case.gd"

const Potg := preload("res://src/sim/potg.gd")
const World := preload("res://src/sim/world.gd")
const Roster := preload("res://src/sim/roster.gd")
const Stats := preload("res://src/sim/stats.gd")
const Athlete := preload("res://src/sim/athlete.gd")

func _line(team: int, pos: String, owner: String, f: Dictionary) -> Dictionary:
	var l := {"team": team, "pos": pos, "owner": owner}
	for k in Stats.FIELDS:
		l[k] = float(f.get(k, 0))
	return l

func test_return_touchdown_display_and_team_total() -> void:
	var line := {"team": 1, "ret_td": 1.0}
	assert_eq(Potg.stat_lines(line), ["1 RET TD"])
	assert_eq(Potg.category(line), "SPECIAL TEAMS STANDOUT")
	assert_near(Potg.impact(line), Potg.impact({"def_td": 1.0}))
	assert_eq(Potg.team_totals({3: line})[1]["td"], 1)

func test_picks_between_two_and_four() -> void:
	var a := {}
	for i in 8:
		a[i] = _line(i % 2, "WR", "P%d" % i, {"rec": 1 + i, "rec_yds": 10 * (i + 1), "rec_td": 1})
	var p := Potg.pick(a, 0)
	assert_true(p.size() >= 2 and p.size() <= 4, "2-4 picks, got %d" % p.size())
	assert_eq(p[0]["title"], "PLAYER OF THE GAME")
	for i in p.size() - 1:
		assert_true(p[i]["score"] >= p[i + 1]["score"], "sorted by score")

func test_min_two_even_with_one_dominant_line() -> void:
	var a := {1: _line(0, "QB", "Ann", {"att": 20, "comp": 15, "pass_yds": 300, "pass_td": 4}),
		2: _line(1, "LB", "Bot", {"tkl": 1}), 3: _line(1, "CB", "Bot", {})}
	var p := Potg.pick(a, 0)
	assert_eq(p.size(), 2, "dominant line + one more; pads stop at the minimum")
	assert_eq(int(p[0]["id"]), 1)
	assert_eq(p[0]["owner"], "Ann")
	assert_eq(p[0]["lines"][0], "15/20  300 YDS  4 TD")

func test_cutoff_drops_minor_lines() -> void:
	var a := {1: _line(0, "RB", "A", {"car": 10, "rush_yds": 120, "rush_td": 3}),
		2: _line(0, "WR", "B", {"rec": 5, "rec_yds": 80, "rec_td": 1}),
		3: _line(1, "LB", "C", {"tkl": 1}), 4: _line(1, "S", "D", {"tkl": 1})}
	var p := Potg.pick(a, 0)
	assert_eq(p.size(), 2, "tiny tackle lines fall under the cutoff once two picks exist")
	assert_eq(p[1]["title"], "TOP RECEIVER")

func test_win_bonus_and_empty() -> void:
	var a := {1: _line(0, "WR", "A", {"rec": 3, "rec_yds": 50, "rec_td": 1}),
		2: _line(1, "WR", "B", {"rec": 3, "rec_yds": 50, "rec_td": 1})}
	assert_eq(int(Potg.pick(a, 1)[0]["id"]), 2, "winner breaks an even tie")
	assert_eq(Potg.pick({}, 0).size(), 0)
	var lone := {1: _line(0, "QB", "A", {"att": 1, "comp": 1, "pass_td": 1}), 2: _line(1, "S", "B", {"int_thrown": 0, "pbu": 0, "fr": 0, "blk": 0}),
		3: _line(1, "QB", "C", {"att": 2, "int_thrown": 1})}
	var p := Potg.pick(lone, 0)
	assert_eq(p.size(), 2, "one standout still gets a second pick")
	assert_eq(int(p[1]["id"]), 2, "a zero line outranks a negative one")

func test_defense_category_and_totals() -> void:
	var l := _line(1, "LB", "Bot", {"tkl": 6, "sack": 2, "int": 1})
	assert_eq(Potg.category(l), "DEFENSIVE STANDOUT")
	assert_eq(Potg.stat_lines(l)[0], "6 TKL  2 SACK  1 INT")
	var t := Potg.team_totals({1: _line(0, "QB", "A", {"pass_yds": 100, "pass_td": 1, "int_thrown": 2}), 2: l})
	assert_eq(t[0]["pass_yds"], 100)
	assert_eq(t[0]["turnovers"], 2)
	assert_eq(t[1]["sack"], 2)

## #100: return yards ride on the defensive card and count like scrimmage yards.
func test_return_yards_on_cards() -> void:
	var l := _line(1, "CB", "Ann", {"int": 1, "int_ret_yds": 34, "def_td": 1, "fr": 1, "fr_ret_yds": 12})
	assert_eq(Potg.stat_lines(l)[0], "1 INT  1 FR  1 DEF TD  34 INT RET YDS  12 FUM RET YDS")
	assert_near(Potg.impact(l), 5.0 + 2.0 + 6.0 + 4.6, 0.001)
	assert_eq(Potg.category(l), "DEFENSIVE STANDOUT")
	var zero := _line(1, "CB", "Bo", {"int": 1})
	assert_eq(Potg.stat_lines(zero)[0], "1 INT", "a zero-yard return shows nothing")

func test_stats_tracks_athletes() -> void:
	var w := World.new()
	Roster.new().build(w, 7)
	var owners := {}
	var s := Stats.new()
	s.attach(w, func(aid): return owners.get(aid, "Bot"))
	var qb := w.find_role(0, Athlete.Role.QB).id
	var lb := w.find_role(1, Athlete.Role.LB).id
	owners[qb] = "Ann"
	w.event.emit("snap", {})
	w.event.emit("tackle", {"by": lb, "carrier": qb, "spot": Vector2(20, w.los_y + 6), "team": 0})
	assert_eq(s.athletes[qb]["owner"], "Ann")
	assert_eq(int(s.athletes[qb]["car"]), 1)
	assert_eq(s.athletes[lb]["pos"], "LB")
	assert_eq(int(s.athletes[lb]["tkl"]), 1)
	assert_eq(int(s.athletes[lb]["team"]), 1)
