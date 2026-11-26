extends Node
## Queue client: connect to the matchmaker, enqueue, receive host/join orders.

signal queued(ok: bool, n: int)
signal host_match(settings: Dictionary)
signal join_match(code: String)
signal lobbies(list: Array)
signal registered(ok: bool)
signal connected
signal failed

var api: SceneMultiplayer
var peer: ENetMultiplayerPeer
var _req := {}

func queue_up(address: String, port: int, mode: String, size: int, rating: float, name: String = "", party: String = "", party_size: int = 1, game: String = "classic", seat: String = "") -> Error:
	api = SceneMultiplayer.new()
	get_tree().set_multiplayer(api, get_path())
	api.peer_packet.connect(_on_packet)
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	api.multiplayer_peer = peer
	_req = {"k": "enq", "mode": mode, "size": size, "rating": rating, "name": name, "party": party, "party_size": party_size, "game": game, "seat": seat}
	api.connected_to_server.connect(func(): _send(_req))
	api.connection_failed.connect(func(): failed.emit())
	return OK

## Connect without queueing (server browser / lobby advertising). Emits connected|failed.
func open(address: String, port: int) -> Error:
	api = SceneMultiplayer.new()
	get_tree().set_multiplayer(api, get_path())
	api.peer_packet.connect(_on_packet)
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	api.multiplayer_peer = peer
	api.connected_to_server.connect(func(): connected.emit())
	api.connection_failed.connect(func(): failed.emit())
	return OK

func is_open() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func request_list() -> void:
	_send({"k": "list"})

func register_lobby(info: Dictionary) -> void:
	_send({"k": "register", "info": info})

func unregister_lobby() -> void:
	_send({"k": "unregister"})

func send_hosting(code: String) -> void:
	_send({"k": "hosting", "code": code})

func _send(msg: Dictionary) -> void:
	api.send_bytes(var_to_bytes(msg), 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0)

func _on_packet(from: int, bytes: PackedByteArray) -> void:
	var msg = bytes_to_var(bytes)
	if from != 1 or not (msg is Dictionary):
		return
	match msg.get("k", ""):
		"lobbies":
			var l = msg.get("list", [])
			lobbies.emit(l if l is Array else [])
		"registered":
			registered.emit(msg.get("ok", false) == true)
		"queued":
			queued.emit(msg.get("ok", false) == true, int(msg.get("n", 0)))
		"match":
			if msg.get("role", "") == "host":
				host_match.emit(msg)
			elif msg.get("role", "") == "join":
				join_match.emit(str(msg.get("code", "")))
