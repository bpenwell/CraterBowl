extends RefCounted
## Per-owner, per-position match stats from World events. Pure.

const Athlete := preload("res://src/sim/athlete.gd")
const ROLE := {0: "QB", 1: "C", 2: "WR", 3: "RB", 4: "LB", 5: "CB", 6: "S", 7: "OL", 8: "DL"}
const FIELDS := ["att", "comp", "pass_yds", "pass_td", "int_thrown", "rec", "rec_yds", "rec_td",
	"car", "rush_yds", "rush_td", "tkl", "sack", "int", "pbu", "ff", "fr", "pts", "blk", "def_td", "max_td_pts",
	"int_ret_yds", "fr_ret_yds",
	"fg_made", "fg_att", "fg_long", "xp_made", "xp_att", "punts", "punt_yds", "kr", "kr_yds", "pr", "pr_yds", "ret_td"]
## Best-of fields: a new value replaces the old one only when larger (never summed).
const MAX_FIELDS := ["max_td_pts", "fg_long"]

var world
var owner_fn: Callable     # athlete_id -> owner name ("Bot" for AI)
var player_fn: Callable    # athlete_id -> current player id (-1 for AI)
var lines := {}            # "owner|POS" -> {field: value}
var athletes := {}         # athlete_id -> {"team", "pos", "owner", field: value} (players of the game)
var award_stats := {}      # player id -> {field: value}, across positions
var player_lines := {}     # player id -> {"POS": {field: value}}: your own post-game lines (#200)
var _los := 0.0
var _passer := -1
var _receiver := -1
## Who gets a delayed result (#202, #276, #293): the athlete's line key and player at the
## throw, catch, kick, fielding, takeaway, snap or handoff. Later seat changes keep that credit.
## Rule: docs/features/progression.md "Match awards follow the player in the seat".
var _passer_credit := {}
var _receiver_credit := {}
var _pass_yards_credited := false
var _thrown := false
var _keeper_credit := {}
var _handoff_credit := {}
var _rushing_fumble := false
## Takeaway return in progress (#100): who has the ball, where he took it, which field.
var _returner := -1
var _ret_from := 0.0
var _ret_field := ""
var _returner_credit := {}
## Kick in progress (#67): "fg", "xp" (a PAT try), "punt" or "kickoff", and the kicker.
var _kick_kind := ""
var _kicker := -1
var _kicker_credit := {}
var match_ref = null       # optional Match: tells a PAT try from a field goal

func attach(w, owner: Callable, m = null, player: Callable = Callable()) -> void:
	world = w
	owner_fn = owner
	match_ref = m
	player_fn = player
	w.event.connect(_on_event)

func _key(aid: int) -> String:
	var a = world.get_athlete(aid)
	var owner: String = owner_fn.call(aid) if owner_fn.is_valid() else "Bot"
	return "%s|%s" % [owner, ROLE.get(a.role if a else -1, "?")]

func _player_id(aid: int) -> int:
	return player_fn.call(aid) if player_fn.is_valid() else -1

func _add(aid: int, field: String, v: float = 1.0) -> void:
	if aid < 0 or world.get_athlete(aid) == null:
		return
	var key := _key(aid)
	_add_player_credit(key, _player_id(aid), field, v)
	_add_athlete(aid, field, v, key.get_slice("|", 0))

func _add_player_credit(key: String, player: int, field: String, value: float) -> void:
	if not lines.has(key):
		lines[key] = _blank()
	_add_field(lines[key], field, value)
	if player < 0:
		return
	if not award_stats.has(player):
		award_stats[player] = {}
	_add_field(award_stats[player], field, value)
	var pos := key.get_slice("|", 1)
	if not player_lines.has(player):
		player_lines[player] = {}
	if not player_lines[player].has(pos):
		player_lines[player][pos] = _blank()
	_add_field(player_lines[player][pos], field, value)

## Snapshot who owns `aid` now, for a result that arrives later in the play.
func _credit_for(aid: int) -> Dictionary:
	if aid < 0 or world.get_athlete(aid) == null:
		return {}
	return {"aid": aid, "key": _key(aid), "player": _player_id(aid)}

