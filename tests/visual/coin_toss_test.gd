extends "res://tests/visual/harness.gd"
## #129: the coin-toss cutscene before the opening kickoff. Physics is frozen and the
## cutscene's timeline is pinned with seek(), so every capture shows the same moment:
## - coin-toss-captains:     both captains at midfield with the ref (lower third up)
## - coin-toss-coin-in-air:  the flip, coin near its apex
## - coin-toss-you-won:      result title + RECEIVE / KICK cards (no key hints)
## - coin-toss-decided:      KICK clicked with the real mouse: the pick holds, "WILL KICK"
## - coin-toss-they-choose:  bots won: "<TEAM> WINS THE TOSS", "<TEAM> IS CHOOSING…"
## - coin-toss-online-client: a client fed host snapshots plays it too and shows the host's pick
## On a base without the cutscene (before_after.sh) the same moments show the plain toss HUD.

const Main := preload("res://scenes/main.tscn")
const Protocol := preload("res://src/net/protocol.gd")
const NetSession := preload("res://src/net/net_session.gd")
const World := preload("res://src/sim/world.gd")
const Roster := preload("res://src/sim/roster.gd")
const Match := preload("res://src/sim/match.gd")
## Via the constant map so before_after.sh can run this on a base without TOSS_REVEAL.
var REVEAL: float = (load("res://src/sim/match.gd") as Script).get_script_constant_map().get("TOSS_REVEAL", 3.0)
const HINTS := ["PRESS", "KEY", "SPACE", "ENTER", "ESC", "CLICK", "[1]", "[2]", " 1 ", " 2 ", "(1", "(2"]

var game

func _initialize() -> void:
	_run.call_deferred()

func _new_game(seed: int) -> void:
	if game != null:
		game.queue_free()
		await process_frame
	game = Main.instantiate()
	game.toss_seed = seed
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.auto_replay = false
	game.set_physics_process(false)   # the sim stays at the start of the toss; seek() drives the scene
	await _settle()

func _ct():
	return game.get("coin_toss")

## Pin the cutscene at `at` and let the clips blend in and the HUD text refresh.
func _at(at: float) -> void:
	var ct = _ct()
	if ct != null:
		ct.seek(at)
	await _settle()
	if ct != null and is_instance_valid(ct):
		ct.seek(at)   # re-pose after the frames (the camera reads the same t)
	await process_frame

func _settle() -> void:
	for i in 24:
		await process_frame

func _no_hints(text: String) -> bool:
	var padded := " %s " % text.to_upper()
	for h in HINTS:
		if padded.contains(h):
			return false
	return true

