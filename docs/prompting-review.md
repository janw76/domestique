# Prompting review of the domestique Claude templates

Audit of the five templates emitted by `domestique.sh` (line numbers below refer to that file at commit `cf8bf91`) against Anthropic's prompting guides as fetched on 2026-09-08. The general guide's golden rule — a colleague with minimal context could follow the prompt — is the primary lens. Goal findings are numbered `GO1..` rather than `G1..` because `G1..` is already used for general-guide rule ids; the brief assigned both prefixes and one had to move.

Test phrases locked by `test/*.sh` and kept intact by every proposal: `Parallel eligibility`, `Parallel planning`, `Worktree flow`, `at most 2`, `batch`, `Files:`, `Shared-infra:`, `isolation`, `merge conflict`, `Never commit`, `grilling`, `verbatim`, `full epic title`, `full task title`, both skill-absent notices, and the guest/normal `then commit \`.beads/\`` distinction.

## Rule checklist

Sources: GEN = https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices, SON = .../prompting-claude-sonnet-5, OPU = .../prompting-claude-opus-5, FAB = .../prompting-claude-fable-5-1 (same path prefix as GEN).

General (all templates):
- G1 Be specific about the desired output format and constraints; request "above and beyond" explicitly rather than implying it. GEN#be-clear-and-direct
- G2 Golden rule: a colleague with minimal context must be able to follow the prompt without confusion. GEN#be-clear-and-direct
- G3 Use numbered steps when order or completeness matters. GEN#be-clear-and-direct
- G4 Give the motivation behind an instruction; the model generalizes from the why. GEN#add-context-to-improve-performance
- G5 Steer format and tone with relevant, diverse examples wrapped in `<example>` tags. GEN#use-examples-effectively
- G6 Use XML tags when a prompt mixes instructions, context, examples, and variable inputs. GEN#structure-prompts-with-xml-tags
- G7 Set a role in one sentence. GEN#give-claude-a-role
- G8 Say what to do instead of what not to do. GEN#control-the-format-of-responses
- G9 The prompt's own formatting style shapes the output's style. GEN#control-the-format-of-responses
- G10 Dial back aggressive language ("CRITICAL: you MUST"); current models overtrigger on it. GEN#tool-usage
- G11 Remove over-prompting and anti-laziness scaffolding ("if in doubt, do X"); replace blanket defaults with targeted instructions. GEN#overthinking-and-excessive-thoroughness, GEN#migration-considerations
- G12 Use imperative direction when you want action, not "can you suggest". GEN#tool-usage
- G13 Name which actions are reversible and which need confirmation (deletes, force-push, reset --hard, pushes); never bypass safety checks as a shortcut. GEN#balancing-autonomy-and-safety
- G14 Models delegate natively; state when subagents are and are not warranted. GEN#subagent-orchestration
- G15 Give explicit minimal-scope guidance to prevent over-engineering. GEN#overeagerness
- G16 Tell the model to report incorrect or infeasible tests rather than hard-code around them. GEN#avoid-focusing-on-passing-tests-and-hardcoding
- G17 Investigate before claiming: never speculate about code not opened. GEN#minimizing-hallucinations-in-agentic-coding
- G18 Keep state in structured, durable places (git, structured files) and work incrementally. GEN#state-management-best-practices
- G19 Ask for temporary files to be cleaned up at the end of the task. GEN#reduce-file-creation-in-agentic-coding
- G20 If you want a summary after tool-heavy work, ask for it explicitly. GEN#communication-style-and-verbosity
- G21 Put long data above the query and wrap documents in XML (20k+ token inputs). GEN#long-context-prompting
- G22 In a harness that compacts context, say so and tell the model not to stop tasks early over token-budget concerns; save state before the window refreshes. GEN#context-awareness-and-multiwindow-workflows
- G23 Across context windows: keep durable state in files/git, be prescriptive about how to resume, and encourage completing the task rather than stopping with uncommitted work. GEN#workflows-across-multiple-context-windows
- G24 Independent tool calls run in parallel by default; steer explicitly only if you need more or less of it. GEN#optimize-parallel-tool-calling

