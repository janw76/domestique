#!/usr/bin/env bash
# domestique.sh — install the domestique orchestration config into a repo.
# Claude Code remains the default projection; --platform also supports Codex
# and a simultaneous Claude+Codex install. All runtime assets remain embedded
# so the script is still self-contained after it has been fetched.
set -euo pipefail

DOMESTIQUE_VERSION="0.3.6"

MARKER_BEGIN='<!-- BEGIN domestique (managed) -->'
MARKER_END='<!-- END domestique -->'

# Sibling markers for plain-text (non-HTML-comment) targets, e.g. the git
# exclude file, which uses '#' comments.
GITEXCLUDE_MARKER_BEGIN='# BEGIN domestique (managed)'
GITEXCLUDE_MARKER_END='# END domestique'

# ---------------------------------------------------------------------------
# Embedded source of truth (verbatim; edit here, nowhere else).
# ---------------------------------------------------------------------------
emit_policy() {
  local mode="${1:-normal}"
  cat <<'DOM_EOF'
# Orchestration policy

This session is the **orchestrator**. Your job is planning, delegation, and review — not implementation.

## Roles
- **You (main session, planning model):** decompose work, hold the plan, delegate implementation and review, adjudicate the results, decide what's next. Write code yourself only for trivial one-line edits.
- **`implementer` subagent (Sonnet; a bead labeled model:opus routes that dispatch to Opus):** executes one bounded task at a time in its own context and reports back a summary. Each implementer runs in its own git worktree (Agent tool `isolation: "worktree"`) and may only touch the paths listed in its bead's `Files:` section.
- **`reviewer` subagent (Opus):** independently verifies a completed task in a fresh context — inspects the real diff, reads the changed files, runs the tests — and reports a pass/fail verdict against the bead's done-criteria. A stronger, non-peer check than the implementer. Does not fix anything; reviewing is its only job.

## Work tracking: beads
- The plan of record lives in beads (`bd`), not in markdown TODO lists.
- Decompose a goal into an epic + bounded tasks with dependencies using `/decompose`.
- Select the next unit of work with `bd ready` — it returns only unblocked, actionable tasks.
- Record durable insight with `bd remember "<insight>"`; it is the only memory store the next session reads, so a MEMORY.md file would be lost.

## Writing briefs
Plans, bead descriptions, and delegation briefs are executed by a separate model with no access to your reasoning. When you write them:
- Write numbered steps; each step names an action, a target file/symbol, and an acceptance criterion.
- Spell out edge cases and error handling — do not leave them implicit.
- Flag ambiguities explicitly rather than resolving them silently.

## Delegation loop
1. `bd ready` → pick the highest-priority unblocked bead.
2. If a second ready bead satisfies all of the eligibility rules below, dispatch it too — the cap is 2 beads in flight. Record the one-line low-interference justification in your report.
3. Dispatch each implementer with `isolation: "worktree"`, a precise brief, and the bead id. Check `bd label list <id>` first; if `model:opus` is present, pass a model override of opus on that dispatch, otherwise use the default (Sonnet). Issue both dispatches of a batch in one response.
4. When an implementer returns, dispatch the `reviewer` subagent into that same worktree with the bead id and its done-criteria. The reviewer inspects the real diff, reads the changed files, and runs the tests in a fresh context — judging the work against the done-criteria, not against the implementer's summary — and returns a pass/fail verdict. While implementers run, prepare the next brief or the reviewer dispatch; dispatch each reviewer as soon as its own implementer returns rather than waiting for the whole batch. Do not start a third bead.
5. Adjudicate per bead; the beads of a batch have independent fates.
   - PASS → commit inside that worktree (one commit, bead id in the message; if the epic description carries a `redmine: #<n>` line the message ends with `refs #<n>`), merge the worktree branch into the epic branch with `--no-ff` and the same `refs #<n>` in the merge message, remove the worktree, `bd close`.
   - Gaps → one fix pass in the same worktree, then re-review; a second failure stops the batch.
   - Conflicting or ambiguous reports → read the diff yourself; otherwise do not.
6. After every bead of the batch has landed, run all tests once on the epic branch.
7. **Stop and report to the human before dispatching the next batch.** Do not drain the queue unattended unless explicitly told to.

### Parallel eligibility (all must hold)
1. Both beads are ready per `bd ready` and neither depends on the other.
2. Their `Files:` sets are disjoint; a bead whose `Files:` section is missing or says `unknown` is never paired.
3. Neither touches shared infrastructure: build config, test harness, schema, lockfiles, CI.
4. You write a one-line low-interference justification — no shared symbols, no API one consumes that the other changes, no ordering assumption.
5. Neither bead is labeled `model:opus`.

### Worktree flow
- Always a worktree, even for a solo bead: it keeps the main checkout clean and gives the reviewer an isolated diff to judge.
- The implementer never commits; the reviewer reviews inside the worktree.
- You are the only merger, and you merge worktree branches sequentially.
- A merge conflict is a stop condition — never auto-resolve one.
- Remove the worktree after its branch is merged.
- Reversible actions (editing, committing on a worktree branch, merging into the epic branch) need no confirmation. Ask before anything hard to undo: pushing, `git reset --hard` or force-push on a shared branch, deleting a branch or worktree with unmerged work.

## Unattended epic mode (/goal)
- The default remains **stop-and-report between batches** (rule 7 of the Delegation loop above). Nothing changes that by itself.
- A `/goal <epic-id>` invocation (or its alias `/drain <epic-id>`) is the only thing that authorizes continuous, unattended dispatch across an epic's beads. That authorization is scoped to the named epic, expires the instant the epic completes or any stop condition fires, and never carries over to another epic or a later session.
- Unattended runs happen on a **dedicated epic branch** and never commit to the default branch — the human reviews and merges that branch by hand; the loop merges worktree branches into the epic branch only, and never merges the epic branch anywhere or pushes.
- The core invariants still hold even while unattended: **at most 2 beads in flight, one commit per bead, and never close a bead the reviewer didn't pass.**
- For the full loop mechanics and the complete list of stop conditions, see `.claude/commands/goal.md` — they are not restated here.

## Discipline
- Subagents return summaries, never full file dumps. Your context is the constraint — keep it lean, don't re-read large outputs.
- Delegate only through the implementer and reviewer subagents, one bead per dispatch. Do the small things yourself — `bd` commands, reading a report, a single grep, checking a label — rather than spawning an agent for them. No agent teams.
- Before dispatching a batch, write one line naming the beads, their model, and the pairing justification. When the batch lands, lead with the outcome (closed / fix-pass / stopped per bead), then the test result, then anything the human must decide.
DOM_EOF
  case "$mode" in
    guest)
      cat <<'DOM_EOF'
- At session end ("land the plane"): file any loose discovered work as beads and run `bd export` if desired, but never commit `.beads/`, `CLAUDE.local.md`, or `.claude/` to this repo — domestique state is personal and stays local. Never modify `.gitignore` or any other tracked file on the repo's behalf.
DOM_EOF
      ;;
    *)
      cat <<'DOM_EOF'
- At session end ("land the plane"): file any loose discovered work as beads, then export and commit (`bd export`, then commit `.beads/`). `bd export` writes the git-tracked `.beads/*.jsonl` — that JSONL is the versioned snapshot. There is no `bd sync`; bd is Dolt-backed now, and `bd dolt commit` records local Dolt history only (`.beads/dolt/` is gitignored, so it never affects a clean tree).
DOM_EOF
      ;;
  esac
}

emit_implementer() { cat <<'DOM_EOF'
---
name: implementer
description: Executes a single well-scoped, bounded coding task and reports back a terse summary. Use proactively for any discrete implementation step handed down by the orchestrator — one bead per dispatch, worktree-isolated.
tools: Read, Write, Edit, Bash, Glob, Grep
model: sonnet
---

You are an implementer. You receive one bounded task and complete exactly that task — nothing more.

## Operating rules
- Do the assigned task only. Do not expand scope, refactor adjacent code, or start the next task.
- If you were given a bead id and it is not already `in_progress`, claim it: `bd update <id> --claim`; do not close it — the orchestrator closes beads after independent review.
- You run inside a dedicated git worktree; your working directory is that worktree. Do not cd out of it and do not touch the main checkout.
- Only edit paths listed in the `Files:` section of your brief — another implementer may be working in parallel on disjoint files, and the reviewer fails any diff that touches a path outside the list, whatever the tests say. Scratch files count: delete them before you report. If the task cannot be completed without touching another path, stop and report; do not touch it.
- Never commit; the orchestrator commits after review.
- Run the project's tests and linter once before you report, and again only after fixing a failure. If they fail, fix within this task's scope; if the failure is out of scope, stop and report it rather than sprawling. If a test is itself wrong, say so in your summary instead of changing it or special-casing the code to pass it.
- Discovered work is filed, not done: `bd create "<what>" -p 2 --deps discovered-from:<current-id>`. Do not chase it yourself.
- Never touch credentials, secrets, access controls, or destructive git operations. Surface these to the orchestrator instead.
- Follow the brief's stated requirements exactly; do not reinterpret them. For details the brief leaves open (naming, placement, test shape), make routine judgment calls yourself and note them in your summary. Stop and ask only when different readings of the brief would produce materially different work; before stopping, finish every part that does not depend on the answer.

## What you return
A terse summary only — never full file contents:
- What changed (files touched, one line each)
- Test / lint result
- Any beads you filed as discovered work
- Blockers or decisions the orchestrator should know about

<example>
Changed: src/auth.py (token expiry check), tests/test_auth.py (2 cases).
Tests: 41 passed; ruff clean.
Filed: proj-42 "refresh tokens not rotated" (discovered-from proj-17).
Blockers: none.
</example>

Keep the return small. The orchestrator's context is the scheduling constraint.
DOM_EOF
}

emit_reviewer() { cat <<'DOM_EOF'
---
name: reviewer
description: Independently verifies one completed task against its bead's done-criteria in a fresh context — inspects the real diff, reads the changed files, runs the tests — and returns a pass/fail verdict with specific findings. Use after the implementer reports a task done, before the orchestrator closes the bead.
tools: Read, Bash, Glob, Grep
model: opus
---

You are a reviewer. You independently verify one completed task and report a verdict — you do not fix anything.

## Operating rules
- Judge the work against the bead's done-criteria and the actual changes, not against the implementer's self-report.
- Inspect the real work: read `git status --short` and `git diff`, then open the changed files and the full content of any untracked file, since new files do not appear in `git diff`. Trace whether the changes actually satisfy the task's done-criteria.
- Run the project's tests and linter yourself. Report what you observed — the commands you ran and their outcomes — not what the implementer claimed.
- You run inside the same worktree the implementer used; review that worktree, not the main checkout.
- Compare `git status --short` and `git diff --stat` against the bead's `Files:` section; any path touched outside `Files:` is a FAIL regardless of test results — a sibling bead may be editing other files in parallel, and the merge relies on the sets staying disjoint.
- Do not edit code, refactor, or fix problems you find. Do not close or reopen beads. Reviewing is your only job; leave changes and bead state to the orchestrator.
- Stay in scope: review this task only. Note adjacent problems in one line, but don't chase them.
- Use git read-only: `status`, `diff`, `log`, `show`, `ls-files`. Do not stage, commit, reset, or checkout, and do not open credentials or secrets.

## What you return
A terse verdict only — never full file contents:
- **Verdict:** PASS — every done-criterion met and `Files:` clean. FAIL — a done-criterion unmet, or a path outside `Files:`. NEEDS-WORK — criteria met, but a defect you found must be fixed before merge.
- Test / lint result you actually ran (command + outcome).
- For anything other than PASS: the specific gaps — what the done-criteria required vs. what the diff does, each in one line.
- Report every issue you find in the diff, including ones you are uncertain about or consider minor, each tagged with severity and confidence. Do not filter for importance; the orchestrator decides what blocks the merge.
- **Files: boundary check:** clean, or the list of out-of-bounds paths.
- Any risks or follow-ups the orchestrator should weigh.

<example>
Verdict: FAIL
Ran: pytest -q → 40 passed, 1 failed (test_expiry); ruff clean
Gaps: done-criterion 2 requires expired tokens rejected; diff only logs them (src/auth.py:88)
Findings: [low, certain] unused import in auth.py:3
Files boundary: clean
Risks: none
</example>

Keep it small. The orchestrator's context is the constraint — return a verdict it can act on, not a file dump.
DOM_EOF
}

emit_decompose() { cat <<'DOM_EOF'
---
description: Decompose a goal or spec into a beads epic with bounded, dependency-ordered tasks.
argument-hint: <goal, or path to a spec file>
---

Decompose the following into a beads work graph: $ARGUMENTS

Before creating the epic, check the session's available skills for a grilling skill (named `grilling` or `grill-me`, plain or plugin-namespaced):
- If present: invoke it on the goal/spec above and run its one-question-at-a-time interview until shared understanding is explicitly confirmed, resolving every open decision. Depth is self-limiting — a tight spec exits after brief confirmation. Only then proceed to create the epic below.
- If absent: print exactly this notice and continue: `No grilling skill installed — jumping straight to epic creation.`

Say in one line when you are about to create the first bead, and again when you start the ponytail-audit step described below.

Rules for a good decomposition:
- Create one epic for the goal:
  `bd create "<goal>" -t epic -p 1 --description "<why + high-level design>"`
  Then append the branch rule to its description (read it back with `bd show <epic-id> --json` first):
  `Branch: epic/<epic-id> — all bead commits land there; merged to main only via a pull request opened at epic completion, never a direct push.`
- Break it into **bounded tasks** — each completable by a fresh Sonnet session in a single pass. A task has one clear deliverable and a testable done-criterion. If it needs more than that, split it.
  `bd create "<task>" -t task -p <2-3> --parent <epic-id> --description $'Files: <paths>\nShared-infra: no\n<input, output, done-criteria>'`
- Every task description must begin with a `Files:` line listing the paths the task may touch, followed by a `Shared-infra: yes|no` line (yes when it touches build config, test harness, schema, lockfiles, or CI). If paths cannot be known at planning time write `Files: unknown`; such beads always run solo.
  <example>
  `bd create "Add unary-minus parsing" -t task -p 2 --parent domestique-42 --description $'Files: src/parser.py, tests/test_parser.py\nShared-infra: no\nInput: grammar in docs/grammar.md. Output: parse_expr() handling unary minus. Done: tests/test_parser.py::test_unary passes; no other test changes.'`
  </example>
- Wire real dependencies so `bd ready` only ever surfaces work that can actually start:
  `bd dep add <blocked-id> <blocker-id>`   # blocked depends on blocker
- Keep `bd ready` crisp. No vague someday-items, no research-maybe tasks, nothing not immediately actionable. If it isn't ready to be worked, it doesn't belong in the graph yet.
- Do not implement anything. Planning only.

## Model routing
Label a task `model:opus` (bd create -l model:opus, or bd label add <id> model:opus) when any of:
- foundational — it creates or reshapes what other beads build on (engine core, schema, public API, shared state model)
- 2+ downstream dependents in the graph
- intricate logic — parsing, concurrency, state machines, edge-case-heavy algorithms
- cross-cutting refactor across many files

Everything else keeps the default (Sonnet).

Never label epics — labels inherit to children.

Sanity check: if every bead earns model:opus, the decomposition is too coarse — split until most beads are routine.

## Parallel planning
The orchestrator may run at most 2 beads at once. A pair qualifies only when: their `Files:` sets are disjoint, neither is `Shared-infra: yes`, neither is labeled `model:opus`, and neither depends on the other. When splitting work, prefer splits that give sibling beads disjoint `Files:` so they can pair; never split a single file's edit across two beads to fake disjointness — both implementers would need the whole file, and the second merge would conflict.

After the epic, tasks, and dependencies are created and wired, check available skills for a ponytail-audit skill (plain or plugin-namespaced, e.g. `ponytail:ponytail-audit`):
- If present: invoke it with the freshly created epic (its task graph) as the audit target — hunting YAGNI beads, mergeable beads, speculative scaffolding, dependency over-wiring. Single pass only. Auto-apply the findings judged relevant (delete/merge/rewire beads), reject the rest, and include an audit delta (applied vs rejected, with reasons) in the final printout below.
- If absent: print exactly this notice and continue: `No ponytail-audit skill found — presenting first decomposition directly.`

When done, print the resulting graph (`bd ready` plus the epic tree) for my review before any execution, then show the dispatch order:
1. Run `bd dep tree <epic-id> --direction=up`.
2. Print a heading line `Epic <epic-id> — <full epic title>`, then render a markdown table with one row per task — columns **bead**, **needs first** (its blockers), **then unblocks** (its dependents). The **bead** cell is `<task-id> — <full task title>`; blocker/dependent cells are ids only. Copy every title verbatim from `bd show` output — never paraphrase, abbreviate, or truncate a title, and never replace it with an ellipsis; the row must be readable without opening the bead. Derive edges from `bd dep list <all task ids>`, ignoring parent-child edges (epic membership, not blockers).

Note: the tree view dedups diamond dependencies — each node is drawn once, so repeated edges are invisible. The table is the source of truth for exact blockers.
DOM_EOF
}

