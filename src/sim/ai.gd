extends RefCounted
## Bots (A14): fill every athlete not controlled by a human. Produces inputs for athletes not
## controlled by humans and triggers defender dives. Deterministic.

const T := preload("res://src/sim/tuning.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Passing := preload("res://src/sim/passing.gd")
const Routes := preload("res://src/sim/routes.gd")
const World := preload("res://src/sim/world.gd")

var defense_enabled := true
var offense_enabled := true

var _presnap_t := 0.0
var _presnap_called := false
## #136: a Match play clock snaps for the bots (Match.huddle + Match.tick's snapper =
## snap()), so presnap_tick only calls plays. Off for bare-World use (drills, sim tests).
var snaps_on_clock := false
var _calls := 0           # plays called so far: deterministic variety
var _man := {}            # defender id -> receiver id (set at snap)
var _man_ref = null

func reset_presnap() -> void:
	_presnap_t = 0.0
	_presnap_called = false

## Presnap bot behavior: an AI-run offense calls a situational play and snaps.
## `down`/`distance` describe the situation (pass downs.down / downs.distance()).
func presnap_tick(world, human_ids: Array, dt: float, down: int = 1, distance: float = 10.0, snap_delay: float = T.AI_SNAP_DELAY) -> void:
	if world.phase != world.Phase.PRESNAP:
		reset_presnap()
		return
	_presnap_t += dt
	var humans_on_offense := not offense_is_bot(world, human_ids)
	var qb = world.find_role(world.offense_team, Athlete.Role.QB)
	if world.kick_play == "kickoff":
		if not humans_on_offense and not snaps_on_clock and _presnap_t >= T.AI_SNAP_DELAY:
			snap(world)
		return
	if not _presnap_called and qb and not humans_on_offense:
		if world.kick_play == "":   # PAT kicks are called by the match
			world.call_play(choose_play(down, distance, _calls, world.has_run_back()))
			if world.play_name == "Outside Sweep":
				# Sweep across the formation so the back can keep their exchange momentum.
				world.flip_play()
			if down >= 4:
				world.call_kick(fourth_down_call(world.los_y, world.field.length, world.field.endzone_depth, distance))
		_calls += 1
		_presnap_called = true
	if not humans_on_offense and not snaps_on_clock and _presnap_t >= snap_delay:
		world.snap()

## True when no human is on the offense (the bots own the snap).
static func offense_is_bot(world, human_ids: Array) -> bool:
	for id in human_ids:
		var h = world.get_athlete(id)
		if h and h.team == world.offense_team:
			return false
	return true

## How long a bot offense huddles before it snaps: kickoffs go after AI_SNAP_DELAY.
static func huddle_seconds(world, snap_delay: float) -> float:
	return T.AI_SNAP_DELAY if world.kick_play == "kickoff" else snap_delay

## A bot offense's snap. Kickoffs vary depth so some are returnable and some go for touchbacks.
func snap(world) -> bool:
	if world.kick_play != "kickoff":
		return world.snap()
	var qb = world.find_role(world.offense_team, Athlete.Role.QB)
	if qb == null or not world.ball.is_held_by(qb.id):
		return false
	var p := 0.74 + 0.04 * float(_calls % 4)
	var aim := Vector2(world.field.width * (0.5 + 0.12 * float(_calls % 3 - 1)), world.field.length)
	if not world.kick(qb.id, aim, p):
		return false
	_calls += 1
	return true

## 4th down: kick a field goal in range, go for it on short yardage past midfield, else punt.
static func fourth_down_call(los: float, goal: float, endzone: float, distance: float) -> String:
	if goal - los + T.FG_HOLD_DEPTH + endzone <= T.AI_FG_MAX:
		return "fg"
	if distance <= T.AI_GO_FOR_IT and los >= goal * 0.5:
		return ""
	return "punt"

## Situational play choice: deterministic, rotating through fitting plays so
## drives don't repeat (variant = plays called so far).
static func choose_play(down: int, distance: float, variant: int = 0, can_run: bool = false) -> String:
	if can_run and down <= 2 and distance <= 10.0 and variant % 3 == 1:
		return Routes.RUN_NAMES[0 if variant % 6 == 1 else 1]
	var options: Array
	if distance >= 12.0:
		options = ["Deep Shot", "Verticals", "Flood"]
	elif distance <= 3.0:
		options = ["Slants", "Curls", "Mesh"]
	elif down >= 3:
		options = ["Flood", "Mesh", "Slants", "Deep Shot"]
	else:
		options = ["Curls", "Mesh", "Slants", "Verticals", "Flood"]
	return options[(variant + down) % options.size()]

## Returns inputs for every athlete not in `human_ids`. May call world.tackle()/throw().
func think(world, human_ids: Array) -> Dictionary:
	var out := {}
	if world.phase != world.Phase.LIVE:
		return out
	_refresh_man(world)
	var c = world.carrier()
	var run_call: bool = world.is_run_play() and not world.forward_pass_thrown
	var qb = world.find_role(world.offense_team, Athlete.Role.QB) if run_call else null
	var exchange: bool = qb != null and (c == null or c.id == qb.id) and world.play_time <= T.AI_HANDOFF_WINDOW
	if exchange and c != null and not human_ids.has(qb.id) and world.handoff(qb.id):
		c = world.carrier()
		exchange = false
	var loose: bool = world.ball.state == world.ball.State.LOOSE
	var in_air: bool = c == null and world.ball.state == world.ball.State.IN_FLIGHT and world.forward_pass_thrown
	var pass_phase: bool = c != null and c.team == world.offense_team and c.role == Athlete.Role.QB \
		and c.position.y <= world.los_y and not world.forward_pass_thrown and (world.is_chaos() or not world.ball_crossed_los) \
		and (not run_call or exchange)
	var landing := _landing_point(world) if in_air else Vector2.INF
	if world.kick_live:
		return _kick_coverage(world, human_ids, landing)
	var pre_kick: bool = c != null and c.team == world.offense_team and world.kick_play in ["punt", "fg"] and not world.kicked
	if pre_kick:
		return _kick_protect(world, human_ids, c)
	var ball_chasers := _nearest_to(world, landing, 2) if in_air else []
	for a in world.athletes:
		if human_ids.has(a.id):
			continue
		if loose:
			if a.can_act():
				var bp := Vector2(world.ball.position.x, world.ball.position.y)
				out[a.id] = {"dir": (bp - a.position).normalized(), "sprint": true}
			continue
		if c != null and a.id == c.id:
			if pass_phase:
				if not exchange:
					_qb_decide(world, a)
					out[a.id] = _qb_pocket(world, a)
			else:
				if world.is_chaos():
					_chaos_pass(world, a)
				var run := _run_ball(world, a)
				if run_call and world.route_paths.has(a.id):
					run["dir"] = _avoid(world, a, _route_dir(world, a))
				out[a.id] = run
			continue
		if run_call and offense_enabled and a.team == world.offense_team and (c == null or c.team == a.team):
			if exchange and a.role == Athlete.Role.RB:
				out[a.id] = _arrive(a, qb.position)
				continue
			if world.run_blocks.has(a.id):
				var target = world.get_athlete(world.run_blocks[a.id])
				if not target.is_grounded():
					var lane: Vector2 = world.run_path()[0]
					out[a.id] = _approach_block(world, a, target, lane)
					continue
		if c != null and a.team != c.team:
			if not defense_enabled:
				continue
			if pass_phase and a.role != Athlete.Role.DL:
				var assignment: Dictionary = world.defense_assignment(a)
				match assignment.get("kind", ""):
					"rush": out[a.id] = _pursue(world, a, c)
					"zone": out[a.id] = _arrive(a, assignment.target)
					_: out[a.id] = _cover(world, a, c)
			else:
				out[a.id] = _pursue(world, a, c)
			continue
		if c != null and a.team == c.team and not pass_phase:
			out[a.id] = _escort(world, a, c)
			continue
		# Pass phase (offense) or ball in the air.
		if in_air and a.team != world.offense_team:
			var assignment: Dictionary = world.defense_assignment(a)
			if assignment.get("kind") == "zone":
				if defense_enabled:
					out[a.id] = _arrive(a, landing if ball_chasers.has(a.id) else assignment.target)
				continue
		if in_air and a.team != world.offense_team and _man.has(a.id):
			if not defense_enabled:
				continue
			# Play the receiver's hands, not the ball's landing spot.
			var r = world.get_athlete(_man[a.id])
			var to_r: Vector2 = r.position - r.velocity * T.AI_COVER_REACTION - a.position
			# Receiver knows where the ball is going; defender reacts (no sprint burst).
			out[a.id] = {"dir": to_r.normalized() if to_r.length() > 0.3 else Vector2.ZERO, "sprint": false}
			continue
		if in_air and ball_chasers.has(a.id) and (a.team != world.offense_team or world.is_eligible_receiver(a)):
			if a.team != world.offense_team and not defense_enabled:
				continue
			out[a.id] = _arrive(a, landing)
			continue
		if a.team == world.offense_team:
			if not offense_enabled:
				continue
			if a.role == Athlete.Role.WR or a.role == Athlete.Role.RB:
				out[a.id] = {"dir": _avoid(world, a, _route_dir(world, a)), "sprint": false}
			elif (a.role == Athlete.Role.OL or a.role == Athlete.Role.C) and c != null:
				out[a.id] = _protect(world, a, c)
		elif defense_enabled and in_air:
			out[a.id] = _cover(world, a, null)
	_respect_blocking_zone(world, out)
	return out

## #253: bot linemen never drift past the blocking zone before a pass or run. Within
## AI_BLOCK_ZONE_MARGIN of its edge they stop moving downfield (and step back if past it).
func _respect_blocking_zone(world, out: Dictionary) -> void:
	if not world.blocking_zone_active():
		return
	var edge: float = world.los_y + T.BLOCK_ZONE_DEPTH - T.AI_BLOCK_ZONE_MARGIN
	for id in out:
		var a = world.get_athlete(id)
		if a.team != world.offense_team or world.is_eligible_receiver(a) or a.position.y < edge:
			continue
		var dir: Vector2 = out[id].get("dir", Vector2.ZERO)
		out[id]["dir"] = Vector2(dir.x, minf(dir.y, -0.5 if a.position.y > edge + 0.5 else 0.0))
		out[id]["sprint"] = false

## Steering that arrives at p without overshooting (sprinting overshoots ~2 yd).
func _arrive(a, p: Vector2) -> Dictionary:
	var to: Vector2 = p - a.position
	var d := to.length()
	if d < 0.25:
		return {"dir": Vector2.ZERO, "sprint": false}
	var stop_d: float = a.velocity.length_squared() / (2.0 * T.DECEL)
	var throttle := clampf(d / maxf(stop_d + 0.5, 1.0), 0.15, 1.0)
	return {"dir": to.normalized() * throttle, "sprint": d > 4.0}

## Man assignments at the snap: each eligible receiver gets the nearest free CB/S/LB.
func _refresh_man(world) -> void:
	if _man_ref == world.route_paths:
		return
	_man_ref = world.route_paths
	_man = world.man_assignments()

func man_of(defender_id: int) -> int:
	return _man.get(defender_id, -1)

## Coverage: trail the assigned receiver with a cushion; unassigned = deep zone / QB spy.
func _cover(world, a, qb) -> Dictionary:
	var rid: int = _man.get(a.id, -1)
	if rid >= 0:
		var r = world.get_athlete(rid)
		# Trail technique with a reaction lag: chase where the receiver was ~0.25 s ago,
		# a step behind along his path. Route breaks create separation; the defender
		# stays out of the QB's throwing lane.
		var heading: Vector2 = r.velocity.normalized() if r.velocity.length() > 0.5 else Vector2(0, 1)
		var spot: Vector2 = r.position - r.velocity * T.AI_COVER_REACTION - heading * T.AI_COVER_TRAIL
		# Until the receiver gets past him, a defender lined up downfield holds level and
		# slightly inside; "trailing" would mean walking through the receiver into the backfield.
		if a.position.y > r.position.y and spot.y < r.position.y:
			var inside := 1.0 if r.position.x < world.field.width / 2.0 else -1.0
			spot = Vector2(r.position.x + inside * 1.0, r.position.y + 0.6)
		var to: Vector2 = spot - a.position
		return {"dir": to.normalized() if to.length() > 0.3 else Vector2.ZERO, "sprint": to.length() > 2.0}
	if a.role == Athlete.Role.LB and qb != null:
		var spy: Vector2 = qb.position + Vector2(0, T.AI_SPY_DEPTH)
		if qb.position.y > world.los_y or world.play_time >= T.AI_SPY_BLITZ_TIME:
			return _pursue(world, a, qb)
		var tl: Vector2 = spy - a.position
		return {"dir": tl.normalized() if tl.length() > 0.5 else Vector2.ZERO, "sprint": false}
	var deep := Vector2(world.field.width / 2.0 + (a.home_x - world.field.width / 2.0) * 0.5, world.los_y + T.AI_DEEP_ZONE)
	var tz: Vector2 = deep - a.position
	return {"dir": tz.normalized() if tz.length() > 0.5 else Vector2.ZERO, "sprint": false}

## Where a thrown ball will descend through catch height.
func _landing_point(world) -> Vector2:
	var b = world.ball
	var t: float = Passing.time_to_height(b.velocity, b.position.z, T.CATCH_HEIGHT, world.gravity())
	return Vector2(b.position.x + b.velocity.x * t, b.position.y + b.velocity.y * t)

## Ids of the `per_side` athletes per team nearest to p (standing only).
func _nearest_to(world, p: Vector2, per_side: int) -> Array:
	var out := []
	for team in 2:
		var cands := []
		for a in world.athletes:
			if a.team == team and a.can_act() and (a.team != world.offense_team or world.is_eligible_receiver(a)) and a.id != world.last_thrower_id:
				cands.append(a)
		cands.sort_custom(func(x, y): return x.position.distance_to(p) < y.position.distance_to(p))
		for i in mini(per_side, cands.size()):
			out.append(cands[i].id)
	return out

## QB holding the ball: drift away from the nearest rusher inside the pocket.
func _qb_pocket(world, qb) -> Dictionary:
	var near = null
	var nd := INF
	for d in world.athletes:
		if d.team != qb.team and not d.is_grounded():
			var dist: float = d.position.distance_to(qb.position)
			if dist < nd:
				nd = dist
				near = d
	if near == null or nd > 4.0:
		return {"dir": Vector2.ZERO, "sprint": false}
	var away: Vector2 = (qb.position - near.position).normalized()
	away.y = minf(away.y, 0.0)   # never drift past the LOS while looking to throw
	return {"dir": away.normalized() if away.length() > 0.01 else Vector2(1, 0), "sprint": false}

## Chaosball: a pressured carrier dumps it to the most open teammate.
func _chaos_pass(world, c) -> void:
	var pressure := INF
	for o in world.athletes:
		if o.team != c.team and not o.is_grounded():
			pressure = minf(pressure, o.position.distance_to(c.position))
	var clock_low: bool = world.hold_t >= T.PASS_CLOCK - T.AI_PASS_CLOCK_MARGIN
	if pressure > T.AI_CHAOS_PRESSURE and not clock_low:
		return
	var best = null
	var best_sep := 0.0
	for r in world.athletes:
		if r.team != c.team or r.id == c.id or not r.can_act():
			continue
		var sep := INF
		for o in world.athletes:
			if o.team != c.team:
				sep = minf(sep, o.position.distance_to(r.position))
		if sep > best_sep:
			best_sep = sep
			best = r
	if best == null or (best_sep < 2.0 and not clock_low):
		return
	var from := Vector3(c.position.x, c.position.y, T.RELEASE_HEIGHT)
	world.throw(c.id, Passing.lead_target(from, best.position, best.velocity, 0.7, world.gravity()), 0.7)

## Ball carrier: head for the scoring end zone, juke defenders in the lane, and
## protect the ball (no sprint) when someone is closing from behind.
func _run_ball(world, c) -> Dictionary:
	var goal := Vector2(0, 1) if c.team == world.offense_team else Vector2(0, -1)
	var dir := goal
	var threat_behind := false
	for o in world.athletes:
		if o.team == c.team or o.is_grounded():
			continue
		var rel: Vector2 = o.position - c.position
		var ahead := rel.dot(goal)
		var side := rel.dot(Vector2(goal.y, -goal.x))
		if ahead > -0.5 and ahead < 5.0 and absf(side) < 2.5:
			var away := -signf(side) if absf(side) > 0.05 else (1.0 if c.position.x < world.field.width / 2.0 else -1.0)
			dir = (goal + Vector2(goal.y, -goal.x) * away * 1.3).normalized()
		# Ball security matches the strip rule (any pursuer closing in): don't sprint near defenders.
		if rel.length() < T.AI_PROTECT_BALL_RANGE:
			threat_behind = true
	# stay in bounds
	if c.position.x < 2.0:
		dir.x = maxf(dir.x, 0.3)
	elif c.position.x > world.field.width - 2.0:
		dir.x = minf(dir.x, -0.3)
	return {"dir": dir.normalized(), "sprint": not threat_behind}

func _pursue(world, a, c) -> Dictionary:
	var to: Vector2 = c.position - a.position
	to += c.velocity * clampf(to.length() / T.SPRINT_SPEED, 0.0, 0.6)  # lead the carrier
	if to.length() <= T.AI_DIVE_RANGE and a.can_act():
		a.facing = (c.position - a.position).normalized()
		world.tackle(a.id)
	return {"dir": to.normalized(), "sprint": true}

## Carrier's teammates: get in front of the nearest pursuer.
func _escort(world, a, c) -> Dictionary:
	if a.id == c.id:
		return _run_ball(world, c)
	var best = null
	var best_d := INF
	for o in world.athletes:
		if o.team == a.team or o.is_grounded():
			continue
		var d: float = o.position.distance_to(c.position)
		if d < best_d:
			best_d = d
			best = o
	if best == null:
		return {"dir": Vector2(0, 1) if a.team == world.offense_team else Vector2(0, -1), "sprint": true}
	var spot: Vector2 = best.position + (c.position - best.position).normalized() * 0.9
	return {"dir": (spot - a.position).normalized(), "sprint": true}

## Throw to the most open eligible receiver after QB_THROW_TIME, or early under pressure.
func _qb_decide(world, qb) -> void:
	var pressure := INF
	for d in world.athletes:
		if d.team != world.offense_team:
			pressure = minf(pressure, d.position.distance_to(qb.position))
	# Vary the read slightly per play (deterministic) so drives aren't carbon copies.
	var read_time: float = T.AI_QB_THROW_TIME + fmod(world.los_y * 0.37 + world.athletes.size(), 1.0) - 0.4
	if world.play_time < read_time and pressure > T.AI_QB_PRESSURE:
		return
	var best = null
	var best_sep := -INF
	var best_read := -INF
	for r in world.athletes:
		if r.team != world.offense_team or r.id == qb.id or not world.is_eligible_receiver(r):
			continue
		if r.position.y <= world.los_y:
			continue
		var sep := INF
		for d in world.athletes:
			if d.team != world.offense_team:
				sep = minf(sep, d.position.distance_to(r.position))
		var read: float = sep + (r.position.y - world.los_y) * T.AI_QB_DEPTH_WEIGHT
		if read > best_read:
			best_read = read
			best_sep = sep
			best = r
	if best == null:
		return
	# Wait for real separation unless pressured or out of time.
	if best_sep < T.AI_QB_MIN_SEPARATION and pressure > T.AI_QB_PRESSURE and world.play_time < T.AI_QB_MAX_HOLD:
		return
	var from := Vector3(qb.position.x, qb.position.y, T.RELEASE_HEIGHT)
	var tgt := _route_lead(world, from, best, T.AI_QB_PASS_POWER)
	tgt.x = clampf(tgt.x, 1.5, world.field.width - 1.5)   # never lead a receiver out of bounds
	world.throw(qb.id, tgt, T.AI_QB_PASS_POWER, false, false)

## Where receiver r will be after t seconds if he keeps running his route at run speed.
func predict_on_route(world, r, t: float) -> Vector2:
	var path: Array = world.route_paths.get(r.id, [])
	if path.is_empty():
		return r.position + r.velocity * t
	var pos: Vector2 = r.position
	var dist := T.RUN_SPEED * t
	var i: int = _route_progress.get(r.id, 0)
	while i < path.size() and dist > 0.0:
		var seg: Vector2 = path[i] - pos
		if seg.length() >= dist:
			return pos + seg.normalized() * dist
		dist -= seg.length()
		pos = path[i]
		i += 1
	var prev: Vector2 = path[-2] if path.size() > 1 else pos - Vector2(0, 1)
	var d: Vector2 = (path[-1] - prev).normalized()
	if d.y < 0.0:
		return pos   # settles at the end of a comeback route
	return pos + d * dist

## Lead a receiver along his route (iterate flight time <-> predicted spot).
func _route_lead(world, from: Vector3, r, power: float) -> Vector2:
	var target: Vector2 = r.position
	for i in 6:
		var v := Passing.solve_velocity(from, target, power, world.gravity())
		var t := Passing.time_to_height(v, from.z, T.CATCH_HEIGHT, world.gravity())
		target = predict_on_route(world, r, t)
	return target

## Follow the assigned route path; after the last waypoint keep the final direction.
var _route_progress := {}   # athlete_id -> waypoint index (reset when paths change)
var _paths_ref = null

func _route_dir(world, a) -> Vector2:
	if world.route_paths != _paths_ref:
		_paths_ref = world.route_paths
		_route_progress = {}
	var path: Array = world.route_paths.get(a.id, [])
	if path.is_empty():
		return Vector2(0, 1)
	var i: int = _route_progress.get(a.id, 0)
	while i < path.size() and a.position.distance_to(path[i]) < 1.0:
		i += 1
	_route_progress[a.id] = i
	if i < path.size():
		return (path[i] - a.position).normalized()
	var last: Vector2 = path[-1]
	var prev: Vector2 = path[-2] if path.size() > 1 else last - Vector2(0, 1)
	var d := (last - prev).normalized()
	if d.y < 0.0:
		return Vector2.ZERO   # comeback route (curl): settle in the window, don't backpedal
	return d if d.length_squared() > 0.0 else Vector2(0, 1)

## Steer around an opponent standing directly in the running lane.
func _avoid(world, a, dir: Vector2) -> Vector2:
	for o in world.athletes:
		if o.team == a.team or o.is_grounded():
			continue
		var rel: Vector2 = o.position - a.position
		var ahead := rel.dot(dir)
		var side := rel.dot(Vector2(dir.y, -dir.x))
		if ahead > 0.0 and ahead < 2.5 and absf(side) < 1.2:
			var away := -signf(side) if absf(side) > 0.05 else (1.0 if a.position.x < world.field.width / 2.0 else -1.0)
			return (dir + Vector2(dir.y, -dir.x) * away * 1.2).normalized()
	return dir

## Pass protection: get between the nearest free rusher and the carrier, face him.
func _protect(world, a, carrier) -> Dictionary:
	return _approach_block(world, a, world.protection_target(a), carrier.position)

func _approach_block(world, a, target, lane: Vector2) -> Dictionary:
	if a.engaged_with >= 0:
		var held = world.get_athlete(a.engaged_with)
		return {"dir": (held.position - a.position).normalized(), "sprint": false}
	if target == null:
		return {"dir": Vector2.ZERO, "sprint": false}
	var spot: Vector2 = target.position + (lane - target.position).normalized() * 0.9
	var to: Vector2 = spot - a.position
	if to.length() < 0.2:
		to = target.position - a.position  # in position: face the defender
	return {"dir": to.normalized(), "sprint": false}

## Punt / field goal before the kick: a bot kicker kicks once the snap is in; the
## line protects; rushers (DL) go for the block; the rest hold their spots.
func _kick_protect(world, human_ids: Array, k) -> Dictionary:
	var out := {}
	if not human_ids.has(k.id) and world.play_time >= T.SNAP_TIME + 0.15:
		_bot_kick(world, k)
		if world.kicked:
			return out
	for a in world.athletes:
		if human_ids.has(a.id) or a.id == k.id:
			continue
		if a.team == world.offense_team:
			if not offense_enabled:
				continue
			if a.role == Athlete.Role.OL or a.role == Athlete.Role.C:
				out[a.id] = _protect(world, a, k)
			elif world.kick_play == "punt":
				out[a.id] = {"dir": Vector2(0, 1), "sprint": false}   # release into coverage
		elif defense_enabled and a.role == Athlete.Role.DL:
			out[a.id] = _pursue(world, a, k)
	return out

func _bot_kick(world, k) -> void:
	var cx: float = world.field.width / 2.0
	if world.kick_play == "fg":
		var dist: float = world.field.posts_y() - k.position.y
		var p := clampf(World.kick_power_for("fg", dist + 6.0, T.CROSSBAR_HEIGHT + 2.0, world.gravity()), 0.0, 1.0)
		world.kick(k.id, Vector2(cx, world.field.posts_y()), p)
	else:
		world.kick(k.id, Vector2(cx + (world.los_y - floorf(world.los_y)) * 6.0 - 3.0, k.position.y + 40.0), 0.86)

## Bot fair-catch rule (#189), deterministic: once the punt/kickoff is coming down,
## wave it off if any coverage man is within AI_FAIR_CATCH_PRESSURE of the landing spot.
static func wants_fair_catch(world, landing: Vector2) -> bool:
	if world.kick_play not in ["punt", "kickoff"] or not world.kick_free or world.ball.velocity.z >= 0.0:
		return false
	for a in world.athletes:
		if a.team == world.offense_team and a.can_act() and a.position.distance_to(landing) <= T.AI_FAIR_CATCH_PRESSURE:
			return true
	return false

## Kick in the air: coverage sprints to the landing spot in lanes; the nearest
## returner settles under it and the rest of the return team forms a wall.
func _kick_coverage(world, human_ids: Array, landing: Vector2) -> Dictionary:
	var out := {}
	if world.kick_play == "fg":
		return out
	var cx: float = world.field.width / 2.0
	var ret = null
	var rd := INF
	for a in world.athletes:
		if a.team != world.offense_team and a.can_act() and a.position.distance_to(landing) < rd:
			rd = a.position.distance_to(landing)
			ret = a
	for a in world.athletes:
		if human_ids.has(a.id):
			continue
		if a.team == world.offense_team:
			if offense_enabled:
				var lane := Vector2(landing.x + (a.home_x - cx) * 0.4, landing.y)
				out[a.id] = {"dir": (lane - a.position).normalized(), "sprint": true}
		elif defense_enabled:
			if a == ret:
				out[a.id] = _arrive(a, landing)
				if wants_fair_catch(world, landing):
					world.signal_fair_catch(a.id)
			else:
				var wall := Vector2(landing.x + (a.home_x - cx) * 0.5, landing.y - 10.0)
				out[a.id] = _arrive(a, wall)
	return out

