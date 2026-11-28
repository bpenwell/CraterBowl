extends "res://tests/test_case.gd"
## #165: client, host and matchmaker refuse each other on a protocol version mismatch.

const P := preload("res://src/net/protocol.gd")
const NetSession := preload("res://src/net/net_session.gd")
const MMServer := preload("res://src/net/mm_server.gd")

## A host whose sends are recorded instead of going over ENet.
class RecordingHost extends NetSession:
	var sent: Array = []
	func _send(target: int, msg: Dictionary, _reliable: bool) -> void:
		sent.append([target, msg])

class RecordingMM extends MMServer:
	var sent: Array = []
	func _send(id: int, msg: Dictionary) -> void:
		sent.append([id, msg])

func _host(version: int) -> RecordingHost:
	var host := RecordingHost.new()
	host.mode = NetSession.Mode.SERVER
	host.protocol_version = version
	host.assign_fn = func(_peer): return 3
	host.release_fn = func(_peer): pass
	return host

func _sent(host, kind: String) -> Array:
	return host.sent.filter(func(s): return s[1].get("k") == kind)

func test_hello_carries_version_and_build() -> void:
	var h := P.hello(7)
	assert_eq(h["k"], "hello")
	assert_eq(h["v"], 7)
	assert_true(h["build"] is String and h["build"] != "", "build label from the VERSION file: %s" % h["build"])
	assert_eq(P.hello()["v"], P.VERSION, "default hello announces Protocol.VERSION")

func test_version_refusal_reasons_are_readable() -> void:
	assert_eq(P.version_refusal(3, 3), "", "same version: compatible")
	assert_eq(P.version_refusal(2, 3), "Update Crater Bowl to play online (server is v3, you have v2)")
	assert_true(P.version_refusal(4, 3).contains("server is v3, you have v4"), "newer client told the server is older")
	assert_true(P.version_refusal(null, 3).begins_with("Update Crater Bowl to play online (server is v3"), "no version = pre-handshake build")
	assert_true(P.version_refusal("3", 3) != "", "a non-int version is never compatible")
	assert_true(P.version_refusal(2, 3).length() <= 120, "fits the client's 120-char reason cut")

func test_matching_hello_is_welcomed() -> void:
	var host := _host(5)
	host._on_peer_connected(2)
	assert_eq(host.sent.size(), 0, "nothing sent before the hello")
	assert_true(not host.peer_athlete.has(2), "no athlete before the hello")
	host._on_packet(2, var_to_bytes(P.hello(5)))
	var welcomes := _sent(host, "welcome")
	assert_eq(welcomes.size(), 1, "matching hello is welcomed")
	assert_eq(welcomes[0][1]["aid"], 3)
	assert_eq(_sent(host, "refused").size(), 0, "and not refused")
	host._on_packet(2, var_to_bytes(P.hello(5)))
	assert_eq(_sent(host, "welcome").size(), 1, "a second hello doesn't re-admit")
	host.free()

func test_mismatched_hello_is_refused_with_reason() -> void:
	var host := _host(5)
	host._on_peer_connected(2)
	host._on_packet(2, var_to_bytes(P.hello(4)))
	var refusals := _sent(host, "refused")
	assert_eq(refusals.size(), 1, "mismatched hello is refused")
	assert_eq(refusals[0][1]["why"], "Update Crater Bowl to play online (server is v5, you have v4)")
	assert_eq(refusals[0][1]["v"], 5, "refusal carries the server version")
	assert_eq(_sent(host, "welcome").size(), 0, "never welcomed")
	assert_true(not host.peer_athlete.has(2), "never assigned an athlete")
	host.free()

func test_lobby_host_checks_version_before_seating() -> void:
	var host := _host(5)
	host.lobby_mode = true
	host.lobby = preload("res://src/net/lobby.gd").new()
	host._on_peer_connected(2)
	host._on_packet(2, var_to_bytes(P.hello(6)))
	assert_true(not host.lobby.players.has(2), "mismatched peer never enters the lobby")
	host._on_peer_connected(3)
	host._on_packet(3, var_to_bytes(P.hello(5)))
	assert_true(host.lobby.players.has(3), "matching peer joins the lobby")
	host.free()

