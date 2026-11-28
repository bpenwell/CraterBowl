extends Node
## Headless matchmaking server: queues players, elects a host per match,
## relays the host's invite code to the others.

const MM := preload("res://src/net/matchmaker.gd")
const Registry := preload("res://src/net/lobby_registry.gd")
const P := preload("res://src/net/protocol.gd")
const DEFAULT_PORT := 24600
## #303: seconds the elected host has to answer `hosting` with its invite code. A healthy host
## answers in the frame it gets the order (`main.gd` builds the lobby synchronously), so the reply
## is one round trip away. 10 s covers a slow world rebuild on weak hardware plus ENet resends on
## a lossy link, and still beats waiting for ENet's own disconnect timeout (5-30 s) on a host that
## died silently. Past it the match is dropped and the others are re-queued.
const HOST_REPLY_TIMEOUT := 10.0

var api: SceneMultiplayer
var peer: ENetMultiplayerPeer
var mm := MM.new()
var registry := Registry.new()   # public lobbies for the server browser
var pending := {}   # host peer id -> {"others": [queue entries], "match": Dictionary, "deadline": float}
var protocol_version := P.local_version()   # queuers must match it (#165)

func start(port: int) -> Error:
	api = SceneMultiplayer.new()
	get_tree().set_multiplayer(api, get_path())
	api.peer_packet.connect(_on_packet)
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 64)
	if err != OK:
		return err
	api.multiplayer_peer = peer
	api.peer_disconnected.connect(_on_peer_left)
	return OK

func _on_peer_left(id: int) -> void:
	mm.dequeue(id)
	registry.remove(id)
	if pending.has(id):
		_drop_pending(id, "host disconnected")
	for h in pending:   # a joiner who left is not re-queued if its host fails later
		pending[h]["others"] = pending[h]["others"].filter(func(e): return e["id"] != id)

## #303: the elected host failed (left, went silent, or sent no code). Forget the match and put
## the others back in the queue with their queue time kept, so they re-form first. The failed host
## is not re-queued: if it is still connected and wants a match, its client queues again.
func _drop_pending(host: int, why: String) -> void:
	var others: Array = pending[host]["others"]
	pending.erase(host)
	mm.requeue(others)
	print("MM host %d failed (%s): %d players back in the queue" % [host, why, others.size()])

func _expire_host(host: int) -> void:
	_drop_pending(host, "no invite code in %.0f s" % HOST_REPLY_TIMEOUT)
	_send(host, {"k": "match", "role": "cancel"})

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _send(id: int, msg: Dictionary) -> void:
	api.send_bytes(var_to_bytes(msg), id, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0)

func _on_packet(from: int, bytes: PackedByteArray) -> void:
	var msg = bytes_to_var(bytes)
	if not (msg is Dictionary):
		return
	match msg.get("k", ""):
		"list":
			_send(from, {"k": "lobbies", "list": registry.listing(_now()), "queued": mm.queue.size()})
		"register":
			var info = msg.get("info", {})
			_send(from, {"k": "registered", "ok": info is Dictionary and registry.register(from, info, _now())})
		"unregister":
			registry.remove(from)
		"enq":
			var why := P.version_refusal(msg.get("v"), protocol_version)
			if why != "":   # #165: never match players whose builds can't play together
				_send(from, {"k": "refused", "why": why, "v": protocol_version})
				print("MM refused %d: %s" % [from, why])
				return
			var size = msg.get("size", 7)
			var rating = msg.get("rating", 1000.0)
			var ok := mm.enqueue(from, str(msg.get("mode", "")), int(size) if size is int else 7,
				float(rating) if (rating is float or rating is int) else 1000.0, _now(), str(msg.get("name", "")).left(16),
				str(msg.get("party", "")).left(12), int(msg.get("party_size", 1)) if (msg.get("party_size", 1) is int) else 1,
				"chaosball" if msg.get("game", "") == "chaosball" else "classic", str(msg.get("seat", "")).left(32))
			_send(from, {"k": "queued", "ok": ok, "n": mm.queue.size()})
			print("MM enqueue %d -> %s (queue %d)" % [from, ok, mm.queue.size()])
		"hosting":
			if not pending.has(from):
				return
			# ENet can deliver a packet before this frame's deadline check in _process.
			if _now() >= pending[from]["deadline"]:
				_expire_host(from)
				return
			var code := str(msg.get("code", ""))
			if code == "":   # nothing to join (#303)
				_drop_pending(from, "empty invite code")
				return
			for o in pending[from]["others"]:
				_send(o["id"], {"k": "match", "role": "join", "code": code})
			print("MM host %d ready with %s -> %d joiners" % [from, code, pending[from]["others"].size()])
			pending.erase(from)

func _process(_dt: float) -> void:
	if api == null:
		return
	var now := _now()
	for host in pending.keys():   # before tick, so the re-queued players can match this frame
		if now >= pending[host]["deadline"]:
			_expire_host(host)
	for m in mm.tick(now):
		var others: Array = m["entries"].filter(func(e): return e["id"] != m["host"])
		pending[m["host"]] = {"others": others, "match": m, "deadline": now + HOST_REPLY_TIMEOUT}
		_send(m["host"], {"k": "match", "role": "host", "mode": m["mode"], "size": m["size"],
			"expected": m["players"].size(), "teams": m["team_names"], "seats": m["team_seats"], "game": m["game"]})
		print("MM formed %s %dv%d: %s (host %d)" % [m["mode"], m["size"], m["size"], str(m["players"]), m["host"]])
