extends "res://src/sim/player_motion.gd"
## An athlete on the field: motion + identity + dive/recover state.

enum Role { QB, C, WR, RB, LB, CB, S, OL, DL }

var id: int = 0
var team: int = 0
var role: Role = Role.WR
var dive_t := 0.0
var recover_t := 0.0
var home_x := 0.0          # formation x for the current side
var off_role: Role = Role.WR
var def_role: Role = Role.LB
var off_x := 0.0
var def_x := 0.0
var engaged_with := -1   # id of blocker (on defender) or defender (on blocker)
var engage_t := 0.0
var immune_t := 0.0
var blocking := false
var move_charge := 2.0
var move_t := 0.0
var spin_move := false
var spin_dir := 0          # -1 left, +1 right: which way the last spin turned (visual)
var emote_cd := 0.0        # taunt rate limit (cosmetic)
var set_lock := false    # pre-snap: held in stance until break_stance (defense)

func _init(p_id: int = 0, p_team: int = 0, p_role: Role = Role.WR, start: Vector2 = Vector2.ZERO, f = null) -> void:
	super(start, f)
	id = p_id
	team = p_team
	role = p_role
	home_x = start.x
	off_role = p_role
	def_role = p_role
	off_x = start.x
	def_x = start.x

## Switch to this side's role + formation x.
func set_side(on_offense: bool) -> void:
	role = off_role if on_offense else def_role
	home_x = off_x if on_offense else def_x

func is_diving() -> bool:
	return dive_t > 0.0

func is_grounded() -> bool:
	return recover_t > 0.0

func can_act() -> bool:
	return not is_diving() and not is_grounded()

## Turn toward dir without moving (stance-locked athletes can still look around).
func face(dir: Vector2) -> void:
	velocity = Vector2.ZERO
	if dir.length_squared() > 0.0001:
		facing = dir.normalized()

func start_move(spin: bool, direction: Vector2) -> bool:
	if move_charge < 1.0 or move_t > 0.0 or not can_act():
		return false
	if not direction.is_zero_approx():
		facing = direction.normalized()
	move_charge -= 1.0
	move_t = T.SPIN_TIME if spin else T.DASH_TIME
	spin_move = spin
	blocking = false
	return true

func is_spinning() -> bool:
	return move_t > 0.0 and spin_move

func start_dive() -> bool:
	if not can_act() or move_t > 0.0:
		return false
	blocking = false
	dive_t = T.DIVE_TIME
	return true

func reset_state() -> void:
	dive_t = 0.0
	recover_t = 0.0
	engaged_with = -1
	engage_t = 0.0
	immune_t = 0.0
	blocking = false
	move_t = 0.0
	velocity = Vector2.ZERO

func step(input: Vector2, wants_sprint: bool, dt: float, wants_block := false, speed_scale := 1.0) -> void:
	blocking = wants_block and can_act() and move_t <= 0.0
	emote_cd = maxf(0.0, emote_cd - dt)
	if dive_t > 0.0:
		dive_t -= dt
		velocity = facing * (T.DIVE_SPEED * speed_scale)
		position = field.clamp_playable(position + velocity * dt)
		if dive_t <= 0.0:
			dive_t = 0.0
			recover_t = T.DIVE_RECOVER
		return
	if recover_t > 0.0:
		recover_t = maxf(0.0, recover_t - dt)
		velocity = velocity.move_toward(Vector2.ZERO, T.DECEL * 2.0 * dt)
		position = field.clamp_playable(position + velocity * dt)
		return
	if move_t > 0.0:
		velocity = facing * ((T.SPIN_SPEED if spin_move else T.DASH_SPEED) * speed_scale)
		position = field.clamp_playable(position + velocity * dt)
		move_t = maxf(0.0, move_t - dt)
		last_sprinting = false
		return
	super.step(input, wants_sprint, dt, blocking, speed_scale)
