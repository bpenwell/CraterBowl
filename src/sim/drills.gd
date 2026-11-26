extends RefCounted
## Practice drills + the training ground. Build their own athletes, score reps,
## reset. Pure (file IO only for personal bests, like leaderboard.gd).
##
## Training kinds (docs/features/training.md):
##   hub       - training ground: free roam with a ball, 3 portals to the stations below.
##               Also the waiting lobby while queued for an online match.
##   blocking  - you're the center: keep the bot QB clean for the pocket clock.
##   catching  - jugs-style: a bot QB throws your route; race to 15 catches.
##   field     - practice field: throwing targets + a timed 40-yard dash lane.
## Classic drills: passing, tackling, scrimmage.

const Athlete := preload("res://src/sim/athlete.gd")
const Routes := preload("res://src/sim/routes.gd")
const T := preload("res://src/sim/tuning.gd")
const R := Athlete.Role
const KINDS := ["passing", "catching", "tackling", "blocking", "field", "hub", "scrimmage"]
## The three stations reachable from the training ground (portal order, left to right).
const STATIONS := ["blocking", "field", "catching"]
const TITLES := {"hub": "TRAINING GROUND", "blocking": "BLOCKING", "catching": "CATCHING",
	"field": "PRACTICE FIELD", "passing": "PASSING", "tackling": "TACKLING", "scrimmage": "SCRIMMAGE"}
const REP_PAUSE := 1.2
const TACKLE_TIMEOUT := 6.0
const LOS := 30.0
const SNAP_DELAY := 1.8          # blocking/catching auto-snap after this long presnap
const LEVEL_EVERY := 3           # streak reps per level-up (blocking, catching)
const MAX_LEVEL := 3
const POCKET_TIME := [3.0, 3.4, 3.8]          # blocking: seconds the QB must stay clean, per level
const CB_CUSHION := [10.0, 6.0, 2.0]          # catching: corner's depth off you, per level
const CATCH_RACE := 15
const CATCH_ROUTES := ["SLANT", "CURL", "OUT", "IN", "POST", "CORNER", "GO"]
const RESPAWN := 0.7             # field/hub: ball back in your hands after it lands
const TARGETS := [               # field: offsets from (center x, LOS) in yards
	{"dx": -12.0, "dy": 12.0, "r": 3.5, "pts": 1, "name": "SHORT"},
	{"dx": 10.0, "dy": 22.0, "r": 3.0, "pts": 2, "name": "MID"},
	{"dx": -2.0, "dy": 38.0, "r": 3.0, "pts": 3, "name": "DEEP"},
]
const BULLSEYE := 1.2            # inner radius for +1
const DASH_X := 47.0             # field: 40-yard dash lane centre x
const DASH_HALF_W := 3.0
const DASH_START := 26.0
const DASH_LEN := 40.0
const PORTAL_Y := 58.0           # hub: portals in a row across midfield
const PORTAL_DX := 15.0
const PORTAL_R := 2.6
const HUB_SPAWN_Y := 40.0
const EXIT_PORTAL := Vector2(3.5, 29.0)   # stations: walk in to return to the training ground (left sideline)
const EXIT_R := 1.8
const DEFAULT_BESTS_PATH := "user://training.json"

var kind := "passing"
var me := -1
var reps := 0
var successes := 0
var streak := 0
var best_streak := 0
var rep_over := false
var level := 1
var portal := ""                 # hub: station the player just walked into (main switches)
var banners: Array = []          # [title, sub, kind] for the overlay; main drains it
var bests := {}                  # persistent personal bests
var bests_path := ""
var last_result := ""            # short line about the previous rep
# blocking
var sacks := 0
var blocks_made := 0
var _qb := -1
var _blockers: Array = []        # bot OL ids (benched until their level)
var _rushers: Array = []         # DL ids
# catching
var session_t := 0.0
var race_done := 0
var route := ""
# field
var throws := 0
var hits := 0
var points := 0
var dash_t := -1.0               # running time, <0 = not running
var dash_last := -1.0
# internals
var _pause := 0.0
var _presnap := 0.0
var _play_i := 0
var _carrier := -1
var _prev := Vector2.ZERO
var _cross_at := Vector2.INF     # field: where the pass came down through catch height

static func valid(k: String) -> bool:
	return KINDS.has(k)

static func is_training(k: String) -> bool:
	return k == "hub" or STATIONS.has(k)

## Portal centres (hub), in STATIONS order.
static func portal_positions(field) -> Array:
	var cx: float = field.width / 2.0
	return [Vector2(cx - PORTAL_DX, PORTAL_Y), Vector2(cx, PORTAL_Y), Vector2(cx + PORTAL_DX, PORTAL_Y)]