Sonnet 5 (implementer):
- S1 Prefer positive examples of the desired concision over "do not" instructions. SON#response-length-and-verbosity
- S2 Sonnet 5 reaches for tools and self-verification loops readily; do not add scaffolding that forces extra loops. SON#tool-use-triggering
- S3 Remove forced interim-status scaffolding; describe the shape of updates only if needed. SON#user-facing-progress-updates
- S4 Sonnet 5 follows instructions literally and does not generalize; state scope explicitly. SON#more-literal-instruction-following
- S5 Specify task, intent, and constraints up front in the first turn. SON#interactive-coding-products
- S6 Avoid "be conservative"/severity-filter language in anything that reports findings; ask for coverage and let a later step filter. SON#code-review-harnesses
- S7 Prose style shifts between models; re-check any voice/tone instruction against the new baseline. SON#tone-and-writing-style

Opus 5 (reviewer):
- O1 Do not say "only high-severity" or "be conservative" in review prompts; ask it to report everything and filter separately. OPU#capability-improvements
- O2 Prompt explicitly for conciseness, with a short reminder near the end of a long prompt. OPU#response-length-and-verbosity
- O3 Describe update cadence; lead with the outcome, detail after. OPU#user-facing-progress-updates
- O4 Calibrate the length of written deliverables explicitly. OPU#written-deliverable-length
- O5 Remove self-verification and re-check instructions; Opus 5 does them unprompted and they compound. OPU#task-scope-and-over-verification, OPU#self-correction
- O6 Constrain scope explicitly for narrow tasks; say so in a sentence and continue rather than transform the task. OPU#task-scope-and-over-verification
- O7 Give explicit guidance or hard caps on subagent spawning; never use subagents to verify its own work. OPU#controlling-subagent-spawning
- O8 Limit correction narration to corrections that change the outcome. OPU#self-correction
- O9 Give the complete task specification up front and let it run. OPU#capability-improvements
- O10 Positive examples of the communication style beat "do not" instructions. OPU#user-facing-progress-updates

Fable 5.1 (policy, decompose, goal):
- F1 Fable 5.1 writes few updates during long tool chains; remove narration-suppressing lines and say when you want a line and what it should contain. FAB#ask-for-user-facing-progress-updates
- F2 In agent loops, nudge it to request every independent item in one response. FAB#batch-independent-tool-calls-in-agent-loops
- F3 Remove mannered prose; say what you mean in literal phrases. FAB#writing-density
- F4 Remove anti-formatting rules; instead say when lists or headings are appropriate. FAB#formatting-in-chat
- F5 For autonomous work, open with "You are operating autonomously. The user is not watching..." and list the specific confirmations it must still stop for; add the last-paragraph check. FAB#finish-the-whole-task
- F6 The request sets the scope and the scope is the deliverable; make routine judgment calls, check in only when readings differ materially. FAB#finish-the-whole-task
- F7 Report pre-existing bugs and extras as follow-ups; keep changes and committed tests to what the task asks. FAB#keep-changes-and-tests-to-what-the-task-asks-for
- F8 Prefer surgical edits over whole-file rewrites. FAB#prefer-targeted-edits-over-whole-file-rewrites
- F9 Let the lead agent keep working while subagents run. FAB#let-the-lead-agent-keep-working-while-subagents-run
- F10 Tell the model what a compaction summary must preserve (constraints, decisions, exact details, where things stand). FAB#tell-the-model-what-to-preserve-in-compaction-summaries

