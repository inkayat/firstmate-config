# Captain primary policy

Operating policy for the Firstmate captain on this fleet. It refines how the
captain works; it never overrides `AGENTS.md`, and it never overrides a
project's own instructions.

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

5. a pre-work requirement: before substantive work, confirm `pwd -P`
   equals `git rev-parse --show-toplevel` (standing at the worker's own
   isolated worktree root, not a parent or the primary checkout), then
   read every path named above relative to that root and report a missing,
   unreadable, or conflicting path instead of silently falling back to a
   different scope or a global default;
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
dispatch categories before harness/model/effort are chosen. Categories are a
semantic-fit classification, not a size ladder and not a keyword match - read
the full "when"/"why" text for each in `config/crew-dispatch.json`, the
authoritative source this table summarizes. An explicit captain choice always
wins over the table.

| Category | Sub-lanes (route) | Role |
| --- | --- | --- |
| QUICK | omp `anthropic/claude-haiku-4-5` low (or omp `openai-codex/gpt-6-luna` low - genuinely interchangeable) | senior-fullstack |
| EXPLORE | simple: omp `anthropic/claude-haiku-4-5` low (or omp `openai-codex/gpt-6-luna` low); hard: omp `anthropic/claude-sonnet-5` medium | senior-fullstack |
| RESEARCH | ordinary: omp `anthropic/claude-sonnet-5` medium; substantial/decision-heavy: omp `anthropic/claude-opus-5-5` high; Pi-tooling advantage: pi `openai-codex/gpt-6-sol` medium | senior-fullstack |
| REVIEW | bounded: omp `anthropic/claude-sonnet-5` high; substantive/cross-component: omp `anthropic/claude-opus-5-5` high; critical/high-consequence: omp `anthropic/claude-opus-5-5` xhigh (optional cross-family second reviewer: pi `openai-codex/gpt-6-sol` xhigh) | senior-fullstack |
| ARCHITECTURE | omp `anthropic/claude-opus-5-5` high; very difficult: xhigh (pi `openai-codex/gpt-6-astra` xhigh only when ultra-exceptional) | architecture |
| TENTH-MAN | Claude-authored work: pi `openai-codex/gpt-6-sol` xhigh (pi `openai-codex/gpt-6-astra` xhigh only when critical/unresolved after Sol); Astra/OpenAI-authored work: omp `anthropic/claude-opus-5-5` xhigh | tenth-man |
| IMPLEMENT | small/bounded: omp `anthropic/claude-sonnet-5` high; substantive: omp `anthropic/claude-opus-5-5` high | senior-fullstack |
| IMPLEMENT-LARGE | omp `anthropic/claude-opus-5-5` high; reasoning-heavy: xhigh | senior-fullstack |
| DEEP | scout and ship: omp `anthropic/claude-opus-5-5` xhigh, with `openai-codex/gpt-6-sol` xhigh reached only through an explicit single-candidate escalation rule (pi for diagnosis, omp for implementation) and `openai-codex/gpt-6-astra` xhigh as the last escalation beyond that - never a quota peer | senior-fullstack |
| UI/BROWSER | normal: omp `anthropic/claude-sonnet-5` high; complex/cross-layer: omp `anthropic/claude-opus-5-5` high | senior-fullstack |
| DEFAULT | omp `anthropic/claude-opus-5-5` high (debugging period, section 8) | senior-fullstack |

Sub-lanes are separate same-category rules, never new categories and never
quota-array peers, so semantic escalation cannot be mistaken for quota
selection.

`config/crew-dispatch.json` carries twenty-seven `rules` entries (ten
distinct `category` values; EXPLORE, IMPLEMENT, IMPLEMENT-LARGE, and
UI/BROWSER each span two more-specific rules; RESEARCH spans three
(ordinary, substantial/decision-heavy, Pi-tooling); REVIEW spans four
(bounded, substantive, critical, cross-family second review);
ARCHITECTURE spans three (ordinary, very difficult, Astra
ultra-exceptional); TENTH-MAN spans three (Claude-primary Sol, Astra
critical escalation, OpenAI-primary Opus 5.5); DEEP spans five
single-candidate conditional rules - scout primary, scout Sol escalation,
ship primary, ship Sol second-hypothesis, Astra exceptional last
escalation - never a quota-resolved array) plus `default` for the DEFAULT
catch-all, in the form Firstmate reads at intake, each with the full
natural-language `when`/`why` text this table compresses. An explicit
captain choice always wins over it.

**Effort is not negotiable downward.** Where the table says xhigh, a lane
that cannot run xhigh does not run at reduced effort; it is reported as
blocked and the work waits for a decision.

