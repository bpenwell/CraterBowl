extends RefCounted
## Match recording + playback. Pure (file I/O via save/load only).

const Tick := preload("res://src/sim/tick.gd")
const FRAME_EVERY := 2           # physics ticks per frame (60 Hz -> 30 Hz)
const FPS := Tick.HZ / FRAME_EVERY
const HEADER := 4                # phase, ball x, y, z
const PER_ATHLETE := 3           # x, y, flags
## Per-athlete flag bits. 1 and 2 since v1; 4, 8 and 16 since v3 (older files: off).
const F_DIVING := 1
const F_GROUNDED := 2
const F_PUSH := 4                # pushing in a block (the view's push pose); set by the caller
const F_CATCH := 8               # reaching for a pass (the view's catch pose); set by the caller
const F_FAIR_CATCH := 16         # the returner signalling a fair catch (raised arm + label)
const END_EVENTS := ["tackle", "out_of_bounds", "touchdown", "incomplete", "explode"]
const BIG_PLAY_YARDS := 20.0     # gains (or losses) this long are highlights
const SLOWMO_TAIL := int(2.0 * FPS)  # frames (2 s) of slow motion at the end of a highlight clip
const SLOWMO_SPEED := 0.35

var frames: Array = []           # Array[PackedFloat32Array]
## [{start, end, label, summary, highlight, yards, los, off, kind, tags, context}]. Files from
## before B04 only have start/end/label, so readers use .get() with defaults.
var plays: Array = []
var meta := {}
var context := ""                # prefix for the next play's label (e.g. "Q2 3rd & 4"); set by the game
var _tick := 0
var _open := -1                  # index into plays of the play in progress
var _world = null

# --- recording ---
func attach(world) -> void:
	_world = world
	world.event.connect(record_event)

## Consume a local world event or a ruling relayed by the match host.
func record_event(n: String, d: Dictionary) -> void:
	if n == "snap":
		plays.append({"start": frames.size(), "end": frames.size(), "label": "Play %d" % (plays.size() + 1),
			"summary": "", "highlight": false, "yards": 0.0, "kind": "run", "tags": [], "context": context,
			"los": _world.los_y if _world else 0.0, "off": _world.offense_team if _world else 0, "qb": d.get("qb", -1)})
		_open = plays.size() - 1
		return
	if _open < 0:
		return
	var p: Dictionary = plays[_open]
	var tags: Array = p["tags"]
	match n:
		"throw":
			p["kind"] = "pass"
		"interception":
			if not tags.has("INTERCEPTION"):
				tags.append("INTERCEPTION")
		"recovery":
			if d.get("turnover", false) and not tags.has("FUMBLE LOST"):
				tags.append("FUMBLE LOST")
	if END_EVENTS.has(n):
		p["end"] = frames.size()
		_finish(_open, n, d)
		_open = -1

## Fill summary/yards/highlight/label for play `i`, which just ended with event `n`.
## Offense always attacks +y, so yards = end spot - line of scrimmage.
func _finish(i: int, n: String, d: Dictionary) -> void:
	var p: Dictionary = plays[i]
	var tags: Array = p["tags"]
	var turnover: bool = tags.has("INTERCEPTION") or tags.has("FUMBLE LOST") or int(d.get("team", p["off"])) != int(p["off"])
	if turnover and not (tags.has("INTERCEPTION") or tags.has("FUMBLE LOST")):
		tags.append("TURNOVER")
	var spot = d.get("spot", d.get("at", null))
	var yards := 0.0
	if spot is Vector2 and n != "incomplete" and n != "explode" and not turnover:
		var y: float = spot.y
		if _world:
			y = clampf(y, _world.field.goal_line_a(), _world.field.goal_line_b())
		yards = y - float(p["los"])
	if n == "touchdown":
		tags.append("TOUCHDOWN")
	if n == "tackle" and p["kind"] == "run" and int(d.get("carrier", -2)) == int(p["qb"]) and yards < 0.0:
		tags.append("SACK")
	var what: String
	if n == "incomplete":
		what = "pass incomplete"
	elif n == "explode":
		what = "ball exploded"
	elif turnover:
		what = "change of possession"
	else:
		var yd := int(round(yards))
		what = "%s for %s" % [p["kind"], "no gain" if yd == 0 else ("%d yd" % yd if yd > 0 else "a loss of %d" % -yd)]
		if n == "out_of_bounds":
			what += ", out of bounds"
	if tags.has("SACK"):
		what = "loss of %d" % int(round(-yards))
	p["yards"] = yards
	p["summary"] = what if tags.is_empty() else ("%s: %s" % [" + ".join(tags), what])
	p["highlight"] = not tags.is_empty() or absf(yards) >= BIG_PLAY_YARDS
	p["label"] = "Play %d%s: %s" % [i + 1, (" (%s)" % p["context"]) if p["context"] != "" else "", p["summary"]]

## `view_bits[i]` holds athlete i's F_PUSH / F_CATCH bits. Push and catch windows are view
## logic (player.gd replay_bits), so the game passes them in; empty = none. frame_due() says
## whether this call records a frame, so the game only computes them then.
func capture(world, view_bits := PackedByteArray()) -> void:
	_tick += 1
	if _tick % FRAME_EVERY != 0:
		return
	var f := PackedFloat32Array([world.phase, world.ball.position.x, world.ball.position.y, world.ball.position.z])
	var fair: int = world.fair_catch_id if int(world.phase) == 1 else -1
	for i in world.athletes.size():
		var a = world.athletes[i]
		var bits := (F_DIVING if a.is_diving() else 0) | (F_GROUNDED if a.is_grounded() else 0) \
			| (F_FAIR_CATCH if a.id == fair else 0) | (view_bits[i] if i < view_bits.size() else 0)
		f.append_array([a.position.x, a.position.y, float(bits)])
	frames.append(f)
	if _open >= 0:
		plays[_open]["end"] = frames.size()

