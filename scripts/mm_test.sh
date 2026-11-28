#!/usr/bin/env bash
# Matchmaking integration: matchmaker + 2 queued headless clients -> one hosts, one joins, match starts.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
MMPORT="${MMPORT:-$((24700 + RANDOM % 200))}"
MODE="${MODE:-casual}"
QUEUE="$MODE"; PARTY=""
if [ "$MODE" = "party" ]; then QUEUE=casual; PARTY="--party=PALS:2"; fi
if [ "$MODE" = "chaos" ]; then QUEUE=casual; PARTY="--mode=chaosball"; fi
# dupname: competitive with both players named Ann (#59: seating must not be keyed by display name).
NAME_B=Ben
if [ "$MODE" = "dupname" ]; then QUEUE=competitive; NAME_B=Ann; fi
. scripts/wait_lib.sh   # wait_for / log_has / show_logs: deadline polls, never fixed counts (#283)
LOGS=".mm-server.log .mm-a.log .mm-b.log"
# fail WHAT: stop everything, say which step never happened, and show the log tails.
fail() { kill ${A:-} ${B:-} $MM 2>/dev/null; wait ${A:-} ${B:-} $MM 2>/dev/null; echo "MM TEST FAIL ($MODE): $1"; show_logs $LOGS; exit 1; }
rm -f $LOGS
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
timeout $((60 + WAIT_SECS)) "$GODOT" --headless --path . -- --matchmaker --port="$MMPORT" > .mm-server.log 2>&1 &
MM=$!
wait_for "$WAIT_SECS" "$MM" log_has "^MM server on $MMPORT: OK" .mm-server.log || fail "matchmaker never listened on $MMPORT after ${WAITED}s"
timeout $((55 + WAIT_SECS)) "$GODOT" --headless --path . -- --queue=$QUEUE $PARTY --mm=127.0.0.1:"$MMPORT" --size=3 --advertise=127.0.0.1 --name=Ann --rating=1000 --profile-file=user://test_mm_profile.json --leaderboard-file=user://test_mm_lb.json --ranked-file=user://test_mm_ranked.json > .mm-a.log 2>&1 &
A=$!
# A queues first (it used to get a fixed 0.5 s head start).
wait_for "$WAIT_SECS" "$MM $A" log_has "^MM enqueue [0-9]+ -> true" .mm-server.log || fail "first client never reached the queue after ${WAITED}s"
timeout $((55 + WAIT_SECS)) "$GODOT" --headless --path . -- --queue=$QUEUE $PARTY --mm=127.0.0.1:"$MMPORT" --size=3 --advertise=127.0.0.1 --name=$NAME_B --rating=1050 --profile-file=user://test_mm_b_profile.json --leaderboard-file=user://test_mm_b_lb.json --ranked-file=user://test_mm_b_ranked.json > .mm-b.log 2>&1 &
B=$!
started() { log_has "NET match started" .mm-a.log .mm-b.log && log_has "NET assigned athlete" .mm-a.log .mm-b.log; }
ok=0
wait_for "$WAIT_SECS" "$MM $A $B" started && ok=1
kill $A $B $MM 2>/dev/null; wait $A $B $MM 2>/dev/null
grep -hE "^MM |^QUEUE|NET match started|NET seats|NET assigned" .mm-server.log .mm-a.log .mm-b.log
if grep -hE "SCRIPT ERROR|Parse Error" .mm-server.log .mm-a.log .mm-b.log | grep -q .; then
  grep -hE "SCRIPT ERROR|Parse Error|at: " .mm-server.log .mm-a.log .mm-b.log | head; echo "MM TEST FAIL (script errors)"; exit 1
fi
# The started match must be the queued 3v3 with both named humans in it.
if [ $ok -eq 1 ] && grep -qE "NET match started: (Chaosball )?3v3.*(Ann ✓, $NAME_B ✓|$NAME_B ✓, Ann ✓)" .mm-a.log .mm-b.log; then
  if [ "$MODE" = "competitive" ]; then
    # Rating-balanced snake draft: Ben (1050) -> team 0, Ann (1000) -> team 1, and the match is ranked.
    grep -qE "NET seats: .*(Ben->0.*Ann->1|Ann->1.*Ben->0).*ranked=true" .mm-a.log .mm-b.log || { echo "MM TEST FAIL (competitive seating)"; exit 1; }
  fi
  if [ "$MODE" = "dupname" ]; then
    # Same display name, different players: still split onto opposite teams, one seat each.
    grep -qE "NET seats: .*(Ann->0.*Ann->1|Ann->1.*Ann->0).*ranked=true" .mm-a.log .mm-b.log || { echo "MM TEST FAIL (duplicate-name seating)"; exit 1; }
  fi
  if [ "$MODE" = "chaos" ]; then
    grep -qE "NET match started: Chaosball 3v3" .mm-a.log .mm-b.log || { echo "MM TEST FAIL (chaosball mode)"; exit 1; }
  fi
  if [ "$MODE" = "party" ]; then
    # Friends who queued as a party must be seated together.
    grep -qE "NET seats: .*(Ann->0.*Ben->0|Ben->0.*Ann->0|Ann->1.*Ben->1|Ben->1.*Ann->1)" .mm-a.log .mm-b.log || { echo "MM TEST FAIL (party split)"; exit 1; }
  fi
  # Both queued players warmed up on the training ground, then left it when matched.
  for f in .mm-a.log .mm-b.log; do
    grep -q "QUEUE warm-up: training ground" $f && grep -q "QUEUE warm-up over" $f || { echo "MM TEST FAIL (queue warm-up in $f)"; exit 1; }
  done
  echo "MM TEST PASS ($MODE)"; exit 0
fi
[ $ok -eq 1 ] || { echo "MM TEST FAIL ($MODE): no match started with a seated joiner after ${WAITED}s"; show_logs $LOGS; exit 1; }
echo "MM TEST FAIL ($MODE): the started match isn't the queued 3v3 with both players"; show_logs $LOGS; exit 1
