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
var player_ids := {}

func _setup() -> Array:
	owners = {}
	player_ids = {}
	var w := World.new()
	Roster.new().build(w, 7)
	var m := Match.new(w)
	m.start(0, 25.0)
	var s := Stats.new()
	s.attach(w, func(aid): return owners.get(aid, "Bot"), null, func(aid): return player_ids.get(aid, -1))
	return [w, m, s]

func _ids(w) -> Dictionary:
	return {"qb": w.find_role(0, R.QB).id, "wr": w.find_role(0, R.WR).id, "rb": w.find_role(0, R.RB).id,
		"lb": w.find_role(1, R.LB).id, "cb": w.find_role(1, R.CB).id}

func test_award_stats_separate_same_named_players() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	owners[i["qb"]] = "Ann"
	owners[i["lb"]] = "Ann"
	player_ids[i["qb"]] = 1
	player_ids[i["lb"]] = 2
	w.event.emit("snap", {})
	w.event.emit("tackle", {"by": i["lb"], "carrier": i["qb"], "spot": Vector2(26, 30), "team": 0})
	w.event.emit("snap", {})
	w.event.emit("touchdown", {"carrier": i["qb"], "spot": Vector2(26, 100), "team": 0, "points": 7})
	w.event.emit("snap", {})
	w.event.emit("touchdown", {"carrier": i["qb"], "spot": Vector2(26, 100), "team": 0, "points": 6})
	assert_eq(s.award_stats[1]["rush_td"], 2.0)
	assert_eq(s.award_stats[1]["max_td_pts"], 7.0)
	assert_eq(s.award_stats[1].get("tkl", 0.0), 0.0)
	assert_eq(s.award_stats[2], {"tkl": 1.0})

func test_award_stats_follow_owner_when_a_seat_is_reused() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var qb: int = _ids(w)["qb"]
	w.event.emit("throw", {"by": qb})
	assert_true(s.award_stats.is_empty(), "bot play earns no award stats")
	owners[qb] = "Ann"
	player_ids[qb] = 1
	w.event.emit("throw", {"by": qb})
	player_ids[qb] = 2
	w.event.emit("throw", {"by": qb})
	assert_eq(s.award_stats[1], {"att": 1.0})
	assert_eq(s.award_stats[2], {"att": 1.0})
	assert_eq(s.get_line("Ann", "QB")["att"], 2.0, "career line keeps the display-name format")

## #200: the personal overview reads lines by player id, so two players named Ann each see
## only their own, while the name-keyed summary (career table format) still files both as "Ann".
func test_player_summary_separates_same_named_players() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	owners[i["qb"]] = "Ann"
	owners[i["lb"]] = "Ann"
	player_ids[i["qb"]] = 1
	player_ids[i["lb"]] = 2
	w.event.emit("snap", {"qb": i["qb"]})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("catch", {"by": i["wr"]})
	w.event.emit("tackle", {"by": i["lb"], "carrier": i["wr"], "spot": Vector2(20, 37), "team": 0})
	w.event.emit("snap", {"qb": i["qb"]})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("breakup", {"by": i["lb"]})
	assert_eq(s.player_summary(1), ["QB: 1/2 12yd 0TD 0INT"], "Ann #1 sees only her passing line")
	assert_eq(s.player_summary(2), ["LB: 1 tkl, 1 pbu"], "Ann #2 sees only her defensive line")
	assert_eq(s.player_summary(3), [], "a player with no stats has no lines")
	assert_true(s.summary_lines().has("Ann QB: 1/2 12yd 0TD 0INT") and s.summary_lines().has("Ann LB: 1 tkl, 1 pbu"),
		"name-keyed summary keeps both under Ann: %s" % str(s.summary_lines()))
	assert_eq(s.summaries_for([i["qb"], i["lb"], i["cb"]]),
		{i["qb"]: ["QB: 1/2 12yd 0TD 0INT"], i["lb"]: ["LB: 1 tkl, 1 pbu"], i["cb"]: []},
		"each athlete carries its own player's lines for the broadcast")