## The next capture() call records a frame.
func frame_due() -> bool:
	return (_tick + 1) % FRAME_EVERY == 0

func last_play() -> Dictionary:
	var i := last_play_index()
	return plays[i] if i >= 0 else {}

func last_play_index() -> int:
	for i in range(plays.size() - 1, -1, -1):
		if plays[i]["end"] > plays[i]["start"]:
			return i
	return -1

## Indexes of finished highlight plays (TD, turnover, sack, 20+ yd), in order.
func highlights() -> Array:
	var out := []
	for i in plays.size():
		if plays[i].get("highlight", false) and plays[i]["end"] > plays[i]["start"] and i != _open:
			out.append(i)
	return out

# --- playback ---
var time := 0.0                  # in frames (fractional)
var speed := 1.0
var stop_at := -1.0              # clip end (frames) or -1 = end of match
var clip_start := 0.0            # clip start (frames); only meaningful while stop_at >= 0
var paused := false
var slowmo_from := -1.0          # frames; >= 0 slows playback from here to the clip end
var reel: Array = []             # play indexes still to show after the current clip

func play_range(start: int, end: int, spd: float = 1.0) -> void:
	time = float(start)
	clip_start = float(start)
	stop_at = float(end)
	speed = spd
	paused = false
	slowmo_from = -1.0

## Clip of one play at `spd` (<= 0 keeps the current speed). `highlight` adds a slow-motion finish.
func clip_play(i: int, spd: float = 1.0, highlight := false) -> bool:
	if i < 0 or i >= plays.size() or plays[i]["end"] <= plays[i]["start"]:
		return false
	play_range(plays[i]["start"], plays[i]["end"], spd if spd > 0.0 else speed)
	if highlight:
		slowmo_from = maxf(float(plays[i]["start"]), float(plays[i]["end"]) - SLOWMO_TAIL)
	return true

## Play several clips back to back (highlight reel). False if none are playable.
func start_reel(indexes: Array) -> bool:
	reel = indexes.duplicate()
	return next_in_reel()

func next_in_reel() -> bool:
	while not reel.is_empty():
		if clip_play(reel.pop_front(), 1.0, true):
			return true
	return false

## The first highlight after the current play (wrapping), or -1.
func next_highlight() -> int:
	var hs := highlights()
	if hs.is_empty():
		return -1
	var cur := current_play()
	for i in hs:
		if i > cur:
			return i
	return hs[0]

func seek_play(i: int) -> void:
	if i >= 0 and i < plays.size():
		time = float(plays[i]["start"])
		stop_at = -1.0
		slowmo_from = -1.0

func current_play() -> int:
	for i in range(plays.size() - 1, -1, -1):
		if time >= plays[i]["start"]:
			return i
	return 0

## Move by whole frames (frame-step while paused), clamped to the clip.
func step_frames(n: int) -> void:
	if frames.is_empty():
		return
	time = clampf(floor(time) + n, clip_start if stop_at >= 0.0 else 0.0, _limit())

## 0..1 through the current clip (or the whole match when not clipped).
func progress() -> float:
	if frames.is_empty():
		return 0.0
	var lo := clip_start if stop_at >= 0.0 else 0.0
	return clampf((time - lo) / maxf(1.0, _limit() - lo), 0.0, 1.0)

func effective_speed() -> float:
	return speed * (SLOWMO_SPEED if slowmo_from >= 0.0 and time >= slowmo_from else 1.0)

func advance(dt: float) -> void:
	if paused or frames.is_empty():
		return
	time = minf(time + dt * FPS * effective_speed(), _limit())

func _limit() -> float:
	var last := float(frames.size() - 1)
	return minf(stop_at, last) if stop_at >= 0.0 else last

func ended() -> bool:
	return frames.is_empty() or time >= _limit()

func athlete_count() -> int:
	return 0 if frames.is_empty() else (frames[0].size() - HEADER) / PER_ATHLETE

## {"ball": Vector3, "pos": Array[Vector2], "flags": Array[int], "phase": int} at the current time.
func sample() -> Dictionary:
	if frames.is_empty():
		return {}
	var i := clampi(int(floor(time)), 0, frames.size() - 1)
	var j := mini(i + 1, frames.size() - 1)
	var k := clampf(time - float(i), 0.0, 1.0)
	var a: PackedFloat32Array = frames[i]
	var b: PackedFloat32Array = frames[j]
	var pos := []
	var flags := []
	for n in athlete_count():
		var o := HEADER + n * PER_ATHLETE
		pos.append(Vector2(lerpf(a[o], b[o], k), lerpf(a[o + 1], b[o + 1], k)))
		flags.append(int(a[o + 2]))
	return {"ball": Vector3(lerpf(a[1], b[1], k), lerpf(a[2], b[2], k), lerpf(a[3], b[3], k)), "pos": pos, "flags": flags, "phase": int(a[0])}

# --- persistence ---
func save(path: String) -> bool:
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	f.store_var({"version": 3, "meta": meta, "plays": plays, "frames": frames})
	return true

func load_file(path: String) -> bool:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	var d = f.get_var(false)   # never decode objects
	if not (d is Dictionary) or not (d.get("frames") is Array):
		return false
	frames = d["frames"]
	plays = d.get("plays", [])
	meta = d.get("meta", {})
	time = 0.0
	stop_at = -1.0
	slowmo_from = -1.0
	reel = []
	return true
