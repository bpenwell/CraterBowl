# Optimization log

Newest first. Every perf change gets an entry with **before/after numbers from the same machine
and mode** (protocol: `README.md` §5). Write down what didn't work too.

Machine for all entries so far: WSL2 Ubuntu 24.04, i7-11800H (16 threads), RTX 3080 Laptop GPU, Godot 4.3.
"CPU" = Xvfb + Mesa llvmpipe; "GPU" = Xvfb + Mesa d3d12 → RTX 3080 (Compatibility renderer).

---

## 2026-11-26 — coin-toss cutscene render cost (#129)
The toss cutscene hides the 14 match athletes and shows 3 puppets (2 captains + ref) and a coin.
`tests/render_budget.gd` counts on this WSL box, headless (GPU-independent):

| Scene | Triangles | Instances | Shadow casters | Materials | Skinned |
|---|---|---|---|---|---|
| Opening kickoff (the budget's scene, unchanged) | 204,060 | 226 | 85 | 142 | 14 |
| Toss cutscene, captains walking (frame 40, `--toss=0`) | 78,080 | 158 | 65 | 79 | 3 |

No budget changed. `render_budget.gd` turns the cutscene off (`toss_cutscene = false`) and takes the
bots' toss pick at frame 4, so it still measures the opening kickoff it always did. The bench
(`tools/bench.gd`) plays the cutscene in its first 5 s: scene p50 906 us, object growth 9, both inside the
budgets.

## 2026-11-26 — perf-03: flaky object-growth check from play-picker churn (#169)

`perf.sh` failed about half the time on origin/main c50b2ba with "objects grew by >= 51/52 in each of two
400-frame windows". A per-path node diff in `tools/bench.gd` showed it wasn't a leak: the play picker
freed and rebuilt its buttons on every possession change, and on some runs it was first built
during the second window. That is a first-use allocation in window 2 plus other first-use allocations in
window 1, so both windows grew. The plays are random per run, so it depended on when the bench
player first saw the picker. Bisect pointed at #155, but that was chance; #155 has no per-frame code.
Fix: build a fixed pool of picker buttons (the longest list either side shows) when the overlay is
built, and relabel/hide them per side. Same machine, CPU, 8 runs each: before, 4/8 FAIL (growth 51);
after, 8/8 PASS (growth 0 or 21, under the 50 threshold). What didn't work: growing the pool lazily
to its max size on first refresh, because the first refresh can still land in window 2.

## 2026-11-26 — perf-04: pin the bench coin toss so the object-growth gate is deterministic (#169)

Follow-up to perf-03 (#185): pooling the picker removes one of the two one-time builds, but the bench still played a
different game per run. The measurements below were taken before #185 merged.

`perf.sh` failed about half the time on origin/main @ c50b2ba (`objects grew by >= 52`). Not a leak.
`tools/bench.gd` plays the real main scene, and its opening coin toss was unseeded `randi() % 2`.
Per-frame object deltas and node-class diffs showed two outcomes:

| Toss | First-use allocations (frame) | Windows 430–830 / 830–1230 | Result |
|---|---|---|---|
| 0 | replay hint bar +107 (687); play picker 10 Buttons +58 (1296) | 107 / 0 | growth 0, PASS |
| 1 | replay hint bar +107 (483); play picker 10 Buttons +52 (1098) | 107 / 52 | growth 52, FAIL |

Two one-time UI builds landed in separate windows, so "growth in both windows" fired. Both builds are
kept and reused: 8000-frame runs plateau at 2965 objects for either toss. The #169 bisect blaming #155
was luck: ac1c6f1 gives the same 0/52 split with `--toss=0/1`.

Fix: the bench pins the toss (`--toss`, default 1) and measures leaks in two 600-frame windows after
a 1200-frame warm-up (`--frames=2400`, about 3 s more). Threshold unchanged at 50. Now growth = 5
on every run (a particle burst alive at the last checkpoint). Planted leaks still fail: `Resource.new()`
per frame reads 605, 30 Labels per snap reads 69. On failure, perf.sh prints both windows and
which node classes grew.

## 2026-11-25 — perf-02: shadow-caster budget broke on main (125/110)

Reported by the loop session on origin/main 8663257. Cause: the sideline chain crew
(`presentation._crew_member`) is 13 ellipsoid parts per member, all casting shadows (39 casters),
each with its own `SphereMesh`. The turf, regolith ground and jumbotron logo sprites also cast.
Fix: only crew torsos cast, parts share `RC.sphere(0.5, 1.0, 12, 6)`, and flat ground and logos don't cast.
Shadow casters **125 → 85**; budget ratcheted 110 → 106. No visual change expected (limb and ground
shadows are invisible at that distance). Lesson: new art layers must set `cast_shadow` deliberately.
The default is ON.

Also: the object-growth gate started failing at 57 objects. That wasn't a leak: growth stayed
flat (57/71/66 at 600/1800/3600 frames) and came from first-use allocations of newer features. The
gate now requires growth in **both** of two consecutive 400-frame windows (clean ≈ ±5; a
planted per-frame `Resource.new()` reads 405 → fail).


## 2026-11-25 — perf-01: render pass, interpolation, gates (branch `perf-optimization`)

Trigger: the user said the game "feels low quality in terms of performance". The windowed game
process sat at about 490% CPU: it was rendering on **llvmpipe** (Vulkan in WSL has no GPU driver).

### Phase 1 (primitive-mesh art, before the rigged athletes landed)
Diagnosis: Godot's default primitive meshes (SphereMesh 64x32 ≈ 4k tris) for 14 athletes plus
24 arc dots plus ball plus reticle, a separate material per mesh, every field box casting
shadows, and 4 shadow splits came to about **590k triangles, about 425 draw calls** for a scene
of capsules.

| Mode | FPS before → after | p99 frame | draws | triangles |
|---|---|---|---|---|
| CPU llvmpipe, GL compat | 4.7 → **32.7** | 457 → 152 ms | 425 → 121 | 592k → 7.7k |
| GPU d3d12, GL compat | 34.2 → **61.2** | 116 → 38 ms | 422 → 156 | 592k → 14.5k |
| CPU llvmpipe, Vulkan Forward+ | 5.3 → 23.2 | 298 → 126 ms | 507 → 157 | 592k → 7.7k |

Changes: `render_cache.gd` (shared low-poly meshes and materials), field boxes batched into one mesh
per color with no shadows, throw arc as one MultiMesh, unshaded markers and reticle with no shadows,
route art rebuilt only on change, render interpolation for athletes and ball, exp-smoothed camera.

### Phase 2 (after merging the CC0 rigged-athlete graphics overhaul)
The new art brought the cost back: **origin/main measured 9.9 fps GPU, 5.0 fps CPU,
1.23M rendered triangles, 737 draws**.

Category bisect (GPU path, `--gfx=low`, `render_bench.sh --exp=...`):

| Hidden | render CPU ms/frame | FPS |
|---|---|---|
| nothing | 127 | 6.4 |
| **skinned athlete bodies** | **16** | **32.8** |
| gear / labels / crowd / stadium / paused anim | within noise of baseline | |

3v3 (6 skinned) measured 38 ms against 127 ms for 7v7 (14): skinning costs **about 8–9 ms per
athlete** on Compatibility + d3d12, linear. Pausing AnimationPlayers doesn't help; it's the
skinning (transform feedback, emulated by Mesa d3d12), not animation playback. Native Vulkan
skins with compute shaders and should not have this cost. **Still to verify on the user's
Windows build.**

Fixes applied on top of the new art:
- Helmet, pads and visor: default `SphereMesh.new()` (4k tris each, x3 per athlete) → `RC.sphere`
  (12x6; helmet 20x12). Triangles in the scene: 1.23M → 816k rendered (GPU, gfx=high).
- Gear, numbers, collar and stripe don't cast shadows: shadow casters 162 → 92.
- Overlay HUD text refresh 60 Hz → 20 Hz; skip unchanged shader params (crowd excitement,
  ring color); skip the trail re-upload when empty. Presentation CPU about 1.6 ms → about 0.4 ms
  per frame (headless, noisy, load 9–13).
- Render interpolation re-applied to the new `player.gd` (`place`/`interpolate`). Its animation
  picker derives speed from position deltas, so it now sees smooth per-frame motion.

| Mode (gfx auto) | origin/main | perf branch |
|---|---|---|
| GPU d3d12 FPS / p99 frame | 9.9 / 520 ms | 11.4 / **117 ms** |
| CPU llvmpipe FPS | 5.0 | 4.8 (pixel-bound) |
| Headless scene tick p50 (3 runs, load ≈10) | 4.0–4.9 ms | 3.35–4.2 ms |

Takeaway: on this WSL box the rigged athletes are skinning-bound and nothing else matters
until that's solved. Options, in order: (1) measure the native Windows build; if it's fine,
WSL is just a bad test bed. (2) A lower-vertex athlete mesh for `--gfx=low`. (3) Skin at
reduced rate for off-screen or far athletes.

### Gates added
`scripts/check.sh` (lint + unit + perf + smoke), `scripts/perf.sh` (render budget plus CPU
medians), `scripts/lint.sh` (every script compiles; perf rules), `tests/test_determinism.gd`,
`tests/test_render_perf.gd`, `tests/render_budget.gd`, and the pre-commit hook
(`scripts/install-hooks.sh`). Mutation-tested: restoring 64-segment spheres makes the render
budget fail (85k > 20k on the old art).

### Didn't work / don't repeat
- `Performance.get_monitor(TIME_PROCESS/TIME_PHYSICS_PROCESS)` per frame: these are about 1 s
  averages, so per-frame spike hunting with them is meaningless. Use wall time between frames under
  `--fixed-fps 60` headless.
- Mean-based CPU gates flaked at load 5–13 (scene "8.7 ms" vs 1.0 ms idle). Use medians.
