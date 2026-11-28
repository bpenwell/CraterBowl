extends RefCounted
## Buffers snapshots by server time and samples interpolated positions. Pure.

const Tick := preload("res://src/sim/tick.gd")
const TICK_RATE := Tick.HZ   # snapshot ticks -> server seconds
const MAX_BUFFER := 32

var drawn_t := -INF   # last time draw_time returned
var buf: Array = []   # [[server_time, positions(PackedFloat32Array xy pairs), ball(Vector3), snapshot], ...]

func push(tick: int, athlete_xy: PackedFloat32Array, ball: Vector3, snap := {}) -> void:
	var t := tick / TICK_RATE
	if not buf.is_empty() and t <= buf[-1][0]:
		return  # out of order / duplicate
	buf.append([t, athlete_xy, ball, snap])
	if buf.size() > MAX_BUFFER:
		buf.pop_front()

## Server time to draw others at: `delay` behind the newest snapshot, advanced by the wall time since
## it arrived, and never earlier than the last draw. A hitch runs the wall clock ahead; the next
## snapshot would pull it back and replay flags (a landed diver standing up again, #421).
func draw_time(latest_tick: int, since_snapshot: float, delay: float) -> float:
	drawn_t = maxf(drawn_t, latest_tick / TICK_RATE + since_snapshot - delay)
	return drawn_t

func latest_time() -> float:
	return buf[-1][0] if not buf.is_empty() else 0.0

## Returns {"xy": PackedFloat32Array, "ball": Vector3, "snap": Dictionary} at server time t (clamped
## to buffer). "snap" is the pushed snapshot nearest t: its flags and timers go with the drawn position (#421).
func sample(t: float) -> Dictionary:
	if buf.is_empty():
		return {}
	if t <= buf[0][0]:
		return {"xy": buf[0][1], "ball": buf[0][2], "snap": buf[0][3]}
	if t >= buf[-1][0]:
		return {"xy": buf[-1][1], "ball": buf[-1][2], "snap": buf[-1][3]}
	for i in range(buf.size() - 1):
		var a = buf[i]
		var b = buf[i + 1]
		if t >= a[0] and t <= b[0]:
			var k: float = (t - a[0]) / maxf(b[0] - a[0], 0.0001)
			var xa: PackedFloat32Array = a[1]
			var xb: PackedFloat32Array = b[1]
			var out := PackedFloat32Array()
			out.resize(mini(xa.size(), xb.size()))
			for j in out.size():
				out[j] = lerpf(xa[j], xb[j], k)
			return {"xy": out, "ball": (a[2] as Vector3).lerp(b[2], k), "snap": a[3] if k < 0.5 else b[3]}
	return {"xy": buf[-1][1], "ball": buf[-1][2], "snap": buf[-1][3]}

## Extract athlete xy pairs from a protocol snapshot.
static func xy_from_snapshot(s: Dictionary) -> PackedFloat32Array:
	var a: PackedFloat32Array = s["a"]
	var out := PackedFloat32Array()
	for i in a.size() / 7:
		out.append(a[i * 7])
		out.append(a[i * 7 + 1])
	return out

static func ball_from_snapshot(s: Dictionary) -> Vector3:
	var b: PackedFloat32Array = s["b"]
	return Vector3(b[2], b[3], b[4])