## #200: same name, same position, different players: the name-keyed line merges them, the
## personal lines don't.
func test_same_named_players_at_one_position_do_not_merge() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	var wrs: Array = w.athletes.filter(func(a): return a.team == 0 and a.role == R.WR).map(func(a): return a.id)
	assert_eq(wrs.size(), 2, "7v7 fields two HELIOS receivers")
	owners[wrs[0]] = "Ann"
	owners[wrs[1]] = "Ann"
	player_ids[wrs[0]] = 1
	player_ids[wrs[1]] = 2
	w.event.emit("snap", {"qb": i["qb"]})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("catch", {"by": wrs[0]})
	w.event.emit("tackle", {"by": i["lb"], "carrier": wrs[0], "spot": Vector2(20, 37), "team": 0})
	w.event.emit("snap", {"qb": i["qb"]})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("catch", {"by": wrs[1]})
	w.event.emit("tackle", {"by": i["lb"], "carrier": wrs[1], "spot": Vector2(20, 30), "team": 0})
	assert_eq(s.get_line("Ann", "WR")["rec"], 2.0, "career line merges by name, as before")
	assert_eq(s.summary_lines().filter(func(l): return l.begins_with("Ann ")), ["Ann WR: 2 rec 17yd 0TD"])
	assert_eq(s.player_summary(1), ["WR: 1 rec 12yd 0TD"])
	assert_eq(s.player_summary(2), ["WR: 1 rec 5yd 0TD"])

## #200: a reused seat splits the personal lines by player, like the awards (#156).
func test_player_summary_follows_owner_when_a_seat_is_reused() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var qb: int = _ids(w)["qb"]
	w.event.emit("throw", {"by": qb})
	assert_true(s.player_lines.is_empty(), "bot play gives no player lines")
	owners[qb] = "Ann"
	player_ids[qb] = 1
	w.event.emit("throw", {"by": qb})
	player_ids[qb] = 2
	w.event.emit("throw", {"by": qb})
	w.event.emit("throw", {"by": qb})
	assert_eq(s.player_summary(1), ["QB: 0/1 0yd 0TD 0INT"])
	assert_eq(s.player_summary(2), ["QB: 0/2 0yd 0TD 0INT"])
	assert_eq(s.summaries_for([qb]), {qb: ["QB: 0/2 0yd 0TD 0INT"]}, "the broadcast follows the seat's current player")

func test_completed_pass_credit_survives_a_replacement() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	var qb: int = i["qb"]
	owners[qb] = "Ann"
	player_ids[qb] = 1
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": qb})
	owners[qb] = "Ben"
	player_ids[qb] = 2
	w.event.emit("catch", {"by": i["wr"]})
	w.event.emit("touchdown", {"carrier": i["wr"], "spot": Vector2(20, 100), "team": 0})
	var passing_touchdown := {"att": 1.0, "comp": 1.0, "pass_yds": 75.0, "pass_td": 1.0}
	assert_eq(s.award_stats[1], passing_touchdown)
	assert_true(not s.award_stats.has(2), "the replacement earned no passing credit yet")
	assert_true(s.get_line("Ben", "QB").is_empty())
	assert_eq(s.player_summary(1), ["QB: 1/1 75yd 1TD 0INT"])
	assert_eq(s.player_summary(2), [])
	assert_eq(s.athletes[qb]["owner"], "Ann")
	for field in passing_touchdown:
		assert_eq(s.get_line("Ann", "QB")[field], passing_touchdown[field], field)
		assert_eq(s.athletes[qb][field], passing_touchdown[field], field)

	w.event.emit("snap", {})
	w.event.emit("throw", {"by": qb})
	w.event.emit("catch", {"by": i["wr"]})
	w.event.emit("out_of_bounds", {"carrier": i["wr"], "spot": Vector2(0, 37), "team": 0})
	assert_eq(s.award_stats[1], passing_touchdown, "the next pass belongs to the new owner")
	assert_eq(s.award_stats.get(2), {"att": 1.0, "comp": 1.0, "pass_yds": 12.0})
	assert_eq(s.player_summary(2), ["QB: 1/1 12yd 0TD 0INT"])

func test_interception_stays_with_original_passer_even_with_the_same_name() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	owners[i["qb"]] = "Ann"
	player_ids[i["qb"]] = 1
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	player_ids[i["qb"]] = 2
	w.event.emit("interception", {"by": i["cb"]})
	assert_eq(s.award_stats[1], {"att": 1.0, "int_thrown": 1.0})
	assert_true(not s.award_stats.has(2))
	assert_eq(s.get_line("Ann", "QB")["int_thrown"], 1.0)

