#!/usr/bin/env bash
# Before/after screenshots for a visual change: run the SAME capture on a base ref (default
# origin/main, in a throwaway worktree) and on this working tree (uncommitted changes included),
# then pair the PNGs by name and build one side-by-side image per pair.
#
#   ./scripts/before_after.sh menu                                   # every main-menu screen
#   ./scripts/before_after.sh potg                                   # post-game flow
#   ./scripts/before_after.sh shot presnap --no-kickoff --frames=60 --snap=120
#   ./scripts/before_after.sh visual scorebug                        # tests/visual/scorebug_test.gd
#   ./scripts/before_after.sh --base=abc123 --out=/tmp/ba menu       # other base / output dir
#
# Runs accumulate in one output dir, so call it once per kind you need:
#   OUT/before/<name>.png  OUT/after/<name>.png  OUT/compare/<name>.png  (before left, after right)
# and it prints "PAIR <name> changed=<pct>%" per pair. A pair you meant to change that says
# UNCHANGED has no sampled changes beyond tolerance. Positive changes that round to 0.0%
# display as <0.1%. Menu animations can move a few percent of pixels. Look at compare/*.png.
# Sides run one after the other (PARALLEL=1 halves the time but adds timing drift).
# Publish with ./scripts/pr_evidence.sh <PR#> OUT. Guide: docs/TESTING.md "Before/after screenshots".
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
GODOT="${GODOT:-godot}"
RES="${RES:-1280x720}"
command -v xvfb-run >/dev/null || { echo "before_after.sh needs xvfb-run: sudo apt install xvfb"; exit 2; }

BASE="origin/main"
OUT="${CLAUDE_JOB_DIR:+$CLAUDE_JOB_DIR/tmp/before-after}"
OUT="${OUT:-${TMPDIR:-/tmp}/crater-before-after}"
while [[ $# -gt 0 && "$1" == --* ]]; do
  case "$1" in
    --base=*) BASE="${1#--base=}" ;;
    --out=*) OUT="${1#--out=}" ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
  shift
