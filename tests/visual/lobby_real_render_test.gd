extends "res://tests/visual/harness.gd"
## #92: the headless mesh guard must stay out of real rendering. Under the real renderer,
## Launch adds no guard, and the 3D home lobby (athlete, stage meshes) still draws.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var launch = root.get_node("Launch")
	check(DisplayServer.get_name() != "headless", "real display server (%s)" % DisplayServer.get_name())
	check(not launch.HeadlessMeshGuard.needed(), "guard reports not needed under real rendering")
	var guards := launch.get_children().filter(func(c): return c.get_script() == launch.HeadlessMeshGuard)
	check(guards.is_empty(), "Launch added no headless mesh guard")
	# Own files for this case's name/profile (optional since #236: every case gets a fresh user://).
	launch.settings_path = "user://test_lobby_render_settings.cfg"
	var menu = preload("res://scenes/menu.tscn").instantiate()
	menu.set_meta("force_menu", true)
	menu.profile_path = "user://test_lobby_render_profile.json"
	menu.leaderboard_path = "user://test_lobby_render_lb.json"
	menu.ranked_path = "user://test_lobby_render_ranked.json"
	menu.replay_dir = "user://test_lobby_render_replays"
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.content.find_child("NameEdit", true, false).text = "Ace"
	for b in menu.content.find_children("*", "Button", true, false):
		if b.text.to_upper() == "CONTINUE":
			b.pressed.emit()
	for i in 30:
		await process_frame
	check(menu.current == "home" and menu.lobby.hero != null, "home lobby shows the player's athlete")
	await capture("home-lobby-real-renderer")
	for f in ["settings.cfg", "profile.json", "lb.json", "ranked.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_lobby_render_" + f))
	finish()
