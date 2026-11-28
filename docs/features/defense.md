# Defense

Feature-level doc: how this works for players **today** on `main`. Design/implementation detail: [architecture](../design/architecture.md). Open work: GitHub issues labelled `area:defense` (listed below).

## Summary
The defense picks one of nine calls (man, zone or blitz in base, goal-line or prevent shells) before the snap. The call
drives bot defenders' assignments and is drawn on the turf for your team only. Defenders line up locked in stance;
non-linemen double-tap Space to break stance and roam up to a visible barrier at the line of scrimmage. The offense
can't move at all before the snap. Tackling is in
[movement.md](movement.md); the pass rush is in [line-play.md](line-play.md).

## How it plays

### Calling a defense
- The picker opens each play (**Q** toggles it). Defense buttons: the nine calls plus **Repeat last** (your team's
  previous call). Any defender can change the call during pre-snap; the host validates it. No defensive calls in Chaosball.
- Each formation pre-selects `DefensivePlaybook.suggest()`:

| Situation | Suggested call |
|---|---|
| Within `DEFENSE_GOAL_LINE_RANGE` (5 yd) of the goal | Goal Line Zone |
| 3rd/4th down, `DEFENSE_PREVENT_DISTANCE` (15+) to go, `DEFENSE_PREVENT_TIME` (60 s) or less left | Deep Zone |
| Otherwise | Cover 2 |

| Call | Family | Shell |
|---|---|---|
| Cover 1 | man | base |
| Cover 2 | zone | base |
| Cover 3 | zone | base |
| Edge Blitz | blitz | base |
| Goal Line Man / Zone / Blitz | man / zone / blitz | goal line |
| Deep Man / Deep Zone | man / zone | prevent |

### Assignments (what bots do; humans are free)
- **DL:** always rush. On blitz calls the LB rushes too. Rushers chase the ball carrier.
- **Man calls:** CBs and LBs play man; safeties take deep zones. At the snap each receiver (left WR, right WR, RB) gets
  the nearest free CB/S/LB; LBs only take backs. An LB without a back spies the QB `AI_SPY_DEPTH` (6 yd) off and
  attacks at `AI_SPY_BLITZ_TIME` (3.5 s) or when the QB crosses the LOS.
- Man technique: trail where the receiver was `AI_COVER_REACTION` (0.25 s) ago, `AI_COVER_TRAIL` (0.8 yd) behind; a
  defender lined up deeper holds level and inside until the receiver passes him.
- **Zone calls:** each defender drops to a landmark: x = 72% of the way from the field center to his alignment, depth
  `DEFENSE_UNDER_DEPTH` (8 yd) or `DEFENSE_DEEP_DEPTH` (18 yd) past the LOS.
  - Deep players: safeties. Cover 3 puts one safety (or the LB with no safety) deep middle plus both CBs deep.
    Cover 2 in 3v3/5v5 uses the safety plus the right-side CB (both CBs with no safety). Deep Zone also sends CBs deep.
  - Goal-line shell: every zone at `DEFENSE_GOAL_DEPTH` (4 yd). Prevent shell: deep at `DEFENSE_PREVENT_DEPTH` (25), others 18.
