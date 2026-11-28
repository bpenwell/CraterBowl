extends "res://tests/test_case.gd"
## #426: a taunt from the dead ball doesn't carry into the next play, and a scorer who is
## down (dove into the end zone) gets up before he celebrates, the ball still in his hands.

const PlayerNode := preload("res://src/game/player.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const T := preload("res://src/sim/tuning.gd")

func test_next_play_teleport_ends_a_taunt() -> void:
	var v = _view()
	v.place(Vector3(10, 0, -20), 0.0)
	v.emote("nod")
	assert_true(v.emote_t > 0.0, "the taunt plays")
	v.place(Vector3(10.1, 0, -20), 0.0)
	assert_true(v.emote_t > 0.0, "a step during the dead ball keeps it")
	v.place(Vector3(30, 0, -45), 0.0)   # the next play lines him up somewhere else
	assert_eq(v.emote_t, 0.0, "the next play's teleport ends it")
	v.free()

func test_down_scorer_celebrates_after_getting_up() -> void:
	var v = _view()
	v.athlete.recover_t = T.DIVE_RECOVER   # lying in the end zone after a dive
	v.celebrate("dance")
	for i in 30:
		v.sync()
	assert_eq(v.celebrate_t, 1.5, "the celebration waits while he is down")
	assert_true(not v.is_celebrating(), "not celebrating yet, so the ball stays in his hands")
	v._choose_anim(0.0, true)
	assert_true(v._cur != "Dance", "no dance on the turf (%s)" % v._cur)
	v.athlete.recover_t = 0.0
	v.sync()
	assert_true(v.is_celebrating() and v.celebrate_t < 1.5, "up: the celebration runs")
	v._choose_anim(0.0, false)
	assert_eq(v._cur, "Dance", "and he dances")
	v.free()

func _view():
	var a = Athlete.new()
	a.role = Athlete.Role.RB
	var v = PlayerNode.new()
	v.setup(a, Color(0.8, 0.2, 0.2))
	v._ready()
	return v
