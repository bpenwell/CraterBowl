# Rules (classic)

Feature-level doc: how this works for players **today** on `main`. Open work: GitHub issues labelled `area:rules` (listed below).

## Summary
Classic Crater Bowl is two-way football with four downs to gain 10 yards, a PAT kick or 2-point scrimmage try,
and four timed quarters (2:30 each by default; #130). Kickoffs, punts and field goals are live kicking plays ([kicking.md](kicking.md)). Fields shrink with match size so 3v3 and 5v5 use the same rules engine as 7v7.
Chaosball changes most of this: see [chaosball.md](chaosball.md).

## How it plays

### Match sizes and field scaling (`src/sim/match_config.gd`, `src/sim/roster.gd`)
| Size | Slots per team (offense/defense) | Field (length × width) | End zones | Kickoff touchback | Timeouts per half |
|---|---|---|---|---|---|
| 3v3 | QB/LB, WR/CB, WR/CB | 60 × 30 | 8 yd | own 15 | 2 (`SMALL_MATCH_TIMEOUTS`) |
| 5v5 | + RB/S, C/DL | 80 × 40 | 10 yd | own 20 | 3 (`TIMEOUTS_PER_HALF`) |
| 7v7 | + OL/DL, OL/S | 100 × 53.33 | 10 yd | own 25 | 3 |

- Every athlete plays both ways; roles swap on change of possession. Formation x offsets scale with field width.
- 3v3 has no center: the QB holds the ball pre-snap and Space goes straight to a live play.
- The first down (10 yd) and the try distances (3 and 10 yd) do **not** scale with field size.
- Unknown sizes fall back to 7v7. Host picks 3/5/7 in the private lobby; offline via "Play vs bots".

### Downs and spotting (`src/sim/downs.gd`, `src/sim/match.gd`)
- 1st & 10 from the spot; "& Goal" when the line to gain would reach the goal line.
- The ball is spotted where the carrier is at the whistle (tackle or stepping out of bounds), clamped to
  the 1 and the opponent's 1. An incompletion returns to the line of scrimmage.
- **Forward progress** (#98): a tackle is spotted at the furthest point the carrier reached
  while in contact with an opponent (within 1.0 yd, window held 0.3 s after contact breaks), but only
  as far as opposing bodies actually pushed him back. Driven back = credited; retreating on your own
  (a QB drifting back with a rusher on him) = spotted where you are. The dead carrier is moved to the
  spot, and the overlay shows "FORWARD PROGRESS +N YD" when it gives back 0.5 yd or more. Touchdowns
  are unchanged. Numbers: `CONTACT_REACH`, `FORWARD_PROGRESS_GRACE`, `FORWARD_PROGRESS_BANNER` in
  `src/sim/tuning.gd`.
- **Driven out of bounds** (#103): the same forward-progress rule applies when the carrier goes out of
  bounds while the contact window is open. The spot moves forward to his forward progress, x stays where he
  crossed the sideline, and the same banner shows. Stepping out untouched, or after the window has closed
  (contact broke more than 0.3 s before), is spotted where he crossed. A carrier met in the field of play and
  driven back through his own end zone and out is spotted at his forward progress, so it's not a safety.
- Four downs; failing on 4th is a turnover on downs, new offense at the mirrored spot (`goal − spot`).
- **Deep QB dropbacks** (#252): the ball-carrying offense QB has full movement speed up to 14 yards behind the
  line of scrimmage. Speed tapers to 65% at 20 yards and stays there at greater depths. Climbing back toward the line
  restores speed. The limit covers normal movement, dashes, spins and dives before a forward pass. It applies on live
  Classic scrimmage plays and excludes kick plays, Chaosball and free practice.
- Snap: Space by any offensive human. If nobody snaps, the play clock auto-snaps. It defaults to 20 s (`Clock.PLAY_CLOCK`), and a hosted debug match can set every countdown with `--playclock=N` (#167).
- **One play clock** (#136): the scorebug's `PLAY :NN` is the countdown the snap obeys. A bot-run offense's play clock
  is its huddle (`HUDDLE_SECONDS` 5 s, kickoffs `AI_SNAP_DELAY` 2.5 s) and the bots snap or kick when it reads 0;
  a human offense gets the full 20 s and may snap any time before. An unattended kickoff gets the default kick
  (`KICKOFF_DEFAULT_POWER`) at 0. The play clock is hidden and doesn't run while it governs no snap: live and dead
  balls, the coin toss (its own `TOSS_WINDOW`) and its cutscene's fade back (`TOSS_OUTRO`, #129), FINAL. A timeout or the one-minute warning restarts it (a fresh huddle
  for bots). Clients show the same value: it is computed by `Match.play_clock_shown()` from snapshot state only.
- Next play starts `NEXT_PLAY_DELAY` (2.0 s) after the whistle; Enter skips the wait (offline or host only; it was R before #138).

### Penalties (`src/sim/penalties.gd`)
- **Flag pipeline** (#253): a foul is recorded during the down as one record (`Penalties.make`: type, team, side,
  spot, yards, replay or loss of down, player). `World.throw_flag` stores it in `World.flags` and emits `"flag"`;
  the HUD shows **FLAG** at once and the play goes on. At the dead ball `Match.next_play` sends the first flag
  through `Penalties.enforce`, the one enforcement path, and emits `"penalty"` with the ruling line.
- **The defense keeps a better result** (`Penalties.defense_declines`): an interception or lost fumble (including a
  return touchdown), a safety, a failed try or a turnover on downs stands, and the flag is declined. Otherwise the
  penalty is enforced and the play's result is wiped, touchdowns included.
- **Enforcement:** the penalty is measured from the previous spot (the line of scrimmage). An offensive foul moves the
  ball back, a defensive one forward. When the yardage is more than half the distance to the goal line it's walking
  toward, the ball goes **half the distance** instead. Spots clamp to the 1 like every other spot. The down is replayed
  (or spent, for loss-of-down fouls) with the line to gain unchanged; a 2-point try is replayed from further back. The
  clock stops.
- **HUD:** a yellow line above the scorebug shows the flag (`FLAG · ILLEGAL MAN DOWNFIELD · OFFENSE`) and then the
  ruling (`… · 10 YD · REPLAY 2ND DOWN`, `… · 6 YD, HALF THE DISTANCE · …`, or `… · DECLINED`) until the next snap.
- **Illegal man downfield** (blocking zone, #253): at a forward pass, an offensive **C or OL** more than
  `BLOCK_ZONE_DEPTH` (5 yd) past the line costs `BLOCK_ZONE_PENALTY_YARDS` (10 yd), replay the down. Exactly 5 yd is
  legal. QB, RB and WR are eligible and may be anywhere. These are the same roles the catch resolver excludes
  (`World.is_eligible_receiver`), so 3v3, which has no linemen, never draws the flag.
  - Only the throw moment counts. A lineman who releases downfield after the ball is out is legal; one who crossed
    before it is not.
  - A pass landing at or behind the line (a screen) is exempt.
  - The zone lifts once the ball has been carried past the line (a run). This also ends
    [passing eligibility](offense.md#passing) for the down (#312). A handoff behind the line keeps the zone active,
    so a halfback pass with a lineman downfield is still a foul. Kick plays, Chaosball and free practice have no zone.
  - Bot linemen respect the zone ([line-play.md](line-play.md#blocking-zone-253)).
- Offsides and false starts stay impossible by construction (the pre-snap neutral-zone clamp); that's the documented
  default on #7.

### Scoring and tries
| Event | Points | Then |
|---|---|---|
| Touchdown (carrier in bounds in the scoring end zone) | 6 (`TD_POINTS`) | scoring team attempts a try |
| Try for 1 (PAT kick from the 15, see [kicking.md](kicking.md)) | 1 | kickoff to the other team |
| Try for 2 (scrimmage snap from the 10) | 2 | kickoff to the other team |
| Field goal (see [kicking.md](kicking.md)) | 3 | kickoff to the other team |
| Safety (offense's own carrier downed or out behind its goal line) | 2 to the defense (`SAFETY_POINTS`) | the defense receives |

- During try pre-snap the offense presses **1** for the PAT kick or **2** for the scrimmage try (gamepad D-pad left/right).
  The PAT is the default. The two-point try scores when the trying team reaches the end zone, and both tries are untimed.
- A defensive touchdown (return of an INT or fumble) scores 6 for the defense, which then attempts the try.
  The returner is credited with INT or fumble return yards from the takeaway spot ([progression.md](progression.md#stats-srcsimstatsgd)).

### Turnovers
- **Interception:** a defender squarely at the ball (`INT_RADIUS` 0.6 yd) with no offensive receiver in reach.
  Within normal reach (`CATCH_RADIUS` 1.2 yd) he only breaks it up; a contested ball (defender within
  `CONTEST_MARGIN` 0.35 yd of the receiver's distance) is a breakup. The play stays live for the return.
- **Fumbles:** a dive tackle can strip the carrier. The chance is a hit-quality outcome
  (`World.fumble_risk`, numbers in `tuning.gd`): a base `FUMBLE_HIT_RISK` (8%) times force² (closing speed along the
  contact normal over `DIVE_SPEED + SPRINT_SPEED`), so even a fresh carrier can lose it on a big hit; plus a rear term
  that scales from 0 at `FUMBLE_BEHIND_DOT` to `FUMBLE_REAR` (25%) for a hit squarely from behind, or
  `FUMBLE_REAR_SPRINT` (97%) if the carrier was sprinting. Fatigue below 84% stamina multiplies the whole chance, up to
  ×(1 + `FUMBLE_FATIGUE_GAIN`) when exhausted; capped at `FUMBLE_MAX_RISK`. The roll is a deterministic hash of the athletes, play tick and impact counter. The ball bounces and rolls
  (`LOOSE_FRICTION`, `LOOSE_BOUNCE`); the nearest standing player within `RECOVER_RADIUS` (0.8 yd) of a low ball recovers.
  A loose ball out of bounds is dead where it crossed and stays with the team that last had it.
- After a takeaway the new offense starts at the mirrored spot; downed in its own end zone = touchback at the kickoff spot.

### Clock (`src/sim/clock.gd`)
- Every match plays four quarters, **Q1-Q4** (#130). Quarters are 2:30 by default (`QUARTER_LENGTH`), so a game
  runs the same 10 minutes the old two 5:00 halves did. In a private lobby the host presses **H** to cycle the
  quarter length: 1, 2, 2.5 or 3 minutes. There is no halves format. Everyone sees the length in the lobby and the
  quarter and time remaining on the scorebug, the Tab scoreboard, the stadium screens and replay labels.
- The game clock runs during live plays. It **keeps running between plays** only after an in-bounds tackle by the
  original offense short of the line to gain, before 4th down, with no change of possession. Incompletions,
  sideline stops, first downs, scores, turnovers and tries stop it.
- **One-minute warning** once per half, in Q2 and Q4. A live play finishes first. A crossing
  between plays stops the clock at 1:00.
- **Timeouts:** T, outside live play, by either team; the scorebug shows pips. Resets the play clock if pre-snap.
  Counts reset at halftime. No gamepad binding.
- A period can end between snaps when the running clock hits 0:00. A play in progress at 0:00 finishes, and a touchdown on it still gets its try.
- At the end of Q1 and Q3, the next period starts with the same possession, down, spot and remaining timeouts.
- The coin toss winner chooses to receive or kick the opening kickoff. At halftime after Q2, the other team receives.
- After Q4 the higher score wins. A tie stands.
- **Switching ends** (#89): teams switch the goal they attack every period, after Q1, Q2 and Q3 (Q2 -> Q3 is
  halftime). Possession, spot, down and line to gain carry over unchanged. Because the view is
  offense-relative, the switch shows on the field: the end zone behind the offense is painted and named for the end
  it defends this period (HELIOS defends the HELIOS end in odd periods), and a **SWITCH ENDS** banner shows at each
  period change. The paint also follows possession within a period (#93).

## Design decisions
- Offense-frame yards (0 = own goal line, `goal` = field length) keep every rule direction-free; the view mirrors the field.
- Switching ends is derived (`Match.defended_end(team)` from `Clock.period()`), not stored, so it needs no snapshot field
  and replays/clients agree automatically. Rotating the stadium 180° was rejected: the turf shader paints by world
  position and the stadium is symmetric, so re-tinting the end zones and swapping their names (`FieldArt.orient_ends`,
  change-driven from `presentation.gd`) is the whole cue.
- The scrimmage try reuses the regular downs engine. The PAT uses the field goal kick.
- Play-clock expiry auto-snaps, so an AFK player can't stall a lobby.
- The authoritative clock stores the configured countdown length so it carries through lobby start, each down and each period.
- One clock, not two (#136). Bots used to snap on a private timer (`AI._presnap_t`) while the scorebug counted a
  20 s clock they ignored, so you'd see `PLAY :16` (`:18` on a bot kickoff) as the ball went, and a bot kickoff after
  the coin toss went the instant the toss was chosen because that timer had run through the toss. Now the bots' huddle
  *is* the play clock (`Match.huddle` caps it, `Match.tick`'s snapper does the bots' snap, so kickoff depth still varies).
  Rejected: keeping both timers and only lining up their starts (still two sources that drift on timeouts, the warning
  and the toss); hiding the clock whenever bots have the ball (the defense loses the one cue for when the ball goes);
  a delay-of-game penalty at 0 (a later rules decision; auto-snap stays).
- The shown value is `ceil(play_clock - 1 ms)`: snapshots carry the clock as float32, and a plain `ceil` put the client
  one second behind the host at every whole-second boundary.
- Forward progress is the furthest point in contact, capped by how far opponents pushed the carrier. Whistling on
  first contact was rejected because it kills the contact game (spins, breaking a lean, the dive). The uncapped
  furthest point was rejected because a QB drifting back with a rusher on him would get the yards back on a sack.
- Out of bounds uses the tackle's forward-progress rule as is (#103): same contact window, same push cap, same
  numbers. Otherwise the defense gets a free shove-out: a carrier driven back three yards and out loses those yards,
  and the same hit followed by a dive keeps them. Rejected: spotting at the furthest in-bounds point whether or not
  he was touched (credits a carrier who backpedals out on his own), and a separate out-of-bounds window (a second
  rule to tune that could disagree with tackles).
- The dropback taper follows depth in offense-frame yards so both offenses have the same window to move in the pocket.
  A smooth ramp avoids a sudden speed change when crossing a yard line. The 65% floor gives the rush a closing advantage
  while keeping enough control to move sideways and climb back toward the line. Host and client derive the scale from
  the same movement step and existing snapshot fields.
- Fields scale with match size so 3v3 isn't played on a lonely 100-yard field.
- The clock once ran only during live plays, for predictable pacing. It now also runs after short in-bounds tackles
  so reaching the sideline matters. Timeouts reuse existing dead-ball phases instead of a separate timeout state,
  which would be one more state for every client.
- Quarters are a counter inside the halves, which stay the unit for rules. Reusing halftime at Q1 and Q3 would reset
  the drive and hand out extra timeouts, so those boundaries only reset the clock.
- **Quarters only** (#130, owner: "I don't like H1 is showing… we should have Q1/2/3/4"). `Clock.quarter` is the one
  source of truth and `half` is derived from it, so `label()` can only build `Q1`-`Q4`. Rejected: keeping halves as a
  hidden rules path that only *displays* quarters, because the shown time would not match the period (a 5:00 "Q1")
  and two rule sets would stay alive for one used format. Legacy inputs are normalized instead: a zero quarter
  length (the old halves marker) falls back to 2:30, a pre-quarters snapshot's half maps to Q1/Q3, and an old
  lobby's `"quarters": false` reads as quarters. 2.5 min was added to the quarter lengths so the default game keeps
  its 10 minutes; 2 (8 min) or 3 (12 min) would have changed pacing.
- **Penalties (#253).** The flag is thrown at the release and the play goes on; the penalty is enforced at the dead ball.
  Rejected: blowing the play dead at the throw (the defense loses its interception, and a ball dying in the air reads
  as a bug), and checking the zone every frame (it would flag legal run plays, where blocking downfield is the point).
  The defense's choice is automatic (it keeps a takeaway, safety, failed try or turnover on downs) because an
  accept/decline prompt would stall an arcade game. The HUD says DECLINED so nobody wonders where the flag went.
- A "blocker" is a C/OL by **position**, whether or not he's engaged. The issue says "a blocker more than 5 yards
  downfield", and position is what a player can see and control; whether he's engaged in a block flickers frame to
  frame. Eligibility matches the catch resolver (owner, #253).
- Flags and rulings travel on the existing reliable event channel (`"flag"` world event, `"penalty"` match event), so the
  snapshot (about 2 bytes under its MTU budget, #193) didn't grow. New event names changed the wire, so
  `Protocol.VERSION` went 3 → 4.
- Half the distance follows the real rule. Spots still clamp to the 1 (the downs engine never spots inside it), so a foul
  on the 2 walks back to the 1 and one on the 1 doesn't move.
- The bots' end-of-half prevent defense (Deep Zone) keys off the time left in the **half**
  (`Clock.half_remaining()`), so it still comes at the end of Q2/Q4, not at the end of every quarter.
- The rear strip is near-certain so fumbles stay readable: don't sprint with a defender closing from behind.
- Fumbles are a hit-quality outcome rather than a fatigue special case (#99): fresh carriers have a small base chance
  that grows with hit speed, and a hit from behind raises it in proportion to the angle (sprinting or not), so a
  carrier jogging away from a pursuer is at risk too. Fatigue stays a multiplier, so tired carriers still fumble most.

## Code and tests
- `src/sim/match.gd` — series flow: scoring, tries, kickoffs, turnovers, safeties, halves, timeouts.
- `src/sim/downs.gd` — downs, line to gain, spot clamping, down & distance label.
- `src/sim/clock.gd` — game/play clock, quarters (Q1-Q4 only), one-minute warning, timeout counts.
- `src/sim/world.gd` — whistles (tackle, out of bounds, touchdown), catches/interceptions, fumbles and loose balls,
  the blocking zone (`blocking_zone_active`, `_check_blocking_zone`, `throw_flag`).
- `src/sim/penalties.gd` — flag records, `enforce` (the one enforcement path), the defense's option, ruling text.
- `src/sim/match_config.gd`, `src/sim/roster.gd`, `src/sim/field.gd` — sizes, slots, field geometry.
- `src/net/lobby.gd` (size and quarter-length settings), `src/net/protocol.gd` (period snapshots and host-validated `try`/`timeout` actions).
- Tests: `tests/test_downs.gd`, `tests/test_scoring.gd`, `tests/test_match.gd`, `tests/test_clock.gd`,
  `tests/test_turnovers.gd`, `tests/test_tackling.gd`, `tests/test_match_sizes.gd`, `tests/test_field.gd`, `tests/test_switch_ends.gd`, `tests/game_flow.gd`,
  `tests/test_lobby.gd`, `tests/test_protocol.gd`, `tests/test_play_clock.gd`, `tests/visual/switch_ends_test.gd`,
  `tests/visual/play_clock_test.gd`, `tests/visual/quarter_clock_test.gd` (scorebug, Tab board and stadium screens at Q1 2:30).
- `tests/test_penalties.gd` (flag, boundaries, eligibility, run/screen exemptions, enforcement, half the distance,
  declines, bot zone discipline), the `tests/game_flow.gd` blocking-zone step (frames 16400-16620) and
  `tests/visual/penalty_flag_test.gd` (the HUD ruling) cover penalties (#253).
- `tests/test_qb_dropback.gd`, `tests/visual/qb_dropback_test.gd` cover authoritative and predicted speed plus keyboard-driven dropbacks.

## Open issues
- #6 C04c Switching ends, mercy rule and clock actions (parent; #89 switching ends in review)
- #90 Host mercy rule (28-point lead)
- #91 Spike and kneel clock actions
- #7 C05 Competitive rules: eligibility, grounding, blocking zone, QB slowdown
- #253 Blocking zone and penalty flags (in review)
- #254 Intentional grounding under pressure
- #8 C06 Spotting: forward progress, return yards, fumble variety (#103 out-of-bounds forward progress in review)
- #16 B10 Overtime for tied games
- #39 B08 Tuning data file editable without code
- #40 C25 Momentum / "on fire"
- #42 C27 Backyard rules / trick plays
- #192 Replays saved before #130 still label plays H1/H2
