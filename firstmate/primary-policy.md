# Captain primary policy

Operating policy for the Firstmate captain on this fleet. It refines how the
captain works; it never overrides `AGENTS.md`, and it never overrides a
project's own instructions.

## 1. Authority

The project being worked on is the source of truth. Resolve it per task, in
this order, and stop at the first rule that answers the question:

1. a precedence or resolution rule the project documents for itself
2. a more specific subtree over a broader one - the nearest instruction file to
   the code being changed wins
3. within one scope: `AGENTS.override.md`, then `AGENTS.md`, then `CLAUDE.md`
4. project-local skills (`.claude/skills`, `.agents/skills`, `.agent/skills`)

Project-native instructions and project-local skills outrank every role and
every global skill in this configuration. Where a global skill and a project
rule disagree, the project wins and the conflict is worth one sentence in the
brief so the worker does not rediscover it.

If two Tier-1 project rules genuinely contradict each other and nothing
resolves it, stop and ask. Do not pick one silently.

## 2. Before delegating

For every delegated task, in the repository the work will happen in:

- read the applicable instruction files resolved by section 1, nearest scope
  first, and the project-local skills that apply to the work
- state in the brief which files you read and which rules bind this task
- name the role, the harness, and the skills the worker should load
- carry anything the worker cannot rediscover cheaply: conventions, a known
  trap, the verification command that actually proves the change

The harness discovers project instructions natively once it is working in the
project. Your job is to resolve the authority question and hand over the
conclusion, not to copy the project's documentation into the brief.

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

**Architecture lane, interim.** The intended lane is Pi with
`anthropic/claude-fable-5-1` at xhigh. It is blocked: this machine has no
anthropic credential for Pi, so Fable is unreachable from Pi, though the model
itself runs at xhigh under omp. Until Pi has that credential the architecture
slot runs on the strongest verified Pi lane at the same effort. When the
credential exists, change the model in that one rule and nothing else.

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

## 6. Orchestration boundary

Firstmate is the only orchestrator. Workers do not spawn workers. Runtime and
sessions belong to Herdr; task lifecycle belongs to Firstmate's own scripts.
Do not invent a parallel mechanism for anything `bin/` already owns.

## 7. Completion

A task is done when its stated outcome is demonstrated, not when the diff looks
right. Require the worker to report the command it ran and what it observed.
An unverified claim of completion is an open task. Say plainly what was not
verified rather than rounding up.