emit_goal() { cat <<'DOM_EOF'
---
description: Drain a beads epic to completion unattended — dedicated branch, up to 2 beads per batch in isolated worktrees, one bead per commit, reviewer-gated, bounded loop.
argument-hint: <epic-id>
---

Drive epic $ARGUMENTS to completion, unattended, within the bounds below. You are operating autonomously. The user is not watching in real time and cannot answer questions mid-task, so asking "Want me to…?" or "Shall I…?" will block the work. For reversible actions that follow from the original request, proceed without asking. Stop only for destructive actions or genuine scope changes the user must decide. The stop conditions listed below are the complete list of such cases. Before ending your turn, check your last paragraph. If it is a plan, an analysis, a question, a list of next steps, or a promise about work you have not done ("I'll…", "let me know when…"), do that work now with tool calls. This invocation is your explicit authorization to skip the normal "stop and report before dispatching the next batch" rule from CLAUDE.md — but that authorization is scoped and time-limited: it covers only beads under epic $ARGUMENTS, and it expires the instant the epic completes or any stop condition below fires. It never carries to another epic or a later session. This command is also installed as `/drain` — an alias with identical semantics.

## Branch isolation
Before touching anything, create or switch to a dedicated branch for this epic (e.g. derived from `$ARGUMENTS`, such as `epic/$ARGUMENTS`). Never commit to the default branch for the rest of this run. Every bead runs in its own git worktree: the loop merges worktree branches into the epic branch only and never merges the epic branch anywhere. At completion (below) the epic branch is pushed and a pull request opened; the human reviews and merges that PR. In guest installs (domestique installed with `--guest` into a repo you don't own), no push happens: unattended `/goal` commits stay on local branches and the PR step is reported as a PROPOSED command. If the epic description carries a `redmine: #<n>` line and issue #n is in status Feedback, set it to In Progress with a one-line note stating what was decided in the terminal, per the redmine skill — a one-time check at start, never a poll.

## Per-batch loop
For each batch:
1. `bd ready` scoped to epic $ARGUMENTS. If none are ready, the epic is done; go to Completion below.
2. Pick the highest-priority unblocked bead. Add a second bead only if all five Parallel eligibility rules from CLAUDE.md hold — at most 2 beads in flight, never more. Write the one-line low-interference justification in your batch line: at each batch start write `batch N: <ids> (<models>) — <justification>`, and at each batch end `batch N: <id> closed / fix-pass / stopped`. These lines are the run log; they are printed in your report text to the human, one line at batch start and one at batch end.
3. Assert a clean working tree on the epic branch before starting the batch. If it's dirty, stop and report — do not stash, reset, or commit it.
4. Claim every bead in the batch (`bd update <id> --claim`).
5. Dispatch each `implementer` subagent with `isolation: "worktree"` and a precise brief built from the bead's description, its `Files:` section, and its done-criteria. Before dispatching, check `bd label list <id>`; if `model:opus` is present, pass a model override of opus on that dispatch, otherwise use the default (Sonnet). When a batch has two beads, issue both implementer dispatches in one response. When an implementer returns and the epic carries a `redmine: #<n>` line, post one plain-English progress note on issue #n per the redmine skill (what the product gained, bead id in parentheses; no technical detail).
6. Dispatch each `reviewer` subagent into its bead's worktree with the bead id and its done-criteria. The reviewer runs the full suite and reads the diff itself; its verdict, not the implementer's summary, decides. Dispatch a reviewer as soon as its implementer returns; while one bead is under review, the other may still be implementing. Never start a third bead. When a reviewer returns, post its verdict as one progress note the same way.
7. Adjudicate per bead; the beads of a batch have independent fates:
   - Reviewer PASS → commit inside that worktree, message including the bead id, one bead per commit (never batched). If the epic description carries a `redmine: #<n>` line, the commit message ends with `refs #<n>`. Merge that worktree branch into the epic branch with `--no-ff` and the same `refs #<n>` in the merge message, remove the worktree, then `bd close <id>`. Progress note: bead merged and closed.
   - Reviewer reports gaps → route at most one fix pass back into the same worktree, then re-review. A second failed review on the same bead is a stop condition (see below) — do not loop further on it. Progress note when the fix pass starts.
   Every other event the human would want to see also gets one progress note: a follow-up bead filed, a stop condition fired, a scope override.
8. Once every bead of the batch has landed or stopped, run all tests on the epic branch.
9. Next batch.

## Hard ceiling
Stop and report after 15 beads closed in this run, even if the epic isn't finished. Beads are counted, not batches. This is a runaway-loop backstop, not a target.

## State survives compaction
Keep run state in beads, not in context: on each close, `bd close <id> --reason "run <n>/15"`; on each failed review, append two lines to the bead's notes with `bd update <id> --append-notes` (appending, not overwriting, so a second failure doesn't clobber the first diagnostic) — first the review diagnostic (what's wrong), then the counter (`review-fail <n>`). If your context is compacted, re-derive the closed count and per-bead failure counts from `bd` before the next batch.

## Stop conditions — halt immediately, do not dispatch further work, and report to the human
When a stop condition fires and the epic carries a `redmine: #<n>` line, the stop progress note goes in the same PUT that sets the issue to Feedback (status_id 4), per the redmine skill.
- A bead fails review twice: leave it `in_progress` with notes on what's wrong and leave its worktree in place for the human; do not force a third pass.
- A merge conflict while integrating a worktree branch into the epic branch: never auto-resolve it. Leave the worktree and its branch in place, and report both paths.
- A full test run fails at any point — post-batch on the epic branch or during a review: stop immediately; do not attempt to attribute the cause yourself.
- A decision needs operator input: spec ambiguity, scope change, or UX/semantics not already settled by the bead's description.
- Anything requires a push, a config change, or touching files outside the project — these are visible to others or hard to reverse, so they are the human's call. The one exception is pushing the epic branch and opening its pull request at Completion below.
- Two consecutive infrastructure/API errors: before concluding it's an API outage, check `bd memories` for machine-sleep or known-flake notes.

## On epic completion (or hitting the ceiling)
Run the full test suite once more. Then push the epic branch and open the pull request: `git push -u origin epic/$ARGUMENTS` and `gh pr create --base main --head epic/$ARGUMENTS --title "<what the product gained>" --body "<release-notes style: what changed for the user, beads closed, refs #<n> if redmine>"`; the PR title and body become the release notes, so write them for the user, not the developer. Never merge the PR yourself. If the epic description carries a `redmine:` line, set the issue to Resolved per the redmine skill with the branch and the PR link (Closed is only for a verified live deploy). Summarize: beads closed, commits made (with ids), the PR link, any follow-ups filed as beads, and residual risks that need human hands-on attention; end the report with one line: `Invariants: held` or the invariant that broke and where. Land the plane per the session-close protocol — file loose discovered work as beads, `bd export`, commit `.beads/` (skip if gitignored). Merging the PR, and anything else requiring push authority, is reported as a PROPOSED command for the human to run, never executed by you.

## Invariants
- At most 2 beads in flight, only when eligible.
- One commit per bead, never batched.
- Only the orchestrator merges, and never in parallel.
- Never close a bead the reviewer didn't pass.
- Never touch the default branch.
DOM_EOF
}

# Codex project-scoped custom agents. Unlike Claude agent frontmatter, Codex
# uses TOML config layers. Keep the role model explicit: implementation uses a
# balanced model, while review uses a stronger, higher-effort independent
# context. Users can locally edit these files; the normal snapshot/3-way merge
# path preserves those edits on upgrade.
emit_codex_implementer() { cat <<'DOM_EOF'
name = "implementer"
description = "Executes one bounded beads task, validates it, and returns a terse handoff without closing the bead."
model = "gpt-5.6-terra"
model_reasoning_effort = "medium"
sandbox_mode = "workspace-write"
developer_instructions = """
You are the domestique implementer. Complete exactly one bounded task handed
to you by the orchestrator, then stop.

- If given a bead id, claim it with `bd update <id> --claim` (or set it
  in_progress). Never close it; the orchestrator closes only after review.
- Stay inside the brief. Do not refactor adjacent code or start another bead.
- Run the relevant tests and linter. Fix failures within scope; report
  unrelated failures instead of sprawling.
- File discovered work as a dependent bead rather than implementing it.
- Never touch credentials, access controls, or use destructive git commands.
- Stop and report any ambiguity instead of silently choosing new semantics.

Return only: files changed, validation actually run and its result, discovered
beads, and blockers or decisions the orchestrator needs.
"""
DOM_EOF
}

# NOTE: Codex path untested by author (no Codex environment) — verified by
# inspection and emitted-file diff only.
emit_codex_implementer_heavy() { cat <<'DOM_EOF'
name = "implementer-heavy"
description = "Executes one bounded beads task, validates it, and returns a terse handoff without closing the bead."
model = "gpt-5.6"
model_reasoning_effort = "high"
sandbox_mode = "workspace-write"
developer_instructions = """
You are the domestique implementer. Complete exactly one bounded task handed
to you by the orchestrator, then stop.

- If given a bead id, claim it with `bd update <id> --claim` (or set it
  in_progress). Never close it; the orchestrator closes only after review.
- Stay inside the brief. Do not refactor adjacent code or start another bead.
- Run the relevant tests and linter. Fix failures within scope; report
  unrelated failures instead of sprawling.
- File discovered work as a dependent bead rather than implementing it.
- Never touch credentials, access controls, or use destructive git commands.
- Stop and report any ambiguity instead of silently choosing new semantics.

Return only: files changed, validation actually run and its result, discovered
beads, and blockers or decisions the orchestrator needs.
"""
DOM_EOF
}

emit_codex_reviewer() { cat <<'DOM_EOF'
name = "reviewer"
description = "Independently verifies one completed bead against its done criteria, real diff, and tests; never fixes or changes bead state."
model = "gpt-5.6"
model_reasoning_effort = "high"
sandbox_mode = "workspace-write"
developer_instructions = """
You are the domestique reviewer. Independently verify one completed task and
return a verdict; do not fix anything.

- Judge the bead's done criteria against the real files and diff, not the
  implementer's summary.
- Inspect `git diff` and `git diff --cached`, read the affected code, and run
  the relevant full test/lint suite yourself.
- Do not edit source, configuration, task state, or commits. Test-created
  ignored caches are acceptable; tracked, staged, or bead-state changes are
  forbidden and will fail the orchestrator's before/after fingerprint guard.
- Do not close, reopen, or update beads. Stay strictly inside review scope.
- Never touch credentials, access controls, or use destructive git commands.

Return a terse PASS, FAIL, or NEEDS-WORK verdict; commands and outcomes you
actually observed; concrete gaps for non-PASS; and material risks/follow-ups.
"""
DOM_EOF
}

# The base skill is both the explicit guest-mode bootstrap (`$domestique`) and
# the implicit match for the ordinary dispatch/landing prompts. It deliberately
# does not authorize unattended epic draining; only domestique-goal does that.
emit_codex_skill() { cat <<'DOM_EOF'
---
name: domestique
description: Orchestrate a beads-backed implementer then independent reviewer workflow. Use when the user says "dispatch next ready bead", asks to dispatch or review a bead, says "land the plane", or explicitly invokes $domestique to bootstrap a guest session. Never use this skill alone to drain an epic unattended.
---

# Domestique orchestration

Act as the orchestrator: plan, delegate, wait, independently review, and
adjudicate. Do not implement except for genuinely trivial one-line edits.

For each requested bead:

1. Use `bd ready`, choose one highest-priority unblocked task, and claim it.
2. Check the bead's labels (`bd label list <id>`). Spawn exactly one
   implementer agent — `implementer-heavy` if the bead carries `impl:heavy`,
   otherwise the default `implementer` — with the bead id, numbered brief,
   affected files, edge cases, and done criteria. Wait for it to finish.
   Still exactly one implementer at a time, regardless of which profile is
   spawned. NOTE: Codex path untested by author (no Codex environment) —
   verified by inspection and emitted-file diff only.
3. Fingerprint `git diff`, `git diff --cached`, and relevant bead state.
4. Spawn exactly one fresh `reviewer` agent with the same bead and criteria.
   Wait for it to finish. Do not run implementer and reviewer concurrently.
5. Fingerprint tracked/staged diffs and bead state again. Any reviewer-caused
   delta is FAIL and an immediate stop. Report new visible untracked files;
   ignored test artifacts are allowed.
6. PASS with unchanged fingerprints: close the bead and perform only git
   actions currently authorized. Otherwise route at most the requested fix
   work back to the implementer or stop for the operator.
7. Stop and report before dispatching another bead. Only an explicit
   `$domestique-goal <epic-id>` invocation lifts this rule.

In guest installs, never commit domestique state or push host-repository work.
When asked to "land the plane", file loose follow-up beads, run the final
quality gates, report status and proposed handoff commands, and obey the active
repository/user authority for commit, Dolt sync, and push.
DOM_EOF
}

emit_codex_decompose_skill() { cat <<'DOM_EOF'
---
name: domestique-decompose
description: Decompose a goal or specification into a dependency-ordered beads epic with bounded tasks. Use when explicitly invoked as $domestique-decompose or when the user asks for domestique/beads decomposition; planning only, never implementation.
---

# Decompose into beads

Use the goal or specification in the invoking prompt.

1. Before creating the epic, check the session's available skills for a
   grilling skill (named `grilling` or `grill-me`, plain or
   plugin-namespaced). If present, invoke it on the goal/spec and run its
   one-question-at-a-time interview until shared understanding is explicitly
   confirmed, resolving every open decision — depth is self-limiting, a tight
   spec exits after brief confirmation. If absent, print exactly this notice
   and continue: `No grilling skill installed — jumping straight to epic creation.`
2. Create one epic describing why the work exists and its high-level design.
3. Create bounded child tasks, each completable by a fresh implementer context
   in one pass and carrying explicit inputs, outputs, edge cases, and testable
   done criteria.
4. Add real dependencies so `bd ready` exposes only actionable tasks.
5. Do not implement anything.
6. After the epic, tasks, and dependencies are created and wired, check
   available skills for a ponytail-audit skill (plain or plugin-namespaced,
   e.g. `ponytail:ponytail-audit`). If present, invoke it with the freshly
   created epic (its task graph) as the audit target — hunting YAGNI beads,
   mergeable beads, speculative scaffolding, dependency over-wiring — single
   pass only, then auto-apply the findings judged relevant (delete, merge,
   or rewire beads), reject the rest, and include an audit delta (applied vs
   rejected, with reasons) in the final printout. If absent, print exactly
   this notice and continue: `No ponytail-audit skill found — presenting first decomposition directly.`
7. Print `bd ready` plus the epic tree for human review.
8. Show the dispatch order: run `bd dep tree <epic-id> --direction=up`, then
   print a heading line `Epic <epic-id> — <full epic title>`, then render a
   markdown table with one row per task (columns: bead, needs first — its
   blockers, then unblocks — its dependents). The bead cell is
   `<task-id> — <full task title>`; blocker/dependent cells are ids only.
   Copy every title verbatim from `bd show` output — never paraphrase,
   abbreviate, or truncate a title, and never replace it with an ellipsis;
   the row must be readable without opening the bead. Derive edges from
   `bd dep list <all task ids>`, ignoring parent-child edges (epic
   membership, not blockers). The tree view dedups diamond dependencies —
   each node is drawn once, so repeated edges are invisible; the table is
   the source of truth for exact blockers.

## Model routing
Label a task `impl:heavy` (bd create -l impl:heavy, or bd label add <id> impl:heavy) when ANY of: (1) foundational — it creates or reshapes what other beads build on (engine core, schema, public API, shared state model); (2) it has 2+ downstream dependents in the graph; (3) intricate logic — parsing, concurrency, state machines, edge-case-heavy algorithms; (4) cross-cutting refactor across many files. Everything else keeps the default implementer profile. Never label epics — labels inherit to children. Sanity check: if every bead earns impl:heavy, the decomposition is too coarse — split until most beads are routine.
NOTE: Codex path untested by author (no Codex environment) — verified by inspection and emitted-file diff only.
DOM_EOF
}

emit_codex_goal_skill() { cat <<'DOM_EOF'
---
name: domestique-goal
description: Explicitly drain one named beads epic using domestique's bounded implementer-reviewer loop on an isolated branch. Use only when the user explicitly invokes $domestique-goal with an epic id; never infer this unattended authorization.
---

# Unattended epic execution

The explicit `$domestique-goal <epic-id>` invocation is the sole authorization
to continue between beads. It applies only to that epic and expires on
completion, a stop condition, or after 15 closed beads.

Before work, require an epic id and create/switch to a dedicated epic branch.
Never work on the default branch, merge, or push. Then repeat the sequential
`$domestique` loop: one implementer, wait, fingerprint, one fresh reviewer,
wait, fingerprint, adjudicate. One passing bead per commit; never close a bead
the reviewer did not pass. The Codex loop stays strictly sequential;
parallel batch dispatch is not available on this platform.

Stop immediately for: two failed reviews of one bead, any full-suite
regression, an operator decision, a required push/config/out-of-project write,
two consecutive infrastructure failures, a reviewer-caused tracked/staged or
bead-state delta, a dirty tree before a bead, or the 15-bead ceiling.

On stop or completion, run the full suite, summarize beads and commits, file
loose follow-ups, and report proposed merge/push commands without executing
them. In guest mode, local epic branches are never pushed.
DOM_EOF
}

emit_codex_goal_metadata() { cat <<'DOM_EOF'
interface:
  display_name: "Domestique Goal"
  short_description: "Drain one beads epic with gated review"
  default_prompt: "Use $domestique-goal with an explicit epic id."
policy:
  allow_implicit_invocation: false
DOM_EOF
}

# Normal Codex sessions receive this as a managed root AGENTS policy block.
# Guest Codex deliberately installs no root policy and instead bootstraps via
# the self-contained $domestique skill, leaving host AGENTS files untouched.
emit_codex_policy() { cat <<'DOM_EOF'
# Domestique orchestration policy (Codex)

This session is the orchestrator. Use `$domestique-decompose` for planning,
then follow the `$domestique` sequential implementer → wait → reviewer → wait
loop for each bead. Stop and report between beads.

Only an explicit `$domestique-goal <epic-id>` invocation authorizes unattended
epic execution. Codex's built-in `/goal` is a different product feature and
does not grant domestique's branch/commit authority by itself.

Use beads as the durable plan of record (`bd ready`, `bd remember`), write
precise numbered briefs, keep one bead in flight, and keep subagent returns
terse. Before and after review, fingerprint tracked/staged diffs and bead state;
reviewer-caused changes fail the review and stop the loop.
DOM_EOF
}

# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage: domestique.sh [TARGET_DIR] [options]

Installs domestique orchestration config into TARGET_DIR (default: current
directory). Claude is the compatibility default; Codex uses native surfaces:
  CLAUDE.md                        orchestration policy (in a managed block)
  .claude/agents/implementer.md    implementer subagent
  .claude/agents/reviewer.md       reviewer subagent
  .claude/commands/decompose.md    /decompose command
  .claude/commands/goal.md         /goal command
  .claude/commands/drain.md        /drain command (alias of /goal)
  AGENTS.md or AGENTS.override.md  Codex policy (normal mode, managed block)
  .codex/agents/*.toml             Codex implementer and reviewer
  .agents/skills/domestique*/      Codex workflow skills

Options:
  --platform <p> Select claude, codex, or both. A fresh selector-less install
                 remains Claude-only. Explicit installs add to the persisted
                 provider set; later selector-less runs update that set.
  --dry-run      Print planned changes; touch nothing.
  --with-beads   If `bd` is on PATH, initialize with safe skip flags when
                 needed. Normal mode runs setup only for selected providers;
                 guest mode uses --stealth and never runs provider setup.
  --force        Overwrite differing provider files without a .bak backup.
                 Managed policy files are always backed up before change.
  --guest        Use personal/guest mode. Claude routes policy to
                 CLAUDE.local.md; Codex leaves both root AGENTS files
                 untouched and bootstraps through `$domestique` skills.
  --no-guest     Convert an existing guest install back to normal: removes
                 the sticky guest-mode marker and prints by-hand conversion
                 guidance where needed, removes stale guest excludes, and
                 installs the normal policy destination. A no-op note if the
                 target isn't a guest install. Mutually exclusive with
                 --guest (passing both is a usage error).
  --uninstall    Remove everything domestique installed from TARGET_DIR, and
                 only that. With --platform it removes only the selected
                 projection; without it, it scans both. Modified owned files
                 are kept as <file>.uninstalled.<timestamp> unless --force.
                 Managed policy/exclude blocks and provider state are removed,
                 and only empty owned directories are pruned. Never touches
                 .beads/ (see --purge-beads). Combinable only with
                 --platform, --dry-run, --force, --purge-beads, and TARGET_DIR;
                 combining with --guest, --no-guest, or --with-beads is a
                 usage error.
  --purge-beads  Only valid with --uninstall: also `rm -rf` TARGET_DIR/.beads.
                 Without --uninstall this is a usage error.
  --help, -h     Show this help.

Behavior:
  * Existing provider files that differ are backed up to <file>.bak.<timestamp>
    before overwriting (unless --force). Identical files are left untouched.
  * CLAUDE.md: created if absent; if it has the managed markers only the
    content between them is replaced; otherwise the block is appended and all
    existing content is preserved verbatim. Always backed up before change.
  * --guest: for installing into a repo you don't own, for personal use only.
    The managed policy block is written to CLAUDE.local.md instead of
    CLAUDE.md. A tracked CLAUDE.md is never read, modified, or backed up in
    this mode. If CLAUDE.md already carries a non-guest domestique install,
    a warning is printed and CLAUDE.md is left untouched. Everything guest
    mode creates is also kept out of `git status`: a managed block is added
    to <git-common-dir>/info/exclude (resolved via `git rev-parse
    --git-common-dir`, so this works correctly from a worktree too) listing
    provider-local entries. Claude keeps its legacy `CLAUDE.local.md` and
    broad `.claude/` entries; Codex lists only exact domestique-owned leaves
    and state. `.beads/` is added only when domestique's safe guest
    initialization created it; broad backup and `.new` suffix patterns
    are never added. Pre-existing visible Codex paths remain visible across
    reruns and scoped uninstall. If an owned path is already tracked, a
    warning is printed (an exclude can't hide it). `.gitignore` itself
    is never read, written, or otherwise touched by guest mode. A non-git target
    directory prints a warning and skips the exclude step entirely (guest
    install of the rest still proceeds). Net effect: a --guest install
    followed by --uninstall returns the host repo to byte-for-byte clean
    git status, provided nothing installed was modified by hand (modified
    files are preserved as <file>.uninstalled.<timestamp> and show up as
    untracked) and no preserved `.beads/` workspace remains (use
    --purge-beads to remove one).
  * Guest mode is sticky per provider: a guest install writes a mode marker
    in that provider's domestique state. A later plain re-run detects it and
    stays in guest mode instead of silently un-guesting the install; pass
    --no-guest to convert
    back to normal on purpose.
  * Running twice in a row makes no changes on the second run.
  * Pre-existing install with no provider snapshot yet
    and a differing file: ADOPTED, not overwritten — local edits are left in
    place and the base snapshot is seeded from the pristine emitted content
    (not the edited file) so the next run 3-way-merges in upstream changes
    while keeping the edits. Use --force to overwrite verbatim instead.

Periodic updates:
  Use update.sh to fetch the latest domestique.sh from GitHub and re-run it
  against a target directory via this same merge path (see
  docs/install-upgrade-design.md §5). Run `./update.sh --help` for details.
EOF
}

TARGET_DIR=""
PLATFORM_ARG=""
PLATFORM_EXPLICIT=0
DRY_RUN=0
WITH_BEADS=0
FORCE=0
GUEST=0
GUEST_EXPLICIT=0
NO_GUEST=0
UNINSTALL=0
PURGE_BEADS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --platform)
      [ "$#" -ge 2 ] || { echo "Missing argument for --platform" >&2; exit 2; }
      PLATFORM_ARG="$2"; PLATFORM_EXPLICIT=1; shift ;;
    --platform=*)
      PLATFORM_ARG="${1#--platform=}"; PLATFORM_EXPLICIT=1 ;;
    --dry-run)      DRY_RUN=1 ;;
    --with-beads)   WITH_BEADS=1 ;;
    --force)        FORCE=1 ;;
    --guest)        GUEST=1; GUEST_EXPLICIT=1 ;;
    --no-guest)     NO_GUEST=1 ;;
    --uninstall)    UNINSTALL=1 ;;
    --purge-beads)  PURGE_BEADS=1 ;;
    -h|--help)      usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [ -z "$TARGET_DIR" ]; then TARGET_DIR="$1"
      else echo "Unexpected argument: $1" >&2; exit 2; fi
      ;;
  esac
  shift
