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

**Category first.** Every delegated task maps to exactly one of eleven
dispatch categories before harness/model/effort are chosen. Categories are a
semantic-fit classification, not a size ladder and not a keyword match - read
the full "when"/"why" text for each in `config/crew-dispatch.json`, the
authoritative source this table summarizes. An explicit captain choice always
wins over the table.

| Category | Primary route | Role |
| --- | --- | --- |
| QUICK | omp `anthropic/claude-haiku-4-5` low (or omp `openai-codex/gpt-5.6-luna` low - genuinely interchangeable) | senior-fullstack |
| EXPLORE | omp `anthropic/claude-haiku-4-5` low | senior-fullstack |
| RESEARCH | omp `anthropic/claude-sonnet-5` medium | senior-fullstack |
| REVIEW | omp `anthropic/claude-sonnet-5` medium | senior-fullstack |
| ARCHITECTURE | pi `openai-codex/gpt-6-astra` xhigh | architecture |
| TENTH-MAN | pi `openai-codex/gpt-6-astra` xhigh | tenth-man |
| IMPLEMENT | omp `anthropic/claude-sonnet-5` medium | senior-fullstack |
| IMPLEMENT-LARGE | omp `anthropic/claude-sonnet-5` high | senior-fullstack |
| DEEP | pi `openai-codex/gpt-6-astra` xhigh (diagnosis) / omp `openai-codex/gpt-6-astra` xhigh (implementation) | senior-fullstack |
| UI/BROWSER | omp `anthropic/claude-sonnet-5` high | senior-fullstack |
| DEFAULT | omp `anthropic/claude-sonnet-5` medium | senior-fullstack |

This table shows each category's active primary route only. Separate
more-specific rules and documented overrides (below) are not primary/
fallback pairs and are deliberately left off this table so it cannot be
misread as a fallback list.

`config/crew-dispatch.json` carries fourteen `rules` entries (ten distinct
`category` values; EXPLORE, RESEARCH, IMPLEMENT-LARGE, and DEEP each span
two more-specific rules sharing the same category value) plus `default` for
the DEFAULT catch-all, in the form Firstmate reads at intake, each with the
full natural-language `when`/`why` text this table compresses. An explicit
captain choice always wins over it.

**Effort is not negotiable downward.** Where the table says xhigh, a lane
that cannot run xhigh does not run at reduced effort; it is reported as
blocked and the work waits for a decision.

**Claude-heavy by design, GPT where reasoning materially helps.** Practical
capacity on this fleet is roughly Claude 20 against GPT 5 - a ratio of about
4:1, not 20:1 - so ordinary, comparable work defaults to a Claude lane
(Haiku for QUICK/EXPLORE, Sonnet for RESEARCH/REVIEW/IMPLEMENT/
IMPLEMENT-LARGE/UI-BROWSER). Scarcer GPT capacity is spent deliberately,
only where OpenAI reasoning materially helps: Astra for ARCHITECTURE,
TENTH-MAN and DEEP, where the point is either independence from the OMP
implementation session (Pi, away from that session) or genuinely hard
reasoning. Semantic fit is decided first, per the category table above;
provider availability and capacity only break ties within a rule's own
listed candidates, never override the category or rule itself.

**`use` arrays versus separate rules versus documented overrides.**
FirstMate resolves a matched rule's `use` array through its own
quota-array procedure, so an array must contain only candidates that are
genuinely, semantically interchangeable - never a mix of semantic
escalations, tooling conditions, or mutability choices dressed up as one
array. QUICK's Haiku/Luna pair is the one case in this configuration that
qualifies: both are the same cheap tier, at the same effort, with no
semantic reason to prefer one over the other. Every other apparent
"alternative" is instead one of two things:

- **A separate, more specific rule carrying the same `category` value**,
  used when the difference is a genuine semantic trigger FirstMate should
  match on its own `when` text, not resolve by quota: EXPLORE's
  harder-reasoning rule (Sonnet), RESEARCH's Pi-tooling-better rule
  (`openai-codex/gpt-5.6-sol` on Pi), IMPLEMENT-LARGE's sustained-execution
  rule (Opus), and DEEP's diagnosis rule (Pi + Astra, read-only) versus its
  implementation rule (OMP + Astra, mutating) - harness and mutability
  differ between them, not just provider.
- **A documented availability/semantic override, never encoded in a `use`
  array**, for a candidate that is not proven interchangeable with the
  active primary: `anthropic/claude-opus-5` for ARCHITECTURE and
  TENTH-MAN (Astra stays the sole active primary on Pi), and for DEEP's
  implementation rule (Astra stays the sole active primary on OMP). The
  captain reaches for Opus deliberately in these three cases - unavailable
  Astra, or OMP-session familiarity outweighing Astra's reasoning edge -
  never as a quota-resolved peer.

**Opus versus Astra** stays a semantic choice, never a size-driven default
and never a shared candidate array: Opus is difficult *execution* - long
sustained work across an unfamiliar repository, subtle invariants, careful
migrations, broad but mostly-settled implementation (IMPLEMENT-LARGE's own
escalation rule) - while Astra is difficult *reasoning* - dense algorithmic
or protocol work, structural judgment, adversarial scrutiny, root-cause
diagnosis (ARCHITECTURE, TENTH-MAN, and both DEEP rules, where Astra is the
active primary and Opus is a documented override, per above). Many files
touched does not by itself select Astra or Opus; a single hard concurrency
bug can.

**Tenth-man independence.** Review on a model that did not produce the work.
If the change came from Astra, override to a different strong model (for
example `openai-codex/gpt-5.6-sol`) rather than the same one.

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

**Model catalog adoption.** `openai-codex/gpt-5.6-luna` is adopted as
QUICK's genuinely-interchangeable OMP array peer: OMP's native catalog
reports its explicit supported effort list (low through max, including
low); Pi's own catalog reports only a bare `thinking: yes/no` column with
no per-level enumeration, so this adoption claim rests on OMP's explicit
levels, not on Pi ever having enumerated Luna's or Astra's individual
effort support - Pi-side effort checks continue to rely on FirstMate's
existing, unchanged detector, which accepts any requested effort once
`thinking` reads `yes`. `openai-codex/gpt-5.6-sol` remains the
Captain-startup-only candidate in `captain-startup-models.tsv` (unchanged)
and is now also RESEARCH's Pi-tooling-better route and the named
tenth-man-independence override above - one model, matched independently
by each rule's own `when` condition, never conflated. `openai-codex/gpt-5.5`
is retired from worker routing entirely: no active route, fallback, or
lane anywhere in this configuration uses it.

**Deferred to a later release.** Two lanes are deliberately absent rather
than blocked by it. Pi with `anthropic/claude-fable-5-1` at xhigh was the
originally intended architecture lane; Pi has no anthropic credential on
this machine, and adopting it is a later decision, so the architecture slot
runs on the strongest verified Pi lane (Astra) at the same effort. The local
Qwen and Ollama lane is likewise deferred while that machine is offline.
Neither is configured anywhere in this repository; adding one is a release
of its own, not a config tweak.

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

This policy and the selected verification skills are guidance, not a
mechanical completion check. This configuration has no trusted verification
runner or FirstMate completion hook; a passing fixture report cannot stand
in for verification of the actual task changes.