## Throwing targets (field) as [{pos, r, pts, name}].
static func target_list(field) -> Array:
	var cx: float = field.width / 2.0
	var out := []
	for t in TARGETS:
		out.append({"pos": Vector2(cx + t["dx"], LOS + t["dy"]), "r": t["r"], "pts": t["pts"], "name": t["name"]})
	return out

static func dash_lane(field) -> Dictionary:
	return {"x": minf(DASH_X, field.width - DASH_HALF_W - 0.5), "half_w": DASH_HALF_W, "start": DASH_START, "finish": DASH_START + DASH_LEN}

## Add this drill's athletes to an empty World and return the human athlete id.
func build(world, k: String) -> int:
	kind = k if valid(k) else "passing"
	var cx: float = world.field.width / 2.0
	match kind:
		"passing":
			var qb = world.add_two_way(0, R.QB, cx, R.LB, cx)
			world.add_two_way(0, R.WR, cx - 18.0, R.CB, cx - 18.0)
			world.add_two_way(0, R.WR, cx + 18.0, R.CB, cx + 18.0)
			world.add_two_way(0, R.RB, cx + 4.0, R.S, cx)
			me = qb.id
		"catching":
			_qb = world.add_two_way(0, R.QB, cx, R.LB, cx).id
			var wr = world.add_two_way(0, R.WR, cx - 14.0, R.CB, cx - 14.0)
			world.add_two_way(1, R.WR, cx - 14.0, R.CB, cx - 14.0)
			me = wr.id
		"tackling":
			var rb = world.add_two_way(0, R.RB, cx, R.S, cx)
			var lb = world.add_two_way(1, R.QB, cx, R.LB, cx)
			_carrier = rb.id
			me = lb.id
		"blocking":
			me = world.add_two_way(0, R.C, cx, R.DL, cx).id
			_qb = world.add_two_way(0, R.QB, cx, R.LB, cx).id
			for dx in [-3.0, 3.0]:
				_blockers.append(world.add_two_way(0, R.OL, cx + dx, R.DL, cx + dx).id)
			for dx in [0.0, -3.0, 3.0]:
				_rushers.append(world.add_two_way(1, R.OL, cx + dx, R.DL, cx + dx).id)
		"field", "hub":
			me = world.add_two_way(0, R.QB, cx, R.LB, cx).id
		"scrimmage":
			return -1   # caller builds a full roster
	return me

func start_rep(world) -> void:
	rep_over = false
	_pause = 0.0
	_presnap = 0.0
	portal = ""
	match kind:
		"passing":
			world.setup_formation(LOS)
			world.call_play(Routes.PLAY_NAMES[_play_i % Routes.PLAY_NAMES.size()])
			_play_i += 1
		"catching":
			world.setup_formation(LOS)
			world.call_play("Curls")
			route = CATCH_ROUTES[_play_i % CATCH_ROUTES.size()]
			world.route_of = {me: route}
			var m = world.get_athlete(me)
			var cb = world.find_role(1, R.CB)
			if cb:
				cb.position = Vector2(m.position.x + 1.0, LOS + CB_CUSHION[level - 1])
			_play_i += 1
		"tackling":
			world.setup_formation(LOS)
			var rb = world.get_athlete(_carrier)
			rb.position = Vector2(world.field.width / 2.0 + (4.0 if _play_i % 2 == 0 else -4.0), LOS - 2.0)
			world.get_athlete(me).position = Vector2(world.field.width / 2.0, LOS + 10.0)
			_play_i += 1
			world.start_live_with(_carrier)
		"blocking":
			world.setup_formation(LOS)
			_place_blocking(world)
			_play_i += 1
		"field", "hub":
			_targets = target_list(world.field)
			world.setup_formation(LOS)
			var a = world.get_athlete(me)
			a.position = Vector2(world.field.width / 2.0, HUB_SPAWN_Y if kind == "hub" else LOS)
			_relive(world)

## Blocking: active rushers/blockers line up; the rest wait on the sideline.
func _place_blocking(world) -> void:
	var cx: float = world.field.width / 2.0
	var n_rush := level
	var n_block := level - 1
	var side := 1.0 if _play_i % 2 == 0 else -1.0
	var bench_x: float = world.field.width - 1.0
	for i in _rushers.size():
		var a = world.get_athlete(_rushers[i])
		if i < n_rush:
			var x: float = cx + side * 1.5 if n_rush == 1 else cx + float([0.0, -3.5, 3.5][i])
			a.position = Vector2(x, LOS + 1.0)
		else:
			a.position = Vector2(bench_x, LOS + 6.0 + i * 1.6)
	for i in _blockers.size():
		var b = world.get_athlete(_blockers[i])
		if i < n_block:
			b.position = Vector2(cx + [-3.0, 3.0][i], LOS - 1.0)
		else:
			b.position = Vector2(bench_x, LOS - 6.0 - i * 1.6)

