extends SceneTree
## Scripted end-to-end flow through the real main scene (presentation glue).
## Each step: [physics frame @60Hz, callable]. Exits 1 on failed check.

const Emotes := preload("res://src/sim/emotes.gd")
const RIVAL_INSTALL := "feedfacecafebeef"   # #102: the ranked rival's install id
var main
var frame := 0
var ok := true
var steps: Array = []
var caught_by := -1
var tackled := false
var spot := 0.0
var series_events := 0
var before_id := -1
var slant_wr = null
var slant_x := 0.0
var picked := false
var xp0 := 0
var frozen_y := 0.0
var offline_replay_frames := 0
var auto_replay_default := false
var wr_id := -1
var kick_events: Array = []
var fc_ret = null   # #189 fair-catch step's returner
var fp_lb = null          # C06a forward progress: the defender driving the carrier back
var fp_contact_y := INF
var fp_driven_y := 0.0
const ZOOM_SETTINGS := "user://test_flow_settings.cfg"   # #140 zoom step
var zoom_path0 := ""
var catch_pose := []   # #246: [catch_weight, catch_reach, hand-to-ball, chest-to-ball] at the A04 catch
var toss_close_clock := -1.0   # #129: kickoff play clock when the toss cutscene closed
var bot_snap_clock := INF   # #136: play clock when the bot offense snapped (frames 4171-4481)
var kick_meter_far := [0, 0]   # #68: [lit steps, shader pushes] with the kickoff aimed deep (frame 9504)

func check(cond: bool, msg: String) -> void:
	print(("  FLOW OK   " if cond else "  FLOW FAIL ") + msg)
	if not cond:
		ok = false

