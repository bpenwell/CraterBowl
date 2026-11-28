## 2026-11-25

- Landed C08a defensive playbook (`153552b`) and C08b defensive play selection and synchronization (`9ed6fee`).
- 204 unit tests and full headless smoke passed. With multiple checkouts active, the first smoke run detected a change to shared settings. Subsequent checks used isolated user data, including a full rerun after the graphics merge.
- C08c and B03 remain open for assignments, bot behavior, play art, and the huddle. No items were skipped or stashed.

## 2026-11-25 — Defensive gameplay and huddle

- Landed C08c and B03 together (`8e823de`). Verified 208 unit tests, full headless smoke including remote recall, and offscreen captures for both teams.
- The first final smoke attempt hit a fixed matchmaker port conflict. The retry passed with isolated user data. B09 and C02 were already claimed by the kicking-game branch.

## 2026-11-27

Six backlog issues reached separate PRs against merged main. Each branch passed the full `./scripts/check.sh` gate, and each PR includes inspected offscreen captures. The issues remain open for owner review and merge.

| Issue | PR | Commit | Unit tests | GitHub Actions at handoff |
|---|---|---|---:|---|
| [#293](https://github.com/bpenwell/CraterBowl/issues/293) Keep rushing credit with the original runner | [#325](https://github.com/bpenwell/CraterBowl/pull/325) | `d2e92e8` | 549 | [Passed](https://github.com/bpenwell/CraterBowl/actions/runs/45963810146) |
| [#308](https://github.com/bpenwell/CraterBowl/issues/308) Resume searching when a host order expires | [#327](https://github.com/bpenwell/CraterBowl/pull/327) | `759c11b` | 547 | [Passed](https://github.com/bpenwell/CraterBowl/actions/runs/45964795180) |
| [#312](https://github.com/bpenwell/CraterBowl/issues/312) Close passing once a Classic runner crosses the line | [#328](https://github.com/bpenwell/CraterBowl/pull/328) | `5f21ee5` | 550 | [Passed](https://github.com/bpenwell/CraterBowl/actions/runs/45965873225) |
| [#324](https://github.com/bpenwell/CraterBowl/issues/324) Return a failure when the branch capture fails | [#330](https://github.com/bpenwell/CraterBowl/pull/330) | `f45c117` | 546 | [Passed](https://github.com/bpenwell/CraterBowl/actions/runs/45966770556) |
| [#329](https://github.com/bpenwell/CraterBowl/issues/329) Report failed comparison writes | [#332](https://github.com/bpenwell/CraterBowl/pull/332) | `daed526` | 547 | [Running](https://github.com/bpenwell/CraterBowl/actions/runs/45968269647) |
| [#254](https://github.com/bpenwell/CraterBowl/issues/254) Enforce intentional grounding under pressure | [#334](https://github.com/bpenwell/CraterBowl/pull/334) | `43d4f12` | 549 | [Running](https://github.com/bpenwell/CraterBowl/actions/runs/45969281566) |

- Opened follow-ups #322, #323, #324, #326, #329, #331 and #333. #324 and #329 reached the PRs above in this run. #335 tracks this entry.
- Skipped #110 because it was blocked, #135 and #273 because they were claimed, #298 because it overlaps the claimed Controls redesign #134, and #323 because it overlaps the rushing-credit code in #325.
- PRs #327, #328 and #334 each start from protocol v4. After one merges, the remaining protocol changes need sequential version bumps and verification against updated main.
- The first full gate on #293 was interrupted during matchmaking. The detached retry passed. The initial checkout was clean and the run added no stashes. The repo records iteration details in PRs since #112 retired `ITERATIONS.md`.

## 2026-11-27 — Fumble stats, diving catches, and audibles

Five backlog items reached separate PRs. Each passed the full local gate. The owner merged the first three during the run.

| Issue | PR | Change commit | Status at the time of writing | Unit tests |
|---|---|---|---|---:|
| [#323](https://github.com/bpenwell/CraterBowl/issues/323) Credit the fumbled keeper | [#356](https://github.com/bpenwell/CraterBowl/pull/356) | `9148cee` | Merged as `b4d6f71`. [CI passed](https://github.com/bpenwell/CraterBowl/actions/runs/46062057587). | 559 |
| [#355](https://github.com/bpenwell/CraterBowl/issues/355) Keep yards on a fumbled completion | [#358](https://github.com/bpenwell/CraterBowl/pull/358) | `96bbf2b` | Merged as `93d617d`. [CI passed](https://github.com/bpenwell/CraterBowl/actions/runs/46062787691). | 558 |
| [#357](https://github.com/bpenwell/CraterBowl/issues/357) Report small screenshot differences | [#359](https://github.com/bpenwell/CraterBowl/pull/359) | `abd6479` | Merged as `04fa61c`. [CI passed](https://github.com/bpenwell/CraterBowl/actions/runs/46063507960). | 559 |
| [#360](https://github.com/bpenwell/CraterBowl/issues/360) Reach for the pass during a dive | [#364](https://github.com/bpenwell/CraterBowl/pull/364) | `f819f0d` | Open for owner review. Verified the merged branch at `0e2bb7b`. [CI run](https://github.com/bpenwell/CraterBowl/actions/runs/46064994314). | 565 |
| [#346](https://github.com/bpenwell/CraterBowl/issues/346) Verify the pre-snap audible | [#365](https://github.com/bpenwell/CraterBowl/pull/365) | `d501b77` | Open for owner review. [CI run](https://github.com/bpenwell/CraterBowl/actions/runs/46065906330). | 565 |

- Opened #355 and #357 from findings during testing, then shipped their fixes through the PRs above. Split #340 into #360 and #361. The jump-catch pose in #361 awaits the jump move in #5. #366 tracks this run record.
- Skipped #298 because #134 claims the overlapping Controls redesign. #7, #9, #10, and #340 track their existing child issues.
- The first full gate for #323 was interrupted during matchmaking. A detached retry passed. When the owner merged #356, #358, and #359, the dive branch kept both timeline changes and passed again on current main.
- Inspected the fumble and dive before/after pairs, the one-pixel comparison fixture, and all three audible states. PR descriptions link to the Actions captures and logs.
- The checkout started clean. No changes were stashed.

## 2026-11-27 — Replay continuity and the audible test gate

| Issue | PR | Change commit | Gate and status |
|---|---|---|---|
| [#375](https://github.com/bpenwell/CraterBowl/issues/375) Release linemen at the whistle | [#383](https://github.com/bpenwell/CraterBowl/pull/383) | `c3091f4` | 566 unit tests. Owner merged as `6093ce8`. [CI passed](https://github.com/bpenwell/CraterBowl/actions/runs/46096661593). |
| [#381](https://github.com/bpenwell/CraterBowl/issues/381) Keep recording during a hosted replay | [#385](https://github.com/bpenwell/CraterBowl/pull/385) | `a5a8948` | 565 unit tests. Owner merged as `9be676c`. [CI passed](https://github.com/bpenwell/CraterBowl/actions/runs/46097357519). |
| [#395](https://github.com/bpenwell/CraterBowl/issues/395) Restore the audible fixtures after route-art extraction | [#396](https://github.com/bpenwell/CraterBowl/pull/396) | `805fcc4` | 569 unit tests. Open for owner review. [CI passed](https://github.com/bpenwell/CraterBowl/actions/runs/46099174783). |
| [#384](https://github.com/bpenwell/CraterBowl/issues/384) Keep the joiner's replay timeline recording | [#399](https://github.com/bpenwell/CraterBowl/pull/399) | `01f87b7` | 570 unit tests. Open for review against #396. [CI run](https://github.com/bpenwell/CraterBowl/actions/runs/46099769931). |
| [#386](https://github.com/bpenwell/CraterBowl/issues/386) Keep the host idle during replay | [#400](https://github.com/bpenwell/CraterBowl/pull/400) | `3359e9d` | 569 unit tests. Open for review against #396. [CI run](https://github.com/bpenwell/CraterBowl/actions/runs/46100439821). |

- All five PR branches passed the full local gate. Inspected the dead-ball, saved host replay, joiner replay, hosted input, and audible captures.
- Opened #384 for the joiner's recording, #386 for the host input leak, and #395 for a merged test failure. #401 tracks this log entry. #398 independently reported the audible failure and is linked to #395.
- Main at `84f7e03` failed when the audible fixtures called the former route-art method after #371. #399 and #400 include the standalone fix and target its branch until it lands. The baseline has file-size warnings in `main.gd` and `player.gd`.
- Skipped #298 because its gamepad help overlaps the claimed Controls redesign #134. Skipped #372 and #373 while their fixes were in review. #376 requires the tackle-fall implementation in #367.
- The checkout started clean. No changes were stashed. The two older Codex stash entries remain available.
