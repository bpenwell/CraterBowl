extends "res://tests/visual/harness.gd"
## #53: two movement packets reach a hosted match between ticks. The host should
## apply the cut and release on successive ticks and acknowledge them as applied.

const PEER := 7
const DT := 1.0 / 60.0
const PAIRS := 24

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.opening_kickoff = false
	game.series.start(0, 30.0)
	game._host_game(30000 + randi() % 20000, {"no_lobby": true})
	check(game.is_server(), "match is hosted")
	if not game.is_server():
		finish()
		return

	var defender = game.world.find_role(1, game.Athlete.Role.CB)
	check(game.roster.claim(PEER, game.roster.slot_of_athlete(defender.id)), "peer seated at CB")
	game.net.peer_athlete[PEER] = defender.id
	defender.set_lock = false
	defender.position = Vector2(12.0, game.world.los_y + 15.0)
	game.set_controlled(defender.id)

	var start_x: float = defender.position.x
	var first_acks: Array[int] = [0, 0, 0]
	for pair in PAIRS:
		_send(game, pair * 2 + 1, Vector2.RIGHT)
		_send(game, pair * 2 + 2, Vector2.ZERO)
		if pair == 0:
			first_acks[0] = _ack(game, defender.id)
		game._physics_process(DT)
		if pair == 0:
			first_acks[1] = _ack(game, defender.id)
		game._physics_process(DT)
		if pair == 0:
			first_acks[2] = _ack(game, defender.id)

	var moved: float = defender.position.x - start_x
	check(first_acks == [0, 1, 2], "first burst acknowledgements: %s" % [first_acks])
	check(moved > 2.5, "host applied the lateral cuts (%.2f yd)" % moved)
	check(_ack(game, defender.id) == PAIRS * 2, "host acknowledged every command")
	_show_evidence(first_acks, moved)

	# Snap view targets and camera to the final sim state before capturing.
	game._render()
	game.player.interpolate(1.0)
	game.cam_yaw = game._camera_target_yaw()
	game.camera_follow = game.player.global_position
	game._update_camera(DT)
	await capture("host-after-bursts")
	finish()

func _send(game, seq: int, dir: Vector2) -> void:
	game.net._on_packet(PEER, var_to_bytes({"k": "in", "seq": seq, "dir": dir}))

func _ack(game, athlete_id: int) -> int:
	return game.net.acks().get(athlete_id, 0)

func _show_evidence(acks: Array[int], moved: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var label := Label.new()
	label.position = Vector2(32, 124)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.text = "Remote CB on the host\nFirst burst ack at receive and next two ticks: %d, %d, %d\nLateral movement after %d input pairs: %.2f yd" % [
		acks[0], acks[1], acks[2], PAIRS, moved]
	layer.add_child(label)
