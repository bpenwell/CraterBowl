extends "res://tests/test_case.gd"

const Cos := preload("res://src/sim/cosmetics.gd")
const World := preload("res://src/sim/world.gd")
const Roster := preload("res://src/sim/roster.gd")
const AI := preload("res://src/sim/ai.gd")

func test_unlocks_by_level_and_badges() -> void:
	var c := Cos.new()
	assert_true(c.is_unlocked("trim", "white"), "default")
	assert_eq(c.level(), 1, "new players start at Level 1")
	assert_true(not c.is_unlocked("trim", "volt"), "level 5 locked at 1")
	c.add_xp(4 * Cos.XP_PER_LEVEL - 1)
	assert_true(not c.is_unlocked("trim", "volt"), "still locked 1 XP short (same XP as before the 1-based shift)")
	c.add_xp(1)
	assert_eq(c.level(), 5)
	assert_true(c.is_unlocked("trim", "volt"))
	assert_true(not c.is_unlocked("badge", "S8100-Gold"), "badge needs the reward")
	c.season_rewards.append("S8100-Gold")
	assert_true(c.is_unlocked("badge", "S8100-Gold"))
	assert_true(c.unlocked("badge").has("S8100-Gold"))

func test_xp_award() -> void:
	assert_eq(Cos.award_xp({}, false), 100, "played")
	assert_eq(Cos.award_xp({"pass_yds": 120.0, "pass_td": 2.0}, true), 100 + 50 + 50 + 12)
	assert_eq(Cos.award_xp({"tkl": 3.0, "int": 1.0, "sack": 1.0}, false), 100 + 30 + 30 + 20)

func test_equip_rules() -> void:
	var c := Cos.new()
	assert_true(not c.equip("trim", "aurora"), "locked")
	assert_true(not c.equip("trim", "rainbow"), "unknown")
	assert_true(c.equip("number", 88))
	assert_true(not c.equip("number", 100), "number range")
	assert_true(c.equip("trim", "black"))
	assert_eq(c.equipped["trim"], "black")

func test_sanitize_look() -> void:
	var s := Cos.sanitize_look({"trim": "ember", "helmet": "hax", "number": 250, "celebration": "flip", "badge": "<script>"})
	assert_eq(s["trim"], "ember")
	assert_eq(s["helmet"], "plain", "unknown dropped")
	assert_eq(s["number"], 99, "clamped")
	assert_eq(s["badge"], "none", "bad badge dropped")
	assert_eq(Cos.sanitize_look("junk"), Cos.DEFAULT_LOOK)

func test_profile_round_trip() -> void:
	var path := "user://test_profile_rt.json"
	var c := Cos.new()
	c.add_xp(1200)
	c.equip("trim", "tide")
	c.equip("number", 7)
	assert_true(c.save(path))
	var c2 := Cos.new()
	c2.load_file(path)
	assert_eq(c2.xp, 1200)
	assert_eq(c2.equipped["trim"], "tide")
	assert_eq(c2.equipped["number"], 7)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_looks_never_touch_sim() -> void:
	# Cosmetics live outside the sim: two identical worlds stay identical no matter the looks.
	var ws := []
	for k in 2:
		var w := World.new()
		Roster.new().build(w, 3)
		w.setup_formation(20.0)
		w.snap()
		ws.append(w)
	var looks := [Cos.sanitize_look({"trim": "ember", "number": 88}), Cos.sanitize_look({"trim": "black", "celebration": "flip"})]
	assert_true(looks[0] != looks[1])
	var ai := [AI.new(), AI.new()]
	for i in 240:
		for k in 2:
			ws[k].step(ai[k].think(ws[k], []), 1.0 / 60.0)
	for j in ws[0].athletes.size():
		assert_true(ws[0].athletes[j].position.distance_to(ws[1].athletes[j].position) < 0.0001, "athlete %d identical" % j)
