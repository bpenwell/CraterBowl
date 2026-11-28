#!/usr/bin/env bash
# Static checks: every script compiles + perf anti-pattern rules. ~5s. Exit non-zero on failure.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
out=$("$GODOT" --headless --path . -s res://tools/lint.gd 2>&1)
echo "$out" | grep -E "^LINT|SCRIPT ERROR|Parse Error"
fail=0
echo "$out" | grep -q "^LINT PASS" || fail=1
# Perf rule 1: per-entity view code (instantiated once per athlete) takes primitive meshes from
# src/game/render_cache.gd: shared + low-poly. Godot's SphereMesh default alone is ~4k triangles.
# One-off builders (field, stadium, presentation) may create meshes; the scene budget
# (tests/render_budget.gd) still caps the total.
hits=$(grep -nE "(SphereMesh|CapsuleMesh|BoxMesh|CylinderMesh|TorusMesh|PlaneMesh|PrismMesh|QuadMesh)\.new\(\)" src/game/player.gd || true)
if [ -n "$hits" ]; then echo "$hits"; echo "LINT FAIL: create meshes/materials via RenderCache (docs/optimization/README.md#rendering)"; fail=1; fi
# Perf rule 2: the sim stays engine-free (no nodes/scenes/rendering) so it is testable, deterministic and server-safe.
hits=$(grep -nE "extends Node|get_tree\(\)|RenderingServer|Input\.|OS\.get_ticks|Time\.get_ticks|randf\(|randi\(" src/sim/*.gd || true)
if [ -n "$hits" ]; then echo "$hits"; echo "LINT FAIL: src/sim must be pure RefCounted, deterministic, no engine/time/random calls"; fail=1; fi
# Rule 3: file-size ratchet. Big shared files are where merge conflicts come from (scripts/size_budget.txt).
bash scripts/size_check.sh || fail=1
[ $fail -eq 0 ] && echo "LINT RULES PASS"
exit $fail
