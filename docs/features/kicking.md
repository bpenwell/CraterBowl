# Kicking

Feature-level doc: how this works for players **today** on `main`. Layering: `../design/architecture.md`. Open work: GitHub issues labelled `area:kicking` (listed below).

## Summary
Every classic match opens with a coin toss. Kickoffs are live plays with coverage and returns. Any scrimmage down can be turned into a punt or a field-goal try, and the 1-point try is a PAT kick. Returners can signal a fair catch with Space (#189). Aim at a point on the field and press **J** or LMB to kick immediately. The distance to the aim point determines the power. Rushers can block a kick early in its flight, and the ball is then live (#2, #3). Chaosball has no kicking (`call_kick` refuses in chaos).

## How it plays
| Situation | What happens |
|---|---|
| Coin toss | Deterministic from a seed (`--toss=N`). It plays as a cutscene (#129, `presentation.md`): the coin is in the air for `TOSS_REVEAL` (3 s), then the winner picks **RECEIVE** or **KICK** on two cards (click, or **1** / **2**; no key hints anywhere) within `TOSS_WINDOW` (5 s, counted from the reveal). No answer = receive. A bot winner picks receive `TOSS_BOT_PICK` (1.2 s) after the reveal. After the pick the kickoff's play clock waits `TOSS_OUTRO` (0.9 s) while the cutscene shows the pick and fades back. The other team receives the second half. |
| Kickoff | From your own 35 (`KICKOFF_SPOT_FRACTION`), or the 20 after a safety. The kicker is on the tee, coverage spreads out, and the receivers form a front row plus two deep returners (`KICKOFF_RETURNER_DEPTH`, their own 10). **Space** or the play clock gives a default kick (`KICKOFF_DEFAULT_POWER` 0.85). **J**/LMB fires an aimed kick on press. The arc previews the kick before you fire. |
| Kickoff results | Return, touchback → own 25 (`KICKOFF_FRACTION`), out of bounds → own 40 (`KICKOFF_OOB_FRACTION`), or a rolled/downed spot. An unfielded ball that stops for `KICK_REST_TIME` is downed. |
| Onside | Recovery past `ONSIDE_MIN_TRAVEL` (10 yd) exists as the `world.onside` mutator, **off by default**. Turning it on belongs to #42. |
| Punt | **K** cycles the kick call on any scrimmage down. The punter lines up `PUNT_DEPTH` 10 yd deep and the returner drops `PUNT_RETURNER_DEPTH` 38 yd past the LOS. A touchback comes out to the 20 (`PUNT_TOUCHBACK_FRACTION`). Fake punts play a normal down. |
| Kick meter and tee (#68) | While you can kick (kickoff on the tee, or the punt/FG snap in your hands), a stepped power meter of 10 bars stands beside your kicker, to his right as the camera sees it. It lights `ceil(power × 10)` bars (green → amber → red), where power is what the aim distance asks for (`main.kick_power()`), so moving the aim moves the bars; aim at or past the kick's maximum and all 10 light. It is gone when you can't kick (the other team kicking, scrimmage plays, after the kick, replays). On a kickoff the ball stands upright on an orange tee 1 yd ahead of the kicker and 0.7 yd to his left; the empty tee stays on the turf for the rest of the play. |
| Field goal | **K K**. The holder sets up `FG_HOLD_DEPTH` 7 yd deep. Good = between the uprights and above the 3.3 yd crossbar at the end line. A miss gives the defense the ball at the kick spot, or at its 20 if that's further out. |
| Tries | 1 point = PAT kick from the 15. 2 points = a scrimmage play from the 10. |
| Fair catch (#189) | While a punt or kickoff is in the air and untouched, a return-team player presses **Space** (the Snap key, gamepad A) to signal. The pill offers it (`PRESS SPACE FOR A FAIR CATCH`), and the signaler raises an arm under a `FAIR CATCH` label. If he catches it in the air the play is dead there: whistle `FAIR CATCH`, no return. A punt is spotted at the catch. A kickoff fair-caught short of the receiving 25 comes out to the 25, otherwise at the catch. Caught in the end zone = touchback. One signal per kick; nobody can block the signaler while the ball is in the air. A muff (the ball reaches the ground) stays live, but a return-team recovery after a signal is dead at the recovery spot, and so is a teammate's catch. |
| Blocks | A rusher within `KICK_BLOCK_REACH` (1 yd) of the ball during its first `KICK_BLOCK_WINDOW` (5 yd), while it is no higher than `KICK_BLOCK_HEIGHT` (3 yd), blocks it. Kickoffs can't be blocked. The ball pops up live (scoop and score). If the kicking team recovers, it plays the down out. |
| Bots | 4th-down rule: try a FG within `AI_FG_MAX` (50 yd); go for it on 4th & ≤2 past midfield; otherwise punt. They always kick the PAT (#190), vary kickoff depth, cover in lanes, and set a return wall. A bot returner fair-catches once the ball is coming down and any coverage man is within `AI_FAIR_CATCH_PRESSURE` (5 yd) of the landing spot, on punts and kickoffs alike; a human returner is never signaled for. |

Kick flight is a ballistic solve: `world.kick_velocity(kind, from, target, power)`. Speed runs from `KICK_SPEED_MIN` 14 to `KICK_SPEED_MAX` 27 yd/s, and the launch angle depends on the kick (`KICK_ANGLE`: punt 52°, FG 38°, kickoff 42°).

A kickoff or punt return touchdown counts as a special-teams score in the [postgame stats](progression.md).

## Design decisions
- **Kicks reuse the passing aim.** The aim point sets the direction and the distance used to calculate power (pillar 3). Rejected: automatic kicks from distance plus a random roll (no skill, nothing to watch) and a separate swinging-needle minigame (a new input mode and UI per kick type).
- **Kicks are deterministic.** No random wobble, so the skill is aim plus power. The ball flies through the real sim, so blocks, catches, bounces and touchbacks are physics, not dice.
- **Onside is a mutator, off by default.** Gridiron removed onside kicks, and backyard rules (#42) own turning it on.
- **The online path:** `kick`, `kick_call` and `toss` actions are sanitized and routed through the host. Snapshots carry the kick call, the kicked flag and the toss winner. The huddle is skipped on kickoffs.
- **Fair catch is the Snap key, contextual (#189).** Space already routes by side (offense hikes, defense breaks stance) and did nothing during live play (it now jumps, #379; the fair-catch signal wins while a kick is in the air), so it can't clash with the Gridiron map (#138: R dash, T timeout, C taunt, Q/E spin, F dive, G handoff, K kick call, J throw/kick) or #142's pre-snap double-tap. It needs no new binding, gamepad A works, and rebinding Snap moves it. Rejected: a new key (X/Z: one more thing to learn and rebind) and an automatic fair catch for humans (no decision left for the player).
- **Fair-catch rules are NFL-style with these deviations:** no fair-catch free kick, no invalid-signal penalty, and the kicking team still downs a loose kick on touch (existing simplification), so a muff can't be recovered by the kicking team. The kickoff spot uses the NFL's 2023 rule (fair catch behind the 25 = the 25), which equals our kickoff touchback spot. "No advance after a signal" matters here: without it, signal-then-let-it-bounce would be a free return behind an unblockable returner.
- **Bot fair catch is a pressure rule, not a roll.** Deterministic and readable: coverage within 5 yd of where the ball comes down, and the ball already descending (so the decision isn't made at the kick). Kicks stay deterministic.
- **Online:** the signal rides the existing `snap` action (host-authoritative). Snapshots carry `fc` (the signaler) only while a signal is active, because snapshots sit just under the 1400-byte budget (#193). Clients derive "kick in the air" from `kicked` + ball state (`World.kick_in_air()`), so no extra fields.
- **The toss is timed by the sim, shown by the cutscene (#129).** `Match` owns every toss time: the reveal (`TOSS_REVEAL`), the choice window, the bot pick and the clock hold after it (`TOSS_OUTRO`). The cutscene (`src/game/coin_toss.gd`) only follows `state` / `toss_winner`, so the host stays authoritative and clients just play it. Why the sim changed:
  - **The window starts at the reveal.** With the old 5 s from the match start, a 3 s coin flight would have left the winner 2 s with the cards.
  - **Bots wait for the coin to land.** They used to pick at once, which ended the toss before the cutscene could show it and let the kickoff's play clock run underneath it.
  - **The play clock waits for the fade.** Without `TOSS_OUTRO` the pick, dip and fade back (0.88 s) would come off the kickoff clock, and a bot kickoff (`AI_SNAP_DELAY` 2.5 s) would go 1.6 s after the field reappears.
  - Rejected: holding the sim in `TOSS` until the cutscene ends (the outcome is decided, and every "choose → KICKOFF" test and client would have to learn a second meaning of `TOSS`), and running the clock hold in `main.gd` (rules stay in `src/sim`).
  - Choices are still accepted before the reveal (tests, a blind 1 / 2): the cutscene then skips straight to the kickoff, since there's nothing left to reveal.
  - No `Protocol.VERSION` bump: the toss timers run on the host only. Clients read `ms` / `tw` and the play clock from snapshots, as before.
- **The kick meter is a read-out, not a minigame (#68).** Power already comes from the aim distance (above), so the meter shows that number in 10 steps rather than adding a timing input. Stepped (not a smooth bar) because steps are countable at a glance and only change when you cross one. It's a world-space billboard beside the kicker, where your eye already is (kicker + arc), rather than a HUD bar in a corner. One quad and one shader draws all 10 steps; the lit count is a shader uniform pushed only when it changes (`KickArt.set_steps`), so a held aim costs no per-frame work. No text, no shadow, drawn over the field (no depth test) so the kicker's body never hides it. Rejected: a HUD bar (far from the action) and one mesh per step (10 draw calls for the same picture). The `PRESS J OR CLICK TO KICK` pill stays: the meter shows power, not the key (`presentation.md`).
- **The tee is presentation only (#68).** The sim still kicks from the kicker's feet (`world.kick`), so no rule, snapshot or `Protocol.VERSION` change. The tee sits ahead and to the left of the kicker (a soccer-style approach) because straight ahead the follow camera behind him saw the ball through his legs (first try, 0.8 yd and then 1.5 yd ahead: hidden). The cost is a ~1.2 yd hop of the ball on the kick frame, at ~20 yd/s ball speed. Moving the sim's kick origin to the tee would change kickoff distances; not worth it for art.
- **Tests that assumed the old automatic touchback** were changed to expect live kickoffs. `game_flow` resets to a scrimmage for its legacy steps (`opening_kickoff`), and `net_test`'s host runs `--no-kickoff`.

## Code and tests
- `src/sim/world.gd`: `call_kick`, `setup_kickoff`, `kick`, `kick_velocity`, block and rest rules, `signal_fair_catch` / `kick_in_air` and the fair-catch branch of `_field_kick`
- `src/sim/match.gd`: toss, `_kickoff`, kick outcomes and spots
- `src/sim/tuning.gd`: `KICK_*`, `PUNT_*`, `FG_*`, `ONSIDE_*`, `AI_FG_MAX`
- `src/sim/ai.gd`: `_kick_protect`, `_bot_kick`, `_kick_coverage`, the 4th-down rule, `wants_fair_catch`
- `src/net/protocol.gd`: the `snap` action signals a fair catch for a returner; snapshot `fc`
- `src/game/player.gd` (raised arm + `FAIR CATCH` label), `src/game/overlay.gd` (`fair_catch_prompt`)
- `src/sim/stats.gd`: kicking stats (#67): FG made/att/long, XP, punts and gross yards, kick and punt return yards. Rules and display: `progression.md` "Stats"
- `src/game/kick_art.gd` + `src/game/art/kick_meter.gdshader` (#68): the stepped meter and the kickoff tee; `presentation.gd` stands the ball on the tee before the kick
- `src/game/main.gd`: K / 1 / 2 handling, instant kick input in `_set_charging()`, distance-based `kick_power()` and arc preview
- Tests:
  - `tests/test_kicking.gd`: about 30 tests, including a full bot match with kicks
  - `tests/test_kicking_stats.gd`: kicking stats from real kicks, and a bot match whose FG/XP stats must match the scoreboard; `tests/visual/kicking_stats_test.gd` captures them in the game overview
  - `tests/test_kick_meter.gd` (#68): steps per power, change-driven shader pushes, no shadows, tee only before a kickoff; `tests/game_flow.gd` frames 9504-9505, 11100 and 11141 check the meter beside your kicker (fewer steps for a shorter aim, one push per change), the ball upright on the tee and out of his hand, the empty tee after the kick, and the meter without a tee on the punt; `tests/visual/kick_meter_test.gd` captures `kick-meter-kickoff` and `kick-meter-punt`
  - `tests/test_fair_catch.gd`: signal window, spots (punt, kickoff inside/past the 25, end zone), muffs, teammate catch, signaler protection, blocked kick, bot rule, snapshot
  - `tests/game_flow.gd`: toss, aimed kickoff + arc + return, K punt, K K field goal, fair catch on the real Space key; the #129 toss cutscene (click / 1 / AFK / bot pick / skip / drills, frames 14000-16212)
  - `tests/test_kicking.gd` toss tests: window from the reveal, bot pick after the reveal, the outro clock hold, cutscene timing matches the sim
  - `tests/visual/coin_toss_test.gd`: the cutscene's captures (see `presentation.md`)
  - `tests/visual/fair_catch_test.gd`: captures `fair-catch-prompt`, `fair-catch-signal`, `fair-catch-whistle`
  - The scoring, clock and match-size tests expect live kickoffs

## Open issues
- #172 Kick and punt return touchdowns are credited as defensive TDs
- #69 D08 Fair catch + bot 2-pt decisions: #189 fair catch (this doc), #190 bot 2-pt try decision
- #42 C27 Backyard rules / trick plays (onside kick mutator)