func test_replacement_human_does_not_inherit_a_bot_pass() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	owners[i["qb"]] = "Ann"
	player_ids[i["qb"]] = 1
	w.event.emit("catch", {"by": i["wr"]})
	w.event.emit("out_of_bounds", {"carrier": i["wr"], "spot": Vector2(0, 37), "team": 0})
	assert_true(s.award_stats.is_empty())
	assert_eq(s.get_line("Bot", "QB")["comp"], 1.0)
	assert_eq(s.get_line("Bot", "QB")["pass_yds"], 12.0)
	assert_true(s.get_line("Ann", "QB").is_empty())

## #276: give the athlete to a new player (Ben, id 2) mid-play.
func _replace_owner(aid: int) -> void:
	owners[aid] = "Ben"
	player_ids[aid] = 2

func _own(aid: int) -> void:
	owners[aid] = "Ann"
	player_ids[aid] = 1

func test_run_after_the_catch_stays_with_the_receiver_who_caught() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	var wr: int = i["wr"]
	_own(wr)
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("catch", {"by": wr})
	_replace_owner(wr)
	w.event.emit("touchdown", {"carrier": wr, "spot": Vector2(20, 100), "team": 0, "points": 6})
	var catch_td := {"rec": 1.0, "rec_yds": 75.0, "rec_td": 1.0, "pts": 6.0, "max_td_pts": 6.0}
	assert_eq(s.award_stats[1], catch_td)
	assert_true(not s.award_stats.has(2), "the replacement inherits nothing from the catch")
	assert_true(s.get_line("Ben", "WR").is_empty())
	assert_true(s.player_summary(2).is_empty())
	assert_eq(s.athletes[wr]["owner"], "Ann")
	for field in catch_td:
		assert_eq(s.get_line("Ann", "WR")[field], catch_td[field], field)
		assert_eq(s.athletes[wr][field], catch_td[field], field)
	# The next catch belongs to the new owner.
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("catch", {"by": wr})
	w.event.emit("tackle", {"by": i["lb"], "carrier": wr, "spot": Vector2(20, 37), "team": 0})
	assert_eq(s.award_stats[1], catch_td)
	assert_eq(s.award_stats.get(2), {"rec": 1.0, "rec_yds": 12.0})

func test_field_goal_result_stays_with_the_kicker() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var k: int = _ids(w)["qb"]
	_own(k)
	w.event.emit("snap", {})
	w.event.emit("kick", {"by": k, "kind": "fg"})
	_replace_owner(k)
	w.event.emit("field_goal", {"good": true, "distance": 41.6})
	assert_eq(s.award_stats[1], {"fg_att": 1.0, "fg_made": 1.0, "fg_long": 42.0})
	assert_true(not s.award_stats.has(2), "the replacement didn't kick it")
	assert_true(s.get_line("Ben", "QB").is_empty())
	assert_eq(s.athletes[k]["owner"], "Ann")
	assert_eq(s.athletes[k]["fg_made"], 1.0)

func test_pat_result_stays_with_the_kicker() -> void:
	var r := _setup()
	var w: World = r[0]
	var m: Match = r[1]
	var s: Stats = r[2]
	var k: int = _ids(w)["qb"]
	s.match_ref = m
	m.state = Match.State.TRY
	_own(k)
	w.event.emit("snap", {})
	w.event.emit("kick", {"by": k, "kind": "fg"})
	_replace_owner(k)
	w.event.emit("field_goal", {"good": true, "distance": 20.0})
	assert_eq(s.award_stats[1], {"xp_att": 1.0, "xp_made": 1.0})
	assert_true(not s.award_stats.has(2))

func test_punt_yards_stay_with_the_punter() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var k: int = _ids(w)["qb"]
	_own(k)
	w.event.emit("snap", {})
	w.event.emit("kick", {"by": k, "kind": "punt"})
	_replace_owner(k)
	w.event.emit("kick_downed", {"spot": Vector2(20, 68)})
	assert_eq(s.award_stats[1], {"punts": 1.0, "punt_yds": 43.0})
	assert_true(not s.award_stats.has(2), "the replacement didn't punt it")
	assert_eq(s.athletes[k]["punt_yds"], 43.0)

func test_replacement_human_does_not_inherit_a_bot_kick() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var k: int = _ids(w)["qb"]
	w.event.emit("snap", {})
	w.event.emit("kick", {"by": k, "kind": "punt"})
	_own(k)
	w.event.emit("touchback", {"spot": Vector2(20, 80)})
	assert_true(s.award_stats.is_empty())
	assert_eq(s.get_line("Bot", "QB")["punt_yds"], 75.0)
	assert_true(s.get_line("Ann", "QB").is_empty())

