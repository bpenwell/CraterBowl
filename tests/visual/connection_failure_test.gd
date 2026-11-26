extends "res://tests/visual/harness.gd"
## #85: ENet connection failure reaches the menu from the lobby and the queue.

const Main := preload("res://scenes/main.tscn")
const InviteCode := preload("res://src/net/invite_code.gd")
const MENU_SCENE := "res://scenes/menu.tscn"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var launch = root.get_node("Launch")
	launch.settings_path = "user://test_connection_failure_settings.cfg"
	launch.settings.player_name = "Rookie"
	# Hold a UDP socket open without an ENet listener, so the test never hits another
	# session's server. Emit the transport signal directly to avoid the ENet timeout delay.
	var blackhole := PacketPeerUDP.new()
	check(blackhole.bind(0, "127.0.0.1") == OK, "reserved a local port without an ENet host")
	var port := blackhole.get_local_port()
	var host_join = _open_game()
	var invite := InviteCode.encode("127.0.0.1", port)
	host_join._join_game(invite, 0, {})
	check(host_join.is_client() and host_join.in_lobby(), "join waits in the lobby")
	host_join.net.api.connection_failed.emit()
	await _check_menu("Couldn't reach the host")
	await capture("unreachable-host-menu-status")

	var queued = _open_game()
	queued._queue_up({"queue": "casual", "mm": "127.0.0.1:%d" % port})
	check(queued.searching(), "queue waits for the matchmaker")
	queued.mm_client.api.connection_failed.emit()
	await _check_menu("Couldn't reach the matchmaker")
	await capture("unreachable-matchmaker-menu-status")
	blackhole.close()
	finish()

func _open_game():
	if current_scene != null:
		current_scene.queue_free()
	var game = Main.instantiate()
	root.add_child(game)
	current_scene = game
	return game

func _check_menu(status: String) -> void:
	for frame in 80:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == MENU_SCENE:
			break
	var menu = current_scene
	if menu == null or menu.scene_file_path != MENU_SCENE:
		check(false, "returned to the menu")
		return
	check(menu.status_label.text == status and menu.status_label.is_visible_in_tree(),
		"menu status reads " + status)
