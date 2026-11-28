extends "res://tests/flow/segment.gd"
## #139 radial taunt wheel through the real C key + mouse handlers, on a pre-snap QB in POV aim
## (the mode where mouse motion matters most): the wheel opens on C, drag picks a slice while
## the camera and aim hold still, release performs it, the dead zone cancels and a tap repeats
## the last taunt. The mouse wheel no longer picks taunts.

const Emotes := preload("res://src/sim/emotes.gd")

func setup() -> void:
	main.configure(7)
	main.ai.defense_enabled = false
	main.pov_enabled = true
	main.mouse_captured_override = true

func steps() -> Array:
	return [
		[2, func():
			var qb = main.world.get_athlete(main.controlled_id)
			var w = main.taunt_wheel
			check(main.pov_active() and qb.emote_cd == 0.0, "taunt wheel step: QB in POV aim, no taunt yet")
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
			ev.pressed = true
			main._unhandled_input(ev)
			check(not w.open and qb.emote_cd == 0.0, "mouse wheel no longer picks or performs taunts")
			flow._mouse(Vector2(40, 0))
			check(main.aim_yaw > 0.0, "mouse motion turns the aim while the wheel is closed")
			main.reset_aim()
			var before := [main.aim_yaw, main.aim_pitch, main.camera_orbit, main.aim_distance]
			flow._key(KEY_C)
			check(w.open and w.visible and w.ids.size() == 8, "holding C opens the wheel: a slice per taunt")
			flow._mouse(Vector2(0, -80))
			check(w.highlighted() == w.ids[0], "drag up highlights the top slice (%s)" % w.highlighted())
			flow._mouse(Vector2(160, 80))
			check(w.highlighted() == w.ids[2], "drag right highlights the right slice (%s)" % w.highlighted())
			check([main.aim_yaw, main.aim_pitch, main.camera_orbit, main.aim_distance] == before, "camera and aim hold still while the wheel is open")
			flow._key(KEY_C, false)
			var v = main.views[main.controlled_id]
			check(not w.open and qb.emote_cd > 0.0 and v.emote_id == w.ids[2] and v.emote_t > 0.0 and v.bubble.visible, "releasing C performs the highlighted taunt (%s)" % v.emote_id)
			flow._mouse(Vector2(40, 0))
			check(main.aim_yaw > 0.0, "the aim turns again once the wheel closes")
			main.reset_aim()],
		[70, func():
			var qb = main.world.get_athlete(main.controlled_id)
			var w = main.taunt_wheel
			var v = main.views[main.controlled_id]
			check(qb.emote_cd == 0.0, "taunt cooldown over")
			flow._key(KEY_C)
			flow._mouse(Vector2(0, -60))
			flow._mouse(Vector2(0, 60))
			flow._key(KEY_C, false)
			check(not w.open and qb.emote_cd == 0.0, "releasing C in the dead zone cancels")
			flow._key(KEY_C)
			flow._key(KEY_C, false)
			check(qb.emote_cd > 0.0 and v.emote_id == w.ids[2] and v.emote_t > Emotes.DURATION - 0.05, "tapping C repeats the last taunt (%s)" % v.emote_id)],
	]
