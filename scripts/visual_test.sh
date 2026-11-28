#!/usr/bin/env bash
# Run each rendered integration test with isolated saves and output.
set -euo pipefail
# VISUAL_OUTPUT=/abs/dir keeps the captures. VISUAL_CASE_TIMEOUT=N (seconds, default 180) is the
# per-case budget: camera_framing_test alone took ~132 s on llvmpipe at load 12-15 (#281).
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
command -v xvfb-run >/dev/null || { echo "Install Xvfb and xauth to run visual tests." >&2; exit 2; }
output="$(realpath -m "${VISUAL_OUTPUT:-$(mktemp -d)}")"
mkdir -p "$output"
case_timeout="${VISUAL_CASE_TIMEOUT:-180}"
# Fresh user:// per process: each case gets its own empty XDG_DATA_HOME (Godot's user:// lives
# there) and XDG_CONFIG_HOME, so nothing one case saves (settings, profile, replays) can leak into
# a later case, whatever the order (#236). XDG_CACHE_HOME stays shared: it only holds Mesa's
# compiled-shader cache, which keeps llvmpipe from recompiling every shader for every case.
userdata="$(mktemp -d)"
trap 'rm -rf "$userdata"' EXIT
export XDG_CACHE_HOME="$userdata/cache"
fresh_userdata() {
  local dir; dir="$(mktemp -d "$userdata/$1.XXXXXX")"
  export XDG_DATA_HOME="$dir/data" XDG_CONFIG_HOME="$dir/config"
}
fresh_userdata import
timeout 180 "$GODOT" --headless --path . --import

for test in tests/visual/*_test.gd; do
  name="$(basename "$test" .gd)"
  export VISUAL_CASE_OUTPUT="$(mktemp -d "$output/$name.XXXXXX")"
  fresh_userdata "$name"
  log="$VISUAL_CASE_OUTPUT/run.log"
  status=0
  env -u WAYLAND_DISPLAY LIBGL_ALWAYS_SOFTWARE=1 timeout "$case_timeout" \
      xvfb-run -a -s '-screen 0 1280x720x24' "$GODOT" --path . \
      --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
      --resolution 1280x720 --fixed-fps 60 -s "res://$test" >"$log" 2>&1 || status=$?
  if [ "$status" -ne 0 ]; then
    cat "$log"
    if [ "$status" -eq 124 ]; then
      echo "VISUAL FAIL: $name timed out after ${case_timeout}s (raise VISUAL_CASE_TIMEOUT if the machine is just slow)." >&2
    else
      echo "VISUAL FAIL: $name exited with status $status." >&2
    fi
    exit 1
  fi
  cat "$log"
  if grep -Eq 'SCRIPT ERROR|Parse Error' "$log" ||
      ! find "$VISUAL_CASE_OUTPUT" -maxdepth 1 -name '*.png' -size +0c -print -quit | grep -q .; then
    echo "VISUAL FAIL: $name reported a script error or produced no PNG." >&2
    exit 1
  fi
done
echo "VISUAL PASS ($output)"