**Opus 5.5-biased, with bounded work kept cheap.** Substantive work lands on
Opus 5.5: substantial or decision-heavy RESEARCH, substantive and critical
REVIEW, all ARCHITECTURE, substantive IMPLEMENT, all IMPLEMENT-LARGE,
complex UI/BROWSER, both DEEP forms, and - during the debugging period -
the DEFAULT catch-all. Small or bounded work may stay on Sonnet 5
(bounded REVIEW/IMPLEMENT, normal UI/BROWSER, ordinary RESEARCH, hard
EXPLORE) and trivial work on Haiku 4.5 or GPT-6 Luna (QUICK, simple
EXPLORE). "Substantive" is the same standard section 7 uses to require
review: meaningful new behavior, a nontrivial refactor, work spanning
multiple components, or real cross-component regression risk. When
uncertain between Sonnet 5 and Opus 5.5 for a substantive task, choose
Opus 5.5. TENTH-MAN enforces model-family diversity directly: it never
shares a model family with the work it is challenging, defaulting to GPT-6
Sol and escalating to GPT-6 Astra only for critical cases the Sol
challenge leaves unresolved. Semantic fit is decided first; provider
availability and capacity only break ties within a rule's own listed
candidates, never override the category or rule itself.

**`use` arrays versus separate rules versus documented overrides.**
FirstMate resolves a matched rule's `use` array through its quota-array
procedure, so an array contains only candidates intended as semantic peers:
QUICK and EXPLORE's simple rule each pair Haiku and Luna at low effort.
Every other rule is a single candidate, so Sol, Astra, or Sonnet 5 can
never be selected ahead of an Opus 5.5 primary by quota resolution.

Separate, more-specific rules carry the same `category` value when the
difference is a semantic trigger rather than a quota choice: EXPLORE's
harder-reasoning rule, RESEARCH's decision-heavy and Pi-tooling rules,
REVIEW's substantive, critical, and cross-family-second-review rules,
ARCHITECTURE's very-difficult and ultra-exceptional rules, IMPLEMENT's
substantive rule, IMPLEMENT-LARGE's reasoning-heavy rule, TENTH-MAN's
three author-family/escalation conditions, UI/BROWSER's complex/cross-layer
rule, and DEEP's five conditional rules (scout primary, scout Sol
escalation, ship primary, ship Sol second-hypothesis, Astra exceptional
last escalation).

**Sol and Astra** stay semantically scoped. GPT-6 Sol is the everyday
cross-family route: RESEARCH's Pi-tooling rule, REVIEW's cross-family
second reviewer, DEEP's diagnosis/ship escalations, and TENTH-MAN's
default route whenever the work under review was authored by Claude - an
independent second opinion on a Claude-authored architecture
recommendation is dispatched as TENTH-MAN, not as an ARCHITECTURE quota
peer. GPT-6 Astra is reserved strictly for each category's most extreme
escalation beyond Sol or Opus 5.5 xhigh: ARCHITECTURE's ultra-exceptional
rule, DEEP's last escalation across both forms, and TENTH-MAN's
critical/unresolved Claude-primary escalation.

**Role stays separate from category.** The category table selects
harness/model/effort; it never selects a role. Only three roles exist
(section 4): `senior-fullstack` is the default for every category above
except the two that name a different one. `architecture` and `tenth-man`
are used only for their matching categories, and only because those
categories are explicitly risk-triggered or structural, never because a
category happens to route through a strong model.

**Scout or ship is chosen per task, not per category.** EXPLORE, RESEARCH,
REVIEW, ARCHITECTURE, and TENTH-MAN are commonly read-only and commonly run
as a scout; QUICK, IMPLEMENT, IMPLEMENT-LARGE, UI/BROWSER, and the
implementation form of DEEP are commonly mutating and commonly run as a
ship. Neither mapping is fixed: a QUICK question can be a scout, a QUICK
rename a ship; a DEEP diagnosis is naturally a scout, a DEEP fix naturally a
ship. Judge the actual task, not the category label.

**Model catalog adoption.** Active routes use only `anthropic/claude-haiku-4-5`,
`anthropic/claude-sonnet-5`, `anthropic/claude-opus-5-5`,
`openai-codex/gpt-6-luna`, `openai-codex/gpt-6-sol`, and
`openai-codex/gpt-6-astra`. OMP's native catalog lists all six with low
through xhigh support; Pi exposes no Anthropic provider on this machine, so
every Claude route is OMP. `openai-codex/gpt-6-sol` is also the
Captain-startup candidate in `captain-startup-models.tsv` (medium effort);
that chain's Claude Sonnet fallback step is harness-scoped (OMP's own
`anthropic/claude-sonnet-5` versus Pi's `pi-claude-code-provider/sonnet`)
- see README.md "Captain startup model". `openai-codex/gpt-6-astra` is
confined to Pi. Opus 5, Fable 5.1, GPT-5.5, and GPT-5.6 Luna/Sol are
retired from worker routing.

