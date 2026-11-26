extends SceneTree
## Two-process net test (client side). Run with: -- --join=127.0.0.1 --port=N
## against a host started with: -- --host --port=N --playclock=4
## --host-loss (#56): join, print "NET HOSTLOSS ARMED" once in the match, then expect the
## host to be killed (net_test.sh does it) and assert we land on the menu with
## "Host disconnected".

var main
var f := 0
var ok := true
var aid := -1
var snaps := 0
var echoed_input_seq := 0
var input_acks_valid := true
var start_x := INF
var max_dx := 0.0
var got_snap_event := false
var saw_live := false
var bad_snap_sent_at := -1
var bad_snap_rejected := false
var last_server_x := INF
var aid_before_swap := -1
var aid_before_pick := -1
var team_swap_rejected := false
var pick_rejected := false
var equipped_number := ""
var first_team := -1
var saw_lobby := false
var lobby_size := 0
var quarter_lobby_seen := false
var quarter_clock_seen := false
var lobby_code := ""
var lead_samples := 0
var was_locked := false     # C08d: joiner (defense) started in stance per host snapshot
var broke_stance := false   # host snapshot shows the lock cleared after our Space
var crossed_line := false   # predicted defender ever past the neutral zone
var defense_call_seen := false
var defense_recall_seen := false
var sent_timeout := false
var got_timeout_event := false
var timeout_confirmed := false
var called_run := false
var snapped_run := false
var sent_handoff := false
var handoff_to := -1
var remote_handoff_confirmed := false
var host_loss := false      # #56 mode
var armed_at := -1

func check(cond: bool, msg: String) -> void:
	print(("  NET OK   " if cond else "  NET FAIL ") + msg)
	if not cond:
		ok = false

func _on_snap(s: Dictionary) -> void:
	snaps += 1
	if aid >= 0:
		last_server_x = (s["a"] as PackedFloat32Array)[aid * 7]
		var seq: int = s.get("ack", {}).get(aid, 0)
		input_acks_valid = input_acks_valid and seq >= echoed_input_seq and seq <= main.predictor.seq
		echoed_input_seq = seq
	if s.get("dc") == "edge_blitz" and main.world.defensive_call == "edge_blitz":
		defense_call_seen = true
	if main.series.clock.label() == "Q1 3:00" and main.series.clock.quarter_length == 180.0:
		quarter_clock_seen = true
	if s["ph"] == 1:
		saw_live = true

func _on_lobby(st: Dictionary) -> void:
	if not saw_lobby and st.get("phase", 1) == 0:
		saw_lobby = true
		var settings: Dictionary = st.get("settings", {})
		lobby_size = int(settings.get("size", 0))
		quarter_lobby_seen = settings.get("quarters") == true and settings.get("quarter_minutes") == 3
		lobby_code = str(st.get("code", ""))
		main.lobby_key(KEY_ENTER)   # ready up through the real lobby key path

func _on_welcome(id: int) -> void:
	aid = id
	if first_team < 0 and main.profile.install_id != "":   # once: net_test.sh matches this against what the host received (#102)
		print("NET client install id %s" % main.profile.install_id)
	if first_team < 0:
		first_team = main.world.get_athlete(id).team

func _on_event(n: String, _d: Dictionary) -> void:
	if n == "snap":
		got_snap_event = true
	if n == "timeout" and _d.get("team") == 1 and _d.get("remaining") == 2:
		got_timeout_event = true
	if n == "handoff" and _d.get("by") == aid:
		handoff_to = int(_d["to"])

func _initialize() -> void:
	host_loss = OS.get_cmdline_user_args().has("--host-loss")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	if host_loss:
		current_scene = main   # like a real launch, so Launch.go_to_menu swaps it out

