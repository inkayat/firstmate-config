# Captain primary policy

Operating policy for the Firstmate captain on this fleet. It refines how the
captain works; it never overrides `AGENTS.md`, and it never overrides a
project's own instructions. It is longer than one default read: page
through to the end.

**Standing rule (full text in section 8).** Every non-trivial code-changing
task MUST run a workflow: before the first worker is launched, resolve it with
`bin/fm-workflow select <kind> --delivery <mode>` and start it with
`bin/fm-workflow next`. Only the closed list of exceptions in section 8 runs
none. It is repeated here because a default read of this file can stop before
section 8.

## 0. Routing and agent trace (temporary, debugging period)

Until the captain ends this debugging period, print a short trace in the
Captain chat. It discloses decisions sections 3-5 already made -
never reasoning or chain-of-thought, never pasted into the
brief, never written to a file, board, or monitor.

Before each delegation, one block per actually assigned worker and stage
(including an authorized review/re-review). Never instantiate actors to fill
a display or print prospective stages as if already dispatched:

    Routing: <CATEGORY> [#n] | role <role> | <harness> | <provider/model> | <effort> | why: <short reason>
    Agent: <assigned role name>
    Skills: <name>, <name>

- `#n` is the matched rule's position within its category in
  `config/crew-dispatch.json` (1-based; required when the category has
  more than one rule, e.g. `REVIEW #3`), so the sub-lane shown is the rule
  actually used. Print no free-text sub-lane label: nothing can verify it
  against the rule, so a wrong one would mislead; the reason goes in
  `why`. Harness, model, and effort are exactly what is passed to
  `fm-spawn` for that worker - that rule's resolved candidate. An explicit
  captain choice outside the rule says `captain override` in `why`.
- `Skills` is derived, never chosen: exactly the assigned role's frontmatter
  `autoloadSkills` (`bin/fm-role-handoff --skills <role>`), by skill directory
  name, comma-separated, in the role file's order. `Skills: none` stands
  alone for a role that autoloads nothing (`scout`, `chore`, `tenth-man`,
  `risk-classifier`), with no
  `No skill:` line. Nothing else: no project-local skill (the Captain does
  not select those, section 2), no installed-but-unlisted skill, no official
  FirstMate internal skill.
- `Agent` names only the assigned role, for example `senior-fullstack`.
  It is not a native agent identifier or proof of native adoption.
  For several assigned workers or stages print each real assignment;
  deferred stages stay deferred. A stage change reports the changed
  assignment, not fictional new workers.
- Keep Agent/Skills lines names-only: no file paths, worker
  identity, native/adoption columns, stage or why/reason suffixes.
  Full absolute instruction/role/skill paths, actual worker
  identity distinct from native selection, current stage, authority,
  task-specific fit/reasons, input/output handoff, dependencies, scope
  and stop boundary stay inside the task instructions/handoff.
- A task running a workflow (section 8) adds one line to its block, derived by
  `bin/fm-workflow trace <state-file>` from the task's state file and never
  typed from memory:

      Workflow: <workflow> v<version> | step <step> #<run> | loops <loop> <used>/<max>, ... | <running|complete|closed|escalated>

  `bin/fm-workflow trace <state-file> <captured-block>` fails when a captured
  Workflow line differs from the derived one; `tests/routing-trace.sh check`
  ignores the line.

End-of-period removal: when the captain ends debugging, remove this section
0's temporary trace/diagnostic, fixtures and guide references. Retain ordinary
role selection and useful stage/handoff policy in sections 2-6.
No new flag, service, selector, telemetry store or completion
gate is introduced; do not remove debug early.

A separately requested review stays separate from any automated pipeline:

    Review: <role> | <harness> <model> <effort> | why: <reason> | skills: <role's autoloadSkills> | BLOCKER n, IMPORTANT n, OPTIONAL n
    no-mistakes: <result>

`tests/routing-trace.sh check` compares one captured block against the real
spawn axes and the matched rule's route; it derives the expected skills from
the Routing role's `autoloadSkills`, never from a caller-supplied list.
Agent must agree with Routing's role.
Optional trailing `--brief <delivered-brief>` compares the `Agent` name with
`Assigned role:` and the brief's `Role skill:` paths with that same derived
set. Missing or contradictory names fail agreement. Without a brief,
assignment names and brief paths are not compared.
The offline suite also has a real `fm-spawn.sh` seam with a fixture worker.
The checker cannot compare hidden paths, worker/native identity or stage,
prove native adoption, instruction/skill application, outcome correctness,
or that the category/rule was chosen correctly. It is a diagnostic, never
a gate.

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

This session always runs from the FirstMate distribution checkout, regardless of
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

**Role handoff.** The Captain's only capability choice per task is the role
(section 4). Name its absolute `ROLE.md` path in the brief with a
read-and-apply requirement, and hand over the skills that role carries: every
entry of its frontmatter `autoloadSkills` (section 5), by exact shared skill
path, each with the same requirement. `bin/fm-role-handoff <role>` in this
repository prints exactly that block from the role's frontmatter; paste it into
`## Firstmate spec` unchanged. The Captain never adds, drops, swaps or names a
skill of its own for a task: a different skill set is a different role, and a
skill-less role (`scout`, `chore`, `tenth-man`, `risk-classifier`) hands over
none. Official FirstMate's
`bin/fm-brief.sh` has no `--worker-role`, `--skill` or `--skill-root` option
and does not reject unknown arguments, so never pass them: nothing would be
selected or recorded. The worker's first input carries these paths and
requirements, never role or skill bodies. Nothing is inlined before the first
model call, nothing resolves `autoloadSkills` automatically, a missing or
malformed path does not refuse the launch (the worker reports it under step
4), and no selection or provenance record is written. This is a handoff, not
native agent selection or proof of application.

**Continuation versus role change.** Same-role continuation within the
original authorized scope may keep its existing worker. Selecting a different
role requires a fresh task/worker whose brief carries that role's handoff,
even when the harness/model/effort stay the same. An ordinary `fm-send` steer
or an appended "read this role/skill" brief is not a role change, and
`fm-control relaunch` carries the task's existing brief into a fresh agent; it
is not a role change either. Preserve the old identity and its brief, launch
and result evidence; never rewrite them retroactively. Carry needed source
into a new task-owned artifact/copy under explicit authority, preserving
uncommitted work and prior evidence. An exact-source request does not justify
skipping the role handoff: if no authorized safe copy or supported transition
fits it, report the constraint instead.

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
3. the role handoff block printed by `bin/fm-role-handoff <role>`: the
   absolute `ROLE.md` path and each autoloaded skill path, every one with a
   read-and-apply requirement, for example:

       Assigned role: refactorist
       Role source:
         /path/to/firstmate-config/roles/refactorist/ROLE.md
       Requirement:
         Read and apply this role file in full before substantive work.
       Role skill:
         /home/me/.agents/skills/code-simplification/SKILL.md
       Requirement:
         Read and apply this skill in full before the first edit and before
         any shell work; follow its procedure step by step and name the steps
         you applied in your final report.

   Project-local skills are not part of this block and the Captain does not
   select them. A worker applies an applicable project-local skill where the
   project's own instructions require it, under section 1's precedence, which
   this section does not change; where a project-local skill covers the same
   ground as a role skill, the project-local one wins and the conflict is
   worth one sentence in the brief. A companion file a role skill itself makes
   mandatory is read by the worker when that skill requires it, never named or
   chosen by the Captain;
4. a pre-work requirement: before substantive work, confirm `pwd -P`
   equals `git rev-parse --show-toplevel` (standing at the worker's own
   isolated worktree root, not a parent or the primary checkout), then
   read every path named above - instruction paths relative to that root,
   the role and skill paths as given - and report a missing, unreadable, or
   conflicting path instead of silently falling back to a different scope
   or a global default. Each role skill is read with the harness's own file
   read tool before the first edit and before any work done through the
   shell, continuing any truncated or elided output until every line has
   been shown;
5. guidance for target discovery and subtree changes: revisit steps 1-3
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
never part of a role's `autoloadSkills` and never belong in the handoff: they
are Captain/FirstMate-only. Role skills live at the shared worker root
(`~/.agents/skills`, both Pi- and OMP-visible); project-local skills live
under the project's own tracked directories inside the worktree.

Never copy project knowledge into this configuration repository. It resolves
per task, in place.

## 3. Routing

Four decisions, kept separate on purpose: **role** (how to work, and with
which skills - the role's `autoloadSkills`), **harness** (Pi or omp),
**model**, and **effort**. Skills are not a fifth, Captain-made decision: they
come with the role. Never let one decision drag the others along - a hard
task does not automatically mean the strongest model, and a strong model does
not automatically mean maximum effort.

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

**Build, test and review are a workflow, not one worker.** A task that changes
code follows a workflow (section 8, mandatory for non-trivial code-changing
work) instead of being routed once: implementation, independent QA, fresh-context
review with verified findings and, when the change touches a sensitive surface,
a blocking security review, with or without a plan first. Each of its steps is
then routed here like any task.

**Task handoff.** Name the assigned role and absolute role source path
(through the section 2 role handoff), input/output artifacts, acceptance,
true dependencies, scope/mutation/validation limits and delivery/stop
boundary in `## Firstmate spec`. Keep the actual worker identity distinct from
any native agent identifier; unobserved native selection/adoption is unknown,
not implied by the role.

**Model catalog adoption.** Active routes use only `anthropic/claude-haiku-4-5`,
`anthropic/claude-sonnet-5-5`, `anthropic/claude-opus-5-5`,
`openai-codex/gpt-6-luna`, `openai-codex/gpt-6.2-sol`, and
`openai-codex/gpt-6.2-astra`. OMP's native catalog lists all six with low
through xhigh support; every Claude route is OMP. `openai-codex/gpt-6.2-sol`
is also the OMP GPT alternative in all four IMPLEMENT/IMPLEMENT-LARGE rules
(same effort as each rule's Claude candidate) and the first
Captain-startup candidate in `captain-startup-models.tsv` (medium effort);
that chain's Claude Sonnet fallback step is harness-scoped (OMP's own
`anthropic/claude-sonnet-5-5` versus Pi's unversioned
`pi-claude-code-provider/sonnet` alias) - see README.md "Captain startup
model". `openai-codex/gpt-6.2-astra` is confined to Pi. Sonnet 5, Opus 5,
Fable 5.1, GPT-5.5, GPT-5.6 Luna/Sol, GPT-6 Sol, GPT-6.1 Sol, and GPT-6 Astra
are retired from worker routing.

**Deferred to a later release.** The local Qwen/Ollama lane remains absent
while that machine is offline. It is not configured anywhere in this
repository.

## 4. Roles

Roles live at `$FM_CONFIG_ROOT/roles/<name>/ROLE.md`. Each file opens with
OMP task-agent frontmatter - `name: fm-<name>`, a `description`, optional
`autoloadSkills`, an explicit `tools` list and, for a role that calls
sub-agents, `spawns` - so the same file is both the role a brief points at and
a valid OMP agent definition. `install.sh` links each one into OMP's user agent
root as `~/.omp/agent/agents/fm-<name>.md`, so every OMP session can spawn
`fm-<name>`; it never replaces an entry there that is not its own. A role's
`autoloadSkills` is its whole skill set (section 5); choosing the role is the
only way a task gets a skill. `roles/manifest.json` is the one place that
records each role's mode, what it may change, which final block it can end with
and which roles it may call; `bin/fm-workflow check` validates it against the
role files, the workflows and the call-graph rule of section 6.

Core roles:

- `senior-fullstack` - ordinary delivery work; mixed/no-specialist fallback
- `architecture` - structural decisions, not implementation ownership
- `tenth-man` - deliberate adversarial challenge of a plan, design, finding or
  completion claim; risk-triggered or explicitly requested, never routine
  outside a workflow that binds it as a standing step (`research-decide`)

Specialist roles - a starting set, not a closed list. Adding one is a new
role file plus its line here and its entry in the manifest, never a new
dispatch category:

- `security-engineer` - finds, evidences, and ranks security weaknesses in a
  named scope; report-only, never exploits; a blocking gate when a workflow
  asks
- `code-reviewer` - read-only review of a handed diff in fresh context,
  including a review the captain explicitly requests (section 7)
- `refactorist` - one small, behavior-preserving improvement per task, proven
  by the same checks before and after
- `debugger` - source-read-only diagnosis anchored on a red-capable
  reproduction; explicitly authorized local/test reproductions and a causal
  handoff, never source fixes
- `technical-writer` - scoped documentation of settled behavior/decisions;
  no code/config or behavior-defining policy edits merely because it is
  Markdown
- `planner` - turns an unclear or oversized request into a written spec and
  an ordered task list; never implements
- `qa` - independent verification of a change against the task's acceptance
  by running it; never edits it, and ends with a machine-readable verdict
  (section 8)
- `ui-qa` - independent verification of browser-visible behavior by driving
  the real running app, with screenshot or snapshot evidence; ends with a
  verdict
- `test-engineer` - writes the verifiers (failing regression, property,
  differential, end-to-end tests) and proves they fail for the intended reason;
  never edits production source
- `risk-classifier` - reads the change and sets its risk tier, whether a
  security review is required and the diff-triggered checklist items that
  match; ends with a risk block
- `finding-verifier` - tries to disprove each review or security finding
  before it reaches the implementer; only confirmed findings go back
- `release-engineer` - decides ship-readiness for the head commit and prepares
  the delivery package (verification stamp, risk, rollback); never pushes or
  merges
- `researcher` - answers a question from high-trust primary sources with cited
  findings and confidence; distinct from `scout` (facts about this codebase)
- `perf-engineer` - measure-first optimisation: baseline, one change at a
  time, keep-or-revert, the limiter named
- `lead` - owns one large, already-scoped deliverable inside one task worktree:
  decomposes it, fans bounded slices to sub-agents, integrates and verifies; it
  never replaces a workflow's independent QA or review steps
- `improver` - turns recorded failure patterns into proposed role, rule or
  skill changes through a PR; never self-applies (section 8, self-improvement)

Skill-less roles (`tenth-man`, listed above, is one too) - choosing one of
these is how a task gets no skill; the Captain never decides "no skill"
separately:

- `scout` - read-only fact gathering over a codebase or a handed PR, reported
  with evidence and limits; never reviews, judges, or changes anything
- `chore` - fully specified mechanical work (a rename, a one-file edit, a
  format pass, collecting a listed fact) with no methodology; it hands
  anything needing design, diagnosis, new logic or judgment back. It is the
  role for QUICK work that is purely mechanical; a QUICK task that needs
  judgment goes to a narrower or `senior-fullstack` role instead

Name the role and its absolute source path in the brief through section 2's
role handoff. A role describes how to work; it never outranks the project.

## 5. Skills

Skills belong to roles, not to tasks. A role file's frontmatter
`autoloadSkills` is the complete list of shared worker skills a worker running
that role is handed (section 2): at most three per role, and none for a role
that needs none (`scout`, `chore`, `tenth-man`, `risk-classifier`). The Captain
does not select, add, drop, budget, substitute or name skills for a delegated
task, and does not name project-local skills. To change what a kind of work
loads, change the role or add one (a role file plus its line in section 4,
never a dispatch category). Which skill a role carries, and why, is recorded in
README.md "Context and skills".

An autoloaded skill must be a shared skill this repository manages (`skills/`
or `skills/external.lock`), must exist at that path, and appears once per
role. Every repo-authored skill is autoloaded by at least one installed role,
except the operator skills named below, which no role may carry; an external
pin may stay installed without a role.
`tests/roles.sh` enforces all of this.

Operator skills (Captain/operator only): none.

Official FirstMate internal skills (the official checkout's own
`.agents/skills`) are never a role skill, per section 2.

A project-local skill always wins over a shared skill covering the same
ground, and a project-required skill is mandatory; it is reached through the
project's own instructions (section 2), not through the Captain.

Handing a worker a role skill is not reading or applying it. Do not claim a
method was applied when a companion file that skill itself requires was not
read and applied.

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
  FirstMate checkout) already applies to every Firstmate-launched omp
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

**The call graph is data.** Which roles may call which through that helper
lives in one place, `roles/manifest.json`, and each role's frontmatter `spawns`
mirrors it. Only `lead`, `planner`, `finding-verifier` and `improver` call
sub-agents, and every role they call calls nobody, so nothing recurses beyond
one level; a helper never publishes, pushes, merges, creates a Firstmate task
or widens its parent's scope. The `lead` role orchestrates inside one task
only: Firstmate still launches the workflow's QA, review and security steps as
separate fresh workers. `bin/fm-workflow check` (and `tests/workflows.sh`)
validate the graph.

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
separate read-only verification worker: the `ui-qa` role, the verification
worker of the `ui-build-verify-review` workflow (section 8). Request the
capability generically; do not hardcode one machine's browser tool or add
another orchestration or completion mechanism.

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
configuration adds no review requirement of its own except the workflows of
section 8: on direct-PR and local-only they are the captain's standing explicit
request (stated in `captain.md`) for their QA, review, verification, security
and ship steps; on `no-mistakes` they add none. Section 3 still chooses
model and effort by semantics; no category, "substantive" classification, or
security, payment, or other risk label is by itself authority for a reviewer.

**Ordinary implementation.** The implementation worker validates its own
change as its path requires (see "Browser and manual verification" above) and
no independent reviewer is dispatched or awaited - for substantive,
cross-component, security, or payment work too - unless the captain
explicitly requested one or the task runs a workflow (section 8), whose
independent QA, review, finding-verification, security and ship steps are the
captain's standing explicit request for them. That request is what the
official contract requires for a separate review; it is never inferred from
risk, and a per-task choice of none (section 8) withdraws it. Genuine
security, destructive, irreversible, and payment authority boundaries still
escalate to the captain exactly as the official contract and the task's own
authority require, independent of this section.

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
add a reviewer instead. When it is the selected path, the forced workflow of
section 8 is `delegated-build`, which adds no reviewer and no gate.

**Report.** State what was implemented and how it was verified; when a
requested review ran, also who reviewed (route/model/harness) and the
BLOCKER/IMPORTANT/OPTIONAL counts. This is reporting discipline, not a
mechanical gate: this configuration has no trusted enforcement runner for
it and never auto-merges on a pass.

This policy and the role skills are guidance, not a
mechanical completion check. This configuration has no trusted verification
runner or FirstMate completion hook; a passing fixture report cannot stand
in for verification of the actual task changes.

## 8. Workflows

A workflow is a declarative state machine in `workflows/<name>.json`
(structure: `workflows/workflow.schema.json`) that `bin/fm-workflow` executes:
named steps, each bound to a role alias, with an input contract, an output
contract, one transition per outcome, loop limits and gates. The engine decides
only what the definition says. It launches no agent, merges nothing and never
writes to a project; the Captain launches every step's worker through
sections 2-3 exactly as it launches any worker. Seven workflows exist;
`bin/fm-workflow list` prints each with its `when`:

- Workflow `build-test-review`: implement, classify the risk of the change,
  independent QA, a fresh-context review whose findings a second worker
  verifies, a blocking security review when the change touches a sensitive
  surface, a ship-readiness check, delivery. For a task that changes behavior
  or code and whose requirement is clear enough to implement without a plan.
- Workflow `plan-build-test-review`: the same with a planner step first; every
  later step receives the plan. For a requirement a reasonable implementer
  could read two ways that behave differently, or too large to start without an
  ordered task list.
- Workflow `bug-fix`: diagnose to a red-capable reproduction, a failing
  regression test written by the test-engineer, the fix (which may not touch
  that test), then the same gates.
- Workflow `refactor`: one behavior-preserving change proven by the same checks
  before and after, then the same gates.
- Workflow `ui-build-verify-review`: a browser-visible change gets QA and then a
  real-browser verification with screenshot evidence before the review.
- Workflow `research-decide`: research from primary sources, options with one
  recommendation, a challenge, a recorded decision; changes no code.
- Workflow `delegated-build`: implement, then delivery through `no-mistakes`
  (see Composing with no-mistakes).

### Forcing

Every non-trivial code-changing task MUST run a workflow. Before the first
worker is launched, classify the task into one kind of
`workflows/selection.json` and resolve it with
`bin/fm-workflow select <kind> --delivery <direct-pr|local-only|no-mistakes>`
(`--delivery` is required where the delivery path decides the workflow, and
`select` refuses without it);
it prints `workflow: <name>` (start that workflow, below) or the one exception
that applies. Print that result with the section 0 block. The exceptions are a
closed list; nothing else exempts a task:

1. `trivial-chore`: a trivial or mechanical change fully specified in the
   brief (the `chore` role, or the narrowest fitting role, one worker).
2. `question-or-diagnosis`: a pure question, research or diagnosis that changes
   no code and records no decision (the researcher, scout, debugger or
   architecture role alone).
3. `captain-none`: the captain explicitly chose no workflow for this task
   (`bin/fm-workflow select <kind> --none "<the stated choice>"`).

A documentation-only task (`docs`) is outside the rule, not an exception: it
changes no behavior, so it runs no workflow. A change to a role, skill,
workflow or policy file defines agent behavior and is configuration: classify
it `feature` or `refactor`.

A task whose selected delivery path is `no-mistakes` is not a fourth way out:
it runs `delegated-build`. When unsure whether a task is trivial, it is not.
`bin/fm-workflow check` and `tests/workflows.sh` prove mechanically that every
non-trivial code-changing kind resolves to an existing workflow under every
delivery mode, that every workflow's roles exist and can produce their step's
output, and that every role in `roles/manifest.json` is bound by a workflow,
called by a bound role, or documented adhoc. They cannot prove that the Captain
classified the task correctly or ran `select`; the printed result is the audit
trail.

### Composing with no-mistakes

Official FirstMate (`AGENTS.md` section 7, "Selected delivery path and merge
authority") gives `no-mistakes`, when selected, sole ownership of review,
fixes, tests, documentation, push, PR and CI, and allows a separate review only
on the captain's explicit request. A workflow is that explicit request for its
own QA and review steps (section 7), but never on top of `no-mistakes`. So for
a `no-mistakes` task the forced workflow is `delegated-build`: the implementer
commits and shows what it ran (a result block), then Firstmate delivers through
`no-mistakes`. It has no QA, review, verification or security worker; all its
gates are observe-only, so no review gate blocks it; a change of direction can still
be raised early. It adds tracking, an evidence record and an early-exit outcome,
and nothing that holds work outside `no-mistakes` for a manual verdict. If the
change needs more rigor than `no-mistakes` gives, escalate whether to use
another path; never silently add a reviewer. The captain may withdraw the whole
workflow for a task with `captain-none`.

### Choosing

Pick the kind by what the task is: new or changed behavior with a clear
requirement (`feature`), with an ambiguous or oversized one
(`feature-unclear`), a reported defect (`bugfix`), a restructuring that must not
change behavior (`refactor`), a browser-visible change (`ui`), research that
must end in a recorded decision (`decision`). A pure question or diagnosis
(`question`) and trivial work (`trivial`) run no workflow. An explicit captain
choice of workflow, or of none, always wins. Section 7's no-reviewer default
applies to everything that runs no workflow.

### Running

1. Start with `bin/fm-workflow next <workflow> $FM_HOME/data/<task-id>/workflow.json --task <the captain's intent>`.
   The state file lives only in the task's data folder, never in a repository;
   it embeds the definition it started with, so editing `workflows/` never
   changes a task in flight. Beside it the engine appends `retro.jsonl` (see
   Self-improvement). `next` without a result flag only prints the current
   step. A state file from an older engine is refused with an instruction.
2. Every `work` step is a fresh worker with its own task and worktree, even
   when a role repeats (the implementer's fix round): section 2's role-change
   rule, and each step's spec carries everything it needs, so no step relies on
   another worker's memory. Brief it with `next ... --spec` pasted into
   `## Firstmate spec` unchanged: it contains the step's instruction, its
   inputs, its output contract, and `bin/fm-role-handoff <role>` verbatim for
   the role bound to the step's alias. The change travels as a commit range on
   the task branch (the engine carries `base..commit`), a plan, diagnosis or
   report as a file named in the step's inputs; each step's worktree starts from
   that branch (section 2's carry-source route). Route the step by section 3 as
   any task: implementation steps IMPLEMENT or IMPLEMENT-LARGE; classify, qa,
   ui-verify, review, verify-*, security and ship steps REVIEW; the `challenge`
   step (`research-decide`, the one workflow that runs `tenth-man` as a
   standing step) TENTH-MAN; the `options` step ARCHITECTURE; plan, diagnose and
   research steps by their semantics. The role is the step's, never the
   category's.
3. Record each result. A `result`, `verdict` or `risk` step: `--report <the
   worker's final report file>`; the outcome is parsed from its final fenced
   block by the engine, never read, inferred or overridden by the Captain. A
   malformed review or QA verdict is a FAIL; a malformed verify-step verdict,
   result or risk block is sent back twice, then blocked (a verifier's report
   never silently loses the findings it was handed). A `report` step (plan,
   diagnose, research, options):
   `--outcome done|blocked|change-direction` with `--report`, the status being
   the first line of the worker's report. Decision step:
   `--decide <choice> --reason <why>`, by the criteria the step prints; no
   worker is launched and the reason is kept in the state. Delivery step:
   Firstmate delivers through the task's own delivery mode (for direct-PR the
   worker that owns the branch pushes it and opens the PR ready for review,
   with the ship step's package as the body); it never merges, and
   `--outcome done` records it. The engine tracks the change itself, from the
   `base` and `commit` of the result blocks.
4. Feedback travels verbatim. The next step's spec carries the feedback list
   exactly as the verdict recorded it: pasted unchanged, never summarised,
   merged, reordered, softened, or added to by the Captain. Only verified
   findings go back to the implementer: a review or security FAIL goes first to
   a fresh verify worker that tries to disprove each finding, and the
   implementer receives only the findings it confirmed; style-only findings are
   dropped; OPTIONAL (nit) and PRE-EXISTING items never go back, they are kept
   as notes for the delivery. The implementer answers every handed id (fixed
   with evidence, or rejected with a reason); QA and the re-review get the same
   ids, the re-review only the delta and the findings already posted.
5. Every fix is a new commit, so classify, QA and review run again on it; a
   pass is valid only for the commit it ran on (a verdict names its commit; the
   verification stamp marks a stale one).
6. In the Captain chat, each block of section 0 for a worker of a workflow also
   carries the derived `Workflow:` line.

### Convergence, risk and direction

- Round cap. The QA loop and the review loop allow 3 rounds. When a loop is
  exhausted the author does not take a fourth: a `step-back` worker reconsiders
  the approach from every accumulated finding and ends with change-direction or
  with an escalation to the captain, with the feedback attached. An escalated
  or closed state is terminal; continuing is the captain's decision, never an
  edit of the state file.
- Risk tiers are set by the change, not the author. `classify` sets low,
  medium or high, whether a security review is required (a sensitive surface or
  a high tier requires it) and the matched diff-triggered checklist items. A
  required security review blocks like any gate. The human approvals required
  follow the tier (0, 1, 2) and are printed by the delivery step as the
  captain's to give: official merge authority (the captain's approval, or
  `yolo` for green in-scope work) still governs the merge, and a high tier is a
  security-sensitive merge that escalates to the captain even under `yolo`. An
  agent's verdict - QA, review, security, release or the Captain's own - never
  replaces a human's required approval, and the workflow never merges.
- Change of direction. A worker, reviewer or plan that finds the approach
  wrong ends with change-direction as soon as it is established, never as a
  blocking comment on finished work. The `redirect` decision then reshapes (a
  re-plan, at most twice), closes the task, or escalates to the captain. Raised
  early, a wrong approach costs a closed task.
- Verification stamp. The delivery step derives, from the recorded results,
  which gates ran on which commit (or none): it goes into the delivery.

### Gates: observe before enforce

The engine's gates over the structured blocks - `evidence` (a done result shows
commands with observed output), `answers` (every handed id answered), `commit`
(a verdict names the head commit it judged), `coverage` (a verifier accounts
for every finding) - start in observe mode: a would-block is recorded in the
retro log and shown to the next worker, nothing is blocked. A definition flips
a gate to enforce, by a normal PR, after the log shows its would-blocks were
true positives; an enforced gate sends the step back with the problems, and
the third attempt is let through (recorded escaped), so no gate wedges a run.

### Self-improvement

`bin/fm-retro` is the loop's whole machinery (bash and jq; no service, no
network). The engine appends a record for every finding, confirmation, dropped
finding, answer, gate result, round cap, escalation, change of direction and
completion to `retro.jsonl` in the task's data folder, outside every
repository; `bin/fm-retro record` adds what it cannot see (a reverted PR). `bin/fm-retro report` aggregates
recurring finding classes per role, rounds-to-pass, the escalation rate and the
noise rate (findings the verifier dropped or the implementer showed wrong);
`bin/fm-retro propose` prints PROPOSALS only, for a class seen in two or more
tasks. The `improver` role turns proposals into a change; it is applied only
through a normal PR by a worker, approved by a human, never auto-applied and
never by editing a role from inside a running task. `tests/evals.sh` scores each
role or workflow change against fixtures of past failure patterns.

Adding or changing a workflow is a JSON file under `workflows/` plus
`bin/fm-workflow validate` and `check`, never an engine change. Swapping the
agent for every task of a kind of work is one edit of the definition's `roles`
map (a PR); for one task, `next ... --role <alias>=<role>` at the start (for
example `implementer=lead` for one large, already-scoped step) swaps it in that
task's embedded definition, validated like any definition. Bump
`version` on a behavior change. The engine proves sequence, handoff, loop and
routing mechanics; it cannot prove that the Captain chose the right workflow or
that a worker read and applied its role.
