extends "res://tests/test_case.gd"

const Athlete := preload("res://src/sim/athlete.gd")
const Predictor := preload("res://src/net/client_predictor.gd")
const Interp := preload("res://src/net/interpolator.gd")
const P := preload("res://src/net/protocol.gd")
const NetSession := preload("res://src/net/net_session.gd")
const DT := 1.0 / 60.0

class LocalHost extends NetSession:
	func _send(_target: int, _msg: Dictionary, _reliable: bool) -> void:
		pass

func _input_host() -> LocalHost:
	var host := LocalHost.new()
	host.mode = NetSession.Mode.SERVER
	host.release_fn = func(_peer_id): pass
	host.set_assignment(2, 0)
	return host

func _receive_input(host: LocalHost, seq: int, dir: Vector2, peer := 2) -> void:
	host._on_packet(peer, var_to_bytes({"k": "in", "seq": seq, "dir": dir}))

func _copy_state(dst, src) -> void:
	dst.position = src.position
	dst.velocity = src.velocity
	dst.stamina = src.stamina
	dst.sprint_locked = src.sprint_locked
	dst.facing = src.facing

func test_prediction_leads_then_matches_server() -> void:
	var server := Athlete.new(0, 0, Athlete.Role.WR, Vector2(20, 30))
	var client := Athlete.new(0, 0, Athlete.Role.WR, Vector2(20, 30))
	var pred := Predictor.new()
	var latency := 6   # ticks each way
	var in_flight: Array = []   # inputs travelling to server: [arrive_tick, seq, dir, sprint]
	var snaps: Array = []       # snapshots travelling to client: [arrive_tick, state copy, ack]
	var server_ack := 0
	for tick in 180:
		var dir := Vector2(1, 0.5) if tick < 120 else Vector2.ZERO
		var seq := pred.record(dir, tick % 40 < 20, DT)
		client.step(dir, tick % 40 < 20, DT)
		in_flight.append([tick + latency, seq, dir, tick % 40 < 20])
		while not in_flight.is_empty() and in_flight[0][0] <= tick:
			var inp = in_flight.pop_front()
			server.step(inp[2], inp[3], DT)
			server_ack = inp[1]
		var st := Athlete.new()
		_copy_state(st, server)
		snaps.append([tick + latency, st, server_ack])
		while not snaps.is_empty() and snaps[0][0] <= tick:
			var sn = snaps.pop_front()
			_copy_state(client, sn[1])
			pred.reconcile(client, sn[2])
		if tick == 60:
			assert_true(client.position.x > server.position.x + 0.5, "client leads server during latency")
	# drain: let server process everything and client reconcile
	for tick in range(180, 200):
		while not in_flight.is_empty() and in_flight[0][0] <= tick:
			var inp = in_flight.pop_front()
			server.step(inp[2], inp[3], DT)
			server_ack = inp[1]
	_copy_state(client, server)
	pred.reconcile(client, server_ack)
	assert_true(client.position.distance_to(server.position) < 0.01, "converged")
	assert_eq(pred.pending.size(), 0, "acked inputs dropped")

func test_pending_bounded() -> void:
	var pred := Predictor.new()
	for i in 1000:
		pred.record(Vector2.ZERO, false, DT)
	assert_true(pred.pending.size() <= Predictor.MAX_PENDING, "bounded")

func test_interpolation_midpoint_and_clamps() -> void:
	var it := Interp.new()
	it.push(60, PackedFloat32Array([0, 0]), Vector3.ZERO)
	it.push(66, PackedFloat32Array([10, 20]), Vector3(1, 2, 3))
	var mid := it.sample(63.0 / 60.0)
	assert_near(mid["xy"][0], 5.0, 0.001, "x mid")
	assert_near(mid["xy"][1], 10.0, 0.001, "y mid")
	assert_true((mid["ball"] as Vector3).distance_to(Vector3(0.5, 1, 1.5)) < 0.001, "ball mid")
	assert_near(it.sample(0.0)["xy"][0], 0.0, 0.001, "before first -> first")
	assert_near(it.sample(99.0)["xy"][0], 10.0, 0.001, "after last -> last")

