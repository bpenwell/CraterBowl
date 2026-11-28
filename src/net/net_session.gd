extends Node
## ENet transport. Server: assigns athletes to peers, collects inputs/actions,
## broadcasts snapshots + events. Client: sends inputs/actions, receives state.

signal welcomed(athlete_id: int)
signal snapshot_received(snap: Dictionary)
signal event_received(n: String, d: Dictionary)
signal peer_joined(peer_id: int, athlete_id: int)
signal peer_left(peer_id: int, athlete_id: int)
signal lobby_received(state: Dictionary)
signal lobby_changed()
signal refused(reason: String)
signal connection_failed()     # client: the initial connection never reached the host
signal host_lost()             # client: the host went away (quit, crashed, timed out) mid-session
signal host_stalled()          # client: in the match, nothing from the host for STALL_AFTER s (#86)
signal host_recovered()        # client: the host was heard from again before DROP_AFTER

const P := preload("res://src/net/protocol.gd")
const DEFAULT_PORT := 24565
const MAX_PEERS := 13
const INPUT_BUFFER_LIMIT := 6  # 100 ms at the 60 Hz sim rate
const NO_INPUT := {}
const REFUSE_GRACE := 1.0      # s: server drops a refused peer after this (the client normally hangs up first)
const FULL_MATCH_REASON := "Match full: every seat is taken"
# #86 host-silence watchdog (client, in the match). The host sends 30 snapshots/s, so silence
# means trouble long before ENet's own peer timeout (5-30 s, measured 5.8-9.7 s). Decision and
# why: docs/features/online.md "Design decisions".
const STALL_AFTER := 2.0       # s of silence: warn ("Connection to host lost...")
const DROP_AFTER := 4.0        # s of silence: give up -> host_lost (the #17 reconnect grace would go here)
const SILENCE_STEP_MAX := 0.25 # s: one frame counts at most this much, so our own hitch isn't the host's silence
const HELLO_TIMEOUT := 5.0      # s: server refuses a peer that never says hello (a pre-#165 build)

enum Mode { OFFLINE, SERVER, CLIENT }

var mode: Mode = Mode.OFFLINE
var peer: ENetMultiplayerPeer
var api: SceneMultiplayer
var assign_fn: Callable       # server: func(peer_id) -> athlete_id or -1
var release_fn: Callable      # server: func(peer_id)
var peer_athlete := {}         # server: peer_id -> athlete_id
var _input_queues := {}        # server: athlete_id -> pending movement commands
var _input_acks := {}          # server: athlete_id -> last consumed sequence
var actions: Array = []        # server: [[peer_id, athlete_id, action], ...] pending
var my_athlete := -1           # client
var match_size := 7            # server: sent in welcome
var match_mode := "classic"    # server: sent in welcome
var host_size := 7             # client: host's match size from welcome
var host_mode := "classic"     # client: host's ruleset from welcome
var lobby_mode := false        # server: joiners wait in the lobby (no athlete) until start
var lobby                      # server: Lobby (set by main)
var lobby_actions: Array = []  # server: [[peer_id, action], ...]
var last_snapshot_tick := -1
var refused_reason := ""       # client: why the host turned us away ("" = not refused)
var host_silence := 0.0        # client: seconds since the last packet from the host (watchdog clock)
var stalled := false           # client: the watchdog is warning (host_stalled sent, not yet recovered)
var _host_gone := false        # client: host_lost already sent (once per session)
var _watch_us := 0             # client: wall clock of the previous watchdog step
var version_refused := false   # client: the refusal was a protocol version mismatch (#165)
var protocol_version := P.local_version()   # both: announced (client) / required (server) wire version
var _awaiting_hello := {}      # server: peer_id -> true until its hello arrives (#165)

func _ready() -> void:
	api = SceneMultiplayer.new()
	get_tree().set_multiplayer(api, get_path())
	api.peer_packet.connect(_on_packet)

