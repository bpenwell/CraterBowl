extends "res://tests/visual/harness.gd"
## #299: hosting on a UDP port something else already holds opens no lobby and issues no
## invite code. From the menu's Online → Private match → "Host a match" it goes back to the
## menu saying "Couldn't host on port N". (The CLI/headless host's non-zero exit:
## tests/test_host_port_in_use.gd.)

const Main := preload("res://scenes/main.tscn")
const MENU_SCENE := "res://scenes/menu.tscn"
const HELD_PORT := 24599

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var launch = root.get_node("Launch")
	launch.settings.player_name = "Ace"
	launch.settings.upnp = false              # never touch a real router from tests
	# Another host already holds the port, as a second Crater Bowl on this machine would.
	# A fixed port keeps the capture's text stable; if another run holds it, it's just as taken.
	var holder := ENetMultiplayerPeer.new()
	print("test holder on %d: %s" % [HELD_PORT, error_string(holder.create_server(HELD_PORT, 1))])
	var status := "Couldn't host on port %d. Is another game using it?" % HELD_PORT

	# The player's path: Online → Private match → Host a match.
	var menu = preload("res://scenes/menu.tscn").instantiate()
	menu.set_meta("force_menu", true)
	menu.host_port = HELD_PORT
	root.add_child(menu)
	current_scene = menu
	await _frames(3)
	menu.list_public = false
	menu.show_screen("online")
	# The game scene opens and leaves within one frame, so watch it from the tree.
	var seen := {}
	node_added.connect(func(n):
		if n.scene_file_path == launch.GAME_SCENE and n.get_parent() == root:
			n.tree_exiting.connect(func():
				seen["code"] = n.lobby.code
				seen["lobby"] = n.in_lobby() or n.is_server()))
	menu.host_match()
	for i in 120:
		await process_frame
		if seen.has("code") and current_scene != null and current_scene.scene_file_path == MENU_SCENE:
			break
	check(seen.has("code"), "Host a match opened the game scene and left it")
	check(seen.get("code", "x") == "" and not seen.get("lobby", true), "no lobby or invite code on the held port")
	await _check_menu(status)
	await _frames(5)
	await capture("host-port-in-use-menu-status")

	# The hosting call every launcher uses (menu, CLI --host, matchmade host) refuses outright.
	launch.from_menu = true                   # a menu launch: failure returns to the menu
	var direct = Main.instantiate()
	root.add_child(direct)
	current_scene = direct
	var code: String = direct._host_game(HELD_PORT, {"advertise": "127.0.0.1"})
	check(code == "", "_host_game returns no invite code for a held port (got '%s')" % code)
	check(direct.lobby.code == "" and not direct.in_lobby() and direct.net == null, "no lobby and no net session")
	await _check_menu(status)
	holder.close()
	finish()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _check_menu(status: String) -> void:
	for frame in 80:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == MENU_SCENE:
			break
	var menu = current_scene
	if menu == null or menu.scene_file_path != MENU_SCENE:
		check(false, "returned to the menu")
		return
	await process_frame
	check(menu.status_label.text == status and menu.status_label.is_visible_in_tree(),
		"menu status reads '%s' (got '%s')" % [status, menu.status_label.text])
