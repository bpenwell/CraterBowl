extends RefCounted
## Ratings, tiers, seasons, season rewards. JSON-backed.

const DEFAULT_PATH := "user://ranked.json"
const START := 1000.0
const K := 32.0
const K_PROVISIONAL := 48.0
const PROVISIONAL_GAMES := 10
const TIERS := [[1900.0, "Legend"], [1700.0, "Diamond"], [1500.0, "Platinum"], [1300.0, "Gold"], [1100.0, "Silver"], [-INF, "Bronze"]]

var season := 0
## Records are keyed by `id_key(install id)` (#102) so two players who share a display name keep separate
## ratings. Peers that never sent an install id (older builds) still key by display name, as before.
var players := {}   # key -> {"rating", "peak", "games", "wins", "name"}
var rewards := {}   # key -> [reward ids]

const ID_PREFIX := "id:"   # display names are <= 16 chars, so "id:" + 16+ hex can't collide with one

static func id_key(install_id: String) -> String:
	return ID_PREFIX + install_id

## Carry a pre-#102 rating (keyed by display name) over to this player's install-id key, once.
## The first id-keyed player to claim a name takes its record; later same-named players start fresh.
func claim(key: String, name: String) -> void:
	if not key.begins_with(ID_PREFIX) or players.has(key) or name.begins_with(ID_PREFIX) or not players.has(name):
		return
	players[key] = players[name]
	players.erase(name)
	if rewards.has(name):
		rewards[key] = rewards[name]
		rewards.erase(name)

static func season_id(unix_time: float) -> int:
	var d := Time.get_datetime_dict_from_unix_time(int(unix_time))
	return int(d["year"]) * 4 + (int(d["month"]) - 1) / 3

static func tier(rating: float) -> String:
	for t in TIERS:
		if rating >= t[0]:
			return t[1]
	return "Bronze"

func get_player(name: String) -> Dictionary:
	if not players.has(name):
		players[name] = {"rating": START, "peak": START, "games": 0, "wins": 0}
	return players[name]

func rating(name: String) -> float:
	return float(get_player(name)["rating"])

## Roll to `new_season`: peak tier -> reward, soft reset halfway to START.
func ensure_season(new_season: int) -> void:
	if season == 0:
		season = new_season
		return
	if new_season == season:
		return
	for name in players:
		var p: Dictionary = players[name]
		if int(p["games"]) > 0:
			if not rewards.has(name):
				rewards[name] = []
			rewards[name].append("S%d-%s" % [season, tier(p["peak"])])
		p["rating"] = START + (float(p["rating"]) - START) * 0.5
		p["peak"] = p["rating"]
		p["games"] = 0
		p["wins"] = 0
	season = new_season

## Teams are lists of record keys. result_a: 1 win for team A, 0 loss, 0.5 tie. Returns {key: delta}.
## `names` (key -> display name) is stored on each record so the file stays readable.
func record_match(team_a: Array, team_b: Array, result_a: float, names: Dictionary = {}) -> Dictionary:
	if team_a.is_empty() or team_b.is_empty():
		return {}
	var avg := func(team): 
		var s := 0.0
		for n in team: s += rating(n)
		return s / team.size()
	var ra: float = avg.call(team_a)
	var rb: float = avg.call(team_b)
	var exp_a := 1.0 / (1.0 + pow(10.0, (rb - ra) / 400.0))
	var deltas := {}
	for side in [[team_a, result_a, exp_a], [team_b, 1.0 - result_a, 1.0 - exp_a]]:
		for n in side[0]:
			var p := get_player(n)
			var k := K_PROVISIONAL if int(p["games"]) < PROVISIONAL_GAMES else K
			var d: float = k * (side[1] - side[2])
			p["rating"] = float(p["rating"]) + d
			p["peak"] = maxf(float(p["peak"]), float(p["rating"]))
			p["games"] = int(p["games"]) + 1
			if side[1] > 0.5:
				p["wins"] = int(p["wins"]) + 1
			if names.has(n):
				p["name"] = str(names[n])
			deltas[n] = d
	return deltas

func save(path: String = DEFAULT_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"version": 1, "season": season, "players": players, "rewards": rewards}))
	return true

func load_file(path: String = DEFAULT_PATH) -> void:
	season = 0
	players = {}
	rewards = {}
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		season = int(d.get("season", 0))
		players = d.get("players", {}) if d.get("players") is Dictionary else {}
		rewards = d.get("rewards", {}) if d.get("rewards") is Dictionary else {}

func label(name: String) -> String:
	var p := get_player(name)
	return "%d %s (%d-%d)" % [int(round(p["rating"])), tier(p["rating"]), int(p["wins"]), int(p["games"]) - int(p["wins"])]
