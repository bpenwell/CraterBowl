extends RefCounted
## Cosmetic catalog, unlocks, XP, profile. No gameplay effect (view-only data). Pure + JSON store.

const DEFAULT_PATH := "user://profile.json"
const XP_PER_LEVEL := 500

## slot -> id -> {name, level?, color?}
const CATALOG := {
	"trim": {
		"white": {"name": "Chalk", "level": 1, "color": Color(0.95, 0.95, 0.95)},
		"black": {"name": "Ink", "level": 1, "color": Color(0.08, 0.08, 0.1)},
		"ember": {"name": "Ember", "level": 2, "color": Color(1.0, 0.35, 0.1)},
		"tide": {"name": "Tide", "level": 3, "color": Color(0.1, 0.6, 0.9)},
		"volt": {"name": "Volt", "level": 5, "color": Color(0.75, 1.0, 0.1)},
		"aurora": {"name": "Aurora", "level": 9, "color": Color(0.7, 0.3, 1.0)},
	},
	"helmet": {
		"plain": {"name": "Plain", "level": 1, "color": Color(0.85, 0.85, 0.85)},
		"gold": {"name": "Gold Stripe", "level": 3, "color": Color(1.0, 0.8, 0.2)},
		"crimson": {"name": "Crimson Stripe", "level": 4, "color": Color(0.8, 0.1, 0.15)},
		"chrome": {"name": "Chrome", "level": 7, "color": Color(0.8, 0.85, 0.95)},
	},
	"celebration": {
		"none": {"name": "None", "level": 1},
		"spin": {"name": "Spin", "level": 2},
		"hop": {"name": "Moon Hop", "level": 4},
		"flip": {"name": "Flip", "level": 6},
	},
	"badge": {
		"none": {"name": "None", "level": 1},
	},
}
const DEFAULT_LOOK := {"trim": "white", "helmet": "plain", "number": 1, "celebration": "none", "badge": "none"}

var xp := 0
var equipped := DEFAULT_LOOK.duplicate()
var season_rewards: Array = []   # e.g. ["S8100-Gold"] from ranked
var achievements: Array = []     # unlocked achievement ids
var games := 0                   # matches finished

## Players start at Level 1 (#125); each XP_PER_LEVEL adds one. CATALOG levels use the same scale.
func level() -> int:
	return xp / XP_PER_LEVEL + 1

## XP for one match from a Stats line (or {}) and whether your team won.
static func award_xp(line: Dictionary, won: bool) -> int:
	var g := func(f): return float(line.get(f, 0.0))
	var yds: float = g.call("pass_yds") + g.call("rec_yds") + g.call("rush_yds")
	var tds: float = g.call("pass_td") + g.call("rec_td") + g.call("rush_td")
	return int(100 + (50 if won else 0) + 25 * tds + floor(maxf(yds, 0.0) / 10.0)
		+ 10 * g.call("tkl") + 30 * g.call("int") + 20 * g.call("sack"))

func add_xp(amount: int) -> int:
	var before := level()
	xp += maxi(0, amount)
	return level() - before   # levels gained

static func is_badge(id: String) -> bool:
	return id.begins_with("S") and id.find("-") > 0

func is_unlocked(slot: String, id) -> bool:
	if slot == "number":
		return id is int and id >= 0 and id <= 99
	if slot == "badge" and is_badge(str(id)):
		return season_rewards.has(id)
	if not CATALOG.has(slot) or not CATALOG[slot].has(id):
		return false
	return level() >= int(CATALOG[slot][id]["level"])

func equip(slot: String, id) -> bool:
	if not DEFAULT_LOOK.has(slot) or not is_unlocked(slot, id):
		return false
	equipped[slot] = id
	return true

func unlocked(slot: String) -> Array:
	var out := []
	for id in CATALOG.get(slot, {}):
		if is_unlocked(slot, id):
			out.append(id)
	if slot == "badge":
		out += season_rewards
	return out

## Server side: keep only well-formed, known values (ownership is client-local; no gameplay effect).
static func sanitize_look(look) -> Dictionary:
	var out := DEFAULT_LOOK.duplicate()
	if not (look is Dictionary):
		return out
	for slot in ["trim", "helmet", "celebration"]:
		var v = look.get(slot, "")
		if v is String and CATALOG[slot].has(v):
			out[slot] = v
	var n = look.get("number", 1)
	if n is int or n is float:
		out["number"] = clampi(int(n), 0, 99)
	var b = look.get("badge", "none")
	if b is String and (b == "none" or (is_badge(b) and b.length() <= 24)):
		out["badge"] = b
	return out

static func color_of(slot: String, id: String) -> Color:
	return CATALOG.get(slot, {}).get(id, {}).get("color", Color.WHITE)

func save(path: String = DEFAULT_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"version": 1, "xp": xp, "equipped": equipped, "season_rewards": season_rewards,
		"achievements": achievements, "games": games}))
	return true

func load_file(path: String = DEFAULT_PATH) -> void:
	xp = 0
	equipped = DEFAULT_LOOK.duplicate()
	season_rewards = []
	achievements = []
	games = 0
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		xp = int(d.get("xp", 0))
		season_rewards = d.get("season_rewards", []) if d.get("season_rewards") is Array else []
		achievements = d.get("achievements", []) if d.get("achievements") is Array else []
		games = int(d.get("games", 0))
		var eq = sanitize_look(d.get("equipped", {}))
		eq["number"] = int(eq["number"])
		equipped = eq
