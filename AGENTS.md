# Crater Bowl (repo: football-game): agent guide

Godot 4.3 arcade online football. This file is the entry point for any agent, human or
looped. It's short on purpose: each section links to the doc that owns the details (`docs/README.md`).

| Need | Read |
|---|---|
| Iteration procedure (orient → pick → design → build → check → record → commit) | `LOOP.md` |
| **What to work on, status, bugs, ideas** | **GitHub issues** (`gh issue list`), rules in `docs/workflow.md` |
| How a feature plays today (feature level) | `docs/features/<area>.md` |
| How it's built (design level) | `docs/design/` (architecture, netcode, voice chat, regression baselines) |
| Vision and pillars, history | `docs/vision.md`; history is merged PRs, closed issues and `git log` |
| Old ids (`B09`, `C05`…) → issue # | `docs/backlog/legacy-ids.md` |
| How to test anything without a window | `docs/TESTING.md` |
| Performance rules, budgets, measuring | `docs/optimization/README.md`, `docs/optimization/LOG.md` |
| Menus, brand, distribution | `docs/features/out-of-game.md` |

### Work tracking: GitHub issues (always)
The backlog, bugs, ideas and owner decisions live **only** in GitHub issues on `bpenwell/CraterBowl`,
not in markdown checklists. Full protocol with `gh` commands: `docs/workflow.md`.
1. **Keep issues updated.** Claim the issue when you start (`status:in-progress` + a comment naming your
   session and branch). Comment on material changes. When you ship, close it with SHA, iteration, tests,
   docs and follow-ups. No issue for your task? Create one first.
2. **Side findings become new issues immediately.** This covers any bug, gap, improvement, wrong doc,
   flaky test or owner question you notice that isn't your current objective. Open an issue at the moment
   you notice, labelled type/priority/area, saying where you saw it. You may still fix it in the same change
   (then close it with that commit). The point is a traceable history to come back to. List the issues
   you opened in your report.

### Shipping: one PR per change; the owner reviews and merges
Every change reaches `main` through a GitHub PR that the owner reviews and merges. Never commit to
or push `main` yourself, and never merge a PR (not even your own, not even when checks are green).
1. **Own worktree, own branch** off the latest `origin/main`:
   `git fetch origin && git worktree add ../football-game-<topic> -b <type>/<N>-<topic> origin/main`.
   Parallel sessions share this machine. Never `git stash`, reset or check out files in someone else's
   worktree, and stage only your own paths (`git add <files>`, not `git add -A`).
2. **Before opening:** merge the latest `origin/main` into your branch, run `./scripts/check.sh` (must
   pass), then `git push -u origin <branch>`.
3. **Open the PR:** `gh pr create` with what changed and why, how it was verified (check.sh results,
   screenshots for visual changes per the PR evidence rules), and `Closes #N`. One issue or feature per PR.
4. **After review:** push fixes to the same branch. If `main` moves, merge it in and re-run check.sh.
5. **Clean up** once the owner merges: remove your worktree (`git worktree remove ../football-game-<topic>`),
   or run `/football-janitor`, which removes merged, clean and idle worktrees and branches for everyone.
- New end-to-end flow coverage goes in its own `tests/flow/segments/<name>.gd` (see `tests/flow/segment.gd`),
  not in `tests/game_flow.gd`'s shared step array. Segments get relative frames, so there's no window to claim.

### Opening pull requests

- Use the headings `### Motivation`, `### Solution`, and `### Testing` in the PR description.
- Add automated integration coverage for the specific behavior changed. The new test must
  generate a screenshot or video of the exercised state. Inspect the capture before sharing it.
- In Testing, name the automated checks that produced the evidence. **Visual changes embed
  before/after pairs** (same capture on `origin/main` and on the branch):
  `./scripts/before_after.sh <menu|potg|shot NAME ...|visual CASE>`, look at the compare PNGs,
  then `./scripts/pr_evidence.sh <PR#> <out>` and paste its Before | After table with captions
  saying what to look at. Rules and examples: `docs/TESTING.md` "Before/after screenshots".
  For video evidence, embed the uploaded video where GitHub supports playback or embed a
  test-generated screenshot and link to the video. Verify the media displays in the PR.
  Include the Actions artifact link for the full set of captures and logs.
- Use a topic branch based on `origin/main` and open the PR after verification. Preserve other
  sessions' work (see Shipping above).

### Building your own loop

Every unit of work, whether a loop iteration, a bug fix or a perf pass, has the same shape:

1. **Orient.** `git log --oneline -10`, the issue you're on (or `docs/workflow.md` → find work), and `./scripts/check.sh --fast`. If it's red, fixing it is the job (open a `type:bug` issue for it).
2. **Define done first.** Write acceptance criteria as testable statements in the issue (Scope / Accept).
3. **Smallest complete change.** One item per loop. Rules in `src/sim`, visuals in `src/game`.
4. **Gate.** `./scripts/check.sh` must print `CHECK PASS`. Add tests for every criterion *before* calling it done.
5. **Look** at visual changes with `./scripts/shot.sh` and actually view the PNGs; for the PR, capture before/after pairs with `./scripts/before_after.sh`.
6. **Record.** Docs that own what you changed (below), the PR description (what, why, tests, follow-up issues), and the issue itself (link the PR or narrow it).
7. **Ship a PR** (see Shipping above): commit your own files on your branch, check `git show --stat`, push, and `gh pr create`. Never commit to `main` and never merge.

