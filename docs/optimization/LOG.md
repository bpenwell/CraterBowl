# Optimization log

Newest first. Every perf change gets an entry with **before/after numbers from the same machine
and mode** (protocol: `README.md` §5). Write down what didn't work too.

Machine for all entries so far: WSL2 Ubuntu 24.04, i7-11800H (16 threads), RTX 3080 Laptop GPU, Godot 4.3.
"CPU" = Xvfb + Mesa llvmpipe; "GPU" = Xvfb + Mesa d3d12 → RTX 3080 (Compatibility renderer).

---

## 2026-11-26 — perf-10: the football is one mesh (#159)

The old ball was a SphereMesh stretched 1.75x plus a lace box and two `TorusMesh` stripes at the
default 64x32 tessellation (~4k triangles each). The new ball (`src/game/art/football.gd`) is one
code-built 20x14 mesh (560 triangles) with the seams, laces and stripes drawn by
`football.gdshader`. `perf.sh` render budget, same machine (native Windows, Godot 4.3, opengl3),
`feat/244-ball-carry-pose` @ d56023a vs this branch:

| | before | after |
|---|---|---|
| triangles | 204,060 | 196,064 (−7,996) |
| instances | 226 | 223 |
| shadow casters | 85 | 82 |
| materials | 142 | 141 |

Budgets in `tests/render_budget.gd` ratcheted down by the same amounts. CPU medians unchanged
within noise (scene_frame_p50 965 µs after; the ball has no per-frame work beyond its transform).

## 2026-11-26 — perf-09: catch stance and reach (#246)

Same machine and mode as perf-05, CPU load 26%, 3 rounds interleaved, scene_frame p50 / p99 medians in µs:
#245 tree 1123 (1088–1239) / 3584; #246 tree 997 (991–1074) / 2452. No measurable cost: only the few
athletes near a pass's catch point run the catch IK, and only while it's in the air. The #246 tree
measuring *faster* is noise, not a win: it only adds code, and the #245 runs had p99 spikes up to 5163 µs
in this session. Render budget unchanged (no meshes or materials).

## 2026-11-26 — perf-08: decide who looks at 10 Hz (#245)

`player.gd` now decides "near the camera" and "watches the ball" at `LOOK_DECIDE_HZ` (10 Hz, staggered by
athlete id) instead of every frame; carrying, down and celebrating still apply at once. Same machine and
mode as perf-05, CPU load 16% (quiet, so tighter spread than perf-06/07), 3 rounds interleaved,
scene_frame p50 / p99 medians in µs:

| Tree | p50 | p99 |
|---|---|---|
| #244 baseline | 919 (909–929) | 1898 |
| role rules, decided every frame | 969 (963–972) | 1927 |
| role rules, decided at 10 Hz | 948 (942–993) | 1924 |

The head look's cost goes from about +50 to about +29 µs/frame (about 3% of this headless frame). Round 1 of
the throttled tree was an outlier (993); rounds 2–3 were 21–27 µs under the per-frame tree. Remaining cost:
the look math for the athletes who do look, plus the per-frame target and blend update.

## 2026-11-26 — perf-07: only athletes who need the ball watch it (#245)

Behavior change for realism (owner's call): defense reads the ball unless blocked; offensive linemen
only on a loose ball nearby; other offense at the snap and on a pass or loose ball within 15 yd;
nobody while engaged (`player.gd` `watches_ball()`). Same machine and mode as perf-05, CPU load 46%,
3 rounds interleaved, scene_frame p50 medians in µs: #244 baseline 953 (935–987); camera cutoff only
1022 (1016–1044); cutoff + role rules 1023 (1015–1038). No measurable gain: fewer heads run the look
math, but every view now runs the role check per frame, and the net is inside the noise (about ±40 µs
at this load). Note the cutoff-only tree measured +69 here vs +41 in perf-06: the remaining cost of
the feature is roughly +40 to +70 µs/frame. Likely next step if it matters: decide "near camera" and
"watches the ball" at 10 Hz (staggered by athlete id) instead of every frame, since those decisions
rarely change frame to frame; only the look target and weight need per-frame updates.

## 2026-11-26 — perf-06: where the head look's cost goes, and a camera-distance cutoff (#245)

Same machine and mode as perf-05. **Attribution** (variants of `athlete_pose.gd` swapped into one tree,
interleaved with the #244 baseline, 3 rounds, scene_frame p50 medians in µs, CPU load 18%): baseline 998;
`player.gd` target/weight update only 978; the two bone writes only (no math) 1002; the look math only
(no bone writes) 1032; full look 1055. So the cost is the GDScript math in `_look()` (several `Basis`
builds and two inverses per athlete), not the bone writes; run-to-run noise is about ±50 µs, so the
split is rough. **Fix:** heads only turn when the athlete is big enough on screen to see it
(`player.gd` `head_visible()`: distance × tan(fov/2) < `LOOK_VIEW_SIZE` 16 yd, about 25 yd for the 65°
follow camera), and views that don't look and have faded out skip the look entirely.

| Tree (3 rounds interleaved, CPU load 48%) | scene_frame p50 | scene_frame p99 |
|---|---|---|
| #244 baseline | 958 (927–1013) | 2284 |
| head look before the cutoff | 1031 (992–1040) | 2410 |
| head look with the cutoff | 999 (993–1025) | 2550 |

The cutoff cuts the look's cost from about +73 to +41 µs/frame. Not done: rewriting `_look()` to
rotate in each bone's local frame (fewer `Basis` ops); worth it only if the remaining ~40 µs matters.

## 2026-11-26 — perf-05: cost of procedural head look (#245)

Machine: native Windows 11, RTX 3060 Ti, Godot 4.3 console exe, `./scripts/perf.sh` (headless bench, so CPU-side
only), CPU load 19% at start. Three trees, interleaved, 3 rounds each; medians in µs.

| Tree | scene_frame p50 | scene_frame p99 | sim_tick p50 |
|---|---|---|---|
| #244 carry pose only (baseline) | 953 (920–998) | 2436 | 120 |
| #245 head look, first version | 1052 (1008–1076) | 2730 | 118 |
| #245 after review fixes | 1050 (1040–1089) | 2713 | 118 |

The head look costs about +100 µs/frame (+10%): the `AthletePose` modifier now runs for all 14 athletes
(neck + head, a few `get_bone_global_pose` reads each) instead of only the carrier. The sim is unchanged.
Render budget unchanged (no meshes, materials or shadow casters). What didn't help: the review fixes
(cache the rig check instead of building `_bones.values()` per athlete per frame, and drop a per-call `[]`
default in `_open_hand`) removed the per-frame allocations but made no measurable difference (1052 vs 1050,
inside run-to-run noise of about 150 µs). Not measured: real-GPU frame time with a window.

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
