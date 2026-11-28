extends RefCounted
## Authoritative match simulation: athletes, ball, play phase.
## Deterministic and input-driven: step(inputs, dt) where inputs maps
## athlete id -> {"dir": Vector2, "sprint": bool}.

const T := preload("res://src/sim/tuning.gd")
const Tick := preload("res://src/sim/tick.gd")
const Field := preload("res://src/sim/field.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Ball := preload("res://src/sim/ball.gd")
const Passing := preload("res://src/sim/passing.gd")
const Routes := preload("res://src/sim/routes.gd")
const Emotes := preload("res://src/sim/emotes.gd")
const DefensivePlaybook := preload("res://src/sim/defensive_playbook.gd")
const Penalties := preload("res://src/sim/penalties.gd")

enum Phase { PRESNAP, LIVE, DEAD }

signal event(name: String, data: Dictionary)

var field := Field.new()
var ball := Ball.new()
var athletes: Array = []   # Array[Athlete]
var phase: Phase = Phase.DEAD
var offense_team := 0
var los_y := 25.0
var _snap_t := 0.0
var _snap_from := Vector3.ZERO
var _snap_to_id := -1
var forward_pass_thrown := false
var last_thrower_id := -1
var throw_origin := Vector2.ZERO
var dead_ball_spot := Vector2.ZERO
var last_possession := 0
var dead_ball_team := 0
var play_time := 0.0
var _impact_rolls := 0   # deterministic per-match counter for fumble rolls (no RNG in the sim)
# Forward progress (#98): contact window on the current carrier, in attack-direction yards.
var _fp_carrier := -1
var _fp_open := false
var _fp_best := 0.0      # furthest forward point reached during the window
var _fp_pushed := 0.0    # net yards opponents' bodies pushed the carrier back during the window
var _fp_grace := 0.0
var _fp_frame_push := 0.0
var play_name := "Verticals"
var run_flipped := false
var run_blocks := {}    # blocker id -> defender id (set at snap)
var handoff_cooldown := 0.0
var defensive_call := ""
var last_offensive_calls := ["", ""]
var last_defensive_calls := ["", ""]
var route_of := {}      # athlete_id -> route name (eligible offense receivers)
var route_paths := {}   # athlete_id -> Array[Vector2] absolute, set at snap
var ruleset := "classic"
var rules := {"gravity": 1.0, "anyone_throws": false, "self_catch": false, "max_bounces": 0, "walls": false}
var bounces := 0
var streak := 0          # Chaosball: completed teammate passes this possession
var hold_t := 0.0        # Chaosball: how long the current holder has had the ball
# Kicking (B09/C02). Kicks always travel +y (the kicking team is the world offense).
const KICK_CALLS := ["", "punt", "fg"]
var kick_play := ""      # "", "punt", "fg" (field goal or PAT), "kickoff"
var kick_locked := false # kickoff can't go yet (coin-toss choice pending)
var onside := false      # C27 mutator: kicking team keeps a kickoff it recovers past 10 yd (off by default)
var kicked := false      # the ball was kicked this play
var kick_live := false   # a kick is in the air
var kick_free := false   # kicked ball not yet possessed by anyone (and not blocked)
var kick_blocked := false
var kick_spot := Vector2.ZERO
var fair_catch_id := -1  # returner who signaled a fair catch on this kick (#189), else -1
var _kick_rest_t := 0.0
var flags: Array = []            # penalty records thrown this down (#253; Penalties.make)
var ball_crossed_los := false    # a runner took the ball past the LOS this down (#253, #312)

func _init() -> void:
	_impact_rolls = 0

## role/pos are for the athlete's current side. Optional two-way setup:
## off/def roles + x via set_two_way().
func set_ruleset(name: String) -> void:
	ruleset = name if name == "chaosball" else "classic"
	if ruleset == "chaosball":
		rules = {"gravity": T.CHAOS_GRAVITY_SCALE, "anyone_throws": true, "self_catch": true,
			"max_bounces": T.CHAOS_MAX_BOUNCES, "walls": true}
	else:
		rules = {"gravity": 1.0, "anyone_throws": false, "self_catch": false, "max_bounces": 0, "walls": false}

func gravity() -> float:
	return T.GRAVITY * rules["gravity"]

func is_chaos() -> bool:
	return ruleset == "chaosball"

func add_athlete(team: int, role: int, pos: Vector2) -> Athlete:
	var a := Athlete.new(athletes.size(), team, role, pos, field)
	athletes.append(a)
	return a

func add_two_way(team: int, off_role: int, off_x: float, def_role: int, def_x: float) -> Athlete:
	var a := add_athlete(team, off_role, Vector2(off_x, 0))
	a.off_role = off_role
	a.def_role = def_role
	a.off_x = off_x
	a.def_x = def_x
	a.set_side(team == offense_team)
	return a

func set_offense(team: int) -> void:
	offense_team = team
	for a in athletes:
		a.set_side(a.team == team)

func get_athlete(id: int) -> Athlete:
	return athletes[id] if id >= 0 and id < athletes.size() else null

func find_role(team: int, role: int) -> Athlete:
	for a in athletes:
		if a.team == team and a.role == role:
			return a
	return null

## Depth from the LOS per role (offense behind, defense ahead).
const FORMATION_DEPTH := {
	Athlete.Role.C: 0.5, Athlete.Role.OL: 1.0, Athlete.Role.WR: 1.0, Athlete.Role.QB: 5.0,
	Athlete.Role.RB: 6.0, Athlete.Role.DL: 1.0, Athlete.Role.LB: 5.0, Athlete.Role.CB: 2.0,
	Athlete.Role.S: 12.0,
}

## Offense attacks +y. Everyone returns to their home x at role depth; the C
## lines up at the field center with the ball.
func setup_formation(los: float) -> void:
	los_y = los
	play_time = 0.0
	var cx := field.width / 2.0
	for a in athletes:
		a.reset_state()
		a.set_lock = true   # everyone lines up set (#142): offense until the snap, defense non-DL until break_stance
		var depth: float = FORMATION_DEPTH.get(a.role, 1.0)
		var y := los - depth if a.team == offense_team else los + depth
		a.position = Vector2(a.home_x, y)
	var c := find_role(offense_team, Athlete.Role.C)
	var qb := find_role(offense_team, Athlete.Role.QB)
	if c:
		c.position.x = cx
	if qb:
		qb.position.x = cx
	if c:
		ball.hold(c.id)
	elif qb:
		ball.hold(qb.id)   # no center (3v3): QB starts with the ball
	forward_pass_thrown = false
	last_thrower_id = -1
	_snap_to_id = -1
	route_paths = {}
	run_blocks = {}
	handoff_cooldown = 0.0
	last_possession = offense_team
	streak = 0
	hold_t = 0.0
	call_play("Verticals")
	defensive_call = ""
	_reset_kick()
	phase = Phase.PRESNAP
	_sync_ball()

func _reset_kick() -> void:
	kick_play = ""
	kick_locked = false
	kicked = false
	kick_live = false
	kick_free = false
	kick_blocked = false
	fair_catch_id = -1
	_kick_rest_t = 0.0

## Fair catch (#189): a return-team athlete waves off the return while a punt or
## kickoff is in the air and untouched. One signal per kick. The signaler can't be
## blocked; if he catches it in the air the play is dead there (`fair_catch`).
func can_signal_fair_catch(id: int) -> bool:
	var a := get_athlete(id)
	return a != null and kick_in_air() and fair_catch_id < 0 and a.team != offense_team and a.can_act()

## A punt or kickoff still in the air and untouched. Any touch (a catch, a block)
## or landing changes the ball state, so this also holds on a client from snapshots.
func kick_in_air() -> bool:
	return phase == Phase.LIVE and kicked and ball.state == Ball.State.IN_FLIGHT and kick_play in ["punt", "kickoff"]

func signal_fair_catch(id: int) -> bool:
	if not can_signal_fair_catch(id):
		return false
	fair_catch_id = id
	event.emit("fair_catch_signal", {"by": id, "team": get_athlete(id).team})
	return true

func kicker() -> Athlete:
	return find_role(offense_team, Athlete.Role.QB)

## Presnap: offense calls a punt / field goal ("" = run a normal play). The kicker
## backs up to punt/hold depth and the return team drops a returner deep on punts.
func call_kick(kind: String) -> bool:
	if phase != Phase.PRESNAP or is_chaos() or not KICK_CALLS.has(kind) or kick_play == "kickoff":
		return false
	kick_play = kind
	var k := kicker()
	var c := find_role(offense_team, Athlete.Role.C)
	if k and c:   # 3v3 has no snapper: the QB kicks from where he stands
		var depth: float = {"punt": T.PUNT_DEPTH, "fg": T.FG_HOLD_DEPTH}.get(kind, FORMATION_DEPTH[Athlete.Role.QB])
		k.position = Vector2(field.width / 2.0, los_y - depth)
	var ret := returner()
	if ret:
		var deep: float = los_y + (T.PUNT_RETURNER_DEPTH if kind == "punt" else FORMATION_DEPTH.get(ret.role, 12.0))
		ret.position = Vector2(field.width / 2.0 if kind == "punt" else ret.home_x, minf(deep, field.length + field.endzone_depth * 0.5))
	_sync_ball()
	return true

## The return team's deep man: a safety, else a corner, else anyone.
func returner() -> Athlete:
	var best: Athlete = null
	for a in athletes:
		if a.team == offense_team:
			continue
		if best == null or _return_rank(a.role) > _return_rank(best.role) or (_return_rank(a.role) == _return_rank(best.role) and a.id < best.id):
			best = a
	return best

static func _return_rank(role: int) -> int:
	return {Athlete.Role.S: 3, Athlete.Role.CB: 2, Athlete.Role.LB: 1}.get(role, 0)

## Kickoff alignment: kicker on the tee at the LOS with the coverage spread
## beside him; the return team lines up 12+ yd off with a returner deep.
func setup_kickoff(los: float) -> void:
	setup_formation(los)
	kick_play = "kickoff"
	var cx := field.width / 2.0
	var k := kicker()
	var cover: Array = []
	var ret := returner()
	var front: Array = []
	for a in athletes:
		if a.team == offense_team and a != k:
			cover.append(a)
		elif a.team != offense_team and a != ret:
			front.append(a)
	# Front row + two deep returners (one deep man in 3v3).
	var ret2: Athlete = null
	if front.size() >= 3:
		front.sort_custom(func(p, q): return _return_rank(p.role) > _return_rank(q.role) or (_return_rank(p.role) == _return_rank(q.role) and p.id < q.id))
		ret2 = front.pop_front()
	cover.sort_custom(func(p, q): return p.home_x < q.home_x)
	front.sort_custom(func(p, q): return p.home_x < q.home_x)
	for i in cover.size():
		cover[i].position = Vector2(_spread(i, cover.size()), los - 1.0)
	for i in front.size():
		front[i].position = Vector2(_spread(i, front.size()), los + 12.0 + 6.0 * (i % 2))
	var deep := field.length * (1.0 - T.KICKOFF_RETURNER_DEPTH)
	if ret:
		ret.position = Vector2(cx if ret2 == null else cx - field.width * 0.15, deep)
	if ret2:
		ret2.position = Vector2(cx + field.width * 0.15, deep)
	if k:
		k.position = Vector2(cx, los - 3.0)
		ball.hold(k.id)
	_sync_ball()

func _spread(i: int, n: int) -> float:
	var margin := minf(4.0, field.width * 0.1)
	return lerpf(margin, field.width - margin, (i + 0.5) / float(n))

## Kick from the holder toward `target` (field plane) with meter power 0..1.
## Kickoff: from presnap (this starts the play). Punt/FG: live, behind the LOS.
func kick(id: int, target: Vector2, power: float) -> bool:
	var a := get_athlete(id)
	if a == null or kick_play == "" or kicked or not ball.is_held_by(id) or a.team != offense_team:
		return false
	if kick_play == "kickoff":
		if phase != Phase.PRESNAP or kick_locked:
			return false
		_go_live()
		play_time = 0.0
		event.emit("snap", {"qb": id})
	elif phase != Phase.LIVE or forward_pass_thrown or a.position.y > los_y:
		return false
	ball.state = Ball.State.IN_FLIGHT
	ball.holder_id = -1
	ball.position = Vector3(a.position.x, a.position.y, T.KICK_HEIGHT)
	ball.velocity = kick_velocity(kick_play, a.position, target, power)
	kicked = true
	kick_live = true
	kick_free = true
	kick_spot = a.position
	forward_pass_thrown = true   # no throws after a kick
	last_thrower_id = id
	last_possession = a.team
	throw_origin = a.position
	event.emit("kick", {"by": id, "kind": kick_play, "power": power, "target": target})
	return true

## Launch velocity of a kick: fixed angle per kind, speed from the meter, forward only.
static func kick_velocity(kind: String, from: Vector2, target: Vector2, power: float) -> Vector3:
	var dir := target - from
	dir = dir.normalized() if dir.length() > 0.01 else Vector2(0, 1)
	if dir.y < 0.2:   # kicks go forward
		dir = Vector2(signf(dir.x), 0.2).normalized()
	var ang := deg_to_rad(T.KICK_ANGLE.get(kind, 45.0))
	var speed := lerpf(T.KICK_SPEED_MIN, T.KICK_SPEED_MAX, clampf(power, 0.0, 1.0))
	return Vector3(dir.x * speed * cos(ang), dir.y * speed * cos(ang), speed * sin(ang))

## Kick speed needed to carry `dist` yd and be `h` yd high there (for bots).
static func kick_power_for(kind: String, dist: float, h: float, g: float) -> float:
	var ang := deg_to_rad(T.KICK_ANGLE[kind])
	var denom := 2.0 * cos(ang) * cos(ang) * (dist * tan(ang) - h)
	if denom <= 0.0:
		return 2.0
	var v := sqrt(g * dist * dist / denom)
	return (v - T.KICK_SPEED_MIN) / (T.KICK_SPEED_MAX - T.KICK_SPEED_MIN)

## Eligible receivers in playbook order: left WR, right WR, RB.
func receivers_in_order() -> Array:
	var wrs := []
	var rb = null
	for a in athletes:
		if a.team != offense_team:
			continue
		if a.role == Athlete.Role.WR:
			wrs.append(a)
		elif a.role == Athlete.Role.RB:
			rb = a
	wrs.sort_custom(func(p, q): return p.home_x < q.home_x)
	if rb:
		wrs.append(rb)
	return wrs

func has_run_back() -> bool:
	return not is_chaos() and find_role(offense_team, Athlete.Role.RB) != null

func available_plays() -> Array:
	return Routes.PLAY_NAMES + Routes.RUN_NAMES if has_run_back() else Routes.PLAY_NAMES

func is_run_play() -> bool:
	return Routes.RUN_PLAYS.has(play_name)

func call_play(name: String) -> bool:
	if not available_plays().has(name):
		return false
	play_name = name
	route_of = {}
	run_flipped = false
	if not is_run_play():
		var recv := receivers_in_order()
		var routes: Array = Routes.PLAYBOOK[name]
		for i in mini(recv.size(), routes.size()):
			route_of[recv[i].id] = routes[i]
	return true

func run_path() -> Array:
	return Routes.run_path(play_name, los_y, field.width, run_flipped)

## Match each lineman to a reachable defender, shading toward the called lane.
func run_block_assignments() -> Dictionary:
	var assignments := {}
	var lane: Vector2 = run_path()[0]
	for b in athletes:
		if b.team != offense_team or b.role not in [Athlete.Role.C, Athlete.Role.OL]:
			continue
		var landmark := Vector2(lerpf(b.position.x, lane.x, T.RUN_BLOCK_LANE_WEIGHT), los_y)
		var best := INF
		var target := -1
		for d in athletes:
			if d.team == offense_team or d.is_grounded() or assignments.values().has(d.id):
				continue
			if b.position.distance_to(d.position) > T.PROTECTION_RANGE:
				continue
			var distance: float = d.position.distance_squared_to(landmark)
			if distance < best:
				best = distance
				target = d.id
		if target >= 0:
			assignments[b.id] = target
	return assignments

func call_defense(id: String) -> bool:
	if phase != Phase.PRESNAP or is_chaos() or not DefensivePlaybook.CALLS.has(id):
		return false
	defensive_call = id
	return true

func protection_target(blocker: Athlete) -> Athlete:
	var best: Athlete = null
	var best_d := T.PROTECTION_RANGE
	for d in athletes:
		if d.team == offense_team or d.is_grounded():
			continue
		var dist: float = d.position.distance_to(blocker.position)
		if dist < best_d:
			best_d = dist
			best = d
	return best

func man_assignments() -> Dictionary:
	var assignments := {}
	var taken := {}
	for r in receivers_in_order():
		var best = null
		var best_d := INF
		for d in athletes:
			if d.team == offense_team or taken.has(d.id):
				continue
			if not (d.role == Athlete.Role.CB or d.role == Athlete.Role.S or d.role == Athlete.Role.LB):
				continue
			if d.role == Athlete.Role.LB and r.role != Athlete.Role.RB:
				continue   # LBs only take backs; they spy the QB otherwise
			var dist: float = d.position.distance_to(r.position)
			if dist < best_d:
				best_d = dist
				best = d
		if best:
			assignments[best.id] = r.id
			taken[best.id] = true
	return assignments

## Shared coverage landmarks in offense-frame yards. Man defenders use the AI's
## receiver matching. Line rushers keep their normal pursuit behavior.
func defense_assignment(a: Athlete) -> Dictionary:
	if a.team == offense_team or defensive_call.is_empty():
		return {}
	var call: Dictionary = DefensivePlaybook.CALLS[defensive_call]
	var cx := field.width * 0.5
	if a.role == Athlete.Role.DL or (call.family == DefensivePlaybook.Family.BLITZ and a.role == Athlete.Role.LB):
		return {"kind": "rush", "target": Vector2(cx, los_y - 5.0)}
	if call.family == DefensivePlaybook.Family.MAN and a.role != Athlete.Role.S:
		return {"kind": "man"}
	var deep := a.role == Athlete.Role.S or (defensive_call == "deep_zone" and a.role == Athlete.Role.CB)
	var deep_middle := false
	if defensive_call == "cover_3":
		var safety := find_role(a.team, Athlete.Role.S)
		deep_middle = a == safety if safety != null else a.role == Athlete.Role.LB
		deep = deep_middle or a.role == Athlete.Role.CB
	elif defensive_call == "cover_2" and athletes.size() < 14:
		deep = a.role == Athlete.Role.S or (a.role == Athlete.Role.CB and
			(a.home_x > cx or find_role(a.team, Athlete.Role.S) == null))
	var depth := T.DEFENSE_DEEP_DEPTH if deep else T.DEFENSE_UNDER_DEPTH
	if call.shell == DefensivePlaybook.Shell.GOAL_LINE:
		depth = T.DEFENSE_GOAL_DEPTH
	elif call.shell == DefensivePlaybook.Shell.PREVENT:
		depth = T.DEFENSE_PREVENT_DEPTH if deep else T.DEFENSE_DEEP_DEPTH
	var x := cx if deep_middle else lerpf(cx, a.home_x, 0.72)
	var y := minf(los_y + depth, field.length + field.endzone_depth * 0.5)
	return {"kind": "zone", "target": Vector2(x, y), "deep": deep}

func recall_call(team: int) -> bool:
	if phase != Phase.PRESNAP:
		return false
	if team == offense_team:
		return call_play(last_offensive_calls[team])
	return call_defense(last_defensive_calls[team])

## Mirror the play across the formation.
func flip_play() -> bool:
	if phase != Phase.PRESNAP:
		return false
	if is_run_play():
		run_flipped = not run_flipped
		return true
	var receivers := receivers_in_order()
	if receivers.size() < 2 or receivers[0].role != Athlete.Role.WR or receivers[1].role != Athlete.Role.WR:
		return false
	var left: int = receivers[0].id
	var right: int = receivers[1].id
	if not route_of.has(left) or not route_of.has(right):
		return false
	var route: String = route_of[left]
	route_of[left] = route_of[right]
	route_of[right] = route
	return true

func _record_calls() -> void:
	last_offensive_calls[offense_team] = play_name
	last_defensive_calls[1 - offense_team] = defensive_call

func set_route(id: int, route: String) -> bool:
	var a := get_athlete(id)
	if a == null or a.team != offense_team or not is_eligible_receiver(a) or a.role == Athlete.Role.QB:
		return false
	if is_run_play() or not Routes.ROUTES.has(route):
		return false
	route_of[id] = route
	return true

## A set defender who may stand up and roam: pre-snap, non-DL, still locked.
## The offense never can: it stays set until the snap (#142).
func can_break_stance(a: Athlete) -> bool:
	return a != null and phase == Phase.PRESNAP and a.team != offense_team and a.role != Athlete.Role.DL and a.set_lock

## Defense pre-snap: stand up out of stance and roam (one-way per play). The
## client asks for it only on a Space double-tap (DoubleTap); the action is one press.
func break_stance(id: int) -> bool:
	var a := get_athlete(id)
	if not can_break_stance(a):
		return false
	a.set_lock = false
	event.emit("break_stance", {"id": id})
	return true

func is_stance_locked(a: Athlete) -> bool:
	return phase == Phase.PRESNAP and a.set_lock

## Live classic dropbacks use real scrimmage lines. Free practice sets a
## virtual line beyond the field so the quarterback can throw from anywhere.
func _qb_dropback_speed_scale(a: Athlete) -> float:
	if a.role != Athlete.Role.QB or a.team != offense_team or phase != Phase.LIVE \
			or not ball.is_held_by(a.id) or forward_pass_thrown or not kick_play.is_empty() \
			or is_chaos() or los_y > field.length:
		return 1.0
	var depth := los_y - a.position.y
	var blend := clampf(inverse_lerp(T.QB_DROPBACK_SLOW_START, T.QB_DROPBACK_SLOW_END, depth), 0.0, 1.0)
	return lerpf(1.0, T.QB_DROPBACK_SPEED_FLOOR, blend)

## Shared athlete movement rules for the authoritative step and prediction.
func step_athlete(a: Athlete, dir: Vector2, sprint: bool, dt: float, block := false) -> void:
	if is_stance_locked(a):
		a.face(dir)
		a.emote_cd = maxf(0.0, a.emote_cd - dt)   # taunts still recharge while set (#240)
	else:
		var start := a.position
		var moving_special := a.move_t > 0.0
		var active := phase == Phase.LIVE and a.can_act()
		var blocking := active and block and a.team == possession_team() and not ball.is_held_by(a.id)
		a.step(dir, sprint, dt, blocking, _qb_dropback_speed_scale(a))
		if active and not moving_special:
			a.move_charge = minf(2.0, a.move_charge + start.distance_to(a.position) * T.MOVE_CHARGE_PER_YARD)

func _go_live() -> void:
	phase = Phase.LIVE
	flags = []
	ball_crossed_los = false
	_fp_carrier = -1
	_fp_open = false
	for a in athletes:
		a.set_lock = false

## Client prediction: one athlete's step with the same movement rules as step().
func predict_step(a: Athlete, dir: Vector2, sprint: bool, dt: float, block := false) -> void:
	if phase == Phase.DEAD and ball.holder_id == a.id:
		return
	step_athlete(a, dir, sprint, dt, block)
	if phase == Phase.PRESNAP:
		enforce_neutral_zone(a)

## Drills: go LIVE immediately with `id` carrying the ball (no snap).
func start_live_with(id: int) -> void:
	var a := get_athlete(id)
	ball.hold(a.id)
	last_possession = a.team
	play_time = 0.0
	_go_live()
	_sync_ball()
	event.emit("snap", {"qb": a.id})

func snap() -> bool:
	if phase != Phase.PRESNAP:
		return false
	if kick_play == "kickoff":
		var k := kicker()
		return k != null and kick(k.id, Vector2(field.width / 2.0, field.length), T.KICKOFF_DEFAULT_POWER)
	var c := find_role(offense_team, Athlete.Role.C)
	var qb := find_role(offense_team, Athlete.Role.QB)
	if qb == null:
		return false
	if c == null:
		if not ball.is_held_by(qb.id):
			return false
		_snap_to_id = -1
		_prepare_assignments()
		_go_live()
		_record_calls()
		event.emit("snap", {"qb": qb.id})
		event.emit("snap_received", {"qb": qb.id})
		return true
	if not ball.is_held_by(c.id):
		return false
	ball.state = Ball.State.IN_FLIGHT
	ball.holder_id = -1
	_snap_t = 0.0
	_snap_from = ball.position
	_snap_to_id = qb.id
	_prepare_assignments()
	_go_live()
	_record_calls()
	event.emit("snap", {"qb": qb.id})
	return true

func _prepare_assignments() -> void:
	route_paths = {}
	run_blocks = {}
	if is_run_play():
		var back := find_role(offense_team, Athlete.Role.RB)
		if back:
			route_paths[back.id] = run_path()
			run_blocks = run_block_assignments()
		return
	for id in route_of:
		var a := get_athlete(id)
		route_paths[id] = Routes.path_for(route_of[id], a.position, field.width)

func handoff_receiver(id: int) -> Athlete:
	if phase != Phase.LIVE or is_chaos() or handoff_cooldown > 0.0 or forward_pass_thrown or not ball.is_held_by(id):
		return null
	var qb := get_athlete(id)
	if qb == null or qb.team != offense_team or qb.role != Athlete.Role.QB or not qb.can_act() or qb.is_jumping() or qb.position.y > los_y:
		return null
	var back := find_role(offense_team, Athlete.Role.RB)
	if back == null or not back.can_act() or back.position.y > los_y or back.position.distance_to(qb.position) > T.HANDOFF_REACH:
		return null
	return back

func handoff(id: int) -> bool:
	var back := handoff_receiver(id)
	if back == null:
		return false
	ball.hold(back.id)
	_sync_ball()
	handoff_cooldown = T.HANDOFF_COOLDOWN
	event.emit("handoff", {"by": id, "to": back.id})
	return true

func can_throw(id: int) -> bool:
	var a := get_athlete(id)
	if a == null or phase != Phase.LIVE or not ball.is_held_by(id) or not a.can_act() or a.move_t > 0.0 or a.is_jumping():
		return false
	return rules["anyone_throws"] or (not forward_pass_thrown and not ball_crossed_los and a.position.y <= los_y)

## Throw from the holder toward target (field plane) with power 0..1.
func throw(id: int, target: Vector2, power: float, lob: bool = false, inherit_motion := true) -> bool:
	if not can_throw(id):
		return false
	var a := get_athlete(id)
	var from := Vector3(a.position.x, a.position.y, T.RELEASE_HEIGHT)
	var v := Passing.solve_velocity(from, target, power, gravity(), lob)
	if inherit_motion:
		v += Vector3(a.velocity.x, a.velocity.y, 0.0) * T.THROW_INHERIT
	return _launch(a, v, power, lob)

## POV throw: the passer's view sets direction (field plane) and launch angle
## (degrees above horizontal); power sets the speed, so it sets the distance.
func throw_dir(id: int, dir: Vector2, angle_deg: float, power: float) -> bool:
	if not can_throw(id) or dir.length_squared() < 0.0001:
		return false
	var a := get_athlete(id)
	var v := Passing.velocity_for(dir, angle_deg, power) + Vector3(a.velocity.x, a.velocity.y, 0.0) * T.THROW_INHERIT
	return _launch(a, v, power, false)

func _launch(a: Athlete, v: Vector3, power: float, lob: bool) -> bool:
	var from := Vector3(a.position.x, a.position.y, T.RELEASE_HEIGHT)
	var id := a.id
	var t_land := Passing.time_to_height(v, from.z, T.CATCH_HEIGHT, gravity())
	var target := Vector2(from.x + v.x * t_land, from.y + v.y * t_land)
	if not _check_grounding(a, target, t_land):
		_check_blocking_zone(target)
	ball.state = Ball.State.IN_FLIGHT
	ball.holder_id = -1
	ball.position = from
	ball.velocity = v
	forward_pass_thrown = true
	last_thrower_id = id
	last_possession = a.team
	bounces = 0
	throw_origin = Vector2(from.x, from.y)
	event.emit("throw", {"by": id, "target": target, "power": power, "lob": lob})
	return true

## Dive in the facing direction: a tackle attempt for the defense; a ball
## carrier dives for extra yards and is down where they land.
func tackle(id: int) -> bool:
	var a := get_athlete(id)
	if a == null or phase != Phase.LIVE:
		return false
	return a.start_dive()

## Jump (#379): a committed hop in live play; costs stamina, more when chained.
func jump(id: int) -> bool:
	var a := get_athlete(id)
	if a == null or phase != Phase.LIVE or not a.start_jump():
		return false
	event.emit("jump", {"by": id})
	return true

## Taunt (cosmetic, any phase). Rate-limited per athlete.
func emote(id: int, e: String) -> bool:
	var a := get_athlete(id)
	if a == null or not Emotes.has(e) or a.emote_cd > 0.0:
		return false
	a.emote_cd = Emotes.COOLDOWN
	event.emit("emote", {"by": id, "e": e})
	return true

## Q / E spin: an evade-spin angled SPIN_ANGLE left (-1) or right (+1) of facing.
func spin(id: int, side: int) -> bool:
	var a := get_athlete(id)
	if a == null or side == 0:
		return false
	var dir: Vector2 = a.facing.rotated(-float(signi(side)) * deg_to_rad(T.SPIN_ANGLE))
	if evade(id, true, dir):
		a.spin_dir = signi(side)
		event.emit("spin", {"by": id, "side": signi(side)})
		return true
	return false

## Spend an evasion charge and disengage from a block.
func evade(id: int, spin: bool, direction: Vector2) -> bool:
	var a := get_athlete(id)
	if a == null or phase != Phase.LIVE or not a.start_move(spin, direction):
		return false
	if a.engaged_with >= 0:
		var other := get_athlete(a.engaged_with)
		if a.team == possession_team():
			_release_block(other, a)
		else:
			_release_block(a, other)
	return true

## Team in possession during live play (carrier's team), else the offense.
func possession_team() -> int:
	var c := carrier()
	if c != null:
		return c.team
	if ball.state == Ball.State.LOOSE:
		return last_possession
	return offense_team

func carrier() -> Athlete:
	return get_athlete(ball.holder_id) if ball.state == Ball.State.HELD else null

## Input key that marks an athlete as human-controlled (#62). Callers set it on
## every human input (main.gd: local player and each remote peer); `ai.think`
## never does. Humans block only while holding the shield and release when they
## let go; bots auto-engage. The flag is explicit so a `block` key on a bot
## input can't silently flip it to human rules.
const HUMAN := "human"

static func is_human_input(inp: Dictionary) -> bool:
	return inp.get(HUMAN, false) == true

func step(inputs: Dictionary, dt: float) -> void:
	if phase == Phase.LIVE:
		play_time += dt
		handoff_cooldown = maxf(0.0, handoff_cooldown - dt)
	var prev: Array = []
	for a in athletes:
		prev.append(a.position)
		var inp: Dictionary = inputs.get(a.id, {})
		if phase == Phase.DEAD and ball.holder_id == a.id:
			a.jump_t = 0.0   # the dead ball's holder is frozen at the spot: land him there (#379)
			continue
		var human := is_human_input(inp)
		step_athlete(a, inp.get("dir", Vector2.ZERO), inp.get("sprint", false), dt, inp.get("block", false))
		if human and not a.blocking and a.engaged_with >= 0 and a.team == possession_team():
			var defender := get_athlete(a.engaged_with)
			if defender:
				_release_block(defender, a)
	if phase == Phase.LIVE:
		_step_blocks(prev, inputs, dt)
	if phase != Phase.DEAD:
		_resolve_collisions()
	if phase == Phase.PRESNAP:
		for a in athletes:
			enforce_neutral_zone(a)
	_step_snap(dt)
	_step_flight(dt)
	if phase == Phase.LIVE:
		_step_loose(dt)
	_sync_ball()
	if phase == Phase.LIVE:
		_track_progress(dt)
		_check_tackles()
	if phase == Phase.LIVE and is_chaos():
		_step_pass_clock(dt)
	if phase == Phase.LIVE:
		var rc := carrier()
		if rc != null and rc.team == offense_team and rc.position.y > los_y:
			ball_crossed_los = true

## Blocking zone (#253): until a pass or a run (the ball carried past the LOS), offensive
## linemen (C/OL, the roles `is_eligible_receiver` excludes) must stay within
## BLOCK_ZONE_DEPTH of the line. Kick plays, Chaosball and free practice have no zone.
func blocking_zone_active() -> bool:
	return phase == Phase.LIVE and not is_chaos() and kick_play.is_empty() and not forward_pass_thrown 		and not ball_crossed_los and los_y <= field.length

## Linemen more than BLOCK_ZONE_DEPTH past the LOS (exactly the depth is legal), deepest first.
func linemen_past_zone() -> Array:
	var out: Array = []
	for a in athletes:
		if a.team == offense_team and not is_eligible_receiver(a) and a.position.y - los_y > T.BLOCK_ZONE_DEPTH:
			out.append(a)
	out.sort_custom(func(x, y): return x.position.y > y.position.y)
	return out

## At a forward pass: flag illegal man downfield. A pass landing at or behind the line (a
## screen) is exempt, as in real football, since only passes that cross the line care.
## A rushed throw away from eligible targets is a spot foul (#254).
func _check_grounding(passer: Athlete, target: Vector2, flight: float) -> bool:
	if not blocking_zone_active() or passer.team != offense_team:
		return false
	var pressured := false
	var receiver_radius_sq := T.GROUNDING_RECEIVER_RADIUS * T.GROUNDING_RECEIVER_RADIUS
	var pressure_radius_sq := T.GROUNDING_PRESSURE_RADIUS * T.GROUNDING_PRESSURE_RADIUS
	for a in athletes:
		if a.team != passer.team:
			if a.can_act() and a.engaged_with < 0 and a.position.distance_squared_to(passer.position) <= pressure_radius_sq:
				pressured = true
			continue
		if a == passer or not is_eligible_receiver(a) or field.zone_of(a.position) == Field.Zone.OUT_OF_BOUNDS:
			continue
		var projected: Vector2 = a.position + a.velocity * flight
		if a.position.distance_squared_to(target) <= receiver_radius_sq or (
			field.zone_of(projected) != Field.Zone.OUT_OF_BOUNDS and projected.distance_squared_to(target) <= receiver_radius_sq
		):
			return false
	if not pressured:
		return false
	throw_flag(Penalties.make(Penalties.INTENTIONAL_GROUNDING, offense_team, true, maxf(1.0, passer.position.y),
		0.0, passer.id, false, true))
	return true

func _check_blocking_zone(target: Vector2) -> void:
	if not blocking_zone_active() or target.y <= los_y:
		return
	var deep := linemen_past_zone()
	if not deep.is_empty():
		throw_flag(Penalties.make(Penalties.ILLEGAL_MAN_DOWNFIELD, offense_team, true, los_y,
			T.BLOCK_ZONE_PENALTY_YARDS, deep[0].id))

## Record a foul; the play goes on and Match enforces it at the dead ball.
func throw_flag(p: Dictionary) -> void:
	flags.append(p)
	event.emit("flag", p)

## Linemen block any time; skill players only block downfield (after a catch
## or once the carrier is past the LOS), so receivers run routes instead.
func _can_block(a: Athlete) -> bool:
	var pt := possession_team()
	if a.team != pt or ball.is_held_by(a.id) or not a.can_act() or a.engaged_with >= 0 or a.immune_t > 0.0:
		return false
	if a.blocking or pt != offense_team:
		return true   # return after a takeaway: anyone can block
	if a.role == Athlete.Role.OL or a.role == Athlete.Role.C:
		return true
	var c := carrier()
	return c != null and (c.role != Athlete.Role.QB or c.position.y > los_y)

func _can_be_blocked(d: Athlete) -> bool:
	if d.id == fair_catch_id and kick_live:
		return false   # fair-catch protection: nobody touches the signaling returner (#189)
	return d.team != possession_team() and not d.is_grounded() and not d.is_spinning() and d.engaged_with < 0 and d.immune_t <= 0.0

func _step_blocks(prev: Array, inputs: Dictionary, dt: float) -> void:
	for a in athletes:
		a.immune_t = maxf(0.0, a.immune_t - dt)
	# Form new engagements
	for b in athletes:
		if not _can_block(b) or (is_human_input(inputs.get(b.id, {})) and not b.blocking):
			continue
		for d in athletes:
			if not _can_be_blocked(d):
				continue
			var to: Vector2 = d.position - b.position
			var dir := to.normalized()
			# Face to face: the blocker faces the defender, and a moving defender is heading at
			# the blocker (his velocity, not facing: a standing athlete's facing can be stale).
			# No blocks from behind or on a pair running side by side the same way.
			var d_spd: float = d.velocity.length()
			var heading_in: bool = d_spd < T.ENGAGE_FOE_MOVING or d.velocity.dot(-dir) >= T.ENGAGE_FOE_HEADING_DOT * d_spd
			if to.length() <= T.ENGAGE_DIST and b.facing.dot(dir) >= T.ENGAGE_FACING_DOT and heading_in:
				b.engaged_with = d.id
				d.engaged_with = b.id
				b.engage_t = 0.0
				d.engage_t = 0.0
				event.emit("block", {"blocker": b.id, "defender": d.id})
				break
	# Apply engagements: defender displacement driven by blocker
	var pt := possession_team()
	for d in athletes:
		if d.team == pt or d.engaged_with < 0:
			continue
		var b := get_athlete(d.engaged_with)
		d.engage_t += dt
		if d.engage_t >= T.BLOCK_HOLD or b == null or not b.can_act() or ball.is_held_by(b.id):
			_release_block(d, b)
			continue
		if b.blocking and prev[b.id].distance_to(d.position) > T.ENGAGE_DIST + 0.12:
			_release_block(d, b)
			continue
		var d_delta: Vector2 = d.position - prev[d.id]
		var b_delta: Vector2 = b.position - prev[b.id]
		d.position = field.clamp_playable(prev[d.id] + d_delta.lerp(b_delta, T.BLOCK_DRIVE))
		d.velocity = d.velocity.lerp(b.velocity, T.BLOCK_DRIVE)

func _release_block(d: Athlete, b: Athlete) -> void:
	d.engaged_with = -1
	d.immune_t = T.BLOCK_IMMUNITY
	if b:
		b.engaged_with = -1
		b.immune_t = T.BLOCKER_BEATEN
	event.emit("shed", {"defender": d.id})

func _resolve_collisions() -> void:
	var min_d := T.BODY_RADIUS * 2.0
	_fp_frame_push = 0.0
	var c := carrier()
	for i in athletes.size():
		var a: Athlete = athletes[i]
		if a.is_grounded():
			continue
		for j in range(i + 1, athletes.size()):
			var o: Athlete = athletes[j]
			if o.is_grounded():
				continue
			var delta: Vector2 = o.position - a.position
			var d := delta.length()
			if d < min_d:
				var n := delta / d if d > 0.0001 else Vector2(1, 0)
				var push := (min_d - d) * 0.5
				a.position -= n * push
				o.position += n * push
				if c and a.team != o.team and (a == c or o == c):
					# Opponent body contact moving the carrier; + = toward his own goal (driven back).
					var moved: float = (-n.y if a == c else n.y) * push
					_fp_frame_push -= moved * attack_sign(c.team)

func _check_tackles() -> void:
	var c := carrier()
	if c == null:
		return
	last_possession = c.team
	var z := field.zone_of(c.position)
	var scoring_zone := Field.Zone.ENDZONE_B if c.team == offense_team else Field.Zone.ENDZONE_A
	if z == scoring_zone:
		_whistle("touchdown", {"carrier": c.id, "team": c.team, "points": streak_points() if is_chaos() else 6})
		return
	if z == Field.Zone.OUT_OF_BOUNDS:
		_whistle("out_of_bounds", {"carrier": c.id, "team": c.team})
		return
	if c.is_grounded():
		# Carrier dove and hit the turf: down where they landed (by = -1: no tackler).
		_whistle("tackle", {"by": -1, "carrier": c.id, "team": c.team, "dive": true})
		return
	for a in athletes:
		if a.team != c.team and a.is_diving() and not c.is_spinning() and a.position.distance_to(c.position) <= T.TACKLE_REACH:
			if _is_strip(a, c):
				_fumble(c, a)
			else:
				_whistle("tackle", {"by": a.id, "carrier": c.id, "team": c.team})
			return

## +1 if `team` attacks +y (the world offense, incl. the kicking team), -1 for the other team.
func attack_sign(team: int) -> float:
	return 1.0 if team == offense_team else -1.0

## Forward progress (#98): while an opponent is within CONTACT_REACH of the carrier (plus a short
## grace after contact breaks), track the furthest point he reached and how far opposing bodies
## pushed him back. A carrier who retreats on his own (a QB drifting back with a rusher on him)
## isn't credited; one driven back by contact is.
func _track_progress(dt: float) -> void:
	var c := carrier()
	if c == null:
		_fp_carrier = -1
		_fp_open = false
		return
	if c.id != _fp_carrier:
		_fp_carrier = c.id
		_fp_open = false
	var s := attack_sign(c.team)
	var touching := false
	for a in athletes:
		if a.team != c.team and a.position.distance_to(c.position) <= T.CONTACT_REACH:
			touching = true
			break
	var y := s * c.position.y
	if touching and not _fp_open:
		_fp_open = true
		_fp_best = y + maxf(0.0, _fp_frame_push)   # where he was before this frame's push
		_fp_pushed = _fp_frame_push
	elif _fp_open:
		_fp_best = maxf(_fp_best, y)
		_fp_pushed += _fp_frame_push
	if touching:
		_fp_grace = T.FORWARD_PROGRESS_GRACE
	elif _fp_open:
		_fp_grace -= dt
		if _fp_grace <= 0.0:
			_fp_open = false

## Yards the spot moves forward of the carrier's current position under forward progress (>= 0).
func forward_progress_credit() -> float:
	var c := carrier()
	if c == null or not _fp_open or c.id != _fp_carrier:
		return 0.0
	var y := attack_sign(c.team) * c.position.y
	return maxf(0.0, minf(_fp_best, y + maxf(0.0, _fp_pushed)) - y)

## Fumble chance is a hit-quality outcome: closing speed along the contact normal,
## how far behind the carrier the diver came from, and the carrier's fatigue.
func _is_strip(diver: Athlete, c: Athlete) -> bool:
	var normal := diver.position.direction_to(c.position)
	if normal.is_zero_approx():
		normal = diver.facing
	var impact := maxf(0.0, (diver.velocity - c.velocity).dot(normal))
	var risk := fumble_risk(impact, c.stamina, diver.facing.dot(c.facing), c.last_sprinting)
	return _impact_roll(diver.id, c.id) < risk

## Deterministic pseudo-random roll in [0, 1) from the play situation (sim must stay pure).
func _impact_roll(a: int, b: int) -> float:
	_impact_rolls += 1
	var h := hash([1837, a, b, int(round(play_time * Tick.HZ)), _impact_rolls])
	return float(posmod(h, 100000)) / 100000.0

## 0 when the diver comes from the side or front (facing dot <= FUMBLE_BEHIND_DOT),
## rising to 1 when diver and carrier face the same way (hit squarely from behind).
static func behind_factor(facing_dot: float) -> float:
	return clampf((facing_dot - T.FUMBLE_BEHIND_DOT) / (1.0 - T.FUMBLE_BEHIND_DOT), 0.0, 1.0)

## `impact`: closing speed (yd/s); `facing_dot`: diver.facing . carrier.facing;
## `sprinting`: the carrier was sprinting. Fresh carriers can fumble from big hits;
## fatigue multiplies the whole chance.
static func fumble_risk(impact: float, stamina: float, facing_dot: float = -1.0, sprinting: bool = false) -> float:
	var force := clampf(impact / (T.DIVE_SPEED + T.SPRINT_SPEED), 0.0, 1.0)
	var hit := T.FUMBLE_HIT_RISK * force * force
	var rear := behind_factor(facing_dot) * (T.FUMBLE_REAR_SPRINT if sprinting else T.FUMBLE_REAR)
	var fatigue := clampf((T.FUMBLE_FRESH_STAMINA - stamina) / T.FUMBLE_FRESH_STAMINA, 0.0, 1.0)
	var mult := 1.0 + T.FUMBLE_FATIGUE_GAIN * fatigue * fatigue
	return minf(T.FUMBLE_MAX_RISK, (hit + rear) * mult)

func _fumble(c: Athlete, by: Athlete) -> void:
	ball.state = Ball.State.LOOSE
	ball.holder_id = -1
	ball.position = Vector3(c.position.x, c.position.y, T.BALL_CARRY_HEIGHT)
	var knock := c.velocity * 0.45 + by.facing * 2.4
	ball.velocity = Vector3(knock.x, knock.y, 3.0)
	c.recover_t = T.FUMBLE_KNOCKDOWN
	c.velocity *= 0.3
	last_possession = c.team
	event.emit("fumble", {"carrier": c.id, "by": by.id, "at": c.position})

func _step_loose(dt: float) -> void:
	if ball.state != Ball.State.LOOSE:
		return
	ball.velocity.z -= T.GRAVITY * dt
	ball.position += ball.velocity * dt
	if ball.position.z <= 0.0:
		ball.position.z = 0.0
		ball.velocity.z = -ball.velocity.z * T.LOOSE_BOUNCE if absf(ball.velocity.z) > 1.0 else 0.0
		var flat := Vector2(ball.velocity.x, ball.velocity.y)
		flat = flat.move_toward(Vector2.ZERO, T.LOOSE_FRICTION * dt)
		ball.velocity.x = flat.x
		ball.velocity.y = flat.y
	var bp := Vector2(ball.position.x, ball.position.y)
	if kick_free:
		_step_free_kick(bp, dt)
		return
	if field.zone_of(bp) == Field.Zone.OUT_OF_BOUNDS:
		dead_ball_spot = bp
		dead_ball_team = last_possession
		_end_play()
		var data := {"spot": bp, "team": last_possession, "loose": true}
		event.emit("out_of_bounds", data)
		event.emit("whistle", data)
		return
	if ball.position.z > T.RECOVER_MAX_HEIGHT:
		return
	var best: Athlete = null
	var best_d := T.RECOVER_RADIUS
	for a in athletes:
		if not a.can_act():
			continue
		var d: float = a.position.distance_to(bp)
		if d <= best_d:
			best_d = d
			best = a
	if best:
		ball.hold(best.id)
		event.emit("recovery", {"by": best.id, "team": best.team, "turnover": best.team != last_possession})
		last_possession = best.team

func _end_play() -> void:
	ball.state = Ball.State.DEAD
	phase = Phase.DEAD
	for athlete in athletes:
		athlete.engaged_with = -1
		athlete.engage_t = 0.0

func _whistle(reason: String, data: Dictionary) -> void:
	var c := carrier()
	dead_ball_spot = c.position
	if reason == "tackle" or reason == "out_of_bounds":
		# Forward progress (#98, #103): driven back then tackled or forced out, the ball goes back to
		# where contact stopped him. Out of bounds keeps x where he crossed (spot = y only).
		var credit := forward_progress_credit()
		dead_ball_spot.y += credit * attack_sign(c.team)
		c.position = dead_ball_spot   # the dead ball (and its carrier) sits at the spot
		data["progress"] = credit
	dead_ball_team = c.team
	data["spot"] = dead_ball_spot
	c.velocity = Vector2.ZERO
	_end_play()
	event.emit(reason, data)
	event.emit("whistle", data)

func _step_flight(dt: float) -> void:
	if ball.state != Ball.State.IN_FLIGHT or _snap_to_id >= 0:
		return
	if kick_live:
		_step_kick(dt)
		return
	ball.velocity.z -= gravity() * dt
	ball.position += ball.velocity * dt
	if rules["walls"]:
		_wall_bounce()
	if _try_catch():
		return
	if ball.position.z <= 0.0:
		ball.position.z = 0.0
		if rules["max_bounces"] > 0:
			bounces += 1
			event.emit("bounce", {"n": bounces})
			if bounces < rules["max_bounces"]:
				ball.velocity.z = -ball.velocity.z * T.BOUNCE_RESTITUTION
				ball.velocity.x *= T.BOUNCE_FRICTION
				ball.velocity.y *= T.BOUNCE_FRICTION
				return
		ball.velocity = Vector3.ZERO
		_end_play()
		var at := Vector2(ball.position.x, ball.position.y)
		dead_ball_spot = at
		event.emit("incomplete", {"at": at, "team": last_possession})

## Arena walls (Chaosball): sidelines and back lines reflect the ball; each hit is a bounce.
func _wall_bounce() -> void:
	var lo := Vector2(0.0, -field.endzone_depth)
	var hi := Vector2(field.width, field.length + field.endzone_depth)
	var hit := false
	if ball.position.x < lo.x or ball.position.x > hi.x:
		ball.position.x = clampf(ball.position.x, lo.x, hi.x)
		ball.velocity.x = -ball.velocity.x * T.BOUNCE_FRICTION
		hit = true
	if ball.position.y < lo.y or ball.position.y > hi.y:
		ball.position.y = clampf(ball.position.y, lo.y, hi.y)
		ball.velocity.y = -ball.velocity.y * T.BOUNCE_FRICTION
		hit = true
	if hit:
		bounces += 1
		event.emit("bounce", {"n": bounces, "wall": true})
		if bounces >= rules["max_bounces"]:
			ball.velocity = Vector3.ZERO
			_end_play()
			var at := Vector2(ball.position.x, ball.position.y)
			dead_ball_spot = at
			event.emit("incomplete", {"at": at, "team": last_possession})

## Offensive linemen (C, OL) are ineligible; all defenders may play the ball.
func is_eligible_receiver(a: Athlete) -> bool:
	if a.team != offense_team:
		return true
	return a.role != Athlete.Role.C and a.role != Athlete.Role.OL

## Highest ball a player can catch or deflect: a jump raises it (high-pointing, #379).
func catch_ceiling(a: Athlete) -> float:
	return T.CATCH_MAX_HEIGHT + a.jump_height()

## Resolve catches for a ball in flight. Returns true if the play state changed.
func _try_catch() -> bool:
	var z := ball.position.z
	if z < T.CATCH_MIN_HEIGHT or z > T.CATCH_MAX_HEIGHT + T.JUMP_HEIGHT:
		return false
	var bp := Vector2(ball.position.x, ball.position.y)
	var travel := bp.distance_to(throw_origin)
	# Not catchable/deflectable until it has left the thrower's immediate area.
	if travel < T.MIN_PASS_TRAVEL:
		return false
	if rules["anyone_throws"]:
		return _try_catch_chaos()
	var best := [null, null]   # per side: [offense, defense]
	var best_d := [INF, INF]
	for a in athletes:
		if a.id == last_thrower_id or not is_eligible_receiver(a) or z > catch_ceiling(a):
			continue
		var d: float = a.position.distance_to(bp)
		var side := 0 if a.team == offense_team else 1
		# Defenders contest from slightly further out (body position matters).
		var reach := T.CATCH_RADIUS + (T.CONTEST_MARGIN if side == 1 else 0.0)
		if d > reach:
			continue
		if d < best_d[side]:
			best_d[side] = d
			best[side] = a
	if best[0] == null and best[1] == null:
		return false
	var at := bp
	var defender_reaches: bool = best[1] != null and best_d[1] <= T.CATCH_RADIUS
	var defender_contests: bool = best[1] != null and best[0] != null and best_d[1] <= best_d[0] + T.CONTEST_MARGIN
	if best[0] == null and not defender_reaches:
		return false
	var lone_defender: bool = defender_reaches and best[0] == null
	if defender_contests or (lone_defender and travel <= T.BATTED_PASS_MAX_TRAVEL):
		_end_incomplete("breakup", {"by": best[1].id, "at": at})
		return true
	if lone_defender:
		var dfn: Athlete = best[1]
		# Only a defender squarely at the ball intercepts; within normal reach he deflects it.
		# Decide at the ball's closest approach: keep flying while it's still getting closer.
		if best_d[1] > T.INT_RADIUS:
			var next := bp + Vector2(ball.velocity.x, ball.velocity.y) / Tick.HZ
			var next_z := ball.position.z + ball.velocity.z / Tick.HZ
			if next.distance_to(dfn.position) < best_d[1] and next_z >= T.CATCH_MIN_HEIGHT:
				return false
			_end_incomplete("breakup", {"by": dfn.id, "at": at})
			return true
		if field.zone_of(dfn.position) == Field.Zone.OUT_OF_BOUNDS:
			_end_incomplete("breakup", {"by": dfn.id, "at": at})
			return true
		ball.hold(dfn.id)
		last_possession = dfn.team
		event.emit("interception", {"by": dfn.id, "at": at, "team": dfn.team})
		return true
	var rx: Athlete = best[0]
	if field.zone_of(rx.position) == Field.Zone.OUT_OF_BOUNDS:
		_end_incomplete("caught_out_of_bounds", {"by": rx.id, "at": at})
		return true
	ball.hold(rx.id)
	event.emit("catch", {"by": rx.id, "at": at})
	return true

## Chaosball: nearest standing player in reach catches (own pass allowed); no breakups.
func _try_catch_chaos() -> bool:
	var bp := Vector2(ball.position.x, ball.position.y)
	var best: Athlete = null
	var best_d := T.CATCH_RADIUS
	for a in athletes:
		if not a.can_act() or (a.id == last_thrower_id and not rules["self_catch"]) or ball.position.z > catch_ceiling(a):
			continue
		var d: float = a.position.distance_to(bp)
		if d <= best_d:
			best_d = d
			best = a
	if best == null:
		return false
	var swing: bool = best.team != last_possession
	var thrower := last_thrower_id
	ball.hold(best.id)
	last_possession = best.team
	hold_t = 0.0
	if swing:
		streak = 0
	elif best.id != thrower:
		streak += 1                     # self-catches don't farm the streak
		event.emit("streak", {"n": streak, "team": best.team})
	event.emit("interception" if swing else "catch", {"by": best.id, "at": bp, "team": best.team})
	return true

## Chaosball touchdown value for the current streak.
func streak_points() -> int:
	return mini(T.STREAK_BASE_POINTS + streak, T.STREAK_MAX_POINTS)

## Chaosball pass clock: the ball explodes in a hogger's hands.
func _step_pass_clock(dt: float) -> void:
	var c := carrier()
	if c == null:
		return
	hold_t += dt
	if hold_t >= T.PASS_CLOCK:
		var spot := c.position
		dead_ball_spot = spot
		dead_ball_team = c.team
		c.recover_t = T.FUMBLE_KNOCKDOWN
		_end_play()
		var data := {"carrier": c.id, "spot": spot, "team": c.team}
		event.emit("explode", data)
		event.emit("whistle", data)

func _end_incomplete(reason: String, data: Dictionary) -> void:
	ball.velocity = Vector3.ZERO
	_end_play()
	event.emit(reason, data)
	data["reason"] = reason
	event.emit("incomplete", data)

## Pre-snap: keep each side behind its edge of the neutral zone. Returns true
## when it actually stopped the athlete (presentation ripples the barrier).
func enforce_neutral_zone(a: Athlete) -> bool:
	if a.team == offense_team:
		if a.position.y > los_y - T.NEUTRAL_ZONE_HALF:
			var pushing := a.velocity.y > 0.05
			a.position.y = los_y - T.NEUTRAL_ZONE_HALF
			a.velocity.y = minf(a.velocity.y, 0.0)
			return pushing
	elif a.position.y < los_y + T.NEUTRAL_ZONE_HALF:
		var pushing := a.velocity.y < -0.05
		a.position.y = los_y + T.NEUTRAL_ZONE_HALF
		a.velocity.y = maxf(a.velocity.y, 0.0)
		return pushing
	return false

## True while the snap is travelling from the center to the QB (the ball is IN_FLIGHT then too).
func snap_in_flight() -> bool:
	return _snap_to_id >= 0

func _step_snap(dt: float) -> void:
	if _snap_to_id < 0 or ball.state != Ball.State.IN_FLIGHT:
		return
	_snap_t += dt
	var qb := get_athlete(_snap_to_id)
	var to := Vector3(qb.position.x, qb.position.y, T.BALL_CARRY_HEIGHT)
	var k := clampf(_snap_t / T.SNAP_TIME, 0.0, 1.0)
	ball.position = _snap_from.lerp(to, k)
	if k >= 1.0:
		ball.hold(_snap_to_id)
		_snap_to_id = -1
		event.emit("snap_received", {"qb": qb.id})

func _sync_ball() -> void:
	if ball.state == Ball.State.HELD:
		var h := get_athlete(ball.holder_id)
		if h:
			ball.position = Vector3(h.position.x, h.position.y, T.BALL_CARRY_HEIGHT)

## Kick in the air: block window near the kicker, uprights for field goals,
## fair fielding by the return team for punts/kickoffs, then a live bounce.
func _step_kick(dt: float) -> void:
	var prev := ball.position
	ball.velocity.z -= gravity() * dt
	ball.position += ball.velocity * dt
	var bp := Vector2(ball.position.x, ball.position.y)
	var travel := bp.distance_to(kick_spot)
	if kick_play != "kickoff" and travel <= T.KICK_BLOCK_WINDOW and ball.position.z <= T.KICK_BLOCK_HEIGHT:
		for a in athletes:
			if a.team != offense_team and a.can_act() and a.position.distance_to(bp) <= T.KICK_BLOCK_REACH:
				_block_kick(a)
				return
	if kick_play == "fg":
		var py := field.posts_y()
		if prev.y < py and ball.position.y >= py:
			var k := (py - prev.y) / maxf(ball.position.y - prev.y, 0.0001)
			var x := lerpf(prev.x, ball.position.x, k)
			var z := lerpf(prev.z, ball.position.z, k)
			var good := absf(x - field.width / 2.0) <= field.upright_span() / 2.0 and z >= T.CROSSBAR_HEIGHT
			_kick_dead("field_goal", Vector2(x, py), {"good": good, "distance": py - kick_spot.y})
			return
		if ball.position.z <= 0.0:
			_kick_dead("field_goal", bp, {"good": false, "distance": field.posts_y() - kick_spot.y})
		return
	# Punt / kickoff: sails past the end line -> touchback.
	if ball.position.y > field.length + field.endzone_depth:
		_kick_dead("touchback", bp, {})
		return
	if travel > T.KICK_BLOCK_WINDOW and ball.position.z >= T.CATCH_MIN_HEIGHT and ball.position.z <= T.CATCH_MAX_HEIGHT:
		var best: Athlete = null
		var best_d := T.CATCH_RADIUS
		for a in athletes:
			if a.team == offense_team or not a.can_act():
				continue
			var d: float = a.position.distance_to(bp)
			if d <= best_d:
				best_d = d
				best = a
		if best:
			_field_kick(best, bp, true)
			return
	if ball.position.z <= 0.0:
		ball.position.z = 0.0
		kick_live = false
		if field.zone_of(bp) == Field.Zone.OUT_OF_BOUNDS or bp.x < 0.0 or bp.x > field.width:
			_kick_dead("touchback" if bp.y > field.length else "kick_out_of_bounds", bp, {})
			return
		if bp.y > field.length:
			_kick_dead("touchback", bp, {})
			return
		ball.state = Ball.State.LOOSE
		ball.velocity = Vector3(ball.velocity.x * 0.55, ball.velocity.y * 0.55, absf(ball.velocity.z) * T.LOOSE_BOUNCE)
		event.emit("kick_land", {"at": bp})

## The return team gets the ball (catch in the air or a clean pickup).
## After a fair-catch signal there is no return: the signaler's catch in the air is
## a fair catch, and any other return-team possession (a teammate's catch, or a
## pickup after a muff) is dead where it happened, as in the NFL.
func _field_kick(a: Athlete, bp: Vector2, in_air := false) -> void:
	kick_live = false
	kick_free = false
	if a.position.y > field.length:
		ball.state = Ball.State.DEAD   # fielded in the end zone: downed for a touchback
		_kick_dead("touchback", a.position, {"by": a.id})
		return
	if fair_catch_id >= 0:
		ball.hold(a.id)
		last_possession = a.team
		var fair: bool = in_air and a.id == fair_catch_id
		_kick_dead("fair_catch" if fair else "kick_downed", a.position, {"by": a.id, "fair_catch": fair})
		return
	ball.hold(a.id)
	last_possession = a.team
	event.emit("kick_catch", {"by": a.id, "team": a.team, "at": bp})

func _block_kick(a: Athlete) -> void:
	kick_live = false
	kick_free = false
	kick_blocked = true
	fair_catch_id = -1   # a blocked kick is a loose ball; the signal no longer applies
	ball.state = Ball.State.LOOSE
	var side := signf(ball.position.x - a.position.x)
	ball.velocity = Vector3(side * 2.5, -absf(ball.velocity.y) * 0.25 - 2.0, 3.0)
	ball.position.z = maxf(ball.position.z, T.RECOVER_MAX_HEIGHT + 0.2)   # pops up: a live scramble, not an instant pickup
	last_possession = offense_team
	event.emit("kick_blocked", {"by": a.id, "team": a.team, "at": Vector2(ball.position.x, ball.position.y)})

## A kicked ball on the ground that nobody has possessed yet.
func _step_free_kick(bp: Vector2, dt: float) -> void:
	if bp.x < 0.0 or bp.x > field.width or field.zone_of(bp) == Field.Zone.OUT_OF_BOUNDS:
		_kick_dead("touchback" if bp.y > field.length else "kick_out_of_bounds", bp, {})
		return
	if bp.y > field.length:
		_kick_dead("touchback", bp, {})
		return
	if Vector2(ball.velocity.x, ball.velocity.y).length() < 0.3 and ball.position.z <= 0.01:
		_kick_rest_t += dt
		if _kick_rest_t >= T.KICK_REST_TIME:
			_kick_dead("kick_downed", bp, {})
			return
	if ball.position.z > T.RECOVER_MAX_HEIGHT:
		return
	var best: Athlete = null
	var best_d := T.RECOVER_RADIUS
	for a in athletes:
		if a.can_act() and a.position.distance_to(bp) <= best_d:
			best_d = a.position.distance_to(bp)
			best = a
	if best == null:
		return
	if best.team != offense_team:
		_field_kick(best, bp)
	elif onside and kick_play == "kickoff" and bp.y - kick_spot.y >= T.ONSIDE_MIN_TRAVEL:
		kick_free = false
		ball.hold(best.id)
		last_possession = best.team
		event.emit("recovery", {"by": best.id, "team": best.team, "turnover": false, "onside": true})
	else:
		_kick_dead("kick_downed", bp, {"by": best.id})   # kicking team downs it

## Kick play over. `reason`: field_goal, touchback, kick_out_of_bounds, kick_downed, fair_catch.
func _kick_dead(reason: String, at: Vector2, extra: Dictionary) -> void:
	kick_live = false
	kick_free = false
	ball.velocity = Vector3.ZERO
	_end_play()
	dead_ball_spot = at
	dead_ball_team = offense_team
	var data := {"spot": at, "team": offense_team, "kind": kick_play}
	data.merge(extra)
	event.emit(reason, data)
	event.emit("whistle", data)

