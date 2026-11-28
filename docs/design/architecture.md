# Architecture

Scope: how Crater Bowl is put together — layers, entry points, the tick loop, determinism,
tuning, persistence, and the path for adding a rule end to end. Feature-level behavior lives in
`docs/features/` (one file per area). Netcode details: `docs/design/netcode.md`. Performance rules:
`docs/optimization/README.md`. Test tiers and harnesses: `docs/TESTING.md`.

## Layers

| Dir | Role | Depends on | Rules |
|---|---|---|---|
| `src/sim/` | Game rules: `World` (one play), `Match` (downs, score, clock), `AI`, `Roster`, `Stats`, `Drills`, `Replay`, `Ranked`, `Leaderboard`, `Cosmetics`, `tuning.gd` | nothing outside `src/sim` | `extends RefCounted`, no `Node`, no `Input`, no wall clock. Deterministic. Unit-tested headless. |
| `src/net/` | Transport (`net_session.gd`, `mm_*.gd` are `Node`s) plus pure codecs/rules (`protocol.gd`, `lobby.gd`, `matchmaker.gd`, `client_predictor.gd`, `interpolator.gd`, `invite_code.gd`, `lobby_registry.gd`) | `src/sim` | The pure files are RefCounted and unit-tested like sim. |
| `src/game/` | Presentation and input glue: `main.gd` (the match scene), `player.gd` (athlete view), `presentation.gd` (FX, ball model, camera shake), `overlay.gd` (scorebug/HUD), `art/` (field, stadium, shaders, `quality.gd`) | sim, net, ui | Reads sim state; owns no rules (`presentation.gd`, `player.gd` headers say so). |
| `src/ui/` | Out-of-game: `main_menu.gd`, `launch.gd` (autoload `Launch`), `settings_store.gd`, `controls.gd` (rebinding, gamepad), lobby/post-game stages, server browser, music | sim (profile/ranked reads), net (UPnP, browser) | Menu choices become launch options; see below. |

Purity is enforced by `scripts/lint.sh` (run by `check.sh`): it greps `src/sim` for engine, time and random calls and fails with "src/sim must be pure RefCounted…". `tools/lint.gd` separately verifies every script compiles. The
only clock use in sim is `ranked.gd` turning a *passed-in* unix time into a season id.

```
 scenes/menu.tscn (main_menu.gd)                CLI: godot -- --host --size=5 ...
        │ Launch.start_game(opts)                        │
        ▼                                                ▼
   Launch.options ──────────── merged by main._cli_args() ──────────┐
                                                                     ▼
 scenes/main.tscn ─ main.gd ──────────────────────────────────────────────────────
   _physics_process (60 Hz)                       _process (display rate)
     input ─► do_action ─► protocol.apply_action    _render_frame(): views.interpolate(f)
     ai.think + net.inputs ─► world.step(inputs,dt)  presentation.gd / overlay.gd read state
     series.tick ─► world/match signals ─► stats, replay, pres.on_event, net.broadcast_event
     net.broadcast_snapshot every 2nd tick            ▲
        │                                            │ _render(): views.sync() per tick
        ▼                                            │
   src/net (NetSession, ENet)                 src/sim (World, Match, AI, Roster ...)
```

## Entry points

- `project.godot`: `run/main_scene = scenes/menu.tscn`; one autoload, `Launch` (`src/ui/launch.gd`);
  user dir `crater-bowl`.
- `main_menu.gd:_ready` jumps straight to `scenes/main.tscn` when `Launch.should_skip_menu()` is true:
  headless display, or any user arg other than `--settings-file=`, `--no-migrate`, `--menu`.
- **CLI flags == menu choices.** `Launch.start_game(opts)` stores `opts` in `Launch.options` and changes
  scene; `main.gd:_cli_args()` parses `OS.get_cmdline_user_args()` (`--key=value` / `--flag`) and merges
  `Launch.options` over them. Tests and the menu therefore hit the same code paths.