A loop that can't measure its own success isn't done. If an item has no test, perf number or
screenshot proving it, add one.

### Testing

**Never open a game window** (`godot --path .`, `godot -e`). In WSL it pops up on the user's
desktop, and five sessions share this machine. Everything below runs offscreen and parallel-safe.
Full guide: `docs/TESTING.md`.

| Command | What | Time |
|---|---|---|
| `./scripts/check.sh` | **the gate**: lint + unit + perf + smoke, fail-fast | 3–4 min |
| `./scripts/check.sh --fast` | lint + unit + perf (the pre-commit hook) | about 45 s |
| `./scripts/test.sh` | unit tests `tests/test_*.gd` (incl. determinism) | about 10 s |
| `./scripts/smoke.sh` | headless boot + `game_flow.gd` + `menu_flow.gd` + net + matchmaking | 2–3 min |
| `./scripts/shot.sh --frames=60,200 --snap=100` | real-renderer PNGs via Xvfb. **View them.** | about 30 s |
| `./scripts/visual_test.sh` | rendered integration tests in `tests/visual/` (what CI runs). Linux/WSL only | about 2.5 min |
| `./scripts/before_after.sh menu` (or `shot NAME ...`, `visual CASE`, `potg`) | same capture on `origin/main` and your tree, side by side: the PR's visual evidence | 1–4 min |

- New player-facing behavior gets a game_flow segment (`tests/flow/segments/<name>.gd`), driven through the
  real input handler (`flow._key()`). Run just yours with `-s res://tests/game_flow.gd -- --segment=<name>`. New networked behavior extends `tests/net_client.gd`.
- A new check must go red when you plant the bug it's meant to catch. Try it once.
- Don't weaken or delete older tests to go green. `check.sh` isolates `user://` (temp
  `XDG_DATA_HOME`), so tests can't touch real saves.
- Run `./scripts/check.sh` before you commit. An opt-in pre-commit hook (`./scripts/install-hooks.sh`) runs
  `check.sh --fast` on commits that stage code files. Nothing installs it by default, and installing it turns it on for every
  worktree of the clone. Details: `docs/TESTING.md`.

#### Regressions: every change is asserted or visible