## Delayed results use the recorded owner. A rush records its carry here, so its first
## stat also records the original runner as the athlete line's last human contributor.
func _add_credit(credit: Dictionary, field: String, value: float = 1.0, record_owner := false) -> void:
	if credit.is_empty():
		return
	var aid: int = credit["aid"]
	var key: String = credit["key"]
	_add_player_credit(key, credit["player"], field, value)
	if record_owner or not athletes.has(aid):
		_add_athlete(aid, field, value, key.get_slice("|", 0))
	else:
		_add_field(athletes[aid], field, value)

static func _blank() -> Dictionary:
	var line := {}
	for f in FIELDS:
		line[f] = 0.0
	return line

static func _add_field(line: Dictionary, field: String, value: float) -> void:
	var previous: float = line.get(field, 0.0)
	line[field] = maxf(previous, value) if field in MAX_FIELDS else previous + value

## Same stat, keyed by the athlete itself. The owner is the last human who
## controlled it (a bot that a human took over is credited to the human).
func _add_athlete(aid: int, field: String, v: float, owner: String) -> void:
	var a = world.get_athlete(aid)
	if not athletes.has(aid):
		athletes[aid] = {"team": a.team, "pos": ROLE.get(a.role, "?"), "owner": "Bot"}
		for f in FIELDS:
			athletes[aid][f] = 0.0
	if owner != "Bot":
		athletes[aid]["owner"] = owner
	_add_field(athletes[aid], field, v)

func _on_event(n: String, d: Dictionary) -> void:
	match n:
		"snap":
			_los = world.los_y
			_passer = -1
			_receiver = -1
			_pass_yards_credited = false
			_thrown = false
			_keeper_credit = _credit_for(d.get("qb", -1))
			_handoff_credit = {}
			_rushing_fumble = false
			_returner = -1
			_kick_kind = ""
			_kicker = -1
			_passer_credit = {}
			_receiver_credit = {}
			_returner_credit = {}
			_kicker_credit = {}
		"kick":
			_on_kick(d)
		"field_goal":
			_on_field_goal(d)
		"kick_catch":
			var kind := _kick_kind
			_end_punt(d["at"].y)
			if kind == "kickoff" or kind == "punt":
				var f := "kr" if kind == "kickoff" else "pr"
				_add(d["by"], f)
				_start_return(d["by"], d["at"].y, f + "_yds")
		"kick_blocked":
			_end_punt(_los)   # a blocked punt counts as a punt for 0 yards
		"kick_downed", "kick_out_of_bounds":
			_end_punt(d["spot"].y)
		"touchback":
			_end_punt(world.field.length)   # punt yardage on a touchback runs to the goal line
		"handoff":
			_handoff_credit = _credit_for(d["to"])
		"throw":
			if d["by"] == _returner:   # a pass/lateral (chaosball swings) ends the return at the throw
				_credit_return(world.get_athlete(_returner).position.y)
			if not _thrown:
				_passer = d["by"]
				_passer_credit = _credit_for(_passer)
			_thrown = true
			_add(d["by"], "att")
		"catch":
			if _passer >= 0 and world.get_athlete(d["by"]).team == world.get_athlete(_passer).team:
				_receiver = d["by"]
				_receiver_credit = _credit_for(_receiver)
				_add_credit(_passer_credit, "comp")
				_add(_receiver, "rec")
		"interception":
			if _passer >= 0:
				_add_credit(_passer_credit, "int_thrown")
			_add(d["by"], "int")
			var at: Vector2 = d.get("at", world.get_athlete(d["by"]).position)
			_start_return(d["by"], at.y, "int_ret_yds")
		"breakup":
			_add(d["by"], "pbu")
		"block":
			_add(d["blocker"], "blk")
		"fumble":
			if d["carrier"] == _receiver and not _pass_yards_credited:
				_credit_pass_yards(d["at"].y - _los)
			_add(d["by"], "ff")
			var carrier: int = d["carrier"]
			if carrier == _returner:   # fumbled mid-return: the return ends where he lost it
				_credit_return(d["at"].y)
			elif not _rushing_fumble and not _thrown:
				var gain: float = d["at"].y - _los
				var credit := {}
				if carrier == _handoff_credit.get("aid", -1):
					credit = _handoff_credit
				elif carrier == _keeper_credit.get("aid", -1) and gain > 0.0 and not world.kicked:
					credit = _keeper_credit
				if not credit.is_empty():
					_rushing_fumble = true
					_add_credit(credit, "car", 1.0, true)
					_add_credit(credit, "rush_yds", gain)
		"recovery":
			_add(d["by"], "fr")
			if d.get("turnover", false):
				_start_return(d["by"], world.get_athlete(d["by"]).position.y, "fr_ret_yds")
		"tackle", "out_of_bounds", "touchdown":
			_end_play(n, d)

