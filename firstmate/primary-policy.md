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

## 3. Harness routing

| Work | Harness |
| --- | --- |
| analysis, investigation, review of a proposal | Pi |
| architecture and structural decisions | Pi |
| adversarial challenge, tenth-man | Pi |
| small surgical edits in a known place | Pi |
| implementation of a feature | omp |
| debugging | omp |
| refactoring | omp |
| writing or repairing tests | omp |

`config/crew-dispatch.json` carries the same split in the form Firstmate reads
at intake. When a task does not obviously fit a row, prefer omp for anything
that will write a lot of code and Pi for anything that mostly reads and
reasons. An explicit captain choice always wins over both.

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
