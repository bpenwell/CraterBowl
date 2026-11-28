#!/usr/bin/env bash
# #406: run the production smoke wrapper against a disposable gameplay process.
set -euo pipefail
cd "$(dirname "$0")/.."

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/scripts"
cp scripts/smoke.sh "$fixture/scripts/"
cat > "$fixture/godot" <<'GODOT'
#!/usr/bin/env bash
if [[ "$*" == *res://tests/game_flow.gd* ]]; then
  echo "  FLOW OK fixture reached the gameplay loop"
  if [[ "$FIXTURE_FLOW" == hang ]]; then
    exec sleep 3
  fi
  echo "  FLOW FAIL fixture assertion"
  exit 1
fi
GODOT
chmod +x "$fixture/godot"

expect_flow_failure() {
  local status=0
  result="$(GODOT="$fixture/godot" XDG_DATA_HOME="$fixture/user-data" \
    GAME_FLOW_TIMEOUT=1 FIXTURE_FLOW="$1" bash "$fixture/scripts/smoke.sh" 2>&1)" || status=$?
  if [[ $status != 1 || "$result" != *"$2"* || "$result" != *"$3"* ]]; then
    printf 'SMOKE TIMEOUT TEST FAIL (%s, exit %s)\n%s\n' "$1" "$status" "$result" >&2
    exit 1
  fi
}

expect_flow_failure hang "GAME FLOW FAIL: timed out after 1s" "fixture reached the gameplay loop"
expect_flow_failure assertion "GAME FLOW FAIL" "FLOW FAIL fixture assertion"
[[ "$result" != *"timed out"* ]] || { printf '%s\n' "$result" >&2; exit 1; }
echo "SMOKE TIMEOUT TEST PASS"
