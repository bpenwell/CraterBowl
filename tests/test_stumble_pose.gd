extends "res://tests/test_case.gd"
## Stumble pose (#389, src/game/art/stumble_pose.gd): the view's lean, from the sim's stumble
## state or a replay frame's bits. Sampled on the real rig and Sprint clip (no mixer).

const PlayerNode := preload("res://src/game/player.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const Replay := preload("res://src/sim/replay.gd")
const StumblePose := preload("res://src/game/art/stumble_pose.gd")
const S := Athlete.Stumble

func test_envelope_peaks_early_and_ends_with_the_stumble() -> void:
	var dur := Athlete.stumble_time(S.STUMBLE)
	assert_eq(StumblePose.envelope(S.STUMBLE, 0.0), 0.0, "starts upright")
	assert_near(StumblePose.envelope(S.STUMBLE, StumblePose.PEAK_T), 1.0, 0.0001, "full lean at the peak")
	assert_near(StumblePose.envelope(S.STUMBLE, dur), 0.0, 0.0001, "upright when the stumble ends")
	assert_true(StumblePose.envelope(S.STUMBLE, 0.45) < 0.25, "mostly recovered by 0.45 s")
	var bob := 0.0
	for i in 16:
		bob = maxf(bob, StumblePose.envelope(S.BOBBLE, i / 60.0))
	assert_near(bob, StumblePose.BOBBLE_AMOUNT, 0.02, "a bobble is a smaller lurch")
	assert_eq(StumblePose.envelope(S.NONE, 0.1), 0.0, "no stumble: no lean")

## Live: from the athlete's stumble_t. Replay: from the frame bits alone, even after a seek.
func test_follows_the_sim_and_the_replay_bits() -> void:
	var p := StumblePose.new()
	var a := Athlete.new()
	p.follow(a, -1, 1.0 / 60.0)
	assert_eq(p.weight, 0.0, "upright athlete")
	assert_true(not p.active, "idle layer is off: no per-frame cost")
	a.trip(S.STUMBLE)
	a.stumble_t -= StumblePose.PEAK_T
	p.follow(a, -1, 1.0 / 60.0)
	assert_near(p.weight, 1.0, 0.01, "peak, from the sim")
	assert_true(p.active, "on while stumbling")
	p.follow(null, Replay.stumble_bits(S.STUMBLE, 0.5), 1.0 / 60.0)
	assert_near(p.weight, StumblePose.envelope(S.STUMBLE, 0.1), 0.01, "replay frame alone gives the same moment")
	p.follow(null, Replay.stumble_bits(S.STUMBLE, 0.1), 1.0 / 60.0)
	assert_near(p.elapsed, 0.5, 0.034, "a seek jumps the clock to the frame")
	p.follow(null, Replay.F_PUSH, 1.0 / 60.0)
	assert_eq(p.weight, 0.0, "frame without a stumble: upright")
	assert_near(p.anim_scale(), 1.0, 0.0001, "clip at full speed")
	p.free()

func test_pose_leans_forward_and_flings_the_free_arm() -> void:
	var v = _view()
	var sk: Skeleton3D = v.mesh_i.get_parent()
	var clip: Animation = v.anim.get_animation("Sprint")
	for t in [0.1, 0.3, 0.5]:
		_pose(sk, clip, t)
		var chest0 := _pos(sk, "neck_01") - _pos(sk, "pelvis")
		var hand_l0 := _pos(sk, "hand_l")
		var right0 := sk.get_bone_pose_rotation(sk.find_bone("upperarm_r"))
		var legs0 := sk.get_bone_pose_rotation(sk.find_bone("thigh_l"))
		v.stumble.weight = 1.0
		v.stumble.free_r = 0.0   # carrying: the ball arm stays tucked
		v.stumble.free_l = 1.0
		v.stumble.apply(sk)
		sk.force_update_all_bone_transforms()
		var chest := _pos(sk, "neck_01") - _pos(sk, "pelvis")
		assert_true(chest.z - chest0.z > 0.07, "upper body pitches forward at t=%.1f (%.3f m)" % [t, chest.z - chest0.z])
		assert_true(chest.y < chest0.y, "and down")
		assert_true(_pos(sk, "hand_l").x - hand_l0.x > 0.05, "free left arm flung out (%.3f m)" % (_pos(sk, "hand_l").x - hand_l0.x))
		assert_true(sk.get_bone_pose_rotation(sk.find_bone("upperarm_r")).is_equal_approx(right0), "ball arm untouched")
		assert_true(sk.get_bone_pose_rotation(sk.find_bone("thigh_l")).is_equal_approx(legs0), "legs keep the run clip")
		var head_fwd := sk.get_bone_global_pose(sk.find_bone("Head")).basis.z.normalized()
		var chest_fwd := sk.get_bone_global_pose(sk.find_bone("spine_03")).basis.z.normalized()
		assert_true(head_fwd.y > chest_fwd.y, "head lifts back toward the field")
	_pose(sk, clip, 0.2)
	var before := sk.get_bone_pose_rotation(sk.find_bone("spine_02"))
	v.stumble.weight = 0.0
	v.stumble.apply(sk)
	assert_true(sk.get_bone_pose_rotation(sk.find_bone("spine_02")).is_equal_approx(before), "weight 0: clip untouched")
	v.free()

func _view():
	var a = Athlete.new()
	a.role = Athlete.Role.RB
	var v = PlayerNode.new()
	v.setup(a, Color(0.8, 0.2, 0.2))
	v._ready()   # unit tests run before the tree processes; build the rig directly
	return v

func _pos(sk: Skeleton3D, bone: String) -> Vector3:
	return sk.get_bone_global_pose(sk.find_bone(bone)).origin

## The skeleton at `anim` time t from the clip's own tracks (as test_athlete_pose.gd).
func _pose(sk: Skeleton3D, anim: Animation, t: float) -> void:
	sk.reset_bone_poses()
	for tr in anim.get_track_count():
		var bone := sk.find_bone(anim.track_get_path(tr).get_concatenated_subnames())
		if bone < 0:
			continue
		match anim.track_get_type(tr):
			Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(bone, anim.position_track_interpolate(tr, t))
			Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(tr, t))
			Animation.TYPE_SCALE_3D:
				sk.set_bone_pose_scale(bone, anim.scale_track_interpolate(tr, t))
	sk.force_update_all_bone_transforms()
