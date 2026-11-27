#!/usr/bin/env bash
# Offscreen screenshots of the real game, with no window on the desktop.
# Runs tools/capture.gd under a private Xvfb display with Mesa software GL (llvmpipe),
# so it works in WSL/CI without a GPU and never pops a WSLg window.
#
#   ./scripts/shot.sh --frames=60,200 --snap=100                 # pre-snap + mid-play
#   ./scripts/shot.sh --out=/tmp/shots/hud --frames=30 --size=5  # extra args reach main.gd
#   ./scripts/shot.sh --frames=400 --press=100:Space,300:V       # real key handler (V = replay)
#
# Prints one "SHOT <abs path>" line per PNG. Open them with your image viewer/Read tool.
# Exits non-zero on script errors or if no PNG was written. See docs/TESTING.md.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
RES="${RES:-1280x720}"
# Native Windows (Git Bash): no Xvfb there, so render on the real GPU in a window parked
# far off-screen. Nothing shows on the desktop, but a taskbar button flashes for the run.
WINDOWS=0
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WINDOWS=1 ;; esac
[ $WINDOWS = 1 ] || command -v xvfb-run >/dev/null || { echo "shot.sh needs xvfb-run: sudo apt install xvfb"; exit 2; }

args=("$@")
has() { for a in "${args[@]}"; do [[ "$a" == --$1=* || "$a" == --$1 ]] && return 0; done; return 1; }
# Default output prefix outside the repo; per-job tmp when running as a background job.
SHOT_DIR="${SHOT_DIR:-${CLAUDE_JOB_DIR:+$CLAUDE_JOB_DIR/tmp/shots}}"
SHOT_DIR="${SHOT_DIR:-/tmp/crater-bowl-shots}"
# Windows Godot can't resolve MSYS paths like /tmp; hand it a C:/... path.
[ $WINDOWS = 1 ] && { mkdir -p "$SHOT_DIR"; SHOT_DIR="$(cygpath -m "$SHOT_DIR")"; }
has out || args+=("--out=$SHOT_DIR/shot")
# Never touch the player's real profile/leaderboard/ratings/replays.
has profile-file     || args+=("--profile-file=user://test_shot_profile.json")
has leaderboard-file || args+=("--leaderboard-file=user://test_shot_lb.json")
has ranked-file      || args+=("--ranked-file=user://test_shot_ranked.json")
has replay-dir       || args+=("--replay-dir=user://test_shot_replays")

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
LOG="$(mktemp "${TMPDIR:-/tmp}/shot.XXXXXX.log")"
if [ $WINDOWS = 1 ]; then
  timeout "${TIMEOUT:-240}" \
    "$GODOT" --path . --rendering-driver opengl3 --audio-driver Dummy --position -20000,-20000 \
    --resolution "$RES" --fixed-fps 60 -s res://tools/capture.gd -- "${args[@]}" > "$LOG" 2>&1
else
  # -a picks a free display number, so parallel sessions don't collide.
  env -u WAYLAND_DISPLAY timeout "${TIMEOUT:-240}" \
    xvfb-run -a -s "-screen 0 ${RES}x24" \
    "$GODOT" --path . --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
    --resolution "$RES" --fixed-fps 60 -s res://tools/capture.gd -- "${args[@]}" > "$LOG" 2>&1
fi
status=$?
grep -E "^SHOT |^CAPTURE " "$LOG"
if grep -E "SCRIPT ERROR|Parse Error|CAPTURE FAIL" "$LOG" | grep -q .; then
  grep -E "SCRIPT ERROR|Parse Error|CAPTURE FAIL|at: " "$LOG" | head -20; echo "SHOT FAIL (script errors, log: $LOG)"; exit 1
fi
if [ $status -ne 0 ] || ! grep -q "^SHOT .*(OK)" "$LOG"; then
  tail -20 "$LOG"; echo "SHOT FAIL (exit $status, log: $LOG)"; exit 1
fi
rm -f "$LOG"
