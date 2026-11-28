extends RefCounted
## Ballistic pass solver. Sim space: (x, y) field, z height. Units yards/s.

const T := preload("res://src/sim/tuning.gd")

static func speed_for_power(power: float) -> float:
	return lerpf(T.THROW_SPEED_MIN, T.THROW_SPEED_MAX, clampf(power, 0.0, 1.0))

## Launch velocity for a POV throw: direction on the field plane, angle in degrees.
static func velocity_for(dir: Vector2, angle_deg: float, power: float) -> Vector3:
	var a := deg_to_rad(clampf(angle_deg, T.POV_ANGLE_MIN, T.POV_ANGLE_MAX))
	var s := speed_for_power(power)
	var d := dir.normalized()
	return Vector3(d.x * s * cos(a), d.y * s * cos(a), s * sin(a))

## Horizontal distance at which a ball launched at (speed, angle) from h0
## descends through height h1. Returns -1 if it never reaches h1 descending.
static func range_at(speed: float, angle: float, h0: float, h1: float, g: float = T.GRAVITY) -> float:
	var vz := speed * sin(angle)
	var vh := speed * cos(angle)
	# h0 + vz t - g t^2 / 2 = h1  -> g/2 t^2 - vz t + (h1 - h0) = 0
	var disc := vz * vz - 2.0 * g * (h1 - h0)
	if disc < 0.0:
		return -1.0
	var t := (vz + sqrt(disc)) / g
	return vh * t

## Initial 3D velocity to send the ball from `from` (z = release height) so it
## crosses `target` at catch height. Uses the flattest angle; if out of range,
## throws at 45 degrees (falls short).
static func solve_velocity(from: Vector3, target: Vector2, power: float, g: float = T.GRAVITY, lob: bool = false) -> Vector3:
	var s := speed_for_power(power)
	var flat := Vector2(target.x - from.x, target.y - from.y)
	var d := flat.length()
	var dir := flat.normalized() if d > 0.001 else Vector2(0, 1)
	if lob:
		return _solve_lob(s, dir, d, from.z, g)
	var lo := deg_to_rad(-10.0)
	var hi := deg_to_rad(45.0)
	var angle := hi
	if range_at(s, hi, from.z, T.CATCH_HEIGHT, g) >= d:
		for i in 40:
			var mid := (lo + hi) * 0.5
			if range_at(s, mid, from.z, T.CATCH_HEIGHT, g) < d:
				lo = mid
			else:
				hi = mid
		angle = hi
	var vh := s * cos(angle)
	return Vector3(dir.x * vh, dir.y * vh, s * sin(angle))

## Lob = touch pass: fixed steep arc (LOB_ANGLE); solve the launch speed so it
## lands exactly on target. Power is ignored (the arc, not the zip, matters).
static func _solve_lob(_s: float, dir: Vector2, d: float, h0: float, g: float) -> Vector3:
	var angle := deg_to_rad(T.LOB_ANGLE)
	var lo := 1.0
	var hi := T.THROW_SPEED_MAX
	for i in 50:
		var mid := (lo + hi) * 0.5
		if range_at(mid, angle, h0, T.CATCH_HEIGHT, g) < d:
			lo = mid
		else:
			hi = mid
	var s := hi
	return Vector3(dir.x * s * cos(angle), dir.y * s * cos(angle), s * sin(angle))

## Time for a ball with velocity v from height h0 to descend to h1.
static func time_to_height(v: Vector3, h0: float, h1: float, g: float = T.GRAVITY) -> float:
	var disc := v.z * v.z - 2.0 * g * (h1 - h0)
	if disc < 0.0:
		return 0.0
	return (v.z + sqrt(disc)) / g

## Predict the ground contact from the current pass position and velocity.
static func ground_landing(position: Vector3, velocity: Vector3, gravity: float) -> Vector2:
	var seconds := time_to_height(velocity, position.z, 0.0, gravity)
	return Vector2(position.x, position.y) + Vector2(velocity.x, velocity.y) * seconds

## Predict where a receiver moving at constant velocity will be when the ball arrives.
static func lead_target(from: Vector3, rx_pos: Vector2, rx_vel: Vector2, power: float, g: float = T.GRAVITY) -> Vector2:
	var target := rx_pos
	for i in 6:
		var v := solve_velocity(from, target, power, g)
		var t := time_to_height(v, from.z, T.CATCH_HEIGHT, g)
		target = rx_pos + rx_vel * t
	return target