- `main.gd:_setup_net()` dispatches on the merged options: `--matchmaker` (headless MM server),
  `--queue=casual|competitive`, `--host`, `--join=CODE|IP`; otherwise offline vs bots. Other options
  read in `main.gd:_ready`: `--size`, `--mode`, `--practice`, `--replay`, `--name`, `--ranked`,
  `--equip`, `--leaderboard[=pos]`, and the `--*-file` / `--replay-dir` path overrides (persistence below).

## main.gd's role

`main.gd` is the match-scene composition root (~1.4k lines). It owns one `World`, one `Match`
(`series`), `Roster`, `AI`, `Stats`, `Replay`, the views, camera and HUD, and an optional `NetSession`
or `MMClient` child. Key functions:

| Function | Does |
|---|---|
| `configure(size, practice, mode)` | Rebuilds field, roster, sim, views. Called at start, from the lobby start, and on clients when the host's size/mode differs. |
| `do_action(action)` | Single funnel for human actions: client → `net.send_action`, else `Protocol.apply_action(series, controlled_id, action)`. |
| `_physics_process` | Lobby → `_step_lobby`; replay → `replay.advance`; client → predict + interpolate; host/offline → `_step_authoritative`. Then `replay.capture` and `_render`. |
| `_step_authoritative` | `series.tick`, drill tick, auto next play, drain peer actions, `ai.presnap_tick` + `ai.think`, overlay human inputs, `world.step`, snapshot every `SNAPSHOT_EVERY` ticks. |
| `_on_world_event` / `_on_match_event` | Fan sim events to presentation, HUD text, stats; on host re-broadcast to clients; at `final` record leaderboard/ranked/XP and post-game. |

## Tick model

- **Sim: fixed 60 Hz.** The rate has one source: `src/sim/tick.gd` (`Tick.RATE`, `Tick.HZ`, `Tick.DT`).
  `project.godot` sets `physics/common/physics_ticks_per_second` to the same value explicitly; sim runs only
  in `_physics_process(delta)`. Tests force it with `--fixed-fps 60`, and `test_determinism.gd` steps `dt = 1/60`.
- **Render: display rate.** `_render()` (per tick) calls `views.sync()` and `_place_ball` to record
  targets; `_render_frame()` (per frame, from `_process`) interpolates by
  `Engine.get_physics_interpolation_fraction()`. Big jumps snap (`PlayerNode.TELEPORT_DIST`).
