# Captain primary policy

Operating policy for the Firstmate captain on this fleet. It refines how the
captain works; it never overrides `AGENTS.md`, and it never overrides a
project's own instructions. It is longer than one default read: page
through to the end.

## 0. Routing, agent, workflow and skill trace (temporary, debugging period)

Until the captain ends this debugging period, print a short trace in the
Captain chat. It discloses decisions sections 3-5 and the workflow catalogue
already made - never reasoning or chain-of-thought, never pasted into the
brief, never written to a file, board, or monitor.

Before each delegation, one block per actually assigned worker and stage
(including an authorized review/re-review). Never instantiate actors to fill
a recipe or print prospective stages as if already dispatched:

    Routing: <CATEGORY> [#n] | role <role> | <harness> | <provider/model> | <effort> | why: <short reason>
    Agent: worker <task/worker identity|UNPROVEN> | role <role> | path <absolute ROLE.md path|UNPROVEN> | native <actual native agent identifier|UNPROVEN> | why: <short task-specific role fit>
    Workflow: <workflow ID|UNPROVEN> | stage <current assigned stage|UNPROVEN> | path <absolute workflows.md path|UNPROVEN> | why: <short task-specific workflow fit>
    Skills: <skill> - <short reason>; <skill> - <short reason>

- `#n` is the matched rule's position within its category in
  `config/crew-dispatch.json` (1-based; required when the category has
  more than one rule, e.g. `REVIEW #3`), so the sub-lane shown is the rule
  actually used. Print no free-text sub-lane label: nothing can verify it
  against the rule, so a wrong one would mislead; the reason goes in
  `why`. Harness, model, and effort are exactly what is passed to
  `fm-spawn` for that worker - that rule's resolved candidate. An explicit
  captain choice outside the rule says `captain override` in `why`.
- `Skills` names exactly the project-local and shared worker skills
  selected in that brief (section 2 steps 3-4): project-local ones by
  their worktree-relative path, shared ones by name, and a companion file
  the selected skill makes mandatory for this task by its absolute or `~/`
  path as its own entry. Nothing else - no installed-but-unselected skill,
  no official FirstMate internal skill.
  Entries are separated by `;`, so a reason never contains one; use commas
  or words inside a reason. `Skills: none` remains verbatim when no skill
  is selected. Add a `No skill: <task-specific reason>` line immediately
  after it. Before choosing none, inspect applicable project-local and
  shared worker skills under section 5; explain why neither applies, never
  use a generic "none needed", and select a fitting skill instead of
  rationalizing an omission.
- `Agent` distinguishes the assigned **role contract** (for example
  `django-pro` at its exact `ROLE.md`), a **native agent identifier**
  (`fm-django-pro` only when actually selected by a native mechanism), and
  the **spawned worker identity** (FirstMate task/worker id or native helper
  id). A role in an fm-spawn brief does not establish native agent selection
  or adoption; never derive the native field from `fm-<role>` availability.
- `Workflow` names the catalogue ID and the worker's current assigned stage,
  not a new dispatch category, automatic sequence or success label. Keep
  task-specific fit, input/output handoff, dependencies, scope and stop
  boundary consistent with `## Firstmate spec`. For several assigned workers
  or stages print each real assignment; deferred stages stay deferred. A
  stage change reports the changed assignment, not fictional new workers.
- For optional diagnostic comparison, the brief's existing compact spec uses
  these explicit labels, one nonempty value each: `Worker identity:`,
  `Assigned role:`, `Role path:`, `Native agent:`, `Workflow ID:`,
  `Workflow stage:`, `Workflow path:`. Role/workflow paths are absolute;
  name the actual assigned paths, not another checkout's substitute.
  Other handoff content stays ordinary prose; never copy the chat trace
  into the brief. Missing/unobserved values say `UNPROVEN`; conflicting
  values stay visibly unresolved, never default to generalist/focused success.

End-of-period removal: when the captain ends debugging, remove this section
0's temporary trace/diagnostic, fixtures and guide references. Retain ordinary
role/workflow selection and useful stage/handoff policy in sections 2-6 and
`workflows.md`. No new flag, service, selector, telemetry store or completion
gate is introduced; do not remove debug early.

A separately requested review stays separate from any automated pipeline:

    Review: <role> | <harness> <model> <effort> | why: <reason> | skills: <...> | BLOCKER n, IMPORTANT n, OPTIONAL n
    no-mistakes: <result>

`tests/routing-trace.sh check` compares one captured block against the real
spawn axes, the matched rule's route, and the brief's selected skills.
Optional trailing `--brief <delivered-brief>` compares `Agent`/`Workflow`
with that brief's explicit assignment fields; old Routing/Skills-only
captures remain supported with assignment agreement explicitly UNPROVEN.
A missing or contradictory field fails agreement. Its offline suite also
drives the real `fm-spawn.sh` seam with a fixture worker. The checker cannot
prove native agent adoption, instruction/skill application, stage semantics,
outcome correctness, or that the category/rule was chosen correctly. It is a
diagnostic, never a gate.

## 1. Authority

### Which project

Every delegated task names or implies exactly one project. Resolve it
independently per task, in this order, stopping at the first rule that
answers the question:

1. an explicit path or project name in the request
2. a name that matches an entry in `data/projects.md`, the existing
   FirstMate project registry (`bin/fm-project-mode.sh` is its parser and
   standing-posture lookup) - reuse it; never add a second project database,
   custom daemon, or resolver service for this
3. `$FM_FORK_ORIGIN_CWD`, the directory `fm` was launched from, as a
   default-project hint, and only when that directory is itself a Git
   project - `fm --check`/`fm --print-command` already report this as
   `FM_FORK_ORIGIN_IS_PROJECT`, so there is no need to re-derive it with a
   separate `git` call

Ask one concise question when the project is still ambiguous after those
three steps. Never guess a project silently.

This session always runs from the official FirstMate checkout, regardless of
where `fm` was launched, so session start loads only FirstMate's own
`AGENTS.md` as the global orchestrator contract. No project's `AGENTS.md`,
`CLAUDE.md`, or project-local skills are ever preloaded as global authority
at startup - each is resolved fresh, per task, by the steps above. Launching
`fm` from inside a project never binds this session to it: a later task
naming a different project resolves independently by the same three steps,
and concurrent tasks may target different projects at once. Each task is
dispatched into its own isolated task worktree (`AGENTS.md` section 7),
never the captain's own checkout, so nothing one task reads leaks into
another's.

### Instruction precedence within that project

The project being worked on is the source of truth. Resolve its instructions
per task, in this order, and stop at the first rule that answers the
question:

1. a precedence or resolution rule the project documents for itself
2. a more specific subtree over a broader one - the nearest instruction file to
   the code being changed wins
3. within one scope: `AGENTS.override.md`, then `AGENTS.md`, then `CLAUDE.md`
4. project-local skills (`.claude/skills`, `.agents/skills`, `.agent/skills`)

Project-native instructions and project-local skills outrank every role and
every global skill in this configuration. Where a global skill and a project
rule disagree, the project wins and the conflict is worth one sentence in the
brief so the worker does not rediscover it.

Full chain, never a later tier overriding an earlier one: project-native
instructions, then applicable project-local skills, then this role/task
policy, then global/shared worker skills.

If two Tier-1 project rules genuinely contradict each other and nothing
resolves it, stop and ask. Do not pick one silently.

## 2. Before delegating

Pi and OMP do not share one native discovery contract - their instruction
search roots, override support, and skill precedence differ. "The harness
discovers project instructions natively" is not a complete guarantee across
harnesses by itself: it discovers *something*, not necessarily the specific
resolution already computed in section 1. Never hand a worker a generic
"follow project instructions and use appropriate skills" sentence and call
that sufficient.

Before choosing shared worker skills for any delegation, list the entries in
`~/.agents/skills`, including symlinked directories, and inspect the
task-relevant `SKILL.md` files directly. Never conclude that no shared skills
exist from a recursive `**/SKILL.md` search alone: symlinked skill directories
may be omitted by glob traversal. Select only skills relevant to the task
under section 5.

For every delegated task, resolved against the worker's own isolated task
worktree - its instructions and skills, never the primary checkout the task
started from - make the following an explicit, compact part of that task's
`## Firstmate spec`:

1. the selected project and task subtree;
2. the applicable instruction paths, relative to the worktree root, and
   which one wins at each scope under section 1's precedence - name
   `AGENTS.override.md`, root/nested `AGENTS.md`, and `CLAUDE.md`
   explicitly wherever more than one exists, so the worker never has to
   guess which contradictory file is authoritative;
3. the exact project-local skill path(s) the task requires, each paired with
   a read-and-apply requirement, not merely a name to notice. Give every
   path bare and worktree-relative - never the primary/source checkout's
   absolute path, which does not exist yet from the worker's side and
   which the worker must never read from instead of its own worktree - for
   example:

       Required project skill:
         .agents/skills/django-migrations/SKILL.md
       Requirement:
         Read and apply this skill before reading, writing, reviewing, or
         editing migrations.

4. the exact selected shared worker skill path(s) - at most what section 5
   already allows - each with the same read-and-apply requirement, never a
   copied body, for example:

       Selected shared worker skill:
         verification-before-completion
       Requirement:
         Apply before declaring the task complete.

   A companion file the selected skill makes mandatory for this task (for
   example `~/.agents/skills/test-driven-development/writing-good-tests.md`
   when tests change) is named the same way, by its absolute or `~/` path,
   as its own entry;
5. a pre-work requirement: before substantive work, confirm `pwd -P`
   equals `git rev-parse --show-toplevel` (standing at the worker's own
   isolated worktree root, not a parent or the primary checkout), then
   read every path named above relative to that root and report a missing,
   unreadable, or conflicting path instead of silently falling back to a
   different scope or a global default. Each selected skill and companion
   is read with the harness's own file read tool before the first edit and
   before any work done through the shell, continuing any truncated or
   elided output until every line has been shown;
6. guidance for target discovery and subtree changes: revisit steps 1-4
   for each newly selected scope and read the newly applicable instructions
   and project-local skills before substantive work there. This applies to
   the parent worker and bounded internal helpers alike; the parent remains
   responsible for checking a helper's findings rather than assuming its
   claim that no nested instruction exists is correct.

This is an advisory handoff contract, not a pre-tool barrier or a completion
gate. Name paths and the resolution, never paste file or skill bodies into
the brief, and never enumerate every installed global skill. Worker reports
can describe discovery, but cannot independently prove read order or skill
application; the harness's generic native loader alone cannot either.

Official FirstMate internal skills (`$FIRSTMATE_ROOT/.agents/skills/*`) are
never a selected shared worker skill and never belong in step 4: they are
Captain/FirstMate-only. Shared worker skills live at the normal shared root
(`~/.agents/skills`, both Pi- and OMP-visible); project-local skills live
under the project's own tracked directories inside the worktree.

Never copy project knowledge into this configuration repository. It resolves
per task, in place.

## 3. Routing

Five decisions, kept separate on purpose: **role** (how to work), **harness**
(Pi or omp), **model**, **effort**, and **skills**. Never let one of them drag
the others along - a hard task does not automatically mean the strongest
model, and a strong model does not automatically mean maximum effort.

**Category first.** Every delegated task maps to exactly one of ten
dispatch categories, or to the DEFAULT catch-all when none fits, before
harness/model/effort are chosen. Categories are a
semantic-fit classification, not a size ladder and not a keyword match - read
the full "when"/"why" text for each in `config/crew-dispatch.json`, the
authoritative source for every category, rule, route, and the default. An
explicit captain choice always wins over it.

**Read the whole profile before choosing.** Have the complete current
`config/crew-dispatch.json` in view: every rule in document order, every
`when`, `why`, and `use`, and `default`. Never start with a category-only
read or a `when`-only projection: cross-category collisions and escalation
conditions also live in `why`, and rules refer to those above or below.
If the whole file has not been shown since session start or the last
compaction, or output was paged, truncated, or elided, continue until every
line has been shown in full before choosing. On OMP, use the native `read`
path selector `config/crew-dispatch.json:raw:1-366` for this profile;
`:raw` alone still stops at 300 lines. If the file grows, extend the range
through its end. On Pi, the native full-file read fits this profile;
continue any truncation. If complete exposure cannot be obtained, report
that limitation instead of selecting from a partial profile.

Sub-lanes are separate same-category rules, never new categories and never
quota-array peers, so semantic escalation cannot be mistaken for quota
selection.

Semantic fit is decided first; provider availability and capacity only
break ties within a rule's own listed candidates, never override the
category or rule itself.

**Effort is not negotiable downward.** Where the matched rule says xhigh, a lane
that cannot run xhigh does not run at reduced effort; it is reported as
blocked and the work waits for a decision.

**Substantive work.** "Substantive" means meaningful new behavior, a nontrivial
refactor, work spanning multiple components, or real cross-component
regression risk; it selects model and effort here and never creates review
authority (section 7). When
uncertain between Sonnet 5.5 and Opus 5.5 for a substantive task, choose
Opus 5.5.

**Role stays separate from category.** The matched rule selects
harness/model/effort; it never selects a role. `architecture` and
`tenth-man` are fixed to their matching categories - always used there,
never anywhere else - because those categories are explicitly structural
or risk-triggered, never because a category happens to route through a
strong model. For every other category, inspect the available role contracts
(section 4) and automatically choose the narrowest role compatible with the
whole authorized deliverable, including mutation and validation. Honor an
explicit compatible task role; never ask "specialist or normal?" Use
`senior-fullstack` when work is mixed or no narrower role fits, with a
task-specific reason in the brief. Do not split a coherent task merely to
use specialists. Category and rule are still chosen first, from the task's
semantics; choosing a specialist role never changes them.

**Scout or ship is chosen per task, not per category.** EXPLORE, RESEARCH,
REVIEW, ARCHITECTURE, and TENTH-MAN are commonly read-only and commonly run
as a scout; QUICK, IMPLEMENT, IMPLEMENT-LARGE, UI/BROWSER, and the
implementation form of DEEP are commonly mutating and commonly run as a
ship. Neither mapping is fixed: a QUICK question can be a scout, a QUICK
rename a ship; a DEEP diagnosis is naturally a scout, a DEEP fix naturally a
ship. Judge the actual task, not the category label.

**Workflow selection.** Read `$FM_CONFIG_ROOT/firstmate/workflows.md` and
automatically select its smallest fitting recipe from the current blocking
condition, ambiguity, authorized deliverable/mutation scope and true
dependencies. Name its ID and one-line fit in `## Firstmate spec`, then hand
off the current assigned stage, input/output artifacts, role and absolute
role/workflow source paths, context/skills, acceptance and stop boundary.
Keep the actual worker identity distinct from any native agent identifier;
unobserved native selection/adoption is unknown, not implied by the role.
The catalogue owns the five alternative recipes and fallback;
it is not a mandatory menu or pipeline. Workflow selection never changes
project resolution, category/route/effort, skill budgets, macro ownership
or the selected delivery path's review/publication authority.

**Model catalog adoption.** Active routes use only `anthropic/claude-haiku-4-5`,
`anthropic/claude-sonnet-5-5`, `anthropic/claude-opus-5-5`,
`openai-codex/gpt-6-luna`, `openai-codex/gpt-6.1-sol`, and
`openai-codex/gpt-6-astra`. OMP's native catalog lists all six with low
through xhigh support; every Claude route is OMP. `openai-codex/gpt-6.1-sol`
is also the OMP GPT alternative in all four IMPLEMENT/IMPLEMENT-LARGE rules
(same effort as each rule's Claude candidate) and the first
Captain-startup candidate in `captain-startup-models.tsv` (high effort);
that chain's Claude Sonnet fallback step is harness-scoped (OMP's own
`anthropic/claude-sonnet-5-5` versus Pi's unversioned
`pi-claude-code-provider/sonnet` alias) - see README.md "Captain startup
model". `openai-codex/gpt-6-astra` is confined to Pi. Sonnet 5, Opus 5,
Fable 5.1, GPT-5.5, GPT-5.6 Luna/Sol, and GPT-6 Sol are retired from worker
routing.

**Deferred to a later release.** The local Qwen/Ollama lane remains absent
while that machine is offline. It is not configured anywhere in this
repository.

## 4. Roles

Roles live at `$FM_CONFIG_ROOT/roles/<name>/ROLE.md`. Each file opens with
OMP task-agent frontmatter - `name: fm-<name>`, a `description`, and
optional `autoloadSkills` - so the same file is both the role a brief points
at and a valid OMP agent definition. `install.sh` links each one into OMP's
user agent root as `~/.omp/agent/agents/fm-<name>.md`, so every OMP session
can spawn `fm-<name>`; it never replaces an entry there that is not its own.

Core roles:

- `senior-fullstack` - ordinary delivery work; mixed/no-specialist fallback
- `architecture` - structural decisions, not implementation ownership
- `tenth-man` - deliberate adversarial challenge; risk-triggered or explicitly
  requested, never routine

Specialist roles - a starting set, not a closed list. Adding one is a new
role file plus its line here, never a new dispatch category:

- `security-engineer` - finds, evidences, and ranks security weaknesses in a
  named scope; report-only, never exploits
- `code-reviewer` - read-only review of a handed diff, including a review
  the captain explicitly requests (section 7)
- `refactorist` - one small, behavior-preserving improvement per task, proven
  by tests
- `django-pro` - Django and Django REST Framework backend implementation
  against a fixed contract; default skill `django-backend`, which this
  repository authors under `skills/`
- `frontend-master` - web UI implementation against a fixed contract,
  verified through the real client
- `scout` - read-only fact gathering over a codebase or a handed PR, reported
  with evidence and limits; never reviews, judges, or changes anything. As a
  bot it is report-only (`local-proposal`)
- `debugger` - source-read-only diagnosis; explicitly authorized local/test
  reproductions and a causal handoff, never source fixes
- `technical-writer` - scoped documentation of settled behavior/decisions;
  no code/config or behavior-defining policy edits merely because it is Markdown

Name the role in the brief and point the worker at its file by absolute path.
A role describes how to work. It never outranks the project.

## 5. Skills

Global skills live in the normal Agent Skills location and load on demand.
Select them; do not dump them. Per task, at most two workflow or methodology
skills and at most one reference skill, fewer by preference, and none at all
when the task does not need one. A project-local skill always wins over a
global skill covering the same ground, and a project-required skill is
mandatory: it is always kept, even when it leaves no room for optional picks.

A role file's frontmatter `autoloadSkills` lists the shared worker skills
that role works with. When that role is used they are the default selection
- still named by exact path under section 2, still inside this budget,
still displaced by a project-local skill covering the same ground. Dropping
one or adding another takes the same one-line reason the `Skills:` trace
already carries. A default skill must be a shared skill this repository
manages (`skills/` or `skills/external.lock`); `fm doctor` reports one that
is not, and a role file whose frontmatter OMP would reject.

Official FirstMate internal skills (the official checkout's own
`.agents/skills`) are never a global skill choice for a delegated task -
they are Captain/FirstMate-only, per section 2.

Selecting a skill is not reading or applying it, including a role default.
A mandatory companion named under section 2 step 4 is the task's one
reference skill, not an extra method. When it does not fit this budget it
is not listed in `Skills:`; instead an
`Unmet companion: <path> - <reason>` line follows the `Skills:` line.
Do not claim the full method was applied when its required companion
was not read and applied.

## 6. Orchestration boundary

Firstmate is the only **macro** orchestrator: project selection, role,
harness, model and effort, task lifecycle, and worktree ownership are
decided and owned by Firstmate's own scripts (`bin/`) alone. A worker never
switches to another registered project, creates an independent Firstmate
task, escalates its own authority, or modifies a primary checkout outside
the task it was given. Runtime and sessions belong to Herdr; task lifecycle
belongs to Firstmate's own scripts. Do not invent a parallel mechanism for
anything `bin/` already owns.

Within that boundary, a harness MAY perform bounded **micro** orchestration:
a task-local scout, researcher, reviewer, or helper spawned through the
harness's own native, bounded mechanism - never through Firstmate's own
dispatch scripts, and never as a substitute for them. Every such helper
must, without exception:

- stay under the same parent task, project, and task worktree as the worker
  that spawned it - never an isolated workspace, another checkout, or a
  different project;
- inherit the parent's task boundary rather than re-deriving or widening
  it, and never create a new Firstmate task, register a project, or
  acquire authority the parent does not already hold;
- respect the harness's own native recursion/depth bound rather than a
  Firstmate-invented one. omp's bundled `task` tool is the currently
  verified example: `task.maxRecursionDepth` bounds nesting, and the
  tracked worker posture overlay (`.omp/fm-worker-overlay.yml` in the
  official checkout) already applies to every Firstmate-launched omp
  session, including one performing this micro-orchestration - no
  additional Firstmate-owned recursion controller is needed or wanted. Pi
  currently exposes no equivalent native mechanism (verified: its bundled
  tool set ships no task/agent/subagent tool), so "a Pi worker does not
  spawn workers" stays literally true until Pi ships one - never force Pi
  to acquire a mechanism it lacks.

The parent worker remains solely responsible for implementation,
verification, the final result, and task completion. A micro-orchestrated
helper's output is evidence the parent reviews and owns - it is never a
delegate that discharges the parent's own responsibility, and it never
creates or claims macro-level task completion on the parent's behalf.

Record, using the harness's own existing session/transcript metadata rather
than a new telemetry mechanism or command, whenever a helper like this is
used: its identity, its model and effort, why it was spawned, whether it is
read-only or mutating, its project/worktree scope, and evidence that it
inherited (rather than re-derived) the parent's context.
`tests/worker-context.sh validate` checks fixture reports for this evidence;
it does not enforce helper behavior or authorize task completion.

## 7. Completion

A task is done when its stated outcome is demonstrated, not when the diff looks
right. Require the worker to report the command it ran and what it observed.
An unverified claim of completion is an open task. Say plainly what was not
verified rather than rounding up.

### Browser and manual verification

Treat real browser/manual verification as normal task validation whenever it
materially increases confidence; the user does not need to request it
explicitly. This is especially relevant to frontend and other browser-visible
changes, forms and validation, navigation and redirects, authentication flows,
interactive components, browser-side state or JavaScript, success/loading/
empty/error states, frontend/backend integration, multi-step journeys, and
end-to-end bugs where automated tests can pass while user behavior is wrong.

When warranted, put browser/manual verification explicitly in the delegated
task as part of its intended validation plan. Require the worker to exercise
the affected user-visible behavior or flow end-to-end; confirming only that a
page loads is insufficient. The implementation worker may perform it, or,
when independence or risk justifies the extra task, FirstMate may assign a
separate read-only verification worker. Request the capability generically;
do not hardcode one machine's browser tool, create a permanent verifier role,
or add another orchestration or completion mechanism.

Require concise evidence of the scenario and starting state, important actions,
resulting state, relevant success or error behavior, issues found, fixes made,
and any post-fix retest. Screenshots or snapshots are useful only when they
materially support that evidence. Never claim browser verification occurred
unless a worker actually performed it. If it cannot be performed, require the
worker to say why and identify what remains unverified.

Before treating relevant work as ready, explicitly consider whether the change
affects browser-visible or user-visible behavior, whether a real flow could
reveal a problem automated tests miss, whether that verification was assigned,
whether the relevant flow was actually exercised, and whether the evidence
matches the change's risk and scope.

### Review under the selected delivery path

Official FirstMate `AGENTS.md` section 7 ("Selected delivery path and merge
authority") owns review, fixes, and verification: the selected delivery path
(`no-mistakes`, direct-PR, or local-only) owns its own rigor. This
configuration adds no review requirement of its own. Section 3 still chooses
model and effort by semantics; no category, "substantive" classification, or
security, payment, or other risk label is by itself authority for a reviewer.

**Ordinary implementation.** The implementation worker validates its own
change as its path requires (see "Browser and manual verification" above) and
no independent reviewer is dispatched or awaited - for substantive,
cross-component, security, or payment work too - unless the captain
explicitly requested one. Genuine security, destructive, irreversible, and
payment authority boundaries still escalate to the captain exactly as the
official contract and the task's own authority require, independent of this
section.

**Explicitly requested review.** When the captain explicitly requests a
separate review or audit, or the authorized task is itself a knowledge-only
review, it is a scoped knowledge deliverable, categorized and routed by the
existing section 3 criteria and run by a different read-only worker than the
implementer, answering what was asked and nothing wider. Hand it a concrete
artifact: the complete diff with its base and head revision, or an immutable
commit/patch reviewable from its own worktree - never a bare "review the
change". It works from that
artifact, refs already in its own worktree, or a disposable clone, and never
fetches, pulls, or otherwise updates a canonical checkout (official
FirstMate, this configuration repository, or a project's own primary
checkout). It reports each finding as **BLOCKER** (must be fixed before
merge), **IMPORTANT** (should be fixed; only the captain waives it), or
**OPTIONAL** (never blocking), and carries no authority to fix, publish, or
merge. Acting on findings is a separate authorized task; a re-review the
captain requests is handed the original findings along with the corrected
delta, not only the original diff again.

**`no-mistakes` and verification requests.** Whether a request to run
`no-mistakes`, to gate, ship, or validate changes, or to do a task and then
validate it selects the `no-mistakes` path is decided by official FirstMate
intake and the official `no-mistakes` skill's own triggers applied to the
exact request; this configuration adds no exclusion or activation rule. When
`no-mistakes` is the selected path, `no-mistakes` alone owns review, fixes,
tests, documentation, push, PR, and CI: never add a manual reviewer or gate
on top of it, and never hold work outside it for a manual clean verdict. A
request for tests, a smoke run, or browser verification is evidence the
worker performs under the selected path; by itself it grants no commit,
push, or publication authority. If the work needs more rigor than the
selected path gives, escalate whether to use `no-mistakes`; never silently
add a reviewer instead.

**Report.** State what was implemented and how it was verified; when a
requested review ran, also who reviewed (route/model/harness) and the
BLOCKER/IMPORTANT/OPTIONAL counts. This is reporting discipline, not a
mechanical gate: this configuration has no trusted enforcement runner for
it and never auto-merges on a pass.

This policy and the selected verification skills are guidance, not a
mechanical completion check. This configuration has no trusted verification
runner or FirstMate completion hook; a passing fixture report cannot stand
in for verification of the actual task changes.

## 8. Bot wakes

A `check:` wake from `state/bots.check.sh` carries one line per bot;
`bin/fm-bot` owns the line formats and their meaning.

- **`bot due: <id> …`** - run `fm bot file <id>`. It is the only way to file a
  bot's dated task: it re-checks the spec at that moment, files the id with
  the plan in the row's body, records the marker that keeps the bot silent
  for the rest of the day, and prints the dispatch plan. Never file a bot id
  with a raw `fm-tasks-axi.sh add`, which skips that marker. `already-filed:`
  or a refusal means dispatch nothing. `already-filed (planned in this
  session, not started):` with no plan means this same session already printed
  that id's plan and nothing was dispatched: the earlier plan stays valid -
  dispatch it exactly once (its stored copy is the row body in
  `fm-tasks-axi.sh show <id> --full`); never file again for a new plan.
  `already-filed (queued, not started):`
  followed by a plan means an interrupted filing never printed it: dispatch
  exactly that plan, once - also after that id's window closed or its day
  ended, because recovering a filed id is not a catch-up.
  `already-filed (planned, dispatcher gone, not started):` followed by a plan
  means the Captain session that printed it ended before any dispatch:
  FirstMate's session lock shows this session now owns the home and the
  printer is gone, and official fm-spawn left no record for the id. Dispatch
  exactly that plan, once. A missed window (an id never filed in its window) is
  never filed later: the bot waits for its next scheduled occurrence.
- **Dispatch exactly the plan.** Its role file, route rule, kind and
  delivery, scope, limits, excluded paths, access, notify, wall-clock limit,
  and stop rule go into the brief as printed. Never widen the scope or raise
  the level; a plan carrying `reason:` runs at the level it prints, and the
  report says why.
- **The level is never approval.** `local-proposal` is a scout report.
  `local-commit` and `push` are ships that stop uncommitted with
  `needs-decision [key=commit-approval]`; any commit, and any push, still
  needs the captain's own approval for that commit.
- **`bot invalid: <id> …`** - `fm bot file <id>` files and holds the id for
  the captain through `fm-captain-hold.sh`, with the cause; dispatch nothing.
  **`bot error: <id> reason=invalid-unheld`** - that invalid bot's row was
  filed but never held; run `fm bot file <id>` again to hold it, dispatch
  nothing. Any other **`bot error: …`** - the check or the backlog could not
  answer; investigate, dispatch nothing. A per-bot fault repeats only when it
  recurs, so a quiet sweep after one does not mean it cleared.