func test_client_flags_version_refusal() -> void:
	var client := NetSession.new()
	client.mode = NetSession.Mode.CLIENT
	client.peer = ENetMultiplayerPeer.new()
	client._on_packet(1, var_to_bytes({"k": "refused", "why": P.version_refusal(1, 2), "v": 2}))
	assert_eq(client.refused_reason, "Update Crater Bowl to play online (server is v2, you have v1)")
	assert_true(client.version_refused, "client knows it was a version refusal")
	var full := NetSession.new()
	full.mode = NetSession.Mode.CLIENT
	full.peer = ENetMultiplayerPeer.new()
	full._on_packet(1, var_to_bytes({"k": "refused", "why": "Lobby full"}))
	assert_true(not full.version_refused, "a capacity refusal isn't a version refusal")
	client.free()
	full.free()

func test_matchmaker_refuses_mismatched_enqueue() -> void:
	var mm := RecordingMM.new()
	mm.protocol_version = 5
	mm._on_packet(2, var_to_bytes({"k": "enq", "mode": "casual", "size": 3, "v": 4}))
	assert_eq(mm.mm.queue.size(), 0, "mismatched player not queued")
	assert_eq(mm.sent.size(), 1)
	assert_eq(mm.sent[0][1].get("k"), "refused")
	assert_eq(mm.sent[0][1].get("why"), "Update Crater Bowl to play online (server is v5, you have v4)")
	mm._on_packet(3, var_to_bytes({"k": "enq", "mode": "casual", "size": 3}))
	assert_eq(mm.mm.queue.size(), 0, "pre-handshake build (no v) not queued")
	mm._on_packet(4, var_to_bytes({"k": "enq", "mode": "casual", "size": 3, "v": 5}))
	assert_eq(mm.mm.queue.size(), 1, "matching player queued")
	assert_eq(mm.sent.back()[1].get("k"), "queued")
	mm.free()

## #224: the client checks the host's version off `welcome` (a pre-#165 host never checks ours).
func _client(version: int) -> NetSession:
	var client := NetSession.new()
	client.mode = NetSession.Mode.CLIENT
	client.protocol_version = version
	client.peer = ENetMultiplayerPeer.new()
	return client

func test_host_welcome_carries_version() -> void:
	var host := _host(5)
	host._on_peer_connected(2)
	host._on_packet(2, var_to_bytes(P.hello(5)))
	assert_eq(_sent(host, "welcome")[0][1].get("v"), 5, "welcome announces the host's version")
	host.free()

func test_client_seated_by_matching_welcome() -> void:
	var client := _client(5)
	client._on_packet(1, var_to_bytes({"k": "welcome", "aid": 2, "size": 3, "mode": "classic", "v": 5}))
	assert_eq(client.my_athlete, 2, "matching welcome seats the client")
	assert_eq(client.refused_reason, "", "and doesn't refuse")
	client.free()

func test_client_refuses_welcome_without_version() -> void:
	var client := _client(5)
	var reasons: Array = []
	client.refused.connect(func(r): reasons.append(r))
	client._on_packet(1, var_to_bytes({"k": "welcome", "aid": 2, "size": 3, "mode": "classic"}))
	assert_eq(client.my_athlete, -1, "pre-#165 host's welcome doesn't seat the client")
	assert_eq(client.refused_reason, "This server runs an older Crater Bowl (server is an older build, you have v5)")
	assert_true(client.version_refused, "counts as a version refusal (no capacity hint)")
	assert_eq(reasons, [client.refused_reason], "refused signal fires like a host refusal")
	client._on_packet(1, var_to_bytes({"k": "welcome", "aid": 2, "size": 3, "mode": "classic", "v": 5}))
	assert_eq(client.my_athlete, -1, "nothing after the refusal is accepted")
	client.free()

func test_client_refuses_welcome_with_other_version() -> void:
	var older := _client(5)
	older._on_packet(1, var_to_bytes({"k": "welcome", "aid": 2, "size": 3, "mode": "classic", "v": 4}))
	assert_eq(older.my_athlete, -1, "older host doesn't seat the client")
	assert_eq(older.refused_reason, "This server runs an older Crater Bowl (server is v4, you have v5)")
	var newer := _client(5)
	newer._on_packet(1, var_to_bytes({"k": "welcome", "aid": 2, "size": 3, "mode": "classic", "v": 6}))
	assert_eq(newer.my_athlete, -1, "newer host doesn't seat the client")
	assert_eq(newer.refused_reason, "Update Crater Bowl to play online (server is v6, you have v5)")
	var odd := _client(5)
	odd._on_packet(1, var_to_bytes({"k": "welcome", "aid": 2, "size": 3, "mode": "classic", "v": "5"}))
	assert_eq(odd.my_athlete, -1, "a non-int version is never compatible")
	assert_true(older.version_refused and newer.version_refused and odd.version_refused, "all version refusals")
	older.free()
	newer.free()
	odd.free()