**Deferred to a later release.** The local Qwen/Ollama lane remains absent
while that machine is offline. It is not configured anywhere in this
repository.

**Collisions.** The full disambiguating language for every adjacent-category
pair a task could plausibly straddle (QUICK/IMPLEMENT, EXPLORE/RESEARCH,
RESEARCH/REVIEW, REVIEW/TENTH-MAN, REVIEW/ARCHITECTURE, ARCHITECTURE/DEEP,
IMPLEMENT/IMPLEMENT-LARGE, IMPLEMENT-LARGE/DEEP, IMPLEMENT/UI-BROWSER,
DEEP/TENTH-MAN) lives in each category's own primary rule's `when` text in
`config/crew-dispatch.json`, not as a separate keyword table here: that
`when` clause names the neighboring category it could be confused with and
states the concrete test that resolves it. A category's more-specific
secondary rule(s) instead state the narrower trigger that distinguishes
them from their own category's primary rule.

## 4. Roles

Three generic roles, at `$FM_CONFIG_ROOT/roles/<name>/ROLE.md`:

- `senior-fullstack` - ordinary delivery work
- `architecture` - structural decisions, not implementation ownership
- `tenth-man` - deliberate adversarial challenge; risk-triggered or explicitly
  requested, never routine

Name the role in the brief and point the worker at its file by absolute path.
A role describes how to work. It never outranks the project.

## 5. Skills

Global skills live in the normal Agent Skills location and load on demand.
Select them; do not dump them. Per task, at most two workflow or methodology
skills and at most one reference skill, fewer by preference, and none at all
when the task does not need one. A project-local skill always wins over a
global skill covering the same ground.

Official FirstMate internal skills (the official checkout's own
`.agents/skills`) are never a global skill choice for a delegated task -
they are Captain/FirstMate-only, per section 2.

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

### Independent review before merge

Before treating a merge-eligible task as ready, judge whether the change
warrants an independent read-only review pass separate from the worker that
wrote it. This is advisory guidance layered on the existing REVIEW/TENTH-MAN
routes (section 3) - it adds no new dispatch category, severity engine, or
router logic. This section
governs only the Captain-dispatched advisory path described below; a task
running through `no-mistakes`'s own automated pipeline is reviewed by that
pipeline's own gate, which this policy does not touch, does not duplicate,
and cannot guarantee a separate outside reviewer for - reaching into that
pipeline to insert or require one is an official FirstMate change, out of
scope for this configuration.

**When review is required**, not merely considered: IMPLEMENT-LARGE work
(including its reasoning-heavy escalation), a DEEP ship/implementation
outcome, any change touching authentication or security, payments, data
integrity, a nontrivial migration, concurrency, or otherwise carrying a
high blast radius, release-critical status, or a substantial public API
change - and, independent of that topic list, any change that is
materially substantive (meaningful new behavior, a nontrivial refactor, or
work spanning multiple components) or that carries real cross-component
regression risk, whatever its category. Ordinary IMPLEMENT work is judged
by its actual risk and substance against that same standard, never
exempted merely for not naming a listed topic - a normal IMPLEMENT task
that is materially substantive, carries cross-component regression risk,
or touches one of the listed areas needs review; a narrowly bounded one
that does none of those does not. QUICK work and other genuinely trivial,
narrowly bounded changes may skip review only when neither a listed
mandatory-risk topic nor this substantive/regression-risk trigger applies
- never as a blanket exemption for the category alone.

**How review runs.** Every required review needs a different, read-only
worker in a fresh context, never the implementation worker itself even in
a new context or session - this is the baseline independence axis, and
REVIEW's existing rules (bounded, substantive, critical, section 3) already
satisfy it by construction, since REVIEW always dispatches as its own
separate task with its own worker. Model-family or adversarial independence is a second, separate
axis: reach for REVIEW's cross-family second-reviewer rule or for
TENTH-MAN only when that additional adversarial or cross-family check is
itself warranted - the highest-stakes review escalation, or a deliberate
adversarial challenge - never merely because a review is required; an
ordinary REVIEW pass in a fresh session already satisfies this section's
baseline. The reviewer is read-only: it inspects the resulting diff and the
surrounding code it touches, never re-implements. Read-only also means it
never fetches, pulls, or otherwise updates a canonical checkout (official
FirstMate, this configuration repository, or a project's own primary
checkout) to get evidence - it works from the diff/patch and base/head
revisions it was handed, refs already present in its own isolated
worktree, or a disposable clone made for that one review, never a live
`git fetch`/`git pull`/`fm update` against shared state. This is a rule
for how a review is conducted, not new enforcement infrastructure. Model
and harness choice for the reviewer stays exactly what section 3 already
assigns for the matched rule - this policy changes when a reviewer is
required and what it must report, never which model reviews it.