done
TARGET_DIR="${TARGET_DIR:-.}"

case "${PLATFORM_ARG:-claude}" in
  claude|codex|both) ;;
  *)
    echo "Error: --platform must be one of: claude, codex, both (got '$PLATFORM_ARG')." >&2
    usage >&2
    exit 2
    ;;
esac

if [ "$GUEST_EXPLICIT" -eq 1 ] && [ "$NO_GUEST" -eq 1 ]; then
  echo "Error: --guest and --no-guest are mutually exclusive." >&2
  usage >&2
  exit 2
fi

if [ "$PURGE_BEADS" -eq 1 ] && [ "$UNINSTALL" -eq 0 ]; then
  echo "Error: --purge-beads is only valid together with --uninstall." >&2
  usage >&2
  exit 2
fi

# configure_provider <claude|codex> — select one provider's inventory and
# snapshot namespace. Policy destination is finalized after sticky guest mode
# is resolved for that provider.
configure_provider() {
  CURRENT_PROVIDER="$1"
  SNAPSHOT_TOUCHED=0
  POLICY_DEST=""
  case "$CURRENT_PROVIDER" in
    claude)
      SNAPSHOT_DIR="$TARGET_DIR/.claude/.domestique"
      POLICY_EMITTER="emit_policy"
      POLICY_LABEL="CLAUDE.md"
      POLICY_CANDIDATES="CLAUDE.md CLAUDE.local.md"
      MANAGED_PLAIN_FILES=".claude/agents/implementer.md,.claude/agents/reviewer.md,.claude/commands/decompose.md,.claude/commands/goal.md,.claude/commands/drain.md"
      ;;
    codex)
      SNAPSHOT_DIR="$TARGET_DIR/.codex/.domestique"
      POLICY_EMITTER="emit_codex_policy"
      POLICY_LABEL="AGENTS.md"
      POLICY_CANDIDATES="AGENTS.md AGENTS.override.md"
      MANAGED_PLAIN_FILES=".codex/agents/implementer.toml,.codex/agents/implementer-heavy.toml,.codex/agents/reviewer.toml,.agents/skills/domestique/SKILL.md,.agents/skills/domestique-decompose/SKILL.md,.agents/skills/domestique-goal/SKILL.md,.agents/skills/domestique-goal/agents/openai.yaml"
      ;;
  esac
  SNAPSHOT_BASE="$SNAPSHOT_DIR/base"
  MODE_MARKER="$SNAPSHOT_DIR/mode"
}