func host(port: int, assign: Callable, release: Callable) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		return err
	api.multiplayer_peer = peer
	assign_fn = assign
	release_fn = release
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)
	mode = Mode.SERVER
	return OK

func join(address: String, port: int) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	api.multiplayer_peer = peer
	host_silence = 0.0
	stalled = false
	_host_gone = false
	if not api.server_disconnected.is_connected(_on_server_disconnected):
		api.server_disconnected.connect(_on_server_disconnected)
	if not api.connection_failed.is_connected(_on_connection_failed):
		api.connection_failed.connect(_on_connection_failed)
	if not api.connected_to_server.is_connected(_say_hello):
		api.connected_to_server.connect(_say_hello)
	mode = Mode.CLIENT
	return OK

func _on_connection_failed() -> void:
	if mode == Mode.CLIENT:
		mode = Mode.OFFLINE
		connection_failed.emit()

## Client: the connection to the host dropped. A refused client hung up on purpose
## (and already shows why), so only an unexpected loss counts.
func _on_server_disconnected() -> void:
	if mode == Mode.CLIENT and refused_reason == "":
		_lose_host("disconnected")

func _lose_host(why: String) -> void:
	if _host_gone:
		return
	_host_gone = true
	print("NET host lost (%s)" % why)
	host_lost.emit()

## Client watchdog (#86): armed once we're seated in the match (the host then sends snapshots
## every other tick). Wall clock, so time scale doesn't matter; each frame counts at most
## SILENCE_STEP_MAX so a hitch on our side (loading, a debugger) isn't blamed on the host.
func _process(_delta: float) -> void:
	if mode != Mode.CLIENT or my_athlete < 0 or refused_reason != "" or _host_gone:
		_watch_us = 0
		return
	var now := Time.get_ticks_usec()
	var step := 0.0 if _watch_us == 0 else minf((now - _watch_us) / 1000000.0, SILENCE_STEP_MAX)
	_watch_us = now
	watch_host(step)

## Advance the silence clock by `step` seconds: warn at STALL_AFTER, give up at DROP_AFTER.
## Hearing from the host (any packet) resets it in _heard_host. #17 (reconnect) slots in at the
## DROP_AFTER branch: try to rejoin during a grace window instead of leaving.
func watch_host(step: float) -> void:
	host_silence += step
	if not stalled and host_silence >= STALL_AFTER:
		stalled = true
		print("NET host stalled (%.1fs silent)" % host_silence)
		host_stalled.emit()
	if host_silence >= DROP_AFTER:
		_lose_host("silent %.1fs" % host_silence)
		if peer != null:
			peer.close.call_deferred()   # stop sending into the void; the menu frees us anyway

func _heard_host() -> void:
	host_silence = 0.0
	if stalled and not _host_gone:
		stalled = false
		print("NET host recovered")
		host_recovered.emit()

func human_athletes() -> Array:
	return peer_athlete.values()

func _send(target: int, msg: Dictionary, reliable: bool) -> void:
	var m := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	api.send_bytes(var_to_bytes(msg), target, m, 0 if reliable else 1)

## Client: the first message on a new connection announces our protocol version (#165).
func _say_hello() -> void:
	if mode == Mode.CLIENT:
		_send(1, P.hello(protocol_version), true)

# ---- server ----
## A new peer gets nothing until its hello proves a matching protocol version (#165).
## Builds from before the handshake never send one and are refused after HELLO_TIMEOUT.
func _on_peer_connected(id: int) -> void:
	_awaiting_hello[id] = true
	if is_inside_tree():
		get_tree().create_timer(HELLO_TIMEOUT).timeout.connect(func():
			if mode == Mode.SERVER and _awaiting_hello.has(id):
				_on_hello(id, {}))