func _end_play(n: String, d: Dictionary) -> void:
	var carrier: int = d.get("carrier", -1)
	if carrier < 0:
		return
	var c = world.get_athlete(carrier)
	var on_offense: bool = c.team == world.offense_team
	if n == "tackle":
		_add(d.get("by", -1), "tkl")
	var current_credit := _credit_for(carrier)
	var credit := current_credit
	if carrier == _receiver:
		credit = _receiver_credit
	var returning := carrier == _returner
	if returning:
		credit = _returner_credit
		var end_y: float = d["spot"].y
		if n == "touchdown":
			end_y = world.field.length if on_offense else 0.0
		_credit_return(end_y)
	var gain: float = d["spot"].y - _los if on_offense else 0.0
	if n == "touchdown" and on_offense:
		gain = world.field.length - _los
	if n == "tackle" and c.role == Athlete.Role.QB and not _thrown and on_offense and d["spot"].y < _los:
		_add(d.get("by", -1), "sack")
		return
	if not on_offense:
		if n == "touchdown":
			_add_credit(credit, "pts", d.get("points", 6))
			var kick_return: bool = world.kicked and world.kick_play in ["kickoff", "punt"]
			_add_credit(credit, "ret_td" if kick_return else "def_td")
			_note_td_points(credit, d.get("points", 6))
		return   # returns (kick, punt, takeaway) are credited above
	if _receiver >= 0 and carrier == _receiver:
		if not _pass_yards_credited:
			_credit_pass_yards(gain)
		if n == "touchdown":
			_add_credit(_passer_credit, "pass_td")
			_add_credit(_receiver_credit, "rec_td")
	elif not _thrown and not _rushing_fumble:
		var rush_credit := current_credit
		if not returning:
			if carrier == _handoff_credit.get("aid", -1):
				rush_credit = _handoff_credit
			elif carrier == _keeper_credit.get("aid", -1):
				rush_credit = _keeper_credit
			credit = rush_credit
		_add_credit(rush_credit, "car", 1.0, true)
		_add_credit(rush_credit, "rush_yds", gain)
		if n == "touchdown":
			_add_credit(rush_credit, "rush_td")
	if n == "touchdown":
		_add_credit(credit, "pts", d.get("points", 6))
		_note_td_points(credit, d.get("points", 6))

## A completion already credited at the fumble spot keeps those yards at the whistle.
func _credit_pass_yards(gain: float) -> void:
	_pass_yards_credited = true
	_add_credit(_passer_credit, "pass_yds", gain)
	_add_credit(_receiver_credit, "rec_yds", gain)

## A takeaway (interception or a fumble recovered by the other team) starts a return at
## the catch / recovery spot. The returner may be on either team (a double turnover).
func _start_return(aid: int, from_y: float, field: String) -> void:
	_returner = aid
	_returner_credit = _credit_for(aid)
	_ret_from = from_y
	_ret_field = field

## Credit the return from the takeaway spot to `end_y`, measured toward the returner's
## scoring end zone (negative when he is driven back), then close it.
func _credit_return(end_y: float) -> void:
	var a = world.get_athlete(_returner)
	if a:
		_add_credit(_returner_credit, _ret_field, (end_y - _ret_from) * world.attack_sign(a.team))
	_returner = -1

func _note_td_points(credit: Dictionary, pts) -> void:
	_add_credit(credit, "max_td_pts", float(pts))

## A kick is away (#67). Field goals and PATs count the attempt now (a blocked kick is a miss);
## a punt counts now and gets its yards when the ball is fielded or dies.
func _on_kick(d: Dictionary) -> void:
	_kicker = d["by"]
	_kicker_credit = _credit_for(_kicker)
	_kick_kind = str(d.get("kind", ""))
	if _kick_kind == "fg" and match_ref != null and match_ref.state == match_ref.State.TRY:
		_kick_kind = "xp"
	match _kick_kind:
		"fg":
			_add(_kicker, "fg_att")
		"xp":
			_add(_kicker, "xp_att")
		"punt":
			_add(_kicker, "punts")

