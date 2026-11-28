extends RefCounted
## Tackled carrier goes down hugging the ball: a physics ragdoll for the legs, spine and head
## (PhysicalBoneSimulator3D), caught by the turf. The arms stay out of the physics and keep the
## athlete_pose "secure" hug, so the ball stays tucked whatever the body does. View-only (no sim
## state): every client runs its own, and replays may differ slightly.
##
## Impact: the carrier freezes for HIT_STOP on contact, then the whole body keeps its run and one
## impulse lands at the hit point, shared by the bones nearest it (each pushed at that point, so
## an off-centre hit also turns them). A low hit from the front stops the legs and he falls
## forward over it; a high one knocks the chest back; one on the hip spins him. The fall comes
## only from where and how hard he was hit, never a random push.
##
## Get-up: `rise_after` s after the hit he gets up where he lies. The view root moves under the
## settled body (pelvis and head lined up with the first frame of LayToIdle) and the ragdoll pose
## blends into that clip (Hold, below). He rises where he lies, then jogs back onto the sim spot
## (player.gd chase_sim): sliding the root while he rises reads as skating. A teleport (next snap, replay seek) still stops it all at once (player.gd place()).

## Simulated bones: [bone, child (capsule end), radius, mass, bend limits (deg, lower, upper),
## side bend +- (deg), twist +- (deg)].
## Bend is about the athlete's left (+X) axis, in the rest pose: + bends the spine and head
## forward, swings a leg back, bends the knee and points the toes. Knees and ankles are hinges
## (no side bend or twist), so no joint can bend a way a body can't.
const BONES := [
	["pelvis", "spine_01", 0.13, 12.0, 0.0, 0.0, 0.0, 0.0],
	["spine_01", "spine_02", 0.12, 8.0, -10.0, 25.0, 10.0, 8.0],
	["spine_02", "spine_03", 0.13, 8.0, -10.0, 25.0, 10.0, 8.0],
	["spine_03", "neck_01", 0.15, 10.0, -10.0, 25.0, 10.0, 8.0],
	["Head", "", 0.12, 5.0, -35.0, 45.0, 25.0, 50.0],
	["thigh_l", "calf_l", 0.08, 8.0, -100.0, 20.0, 30.0, 15.0],
	["calf_l", "foot_l", 0.06, 6.0, 0.0, 115.0, 0.0, 0.0],
	["foot_l", "ball_l", 0.05, 3.0, -25.0, 40.0, 0.0, 0.0],
	["thigh_r", "calf_r", 0.08, 8.0, -100.0, 20.0, 30.0, 15.0],
	["calf_r", "foot_r", 0.06, 6.0, 0.0, 115.0, 0.0, 0.0],
	["foot_r", "ball_r", 0.05, 3.0, -25.0, 40.0, 0.0, 0.0],
]
const LAYER_BONES := 1 << 9
const LAYER_TURF := 1 << 10
const RAGDOLL_LINEAR_DAMP := 0.4
const RAGDOLL_ANGULAR_DAMP := 4.0   # high: limbs settle instead of flailing
## Speed caps (yd/s, rad/s): a bone faster than this is the solver fighting a joint limit,
## not the hit. Capping every physics tick keeps a bad contact from launching the body.
const MAX_SPEED := 12.0
const MAX_SPIN := 14.0
## Contact freeze (s): the carrier holds the frame of impact before the hit lands.
const HIT_STOP := 0.07
## How far (yd) the hit spreads through the body: a bone this far from the hit point takes
## e^-1 of the share the nearest bone takes.
const HIT_SPREAD := 0.35
## Get-up (s after the hit): a dead ball lets him lie a moment; a fumbled carrier is live and
## the sim frees him after T.FUMBLE_KNOCKDOWN, so he scrambles up.
const RISE_DEAD := 1.0
const RISE_FUMBLE := 0.45
const RISE_CLIP := "u2/LayToIdle"   # starts on his back, head behind him; ends in Idle
const RISE_SPEED_DEAD := 1.6
const RISE_SPEED_FUMBLE := 2.0
const RISE_BLEND := 0.3     # s from the lying pose into the clip
const RISE_ARMS_FREE := 0.6 # rise progress where the arms start easing from the hug into the carry

