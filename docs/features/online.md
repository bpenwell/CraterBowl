# Online play

Feature-level doc: how this works for players **today** on `main`. Design/implementation detail: [../design/netcode.md](../design/netcode.md), [../design/architecture.md](../design/architecture.md). Open work: GitHub issues labelled `area:online` (listed below).

## Summary
One player hosts (listen server, ENet/UDP). Everyone else joins with an invite code, an IP, the match browser, or by queueing on the matchmaker, which picks one queued player to host and sends the rest that host's code.
Bots fill every empty slot, so a 1v1 friend game or a two-player casual queue still plays a full match. Everything runs peer-hosted: there are no dedicated servers. Quick match, ranked and the browser all need a matchmaker, and the default address is `127.0.0.1:24600`, so they work only if someone runs one (#48).

## How it plays

### Ways in (menu: **Online** tab, or the home-screen PLAY selector)
| Path | What happens |
|---|---|
| Host a match | Opens a private lobby on UDP **24565** with the picked size/rules. "List publicly in the match browser" (on by default) advertises it. |
| Join | Type an invite code `XXXXX-XXXXX` or an IPv4 address. Anything else is rejected with a hint. |
| Open matches (browser) | List from the matchmaker, refreshed every 3 s; JOIN launches with that lobby's code. |
| Quick match / Ranked | Queue `casual` / `competitive` on the matchmaker for the picked size and rules, solo or as a party. |
| Home PLAY selector | Shortcuts: 3v3/5v5/7v7 quick match, 5v5 ranked (plus the offline modes). |

### Invite codes
- 10 Crockford base32 chars encoding IPv4 + port (`src/net/invite_code.gd`). Case-insensitive; `O`→0, `I`/`L`→1 are forgiven.
- The address inside is the router's public IP when UPnP succeeded, otherwise this PC's LAN address.

### Private lobby (in the match scene, text HUD)
- HUD: `PRIVATE MATCH LOBBY  Invite code: …`, settings, seats taken (`6/6 players`) and names (✓ = ready).
- **Enter** toggles ready. The host can press **3/5/7** for team size, **M** for classic/Chaosball, and **H** for the quarter length. Every match plays four quarters (#130); defaults are 7v7 and 2.5-minute quarters. See [clock rules](rules.md#clock-srcsimclockgd) for the duration choices.
- Any settings change un-readies everyone except the host.
- Hosting from the menu with Chaosball selected opens the lobby in Chaosball 3v3, whatever size was picked (`--host --mode=chaosball` does the same). The host can still press **M** to switch back to classic (#74).
- The host can press **I** to toggle the in-flight pass landing marker for the match. The lobby shows its
  current value. The option defaults to on and follows the same ready rules as the other host settings (#108).
- Starts automatically when **every player is ready and at least 2 are present**. A host alone can't start a private match.
- **Seats are capped at the match size** (both teams' slots: 3v3 = 6, 5v5 = 10, 7v7 = 14 players, host included; #54). A joiner beyond that is turned away and their screen shows `COULDN'T JOIN THE MATCH` with the reason (`Lobby full: 3v3 seats 6 players`). Nobody waits in a lobby they can never play from. There are no spectators yet (#20).
- **The host can't shrink the match below the players already present.** Pressing 3/5 or M (Chaosball is 3v3) with too many players is refused, and the host lobby shows why (`Can't switch to 3v3: 7 players here, 6 seats. Someone has to leave first.`). Nobody is kicked. Growing the match is always allowed.
- **Mismatched builds are turned away (#165).** Every client says which protocol version it speaks before the host seats it. If the host runs a different version, the joiner's screen shows `COULDN'T JOIN THE MATCH` and `Update Crater Bowl to play online (server is v2, you have v1)` (or, when the joiner is the newer one, `This server runs an older Crater Bowl …`). A build from before this check is turned away after 5 s with `… you have an older build`. The other way round, a host from before this check is turned away by the joiner: `This server runs an older Crater Bowl (server is an older build, you have v3)` (#224). Queueing at a matchmaker on another version returns to the menu with the same reason (the footer clips it today: #221). How it works and when the version is bumped: [netcode](../design/netcode.md#version-handshake-165).
- Players who join after kickoff go straight into a free slot. With every seat taken they're turned away with `Match full: every seat is taken`. ENet allows at most 13 clients (14 humans, a full 7v7).

### Team and position online
- Humans are seated automatically: each joins the team with fewer humans and takes the first free slot in priority order (QB/LB, WR/CB, WR/CB, RB/S, C/DL, OL/DL, OL/S).
- Queue matches seat players on the matchmaker's team split, matched by a random per-queue seat token, so two players with the same name each get their own seat on their drafted team (#59). Older clients without a token are matched by name.
- Online players keep their host-assigned athlete during the match. Pre-match role preferences and QB voting are tracked in #18.

### Queues (`src/net/matchmaker.gd`)
| Rule | Casual | Competitive (Ranked) |
|---|---|---|
| Match formed when | both teams full, or ≥ 2 players after **8 s** | same, after **15 s**, within the rating window |
| Rating window | none | ±(100 + 25 × seconds waited), max ±600, around the longest-waiting unit |
| Sizes | 3v3 / 5v5 / 7v7, never mixed | same |
| Rules | classic or Chaosball (Chaosball always 3v3), never mixed | same; a competitive Chaosball queue exists and uses the same rating |

- The host is the first member of the longest-waiting unit. They open a lobby with 5-min halves and auto-ready, and the match starts only when **all** matched players have joined. Joiners auto-ready.
- Team split for every queue match: biggest units first, each onto the team with fewer players (tie: lower rating total).
- Your queue rating is the one in your own `user://ranked.json` (see [progression.md](progression.md)).
- While you wait you free-roam the training ground, with the title `SEARCHING FOR A CASUAL MATCH m:ss` ([training.md](training.md)).
- If the elected host misses the invite-code deadline, the other players return to the queue with their wait time preserved. The timed-out host closes the empty lobby and resumes searching solo with the same queue, size and rules (#308).

### Parties
- Online tab → Party: Solo or 2–7, plus a 5-char code (**New code** generates one). Every member picks the same size, rules and code, then queues.
- A party waits until all members have queued, is never split across teams, and must fit on one team (party size ≤ team size). Otherwise the matchmaker refuses the enqueue.

### Match browser (`src/ui/server_browser.gd`, `src/net/lobby_registry.gd`)
- Row: `<name>'s match · 5v5 CLASSIC · 3/10 · IN PROGRESS`. JOIN is disabled when full.
- Order: open lobbies before in-progress ones, then not-full before full, then by player count. At most 50 rows.
- A public host re-registers every 5 s, and an entry disappears 20 s after its last refresh.
- No connection within 4 s shows "Matchmaker … is offline", and hosting/joining by code still work.

### UPnP (`src/net/port_mapper.gd`)
- Settings → Online → "Open my router port automatically when hosting (UPnP)", on by default.
- Before hosting (24565) or queueing (24566, so any queuer can be elected host), the game asks the router to forward the UDP port. The lease is 4 h. The game removes the mapping when hosting ends: on any return to the menu (Leave match, match end, queue leave) and when the app closes (window close or Quit to desktop). Removal runs off the main thread on menu return and is best effort; if the router refuses or the game crashes, the lease expires on its own (#57).
- A private or carrier-grade NAT external IP (100.64/10) counts as a mapping failure. The code uses the LAN address, and the host lobby shows the failure and the UDP port to forward (#47).

### Disconnects
- **A client leaves (host side):** in the lobby they're removed. In a match their slot is released and a bot plays that athlete for the rest of the match.
- **Host leaves or crashes (#56):** the client goes back to the menu, and the footer status reads **Host disconnected**. This works in the lobby or mid-match. If the match already ended (FINAL hold or Players of the Game), the game overview is kept. A host that quits cleanly is noticed right away. In the match, a crashed or unreachable host is noticed by silence (#86): after **2 s** with nothing from the host a **Connection to host lost…** banner shows at the top with a countdown, it clears if the host is heard again, and after **4 s** the client goes to the menu. Measured 2026-11-26 on WSL localhost with a SIGKILLed host: host_lost 4.0 s after the last snapshot, menu up at 4.2 s (was 5.8-9.7 s at ENet's peer timeout). In the lobby the host sends nothing while nothing changes, so a crash there still waits for ENet's timeout (#175). There is no reconnect or host migration (#17).
- **Esc menu online:** the match keeps running (no pause). Leave match closes the connection.
- **Unreachable host or matchmaker:** an initial connection failure returns the player to the menu. The footer says **Couldn't reach the host** or **Couldn't reach the matchmaker**. This covers both connection setup errors and ENet timeouts.

- **Host can't open its port (#299):** if another program (or a second Crater Bowl) already holds the UDP port, hosting stops there. No lobby opens and no invite code is issued, since that code would send friends to whatever holds the port. A menu host goes back to the menu and the footer reads **Couldn't host on port N. Is another game using it?**; a CLI/headless `--host` exits with code 1. A matchmade host that hits this leaves its joiners waiting (#303). Tests: `tests/test_host_port_in_use.gd` (CLI exit code), `tests/visual/host_port_in_use_test.gd` (menu).

## Design decisions
- **A menu choice is a CLI launch** (`{"host": true}` == `--host`), so the menu runs the same paths `net_test.sh`/`mm_test.sh` cover ([out-of-game.md](out-of-game.md)).
- **Peer-hosted, matchmaker only brokers.** The matchmaker never carries game traffic. That keeps hosting free but leaves CGNAT players unable to host (#32, #21).
- **Refuse mismatched builds up front (#165)** instead of letting them connect and desync. One integer (`Protocol.VERSION`) decides compatibility, not the release number: two releases can be wire-compatible, and an exact integer check is cheap and obvious. The matchmaker refuses rather than queueing each version separately; serving two versions during a rollout matters only once there's a hosted server (#222, part of #166).
- **Invite code = address.** No server is needed to resolve codes. The downside is that a code changes whenever the host's IP or port does.
- **Queue matches start only with the full matched group** (`Lobby.expected`), so no one is seated by a bot because they joined late.
- **The deadline ends the host order (#308).** The matchmaker re-queues the waiting players immediately. A recovered host searches again with its existing connection. Accepting a late invite code would keep the waiting players reserved longer or risk interrupting a new match. See [pending hosts](../design/matchmaking.md).
- **No team or position changes online.** The old team/slot requests are rejected rather than kept as an online position-selection API ahead of #18.
- Teams come from the party-aware `unit_teams`.
- **Host loss is a client-side silence watchdog, not a shorter ENet timeout (#86).** The host streams 30 snapshots/s in a match, so 2 s of silence already means trouble. `NetSession.watch_host` warns at `STALL_AFTER` (2 s) and gives up at `DROP_AFTER` (4 s); any packet from the host resets it, so a lag spike shorter than 4 s shows the banner and then carries on. Rejected: lowering `ENetPacketPeer.set_timeout` on the server peer. ENet's drop is final (no warning, no recovery) and depends on retransmit backoff (it measured anywhere from 5.8 s to 9.7 s for the same kill), and the watchdog leaves a clean seam for #17: a "reconnecting…" grace window replaces the `DROP_AFTER` branch. The clock is wall time, but one frame counts at most `SILENCE_STEP_MAX` (0.25 s), so a hitch on the client's side (loading, a debugger) isn't blamed on the host. The cost: a client running below ~4 FPS detects more slowly (seen in the llvmpipe visual test). 4 s rather than 3 s because Wi-Fi roams and brief route flaps run 1-3 s; ENet keeps the link through those, so dropping a live match for one would be worse than waiting 1 s longer for a dead host.
- **The host-loss smoke times the drop the way the watchdog counts it (#279).** `net_test.sh`'s second phase asserts detection within `DROP_AFTER` + 0.75 s, measured as wall time from the host's last *packet* (any packet resets the watchdog, not only snapshots) minus the client's own frame gaps beyond `SILENCE_STEP_MAX`. A pure wall-clock bound failed under CI load (4.99 s against 4.75 s on 2026-11-26) while the watchdog fired on time: the starved client process ran long frames, each of which the watchdog deliberately counts as only 0.25 s, so its clock trailed the wall. Rejected: widening the slack, which would also hide a genuinely late watchdog; asserting `host_silence` at the drop, which only restates `watch_host`'s threshold and misses a clock that runs slow. The log line reports wall time, the excluded hitch and the watchdog's clock, so a red run shows which one moved.
- **Remote movement inputs are buffered.** The host preserves short bursts of commands so rapid cuts
  survive uneven packet delivery. The queue has a fixed limit to keep corrections responsive. See
  [client prediction](../design/netcode.md#client-prediction-client_predictorgd).

## Code and tests
- `src/net/net_session.gd`: ENet host/join, seat assignment, lobby relay, disconnect → release, host-silence watchdog (#86). `src/game/link_banner.gd`: the "Connection to host lost…" banner.
- `src/net/lobby.gd`: lobby state, ready rules, host-only settings.
- `src/net/invite_code.gd`: code ⇄ IP:port.
- `src/net/matchmaker.gd`: queue rules, parties, team split. `src/net/mm_server.gd` / `src/net/mm_client.gd`: matchmaker process and client.
- `src/net/lobby_registry.gd`, `src/net/lobby_advertiser.gd`, `src/ui/server_browser.gd`: match browser.
- `src/net/port_mapper.gd`: UPnP. `src/sim/roster.gd`: slots, auto-assign.
- `src/game/main.gd` (`_host_game`, `_join_game`, `_queue_up`, `_step_lobby`, `_start_from_lobby`) and `src/ui/main_menu.gd` (`_screen_online`, `_queue`, `host_match`, `_with_port`).
- Tests: `tests/test_lobby.gd`, `tests/test_matchmaker.gd`, `tests/test_protocol.gd`, `tests/test_roster.gd`, `tests/test_out_of_game.gd` (registry, advertiser, public-IP check), `tests/test_port_mapper.gd` (UPnP map/unmap lifetime with a fake router), `tests/net_host.gd` + `tests/net_client.gd` via `scripts/net_test.sh` (second phase: SIGKILLs the host and expects the client on the menu with "Host disconnected", #56, within `DROP_AFTER` + 0.75 s of the last host packet, own frame hitches excluded, after the banner, #86, #279), `tests/test_netcode.gd` (`test_watchdog_*`: warn/drop thresholds, lag spike recovers, only seated clients, own-hitch cap), `tests/visual/host_lost_test.gd` (rendered menu after the host quits), `tests/visual/host_stall_test.gd` (rendered "Connection to host lost…" banner; it clears on a packet, then drops at 4 s with ENet still connected), `scripts/mm_test.sh` (`MODE=casual|competitive|party|chaos`), `tests/menu_flow.gd` (classic and Chaosball private hosts), `tests/visual/private_lobby_chaosball_test.gd` (rendered Chaosball lobby), `tests/visual/size_picker_chaosball_test.gd` (Size row locked to 3v3 under Chaosball, #83), `tests/test_protocol_version.gd` + `tests/visual/version_mismatch_test.gd` + `net_test.sh` phase 3 (version handshake, #165).

## Open issues
- #14 C32 Co-op vs bots playlist + bot difficulty
- #17 C11 Reconnect, leavers, forfeit
- #18 C12 Position assignment: QB vote, role preferences
- #20 C14 Spectators
- #21 C15 Find a game without port-forwarding: dedicated server + browser
- #26 C20 Rematch and keep-the-lobby
- #27 C21 Host tools: mutators, ref console, kick/mute
- #28 C22 Trustworthy progression
- #29 C23 New-player protection
- #32 B07 NAT relay for CGNAT/strict routers + hosted public matchmaker
- #44 C29 Events and variety: weather, time of day, rotating modes
- #48 Decide: host the public matchmaker (VPS/AWS + DNS)?
- #85 Joining a bad code / unreachable host hangs forever
- #175 A host that crashes while you're in the lobby still takes ENet's 5-30 s timeout
- #221 Menu footer status clips long reasons
- #222 Matchmaker serves more than one protocol version during a rollout
- #75 Stadium screen shows a running-match clock in the private lobby
