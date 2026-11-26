# Netcode

Scope: how online play is built — the listen-server session, wire messages, validation, snapshots,
prediction/interpolation, lobby, matchmaker, invite codes and UPnP. Feature-level behavior (what players
see when hosting, joining, queueing) lives in `docs/features/` (online play). Layering and the tick loop:
`docs/design/architecture.md`. Voice (planned, ENet channel 2): `docs/design/voice-chat.md`.

## Topology and rates

- **Listen server.** The host runs the authoritative sim and also plays as peer 1 (`main.gd:LOCAL_PLAYER`).
  Clients talk only to the host. `NetSession` (`src/net/net_session.gd`) is a `Node` with its own
  `SceneMultiplayer`, used only for raw `send_bytes` / `peer_packet` (no RPCs). Why: high-level RPCs and
  `MultiplayerSynchronizer` tie sim state to scene nodes, which fights the pure sim, while our own snapshot codec
  keeps bandwidth explicit and testable. Lockstep was rejected as too fragile over the internet with 14 athletes.
- Game port `NetSession.DEFAULT_PORT = 24565`, `MAX_PEERS = 13` (7v7 minus the host). Queue hosts use
  `main_menu.gd:QUEUE_HOST_PORT = 24566` from the menu, or a random 25000–29999 if `--host-port` isn't given.
- **Rates:** sim 60 Hz (physics tick); client input sent every tick (60 Hz); snapshots every
  `main.gd:SNAPSHOT_EVERY = 2` ticks (30 Hz); clients render others `INTERP_DELAY = 0.1` s in the past.
- Encoding: every message is a `Dictionary` → `var_to_bytes`; receivers use `bytes_to_var` (never
  decodes objects) and drop anything that isn't a Dictionary. Routing key is `msg.k`.
- Channels (`NetSession._send`): reliable → `TRANSFER_MODE_RELIABLE` on channel 0; unreliable →
  `TRANSFER_MODE_UNRELIABLE_ORDERED` on channel 1.

## Peer / athlete assignment

