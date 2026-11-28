extends SkeletonModifier3D
## Stumble pose (#389): the upper body pitches forward, the head lifts back toward the field and
## the free arms fling out for balance, then it all eases back into the run. Runs after
## athlete_pose.gd (carry, catch, look), so a tucked ball stays tucked. Keyed off the sim's
## stumble tier and time left (live and online) or the replay frame's bits, never events, so
## live, online and replays look the same. View-only; inactive (no per-frame cost) when upright.

const Tick := preload("res://src/sim/tick.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Replay := preload("res://src/sim/replay.gd")

const PEAK_T := 0.1            # s after the trip at which the lean peaks
const BOBBLE_AMOUNT := 0.45    # a bobble is a smaller version of the same lurch
const SPINE_PITCH := deg_to_rad(11.0)   # per spine bone (3): about 33 deg forward at the peak
const HEAD_UP := deg_to_rad(16.0)       # the head lifts back up: eyes stay on the field
const ARMS_OUT := deg_to_rad(28.0)      # 40 read as "jazz hands" in the prototype
const ARMS_FWD := deg_to_rad(18.0)
const ANIM_DIP := 0.4          # the run clip slows by up to this at the peak
const SPINE := ["spine_01", "spine_02", "spine_03"]

var weight := 0.0   # 0 = upright, 1 = peak of a STUMBLE
var free_r := 1.0   # 0 while the right arm carries the ball or reaches for a pass
var free_l := 1.0
var elapsed := 0.0  # s since the trip, as shown (display-rate clock)
var _bones := {}
var _ok := false

## Lean weight `elapsed` s into a stumble of `tier`: up by PEAK_T, back to 0 at the tier's end.
static func envelope(tier: int, t: float) -> float:
	if tier == Athlete.Stumble.NONE:
		return 0.0
	var dur := Athlete.stumble_time(tier)
	var peak := minf(PEAK_T, dur * 0.4)
	var amount := BOBBLE_AMOUNT if tier == Athlete.Stumble.BOBBLE else 1.0
	return amount * smoothstep(0.0, peak, t) * (1.0 - smoothstep(peak, dur, t))

## Follow a live athlete (sim stumble state; null or a stub without it: none) or, for a replay
## view, the frame's flags.
func follow(athlete, replay_flags: int, delta: float) -> void:
	var tier := 0
	var left := 0.0
	var step := Tick.DT
	if replay_flags >= 0:
		var st := Replay.stumble_of(replay_flags)
		tier = st[0]
		left = st[1]
		step = Replay.FRAME_EVERY * Tick.DT
	elif athlete != null and athlete.get("stumble_t") != null and athlete.stumble_t > 0.0:
		tier = athlete.stumble_tier
		left = athlete.stumble_t
	if tier == Athlete.Stumble.NONE:
		weight = 0.0
	else:
		# Our clock runs at display rate between sim ticks (or replay frames) but never leaves
		# [source, source + one step]: a new trip, a seek, a pause or slow motion stays in sync.
		var src := Athlete.stumble_time(tier) - left
		elapsed = clampf(elapsed + delta, src, src + step)
		weight = envelope(tier, elapsed)
	if active != (weight > 0.0):
		active = weight > 0.0

## Multiplier for the run clip's playback speed (player.gd _play).
func anim_scale() -> float:
	return 1.0 - ANIM_DIP * weight

func _process_modification() -> void:
	apply(get_skeleton())

func apply(sk: Skeleton3D) -> void:
	if sk == null or weight <= 0.0:
		return
	if _bones.is_empty():
		for n in SPINE + ["Head", "upperarm_r", "upperarm_l"]:
			_bones[n] = sk.find_bone(n)
		_ok = not _bones.values().has(-1)
	if not _ok:
		return
	# Skeleton space: +Y up, +Z forward, +X the athlete's left. Spine and head turn about the
	# same X axis, so the three spine turns add up to the lean and the head undoes part of it.
	var lean := Basis(Vector3.RIGHT, SPINE_PITCH * weight)
	for n in SPINE:
		_turn(sk, _bones[n], lean)
	_turn(sk, _bones.Head, Basis(Vector3.RIGHT, -HEAD_UP * weight))
	for side in [["upperarm_l", 1.0, free_l], ["upperarm_r", -1.0, free_r]]:
		var k: float = weight * side[2]
		if k > 0.0:
			_turn(sk, _bones[side[0]], Basis(Vector3.BACK, ARMS_OUT * k * side[1]) * Basis(Vector3.RIGHT, -ARMS_FWD * k))

## Rotate `bone` by `r` (skeleton space, about the bone's own origin) on top of its pose.
func _turn(sk: Skeleton3D, bone: int, r: Basis) -> void:
	var parent := sk.get_bone_parent(bone)
	var p := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	var local := Basis(sk.get_bone_pose_rotation(bone))
	sk.set_bone_pose_rotation(bone, (p.inverse() * r * p * local).orthonormalized().get_rotation_quaternion())