func test_kick_return_stays_with_the_player_who_fielded_it() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var k: int = _ids(w)["qb"]
	var ret: int = _ids(w)["cb"]
	_own(ret)
	w.event.emit("snap", {})
	w.event.emit("kick", {"by": k, "kind": "punt"})
	w.event.emit("kick_catch", {"by": ret, "team": 1, "at": Vector2(20, 80)})
	_replace_owner(ret)
	w.event.emit("tackle", {"by": _ids(w)["lb"], "carrier": ret, "spot": Vector2(20, 66), "team": 1})
	assert_eq(s.award_stats[1], {"pr": 1.0, "pr_yds": 14.0})
	assert_true(not s.award_stats.has(2), "the replacement didn't field the punt")
	# A return touchdown: the score belongs to whoever ran that return.
	_own(ret)
	w.event.emit("snap", {})
	w.kicked = true
	w.kick_play = "kickoff"
	w.event.emit("kick", {"by": k, "kind": "kickoff"})
	w.event.emit("kick_catch", {"by": ret, "team": 1, "at": Vector2(20, 95)})
	_replace_owner(ret)
	w.event.emit("touchdown", {"carrier": ret, "spot": Vector2(20, -2), "team": 1, "points": 6})
	assert_eq(s.award_stats[1], {"pr": 1.0, "pr_yds": 14.0, "kr": 1.0, "kr_yds": 95.0, "pts": 6.0,
		"ret_td": 1.0, "max_td_pts": 6.0})
	assert_true(not s.award_stats.has(2))
	assert_eq(s.athletes[ret]["owner"], "Ann")

func test_takeaway_return_stays_with_the_player_who_made_it() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	_own(i["cb"])
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("interception", {"by": i["cb"], "at": Vector2(20, 40), "team": 1})
	_replace_owner(i["cb"])
	w.event.emit("touchdown", {"carrier": i["cb"], "spot": Vector2(20, -3), "team": 1, "points": 6})
	assert_eq(s.award_stats[1], {"int": 1.0, "int_ret_yds": 40.0, "pts": 6.0, "def_td": 1.0, "max_td_pts": 6.0})
	assert_true(not s.award_stats.has(2), "the replacement didn't make the pick")
	# Fumble return, ended by a tackle.
	_own(i["lb"])
	w.event.emit("snap", {})
	w.event.emit("handoff", {"to": i["rb"]})
	w.event.emit("fumble", {"carrier": i["rb"], "by": i["cb"], "at": Vector2(26, 30)})
	w.get_athlete(i["lb"]).position = Vector2(27, 33)
	w.event.emit("recovery", {"by": i["lb"], "team": 1, "turnover": true})
	_replace_owner(i["lb"])
	w.event.emit("tackle", {"by": i["wr"], "carrier": i["lb"], "spot": Vector2(20, 21), "team": 1})
	assert_eq(s.award_stats[1].get("fr_ret_yds", 0.0), 12.0)
	assert_true(not s.award_stats[2].has("fr_ret_yds"), "the replacement didn't recover it")

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

func test_keeper_credit_survives_seat_replacement_and_resets_at_next_snap() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var qb: int = _ids(w)["qb"]
	owners[qb] = "Riley"
	player_ids[qb] = 1
	assert_true(w.snap())
	owners[qb] = "Morgan"
	player_ids[qb] = 2
	w.event.emit("touchdown", {"carrier": qb, "spot": Vector2(26, 100), "team": 0, "points": 6})

	assert_eq(s.award_stats.get(1, {}), {"car": 1.0, "rush_yds": 75.0, "rush_td": 1.0, "pts": 6.0, "max_td_pts": 6.0})
	assert_eq(s.player_summary(1), ["QB: 1 car 75yd 1TD"])
	assert_eq(s.get_line("Riley", "QB").get("rush_yds"), 75.0)
	assert_eq(s.player_summary(2), [])
	assert_eq(s.athletes.get(qb, {}).get("owner"), "Riley")

	r[1].start(0, 25.0)
	assert_true(w.snap())
	w.event.emit("out_of_bounds", {"carrier": qb, "spot": Vector2(0, 29), "team": 0})
	assert_eq(s.award_stats.get(2, {}), {"car": 1.0, "rush_yds": 4.0})
	assert_eq(s.player_summary(2), ["QB: 1 car 4yd 0TD"])
	assert_eq(s.athletes.get(qb, {}).get("owner"), "Morgan")
	assert_eq(s.total("car"), 2.0)

