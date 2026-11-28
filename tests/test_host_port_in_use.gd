extends "res://tests/test_case.gd"

## #299: a CLI/headless host whose UDP port is already held must exit non-zero without
## opening a lobby or printing an invite code. This test holds the port with its own ENet
## host, then runs the real `--host` launch in a headless child (the child's expected
## "Couldn't create an ENet host" engine error stays in its own log). `--quit-after` bounds
## the child if it wrongly keeps hosting.
func test_cli_host_on_a_held_port_exits_without_an_invite_code() -> void:
	var holder := ENetMultiplayerPeer.new()
	var port := 0
	for attempt in 20:
		var p := 30000 + randi() % 20000
		if holder.create_server(p, 1) == OK:
			port = p
			break
	assert_true(port != 0, "test holds a UDP port with its own ENet host")
	if port == 0:
		return
	var out := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--quit-after", "600", "--", "--host", "--port=%d" % port, "--advertise=127.0.0.1"], out, true)
	holder.close()
	var log: String = "".join(out)
	assert_eq(code, 1, "host exit code on a held port")
	assert_true(log.contains("NET host on %d: Can't create" % port), "reports the failed bind: " + _lines(log, "NET"))
	assert_true(not log.contains("NET invite code"), "no invite code for a port it doesn't hold: " + _lines(log, "NET"))

func _lines(log: String, key: String) -> String:
	return " | ".join(Array(log.split("\n")).filter(func(l): return l.contains(key)))
