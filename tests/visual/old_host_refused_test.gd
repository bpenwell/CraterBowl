extends "res://tests/visual/harness.gd"
## #224: a host from before the version handshake (#165) never checks our hello and sends a
## `welcome` without its version `v`. The client must refuse it itself: the join screen says
## "This server runs an older Crater Bowl (...)" and the player is never seated.
## On a base tree without the client-side check the joiner simply gets seated (before_after.sh).

const NetSession := preload("res://src/net/net_session.gd")

## A pre-#165 host: seats every joiner straight away and its welcome carries no `v`.
class OldHost extends NetSession:
	func _on_peer_connected(id: int) -> void:
		_admit(id)
	func _send(target: int, msg: Dictionary, reliable: bool) -> void:
		if msg.get("k") == "welcome":
			msg = msg.duplicate()
			msg.erase("v")
		super._send(target, msg, reliable)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var port := 32000 + randi() % 2000
	var host := OldHost.new()
	host.name = "OldHost"
	root.add_child(host)
	check(host.host(port, func(_p): return 7, func(_p): pass) == OK, "old host listening on %d" % port)

	var game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._join_game("127.0.0.1", port, {})
	var ours: int = game.net.protocol_version
	for frame in 300:
		await process_frame
		if game.net.refused_reason != "" or game.net.my_athlete >= 0:
			break
	for frame in 10:   # let the HUD redraw
		await process_frame
	var want := "This server runs an older Crater Bowl (server is an older build, you have v%d)" % ours
	check(game.net.refused_reason == want, "joiner refused the old host's welcome: '%s'" % game.net.refused_reason)
	check(game.net.my_athlete < 0, "never seated on the old host")
	check(game.in_lobby() and game.hud.visible and game.hud.text.contains("COULDN'T JOIN") and game.hud.text.contains(want), "join screen shows why")
	check(not game.hud.text.contains("bigger match"), "no capacity hint for a version mismatch")
	await capture("old-host-refused")
	finish()
