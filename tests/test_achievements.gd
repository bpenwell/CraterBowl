extends "res://tests/test_case.gd"

const Ach := preload("res://src/sim/achievements.gd")
const Stats := preload("res://src/sim/stats.gd")
const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Roster := preload("res://src/sim/roster.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Cos := preload("res://src/sim/cosmetics.gd")

func _ids(list: Array) -> Array:
	return list.map(func(a): return a["id"])

func test_thresholds() -> void:
	assert_true(Ach.earned("gunslinger", {"line": {"pass_yds": 300.0}}))
	assert_true(not Ach.earned("gunslinger", {"line": {"pass_yds": 299.0}}))
	assert_true(Ach.earned("sure_hands", {"line": {"rec": 8.0}}))
	assert_true(Ach.earned("sack_artist", {"line": {"sack": 3.0}}))
	assert_true(not Ach.earned("lockdown", {"line": {"int": 1.0}}))
	assert_true(Ach.earned("comeback", {"won": true, "deficit": 14}))
	assert_true(not Ach.earned("comeback", {"won": false, "deficit": 21}), "must win")
	assert_true(Ach.earned("perfect_chaos", {"mode": "chaosball", "line": {"max_td_pts": 7.0}}))
	assert_true(not Ach.earned("perfect_chaos", {"mode": "classic", "line": {"max_td_pts": 7.0}}))
	assert_true(Ach.earned("gold_tier", {"rating": 1300.0}))
	assert_true(Ach.earned("iron_man", {"games": 10}))

func test_evaluate_only_new() -> void:
	var ctx := {"line": {"rush_td": 1.0}, "won": true}
	var first := _ids(Ach.evaluate(ctx, []))
	assert_true(first.has("first_td") and first.has("first_win"))
	assert_eq(Ach.evaluate(ctx, first).size(), 0, "nothing new the second time")

func test_return_touchdown_unlocks_first_td() -> void:
	var ctx := {"line": {"ret_td": 1.0}}
	assert_true(Ach.earned("first_td", ctx))
	assert_true(not Ach.earned("pick_six", ctx))

func test_stats_def_td_and_max_td_pts() -> void:
	var w := World.new()
	Roster.new().build(w, 3)
	var s := Stats.new()
	s.attach(w, func(_aid): return "You")
	var cb := w.find_role(1, Athlete.Role.CB)
	w.event.emit("snap", {})
	w.event.emit("touchdown", {"carrier": cb.id, "spot": Vector2(10, -1), "team": 1, "points": 6})
	var l := s.get_line("You", "CB")
	assert_eq(int(l["def_td"]), 1, "pick six recorded")
	assert_eq(int(l["pts"]), 6)
	var qb := w.find_role(0, Athlete.Role.QB)
	w.event.emit("snap", {})
	w.event.emit("touchdown", {"carrier": qb.id, "spot": Vector2(10, 61), "team": 0, "points": 7})
	assert_near(s.get_line("You", "QB")["max_td_pts"], 7.0)

func test_match_max_deficit() -> void:
	var w := World.new()
	Roster.new().build(w, 7)
	var m := Match.new(w)
	m.start(0)
	m._award(1, 7, "td")
	m._award(1, 7, "td")
	m._award(0, 7, "td")
	assert_eq(m.max_deficit[0], 14)
	assert_eq(m.max_deficit[1], 0)

func test_profile_keeps_achievements() -> void:
	var path := "user://test_ach_profile.json"
	var c := Cos.new()
	c.achievements = ["first_td"]
	c.games = 3
	c.save(path)
	var c2 := Cos.new()
	c2.load_file(path)
	assert_eq(c2.achievements, ["first_td"])
	assert_eq(c2.games, 3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
