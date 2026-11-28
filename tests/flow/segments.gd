extends RefCounted
## Loads tests/flow/segments/*.gd (see tests/flow/segment.gd) and appends their steps after
## game_flow.gd's own steps, one segment after another in file-name order.

const DIR := "res://tests/flow/segments"
const GAP := 30   # frames between segments, so the last one's events settle
## main's test knobs; each segment starts from the values they had at boot, except
## SEGMENT_DEFAULTS: a scripted segment starts on a scrimmage snap (no coin toss) and never
## advances or replays on its own. A segment that wants the toss sets opening_kickoff itself.
const KNOBS := ["auto_next", "auto_replay", "opening_kickoff", "toss_seed", "pov_enabled",
	"input_override", "sprint_override", "lob_override", "mouse_captured_override"]
const SEGMENT_DEFAULTS := {"auto_next": false, "auto_replay": false, "opening_kickoff": false}

## `steps` must already be sorted by frame. With `-- --segment=NAME` only frames <= 2 of the
## legacy steps (listeners, isolated user files) run, then that one segment.
static func append(flow, steps: Array) -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--segment="):
			only = a.trim_prefix("--segment=")
	if only != "":
		var keep: Array = steps.filter(func(s): return s[0] <= 2)
		steps.clear()
		steps.append_array(keep)
	var boot := {}
	for k in KNOBS:
		boot[k] = SEGMENT_DEFAULTS.get(k, flow.main.get(k))
	var start: int = (steps[-1][0] if not steps.is_empty() else 0) + GAP
	var found := 0
	for f in _files():
		var seg_name: String = f.get_basename()
		if only != "" and seg_name != only:
			continue
		var seg = load(DIR.path_join(f)).new()
		seg.flow = flow
		seg.main = flow.main
		seg.name = seg_name
		var rel: Array = seg.steps()
		rel.sort_custom(func(a, b): return a[0] < b[0])
		var last: int = rel[-1][0] if not rel.is_empty() else 0
		print("  FLOW SEGMENT %s: frames %d-%d" % [seg_name, start, start + last])
		steps.append([start, func(): _reset_knobs(flow.main, boot); seg.setup()])
		for s in rel:
			assert(s[0] >= 1, "segment %s: relative frames start at 1" % seg_name)
			steps.append([start + s[0], s[1]])
		start += last + GAP
		found += 1
	if only != "" and found == 0:
		flow.check(false, "no segment named %s in %s" % [only, DIR])

static func _reset_knobs(main, boot: Dictionary) -> void:
	for k in boot:
		main.set(k, boot[k])

static func _files() -> Array:
	var out := []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(f)
	out.sort()
	return out
