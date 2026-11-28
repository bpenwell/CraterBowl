extends "res://tests/visual/harness.gd"
## #308: a real queue client abandons a lobby whose invite code missed the deadline.

const Main := preload("res://scenes/main.tscn")
const MMClient := preload("res://src/net/mm_client.gd")
const MM := preload("res://src/net/matchmaker.gd")

class DeadlineServer extends "res://src/net/mm_server.gd":
	var clock := 0.0
	var late_host := -1
	var retried := {}

	func _now() -> float:
		return clock

	func _on_packet(from: int, bytes: PackedByteArray) -> void:
		var msg = bytes_to_var(bytes)
		if msg is Dictionary:
			if msg.get("k") == "hosting" and late_host < 0 and pending.has(from):
				# Receive the real invite code just as the deadline expires, before _process runs.
				late_host = from
				clock = pending[from]["deadline"]
			elif msg.get("k") == "enq" and from == late_host:
				retried = msg
		super._on_packet(from, bytes)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var mms := DeadlineServer.new()
	mms.name = "TimeoutMatchmaker"
	root.add_child(mms)
	var port := 30000 + (Time.get_ticks_usec() + OS.get_process_id()) % 5000 * 2
	if not _expect(mms.start(port) == OK, "loopback matchmaker is listening"):
		return
	var game_port := port + 1
	var launch = root.get_node("Launch")
	launch.options = {"queue": "casual", "size": 3, "name": "Riley", "rating": 1150,
		"party": "FRIENDS:2", "mm": "127.0.0.1:%d" % port, "host-port": game_port, "advertise": "127.0.0.1"}
	var game = Main.instantiate()
	root.add_child(game)
	current_scene = game
	if not _expect(await _until(func(): return mms.mm.queue.size() == 1), "the game enters the party queue"):
		return
	check(game.searching() and game.drill != null, "the original search shows warm-up")

	mms.clock = 1.0
	var friend := MMClient.new()
	friend.name = "QueuedFriend"
	root.add_child(friend)
	var friend_orders: Array = []
	friend.host_match.connect(func(order): friend_orders.append(order))
	if not _expect(friend.queue_up("127.0.0.1", port, "casual", 3, 1050, "Morgan", "FRIENDS", 2) == OK
			and await _until(func(): return mms.mm.queue.size() == 2), "the other party member enters"):
		return
	mms.clock = MM.CASUAL_WAIT + 1.0
	check(await _until(func(): return mms.late_host >= 0), "the elected host opens the lobby and sends its code")
	check(await _until(func(): return not mms.retried.is_empty()), "the timed-out host queues again on the same connection")
	check(game.searching() and game.net == null and game.drill != null and game.drill.kind == "hub",
		"the host returns to the training ground and resumes its search")
	check(mms.retried.get("game") == "classic" and mms.retried.get("mode") == "casual"
		and mms.retried.get("size") == 3 and mms.retried.get("rating") == 1150,
		"the retry preserves game, queue, size and rating")
	check(mms.retried.get("party") == "" and mms.retried.get("party_size") == 1,
		"the host retries as solo after the party falls apart")
	check(await _until(func(): return not friend_orders.is_empty()), "the waiting player can host a new match")
	var freed_port := ENetMultiplayerPeer.new()
	if game.net == null:
		check(freed_port.create_server(game_port, 1) == OK, "the cancelled lobby released its UDP port")
		freed_port.close()

	game.queue_started_ms = Time.get_ticks_msec()
	game.set_physics_process(false)
	game._update_camera(4.0)
	await process_frame
	check(game.pres.overlay.mode_l.text.begins_with("SEARCHING FOR A CASUAL MATCH"),
		"the HUD displays the resumed search")
	await capture("host-timeout-search")
	finish()

func _expect(condition: bool, message: String) -> bool:
	check(condition, message)
	if not condition:
		finish()
	return condition

func _until(condition: Callable) -> bool:
	for frame in 100:
		if condition.call():
			return true
		await process_frame
	return false