# resolve_provider_mode — apply explicit guest/no-guest selection or the
# provider's own sticky marker. Different installed providers may therefore
# retain different guest modes on the same selector-less rerun.
resolve_provider_mode() {
  local marker_content=""
  GUEST="$REQUESTED_GUEST"
  if [ -e "$MODE_MARKER" ]; then
    marker_content="$(cat "$MODE_MARKER" 2>/dev/null || true)"
    case "$marker_content" in
      guest)
        if [ "$NO_GUEST" -eq 1 ]; then
          if [ "$DRY_RUN" -eq 1 ]; then
            note_dry "remove mode marker $MODE_MARKER (--no-guest)"
          else
            rm -f "$MODE_MARKER"
          fi
          echo "domestique: converting guest install for $CURRENT_PROVIDER in $TARGET_DIR to normal mode." >&2
          if [ "$CURRENT_PROVIDER" = "claude" ]; then
            echo "  CLAUDE.local.md is left in place; fold any customizations into CLAUDE.md or remove it by hand." >&2
          else
            echo '  Skills and agents are retained; normal mode now adds the active root AGENTS policy block.' >&2
          fi
          GUEST=0
        elif [ "$GUEST_EXPLICIT" -eq 0 ]; then
          GUEST=1
          echo "Note: existing $CURRENT_PROVIDER guest install detected in $TARGET_DIR — staying in guest mode. Pass --no-guest to convert." >&2
        fi
        ;;
      *)
        echo "Warning: $MODE_MARKER has unexpected content '$marker_content' (expected 'guest') — treating $CURRENT_PROVIDER as normal." >&2
        GUEST=0
        ;;
    esac
  elif [ "$NO_GUEST" -eq 1 ]; then
    echo "Note: --no-guest passed but no $CURRENT_PROVIDER guest marker was found — proceeding normally." >&2
    GUEST=0
  fi

  case "$CURRENT_PROVIDER:$GUEST" in
    claude:1)
      POLICY_DEST="CLAUDE.local.md"
      POLICY_LABEL="$POLICY_DEST"
      if [ -e "$TARGET_DIR/CLAUDE.md" ] && grep -qxF "$MARKER_BEGIN" "$TARGET_DIR/CLAUDE.md" 2>/dev/null; then
        echo "Warning: a normal domestique install exists in $TARGET_DIR/CLAUDE.md — left untouched; guest policy goes to $TARGET_DIR/$POLICY_DEST." >&2
      fi
      ;;
    claude:0)
      POLICY_DEST="CLAUDE.md"
      POLICY_LABEL="$POLICY_DEST"
      ;;
    codex:1)
      # No additive root instruction file exists in Codex. Skills-only guest
      # mode is intentional and leaves both host AGENTS files byte-untouched.
      POLICY_DEST=""
      POLICY_LABEL="skills-only"
      ;;
    codex:0)
      if [ -e "$TARGET_DIR/AGENTS.override.md" ]; then
        POLICY_DEST="AGENTS.override.md"
      else
        POLICY_DEST="AGENTS.md"
      fi
      POLICY_LABEL="$POLICY_DEST"
      ;;
  esac

  if [ -n "$POLICY_DEST" ]; then
    POLICY_SNAPSHOT="$SNAPSHOT_BASE/$POLICY_DEST.block"
  else
    POLICY_SNAPSHOT=""
  fi
}

