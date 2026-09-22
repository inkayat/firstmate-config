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
policy, then global/shared worker skills, then optional specialist vault
picks.

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
| ARCHITECTURE | pi `openai-codex/gpt-6-astra` xhigh or omp `anthropic/claude-fable-5-1` xhigh | architecture |
| TENTH-MAN | pi `openai-codex/gpt-6-astra` xhigh | tenth-man |
| IMPLEMENT | omp `anthropic/claude-sonnet-5` medium | senior-fullstack |
| IMPLEMENT-LARGE | omp `anthropic/claude-sonnet-5` high | senior-fullstack |
| DEEP | omp `anthropic/claude-fable-5-1` xhigh or Astra xhigh (Pi for diagnosis, omp for implementation) | senior-fullstack |
| UI/BROWSER | omp `anthropic/claude-sonnet-5` high | senior-fullstack |
| DEFAULT | omp `anthropic/claude-sonnet-5` medium | senior-fullstack |

This table summarizes each category's active candidate set. Separate
more-specific rules and documented overrides (below) are not fallback pairs;
they remain explicit so semantic escalation cannot be mistaken for quota
selection.

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
IMPLEMENT-LARGE/UI-BROWSER). Architecture and DEEP instead pair Claude Fable
5.1 with GPT-6 Astra at xhigh because those categories are defined by
structural or root-cause reasoning. TENTH-MAN stays on Astra so adversarial
review remains independent from the OMP implementation session. Semantic fit
is decided first; provider availability and capacity only break ties within a
rule's own listed candidates, never override the category or rule itself.

**`use` arrays versus separate rules versus documented overrides.**
FirstMate resolves a matched rule's `use` array through its quota-array
procedure, so an array contains only candidates intended as semantic peers:

- QUICK pairs Haiku and Luna at low effort.
- ARCHITECTURE pairs Pi + Astra and OMP + Fable 5.1 at xhigh.
- DEEP diagnosis pairs OMP + Fable 5.1 with Pi + Astra at xhigh; DEEP
  implementation pairs both models on OMP at xhigh.

Separate, more-specific rules carry the same `category` value when the
difference is a semantic trigger rather than a quota choice: EXPLORE's
harder-reasoning rule, RESEARCH's Pi-tooling-better rule,
IMPLEMENT-LARGE's sustained-execution rule, and DEEP diagnosis versus
implementation. TENTH-MAN keeps Astra as its sole active candidate; Opus
remains a deliberate documented override there when independence requires a
different strong model.

**Opus, Astra, and Fable** stay semantically scoped. Opus is difficult
*execution* for IMPLEMENT-LARGE's sustained-work escalation. Astra and Fable
5.1 are difficult *reasoning* peers for ARCHITECTURE and DEEP. Astra remains
TENTH-MAN's independent adversarial lane. Many files touched does not itself
select any of them; a single hard concurrency bug can.

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
reports its explicit supported effort list (low through max, including low).
`anthropic/claude-fable-5-1` is likewise an active OMP candidate for
ARCHITECTURE and both DEEP forms; OMP's catalog reports xhigh support, while
Pi exposes no Anthropic provider on this machine. Pi therefore carries Astra,
and OMP carries Fable 5.1 plus Astra where the mutating DEEP form requires
that harness. `openai-codex/gpt-5.6-sol` remains the Captain-startup
candidate in `captain-startup-models.tsv`, RESEARCH's Pi-tooling-better
route, and the named tenth-man-independence override; that chain's Claude
Sonnet fallback step is harness-scoped (OMP's own `anthropic/claude-sonnet-5`
versus Pi's `pi-claude-code-provider/sonnet`) - see README.md "Captain
startup model". `openai-codex/gpt-5.5` remains retired from worker routing.

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

### Specialist skill vault (optional)

`FM_SKILL_VAULT_ROOT` (written to `~/.config/firstmate-config/env` by
`install.sh`, pinned to one exact commit by `skills/vault.lock`, health
reported by `fm doctor`'s `vault.pin`/`vault.no_global_leak` checks) is a
private, curated, provenance-pinned index of specialist skills beyond the
shared worker skills above. It resolves to one immutable, commit-qualified
directory (`<cache-root>/<owner>-<repo>/<exact-commit>`), so an exact path
handed to a worker keeps meaning what it meant when it was issued: a new pin
is a new directory beside the old one, never a rewrite of it. It is never
globally registered - never symlinked into `~/.agents/skills`, never an OMP
`skills.customDirectories`/`includeSkills` entry - so consulting it is always
this per-task, explicit decision, never ambient context.

Consult it only when a task plausibly benefits from a specialist skill past
what the shared worker skills already cover. Zero is the default and a fully
valid outcome for an ordinary task. Look up candidates read-only, never by
parsing a skill body: `bun "$FM_SKILL_VAULT_ROOT/bin/lookup.ts" --category
<CATEGORY>` returns the full, never-truncated, deterministic shortlist of
that category's `firstmate_candidate` rows with `activation: auto-candidate`;
`--id <vault-id>` resolves one exact row by id, `installed`/
`firstmate_candidate`/`reference-only` alike. `catalog`/`team-only`/
`restricted` rows never resolve through either form - naming one explicitly
is never a way around its status. The vault's own `README.md` is
authoritative for its vocabulary (`status`, `activation`, `scope`, `cluster`,
`favorite`); do not duplicate it here, and no category-to-row table exists
in this policy or in `crew-dispatch.json` - a pick is always this per-task
judgment call against the returned shortlist, never a lookup keyed only by
category.

A vault pick counts against, never adds to, this section's first
paragraph's ≤2-methodology + ≤1-reference cap - it is one more place that
cap's picks may come from, not a second budget. Zero or one methodology is
the normal task, one or two a genuinely specialist one, and three the
exceptional maximum; zero vault picks is a fully valid outcome, including for
work that looks specialist at first glance.

A selected vault skill never expands that selection itself. Whatever its body
names, recommends, or chains to is not thereby selected; a methodology it
genuinely requires is the Captain's own pick, made before the brief goes out
and counted against the same cap - if it does not fit inside the cap, the
selection was wrong. The support, reference, helper, and prompt files
belonging to one selected skill are part of that one pick and never count
separately. Within one `cluster`, methodologies are alternatives by default:
selecting two needs a deliberate reason stated in the brief, not a wish for
coverage.

A project-local skill always wins over a vault pick, exactly as it wins over
any other global skill (section 1). `scope: captain` rows (mostly
`reference-only`) are for the Captain's own reading when the human explicitly
asks for that mode (interrogation, planning, retro) - never a worker brief
item; `scope: worker` rows, whether `firstmate_candidate` or
`reference-only`, may be handed to a worker. Canonical Matt-style grilling is
exactly that kind of Captain-scope row: use it deliberately, for a materially
important ambiguity worth pressure-testing before commitment, and never on a
clear architecture decision or an immediate-execution ask.

Handoff format for a selected row mirrors section 2 step 4: the exact
resolved path under `$FM_SKILL_VAULT_ROOT` - an absolute path is correct here,
like the shared worker skill root this is a machine-local cache outside any
worktree, not the primary-checkout path step 3 forbids - plus the same
read-and-apply requirement, plus the row's notes - the ninth, tab-separated
field `bun "$FM_SKILL_VAULT_ROOT/bin/lookup.ts" --id <vault-id>` prints for that
row - as the adaptation/usage caveat when one exists. Read notes from that
field only; never grep or otherwise parse `catalog.yaml` directly for it.

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
