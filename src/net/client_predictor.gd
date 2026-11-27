extends RefCounted
## Client-side prediction for the local athlete. Pure.

const MAX_PENDING := 240

var seq := 0
var pending: Array = []   # [[seq, dir, sprint, dt, block], ...]

## Record a new local input; returns its seq. Caller steps the athlete locally.
func record(dir: Vector2, sprint: bool, dt: float, block := false) -> int:
	seq += 1
	pending.append([seq, dir, sprint, dt, block])
	if pending.size() > MAX_PENDING:
		pending.pop_front()
	return seq

## Reset athlete to authoritative state (already applied by caller), drop acked
## inputs and replay the rest on top.
## With `world`, replays use the same movement rules as the host.
func reconcile(athlete, acked_seq: int, world = null) -> void:
	while not pending.is_empty() and pending[0][0] <= acked_seq:
		pending.pop_front()
	for p in pending:
		if world != null:
			world.predict_step(athlete, p[1], p[2], p[3], p[4])
		else:
			athlete.step(p[1], p[2], p[3], p[4])