done
KIND="${1:-}"; shift || true
usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
case "$KIND" in
  menu|potg) ;;
  shot|visual) [[ $# -ge 1 ]] || usage; NAME="$1"; shift ;;
  *) usage ;;
esac
OUT="$(realpath -m "$OUT")"
mkdir -p "$OUT/before" "$OUT/after" "$OUT/compare"

SHA="$(git rev-parse --verify --quiet "$BASE^{commit}")" || { echo "unknown base ref: $BASE"; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/crater-ba.XXXXXX")"
BASE_TREE="$WORK/base"
cleanup() { git worktree remove --force "$BASE_TREE" >/dev/null 2>&1; rm -rf "$WORK"; }
trap cleanup EXIT
git worktree add --detach --quiet "$BASE_TREE" "$SHA" || { echo "could not create base worktree at $SHA"; exit 1; }
# Seed the import cache from this tree: unchanged assets skip reimport (much faster first run).
[[ -d .godot ]] && cp -r .godot "$BASE_TREE/" 2>/dev/null
echo "$BASE $(git rev-parse --short "$SHA")" > "$OUT/base.txt"
echo "BEFORE $BASE ($(git log -1 --format='%h %s' "$SHA" | cut -c1-70))"
echo "AFTER  working tree ($(git rev-parse --short HEAD)$(git diff --quiet HEAD -- . 2>/dev/null || echo ' + uncommitted changes'))"

# A capture script or visual test that only exists on this branch is copied into the base tree,
# so the base can be photographed with the new test (its checks may fail there; that's expected).
carry() { [[ -f "$BASE_TREE/$1" ]] || { mkdir -p "$BASE_TREE/$(dirname "$1")"; cp "$ROOT/$1" "$BASE_TREE/$1"; echo "(carried $1 into the base tree)"; }; }

# run_side <tree> <before|after>: one capture into $OUT/<side>, with throwaway user data.
run_side() {
  local tree="$1" side="$2" dest="$OUT/$2" data log status=0
  shift 2
  data="$(mktemp -d "$WORK/data-$side.XXXX")"
  log="$WORK/$side.log"
  export XDG_DATA_HOME="$data/data" XDG_CONFIG_HOME="$data/config" XDG_CACHE_HOME="$data/cache"
  (cd "$tree" && "$GODOT" --headless --path . --import >/dev/null 2>&1)
  local render=(env -u WAYLAND_DISPLAY timeout "${TIMEOUT:-240}" xvfb-run -a -s "-screen 0 ${RES}x24"
    "$GODOT" --path "$tree" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy
    --resolution "$RES" --fixed-fps 60)
  case "$KIND" in
    menu) "${render[@]}" -s res://tools/menu_capture.gd -- --out="$dest/menu" \
            --settings-file=user://ba_settings.cfg >"$log" 2>&1 || status=$? ;;
    potg) "${render[@]}" -s res://tools/potg_capture.gd -- --out="$dest/potg" \
            --settings-file=user://ba_settings.cfg >"$log" 2>&1 || status=$? ;;
    shot) (cd "$tree" && ./scripts/shot.sh --out="$dest/$NAME" "$@") >"$log" 2>&1 || status=$? ;;
    visual)
      local case_dir="$WORK/visual-$side"; mkdir -p "$case_dir"
      VISUAL_CASE_OUTPUT="$case_dir" "${render[@]}" -s "res://tests/visual/${NAME}_test.gd" >"$log" 2>&1 || status=$?
      for f in "$case_dir"/*.png; do [[ -e "$f" ]] && { local b; b="$(basename "$f")"; cp "$f" "$dest/${NAME}-${b#"$NAME"-}"; }; done ;;
  esac
  if ! grep -qE "^SHOT .*\(OK\)|VISUAL OK capture" "$log"; then
    echo "$side: NO CAPTURES (exit $status). Last lines of $side log:"; tail -15 "$log"; return 1
  fi
  if [[ $status -ne 0 ]]; then
    if [[ "$side" == before && "$KIND" == visual ]]; then
      echo "before: visual checks failed on the base (expected when they cover the new behavior)"
    else
      echo "$side: capture exited $status"; grep -E "SCRIPT ERROR|VISUAL FAIL|SHOT FAIL" "$log" | head -10
      return "$status"
    fi
  fi
}

case "$KIND" in
  menu) carry tools/menu_capture.gd ;;
  potg) carry tools/potg_capture.gd ;;
  shot) carry scripts/shot.sh; carry tools/capture.gd ;;
  visual) [[ -f "tests/visual/${NAME}_test.gd" ]] || { echo "no tests/visual/${NAME}_test.gd"; exit 2; }
          carry tests/visual/harness.gd; carry "tests/visual/${NAME}_test.gd" ;;
esac

# One side at a time by default: two llvmpipe renders at once load the CPU enough that
# time-driven motion (camera smoothing) drifts, and an untouched frame then "changes" ~40%.
if [[ -n "${PARALLEL:-}" ]]; then
  run_side "$BASE_TREE" before "$@" & pb=$!
  run_side "$ROOT" after "$@" & pa=$!
  wait $pb; sb=$?; wait $pa; sa=$?
else
  run_side "$BASE_TREE" before "$@"; sb=$?
  run_side "$ROOT" after "$@"; sa=$?
fi
[[ $sb -eq 0 && $sa -eq 0 ]] || { echo "BEFORE/AFTER FAIL"; exit 1; }

if ! comparison=$("$GODOT" --headless --path "$ROOT" -s res://tools/compare.gd -- \
  --before="$OUT/before" --after="$OUT/after" --out="$OUT/compare" 2>&1); then
  printf '%s\n' "$comparison" >&2
  echo "BEFORE/AFTER FAIL: comparison" >&2
  exit 1
fi
printf '%s\n' "$comparison" | grep -E "^(PAIR|ONLY_)"
echo "BEFORE/AFTER OK  $OUT  (view compare/*.png; publish: ./scripts/pr_evidence.sh <PR#> $OUT)"
