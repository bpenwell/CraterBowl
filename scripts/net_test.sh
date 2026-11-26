#!/usr/bin/env bash
# Two-process network test: headless host (5v5) + headless client (default 7v7, must adopt host size).
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PORT="${PORT:-$((24000 + RANDOM % 1000))}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
timeout 40 "$GODOT" --headless --path . -s res://tests/net_host.gd -- --host --port="$PORT" --playclock=4 --no-kickoff --size=5 --start-when-ready --advertise=127.0.0.1 --profile-file=user://test_net_profile.json --leaderboard-file=user://test_net_lb.json --ranked-file=user://test_net_ranked.json > .net-host.log 2>&1 &
HOST=$!
# Join the private lobby by its invite code (printed by the host).
CODE=""
for i in $(seq 1 50); do
  CODE=$(grep -oE "invite code: [0-9A-Z]{5}-[0-9A-Z]{5}" .net-host.log | awk '{print $3}')
  [ -n "$CODE" ] && break
  sleep 0.1
done
echo "invite code: ${CODE:-<none>}"
timeout 35 "$GODOT" --headless --path . -s res://tests/net_client.gd -- --join="$CODE" --equip=number:88 --profile-file=user://test_net_client_profile.json > .net-client.log 2>&1
status=$?
kill "$HOST" 2>/dev/null; wait "$HOST" 2>/dev/null
grep -E "NET " .net-client.log
if [ $status -ne 0 ] || grep -E "SCRIPT ERROR|Parse Error" .net-client.log .net-host.log | grep -q .; then
  grep -E "SCRIPT ERROR|Parse Error|at: " .net-client.log .net-host.log | head; echo "NET TEST FAIL"; exit 1
fi
# #102: the host keys ranked records by the joiner's install id, sent as a lobby action.
CID=$(grep -oE "NET client install id [0-9a-f]{16,32}" .net-client.log | awk '{print $5}')
if [ -z "$CID" ] || ! grep -q "NET host got install id $CID" .net-host.log; then
  echo "NET TEST FAIL: host didn't receive the client's install id (client '${CID:-<none>}', host: $(grep 'NET host got install id' .net-host.log | head -1))"; exit 1
fi
echo "NET install id reached the host: $CID"
# Host loss (#56): a client in the match whose host dies (SIGKILL: no goodbye packet)
# must return to the menu with "Host disconnected".
PORT2=$((PORT + 1000))
timeout 80 "$GODOT" --headless --path . -- --host --port="$PORT2" --no-lobby --no-kickoff --profile-file=user://test_net_profile.json --leaderboard-file=user://test_net_lb.json --ranked-file=user://test_net_ranked.json > .net-host2.log 2>&1 &
HOST=$!
sleep 1
ARMED="$(mktemp -u)"
timeout 70 "$GODOT" --headless --path . -s res://tests/net_client.gd -- --join=127.0.0.1 --port="$PORT2" --host-loss --armed-file="$ARMED" --settings-file=user://test_net_hostloss_settings.cfg --profile-file=user://test_net_client_profile.json > .net-hostloss.log 2>&1 &
CLIENT=$!
for i in $(seq 1 200); do
  [ -f "$ARMED" ] && break
  kill -0 "$CLIENT" 2>/dev/null || break
  sleep 0.1
done
pkill -9 -P "$HOST" 2>/dev/null   # the godot under `timeout` (SIGKILL on timeout itself would orphan it)
wait "$HOST" 2>/dev/null
wait "$CLIENT"; status=$?
rm -f "$ARMED"
grep -E "NET " .net-hostloss.log
if [ $status -ne 0 ] || grep -E "SCRIPT ERROR|Parse Error" .net-hostloss.log | grep -q .; then
  grep -E "SCRIPT ERROR|Parse Error|at: " .net-hostloss.log | head; echo "NET TEST FAIL (host loss)"; exit 1
fi
echo "NET TEST PASS"