func _check_team_uniforms(context: String) -> void:
	var team: int = main.world.get_athlete(main.my_id).team
	check(main.views.all(func(view):
		var opponent: bool = view.athlete.team != team
		return (view.is_opponent == opponent and view._opponent_mesh.visible == opponent
			and view.mesh_i.visible != opponent and view._open_helmet.visible != opponent
			and view.anim.has_animation("u2/OverhandThrow"))
	), "both uniforms share the live animation rig " + context)

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.auto_next = false
	auto_replay_default = main.auto_replay
	main.auto_replay = false   # scripted timings assume the offline sim never pauses; B04a steps turn it on
	# scripted steps drive play changes; auto-advance checked at the end
	var held := {}   # #142 step: the offense's pre-snap spot
	steps = [
		[2, func(): _connect_listeners(); _isolate_user_files(); main.pov_enabled = false],   # legacy target-aim steps; POV steps re-enable it  # world/series are (re)built in main._ready -> connect after
		# Random toss at boot: a human winner gets the choice; a bot winner takes the ball at once.
		[3, func(): var s = main.series; check(s.toss_winner >= 0 and main.world.kick_play == "kickoff", "match opens with a coin toss + kickoff"); check((s.state == main.Match.State.TOSS and main.world.kick_locked and main.hud.text.find("COIN TOSS") >= 0) or (s.state == main.Match.State.KICKOFF and s.toss_choice == "receive" and main.hud.text.find("KICKOFF") >= 0), "toss pending for a human winner, else decided (%s)" % s.toss_choice)],
		[4, func(): main.opening_kickoff = false; main.series.start(0); main.set_controlled(main.my_id)],  # legacy steps start on a scrimmage snap
		[5, func(): check(main.world.phase == main.World.Phase.PRESNAP, "starts presnap"); _check_team_uniforms("opening lineup")],
		[6, func(): check(main.world.snap(), "snap")],
		[39, func(): _check_carry_pose(true, "QB holding before the throw")],   # #244 (frame 39 only)
		[40, func(): check(main.world.ball.is_held_by(main.controlled_id), "QB has ball")],
		[41, func(): main.aim_point = Vector2(40, 45)],
		[80, func(): check(main.arc_shown(), "pass preview shown before input")],
		[81, func(): _key(KEY_J)],
		[82, func(): check(main.world.forward_pass_thrown, "pass thrown")],
		[90, func(): _check_ball_flight(true)],   # #159 (frames 90 and 92 only)
		[92, func(): _check_ball_flight(false)],
		[396, func(): _drop_dead_ball()],   # #159 (frames 396 and 400 only)
		[400, func(): check(main.world.phase == main.World.Phase.DEAD, "incomplete ends play"); _check_ball_lying()],
		# A04: reset, snap, lead a pass to a WR running his go route -> catch while keeping the assigned athlete
		[401, func(): main.next_play(); check(main.series.downs.down == 2, "incomplete -> 2nd down"); check(main.controlled_id == main.my_id, "control back to my athlete")],
		[402, func(): main.ai.defense_enabled = false; main.world.snap()],
		[480, func(): _lead_to_wr(); _key(KEY_J)],
		[531, func(): check(main.world.forward_pass_thrown, "lead pass thrown")],
		[800, func():
			main.ai.defense_enabled = true
			check(caught_by >= 0, "WR caught it")
			check(catch_pose.size() == 4 and catch_pose[0] > 0.8 and catch_pose[1] > 0.8 and catch_pose[2] < catch_pose[3] - 0.3,
				"receiver reaches for the ball as it arrives (#246): weight/reach/hand-to-ball/chest-to-ball %s" % str(catch_pose))
			check(main.controlled_id == main.my_id and main.controlled_id != caught_by, "assigned athlete retained after catch")],
		# A05: idle receiver gets run down by AI pursuit and tackled
		[1300, func():
			check(tackled, "AI defender tackled the carrier")
			check(main.world.phase == main.World.Phase.DEAD, "whistle: play dead")
			check(main.last_whistle == "TACKLE", "HUD whistle reason")
			var holder_id: int = main.world.ball.holder_id
			check(holder_id >= 0 and main.ball_view.global_position.distance_to(main.views[holder_id].hand_position()) < 0.2,
				"tackled player still carries the ball in hand")],
		# A07: next play at the tackle spot with correct down
		[1301, func(): spot = main.world.dead_ball_spot.y; main.next_play()],
		[1302, func(): check(absf(main.world.los_y - clampf(spot, 1, 99)) < 0.01, "LOS moved to tackle spot"); check(main.series.downs.down == 1 if spot >= 35.0 else main.series.downs.down == 3, "down advanced correctly (spot %.1f, %s)" % [spot, main.series.downs.label()]); check(main.hud.text.find(" & ") >= 0, "HUD shows down & distance")],
		[1303, func(): main.world.snap(); main.auto_next = true; series_events = 0],
		[2400, func(): check(series_events >= 1, "auto next play fired after whistle (%d)" % series_events)],
		# A08: forced touchdown -> score -> try -> kickoff
		[2401, func(): main.auto_next = false; main.series.start(0, 95.0); main.set_controlled(main.my_id)],
		[2402, func(): main.world.snap()],
		[2430, func(): var c = main.world.carrier(); c.position = Vector2(26, 101.0)],
		[2432, func(): check(main.last_whistle == "TOUCHDOWN", "touchdown whistle")],
		[2433, func(): main.next_play(); check(main.series.score[0] == 6, "home +6"); check(main.series.state == main.Match.State.TRY, "try state")],
		[2434, func(): check(main.hud.text.find("HOME 6") >= 0 and main.hud.text.find("TRY") >= 0, "HUD scoreboard + try")],
		[2435, func(): check(main.series.choose_try(2), "choose 2-pt try"); check(absf(main.world.los_y - 90.0) < 0.01, "2-pt from the 10")],
		[2436, func(): main.world.snap()],
		[2470, func(): var c = main.world.carrier(); c.position = Vector2(26, 101.0)],
		[2472, func(): main.next_play(); check(main.series.score[0] == 8, "try good: 8"); check(main.series.state == main.Match.State.KICKOFF and main.world.offense_team == 0 and absf(main.world.los_y - 35.0) < 0.01, "kickoff: home kicks from its 35")],
		# A09: play clock auto-snap, untimed down, halftime
		[2474, func(): _check_look_snaps("kickoff reset after the try")],   # #245 (frame 2474 only)
		[2473, func(): check(main.hud.text.find("Q1 ") >= 0 and main.hud.text.find("H1 ") < 0 and main.hud.text.find("PLAY ") >= 0, "HUD game + play clock"); main.series.clock.play_clock = 0.3],
		[2500, func(): check(main.world.phase == main.World.Phase.LIVE, "play clock auto-snapped"); main.series.clock.quarter = 2; main.series.clock.remaining = 0.2],
		[2530, func(): check(main.series.clock.expired(), "clock hit 0:00")],
		[3200, func(): _force_dead_if_live(); main.next_play(); check(main.series.clock.half == 2, "halftime -> 2nd half"); check(main.series.last_outcome.get("receiving", -1) == 1 - main.series.opening_receiver, "other team receives 2nd half")],
		# Match assignment stays fixed between plays as well as during them.
		[3201, func(): before_id = main.my_id; check(not main.do_action({"a": "cycle"}), "position change rejected between plays")],
		[3202, func(): check(not main.do_action({"a": "team"}), "team swap rejected between plays"); check(main.controlled_id == before_id, "assignment unchanged")],
		[3203, func(): _check_team_uniforms("fixed assignment")],
		[3204, func(): main.world.snap()],
		[3205, func(): check(not main.do_action({"a": "team"}), "no team swap during live play")],
		# A12: play call -> route art -> receivers run it
		[3206, func(): _force_dead_if_live(); main.series.start(0, 30.0)],
		[3207, func(): check(main.do_action({"a": "play", "p": "Slants"}), "call Slants"); check(main.world.play_name == "Slants", "play set")],
		[3209, func(): check(main.route_mesh.get_surface_count() > 0, "route lines drawn presnap"); check(main.hud.text.find("PLAY: Slants") >= 0, "HUD shows play")],
		[3210, func(): main.ai.defense_enabled = false; slant_wr = _ai_receiver(); slant_x = slant_wr.position.x; main.world.snap()],  # route glue only (CB inside leverage takes slants away)
		[3300, func(): check(absf(slant_wr.position.x - slant_x) > 2.0 and absf(slant_wr.position.x - main.field.width / 2.0) < absf(slant_x - main.field.width / 2.0), "AI WR broke inside on slant (dx %.1f)" % (slant_wr.position.x - slant_x)); check(main.route_mesh.get_surface_count() == 0, "route lines hidden after snap"); main.ai.defense_enabled = true],
		# A13: forced interception -> live return -> whistle -> possession flips
		[3301, func(): _force_dead_if_live(); main.series.start(0, 30.0); main.world.snap()],
		[3330, func(): main.ai.defense_enabled = false; _setup_pick()],  # CB holds the spot (bots would play man)
		[3331, func(): main.world.throw(main.world.find_role(0, main.Athlete.Role.QB).id, Vector2(50, 60), 0.9)],
		[3470, func(): check(picked, "interception happened"); check(main.hud.text.find("INTERCEPTION") >= 0, "HUD interception banner"); main.ai.defense_enabled = true],
		[4170, func(): _force_dead_if_live(); main.next_play(); check(main.world.offense_team == 1, "possession flipped after the pick (%s)" % main.series.last_outcome.get("outcome", "?"))],
		# A14: you're on defense vs a bot offense -> bots call a play and snap on their own
		[4171, func(): check(main.world.get_athlete(main.my_id).team != main.world.offense_team, "human on defense"); check(main.world.phase == main.World.Phase.PRESNAP, "presnap")],
		[4172, func():
			var old: String = main.world.defensive_call
			var overlay = main.pres.overlay
			check(overlay.picker.visible, "defensive picker opens automatically")
			var ids: Array = main.World.DefensivePlaybook.CALLS.keys()
			var index := (ids.find(old) + 1) % ids.size()
			overlay.picker_grid.get_child(index).pressed.emit()
			check(main.world.defensive_call != old, "clicking a defensive play calls it")
			_key(KEY_Q)
			check(not main.play_picker_open, "Q toggles the picker")
			_key(KEY_Q)
			check(main.play_picker_open, "Q reopens the picker")],
		# On defense the follow camera turns around to face the offense/ball, and WASD turns with it.
		[4240, func():
			var me_z: float = main.player.global_position.z
			check(absf(angle_difference(main.cam_yaw, PI)) < 0.05, "defense camera swung around (yaw %.2f)" % main.cam_yaw)
			check(main.camera.global_position.z < me_z - 3.0, "defense camera sits on the far side, looking at the offense")
			check(-main.camera.global_transform.basis.z.z > 0.5, "defense camera looks back up the field toward the ball")
			check(main.screen_to_field(Vector2(0, 1)).y < -0.9, "W moves a defender toward the ball (up the screen)")
			check(main.screen_to_field(Vector2(1, 0)).x < -0.9, "D moves a defender screen-right")],
		# #136: the scorebug counts down the bots' huddle and they snap when it reads 0, not at :15.
		[4300, func():
			var shown: int = main.series.play_clock_shown()
			check(shown >= 0 and shown <= int(main.T.HUDDLE_SECONDS) and main.pres.overlay.play_clock_l.text == "PLAY :%02d" % shown,
				"bot huddle on the scorebug (%s)" % main.pres.overlay.play_clock_l.text)],
		[4171 + int(60 * 5.0) + 10, func():
			check(main.world.phase != main.World.Phase.PRESNAP, "bot offense snapped by itself")
			check(bot_snap_clock <= 0.0, "bot snap waited for the shown play clock (%.2f s left)" % bot_snap_clock)],
		# A15: rebuild as 3v3 in place
		[4500, func(): main.configure(3)],
		[4502, func(): check(main.world.athletes.size() == 6 and main.athlete_root.get_child_count() == 6, "3v3: 6 athletes + views"); check(absf(main.field.width - 30.0) < 0.01, "3v3 field width 30"); check(main.hud.text.find("3v3") >= 0, "HUD shows 3v3")],
		[4503, func(): var qb = main.world.find_role(0, main.Athlete.Role.QB); check(main.world.ball.is_held_by(qb.id), "3v3: QB starts with the ball"); check(main.world.snap(), "3v3 snap")],
		# Real keyboard path (regression: handler had silently never been updated since iter 002)
		[4600, func(): main.configure(7)],
		[4602, func():
			var overlay = main.pres.overlay
			var old: String = main.world.play_name
			overlay.picker_grid.get_child(1).pressed.emit()
			check(main.world.play_name != old, "clicked an offensive play")],
		[4603, func(): before_id = main.my_id; _key(KEY_TAB)],
		[4604, func(): check(main.pres.overlay.scoreboard.visible and main.my_id == before_id, "Tab shows scoreboard with fixed assignment"); _key(KEY_TAB, false)],
		[4605, func(): check(not main.pres.overlay.scoreboard.visible, "scoreboard closes on release"); _key(KEY_SPACE)],
		[4606, func(): check(main.world.phase == main.World.Phase.LIVE, "Space key snaps"); _key(KEY_R)],
		[4607, func(): check(main.player.athlete.move_charge == 1.0, "R consumes one dash charge")],
		[4625, func(): _key(KEY_E)],
		[4626, func(): check(main.player.athlete.is_spinning() and main.player.athlete.move_charge < 1.0, "E (spin right) consumes one spin charge")],
		# #183 (window 4640-4649): a set defender sees "SPACE ×2 TO ROAM" (the bound key) in the
		# pill and the text HUD until the first double-tap roam; later plays read plain SET.
		[4640, func(): check(not main.roamed_once, "no roam yet this session"); main.series.start(1, 25.0); main.set_controlled(main.my_id)],
		[4644, func():
			var me = main.world.get_athlete(main.my_id)
			var hint := "PRE-SNAP: SET  ·  SPACE ×2 TO ROAM"
			check(me.set_lock and me.role != main.Athlete.Role.DL, "set non-DL defender (%s)" % me.role)
			check(main.pres.overlay.status_l.text == hint and main.pres.overlay.status_pill.visible, "pill shows the roam hint (%s)" % main.pres.overlay.status_l.text)
			check(main.hud.text.find(hint) >= 0, "text HUD prompt carries the hint")
			var launch = root.get_node_or_null("Launch")
			var saved: Dictionary = launch.settings.bindings
			launch.settings.bindings = {"snap": KEY_B}
			check(main.roam_hint_key() == "B", "hint names the rebound snap key (%s)" % main.roam_hint_key())
			launch.settings.bindings = saved
			_key(KEY_SPACE)
			check(main.roam_hint_key() == "SPACE", "one press: still set, hint stays")
			_key(KEY_SPACE)
			check(not me.set_lock and main.roamed_once and main.roam_hint_key() == "", "double-tap roams and retires the hint")],
		[4645, func(): main.series.start(1, 25.0)],
		[4649, func():
			check(main.world.get_athlete(main.my_id).set_lock, "later play: set again")
			check(main.pres.overlay.status_l.text == "" and not main.pres.overlay.status_pill.visible, "later play: no hint in the pill (%s)" % main.pres.overlay.status_l.text)
			check(main.hud.text.find("PRE-SNAP: SET") >= 0 and main.hud.text.find("TO ROAM") < 0, "later play: plain PRE-SNAP: SET")],
		# Defense Space double-tap unlocks a stance without snapping; one press does nothing (#142).
		[4650, func(): main.series.start(1, 25.0)],
		[4651, func():
			var me = main.world.get_athlete(main.my_id)
			check(me.set_lock and main.pres.barrier.visible, "defender starts in stance")
			_key(KEY_SPACE)
			check(main.world.phase == main.World.Phase.PRESNAP and me.set_lock, "one Space press keeps the defender set")
			_key(KEY_SPACE)
			check(main.world.phase == main.World.Phase.PRESNAP and not me.set_lock, "Space double-tap breaks stance without snapping")],
		# #142: the whole offense is frozen until the snap, the human included.
		[4660, func(): main.series.start(0, 25.0); main.input_override = Vector2(1, 0); main.sprint_override = true],
		[4662, func():
			for a in main.world.athletes:
				if a.team == main.world.offense_team:
					held[a.id] = a.position],
		[4690, func():
			var moved := 0.0
			for id in held:
				moved = maxf(moved, main.world.get_athlete(id).position.distance_to(held[id]))
			check(main.world.phase == main.World.Phase.PRESNAP and held.has(main.controlled_id) and moved < 0.01, "no offensive athlete moves pre-snap, human input included (%.3f yd)" % moved)
			main.input_override = null
			main.sprint_override = null],
		# A17: practice drills through the real game
		[4700, func(): main.start_practice("passing"); check(main.drill != null and main.world.athletes.size() == 4, "passing drill: 4 athletes")],
		[4702, func(): check(main.hud.text.find("PRACTICE: Passing") >= 0, "HUD shows drill"); _key(KEY_SPACE)],
		[4703, func(): main.world.call_play("Verticals")],
		[4790, func(): _lead_to_wr(); _key(KEY_J)],
		[5100, func(): check(main.drill.successes == 1 and main.drill.reps == 1, "drill counted the completion (%d/%d)" % [main.drill.successes, main.drill.reps])],
		[5200, func(): check(main.world.phase == main.World.Phase.PRESNAP and main.controlled_id == main.my_id, "rep reset to presnap, control back to QB")],
		[5300, func(): main.start_practice("tackling"); check(main.world.phase == main.World.Phase.LIVE, "tackling drill starts live")],
		[5301, func(): _chase_and_tackle()],
		[5800, func(): check(not _chasing, "tackling rep finished")],
		# A19: Chaosball through the real game
		[5900, func(): main.configure(7, "", "chaosball")],
		[5902, func(): check(main.world.is_chaos() and main.match_size == 3, "chaosball forces 3v3 + ruleset"); check(main.hud.text.find("CHAOSBALL") >= 0, "HUD shows CHAOSBALL"); _key(KEY_SPACE)],
		[5903, func(): main.ai.defense_enabled = false; var qb = main.world.get_athlete(main.my_id); qb.position.y = main.world.los_y + 6.0; main.aim_point = qb.position + Vector2(0, 8); main.lob_override = true],
		[5910, func(): _key(KEY_J); main.lob_override = null; check(main.world.forward_pass_thrown, "real throw past the LOS accepted (lob)"); main.ai.defense_enabled = true],
		# A20: streak HUD + pass clock explosion through the real game
		[6000, func(): main.configure(3, "", "chaosball"); main.ai.defense_enabled = false; main.ai.offense_enabled = false],
		[6002, func(): check(main.hud.text.find("STREAK 0 -> TD 2") >= 0, "HUD shows streak + TD value"); _key(KEY_SPACE)],
		[6002 + int(60 * 5.3), func(): check(main.last_whistle == "EXPLODE", "held too long: ball exploded (%s)" % main.last_whistle); main.ai.defense_enabled = true; main.ai.offense_enabled = true],
		# A21: stats from a real completion -> final whistle -> HUD summary
		[6400, func(): main.configure(7); main.ai.defense_enabled = false; main.world.call_play("Verticals")],
		[6401, func(): _key(KEY_SPACE)],
		[6480, func(): _lead_to_wr(); _key(KEY_J)],
		[6690, func():
			var carrier = main.world.carrier()
			if carrier != null and main.world.phase == main.World.Phase.LIVE:
				carrier.position.x = -1.0],
		[6799, func(): main.leaderboard_path = "user://test_flow_leaderboard.json"; DirAccess.remove_absolute(ProjectSettings.globalize_path(main.leaderboard_path))],
		[6800, func(): check(main.stats.total("att") >= 1 and main.stats.total("comp") >= 1, "stats tracked the completion (%d/%d)" % [main.stats.total("comp"), main.stats.total("att")]); _force_dead_if_live(); main.series.clock.quarter = 4; main.series.clock.remaining = 0.0; main.next_play(); main.ai.defense_enabled = true],
		[6802, func(): check(main.series.is_final(), "final"); check(main.hud.text.find("You QB: 1/1") >= 0, "HUD summary shows your QB line"); check(not main.replay_active, "final whistle ends an auto highlight replay")],
		# A22: match recorded to the leaderboard file; HUD shows your rank
		[6803, func(): var lb = main.Leaderboard.new(); lb.load_file(main.leaderboard_path); check(lb.rank_of("You", "QB") == 1, "leaderboard file has You|QB at #1"); check(main.hud.text.find("YOUR RANKS: QB #1") >= 0, "HUD shows your rank"); DirAccess.remove_absolute(ProjectSettings.globalize_path(main.leaderboard_path))],
		# Post-game: players of the game picked at final -> presentation beats -> overview data
		[6804, func(): check(main.potg.size() >= 2 and main.potg.size() <= 4, "2-4 players of the game (%d)" % main.potg.size()); check(main.potg[0]["title"] == "PLAYER OF THE GAME" and main.potg.any(func(e): return e["name"] == "You"), "your QB line made the cut"); check(main.postgame_t >= 0.0 and main.postgame == null, "presentation queued after the FINAL hold"); main.start_postgame()],
		[6806, func(): var st = main.postgame; check(st != null and st.views.size() == main.potg.size() and st.step == -1, "presentation intro with one athlete per pick"); st.advance(); check(st.step == 0 and st.cards[0].visible, "first spotlight card")],
		[6810, func(): var st = main.postgame; st.skip(); check(st.is_done() and main.postgame_done and main.postgame == null, "skip ends the presentation"); var ov = main.match_overview(); check(ov["potg"].size() == main.potg.size() and ov["teams"].size() == 2 and ov["my_lines"].size() >= 1, "overview carries picks, team stats, your line %s" % str(ov["my_lines"]))],
		# A23: ranked match vs a human rival -> rating change saved + on HUD.
		# #102: the rival shares our display name ("You"); records are keyed by install id, so each keeps its own.
		[6900, func(): main.configure(7); _setup_ranked_rival()],
		[6901, _check_same_name_awards],
		[6902, func(): main.series.score = [7, 0]; main.series.clock.quarter = 4; main.series.clock.remaining = 0.0; main.world.phase = main.World.Phase.DEAD; main.series.last_result = {"type": "incomplete"}; main.next_play()],
		[6904, func(): var rk = main.Ranked.new(); rk.load_file(main.ranked_path); var mine: String = main.Ranked.id_key(main.profile.install_id); var theirs: String = main.Ranked.id_key(RIVAL_INSTALL); check(rk.players.size() == 2 and not rk.players.has("You"), "same-named players get two id-keyed records (%s)" % str(rk.players.keys())); check(rk.rating(mine) > 1000.0 and rk.rating(theirs) < 1000.0, "ratings saved (host %.0f, rival %.0f)" % [rk.rating(mine), rk.rating(theirs)]); check(int(rk.players[mine]["games"]) == 1 and int(rk.players[mine]["wins"]) == 1 and int(rk.players[theirs]["wins"]) == 0, "one game each, one win"); check(rk.players[theirs].get("name") == "You", "display name kept on the record"); check(main.hud.text.find("RATING ") >= 0 and main.hud.text.find("(+24)") >= 0, "HUD shows rating change"); var saved = main.Cosmetics.new(); saved.load_file(main.profile_path); check(saved.install_id != "" and saved.install_id == main.profile.install_id, "host install id minted + saved with the profile"); main.peer_installs.erase(99); DirAccess.remove_absolute(ProjectSettings.globalize_path(main.ranked_path)); DirAccess.remove_absolute(ProjectSettings.globalize_path(main.leaderboard_path))],
		# A24: earned cosmetics on your athlete, TD celebration, XP at final
		[7000, func(): main.profile.xp = 600; check(main.profile.equip("trim", "ember") and main.profile.equip("celebration", "spin") and main.profile.equip("number", 88), "equip earned items (level 1)"); check(not main.profile.equip("trim", "aurora"), "locked item refused"); main.configure(7)],
		[7002, func(): var v = main.views[main.my_id]; check(v.number_text == "88" and v.trim_color.is_equal_approx(main.Cosmetics.color_of("trim", "ember")), "your look shown on your athlete"); check(main.views[(main.my_id + 1) % main.views.size()].number_text != "88", "others keep their own looks")],
		[7003, func(): _key(KEY_SPACE)],
		[7030, func(): main.world.carrier().position = Vector2(26, 101.0)],
		[7032, func(): check(main.views[main.my_id].is_celebrating(), "TD celebration plays")],
		[7033, func(): xp0 = main.profile.xp; main.next_play(); main.series.clock.quarter = 4; main.series.clock.remaining = 0.0; main.world.phase = main.World.Phase.DEAD; main.series.last_result = {"type": "incomplete"}; main.next_play()],
		[7035, func(): check(main.profile.xp > xp0 and main.hud.text.find("XP +") >= 0, "XP awarded at final (%d -> %d)" % [xp0, main.profile.xp]); var saved = main.Cosmetics.new(); saved.load_file(main.profile_path); check(saved.xp == main.profile.xp, "XP saved to (temp) profile"); DirAccess.remove_absolute(ProjectSettings.globalize_path(main.profile_path))],
		# A25: instant replay with the real V key, saved replay, viewer
		[7100, func(): main.replay_dir = "user://test_flow_replays"; main.configure(7); main.ai.defense_enabled = false],
		[7101, func(): _key(KEY_SPACE)],
		[7200, func(): main.world.carrier().position = Vector2(26, 101.0)],
		[7203, func():
			check(main.world.phase == main.World.Phase.DEAD, "play over")
			frozen_y = main.world.athletes[0].position.y
			offline_replay_frames = main.replay.frames.size()
			_key(KEY_V)
			check(main.replay_active, "V starts instant replay")],
		[7210, func(): var p = main.replay.last_play(); var smp = main.replay.sample(); var rp = Vector3(smp["pos"][3].x, 0, -smp["pos"][3].y); check(main.views[3].target_position().distance_to(rp) < 0.01, "views show replay frames"); check(main.views[3].position.distance_to(rp) < 0.5, "drawn view within one interpolation step of the replay frame"); check(main.hud.text.find("REPLAY 0.5x") >= 0, "HUD shows replay"); check(absf(main.world.athletes[0].position.y - frozen_y) < 0.001 and main.world.phase == main.World.Phase.DEAD, "offline sim frozen during replay")],
		[7211, func(): check(main.replay.frames.size() == offline_replay_frames, "offline instant replay pauses recording")],
		[7500, func(): check(not main.replay_active, "replay ends -> back to live"); main.ai.defense_enabled = true],
		[7501, func(): main.series.clock.quarter = 4; main.series.clock.remaining = 0.0; main.series.last_result = {"type": "incomplete"}; main.next_play()],
		[7502, func(): check(main.saved_replay != "" and FileAccess.file_exists(main.saved_replay), "replay saved at final (%s)" % main.saved_replay)],
		[7503, func(): check(main.open_replay(main.saved_replay) and main.replay_viewer and main.replay.plays.size() >= 1, "viewer opens the saved replay"); _key(KEY_BRACKETRIGHT); check(main.replay.speed == 2.0, "] speeds up")],
		[7504, func(): _key(KEY_V); check(not main.replay_active, "V exits viewer"); for f in DirAccess.get_files_at(ProjectSettings.globalize_path("user://test_flow_replays")): DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_flow_replays/" + f))],
		# D04: achievements unlocked by a real TD + win, saved to the (temp) profile
		[7600, func(): main.profile.achievements = []; main.profile.games = 0; main.configure(7); main.ai.defense_enabled = false],
		[7601, func(): _key(KEY_SPACE)],
		[7630, func(): main.world.carrier().position = Vector2(26, 101.0)],
		[7632, func(): main.next_play(); main.world.snap(); main.series.last_result = {"type": "touchdown", "team": 0}; main.world.phase = main.World.Phase.DEAD; main.series.clock.quarter = 4; main.series.clock.remaining = 0.0; main.next_play()],
		[7634, func(): check(main.series.is_final(), "final"); check(main.profile.achievements.has("first_td") and main.profile.achievements.has("first_win"), "First Touchdown + First Win unlocked (%s)" % str(main.profile.achievements)); check(main.hud.text.find("ACHIEVEMENTS: ") >= 0, "HUD lists achievements"); var saved = main.Cosmetics.new(); saved.load_file(main.profile_path); check(saved.achievements.has("first_win"), "achievements saved"); main.ai.defense_enabled = true; DirAccess.remove_absolute(ProjectSettings.globalize_path(main.profile_path))],
		# C01: call a run, hand off, and keep the assigned quarterback.
		[7710, func():
			main.configure(7)
			main.ai.defense_enabled = false],
		[7712, func():
			var picker = main.pres.overlay.picker_grid
			var plays = main.world.available_plays()
			picker.get_child(plays.find("Outside Sweep")).pressed.emit()
			picker.get_child(plays.size() + 1).pressed.emit()
			check(main.world.play_name == "Outside Sweep" and main.world.run_flipped, "picker selects and flips the sweep")],
		[7714, func():
			check(main.route_mesh.get_surface_count() > 0, "turf shows the selected run")
			_key(KEY_SPACE)],
		[7764, func():
			check(main.world.handoff_receiver(main.my_id) != null, "handoff available in reach")
			_key(KEY_G)
			var back = main.world.find_role(0, main.Athlete.Role.RB)
			check(main.world.carrier() == back and main.controlled_id == main.my_id, "handoff keeps control of the assigned QB")],
		[7900, func(): _check_carry_pose(false, "RB running after the handoff")],   # #244 (frame 7900 only)
		[7930, func():
			var back = main.world.carrier()
			check(back != null and back.position.y > main.world.los_y and main.world.phase == main.World.Phase.LIVE, "bot RB runs across the LOS and stays live")
			if back != null:
				check(main.roster.claim(98, main.roster.slot_of_athlete(back.id)), "replacement takes over the bot RB")
				back.position.x = -0.5],
		[7932, func():
			check(main.world.phase == main.World.Phase.DEAD and main.stats.total("car") == 1 and main.stats.total("rush_yds") > 0.0, "whistle records the RB's rushing attempt and gain")
			check(main.stats.get_line("Bot", "RB").get("car") == 1.0 and main.stats.player_summary(98).is_empty(),
				"handoff through G leaves the carry with the bot who received it")
			main.roster.release(98)],
		# C04a: T from dead ball, then the one-minute warning at the next whistle.
		[7950, func():
			main.configure(3)
			main.ai.defense_enabled = false
			main.series.clock.quarter = 2   # #130: the warning comes in Q2/Q4
			main.pres._period = 1           # jumped there: no SWITCH ENDS banner over the timeout one
			main.series.clock.remaining = 60.1
			_key(KEY_T)
			check(main.series.clock.timeouts == [1, 2], "T spends a timeout in 3v3")
			check(main.pres.overlay.banner.text == "TIMEOUT", "timeout banner appears")
			_key(KEY_SPACE)],
		[7970, func():
			check(main.world.phase == main.World.Phase.LIVE and main.series.clock.remaining < 60.0, "play stays live below 1:00")
			check(not main.pres.overlay.banner.visible, "timeout banner clears on the snap")
			check(main.pres.overlay.timeout_pips[0].is_visible_in_tree() and main.pres.overlay.timeout_pips[0].text == "●○", "live scorebug shows remaining timeouts")
			var overlay = main.pres.overlay
			check(overlay.field_strip.is_visible_in_tree() and overlay.play_clock_l.text == "",
				"the field strip remains live and the play clock clears on snap")
			_key(KEY_T)
			check(main.series.clock.timeouts == [1, 2], "T cannot call timeout during the play")
			main.world.carrier().position.x = -0.5],
		[7974, func():
			check(main.world.phase == main.World.Phase.DEAD and main.pres.overlay.banner.text == "ONE-MINUTE WARNING", "warning appears after the whistle")],
		# B04a: auto highlight replay, replay camera + transport keys, highlight reel at FINAL
		[8000, func(): check(auto_replay_default, "auto replay on by default"); main.auto_replay = true; main.configure(7); main.ai.defense_enabled = false],
		[8001, func(): _key(KEY_SPACE)],
		[8100, func(): main.world.carrier().position = Vector2(26, 101.0)],
		[8105, func(): check(main.world.phase == main.World.Phase.DEAD and not main.replay_active, "TD: no replay before the delay"); check(main.replay.last_play().get("highlight", false), "TD tagged as highlight (%s)" % main.replay.last_play().get("label", ""))],
		[8170, func(): check(main.replay_active and main.replay_auto, "TD replays itself after the whistle"); check(main.hud.text.find("HIGHLIGHT") >= 0 and main.hud.text.find("TOUCHDOWN") >= 0, "HUD: HIGHLIGHT + play label"); check(main.replay_overlay.root.visible and main.replay_overlay.badge_l.text == "HIGHLIGHT" and main.replay_overlay.summary_l.text.begins_with("TOUCHDOWN"), "replay overlay shows HIGHLIGHT + summary (%s)" % main.replay_overlay.summary_l.text); frozen_y = main.world.athletes[0].position.y; _key(KEY_C); check(main.hud.text.find("cam: End zone") >= 0 or main.replay_cam == 1, "C cycles replay camera")],
		[8200, func(): var pose = main.replay_camera_pose(); check(main.camera.global_position.distance_to(pose[0]) < 1.5, "camera follows the end-zone replay pose (%.1f m off)" % main.camera.global_position.distance_to(pose[0])); check(absf(main.world.athletes[0].position.y - frozen_y) < 0.001, "sim frozen during auto replay")],
		[8201, func(): var t0 = main.replay.time; _key(KEY_PERIOD); check(main.replay.paused and absf(main.replay.time - (floor(t0) + 1.0)) < 0.001, ". pauses and steps one frame")],
		[8210, func(): var t0 = main.replay.time; _key(KEY_COMMA); check(absf(main.replay.time - (t0 - 1.0)) < 0.001 and main.hud.text.find("(paused)") >= 0, ", steps back while paused"); _key(KEY_SPACE); check(not main.replay.paused, "Space resumes")],
		[8211, func(): _key(KEY_ENTER); check(not main.replay_active, "Enter skips the highlight")],
		[8250, func(): check(not main.replay_active and main.world.phase == main.World.Phase.DEAD, "a skipped highlight does not replay again"); var o = main.pres.overlay if main.pres else null; check(o == null or o.bug.is_visible_in_tree(), "live overlay widgets restored after replay")],
		[8251, func(): main.series.clock.quarter = 4; main.series.clock.remaining = 0.0; main.series.last_result = {"type": "incomplete"}; main.next_play()],
		[8252, func(): check(main.series.is_final(), "final"); _key(KEY_V); check(main.replay_active and main.replay_reel, "V at FINAL plays the highlight reel")],
		[8254, func(): check(main.hud.text.find("HIGHLIGHT REEL") >= 0, "HUD: HIGHLIGHT REEL"); check(main.postgame == null, "postgame show waits while the reel plays"); _key(KEY_V); check(not main.replay_active, "V exits the reel"); main.auto_replay = false; main.ai.defense_enabled = true; for f in DirAccess.get_files_at(ProjectSettings.globalize_path("user://test_flow_replays")): DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_flow_replays/" + f))],
		# #379 jump: Space in live play hops (JUMP_STAMINA); again within the chain window costs JUMP_CHAIN_STAMINA.
		[8260, func(): main.configure(7); main.ai.defense_enabled = false],
		[8261, func(): _key(KEY_SPACE); check(main.world.phase == main.World.Phase.LIVE, "Space snaps before the jump step")],
		[8270, func():
			var a = main.world.get_athlete(main.controlled_id)
			var s0: float = a.stamina
			check(a.can_act() and not a.is_jumping() and a.jump_chain_t == 0.0, "jump: controlled athlete can act on the ground")
			_key(KEY_SPACE)
			check(a.is_jumping(), "Space jumps in live play (#379)")
			check(absf(s0 - a.stamina - main.T.JUMP_STAMINA) < 0.001, "jump costs JUMP_STAMINA (%.3f -> %.3f)" % [s0, a.stamina])],
		[8310, func():
			var a = main.world.get_athlete(main.controlled_id)
			var s0: float = a.stamina
			check(not a.is_jumping() and a.jump_chain_t > 0.0, "jump: landed, inside the chain window (%.2f s left)" % a.jump_chain_t)
			_key(KEY_SPACE)
			check(a.is_jumping(), "Space jumps again right after landing")
			check(absf(s0 - a.stamina - main.T.JUMP_CHAIN_STAMINA) < 0.001, "chained jump costs JUMP_CHAIN_STAMINA (%.3f -> %.3f)" % [s0, a.stamina])],
		[8350, func(): check(not main.world.get_athlete(main.controlled_id).is_jumping(), "chained jump lands"); _force_dead_if_live(); main.ai.defense_enabled = true],
		# Training ground: hub portals, blocking station, Backspace home, practice-field targets
		[8600, func(): main.training_path = "user://test_flow_training.json"; DirAccess.remove_absolute(ProjectSettings.globalize_path(main.training_path)); main.start_practice("hub")],
		[8602, func(): check(main.drill.kind == "hub" and main.world.phase == main.World.Phase.LIVE, "training ground: free roam with the ball"); check(main.field_root.get_node_or_null("TrainingArt") != null and main.field_root.get_node("TrainingArt").get_children().filter(func(n): return n.name.begins_with("Portal_")).size() == 3, "three portals built"); check(main.pres.overlay.picker_title.text == "PICK A STATION", "overlay coaching card (%s)" % main.pres.overlay.picker_title.text); check(main.pres.overlay.mode_l.text == "TRAINING GROUND", "overlay title")],
		[8603, func(): var p: Vector2 = main.Drills.portal_positions(main.field)[0]; main.world.get_athlete(main.my_id).position = p - Vector2(0, main.Drills.PORTAL_R + 1.5); main.input_override = Vector2(0, 1)],
		[8700, func(): main.input_override = null; check(main.drill.kind == "blocking", "walked into the BLOCKING portal (%s)" % main.drill.kind); check(main.world.get_athlete(main.my_id).role == main.Athlete.Role.C, "you're the center")],
		[8701, func(): check(main.pres.overlay.status_l.text.begins_with("SNAP IN"), "auto-snap countdown shown (%s)" % main.pres.overlay.status_l.text)],
		[9000, func(): check(main.drill.reps >= 1, "blocking rep played out (%s)" % main.drill.last_result); _key(KEY_BACKSPACE); check(main.drill.kind == "hub", "real Backspace returns to the training ground")],
		[9001, func(): main.start_practice("field")],
		[9002, func(): var t: Vector2 = main.Drills.target_list(main.field)[0]["pos"]; main.world.get_athlete(main.my_id).position = t - Vector2(0, 10); main.aim_point = t],
		[9030, func(): _key(KEY_J); check(main.drill.throws == 1, "practice-field throw with the real throw path")],
		[9200, func(): check(main.drill.hits == 1 and main.drill.points >= 1, "hit the short target (%s)" % main.drill.last_result); check(main.world.ball.is_held_by(main.my_id), "ball back in your hands"); DirAccess.remove_absolute(ProjectSettings.globalize_path(main.training_path))],
		# #140 mouse-wheel camera zoom through the real mouse handler: pre-snap and live on the
		# follow camera, clamped both ways, saved to settings, middle click resets; ignored in
		# the passer's POV aim, with the taunt wheel open and in replays. Window 12300-12390.
		[12300, func():
			main.configure(7); main.ai.defense_enabled = false; main.pov_enabled = false
			var launch = root.get_node("/root/Launch")
			zoom_path0 = launch.settings_path
			launch.settings_path = ZOOM_SETTINGS
			DirAccess.remove_absolute(ProjectSettings.globalize_path(ZOOM_SETTINGS))
			main.set_camera_zoom(main.CameraZoom.DEFAULT); main.cam_zoom_shown = main.cam_zoom],
		[12302, func():
			var Z = main.CameraZoom
			check(main.world.phase == main.World.Phase.PRESNAP and not main.pov_active(), "zoom step: pre-snap on the follow camera")
			_wheel(true)
			check(is_equal_approx(main.cam_zoom, Z.DEFAULT - Z.STEP), "wheel up zooms in pre-snap (%.2f)" % main.cam_zoom)
			check(main.cam_zoom_shown == Z.DEFAULT, "the zoom eases (not applied until the camera updates)")
			var saved = load("res://src/ui/settings_store.gd").new(); saved.load_file(ZOOM_SETTINGS)
			check(is_equal_approx(saved.camera_zoom, main.cam_zoom), "the zoom level is saved to settings (%.2f)" % saved.camera_zoom)
			for i in 30: _wheel(true)
			check(main.cam_zoom == Z.MIN, "wheel up stops at the near limit %.1f" % Z.MIN)
			for i in 30: _wheel(false)
			check(main.cam_zoom == Z.MAX, "wheel down stops at the far limit %.1f" % Z.MAX)
			_middle_click()
			check(main.cam_zoom == Z.DEFAULT, "middle click resets the zoom")
			_wheel(false); _wheel(false)
			check(is_equal_approx(main.cam_zoom, 1.2), "two notches down = 1.2 (%.2f)" % main.cam_zoom)],
		[12340, func():
			var d: float = main.camera.global_position.distance_to(main.player.global_position)
			var want: float = main.FOLLOW_CAM_OFFSET.length() * 1.2
			check(absf(main.cam_zoom_shown - 1.2) < 0.001 and absf(d - want) < 0.6, "the follow camera eased out to 1.2x (%.1f m from the player, want %.1f)" % [d, want])
			_key(KEY_SPACE)],
		[12350, func():
			check(main.world.phase == main.World.Phase.LIVE, "zoom step: snapped")
			_wheel(true)
			check(is_equal_approx(main.cam_zoom, 1.1), "wheel zooms during live play (%.2f)" % main.cam_zoom)
			var launch = root.get_node("/root/Launch")
			main.replay_active = true
			check(not main.zoom_camera(1.0) and is_equal_approx(main.cam_zoom, 1.1), "wheel ignored during a replay")
			main.camera_follow = main.player.global_position
			main._update_camera(1.0 / 60.0)
			var d: float = main.camera.global_position.distance_to(main.player.global_position)
			check(absf(d - main.FOLLOW_CAM_OFFSET.length()) < 0.01, "the replay Player cam uses the default framing (%.2f m)" % d)
			main.replay_active = false
			var ct = main.CoinToss.new()   # stand-in: only "a toss cutscene is up" matters here
			main.coin_toss = ct
			check(not main.zoom_camera(-1.0) and is_equal_approx(main.cam_zoom, 1.1), "wheel ignored during the coin-toss cutscene (#129 poses the camera itself)")
			main.coin_toss = null
			ct.free()
			check(launch.settings.camera_zoom == main.cam_zoom, "Launch settings hold the live zoom")],
		[12360, func(): _force_dead_if_live(); main.configure(7); main.pov_enabled = true; main.mouse_captured_override = true],
		[12362, func():
			check(main.pov_active(), "zoom step: QB in POV aim")
			var before := [main.cam_zoom, main.aim_yaw, main.aim_pitch, main.charge, main.charging]
			_wheel(true); _wheel(false); _wheel(false); _middle_click()
			check([main.cam_zoom, main.aim_yaw, main.aim_pitch, main.charge, main.charging] == before, "wheel and middle click do nothing in POV aim (zoom, aim, charge unchanged)")
			main.pov_enabled = false
			main.mouse_captured_override = null
			_key(KEY_C)
			check(main.taunt_wheel.open and not main.pov_active(), "taunt wheel open on the follow camera")
			_wheel(true); _middle_click()
			check(is_equal_approx(main.cam_zoom, 1.1), "wheel and middle click do nothing while the taunt wheel is open")
			main.taunt_wheel.close()
			_wheel(true)
			check(is_equal_approx(main.cam_zoom, 1.0), "the wheel zooms again once the taunt wheel closes")],
		[12390, func():
			var launch = root.get_node("/root/Launch")
			launch.settings_path = zoom_path0
			DirAccess.remove_absolute(ProjectSettings.globalize_path(ZOOM_SETTINGS))
			main.ai.defense_enabled = true],
		# Gridiron controls: POV aim + throw (mouse look), Q/E spin, F dive, wheel/C taunt
		[12400, func(): main.configure(7); main.ai.defense_enabled = false; main.pov_enabled = true],
		[12402, func(): check(main.pov_active(), "QB presnap: POV aim active"); check(absf(main.aim_yaw) < 0.001, "aim starts downfield"); _key(KEY_SPACE)],
		[12405, func(): check(main.pov_active(), "POV stays on while the snap is in the air")],
		[12430, func(): main.look(Vector2(200, -100)); check(absf(main.aim_yaw - 0.5) < 0.001 and main.aim_pitch > main.POV_PITCH_START, "mouse look turns + raises the aim"); _key(KEY_J)],
		[12460, func():
			var ang: float = main.launch_angle()
			var dir: Vector2 = main.aim_dir()
			var qb = main.world.get_athlete(main.controlled_id)
			check(main.screen_to_field(Vector2(0, 1)).dot(main.aim_dir()) > 0.99, "W moves along the passer's view (cam yaw %.2f, aim yaw %.2f)" % [main.cam_yaw, main.aim_yaw])
			check(main.charging and main.camera.fov < main.CAMERA_FOV - 5.0 and main.camera.fov > main.AIM_ZOOM_FOV, "holding J aim-zooms the camera (fov %.1f, charge %.2f)" % [main.camera.fov, main.charge])
			_key_up(KEY_J)
			var v: Vector3 = main.world.ball.velocity - Vector3(qb.velocity.x, qb.velocity.y, 0) * main.T.THROW_INHERIT
			check(main.world.forward_pass_thrown, "J release throws (POV)")
			check(Vector2(v.x, v.y).normalized().dot(dir) > 0.999, "ball flies where the QB looked")
			check(absf(rad_to_deg(atan2(v.z, Vector2(v.x, v.y).length())) - ang) < 0.5, "view pitch = launch angle (%.1f)" % ang)
			check(not main.pov_active(), "POV ends once the ball is thrown")],
		[12490, func(): check(absf(main.camera.fov - main.CAMERA_FOV) < 0.5, "FOV eases back after the throw (%.2f)" % main.camera.fov)],
		[12500, func(): main.configure(7); main.ai.defense_enabled = false],
		[12501, func(): _key(KEY_SPACE)],
		[12540, func(): check(main.world.ball.is_held_by(main.controlled_id), "QB has the ball"); _key(KEY_E); check(main.world.get_athlete(main.controlled_id).is_spinning() and main.world.get_athlete(main.controlled_id).spin_dir == 1, "E spins right")],
		[12543, func(): check(main.views[main.controlled_id].spin_vis_t > 0.0, "spin animates the athlete")],
		[12640, func(): _key(KEY_Q); check(main.world.get_athlete(main.controlled_id).spin_dir == -1, "Q spins left")],
		# #138: R dashes only with a charge. Both charges are spent (E, Q): R does nothing.
		[12670, func():
			var qb = main.world.get_athlete(main.controlled_id)
			var c0: float = qb.move_charge
			check(main.world.phase == main.World.Phase.LIVE and c0 < 1.0 and qb.move_t == 0.0, "both move charges spent (%.2f)" % c0)
			_key(KEY_R)
			check(qb.move_t == 0.0 and qb.move_charge == c0, "R without a charge does not dash")],
		[12680, func(): main.world.get_athlete(main.controlled_id).facing = Vector2(0, 1); _key(KEY_F); check(main.world.get_athlete(main.controlled_id).is_diving(), "F dives with the ball")],
		[12720, func(): check(main.world.phase == main.World.Phase.DEAD and main.last_whistle == "TACKLE", "carrier dive: down where he lands (%s)" % main.last_whistle)],
		# #139 taunt wheel: moved to tests/flow/segments/taunt_wheel.gd. Restore the knobs it left
		# for the steps after it (they aim at a field point, with the defense on).
		[12800, func(): main.mouse_captured_override = null; main.ai.defense_enabled = true; main.pov_enabled = false],
		# C04c (#89): Q1 runs out on a live play snapped with Space -> after the whistle the
		# next play lines up in Q2 at the same spot with the end zones switched. Window 13000-13170.
		[13000, func(): main.configure(7); main.auto_next = false; main.series.clock.quarter_length = 60.0; main.series.start(0, 40.0); main.set_controlled(main.my_id)],
		[13002, func():
			check(main.series.clock.label().begins_with("Q1"), "quarters format (%s)" % main.series.clock.label())
			check(main.field_root.get_node("EndZoneName0").text == "HELIOS", "Q1: HELIOS end zone behind the HELIOS offense")
			main.series.clock.remaining = 0.05
			_key(KEY_SPACE)
			check(main.world.phase == main.World.Phase.LIVE, "Space snaps the last play of Q1")],
		[13030, func(): check(main.series.clock.expired() and main.series.clock.quarter == 1, "Q1 clock out, play still live"); var c = main.world.carrier(); c.position.y = 44.0; main.world._whistle("tackle", {"carrier": c.id, "team": 0}); main.auto_next = true],
		[13170, func():
			main.auto_next = false
			var s = main.series
			check(s.clock.quarter == 2 and s.last_outcome.get("switch_ends", false), "next play is Q2 and switches ends (%s)" % s.last_outcome.get("outcome", "?"))
			check(s.downs.offense_team == 0 and absf(main.world.los_y - 44.0) < 0.01 and s.downs.down == 2, "field position carries over: HELIOS 2nd down at the 44 (%s)" % s.downs.label())
			check(main.field_root.get_node("EndZoneName0").text == "NEBULA" and main.field_root.get_node("EndZoneName1").text == "HELIOS", "Q2: HELIOS now defends the NEBULA-painted end")
			check(main.pres.overlay.banner.visible and main.pres.overlay.banner.text == "SWITCH ENDS", "SWITCH ENDS banner (%s)" % main.pres.overlay.banner.text)],
		# B09/C02: coin toss with the real keys -> live kickoff aimed like a pass (J) -> return
		[9500, func(): main.opening_kickoff = true; main.toss_seed = 0; main.configure(7); kick_events.clear(); main.world.event.connect(func(n, _d): kick_events.append(n))],
		[9502, func(): check(main.series.state == main.Match.State.TOSS and main.series.toss_winner == 0, "home won the toss"); check(main.hud.text.find("COIN TOSS: HOME wins") >= 0, "HUD offers the choice"); check(main.pres.overlay.status_l.text == "YOU WON THE TOSS" and main.pres.overlay.down_l.text == "", "toss pill names the winner, no key hints or COIN TOSS chip (#131) (%s)" % main.pres.overlay.status_l.text); _key(KEY_2)],
		[9503, func(): check(main.series.state == main.Match.State.KICKOFF and main.world.offense_team == 0, "2 key: home kicks"); check(main.world.ball.is_held_by(main.controlled_id), "you are the kicker"); main.aim_point = Vector2(main.field.width / 2.0, 92.0)],
		# #68 (frame 9504, plus checks in 9505, 11100, 11141): the stepped meter beside your kicker
		# follows the aim distance and is change-driven; the kickoff ball stands on a tee.
		[9504, func():
			var ka = main.pres.kick_art
			check(ka.meter.visible and ka.lit == ka.steps_for(main.kick_power()), "kick meter beside your kicker: %d/%d steps for power %.2f" % [ka.lit, ka.STEPS, main.kick_power()])
			var side: Vector3 = ka.meter.global_position - main.views[main.controlled_id].global_position
			check(Vector2(side.x, side.z).length() < 2.0, "meter stands next to the kicker (%.2f m)" % Vector2(side.x, side.z).length())
			check(ka.tee.visible and main.ball_view.global_position.distance_to(ka.tee.global_position) < 0.5, "kickoff ball stands on the tee")
			check(main.views[main.controlled_id].ball_node == null, "not in the kicker's hand")
			check(main.ball_view.global_basis.z.normalized().y > 0.9, "ball stands upright")
			kick_meter_far = [ka.lit, ka.pushes]
			main.aim_point = Vector2(main.field.width / 2.0, 55.0)],
		[9505, func():
			check(main.can_kick() and main.arc_dots[0].visible, "kick arc preview on the tee"); check(main.hud.text.find("KICKOFF") >= 0, "HUD: kickoff"); check(not main.pres.overlay.picker.visible, "no play picker on a kickoff")
			var ka = main.pres.kick_art
			check(ka.lit < kick_meter_far[0] and ka.lit == ka.steps_for(main.kick_power()), "shorter aim lights fewer steps (%d < %d)" % [ka.lit, kick_meter_far[0]])
			check(ka.pushes == kick_meter_far[1] + 1, "meter pushed once for one change, not per frame (%d pushes)" % (ka.pushes - kick_meter_far[1]))
			main.aim_point = Vector2(main.field.width / 2.0, 92.0)],
		[9506, func(): _key(KEY_J); check(main.world.kicked and kick_events.has("kick"), "J kicks off at the aim point")],
		[11100, func(): check(not main.pres.kick_art.meter.visible and main.pres.kick_art.tee.visible and not main.pres.kick_art.ball_on_tee(main.world), "after the kickoff: meter gone, empty tee left on the turf"); check(main.world.phase == main.World.Phase.DEAD, "kickoff play over (%s; events %s; ball %d holder %d)" % [main.last_whistle, str(kick_events), main.world.ball.state, main.world.ball.holder_id]); _force_dead_if_live(); main.next_play(); check(main.series.state != main.Match.State.KICKOFF and (main.world.offense_team == 1 or main.series.state == main.Match.State.TRY), "kickoff resolved: return team's ball or a score (%s)" % main.series.last_outcome.get("outcome", "?"))],
		# 4th down: K calls a punt, Space snaps, J punts toward the aim point
		[11101, func(): main.series.start(0, 30.0); main.series.downs.down = 4; main.set_controlled(main.my_id); kick_events.clear()],
		[11102, func(): _key(KEY_K); check(main.world.kick_play == "punt", "K key calls a punt")],
		[11103, func(): check(main.hud.text.find("KICK: PUNT") >= 0, "HUD shows the punt call"); _key(KEY_SPACE)],
		[11140, func(): check(main.world.ball.is_held_by(main.controlled_id), "punter has the snap"); main.aim_point = Vector2(main.field.width / 2.0, 70.0)],
		[11141, func(): check(main.pres.kick_art.meter.visible and not main.pres.kick_art.tee.visible, "punt: meter beside the punter, no tee"); _key(KEY_J); check(kick_events.has("kick") and not kick_events.has("throw"), "punted, not thrown")],
		[11900, func(): _force_dead_if_live(); main.next_play(); check(main.world.offense_team == 1, "punt: possession changes (%s)" % main.series.last_outcome.get("outcome", "?"))],
		# K twice = field goal; aiming at the posts clears the bar
		[11901, func(): main.series.start(0, 85.0); main.series.downs.down = 4; main.set_controlled(main.my_id); main.ai.defense_enabled = false],
		[11902, func(): _key(KEY_K); _key(KEY_K); check(main.world.kick_play == "fg", "K K: field goal"); _key(KEY_SPACE)],
		[11940, func(): main.aim_point = Vector2(main.field.width / 2.0, main.field.posts_y())],
		[11941, func(): _key(KEY_J)],
		[12200, func(): check(main.last_whistle == "FIELD GOAL GOOD", "field goal good (%s)" % main.last_whistle); main.next_play(); check(main.series.score[0] == 3, "+3"); check(main.series.state == main.Match.State.KICKOFF, "then a kickoff"); main.ai.defense_enabled = true],
		# #189 fair catch through the real Snap key: you're the punt returner, Space while the punt is
		# in the air signals, the catch ends the play at the spot. Frames 13600-13900 (after the last step).
		[13600, func():
			_force_dead_if_live()
			var mine: int = main.world.get_athlete(main.my_id).team
			main.series.start(1 - mine, 30.0); main.series.downs.down = 4
			check(main.series.call_kick("punt"), "bot offense lines up to punt")
			fc_ret = main.world.returner(); main.set_controlled(fc_ret.id)
			check(fc_ret.team == mine, "you are the punt returner")],
		[13601, func(): _key(KEY_SPACE); check(main.world.phase == main.World.Phase.PRESNAP and main.world.fair_catch_id == -1, "Space on the return team before the snap does not signal"); main.world.snap()],
		[13650, func():
			var ov = main.pres.overlay
			check(main.world.kick_in_air(), "bot punter kicked it (%s)" % main.world.kick_play)
			check(ov.fair_catch_prompt(main.world, main.controlled_id) == "PRESS SPACE FOR A FAIR CATCH", "returner prompt while the punt is in the air")
			fc_ret.position = main.ai._landing_point(main.world)
			_key(KEY_SPACE)
			check(main.world.fair_catch_id == fc_ret.id, "Space signals a fair catch")
			check(ov.fair_catch_prompt(main.world, main.controlled_id).begins_with("FAIR CATCH SIGNALED"), "prompt confirms the signal")],
		[13900, func():
			check(main.world.phase == main.World.Phase.DEAD and main.last_whistle == "FAIR CATCH", "play dead on the fair catch (%s)" % main.last_whistle)
			check(main.pres.overlay.whistle_summary(main.last_whistle, main.world) == "FAIR CATCH", "dead-ball line says FAIR CATCH")
			var spot: float = main.world.dead_ball_spot.y
			main.next_play()
			check(main.series.last_outcome.get("outcome", "") == "fair_catch" and main.world.offense_team == fc_ret.team, "return team's ball after the fair catch")
			check(absf(main.world.los_y - (100.0 - spot)) < 0.01, "spotted at the catch (%.1f)" % main.world.los_y)
			main.set_controlled(main.my_id)],
		# C04b: change quarters on the normal dead-ball advance.
		[12210, func():
			main.opening_kickoff = false
			main.configure(3)
			main.ai.defense_enabled = false
			main.series.clock.quarter_length = 120.0
			main.series.clock.reset()],
		[12212, func():
			check(main.pres.overlay.clock_l.text == "Q1 2:00", "scorebug opens in Q1")
			_key(KEY_SPACE)],
		[12225, func():
			check(main.world.phase == main.World.Phase.LIVE, "Space starts the last play of Q1")
			main.series.clock.remaining = 0.0
			main.world.carrier().position.x = -0.5],
		[12228, func():
			_key(KEY_R)
			check(main.series.clock.quarter == 1 and main.world.phase == main.World.Phase.DEAD, "R (dash) no longer advances the play (#138)")
			_key(KEY_ENTER)],
		[12238, func():
			check(main.series.clock.quarter == 2 and main.series.downs.down == 2 and main.world.offense_team == 0, "Enter advances to Q2 and preserves the drive")
			check(main.pres.overlay.clock_l.text == "Q2 2:00", "scorebug updates to Q2")
			main.ai.defense_enabled = true],
		# C06a (#98): forward progress. Space snaps; a linebacker meets the QB and drives him back
		# two yards before diving; the ball is spotted where his progress stopped. Window 13400-13480.
		[13400, func(): main.configure(7); main.auto_next = false; main.ai.defense_enabled = false; main.series.start(0, 40.0); main.set_controlled(main.my_id)],
		[13402, func(): _key(KEY_SPACE); check(main.world.phase == main.World.Phase.LIVE, "Space snaps (forward progress play)")],
		[13430, func():
			var c = main.world.carrier()
			check(c != null and c.team == 0, "QB has the ball")
			c.position = Vector2(6.0, 38.0)
			fp_lb = main.world.find_role(1, main.Athlete.Role.LB)
			fp_lb.position = Vector2(6.0, 39.6)
			fp_lb.facing = Vector2(0, -1)],
		[13470, func():
			fp_driven_y = main.world.carrier().position.y
			check(fp_contact_y - fp_driven_y > 1.0, "LB drove the QB back (%.2f yd)" % (fp_contact_y - fp_driven_y))
			check(main.world.tackle(fp_lb.id), "LB dives")],
		[13476, func():
			check(main.world.phase == main.World.Phase.DEAD and main.last_whistle == "TACKLE", "tackled (%s)" % main.last_whistle)
			check(absf(main.world.dead_ball_spot.y - fp_contact_y) < 0.2, "spotted at forward progress %.2f, not where he was driven to %.2f (spot %.2f)" % [fp_contact_y, fp_driven_y, main.world.dead_ball_spot.y])
			var ov = main.pres.overlay
			check(ov.banner.visible and ov.banner.text == "FORWARD PROGRESS" and ov.banner_sub.text.begins_with("+"), "FORWARD PROGRESS banner (%s %s)" % [ov.banner.text, ov.banner_sub.text])
			main.next_play()
			check(absf(main.world.los_y - fp_contact_y) < 0.2 and main.series.downs.down == 2, "next snap from the forward-progress spot (%s)" % main.series.downs.label())
			main.ai.defense_enabled = true],
		[13500, _check_kick_return_touchdown],
		# #129 coin-toss cutscene, window 14000-16220 (60 Hz: the coin lands 180 frames in).
		# You win: Space / J do nothing in the air; at the reveal the title + cards show with no
		# key hints and the play clock held; a real click on KICK picks; the field comes back with
		# the kickoff clock untouched.
		[14000, func(): _toss_setup(0)],
		[14002, func():
			var ct = main.coin_toss
			check(ct != null and main.series.state == main.Match.State.TOSS, "coin-toss cutscene plays before the opening kickoff")
			check(ct != null and not main.athlete_root.visible and not main.pres.overlay.visible, "the match and its HUD wait behind it")
			_key(KEY_SPACE)
			_key(KEY_J)
			check(main.coin_toss != null and main.series.state == main.Match.State.TOSS and not main.world.kicked, "Space / J before the coin lands do nothing")],
		[14220, func():
			var ct = main.coin_toss
			check(ct != null and ct.title.text == "YOU WON THE TOSS" and ct.card_row.visible, "you won: title + RECEIVE / KICK cards")
			check(ct != null and _no_key_hints(ct.all_text()), "no key hints in the toss UI (%s)" % (ct.all_text() if ct else ""))
			check(main.series.play_clock_shown() == -1 and absf(main.series.clock.play_clock - main.series.clock.PLAY_CLOCK) < 0.001, "the play clock doesn't run during the toss")
			check(main.pres.excite > 0.5, "the crowd roars on the reveal (%.2f)" % main.pres.excite)
			_click(ct.cards[1])
			check(main.series.state == main.Match.State.KICKOFF and main.world.offense_team == _my_team(), "clicking KICK: you kick off")],
		[14222, func(): check(main.coin_toss != null and main.coin_toss.sub.text == "HELIOS WILL KICK", "the pick holds on screen (%s)" % (main.coin_toss.sub.text if main.coin_toss else "gone"))],
		[14290, func():
			check(main.coin_toss == null and main.athlete_root.visible and main.pres.overlay.visible, "faded back to the kickoff, HUD back")
			check(absf(toss_close_clock - main.series.clock.PLAY_CLOCK) < 0.001, "the kickoff's play clock is untouched when the field comes back (%.3f)" % toss_close_clock)
			check(main.can_kick(), "you're on the tee")],
		# Key 2 still works (no hint says so): 1 = receive.
		[14300, func(): _toss_setup(0)],
		[14490, func():
			_key(KEY_1)
			check(main.series.state == main.Match.State.KICKOFF and main.world.offense_team != _my_team(), "key 1 after the reveal: you receive")],
		[14492, func(): check(main.coin_toss != null and main.coin_toss.sub.text == "HELIOS WILL RECEIVE", "receive shows (%s)" % (main.coin_toss.sub.text if main.coin_toss else "gone"))],
		# AFK winner: receive when the window (from the reveal) runs out.
		[14600, func(): _toss_setup(0)],
		[15070, func(): check(main.series.state == main.Match.State.TOSS and main.coin_toss != null and main.coin_toss.timer_back.visible, "still choosing near the end of the window, timer shown")],
		[15090, func(): check(main.series.state == main.Match.State.KICKOFF and main.series.toss_choice == "receive" and main.coin_toss != null and main.coin_toss.receiver == _my_team(), "no answer = receive, shown in the cutscene")],
		# Bots win: you see them choose, they receive TOSS_BOT_PICK after the reveal.
		[15200, func(): _toss_setup(1)],
		[15420, func():
			var ct = main.coin_toss
			check(ct != null and ct.title.text == "NEBULA WINS THE TOSS" and ct.waiting_box.visible and ct.waiting.text == "NEBULA IS CHOOSING…" and not ct.card_row.visible, "bots won: they choose, you wait")
			check(ct != null and _no_key_hints(ct.all_text()), "no key hints (%s)" % (ct.all_text() if ct else ""))
			check(main.series.state == main.Match.State.TOSS, "bots still thinking")],
		[15460, func(): check(main.series.state == main.Match.State.KICKOFF and main.series.toss_choice == "receive" and main.world.offense_team == _my_team() and main.coin_toss != null and main.coin_toss.sub.text == "NEBULA WILL RECEIVE", "bots auto-pick receive after the reveal (%s)" % (main.coin_toss.sub.text if main.coin_toss else "gone"))],
		[15530, func(): check(main.coin_toss == null and absf(toss_close_clock - main.series.clock.PLAY_CLOCK) < 0.001, "you kick with a full play clock after the cutscene (%.3f)" % toss_close_clock)],
		# Skip (Space) once the result shows: the loser just closes it and it doesn't come back.
		[15600, func(): _toss_setup(1)],
		[15800, func(): _key(KEY_SPACE)],
		[15840, func():
			check(main.coin_toss == null and main.series.state == main.Match.State.TOSS and main.pres.overlay.visible, "loser skipped: back on the field while they choose")
			check(main.pres.overlay.status_l.text == "NEBULA IS CHOOSING", "the HUD pill says who's choosing (%s)" % main.pres.overlay.status_l.text)],
		[15845, func(): check(main.coin_toss == null, "a skipped cutscene doesn't restart")],
		# The winner's skip takes the default (receive).
		[15900, func(): _toss_setup(0)],
		[16100, func(): _key(KEY_SPACE); check(main.series.state == main.Match.State.KICKOFF and main.series.toss_choice == "receive", "winner's skip = receive")],
		[16160, func(): check(main.coin_toss == null and main.athlete_root.visible, "skipped back to the field")],
		# Training never shows it; neither does a match without the opening kickoff.
		[16200, func(): main.start_practice("passing")],
		[16202, func(): check(main.drill != null and main.coin_toss == null, "drills never show the coin toss")],
		[16210, func(): main.opening_kickoff = false; main.configure(7)],
		[16212, func(): check(main.coin_toss == null and main.series.state != main.Match.State.TOSS, "--no-kickoff: no toss, no cutscene")],
		# #253: blocking zone. Space snaps, a guard is 7 yd downfield when J throws: FLAG on the HUD;
		# Enter walks it off 10 yd and replays the down; the next snap clears the line. Window 16400-16700.
		[16400, func(): main.opening_kickoff = false; main.configure(7); main.auto_next = false; main.pov_enabled = false; main.ai.defense_enabled = false; main.series.start(0, 40.0); main.set_controlled(main.my_id)],
		[16402, func(): _key(KEY_SPACE); check(main.world.phase == main.World.Phase.LIVE, "Space snaps (blocking-zone play)")],
		[16440, func():
			var w = main.world
			check(w.ball.is_held_by(main.controlled_id) and w.blocking_zone_active(), "QB holds it, blocking zone on")
			var ol = w.find_role(0, main.Athlete.Role.OL)
			ol.position = Vector2(ol.position.x, w.los_y + 7.0)
			main.aim_point = Vector2(3.0, w.los_y + 18.0)
			_key(KEY_J)
			check(w.forward_pass_thrown and w.flags.size() == 1 and w.flags[0]["player"] == ol.id, "J throws with a guard 7 yd downfield: flagged (%d)" % w.flags.size())
			var ov = main.pres.overlay
			check(ov.banner.visible and ov.banner.text == "FLAG" and ov.banner_sub.text == "ILLEGAL MAN DOWNFIELD", "FLAG banner (%s %s)" % [ov.banner.text, ov.banner_sub.text])
			check(ov.flag_pill.visible and ov.flag_l.text == "FLAG · ILLEGAL MAN DOWNFIELD · OFFENSE", "flag line while the play is on (%s)" % ov.flag_l.text)],
		[16600, func():
			check(main.world.phase == main.World.Phase.DEAD, "pass play over")
			_key(KEY_ENTER)
			var d = main.series.downs
			check(absf(d.los - 30.0) < 0.001 and d.down == 1 and absf(d.first_down_y - 50.0) < 0.001, "Enter: 10 yd walked off, 1st down replayed, line to gain kept (los %.1f, down %d)" % [d.los, d.down])
			var ov = main.pres.overlay
			check(ov.flag_pill.visible and ov.flag_l.text == "FLAG · ILLEGAL MAN DOWNFIELD · OFFENSE · 10 YD · REPLAY 1ST DOWN", "ruling on the HUD (%s)" % ov.flag_l.text)],
		[16620, func(): _key(KEY_SPACE); check(main.world.phase == main.World.Phase.LIVE and not main.pres.overlay.flag_pill.visible, "the next snap clears the ruling")],
		# #355: window 16820–16824. A completed pass keeps its yards when the receiver fumbles.
		[16820, func():
			main.configure(3)
			main.auto_next = false
			main.pov_enabled = false
			main.ai.defense_enabled = false
			main.ai.offense_enabled = false
			main.series.start(0, 25.0)
			main.set_controlled(main.my_id)],
		[16822, _fumble_completed_pass],
		[16824, func():
			check(main.world.phase == main.World.Phase.DEAD, "defender took the receiver's fumble out of bounds")
			check(main.match_overview()["my_lines"] == ["QB: 1/1 12yd 0TD 0INT"], "Your game credits the completed pass to the fumble spot")
			check(main.stats.total("rec_yds") == 12.0, "the receiver also keeps the 12 yards")],
		# #337: window 17400–17452. A short defensive tip spends a down but leaves the ball at the LOS.
		[17400, func():
			main.opening_kickoff = false
			main.configure(3)
			main.auto_next = false
			main.pov_enabled = false
			main.ai.defense_enabled = false
			main.ai.offense_enabled = false
			main.series.start(0, 40.0)
			main.set_controlled(main.my_id)],
		[17402, func():
			_key(KEY_SPACE)
			check(main.world.ball.is_held_by(main.my_id) and main.world.phase == main.World.Phase.LIVE, "Space snaps the short-pass play")
			var w = main.world
			for a in w.athletes:
				a.position = Vector2(25.0, 40.0 + a.id * 2.0)
			var qb = w.carrier()
			qb.position = Vector2(12.0, 35.0)
			w.find_role(1, main.Athlete.Role.CB).position = qb.position + Vector2(0.0, 4.25)
			main.aim_point = qb.position + Vector2(0.0, 6.0)
			_key(KEY_J)
			check(w.forward_pass_thrown, "J releases the short pass")],
		[17432, func():
			check(main.world.phase == main.World.Phase.DEAD and main.last_whistle == "BREAKUP", "short defensive touch ends the play as a breakup")
			check(main.pres.overlay.status_l.text == "PASS BROKEN UP", "HUD shows the breakup ruling")],
		[17452, func():
			_key(KEY_ENTER)
			var d = main.series.downs
			check(d.offense_team == 0 and is_equal_approx(d.los, 40.0) and d.down == 2, "tip spends the down at the old spot without changing possession")],
		# #346: window 17500–17502. The picker replaces the pre-snap call and locks on Space.
		[17500, func():
			main.configure(3)
			main.auto_next = false
			main.ai.defense_enabled = false
			main.ai.offense_enabled = false
			main.series.start(0, 25.0)
			main.set_controlled(main.my_id)],
		[17502, _check_audible],
		# #323: window 17900–17904. A fumbled keeper still appears in the QB's match stats.
		[17900, func():
			main.configure(3)
			main.auto_next = false
			main.ai.defense_enabled = false
			main.ai.offense_enabled = false
			main.series.start(0, 25.0)
			main.set_controlled(main.my_id)],
		[17902, _fumble_keeper],
		[17904, func():
			check(main.world.phase == main.World.Phase.DEAD, "defender took the fumble out of bounds")
			check(main.match_overview()["my_lines"] == ["QB: 1 car 12yd 0TD"], "Your game credits the fumbled keeper once")],
		# #375: window 18100–18142. The center and rusher release as the QB steps out.
		[18100, func():
			main.configure(5)
			main.auto_replay = false
			main.auto_next = false
			main.ai.offense_enabled = false
			main.ai.defense_enabled = false
			main.series.start(0, 40.0)
			main.set_controlled(main.my_id)],
		[18102, func(): _key(KEY_SPACE); check(main.world.phase == main.World.Phase.LIVE, "Space starts the blocking play")],
		[18138, func():
			var w = main.world
			var x: float = w.field.width * 0.5
			var blocker = w.find_role(0, main.Athlete.Role.C)
			blocker.position = Vector2(x, 39.6)
			blocker.facing = Vector2.DOWN
			w.find_role(1, main.Athlete.Role.DL).position = Vector2(x, 40.5)],
		[18140, func():
			var w = main.world
			var blocker = w.find_role(0, main.Athlete.Role.C)
			var defender = w.find_role(1, main.Athlete.Role.DL)
			check(blocker.engaged_with == defender.id and defender.engaged_with == blocker.id, "center and rusher are engaged")
			var qb = w.carrier()
			check(qb != null, "QB holds the snap")
			if qb != null:
				qb.position.x = -0.5],
		[18142, func():
			var w = main.world
			check(w.phase == main.World.Phase.DEAD and main.last_whistle == "OUT OF BOUNDS", "QB stepping out ends the play")
			check(w.athletes.all(func(a): return a.engaged_with == -1), "all blocks end at the whistle")],
	]
	for f in range(13431, 13470):   # the LB keeps walking into the QB (bodies collide, QB gives ground)
		steps.append([f, _fp_push])

func _check_audible() -> void:
	var overlay = main.pres.overlay
	_key(KEY_Q)
	overlay._refresh_picker(main, false)
	check(not overlay.picker.visible, "Q closes the pre-snap play picker")
	_key(KEY_Q)
	overlay._refresh_picker(main, false)
	check(overlay.picker.visible, "Q reopens the pre-snap play picker")
	var slants: Button = overlay.picker_grid.get_children().filter(func(b): return b.text == "Slants")[0]
	var flood: Button = overlay.picker_grid.get_children().filter(func(b): return b.text == "Flood")[0]
	slants.pressed.emit()
	flood.pressed.emit()
	overlay._refresh_picker(main, false)
	main._render()
	check(main.world.play_name == "Flood" and flood.button_pressed and not slants.button_pressed, "the second picker call selects Flood")
	check(main.route_mesh.get_surface_count() > 0, "the offense sees the audible's routes")
	_key(KEY_SPACE)
	slants.pressed.emit()
	overlay._refresh_picker(main, false)
	main._render()
	check(main.world.phase == main.World.Phase.LIVE and main.world.play_name == "Flood", "a stale picker action cannot change a live call")
	check(not overlay.picker.visible and main.route_mesh.get_surface_count() == 0, "Space hides the picker and route art")

func _fumble_keeper() -> void:
	_key(KEY_SPACE)
	var w = main.world
	var qb = w.carrier()
	check(qb != null and qb.id == main.my_id, "Space snaps to the local quarterback")
	if qb == null:
		return
	var defender = w.find_role(1, main.Athlete.Role.CB)
	qb.position = Vector2(5.0, w.los_y + 12.0)
	defender.position = qb.position
	w._fumble(qb, defender)
	w.ball.position.z = 0.0
	w._step_loose(0.0)
	check(w.carrier() == defender, "defense recovers the QB fumble")
	defender.position.x = -0.5

func _fp_push() -> void:
	var c = main.world.carrier()
	if c == null or fp_lb == null:
		return
	fp_lb.position = c.position + Vector2(0, 0.75)   # keeps leaning in: bodies overlap, QB gives ground
	if fp_contact_y == INF and fp_lb.position.distance_to(c.position) <= main.T.CONTACT_REACH:
		fp_contact_y = c.position.y

func _check_kick_return_touchdown() -> void:
	main.opening_kickoff = true
	main.toss_seed = 0
	main.configure(7)
	_key(KEY_2)
	_key(KEY_SPACE)
	var world = main.world
	check(world.kicked and world.kick_play == "kickoff", "Space puts the kickoff in play")
	var returner = world.returner()
	if returner == null:
		check(false, "kickoff returner exists")
		return
	world.ball.hold(returner.id)
	returner.position = Vector2(world.field.width / 2.0, -0.5)
	world.step({}, 1.0 / 60.0)
	check(main.stats.summary_lines().any(func(line): return line.ends_with("1 ret TD")),
		"match summary records the kick return touchdown")
	main.next_play()
	check(main.series.score[1] == 6, "kick return still scores six points")

func _key_up(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = false
	main._input(ev)

## First receiver not controlled by the human (humans don't auto-run routes).
func _ai_receiver():
	for r in main.world.receivers_in_order():
		if r.id != main.controlled_id and r.role == main.Athlete.Role.WR:
			return r
	return null

## Put an opposing CB alone at the throw spot; everyone else well away from it.
func _setup_pick() -> void:
	var cb = main.world.find_role(1, main.Athlete.Role.CB)
	for a in main.world.athletes:
		if a.id != cb.id and a.position.distance_to(Vector2(50, 60)) < 6.0:
			a.position.x = 30.0
	cb.position = Vector2(50, 60)

## Tackling drill: run at the carrier; press the real E key when in range.
var _chasing := false
func _chase_and_tackle() -> void:
	_chasing = true

func _chase_tick() -> void:
	if not _chasing or main.drill == null:
		return
	var me = main.world.get_athlete(main.my_id)
	var c = main.world.carrier()
	if c == null or main.drill.rep_over:
		_chasing = false
		main.input_override = null
		main.sprint_override = null
		check(main.drill.successes == 1, "tackled with the real F (dive) key (%d/%d)" % [main.drill.successes, main.drill.reps])
		return
	var to: Vector2 = c.position + c.velocity * 0.25 - me.position
	main.input_override = to.normalized()
	main.sprint_override = true
	if to.length() < 1.8 and me.can_act():
		me.facing = (c.position - me.position).normalized()
		_key(KEY_F)

## Inject a real key press through main's key handler.
## Press/release a key in Godot's Input state (for code that polls Input.is_key_pressed).
func _hold(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

## One mouse-wheel notch through the real handler (#140 camera zoom).
func _wheel(up: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.factor = 1.0
	ev.pressed = true
	main._unhandled_input(ev)
	ev = ev.duplicate()
	ev.pressed = false
	main._unhandled_input(ev)

## Middle press + release with no drag through the real handler (#140 zoom reset).
func _middle_click() -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_MIDDLE
		ev.pressed = down
		main._unhandled_input(ev)

## Relative mouse motion through the real handler (#139 taunt wheel / mouse look).
func _mouse(rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	main._unhandled_input(ev)

func _key(code: int, pressed := true) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = pressed
	if code == KEY_TAB:
		main._input(ev)
	else:
		main._unhandled_key_input(ev)

## Never touch the player's real profile / leaderboard / ratings from tests.
func _isolate_user_files() -> void:
	main.profile_path = "user://test_flow_profile.json"
	main.leaderboard_path = "user://test_flow_leaderboard.json"
	main.ranked_path = "user://test_flow_ranked.json"
	main.replay_dir = "user://test_flow_replays"   # every final saves a replay; never into the real replays/
	for p in [main.profile_path, main.leaderboard_path, main.ranked_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	main.profile.load_file(main.profile_path)

func _connect_listeners() -> void:
	main.series.match_event.connect(func(_n, _d): series_events += 1)
	main.world.event.connect(func(n, d):
		if n == "catch":
			caught_by = d["by"]
			if frame >= 480 and frame < 800:
				main.ai.defense_enabled = true
				# #246: the receiver's pose as the ball arrives (views still show the last frame).
				var cv = main.views[caught_by]
				var ball: Vector3 = main.ball_view.global_position
				catch_pose = [cv.pose.catch_weight, cv.pose.catch_reach, ball.distance_to(cv.hand_r.global_position),
					ball.distance_to(cv.global_position + Vector3.UP * cv.CATCH_HEIGHT)])
	main.world.event.connect(func(n, d): if n == "tackle" and caught_by >= 0: tackled = true)
	main.world.event.connect(func(n, _d): if n == "interception": picked = true)
	main.world.event.connect(func(n, _d): if n == "snap" and frame > 4171 and frame <= 4481: bot_snap_clock = main.series.clock.play_clock)

## #129: a fresh match with the opening coin toss (seed 0 = HELIOS, the local team, wins).
func _toss_setup(seed: int) -> void:
	main.auto_next = false
	main.opening_kickoff = true
	main.toss_seed = seed
	main.configure(7)
	toss_close_clock = -1.0

## Record the kickoff play clock at the moment a toss cutscene closes.
func _watch_toss() -> void:
	var ct = main.coin_toss
	if ct != null and not ct.closed.is_connected(_on_toss_closed):
		ct.closed.connect(_on_toss_closed)

func _on_toss_closed() -> void:
	toss_close_clock = main.series.clock.play_clock

func _my_team() -> int:
	return main.world.get_athlete(main.my_id).team

## True when `text` carries no key-hint words or bare key numbers.
func _no_key_hints(text: String) -> bool:
	var padded := " %s " % text.to_upper()
	for h in ["PRESS", "KEY", "SPACE", "ENTER", "ESC", "CLICK", "[1]", "[2]", " 1 ", " 2 ", "(1", "(2"]:
		if padded.contains(h):
			return false
	return true

## A left click on a toss card, delivered to the card's own gui_input handler. Headless
## viewports don't hit-test pushed mouse events, so the hit-tested click on the rendered
## screen is covered by tests/visual/coin_toss_test.gd.
func _click(card: Control) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = card.size * 0.5
		ev.global_position = card.get_global_rect().get_center()
		card.gui_input.emit(ev)

func _setup_ranked_rival() -> void:
	main.ranked_match = true
	main.ranked_path = "user://test_flow_ranked.json"
	main.leaderboard_path = "user://test_flow_leaderboard.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main.ranked_path))
	main.lobby.players[99] = {"name": "You", "ready": true}   # same display name as the host (#102)
	main.peer_installs[99] = RIVAL_INSTALL
	main.roster.auto_assign_team(99, 1 - main.world.get_athlete(main.my_id).team)

func _check_same_name_awards() -> void:
	var rival: int = main.roster.athlete_of(99)
	main.series.start(0, 95.0)
	_key(KEY_SPACE)
	check(main.world.phase == main.World.Phase.LIVE, "same-name awards fixture snaps through Space")
	main.world.event.emit("touchdown", {"carrier": main.my_id, "spot": Vector2(26, 100), "team": 0, "points": 6})
	main.series.score = [7, 0]
	var awards: Dictionary = main._match_awards({main.my_id: 1024.0, rival: 976.0})
	check(awards["xp"] == {main.my_id: 175, rival: 100}, "each same-named player gets their own XP")
	var ctx: Dictionary = awards["ctx"]
	check(ctx[main.my_id]["won"] and not ctx[rival]["won"], "only the winner gets the win bonus")
	check(main.Achievements.earned("first_td", ctx[main.my_id]) and not main.Achievements.earned("first_td", ctx[rival]),
		"only the scorer meets First Touchdown")
	check(ctx[main.my_id]["rating"] == 1024.0 and ctx[rival]["rating"] == 976.0,
		"ranked achievement context follows the player's own rating")

func _force_dead_if_live() -> void:
	if main.world.phase != main.World.Phase.DEAD:
		main.series.last_result = {"type": "incomplete"}
		main.world.phase = main.World.Phase.DEAD

func _fumble_completed_pass() -> void:
	_key(KEY_SPACE)
	var w = main.world
	var qb = w.carrier()
	check(qb != null and qb.id == main.my_id, "Space snaps to the quarterback for the fumble scenario")
	if qb == null:
		return
	var receiver = w.find_role(0, main.Athlete.Role.WR)
	var defender = w.find_role(1, main.Athlete.Role.CB)
	for athlete in w.athletes:
		athlete.position = Vector2(24.0, 60.0 + athlete.id * 2.0)
	qb.position = Vector2(5.0, 20.0)
	var catch_spot := Vector2(5.0, 33.0)
	receiver.position = catch_spot
	main.aim_point = catch_spot
	_key(KEY_J)
	check(w.forward_pass_thrown, "J throws the pass")
	w.ball.position = Vector3(catch_spot.x, catch_spot.y, 1.0)
	check(w._try_catch() and w.carrier() == receiver, "the receiver catches the pass")
	receiver.position.y = 37.0
	defender.position = receiver.position
	w._fumble(receiver, defender)
	w.ball.position.z = 0.0
	w._step_loose(0.0)
	check(w.carrier() == defender, "defense recovers the receiver's fumble")
	defender.position.x = -0.5

func _lead_to_wr() -> void:
	var qb = main.world.find_role(0, main.Athlete.Role.QB)
	var wr = main.world.find_role(0, main.Athlete.Role.WR)
	var from: Vector3 = Vector3(qb.position.x, qb.position.y, main.T.RELEASE_HEIGHT)
	main.aim_point = main.Passing.lead_target(from, wr.position, wr.velocity, main.T.PLAYER_PASS_POWER)

## #244: the carrier's arm tucks the ball (both hands for a passer before the throw), and
## the ball view sits in the palm socket in the same frame, not one frame behind the hand.
## #159: a pass in flight points its long axis (the ball's local Z) along its velocity at
## unit scale, and spirals about that axis between frames 90 and 92.
var _flight_y := Vector3.ZERO
func _check_ball_flight(first: bool) -> void:
	var b = main.world.ball
	var bx: Basis = main.ball_view.global_basis
	var v := Vector3(b.velocity.x, b.velocity.z, -b.velocity.y).normalized()
	check(b.state == b.State.IN_FLIGHT, "#159 pass still in the air at frame %d" % (90 if first else 92))
	check(absf(bx.z.length() - 1.0) < 0.01 and absf(bx.x.length() - 1.0) < 0.01, "#159 ball in flight at unit scale (%.2f)" % bx.z.length())
	check(absf(bx.z.normalized().dot(v)) > 0.99, "#159 long axis along the flight (dot %.3f)" % bx.z.normalized().dot(v))
	if first:
		_flight_y = bx.y
	else:
		check(bx.y.angle_to(_flight_y) > 0.3, "#159 ball spirals about its long axis (%.2f rad in 2 frames)" % bx.y.angle_to(_flight_y))

## #159: a dead ball nobody holds lies on its side on the turf, not sunk to its centre. This
## incompletion stops the ball in the air, so frame 396 drops it to the ground (as a pass that
## lands does: sim height 0) and frame 400 checks it, after the view's one-tick interpolation lag.
func _drop_dead_ball() -> void:
	check(main.world.phase == main.World.Phase.DEAD and main.world.ball.holder_id < 0, "#159 the incompletion is dead and nobody holds the ball")
	main.world.ball.position.z = 0.0

func _check_ball_lying() -> void:
	var bv: Node3D = main.ball_view
	check(bv.global_position.y >= preload("res://src/game/art/football.gd").RADIUS - 0.001,
		"#159 dead ball rests on the turf (centre y %.2f)" % bv.global_position.y)
	check(absf(bv.global_basis.z.normalized().y) < 0.05, "#159 dead ball lies on its side")

func _check_carry_pose(two_hand: bool, context: String) -> void:
	var c = main.world.carrier()
	if c == null:
		check(false, "carry pose: someone holds the ball (%s)" % context)
		return
	var v = main.views[c.id]
	check(v.ball_node == main.ball_view and v.pose.weight > 0.9 and v.pose.two_hand == two_hand,
		"carry pose on (%s): weight %.2f, two hands %s" % [context, v.pose.weight, v.pose.two_hand])
	var off: float = main.ball_view.global_position.distance_to(v.ball_transform().origin)
	check(off < 0.05, "ball pinned to the palm socket (%s): %.3f m off" % [context, off])
	var to_hand: float = main.ball_view.global_position.distance_to(v.hand_r.global_position)
	check(to_hand < 0.3, "ball in the hand (%s): %.2f m from the wrist" % [context, to_hand])
	# #245: heads far from the camera and the carrier don't look. Views within 15% of the
	# cutoff are skipped (they may be fading). Near ones are checked by role below.
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	var size := func(o): return o.global_position.distance_to(cam.global_position) * tan(deg_to_rad(cam.fov) * 0.5) / o.LOOK_VIEW_SIZE
	var near: Array = main.views.filter(func(o): return o != v and size.call(o) < 0.85)
	var far: Array = main.views.filter(func(o): return o != v and size.call(o) > 1.15)
	var far_ok: int = far.filter(func(o): return o.pose.look_weight < 0.5).size()
	check(v.pose.look_weight < 0.2 and far_ok == far.size(),   # the carrier's look fades over ~0.3 s
		"heads far from the camera don't look (%s): %d/%d far don't, carrier %.2f" % [context, far_ok, far.size(), v.pose.look_weight])
	# Live with the ball held: offensive linemen and route runners don't watch it; free defenders do.
	var offense: int = main.world.offense_team
	var o_look: int = main.views.filter(func(o): return o != v and o.athlete.team == offense and o.pose.look_weight > 0.5).size()
	var d_free: Array = near.filter(func(o): return o.athlete.team != offense and o.athlete.engaged_with < 0 and not o.athlete.blocking)
	check(main.views.all(func(o): return o.pose.catch_weight == 0.0), "nobody reaches without a pass in the air (%s)" % context)
	check(o_look == 0 and d_free.all(func(o): return o.pose.look_weight > 0.5),
		"only the defense watches a held ball (%s): %d offense look, %d free defenders near the camera all look" % [context, o_look, d_free.size()])

## #245: after the ball teleports (new spot), heads point at it at once instead of
## sweeping across the field: every looking view's look point is already at the ball.
func _check_look_snaps(context: String) -> void:
	var ball: Vector3 = main.ball_view.global_position
	var worst := 0.0
	for o in main.views:
		if o.pose.look_weight > 0.0:
			worst = maxf(worst, o._look_point.distance_to(ball))
	check(worst < 1.0, "heads snap to the ball after a teleport (%s): worst %.1f m behind" % [context, worst])

var _sorted := false
func _physics_process(_dt: float) -> bool:
	if not _sorted and not steps.is_empty():
		steps.sort_custom(func(a, b): return a[0] < b[0])   # out-of-order steps once silently never ran
		load("res://tests/flow/segments.gd").append(self, steps)   # tests/flow/segments/*.gd run after these
		_sorted = true
	if steps.is_empty():  # _initialize failed: never hang
		print("GAME FLOW FAIL (setup error)")
		quit(1)
		return true
	frame += 1
	_chase_tick()
	_watch_toss()
	for s in steps:
		if s[0] == frame:
			s[1].call()
	if frame > steps[-1][0]:
		print("GAME FLOW " + ("PASS" if ok else "FAIL"))
		quit(0 if ok else 1)
	return false
