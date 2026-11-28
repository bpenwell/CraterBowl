extends "res://tests/test_case.gd"
## #68 kick art: stepped power meter + kickoff tee (src/game/kick_art.gd). The scene-level
## behavior (meter beside your kicker, ball on the tee) is asserted in tests/game_flow.gd
## (frames 9503-9506, 11140) and captured by tests/visual/kick_meter_test.gd.

const KickArt := preload("res://src/game/kick_art.gd")
const World := preload("res://src/sim/world.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const R := Athlete.Role

func _world() -> World:
	var w := World.new()
	var cx := w.field.width / 2.0
	for t in 2:
		w.add_two_way(t, R.C, cx, R.DL, cx - 1.5)
		w.add_two_way(t, R.QB, cx, R.LB, cx)
		w.add_two_way(t, R.WR, cx - 18.0, R.CB, cx - 18.0)
	return w

## Free a KickArt built outside the tree without the dummy renderer's freed-mesh error.
func _free(art) -> void:
	var keep: Array = [art.meter.mesh, art.tee.mesh]
	art.free()
	keep.clear()

func test_steps_follow_power() -> void:
	assert_eq(KickArt.STEPS, 10, "ten steps")
	assert_eq(KickArt.steps_for(0.0), 1, "a kick always lights the first step")
	assert_eq(KickArt.steps_for(0.05), 1, "5% -> 1")
	assert_eq(KickArt.steps_for(0.1), 1, "exactly 10% -> 1 (no float spill into step 2)")
	assert_eq(KickArt.steps_for(0.3), 3, "30% -> 3")
	assert_eq(KickArt.steps_for(0.31), 4, "31% -> 4")
	assert_eq(KickArt.steps_for(0.85), 9, "default kickoff power -> 9")
	assert_eq(KickArt.steps_for(1.0), 10, "full power -> all 10")
	assert_eq(KickArt.steps_for(2.0), 10, "out of range (FG past max) -> all 10")
	var prev := 0
	for i in 101:
		var n := KickArt.steps_for(i / 100.0)
		assert_true(n >= prev, "monotonic in power (%d%%)" % i)
		prev = n

func test_meter_pushes_only_on_change() -> void:
	var art = KickArt.new()
	art.set_steps(4)
	art.set_steps(4)
	art.set_steps(4)
	assert_eq(art.pushes, 1, "same step count: one push")
	art.set_steps(7)
	assert_eq(art.pushes, 2, "new step count: one more push")
	assert_eq(art.meter.material_override.get_shader_parameter("lit"), 7, "shader sees the lit count")
	assert_eq(art.meter.material_override.get_shader_parameter("steps"), KickArt.STEPS, "shader sees the step count")
	_free(art)

func test_meter_and_tee_cast_no_shadows_and_start_hidden() -> void:
	var art = KickArt.new()
	for n in [art.meter, art.tee]:
		assert_eq(n.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no shadow" % n.name)
		assert_true(not n.visible, "%s hidden until a kick" % n.name)
	_free(art)

func test_ball_on_tee_only_before_a_kickoff() -> void:
	var w := _world()
	w.setup_formation(25.0)
	assert_true(not KickArt.ball_on_tee(w), "scrimmage play: no tee")
	w.call_kick("punt")
	assert_true(not KickArt.ball_on_tee(w), "punt: no tee")
	w.setup_kickoff(35.0)
	assert_true(KickArt.ball_on_tee(w), "kickoff presnap: ball on the tee")
	assert_true(w.kick(w.kicker().id, Vector2(w.field.width / 2.0, 90.0), 0.8), "kick it")
	assert_true(not KickArt.ball_on_tee(w), "kicked: off the tee")
