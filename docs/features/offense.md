# Offense

Feature-level doc: how this works for players **today** on `main`. Design/implementation detail: [architecture](../design/architecture.md). Open work: GitHub issues labelled `area:offense` (listed below).

## Summary
The offense calls one of six pass plays (plus two runs when a running back is on the field) from a pre-snap
picker, snaps with Space, and either throws to a mouse-aimed spot on the turf or hands off to the back.
Passes fly on a solved ballistic arc. Catches are automatic within a reach volume and are contested by
defenders. Line play is in [line-play.md](line-play.md); scoring, tries and turnovers are in [rules.md](rules.md).

## How it plays

### Play calling (pre-snap)
- The picker opens at the start of every play. **Q** toggles it; the mouse is free pre-snap, so you click a call.
- Offense buttons: Verticals, Slants, Mesh, Curls, Flood, Deep Shot, plus Inside Zone and Outside Sweep when the
  formation has an RB and the mode is classic (5v5 and 7v7). Also **Repeat last** (recall your team's previous call)
  and **Flip play** (swap the two WRs' routes; on a run, mirror the lane).
- An eligible receiver (WR or RB, not QB) gets a route dropdown to override their own route on a pass play.
- Each new formation pre-selects a default: Slants on 3 or fewer yards to go, Deep Shot on 15+ to go with 25+ yards to
  the goal, otherwise Mesh (`match.gd _setup_formation`).
- **Space** (gamepad A) snaps. The 20 s play clock (`Clock.PLAY_CLOCK`) auto-snaps if nobody does.
- Bot-only offenses pick their own call (`ai.choose_play`, about one run in three on early downs when an RB exists) and
  snap after `AI_SNAP_DELAY` (2.5 s), or `HUDDLE_SECONDS` (5.0 s) when any human is in a classic match.
- Your team's pre-snap turf art shows every route, the RB's run path and each lineman's target; yours is highlighted.
  The defense never sees it.

| Play | Left WR | Right WR | RB |
|---|---|---|---|
| Verticals | GO | GO | WHEEL |
| Slants | SLANT | SLANT | FLAT |
| Mesh | IN | IN | CURL |
| Curls | CURL | CURL | FLAT |
| Flood | CORNER | OUT | FLAT |
| Deep Shot | POST | GO | CURL |

Routes are waypoint offsets mirrored toward the field center (`routes.gd ROUTES`). Bot receivers follow them, then keep
the last segment's direction; comeback routes (CURL) settle instead of backpedaling.

### Snap
- With a center, the ball flies C to QB in `SNAP_TIME` (0.35 s). In 3v3 there is no center: the QB starts with the
  ball and the snap is instant.

### Passing
- **Aim:** during live play the mouse is captured. Horizontal motion orbits the camera; vertical motion sets the aim
  distance (2 to 65 yd, starts at 22). A ground reticle and a 24-dot arc preview show while you can throw.
- **Throw:** left click or **J** (gamepad RT). Hold **Ctrl** (gamepad RB) for a lob.
- Player throws use a fixed `PLAYER_PASS_POWER` (0.68), so about 24 yd/s. The solver picks the flattest angle that
  crosses the aim point at `CATCH_HEIGHT` (1.1 yd). Past about 56 yd the ball goes out at 45° and falls short.
- A lob uses a fixed `LOB_ANGLE` (65°) arc with the speed solved to land on the target.
- Legal throw: you hold the ball, play is live, you aren't diving, grounded or mid dash/spin, you are at or behind the
  LOS, and no forward pass has been thrown. Any carrier qualifies, so an RB behind the line after a handoff can throw.
- A ball that hits the ground is incomplete.

### Catching
- Automatic. Candidates are eligible players within `CATCH_RADIUS` (1.2 yd) while the ball is between
  `CATCH_MIN_HEIGHT` and `CATCH_MAX_HEIGHT` (0.3 to 2.6 yd). C and OL are ineligible; the thrower can't catch his own pass.
- The ball can't be caught or touched for its first `MIN_PASS_TRAVEL` (2.5 yd).
- Defenders reach `CONTEST_MARGIN` (0.35 yd) further. If the nearest defender is within that margin of the nearest
  receiver's distance, it is a breakup.
- A lone defender intercepts only within `INT_RADIUS` (0.6 yd) at the ball's closest approach; otherwise it is a breakup.
- A receiver (or defender) standing out of bounds can't complete the catch: incomplete.
- Control stays on your own athlete after a catch or handoff. Bots run with the ball when they have it.

### Run game
- **G** (gamepad R3) hands off. Requires: live play, you are the QB holding the ball at or behind the LOS, no forward
  pass yet, and the RB is standing within `HANDOFF_REACH` (1.6 yd) and behind the LOS. `HANDOFF_COOLDOWN` is 0.8 s.
  The handoff itself works on any call, not only run plays.
- On a run call the status line shows **MEET THE BACK** while you hold the ball and the RB is out of reach.
- A bot QB hands off within `AI_HANDOFF_WINDOW` (1.5 s); a bot RB comes to the QB, then follows the called lane.
- Inside Zone hits an interior gap; Outside Sweep goes wide. Bots flip the sweep automatically.

## Design decisions
- The snap is a short visible flight, not a teleport, so its timing is readable.
- Aim point plus solved arc over homing passes (no skill) or golf-style angle/power (too fiddly). The arc preview
  makes it learnable.
- Charged power (hold to charge, release to throw) was removed in the live-controls rework: throws now fire
  on press at fixed power. `THROW_INHERIT` (30% of QB velocity) exists but player and bot throws pass
  `inherit_motion = false`, so throwing on the run no longer drifts the ball.
- Reach-volume catching over physics collision: deterministic and server friendly. A catch button is #9.
- The contest margin makes body position matter: a defender doesn't need to be closer, only close enough.
- Pass not catchable for 2.5 yd and the 0.6 yd interception radius both came from bot sims where rushers batted
  every throw at release.
- Linear receiver lead threw curls and outs to empty grass; bots lead along the route path.
- Route art is shown to your own team only, so the QB can read a human receiver's route override without voice chat.
- Proximity handoff key over an automatic exchange (takes the timing choice away from a human QB) or a timing meter
  (a second timing task on a quick snap).
- Older key bindings (Q cycles plays, F cycles routes, L/X/Y for recall/flip/default) were replaced by the
  clickable picker; F is now spin.

## Code and tests
- `src/sim/routes.gd` — route library, playbook, run lanes.
- `src/sim/passing.gd` — ballistic solver, lob solver, lead prediction.
- `src/sim/world.gd` — `call_play`, `set_route`, `flip_play`, `recall_call`, `snap`, `throw`, `handoff`, `_try_catch`.
- `src/sim/match.gd` — default call per formation. `src/sim/ai.gd` — bot QB reads, routes, play choice, handoffs.
- `src/game/main.gd` — aim, reticle and arc, route art, key handling. `src/game/overlay.gd` — picker, route dropdown, status.
- `src/net/protocol.gd` — host-validated `play`, `route`, `flip_play`, `recall_call`, `throw`, `handoff` actions.
- Tests: `tests/test_passing.gd`, `tests/test_catching.gd`, `tests/test_routes.gd`, `tests/test_run_game.gd`,
  `tests/test_turnovers.gd` (interceptions), `tests/test_bots.gd`, `tests/game_flow.gd` (real J/Q/G/Space keys).

## Open issues
- #9 C07 Catch rules: toe-taps, batted balls, catch button, dive/jump catches
- #10 C09 Offense depth: formations, audibles, hot routes, pre-snap motion
- #11 C10 Throw readability: landing marker, aim-zoom