var view          # player.gd
var active := false
var t := 0.0
var _sim: PhysicalBoneSimulator3D
var _turf: StaticBody3D
var _run := Vector3.ZERO
var _impulse := Vector3.ZERO
var _point := Vector3.ZERO
var _pending := false   # in the hit-stop: the ragdoll starts when it ends
var _rise_at := RISE_DEAD
var _rise_speed := RISE_SPEED_DEAD
var _hold: Hold           # the lying pose, blended out as he rises
var rise_t := -1.0        # s into the get-up; < 0 = not rising
var rise_len := 1.0       # s the get-up takes
var _lie_at := Vector3.ZERO     # pelvis on the ground when he started up

## Pins every bone to the pose it had at the start of the get-up, fading into whatever the clip
## does underneath as `w` goes 0 -> 1. Captures that pose itself on its first run (it runs last,
## after the ragdoll and athlete_pose, so it sees the pose actually on screen). The pelvis is kept
## in world space, so the body stays put while the view root moves under it; the rest blend
## their local rotations, joint by joint.
class Hold extends SkeletonModifier3D:
	var w := 0.0
	var captured := false
	var world: Array[Transform3D] = []
	var local: Array[Transform3D] = []

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		var n := sk.get_bone_count()
		if not captured:
			world.resize(n)
			local.resize(n)
			for i in n:
				world[i] = sk.global_transform * sk.get_bone_global_pose(i)
				local[i] = sk.get_bone_pose(i)
			captured = true
			return
		var inv := sk.global_transform.affine_inverse()
		for i in n:
			var up := sk.get_bone_parent(i)
			if up < 0:
				continue   # the rig's root bone (no mesh) follows the clip, under the moving view root
			if sk.get_bone_parent(up) < 0:   # the pelvis: kept in world space, blended in skeleton space
				sk.set_bone_global_pose(i, (inv * world[i]).interpolate_with(sk.get_bone_global_pose(i), w))
			else:
				sk.set_bone_pose(i, local[i].interpolate_with(sk.get_bone_pose(i), w))

func _init(v) -> void:
	view = v

## run: the carrier's velocity before the hit (yd/s); impulse: the hit (mass x yd/s, world);
## point: where it lands on him (world). fumble: the ball is live, so he gets up quicker.
func start(run: Vector3, impulse: Vector3, point: Vector3, fumble := false) -> void:
	stop()
	active = true
	t = 0.0
	_rise_at = RISE_FUMBLE if fumble else RISE_DEAD
	_rise_speed = RISE_SPEED_FUMBLE if fumble else RISE_SPEED_DEAD
	_run = run
	_impulse = impulse
	_point = point
	_pending = true
	view.pose.secure = 1.0
	if view.anim:
		view.anim.speed_scale = 0.0   # hit-stop: hold the contact frame

func stop() -> void:
	if not active:
		return
	active = false
	_pending = false
	rise_t = -1.0
	_free_ragdoll()
	if _hold:
		_hold.queue_free()
		_hold = null
	view.pose.secure = 0.0
	if view.anim:
		view.anim.speed_scale = 1.0

func _free_ragdoll() -> void:
	if view.get_tree().physics_frame.is_connected(_cap_speeds):
		view.get_tree().physics_frame.disconnect(_cap_speeds)
	if _sim:
		_sim.physical_bones_stop_simulation()
		_sim.queue_free()
		_sim = null
	if _turf:
		_turf.queue_free()
		_turf = null

## True during the contact freeze (player.gd keeps the clip where it is).
func holding() -> bool:
	return active and _pending

## True while getting up: the clip and the view root are this script's (player.gd).
func rising() -> bool:
	return active and rise_t >= 0.0