- `host(port, assign, release)`: `main.gd:_host_game` passes `roster.auto_assign(peer)` / `roster.release(peer)`.
- `_on_peer_connected`: if `lobby_mode` and the lobby is open, the peer joins `lobby.players` with **no
  athlete**, unless `lobby.is_full()` (`players.size() >= capacity()`, capacity = 2 × the size's slots),
  which refuses it. Otherwise (`--no-lobby`, or a match already running) it is auto-assigned at once;
  `-1` (no free slot) refuses it. So every lobby player is guaranteed a seat at start (#54).
- `refuse(id, reason)`: sends `refused` and drops the peer `REFUSE_GRACE` (1 s) later. The delay is
  needed because ENet's `disconnect_peer` discards queued reliable packets, so a same-tick disconnect
  would lose the reason. A well-behaved client hangs up as soon as `refused` arrives.
- `set_assignment(id, aid)` records `peer_athlete[id]` and sends `welcome`. `main.gd:_start_from_lobby`
  seats every lobby player (competitive: `roster.auto_assign_team` by the matchmaker's team split,
  keyed by the player's seat token, display name only as a fallback; else `auto_assign`; #59).
- `_on_peer_disconnected`: removes from lobby, frees the athlete (`release_fn`), drops its input. The
  slot goes back to a bot. There is no rejoin (#17).
- Client side, `join()` hooks `SceneMultiplayer.server_disconnected`. If the client wasn't refused (a refused
  client hangs up on purpose), `NetSession` emits `host_lost`, and `main.gd:_on_host_lost` calls
  `Launch.go_to_menu("Host disconnected")`. It keeps the match overview if the post-game had already started (#56).
  A crash is noticed only at ENet's peer timeout (#86). `connection_failed` is still unhandled (#85).

## Messages — game session (`net_session.gd:_on_packet`)

| `k` | Direction | Delivery | Payload | Receiver checks |
|---|---|---|---|---|
| `in` | C→S | unreliable-ordered, ch 1, every tick | `dir`, `spr`, `seq`, `block` | sender has an athlete; `P.sanitize_input`; `seq` must exceed the last queued or consumed sequence |
| `act` | C→S | reliable, ch 0 | `act` (action dict) | sender has an athlete; `P.is_action(act)` (Dictionary with a String `a`, else dropped); queued as `[peer, aid, act]`, fields validated when applied |
| `lact` | C→S | reliable, ch 0 | `act` = `{"a":"ready"}` / `{"a":"name","n":…}` / `{"a":"seat","s":…}` (queue matches, #59) / `{"a":"id","i":…}` (install id, 16–32 hex chars, #102) | sender is in `lobby.players`; `act` is a Dictionary |
| `refused` | S→C | reliable, ch 0 | `why` (reason text) | from peer 1; cut to 120 chars. Client stores `refused_reason`, emits `refused`, closes its peer and ignores later packets |
| `welcome` | S→C | reliable, ch 0 | `aid`, `size`, `mode` | from peer 1; `aid` must index an athlete, `size` is 3, 5 or 7 (default 7), and `mode` is classic (default) or chaosball. Invalid fields leave the current assignment intact |
| `snap` | S→all | unreliable-ordered, ch 1, 30 Hz | see Snapshots | from peer 1; tick `t` > last seen |
| `ev` | S→all | reliable, ch 0 | `n` (event name), `d` | from peer 1; `d` forced to Dictionary |
| `lobby` | S→all | reliable, ch 0 | `s` = `lobby.to_dict()` | from peer 1; `s` is a Dictionary |

`snap` and `ev` are only broadcast once at least one peer holds an athlete; `lobby` once any peer exists.
The host re-broadcasts every world event from `main.gd:_on_world_event`, plus match-level `looks`,
`ranked`, `awards`, `summary`.

## Validation

- `protocol.gd:sanitize_input`: non-finite `dir` → zero, length clamped to 1; `seq` must be a
  non-negative int (else 0); `spr`/`block` must be exactly `true` (`_flag` type-checks first).
- `protocol.gd:is_action` is the **queue shape gate** (#77): only a Dictionary whose `a` is a String
  enters `NetSession.actions`. Anything else is dropped on receipt. Why it exists: in Godot 4, `==`
  between a String and an int/Array/Vector2/bool raises a script error, and passing a non-Dictionary
  to a typed parameter aborts the caller. Either one inside `main.gd:_step_authoritative` killed the
  host's whole tick, so every valid action queued behind the junk that tick was lost.
  `sanitize_action` re-checks the shape and `apply_action` takes an untyped `action`, so the
  dispatcher returns `false` rather than erroring even if a caller skips the gate. Wire booleans
  (`lob`, `spr`, `block`) go through `_flag` and never use `== true` on a peer value.
  Tests: `tests/test_action_validation.gd` (unit) and `tests/visual/invalid_actions_test.gd`
  (real host scene: junk plus a same-tick play call, then a valid snap).
- `protocol.gd:sanitize_action` is the **action whitelist**: `snap`, `tackle`, `recall_call`,
  `flip_play`, `handoff`, `timeout` (no args); `dash`/`spin` (finite `dir`, clamped); `throw` (finite
  target `t`, finite power `p` clamped 0–1, `lob` bool); `try` (`n` ∈ {1,2}); `play` (name in
  `Routes.PLAYBOOK`/`RUN_PLAYS`); `defense` (in `DefensivePlaybook.CALLS`); `route` (in `Routes.ROUTES`).
  The kicking actions are `kick` (finite target `t` and power `p` clamped to 0–1),
  `kick_call` (`k` is `""`, `"punt"` or `"fg"`), and `toss` (`c` is `"receive"` or `"kick"`).
  Other actions return `{}`, including legacy `team` and `pick` requests.
- `protocol.gd:apply_action` then checks side and phase (e.g. `play`/`flip_play`/`try` offense only,
  `defense` defense only, `play`/`route` PRESNAP only) and delegates to `World`/`Match`. Client throws
  always use `T.PLAYER_PASS_POWER`; the client's `p` is sanitized but not used.
- `look` is the one action outside the whitelist: `main.gd:_step_authoritative` intercepts it and runs
  `Cosmetics.sanitize_look` before rebroadcasting `looks`.
- Lobby: names stripped and cut to 16 chars (`lobby.gd:set_name`); settings change only via
  `set_setting(by == host_id, phase LOBBY)` with whitelisted values, called from the host's own keys.
- `Roster.claim` rejects occupied slots before releasing the requester's current slot. Unit tests check
  both the protocol rejection and the roster rule. The network flow checks that the legacy requests
  leave the connected client's assignment intact.
- Not validated: message rate. `actions` and `lobby_actions` are unbounded queues drained once per tick.

## Snapshots (`protocol.gd:encode_snapshot` / `apply_snapshot`)

| Key | Content |
|---|---|
| `t` | server tick (`main.gd:net_tick`) |
| `a` | `PackedFloat32Array`, 7 per athlete: pos x/y, vel x/y, facing x/y, stamina |
| `r` | `PackedInt32Array`, 3 per athlete: role, flags (DIVE 1, GROUND 2, LOCK 4, BLOCK 8, SPIN 16), team |
| `moves` | 2 per athlete: `move_charge`, `move_t` |
| `b` | ball: state, holder, pos xyz, vel xyz |
| `d`, `s`, `c`, `to` | downs (offense, down, los, first-down y), score, clock (half, remaining, play clock, final, quarter, quarter length in seconds), timeouts |
| `ph`, `off`, `los`, `fpt`, `pt`, `ms`, `tp` | world phase, offense team, LOS, forward pass thrown, last possession, match state, try points |
| `pl`, `rt`, `dc`, `rf`, `hc`, `cs` | play name, route index per athlete (-1 none), defensive call, run flipped, handoff cooldown, Chaosball streak/hold |
| `ack` | athlete id → last input `seq` the server consumed (`NetSession.acks()`) |

Each message contains a full snapshot. Before advancing its last accepted tick, the client validates
the payload types, array lengths for the advertised match size, finite numeric fields and input
acknowledgments. A rejected snapshot leaves the previous game state and tick intact.
`apply_snapshot` writes accepted state into the client's `World` and `Match`. Dive and ground
flags become token timers (`0.01`), and optional fields retain their compatibility defaults.
When adding wire fields, update the encoder, validator, decoder and protocol tests together.
The quarter fields extend the clock array after its four original entries. If they are absent, the client uses halves.

## Client prediction (`client_predictor.gd`)

Predict our own athlete, interpolate everyone else. Interpolating ourselves too makes controls lag by the round trip,
and full rollback of the whole sim is overkill when the host owns every contact.

1. `main.gd:_physics_process` (client): `predictor.record(dir, sprint, dt, block)` → `seq`;
   `net.send_input(..., seq)`; `world.predict_step(me, ...)` moves only the local athlete (stance lock and
   neutral zone apply, `world.gd:predict_step`). A held ball is pinned to the predicted carrier.
2. `main.gd:_on_snapshot`: `apply_snapshot` overwrites everything (including our athlete), then
   `predictor.reconcile(me, ack[my_id], world)` drops acked inputs and replays the rest. `pending` is
   capped at `MAX_PENDING = 240` (4 s).
3. The host buffers up to six commands per remote athlete and applies one per sim tick in sequence
   order. It uses neutral human controls when the queue is empty. Overflow evicts the oldest command
   to cap the delay, and disconnect or reassignment clears the queue and acknowledgement. Snapshots
   acknowledge the last consumed sequence, so the client replays only newer commands.
4. Prediction ignores collisions, blocks, tackles and other athletes; those corrections show up as
   snaps on reconcile (#45).

## Interpolation (`interpolator.gd`)

- `push(tick, xy, ball)` stores `tick / TICK_RATE` (hard-coded 60), drops out-of-order, keeps 32 entries.
- `main.gd:_apply_interpolation` samples at `latest_snap_tick/60 + (now - latest_snap_at) - 0.1` and
  writes positions for every athlete except ours, and the ball unless we hold it. Only position is
  interpolated; velocity/facing/flags come from the latest snapshot. Views then do per-frame render
  interpolation as offline (architecture.md → Tick model).

## Lobby flow (`lobby.gd`, `main.gd`)

1. Host: `_host_game` makes a `Lobby` (`host_id = 1`), sets `code` (invite code), `expected` (queue
   matches), and `NetSession.lobby_mode = true`. Host keys (`main.gd:lobby_key`): Enter ready, 3/5/7 size,
   M classic/chaosball (forces size 3), Q halves/quarters, H duration (2/5/8 min halves or 1/2/3 min quarters).
   Any setting change clears the guests' ready state. A size or mode change whose capacity is below
   `players.size()` is refused and sets `lobby.notice` (shown in the host lobby HUD) rather than kicking
   anyone; an accepted change clears it. Chosen over disconnecting extras because it never throws a
   player out and the host can see why.
2. Client: `_join_game` decodes the code, connects; on the first `lobby` state it sends `name`, its `seat` token (queue joins),
   and, for queue joins (`auto_ready`), `ready`. Clients mirror via `lobby.from_dict`.
3. `main.gd:_step_lobby` (host, each tick): apply `lact`s, broadcast on change, and when
   `lobby.all_ready()` (≥ max(2, `expected`) players, all ready) → `_start_from_lobby`: `configure`, set
   period format and duration, seat everyone, `welcome` each peer. A client whose `welcome` size/mode differs re-runs `configure`.

## Matchmaker (`mm_server.gd`, `mm_client.gd`, `matchmaker.gd`)

A separate headless process (`--matchmaker --port=N`, default `MMServer.DEFAULT_PORT = 24600`, up to 64
peers). It never relays game traffic: it elects a host and forwards that host's invite code. All
messages are reliable on channel 0.

| `k` | Direction | Payload / effect |
|---|---|---|
| `enq` | C→MM | `mode` (casual/competitive), `size`, `rating`, `name`, `party`, `party_size`, `game`, `seat` → `mm.enqueue` |
| `queued` | MM→C | `ok`, `n` (queue length) |
| `match` | MM→C | `role:"host"` + `mode`, `size`, `expected`, `seats` (seat token → team), `teams` (name → team, legacy), `game`; or `role:"join"` + `code` |
| `hosting` | C→MM | `code` from the elected host → MM sends `match/join` to the others |
| `list` / `lobbies` | C↔MM | server browser: `registry.listing()` + `queued` count |
| `register` / `registered`, `unregister` | C↔MM | public lobby advertising |

- `matchmaker.gd:tick` (called from `mm_server._process` every frame) forms matches per (game, mode,
  size). Parties are one unit once all `party_size` members queued and must fit one team. Competitive
  filters by rating window `min(100 + 25·waited, 600)`. A match forms when full, or after `CASUAL_WAIT`
  8 s / `COMP_WAIT` 15 s with ≥ 2 players. Host = oldest unit's first member. Teams: `unit_teams`.
- **Seat tokens (#59).** Display names aren't unique, so queue seating is keyed by a per-queue token:
  `main.gd:_queue_up` makes 8 random bytes (`seat_token`, hex) and sends it as `enq.seat`. The host's
  `match` order carries `seats` (token → team). A joiner sends its token as the `seat` lobby action next
  to `name`; the host keeps it in `peer_seats` (not in the broadcast lobby state) and seats each player
  with `Matchmaker.drafted_team(token, name, seats, teams)`. Backward compatible both ways: an older
  host ignores `seats` and the `seat` action and still reads `teams`; an older client sends no token and
  is matched by name. `teams` leaves out any name two queued players share, so an old host
  auto-balances them instead of stacking both on one team. Test: `MODE=dupname ./scripts/mm_test.sh`
  (two competitive clients both named Ann) and `test_matchmaker.gd`.
- **Install ids (#102).** Ranked records are keyed by a per-install id (`Cosmetics.install_id`, 8 random
  bytes hex, minted by `main.gd:install_id()`). A joiner sends it as the `id` lobby action next to `name`.
  The host validates it (`Cosmetics.valid_install_id`), keeps it in `peer_installs` (not in the broadcast
  lobby state), and `_record_ranked` keys each human by `ranked_key(owner, aid)`. The broadcast `ranked`
  event is keyed by athlete id, so ids never leave the host. An older client sends no id and is keyed by
  name. Test: `net_test.sh` checks that the id the client minted is the one the host received.
- Disconnect from the MM dequeues, drops pending host relays and the registry entry.
- Server browser: `lobby_advertiser.gd` (attached by `Launch._advertise` when `options.public`)
  re-registers `{code, name, size, mode, players, in_game}` every 5 s; `lobby_registry.gd` expires
  entries after `TTL = 20` s, lists ≤ 50, open lobbies first, then not-full, then fullest.
  `server_browser.gd` polls `list`.

## Invite codes and UPnP

- `invite_code.gd`: IPv4 (32 bits) + port (16) → 10 Crockford base32 chars `XXXXX-XXXXX`. Decode is
  case/dash/space tolerant, maps O→0, I/L→1, rejects port 0 and > 48 bits. IPv4 only; the code is the
  address, not a secret.
- The advertised address is the UPnP public IP when mapping succeeded, else `--advertise`, else
  `main.gd:_local_ipv4()` (LAN; works on LAN or with a manual forward).
- `port_mapper.gd:open_port` (on a `Thread` via `open_port_async`, from `main_menu.gd:_with_port` for host
  and queue): UPnP discover 2 s, map UDP `port→port` for 4 h, query the external IP, reject non-public
  (CGNAT, private) addresses. The launch options carry any failure notice into the host lobby (#47).
  Each accepted mapping is kept in `_mapped` with the `UPNP` object that found the gateway, so removal
  needs no second discovery. `Launch.go_to_menu` calls `release_all_async()` (forget now, delete on a
  `WorkerThreadPool` task; a port re-mapped before the task runs is skipped), and a `QuitGuard` node under
  `/root`, installed by the first `open_port_async`, calls `release_all()` on `NOTIFICATION_WM_CLOSE_REQUEST`
  or `NOTIFICATION_EXIT_TREE`. Release is idempotent; a refused delete is dropped and the 4 h lease is the
  fallback (#57). `upnp_factory` lets tests inject a fake router. Relay support is tracked in #32.

## Trust model and known limits

- Server-authoritative for movement and actions; clients can't teleport or call plays for the other side.
- Clients validate snapshot shape and accept integer match XP from 0 through 10,000. Malformed
  achievement context or XP leaves the local profile untouched. The host remains the authority on
  match outcomes and awards. Ratings and leaderboards live only on the host's disk (#28).
- No reconnect, leaver handling or forfeit; a client doesn't react to losing the host (#17).
- Prediction covers the local athlete's free movement only (#45). No snapshot deltas or compression.
- No message rate limits on game or matchmaker sockets.

## Open issues

- #17 C11 Reconnect, leavers, forfeit
- #45 C30 Netcode feel II
- #28 C22 Trustworthy progression
- #32 B07 NAT relay for CGNAT/strict routers + hosted public matchmaker
- #21 C15 Find a game without port-forwarding: dedicated server + browser
- #48 Decide: host the public matchmaker (VPS/AWS + DNS)?
- #31 Team voice chat (team-only, host-relayed)
- #18 C12 Position assignment: QB vote, role preferences
- #20 C14 Spectators
- #26 C20 Rematch and keep-the-lobby
- #55 No rate limits on client actions or matchmaker messages
- #56 Client doesn't detect losing the host
- #57 UPnP port mapping is never removed after hosting
- #60 Client trusts host snapshots and awards
- #61 Tick rate (60 Hz) hard-coded in several places