func _active(id: int) -> bool:
	var i := _rushers.find(id)
	if i >= 0:
		return i < level
	i = _blockers.find(id)
	if i >= 0:
		return i < level - 1
	return true

## Field/hub: ball back in your hands, live, throwable from anywhere.
func _relive(world) -> void:
	var a = world.get_athlete(me)
	var f = world.field
	a.position = Vector2(clampf(a.position.x, 1.0, f.width - 1.0), clampf(a.position.y, 1.0, f.length - 1.0))
	a.reset_state()
	world.start_live_with(me)
	world.los_y = f.length + f.endzone_depth + 10.0   # throws allowed anywhere
	world.forward_pass_thrown = false
	rep_over = false
	_pause = 0.0
	_cross_at = Vector2.INF

## Drills overwrite bot inputs after the AI thinks (benched athletes stand still).
func override_inputs(world, inputs: Dictionary) -> void:
	if kind != "blocking":
		return
	for id in _rushers + _blockers:
		if not _active(id):
			inputs[id] = {"dir": Vector2.ZERO, "sprint": false}
	# The QB never scrambles: he sets up and drifts in the pocket.
	if world.phase == world.Phase.LIVE and inputs.has(_qb):
		var d: Vector2 = inputs[_qb].get("dir", Vector2.ZERO)
		inputs[_qb] = {"dir": Vector2(d.x, minf(d.y, 0.0)) * 0.6, "sprint": false}

func _score(ok: bool) -> void:
	if rep_over:
		return
	rep_over = true
	reps += 1
	if ok:
		successes += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
	else:
		streak = 0
	if kind == "blocking" or kind == "catching":
		var new_level := mini(MAX_LEVEL, 1 + streak / LEVEL_EVERY)
		if not ok:
			new_level = maxi(1, level - 1)
		if new_level > level:
			_banner("LEVEL %d" % new_level, _level_text(new_level), "up")
		level = new_level
		_best_max("%s_streak" % kind, best_streak)

func _level_text(l: int) -> String:
	if kind == "blocking":
		return "%d RUSHER%s · %.1fs POCKET" % [l, "" if l == 1 else "S", POCKET_TIME[l - 1]]
	return ["SOFT COVERAGE", "TIGHT COVERAGE", "PRESS COVERAGE"][l - 1]

func _banner(title: String, sub: String, k: String = "info") -> void:
	banners.append([title, sub, k])

## Feed every World event.
func on_event(n: String, d: Dictionary) -> void:
	match kind:
		"passing":
			if n == "catch":
				_score(true)
			elif n in ["incomplete", "interception", "tackle", "out_of_bounds"]:
				_score(false)
		"catching":
			if n == "catch" and d.get("by", -1) == me:
				_score(true)
				last_result = "CAUGHT %s" % route
				if successes - race_done * CATCH_RACE >= CATCH_RACE:
					_finish_race()
			elif n in ["incomplete", "interception", "catch", "tackle", "out_of_bounds"]:
				if not rep_over:
					last_result = {"interception": "PICKED OFF", "catch": "CORNER WON IT"}.get(n, "DROPPED / MISSED")
					_banner(last_result, "", "miss")
				_score(false)
		"tackling":
			if n == "tackle":
				_score(true)
			elif n in ["touchdown", "out_of_bounds", "fumble"]:
				_score(n == "fumble")
		"blocking":
			if n == "block" and d.get("blocker", -1) == me:
				blocks_made += 1
			elif n in ["tackle", "fumble"] and not rep_over:
				sacks += 1
				last_result = "SACKED"
				_banner("SACKED", "STAY BETWEEN HIM AND THE QB", "miss")
				_score(false)
			elif n == "pocket_clean":
				last_result = "CLEAN POCKET"
				_banner("CLEAN POCKET", "+1  ·  STREAK %d" % (streak + 1), "good")
				_score(true)
		"field", "hub":
			if n == "throw":
				throws += 1 if kind == "field" else 0
			elif n == "incomplete" and kind == "field":
				# Score where a receiver's hands would be (the aim point), not the bounce spot.
				_score_throw(_cross_at if _cross_at != Vector2.INF else d.get("at", Vector2.INF))
			if n in ["incomplete", "touchdown", "out_of_bounds", "tackle", "catch"]:
				rep_over = true
				_pause = 0.0

