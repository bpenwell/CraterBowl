extends RefCounted
## Queue rules (pure). Players: {id, mode, size, rating, since}.

const CASUAL_WAIT := 8.0
const COMP_WAIT := 15.0
const BASE_WINDOW := 100.0
const WINDOW_GROWTH := 25.0   # rating points per second waited
const MAX_WINDOW := 600.0
const MODES := ["casual", "competitive"]
const GAMES := ["classic", "chaosball"]

var queue: Array = []

## party: shared code among friends ("" = solo); party_size: members expected.
## seat: the client's random per-queue token; the host seats players by it, never by display
## name, because two players can share a name (#59). "" = an older client that sent none.
func enqueue(id: int, mode: String, size: int, rating: float, now: float, name: String = "", party: String = "", party_size: int = 1, game: String = "classic", seat: String = "") -> bool:
	if not GAMES.has(game):
		return false
	if game == "chaosball":
		size = 3   # Chaosball is always 3v3
	if not MODES.has(mode) or not [3, 5, 7].has(size):
		return false
	if party != "" and (party_size < 2 or party_size > size):
		return false   # a party must fit on one team
	dequeue(id)
	queue.append({"id": id, "mode": mode, "size": size, "rating": rating, "since": now,
		"name": name if name != "" else "P%d" % id, "party": party, "party_size": party_size if party != "" else 1, "game": game, "seat": seat})
	return true

func dequeue(id: int) -> void:
	for i in range(queue.size() - 1, -1, -1):
		if queue[i]["id"] == id:
			queue.remove_at(i)

static func window_for(waited: float) -> float:
	return minf(BASE_WINDOW + WINDOW_GROWTH * waited, MAX_WINDOW)

## Form as many matches as the rules allow at time `now`.
func tick(now: float) -> Array:
	var out := []
	var formed := true
	while formed:
		formed = false
		for game in GAMES:
			for mode in MODES:
				for size in [3, 5, 7]:
					var m := _try_form(mode, size, now, game)
					if not m.is_empty():
						out.append(m)
						for p in m["players"]:
							dequeue(p)
						formed = true
	return out

func _group(mode: String, size: int, game: String = "classic") -> Array:
	var g := []
	for e in queue:
		if e["mode"] == mode and e["size"] == size and e.get("game", "classic") == game:
			g.append(e)
	g.sort_custom(func(a, b): return a["since"] < b["since"])
	return g

## Matchable units: solo players, and parties once every member has queued.
func _units(mode: String, size: int, game: String = "classic") -> Array:
	var by_key := {}
	for e in _group(mode, size, game):
		var key: String = e["party"] if e["party"] != "" else "solo:%d" % e["id"]
		if not by_key.has(key):
			by_key[key] = []
		by_key[key].append(e)
	var units := []
	for key in by_key:
		var members: Array = by_key[key]
		if members.size() < int(members[0]["party_size"]):
			continue   # party still assembling
		var r := 0.0
		var since := INF
		for m in members:
			r += m["rating"]
			since = minf(since, m["since"])
		units.append({"members": members, "rating": r / members.size(), "since": since})
	units.sort_custom(func(a, b): return a["since"] < b["since"])
	return units

func _try_form(mode: String, size: int, now: float, game: String = "classic") -> Dictionary:
	var units := _units(mode, size, game)
	if units.is_empty():
		return {}
	var full := size * 2
	var oldest: Dictionary = units[0]
	var waited: float = now - oldest["since"]
	var pool := units
	if mode == "competitive":
		var w := window_for(waited)
		pool = units.filter(func(u): return absf(u["rating"] - oldest["rating"]) <= w)
		pool.sort_custom(func(a, b): return absf(a["rating"] - oldest["rating"]) < absf(b["rating"] - oldest["rating"]))
	var picked := []
	var count := 0
	for u in pool:
		if count + u["members"].size() <= full:
			picked.append(u)
			count += u["members"].size()
	var wait_needed := CASUAL_WAIT if mode == "casual" else COMP_WAIT
	if count < full and not (waited >= wait_needed and count >= 2):
		return {}
	var ids := []
	var entries := []   # the queue entries, so a failed host's match can re-queue them (#303)
	var host := -1
	for u in picked:
		for m in u["members"]:
			ids.append(m["id"])
			entries.append(m)
	host = oldest["members"][0]["id"]
	var teams := unit_teams(picked, size)
	# team_seats: seat token -> team (what the host seats by). team_names: name -> team, kept for
	# older hosts and seat-less clients; a name two players share is left out (ambiguous).
	var team_seats := {}
	var team_names := {}
	var dup_names := {}
	for u in picked:
		for m in u["members"]:
			if str(m.get("seat", "")) != "":
				team_seats[m["seat"]] = teams[m["id"]]
			if team_names.has(m["name"]):
				dup_names[m["name"]] = true
			team_names[m["name"]] = teams[m["id"]]
	for n in dup_names:
		team_names.erase(n)
	return {"mode": mode, "size": size, "game": game, "players": ids, "host": host, "teams": teams,
		"team_names": team_names, "team_seats": team_seats, "entries": entries}

## #303: put players from a match that fell through back in the queue. They keep their original
## `since`, so they are the oldest in their group and the next tick re-forms them first (a casual
## group already past CASUAL_WAIT matches at once). A party that lost members (the failed host was
## one of them) shrinks to who came back; a lone survivor queues solo.
func requeue(entries: Array) -> void:
	var party_left := {}
	for e in entries:
		if e["party"] != "":
			party_left[e["party"]] = party_left.get(e["party"], 0) + 1
	for e in entries:
		var back: Dictionary = e.duplicate()
		if back["party"] != "":
			back["party_size"] = party_left[back["party"]]
			if back["party_size"] < 2:
				back["party"] = ""
		dequeue(back["id"])
		queue.append(back)

## Host side: the team the matchmaker drafted a player onto, by seat token first, then by
## display name for older clients that sent no token. -1 = unknown (auto-assign).
static func drafted_team(seat: String, name: String, seats: Dictionary, names: Dictionary) -> int:
	if seat != "" and seats.has(seat):
		return int(seats[seat])
	if names.has(name):
		return int(names[name])
	return -1

## Team split that keeps parties together: biggest units first, each onto the team
## with fewer players (tie: lower rating total), never over `size`.
static func unit_teams(units: Array, size: int) -> Dictionary:
	var order := units.duplicate()
	order.sort_custom(func(a, b): return a["members"].size() > b["members"].size() or (a["members"].size() == b["members"].size() and a["rating"] > b["rating"]))
	var n := [0, 0]
	var sum := [0.0, 0.0]
	var teams := {}
	for u in order:
		var k: int = u["members"].size()
		var t := 0 if (n[0] < n[1] or (n[0] == n[1] and sum[0] <= sum[1])) else 1
		if n[t] + k > size:
			t = 1 - t
		for m in u["members"]:
			teams[m["id"]] = t
		n[t] += k
		sum[t] += u["rating"] * k
	return teams