func _run() -> void:
	# --- You won the toss (seed 0 = HELIOS; the local player is on HELIOS).
	await _new_game(0)
	var mine: int = game.world.get_athlete(game.my_id).team
	check(mine == 0 and game.series.toss_winner == 0 and game.series.state == game.Match.State.TOSS, "you won the toss and it is pending")
	var ct = _ct()
	var has_cut: bool = game.get("coin_toss") != null
	check(has_cut, "the toss cutscene plays before the opening kickoff")
	if has_cut:
		check(not game.athlete_root.visible and not game.pres.overlay.visible, "the match and its HUD are hidden behind the cutscene")
	await _at(1.75)
	if has_cut:
		check(ct.lower_third.visible and ct.captains.size() == 2, "captains at midfield, lower third up")
		var d: float = ct.captains[0].position.distance_to(ct.captains[1].position)
		check(d > 2.5 and d < 3.6, "captains face off across the coin spot (%.2f)" % d)
	await capture("coin-toss-captains")
	await _at(2.45)
	if has_cut:
		check(ct.coin.position.y > 2.8, "coin in the air (%.2f)" % ct.coin.position.y)
		check(not ct.title.visible, "no result before the coin lands")
	await capture("coin-toss-coin-in-air")
	await _at(ct.CARDS_AT + 1.2 if has_cut else 4.8)
	if has_cut:
		check(ct.title.text == "YOU WON THE TOSS", "title: %s" % ct.title.text)
		check(ct.card_row.visible and ct.cards[0].is_visible_in_tree() and ct.cards[1].is_visible_in_tree(), "RECEIVE and KICK cards shown")
		check(ct.timer_back.visible, "the choice window drains under the cards")
		check(_no_hints(ct.all_text()), "no key hints in the toss UI (%s)" % ct.all_text())
		check(game.pres.excite > 0.5, "the crowd roars on the reveal (%.2f)" % game.pres.excite)
	await capture("coin-toss-you-won")
	if has_cut:
		# Click KICK with the real mouse path (GUI -> card -> toss action).
		var at: Vector2 = ct.card_rect(1).get_center()
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.position = at
			ev.global_position = at
			root.push_input(ev)
		check(game.series.state == game.Match.State.KICKOFF and game.world.offense_team == mine, "clicking KICK makes you kick off")
		await _at(ct.CARDS_AT + 1.4)
		check(ct.receiver == 1 and ct.sub.text == "HELIOS WILL KICK", "the pick holds on screen (%s)" % ct.sub.text)
		check(play_clock_ok(), "play clock untouched while the cutscene plays (%.3f)" % game.series.clock.play_clock)
	await capture("coin-toss-decided")
	if has_cut:
		await _at(ct.CARDS_AT + 1.4 + ct.HOLD + ct.DIP + ct.UNDIP + 0.05)
		check(_ct() == null and game.athlete_root.visible and game.pres.overlay.visible, "cutscene gone, the match and HUD are back")

	# --- Bots won: you watch them choose.
	await _new_game(1)
	ct = _ct()
	await _at(REVEAL + 1.0)
	if ct != null:
		check(ct.title.text == "NEBULA WINS THE TOSS", "title: %s" % ct.title.text)
		check(ct.waiting_box.visible and ct.waiting.text == "NEBULA IS CHOOSING…" and not ct.card_row.visible, "the other side waits, no cards")
		check(_no_hints(ct.all_text()), "no key hints (%s)" % ct.all_text())
	await capture("coin-toss-they-choose")

	# --- Online client: the host's snapshots drive it; the host's pick shows up.
	if game != null:
		game.queue_free()
		await process_frame
	game = Main.instantiate()
	game.toss_seed = 0
	root.add_child(game)
	current_scene = game
	game.auto_next = false
	game.auto_replay = false
	game.set_physics_process(false)
	game._ensure_net()
	game.net.host_size = game.match_size
	game.net.mode = NetSession.Mode.CLIENT
	game.net.my_athlete = game.my_id
	game.net.snapshot_received.connect(game._on_snapshot)
	var hw := World.new()
	Roster.new().build(hw, game.match_size)
	var host := Match.new(hw)
	host.start_match(1, true)   # NEBULA (a human on the other side) wins
	game.net._on_packet(1, var_to_bytes(Protocol.encode_snapshot(host, 10)))
	await _settle()
	ct = _ct()
	check(game.is_client() and game.series.toss_winner == 1, "client mirrors the host's toss")
	check(ct != null, "the client plays the toss cutscene too")
	if ct != null:
		await _at(REVEAL + 1.0)
		check(ct.title.text == "NEBULA WINS THE TOSS" and ct.waiting.text == "NEBULA IS CHOOSING…", "client: %s / %s" % [ct.title.text, ct.waiting.text])
		host.choose_toss(1, "kick")
		game.net._on_packet(1, var_to_bytes(Protocol.encode_snapshot(host, 11)))
		await _at(REVEAL + 1.2)
		check(ct.receiver == 0 and ct.sub.text == "NEBULA WILL KICK", "client shows the host's pick (%s)" % ct.sub.text)
	await capture("coin-toss-online-client")
	finish()

func play_clock_ok() -> bool:
	return absf(game.series.clock.play_clock - game.series.clock.PLAY_CLOCK) < 0.001