func _score_throw(at: Vector2) -> void:
	if at == Vector2.INF:
		return
	var best_pts := 0
	var label := ""
	var bull := false
	for t in _targets:
		var dist: float = at.distance_to(t["pos"])
		if dist <= t["r"] and t["pts"] > best_pts:
			best_pts = t["pts"]
			label = t["name"]
			bull = dist <= BULLSEYE
	if best_pts == 0:
		last_result = "MISS"
		return
	var gained := best_pts + (1 if bull else 0)
	hits += 1
	points += gained
	last_result = "%s +%d" % [label, gained]
	_banner("BULLSEYE" if bull else "%s TARGET" % label, "+%d  ·  %d PTS" % [gained, points], "good")
	_best_max("field_points", points)

var _targets: Array = []

func _finish_race() -> void:
	race_done += 1
	var t := session_t
	var prev := float(bests.get("catch_race_time", 0.0))
	var is_best := prev <= 0.0 or t < prev
	if is_best:
		bests["catch_race_time"] = t
		save_bests()
	_banner("%d CATCHES · %s" % [CATCH_RACE, clock_text(t)], "NEW PERSONAL BEST" if is_best else "BEST %s" % clock_text(prev), "good")
	session_t = 0.0

static func clock_text(t: float) -> String:
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]

## Returns true when the rep should be reset now (main then calls start_rep).
func tick(world, dt: float) -> bool:
	if STATIONS.has(kind) and world.get_athlete(me).position.distance_to(EXIT_PORTAL) <= EXIT_R:
		portal = "hub"
	match kind:
		"scrimmage":
			return false
		"field", "hub":
			_tick_field(world, dt)
			return false
	if kind == "catching" and (reps > race_done * CATCH_RACE or world.phase != world.Phase.PRESNAP):
		session_t += dt   # the race clock starts at your first snap
	if (kind == "blocking" or kind == "catching") and world.phase == world.Phase.PRESNAP:
		_presnap += dt
		if _presnap >= SNAP_DELAY:
			world.snap()
	if kind == "tackling" and not rep_over and world.phase == world.Phase.LIVE and world.play_time >= TACKLE_TIMEOUT:
		_score(false)
	if kind == "blocking" and not rep_over and world.phase == world.Phase.LIVE and world.play_time >= POCKET_TIME[level - 1]:
		var qb = world.get_athlete(_qb)
		if world.ball.is_held_by(_qb) and qb != null:
			world._whistle("pocket_clean", {"carrier": _qb, "team": qb.team})
	if rep_over:
		_pause += dt
		return _pause >= REP_PAUSE
	return false

func _tick_field(world, dt: float) -> void:
	var a = world.get_athlete(me)
	var b = world.ball
	if b.state == b.State.IN_FLIGHT and b.velocity.z < 0.0 and b.position.z <= T.CATCH_HEIGHT and _cross_at == Vector2.INF:
		_cross_at = Vector2(b.position.x, b.position.y)
	if kind == "hub":
		var ps := portal_positions(world.field)
		for i in ps.size():
			if a.position.distance_to(ps[i]) <= PORTAL_R:
				portal = STATIONS[i]
	else:
		_tick_dash(world.field, a.position, dt)
	_prev = a.position
	if rep_over or world.phase != world.Phase.LIVE:
		_pause += dt
		if _pause >= RESPAWN and world.ball.state != world.ball.State.IN_FLIGHT:
			_relive(world)

func _tick_dash(field, p: Vector2, dt: float) -> void:
	var lane := dash_lane(field)
	var in_lane: bool = absf(p.x - lane["x"]) <= lane["half_w"]
	if dash_t >= 0.0:
		dash_t += dt
		if not in_lane or p.y < lane["start"] - 0.5:
			dash_t = -1.0   # left the lane: run cancelled
		elif _prev.y < lane["finish"] and p.y >= lane["finish"]:
			# interpolate the crossing inside this tick
			var f: float = (lane["finish"] - _prev.y) / maxf(p.y - _prev.y, 0.0001)
			var t := dash_t - dt * (1.0 - f)
			dash_last = t
			dash_t = -1.0
			var prev := float(bests.get("dash_40", 0.0))
			var is_best := prev <= 0.0 or t < prev
			if is_best:
				bests["dash_40"] = t
				save_bests()
			last_result = "40 YD %.2fs" % t
			_banner("40 YD  %.2fs" % t, "NEW PERSONAL BEST" if is_best else "BEST %.2fs" % prev, "good" if is_best else "info")
	elif in_lane and _prev.y < lane["start"] and p.y >= lane["start"] and _prev != Vector2.ZERO:
		var f: float = (p.y - lane["start"]) / maxf(p.y - _prev.y, 0.0001)
		dash_t = dt * f