func _on_field_goal(d: Dictionary) -> void:
	if not d.get("good", false) or _kicker < 0:
		return
	if _kick_kind == "xp":
		_add_credit(_kicker_credit, "xp_made")
	elif _kick_kind == "fg":
		_add_credit(_kicker_credit, "fg_made")
		_add_credit(_kicker_credit, "fg_long", roundf(float(d.get("distance", 0.0))))

## Gross punt yards: line of scrimmage to where the punt is fielded or dies. Credited once.
func _end_punt(end_y: float) -> void:
	if _kick_kind != "punt" or _kicker < 0:
		return
	_add_credit(_kicker_credit, "punt_yds", end_y - _los)
	_kick_kind = "punt_done"

func get_line(owner: String, pos: String) -> Dictionary:
	return lines.get("%s|%s" % [owner, pos], {})

func total(field: String) -> float:
	var t := 0.0
	for k in lines:
		t += lines[k][field]
	return t

func to_dict() -> Dictionary:
	return lines.duplicate(true)

## Compact human-readable lines for every non-bot owner + bot totals, keyed by display name
## ("Ann QB: ..."): same-named players share a line here, as in the career table.
func summary_lines() -> Array:
	var out := []
	var keys := lines.keys()
	keys.sort()
	for k in keys:
		var text := line_text(lines[k])
		if text != "":
			out.append("%s %s: %s" % [k.get_slice("|", 0), k.get_slice("|", 1), text])
	return out

## One player's own lines ("QB: ..."), keyed by match identity rather than display name (#200),
## so two players named Ann never see or merge each other's numbers.
func player_summary(player: int) -> Array:
	var out := []
	var by_pos: Dictionary = player_lines.get(player, {})
	var positions := by_pos.keys()
	positions.sort()
	for pos in positions:
		var text := line_text(by_pos[pos])
		if text != "":
			out.append("%s: %s" % [pos, text])
	return out

## player_summary() for whoever plays each athlete now, keyed by athlete id: the final-whistle
## broadcast, where each machine finds its own lines by its athlete (#200).
func summaries_for(aids: Array) -> Dictionary:
	var out := {}
	for aid in aids:
		out[aid] = player_summary(_player_id(aid))
	return out

## The stat text of one line ("1/2 12yd 0TD 0INT | 1 car 5yd 1TD"), "" when it has no stats.
static func line_text(l: Dictionary) -> String:
	var parts := []
	if l["att"] > 0: parts.append("%d/%d %dyd %dTD %dINT" % [l["comp"], l["att"], l["pass_yds"], l["pass_td"], l["int_thrown"]])
	if l["rec"] > 0: parts.append("%d rec %dyd %dTD" % [l["rec"], l["rec_yds"], l["rec_td"]])
	if l["car"] > 0: parts.append("%d car %dyd %dTD" % [l["car"], l["rush_yds"], l["rush_td"]])
	var dfn := []
	for f in ["tkl", "sack", "int", "pbu", "ff", "fr"]:
		if l[f] > 0: dfn.append("%d %s" % [l[f], f])
	for f in [["int_ret_yds", "int ret"], ["fr_ret_yds", "fum ret"]]:
		if roundi(l[f[0]]) != 0: dfn.append("%dyd %s" % [roundi(l[f[0]]), f[1]])
	if not dfn.is_empty(): parts.append(", ".join(dfn))
	var st := []
	if l["fg_att"] > 0: st.append("%d/%d FG" % [l["fg_made"], l["fg_att"]] + (" long %d" % l["fg_long"] if l["fg_made"] > 0 else ""))
	if l["xp_att"] > 0: st.append("%d/%d XP" % [l["xp_made"], l["xp_att"]])
	if l["punts"] > 0: st.append("%d punt %.1f avg" % [l["punts"], l["punt_yds"] / l["punts"]])
	for f in [["kr", "kick ret"], ["pr", "punt ret"]]:
		if l[f[0]] > 0: st.append("%d %s %dyd" % [l[f[0]], f[1], roundi(l[f[0] + "_yds"])])
	if l["ret_td"] > 0: st.append("%d ret TD" % l["ret_td"])
	if not st.is_empty(): parts.append(", ".join(st))
	return " | ".join(parts)
