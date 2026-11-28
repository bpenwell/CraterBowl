extends "res://tests/test_case.gd"
## #303: a matchmade host that never answers (can't bind, crashed, left) must not strand the
## other players in "searching". mm_server drops the pending match and re-queues them.

const MM := preload("res://src/net/matchmaker.gd")
const P := preload("res://src/net/protocol.gd")

## The real server with the clock and the socket stubbed out (no ENet, no scene tree).
class FakeServer extends "res://src/net/mm_server.gd":
	var clock := 0.0
	var sent := []   # [peer id, message]
	func _init() -> void:
		api = SceneMultiplayer.new()   # non-null so _process runs; it has no peer and sends nothing
	func _now() -> float:
		return clock
	func _send(id: int, msg: Dictionary) -> void:
		sent.append([id, msg])
	func orders(role: String) -> Array:
		return sent.filter(func(s): return s[1].get("k") == "match" and s[1].get("role") == role)
	func at(t: float) -> void:
		clock = t
		_process(0.0)

func _enq(s: FakeServer, id: int, t: float, party: String = "", party_size: int = 1) -> void:
	s.clock = t
	s._on_packet(id, var_to_bytes({"k": "enq", "mode": "casual", "size": 3, "rating": 1000.0,
		"name": "P%d" % id, "party": party, "party_size": party_size, "v": P.local_version()}))

## Players 1, 2, 3 queue (1 is oldest), the casual wait passes, 1 is elected host.
func _formed() -> FakeServer:
	var s := FakeServer.new()
	_enq(s, 1, 0.0)
	_enq(s, 2, 0.1)
	_enq(s, 3, 0.2)
	s.at(MM.CASUAL_WAIT + 0.5)
	assert_eq(s.orders("host").size(), 1, "one match formed")
	assert_eq(s.orders("host")[0][0], 1, "oldest player hosts")
	assert_true(s.pending.has(1), "waiting on host 1's code")
	assert_eq(s.mm.queue.size(), 0, "everyone left the queue")
	return s

func _queued_ids(s: FakeServer) -> Array:
	var ids := s.mm.queue.map(func(e): return e["id"])
	ids.sort()
	return ids

## After host 1 failed: 2 and 3 are back with their original queue time and form a new match
## hosted by 2 by the next tick, without waiting another CASUAL_WAIT. A timeout drops and
## re-forms in the same _process frame, so the queue is already empty there.
func _assert_requeued_and_rematched(s: FakeServer, why: String) -> void:
	assert_true(not s.pending.has(1), "%s: pending match dropped" % why)
	if not s.mm.queue.is_empty():
		assert_eq(_queued_ids(s), [2, 3], "%s: others back in the queue" % why)
		s.at(s.clock + 0.1)
	var hosts := s.orders("host")
	assert_eq(hosts.size(), 2, "%s: a new match formed" % why)
	if hosts.size() == 2:
		assert_eq(hosts[1][0], 2, "%s: a different host (the next oldest)" % why)
		assert_eq(hosts[1][1]["expected"], 2, "%s: the failed host is not in it" % why)
	assert_true(s.pending.has(2), "%s: now waiting on host 2" % why)
	if s.pending.has(2):
		var since := {}
		for e in s.pending[2]["match"]["entries"]:
			since[e["id"]] = e["since"]
		assert_eq(since.keys().size(), 2, "%s: just 2 and 3" % why)
		assert_near(since.get(2, -1.0), 0.1, 0.001, "%s: 2 kept its queue time" % why)
		assert_near(since.get(3, -1.0), 0.2, 0.001, "%s: 3 kept its queue time" % why)
	assert_eq(s.orders("join").size(), 0, "%s: nobody was sent a dead code" % why)

func test_host_disconnect_requeues_the_others() -> void:
	var s := _formed()
	s.clock += 1.0
	s._on_peer_left(1)
	_assert_requeued_and_rematched(s, "host left")
	assert_eq(s.orders("cancel"), [], "no cancellation sent to a disconnected peer")
	s.free()