# Record the exact Codex paths that domestique may hide in guest mode.  The
# file is written for normal installs too, so a later normal -> guest
# conversion can distinguish domestique-created files from host files that
# merely happened to exist before installation.  Older managed exclude blocks
# are accepted as a one-time migration source.
codex_exclude_was_owned() {
  local rel="$1" ownership="$TARGET_DIR/.codex/.domestique/guest-excludes"
  if [ -e "$ownership" ] && grep -qxF "$rel" "$ownership" 2>/dev/null; then
    return 0
  fi

  local common_dir="" exclude_file
  if command -v git >/dev/null 2>&1; then
    common_dir="$(git -C "$TARGET_DIR" rev-parse --git-common-dir 2>/dev/null)" || common_dir=""
    if [ -n "$common_dir" ]; then
      case "$common_dir" in /*) : ;; *) common_dir="$TARGET_DIR/$common_dir" ;; esac
    fi
  fi
  [ -z "$common_dir" ] && [ -d "$TARGET_DIR/.git" ] && common_dir="$TARGET_DIR/.git"
  [ -n "$common_dir" ] || return 1
  exclude_file="$common_dir/info/exclude"
  [ -e "$exclude_file" ] || return 1
  awk -v beginm="$GITEXCLUDE_MARKER_BEGIN" -v endm="$GITEXCLUDE_MARKER_END" -v wanted="$rel" '
    $0 == beginm && !seen { seen=1; inblock=1; next }
    inblock && $0 == endm { exit found ? 0 : 1 }
    inblock && $0 == wanted { found=1 }
    END { exit found ? 0 : 1 }
  ' "$exclude_file"
}

write_codex_guest_ownership() {
  local ownership="$TARGET_DIR/.codex/.domestique/guest-excludes"
  local staged="$TMPDIR_WORK/codex_guest_excludes"
  {
    [ "${CODEX_PREEXIST_IMPL:-0}" -eq 1 ] || printf '.codex/agents/implementer.toml\n'
    [ "${CODEX_PREEXIST_IMPL_HEAVY:-0}" -eq 1 ] || printf '.codex/agents/implementer-heavy.toml\n'
    [ "${CODEX_PREEXIST_REVIEWER:-0}" -eq 1 ] || printf '.codex/agents/reviewer.toml\n'
    printf '.codex/.domestique/\n'
    [ "${CODEX_PREEXIST_BASE_SKILL:-0}" -eq 1 ] || printf '.agents/skills/domestique/SKILL.md\n'
    [ "${CODEX_PREEXIST_DECOMPOSE_SKILL:-0}" -eq 1 ] || printf '.agents/skills/domestique-decompose/SKILL.md\n'
    [ "${CODEX_PREEXIST_GOAL_SKILL:-0}" -eq 1 ] || printf '.agents/skills/domestique-goal/SKILL.md\n'
    [ "${CODEX_PREEXIST_GOAL_META:-0}" -eq 1 ] || printf '.agents/skills/domestique-goal/agents/openai.yaml\n'
  } > "$staged"
  if [ "$DRY_RUN" -eq 1 ]; then
    note_dry "record exact Codex guest ownership -> $ownership"
  else
    mkdir -p "$(dirname "$ownership")"
    [ -e "$ownership" ] && cmp -s "$staged" "$ownership" || cp "$staged" "$ownership"
  fi
}

write_provider_manifest() {
  local manifest="$SNAPSHOT_DIR/manifest" manifest_version=""
  if [ "$SNAPSHOT_TOUCHED" -ne 1 ]; then
    if [ -e "$manifest" ]; then
      manifest_version="$(grep '^domestique_version=' "$manifest" | cut -d= -f2- || true)"
      [ "$manifest_version" = "$DOMESTIQUE_VERSION" ] && return 0
    fi
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note_dry "write/update manifest -> $SNAPSHOT_DIR/manifest"
  else
    mkdir -p "$SNAPSHOT_DIR"
    write_manifest
  fi
}

install_current_provider() {
  echo "domestique: platform=$CURRENT_PROVIDER mode=$([ "$GUEST" -eq 1 ] && printf guest || printf normal) policy=${POLICY_DEST:-skills-only}"

  if [ -n "$POLICY_DEST" ]; then
    install_claude_md "$TARGET_DIR/$POLICY_DEST" "$([ "$GUEST" -eq 1 ] && printf guest || printf normal)" "$POLICY_EMITTER"
  fi

  case "$CURRENT_PROVIDER" in
    claude)
      install_plain "$TARGET_DIR/.claude/agents/implementer.md" emit_implementer
      install_plain "$TARGET_DIR/.claude/agents/reviewer.md" emit_reviewer
      install_plain "$TARGET_DIR/.claude/commands/decompose.md" emit_decompose
      install_plain "$TARGET_DIR/.claude/commands/goal.md" emit_goal
      install_plain "$TARGET_DIR/.claude/commands/drain.md" emit_goal
      ;;
    codex)
      install_plain "$TARGET_DIR/.codex/agents/implementer.toml" emit_codex_implementer
      install_plain "$TARGET_DIR/.codex/agents/implementer-heavy.toml" emit_codex_implementer_heavy
      install_plain "$TARGET_DIR/.codex/agents/reviewer.toml" emit_codex_reviewer
      install_plain "$TARGET_DIR/.agents/skills/domestique/SKILL.md" emit_codex_skill
      install_plain "$TARGET_DIR/.agents/skills/domestique-decompose/SKILL.md" emit_codex_decompose_skill
      install_plain "$TARGET_DIR/.agents/skills/domestique-goal/SKILL.md" emit_codex_goal_skill
      install_plain "$TARGET_DIR/.agents/skills/domestique-goal/agents/openai.yaml" emit_codex_goal_metadata
      write_codex_guest_ownership
      ;;
  esac

  if [ "$GUEST" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      note_dry "write mode marker -> $MODE_MARKER (guest)"
    else
      mkdir -p "$(dirname "$MODE_MARKER")"
      printf 'guest\n' > "$MODE_MARKER"
    fi
  fi
  write_provider_manifest
}

persist_platform_set() {
  local state_dir state_file old
  [ "$CONFLICT_OCCURRED" -eq 0 ] || return 0
  for state_dir in "$TARGET_DIR/.claude/.domestique" "$TARGET_DIR/.codex/.domestique"; do
    case "$state_dir" in
      "$TARGET_DIR/.claude/.domestique") [ "$SELECT_CLAUDE" -eq 1 ] || continue ;;
      "$TARGET_DIR/.codex/.domestique") [ "$SELECT_CODEX" -eq 1 ] || continue ;;
    esac
    state_file="$state_dir/platforms"
    old="$(cat "$state_file" 2>/dev/null || true)"
    [ "$old" = "$PLATFORM_SET" ] && continue
    if [ "$DRY_RUN" -eq 1 ]; then
      note_dry "persist platform set '$PLATFORM_SET' -> $state_file"
    else
      mkdir -p "$state_dir"
      printf '%s\n' "$PLATFORM_SET" > "$state_file"
    fi
  done
}

if [ "$UNINSTALL" -eq 1 ]; then
  if [ "$GUEST_EXPLICIT" -eq 1 ] || [ "$NO_GUEST" -eq 1 ] || [ "$WITH_BEADS" -eq 1 ]; then
    echo "Error: --uninstall is only combinable with --platform, --dry-run, --force, --purge-beads, and TARGET_DIR." >&2
    usage >&2
    exit 2
  fi
fi

if [ ! -d "$TARGET_DIR" ]; then
  echo "Target directory does not exist: $TARGET_DIR" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Platform selection. Provider-owned `platforms` files all carry the same
# canonical installed set. Explicit installs add to that set; selector-less
# reruns use it. A legacy Claude state dir without a platforms file counts as
# Claude, while a genuinely fresh selector-less install remains Claude-only.
# ---------------------------------------------------------------------------
SELECT_CLAUDE=0
SELECT_CODEX=0
PERSISTED_CLAUDE=0
PERSISTED_CODEX=0

read_platform_state() {
  local statefile="$1" value
  [ -e "$statefile" ] || return 0
  value="$(cat "$statefile" 2>/dev/null || true)"
  case "$value" in
    claude) PERSISTED_CLAUDE=1 ;;
    codex) PERSISTED_CODEX=1 ;;
    both) PERSISTED_CLAUDE=1; PERSISTED_CODEX=1 ;;
    *) echo "Warning: ignoring invalid domestique platform state '$value' in $statefile." >&2 ;;
  esac
}

read_platform_state "$TARGET_DIR/.claude/.domestique/platforms"
read_platform_state "$TARGET_DIR/.codex/.domestique/platforms"

# Backfill provider state that predates the platforms marker.
if [ "$PERSISTED_CLAUDE" -eq 0 ] && [ -d "$TARGET_DIR/.claude/.domestique" ]; then
  PERSISTED_CLAUDE=1
fi
if [ "$PERSISTED_CODEX" -eq 0 ] && [ -d "$TARGET_DIR/.codex/.domestique" ]; then
  PERSISTED_CODEX=1
fi

if [ "$PLATFORM_EXPLICIT" -eq 1 ]; then
  SELECT_CLAUDE="$PERSISTED_CLAUDE"
  SELECT_CODEX="$PERSISTED_CODEX"
  case "$PLATFORM_ARG" in
    claude) SELECT_CLAUDE=1 ;;
    codex) SELECT_CODEX=1 ;;
    both) SELECT_CLAUDE=1; SELECT_CODEX=1 ;;
  esac
elif [ "$PERSISTED_CLAUDE" -eq 1 ] || [ "$PERSISTED_CODEX" -eq 1 ]; then
  SELECT_CLAUDE="$PERSISTED_CLAUDE"
  SELECT_CODEX="$PERSISTED_CODEX"
else
  SELECT_CLAUDE=1
fi

if [ "$SELECT_CLAUDE" -eq 1 ] && [ "$SELECT_CODEX" -eq 1 ]; then
  PLATFORM_SET="both"
elif [ "$SELECT_CODEX" -eq 1 ]; then
  PLATFORM_SET="codex"
else
  PLATFORM_SET="claude"
fi

REQUESTED_GUEST="$GUEST"

TS="$(date +%Y%m%d%H%M%S)"
TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# Summary accumulators.
SUM_CREATED=()
SUM_UPDATED=()
SUM_BACKEDUP=()
SUM_SKIPPED=()
SUM_MERGED=()
SUM_CONFLICT=()
SUM_ADOPTED=()
SUM_RESOLVED=()
# --uninstall-only accumulators.
SUM_REMOVED=()
SUM_KEPT=()

# Set to 1 if any file ended in a merge conflict or hard merge error this run;
# drives the final non-zero exit (see docs/install-upgrade-design.md §4).
CONFLICT_OCCURRED=0

note_dry() { [ "$DRY_RUN" -eq 1 ] && echo "  [dry-run] $*"; return 0; }

# print_group <label> <item...> — used by both the install and uninstall
# summary printers. Hoisted here (from its original position just above the
# install summary) so do_uninstall() can call it too.
print_group() {
  local label="$1"; shift
  [ "$#" -eq 0 ] && return 0
  echo "  $label:"
  local item
  for item in "$@"; do echo "    - $item"; done
}

# Provider configuration is swapped before each install projection. Initialize
# with Claude values for compatibility; configure_provider replaces them before
# every selected provider is installed.
CURRENT_PROVIDER="claude"
POLICY_DEST="CLAUDE.md"
POLICY_EMITTER="emit_policy"
POLICY_LABEL="CLAUDE.md"
POLICY_CANDIDATES="CLAUDE.md CLAUDE.local.md"
MANAGED_PLAIN_FILES=".claude/agents/implementer.md,.claude/agents/reviewer.md,.claude/commands/decompose.md,.claude/commands/goal.md,.claude/commands/drain.md"

# ---------------------------------------------------------------------------
# Base snapshot / manifest. The existing merge implementation is provider
# neutral once these paths and inventory values are configured.
# ---------------------------------------------------------------------------
SNAPSHOT_DIR="$TARGET_DIR/.claude/.domestique"
SNAPSHOT_BASE="$SNAPSHOT_DIR/base"
# Policy managed-block snapshot is keyed by destination filename (CLAUDE.md
# vs CLAUDE.local.md under --guest) so a --guest run never reads or rewrites
# the plain run's merge base, and vice versa. See docs/install-upgrade-design.md.
POLICY_SNAPSHOT="$SNAPSHOT_BASE/$POLICY_DEST.block"
SNAPSHOT_TOUCHED=0

# rel_to_base <dest> -> absolute path under SNAPSHOT_BASE mirroring <dest>'s
# path relative to TARGET_DIR, 1:1 (including the .claude/ prefix — no
# managed file lives under .claude/.domestique/, so this never recurses).
rel_to_base() {
  local dest="$1"
  printf '%s' "$SNAPSHOT_BASE/${dest#"$TARGET_DIR"/}"
}

# snapshot_plain <dest> <content-file>
# Record the pristine emitted content as the future merge base. Call only
# after <dest> was actually created/overwritten with <content-file>'s bytes
# (never on an identical-skip — the snapshot is already correct there).
snapshot_plain() {
  local dest="$1" content="$2" basepath
  basepath="$(rel_to_base "$dest")"
  SNAPSHOT_TOUCHED=1
  if [ "$DRY_RUN" -eq 1 ]; then
    note_dry "snapshot base -> $basepath"
    return 0
  fi
  mkdir -p "$(dirname "$basepath")"
  cp "$content" "$basepath"
  # Any base advance supersedes a recorded conflict.
  rm -f "$basepath.conflict"
}

# snapshot_claude_block <content-file>
# Record the managed block BODY (no marker lines) as the future merge base
# for the policy file at $POLICY_DEST (CLAUDE.md, or CLAUDE.local.md under
# --guest). Call only after $POLICY_DEST was actually created/updated.
snapshot_claude_block() {
  local content="$1" basepath="$POLICY_SNAPSHOT"
  SNAPSHOT_TOUCHED=1
  if [ "$DRY_RUN" -eq 1 ]; then
    note_dry "snapshot base -> $basepath"
    return 0
  fi
  mkdir -p "$(dirname "$basepath")"
  cp "$content" "$basepath"
  # Any block base advance supersedes a recorded conflict.
  rm -f "$basepath.conflict"
}

# managed_files_list — provider inventory plus every sound managed policy
# destination still on disk. The current policy destination is included under
# dry-run even before it exists.
managed_files_list() {
  local out="$MANAGED_PLAIN_FILES" policyfile include
  for policyfile in $POLICY_CANDIDATES; do
    include=0
    if [ -n "$POLICY_DEST" ] && [ "$policyfile" = "$POLICY_DEST" ]; then
      include=1
    elif [ -e "$TARGET_DIR/$policyfile" ] && grep -qxF "$MARKER_BEGIN" "$TARGET_DIR/$policyfile" 2>/dev/null; then
      include=1
    fi
    [ "$include" -eq 1 ] && out="$out,$policyfile"
  done
  printf '%s' "$out"
}

# file_sha256 <path> — print the hex sha256 of <path>, or "unavailable" when
# no sha256sum/shasum exists or hashing fails. Never fails the run.
file_sha256() {
  local sha=""
  if command -v sha256sum >/dev/null 2>&1; then
    sha="$(sha256sum "$1" 2>/dev/null | awk '{print $1}')" || sha=""
  elif command -v shasum >/dev/null 2>&1; then
    sha="$(shasum -a 256 "$1" 2>/dev/null | awk '{print $1}')" || sha=""
  fi
  printf '%s\n' "${sha:-unavailable}"
}

# write_manifest — flat key=value manifest describing the snapshot.
write_manifest() {
  local manifest="$SNAPSHOT_DIR/manifest" ref sha
  ref="$(git -C "$(dirname "$0")" rev-parse --short HEAD 2>/dev/null)" || ref="unknown"
  [ -z "$ref" ] && ref="unknown"
  sha="$(file_sha256 "$0")"
  {
    printf 'snapshot_format=1\n'
    printf 'platform=%s\n' "$CURRENT_PROVIDER"
    printf 'domestique_version=%s\n' "$DOMESTIQUE_VERSION"
    printf 'installed_ref=%s\n' "$ref"
    printf 'installed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'script_sha256=%s\n' "$sha"
    printf 'files=%s\n' "$(managed_files_list)"
  } > "$manifest"
}

# install_plain <dest> <emitter-fn>
# Missing -> write. Identical -> skip. --force -> overwrite verbatim, no merge.
# Differs (no --force):
#   - base snapshot exists -> 3-way merge (git merge-file); clean merge
#     overwrites dest and advances the snapshot; conflict/error leaves dest
#     untouched, writes dest.new + a .bak, and does not advance the snapshot.
#     A clean merge whose result is byte-identical to the live file is
#     reported as Skipped and writes nothing; the snapshot advances only if
#     it still lags upstream.
#   - no base snapshot (legacy/pre-snapshot install) -> ADOPT: seed the base
#     snapshot from the PRISTINE freshly-emitted content (not the edited
#     on-disk file), leave the live file unchanged (no .bak, no overwrite).
#     This preserves any local edits now, and sets up the NEXT run to
#     3-way-merge against a vanilla base, so upstream gets applied and
#     local edits are preserved from then on. (Seeding base from the
#     current/edited content instead would make ours == base whenever no
#     further edit is made, causing the next merge to silently drop it.)
# See docs/install-upgrade-design.md §2.
install_plain() {
  local dest="$1" emitter="$2" staged
  staged="$TMPDIR_WORK/staged"
  "$emitter" > "$staged"

  if [ ! -e "$dest" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      note_dry "create $dest"
    else
      mkdir -p "$(dirname "$dest")"
      cp "$staged" "$dest"
    fi
    SUM_CREATED+=("$dest")
    snapshot_plain "$dest" "$staged"
    return 0
  fi

  if cmp -s "$staged" "$dest"; then
    # Identical to the fresh emit — no change needed, but refresh the base
    # snapshot whenever it doesn't already match the fresh emit (covers both
    # a missing base from a legacy install and a stale base left behind when
    # the live file was hand-edited to match upstream before this run).
    local ident_basepath
    ident_basepath="$(rel_to_base "$dest")"
    cmp -s "$staged" "$ident_basepath" || snapshot_plain "$dest" "$staged"
    SUM_SKIPPED+=("$dest (identical)")
    return 0
  fi

  # Differs.
  if [ "$FORCE" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      note_dry "overwrite $dest (--force, no backup)"
    else
      cp "$staged" "$dest"
    fi
    SUM_UPDATED+=("$dest (forced)")
    snapshot_plain "$dest" "$staged"
    return 0
  fi

  local basepath
  basepath="$(rel_to_base "$dest")"

  if [ ! -e "$basepath" ]; then
    # Legacy fallback: no prior snapshot to merge against. ADOPT rather than
    # clobber — leave the live file untouched (no overwrite, no .bak) and
    # seed the base snapshot from the freshly emitted (pristine, un-edited)
    # content, NOT the current on-disk content. This matters: base must
    # represent the *vanilla* baseline so that on the next run,
    # diff(base, ours) reveals the user's local edits (preserved) and
    # diff(base, theirs) reveals the real upstream change (applied). Seeding
    # base from the edited on-disk content instead would make ours == base
    # whenever no further edit has been made, causing git merge-file to
    # take theirs wholesale and silently drop the very edit we're trying
    # to save.
    note_dry "adopt $dest (no base snapshot; seed base from pristine emit, leave file unchanged; re-run to merge upstream)"
    snapshot_plain "$dest" "$staged"
    SUM_ADOPTED+=("$dest (local edits preserved; re-run to merge upstream)")
    return 0
  fi

  # A conflict marker (<base>.conflict, holding the live file's sha256 at
  # conflict time) plus: .new gone, live file changed, no conflict-marker
  # lines -> the user resolved the conflict by hand. Accept it: advance the
  # base to upstream, leave the live file as is.
  if [ -e "$basepath.conflict" ] && [ ! -e "$dest.new" ] \
     && [ "$(file_sha256 "$dest")" != "$(cat "$basepath.conflict")" ] \
     && ! grep -qE '^(<{7}|>{7}|={7}|\|{7})( |$)' "$dest"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      note_dry "resolve $dest (conflict resolved by hand; would advance base, leave file unchanged)"
    else
      snapshot_plain "$dest" "$staged"
    fi
    SUM_RESOLVED+=("$dest (conflict resolved by hand; base advanced, local edits preserved)")
    return 0
  fi

  # 3-way merge: ours=$dest, base=$basepath, theirs=$staged.
  local merged rc=0
  merged="$TMPDIR_WORK/merged"
  git merge-file -p --diff3 \
    -L "yours (local edits)" -L "base (last installed)" -L "upstream (new domestique)" \
    "$dest" "$basepath" "$staged" > "$merged" || rc=$?

  if [ "$rc" -eq 0 ]; then
    if cmp -s "$merged" "$dest"; then
      if [ "$DRY_RUN" -eq 1 ]; then
        note_dry "skip $dest (merge result identical to the live file; local edits preserved)"
      fi
      SUM_SKIPPED+=("$dest (local edits preserved, nothing to apply)")
      # Advance the base only if it still lags upstream; the common no-op case
      # (base == upstream) writes nothing, not even the manifest.
      cmp -s "$staged" "$basepath" || snapshot_plain "$dest" "$staged"
      return 0
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      note_dry "merge $dest (clean)"
    else
      cp "$merged" "$dest"
    fi
    SUM_MERGED+=("$dest")
    snapshot_plain "$dest" "$staged"
    return 0
  fi

  # Conflict (rc = number of conflicted hunks, 1..127) or hard error (rc>=128).
  # Either way: leave the live file untouched, do not advance the snapshot,
  # and force a non-zero exit for the whole run.
  CONFLICT_OCCURRED=1
  local newfile="$dest.new" backup="$dest.bak.$TS" kind="conflict"
  local marker="$basepath.conflict" ours_sha
  ours_sha="$(file_sha256 "$dest")"
  if [ "$rc" -ge 128 ]; then
    kind="error"
    echo "Error: git merge-file failed unexpectedly for $dest (exit $rc)." >&2
  else
    echo "Warning: merge conflict in $dest ($rc hunk(s)) — see $newfile" >&2
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -e "$marker" ] && [ "$(cat "$marker")" = "$ours_sha" ]; then
      note_dry "merge $dest ($kind) — would write $newfile, skip backup (unchanged since the last conflict), record $marker, leave $dest untouched"
    else
      note_dry "merge $dest ($kind) — would write $newfile, back up $dest -> $backup, record $marker, leave $dest untouched"
    fi
  else
    cp "$merged" "$newfile"
    # One .bak per distinct live file: skip it when the file is unchanged
    # since the conflict already recorded in $marker.
    if [ ! -e "$marker" ] || [ "$(cat "$marker")" != "$ours_sha" ]; then
      cp "$dest" "$backup"
      SUM_BACKEDUP+=("$backup")
    fi
    printf '%s\n' "$ours_sha" > "$marker"
  fi
  SUM_CONFLICT+=("$dest ($kind; see $newfile)")
}

# markers_sane <file>
# Checks the domestique managed-block markers (MARKER_BEGIN/MARKER_END) in
# <file> for structural soundness before install/uninstall trust them to
# delimit a single well-formed block. Prints "<status> <begin-count>
# <end-count>" to stdout; status is one of:
#   none       - neither marker present
#   ok         - exactly one of each, BEGIN before END
#   half       - exactly one marker present, its pair missing
#   dup_begin  - BEGIN appears more than once
#   dup_end    - END appears more than once
#   inverted   - one of each present, but END appears before BEGIN
# Any status other than none/ok means the naive BEGIN..END awk strip/splice
# would silently touch the wrong span (data loss) - callers must refuse.
markers_sane() {
  local file="$1" bc ec bl el
  bc=$(grep -cxF "$MARKER_BEGIN" "$file" 2>/dev/null || true)
  ec=$(grep -cxF "$MARKER_END" "$file" 2>/dev/null || true)
  bc="${bc:-0}"; ec="${ec:-0}"
  if [ "$bc" -eq 0 ] && [ "$ec" -eq 0 ]; then
    echo "none $bc $ec"; return 0
  fi
  if [ "$bc" -gt 1 ]; then
    echo "dup_begin $bc $ec"; return 0
  fi
  if [ "$ec" -gt 1 ]; then
    echo "dup_end $bc $ec"; return 0
  fi
  if [ "$bc" -eq 0 ] || [ "$ec" -eq 0 ]; then
    echo "half $bc $ec"; return 0
  fi
  bl=$(grep -nxF "$MARKER_BEGIN" "$file" | head -1 | cut -d: -f1)
  el=$(grep -nxF "$MARKER_END" "$file" | head -1 | cut -d: -f1)
  if [ "$bl" -gt "$el" ]; then
    echo "inverted $bc $ec"; return 0
  fi
  echo "ok $bc $ec"
}

# install_claude_md <dest>
# Missing/no-markers/half-marker -> unchanged from before (create, append,
# refuse). Has both markers, block differs:
#   - --force -> replace block wholesale, no merge, advance snapshot.
#   - base block snapshot exists -> 3-way merge the BLOCK BODY (git
#     merge-file); clean merge splices the merged body back between fresh
#     markers, preserving everything outside the markers byte-for-byte, and
#     advances the snapshot; conflict/error leaves dest untouched, writes
#     dest.new (full file, conflict-marked block spliced in) + a .bak, and
#     does not advance the snapshot.
#   - no base snapshot (legacy/pre-snapshot install) -> ADOPT: seed the
#     block snapshot from the PRISTINE emitted policy body (not the
#     current/edited on-disk block), leave the file unchanged (no
#     overwrite, no .bak); re-run to merge upstream.
# See docs/install-upgrade-design.md §3.
install_claude_md() {
  local dest="$1" mode="${2:-normal}" emitter="${3:-emit_policy}"
  local blk="$TMPDIR_WORK/block" result="$TMPDIR_WORK/claude_result"
  local policybody="$TMPDIR_WORK/policybody"

  "$emitter" "$mode" > "$policybody"

  # Build the managed block: BEGIN marker + verbatim policy + END marker.
  {
    printf '%s\n' "$MARKER_BEGIN"
    cat "$policybody"
    printf '%s\n' "$MARKER_END"
  } > "$blk"

  # Case A: no CLAUDE.md -> create it as just the managed block.
  if [ ! -e "$dest" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      note_dry "create $dest (managed block only)"
    else
      cp "$blk" "$dest"
    fi
    SUM_CREATED+=("$dest")
    snapshot_claude_block "$policybody"
    return 0
  fi

  # Refuse to guess on a structurally unsound managed-block file: a
  # half-marked file (one marker without its pair), duplicate BEGIN/END
  # markers, or END appearing before BEGIN would all make the extract/splice
  # below act on the wrong span - swallowing or misplacing user content is
  # data loss. Leave it untouched and bail.
  local marker_status marker_bc marker_ec
  read -r marker_status marker_bc marker_ec < <(markers_sane "$dest")
  case "$marker_status" in
    none|ok) ;;
    half)
      if [ "$marker_bc" -eq 0 ]; then
        echo "Error: $dest has a '$MARKER_END' marker but no matching '$MARKER_BEGIN'." >&2
      else
        echo "Error: $dest has a '$MARKER_BEGIN' marker but no matching '$MARKER_END'." >&2
      fi
      echo "       Refusing to edit a half-marked file. Fix it by hand and re-run." >&2
      exit 1
      ;;
    dup_begin)
      echo "Error: $dest has more than one '$MARKER_BEGIN' marker ($marker_bc occurrences)." >&2
      echo "       Refusing to edit a file with duplicate markers. Fix it by hand and re-run." >&2
      exit 1
      ;;
    dup_end)
      echo "Error: $dest has more than one '$MARKER_END' marker ($marker_ec occurrences)." >&2
      echo "       Refusing to edit a file with duplicate markers. Fix it by hand and re-run." >&2
      exit 1
      ;;
    inverted)
      echo "Error: $dest has a '$MARKER_END' marker appearing before its '$MARKER_BEGIN' marker." >&2
      echo "       Refusing to edit a file with markers in the wrong order. Fix it by hand and re-run." >&2
      exit 1
      ;;
  esac

  # Case B: has both markers -> replace only the region between them, verbatim rest.
  # marker_status is already known-"ok" here (none/half/dup_*/inverted all
  # exited above), so dispatch on it rather than re-testing with a substring
  # grep that could disagree with markers_sane's whole-line semantics.
  if [ "$marker_status" = "ok" ]; then
    # Extract the current on-disk block body (ours-block) for a potential
    # 3-way merge, and build the wholesale-replace result (today's behavior)
    # for the no-merge-needed / legacy / --force paths.
    local oursblock="$TMPDIR_WORK/oursblock"
    awk -v beginm="$MARKER_BEGIN" -v endm="$MARKER_END" '
      $0 == beginm && !seen { seen=1; inblock=1; next }
      inblock && $0 == endm { inblock=0; next }
      inblock { print }
    ' "$dest" > "$oursblock"

    awk -v beginm="$MARKER_BEGIN" -v endm="$MARKER_END" -v blockfile="$blk" '
      BEGIN { while ((getline line < blockfile) > 0) block = block line ORS }
      $0 == beginm && !seen { seen=1; inblock=1; printf "%s", block; next }
      inblock && $0 == endm { inblock=0; next }
      inblock { next }
      { print }
    ' "$dest" > "$result"

    # If the block body is already current (no user edit, or already up to
    # date), the wholesale-replace result is byte-identical to $dest already
    # — no merge needed. Fall through to the idempotency guard below.
    if ! cmp -s "$oursblock" "$policybody"; then
      if [ "$FORCE" -eq 1 ]; then
        : # wholesale replace (already computed in $result above), no merge.
      else
        local basepath="$POLICY_SNAPSHOT"
        if [ -e "$basepath" ]; then
          # A conflict marker ($basepath.conflict, holding the live file's
          # sha256 at conflict time) plus: dest.new gone, live file changed,
          # no conflict-marker lines -> the user resolved the conflict by
          # hand. Accept it: advance the block base to upstream, leave the
          # live file as is.
          if [ -e "$basepath.conflict" ] && [ ! -e "$dest.new" ] \
             && [ "$(file_sha256 "$dest")" != "$(cat "$basepath.conflict")" ] \
             && ! grep -qE '^(<{7}|>{7}|={7}|\|{7})( |$)' "$dest"; then
            if [ "$DRY_RUN" -eq 1 ]; then
              note_dry "resolve $dest block (conflict resolved by hand; would advance base, leave file unchanged)"
            else
              snapshot_claude_block "$policybody"
            fi
            SUM_RESOLVED+=("$dest ($POLICY_LABEL block: conflict resolved by hand; base advanced, local edits preserved)")
            return 0
          fi

          # 3-way merge the block body: ours=$oursblock, base=$basepath,
          # theirs=$policybody.
          local mergedblock rc=0
          mergedblock="$TMPDIR_WORK/mergedblock"
          git merge-file -p --diff3 \
            -L "yours (local edits)" -L "base (last installed)" -L "upstream (new domestique)" \
            "$oursblock" "$basepath" "$policybody" > "$mergedblock" || rc=$?

          if [ "$rc" -eq 0 ]; then
            # Clean merge: splice the merged block body back between fresh
            # markers, preserving everything outside the markers verbatim.
            awk -v beginm="$MARKER_BEGIN" -v endm="$MARKER_END" -v blockfile="$mergedblock" '
              BEGIN { while ((getline line < blockfile) > 0) block = block line ORS }
              $0 == beginm && !seen { seen=1; inblock=1; print beginm; printf "%s", block; next }
              inblock && $0 == endm { inblock=0; print endm; next }
              inblock { next }
              { print }
            ' "$dest" > "$result"

            if cmp -s "$result" "$dest"; then
              # Live file already matches the merged block — but refresh the
              # block base whenever it doesn't already match the fresh emit
              # (e.g. the block was hand-edited to match upstream).
              cmp -s "$policybody" "$POLICY_SNAPSHOT" || snapshot_claude_block "$policybody"
              SUM_SKIPPED+=("$dest (managed block already current)")
              return 0
            fi

            local backup="$dest.bak.$TS"
            if [ "$DRY_RUN" -eq 1 ]; then
              note_dry "backup $dest -> $backup, then merge managed block (clean)"
            else
              cp "$dest" "$backup"
              cp "$result" "$dest"
            fi
            SUM_BACKEDUP+=("$backup")
            SUM_MERGED+=("$dest ($POLICY_LABEL block)")
            snapshot_claude_block "$policybody"
            return 0
          fi

          # Conflict (rc = number of conflicted hunks, 1..127) or hard error
          # (rc>=128): leave the live file untouched, do not advance the
          # snapshot, write the conflict-marked full file to dest.new, back
          # up the current live file, force a non-zero exit for the run.
          CONFLICT_OCCURRED=1
          local newfile="$dest.new" backup2="$dest.bak.$TS" kind="conflict"
          local marker="$basepath.conflict" ours_sha
          ours_sha="$(file_sha256 "$dest")"
          if [ "$rc" -ge 128 ]; then
            kind="error"
            echo "Error: git merge-file failed unexpectedly for $dest block (exit $rc)." >&2
          else
            echo "Warning: merge conflict in $dest managed block ($rc hunk(s)) — see $newfile" >&2
          fi

          local conflictresult="$TMPDIR_WORK/conflict_result"
          awk -v beginm="$MARKER_BEGIN" -v endm="$MARKER_END" -v blockfile="$mergedblock" '
            BEGIN { while ((getline line < blockfile) > 0) block = block line ORS }
            $0 == beginm && !seen { seen=1; inblock=1; print beginm; printf "%s", block; next }
            inblock && $0 == endm { inblock=0; print endm; next }
            inblock { next }
            { print }
          ' "$dest" > "$conflictresult"

          if [ "$DRY_RUN" -eq 1 ]; then
            if [ -e "$marker" ] && [ "$(cat "$marker")" = "$ours_sha" ]; then
              note_dry "merge $dest block ($kind) — would write $newfile, skip backup (unchanged since the last conflict), record $marker, leave $dest untouched"
            else
              note_dry "merge $dest block ($kind) — would write $newfile, back up $dest -> $backup2, record $marker, leave $dest untouched"
            fi
          else
            cp "$conflictresult" "$newfile"
            # One .bak per distinct live file: skip it when the file is
            # unchanged since the conflict already recorded in $marker.
            if [ ! -e "$marker" ] || [ "$(cat "$marker")" != "$ours_sha" ]; then
              cp "$dest" "$backup2"
              SUM_BACKEDUP+=("$backup2")
            fi
            printf '%s\n' "$ours_sha" > "$marker"
          fi
          SUM_CONFLICT+=("$dest ($kind; see $newfile)")
          return 0
        fi
        # else: no base snapshot -> ADOPT (same rationale as install_plain):
        # seed CLAUDE.md.block from the PRISTINE emitted policy body (not
        # the current on-disk block, which carries the user's edit), and
        # leave the live file unchanged (no overwrite, no .bak). Base must
        # be the vanilla baseline so the next run's merge sees the local
        # edit as ours-vs-base (preserved) and any real upstream change as
        # theirs-vs-base (applied) — seeding from the edited block instead
        # would make ours == base and cause the next merge to silently
        # discard the edit.
        note_dry "adopt $dest (no base snapshot for managed block; seed base from pristine emit, leave file unchanged; re-run to merge upstream)"
        snapshot_claude_block "$policybody"
        SUM_ADOPTED+=("$dest (local edits preserved; re-run to merge upstream)")
        return 0
      fi
    fi
  else
    # Case C: no markers -> append the block, preserving existing bytes verbatim.
    # Add a single newline first only if the file does not already end in one,
    # so the BEGIN marker starts on its own line.
    cp "$dest" "$result"
    if [ -s "$result" ] && [ "$(tail -c 1 "$result" | wc -l)" -eq 0 ]; then
      printf '\n' >> "$result"
    fi
    cat "$blk" >> "$result"
  fi

  # Idempotency guard: if nothing would change, skip (no backup, no write).
  if cmp -s "$result" "$dest"; then
    # Already current — but refresh the block base whenever it doesn't
    # already match the fresh emit (covers both a missing base from a
    # legacy install and a stale base left behind when the block was
    # hand-edited to match upstream before this run).
    cmp -s "$policybody" "$POLICY_SNAPSHOT" || snapshot_claude_block "$policybody"
    SUM_SKIPPED+=("$dest (managed block already current)")
    return 0
  fi

  local backup="$dest.bak.$TS"
  if [ "$DRY_RUN" -eq 1 ]; then
    note_dry "backup $dest -> $backup, then update managed block"
  else
    cp "$dest" "$backup"        # CLAUDE.md is ALWAYS backed up before change.
    cp "$result" "$dest"
  fi
  SUM_BACKEDUP+=("$backup")
  SUM_UPDATED+=("$dest (managed block)")
  snapshot_claude_block "$policybody"
}

