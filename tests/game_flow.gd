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
var auto_replay_default := false
var wr_id := -1
var kick_events: Array = []
var fc_ret = null   # #189 fair-catch step's returner
var fp_lb = null          # C06a forward progress: the defender driving the carrier back
var fp_contact_y := INF
var fp_driven_y := 0.0
var toss_close_clock := -1.0   # #129: kickoff play clock when the toss cutscene closed
var bot_snap_clock := INF   # #136: play clock when the bot offense snapped (frames 4171-4481)

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
		[40, func(): check(main.world.ball.is_held_by(main.controlled_id), "QB has ball")],
		[41, func(): main.aim_point = Vector2(40, 45)],
		[80, func(): check(main.arc_shown(), "pass preview shown before input")],
		[81, func(): _key(KEY_J)],
		[82, func(): check(main.world.forward_pass_thrown, "pass thrown")],
		[400, func(): check(main.world.phase == main.World.Phase.DEAD, "incomplete ends play")],
		# A04: reset, snap, lead a pass to a WR running his go route -> catch while keeping the assigned athlete
		[401, func(): main.next_play(); check(main.series.downs.down == 2, "incomplete -> 2nd down"); check(main.controlled_id == main.my_id, "control back to my athlete")],
		[402, func(): main.ai.defense_enabled = false; main.world.snap()],
		[480, func(): _lead_to_wr(); _key(KEY_J)],
		[531, func(): check(main.world.forward_pass_thrown, "lead pass thrown")],
		[800, func(): main.ai.defense_enabled = true; check(caught_by >= 0, "WR caught it"); check(main.controlled_id == main.my_id and main.controlled_id != caught_by, "assigned athlete retained after catch")],
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
		[7203, func(): check(main.world.phase == main.World.Phase.DEAD, "play over"); frozen_y = main.world.athletes[0].position.y; _key(KEY_V); check(main.replay_active, "V starts instant replay")],
		[7210, func(): var p = main.replay.last_play(); var smp = main.replay.sample(); var rp = Vector3(smp["pos"][3].x, 0, -smp["pos"][3].y); check(main.views[3].target_position().distance_to(rp) < 0.01, "views show replay frames"); check(main.views[3].position.distance_to(rp) < 0.5, "drawn view within one interpolation step of the replay frame"); check(main.hud.text.find("REPLAY 0.5x") >= 0, "HUD shows replay"); check(absf(main.world.athletes[0].position.y - frozen_y) < 0.001 and main.world.phase == main.World.Phase.DEAD, "offline sim frozen during replay")],
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
		[7930, func():
			var back = main.world.carrier()
			check(back != null and back.position.y > main.world.los_y and main.world.phase == main.World.Phase.LIVE, "bot RB runs across the LOS and stays live")
			if back != null:
				back.position.x = -0.5],
		[7932, func():
			check(main.world.phase == main.World.Phase.DEAD and main.stats.total("car") == 1 and main.stats.total("rush_yds") > 0.0, "whistle records the RB's rushing attempt and gain")],
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
		# #139 radial taunt wheel through the real C key + mouse handlers, on a pre-snap QB in
		# POV aim (the mode where mouse motion matters most). Window 12730-12800.
		[12730, func(): main.configure(7); main.ai.defense_enabled = false; main.mouse_captured_override = true],
		[12732, func():
			var qb = main.world.get_athlete(main.controlled_id)
			var w = main.taunt_wheel
			check(main.pov_active() and qb.emote_cd == 0.0, "taunt wheel step: QB in POV aim, no taunt yet")
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
			ev.pressed = true
			main._unhandled_input(ev)
			check(not w.open and qb.emote_cd == 0.0, "mouse wheel no longer picks or performs taunts")
			_mouse(Vector2(40, 0))
			check(main.aim_yaw > 0.0, "mouse motion turns the aim while the wheel is closed")
			main.reset_aim()
			var before := [main.aim_yaw, main.aim_pitch, main.camera_orbit, main.aim_distance]
			_key(KEY_C)
			check(w.open and w.visible and w.ids.size() == 8, "holding C opens the wheel: a slice per taunt")
			_mouse(Vector2(0, -80))
			check(w.highlighted() == w.ids[0], "drag up highlights the top slice (%s)" % w.highlighted())
			_mouse(Vector2(160, 80))
			check(w.highlighted() == w.ids[2], "drag right highlights the right slice (%s)" % w.highlighted())
			check([main.aim_yaw, main.aim_pitch, main.camera_orbit, main.aim_distance] == before, "camera and aim hold still while the wheel is open")
			_key(KEY_C, false)
			var v = main.views[main.controlled_id]
			check(not w.open and qb.emote_cd > 0.0 and v.emote_id == w.ids[2] and v.emote_t > 0.0 and v.bubble.visible, "releasing C performs the highlighted taunt (%s)" % v.emote_id)
			_mouse(Vector2(40, 0))
			check(main.aim_yaw > 0.0, "the aim turns again once the wheel closes")
			main.reset_aim()],
		[12800, func():
			var qb = main.world.get_athlete(main.controlled_id)
			var w = main.taunt_wheel
			var v = main.views[main.controlled_id]
			check(qb.emote_cd == 0.0, "taunt cooldown over")
			_key(KEY_C)
			_mouse(Vector2(0, -60))
			_mouse(Vector2(0, 60))
			_key(KEY_C, false)
			check(not w.open and qb.emote_cd == 0.0, "releasing C in the dead zone cancels")
			_key(KEY_C)
			_key(KEY_C, false)
			check(qb.emote_cd > 0.0 and v.emote_id == w.ids[2] and v.emote_t > Emotes.DURATION - 0.05, "tapping C repeats the last taunt (%s)" % v.emote_id)
			main.mouse_captured_override = null
			main.ai.defense_enabled = true
			main.pov_enabled = false],   # later steps aim at a field point
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
		[9505, func(): check(main.can_kick() and main.arc_dots[0].visible, "kick arc preview on the tee"); check(main.hud.text.find("KICKOFF") >= 0, "HUD: kickoff"); check(not main.pres.overlay.picker.visible, "no play picker on a kickoff")],
		[9506, func(): _key(KEY_J); check(main.world.kicked and kick_events.has("kick"), "J kicks off at the aim point")],
		[11100, func(): check(main.world.phase == main.World.Phase.DEAD, "kickoff play over (%s; events %s; ball %d holder %d)" % [main.last_whistle, str(kick_events), main.world.ball.state, main.world.ball.holder_id]); _force_dead_if_live(); main.next_play(); check(main.series.state != main.Match.State.KICKOFF and (main.world.offense_team == 1 or main.series.state == main.Match.State.TRY), "kickoff resolved: return team's ball or a score (%s)" % main.series.last_outcome.get("outcome", "?"))],
		# 4th down: K calls a punt, Space snaps, J punts toward the aim point
		[11101, func(): main.series.start(0, 30.0); main.series.downs.down = 4; main.set_controlled(main.my_id); kick_events.clear()],
		[11102, func(): _key(KEY_K); check(main.world.kick_play == "punt", "K key calls a punt")],
		[11103, func(): check(main.hud.text.find("KICK: PUNT") >= 0, "HUD shows the punt call"); _key(KEY_SPACE)],
		[11140, func(): check(main.world.ball.is_held_by(main.controlled_id), "punter has the snap"); main.aim_point = Vector2(main.field.width / 2.0, 70.0)],
		[11141, func(): _key(KEY_J); check(kick_events.has("kick") and not kick_events.has("throw"), "punted, not thrown")],
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
	]
	for f in range(13431, 13470):   # the LB keeps walking into the QB (bodies collide, QB gives ground)
		steps.append([f, _fp_push])

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
				main.ai.defense_enabled = true)
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

func _lead_to_wr() -> void:
	var qb = main.world.find_role(0, main.Athlete.Role.QB)
	var wr = main.world.find_role(0, main.Athlete.Role.WR)
	var from: Vector3 = Vector3(qb.position.x, qb.position.y, main.T.RELEASE_HEIGHT)
	main.aim_point = main.Passing.lead_target(from, wr.position, wr.velocity, main.T.PLAYER_PASS_POWER)

var _sorted := false
func _physics_process(_dt: float) -> bool:
	if not _sorted and not steps.is_empty():
		steps.sort_custom(func(a, b): return a[0] < b[0])   # out-of-order steps once silently never ran
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