func _physics_process(_dt: float) -> bool:
	f += 1
	if host_loss:
		return _host_loss_step()
	if f == 2:
		main.net.lobby_received.connect(_on_lobby)
		main.net.welcomed.connect(_on_welcome)
		main.net.snapshot_received.connect(_on_snap)
		main.net.event_received.connect(_on_event)
	if aid >= 0 and snaps > 3:
		var x: float = main.world.get_athlete(aid).position.x
		if start_x == INF:
			start_x = x
			main.do_action({"a": "defense", "p": "edge_blitz"})
			var me = main.world.get_athlete(aid)
			was_locked = me.set_lock or me.role == main.Athlete.Role.DL
			main.do_action({"a": "snap"})          # defense Space: break stance over the wire
			main.input_override = Vector2(1, 0)  # strafe right (legal presnap once roaming)
		if not broke_stance and main.world.phase == 0 and not main.world.get_athlete(aid).set_lock:
			broke_stance = true
		var a = main.world.get_athlete(aid)
		if main.world.phase == 0 and a.team != main.world.offense_team and a.position.y < main.world.los_y + 0.5 - 0.001:
			crossed_line = true

		max_dx = maxf(max_dx, x - start_x)
	# With prediction, the locally shown position leads the last raw server state while moving.
	if aid >= 0 and main.input_override == Vector2(1, 0) and last_server_x != INF and main.world.phase == 0:
		if main.world.get_athlete(aid).position.x - last_server_x > 0.02:
			lead_samples += 1
	# After the first play ends and the next presnap begins, try an illegal defense snap.
	if saw_live and bad_snap_sent_at < 0 and main.world.phase == 0:
		main.input_override = Vector2.ZERO
		main.do_action({"a": "snap"})
		main.do_action({"a": "recall_call"})
		bad_snap_sent_at = f
	if bad_snap_sent_at > 0 and f == bad_snap_sent_at + 30:
		bad_snap_rejected = main.world.phase == 0
		defense_recall_seen = main.world.defensive_call == "edge_blitz"
		aid_before_swap = aid
		main.do_action({"a": "team"})
	if bad_snap_sent_at > 0 and f == bad_snap_sent_at + 60:
		team_swap_rejected = aid == aid_before_swap and main.world.get_athlete(aid).team == first_team
		aid_before_pick = aid
		main.do_action({"a": "pick", "slot": 0})
	if bad_snap_sent_at > 0 and f == bad_snap_sent_at + 90:
		pick_rejected = aid == aid_before_pick and main.world.get_athlete(aid).team == first_team
		equipped_number = main.views[aid].number_text
	if bad_snap_sent_at > 0 and f > bad_snap_sent_at + 90:
		_test_remote_handoff()
	if f == 1500 or remote_handoff_confirmed:
		check(saw_lobby and lobby_size == 5 and lobby_code.length() == 11, "joined by code into the private lobby (5v5, code %s)" % lobby_code)
		check(quarter_lobby_seen and quarter_clock_seen, "host lobby Q and H select three-minute quarters on both machines")
		check(aid >= 0, "readied up -> match started -> welcomed with athlete %d" % aid)
		check(first_team == 1, "joiner initially placed on the opponent team")
		check(main.match_size == 5 and main.world.athletes.size() == 10, "client adopted host's 5v5 (%d athletes)" % main.world.athletes.size())
		check(snaps > 20, "receiving snapshots (%d)" % snaps)
		check(input_acks_valid and echoed_input_seq > 0, "host acknowledges movement inputs in sequence")
		check(max_dx > 2.0, "own input moved own athlete on server (dx %.1f)" % max_dx)
		check(was_locked, "joiner on defense starts in stance")
		check(broke_stance, "defense Space broke stance via the host (snapshot lock cleared)")
		check(not crossed_line, "predicted defender never past the neutral zone")
		check(lead_samples > 10, "own athlete predicted ahead of server state (%d frames)" % lead_samples)
		check(saw_live and got_snap_event, "host auto-snap reached client (snapshot LIVE + reliable event)")
		check(defense_recall_seen, "remote defender recalled the previous snap's call")
		check(defense_call_seen, "defensive selection reached host and returned in a snapshot")
		check(bad_snap_rejected, "defense snap rejected by server")
		check(team_swap_rejected, "legacy team request preserves the host assignment")
		check(equipped_number == "88", "my equipped #88 round-tripped through the host (%s)" % equipped_number)
		check(pick_rejected, "legacy slot request preserves the host assignment")
		check(timeout_confirmed and got_timeout_event, "remote U decrements only its team's timeouts and broadcasts the event")
		check(remote_handoff_confirmed, "client QB hands off through G and sees the host's RB possession")
		check(remote_handoff_confirmed and main.controlled_id == aid, "online QB keeps the same athlete after the handoff")
		print("NET FLOW " + ("PASS" if ok else "FAIL"))
		quit(0 if ok else 1)
	return false

func _test_remote_handoff() -> void:
	var w = main.world
	var me = w.get_athlete(aid)
	if me == null or me.team != 1:
		return
	if w.offense_team != 1 or me.role != main.Athlete.Role.QB:
		return
	if not sent_timeout and w.phase == w.Phase.PRESNAP:
		_key(KEY_U)
		sent_timeout = true
	if sent_timeout and main.series.clock.timeouts == [3, 2]:
		timeout_confirmed = true
	if timeout_confirmed and not called_run and w.phase == w.Phase.PRESNAP:
		main.do_action({"a": "play", "p": "Inside Zone"})
		called_run = true
	if not snapped_run and w.phase == w.Phase.PRESNAP and w.play_name == "Inside Zone":
		_key(KEY_SPACE)
		snapped_run = true
	if snapped_run and not sent_handoff and w.handoff_receiver(aid) != null:
		_key(KEY_G)
		sent_handoff = true
	var back = w.find_role(1, main.Athlete.Role.RB)
	remote_handoff_confirmed = sent_handoff and back != null and back.id == handoff_to and w.ball.is_held_by(back.id)

## #56: in the match, then the host dies -> back on the menu saying why.
func _host_loss_step() -> bool:
	if f == 2:
		main.net.welcomed.connect(_on_welcome)
		main.net.snapshot_received.connect(_on_snap)
	if armed_at < 0 and aid >= 0 and snaps > 5:
		armed_at = f
		print("NET HOSTLOSS ARMED")
		for a in OS.get_cmdline_user_args():   # stdout is buffered: tell net_test.sh via a file
			if a.begins_with("--armed-file="):
				FileAccess.open(a.get_slice("=", 1), FileAccess.WRITE).store_string("armed\n")
	var scene = current_scene
	var on_menu: bool = scene != null and scene.scene_file_path == "res://scenes/menu.tscn" and scene.get("status_label") != null
	if on_menu or f == 3000:
		check(armed_at > 0, "in the match (athlete %d, %d snapshots) before the host died" % [aid, snaps])
		check(on_menu, "client left the frozen match for the menu after losing the host (%.1fs after arming)" % ((f - armed_at) / 60.0))
		var status: String = scene.status_label.text if on_menu else ""
		check(status == "Host disconnected", "menu status says why: '%s'" % status)
		print("NET HOSTLOSS " + ("PASS" if ok else "FAIL"))
		quit(0 if ok else 1)
	return false

func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	main._unhandled_key_input(event)
