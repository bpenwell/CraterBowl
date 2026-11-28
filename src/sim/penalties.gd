extends RefCounted
## Penalty flags (#253): one record shape, one enforcement path, one ruling line.
## World throws flags during the down (World.throw_flag -> "flag" event); Match enforces
## them at the dead ball (Match.next_play -> enforce -> "penalty" event); the HUD prints
## `ruling()`. Later fouls (#254 intentional grounding) build a record with `make()` and
## reuse `enforce()`. Pure + deterministic. Yards are offense-frame (0 = own goal line).

const ILLEGAL_MAN_DOWNFIELD := "illegal_man_downfield"
const INTENTIONAL_GROUNDING := "intentional_grounding"
const NAMES := {ILLEGAL_MAN_DOWNFIELD: "ILLEGAL MAN DOWNFIELD", INTENTIONAL_GROUNDING: "INTENTIONAL GROUNDING"}

## A flag. `team` fouled; `offense` says which side that was on this down; `spot` is the
## yard line (offense frame) the foul is enforced from; `yards` the additional distance;
## `replay` = the down is replayed, `loss_of_down` = it counts (#254); `player` = who fouled.
static func make(type: String, team: int, offense: bool, spot: float, yards: float,
		player := -1, replay := true, loss_of_down := false) -> Dictionary:
	return {"type": type, "team": team, "offense": offense, "spot": spot, "yards": yards,
		"player": player, "replay": replay, "loss_of_down": loss_of_down}

static func name_of(p: Dictionary) -> String:
	var t := str(p.get("type", ""))
	return NAMES.get(t, t.replace("_", " ").to_upper())

## The defense's automatic option on an offensive foul: keep the play's result when it is
## better for the defense than the penalty (a takeaway or defensive score, a safety, a
## failed try, or a turnover on downs). `r` is Match.last_result.
static func defense_declines(r: Dictionary, downs, is_try: bool, flag := {}) -> bool:
	var off: int = downs.offense_team
	var t := str(r.get("type", "incomplete"))
	if int(r.get("team", off)) != off:
		return true
	if is_try:
		return t != "touchdown"
	if t == "touchdown":
		return false
	if t != "incomplete" and float(r.get("spot", 1.0)) < 0.0:
		return true
	if downs.down >= 4:
		var spot: float = downs.los if t == "incomplete" else float(r.get("spot", downs.los))
		if flag.get("type") == INTENTIONAL_GROUNDING:
			return spot < downs.first_down_y and spot <= float(flag["spot"])
		return spot < downs.first_down_y
	return false

## The one enforcement path. Moves `downs` from the foul's spot: back for an offensive foul,
## forward for a defensive one, at most half the distance to the offended goal line, clamped
## to the 1 like every other spot. Replays the down (or spends it with `loss_of_down`).
## Returns what happened: {"los", "down", "yards" (actually walked off), "half_distance",
## "offense", "first_down", "turnover_on_downs"}.
static func enforce(downs, p: Dictionary) -> Dictionary:
	var from: float = float(p.get("spot", downs.los))
	var off_foul: bool = p.get("offense", true)
	var room: float = from if off_foul else downs.goal - from
	var yards := float(p.get("yards", 0.0))
	var half := yards > room / 2.0
	if half:
		yards = room / 2.0
	var to := clampf(from - yards if off_foul else from + yards, 1.0, downs.goal - 1.0)
	downs.los = to
	var out := {"yards": absf(to - from), "half_distance": half, "first_down": false, "turnover_on_downs": false}
	if p.get("loss_of_down", false):
		downs.down += 1
	if not off_foul and downs.los >= downs.first_down_y:
		downs.reset(downs.offense_team, downs.los)
		out["first_down"] = true
	elif downs.down > 4:
		downs.reset(1 - downs.offense_team, downs.goal - downs.los)
		out["turnover_on_downs"] = true
	out["los"] = downs.los
	out["down"] = downs.down
	out["offense"] = downs.offense_team
	return out

static func _yd(y: float) -> String:
	return ("%d" % roundi(y)) if absf(y - roundf(y)) < 0.05 else ("%.1f" % y)

## HUD line. Flag only (play still on): "FLAG · ILLEGAL MAN DOWNFIELD · OFFENSE".
## Enforced: "... · 10 YD · REPLAY 2ND DOWN" (half the distance and tries say so).
## Declined: "... · DECLINED". `result` is enforce()'s return plus optional "try"/"declined".
static func ruling(p: Dictionary, result := {}) -> String:
	var parts := ["FLAG", name_of(p), "OFFENSE" if p.get("offense", true) else "DEFENSE"]
	if result.get("declined", false):
		parts.append("DECLINED")
	elif result.has("yards"):
		var yd := "%s YD" % _yd(float(result["yards"]))
		if result.get("half_distance", false):
			yd += ", HALF THE DISTANCE"
		parts.append("SPOT FOUL" if p.get("type") == INTENTIONAL_GROUNDING else yd)
		if result.get("try", false):
			parts.append("REPLAY TRY")
		elif result.get("turnover_on_downs", false):
			parts.append("TURNOVER ON DOWNS")
		elif result.get("first_down", false):
			parts.append("FIRST DOWN")
		elif p.get("replay", true) and not p.get("loss_of_down", false):
			parts.append("REPLAY %s DOWN" % ["1ST", "2ND", "3RD", "4TH"][clampi(int(result.get("down", 1)) - 1, 0, 3)])
		else:
			parts.append("LOSS OF DOWN")
	return " · ".join(parts)