Green CI only proves what someone asserted. Changes nobody asserted slip through (#93, #110, #115,
#75), and with three developers each reviewing their own slice, nobody notices. These rules close
that gap. Design and rollout: `docs/design/regression-baselines.md` (#121).

- **Fixing a regression? Add the test that would have caught it.** That means an assertion through
  the real entry point, plus a `tests/visual` capture if the bug was visible. Plant the bug once and
  watch the test go red.
- **Every player-visible state you add or change gets a named capture.** Write a
  `tests/visual/<scenario>_test.gd` that sets up exact state, makes its `check()` assertions, then
  calls `capture()`, as `scorebug_test.gd` does. These captures are what CI compares against main.
  A screen without one can regress silently.
- **Captures must be reproducible.** Don't depend on wall-clock time or on how many frames have run.
  Settle camera easing and animations before `capture()`. Most existing captures don't do this
  yet (#124), so don't add new ones that copy the problem.
- **Capture names are baseline keys.** Never rename or delete a capture to make a diff go away. A
  renamed capture shows up as removed + new and loses its comparison.
- **Declare gameplay changes.** If your change can alter play outcomes (`src/sim`, `tuning.gd`, AI,
  playbook), say under Testing which outcomes should move and why. *Once `./scripts/golden.sh` lands
  (#121 phase 1):* it fails on any changed situation line or out-of-range stat. Run
  `./scripts/golden.sh --update`, commit `tests/golden/situations.golden.txt`, and paste its
  `GOLDEN:` summary with one reason per group that moved. Never hand-edit the golden file; on a
  conflict, merge `origin/main` and re-run `--update`. Never widen a range in
  `tests/golden/stat_ranges.cfg` to go green. A range moves only for a stated balance reason.
- **Agents never approve their own diffs.** Never run `golden.sh --update` without explaining the
  resulting diff in the PR. *Once the `visual-diff` check lands (#121 phase 2):* a human maintainer
  approves visual changes by adding the `visuals-ok` label. Agents never add that label.
- **On macOS or Windows,** `shot.sh` and `visual_test.sh` can't run (they need Xvfb). Push a draft
  PR, then look at your captures in the run's `visual-test-evidence` artifact
  (`gh run download <run-id> -n visual-test-evidence`). `remote_shots.sh` (#121) will replace this.

### Optimization

The game must feel smooth: frame-time **p99** over mean FPS. Rules (details and the why:
`docs/optimization/README.md`):

- **Sim at 60 Hz, render at display rate.** Anything visible that moves is interpolated in
  `_process` (`place()`/`interpolate(f)`), never only set in `_physics_process`. Teleports snap.
  Smoothing uses `1 - exp(-k*dt)`.
- **No default-tessellation meshes** (`SphereMesh.new()` ≈ 4k tris). Use `src/game/render_cache.gd`.
  Share meshes and materials.
- **Shadows only from things that need them.** Flat, small, UI-ish and transparent geometry gets `cast_shadow = OFF`.
- **Skinned athletes are the most expensive thing on screen** (about 8 ms each on WSL's GL path). Measure before adding bones, verts or characters.
- **Per-frame work is change-driven.** Text at 10–20 Hz, no mesh rebuilds or shader-param pushes
  when nothing changed, no allocations or `print()` per frame.
- **Expensive effects go behind `src/game/art/quality.gd`** (`--gfx=low|medium|high`).
- `./scripts/perf.sh` enforces budgets (render counts plus CPU medians). Ratchet: lower a budget when you
  make something cheaper; raise one only with a written reason in `docs/optimization/LOG.md`.
- Claim a perf win only with before/after numbers: `./scripts/render_bench.sh`
  (`GPU=1` for the real GPU via d3d12), interleaved runs, `uptime` noted. This WSL box is not
  player hardware; feel on real hardware is the user's call (native Windows build).

### Where new code goes (keeping PRs from conflicting)

About one in four "merge main into branch" syncs conflicted, and the conflicts almost always came
from a few shared spots that every feature extends at the same point: `src/game/main.gd` (the
key handler, `_process`, the aim arc, route drawing, the var block), `tests/game_flow.gd` (the
one step array and its var block), the "Code and tests" and "Open issues" tails of
`docs/features/*.md`, and `src/net/protocol.gd` snapshot/action code. Two PRs that are each
green can also break `main` together (#205 + #129). CI now runs on `main` after every merge, so
that kind of break shows up right away.

- **New behavior goes in a new file** that the switchboard calls, not as more lines in it. In the
  main scene that means a component: extend `src/game/component.gd`, read state through `ctx`
  (`src/game/game_context.gd`; add a getter there if you need more), override the hooks you
  need (`on_render`, `on_frame`, `on_configure`, `on_world_event`, `on_match_event`) and register
  it with one `add_component()` line in `main._ready`. Worked example:
  `src/game/components/route_art.gd`. Pure math goes in a RefCounted like `camera_zoom.gd`.
  Don't copy `coin_toss.gd`'s `setup(main)` back-reference.
- **File-size ratchet** (`scripts/size_check.sh`, run by `lint.sh`). A new `src/**/*.gd` over
  500 lines fails lint. Files already over that limit have a budget in `scripts/size_budget.txt`,
  and growing past it prints `SIZE WARN`. Treat the warning as a request to extract. When you
  shrink a file, lower its budget in the same PR.
- **Docs:** add your notes inside the section they belong to, not at the end of a shared list.
  Describe a test in the test file's own `##` header.

### Documenting your work (updating docs/)

`docs/README.md` maps every kind of fact to the one doc that owns it. Rules:

- **Docs ship in the same commit as the change.** A behavior change without its doc update is unfinished.
- Changed how to test? Update `docs/TESTING.md`. Changed perf, budgets or rules? Update `docs/optimization/README.md`,
  and add dated numbers to `docs/optimization/LOG.md`. Changed player-facing behavior? Update `docs/features/<area>.md`. New subsystem or
  protocol? Write or update `docs/design/<topic>.md`. Found a bug or idea you're not fixing now? Open a GitHub issue (Work tracking rule 2).
- **Changed the wire format or sim rules a client depends on? Bump `Protocol.VERSION`** (`src/net/protocol.gd`) in
  the same PR, and say so in the PR body. Mismatched builds are refused online instead of desyncing. What
  counts, and why: `docs/design/netcode.md` "When to bump `Protocol.VERSION`" (#165).
- One home per fact: link, don't copy. Numbers carry date, machine and mode. Write down what
  **didn't** work; the next agent needs that most.
- If you change a rule here, update the doc it links to as well (and vice versa).

### Parallel sessions and git

Several Claude sessions work on this repo at once (game loop, graphics, out-of-game, perf).

- The `main` checkout at `~/Coding/football-game` belongs to the loop session. Other work uses
  its own worktree (`~/Coding/football-game-<topic>`) on a branch, merges `origin/main` often,
  and reaches `main` only through a PR the owner merges (see Shipping).
- Other sessions' uncommitted files are theirs. Stage only your own paths (`git add <files>`, never
  `git add -A` or `git commit -a`) and check `git show --stat` before pushing.
- Never `git stash` / `stash pop` bare: the stash is shared across worktrees.
- Claim work on the GitHub issue (`status:in-progress` + claim comment), never by editing files. `FEATURES.md` and `docs/gaps/TODO.md` are stubs now.

### Definition of done
`CHECK PASS`; acceptance criteria covered by tests; visual changes viewed via `shot.sh`;
perf budgets green (ratcheted if you improved them); owning docs updated (feature doc + design doc where relevant);
issue closed or narrowed with a summary comment; side findings filed as issues; your own files committed on
your branch and a PR open (Shipping); report lists issues touched/opened and ends with a `result:` line.
