# Daily Iteration Loop: Procedure

Each run is one iteration. Each iteration builds on the last. **Tackle exactly one issue.** Work tracking rules (labels, claim/close, side findings): `docs/workflow.md`.

## Steps
1. **Orient.** Read `docs/vision.md` (pillars), the last 3 merged PRs (`gh pr list --state merged -L 3`), and `git log --oneline -10`. Run `./scripts/test.sh` first. If it's red, open (or find) a `type:bug` issue for it; fixing it is this iteration's one thing.
2. **Pick** the first match, skipping `status:in-progress`, `status:blocked` and `status:needs-decision`:
   - open `type:bug`, oldest first, then
   - `P0`, then `P1`, then `P2`, oldest first. Issues were created in build order.

   ```bash
   F='-label:status:in-progress -label:status:blocked -label:status:needs-decision sort:created-asc'
   gh issue list --label type:bug --search "$F"; gh issue list --label P0 --search "$F"
   ```
   **Claim it:** `gh issue edit N --add-label status:in-progress` + a comment naming the session and branch. If the issue carries `question`, follow its documented default and say so in the design comment (step 3).
3. **Brainstorm.** Post a design comment on the issue (no new doc file):
   - Goal (1–2 sentences) and how Gridiron does it (genre mechanic only).
   - 2–3 design options, the pick, and why. Note one way to make it *better* than Gridiron.
   - Acceptance criteria written as testable statements: refine the issue's Scope / Accept list.
   The pick and its *why* also go in the feature doc's **Design decisions** at step 6; that's the durable home.
   - If the issue is too big for one iteration, split it: open child issues (`Part of #N`), narrow #N in a comment, and do the first part.
4. **Build.** Smallest complete version that meets the criteria.
   - Game rules/physics math go in `src/sim/` as plain `RefCounted` scripts (no Node/scene deps, deterministic, input-driven). This keeps them unit-testable and ready for server authority.
   - Scenes/visuals/input in `src/game/` + `scenes/`. Presentation reads sim state; it never owns rules.
   - Feel numbers go in `src/sim/tuning.gd` constants.
   - Scripted multi-line edits must use `tools/patch.py` `sub()` (fails loudly when a pattern doesn't match). Plain `str.replace` silently no-ops; that hid a stale key handler from iter 010 to 017.
   - Player-facing input must be tested through the real handler (`_key()` in game_flow.gd), not only by calling `do_action()` directly.
   - Use only original or CC0 assets. Never use Gridiron's name, art, UI or audio.
   - Performance: follow `docs/optimization/README.md`. Visible motion is interpolated in `_process`, not set in `_physics_process`. No default-tessellation meshes, no per-frame text rebuilds or allocations, `cast_shadow` off for small or flat things. New expensive effects go behind `src/game/art/quality.gd`.
   - **Noticed something else** (bug, gap, idea, wrong doc)? Open an issue now (`docs/workflow.md`), even if you fix it in this iteration.
5. **Test.** Add `tests/test_<area>.gd` covering every acceptance criterion. The gate is **`./scripts/check.sh`** (lint + unit + perf + smoke, about 4 min); it must end `CHECK PASS`. It runs:
   - `./scripts/test.sh`: all unit tests must pass (previous iterations' tests included).
   - `./scripts/smoke.sh`: main scene boots headless for ~300 frames with zero script errors, then `tests/game_flow.gd` drives the real scene through a scripted play. **Add a game_flow segment (`tests/flow/segments/<name>.gd`) for each new player-facing feature.**
   - `./scripts/mm_test.sh` (also run by smoke.sh): matchmaker + 2 queued clients → hosted match starts.
   - `./scripts/net_test.sh` (also run by smoke.sh): headless host + client over localhost. Extend `tests/net_client.gd` when a feature changes networked behavior.
   - `./scripts/shot.sh` for any visual change (art, HUD, camera, effects): renders the real scene offscreen (Xvfb + software GL) to PNGs. **View the PNGs before calling it done.** See `docs/TESTING.md`.
   - `./scripts/perf.sh` (in check.sh): render budget plus CPU medians. If you made something cheaper, lower its budget (ratchet); if you must raise one, log why in `docs/optimization/LOG.md`.
   Iterate until check.sh passes. Do not weaken or delete older tests to go green. **Never launch a windowed game** (`godot --path .`) to check your work; it opens on the user's desktop. Everything in `docs/TESTING.md` runs offscreen.
6. **Record.** In the same commit:
   - Update the feature doc for the area (`docs/features/<area>.md`: how it plays now, decisions and why, rejected options, what didn't work, open-issues list), and the design doc if you built a subsystem or protocol (`docs/design/`).
   - Update other owning docs (`docs/README.md` says which: testing → `docs/TESTING.md`, perf → `docs/optimization/`).
   - There is no iteration log: what was built, test counts and known gaps go in the PR description. **Every known gap is an issue**; list their numbers rather than leaving prose gaps.
7. **Open a PR** from your branch (see "Shipping" in `AGENTS.md`): commit your own files as `<title> (#N)`, merge the latest `origin/main`, re-run `./scripts/check.sh`, push the branch, and `gh pr create` with `Closes #N` plus test evidence. Never commit to or push `main`, and never merge the PR; the owner reviews and merges.
8. **Update the issue:** comment the PR link (`gh issue comment N --body "PR #M: …"`). The issue closes when the owner merges the PR. If only part is done, remove `status:in-progress`, comment what's left, and leave it open.
9. **Report.** Summarize what shipped, the test results, the issues closed/opened, and what's next, ending with a `result:` line.

## Guardrails
- One issue per iteration. If an issue is too big, split it into child issues and do the first part.
- If blocked (missing tool, a design decision only the user can make), comment on the issue, add `status:needs-decision` or `status:blocked`, and report `needs input:`. Don't guess on irreversible things.
- Keep the game runnable: `godot --path . ` opens to a playable scene after every iteration. Verify that with `./scripts/smoke.sh` + `./scripts/shot.sh`, not by opening a window.
