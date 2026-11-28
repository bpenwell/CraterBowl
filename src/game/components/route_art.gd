extends "res://src/game/component.gd"
## Presnap route art on the turf, rebuilt only when its inputs change: on offense your
## receivers' routes (a distinct color each, arrowheads, start dots), the run path on run
## plays and the line's protection/run-block lines; on defense each defender's assignment
## (man: a line to his receiver; zone: a line to the spot plus a disc). Yours is drawn
## brighter and wider. Hidden once the ball is snapped. Moved out of main.gd (#369).

const World := preload("res://src/sim/world.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Routes := preload("res://src/sim/routes.gd")
const Field := preload("res://src/sim/field.gd")

var mesh := ImmediateMesh.new()   # main.route_mesh forwards here (tests read it)
var _route_key := 0               # last drawn route-art state; rebuild only when it changes

func _ready() -> void:
	var lines := MeshInstance3D.new()
	lines.name = "RouteLines"
	lines.mesh = mesh
	var rlm := StandardMaterial3D.new()
	rlm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rlm.vertex_color_use_as_albedo = true
	rlm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rlm.cull_mode = BaseMaterial3D.CULL_DISABLED
	rlm.no_depth_test = false
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lines.material_override = rlm
	add_child(lines)

func on_render() -> void:
	_draw_routes()

const ROUTE_COLORS := [Color(1.0, 0.82, 0.25), Color(1.0, 0.45, 0.75), Color(0.55, 0.6, 1.0), Color(1.0, 0.55, 0.2), Color(0.75, 0.5, 1.0)]
const MY_ROUTE_COLOR := Color(0.35, 1.0, 0.55)

func _draw_routes() -> void:
	var world: World = ctx.world
	var field: Field = ctx.field
	var my_id: int = ctx.my_id
	var me = world.get_athlete(my_id)
	var offense: bool = me != null and me.team == world.offense_team
	var is_run := world.is_run_play()
	var show: bool = me != null and world.phase == World.Phase.PRESNAP and (not offense or is_run or not world.route_of.is_empty())
	if not show:
		if _route_key != 0:
			mesh.clear_surfaces()
			_route_key = 0
		return
	# Rebuilding an ImmediateMesh re-uploads it to the GPU; only do it when the art's inputs
	# change. Offense art = routes + protection lines, defense art = assignments; both depend
	# on every athlete's position, the calls, the LOS and which side you're on.
	var key_src := [my_id, me.team, world.offense_team, field.width, world.los_y, world.play_name, is_run, world.route_of, world.defensive_call]
	for a in world.athletes:
		key_src.append(a.position)
	var key := hash(key_src)
	if key == _route_key:
		return
	_route_key = key
	mesh.clear_surfaces()
	if not offense:
		_draw_defense_routes(me.team)
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var blocks := {}
	if is_run:
		var back := world.find_role(me.team, Athlete.Role.RB)
		var qb := world.find_role(me.team, Athlete.Role.QB)
		if back and qb:
			var mine := back.id == my_id
			var color: Color = MY_ROUTE_COLOR if mine else ROUTE_COLORS[0]
			_route_ribbon([back.position, qb.position] + world.run_path(), color, 0.48 if mine else 0.34)
		blocks = world.run_block_assignments()
	var k := 0
	for id in world.route_of:
		var a = world.get_athlete(id)
		var pts: Array = [a.position] + Routes.path_for(world.route_of[id], a.position, field.width)
		var mine: bool = id == my_id
		var c: Color = MY_ROUTE_COLOR if mine else ROUTE_COLORS[k % ROUTE_COLORS.size()]
		k += 1
		_route_ribbon(pts, c, 0.42 if mine else 0.3)
	for blocker in world.athletes:
		if blocker.team != me.team or blocker.role not in [Athlete.Role.C, Athlete.Role.OL]:
			continue
		var defender = world.get_athlete(blocks.get(blocker.id, -1)) if is_run else world.protection_target(blocker)
		if defender != null:
			var mine: bool = blocker.id == my_id
			_route_ribbon([blocker.position, defender.position], MY_ROUTE_COLOR if mine else Color(0.76, 0.82, 0.90), 0.42 if mine else 0.22)
	mesh.surface_end()

func _draw_defense_routes(team: int) -> void:
	var world: World = ctx.world
	var my_id: int = ctx.my_id
	if world.defensive_call.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var matchups: Dictionary = world.man_assignments()
	for athlete in world.athletes:
		if athlete.team != team:
			continue
		var assignment: Dictionary = world.defense_assignment(athlete)
		var mine: bool = athlete.id == my_id
		if assignment.kind == "man":
			if matchups.has(athlete.id):
				var receiver = world.get_athlete(matchups[athlete.id])
				_route_ribbon([athlete.position, receiver.position], Color(1.0, 0.82, 0.38), 0.50 if mine else 0.26)
			continue
		var target: Vector2 = assignment.target
		var color := Color(1.0, 0.30, 0.26)
		if assignment.kind == "zone":
			color = Color(0.50, 0.68, 1.0) if assignment.deep else Color(0.24, 0.94, 0.81)
			_disc(target, 2.0 if mine else 1.5, Color(color, 0.35), 0.055, 0.65)
		_route_ribbon([athlete.position, target], color, 0.50 if mine else 0.26)
	mesh.surface_end()

func _route_ribbon(pts: Array, c: Color, wdt: float) -> void:
	var h := 0.06
	var total := 0.0
	for i in range(pts.size() - 1):
		total += (pts[i + 1] - pts[i]).length()
	var run := 0.0
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var seg := p1 - p0
		if seg.length() < 0.01:
			continue
		var dir := seg.normalized()
		var is_last := i == pts.size() - 2
		if is_last:   # leave room for the arrowhead
			p1 = p1 - dir * minf(1.1, seg.length() * 0.6)
		var n := Vector2(-dir.y, dir.x) * wdt * 0.5
		var a0 := c * Color(1, 1, 1, lerpf(0.75, 1.0, run / maxf(total, 0.01)))
		run += seg.length()
		var a1 := c * Color(1, 1, 1, lerpf(0.75, 1.0, run / maxf(total, 0.01)))
		_tri(p0 + n, p0 - n, p1 + n, a0, a0, a1, h)
		_tri(p1 + n, p0 - n, p1 - n, a1, a0, a1, h)
		if i > 0:   # round the joint
			_disc(p0, wdt * 0.5, a0, h)
		if is_last:
			var tip: Vector2 = pts[i + 1]
			var base := p1
			var wing := Vector2(-dir.y, dir.x) * wdt * 1.6
			_tri(base + wing, base - wing, tip, a1, a1, a1, h)
	_disc(pts[0], wdt * 1.1, c, h)

func _tri(a: Vector2, b: Vector2, c2: Vector2, ca: Color, cb: Color, cc: Color, h: float) -> void:
	for pc in [[a, ca], [b, cb], [c2, cc]]:
		mesh.surface_set_color(pc[1])
		mesh.surface_add_vertex(Vector3(pc[0].x, h, -pc[0].y))

func _disc(p: Vector2, r: float, c: Color, h: float, depth_scale: float = 1.0) -> void:
	for s in 10:
		var t0 := TAU * s / 10.0
		var t1 := TAU * (s + 1) / 10.0
		_tri(p, p + Vector2(cos(t0), sin(t0) * depth_scale) * r, p + Vector2(cos(t1), sin(t1) * depth_scale) * r, c, c, c, h)