func test_host_silent_past_deadline_requeues_the_others() -> void:
	var s := _formed()
	var t0 := s.clock
	s.at(t0 + s.HOST_REPLY_TIMEOUT - 0.1)
	assert_true(s.pending.has(1), "still inside the deadline")
	assert_eq(s.orders("host").size(), 1, "no new match yet")
	s.at(t0 + s.HOST_REPLY_TIMEOUT + 0.1)
	_assert_requeued_and_rematched(s, "timeout")
	assert_eq(s.orders("cancel"), [[1, {"k": "match", "role": "cancel"}]], "only the expired host is notified")
	s._on_packet(1, var_to_bytes({"k": "hosting", "code": "ABCDE-12345"}))
	assert_eq(s.orders("join"), [], "a late code is ignored")
	assert_eq(s.orders("cancel").size(), 1, "the host is cancelled once")
	s.free()

func test_host_reply_at_deadline_before_timeout_tick_is_cancelled() -> void:
	var s := _formed()
	s.clock += s.HOST_REPLY_TIMEOUT
	s._on_packet(1, var_to_bytes({"k": "hosting", "code": "ABCDE-12345"}))
	assert_eq(s.orders("cancel"), [[1, {"k": "match", "role": "cancel"}]], "packet dispatch enforces the same deadline")
	_assert_requeued_and_rematched(s, "late packet")
	s.free()

func test_empty_invite_code_requeues_the_others() -> void:
	var s := _formed()
	s._on_packet(1, var_to_bytes({"k": "hosting", "code": ""}))
	_assert_requeued_and_rematched(s, "empty code")
	s.free()

## Control: a host that answers in time is relayed exactly as before.
func test_host_replies_in_time_relays_code() -> void:
	var s := _formed()
	s.at(s.clock + s.HOST_REPLY_TIMEOUT - 1.0)
	s._on_packet(1, var_to_bytes({"k": "hosting", "code": "ABCDE-12345"}))
	var joins := s.orders("join")
	assert_eq(joins.map(func(j): return j[0]), [2, 3], "both joiners told")
	assert_true(joins.all(func(j): return j[1]["code"] == "ABCDE-12345"), "with the host's code")
	assert_true(s.pending.is_empty(), "relay done")
	assert_eq(s.orders("cancel"), [], "an accepted host never gets cancelled")
	s.at(s.clock + s.HOST_REPLY_TIMEOUT * 3)
	s._on_peer_left(1)   # host leaving later (match over) re-queues nobody
	s.at(s.clock + 0.1)
	assert_eq(s.mm.queue.size(), 0, "nobody re-queued")
	assert_eq(s.orders("host").size(), 1, "no second match")
	s.free()

## A joiner who leaves while the host is pending is not re-queued with the others.
func test_joiner_left_while_pending_is_not_requeued() -> void:
	var s := _formed()
	s._on_peer_left(3)
	s._on_peer_left(1)
	assert_eq(_queued_ids(s), [2], "only the joiner still connected")
	s.free()

## The failed host's party friend comes back as a solo; a party of one would never be complete.
func test_party_member_of_failed_host_requeues_as_solo() -> void:
	var s := FakeServer.new()
	_enq(s, 1, 0.0, "FRIENDS", 2)
	_enq(s, 2, 0.1, "FRIENDS", 2)
	_enq(s, 3, 0.2)
	s.at(MM.CASUAL_WAIT + 0.5)
	assert_eq(s.orders("host").size(), 1, "party + solo matched")
	s._on_peer_left(1)
	s.at(s.clock + 0.1)
	assert_eq(s.orders("host").size(), 2, "friend and solo form a new match")
	if s.orders("host").size() == 2:
		assert_eq(s.orders("host")[1][0], 2, "the friend hosts it")
	s.free()
