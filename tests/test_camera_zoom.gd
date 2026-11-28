extends "res://tests/test_case.gd"
## #140 mouse-wheel camera zoom: the pure step/clamp/ease math, the limits' geometry and
## settings persistence. The input routing (wheel through main._unhandled_input, ignored in
## POV aim / taunt wheel / replay) is driven in tests/game_flow.gd, frames 12300-12390.

const Z := preload("res://src/game/camera_zoom.gd")
const Settings := preload("res://src/ui/settings_store.gd")
const T := preload("res://src/sim/tuning.gd")
const TMP := "user://test_camera_zoom.cfg"

func test_wheel_steps_and_clamps() -> void:
	assert_near(Z.step(1.0, 1.0), 0.9, 0.0001, "wheel up = closer")
	assert_near(Z.step(1.0, -1.0), 1.1, 0.0001, "wheel down = further")
	assert_near(Z.step(1.0, 0.5), 0.95, 0.0001, "trackpad fractions")
	var z := Z.DEFAULT
	for i in 50:
		z = Z.step(z, 1.0)
	assert_eq(z, Z.MIN, "clamped at the near limit")
	assert_eq(Z.step(Z.MIN, 1.0), Z.MIN, "wheel up at MIN stays at MIN")
	for i in 50:
		z = Z.step(z, -1.0)
	assert_eq(z, Z.MAX, "clamped at the far limit")
	assert_eq(Z.step(Z.MAX, -1.0), Z.MAX, "wheel down at MAX stays at MAX")
	z = Z.DEFAULT
	for i in 3:
		z = Z.step(z, -1.0)
	for i in 3:
		z = Z.step(z, 1.0)
	assert_eq(z, Z.DEFAULT, "three notches out and back lands exactly on the default")
	assert_eq(Z.clamp_zoom(NAN), Z.DEFAULT, "NaN -> default")
	assert_eq(Z.clamp_zoom(9.0), Z.MAX, "over -> MAX")

func test_easing_is_smooth_and_frame_rate_independent() -> void:
	var one := Z.ease_toward(1.0, 1.6, 0.1)
	var two := Z.ease_toward(Z.ease_toward(1.0, 1.6, 0.05), 1.6, 0.05)
	assert_near(one, two, 0.0001, "one 0.1 s frame == two 0.05 s frames")
	assert_true(one > 1.0 and one < 1.6, "eases, doesn't jump (%.3f)" % one)
	var v := 1.0
	for i in 120:
		v = Z.ease_toward(v, 1.6, 1.0 / 60.0)
	assert_eq(v, 1.6, "settles exactly on the target within 2 s")

## The limits keep the camera out of the player and out of the stands.
func test_limits_clear_the_player_and_the_stands() -> void:
	var m = load("res://scenes/main.tscn").instantiate()
	var near: Vector3 = m.FOLLOW_CAM_OFFSET * Z.MIN
	assert_true(near.y > 2.0 + 1.0 and near.z > 2.0, "MIN boom %s is well clear of a 2 m athlete" % near)
	# stadium.gd: the wall ribbon (1.3 m) stands 10 yd past the end line (12 past the
	# sidelines); lower bowl rises 0.62 per 1.15 tread, upper deck 0.78 per 1.2. Players can
	# stand OOB_MARGIN past the line. The boom's sight line rises faster than any stand and is
	# already above the wall there, so no zoom level can put the camera in the seats.
	var slope: float = m.FOLLOW_CAM_OFFSET.y / m.FOLLOW_CAM_OFFSET.z
	assert_true(slope > 0.78 / 1.2 and slope > 0.62 / 1.15, "boom slope %.2f beats every stand's rise" % slope)
	var at_wall: float = (10.0 - T.OOB_MARGIN) * slope
	assert_true(at_wall > 1.3 + 1.0, "boom is %.1f m up at the end-zone wall" % at_wall)
	m.free()

func test_zoom_persists_in_settings() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var s := Settings.new()
	assert_eq(s.camera_zoom, Z.DEFAULT, "fresh settings use the default zoom")
	s.camera_zoom = 1.3
	assert_true(s.save(TMP), "saved")
	var back := Settings.new()
	back.load_file(TMP)
	assert_near(back.camera_zoom, 1.3, 0.0001, "zoom survives a save/load")
	var cf := ConfigFile.new()
	cf.load(TMP)
	cf.set_value("camera", "zoom", 40.0)
	cf.save(TMP)
	back.load_file(TMP)
	assert_eq(back.camera_zoom, Z.MAX, "a hand-edited out-of-range zoom loads clamped")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
