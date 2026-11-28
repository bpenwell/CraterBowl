extends SceneTree
## #250: touchdown fireworks across a freed match scene. Run headless by
## tests/test_presentation.gd, which fails on any engine error in this script's output:
## freeing main.tscn while the fireworks' ignition timers were armed used to log
## `Lambda capture at index 0 was freed` when they fired.
## 1. Fireworks in a live match: all 6 bursts ignite on their 0.25 s stagger.
## 2. Fireworks again, then free the match scene before any timer fires; run past them all.

const FIRE := 5        # frame the first fireworks go off
const LOOK := 84       # 1.4 s later: every burst has ignited (last at 1.25 s, lifetime 1.6 s)
var main
var pres
var frame := 0
var ok := true

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)

func _process(_dt: float) -> bool:
	frame += 1
	if frame == FIRE:
		pres = main.pres
		pres._fireworks()
	elif frame == FIRE + LOOK:
		var lit := 0
		for c in pres.get_children():
			if c is CPUParticles3D and c.amount == 60 and c.emitting:
				lit += 1
		_check(lit == 6, "all 6 fireworks bursts ignited (%d)" % lit)
		pres._fireworks()   # what a touchdown (or the coin-toss roar, #129) runs
		main.queue_free()   # leave the match before the new ignition timers fire
	elif frame == FIRE + LOOK + 4 * 60:   # 4 s: past every fireworks timer (3.5 s max)
		_check(not is_instance_valid(main), "match scene freed")
		print("FIREWORKS FREE DONE")
		quit(0 if ok else 1)
	return false

func _check(cond: bool, msg: String) -> void:
	print(("  FIREWORKS OK   " if cond else "  FIREWORKS FAIL ") + msg)
	ok = ok and cond
