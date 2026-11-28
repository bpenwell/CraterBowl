extends "res://tests/visual/harness.gd"
## #236/#206: a case that saves settings to the default user://settings.cfg (no settings_path
## of its own) must not leak them into later cases. visual_test.sh gives each case fresh user
## data, and harness.gd's _init asserts every case starts empty, so if isolation breaks, the
## cases after this one fail (menu_boot_test would land on home instead of the welcome prompt).
## The name sorts early on purpose so most of the suite runs after it.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var launch = root.get_node("Launch")
	# Never write a developer's real settings when run by hand outside visual_test.sh.
	var isolated := OS.get_environment("XDG_DATA_HOME") != ""
	check(isolated, "runs with throwaway user data (XDG_DATA_HOME set)")
	if isolated:
		launch.settings.player_name = "Leaky"
		launch.save_settings()
	check(FileAccess.file_exists("user://settings.cfg"), "saved a name to the default user://settings.cfg")
	var menu = preload("res://scenes/menu.tscn").instantiate()
	menu.set_meta("force_menu", true)
	root.add_child(menu)
	current_scene = menu
	for i in 5:
		await process_frame
	check(menu.current == "home", "the saved name skips the welcome prompt in this case")
	await capture("saved-name-home")
	finish()
