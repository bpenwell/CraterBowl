extends RefCounted
## Achievement catalog + evaluation over a per-player match context. Pure.

const CATALOG := [
	{"id": "first_td", "name": "First Touchdown", "desc": "Score a touchdown.", "xp": 100},
	{"id": "first_win", "name": "First Win", "desc": "Win a match.", "xp": 100},
	{"id": "gunslinger", "name": "Gunslinger", "desc": "Throw for 300+ yards in a match.", "xp": 250},
	{"id": "sure_hands", "name": "Sure Hands", "desc": "Make 8+ catches in a match.", "xp": 200},
	{"id": "workhorse", "name": "Workhorse", "desc": "Rush for 100+ yards in a match.", "xp": 200},
	{"id": "sack_artist", "name": "Sack Artist", "desc": "Record 3+ sacks in a match.", "xp": 200},
	{"id": "lockdown", "name": "Lockdown", "desc": "Intercept 2+ passes in a match.", "xp": 250},
	{"id": "pick_six", "name": "Pick Six", "desc": "Score a touchdown on defense.", "xp": 300},
	{"id": "perfect_chaos", "name": "Perfect Chaos", "desc": "Score a 7-point Chaosball touchdown.", "xp": 300},
	{"id": "comeback", "name": "Comeback Kids", "desc": "Win after trailing by 14+.", "xp": 300},
	{"id": "gold_tier", "name": "Going for Gold", "desc": "Reach Gold tier in ranked.", "xp": 300},
	{"id": "iron_man", "name": "Iron Man", "desc": "Play 10 matches.", "xp": 200},
]

static func _f(line: Dictionary, k: String) -> float:
	return float(line.get(k, 0.0))

static func valid_match_context(ctx) -> bool:
	if not (ctx is Dictionary):
		return false
	var line = ctx.get("line", {})
	if not (line is Dictionary and ctx.get("won", false) is bool and ctx.get("mode", "") is String):
		return false
	for key in ["deficit", "rating"]:
		if not _finite_number(ctx.get(key, 0.0)):
			return false
	for value in line.values():
		if not _finite_number(value):
			return false
	return true

static func _finite_number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func earned(id: String, ctx: Dictionary) -> bool:
	var l: Dictionary = ctx.get("line", {})
	match id:
		"first_td":
			return _f(l, "pass_td") + _f(l, "rec_td") + _f(l, "rush_td") + _f(l, "def_td") + _f(l, "ret_td") >= 1.0
		"first_win": return ctx.get("won", false)
		"gunslinger": return _f(l, "pass_yds") >= 300.0
		"sure_hands": return _f(l, "rec") >= 8.0
		"workhorse": return _f(l, "rush_yds") >= 100.0
		"sack_artist": return _f(l, "sack") >= 3.0
		"lockdown": return _f(l, "int") >= 2.0
		"pick_six": return _f(l, "def_td") >= 1.0
		"perfect_chaos": return ctx.get("mode", "") == "chaosball" and _f(l, "max_td_pts") >= 7.0
		"comeback": return ctx.get("won", false) and float(ctx.get("deficit", 0)) >= 14.0
		"gold_tier": return float(ctx.get("rating", 0.0)) >= 1300.0
		"iron_man": return int(ctx.get("games", 0)) >= 10
	return false

## New unlocks (not in `already`) for this context: [{id, name, desc, xp}, ...]
static func evaluate(ctx: Dictionary, already: Array) -> Array:
	var out := []
	for a in CATALOG:
		if not already.has(a["id"]) and earned(a["id"], ctx):
			out.append(a)
	return out

static func name_of(id: String) -> String:
	for a in CATALOG:
		if a["id"] == id:
			return a["name"]
	return id
