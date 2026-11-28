# Line play

Feature-level doc: how this works for players **today** on `main`. Design/implementation detail: [architecture](../design/architecture.md). Open work: GitHub issues labelled `area:line-play` (listed below).

## Summary
Blocking is a sim of body circles plus engagement pairs. A blocker who meets a defender face-on holds him for up to
1.5 s, dragging most of his movement along. Bot linemen pass-protect or run-block automatically. Humans block by
holding right mouse (a "shield"). Rushers beat blocks by waiting out the hold or with a spin or dash.

## How it plays

### Bodies
- Every standing athlete is a circle of `BODY_RADIUS` (0.45 yd); overlaps push both apart equally. Grounded
  (diving or recovering) athletes don't collide.

### Engagement rules
- Only the team in possession blocks, only during live play, and never the ball carrier.
- A block forms when the blocker faces the defender (`ENGAGE_FACING_DOT` 0.3) within `ENGAGE_DIST` (1.0 yd), and the
  defender isn't grounded, spinning, already engaged or immune.
- **Face to face (no blocks from behind).** A defender moving faster than 1 yd/s (`ENGAGE_FOE_MOVING`) is blocked
  only if the blocker is ahead of his path: his velocity . the direction to the blocker >= `ENGAGE_FOE_HEADING_DOT`
  (0.2, about 78 deg either side). A standing defender can be blocked from any side. It used his velocity, not his
  `facing`: facing defaults to (0, 1) and a defender who hasn't moved yet faced away from the line. Before this,
  a blocker chasing a defender or running beside him the same way locked on, and the pair slid downfield together
  with the block clip's arms out. In a 108 000-tick all-AI match (63 vs 57 plays): blocks 154 to 135, same-direction
  pairs 12 to 1, from behind 5 to 0; sacks 25 to 29, yards/play -0.69 to -2.01 (single sample, noisy). At 0.0 (beside
  allowed): same-direction pairs 14, yards/play -0.08. The owner play-tested 0.2 and kept it (2026-11-27). `tests/test_blocking.gd`
  `test_no_block_from_behind_or_running_alongside`.
- While engaged the defender's movement each step is 70% the blocker's and 30% his own (`BLOCK_DRIVE`).
- The block ends after `BLOCK_HOLD` (1.5 s), when the blocker can't act or gets the ball, or when either player
  dashes or spins. The defender is then immune for `BLOCK_IMMUNITY` (0.75 s) and the blocker can't re-engage for
  `BLOCKER_BEATEN` (1.5 s).
- All active blocks end when the ball goes dead. Both players leave the push animation during the dead-ball interval.
- Who may block: C and OL any time; skill players only downfield (after a catch or once the carrier is past the LOS);
  after a takeaway anyone on the returning team. A human holding the shield can block from any position.

### Human blocking (shield)
- Hold **right mouse** while your team has the ball and you aren't the carrier. You move at `BLOCK_SPEED`
  (2.8 yd/s), can't sprint, and keep your facing (so you can backpedal while squared up).
- Without the shield a human never starts a block. "Human" means the athlete's input carries the explicit
  `World.HUMAN` flag that `main.gd` sets for the local player and every joined peer (#62); bots auto-engage. Releasing it drops the block, and so does drifting more than
  about 1.12 yd (`ENGAGE_DIST` + 0.12) from the defender.
- No gamepad binding for the shield yet.

### Pass protection (bots)
- Each bot C/OL targets the nearest standing defender within `PROTECTION_RANGE` (8 yd), moves to a spot 0.9 yd in
  front of him toward the ball carrier, and faces him. Pre-snap art draws a grey line from each blocker to that target.

### Run blocking (bots)
- On a run call each C/OL is assigned, at the snap, the defender closest to a landmark shaded `RUN_BLOCK_LANE_WEIGHT`
  (55%) from the blocker toward the called lane, within 8 yd, one defender per blocker. Pre-snap art shows these pairs.

### Blocking zone (#253)
- C and OL may not be more than 5 yd (`BLOCK_ZONE_DEPTH`) past the line when a pass is thrown, or it's
  illegal man downfield: 10 yd and the down is replayed ([rules.md](rules.md#penalties-srcsimpenaltiesgd)).
  A human lineman can go anywhere, but going too deep before the throw draws the flag.
- Bot C/OL respect the zone while it's active (`World.blocking_zone_active()`: until a pass or until the ball is
  carried past the line). Within `AI_BLOCK_ZONE_MARGIN` (1 yd) of its edge they stop moving downfield, even to
  follow a defender they were blocking, and they step back if a collision shoves them past it.

### Pass rush
- DL bots (and the LB on blitz calls) sprint at the ball carrier, leading him by up to 0.6 s, and dive within
  `AI_DIVE_RANGE` (2.0 yd).
- A human rusher can wait out the 1.5 s hold, or spend a move charge: **Q/E** spin or **R** dash both break the block,
  and a spinning player can't be engaged. See [movement.md](movement.md).
- A bot QB drifts away from any rusher within 4 yd (never past the LOS) and throws early under `AI_QB_PRESSURE` (3 yd).

## Design decisions
- Sim circles plus engagement pairs over Godot physics (non-deterministic) or a rock-paper-scissors minigame
  (that is #15).
- A timed shed plus immunity makes a block buy a fixed, readable amount of time.
- The world clears engagement pairs as it enters DEAD, so every play-ending path releases them before
  the ruling reaches the view. This cleanup does not award a shed.
- The beaten-blocker cooldown is longer than the defender's immunity because a lone C could re-block one LB forever.
- Receivers don't auto-block during a pass play, so they run routes instead of locking onto the nearest defender.
- Bot linemen hold the zone edge in `AI.think` after every other decision (`_respect_blocking_zone`) rather than inside
  `_protect`/`_approach_block`, so one clamp covers pass protection, run blocking and holding a block.
- Human shield and spin/dash shedding came with the live-controls rework (commit `ec09b1e`); before that blocking was
  automatic for everyone.

## Code and tests
- `src/sim/world.gd` — `_can_block`, `_can_be_blocked`, `_step_blocks`, `_release_block`, `_resolve_collisions`,
  `protection_target`, `run_block_assignments`, `evade`.
- `src/sim/player_motion.gd` — shield speed and frozen facing. `src/sim/athlete.gd` — `blocking`, engagement fields.
- `src/sim/ai.gd` — `_protect`, `_approach_block`, `_pursue`, `_qb_pocket`, `_respect_blocking_zone` (#253).
- `src/game/main.gd` — right-mouse shield input, `World.HUMAN` flag on local and peer inputs, protection/run-block art.
- Tests: `tests/test_blocking.gd`, `tests/test_live_controls.gd` (shield, spin shed), `tests/test_run_game.gd`
  (run-block targets), `tests/test_training.gd` (blocking station), `tests/visual/peer_human_block_test.gd`
  (host flags a joined peer's lineman as human), `tests/test_penalties.gd` (bot linemen stay inside the blocking zone).

## Open issues
- #15 B01 Line play minigame (leverage / hand-fighting timing, shield resource)