## Rise progress 0..1 (0 when not rising).
func rise_k() -> float:
	return clampf(rise_t / rise_len, 0.0, 1.0) if rising() else 0.0

## Where the body is on the ground (world, y = 0): the pelvis while he's down.
func ground_position() -> Vector3:
	if rising():
		return _lie_at.lerp(Vector3(view.global_position.x, 0.0, view.global_position.z), smoothstep(0.0, 1.0, rise_k()))
	var pb := _sim.get_node_or_null("PB_pelvis") as PhysicalBone3D if _sim else null
	var p: Vector3 = pb.global_position if pb else view.global_position
	return Vector3(p.x, 0.0, p.z)

func update(delta: float) -> void:
	if not active:
		return
	t += delta
	if _pending and t >= HIT_STOP:
		_pending = false
		if view.anim:
			view.anim.speed_scale = 1.0
		_start_ragdoll()
	if rise_t >= 0.0:
		rise_t += delta
		_hold.w = smoothstep(0.0, RISE_BLEND, rise_t)
		view.pose.secure = 1.0 - smoothstep(RISE_ARMS_FREE, 1.0, rise_k())
		if rise_t >= rise_len:
			stop()
			view.chase_sim = true   # up where he fell: jog back onto the sim spot
	elif _hold == null and _sim and t >= _rise_at:
		_hold = Hold.new()   # captures the lying pose on the next skeleton update
		view._skel.add_child(_hold)
	elif _hold and _hold.captured:
		_begin_rise()

## Swap the ragdoll for the get-up clip without a visible change: free the physics, move the
## view root so the clip's first frame (on his back, head behind) lies where the body is, and let
## Hold fade the lying pose into the clip.
func _begin_rise() -> void:
	_free_ragdoll()
	var sk: Skeleton3D = view._skel
	var pelvis := sk.find_bone("pelvis")
	var head := sk.find_bone("Head")
	var lie_p: Vector3 = _hold.world[pelvis].origin
	var lie_dir: Vector3 = _hold.world[head].origin - lie_p
	view._play(RISE_CLIP, 0.0, _rise_speed)
	view.anim.seek(0.0, true)
	var clip_p := sk.get_bone_global_pose(pelvis).origin   # outside the skeleton update: the plain clip pose
	var clip_dir := sk.get_bone_global_pose(head).origin - clip_p
	var to := Vector3(lie_dir.x, 0.0, lie_dir.z)
	var from := sk.global_basis * clip_dir
	from.y = 0.0
	if to.length() > 0.01 and from.length() > 0.01:
		view.rotation.y += from.signed_angle_to(to, Vector3.UP)
	var at := sk.global_transform * clip_p
	view.global_position += Vector3(lie_p.x - at.x, 0.0, lie_p.z - at.z)
	_lie_at = Vector3(lie_p.x, 0.0, lie_p.z)
	rise_len = view.anim.get_animation(RISE_CLIP).length / _rise_speed
	rise_t = 0.0
	_hold.w = 0.0

