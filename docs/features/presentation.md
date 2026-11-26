# Presentation (graphics, camera, HUD, audio)

Feature-level doc: how a match looks and sounds for players **today** on `main`. Performance rules and budgets: `../optimization/README.md`. Layering (presentation reads sim state and owns no rules): `../design/architecture.md`. Open work: GitHub issues labelled `area:presentation` and `area:audio` (listed below).

## Summary
Matches are played in **Crater Bowl**, an original lunar stadium built inside a crater. Rigged CC0 athletes, a broadcast-style overlay and event effects (camera shake, tackle dust, touchdown fireworks) sit on top of a sim that knows nothing about them. The menus have a licensed music soundtrack. Matches have no sound effects yet.

The stadium screens show “PRIVATE MATCH LOBBY” while players are in the private lobby. When the
match starts, the screens show the score and the configured game clock.

## How it looks and plays
| Piece | What the player sees | Owner |
|---|---|---|
| Stadium | Bowl seating with an instanced crowd, LED ribbon boards, light towers, dome arches, jumbotrons, crater rim and regolith | `src/game/art/stadium.gd` |
| Field | Turf, lines, end zones, line-of-scrimmage barrier (see `defense.md`), sideline chains | `src/game/art/field_art.gd`, `los_barrier.gd`, `presentation.gd` |
| Athletes | Quaternius rig. Your team wears the CC0 mannequin and helmet, and opponents wear a custom uniform. Jersey numbers are `Label3D` on chest and back. Cosmetics are view-only. | `src/game/player.gd`, `art/character_art.gd`, `art/football_uniforms.gd` |
| Ball | Leather spheroid with laces, spiral, flight trail and a landing marker | `src/game/presentation.gd` |
| You | A ring and a small cyan chevron mark the controlled player. The chevron fades out when the camera is close (over the shoulder, POV). | `presentation.gd` |
| Camera | Follow camera behind your player. The mouse moves the aim range on the turf. | `src/game/main.gd` `_update_camera`, `_camera_target_yaw` |
| Effects | Camera shake on big events, tackle dust, touchdown fireworks, crowd excitement, jumbotron | `presentation.gd` |
| Overlay | Scorebug (possession, score, period and game clock, play clock, down and distance, timeout pips, ball spot, mode and mini field), status line, play-call picker, movement meters, hold-Tab scoreboard, event banners | `src/game/overlay.gd` |
| Play art | Routes, run paths, blocking targets and coverage drawn on the turf before the snap | `offense.md`, `defense.md` |
| Quality | `--gfx=low\|medium\|high`. Software rasterizers (llvmpipe etc.) auto-select `low`. | `src/game/art/quality.gd` |

**Scorebug.** The ball spot names the team whose territory contains the ball. The mini field reads
from the offense’s end toward the goal it attacks. Its cyan marker is the line of scrimmage and
its gold marker is the line to gain. The mini field appears during Classic scrimmage. Kickoffs and
conversion attempts have distinct labels. The period label follows the match rules, which use
halves today.

**HUD layout (#116).** The scorebug sits on the bottom edge at one fixed width: down & distance
takes the slack, so the bug doesn't jump when the play-clock cell hides at the snap. The movement
meters sit to its left. The status line is a small backed pill on the scorebug's top-left edge, so
nothing floats over the controlled player. After the whistle it summarizes the play in player words
(`TACKLED · +3`, `SACK · -5`, `OUT OF BOUNDS · +7`, `INCOMPLETE`, `INTERCEPTION`), not the raw whistle
code. The play-call picker uses the menu theme and is pinned top-right, over the sky. Replay key
hints are a backed bar of key + action pairs just above the scorebug. Post-game, only the featured
player stands on stage while their stat card is up, and the hint is a backed pill in the corner.

**Audio today:** only the menu soundtrack. It plays `assets/music/tracks.json` in order, loops the playlist, and has a "now playing" widget (prev / pause / next). Credits are in `assets/music/CREDITS.md`. Volume follows the music and master settings. A match plays no SFX, crowd or whistle (#22).

## Design decisions
- **Original look only.** It's a sci-fi lunar dome, never Gridiron's art or UI. Assets must be CC0 or compatible-license, logged in `ASSETS.md`.
- **Presentation never owns rules.** Views mirror sim state and are interpolated per render frame, so the sim stays deterministic and testable headless.
- **Rigged athletes are the most expensive thing on screen** (about 8 ms each on WSL's GL path). Measure before adding bones or characters. Details: `../optimization/README.md`.
- **HUD text refreshes at about 10 Hz.** Rebuilding scorebug strings every frame cost ~1 ms/frame (`../optimization/LOG.md`). Animated parts (throw bar, banners) still run per frame.

## Code and tests
- `src/game/presentation.gd`: ball, markers, effects, crowd, jumbotron
- `src/game/overlay.gd`: scorebug and HUD
- `src/game/player.gd`: athlete views
- `src/game/art/`: stadium, field, materials, shaders, quality presets
- `src/game/render_cache.gd`: shared low-poly meshes and materials (lint forbids default-tessellation meshes)
- `src/ui/music_player.gd`: menu soundtrack
- Tests:
  - `tests/render_budget.gd` and `tests/test_render_perf.gd` cap tris, instances, shadows, materials and skinned meshes (`./scripts/perf.sh`)
  - Visuals are verified with `./scripts/shot.sh` PNGs (`../TESTING.md`)
  - `tests/game_flow.gd` exercises the live overlay. `./scripts/visual_test.sh` checks and captures the scorebug in scrimmage, kickoff and conversion states.
  - `tests/visual/hud_polish_test.gd` asserts the fixed scorebug width (presnap, live, whistle), the dead-ball summary, the status pill clearing the scorebug, the themed picker pinned top-right and the meters beside the bug.

## Open issues
- #10 C10 Throw readability: landing marker, aim-zoom
- #12 C31 Who's who on the field: nameplates, rings, "you" marker
- #22 C16 Audio foundation + live play feed
- #31 Team voice chat (team-only, host-relayed)
- #34 C33 Team identity: names, colors, field branding, "ball on <TEAM> 19"
- #38 B06 Juice: hit-stop, screenshake, crowd stingers
- #43 C28 Commentary barks
- #44 C29 Events and variety: weather, time of day, rotating modes
