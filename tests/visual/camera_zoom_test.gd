extends "res://tests/visual/harness.gd"
## #140 mouse-wheel zoom: the same 7v7 pre-snap follow camera at the near limit, the default
## and the far limit, driven through the real wheel handler, plus the far limit on the
## offense's own 1 (boom pointing out over the end-zone stands). At every level the
## controlled player's ring stays above the scorebug (#128). The game reads the saved level
## from Launch.settings on load. Each capture waits for the camera to settle (#124).
## Zoom state is read with get()/set() so before_after.sh can run this file on a base without
## #140: there the wheel does nothing and every capture shows the fixed default camera.

const RING_R := 1.1   # PlayerRing quad half-size (presentation.gd)

var game

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var launch = root.get_node("/root/Launch")
	launch.settings.set("camera_zoom", 1.3)   # a level saved by an earlier session
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	check(game.get("cam_zoom") == 1.3 and game.get("cam_zoom_shown") == 1.3, "the saved zoom (1.3) is loaded with the match (%s)" % game.get("cam_zoom"))
	game.auto_next = false
	game.opening_kickoff = false
	game.configure(7)
	game.ai.defense_enabled = false
	game.pov_enabled = false   # the follow camera (receiver/runner/defender view)

	for shot in [["camera-zoom-min", true, 0.6], ["camera-zoom-default", false, 1.0], ["camera-zoom-max", false, 1.6]]:
		_new_play(30.0)
		if shot[0] == "camera-zoom-default":
			_middle_click()
		else:
			for i in 20:
				_wheel(shot[1])
		check(game.get("cam_zoom") == shot[2], "%s: wheel lands on %.1f (%s)" % [shot[0], shot[2], game.get("cam_zoom")])
		await _settle()
		check(game.get("cam_zoom_shown") == shot[2], "%s: zoom eased to its target" % shot[0])
		var d: float = game.camera.global_position.distance_to(game.player.global_position)
		check(absf(d - game.FOLLOW_CAM_OFFSET.length() * shot[2]) < 0.05, "%s: camera %.1f m from the player" % [shot[0], d])
		_check_ring(shot[0])
		await capture(shot[0])

	# Far limit, backed up to the offense's own 1: the boom reaches over the end line toward the stands.
	_new_play(1.0)
	await _settle()
	check(game.get("cam_zoom") == 1.6, "still at the far limit")
	_check_ring("max zoom, own 1")
	await capture("camera-zoom-max-own-1")
	launch.settings.set("camera_zoom", 1.0)
	finish()

func _new_play(los: float) -> void:
	game.series.start(0, los)
	game.series.clock.new_play()
	game.set_controlled(game.my_id)
	game.play_picker_open = false

func _wheel(up: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.factor = 1.0
	ev.pressed = true
	game._unhandled_input(ev)

func _middle_click() -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_MIDDLE
		ev.pressed = down
		game._unhandled_input(ev)

func _check_ring(what: String) -> void:
	var cam: Camera3D = game.camera
	var ring: Node3D = game.pres.ring
	var r := Rect2(cam.unproject_position(ring.global_position), Vector2.ZERO)
	for i in 24:
		var t := TAU * i / 24.0
		r = r.expand(cam.unproject_position(ring.global_position + Vector3(cos(t), 0, sin(t)) * RING_R))
	var bug: Rect2 = game.pres.overlay.bug.get_global_rect()
	check(root.get_visible_rect().encloses(r), "%s: ring on screen %s" % [what, r])
	check(r.end.y < bug.position.y, "%s: ring bottom %.0f px above the scorebug top %.0f px" % [what, r.end.y, bug.position.y])

## Run frames until the camera has stopped moving (position and zoom easing).
func _settle() -> void:
	var last: Transform3D = game.camera.global_transform
	var still := 0
	for frame in 400:
		await process_frame
		var t: Transform3D = game.camera.global_transform
		var moved: bool = t.origin.distance_to(last.origin) > 0.0001 or not t.basis.is_equal_approx(last.basis)
		last = t
		still = 0 if moved or game.get("cam_zoom_shown") != game.get("cam_zoom") else still + 1
		if still >= 3:
			print("VISUAL INFO camera settled after %d frames" % frame)
			break
	await process_frame
