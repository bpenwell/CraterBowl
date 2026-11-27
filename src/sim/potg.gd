extends RefCounted
## Players of the game: rank every athlete's stat line by impact and pick the
## 2-4 standouts shown in the post-game presentation and the lobby's game
## overview. Pure: input is Stats.athletes ({athlete_id: line}).

const MIN_PICKS := 2
const MAX_PICKS := 4
## A pick must reach this share of the top score (between MIN and MAX picks).
const CUTOFF := 0.3
## Small nudge so a winner usually takes the top spot when lines are close.
const WIN_BONUS := 1.15
const TEAM_NAMES := ["HELIOS", "NEBULA"]
## Fantasy-style weights: a touchdown ~ 6, ten scrimmage yards ~ 1.
const WEIGHTS := {"pass_yds": 0.04, "pass_td": 4.0, "int_thrown": -2.0, "comp": 0.2,
	"rec": 0.5, "rec_yds": 0.1, "rec_td": 6.0, "rush_yds": 0.1, "rush_td": 6.0,
	"tkl": 1.0, "sack": 3.0, "int": 5.0, "pbu": 1.5, "ff": 3.0, "fr": 2.0, "def_td": 6.0, "blk": 0.3,
	"int_ret_yds": 0.1, "fr_ret_yds": 0.1, "fg_made": 3.0, "kr_yds": 0.04, "pr_yds": 0.04, "ret_td": 6.0}
## Category -> fields, for the card title of picks after the first.
const CATEGORIES := [["TOP PASSER", ["pass_yds", "pass_td", "comp", "int_thrown"]],
	["TOP RECEIVER", ["rec", "rec_yds", "rec_td"]], ["TOP RUSHER", ["rush_yds", "rush_td"]],
	["DEFENSIVE STANDOUT", ["tkl", "sack", "int", "pbu", "ff", "fr", "def_td", "int_ret_yds", "fr_ret_yds"]], ["TRENCH ANCHOR", ["blk"]],
	["SPECIAL TEAMS STANDOUT", ["ret_td", "fg_made", "kr_yds", "pr_yds"]]]

static func impact(line: Dictionary) -> float:
	var s := 0.0
	for f in WEIGHTS:
		s += float(line.get(f, 0.0)) * WEIGHTS[f]
	return s

## Ranked picks: [{id, team, pos, owner, score, title, lines: [String], stats: {field: n}}].
## `winner` is the winning team (-1 tie). Deterministic (ties break on athlete id).
## Always 2 picks when at least two athletes recorded any stat.
static func pick(athletes: Dictionary, winner: int) -> Array:
	var ranked := []
	for aid in athletes:
		var l: Dictionary = athletes[aid]
		var sc := impact(l)
		if winner >= 0 and int(l.get("team", -1)) == winner:
			sc *= WIN_BONUS
		ranked.append([sc, int(aid)])
	ranked.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out := []
	for r in ranked:
		if out.size() >= MAX_PICKS:
			break
		# Past the minimum, only real standouts; below it, pad with the next best line.
		if out.size() >= MIN_PICKS and (r[0] <= 0.0 or r[0] < ranked[0][0] * CUTOFF):
			break
		var l: Dictionary = athletes[r[1]]
		var stat := {}
		for f in WEIGHTS:
			if float(l.get(f, 0.0)) != 0.0:
				stat[f] = int(round(float(l[f])))
		out.append({"id": r[1], "team": int(l.get("team", 0)), "pos": str(l.get("pos", "?")),
			"owner": str(l.get("owner", "Bot")), "score": snappedf(r[0], 0.01),
			"title": "PLAYER OF THE GAME" if out.is_empty() else category(l),
			"lines": stat_lines(l), "stats": stat})
	return out

## Biggest contributing category of a line ("TOP RUSHER", ...).
static func category(line: Dictionary) -> String:
	var best := ""
	var best_v := -INF
	for c in CATEGORIES:
		var v := 0.0
		for f in c[1]:
			v += float(line.get(f, 0.0)) * WEIGHTS[f]
		if v > best_v:
			best_v = v
			best = c[0]
	return best