func _on_hello(id: int, msg: Dictionary) -> void:
	if not _awaiting_hello.has(id):
		return   # one hello per connection
	_awaiting_hello.erase(id)
	var why := P.version_refusal(msg.get("v"), protocol_version)
	if why != "":
		print("NET peer %d build %s: protocol v%s, need v%d" % [id, str(msg.get("build", "?")).left(32), str(msg.get("v", "?")).left(8), protocol_version])
		refuse(id, why, true)
		return
	_admit(id)

func _admit(id: int) -> void:
	if lobby_mode and lobby != null and lobby.phase == lobby.Phase.LOBBY:
		if lobby.is_full():
			refuse(id, lobby.full_reason())
			return
		lobby.add(id)
		lobby_changed.emit()
		return
	var aid: int = assign_fn.call(id)
	if aid < 0:
		refuse(id, FULL_MATCH_REASON)
		return
	set_assignment(id, aid)
	peer_joined.emit(id, aid)

## Server: tell a peer why it can't join, then drop it. ENet's disconnect discards queued
## packets, so the drop waits REFUSE_GRACE (the client hangs up itself on receipt).
func refuse(id: int, reason: String, version_mismatch := false) -> void:
	print("NET refused peer %d: %s" % [id, reason])
	var msg := {"k": "refused", "why": reason}
	if version_mismatch:
		msg["v"] = protocol_version
	_send(id, msg, true)
	if not is_inside_tree():
		return
	get_tree().create_timer(REFUSE_GRACE).timeout.connect(func():
		if mode == Mode.SERVER and api.get_peers().has(id):
			peer.disconnect_peer(id))

## Server: (re)assign a peer to an athlete and tell them.
func set_assignment(id: int, aid: int) -> void:
	if peer_athlete.has(id):
		_clear_inputs(peer_athlete[id])
	peer_athlete[id] = aid
	_send(id, {"k": "welcome", "aid": aid, "size": match_size, "mode": match_mode, "v": protocol_version}, true)

func _on_peer_disconnected(id: int) -> void:
	_awaiting_hello.erase(id)
	if lobby != null and lobby.players.has(id):
		lobby.remove(id)
		lobby_changed.emit()
	if peer_athlete.has(id):
		var aid: int = peer_athlete[id]
		peer_athlete.erase(id)
		_clear_inputs(aid)
		release_fn.call(id)
		peer_left.emit(id, aid)

func _clear_inputs(aid: int) -> void:
	_input_queues.erase(aid)
	_input_acks.erase(aid)

func _queue_input(aid: int, input: Dictionary) -> void:
	if input.is_empty():
		return
	if not _input_queues.has(aid):
		_input_queues[aid] = []
	var pending: Array = _input_queues[aid]
	var latest: int = _input_acks.get(aid, -1) if pending.is_empty() else pending.back()["seq"]
	if input["seq"] <= latest:
		return
	if pending.size() == INPUT_BUFFER_LIMIT:
		pending.pop_front()
	pending.append(input)

## Server: consume at most one movement command per remote athlete per sim tick.
func take_input(aid: int) -> Dictionary:
	if not _input_queues.has(aid):
		return NO_INPUT
	var pending: Array = _input_queues[aid]
	if pending.is_empty():
		return NO_INPUT
	var input: Dictionary = pending.pop_front()
	_input_acks[aid] = input["seq"]
	return input

## Server: athlete_id -> last consumed input seq (for client reconciliation).
func acks() -> Dictionary:
	return _input_acks.duplicate()

func broadcast_snapshot(snap: Dictionary) -> void:
	if mode == Mode.SERVER and not peer_athlete.is_empty():
		_send(0, snap, false)

func broadcast_event(n: String, d: Dictionary) -> void:
	if mode == Mode.SERVER and not peer_athlete.is_empty():
		_send(0, {"k": "ev", "n": n, "d": d}, true)

func broadcast_lobby(state: Dictionary) -> void:
	if mode == Mode.SERVER and not api.get_peers().is_empty():
		_send(0, {"k": "lobby", "s": state}, true)

