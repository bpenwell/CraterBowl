extends "res://tests/test_case.gd"
## The sim must be deterministic: same inputs -> bit-identical state. Netcode
## reconciliation (the client re-runs unacked inputs through World.predict_step) and
## every perf refactor of src/sim rely on this. Replays do not: src/sim/replay.gd
## records positions every frame, not inputs. If a change makes this fail, it changed
## behavior (not just speed); see docs/optimization/README.md.

const World := preload("res://src/sim/world.gd")
const Match := preload("res://src/sim/match.gd")
const Roster := preload("res://src/sim/roster.gd")
const AI := preload("res://src/sim/ai.gd")

## Run an all-bot game and return a state fingerprint every second.
func _run(size: int, mode: String, seconds: float) -> Array:
	var w := World.new()
	w.set_ruleset(mode)
	Roster.new().build(w, size)
	var m := Match.new(w)
	m.start(0, 25.0)
	var ai := AI.new()
	var prints := []
	var dead_t := 0.0
	var dt := 1.0 / 60.0
	for i in int(seconds * 60.0):
		m.tick(dt)
		ai.presnap_tick(w, [], dt, m.downs.down, m.downs.distance())
		w.step(ai.think(w, []), dt)
		if w.phase == World.Phase.DEAD:
			dead_t += dt
			if dead_t > 0.5:
				m.next_play()
				dead_t = 0.0
		if i % 60 == 59:
			var s := [w.phase, m.score, w.ball.position, m.downs.los]
			for a in w.athletes:
				s.append(a.position)
				s.append(a.velocity)
				s.append(a.stumble_t)   # #389: stumble state must replay bit-identically too
				s.append(a.stumble_tier)
			prints.append(var_to_str(s))
	return prints

func test_classic_7v7_is_deterministic() -> void:
	var a := _run(7, "classic", 90.0)
	var b := _run(7, "classic", 90.0)
	assert_eq(a.size(), 90, "fingerprints")
	for i in a.size():
		if a[i] != b[i]:
			assert_true(false, "7v7 diverged at second %d" % (i + 1))
			return

func test_chaosball_is_deterministic() -> void:
	var a := _run(3, "chaosball", 60.0)
	var b := _run(3, "chaosball", 60.0)
	assert_eq(a, b, "chaosball fingerprints")