func _start_ragdoll() -> void:
	var sk: Skeleton3D = view._skel
	_sim = PhysicalBoneSimulator3D.new()
	sk.add_child(_sim)
	var names := []
	for b in BONES:
		if sk.find_bone(b[0]) < 0:
			continue
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + b[0]
		pb.bone_name = b[0]
		# Capsule from the bone to its child (or a head-sized one), as the editor's
		# "Create Physical Skeleton" lays it out.
		var child := sk.find_bone(b[1]) if b[1] != "" else -1
		var tip: Vector3 = sk.get_bone_rest(child).origin if child >= 0 else Vector3(0, 0.22, 0.02)
		var half := tip.length() * 0.5
		var up := Vector3.UP if not Vector3.UP.cross(tip).is_zero_approx() else Vector3.BACK
		var body_xf := Transform3D(Basis.looking_at(tip, up), Vector3.ZERO)
		body_xf.origin = body_xf.basis * Vector3(0, 0, -half)
		pb.body_offset = body_xf
		pb.joint_offset = Transform3D(Basis(), Vector3(0, 0, half))
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = b[2]
		cap.height = half * 2.0 + b[2] * 2.0
		cs.shape = cap
		cs.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))   # capsule Y along the body's Z
		pb.add_child(cs)
		pb.mass = b[3]
		pb.friction = 0.9
		pb.bounce = 0.0
		pb.linear_damp = RAGDOLL_LINEAR_DAMP
		pb.angular_damp = RAGDOLL_ANGULAR_DAMP
		pb.collision_layer = LAYER_BONES
		pb.collision_mask = LAYER_TURF
		if b[0] != "pelvis":
			# 6DOF joint in an anatomical frame: X = the athlete's left, Y = along the bone, Z = X x Y.
			# Joints are built in the rest pose (PhysicalBone3D resets to rest on entering the
			# tree), so limits are measured from standing straight, not from the hit frame.
			var id := sk.find_bone(b[0])
			var rest := sk.get_bone_global_rest(id)
			var y: Vector3 = ((sk.get_bone_global_rest(child).origin - rest.origin) if child >= 0 else Vector3.UP).normalized()
			var x := (Vector3.RIGHT - y * y.dot(Vector3.RIGHT)).normalized()
			var anat := Basis(x, y, x.cross(y))
			pb.joint_offset = Transform3D((rest.basis * body_xf.basis).inverse() * anat, pb.joint_offset.origin)
		_sim.add_child(pb)
		if b[0] != "pelvis":
			# Joint creation reads the bodies' world transforms. Wait until the bone has entered the tree.
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF
			# Godot measures the bend the other way round from the table: negate it.
			for a in [["x", -b[5], -b[4]], ["y", -b[7], b[7]], ["z", -b[6], b[6]]]:
				pb.set("joint_constraints/%s/angular_limit_enabled" % a[0], true)
				pb.set("joint_constraints/%s/angular_limit_lower" % a[0], a[1])
				pb.set("joint_constraints/%s/angular_limit_upper" % a[0], a[2])
		names.append(StringName(b[0]))
	_turf = StaticBody3D.new()
	_turf.top_level = true
	_turf.collision_layer = LAYER_TURF
	_turf.collision_mask = 0
	var ts := CollisionShape3D.new()
	ts.shape = WorldBoundaryShape3D.new()
	_turf.add_child(ts)
	view.add_child(_turf)
	_turf.global_transform = Transform3D()
	_sim.physical_bones_start_simulation(names)
	view.get_tree().physics_frame.connect(_cap_speeds)
	# Everyone keeps running; the hit lands where it was made, on the bones nearest it. Bone
	# segments come from the contact-frame pose (the hit-stop held it).
	var parts := []
	var total := 0.0
	for b in BONES:
		var pb := _sim.get_node_or_null("PB_" + b[0]) as PhysicalBone3D
		if pb == null:
			continue
		pb.linear_velocity = _run
		var pose := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b[0]))
		var child := sk.find_bone(b[1]) if b[1] != "" else -1
		var tip: Vector3 = (sk.global_transform * sk.get_bone_global_pose(child)).origin if child >= 0 else pose * Vector3(0, 0.22, 0.02)
		var d := _point.distance_to(Geometry3D.get_closest_point_to_segment(_point, pose.origin, tip))
		var w := exp(-pow(d / HIT_SPREAD, 2.0))
		parts.append([pb, w, (pose.origin + tip) * 0.5])
		total += w
	for p in parts:
		p[0].apply_impulse(_impulse * p[1] / total, _point - p[2])

func _cap_speeds() -> void:
	if _sim == null:
		return
	for pb in _sim.get_children():
		var b := pb as PhysicalBone3D
		if b.linear_velocity.length() > MAX_SPEED:
			b.linear_velocity = b.linear_velocity.limit_length(MAX_SPEED)
		if b.angular_velocity.length() > MAX_SPIN:
			b.angular_velocity = b.angular_velocity.limit_length(MAX_SPIN)