## #421: flags and timers come from the snapshot nearest the drawn time, not the latest one.
func test_interpolation_samples_nearest_snapshot() -> void:
	var it := Interp.new()
	it.push(60, PackedFloat32Array([0, 0]), Vector3.ZERO, {"t": 60})
	it.push(66, PackedFloat32Array([10, 0]), Vector3.ZERO, {"t": 66})
	assert_eq(it.sample(62.0 / 60.0)["snap"]["t"], 60, "nearer the older snapshot")
	assert_eq(it.sample(64.0 / 60.0)["snap"]["t"], 66, "nearer the newer snapshot")
	assert_eq(it.sample(0.0)["snap"]["t"], 60, "before first -> first")
	assert_eq(it.sample(99.0)["snap"]["t"], 66, "after last -> last")

## #421: a hitch runs the draw clock ahead; the next snapshot must not pull it back.
func test_draw_time_never_rewinds() -> void:
	var it := Interp.new()
	assert_near(it.draw_time(60, 0.0, 0.1), 0.9, 0.0001, "delay behind the newest snapshot")
	var after_hitch := it.draw_time(60, 0.3, 0.1)
	assert_near(after_hitch, 1.2, 0.0001, "wall time advances it")
	assert_near(it.draw_time(62, 0.0, 0.1), after_hitch, 0.0001, "the next snapshot doesn't rewind it")
	assert_true(it.draw_time(80, 0.0, 0.1) > after_hitch, "and it moves on once snapshots catch up")

func test_interpolation_ignores_out_of_order() -> void:
	var it := Interp.new()
	it.push(60, PackedFloat32Array([0, 0]), Vector3.ZERO)
	it.push(70, PackedFloat32Array([10, 0]), Vector3.ZERO)
	it.push(64, PackedFloat32Array([99, 99]), Vector3.ZERO)
	assert_eq(it.buf.size(), 2, "stale snapshot dropped")

func test_input_seq_sanitized() -> void:
	assert_eq(P.sanitize_input({"dir": Vector2.ZERO, "seq": 17})["seq"], 17)
	assert_eq(P.sanitize_input({"dir": Vector2.ZERO, "seq": -5})["seq"], 0)
	assert_eq(P.sanitize_input({"dir": Vector2.ZERO, "seq": "x"})["seq"], 0)

func test_host_consumes_burst_in_order_and_acks_only_consumed_input() -> void:
	var host := _input_host()
	_receive_input(host, 1, Vector2.RIGHT)
	_receive_input(host, 2, Vector2.UP)
	_receive_input(host, 2, Vector2.LEFT)
	assert_eq(host.acks(), {}, "received commands are still pending")
	assert_eq(host.take_input(0).get("dir"), Vector2.RIGHT)
	assert_eq(host.acks().get(0, -1), 1)
	assert_eq(host.take_input(0).get("dir"), Vector2.UP, "duplicate cannot replace the queued command")
	assert_eq(host.acks().get(0, -1), 2)
	_receive_input(host, 1, Vector2.LEFT)
	assert_eq(host.take_input(0), {}, "stale input cannot refill an empty queue")
	assert_eq(host.acks().get(0, -1), 2, "an idle tick does not acknowledge a new command")
	host.free()

func test_host_bounds_each_input_queue_and_clears_it_with_assignment() -> void:
	var host := _input_host()
	host.set_assignment(3, 1)
	_receive_input(host, 1, Vector2.UP, 3)
	for seq in range(1, NetSession.INPUT_BUFFER_LIMIT + 3):
		_receive_input(host, seq, Vector2.RIGHT)
	assert_eq(host.take_input(0).get("seq"), 3, "oldest two commands evicted")
	assert_eq(host.take_input(1).get("seq"), 1, "the second athlete has an independent queue")
	_receive_input(host, 2, Vector2.DOWN, 3)
	host.set_assignment(2, 4)
	host._on_peer_disconnected(3)
	assert_eq(host.acks(), {}, "reassignment and disconnection clear previous acknowledgements")
	assert_eq(host.take_input(0), {}, "reassignment clears the old athlete's backlog")
	assert_eq(host.take_input(1), {}, "disconnect clears the athlete's backlog")
	assert_eq(host.take_input(4), {}, "the new assignment starts empty")
	_receive_input(host, 1, Vector2.DOWN)
	assert_eq(host.take_input(4).get("seq"), 1, "the new assignment starts a new sequence")
	host.free()

