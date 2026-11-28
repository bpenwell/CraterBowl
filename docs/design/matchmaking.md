# Matchmaker: pending hosts

The matchmaker protocol, queue rules and host election are in `docs/design/netcode.md` ("Matchmaker").
This doc owns one rule that sits on top of them: what happens between electing a host and relaying its
invite code (#303).

## The rule

When `matchmaker.gd:tick` forms a match, `mm_server.gd` sends the elected host `match/host` and keeps
`pending[host] = {others, match, deadline}`. `others` are the other players' queue entries, not just
their ids. The match is relayed (`match/join` + code to every other) only when the host answers
`hosting` with a non-empty `code` before `deadline`.

The host **fails** if any of these happens first:

| Trigger | Where | Typical cause |
|---|---|---|
| The host disconnects from the matchmaker | `_on_peer_left` | It couldn't bind its game port and went back to the menu (#299/#305), crashed, or quit |
| No `hosting` within `HOST_REPLY_TIMEOUT` = 10 s | `_process`, before `tick` | It hung, or died without ENet noticing yet |
| `hosting` with an empty `code` | `hosting` handler | Nothing to join |

On failure `_drop_pending` erases the pending match and calls `Matchmaker.requeue(others)`:

- **The others keep their original `since`.** They have already waited at least a full match wait, so
  they go back as the oldest players in their group and re-form first. A casual group already past
  `CASUAL_WAIT` matches on the same tick (the timeout check runs before `tick` for that reason). We
  chose this over "back of the queue" because none of them did anything wrong. Nothing is sent to
  them: their clients never left "searching", so a re-queue is invisible except that a match now forms.
- **A connected host whose order expires receives `match/cancel` (#308).** This applies whether the
  frame tick observes the deadline first or the late invite code arrives first. Later replies are
  ignored. The cancelling server keeps the other players' wait times. The host closes its game
  connection, uses its existing matchmaker connection to enqueue solo, and starts a fresh wait.
  Reliable ordering on channel 0 keeps the reply from the old order ahead of the new enqueue.
- **Parties shrink to who came back.** If the failed host was in a party, its friends return with
  `party_size` set to the members re-queued, and a lone survivor queues solo. Otherwise the party
  could never be complete again and would wait forever.
- A joiner that disconnects while its host is pending is removed from `others`, so it is never
  re-queued.

## Why 10 seconds

A healthy host answers in the frame it receives the order: `main.gd` rebuilds the world and creates
the lobby synchronously in the `host_match` callback, then sends `hosting`. So the normal reply is
one round trip. 10 s leaves room for a slow world rebuild on weak hardware and for ENet resending
over a lossy link. It is shorter than ENet's own disconnect timeout (5–30 s), which is all the
disconnect path would otherwise have for a host that died silently. The joiners have already waited
8–15 s for the match to form, so a longer deadline would double their wait for nothing.

## Tests

`tests/test_mm_pending_host.gd` drives the real `mm_server.gd` with the clock and socket stubbed:
host disconnect, timeout and empty code each re-queue the others and form a new match with a
different host; a host that answers in time is relayed unchanged; a joiner that left is not
re-queued; a failed host's party friend re-queues as a solo. The test also covers cancellation
at the deadline and verifies that a late code never reaches joiners.

`tests/visual/matchmaker_host_timeout_test.gd` uses loopback ENet and advances the server clock
when the real host replies. It checks the host re-enqueues without its old party, releases its
game port and shows the training-ground search again.
