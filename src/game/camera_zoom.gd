extends RefCounted
## Mouse-wheel follow-camera zoom (#140). Pure math so it unit-tests on its own; main.gd
## owns the input and the camera, settings_store.gd persists the level.
##
## The zoom scales the follow-camera boom (FOLLOW_CAM_OFFSET, up and back together), so the
## camera dollies along the same 34° sight line and the #128 framing clamp keeps the ring
## above the scorebug at every level. 1.0 = the default (6 m up, 9 m back).
## - MIN 0.6: 3.6 m up, 5.4 m back. Well clear of a 2 m athlete; closer and the player
##   blocks the play in front of him.
## - MAX 1.6: 9.6 m up, 14.4 m back. Further out the controlled player gets too small to
##   read. The boom rises faster (0.67 m per m) than any stand (upper deck 0.65 m per m),
##   so even at MAX on the end line the camera stays above the seats.

const MIN := 0.6
const MAX := 1.6
const DEFAULT := 1.0
const STEP := 0.1      # zoom per wheel notch
const RATE := 10.0     # 1/s easing toward the target (frame-rate independent)

static func clamp_zoom(z: float) -> float:
	return clampf(z, MIN, MAX) if is_finite(z) else DEFAULT

## New target after `notches` wheel notches: + = wheel up = zoom in (camera closer).
## Trackpads send fractional notches. Snapped to 0.01 so repeated steps land exactly.
static func step(z: float, notches: float) -> float:
	return clamp_zoom(snappedf(z - notches * STEP, 0.01))

## Eased zoom shown this frame; reaches the target exactly once it's within 0.0005.
static func ease_toward(shown: float, target: float, delta: float) -> float:
	var v := lerpf(shown, target, 1.0 - exp(-RATE * delta))
	return target if absf(v - target) < 0.0005 else v