- **Ball in the air:** the two nearest defenders break to the landing point; other zone players hold their spots; man
  defenders play the receiver's hands without sprinting. At a longer contested catch, a defender who lines up
  squarely with the ball can intercept by winning the closest-contact margin. See [catching](offense.md#catching).

### Pre-snap stance and roam
- Everyone lines up set (`set_lock`), both teams. A locked athlete can turn to face but not move.
- **Offense:** every offensive athlete, human or bot, stays set until the snap (or the kickoff kick). Space on
  offense snaps on one press, as before (#142).
- **Defense:** a **double-tap of Space** (gamepad A), two presses within `STANCE_DOUBLE_TAP` (0.35 s), breaks stance
  for LB, CB and S. One press does nothing. It is one-way for the play. DL can never break stance (#142).
- The double-tap is resolved on the pressing machine (`src/sim/double_tap.gd`, used by `main.gd`'s Space handler)
  into the same single `snap` action as before, which the host routes to `World.break_stance`. The protocol is
  unchanged. `World.can_break_stance` is the one predicate for both.
- A set LB/CB/S holds the shield stance; once roaming he stands in a plain idle, so roamers read differently from set teammates.
- **Roam hint (#183):** until you have roamed once this session, a set LB/CB/S sees `PRE-SNAP: SET  ·  SPACE ×2 TO ROAM`
  in the status pill (the key is your bound snap key, `Controls.key_name`, so a rebind shows). After your first double-tap
  roam the pill stays empty on later plays. The flag is a `static var` in `main.gd`: per session, it survives the
  scene reload between matches and resets on relaunch. Not saved in settings: one reminder per launch is cheap, and a
  settings key would add schema and save paths for a one-line hint. Pads still see the keyboard key (#309).
- Text HUD (`presnap_defense_prompt`): `PRE-SNAP: SET` (plus the hint above), then `PRE-SNAP: ROAMING`; DL see
  `PRE-SNAP (hold your stance)`. That debug text HUD is hidden in a match (overlay shows it only in the lobby and
  final), so the steady-state SET/ROAMING text isn't on screen; the pose is the cue (#307).
- Neutral zone: offense stops `NEUTRAL_ZONE_HALF` (0.5 yd) short of the LOS, defense 0.5 yd past it. The same clamp
  runs in client prediction, so there is no rubber-banding.
- A translucent hex barrier (`BARRIER_HEIGHT` 2.4 m) stands at the LOS. It brightens near athletes within
  `BARRIER_REVEAL_DIST` (3 yd), ripples where someone is stopped, and dissolves over `BARRIER_DROP_TIME` (0.3 s) at the snap.

### Assignment art (pre-snap, your team only)
- Gold tether = man matchup; teal disc = underneath zone; blue disc = deep zone; red line = rush. Your own is thicker.

## Design decisions
- Curated nine-call list with stable ids, families and shells over a flat list (hard to group) or a generator
  (too many combinations to balance).
- The call lives in the sim and rides match snapshots so late joiners see it; the server pre-selects the
  suggestion so the defense can just accept it.
- Cover 2 cut deep completions from 8 to 1 across 24 matched bot snaps versus legacy coverage.
- Calls ride the normal pre-snap action channel, not a separate timed match phase (extra state to sync, slower practice snaps).
  Assignments are drawn on the field so they read from the normal camera.
- Stance-lock plus Space (C08d) over always-free or auto-unlock on push (accidental breaks). One key routed by side:
  offense snaps, defense breaks stance.
- Whole offense frozen pre-snap, defense double-tap (#142, owner's call): "The entire offense should not be able to
  move before the play starts." Before this the offense lined up free (`set_lock` only on defense), so any human
  could walk a receiver anywhere behind the line. Locking by `set_lock = true` for everyone (not a separate offense
  check in `is_stance_locked`) keeps one rule for host step, client prediction and snapshots, and leaves a clean hook
  for pre-snap motion (#10): motion would clear one athlete's lock. That motion needs an explicit exception later.
- Double-tap over a single press: a stray Space (e.g. mashing to snap after switching sides) no longer pulls a
  defender out of stance. Resolving it client-side keeps the wire at one action; a host-side "two snap actions
  within N ticks" rule was rejected because latency jitter would stretch or shrink the window per player.
- The in-game hint is the settings label for now; a HUD "Space ×2 to roam" hint is #183.
- The barrier is one vertical wall. A recolored ground line is flat and doesn't read as "can't pass"; a two-wall
  neutral-zone box doubles the visual noise, and the camera sits behind one wall anyway. The proximity reveal keeps it
  near-invisible from the backfield, and the ripple gives feedback instead of an invisible stop.
- The barrier shader is unshaded with `depth_draw_never`, so it never hides athletes behind it, and uses plain
  uniform arrays because GL-compat has no instance uniforms.
- An earlier five-second call view with L/X/Y keys is gone; the picker stays open until Q or the snap.
- `AI_RUSH_DELAY` (2.5 s hold before pursuit) is defined in `tuning.gd` but no longer used.

## Code and tests
- `src/sim/defensive_playbook.gd` — call catalog and `suggest()`.
- `src/sim/world.gd` — `call_defense`, `defense_assignment`, `man_assignments`, `can_break_stance`, `break_stance`,
  `enforce_neutral_zone`. `src/sim/double_tap.gd` — Space double-tap window.
- `src/sim/ai.gd` — coverage, spy, zone drops, breaking on the ball, pursuit.
- `src/game/main.gd` — `_draw_defense_routes`, pre-snap prompt, Space double-tap. `src/game/overlay.gd` — picker.
- `src/game/art/los_barrier.gd` + `los_barrier.gdshader` — barrier view. `src/net/protocol.gd` — `defense`, `recall_call`, `snap` routing.
- Tests: `tests/test_defensive_playbook.gd`, `tests/test_presnap_roam.gd` (offense lock, double-tap),
  `tests/visual/presnap_locks_test.gd`, `tests/test_bots.gd` (man coverage, break on
  ball, press), `tests/test_turnovers.gd`, `tests/game_flow.gd` (Space on defense), `tests/net_client.gd`.

## Open issues
- #35 B02 DB press / jam mechanic
- #307 visible SET / ROAMING cue in the overlay
- #309 pad button names in key hints
