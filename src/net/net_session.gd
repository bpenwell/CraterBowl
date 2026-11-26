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

const P := preload("res://src/net/protocol.gd")
const DEFAULT_PORT := 24565
const MAX_PEERS := 13
const INPUT_BUFFER_LIMIT := 6  # 100 ms at the 60 Hz sim rate
const NO_INPUT := {}
const REFUSE_GRACE := 1.0      # s: server drops a refused peer after this (the client normally hangs up first)
const FULL_MATCH_REASON := "Match full: every seat is taken"

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
	if not api.server_disconnected.is_connected(_on_server_disconnected):
		api.server_disconnected.connect(_on_server_disconnected)
	if not api.connection_failed.is_connected(_on_connection_failed):
		api.connection_failed.connect(_on_connection_failed)
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
		print("NET host lost")
		host_lost.emit()

func human_athletes() -> Array:
	return peer_athlete.values()

func _send(target: int, msg: Dictionary, reliable: bool) -> void:
	var m := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	api.send_bytes(var_to_bytes(msg), target, m, 0 if reliable else 1)

# ---- server ----
func _on_peer_connected(id: int) -> void:
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
func refuse(id: int, reason: String) -> void:
	print("NET refused peer %d: %s" % [id, reason])
	_send(id, {"k": "refused", "why": reason}, true)
	get_tree().create_timer(REFUSE_GRACE).timeout.connect(func():
		if mode == Mode.SERVER and api.get_peers().has(id):
			peer.disconnect_peer(id))

## Server: (re)assign a peer to an athlete and tell them.
func set_assignment(id: int, aid: int) -> void:
	if peer_athlete.has(id):
		_clear_inputs(peer_athlete[id])
	peer_athlete[id] = aid
	_send(id, {"k": "welcome", "aid": aid, "size": match_size, "mode": match_mode}, true)

func _on_peer_disconnected(id: int) -> void:
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

# ---- both ----
func _on_packet(from: int, bytes: PackedByteArray) -> void:
	var msg = bytes_to_var(bytes)   # never decodes objects
	if not (msg is Dictionary):
		return
	if mode == Mode.CLIENT and refused_reason != "":
		return   # turned away: ignore anything still in flight
	match msg.get("k", ""):
		"refused":
			if mode == Mode.CLIENT and from == 1:
				var why = msg.get("why", "")
				refused_reason = str(why).left(120) if why is String and why != "" else "The host refused the connection"
				print("NET refused by host: %s" % refused_reason)
				refused.emit(refused_reason)
				peer.close.call_deferred()
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
