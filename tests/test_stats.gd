extends "res://tests/test_case.gd"

const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Roster := preload("res://src/sim/roster.gd")
const Stats := preload("res://src/sim/stats.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const AI := preload("res://src/sim/ai.gd")
const DT := 1.0 / 60.0
const R := Athlete.Role

var owners := {}

func _setup() -> Array:
	owners = {}
	var w := World.new()
	Roster.new().build(w, 7)
	var m := Match.new(w)
	m.start(0, 25.0)
	var s := Stats.new()
	s.attach(w, func(aid): return owners.get(aid, "Bot"))
	return [w, m, s]

func _ids(w) -> Dictionary:
	return {"qb": w.find_role(0, R.QB).id, "wr": w.find_role(0, R.WR).id, "rb": w.find_role(0, R.RB).id,
		"lb": w.find_role(1, R.LB).id, "cb": w.find_role(1, R.CB).id}

func test_completion_line() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	owners[i["qb"]] = "Ann"
	owners[i["wr"]] = "Ben"
	w.event.emit("snap", {"qb": i["qb"]})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("catch", {"by": i["wr"]})
	w.event.emit("tackle", {"by": i["lb"], "carrier": i["wr"], "spot": Vector2(20, 37), "team": 0})
	var qb := s.get_line("Ann", "QB")
	assert_eq(int(qb["comp"]), 1)
	assert_eq(int(qb["att"]), 1)
	assert_near(qb["pass_yds"], 12.0)
	var wr := s.get_line("Ben", "WR")
	assert_eq(int(wr["rec"]), 1)
	assert_near(wr["rec_yds"], 12.0)
	assert_eq(int(s.get_line("Bot", "LB")["tkl"]), 1)

func test_incomplete_int_breakup() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("breakup", {"by": i["cb"]})
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("interception", {"by": i["cb"]})
	var qb := s.get_line("Bot", "QB")
	assert_eq(int(qb["att"]), 2)
	assert_eq(int(qb["comp"]), 0)
	assert_eq(int(qb["int_thrown"]), 1)
	var cb := s.get_line("Bot", "CB")
	assert_eq(int(cb["pbu"]), 1)
	assert_eq(int(cb["int"]), 1)

func test_sack_and_run_and_td() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	w.event.emit("snap", {})
	w.event.emit("tackle", {"by": i["lb"], "carrier": i["qb"], "spot": Vector2(26, 19), "team": 0})
	assert_eq(int(s.get_line("Bot", "LB")["sack"]), 1, "sack")
	assert_eq(int(s.get_line("Bot", "QB").get("car", 0)), 0, "sack isn't a carry")
	w.event.emit("snap", {})
	w.event.emit("tackle", {"by": i["lb"], "carrier": i["rb"], "spot": Vector2(26, 31), "team": 0})
	var rb := s.get_line("Bot", "RB")
	assert_eq(int(rb["car"]), 1)
	assert_near(rb["rush_yds"], 6.0)
	w.event.emit("snap", {})
	w.event.emit("touchdown", {"carrier": i["rb"], "spot": Vector2(26, 101), "team": 0, "points": 6})
	rb = s.get_line("Bot", "RB")
	assert_eq(int(rb["rush_td"]), 1)
	assert_eq(int(rb["pts"]), 6)

func test_passing_td_and_fumble() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("catch", {"by": i["wr"]})
	w.event.emit("touchdown", {"carrier": i["wr"], "spot": Vector2(20, 101), "team": 0, "points": 6})
	assert_eq(int(s.get_line("Bot", "QB")["pass_td"]), 1)
	assert_eq(int(s.get_line("Bot", "WR")["rec_td"]), 1)
	assert_near(s.get_line("Bot", "WR")["rec_yds"], 75.0, 0.001, "100 - LOS 25")
	w.event.emit("fumble", {"carrier": i["wr"], "by": i["lb"]})
	w.event.emit("recovery", {"by": i["cb"], "team": 1})
	assert_eq(int(s.get_line("Bot", "LB")["ff"]), 1)
	assert_eq(int(s.get_line("Bot", "CB")["fr"]), 1)

## #100: takeaway returns. Team 0 attacks +y from the 25; the defense (team 1) returns toward y = 0.
func test_int_return_yards() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	owners[i["cb"]] = "Ann"
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("interception", {"by": i["cb"], "at": Vector2(20, 40), "team": 1})
	w.event.emit("tackle", {"by": i["wr"], "carrier": i["cb"], "spot": Vector2(18, 12), "team": 1})
	var cb := s.get_line("Ann", "CB")
	assert_eq(int(cb["int"]), 1)
	assert_near(cb["int_ret_yds"], 28.0, 0.001, "catch at 40, down at 12, toward his goal")
	assert_near(cb["fr_ret_yds"], 0.0)
	assert_near(s.total("rush_yds") + s.total("rec_yds") + s.total("pass_yds"), 0.0, 0.001, "no scrimmage yards")
	assert_eq(int(s.get_line("Bot", "WR")["tkl"]), 1)
	assert_true(s.summary_lines().any(func(l): return l.begins_with("Ann CB:") and l.contains("28 INT RET YDS")),
		"post-game line shows it: %s" % str(s.summary_lines()))
	assert_near(s.athletes[i["cb"]]["int_ret_yds"], 28.0, 0.001, "players-of-the-game line too")
	# Next play starts clean: a later tackle of the same CB isn't another return.
	w.event.emit("snap", {})
	w.event.emit("tackle", {"by": i["wr"], "carrier": i["cb"], "spot": Vector2(18, 2), "team": 1})
	assert_near(s.get_line("Ann", "CB")["int_ret_yds"], 28.0, 0.001, "snap closes the return")

func test_fumble_return_yards() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	w.event.emit("snap", {})
	w.event.emit("handoff", {"to": i["rb"]})
	w.event.emit("fumble", {"carrier": i["rb"], "by": i["lb"], "at": Vector2(26, 30)})
	w.get_athlete(i["cb"]).position = Vector2(27, 33)
	w.event.emit("recovery", {"by": i["cb"], "team": 1, "turnover": true})
	w.event.emit("out_of_bounds", {"carrier": i["cb"], "spot": Vector2(0, 21), "team": 1})
	var cb := s.get_line("Bot", "CB")
	assert_eq(int(cb["fr"]), 1)
	assert_near(cb["fr_ret_yds"], 12.0, 0.001, "recovered at 33, out at 21")
	assert_near(cb["int_ret_yds"], 0.0)
	assert_near(s.get_line("Bot", "RB")["rush_yds"], 5.0, 0.001, "run still ends at the fumble")
	assert_true(s.summary_lines().any(func(l): return l.contains("12 FUM RET YDS")), str(s.summary_lines()))
	# Own-team recovery isn't a takeaway: no return yards.
	w.event.emit("snap", {})
	w.event.emit("handoff", {"to": i["rb"]})
	w.event.emit("fumble", {"carrier": i["rb"], "by": i["lb"], "at": Vector2(26, 30)})
	w.event.emit("recovery", {"by": i["wr"], "team": 0, "turnover": false})
	w.event.emit("tackle", {"by": i["lb"], "carrier": i["wr"], "spot": Vector2(26, 40), "team": 0})
	assert_near(s.total("fr_ret_yds"), 12.0, 0.001, "own recovery adds nothing")

func test_return_td_and_fumbled_return() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("interception", {"by": i["lb"], "at": Vector2(20, 31), "team": 1})
	w.event.emit("touchdown", {"carrier": i["lb"], "spot": Vector2(20, -3), "team": 1, "points": 6})
	var lb := s.get_line("Bot", "LB")
	assert_near(lb["int_ret_yds"], 31.0, 0.001, "pick-six credited to the goal line, not the spot in the end zone")
	assert_eq(int(lb["def_td"]), 1)
	assert_eq(int(lb["pts"]), 6)
	# Return fumbled away: the return ends at the fumble, and the offense's recovery is its own return.
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("interception", {"by": i["cb"], "at": Vector2(20, 50), "team": 1})
	w.event.emit("fumble", {"carrier": i["cb"], "by": i["wr"], "at": Vector2(20, 42)})
	w.get_athlete(i["wr"]).position = Vector2(21, 41)
	w.event.emit("recovery", {"by": i["wr"], "team": 0, "turnover": true})
	w.event.emit("tackle", {"by": i["cb"], "carrier": i["wr"], "spot": Vector2(21, 47), "team": 0})
	assert_near(s.get_line("Bot", "CB")["int_ret_yds"], 8.0, 0.001, "50 -> fumbled at 42")
	assert_near(s.get_line("Bot", "WR")["fr_ret_yds"], 6.0, 0.001, "offense re-recovers at 41, runs to 47")
	assert_near(s.get_line("Bot", "WR")["rec_yds"], 0.0, 0.001, "not a reception")

func test_owner_change_splits_lines() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	owners[i["wr"]] = "Cy"
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("catch", {"by": i["wr"]})
	owners.erase(i["wr"])   # Cy switches away; a bot takes the WR
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("catch", {"by": i["wr"]})
	assert_eq(int(s.get_line("Cy", "WR")["rec"]), 1)
	assert_eq(int(s.get_line("Bot", "WR")["rec"]), 1)

func test_bot_game_consistency() -> void:
	var r := _setup()
	var w: World = r[0]
	var m: Match = r[1]
	var s: Stats = r[2]
	var ai := AI.new()
	var dead_t := 0.0
	for k in int(180.0 / DT):
		m.tick(DT)
		ai.presnap_tick(w, [], DT, m.downs.down, m.downs.distance())
		w.step(ai.think(w, []), DT)
		if w.phase == World.Phase.DEAD:
			dead_t += DT
			if dead_t > 0.5:
				m.next_play()
				dead_t = 0.0
	assert_true(s.total("att") >= 5, "passes tracked (%d)" % s.total("att"))
	assert_true(s.total("comp") <= s.total("att"))
	assert_near(s.total("pass_yds"), s.total("rec_yds"), 0.01, "pass yds == rec yds")
	assert_eq(int(s.total("comp")), int(s.total("rec")))
	assert_true(not s.summary_lines().is_empty(), "summary")
	for l in s.summary_lines():
		print("    " + l)
