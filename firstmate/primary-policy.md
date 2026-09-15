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
   a read-and-apply requirement, not merely a name to notice, for example:

       Required project skill:
         <worktree>/.agents/skills/django-migrations/SKILL.md
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

5. a pre-work requirement: before substantive work, read every path named
   above and report a missing, unreadable, or conflicting path instead of
   silently falling back to a different scope or a global default;
6. a requirement that scope expansion re-triggers step 2 for the newly
   touched subtree before editing there.

This is a semantic contract, not a copy of the project's documentation:
name paths and the resolution, never paste file bodies or skill bodies into
the brief, and never enumerate every installed global skill. The worker's
own read of the named paths, and its report of what it found, is the
evidence discovery happened - not the harness's generic native loader by
itself.

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

| Work | Harness | Model | Effort |
| --- | --- | --- | --- |
| small or surgical edit, quick factual question | Pi | `openai-codex/gpt-5.3-codex-spark` | low |
| ordinary analysis, investigation, reviewing a proposal | Pi | `openai-codex/gpt-5.5` | medium |
| difficult, broad or high-impact architecture | Pi | `openai-codex/gpt-6-astra` **(interim, see below)** | xhigh |
| adversarial review, tenth-man | Pi | a strong model the work under review did not use | xhigh |
| ordinary substantial implementation, normal debugging, refactors, tests | omp | `anthropic/claude-sonnet-5` | medium or high |
| hard or large implementation, broad blast radius, security / migration / data-integrity / concurrency sensitive, difficult production bugs, high-risk refactors | omp | `anthropic/claude-opus-5` **or** `openai-codex/gpt-6-astra` | xhigh |

`config/crew-dispatch.json` carries the same table in the form Firstmate reads
at intake. An explicit captain choice always wins over it.

**Effort is not negotiable downward.** Where this table says xhigh, a lane
that cannot run xhigh does not run at reduced effort; it is reported as
blocked and the work waits for a decision.

**Medium versus high** on the Sonnet lane is a judgement about actual
complexity - files touched, how settled the design is, how much of the system
the change can disturb - never about how urgently the request was phrased.

**Opus versus Astra** is a semantic choice between two peers, both at xhigh,
made per task: Opus for long-context work across an unfamiliar repository,
subtle invariants and careful migrations; Astra for dense algorithmic or
protocol work and long autonomous tool loops. Weigh task shape, blast radius,
reasoning needs, repository context and current provider headroom. Difficulty
alone does not select Astra, and neither model is the default for everything.

**Tenth-man independence.** Review on a model that did not produce the work.
If the change came from Astra, review on a different strong model rather than
the same one.

**Deferred to a later release.** Two lanes are deliberately absent from v0.1
rather than blocked by it. Pi with `anthropic/claude-fable-5-1` at xhigh was
the originally intended architecture lane; Pi has no anthropic credential on
this machine, and adopting it is a later decision, so the architecture slot
runs on the strongest verified Pi lane at the same effort. The local Qwen and
Ollama lane is likewise deferred while that machine is offline. Neither is
configured anywhere in this repository; adding one is a release of its own,
not a config tweak.

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

Firstmate is the only orchestrator. Workers do not spawn workers. Runtime and
sessions belong to Herdr; task lifecycle belongs to Firstmate's own scripts.
Do not invent a parallel mechanism for anything `bin/` already owns.

## 7. Completion

A task is done when its stated outcome is demonstrated, not when the diff looks
right. Require the worker to report the command it ran and what it observed.
An unverified claim of completion is an open task. Say plainly what was not
verified rather than rounding up.
