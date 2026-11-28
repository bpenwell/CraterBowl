extends RefCounted
## View-side jump (#379) for player.gd: a display-rate clock synced to the sim's `jump_t`,
## the body lift and the UAL jump clips. Lives here so player.gd (a shared switchboard) stays small.

const T := preload("res://src/sim/tuning.gd")
const LAND_POSE_TIME := 0.18   # s of Jump_Land after touching down

var vis_t := 0.0    # s left in the air as the view shows it; counts down at display rate
var land_t := 0.0   # s left of the landing pose

## Run our own clock so the arc is smooth between 60 Hz sim steps: snap to the sim on takeoff
## (or drift past 0.1 s) and drop it the moment the sim says we're down (landed or knocked over).
## Menu/POTG stub athletes have no jump state; null (a replay view) shows no jump.
func update(athlete, delta: float) -> void:
	var sim: float = athlete.jump_t if athlete != null and athlete.has_method("is_jumping") else 0.0
	if sim <= 0.0:
		if vis_t > 0.0:
			land_t = LAND_POSE_TIME
		vis_t = 0.0
	elif vis_t <= 0.0 or absf(vis_t - sim) > 0.1:
		vis_t = sim
	else:
		vis_t = maxf(0.001, vis_t - delta)
	land_t = maxf(0.0, land_t - delta)

## Feet height in yards (same parabola as Athlete.jump_height).
func lift() -> float:
	if vis_t <= 0.0:
		return 0.0
	var k := 1.0 - vis_t / T.JUMP_TIME
	return 4.0 * T.JUMP_HEIGHT * k * (1.0 - k)

## Play the jump clip on the view: Jump_Start for the first third of the hop, then the "Jump"
## tuck loop (UAL's Jump_Loop; the importer drops the _Loop suffix), then Jump_Land.
## False when no jump is showing.
func play(view) -> bool:
	if vis_t > 0.0:
		var up := vis_t > T.JUMP_TIME * (2.0 / 3.0)
		view._play("Jump_Start" if up else "Jump", 0.06 if up else 0.1, 1.6 if up else 1.0)
	elif land_t > 0.0:
		view._play("Jump_Land", 0.05, 1.8)
	else:
		return false
	return true