# install_git_exclude <target-dir>
# Guest-mode only: hide everything domestique creates from git via a managed
# block in the target repo's git exclude file (.git/info/exclude — a
# local-only ignore file, unlike .gitignore, so it is never committed).
# Resolves the exclude file via `git -C <target> rev-parse --git-common-dir`
# so worktrees/submodules land in the shared common git dir; falls back to
# <target>/.git/info/exclude if git isn't on PATH but .git is a real dir;
# warns and skips (without failing) if the target isn't a git repo at all.
install_git_exclude() {
  local target="$1" common_dir="" exclude_file
  local block="$TMPDIR_WORK/exclude_block" result="$TMPDIR_WORK/exclude_result"

  if command -v git >/dev/null 2>&1; then
    common_dir="$(git -C "$target" rev-parse --git-common-dir 2>/dev/null)" || common_dir=""
    if [ -n "$common_dir" ]; then
      case "$common_dir" in
        /*) : ;;
        *) common_dir="$target/$common_dir" ;;
      esac
    fi
  fi
  if [ -z "$common_dir" ] && [ -d "$target/.git" ]; then
    common_dir="$target/.git"
  fi

  if [ -z "$common_dir" ]; then
    echo "Warning: $target does not look like a git repository — skipping the .git/info/exclude managed block (guest mode)." >&2
    SUM_SKIPPED+=(".git/info/exclude (not a git repository)")
    return 0
  fi

  exclude_file="$common_dir/info/exclude"

  # Warn (never fail) if a guest-managed path is already tracked in the
  # target repo — an exclude entry cannot hide an already-tracked path.
  if command -v git >/dev/null 2>&1; then
    local trackme tracked_paths=".beads"
    [ "${CLAUDE_GUEST_SELECTED:-0}" -eq 1 ] && tracked_paths="CLAUDE.local.md .claude $tracked_paths"
    [ "${CODEX_GUEST_SELECTED:-0}" -eq 1 ] && tracked_paths=".codex/agents/implementer.toml .codex/agents/implementer-heavy.toml .codex/agents/reviewer.toml .codex/.domestique .agents/skills/domestique .agents/skills/domestique-decompose .agents/skills/domestique-goal $tracked_paths"
    for trackme in $tracked_paths; do
      if git -C "$target" ls-files --error-unmatch "$trackme" >/dev/null 2>&1; then
        echo "Warning: $trackme is already tracked in $target — a git exclude entry cannot hide a tracked path. Run 'git rm --cached -r $trackme' if you want it hidden." >&2
      fi
    done
  fi

  {
    printf '%s\n' "$GITEXCLUDE_MARKER_BEGIN"
    if [ "${CLAUDE_GUEST_SELECTED:-0}" -eq 1 ]; then
      printf 'CLAUDE.local.md\n'
      printf '.claude/\n'
    fi
    if [ "${CODEX_GUEST_SELECTED:-0}" -eq 1 ]; then
      local codex_ownership="$target/.codex/.domestique/guest-excludes"
      if [ -e "$codex_ownership" ]; then
        cat "$codex_ownership"
      else
        # Dry-run and legacy-state fallback.  Fresh real installs persist the
        # exact list before this block is reconciled.
        [ "${CODEX_PREEXIST_IMPL:-0}" -eq 1 ] || printf '.codex/agents/implementer.toml\n'
        [ "${CODEX_PREEXIST_IMPL_HEAVY:-0}" -eq 1 ] || printf '.codex/agents/implementer-heavy.toml\n'
        [ "${CODEX_PREEXIST_REVIEWER:-0}" -eq 1 ] || printf '.codex/agents/reviewer.toml\n'
        printf '.codex/.domestique/\n'
        [ "${CODEX_PREEXIST_BASE_SKILL:-0}" -eq 1 ] || printf '.agents/skills/domestique/SKILL.md\n'
        [ "${CODEX_PREEXIST_DECOMPOSE_SKILL:-0}" -eq 1 ] || printf '.agents/skills/domestique-decompose/SKILL.md\n'
        [ "${CODEX_PREEXIST_GOAL_SKILL:-0}" -eq 1 ] || printf '.agents/skills/domestique-goal/SKILL.md\n'
        [ "${CODEX_PREEXIST_GOAL_META:-0}" -eq 1 ] || printf '.agents/skills/domestique-goal/agents/openai.yaml\n'
      fi
    fi
    if { [ "${CLAUDE_GUEST_SELECTED:-0}" -eq 1 ] && [ -e "$target/.claude/.domestique/beads-owned" ]; } ||
       { [ "${CODEX_GUEST_SELECTED:-0}" -eq 1 ] && [ -e "$target/.codex/.domestique/beads-owned" ]; }; then
      printf '.beads/\n'
    fi
    printf '%s\n' "$GITEXCLUDE_MARKER_END"
  } > "$block"

  if [ -e "$exclude_file" ]; then
    if grep -qF "$GITEXCLUDE_MARKER_BEGIN" "$exclude_file" && ! grep -qF "$GITEXCLUDE_MARKER_END" "$exclude_file"; then
      echo "Error: $exclude_file has a '$GITEXCLUDE_MARKER_BEGIN' marker but no matching '$GITEXCLUDE_MARKER_END'." >&2
      echo "       Refusing to edit a half-marked file. Fix it by hand and re-run." >&2
      exit 1
    fi

    if grep -qF "$GITEXCLUDE_MARKER_BEGIN" "$exclude_file"; then
      awk -v beginm="$GITEXCLUDE_MARKER_BEGIN" -v endm="$GITEXCLUDE_MARKER_END" -v blockfile="$block" '
        BEGIN { while ((getline line < blockfile) > 0) blk = blk line ORS }
        $0 == beginm && !seen { seen=1; inblock=1; printf "%s", blk; next }
        inblock && $0 == endm { inblock=0; next }
        inblock { next }
        { print }
      ' "$exclude_file" > "$result"
    else
      cp "$exclude_file" "$result"
      if [ -s "$result" ] && [ "$(tail -c 1 "$result" | wc -l)" -eq 0 ]; then
        printf '\n' >> "$result"
      fi
      cat "$block" >> "$result"
    fi
  else
    cp "$block" "$result"
  fi

  if [ -e "$exclude_file" ] && cmp -s "$result" "$exclude_file"; then
    SUM_SKIPPED+=("$exclude_file (managed block already current)")
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -e "$exclude_file" ]; then
      note_dry "update $exclude_file (managed block)"
      SUM_UPDATED+=("$exclude_file")
    else
      note_dry "create $exclude_file (managed block only)"
      SUM_CREATED+=("$exclude_file")
    fi
    return 0
  fi

  mkdir -p "$(dirname "$exclude_file")"
  if [ -e "$exclude_file" ]; then
    cp "$result" "$exclude_file"
    SUM_UPDATED+=("$exclude_file (managed block)")
  else
    cp "$result" "$exclude_file"
    SUM_CREATED+=("$exclude_file")
  fi
}

# Remove only domestique's managed ignore block.  This is also run after a
# guest -> normal conversion so stale ignores cannot keep normal assets hidden.
remove_git_exclude() {
  local target="$1" common_dir="" exclude_file result="$TMPDIR_WORK/exclude_remove_result"
  if command -v git >/dev/null 2>&1; then
    common_dir="$(git -C "$target" rev-parse --git-common-dir 2>/dev/null)" || common_dir=""
    if [ -n "$common_dir" ]; then
      case "$common_dir" in /*) : ;; *) common_dir="$target/$common_dir" ;; esac
    fi
  fi
  [ -z "$common_dir" ] && [ -d "$target/.git" ] && common_dir="$target/.git"
  [ -n "$common_dir" ] || return 0
  exclude_file="$common_dir/info/exclude"
  [ -e "$exclude_file" ] || return 0
  grep -qF "$GITEXCLUDE_MARKER_BEGIN" "$exclude_file" 2>/dev/null || return 0
  if ! grep -qF "$GITEXCLUDE_MARKER_END" "$exclude_file" 2>/dev/null; then
    echo "Error: $exclude_file has a '$GITEXCLUDE_MARKER_BEGIN' marker but no matching '$GITEXCLUDE_MARKER_END'." >&2
    echo "       Refusing to edit a half-marked file. Fix it by hand and re-run." >&2
    exit 1
  fi
  awk -v beginm="$GITEXCLUDE_MARKER_BEGIN" -v endm="$GITEXCLUDE_MARKER_END" '
    $0 == beginm && !seen { seen=1; inblock=1; next }
    inblock && $0 == endm { inblock=0; next }
    inblock { next }
    { print }
  ' "$exclude_file" > "$result"
  if [ "$DRY_RUN" -eq 1 ]; then
    note_dry "strip domestique block from $exclude_file"
  else
    cp "$result" "$exclude_file"
  fi
  SUM_UPDATED+=("$exclude_file (removed stale guest block)")
}

# `.beads/` is shared across providers. If one domestique guest projection
# created it, every subsequently active guest provider must carry that fact so
# a scoped uninstall of the original owner cannot make the workspace visible.
sync_guest_beads_ownership() {
  local claude_marker="$TARGET_DIR/.claude/.domestique/beads-owned"
  local codex_marker="$TARGET_DIR/.codex/.domestique/beads-owned"
  if [ ! -d "$TARGET_DIR/.beads" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
      rm -f "$claude_marker" "$codex_marker"
    fi
    return 0
  fi
  [ "${ANY_GUEST:-0}" -eq 1 ] || return 0
  if [ ! -e "$claude_marker" ] && [ ! -e "$codex_marker" ]; then
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note_dry "propagate shared .beads ownership across active guest providers"
    return 0
  fi
  if [ "${CLAUDE_GUEST_SELECTED:-0}" -eq 1 ]; then
    mkdir -p "$(dirname "$claude_marker")"
    : > "$claude_marker"
  fi
  if [ "${CODEX_GUEST_SELECTED:-0}" -eq 1 ]; then
    mkdir -p "$(dirname "$codex_marker")"
    : > "$codex_marker"
  fi
}

# do_uninstall <target-dir>
# Remove everything domestique installed into <target-dir>, and only that.
# See usage() --uninstall for the summary of what is (and is not) removed.
do_uninstall() {
  local target="$1"
  local anything_done=0

  # Fixed path inventories are not ownership proof by themselves. Require a
  # provider state tree or one of our managed policy markers before touching
  # plain projection files; this keeps a never-installed host file safe even
  # if its bytes happen to match a domestique template exactly.
  local claude_evidence=0 codex_evidence=0 evidence_file
  [ -d "$target/.claude/.domestique" ] && claude_evidence=1
  [ -d "$target/.codex/.domestique" ] && codex_evidence=1
  for evidence_file in "$target/CLAUDE.md" "$target/CLAUDE.local.md"; do
    [ -e "$evidence_file" ] && grep -qxF "$MARKER_BEGIN" "$evidence_file" 2>/dev/null && claude_evidence=1
  done
  for evidence_file in "$target/AGENTS.md" "$target/AGENTS.override.md"; do
    [ -e "$evidence_file" ] && grep -qxF "$MARKER_BEGIN" "$evidence_file" 2>/dev/null && codex_evidence=1
  done

  # --- 1. provider-owned plain files, safety-compared ----------------------
  local provider state_rel rel emitter dest staged basepath reference
  while IFS='|' read -r provider state_rel rel emitter; do
    [ -z "$rel" ] && continue
    [ "$provider" = "claude" ] && [ "$UNINSTALL_CLAUDE" -eq 0 ] && continue
    [ "$provider" = "codex" ] && [ "$UNINSTALL_CODEX" -eq 0 ] && continue
    [ "$provider" = "claude" ] && [ "$claude_evidence" -eq 0 ] && continue
    [ "$provider" = "codex" ] && [ "$codex_evidence" -eq 0 ] && continue
    dest="$target/$rel"
    [ -e "$dest" ] || continue
    if [ "$provider" = "codex" ] && [ -e "$target/.codex/.domestique/guest-excludes" ] &&
       ! grep -qxF "$rel" "$target/.codex/.domestique/guest-excludes" 2>/dev/null; then
      SUM_KEPT+=("$dest (pre-existing; never domestique-owned)")
      continue
    fi
    staged="$TMPDIR_WORK/uninstall_staged"
    "$emitter" > "$staged"
    basepath="$target/$state_rel/base/$rel"
    reference="$basepath"
    [ -e "$reference" ] || reference="$staged"

    if cmp -s "$dest" "$reference"; then
      anything_done=1
      if [ "$DRY_RUN" -eq 1 ]; then
        note_dry "remove $dest"
      else
        rm -f "$dest"
      fi
      SUM_REMOVED+=("$dest")
    elif [ "$FORCE" -eq 1 ]; then
      anything_done=1
      if [ "$DRY_RUN" -eq 1 ]; then
        note_dry "remove $dest (modified, --force)"
      else
        rm -f "$dest"
      fi
      SUM_REMOVED+=("$dest (modified, --force)")
    else
      anything_done=1
      local kept="$dest.uninstalled.$TS"
      if [ "$DRY_RUN" -eq 1 ]; then
        note_dry "keep $dest (modified) -> would rename to $kept"
      else
        mv "$dest" "$kept"
      fi
      SUM_KEPT+=("$kept")
    fi
  done <<UNINSTALL_FILES
claude|.claude/.domestique|.claude/agents/implementer.md|emit_implementer
claude|.claude/.domestique|.claude/agents/reviewer.md|emit_reviewer
claude|.claude/.domestique|.claude/commands/decompose.md|emit_decompose
claude|.claude/.domestique|.claude/commands/goal.md|emit_goal
claude|.claude/.domestique|.claude/commands/drain.md|emit_goal
codex|.codex/.domestique|.codex/agents/implementer.toml|emit_codex_implementer
codex|.codex/.domestique|.codex/agents/implementer-heavy.toml|emit_codex_implementer_heavy
codex|.codex/.domestique|.codex/agents/reviewer.toml|emit_codex_reviewer
codex|.codex/.domestique|.agents/skills/domestique/SKILL.md|emit_codex_skill
codex|.codex/.domestique|.agents/skills/domestique-decompose/SKILL.md|emit_codex_decompose_skill
codex|.codex/.domestique|.agents/skills/domestique-goal/SKILL.md|emit_codex_goal_skill
codex|.codex/.domestique|.agents/skills/domestique-goal/agents/openai.yaml|emit_codex_goal_metadata
UNINSTALL_FILES

  # --- 2. managed policy blocks for selected providers --------------------
  local policyfile policymode policyemitter policybase
  while IFS='|' read -r provider policyfile policymode policyemitter policybase; do
    [ "$provider" = "claude" ] && [ "$UNINSTALL_CLAUDE" -eq 0 ] && continue
    [ "$provider" = "codex" ] && [ "$UNINSTALL_CODEX" -eq 0 ] && continue
    dest="$target/$policyfile"
    [ -e "$dest" ] || continue

    local marker_status marker_bc marker_ec
    read -r marker_status marker_bc marker_ec < <(markers_sane "$dest")
    [ "$marker_status" = "none" ] && continue

    # Refuse to guess on a structurally unsound managed-block file: one
    # marker present without its pair, duplicate BEGIN/END markers, or END
    # appearing before BEGIN would all make the strip below act on the wrong
    # span (data loss). Leave it byte-untouched and mark the run conflicted,
    # mirroring install's guard, but without aborting the whole run — other
    # files still get uninstalled.
    if [ "$marker_status" != "ok" ]; then
      anything_done=1
      CONFLICT_OCCURRED=1
      local marker_problem=""
      case "$marker_status" in
        half)
          if [ "$marker_bc" -eq 0 ]; then
            echo "Error: $dest has a '$MARKER_END' marker but no matching '$MARKER_BEGIN'." >&2
          else
            echo "Error: $dest has a '$MARKER_BEGIN' marker but no matching '$MARKER_END'." >&2
          fi
          echo "       Refusing to edit a half-marked file. Fix it by hand and re-run." >&2
          marker_problem="half-marked managed block"
          ;;
        dup_begin)
          echo "Error: $dest has more than one '$MARKER_BEGIN' marker ($marker_bc occurrences)." >&2
          echo "       Refusing to edit a file with duplicate markers. Fix it by hand and re-run." >&2
          marker_problem="duplicate BEGIN marker"
          ;;
        dup_end)
          echo "Error: $dest has more than one '$MARKER_END' marker ($marker_ec occurrences)." >&2
          echo "       Refusing to edit a file with duplicate markers. Fix it by hand and re-run." >&2
          marker_problem="duplicate END marker"
          ;;
        inverted)
          echo "Error: $dest has a '$MARKER_END' marker appearing before its '$MARKER_BEGIN' marker." >&2
          echo "       Refusing to edit a file with markers in the wrong order. Fix it by hand and re-run." >&2
          marker_problem="markers in wrong order (END before BEGIN)"
          ;;
      esac
      note_dry "ERROR: $dest has $marker_problem — leaving it untouched, not uninstalling"
      SUM_CONFLICT+=("$dest ($marker_problem)")
      continue
    fi

    anything_done=1

    local oursblock pristine refblock modified=0
    oursblock="$TMPDIR_WORK/uninstall_oursblock"
    awk -v beginm="$MARKER_BEGIN" -v endm="$MARKER_END" '
      $0 == beginm && !seen { seen=1; inblock=1; next }
      inblock && $0 == endm { inblock=0; next }
      inblock { print }
    ' "$dest" > "$oursblock"

    pristine="$TMPDIR_WORK/uninstall_pristine"
    "$policyemitter" "$policymode" > "$pristine"
    refblock="$target/$policybase/base/$policyfile.block"
    [ -e "$refblock" ] || refblock="$pristine"
    cmp -s "$oursblock" "$refblock" || modified=1

    # Strip the block (including markers), preserving everything else
    # verbatim. Back the file up first ONLY when the block was user-modified
    # relative to its base/pristine content — an exact-inverse strip needs no
    # backup and must not leave a stray .bak behind (round-trip byte-parity
    # with the pre-install tree, verified by scenario a/b).
    local result backup
    result="$TMPDIR_WORK/uninstall_result"
    awk -v beginm="$MARKER_BEGIN" -v endm="$MARKER_END" '
      $0 == beginm && !seen { seen=1; inblock=1; next }
      inblock && $0 == endm { inblock=0; next }
      inblock { next }
      { print }
    ' "$dest" > "$result"

    if [ "$modified" -eq 1 ]; then
      backup="$dest.bak.$TS"
      if [ "$DRY_RUN" -eq 1 ]; then
        note_dry "backup $dest -> $backup (managed block was modified)"
      else
        cp "$dest" "$backup"
      fi
      SUM_BACKEDUP+=("$backup")
    fi

    if grep -q '[^[:space:]]' "$result" 2>/dev/null; then
      if [ "$DRY_RUN" -eq 1 ]; then
        note_dry "strip managed block from $dest, leaving the rest of the file intact"
      else
        cp "$result" "$dest"
      fi
      SUM_REMOVED+=("$dest (managed block)")
    else
      if [ "$DRY_RUN" -eq 1 ]; then
        note_dry "remove $dest (empty after stripping managed block)"
      else
        rm -f "$dest"
      fi
      SUM_REMOVED+=("$dest")
    fi
  done <<UNINSTALL_POLICIES
claude|CLAUDE.md|normal|emit_policy|.claude/.domestique
claude|CLAUDE.local.md|guest|emit_policy|.claude/.domestique
codex|AGENTS.md|normal|emit_codex_policy|.codex/.domestique
codex|AGENTS.override.md|normal|emit_codex_policy|.codex/.domestique
UNINSTALL_POLICIES

  # --- 3. managed block in <git-common-dir>/info/exclude ------------------
  # A scoped uninstall retains an exact union for any other provider that is
  # still guest-installed. Only the final guest-provider removal strips it.
  local keep_claude_guest=0 keep_codex_guest=0
  if [ "$UNINSTALL_CLAUDE" -eq 0 ] && [ "$(cat "$target/.claude/.domestique/mode" 2>/dev/null || true)" = "guest" ]; then
    keep_claude_guest=1
  fi
  if [ "$UNINSTALL_CODEX" -eq 0 ] && [ "$(cat "$target/.codex/.domestique/mode" 2>/dev/null || true)" = "guest" ]; then
    keep_codex_guest=1
  fi

  if [ "$keep_claude_guest" -eq 1 ] || [ "$keep_codex_guest" -eq 1 ]; then
    CLAUDE_GUEST_SELECTED="$keep_claude_guest"
    CODEX_GUEST_SELECTED="$keep_codex_guest"
    install_git_exclude "$target"
    anything_done=1
  else
  local common_dir="" exclude_file
  if command -v git >/dev/null 2>&1; then
    common_dir="$(git -C "$target" rev-parse --git-common-dir 2>/dev/null)" || common_dir=""
    if [ -n "$common_dir" ]; then
      case "$common_dir" in
        /*) : ;;
        *) common_dir="$target/$common_dir" ;;
      esac
    fi
  fi
  if [ -z "$common_dir" ] && [ -d "$target/.git" ]; then
    common_dir="$target/.git"
  fi

  if [ -n "$common_dir" ]; then
    exclude_file="$common_dir/info/exclude"
    if [ -e "$exclude_file" ] && grep -qF "$GITEXCLUDE_MARKER_BEGIN" "$exclude_file" 2>/dev/null; then
      anything_done=1
      local exresult
      exresult="$TMPDIR_WORK/uninstall_exclude_result"
      awk -v beginm="$GITEXCLUDE_MARKER_BEGIN" -v endm="$GITEXCLUDE_MARKER_END" '
        $0 == beginm && !seen { seen=1; inblock=1; next }
        inblock && $0 == endm { inblock=0; next }
        inblock { next }
        { print }
      ' "$exclude_file" > "$exresult"
      if [ "$DRY_RUN" -eq 1 ]; then
        note_dry "strip domestique block from $exclude_file (preserving everything else)"
      else
        cp "$exresult" "$exclude_file"
      fi
      SUM_REMOVED+=("$exclude_file (managed block)")
    fi
  fi
  # Non-git target: nothing was installed there — skip silently.
  fi

  # --- 4. selected provider state (do this after snapshot comparisons) -----
  local snapshot_dir
  for snapshot_dir in "$target/.claude/.domestique" "$target/.codex/.domestique"; do
    case "$snapshot_dir" in
      "$target/.claude/.domestique") [ "$UNINSTALL_CLAUDE" -eq 1 ] || continue ;;
      "$target/.codex/.domestique") [ "$UNINSTALL_CODEX" -eq 1 ] || continue ;;
    esac
    [ -e "$snapshot_dir" ] || continue
    anything_done=1
    if [ "$DRY_RUN" -eq 1 ]; then
      note_dry "remove $snapshot_dir (snapshots, manifest, mode marker)"
    else
      rm -rf "$snapshot_dir"
    fi
    SUM_REMOVED+=("$snapshot_dir")
  done

  # Keep the surviving provider's persisted set authoritative.
  local remaining_state="" remaining_value=""
  if [ "$UNINSTALL_CLAUDE" -eq 1 ] && [ "$UNINSTALL_CODEX" -eq 0 ] && [ -d "$target/.codex/.domestique" ]; then
    remaining_state="$target/.codex/.domestique/platforms"; remaining_value="codex"
  elif [ "$UNINSTALL_CODEX" -eq 1 ] && [ "$UNINSTALL_CLAUDE" -eq 0 ] && [ -d "$target/.claude/.domestique" ]; then
    remaining_state="$target/.claude/.domestique/platforms"; remaining_value="claude"
  fi
  if [ -n "$remaining_state" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      note_dry "persist platform set '$remaining_value' -> $remaining_state"
    else
      printf '%s\n' "$remaining_value" > "$remaining_state"
    fi
  fi

  # Prune now-empty dirs, never one that still has user content.
  if [ "$DRY_RUN" -eq 1 ]; then
    note_dry "prune selected provider directories if left empty"
  else
    if [ "$UNINSTALL_CLAUDE" -eq 1 ]; then
      rmdir "$target/.claude/agents" 2>/dev/null || true
      rmdir "$target/.claude/commands" 2>/dev/null || true
      rmdir "$target/.claude" 2>/dev/null || true
    fi
    if [ "$UNINSTALL_CODEX" -eq 1 ]; then
      rmdir "$target/.codex/agents" 2>/dev/null || true
      rmdir "$target/.codex" 2>/dev/null || true
      rmdir "$target/.agents/skills/domestique-goal/agents" 2>/dev/null || true
      rmdir "$target/.agents/skills/domestique-goal" 2>/dev/null || true
      rmdir "$target/.agents/skills/domestique-decompose" 2>/dev/null || true
      rmdir "$target/.agents/skills/domestique" 2>/dev/null || true
      rmdir "$target/.agents/skills" 2>/dev/null || true
      rmdir "$target/.agents" 2>/dev/null || true
    fi
  fi

  # --- 7. .beads/ — never touched by default -------------------------------
  if [ -d "$target/.beads" ]; then
    if [ "$PURGE_BEADS" -eq 1 ]; then
      anything_done=1
      if [ "$DRY_RUN" -eq 1 ]; then
        note_dry "remove $target/.beads (--purge-beads)"
      else
        rm -rf "$target/.beads"
      fi
      SUM_REMOVED+=("$target/.beads (--purge-beads)")
    else
      echo "Note: $target/.beads left in place (domestique never removes it by default) — pass --purge-beads, or remove it by hand: rm -rf $target/.beads" >&2
    fi
  fi

  echo
  if [ "$anything_done" -eq 0 ]; then
    echo "domestique: nothing to remove in $target — no domestique install detected."
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then echo "Summary (planned uninstall):"; else echo "Summary (uninstall):"; fi
  [ "${#SUM_REMOVED[@]}"   -gt 0 ] && print_group "Removed"         "${SUM_REMOVED[@]}"
  [ "${#SUM_KEPT[@]}"      -gt 0 ] && print_group "Kept (modified)" "${SUM_KEPT[@]}"
  [ "${#SUM_BACKEDUP[@]}"  -gt 0 ] && print_group "Backed up"       "${SUM_BACKEDUP[@]}"
  [ "${#SUM_SKIPPED[@]}"   -gt 0 ] && print_group "Skipped"         "${SUM_SKIPPED[@]}"
  [ "${#SUM_CONFLICT[@]}"  -gt 0 ] && print_group "Conflicted"      "${SUM_CONFLICT[@]}"
  [ "$DRY_RUN" -eq 1 ] && echo "  (dry run: nothing was actually changed)"

  if [ "$CONFLICT_OCCURRED" -eq 1 ]; then
    echo
    echo "One or more files ended in conflict/error — see 'Conflicted' above." >&2
    return 3
  fi
  echo "Done."
}

if [ "$UNINSTALL" -eq 1 ]; then
  UNINSTALL_CLAUDE=1
  UNINSTALL_CODEX=1
  if [ "$PLATFORM_EXPLICIT" -eq 1 ]; then
    UNINSTALL_CLAUDE=0
    UNINSTALL_CODEX=0
    case "$PLATFORM_ARG" in
      claude) UNINSTALL_CLAUDE=1 ;;
      codex) UNINSTALL_CODEX=1 ;;
      both) UNINSTALL_CLAUDE=1; UNINSTALL_CODEX=1 ;;
    esac
  fi
  echo "domestique: uninstalling from $TARGET_DIR (platform=${PLATFORM_ARG:-all})"
  [ "$DRY_RUN" -eq 1 ] && echo "(dry run — no files will be modified)"
  do_uninstall "$TARGET_DIR"
  exit $?
fi

# ---------------------------------------------------------------------------
echo "domestique: installing into $TARGET_DIR (platforms=$PLATFORM_SET)"
[ "$DRY_RUN" -eq 1 ] && echo "(dry run — no files will be modified)"

ANY_GUEST=0
CLAUDE_GUEST_SELECTED=0
CODEX_GUEST_SELECTED=0
# Preserve the pre-install visibility of existing untracked Codex-owned
# paths: guest exclude hides only files domestique is creating itself.
CODEX_PREEXIST_IMPL=0
CODEX_PREEXIST_IMPL_HEAVY=0
CODEX_PREEXIST_REVIEWER=0
CODEX_PREEXIST_BASE_SKILL=0
CODEX_PREEXIST_DECOMPOSE_SKILL=0
CODEX_PREEXIST_GOAL_SKILL=0
CODEX_PREEXIST_GOAL_META=0
[ -e "$TARGET_DIR/.codex/agents/implementer.toml" ] && ! codex_exclude_was_owned '.codex/agents/implementer.toml' && CODEX_PREEXIST_IMPL=1
[ -e "$TARGET_DIR/.codex/agents/implementer-heavy.toml" ] && ! codex_exclude_was_owned '.codex/agents/implementer-heavy.toml' && CODEX_PREEXIST_IMPL_HEAVY=1
[ -e "$TARGET_DIR/.codex/agents/reviewer.toml" ] && ! codex_exclude_was_owned '.codex/agents/reviewer.toml' && CODEX_PREEXIST_REVIEWER=1
[ -e "$TARGET_DIR/.agents/skills/domestique/SKILL.md" ] && ! codex_exclude_was_owned '.agents/skills/domestique/SKILL.md' && CODEX_PREEXIST_BASE_SKILL=1
[ -e "$TARGET_DIR/.agents/skills/domestique-decompose/SKILL.md" ] && ! codex_exclude_was_owned '.agents/skills/domestique-decompose/SKILL.md' && CODEX_PREEXIST_DECOMPOSE_SKILL=1
[ -e "$TARGET_DIR/.agents/skills/domestique-goal/SKILL.md" ] && ! codex_exclude_was_owned '.agents/skills/domestique-goal/SKILL.md' && CODEX_PREEXIST_GOAL_SKILL=1
[ -e "$TARGET_DIR/.agents/skills/domestique-goal/agents/openai.yaml" ] && ! codex_exclude_was_owned '.agents/skills/domestique-goal/agents/openai.yaml' && CODEX_PREEXIST_GOAL_META=1
if [ "$SELECT_CLAUDE" -eq 1 ]; then
  configure_provider claude
  resolve_provider_mode
  if [ "$GUEST" -eq 1 ]; then
    ANY_GUEST=1
    CLAUDE_GUEST_SELECTED=1
  fi
  install_current_provider
fi
if [ "$SELECT_CODEX" -eq 1 ]; then
  configure_provider codex
  resolve_provider_mode
  if [ "$GUEST" -eq 1 ]; then
    ANY_GUEST=1
    CODEX_GUEST_SELECTED=1
    printf '%s\n' "Note: Codex guest mode is skills-only; start each new session with \`\$domestique\`." >&2
  fi
  install_current_provider
fi

persist_platform_set

# --- beads (opt-in) --------------------------------------------------------
if [ "$WITH_BEADS" -eq 1 ]; then
  if command -v bd >/dev/null 2>&1; then
    BD_READY_FOR_SETUP=0
    if [ -d "$TARGET_DIR/.beads" ]; then
      SUM_SKIPPED+=("bd init (.beads/ already present)")
      BD_READY_FOR_SETUP=1
    else
      BD_INIT_SAFE=1
      if [ "$DRY_RUN" -eq 0 ]; then
        BD_INIT_HELP="$(bd init --help 2>&1 || true)"
        case "$BD_INIT_HELP" in
          *--skip-agents*--skip-hooks*) : ;;
          *) BD_INIT_SAFE=0 ;;
        esac
        if [ "$ANY_GUEST" -eq 1 ]; then
          case "$BD_INIT_HELP" in *--stealth*) : ;; *) BD_INIT_SAFE=0 ;; esac
        fi
      fi
      if [ "$BD_INIT_SAFE" -eq 0 ]; then
        echo "Warning: installed bd lacks the safe init flags required by domestique; skipping --with-beads initialization." >&2
        SUM_SKIPPED+=("beads init (safe --skip-agents/--skip-hooks flags unavailable)")
      elif [ "$DRY_RUN" -eq 1 ]; then
        if [ "$ANY_GUEST" -eq 1 ]; then
          note_dry "run: bd init --stealth --skip-agents --skip-hooks --non-interactive (in $TARGET_DIR)"
        else
          note_dry "run: bd init --skip-agents --skip-hooks --non-interactive (in $TARGET_DIR)"
        fi
      else
        if [ "$ANY_GUEST" -eq 1 ]; then
          ( cd "$TARGET_DIR" && bd init --stealth --skip-agents --skip-hooks --non-interactive )
          if [ "$CLAUDE_GUEST_SELECTED" -eq 1 ]; then
            mkdir -p "$TARGET_DIR/.claude/.domestique"
            : > "$TARGET_DIR/.claude/.domestique/beads-owned"
          fi
          if [ "$CODEX_GUEST_SELECTED" -eq 1 ]; then
            mkdir -p "$TARGET_DIR/.codex/.domestique"
            : > "$TARGET_DIR/.codex/.domestique/beads-owned"
          fi
        else
          ( cd "$TARGET_DIR" && bd init --skip-agents --skip-hooks --non-interactive )
        fi
      fi
      [ "$BD_INIT_SAFE" -eq 1 ] && SUM_CREATED+=(".beads/ (bd init)")
      [ "$BD_INIT_SAFE" -eq 1 ] && BD_READY_FOR_SETUP=1
    fi

    if [ "$ANY_GUEST" -eq 1 ]; then
      echo "Note: guest mode intentionally skips bd setup provider recipes to preserve host instructions and hooks." >&2
      SUM_SKIPPED+=("bd setup (guest isolation)")
    elif [ "$BD_READY_FOR_SETUP" -eq 1 ]; then
      if [ "$SELECT_CLAUDE" -eq 1 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then note_dry "run: bd setup claude (in $TARGET_DIR)"
        else ( cd "$TARGET_DIR" && bd setup claude ); fi
        SUM_UPDATED+=("bd setup claude")
      fi
      if [ "$SELECT_CODEX" -eq 1 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then note_dry "run: bd setup codex (in $TARGET_DIR)"
        else ( cd "$TARGET_DIR" && bd setup codex ); fi
        SUM_UPDATED+=("bd setup codex")
      fi
    else
      SUM_SKIPPED+=("bd setup (beads workspace unavailable)")
    fi
  else
    SUM_SKIPPED+=("beads: 'bd' not found on PATH — skipped (install not required)")
  fi
fi

sync_guest_beads_ownership
if [ "$ANY_GUEST" -eq 1 ]; then
  install_git_exclude "$TARGET_DIR"
else
  remove_git_exclude "$TARGET_DIR"
fi

# --- summary ---------------------------------------------------------------
echo
if [ "$DRY_RUN" -eq 1 ]; then echo "Summary (planned):"; else echo "Summary:"; fi
[ "${#SUM_CREATED[@]}"  -gt 0 ] && print_group "Created"    "${SUM_CREATED[@]}"
[ "${#SUM_UPDATED[@]}"  -gt 0 ] && print_group "Updated"    "${SUM_UPDATED[@]}"
[ "${#SUM_MERGED[@]}"   -gt 0 ] && print_group "Merged"     "${SUM_MERGED[@]}"
[ "${#SUM_ADOPTED[@]}"  -gt 0 ] && print_group "Adopted"    "${SUM_ADOPTED[@]}"
[ "${#SUM_RESOLVED[@]}" -gt 0 ] && print_group "Resolved"   "${SUM_RESOLVED[@]}"
[ "${#SUM_BACKEDUP[@]}" -gt 0 ] && print_group "Backed up"  "${SUM_BACKEDUP[@]}"
[ "${#SUM_SKIPPED[@]}"  -gt 0 ] && print_group "Skipped"    "${SUM_SKIPPED[@]}"
[ "${#SUM_CONFLICT[@]}" -gt 0 ] && print_group "Conflicted" "${SUM_CONFLICT[@]}"
[ "$DRY_RUN" -eq 1 ] && echo "  (dry run: nothing was actually changed)"

if [ "$CONFLICT_OCCURRED" -eq 1 ]; then
  echo
  echo "One or more files ended in conflict/error — see 'Conflicted' above and the .new/.bak files for each." >&2
  exit 3
fi
echo "Done."
