# Replays

Feature-level doc: how this works for players **today** on `main`. Open work: GitHub issues labelled `area:replays` (listed below).

## Summary
Every match is recorded, and every play gets a one-line description of what happened. Big plays replay
themselves offline with a slow-motion finish. At any dead ball you can press V to watch the last play again,
scrub it frame by frame, jump between plays and highlights, and switch between four cameras. At FINAL, V plays
a highlight reel. The whole match is saved to disk and opens in the same viewer from the main menu, the
post-game overview or the command line. Online skip votes, a free camera and clip export are still open (#36).

## How it plays

### Automatic highlight replays (offline)
- Highlights are plays tagged TOUCHDOWN, INTERCEPTION, FUMBLE LOST, TURNOVER or SACK, plus any gain or loss of 20+ yards.
- About 1 s after the whistle (`AUTO_REPLAY_DELAY`), a highlight replays once at 1×, and its last 2 s run at 0.35×.
  The match is paused while it shows. V or Enter skips it, and a skipped play never auto-replays again.
- Not online (the match keeps running there), not in practice drills, and not after FINAL. The final whistle
  ends an auto highlight that's still on screen, so the summary and Players of the Game take over.
- `--auto-replay=0` turns it off. There's no Settings toggle yet (#36).

### Instant replay and the replay controls
| Input | Effect |
|---|---|
| V (gamepad Back) | outside a live play: replay the last completed play at 0.5×; at FINAL: the highlight reel; again: exit |
| Enter | back to the game (skips an auto highlight or the reel) |
| Space | pause / resume |
| `,` / `.` | step one frame back / forward (pauses) |
| Home | back to the start of the clip |
| Left / Right | previous / next play (in a match: that play's clip at the current speed) |
| H | next highlight (wraps) |
| [ / ] | halve / double speed (0.25× to 2×) |
| C | camera: Broadcast → End zone → Sky → Player |

- Held movement, sprint and block controls on the host apply again when the host closes the replay.
- Cameras: **Broadcast** is a zoomed shot from high on the near sideline, panning with the ball. **End zone** is
  behind the offense. **Sky** looks down from above. **Player** is the normal follow camera. The view cuts into a
  replay and on every camera change, then tracks smoothly.
- The replay overlay (`src/game/replay_overlay.gd`) shows:
  - a REPLAY / HIGHLIGHT / HIGHLIGHT REEL badge with a blinking dot
  - the speed (or SLOW-MO / PAUSED) and the camera ("BROADCAST VIEW")
  - the play summary ("TOUCHDOWN: PASS FOR 31 YD")
  - the play number, game clock, down and distance, and highlight count
  - a progress bar, and the key hints as a backed bar of key + action pairs above the scorebug (#116)
  The scorebug stays up. Live-only widgets are hidden during the replay and restored afterwards.
- Offline, the match is paused while you watch. Online, the host's match keeps running underneath, and your own
  input isn't sent while the replay shows.
- A joiner can replay the downs their client received. New downs keep recording while a replay is on
  screen, so a play that finishes during the clip is available the next time they press V.
- Players of the Game waits while a replay or the reel is on screen.

### Saved replays and the viewer
- At FINAL the match host (or offline player) saves `user://replays/<timestamp>.replay` and prints `REPLAY saved: <path>`.
  The host records the ongoing match even while watching or pausing an instant replay.
  `--replay-dir=DIR` overrides the folder.
- Open one from **Main menu → Replays** (newest first; test files skipped), the **Watch replay** button in the
  post-game overview, or `-- --replay=FILE`.
- The viewer rebuilds the match size and mode from the file and plays the whole match from the start at 1×.
  It uses the same keys as above. Left/Right and H jump within the continuous recording, and V exits.

### What is recorded
- 30 frames per second (`Replay.FRAME_EVERY` = every 2nd 60 Hz tick): phase, ball x/y/z, and each athlete's
  x/y plus a flags value. Facing, score and HUD state are not recorded.
- Flags (`Replay.F_*` bits) drive the replayed view's clips and poses (`player.gd` `_choose_replay_anim`), never the live sim:
  - 1 diving, 2 grounded: the dive and lying clips
  - 4 pushing in a block (engaged, below `PUSH_MAX_SPEED` in the sim): the upper-body push, and a backpedal when driven back (#374)
  - 8 reaching for a pass: the catch pose, hands to the replayed ball (#374)
  - 16 signalling a fair catch: the raised arm and the FAIR CATCH label (#198)
- Plays: a snap opens a play, and tackle, out of bounds, touchdown, incomplete or explosion closes it. Each play stores:
  - the line of scrimmage, the offense and the QB at the snap
  - pass or run (a throw makes it a pass)
  - tags from interception, recovery-turnover and sack events
  - yards (end spot minus LOS, clamped to the goal lines; the offense always attacks +y)
  - a summary, a highlight flag, and the clock/down context
  Label: `Play 7 (Q2 1:12, 3rd & 4 at OWN 30): TOUCHDOWN: pass for 31 yd`.
- File: zstd-compressed Godot `store_var` of `{version: 3, meta: {size, mode}, plays, frames}`. Loading never decodes objects.
  Version 3 only adds flag bits 4, 8 and 16 in the same float; the frame layout is unchanged. Version-2 files load with
  those bits off (no push, reach or signal). Version-1 files still load; their plays have no tags, so they have no highlights.

## Design decisions
- Playback is view-only: views read interpolated replay frames, and the sim is never rewound, so replay can't desync a match.
  Capturing on the authoritative tick keeps the saved match continuous as the host's view shows an earlier play.
- Plays are classified by the recorder from sim events, so the sim needs no replay-specific code and saved files carry their highlights.
  Joining clients use the host's snap and ruling events to bracket their locally interpolated frames.
- The push and catch bits are view rules evaluated on the sim (`player.gd` `replay_bits`). Push: engaged and slower than
  `PUSH_MAX_SPEED`, by the athlete's sim speed, so the replay's playback rate (half speed, slow-mo) can't turn it on or off.
  Catch: the live view's catch window (`watches_ball`, near where the ball comes down, the last `CATCH_LEAD` s of flight)
  without its camera gate. `main.gd` computes them on frame ticks only (`replay.frame_due()`) and passes them to
  `replay.capture`, so the recorder in `src/sim` stays free of `src/game`. The fair-catch bit comes straight from the sim
  (`fair_catch_id` while live).
- Facing isn't recorded (#209): a replayed view turns to its motion, except while the recording has it pushing, when it holds
  its facing (as live).
- Only highlights auto-replay. Replaying every play would train players to skip.
- No director AI picking cuts per frame: it needs a lot of tuning and belongs with the free-cam theater (#36).
- The replay overlay is its own CanvasLayer (`process_priority` 100, after the match overlay). It finds match-overlay
  widgets by name, so a rework of `overlay.gd` can't break replays.
- Scripted flow tests turn auto replay off (their timings assume the offline sim never pauses) and turn it on only
  for the B04a steps.

## Code and tests
- `src/sim/replay.gd` contains:
  - the recorder and the play classifier (summaries, tags, highlights)
  - playback: time, speed, seek, clips, slow-mo tail, reel, frame-step, progress, interpolation
  - save/load
- `src/game/main.gd` contains:
  - `toggle_replay`, `maybe_auto_replay`, `replay_key`, `stop_replay`
  - `replay_camera_pose` / `_replay_camera`, `replay_hud_text`
  - `open_replay`, `_save_replay`, `_render_replay`
- `src/game/replay_overlay.gd` is the broadcast replay overlay.
- `src/ui/main_menu.gd` has the Replays screen (`list_replays`) and the post-game "Watch replay" button.
- `src/ui/controls.gd` has the V / gamepad Back binding and the viewer help line.
- Tests:
  - `tests/test_replay.gd`: capture rate, bracketing, interpolation/seek/speed, save/load size, summaries/yards/context,
    highlight tags, slow-mo + reel, frame-step/progress, old files, the block / catch / fair-catch flag bits, v2 files
  - `tests/visual/replay_poses_test.gd`: a staged block, catch and fair catch, recorded and replayed: captures
    `replay-block-push`, `replay-catch-reach`, `replay-fair-catch`
  - `tests/visual/replay_arms_test.gd`: replayed views run, not the live sim's clips
  - `tests/game_flow.gd` (real keys): V replay, auto highlight after a TD, overlay, camera, frame-step, skip,
    no re-trigger, widgets restored, final whistle ends an auto highlight, the reel at FINAL with postgame waiting
  - `tests/test_out_of_game.gd`: replay listing

## Open issues
- #36 B04 Instant replay + highlight clips (remaining after B04a: online skip vote, free-cam theater, clip export, Settings toggle)
