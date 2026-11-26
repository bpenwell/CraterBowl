#!/usr/bin/env bash
# Run all headless unit tests. Exit non-zero on failure.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://tests/run_tests.gd 2>&1 | tee .test-output.log
status=${PIPESTATUS[0]}
if grep -qE "SCRIPT ERROR|Parse Error|still in use at exit" .test-output.log; then echo "Script errors or leaks detected"; exit 1; fi
# Engine errors (e.g. the dummy renderer's `Parameter "m" is null`, #179) don't fail a test
# by themselves, so fail the run here. Each one prints before the PASS/FAIL line of its test.
if grep -q "ERROR:" .test-output.log; then
  awk '/ERROR:/{e=e $0 "\n"; getline; e=e $0 "\n"; next} e && /^  (PASS|FAIL) /{printf "%s  in %s\n", e, $2; e=""}' .test-output.log
  echo "Engine errors detected"; exit 1
fi
exit "$status"
