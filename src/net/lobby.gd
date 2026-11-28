extends RefCounted
## Private match lobby state. Pure; server-authoritative, mirrored to clients.

enum Phase { LOBBY, IN_GAME }
const SIZES := [3, 5, 7]
## #130: every match plays four quarters; the host picks only their length. 2.5 min keeps a
## game at the 10 minutes the old two 5-min halves ran. `quarters` stays in the dict (always
## true) so a pre-#130 client still reads the format right.
const QUARTER_MINUTES := [1.0, 2.0, 2.5, 3.0]
const DEFAULT_QUARTER_MINUTES := 2.5
const MatchConfig := preload("res://src/sim/match_config.gd")

var phase: Phase = Phase.LOBBY
var host_id := 1
var code := ""
var settings := {"size": 7, "mode": "classic", "quarters": true, "quarter_minutes": DEFAULT_QUARTER_MINUTES,
	"pass_marker": true}
var players := {}   # id -> {"name": String, "ready": bool}
var expected := 0   # queue matches: auto-start only once this many players are present
var notice := ""    # host-facing: why the last settings change was refused ("" = none)

## Seats in a match of `size` (both teams' slots); defaults to the current setting.
func capacity(size: int = -1) -> int:
	return MatchConfig.get_config(settings["size"] if size < 0 else size)["slots"] * 2

func is_full() -> bool:
	return players.size() >= capacity()

## What a joiner turned away from a full lobby is told.
func full_reason() -> String:
	return "Lobby full: %dv%d seats %d players" % [settings["size"], settings["size"], capacity()]

func add(id: int, name: String = "") -> void:
	if not players.has(id):
		players[id] = {"name": name if name != "" else "Player %d" % (players.size() + 1), "ready": false}

func remove(id: int) -> void:
	players.erase(id)

func set_ready(id: int, ready: bool) -> bool:
	if phase != Phase.LOBBY or not players.has(id):
		return false
	players[id]["ready"] = ready
	return true

func toggle_ready(id: int) -> bool:
	return players.has(id) and set_ready(id, not players[id]["ready"])

func set_name(id: int, name: String) -> bool:
	if not players.has(id):
		return false
	var n := name.strip_edges().left(16)
	if n == "":
		return false
	players[id]["name"] = n
	return true

## Host-only, lobby-only, validated.
## Shrinking below the players already present is refused (nobody gets kicked); `notice` says why.
func set_setting(by: int, key: String, value) -> bool:
	if by != host_id or phase != Phase.LOBBY:
		return false
	var new_size: int = settings["size"]
	match key:
		"size":
			if not (value is int and SIZES.has(value)):
				return false
			new_size = value
		"quarter_minutes":
			if not valid_quarter_minutes(value):
				return false
			value = float(value)
		"pass_marker":
			if not (value is bool):
				return false
		"mode":
			if not (value is String and (value == "classic" or value == "chaosball")):
				return false
			if value == "chaosball":
				new_size = 3   # Chaosball is 3v3
		_:
			return false
	if players.size() > capacity(new_size):
		notice = "Can't switch to %s%dv%d: %d players here, %d seats. Someone has to leave first." % [
			"Chaosball " if key == "mode" and value == "chaosball" else "", new_size, new_size, players.size(), capacity(new_size)]
		return false
	notice = ""
	settings["size"] = new_size
	settings[key] = value
	for id in players:
		players[id]["ready"] = id == host_id and players[id]["ready"]   # settings changed: re-ready
	return true

func all_ready() -> bool:
	if players.size() < maxi(2, expected):
		return false
	for id in players:
		if not players[id]["ready"]:
			return false
	return true

func start() -> bool:
	if phase != Phase.LOBBY or not all_ready():
		return false
	phase = Phase.IN_GAME
	return true

func to_dict() -> Dictionary:
	return {"phase": phase, "host": host_id, "code": code, "settings": settings.duplicate(), "players": players.duplicate(true)}

func from_dict(d: Dictionary) -> void:
	phase = int(d.get("phase", 0))
	host_id = int(d.get("host", 1))
	code = str(d.get("code", ""))
	var s = d.get("settings", {})
	if s is Dictionary:
		# A pre-#130 host's halves settings ("quarters": false, "half_minutes") read as quarters.
		var qmin = s.get("quarter_minutes", DEFAULT_QUARTER_MINUTES)
		var marker = s.get("pass_marker", true)
		settings = {"size": int(s.get("size", 7)),
			"mode": "chaosball" if s.get("mode", "") == "chaosball" else "classic", "quarters": true,
			"quarter_minutes": float(qmin) if valid_quarter_minutes(qmin) else DEFAULT_QUARTER_MINUTES,
			"pass_marker": marker if marker is bool else true}
	var p = d.get("players", {})
	players = p if p is Dictionary else {}

func summary() -> String:
	var names := []
	for id in players:
		names.append("%s%s" % [players[id]["name"], " ✓" if players[id]["ready"] else ""])
	var mode_txt := "Chaosball " if settings.get("mode", "classic") == "chaosball" else ""
	return "%s%dv%d, %s-min quarters | Pass marker %s | %d/%d players | %s" % [mode_txt, settings["size"], settings["size"],
		String.num(settings["quarter_minutes"]), "on" if settings["pass_marker"] else "off",
		players.size(), capacity(), ", ".join(names)]

## A supported quarter length in minutes (int or float: 2 and 2.0 both count).
static func valid_quarter_minutes(value) -> bool:
	return (value is int or value is float) and QUARTER_MINUTES.has(float(value))
