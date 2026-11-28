extends "res://tests/visual/harness.gd"
## #397: a real loopback joiner shows a remote diver lying on the turf before the get-up,
## with the same dive and ground timing as the host.
## #421: the joiner applies the dive and ground flags on the interpolated (INTERP_DELAY) timeline,
## so the dive clip starts with the lunge and the diver lies where it landed.

const NetSession := preload("res://src/net/net_session.gd")
const Protocol := preload("res://src/net/protocol.gd")
const Replay := preload("res://src/sim/replay.gd")
const Tick := preload("res://src/sim/tick.gd")
const T := preload("res://src/sim/tuning.gd")
const DIVER := 1   # a remote athlete: the joiner is seat 3

var game
var hosted_match
var host := NetSession.new()
var tick := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.opening_kickoff = false
	game.configure(3)
	game.pov_enabled = false
	var world = game.World.new()
	game.Roster.new().build(world, 3)
	hosted_match = game.Match.new(world)
	hosted_match.start(0, 25.0)
	root.add_child(host)
	host.match_size = 3
	var port := 30000 + randi() % 20000
	var result := host.host(port, func(_peer): return 3, func(_peer): pass)
	check(result == OK, "loopback host bound its port")
	if result != OK:
		finish()
		return
	world.event.connect(host.broadcast_event)
	game._join_game("127.0.0.1", port, {})
	for frame in 120:
		if game.net.my_athlete >= 0:
			break
		await process_frame
	check(game.net.my_athlete == 3, "real client joined the host")
	if game.net.my_athlete != 3:
		finish()
		return
	await _advance(4)
	check(world.snap(), "down snapped")
	await _advance(4)

	# The diver lands beside the joiner's athlete, so the joiner's camera frames it.
	var diver = world.athletes[DIVER]
	diver.position = world.athletes[3].position + Vector2(-4.0, 1.0)
	diver.facing = Vector2.RIGHT
	await _advance(20)   # let the joiner's interpolation settle on the moved diver
	var seen = game.world.athletes[DIVER]
	var view = game.views[DIVER]
	var start_pos: Vector2 = seen.position
	check(start_pos.distance_to(diver.position) < 0.01, "joiner's diver settled before the dive")
	check(diver.start_dive(), "host starts the remote dive")
	var lunge_at := -1
	var dive_on := -1
	var land_pos := Vector2.ZERO
	var land_gap := -1.0
	var saw_dive := false
	var host_down := -1
	var host_up := -1
	var client_down := -1
	var client_up := -1
	var lay_at := -1
	var first_recover := 0.0
	var captured := false
	for i in 150:
		await _advance(1)
		if host_down < 0 and diver.is_grounded():
			host_down = tick
			land_pos = diver.position
		if lunge_at < 0 and seen.position.distance_to(start_pos) > 0.05:
			lunge_at = tick
		if dive_on < 0 and seen.is_diving():
			dive_on = tick
		if host_down >= 0 and host_up < 0 and not diver.is_grounded():
			host_up = tick
		saw_dive = saw_dive or seen.is_diving()
		if client_down < 0 and seen.is_grounded():
			client_down = tick
			first_recover = seen.recover_t
			land_gap = seen.position.distance_to(land_pos)
			# The diver goes down where it landed, not a lunge-length short of it.
			check(view.is_inside_tree(), "joiner has the diver's view")
			await capture("remote-dive-landing")
		if client_down >= 0 and client_up < 0 and not seen.is_grounded():
			client_up = tick
		if client_down >= 0 and lay_at < 0 and view._cur == "u2/LayToIdle":
			lay_at = tick
		# 0.15 s into the host's ground time (decoded, so not tied to packet timing): still lying down.
		if client_down >= 0 and not captured and seen.recover_t <= T.DIVE_RECOVER - 0.15:
			captured = true
			check(view._cur == "u2/Slide", "joiner shows the lying clip 0.15 s after landing (got %s)" % view._cur)
			await capture("remote-dive-lying")
		if client_up >= 0 and host_up >= 0:
			break
	print("DIVE397 host_down=%d host_up=%d client_down=%d client_up=%d lay_at=%d first_recover=%.3f" % [
		host_down, host_up, client_down, client_up, lay_at, first_recover])
	print("DIVE421 lunge_at=%d dive_on=%d land_gap=%.2f" % [lunge_at, dive_on, land_gap])
	check(saw_dive, "joiner sees the dive flag")
	check(lunge_at >= 0 and absi(dive_on - lunge_at) <= Replay.FRAME_EVERY,   # flags step once per snapshot
		"dive flag starts with the interpolated lunge (flag %d, lunge %d)" % [dive_on, lunge_at])
	check(land_gap >= 0.0 and land_gap < 0.6,   # ~3 ticks of dive; the bug was 1.1 m
		"joiner's diver goes down at the landing spot (%.2f m off)" % land_gap)
	check(host_down >= 0 and client_down >= 0, "host and joiner both see the diver grounded")
	check(first_recover >= T.DIVE_RECOVER - 0.15,   # the bug decoded 0.01 s
		"joiner decodes the remaining ground time (%.3f s)" % first_recover)
	var host_ticks := host_up - host_down
	var client_ticks := client_up - client_down
	check(client_up >= 0 and absi(client_ticks - host_ticks) <= 2 * Replay.FRAME_EVERY + 1,   # slow CI batches packets
		"joiner's ground time matches the host's (%d vs %d ticks)" % [client_ticks, host_ticks])
	var lie_ticks := lay_at - client_down
	var expect_lie := roundi((T.DIVE_RECOVER - 0.7) * Tick.RATE)
	check(lay_at >= 0 and lie_ticks >= expect_lie - Replay.FRAME_EVERY - 1,
		"joiner lies ~%d ticks before the get-up clip (got %d)" % [expect_lie, lie_ticks])
	finish()

func _advance(count: int) -> void:
	for i in count:
		tick += 1
		hosted_match.world.step({}, Tick.DT)
		if tick % Replay.FRAME_EVERY == 0:
			host.broadcast_snapshot(Protocol.encode_snapshot(hosted_match, tick))
		await process_frame
		# One sim tick per frame here, whatever the wall clock does (captures stall it): pin the
		# joiner's draw clock to ticks so the checks don't depend on frame pacing.
		game.latest_snap_at = Time.get_ticks_msec() / 1000.0 - (tick - game.latest_snap_tick) / Tick.HZ
		game._physics_process(Tick.DT)
