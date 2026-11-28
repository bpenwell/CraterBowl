extends "res://tests/visual/harness.gd"
## #183: a set defender who hasn't roamed yet this session sees "SPACE ×2 TO ROAM" in the
## HUD status pill; after the first double-tap roam the next play's pill is empty again.
## Driven through the real key handler, like a player would.

const DT := 1.0 / 60.0
const HINT := "PRE-SNAP: SET  ·  SPACE ×2 TO ROAM"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.auto_next = false
	game.opening_kickoff = false
	var w = game.world
	var pill = game.pres.overlay.status_l

	game.series.start(1, 30.0)
	game.set_controlled(game.my_id)
	var me = w.get_athlete(game.my_id)
	check(me.role != game.Athlete.Role.DL and me.set_lock, "human defender (%s) lines up set" % me.role)
	await _settle(game)
	check(pill.text == HINT and game.pres.overlay.status_pill.visible, "first set play: pill shows the roam hint (%s)" % pill.text)
	await capture("presnap-roam-hint")

	_space(game)
	_space(game)
	check(not me.set_lock and game.roamed_once, "double-tap roams")
	game.series.start(1, 30.0)
	game.set_controlled(game.my_id)
	await _settle(game)
	check(w.get_athlete(game.my_id).set_lock, "next play: set again")
	check(pill.text == "" and not game.pres.overlay.status_pill.visible, "after the first roam: no hint (%s)" % pill.text)
	await capture("presnap-roam-hint-gone")
	finish()

func _space(game) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	game._unhandled_key_input(ev)

## Snap every view and the camera to the final sim state and let the 20 Hz HUD text refresh.
func _settle(game) -> void:
	game._render()
	for v in game.views:
		v.interpolate(1.0)
	for i in 6:
		await process_frame
	game.cam_yaw = game._camera_target_yaw()
	game.camera_follow = game.player.global_position
	game._update_camera(DT)