func test_bursty_inputs_match_delayed_reference_motion() -> void:
	var host := _input_host()
	var expected := Athlete.new()
	var authority := Athlete.new()
	var previous_authority := Athlete.new()
	for tick in 50:
		var command_tick := tick - 2
		var sends_pair := command_tick >= 0 and command_tick % 2 == 0
		if sends_pair:
			_receive_input(host, command_tick + 1, Vector2.RIGHT)
			_receive_input(host, command_tick + 2, Vector2.ZERO)
		expected.step(Vector2.RIGHT if sends_pair else Vector2.ZERO, false, DT)
		# The old host saw only the second command in each pair.
		previous_authority.step(Vector2.ZERO, false, DT)
		authority.step(host.take_input(0).get("dir", Vector2.ZERO), false, DT)
	var previous_error := previous_authority.position.distance_to(expected.position)
	var buffered_error := authority.position.distance_to(expected.position)
	assert_true(previous_error > 2.0, "the packet schedule reproduces the position error")
	assert_near(buffered_error, 0.0, 0.001, "buffered movement follows the delayed reference")
	assert_eq(host.acks().get(0, -1), 48)
	host.free()

# ---- #86 host-silence watchdog (client) ----
func _seated_client() -> LocalHost:
	var c := LocalHost.new()
	c.mode = NetSession.Mode.CLIENT
	c.my_athlete = 3
	return c

func _from_host(c: LocalHost) -> void:
	c._on_packet(1, var_to_bytes({"k": "noop"}))

func test_watchdog_warns_then_drops_once() -> void:
	var c := _seated_client()
	var seen := {"stalled": 0, "recovered": 0, "lost": 0}
	c.host_stalled.connect(func(): seen["stalled"] += 1)
	c.host_recovered.connect(func(): seen["recovered"] += 1)
	c.host_lost.connect(func(): seen["lost"] += 1)
	for i in int(NetSession.STALL_AFTER * 60) - 1:
		c.watch_host(1.0 / 60.0)
	assert_eq(seen["stalled"], 0, "no warning before STALL_AFTER of silence")
	c.watch_host(2.0 / 60.0)
	assert_eq(seen["stalled"], 1, "warning at STALL_AFTER")
	assert_true(c.stalled, "stalled flag set")
	c.watch_host(NetSession.DROP_AFTER - NetSession.STALL_AFTER - 0.1)
	assert_eq(seen["lost"], 0, "still waiting just before DROP_AFTER")
	c.watch_host(0.1)
	assert_eq(seen, {"stalled": 1, "recovered": 0, "lost": 1}, "warned once, dropped once at DROP_AFTER")
	c._on_server_disconnected()   # ENet's own timeout (or our close) arriving later
	c.watch_host(10.0)
	assert_eq(seen["lost"], 1, "host_lost is sent once per session")
	c.free()

func test_watchdog_lag_spike_recovers_without_drop() -> void:
	var c := _seated_client()
	var seen := {"recovered": 0, "lost": 0}
	c.host_recovered.connect(func(): seen["recovered"] += 1)
	c.host_lost.connect(func(): seen["lost"] += 1)
	c.watch_host(NetSession.DROP_AFTER - 0.05)
	assert_true(c.stalled, "warning during a long spike")
	_from_host(c)
	assert_eq(seen, {"recovered": 1, "lost": 0}, "any packet from the host clears the warning, no drop")
	assert_eq(c.host_silence, 0.0, "silence clock reset")
	c.watch_host(NetSession.DROP_AFTER - 0.05)
	_from_host(c)
	assert_eq(seen["lost"], 0, "silence is per gap, not cumulative across spikes")
	c.free()

func test_watchdog_only_runs_seated_in_a_match() -> void:
	var c := LocalHost.new()
	c.mode = NetSession.Mode.CLIENT   # in the lobby: no snapshots expected, ENet's timeout applies
	c._watch_us = Time.get_ticks_usec() - 10_000_000
	c._process(0.0)
	assert_eq(c.host_silence, 0.0, "unseated client doesn't count silence")
	c.my_athlete = 2
	c.refused_reason = "Match full"
	c._process(0.0)
	assert_eq(c.host_silence, 0.0, "refused client doesn't count silence")
	var server := LocalHost.new()
	server.mode = NetSession.Mode.SERVER
	server._process(0.0)
	assert_eq(server.host_silence, 0.0, "server never runs the watchdog")
	c.free()
	server.free()

func test_watchdog_caps_our_own_hitch() -> void:
	var c := _seated_client()
	c._process(0.0)                                    # first step only starts the clock
	c._watch_us = Time.get_ticks_usec() - 3_000_000    # our frame took 3 s (loading, debugger)
	c._process(0.0)
	assert_near(c.host_silence, NetSession.SILENCE_STEP_MAX, 0.01, "one long frame counts SILENCE_STEP_MAX")
	assert_true(not c.stalled, "our hitch alone doesn't warn")
	c.free()