## Up to three short stat strings, biggest first ("14/20  212 YDS  2 TD").
static func stat_lines(l: Dictionary) -> Array:
	var parts := []   # [weight, text]
	var g := func(f): return int(round(float(l.get(f, 0.0))))
	if g.call("att") > 0:
		parts.append([g.call("pass_yds") * 0.04 + g.call("pass_td") * 4,
			"%d/%d  %d YDS%s%s" % [g.call("comp"), g.call("att"), g.call("pass_yds"), _td(g.call("pass_td")),
			("  %d INT" % g.call("int_thrown")) if g.call("int_thrown") > 0 else ""]])
	if g.call("rec") > 0:
		parts.append([g.call("rec_yds") * 0.1 + g.call("rec_td") * 6 + g.call("rec") * 0.5,
			"%d REC  %d YDS%s" % [g.call("rec"), g.call("rec_yds"), _td(g.call("rec_td"))]])
	if g.call("car") > 0:
		parts.append([g.call("rush_yds") * 0.1 + g.call("rush_td") * 6,
			"%d CAR  %d YDS%s" % [g.call("car"), g.call("rush_yds"), _td(g.call("rush_td"))]])
	var dfn := []
	var dw := 0.0
	for f in [["tkl", "TKL"], ["sack", "SACK"], ["int", "INT"], ["pbu", "PBU"], ["ff", "FF"], ["fr", "FR"], ["def_td", "DEF TD"]]:
		if g.call(f[0]) > 0:
			dfn.append("%d %s" % [g.call(f[0]), f[1]])
			dw += g.call(f[0]) * WEIGHTS[f[0]]
	for f in [["int_ret_yds", "INT RET YDS"], ["fr_ret_yds", "FUM RET YDS"]]:
		if g.call(f[0]) != 0:
			dfn.append("%d %s" % [g.call(f[0]), f[1]])
			dw += g.call(f[0]) * WEIGHTS[f[0]]
	if not dfn.is_empty():
		parts.append([dw, "  ".join(dfn)])
	var return_tds: int = g.call("ret_td")
	if return_tds > 0:
		parts.append([return_tds * WEIGHTS["ret_td"], "%d RET TD" % return_tds])
	if g.call("fg_att") > 0:
		parts.append([g.call("fg_made") * WEIGHTS["fg_made"], "%d/%d FG%s" % [g.call("fg_made"), g.call("fg_att"),
			("  LONG %d" % g.call("fg_long")) if g.call("fg_made") > 0 else ""]])
	for f in [["kr_yds", "KR YDS"], ["pr_yds", "PR YDS"]]:
		if g.call(f[0]) != 0:
			parts.append([g.call(f[0]) * WEIGHTS[f[0]], "%d %s" % [g.call(f[0]), f[1]]])
	if g.call("blk") > 0:
		parts.append([g.call("blk") * 0.3, "%d BLOCKS" % g.call("blk")])
	parts.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	for p in parts.slice(0, 3):
		out.append(p[1])
	return out

static func _td(n: int) -> String:
	return "  %d TD" % n if n > 0 else ""

## Per-team totals for the overview box score: [{pass_yds, rush_yds, td, turnovers, tkl, sack}, x2].
static func team_totals(athletes: Dictionary) -> Array:
	var out := []
	for t in 2:
		out.append({"pass_yds": 0, "rush_yds": 0, "td": 0, "turnovers": 0, "tkl": 0, "sack": 0})
	for aid in athletes:
		var l: Dictionary = athletes[aid]
		var t := int(l.get("team", -1))
		if t < 0 or t > 1:
			continue
		var o: Dictionary = out[t]
		o["pass_yds"] += int(round(float(l.get("pass_yds", 0.0))))
		o["rush_yds"] += int(round(float(l.get("rush_yds", 0.0))))
		o["td"] += int(l.get("pass_td", 0.0) + l.get("rush_td", 0.0)
			+ l.get("def_td", 0.0) + l.get("ret_td", 0.0))
		o["turnovers"] += int(l.get("int_thrown", 0.0))
		o["tkl"] += int(l.get("tkl", 0.0))
		o["sack"] += int(l.get("sack", 0.0))
	return out
