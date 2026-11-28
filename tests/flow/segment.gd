extends RefCounted
## One self-contained game_flow segment. Add new end-to-end coverage as a file in
## tests/flow/segments/ instead of more steps in tests/game_flow.gd's shared array, so
## parallel PRs don't all edit the same lines.
##
## - steps() returns [relative_frame, callable] pairs (frame 1 = the first frame after
##   setup()). The runner (tests/flow/segments.gd) places each segment after the previous one,
##   so there's no shared frame timeline to claim a window in.
## - Before setup() the runner puts main's test knobs (auto_next, pov_enabled, overrides, …)
##   back to their boot values, so a segment never inherits another one's settings.
## - Keep the segment's state in its own vars, not in game_flow.gd's.
## - Run one segment on its own: `godot --headless --path . --fixed-fps 60
##   -s res://tests/game_flow.gd -- --segment=<file name without .gd>`

var flow    # the game_flow.gd SceneTree: check(), _key(), _mouse(), _wheel(), _hold(), …
var main    # the live main scene (scenes/main.tscn)
var name := ""

## A fresh 7v7 match by default. Override to set up something else (practice, 3v3, …).
func setup() -> void:
	main.configure(7)

func steps() -> Array:
	return []

func check(cond: bool, msg: String) -> void:
	flow.check(cond, msg)
