extends "res://tests/test_case.gd"
## #426: a taunt or celebration from the dead ball doesn't carry into the next play, and a
## scorer who is down (dove into the end zone) gets up before he celebrates, ball in hand.

const PlayerNode := preload("res://src/game/player.gd")
const Athlete := preload("res://src/sim/athlete.gd")
const T := preload("res://src/sim/tuning.gd")
const World := preload("res://src/sim/world.gd")

func test_next_play_ends_a_taunt_and_a_celebration() -> void:
	var w := {"phase": World.Phase.DEAD}   # sync() only reads the phase here
	var v = _view(null, w)
	v.sync()
	v.emote_t = 1.8   # what emote() sets (its speech bubble needs a renderer)
	v.celebrate("dance")
	v.sync()
	assert_true(v.emote_t > 0.0 and v.celebrate_t > 0.0, "both play in the dead ball")
	w.phase = World.Phase.PRESNAP   # the next play lines up, even for a lineman who barely moved
	v.sync()
	assert_eq(v.emote_t, 0.0, "the taunt ends")
	assert_eq(v.celebrate_t, 0.0, "the celebration ends")
	v.free()

## The sim holds a dead ball's holder where he is (world.gd step), so a scorer who dove into
## the end zone stays grounded for the whole dead ball. The view gets him up, then he dances.
func test_down_scorer_gets_up_then_celebrates() -> void:
	var v = _view()
	v.athlete.recover_t = T.DIVE_RECOVER   # frozen: lying in the end zone
	v.celebrate("dance")
	var frames_down := 0
	for i in 120:
		v.sync()
		v._choose_anim(0.0, true)
		v.anim.advance(1.0 / 60.0)
		if v._cur == "Dance":
			break
		frames_down += 1
		assert_true(not v.is_celebrating(), "getting up: not celebrating, the ball stays in his hands")
	assert_eq(v._cur, "Dance", "after the get-up he dances")
	assert_true(frames_down > 20 and frames_down < 90, "the get-up plays first: %d frames" % frames_down)
	assert_true(v.is_celebrating() and v.celebrate_t == 1.5, "the celebration starts now, from the top (%.2f)" % v.celebrate_t)
	v.free()

func _view(a = null, world = null):
	if a == null:
		a = Athlete.new()
		a.role = Athlete.Role.RB
	var v = PlayerNode.new()
	v.setup(a, Color(0.8, 0.2, 0.2), world)
	v._ready()
	return v