func test_lost_keeper_fumble_credits_original_qb_and_separate_defensive_return() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	var qb := w.get_athlete(i["qb"])
	var defender := w.get_athlete(i["lb"])
	owners[qb.id] = "Riley"
	player_ids[qb.id] = 1
	assert_true(w.snap())
	while w.snap_in_flight():
		w.step({}, DT)
	owners[qb.id] = "Morgan"
	player_ids[qb.id] = 2
	qb.position = Vector2(5.0, 37.0)
	defender.position = qb.position
	w._fumble(qb, defender)
	w.ball.position.z = 0.0
	w._step_loose(0.0)
	assert_eq(w.carrier(), defender, "defense recovered the live ball")
	defender.position = Vector2(-0.5, 32.0)
	w.step({}, DT)

	assert_eq(s.award_stats.get(1, {}), {"car": 1.0, "rush_yds": 12.0})
	assert_eq(s.player_summary(1), ["QB: 1 car 12yd 0TD"])
	assert_eq(s.player_summary(2), [])
	assert_eq(s.athletes.get(qb.id, {}).get("owner"), "Riley")
	assert_eq(s.total("car"), 1.0)
	assert_eq(s.get_line("Bot", "LB").get("ff"), 1.0)
	assert_eq(s.get_line("Bot", "LB").get("fr"), 1.0)
	assert_eq(s.get_line("Bot", "LB").get("fr_ret_yds"), 5.0)

func test_qb_recovery_keeps_one_carry_to_the_fumble_spot() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	var qb := w.get_athlete(i["qb"])
	assert_true(w.snap())
	while w.snap_in_flight():
		w.step({}, DT)
	qb.position = Vector2(5.0, 32.0)
	w._fumble(qb, w.get_athlete(i["lb"]))
	qb.recover_t = 0.0
	w.ball.position.z = 0.0
	w._step_loose(0.0)
	assert_eq(w.carrier(), qb, "QB recovered his own fumble")
	qb.position = Vector2(-0.5, 38.0)
	w.step({}, DT)

	assert_eq(s.total("car"), 1.0)
	assert_eq(s.total("rush_yds"), 7.0, "later whistle cannot move the credited spot")
	assert_eq(s.total("fr_ret_yds"), 0.0)

func test_fumble_outside_a_keeper_does_not_add_a_carry() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	var carrier: int = i["qb"]
	var hit := {"carrier": carrier, "by": i["lb"], "at": Vector2(5.0, 23.0)}
	w.event.emit("snap", {"qb": carrier})
	w.event.emit("fumble", hit)
	assert_eq(s.total("car"), 0.0, "a sack fumble is not a carry")
	hit["at"] = Vector2(5.0, 25.0)
	w.event.emit("fumble", hit)
	assert_eq(s.total("car"), 0.0, "a fumble on the line is not a carry")

	hit["at"] = Vector2(5.0, 32.0)
	w.event.emit("throw", {"by": carrier})
	w.event.emit("catch", {"by": carrier})
	w.event.emit("fumble", hit)
	assert_eq(s.total("car"), 0.0, "a QB fumble on a catch is not a carry")

	w.event.emit("snap", {"qb": carrier})
	w.kicked = true
	w.event.emit("kick", {"by": carrier, "kind": "punt"})
	w.event.emit("kick_catch", {"by": i["cb"], "at": Vector2(5.0, 70.0)})
	w.event.emit("recovery", {"by": carrier, "turnover": true})
	w.event.emit("fumble", hit)
	assert_eq(s.total("car"), 0.0, "a QB fumble on a kick-play recovery is not a carry")

func test_fumbled_handoff_credits_the_owner_at_the_exchange() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	var back := w.get_athlete(i["rb"])
	var qb := w.get_athlete(i["qb"])
	assert_true(w.snap())
	while w.snap_in_flight():
		w.step({}, DT)
	owners[back.id] = "Riley"
	player_ids[back.id] = 1
	back.position = qb.position + Vector2.RIGHT
	assert_true(w.handoff(qb.id))
	owners[back.id] = "Morgan"
	player_ids[back.id] = 2
	back.position.y = w.los_y + 4.0
	w._fumble(back, w.get_athlete(i["lb"]))
	w.ball.hold(back.id)
	back.position = Vector2(-0.5, w.los_y + 5.0)
	w.step({}, DT)

	assert_eq(s.award_stats.get(1, {}), {"car": 1.0, "rush_yds": 4.0})
	assert_eq(s.player_summary(1), ["RB: 1 car 4yd 0TD"])
	assert_eq(s.player_summary(2), [])
	assert_eq(s.athletes.get(back.id, {}).get("owner"), "Riley")
	assert_eq(s.total("car"), 1.0)