func take_lobby_actions() -> Array:
	var out := lobby_actions
	lobby_actions = []
	return out

func send_lobby_action(action: Dictionary) -> void:
	if mode == Mode.CLIENT:
		_send(1, {"k": "lact", "act": action}, true)

func take_actions() -> Array:
	var out := actions
	actions = []
	return out

# ---- client ----
func send_input(dir: Vector2, sprint: bool, seq: int = 0, block := false) -> void:
	if mode == Mode.CLIENT and my_athlete >= 0:
		_send(1, {"k": "in", "dir": dir, "spr": sprint, "seq": seq, "block": block}, false)

func send_action(action: Dictionary) -> void:
	if mode == Mode.CLIENT and my_athlete >= 0:
		_send(1, {"k": "act", "act": action}, true)

## Client: the host turned us away (a `refused` packet, or a welcome on another version): hang up.
func _refused_by_host(reason: String, version_mismatch: bool) -> void:
	refused_reason = reason
	version_refused = version_mismatch
	print("NET refused by host: %s" % refused_reason)
	refused.emit(refused_reason)
	peer.close.call_deferred()

# ---- both ----
func _on_packet(from: int, bytes: PackedByteArray) -> void:
	var msg = bytes_to_var(bytes)   # never decodes objects
	if not (msg is Dictionary):
		return
	if mode == Mode.CLIENT and refused_reason != "":
		return   # turned away: ignore anything still in flight
	if mode == Mode.CLIENT and from == 1:
		_heard_host()
	match msg.get("k", ""):
		"hello":
			if mode == Mode.SERVER:
				_on_hello(from, msg)
		"refused":
			if mode == Mode.CLIENT and from == 1:
				var why = msg.get("why", "")
				_refused_by_host(str(why).left(120) if why is String and why != "" else "The host refused the connection", msg.has("v"))
		"in":
			if mode == Mode.SERVER and peer_athlete.has(from):
				_queue_input(peer_athlete[from], P.sanitize_input(msg))
		"act":
			if mode == Mode.SERVER and peer_athlete.has(from) and P.is_action(msg.get("act")):
				actions.append([from, peer_athlete[from], msg["act"]])
		"lact":
			if mode == Mode.SERVER and lobby != null and lobby.players.has(from) and msg.get("act") is Dictionary:
				lobby_actions.append([from, msg["act"]])
		"lobby":
			if mode == Mode.CLIENT and from == 1 and msg.get("s") is Dictionary:
				lobby_received.emit(msg["s"])
		"welcome":
			if mode == Mode.CLIENT and from == 1:
				# #224: a pre-#165 host never checked our hello, so check its version here.
				var host_refusal := P.host_version_refusal(msg.get("v"), protocol_version)
				if host_refusal != "":
					_refused_by_host(host_refusal, true)
					return
				var size = msg.get("size", 7)
				var rules = msg.get("mode", "classic")
				var aid = msg.get("aid")
				if not (size is int and size in [3, 5, 7]):
					return
				if not (rules is String and rules in ["classic", "chaosball"]):
					return
				# Chaosball always creates a 3v3 world, independently of the supplied size.
				var team_size: int = 3 if rules == "chaosball" else size
				if not (aid is int and aid >= 0 and aid < team_size * 2):
					return
				host_size = team_size
				host_mode = rules
				my_athlete = aid
				welcomed.emit(my_athlete)
		"snap":
			var tick = msg.get("t")
			if (mode == Mode.CLIENT and from == 1 and tick is int and tick > last_snapshot_tick
					and P.valid_snapshot(msg, host_size * 2)):
				last_snapshot_tick = tick
				snapshot_received.emit(msg)
		"ev":
			if mode == Mode.CLIENT and from == 1:
				event_received.emit(str(msg.get("n", "")), msg.get("d", {}) if msg.get("d") is Dictionary else {})
