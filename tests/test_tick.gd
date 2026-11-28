extends "res://tests/test_case.gd"
## #61: one tick rate. src/sim/tick.gd is the source; project.godot, the running engine and every
## tick <-> seconds conversion must agree with it. Changing the physics rate in one place only
## used to silently break interpolation and replay timing.

const Tick := preload("res://src/sim/tick.gd")
const Interp := preload("res://src/net/interpolator.gd")
const Replay := preload("res://src/sim/replay.gd")

## Files that convert ticks to seconds. They must read Tick, not spell the rate out.
const DERIVED := ["res://src/net/interpolator.gd", "res://src/sim/replay.gd",
	"res://src/sim/world.gd", "res://src/game/player.gd"]

func test_project_sets_physics_rate_explicitly() -> void:
	var cf := ConfigFile.new()
	assert_eq(cf.load("res://project.godot"), OK, "project.godot loads")
	assert_true(cf.has_section_key("physics", "common/physics_ticks_per_second"),
		"project.godot sets physics/common/physics_ticks_per_second explicitly (not the engine default)")
	assert_eq(int(cf.get_value("physics", "common/physics_ticks_per_second", -1)), Tick.RATE,
		"project.godot physics_ticks_per_second == Tick.RATE")

func test_engine_runs_at_tick_rate() -> void:
	assert_eq(int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")), Tick.RATE,
		"ProjectSettings physics rate == Tick.RATE")
	assert_eq(Engine.physics_ticks_per_second, Tick.RATE, "Engine.physics_ticks_per_second == Tick.RATE")

func test_derived_rates_follow_tick() -> void:
	assert_eq(Tick.HZ, float(Tick.RATE), "Tick.HZ")
	assert_near(Tick.DT * Tick.RATE, 1.0, 1e-9, "Tick.DT is one tick")
	assert_eq(Interp.TICK_RATE, Tick.HZ, "interpolator converts snapshot ticks at Tick.HZ")
	assert_eq(Replay.FPS * Replay.FRAME_EVERY, Tick.HZ, "replay frames are FRAME_EVERY ticks")
	var it := Interp.new()
	it.push(Tick.RATE, PackedFloat32Array(), Vector3.ZERO)
	assert_near(it.latest_time(), 1.0, 1e-9, "Tick.RATE ticks of snapshots = 1 s of server time")

func test_no_hardcoded_rate_in_derived_sites() -> void:
	var re := RegEx.create_from_string("\\b60(\\.0*)?\\b|\\b0\\.016")
	for path in DERIVED:
		var src := FileAccess.get_file_as_string(path)
		assert_true(src.contains("tick.gd"), "%s reads src/sim/tick.gd" % path)
		var n := 0
		for line in src.split("\n"):
			n += 1
			var code: String = line.split("#")[0]
			if re.search(code):
				errors.append("%s:%d spells the tick rate out (%s); use Tick.RATE/HZ/DT" % [path, n, line.strip_edges()])
