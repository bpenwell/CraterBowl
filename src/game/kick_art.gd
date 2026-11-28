extends Node3D
## #68 kick art: a stepped power meter beside your kicker while you line up a kick, and the
## kickoff tee the ball stands on until it's kicked. Presentation only: it reads
## main.can_kick() / main.kick_power() and the world's kick state, and owns no rules.
## Change-driven: the meter's shader parameter is pushed only when the lit step count changes.

const RC := preload("res://src/game/render_cache.gd")
const Mats := preload("res://src/game/art/materials.gd")
const Football := preload("res://src/game/art/football.gd")

const STEPS := 10
const METER_SIZE := Vector2(0.75, 2.3)   # m: reads from the follow camera, a bit taller than an athlete
const METER_SIDE := 1.5    # m to the kicker's right, as the camera sees it
const METER_LIFT := 0.35   # m from the turf to the meter's bottom edge
## The tee sits ahead of the kicker and off to his left, like a soccer-style approach, so the
## follow camera behind him sees the ball beside his legs instead of through them. The sim
## kicks from his feet, so this is also how far the ball hops on the kick frame.
const TEE_AHEAD := 1.0     # yd downfield of the kicker
const TEE_SIDE := 0.7      # yd toward -x (screen left with the camera behind him)
const TEE_HEIGHT := 0.14   # m
const TEE_COLOR := Color(0.95, 0.42, 0.1)
## The ball stands on the tee, tipped back toward the kicker a little.
const TEE_TILT := 0.22     # rad

var meter: MeshInstance3D
var tee: MeshInstance3D
var lit := -1              # steps lit as last pushed to the shader (-1 = never)
var pushes := 0            # shader parameter pushes so far (tests: change-driven)
var _meter_mat: ShaderMaterial

func _init() -> void:
	name = "KickArt"
	meter = MeshInstance3D.new()
	meter.name = "KickMeter"
	var q := QuadMesh.new()
	q.size = METER_SIZE
	meter.mesh = q
	_meter_mat = Mats.shader("res://src/game/art/kick_meter.gdshader")
	_meter_mat.set_shader_parameter("steps", STEPS)
	meter.material_override = _meter_mat
	meter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	meter.visible = false
	add_child(meter)
	tee = MeshInstance3D.new()
	tee.name = "KickTee"
	tee.mesh = RC.cone(0.045, 0.12, TEE_HEIGHT)
	tee.material_override = RC.mat(TEE_COLOR)
	tee.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tee.visible = false
	add_child(tee)

## Steps lit for a kick power 0..1: ceil(power * STEPS), at least one, at most all.
static func steps_for(power: float) -> int:
	return clampi(ceili(clampf(power, 0.0, 1.0) * STEPS - 0.0001), 1, STEPS)

## Kickoff, before the kick: the ball belongs on the tee, not in the kicker's hand.
static func ball_on_tee(w) -> bool:
	return w.kick_play == "kickoff" and not w.kicked and w.phase == w.Phase.PRESNAP and w.ball.holder_id >= 0

## Called by presentation._process (after main has placed the views and camera).
func update(main, w) -> void:
	_update_meter(main)
	_update_tee(main, w)

func _update_meter(main) -> void:
	var show: bool = not main.replay_active and main.can_kick()
	meter.visible = show
	if not show:
		return
	set_steps(steps_for(main.kick_power()))
	var kv: Node3D = main.views[main.controlled_id]
	var right := Vector3.RIGHT
	if main.camera:
		right = main.camera.global_basis.x
		right.y = 0.0
		right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT
	meter.global_position = kv.global_position + right * METER_SIDE + Vector3(0, METER_LIFT + METER_SIZE.y * 0.5, 0)

## Push the lit count to the shader only when it changed.
func set_steps(n: int) -> void:
	if n == lit:
		return
	lit = n
	pushes += 1
	_meter_mat.set_shader_parameter("lit", n)

func _update_tee(main, w) -> void:
	var show: bool = w.kick_play == "kickoff" and not main.replay_active
	tee.visible = show
	if not show:
		return
	if ball_on_tee(w):
		# Follow the kicker's drawn (interpolated) feet until he kicks.
		var kv: Node3D = main.views[w.ball.holder_id]
		tee.global_position = Vector3(kv.global_position.x - TEE_SIDE, TEE_HEIGHT * 0.5, kv.global_position.z - TEE_AHEAD)
	else:
		# Kicked: the tee stays where the ball left it for the rest of the play.
		tee.global_position = Vector3(w.kick_spot.x - TEE_SIDE, TEE_HEIGHT * 0.5, -(w.kick_spot.y + TEE_AHEAD))

## The ball's transform standing on the tee: long axis up, tipped back toward the kicker.
func ball_transform() -> Transform3D:
	var basis := Basis(Vector3.RIGHT, -PI * 0.5 + TEE_TILT)
	var top := tee.global_position + Vector3(0, TEE_HEIGHT * 0.5, 0)
	return Transform3D(basis, top + basis.z * (Football.HALF_LENGTH * 0.85))
