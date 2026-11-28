#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
export APT_TEST_SOURCE="$scratch/ubuntu.sources"
export APT_TEST_LOG="$scratch/apt.log"
touch "$APT_TEST_SOURCE"

# Model the hosted runner with an unrelated broken source. Never call real sudo.
cat > "$scratch/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == apt-get ]]
shift
if [[ "${1-}" != -o || "${2-}" != "Dir::Etc::SourceList=$APT_TEST_SOURCE" ||
      "${3-}" != -o || "${4-}" != Dir::Etc::SourceParts=- ]]; then
  echo "Optional APT source returned 403" >&2
  exit 100
fi
shift 4
echo "$1" >> "$APT_TEST_LOG"
if [[ "$1" == update ]]; then
  [[ "$2" == --error-on=any ]]
  exit "${APT_TEST_UPDATE_STATUS:-0}"
fi
[[ "$*" == "install -y xvfb xauth libgl1-mesa-dri libgl1" ]]
EOF
chmod +x "$scratch/sudo"
export PATH="$scratch:$PATH"

bash scripts/install_ci_renderer.sh "$APT_TEST_SOURCE"
[[ "$(cat "$APT_TEST_LOG")" == $'update\ninstall' ]]
echo "CI SETUP PASS: renderer install ignores unrelated APT sources"

: > "$APT_TEST_LOG"
status=0
APT_TEST_UPDATE_STATUS=100 bash scripts/install_ci_renderer.sh "$APT_TEST_SOURCE" || status=$?
[[ "$status" == 100 && "$(cat "$APT_TEST_LOG")" == update ]]
echo "CI SETUP PASS: required archive failure stops renderer installation"

status=0
output="$(GODOT="$scratch/missing-godot" ./scripts/check.sh --fast 2>&1)" || status=$?
[[ "$status" == 1 && "$output" == *"Godot executable '$scratch/missing-godot' not found"* ]]
[[ "$output" != *"== lint"* ]]
echo "CI SETUP PASS: check.sh diagnoses missing Godot before lint"