# --- persistence --------------------------------------------------------------

func _best_max(key: String, v) -> void:
	if float(v) > float(bests.get(key, 0)):
		bests[key] = v
		save_bests()

func load_bests(path: String) -> void:
	bests_path = path
	bests = {}
	if path == "" or not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		bests = d

func save_bests() -> void:
	if bests_path == "":
		return
	var f := FileAccess.open(bests_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(bests))

# --- text for the HUD / overlay ------------------------------------------------

func title() -> String:
	return TITLES.get(kind, "PRACTICE")

## One-line drill status (scorebug + legacy text HUD).
func label() -> String:
	match kind:
		"scrimmage":
			return "PRACTICE: Scrimmage vs bots (no clock)"
		"hub":
			return "FREE ROAM"
		"blocking":
			return "BLOCKING L%d  %d/%d  STREAK %d (BEST %d)" % [level, successes, reps, streak, best_streak]
		"catching":
			return "CATCHING L%d  %d/%d  RACE %d/%d  %s" % [level, successes, reps, successes - race_done * CATCH_RACE, CATCH_RACE, clock_text(session_t)]
		"field":
			return "PRACTICE FIELD  %d PTS  %d/%d HITS%s" % [points, hits, throws, ("  40YD %.2fs" % dash_last) if dash_last > 0.0 else ""]
	return "PRACTICE: %s drill  %d/%d  streak %d (best %d)" % [kind.capitalize(), successes, reps, streak, best_streak]

## Coaching card: [title, body].
func card() -> Array:
	match kind:
		"hub":
			return ["PICK A STATION", "WALK INTO ITS PORTAL\nPRESS BACKSPACE AT ANY STATION TO COME BACK HERE"]
		"blocking":
			return ["BLOCKING · LEVEL %d" % level, "KEEP THE QB CLEAN FOR %.1fs\nFACE THE RUSHER AND RAISE YOUR SHIELD\nA BLOCK HOLDS 1.5s, THEN RE-FIT" % POCKET_TIME[level - 1]]
		"catching":
			return ["CATCHING · LEVEL %d" % level, "YOUR ROUTE  %s\nRUN IT, THEN BEAT THE CORNER TO THE BALL\nRACE TO %d CATCHES%s" % [route, CATCH_RACE,
				("  ·  BEST %s" % clock_text(float(bests["catch_race_time"]))) if bests.has("catch_race_time") else ""]]
		"field":
			return ["PRACTICE FIELD", "THROW AT THE RINGS: 1 · 2 · 3 PTS (+1 BULLSEYE)\nSPRINT THE 40 YD LANE ON THE RIGHT%s" % (("\nBEST 40  %.2fs" % float(bests["dash_40"])) if bests.has("dash_40") else "")]
	return ["DRILL", label()]

func status(world) -> String:
	match kind:
		"blocking", "catching":
			if world.phase == world.Phase.PRESNAP:
				return "SNAP IN %.1f  ·  SPACE TO SNAP NOW" % maxf(0.0, SNAP_DELAY - _presnap)
			if kind == "blocking" and world.phase == world.Phase.LIVE and not rep_over:
				return "POCKET  %.1f" % maxf(0.0, POCKET_TIME[level - 1] - world.play_time)
			return last_result
		"field":
			if dash_t >= 0.0:
				return "40 YD  %.2f" % dash_t
			return last_result
	return ""

func hints() -> String:
	match kind:
		"hub":
			return "MOVE  WASD  ·  SPRINT  SHIFT  ·  THROW  HOLD J OR LEFT CLICK"
		"blocking":
			return "MOVE  WASD  ·  FACE THE RUSHER TO BLOCK  ·  SNAP  SPACE  ·  TRAINING GROUND  BACKSPACE"
		"catching":
			return "RUN YOUR ROUTE  WASD  ·  SPRINT  SHIFT  ·  SNAP  SPACE  ·  TRAINING GROUND  BACKSPACE"
		"field":
			return "AIM + CHARGE  HOLD J OR LEFT CLICK  ·  LOB  CTRL  ·  SPRINT  SHIFT  ·  TRAINING GROUND  BACKSPACE"
	return ""
