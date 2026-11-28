#!/usr/bin/env bash
# Render real scorebug captures and block one destination file in the comparison directory.
set -euo pipefail
cd "$(dirname "$0")/.."

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
out="$(realpath -m "${BEFORE_AFTER_COMPARE_TEST_OUTPUT:-$scratch}")"
shot=scorebug-kickoff.png
mkdir -p "$out/compare/$shot"

status=0
./scripts/before_after.sh --base=HEAD --out="$out" visual scorebug > "$out/run.log" 2>&1 || status=$?
cat "$out/run.log"
if [[ $status -eq 0 ]] || grep -q '^BEFORE/AFTER OK' "$out/run.log"; then
  echo "COMPARE TEST FAIL: the failed comparison reported success" >&2
  exit 1
fi
grep -Fq "Could not save comparison PNG: $out/compare/$shot" "$out/run.log"
grep -q '^BEFORE/AFTER FAIL: comparison' "$out/run.log"
test -s "$out/before/$shot"
test -s "$out/after/$shot"
echo "COMPARE TEST PASS"