- **Net:** snapshots every 2 ticks (30 Hz); `Replay` captures every 2 ticks (30 Hz).
- Tick <-> seconds conversions derive from `Tick`: `interpolator.gd` `TICK_RATE`, `replay.gd` `FPS`
  (`Tick.HZ / FRAME_EVERY`) and `SLOWMO_TAIL`, `world.gd` ball look-ahead and impact-roll tick, `player.gd` timers.
  `tests/test_tick.gd` fails if `project.godot`, the engine or those sites diverge from `Tick.RATE` (#61).
  Changing the rate means editing `tick.gd` and `project.godot` together (the test enforces it); test
  harnesses still hard-code `1/60` and `--fixed-fps 60` (#301).

## Determinism

- `World.step(inputs, dt)` is a function of state + inputs. The one RNG (`world.gd:_impact_rng`,
  fumble rolls) is seeded with a constant in `_init`. AI is documented deterministic (`ai.gd` header).
- `tests/test_determinism.gd` runs two all-bot games (7v7 classic 90 s, chaosball 60 s) and compares
  per-second fingerprints (phase, score, ball, LOS, every athlete's position/velocity). Any perf
  refactor of `src/sim` must keep it green — a diff means behavior changed.
- Client prediction relies on `World.predict_step` producing the same movement as `World.step` for one
  athlete (`tests/test_netcode.gd:test_prediction_leads_then_matches_server`).
- Replays do **not** depend on determinism: `replay.gd` records positions, not inputs.
- Human vs bot input is an explicit flag: `world.step` applies human blocking rules (no auto-engage
  without the shield, releasing the shield drops the block) iff the input has `World.HUMAN: true`
  (`World.is_human_input`). `main.gd` sets it on the local player's input and, on the host, on each
  peer's input after `Protocol.sanitize_input` (the wire never carries it). `ai.think` never sets it,
  so a `block` key on a bot input doesn't change bot rules (#62).

## Tuning

All feel numbers (speeds, stamina, field size, ball, run game, AI timers, Chaosball scales) are
`const`s in `src/sim/tuning.gd` (preloaded as `T`). Smaller rule tables live next to their rules:
`routes.gd` (playbook/routes), `defensive_playbook.gd`, `match_config.gd` (sizes), `lobby.gd`
(`SIZES`, `HALF_MINUTES`), `matchmaker.gd` (queue waits, rating windows). Making tuning data-driven is #39.

## Persistence (`user://` = `<data dir>/crater-bowl`)

| File | Format | Owner (class) | Written by |
|---|---|---|---|
| `settings.cfg` | ConfigFile | `ui/settings_store.gd` | `Launch.save_settings()` (menu). Headless runs ignore it unless `--settings-file` is passed. |
| `profile.json` | JSON | `sim/cosmetics.gd` | `main.gd:_apply_award` (XP/achievements at final), `--equip`, menu `_equip` |
| `leaderboard.json` | JSON | `sim/leaderboard.gd` | `main.gd:_record_leaderboard` — host/offline only, at final |
| `ranked.json` | JSON | `sim/ranked.gd` | `main.gd:_record_ranked` — host only, ranked matches |
| `training.json` | JSON | `sim/drills.gd:save_bests` | practice drills (personal bests) |
| `replays/*.replay` | zstd-compressed | `sim/replay.gd:save` | `main.gd:_save_replay` at final (non-drill) |
| `.migrated` | text | `Launch.migrate` | first non-headless run (copies the legacy "Fourth & Long" dir) |

Every path is overridable from the CLI (`--settings-file`, `--profile-file`, `--leaderboard-file`,
`--ranked-file`, `--training-file`, `--replay-dir`); tests use these, and `check.sh` also isolates
`XDG_DATA_HOME`. Leaderboard and ratings are local to whoever hosted, which is why progression isn't
trustworthy yet (#28).

## Adding a rule or feature end to end

1. **Rule** in `src/sim/` (usually `world.gd` for in-play rules, `match.gd` for series/score/clock),
   numbers in `tuning.gd`. Emit a `world.event` / `series.match_event` for anything the UI or stats react to.
2. **Unit test** in `tests/test_<area>.gd` (extends `tests/test_case.gd`; `scripts/test.sh` picks up
   every `test_*` method). Keep `test_determinism.gd` green.
3. **Player action?** Add it to `protocol.gd:sanitize_action` (whitelist + validation) **and**
   `protocol.gd:apply_action` (side/phase checks); send it via `main.gd:do_action`. Unknown actions are
   silently dropped. See `docs/design/netcode.md`.
4. **New sim state clients must see?** Add it to `protocol.gd:encode_snapshot` and `apply_snapshot`
   (with a `.get()` default), and extend `tests/test_protocol.gd`.
5. **Input** in `main.gd:_unhandled_key_input` / `_input`; rebindable keys go in `src/ui/controls.gd`.
6. **Visuals** in `src/game/` (`presentation.gd:on_event`, `overlay.gd`, `player.gd`), interpolated per
   `docs/optimization/README.md`. Check with `./scripts/shot.sh`.
7. **Flow test**: a step in `tests/game_flow.gd` driven through the real input handler; networked
   behavior extends `tests/net_client.gd` / `net_host.gd` (`scripts/net_test.sh`); menu paths extend
   `tests/menu_flow.gd`. Gate: `./scripts/check.sh`.
8. **Docs**: feature doc in `docs/features/`, design doc here if it adds a subsystem or protocol.

## Open issues

- #28 C22 Trustworthy progression
- #39 B08 Tuning data file editable without code
- #45 C30 Netcode feel II
- #17 C11 Reconnect, leavers, forfeit
- #1 Migrate backlog to GitHub issues; restructure docs into feature/design levels
- #301 Test harnesses and scripts hard-code the 60 Hz tick
- #66 Lint gate red on origin/main since ec09b1e (seeded RNG in world.gd vs the purity rule)