Skipped as not applicable to these templates, with the reason: effort levels, thinking display, history binding, and Opus 5 "Running with thinking disabled" (API/harness configuration, not prompt text; Claude Code runs all three roles with thinking on); search triggering (no search tool in any role); safeguard false positives (no compile-check phrasing, no base64 tool output); quoting retrieved sources (no document summarisation); long-output max_tokens notes (no long single-turn deliverable); "Model self-knowledge" (no role identifies itself or picks model strings); "Document creation", "LaTeX output", vision, frontend design, computer use (none of the roles produce these); "Chain complex prompts" (the implementer → reviewer chain is already an explicit pipeline with inspectable intermediate output, which is what the rule recommends); "Research and information gathering" (no role does open-ended research; the reviewer's investigation is bounded by the diff); prefill migration (no prefilled assistant turns).

## emit_policy (CLAUDE.md, lines 24-88; Fable 5.1)

### Findings

P1. **Rule:** G14, O7 (the orchestrator's own delegation behaviour). **Text:** line 78 `Do not spawn agent teams for this pipeline. Subagents only.` **Change:** replace with `Delegate only through the implementer and reviewer subagents, one bead per dispatch. Do the small things yourself — \`bd\` commands, reading a report, a single grep, checking a label — rather than spawning an agent for them. No agent teams.` **Why:** the policy says what not to spawn but never says when not to delegate at all; G14 asks for both sides.

P2. **Rule:** G3, F3. **Text:** line 50, the single-paragraph step 5 (`Adjudicate per bead; ... delegating the review is the point.`). **Change:** keep the first sentence and split the rest into three sub-bullets: `PASS → commit inside that worktree (one commit, bead id in the message), merge the worktree branch into the epic branch, remove the worktree, \`bd close\`.` / `Gaps → one fix pass in the same worktree, then re-review; a second failure stops the batch.` / `Conflicting or ambiguous reports → read the diff yourself; otherwise do not.` **Why:** three distinct branches in one 70-word sentence; numbered/bulleted structure is what G3 asks for when completeness matters.

P3. **Rule:** G11, F3. **Text:** line 76 `At most 2 beads in flight, and only when the eligibility rules hold. Bounded WIP.` **Change:** delete the bullet; line 47 already states the cap and line 72 restates it for unattended mode. **Why:** the same rule appears three times (47, 72, 76); repetition is over-prompting, and the cap stays stated twice.

P4. **Rule:** G4. **Text:** line 37 `Do not create MEMORY.md files.` **Change:** `Record durable insight with \`bd remember "<insight>"\`; it is the only memory store the next session reads, so a MEMORY.md file would be lost.` **Why:** a negative rule without a reason; the why lets the model generalise to other ad-hoc note files.

P5. **Rule:** G4. **Text:** line 62 `Always a worktree, even for a solo bead.` **Change:** `Always a worktree, even for a solo bead: it keeps the main checkout clean and gives the reviewer an isolated diff to judge.` **Why:** missing motivation for a rule that looks like overhead when only one bead is running.

P6. **Rule:** G13. **Text:** lines 61-66 (`### Worktree flow`) contain no reversibility guidance beyond the merge-conflict stop. **Change:** add a bullet: `Reversible actions (editing, committing on a worktree branch, merging into the epic branch) need no confirmation. Ask before anything hard to undo: pushing, \`git reset --hard\` or force-push on a shared branch, deleting a branch or worktree with unmerged work.` **Why:** the orchestrator is the only agent that runs git write operations, and G13 asks for the reversible/irreversible line to be drawn explicitly.

P7. **Rule:** F1. **Text:** lines 45-52 (`## Delegation loop`) — no instruction about what the orchestrator says to the human while a batch runs; line 47 asks for a justification "in your report" without defining the report. **Change:** add to `## Discipline`: `Before dispatching a batch, write one line naming the beads, their model, and the pairing justification. When the batch lands, lead with the outcome (closed / fix-pass / stopped per bead), then the test result, then anything the human must decide.` **Why:** Fable 5.1 goes quiet in long tool chains; F1 says to state when you want a line and what it contains, and this also defines "your report".

P8. **Rule:** G10. **Text:** line 47 `**all**`, line 70 `**only**`. **Change:** remove the bold on these two words; keep the bold on line 52's stop rule and line 72's invariants. **Why:** emphasis on ordinary words is the over-prompting G10 warns about; the two load-bearing lines keep theirs.

P9. **Rule:** F9, G24. **Text:** line 48 `Dispatch each implementer ...` and line 49 `When an implementer returns, dispatch the \`reviewer\` ...` (implies one dispatch per turn and idle waiting). **Change:** append to line 48: `Issue both dispatches of a batch in one response.` Append to line 49: `While implementers run, prepare the next brief or the reviewer dispatch; dispatch each reviewer as soon as its own implementer returns rather than waiting for the whole batch. Do not start a third bead.` **Why:** F9 measured lower time-to-completion when the lead keeps working, and G24 says to state it when you want independent calls batched; the last sentence keeps the cap.

### Satisfied

- G1/G3: loop and eligibility rules are numbered and specific (46-59).
- G2: line 40 explains that briefs are executed by a model with no access to the orchestrator's reasoning — the golden rule stated in the prompt itself.
- G4: guest branch line 83 gives its why ("domestique state is personal"); line 88 explains the `bd export` mechanics.
- G6: the prompt is instructions only, no mixed inputs or documents; markdown headings suffice, XML would add nothing.
- G7: line 26 sets the role in one sentence.
- G8: line 77 pairs its negatives with the positive "Subagents return summaries".
- G9: bullet-structured prompt matches the bullet-structured report expected back.
- G12: every loop step is an imperative.
- G15: line 29 restricts self-written code to one-line edits.
- G18: state lives in beads and git; `bd export` at session end (88).
- G21: not applicable (short prompt).
- G22/G23: the default mode stops between batches (52), so no run outlives a context window; state already lives in beads and git (33-37, 88).
- G24: the policy says nothing about parallel calls; Claude Code itself appends a parallel-tool-calls instruction to every agent's system prompt, and the only orchestrator-specific case (issuing both dispatches of a batch in one response) is covered by P9's wording.
- F3: apart from P2 the prose is literal; "land the plane" is a named protocol, kept.
- F4: no anti-formatting rules present.
- F5/F6: the default is deliberately human-in-the-loop (52), so the autonomy block belongs in goal.md, not here.
- F7/F8: the orchestrator does not edit code; not applicable.
- F10: covered by GO7 for the only long-running mode.

## emit_implementer (implementer.md, lines 102-124; Sonnet 5)

### Findings

I1. **Rule:** S4, G1. **Text:** line 115 `If anything is ambiguous or not covered by the brief, stop and report the question in your summary — do not improvise.` **Change:** `Make routine judgment calls yourself (naming, placement, test shape) and note them in your summary. Stop and ask only when different readings of the brief would produce materially different work; before stopping, finish every part that does not depend on the answer.` **Why:** Sonnet 5 applies "anything" literally, so trivial gaps become a stalled bead with no delivery; the replacement defines the bar.

I2. **Rule:** G4, S4. **Text:** line 109 `Only edit paths listed in the \`Files:\` section of your brief.` **Change:** `Only edit paths listed in the \`Files:\` section of your brief — another implementer may be working in parallel on disjoint files, and the reviewer fails any diff that touches a path outside the list, whatever the tests say. Scratch files count: delete them before you report.` **Why:** the why turns a bare rule into one the model can reason from, and it covers the scratch-file case (also G19).

I3. **Rule:** G5, S1, G9. **Text:** lines 117-124 (`## What you return`) describe the shape but show none. **Change:** add after line 122 an `<example>` block with one realistic five-line summary, e.g. `Changed: src/auth.py (token expiry check), tests/test_auth.py (2 cases). / Tests: 41 passed; ruff clean. / Filed: proj-42 "refresh tokens not rotated" (discovered-from proj-17). / Blockers: none.`; delete line 124's `do not flood it`. **Why:** one positive example steers length and shape better than the negative instruction (S1, G5).

I4. **Rule:** S2. **Text:** line 111 `Run the project's tests and linter after meaningful changes.` **Change:** `Run the project's tests and linter once before you report, and again only after fixing a failure.` **Why:** Sonnet 5 already loops on self-verification; "after meaningful changes" invites a run per edit.

I5. **Rule:** G16. **Text:** line 111 (no guidance on wrong tests). **Change:** append to the line: `If a test is itself wrong, say so in your summary instead of changing it or special-casing the code to pass it.` **Why:** G16 asks for this explicitly; the implementer often has tests inside `Files:`.

I6. **Rule:** G2. **Text:** line 106 `claim it and mark it in progress before starting` conflicts with goal.md line 217, where the orchestrator has already claimed every bead. **Change:** `If the bead is not already \`in_progress\`, claim it: \`bd update <id> --claim\`.` **Why:** a colleague following both prompts would not know whether a second claim is expected to fail.

I7. **Rule:** G10. **Text:** line 106 `do NOT close it`. **Change:** `do not close it`. **Why:** capitalised emphasis is unnecessary on Sonnet 5 and the why ("the orchestrator closes beads after independent review") already carries the rule.

### Satisfied

- G1/G3: rules are bullets, each concrete; order does not matter so a numbered list is not needed.
- G7: line 102 sets the role.
- G8: each "do not" is paired with the positive action (file it, report it, surface it).
- G13: line 113 names credentials, secrets, access controls, destructive git as off-limits and says what to do instead.
- G15: line 105 gives explicit minimal-scope guidance.
- G17: the task is implementation, not Q&A; not applicable.
- G20: line 118 asks for a summary after the work.
- G22/G23: a bead is sized for one session in a single pass (decompose line 175), so no implementer run spans a context window.
- G24: the prompt is silent on parallel calls; the Claude Code harness injects its own batching instruction into the agent's system prompt, and the reads/greps at task start are the only independent calls, so nothing to add.
- S3: no forced interim-status scaffolding.
- S7: no voice or tone instruction exists to re-check; the output is code plus a fixed-shape summary (I3 adds the example that fixes its style).
- S5: the brief format (policy lines 39-43) front-loads task, files, and done-criteria.
- S6: the implementer reports blockers, not findings; nothing filters severity.

## emit_reviewer (reviewer.md, lines 136-156; Opus 5)

### Findings

R1. **Rule:** O1, S6. **Text:** line 152 `For anything other than PASS: the specific gaps — what the done-criteria required vs. what the diff does, each in one line.` **Change:** insert before it: `Report every issue you find in the diff, including ones you are uncertain about or consider minor, each tagged with severity and confidence. Do not filter for importance; the orchestrator decides what blocks the merge.` Keep line 152 as the format for done-criteria gaps. **Why:** Opus 5 converts fewer investigations into reported findings when the prompt implies a bar; the verdict-only framing implies one.

R2. **Rule:** G11, O5. **Text:** line 139 `Assume the summary may be wrong or incomplete; check it against reality.` **Change:** delete the sentence; the first half of line 139 already says to judge the diff, not the self-report. **Why:** a restatement in emphatic form; lines 140-141 are the reviewer's actual job (verifying another agent's work), which O5 does not cover, so they stay.

R3. **Rule:** G1, G2. **Text:** line 150 `PASS, FAIL, or NEEDS-WORK (partial).` **Change:** `PASS — every done-criterion met and \`Files:\` clean. FAIL — a done-criterion unmet, or a path outside \`Files:\`. NEEDS-WORK — criteria met, but a defect you found must be fixed before merge.` **Why:** three verdicts are named, only PASS is defined, and the policy (line 50) treats the other two identically; a colleague could not pick between them.

R4. **Rule:** G2. **Text:** line 140 `read the diff (\`git diff\`, \`git diff --stat\`)`. **Change:** `read the diff (\`git status --short\`, \`git diff\`, and the full content of any untracked file — new files do not appear in \`git diff\`)`. **Why:** the implementer never commits, so newly created files are untracked and invisible to `git diff`; the literal instruction misses them.

R5. **Rule:** G4. **Text:** line 143 `any path touched outside \`Files:\` is a FAIL regardless of test results.` **Change:** append `— a sibling bead may be editing other files in parallel, and the merge relies on the sets staying disjoint.` **Why:** the strictest rule in the prompt has no stated reason.

R6. **Rule:** G5, O10. **Text:** lines 148-156 describe the verdict format without an example. **Change:** add one `<example>` FAIL verdict after line 154: `Verdict: FAIL / Ran: pytest -q → 40 passed, 1 failed (test_expiry); ruff clean / Gaps: done-criterion 2 requires expired tokens rejected; diff only logs them (src/auth.py:88) / Findings: [low, certain] unused import in auth.py:3 / Files boundary: clean / Risks: none`. **Why:** the format has six parts; one example fixes shape and length better than prose.

R7. **Rule:** G8, G13. **Text:** line 146 `Never touch credentials, secrets, or destructive git operations.` **Change:** `Use git read-only: \`status\`, \`diff\`, \`log\`, \`show\`. Do not stage, commit, reset, or checkout, and do not open credentials or secrets.` **Why:** the positive form names the allowed set, which is what the reviewer needs to act on.

### Satisfied

- G1/G3: bulleted rules, each concrete; the output section is a fixed list.
- G6: no mixed inputs; markdown sections are enough.
- G7: line 136 sets the role and the no-fix boundary in one sentence.
- G12: every rule is an imperative directing tool use (read, run, compare).
- G17: lines 140-141 require opening files and running tests before judging.
- G22/G23: a review is one bounded pass over one diff; it never spans a context window.
- G24: silent on parallel calls; the harness-injected instruction covers the independent reads (`git status`, `git diff`, changed files), and test runs are dependent on nothing but should stay sequential with Bash anyway.
- O2: line 149 asks for terseness and line 156 is the end-of-prompt reminder the guide recommends.
- O3: the return leads with the verdict (150), detail after.
- O4: the deliverable is a short message, not a document.
- O6: line 145 constrains scope and gives the "one line, then continue" pattern.
- O7: the tool list (Read, Bash, Glob, Grep) excludes the Agent tool, so spawning is capped at zero.
- O8: not applicable to a single-turn verdict.
- O9: the dispatch carries the bead id and done-criteria up front (policy line 49).

## emit_decompose (decompose.md, lines 166-197; Fable 5.1)

### Findings

D1. **Rule:** G3, F3. **Text:** line 184, the 90-word `## Model routing` paragraph with inline `(1)...(4)`. **Change:** restructure as a heading line plus four bullets (`foundational — creates or reshapes what other beads build on`, `2+ downstream dependents`, `intricate logic — parsing, concurrency, state machines`, `cross-cutting refactor`), then the two closing sentences as their own lines. **Why:** the criteria are a checklist the model applies per task; G3 wants checklists enumerated.

D2. **Rule:** G2. **Text:** line 176 `--description "Files: <paths>. Shared-infra: no. <input, output, done-criteria>"` versus line 177 `begin with a \`Files:\` line ... followed by a \`Shared-infra: yes|no\` line`. **Change:** make the template match the rule: `--description $'Files: <paths>\nShared-infra: no\n<input, output, done-criteria>'`. **Why:** "line" and inline-with-periods disagree, and the implementer and reviewer prompts both parse a `Files:` section.

D3. **Rule:** G5. **Text:** lines 172-181 (`Rules for a good decomposition`) give a template but no worked instance. **Change:** add one `<example>` after line 177 showing a complete task `bd create` with a real-looking description: `Files: src/parser.py, tests/test_parser.py / Shared-infra: no / Input: grammar in docs/grammar.md. Output: parse_expr() handling unary minus. Done: tests/test_parser.py::test_unary passes; no other test changes.` **Why:** the description format drives three downstream prompts; one example pins it.

D4. **Rule:** G10. **Text:** line 177 `MUST`, line 184 `ANY`. **Change:** lowercase both. **Why:** capitalised emphasis is over-prompting on current models; the rules are already unambiguous.

D5. **Rule:** G4. **Text:** line 187 `never split a single file's edit across two beads to fake disjointness.` **Change:** append `— both implementers would need the whole file, and the second merge would conflict.` **Why:** the reason makes the rule generalise to other fake-disjoint splits (shared fixtures, generated files).

D6. **Rule:** F1. **Text:** lines 168-193 — the command runs an interview, many `bd` calls, and an audit with no instruction about what the human sees between phases. **Change:** add before line 172: `Say in one line when you move from the interview to creating beads, and again when you start the audit.` **Why:** Fable 5.1 goes quiet during long tool chains, and this command has three silent phases.

### Satisfied

- G1: each `bd` invocation is spelled out with flags (174, 176, 179, 194).
- G2 (apart from D2): the routing, pairing, and printout rules are explicit enough for a new colleague.
- G4: line 175 (fresh session, single pass), 180 (`bd ready` crisp), 184 (sanity check) carry their reasons.
- G6: `$ARGUMENTS` is the only variable and is inlined in one sentence; XML is not needed.
- G7: the role is inherited from CLAUDE.md line 26.
- G8: line 195 leads with the positive `Copy every title verbatim`; the negatives that follow are specifics of it.
- G12: skill checks and prints are imperatives with exact strings (170, 191).
- G14/O7: no delegation happens in this command (`Do not implement anything. Planning only.`, 181).
- G22/G23: a decomposition finishes in one session and ends with a printout for human review; state is in beads from the first `bd create`.
- G24: the `bd create` calls are mostly dependent (children need the epic id, `bd dep add` needs both task ids), so sequential is correct; the harness instruction already covers the independent ones and the template rightly adds nothing.
- F4: line 195 says exactly when and how to format (table, columns); no anti-formatting rule.
- F5/F6: stopping for the human's review (193) is the requested deliverable, not premature turn-ending.

## emit_goal (goal.md and drain.md, lines 207-246; Fable 5.1)

### Findings

GO1. **Rule:** F5. **Text:** line 207 `Drive epic $ARGUMENTS to completion, unattended, within the bounds below.` **Change:** insert after that sentence, with the guide's opening kept as written: `You are operating autonomously. The user is not watching in real time and cannot answer questions mid-task, so asking 'Want me to…?' or 'Shall I…?' will block the work. For reversible actions that follow from the original request, proceed without asking. Stop only for destructive actions or genuine scope changes the user must decide. The stop conditions listed below are the complete list of such cases. Before ending your turn, check your last paragraph. If it is a plan, an analysis, a question, a list of next steps, or a promise about work you have not done ('I'll…', 'let me know when…'), do that work now with tool calls.` **Why:** the guide says the opening sentence carries most of the effect and to keep it as written, adding a sentence after it that lists the confirmations the product still needs (here, the existing stop conditions).

GO2. **Rule:** G2. **Text:** lines 232-233, `The post-batch full test run on the epic branch fails: stop immediately...` and `Any full-suite regression: stop immediately...`. **Change:** merge into one bullet: `A full test run fails at any point — post-batch on the epic branch or during a review: stop immediately; do not attempt to attribute the cause yourself.` **Why:** two bullets for one condition leave the reader guessing at a difference; the union of the two is unchanged.

GO3. **Rule:** G11, O5-analogue. **Text:** line 241 `## Invariants — restate these to yourself at the end of the report`. **Change:** `## Invariants` as the heading, and add to line 239 (`Summarize: ...`): `end the report with one line: \`Invariants: held\` or the invariant that broke and where.` **Why:** the ritual self-restatement is re-check scaffolding; the human-readable check line keeps the audit value.