func test_replacing_a_bot_does_not_inherit_its_handoff() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	w.event.emit("snap", {"qb": i["qb"]})
	w.event.emit("handoff", {"to": i["rb"]})
	owners[i["rb"]] = "Riley"
	player_ids[i["rb"]] = 1
	w.event.emit("tackle", {"by": i["lb"], "carrier": i["rb"], "spot": Vector2(26, 31), "team": 0})
	assert_eq(s.get_line("Bot", "RB").get("rush_yds"), 6.0)
	assert_true(s.award_stats.is_empty())
	assert_eq(s.athletes.get(i["rb"], {}).get("owner"), "Bot")

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

func test_receiver_fumble_keeps_yards_with_original_passer_and_receiver() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	owners[i["qb"]] = "Riley"
	owners[i["wr"]] = "Pat"
	player_ids[i["qb"]] = 1
	player_ids[i["wr"]] = 2
	w.event.emit("snap", {"qb": i["qb"]})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("catch", {"by": i["wr"]})
	owners[i["qb"]] = "Morgan"
	owners[i["wr"]] = "Casey"
	player_ids[i["qb"]] = 3
	player_ids[i["wr"]] = 4
	w.event.emit("fumble", {"carrier": i["wr"], "by": i["lb"], "at": Vector2(20, 42)})
	w.get_athlete(i["lb"]).position = Vector2(20, 42)
	w.event.emit("recovery", {"by": i["lb"], "turnover": true})
	w.event.emit("out_of_bounds", {"carrier": i["lb"], "spot": Vector2(0, 35)})

	assert_eq(s.award_stats.get(1, {}), {"att": 1.0, "comp": 1.0, "pass_yds": 17.0})
	assert_eq(s.award_stats.get(2, {}), {"rec": 1.0, "rec_yds": 17.0})
	assert_eq(s.player_summary(1), ["QB: 1/1 17yd 0TD 0INT"])
	assert_eq(s.player_summary(2), ["WR: 1 rec 17yd 0TD"])
	assert_true(s.player_summary(3).is_empty() and s.player_summary(4).is_empty())
	assert_eq(s.get_line("Bot", "LB").get("ff"), 1.0)
	assert_eq(s.get_line("Bot", "LB").get("fr"), 1.0)
	assert_eq(s.get_line("Bot", "LB").get("fr_ret_yds"), 7.0)

func test_receiver_recovery_preserves_fumble_spot_and_next_pass_records_yards() -> void:
	var r := _setup()
	var w: World = r[0]
	var s: Stats = r[2]
	var i := _ids(w)
	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("catch", {"by": i["wr"]})
	w.event.emit("fumble", {"carrier": i["wr"], "by": i["lb"], "at": Vector2(20, 32)})
	w.event.emit("recovery", {"by": i["wr"], "turnover": false})
	w.event.emit("out_of_bounds", {"carrier": i["wr"], "spot": Vector2(0, 38)})
	assert_eq(s.total("pass_yds"), 7.0)
	assert_eq(s.total("rec_yds"), 7.0)
	assert_eq(s.total("fr_ret_yds"), 0.0)

	w.event.emit("snap", {})
	w.event.emit("throw", {"by": i["qb"]})
	w.event.emit("catch", {"by": i["wr"]})
	w.event.emit("out_of_bounds", {"carrier": i["wr"], "spot": Vector2(0, 29)})
	assert_eq(s.total("pass_yds"), 11.0)
	assert_eq(s.total("rec_yds"), 11.0)
	assert_eq(s.total("comp"), 2.0)
	assert_eq(s.total("rec"), 2.0)

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
	assert_true(s.summary_lines().any(func(l): return l.begins_with("Ann CB:") and l.contains("28yd int ret")),
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
	assert_true(s.summary_lines().any(func(l): return l.contains("12yd fum ret")), str(s.summary_lines()))
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
