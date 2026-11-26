extends "res://tests/visual/harness.gd"
## #60: the client receive path preserves game and profile state on invalid host data.

const Main := preload("res://scenes/main.tscn")
const Protocol := preload("res://src/net/protocol.gd")
const NetSession := preload("res://src/net/net_session.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = Main.instantiate()
	root.add_child(game)
	current_scene = game
	game._ensure_net()
	game.net.host_size = game.match_size
	game.net.mode = NetSession.Mode.CLIENT
	game.net.snapshot_received.connect(game._on_snapshot)
	game.net.event_received.connect(game._on_world_event)
	game.profile_path = "user://invalid-host-state-test.json"
	var snapshot: Dictionary = Protocol.encode_snapshot(game.series, 10)
	snapshot["s"] = PackedInt32Array([7, 3])
	game.net._on_packet(1, var_to_bytes(snapshot))
	check(game.series.score == [7, 3], "valid snapshot establishes the score")
	for fields in [
		{"a": PackedFloat32Array()}, {"ack": []}, {"ph": "live"},
		{"b": PackedFloat32Array([0, -1, INF, 0, 0, 0, 0, 0])}, {"t": []},
	]:
		var invalid := snapshot.duplicate()
		invalid.merge({"t": 99, "s": PackedInt32Array([99, 99])}, true)
		invalid.merge(fields, true)
		game.net._on_packet(1, var_to_bytes(invalid))
		check(game.series.score == [7, 3] and game.net.last_snapshot_tick == 10,
			"malformed snapshot preserves the last score and tick")
	var xp_before: int = game.profile.xp
	var games_before: int = game.profile.games
	for award in [
		{"xp": {game.player_name: []}},
		{"xp": {game.player_name: -1}},
		{"xp": {game.player_name: 10_001}},
		{"xp": {game.player_name: 100}, "ctx": {game.player_name: {"line": []}}},
	]:
		game.net._on_packet(1, var_to_bytes({"k": "ev", "n": "awards", "d": award}))
	check(game.profile.xp == xp_before and game.profile.games == games_before,
		"invalid awards leave the profile unchanged")
	snapshot["t"] = 11
	snapshot["s"] = PackedInt32Array([14, 3])
	game.net._on_packet(1, var_to_bytes(snapshot))
	game.net._on_packet(1, var_to_bytes({"k": "ev", "n": "awards", "d": {"xp": {game.player_name: 100}}}))
	check(game.series.score == [14, 3] and game.net.last_snapshot_tick == 11,
		"next valid snapshot still applies")
	check(game.profile.xp == xp_before + 100 and game.profile.games == games_before + 1,
		"valid award still credits the local profile")
	await capture("client-after-invalid-host-state")
	finish()
