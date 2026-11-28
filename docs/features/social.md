# Social and communication

Feature-level doc: how this works for players **today** on `main`. Design/implementation detail: [../design/voice-chat.md](../design/voice-chat.md) (planned). Open work: GitHub issues labelled `area:social` (listed below).

## Summary
There is **no in-match communication** today: no voice, no text chat, no quick-chat wheel and no pings.
The one in-match expression is **taunts**: hold C for a radial wheel of 8 cosmetic taunts (animation + speech bubble). A taunt ends when the next play lines everyone up (#426), so it never carries into the pre-snap.
The social features that do ship sit around a match: names, invite codes, parties and private lobbies. They're documented in [online.md](online.md); this page indexes them and tracks the communication work.

## How it plays

### What exists
| Feature | Where it lives |
|---|---|
| Display name (2–16 chars, not You/Bot/Host), shown in lobby, stats, leaderboards, ratings | Welcome screen, Settings → Player ([out-of-game.md](out-of-game.md)) |
| Invite friends: share an invite code `XXXXX-XXXXX` (out of band, e.g. a chat app) | [online.md](online.md#invite-codes) |
| Queue together as a party (same code + size) | [online.md](online.md#parties) |
| Private lobby with ready-up and host settings | [online.md](online.md#private-lobby-in-the-match-scene-text-hud) |
| Public match browser | [online.md](online.md#match-browser-srcuiserver_browsergd-srcnetlobby_registrygd) |
| Taunts: hold C, drag toward one of 8 on a radial wheel, release (everyone sees the animation and bubble) | [CONTROLS.md](../CONTROLS.md#taunt-wheel-139) |
| Self-expression: jersey number, trim, helmet, TD celebration | [progression.md](progression.md#cosmetics-locker-room) |
| Players of the Game presentation after each match | [presentation.md](presentation.md) |

### What doesn't exist
- In-match voice, text, quick-chat or pings. Play calls are coordinated only by each player seeing their own team's play art.
- Spectating: every connection is a player, and joiners take a slot or are refused when all slots are human (#20).
- Friends lists, presence, or invites sent from inside the game. The home-screen "invite" pads just open the Online tab.
- Moderation: no mute, kick or report (#27).

### Planned: team voice chat (#31)
- Team-only voice in online matches: client → host → same-team clients over the existing ENet session, so the other team never receives your packets.
- No third-party service or account. Push-to-talk or open mic, per-player mute, and a talking indicator are planned; text chat and spectator voice are out of scope for v1.
- The codec and capture approach are still an open question on the issue. Full plan: [../design/voice-chat.md](../design/voice-chat.md).

## Design decisions
- Coordinate through the game first: play art and the play picker carry intent without chat, which fits the 3v3–7v7 pick-up format.
- Voice before text: during a live play, typing isn't possible, and speaking is.
- Voice is host-relayed and team-filtered on the host, so a client can't subscribe to the other team. A modified host could still listen in, which is accepted for a friends game (see the design doc).

## Code and tests
- Taunts: `src/sim/emotes.gd` (list, rate limit), `src/game/taunt_wheel.gd`, tests `tests/test_taunt_wheel.gd` + `tests/game_flow.gd`; a teleport ends a taunt and a down scorer celebrates after getting up: `tests/test_view_celebrate.gd`, `tests/visual/celebrate_after_getup_test.gd` (captures `celebrate-waits-while-down`, `celebrate-after-getup`; 79 frames of dancing on the turf before the fix).
- No voice/text/ping code exists yet. Name handling: `src/ui/settings_store.gd` (`clean_name`), `src/net/lobby.gd` (`set_name`).
- Parties, lobby and browser code and tests: see [online.md](online.md#code-and-tests).

## Open issues
- #19 C13 Communication: quick-chat wheel, pings, text chat
- #20 C14 Spectators
- #31 Team voice chat (team-only, host-relayed)
