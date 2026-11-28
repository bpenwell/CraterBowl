# Work tracking: GitHub issues

All work on Crater Bowl is tracked in **GitHub issues** on `bpenwell/CraterBowl`. That covers features, bugs, improvements, tech debt, doc work and owner decisions. Repo docs hold knowledge, meaning how the game *is*. Issues hold work, meaning what should change, who's on it, and what happened. This doc is the one home for the rules. `AGENTS.md` summarizes them and `LOOP.md` applies them to the iteration loop.

Adopted 2026-11-25 (#1). Old letter ids (`B09`, `C05`, `D05`…) resolve via `docs/backlog/legacy-ids.md`.

## The two rules every session follows

1. **Keep the issue current.** Claim it when you start. Comment when something material changes: scope narrowed, approach changed, blocked, or a decision was made. Close it with a summary when you ship. Someone reading the issue alone should be able to tell where the work stands.
2. **Anything worth remembering that isn't your objective becomes a new issue, right away.** This includes a bug you noticed, a gap, an improvement idea, a doc that's wrong, a flaky test, or a question for the owner. Open it at the moment you notice, even if you'll fix it in the same change. Then the fix has a traceable record (issue → commit → closing comment), and an unfixed finding isn't lost when your session ends. List every issue you opened in your final report.

## Labels

| Group | Labels | Rule |
|---|---|---|
| Type (exactly one) | `type:feature`, `type:improvement`, `type:bug`, `type:tech-debt`, `type:docs`, `type:decision` | `type:decision` = only the owner can resolve it. Agents never close these. |
| Priority (exactly one) | `P0` core football / parity hole noticed in match one · `P1` important: online, social, trust, onboarding, deeper mechanics · `P2` better-than-Gridiron, polish | Bugs that break a match or a test are P0. |
| Area (one or more) | `area:offense`, `defense`, `line-play`, `kicking`, `rules`, `movement`, `chaosball`, `bots`, `online`, `netcode`, `social`, `progression`, `presentation`, `audio`, `ui`, `accessibility`, `replays`, `training`, `infra`, `process` | These match the feature docs in `docs/features/`. |
| Status | `status:in-progress`, `status:blocked`, `status:needs-decision` | `needs-decision` only when *no* part can start. If there's a sensible default, use `question` instead. |
| Other | `parity` (Gridiron/Remaster has it), `question` (has an open owner question, but work can proceed on the documented default) | |

## Lifecycle (with `gh` commands)

```bash
# Find work: bugs first, then P0 → P1 → P2, oldest first, skipping claimed/blocked
gh issue list --label type:bug --search "-label:status:in-progress -label:status:blocked -label:status:needs-decision sort:created-asc"
gh issue list --label P0      --search "-label:status:in-progress -label:status:blocked -label:status:needs-decision sort:created-asc"

# Read the issue and its discussion before claiming. Plain `gh issue view N` / `--comments` (and `gh pr view N`)
# fail with "GraphQL: Projects (classic) is being deprecated ... (repository.issue.projectCards)"; ask for --json fields instead
gh issue view 12 --json number,title,state,labels,body,comments -q '"#\(.number) \(.title) [\(.state)] \([.labels[].name] | join(", "))", .body, (.comments[] | "--- \(.author.login): \(.body)")'
gh pr view 34 --json number,title,state,body,comments -q '"#\(.number) \(.title) [\(.state)]", .body, (.comments[] | "--- \(.author.login): \(.body)")'

# Claim (label + comment naming session and branch/worktree)
gh issue edit 12 --add-label status:in-progress
gh issue comment 12 --body "Claim: <session/agent>, branch \`<branch>\` (worktree \`~/Coding/football-game-<topic>\`)."

# Progress worth keeping (scope change, finding, decision, blocker)
gh issue comment 12 --body "Narrowed scope: ... because ..."

# Side finding → new issue, immediately
gh issue create --title "<what's wrong / what to add>" --label "type:bug,P1,area:online" --body "<where you saw it, repro or evidence, why it matters, suggested fix>. Found while working on #12."

# Ship → open a PR that closes the issue on merge (the owner reviews and merges; never merge it yourself)
gh pr create --title "<title> (#12)" --body "Closes #12. <what/why>. Tests: <check.sh counts>. Docs: <files>. Follow-ups: #61, #62."
gh issue comment 12 --body "PR #<M> open for review."
# `gh pr edit` hits the same projectCards error; change a PR's title/body through the REST API instead
gh api -X PATCH repos/bpenwell/CraterBowl/pulls/<M> -f body="$(cat body.md)"

# Partial ship → keep it open, narrow it
gh issue edit 12 --remove-label status:in-progress && gh issue comment 12 --body "Part 1 shipped in <sha>; remaining: ..."
```

- **Split big issues.** Open child issues and reference the parent (`Part of #12`). Narrow the parent's scope in a comment.
- **Duplicates:** close with `gh issue close N --reason "not planned" --comment "Duplicate of #M"`.
- **Owner decisions:** quote the question in the issue and add `question` or `status:needs-decision`. Proceed on the documented default if there is one. Never decide something irreversible for the owner.
- **Commits and PRs:** cite the issue in commit messages and PR titles (`Switch ends every quarter (#6)`). There is no separate iteration log; the PR description is the record.
- **Public repo:** issues are world-readable. Never put secrets, tokens, personal emails or private paths beyond `~/Coding/...` in them.

## Issue body format

New issues use `.github/ISSUE_TEMPLATE/`. When creating them with `gh`, follow the same shape:

```
## Why            player/problem it solves; source (O/R/R-ss/Gx/PLAN tag or "found in #N")
## Scope / Accept testable acceptance bullets (each becomes a test)
## Touch points   files likely involved
## Docs           the feature doc (docs/features/<area>.md) and any design doc it will change
## Notes          decisions, open questions, related issues
```

Bugs instead use **Repro / Expected / Actual / Evidence** (test output, screenshot path, commit).

## Docs vs issues

| Put it in… | When it is… |
|---|---|
| An issue | Something to do, a bug, an idea, a question, a status, a claim, a decision request, or a finding you won't act on now |
| `docs/features/<area>.md` | How a feature behaves for players today: rules, controls, numbers, decisions and what didn't work. Update it in the same commit as the behavior change. |
| `docs/design/<topic>.md` | How something is built: architecture, protocol, data flow, invariants. Write one when a change needs a design that outlives the issue, such as a new subsystem or protocol. |
| The issue (design comment) | The design pass for a piece of work: options, pick, acceptance criteria. The pick and its why then land in the feature doc. |
| The PR description | What shipped, test evidence, follow-up issues |
| `docs/research/` | Outside research: the gap analysis vs Gridiron/genre, plus dated review logs |

Feature docs end with an **Open issues** list. When you open or close an issue in an area, update that list in the same commit if you're touching the doc anyway. Otherwise it's refreshed when the doc is next edited. GitHub is authoritative for status, and the doc list is just a convenience.