GO4. **Rule:** F3. **Text:** line 209 `(load-bearing)`, line 210 `this is doubly true`, line 216 `do not paper over it`. **Change:** delete `(load-bearing)`; replace `this is doubly true:` with `this also holds:`; replace `do not paper over it` with `do not stash, reset, or commit it`. **Why:** mannered phrases; the literal versions are also more actionable.

GO5. **Rule:** F1, G2. **Text:** line 215 `Write the one-line low-interference justification into the run log.` — "run log" is never defined. **Change:** `Write the one-line low-interference justification in your batch line: at each batch start write \`batch N: <ids> (<models>) — <justification>\`, and at each batch end \`batch N: <id> closed / fix-pass / stopped\`. These lines are the run log.` **Why:** defines the term and gives Fable 5.1 the explicit update cadence F1 recommends.

GO6. **Rule:** F10, G18. **Text:** lines 226-227 (`## Hard ceiling`, counted in the model's head) and line 222 (second failed review per bead). **Change:** add a section `## State survives compaction`: `Keep run state in beads, not in context: on each close, \`bd close <id> --reason "run <n>/15"\`; on each failed review, \`bd update <id> --notes "review-fail <n>"\`. If your context is compacted, re-derive the closed count and per-bead failure counts from \`bd\` before the next batch.` **Why:** a 15-bead run will be compacted; without durable counters the ceiling and the two-failure stop can be lost.

GO7. **Rule:** G10. **Text:** line 215 `**all five Parallel eligibility rules from CLAUDE.md**`, line 219 `must run the full test suite ... every time — never trust the implementer's summary`. **Change:** unbold line 215; rewrite line 219's second sentence as `The reviewer runs the full suite and reads the diff itself; its verdict, not the implementer's summary, decides.` **Why:** emphasis and "never trust" are over-prompting; the plain statement carries the same rule.

GO8. **Rule:** F9, G24. **Text:** lines 218-219 (dispatch all implementers, then dispatch all reviewers). **Change:** append to line 218: `Issue both implementer dispatches in one response.` Append to line 219: `Dispatch a reviewer as soon as its implementer returns; while one bead is under review, the other may still be implementing. Never start a third bead.` **Why:** F9 recommends letting the lead continue and G24 says to state it when independent calls should be batched; the last sentence keeps the cap.

GO9. **Rule:** G1, G22. **Text:** line 227 `(or sooner if you judge the budget exhausted)`. **Change:** delete the parenthetical, so the sentence reads `Stop and report after 15 beads closed in this run, even if the epic isn't finished.`; earlier exits are the stop conditions and nothing else. **Why:** "budget" is undefined, and G22 says not to stop early on self-assessed token budget — Claude Code compacts, GO6 keeps the counters durable across compaction, so the ceiling stays a bead count and every early stop is tied to a concrete stop-condition signal.

GO10. **Rule:** G4. **Text:** line 235 `Anything requires a push, a config change, or touching files outside the project.` **Change:** append `— these are visible to others or hard to reverse, so they are the human's call.` **Why:** the reason lets the model classify actions the list does not name (G13).

### Satisfied

- G1/G3: the per-batch loop is numbered and each step is concrete (214-224).
- G2 (apart from GO2, GO5, GO9): branch rules, adjudication, ceiling, and completion are followable.
- G4: line 207 explains the authorization's scope; 227 explains the ceiling's purpose; 231 the conflict rule.
- G6: `$ARGUMENTS` appears inline in complete sentences; no mixed document inputs.
- G7: role inherited from CLAUDE.md.
- G13: destructive operations (force-resolve, push, default branch) are all stop conditions or prohibitions.
- G14/O7: delegation is fixed at two named subagents per bead; no free-form spawning.
- G18: state is in beads and git commits; GO6 tightens it.
- G22/G23: a 15-bead run does span context windows; the template keeps state in git and beads (G23 met) but says nothing about compaction or early stopping — GO6 and GO9 close that gap.
- G24/F2: the template does not tell the orchestrator to batch its two dispatches (GO8 adds it); every other call in the loop (`bd ready`, claim, merge, test run) depends on the previous result, so sequential is correct there. The per-turn nudge F2 describes is a harness-side message, which Claude Code injects itself; the template cannot and need not carry it.
- F4: no anti-formatting language.
- F6: line 207 defines the scope (beads under the epic) as the deliverable.
- F7/F8: the orchestrator edits no code here.

## Invariants preserved

- At most 2 beads in flight: P3 deletes a duplicate statement only; line 47 and line 72 still state the cap, and P9/GO8 each end with "do not start a third bead".
- One commit per bead: untouched (policy line 50 via P2 sub-bullet, goal line 221).
- Never close a bead the reviewer did not pass: untouched; R3 defines the verdicts more sharply, and only PASS leads to `bd close`.
- All /goal stop conditions: GO2 merges two bullets whose union is unchanged; GO1 references the list rather than replacing it; GO10 adds a reason, not a change. No condition is removed or weakened.
- Epic-branch isolation: untouched (goal lines 209-210 keep their rules; GO4 changes wording only).
- `Files:` boundary: strengthened (I2, R4, R5), never relaxed; scratch files are explicitly inside it.
- Implementer never commits: untouched (line 110); I6 changes only the claim step.
- drain.md byte-identical to goal.md: both are emitted by `emit_goal`, so every GO change lands in both.

Rule conflicts resolved: (1) O5 "remove verification instructions" versus the reviewer's job — O5 targets self-verification of the model's own work; verifying another agent's work is the task, so only the redundant restatement (R2) goes. (2) F5's autonomy block "can make the model less likely to ask about ambiguous requests" versus the goal stop condition on operator input — resolved as F5 itself prescribes, by listing the confirmations (the stop conditions) immediately after the opening sentence (GO1). (3) G5 "3-5 examples" versus O2/O4 conciseness — one example per agent definition (I3, R6, D3), since the goal is format steering, not classification. (4) G22 "do not stop tasks early due to token budget concerns" versus goal line 227's "or sooner if you judge the budget exhausted" — G22 wins: the parenthetical is deleted (GO9), the ceiling remains a count of closed beads, early stops are only the enumerated stop conditions, and GO6 makes the counters survive compaction so the ceiling does not depend on the model's memory.
