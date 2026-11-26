# Defense

Feature-level doc: how this works for players **today** on `main`. Design/implementation detail: [architecture](../design/architecture.md). Open work: GitHub issues labelled `area:defense` (listed below).

## Summary
The defense picks one of nine calls (man, zone or blitz in base, goal-line or prevent shells) before the snap. The call
drives bot defenders' assignments and is drawn on the turf for your team only. Defenders line up locked in stance;
non-linemen press Space to break stance and roam up to a visible barrier at the line of scrimmage. Tackling is in
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
  defenders play the receiver's hands without sprinting.

### Pre-snap stance and roam
- Every defender starts set (`set_lock`). A locked defender can turn but not move.
- **Space** (gamepad A) on defense breaks stance for LB, CB and S. It is one-way for the play. DL can never break stance.
- A set LB/CB/S holds the shield stance; once roaming he stands in a plain idle, so roamers read differently from set teammates.
- HUD: `PRE-SNAP: SET`, then `PRE-SNAP: ROAMING`; DL see `PRE-SNAP (hold your stance)`.
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
- The barrier is one vertical wall. A recolored ground line is flat and doesn't read as "can't pass"; a two-wall
  neutral-zone box doubles the visual noise, and the camera sits behind one wall anyway. The proximity reveal keeps it
  near-invisible from the backfield, and the ripple gives feedback instead of an invisible stop.
- The barrier shader is unshaded with `depth_draw_never`, so it never hides athletes behind it, and uses plain
  uniform arrays because GL-compat has no instance uniforms.
- An earlier five-second call view with L/X/Y keys is gone; the picker stays open until Q or the snap.
- `AI_RUSH_DELAY` (2.5 s hold before pursuit) is defined in `tuning.gd` but no longer used.

## Code and tests
- `src/sim/defensive_playbook.gd` — call catalog and `suggest()`.
- `src/sim/world.gd` — `call_defense`, `defense_assignment`, `man_assignments`, `break_stance`, `enforce_neutral_zone`.
- `src/sim/ai.gd` — coverage, spy, zone drops, breaking on the ball, pursuit.
- `src/game/main.gd` — `_draw_defense_routes`, pre-snap prompt. `src/game/overlay.gd` — picker.
- `src/game/art/los_barrier.gd` + `los_barrier.gdshader` — barrier view. `src/net/protocol.gd` — `defense`, `recall_call`, `snap` routing.
- Tests: `tests/test_defensive_playbook.gd`, `tests/test_presnap_roam.gd`, `tests/test_bots.gd` (man coverage, break on
  ball, press), `tests/test_turnovers.gd`, `tests/game_flow.gd` (Space on defense), `tests/net_client.gd`.

## Open issues
- #35 B02 DB press / jam mechanic
