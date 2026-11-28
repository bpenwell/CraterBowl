extends "res://tests/visual/harness.gd"
## #233 (part of #132): each team's logo sits beside its score on the scorebug, and both
## logos flank the hold-Tab scoreboard. Fixed state (Q1 7-3, HELIOS ball, presnap) so the
## captures are reproducible: physics is frozen and the camera snapped before each capture.

## No preload of the new scripts: before_after.sh carries this test onto a base without them.
const LOGO := "res://assets/teams/%s.png"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.opening_kickoff = false
	var series = game.series
	series.start(0, 30.0)
	game.set_controlled(game.my_id)
	series.score = [7, 3]
	series.clock.remaining = 300.0   # Q1: a Q2 start would raise the animated SWITCH ENDS banner
	series.clock.play_clock = 20.0
	game.set_physics_process(false)   # exact state: no play clock tick, no athlete drift
	var overlay = game.pres.overlay
	await _settle(game)
	# Guarded so before_after.sh can still photograph a base without logos (its checks fail).
	var has_logos: bool = "team_logo" in overlay
	check(has_logos, "overlay has team logos")
	for t in (2 if has_logos else 0):
		var id: String = ["helios", "nebula"][t]
		var logo: TextureRect = overlay.team_logo[t]
		check(logo.is_visible_in_tree() and logo.texture != null and logo.texture.resource_path == LOGO % id, "scorebug shows the %s logo" % id)
		check(overlay.bug.get_global_rect().encloses(logo.get_global_rect()), "%s logo fits inside the scorebug" % id)
		check(logo.size.y >= 30.0, "%s logo is drawn at a readable size (%.0f px)" % [id, logo.size.y])
		check(logo.size.x >= 30.0 and is_equal_approx(logo.size.x, logo.size.y), "%s logo is square" % id)
		var score: Label = overlay.team_score[t]
		check(logo.get_global_rect().end.x <= score.get_global_rect().position.x, "%s logo is beside (left of) its score" % id)
	if has_logos:
		check(overlay.team_logo[0].get_global_rect().end.x <= overlay.team_logo[1].get_global_rect().position.x, "HELIOS logo left, NEBULA logo right")
	check(root.get_visible_rect().encloses(overlay.bug.get_global_rect()), "scorebug still fits the viewport")
	check(not overlay.scoreboard.visible, "Tab board hidden until Tab is held")
	await capture("team-logos-scorebug")

	# Hold Tab through the real input handler.
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	game._input(tab)
	await _settle(game)
	check(overlay.scoreboard.is_visible_in_tree(), "holding Tab shows the scoreboard")
	var text_rect: Rect2 = overlay.scoreboard_label.get_global_rect()
	for t in (2 if has_logos else 0):
		var id: String = ["helios", "nebula"][t]
		var logo: TextureRect = overlay.board_logo[t]
		check(logo.is_visible_in_tree() and logo.texture != null and logo.texture.resource_path == LOGO % id, "Tab board shows the %s logo" % id)
		check(not logo.get_global_rect().intersects(text_rect), "%s board logo clears the text" % id)
		check(overlay.scoreboard.get_global_rect().encloses(logo.get_global_rect()), "%s board logo sits inside the card" % id)
	check(has_logos and overlay.board_logo[0].get_global_rect().end.x <= text_rect.position.x and overlay.board_logo[1].get_global_rect().position.x >= text_rect.end.x, "logos flank the board: HELIOS left, NEBULA right")
	await capture("team-logos-tab-board")
	tab.pressed = false
	game._input(tab)
	finish()

func _refresh() -> void:
	for frame in 5:
		await process_frame

## Snap the views and the follow camera to the sim state (as presnap_locks_test.gd does).
func _settle(game) -> void:
	game._render()
	for v in game.views:
		v.interpolate(1.0)
	await _refresh()
	game.cam_yaw = game._camera_target_yaw()
	game.camera_follow = game.player.global_position
	game._update_camera(1.0 / 60.0)
	await _refresh()
