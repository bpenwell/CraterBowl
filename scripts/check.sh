#!/usr/bin/env bash
# The one gate. Run before every commit that touches code.
#   ./scripts/check.sh          full: lint + unit + perf + smoke (flow, net, matchmaking)  ~3-4 min
#   ./scripts/check.sh --fast   lint + unit + perf (what the pre-commit hook runs)          ~45 s
# Never opens a window. See docs/TESTING.md.
set -uo pipefail
cd "$(dirname "$0")/.."
godot_bin="${GODOT:-godot}"
if ! command -v "$godot_bin" >/dev/null; then
  echo "CHECK FAIL: setup. Godot executable '$godot_bin' not found. Install Godot or set GODOT to its path." >&2
  exit 1
fi
start=$(date +%s)
# Isolate user:// (Godot uses $XDG_DATA_HOME on Linux): tests can never touch the player's real
# saves/settings, and edits the user (or another session) makes mid-run can't fail the guard.
# A fresh empty dir also shows how a first-time player boots (no profile, no settings).
export XDG_DATA_HOME="$(mktemp -d "${TMPDIR:-/tmp}/fl-userdata.XXXXXX")"
trap 'rm -rf "$XDG_DATA_HOME"' EXIT
step() {
  local name=$1; shift
  echo "== $name"
  if "$@" > "${TMPDIR:-/tmp}/fl-check-$$-$name.log" 2>&1; then
    echo "   ok ($name)"
    grep -h "SIZE WARN" "${TMPDIR:-/tmp}/fl-check-$$-$name.log" | sed 's/^/   /'   # warnings survive a pass
    rm -f "${TMPDIR:-/tmp}/fl-check-$$-$name.log"
  else
    tail -25 "${TMPDIR:-/tmp}/fl-check-$$-$name.log"; echo "CHECK FAIL: $name (full log: ${TMPDIR:-/tmp}/fl-check-$$-$name.log)"; exit 1
  fi
}
step lint ./scripts/lint.sh
step unit ./scripts/test.sh
step perf ./scripts/perf.sh
if [ "${1:-}" != "--fast" ]; then
  step smoke ./scripts/smoke.sh
fi
echo "CHECK PASS ($(( $(date +%s) - start ))s${1:+ $1})"