Because each dispatched task owns its own isolated worktree (section 2), a
separately dispatched reviewer cannot assume it can see the implementation
worker's uncommitted change on its own. Before a review pass counts as run,
the Captain hands the reviewer the actual complete diff together with its
base and head revision, or an immutable commit/patch reviewable from the
reviewer's own worktree - never a bare instruction to "review the change"
with no reviewable artifact. The same handoff - including the original
findings/report the re-review must close, not just the corrected code -
scoped to the corrected delta, is required before a re-review can be
claimed complete: a re-review report is not valid without evidence the
reviewer actually received and read the corrected code against those
original findings, not merely the original diff again.

**Findings and severity.** The reviewer reports each finding as one of:

- **BLOCKER** - must be fixed before the change is merge-ready.
- **IMPORTANT** - should be fixed; waivable only by the captain's explicit
  word, never by the implementation worker or the reviewer itself.
- **OPTIONAL** - worth noting, never blocking.

Fix every BLOCKER finding and every IMPORTANT finding that is not
explicitly waived, and send each fix through a targeted independent
re-review of the corrected delta before treating the change as
merge-ready - re-review is not optional for either severity once a fix is
made, only the fix-or-waive choice differs between them: BLOCKER must be
fixed, IMPORTANT either gets fixed or stays open pending an explicit
captain waiver, and it is never silently dropped. OPTIONAL findings alone,
with nothing outstanding at BLOCKER or unwaived IMPORTANT, may proceed
without another review pass.

**Report.** For any task this section applied to, state: what was
implemented, how it was verified, whether review ran or was judged
skippable and why, who reviewed (route/model/harness), the
BLOCKER/IMPORTANT/OPTIONAL counts, and the resulting
merge-readiness. This is guidance and reporting discipline, not a
mechanical gate: this configuration has no trusted enforcement runner for
it, so it never auto-merges on a pass and never substitutes for genuinely
running the review it calls for.

This policy and the selected verification skills are guidance, not a
mechanical completion check. This configuration has no trusted verification
runner or FirstMate completion hook; a passing fixture report cannot stand
in for verification of the actual task changes.

## 8. Routing and skill trace (temporary, debugging period)

Until the captain ends this debugging period, print a short trace in the
Captain chat. It discloses decisions sections 3 and 5 already made - never
reasoning or chain-of-thought, never pasted into the brief, never written
to a file, board, or monitor.

Before each delegation, one block per worker (implementer, reviewer,
re-reviewer, tenth-man):

    Routing: <CATEGORY> [#n] | role <role> | <harness> | <provider/model> | <effort> | why: <short reason>
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
  their worktree-relative path, shared ones by name. Nothing else - no
  installed-but-unselected skill, no official FirstMate internal skill.
  `Skills: none` is valid.

After a worker finishes:

    Skill evidence:
    - <skill>: <observation citing `verbatim excerpt`>
    - <skill>: selected, but no strong application evidence observed

- One line per selected skill, none for an unselected skill, at most two
  observations each.
- Each observation quotes a short verbatim excerpt from the worker's own
  pane, transcript, report, or diff - a command it ran, output it saw, a
  test it added. A skill's existence, its selection, or the worker saying
  it applied the skill is not evidence; use the second form instead. Read
  the excerpt in context first: text the worker only quoted, planned, or
  denied doing is not evidence either.

Independent review stays separate from any automated pipeline:

    Review: <role> | <harness> <model> <effort> | why: <reason> | skills: <...> | BLOCKER n, IMPORTANT n, OPTIONAL n
    no-mistakes: <result>

`tests/routing-trace.sh check` checks one captured block against the real
spawn axes, the matched rule's route, the brief's selected skills, and the
worker transcript; its offline suite also drives the real `fm-spawn.sh`
seam with a fixture worker. A citation PASS is a lexical match only, so
`check` prints each citation's transcript context for that reading. It
does not prove the category or rule was chosen correctly or that a skill
was applied. It is
a diagnostic, never a gate.
