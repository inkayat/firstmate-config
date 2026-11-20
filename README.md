# firstmate-config

A reproducible configuration layer for official
[FirstMate](https://github.com/kunchenguid/firstmate) on its `main` branch:
Captain startup, worker routing, roles, shared skills, and machine-local setup.
This standalone repository remains the active configuration source.
Project instructions stay project-owned;
credentials and operational state stay outside this repository.

## Install

Use a persistent standalone checkout: the installer links live commands and
configuration back to it. **Do not install from a disposable task worktree.**

Have `git`, `pi`, `omp`, and `herdr` on `PATH`; the installer checks them but
does not install them. `jq`, `treehouse`, `gh`, and `bun` are needed for full
fleet behavior. Configure provider authentication in the harness you intend to
use; the installer never stores credentials.

```sh
git clone https://github.com/inkayat/firstmate-config.git
cd firstmate-config
./install.sh
```

[`install.sh`](install.sh) creates the operational home, selects Herdr, writes
`~/.config/firstmate-config/env`, links the routing profile, shared skills and
OMP role agents, and installs the `fm` link under `~/.local/bin`. Add that
directory to `PATH`. Installation requires this directory to be the Git root;
a nested dotfiles copy is refused before machine state is touched.

If FirstMate is missing, installation clones the manifest's official branch at
the validated commit and tracks that branch. An existing checkout is reported,
never updated or switched by the installer. Re-running installation reconciles
machine state; foreign links are reported as failures and never overwritten.

```sh
./install.sh --verify   # read-only drift report
fm --check                                      # resolve startup without launching
fm
```

`--check` and `--print-command` do not start a Captain, but their preflight can
create missing operational-home directories.

## Daily commands

| Command | Purpose |
| --- | --- |
| `fm` | Start the Pi Captain from any directory, preferring GPT-6.2 Sol medium |
| `fm --harness omp` | Use OMP explicitly; harness fallback is not automatic |
| `fm --model claude` | Choose a model preset for this launch only; also accepts `codex` or `grok` |
| `fm --check` / `fm --print-command` | Inspect startup resolution / the resolved command without launching |
| `fm update` | Fast-forward official FirstMate, then firstmate-config, then reconcile and verify this machine |

Startup `--model` and `--harness` flags work in either order; `--model` is not
an `update` option.

## Architecture

```text
fm → Pi Captain (default) or OMP Captain (--harness omp)
   → official FirstMate → Herdr → Pi / OMP workers
```

FirstMate owns task lifecycle, delegation and worktree isolation; Herdr owns
runtime sessions. Captain harness/model selection and worker routing are
independent.

The Captain runs inside the FirstMate distribution checkout, not the launch
directory. It is multi-project: each task resolves its project separately from
an explicit path/name, the FirstMate registry, then the launch directory as a
hint if it is a Git project. Project instructions and skills are not preloaded
as global authority at startup. The exact precedence belongs to
[primary policy §1](firstmate/primary-policy.md#which-project).

### Captain startup model

[`captain-startup-models.tsv`](firstmate/captain-startup-models.tsv) owns the
ordered chain: GPT-6.2 Sol medium, then a harness-specific Sonnet medium fallback.
Rows for a different harness are ignored. Only an authoritative `UNAVAILABLE`
skips a candidate; `UNKNOWN` remains eligible. Launch output explains fallback
decisions.

The Sonnet fallback is `anthropic/claude-sonnet-5-5` on OMP and the unversioned
`pi-claude-code-provider/sonnet` alias on Pi. Claude Code resolves that alias;
it is not a version-pinned Sonnet selector. Its availability uses the provider's
`claude auth status` preflight because Pi's broker does not load extension
providers. OMP probes use `models --json --no-extensions` to avoid writing
FirstMate extension-load markers.

`fm --model codex|claude|grok` selects, respectively,
`openai-codex/gpt-6.2-sol`, `anthropic/claude-sonnet-5-5`, or `xai/grok-4.7`,
all at medium effort. A preset requires `AVAILABLE` for that exact model/effort.
Invalid, unavailable or unverifiable presets warn and use the unchanged default
chain on the same harness. Raw model ids are not accepted; nothing is persisted.
[`fm-captain-lib.sh`](firstmate/fm-captain-lib.sh) is the shared harness and
availability owner.

## Updating

```sh
fm update
```

[`bin/fm-update`](bin/fm-update) checks **both** repositories before changing
either, then fast-forwards the FirstMate checkout's explicit `main` branch,
fast-forwards this standalone firstmate-config checkout, and runs its
`install.sh` and `install.sh --verify`. Configuration updates target this
checkout itself, never a dotfiles parent or another project. A nested config
root is refused. Neither command installs or updates Herdr plugins.

Both working trees must be clean and fast-forwardable with configured
upstreams. FirstMate must
use the manifest's exact official origin
([`stack-manifest.tsv`](firstmate/stack-manifest.tsv)), check out `main`, track
`origin/main`, and set local `origin/HEAD` to that same branch. No unfinished
Git operation or local-only commits are accepted. `fm update --check` verifies
local guards and prints the source, branch, target and pin without fetching,
updating or installing.

Updates never force, stash, reset, rebase, push, or update project/secondmate
checkouts. If the FirstMate checkout moved and a later stage fails, the command
reports `PARTIAL UPDATE`; there is no multi-repository rollback. Fix the stated
error and re-run. Only `fm update complete` means every stage succeeded.

A running Captain is not restarted or notified. Instructions and skills it has
already loaded stay as they are; end that session and run `fm` again to adopt
updates.

External shared skills are pinned by commit in
[`skills/external.lock`](skills/external.lock); `fm update` never moves a pin.
To move one, review the upstream diff, change the sha, and commit.

### Moving a fork installation to official

Installations that followed the retired `https://github.com/inkayat/firstmate.git`
fork retain that origin and `inkayat-main`. `fm update` refuses that layout
before contacting any remote; `install.sh` only warns and leaves it unchanged.
There is no `--migrate`, `--bootstrap` or automatic source conversion. Changing
an existing FirstMate source is separate, explicitly authorized maintenance,
with no Captain or worker using that checkout. This source port does not
perform or authorize that conversion.

### Retired configuration-owned tools

`fm board`, `fm bot`, `fm doctor`, `fm version`, the `ponytail-update` launcher,
the bot-builder skill, slash-command entries (including `/tlw`), the Pi Ponytail
package/settings reconciler and the documentation site are no longer provided.
The pinned shared Ponytail skills in `skills/external.lock` remain unchanged.

Installation does not delete old links, bot definitions/receipts, board state,
or watcher hooks, and it never overwrites an existing `data/captain.md`.
Machine-owned Pi settings and preferences remain untouched. An existing
`state/bots.check.sh` may still refer to the removed bot executable; its owner
must inspect and retire that hook under separate authority before adopting the
new source. No retirement or migration command is supplied here.

After this candidate is approved and published, reconcile only from the
persistent standalone checkout with `./install.sh`, then run
`./install.sh --verify`, `fm update --check` and `fm --check`. An existing fork
must first be resolved through the separate source-maintenance boundary above.
End the old Captain session and all its workers before activation; start a new
`fm` session afterwards. An uncommitted worktree is not an installation.

## Routing

[`crew-dispatch.json`](firstmate/crew-dispatch.json) owns ten semantic categories
and a DEFAULT catch-all. Substantive work prefers Opus 5.5, bounded work may use
Sonnet 5.5, and trivial work uses Haiku/Luna. GPT-6.2 Sol supplies cross-family
routes and implementation alternatives; Astra is reserved for narrow worker
escalations. Explicit Captain choices can override the profile.

Do not maintain a second routing table here: use the full `when`/`why` conditions
in the profile and [primary policy §3](firstmate/primary-policy.md#3-routing).
During the current debugging period, the Captain prints a short
`Routing:` / `Agent:` / `Skills:` block per actual worker/stage; `Skills:` is
derived from the role, never chosen.
It is a diagnostic trace, not an enforcement or completion gate; see
[policy §0](firstmate/primary-policy.md#0-routing-and-agent-trace-temporary-debugging-period)
and its checker [`tests/routing-trace.sh`](tests/routing-trace.sh).

## Context and skills

### Worker context and skill classes

Precedence is project-native instructions → project-local skills → role/task
policy → shared worker skills. Each task carries explicit instruction and role
paths resolved against its own worktree, plus the exact paths of the skills in
the role's `autoloadSkills`; Pi and OMP native discovery alone do not guarantee
the same resolution. Official FirstMate delivers those paths and read-and-apply
requirements, not role or skill bodies: nothing is inlined before the first
model call, a missing path does not refuse the launch, and no selection record
is written.

Keep three populations distinct: official FirstMate internal skills are
Captain-only; this configuration's shared worker skills are installed under
`~/.agents/skills`; project-local skills remain in their project's tracked
skill directories. [Primary policy §2](firstmate/primary-policy.md#2-before-delegating)
owns the handoff, including revisiting context when a new subtree is selected.

### Role-only selection

[`roles/`](roles/) defines worker contracts and OMP agent definitions;
installation links them as `~/.omp/agent/agents/fm-<role>.md`. The Captain's
only per-task capability choice is a role: the narrowest fitting one, with
coherent mixed work staying with `senior-fullstack`. It never selects skills.
Every skill a worker gets is the role's frontmatter `autoloadSkills`, handed
over by [`bin/fm-role-handoff <role>`](bin/fm-role-handoff). "No skills" is a
role too (`chore`, `scout`, `tenth-man`, `risk-classifier`). Project-local
skills are not selected by the Captain: a worker applies them where the
project's own instructions require it. Role, route and skills therefore stay
separate: the route is model/effort, the skills come with the role. The
`tenth-man` role is for deliberate adversarial challenge, not routine review;
`research-decide` is the one workflow that runs it as a standing step.

### The army

Twenty-one roles. [`roles/manifest.json`](roles/manifest.json) is the one place
that records each role's mode, what it may change, the final block it can end
with and the roles it may call; `bin/fm-workflow check` validates it against the
role files and the workflows. Every role body has the same contract: working
shape, definition of done, evidence, what to refuse, what to do when it cannot
finish, sub-agents, final report. A role whose output a workflow step consumes
ends with one machine-read fenced block (`verdict`, `result` or `risk`).
Only `lead`, `planner`, `finding-verifier` and `improver` call sub-agents (OMP's
native bounded `task` helper, [policy §6](firstmate/primary-policy.md#6-orchestration-boundary));
every role they call calls nobody, so nothing recurses beyond one level. Project
instructions outrank every role and skill.

| Role | Skills | Why those skills |
| --- | --- | --- |
| `senior-fullstack` | test-driven-development, ponytail, verification-before-completion | red before green with the failing output shown, the smallest change, evidence before "done" |
| `test-engineer` | test-driven-development, principle-test-behavior-not-implementation | the TDD skill's test-craft companion is the bar for regression, property and differential tests; the two-edit test rejects vacuous and implementation-pinned tests |
| `refactorist` | code-simplification, verification-before-completion, karpathy-guidelines | behavior-preserving change shown by the same checks before and after |
| `perf-engineer` | performance-optimization, benchmark-checklist | neutral is a revert and every attempt is ledgered; every measured number is vetted (limiter, tuning, limits, errors, repeatability, relevance, did the work happen) |
| `technical-writer` | documentation-and-adrs | scoped documentation and ADRs of settled decisions |
| `chore` | none | mechanical work needs no method |
| `lead` | planning-and-task-breakdown, verification-before-completion | ordered, verifiable slices (the skill's plan files and human checkpoints overridden); the parent keeps verification |
| `planner` | spec-driven-development, planning-and-task-breakdown, be-ambitious | spec first, then ordered tasks; the outcome beyond the task and an outside judge, under a scope guard |
| `architecture` | api-and-interface-design, codebase-design, be-ambitious | contract design; deep-module vocabulary (deletion test, seams, leverage); depth and an outside judge per option |
| `researcher` | source-driven-development, be-ambitious | primary-source hierarchy, deep-link citations, UNVERIFIED instead of hedging; name missing access, never fake it |
| `scout` | none | facts only: ambition and judgment would break its contract |
| `debugger` | systematic-debugging | root-cause discipline; the red-capable-reproduction gate and hypothesis rules are distilled into the body |
| `risk-classifier` | none | reads a diff; the blast-radius evidence ladder is distilled into the body |
| `qa` | verification-before-completion | claims need command output; end-to-end, property and differential checks are in the body |
| `ui-qa` | verification-before-completion | the same evidence rule; browser-testing guidance is distilled so no machine's browser tool is hardcoded |
| `code-reviewer` | code-review-and-quality, ponytail-review, karpathy-guidelines | multi-axis review of a diff; the Anthropic severities and drop rules in the body outrank the skills' templates |
| `finding-verifier` | verification-before-completion | a finding is kept only if a re-run shows the failure; interrogate and doubt-driven rules are distilled |
| `security-engineer` | security-and-hardening, verification-before-completion | threat model and sensitive-surface checklist; verified versus suspected |
| `release-engineer` | verification-before-completion | readiness claims need evidence; rollback and flag guidance from shipping-and-launch is distilled |
| `tenth-man` | none | adversarial challenge; doubt-driven rules and the outside-judge rule are distilled |
| `improver` | retro | turns a recorded session into proposals by category; its present-to-the-user step becomes proposals in a PR |

Pinned for this (seven new pins, all MIT, each read in full at the pinned
commit, none tracked by branch; see [`skills/external.lock`](skills/external.lock)):
performance-optimization, source-driven-development (addyosmani/agent-skills);
benchmark-checklist, principle-test-behavior-not-implementation (cursor/plugins
pstack); retro, codebase-design (mattpocock/skills); be-ambitious
(robonuggets/be-ambitious). be-ambitious is attached only where the outcome,
standard or perspectives of a deliverable change its quality (planner,
architecture, researcher) and always under a guard in the role body: the brief's
scope and acceptance are the ceiling, higher rungs are reported as "Proposed
beyond brief", and its ask-first steps become open questions for the
orchestrator. Distilled into role bodies instead of installed, because they are
interactive, spawn their own agents, overlap an installed skill or are too long
for their payoff: incremental-implementation, debugging-and-error-recovery,
diagnosing-bugs, doubt-driven-development, interview-me, shipping-and-launch,
browser-testing-with-devtools, constraint-driven-development, tdd, to-spec,
to-tickets, grilling, implement-spec, code-review, research, writing-for-agents,
blast-radius, interrogate, correct, reflect, architect and the pstack
principle-* skills. Rejected: addyosmani's test-driven-development (the same
installed name as the pinned superpowers skill), idea-refine,
ci-cd-and-automation, observability-and-instrumentation; arena, swarm, recall,
show-me-your-work, sharpen (parallel agents, Cursor-only infrastructure or a
human prompt-rewriter); triage, wayfinder, improve-codebase-architecture,
domain-modeling, prototype, handoff, grill-me, grill-with-docs, implement
(issue-tracker or HTML-report machinery, human interviews, or trivial).

### Workflows

Every non-trivial code-changing task runs a workflow
([primary policy §8](firstmate/primary-policy.md#8-workflows)).
`bin/fm-workflow select <kind> --delivery <mode>` resolves the task's kind
from the closed table in [`workflows/selection.json`](workflows/selection.json)
to a workflow, or names the one exception that applies: a trivial chore, a pure
question or diagnosis, or an explicit captain choice of none (a
documentation-only task changes no code and is outside the rule). When `no-mistakes`
is the selected delivery path it owns review and testing, so the forced
workflow is `delegated-build` (implement, then deliver through `no-mistakes`),
never a second reviewer on top of it.

| Workflow | For |
| --- | --- |
| [`build-test-review`](workflows/build-test-review.json) | a code change with a clear requirement |
| [`plan-build-test-review`](workflows/plan-build-test-review.json) | the same, with an ambiguous or oversized requirement: plan first |
| [`bug-fix`](workflows/bug-fix.json) | diagnose, failing regression test by another worker, fix without touching it |
| [`refactor`](workflows/refactor.json) | one behavior-preserving change shown by the same checks before and after |
| [`ui-build-verify-review`](workflows/ui-build-verify-review.json) | a browser-visible change: real-browser verification before review |
| [`research-decide`](workflows/research-decide.json) | research, options with one recommendation, a challenge, a recorded decision |
| [`delegated-build`](workflows/delegated-build.json) | any code-changing kind when `no-mistakes` is the delivery path |

The code-changing workflows apply Anthropic's
[code review](https://claude.dev/blog/solving-code-review-at-anthropic/) and
[verification](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification/)
practice: the implementer shows command output before anyone reviews; the
change is classified by risk (tier set by the diff, not the author) and QA runs
it; a fresh-context reviewer's findings are verified by a second worker before
they go back; style-only findings are dropped; severities are BLOCKER, IMPORTANT,
OPTIONAL (a nit) and PRE-EXISTING (never the author's fault); every finding is
answered fixed or rejected with a reason and the class of bug is flagged;
re-reviews read only the delta; rounds cap at 3 and then the author steps back;
a security review blocks when the change touches a sensitive surface; required
human approvals scale with the tier and are the captain's to give (official
merge authority, including `yolo`, still governs the merge, and a high tier
escalates even under `yolo`); no agent verdict replaces one; a pass is
valid only for the commit it ran on; gates start in observe mode; and any step
can end with an early `change-direction` (reshape, close or escalate) instead of
grinding on.

A workflow is a JSON file validated by
[`workflows/workflow.schema.json`](workflows/workflow.schema.json): named steps
bound to role aliases, an input contract, an output contract (`report`,
`result`, `verdict` or `risk`), a transition per outcome, conditional
transitions on the risk classification and per-loop `maxIterations` with
`onExhausted`. JSON because the repository already uses `jq` and JSON, so no
runtime, parser or dependency is added.
[`bin/fm-workflow`](bin/fm-workflow) (bash and `jq`) is the engine:

| Command | Purpose |
| --- | --- |
| `fm-workflow list` | Each workflow with its `when` guidance |
| `fm-workflow select [<kind>] (--delivery <mode> \| --none <why>)` | The workflow a kind of task must run, or its exception; `--delivery` is required where the delivery path decides the workflow; no kind prints the closed table |
| `fm-workflow validate <workflow\|file>` | Schema, roles exist and can produce each step's output, every outcome routed, every step reachable, every cycle passes a limited loop |
| `fm-workflow check` | The whole army: workflows validate, the selection table resolves, the manifest matches the roles, the call graph has one level, every role is reachable or documented ad hoc |
| `fm-workflow next <workflow> <state-file> [--task t] [--role alias=role] [--spec] [--report f] [--outcome o] [--decide c --reason r]` | The current step with its exact role handoff, inputs and loop counters; with a result flag, records it and takes the transition; `--role` swaps the agent bound to one alias for this task, at start only |
| `fm-workflow verdict\|result\|risk <report>` | Strict parse of a report's final fenced block; anything else is a FAIL (verdict) or invalid |
| `fm-workflow trace <state-file> [captured-block]` | The `Workflow:` trace line derived from the state file |

The engine launches nothing: the Captain launches each step's worker as it
does any worker. State is one JSON file per task in the task's data folder,
never in a repository; the retro log sits beside it.

### Self-improvement

The engine appends a structured record for every finding, confirmation, dropped
finding, answer, gate result, round cap, escalation, change of direction and
completion to `retro.jsonl` in the task's data folder, outside every project
repository. [`bin/fm-retro`](bin/fm-retro) (bash and `jq`; no service or
network) records what the engine cannot see (a reverted PR), aggregates
recurring finding classes per role, rounds-to-pass, escalation rate and noise
rate, and prints PROPOSALS only (`report`, `propose`). Proposals are applied
solely through a normal PR by a worker and a human approval, never
automatically and never by editing a role from inside a running task; the
`improver` role writes them up. `propose` enforces the two-case minimum; the
diff-readable trigger, the three skeptics that must fail to disprove a rule and
the start in observe mode are the improver's checklist, not tooling.
[`REVIEW.md`](REVIEW.md) holds this repository's diff-triggered
checklist, read from the base branch by the risk classifier, QA and reviewer.
`tests/evals.sh` scores each role or workflow change offline against fixtures of
past failure patterns (a fixed test set separate from a tuning set, clean
controls against over-flagging, raw, verified and final recall scored apart).

### Bounded internal delegation

Only FirstMate owns macro orchestration. OMP's native bounded `task` helpers may
work inside the same parent task/project/worktree and authority; the parent
retains verification and completion responsibility. Pi has no bundled equivalent.
Which role may call which is fixed in [`roles/manifest.json`](roles/manifest.json)
(four roles call sub-agents; everything they call calls nobody) and checked by
`bin/fm-workflow check`. [Policy §6](firstmate/primary-policy.md#6-orchestration-boundary)
owns this boundary; [`tests/worker-context.sh`](tests/worker-context.sh) validates
fixture reports against it.

### Completion evidence limits

Context, roles, role skills and passing fixture reports do not
prove native adoption, read order, application, sandboxing or task completion.
Workers report actual commands, observed outcomes and unverified limits;
browser-visible changes need relevant real-flow evidence.

The selected official FirstMate delivery path owns review, fixes and publication.
This configuration adds no reviewer of its own except the workflows of
[primary policy §8](firstmate/primary-policy.md#8-workflows): on direct-PR and
local-only they are the captain's standing explicit request for their QA,
review, verification, security and ship steps; on `no-mistakes` they add no
reviewer. No workflow verdict is a trusted completion gate or replaces a
required human approval. An explicitly requested separate review is scoped and
read-only; no selection grants publication authority.
See [primary policy §7](firstmate/primary-policy.md#7-completion).

## Machine-local state

| Location | Purpose |
| --- | --- |
| This standalone checkout | Tracked policy, routing, roles, skills and launchers |
| `FIRSTMATE_ROOT` (default `~/Developer/tools/firstmate`) | Official FirstMate distribution checkout |
| `FM_HOME` (default `~/.firstmate`) | Project registry, preferences, task/runtime/session state and local data |
| `~/.config/firstmate-config/env` | Machine-local path resolution |
| `~/.local/share/firstmate-config/skills-src` | Pinned external skill checkouts |

Do not commit credentials, host paths, project knowledge or runtime data here.
Project instructions outrank global defaults.

## Tests

Synthetic only: a throwaway `HOME`, private local Git remotes, and inert
`pi`/`omp`/`herdr` stubs. No network, real harness or real Herdr is used.

```sh
bash tests/install-launch.sh
bash tests/update.sh
bash tests/standalone-contract.sh
bash tests/roles.sh          # role lint, structure, skills inventory, handoff expansion, policy text, install --verify
bash tests/workflows.sh      # schema, block parsers, engine sequences, forcing rule, army check, retro records
bash tests/retro.sh          # bin/fm-retro: record, report, propose, eval
bash tests/evals.sh          # failure-pattern evals, replay baseline, the self-improvement loop on a fixture
```

`tests/routing-trace.sh` also contains a real spawn seam;
`tests/worker-context.sh` includes native loader/documentation probes. Inspect
their headers before execution; they are not part of the synthetic-only
commands above. Linux/Omarchy adoption requires separate evidence.

Role-only delegation is proven in three layers:

| Layer | Command | What it proves |
| --- | --- | --- |
| Automation | `bash tests/roles.sh` | Every role parses and has the contract headings; `autoloadSkills` resolve, are unique and within budget and equal the README table; each role's sub-agent section names exactly the roles the manifest lets it call; every pin is a 40-hex commit; the handoff names the role and exactly its skills; the Captain-side docs hold no skill-selection instruction |
| End to end | `bash tests/roles-e2e.sh` | Per role, the real `fm-brief.sh` and `fm-spawn.sh` deliver a first input with the role path and exactly its skill paths (SKIPs without tmux/treehouse/FirstMate) |
| Live (opt-in) | `FM_ROLE_LIVE=1 bash tests/roles-live.sh [case...]` | A real model (default `anthropic/claude-sonnet-5-5` medium via `omp`, your existing login used in place, nothing copied) reads the skill and shows the skill-only behaviour in a planted problem, and does not without the skill. Two kinds of case: `tests/live/<role>.sh` / `mixed-*.sh` use the real skills; `mech-*.sh` / `mixed-mech-*.sh` use fixture-only roles and skills with an unguessable requirement, proving autoload, read and apply independent of the real skills' text. No cost cap by default (`FM_ROLE_LIVE_BUDGET` / `FM_ROLE_LIVE_RUN_CAP` are optional); a running tally and the transcripts go to git-ignored `tests/live-artifacts/` |

`bash tests/roles-live.sh` without the opt-in runs only its offline self-test:
the harness plumbing and every live case's grader against canned good and bad
workers. The live layer is one run per case plus its control: evidence, not a
guarantee. A real skill whose advice a strong model already follows cannot
discriminate (its control passes); the mechanism cases are the unambiguous
proof that a role's autoloaded skill is read and applied.

Workflows are proven in the same three layers:

| Layer | Command | What it proves |
| --- | --- | --- |
| Automation | `bash tests/workflows.sh` | Every definition validates and each defect (unknown role, a role that cannot produce the step's output, unreachable step, missing `onExhausted`, unrouted outcome, unlimited cycle, bad alternatives, ...) is rejected; the verdict, result and risk parsers are strict; the engine on scripted outcomes: straight through, QA failing and the round cap with the step-back, findings verified before they go back, refuted findings, change of direction (reshape, close, escalate), malformed blocks, security routing by risk tier, gates in observe and enforce mode, and every workflow end to end; handoffs are `bin/fm-role-handoff`'s; retro records are appended; `fm-workflow check` and `select` prove the call graph, the manifest, reachability and that every non-trivial code-changing kind resolves to a workflow under every delivery mode |
| End to end | `bash tests/workflows-e2e.sh` | The two main workflows driven through the real `fm-brief.sh` and `fm-spawn.sh` with a fake `omp`: each launched worker's first input carries the step's role handoff verbatim and exactly the previous verdict's feedback (SKIPs without tmux/treehouse/FirstMate) |
| Live (opt-in) | `FM_WORKFLOW_LIVE=1 bash tests/workflows-live.sh [case...]` | Real workers (same model, login and artifact rules as the roles live layer; `FM_WORKFLOW_LIVE_*` knobs) on fixture problems that force the loops: QA must fail a change that only a hidden acceptance kit catches and the implementer fixes it from QA's feedback; a flaw only the reviewer finds goes back, through the verifier, to the implementer; an ambiguous requirement is settled by the planner's plan, which every later step receives. A control run of the same step without the forcing input must not produce the fix. A thin driver plays the Captain mechanically, so this tests roles, verdicts, handoff and loop mechanics, not the Captain model's choice of workflow |

`bash tests/workflows-live.sh` without the opt-in runs only its offline
self-test: the whole driver against canned workers, including harness
mutations (an implementer that ignores feedback must end in an escalation, one
that is right at once must be flagged as an unforced loop).

### Live layer (opt-in, real models)

Everything above runs offline: fixtures, stand-in workers and fake `omp`
binaries. The live layer runs real workers (`omp`, default
`anthropic/claude-sonnet-5-5` at medium thinking, your existing login used in
place) in throwaway fixture repositories outside the tracked tree. Each
scenario is judged by deterministic code on the output - a hidden kit, the
engine's state, the fixture's history, the transcript, a parsed final block -
never by the worker. Every suite runs its offline self-test first, SKIPs (never
PASSes) without its opt-in variable, and writes transcripts and a results table
to git-ignored `tests/live-artifacts/`. The worker sees a copy of the checkout
without `tests/`, so it cannot read the judge. To run with exactly the skills
`install.sh` would link (including pins this machine has not fetched yet), build
the skill source first: `bash tests/live-lib/pinned-skills.sh /tmp/pinned`, then
set the suite's `..._LIVE_SKILL_SRC=/tmp/pinned/skills`.

| Suite | Command | What it covers |
| --- | --- | --- |
| Skills read and applied | `FM_ROLE_LIVE=1 bash tests/roles-live.sh [case...]` | The cases in `tests/live/`. Each case is in one of three states, named in its file: skill-exclusive (the no-skill control fails), body-carries (`CASE_BODY_PHRASE`: the role body states the rule, checked against the ROLE.md offline), or baseline-informational (`CASE_CONTROL_INFORMATIONAL`: the control passes on the model's own baseline, so the case proves the skill was read and the outcome is right, not that the skill is needed) |
| Role contracts | `FM_CONTRACT_LIVE=1 bash tests/roles-contract-live.sh [case...]` | The roles this army added, one or two scenarios each (`tests/live-contract/`): lead (delegates to roles in its `spawns`, integrates, verifies), perf-engineer (measures first, an independent bench re-measures), test-engineer (red on the bug, green on two different reference implementations), ui-qa (a real browser through `chrome-devtools-axi`, a seeded defect found and a clean app passed), risk-classifier (rules read from the base branch, a weakened rule ignored), release-engineer (a stale gate fails, fresh gates pass), finding-verifier (confirms the real defect, drops the false, style-only and duplicate ones), researcher (citations verifiable in the fixture, the unfound question UNVERIFIED), improver (proposes exactly the recurring classes, applies nothing). The runner gives the worker exactly the tools its ROLE.md lists |
| Workflows | `FM_WORKFLOW_LIVE=1 bash tests/workflows-live.sh [case...]` | `plan`, `qa-loop`, `review-loop`, `bug-fix` (a symptom fix cannot satisfy the hidden two-order scenario; the regression test is red at its own commit and untouched by the fix), `refactor`, `delegated-build`, `change-direction`, `research-decide` (passages quoted verbatim from the vendor docs, the unanswerable question UNVERIFIED, at most three options), `security-route` (the security step finds a sensitive-file exposure that only the deployment fact reveals; verify-security confirms it and the implementer fixes it), `ui-build-verify-review` (the service the stale docs describe wrongly answers 415: only the real-browser step sees it; the judge drives a real browser, so the case SKIPs without `chrome-devtools-axi`) and `round-cap` (the fourth QA FAIL becomes the step-back and an escalation, never a fourth round). The QA kit exists on disk only while QA runs it, and QA is told never to write its path in a report; a non-QA worker that goes looking for it fails the case |
| Captain | `FM_CAPTAIN_LIVE=1 bash tests/captain-live.sh [scenario...]` | A real model plays the Captain with this `captain.md`, the policy and the official `AGENTS.md`; worker launching is stubbed. Judged from the ordered invocation log: `fm-workflow select` before the first launch, the exceptions taken, `delegated-build` under no-mistakes, the engine's `next --spec` pasted unchanged into the brief. Each run has its own `TMPDIR`, so several invocations may run at once; a run whose Captain used a fixed `/tmp` path is flagged in `results.md`. `FM_CAPTAIN_LIVE_CONTROL=1` is the negative control (the rule and every paragraph naming `fm-workflow` removed from the Captain's context), informational only |
| Retro | `bash tests/retro-live.sh` | `fm-retro record`, `report` and `propose` over the retro logs real workflow runs left in `tests/live-artifacts/`, compared with an independent oracle (SKIPs when there is none) |

What the live layer does not prove, and what is known to be unfinished:

- One model (Sonnet 5.5) and a few runs per scenario: evidence, not a guarantee.
  Several judges were loosened after a live run showed a correct worker failing
  them; each such change is in the PR description, and each has a registered
  bad-worker variant (`case_variants` in the case file) that the relaxed judge
  still rejects, run by the offline self-test with the reason it must give.
  `finding-verifier-helper` runs the verifier again with the skeptic helpers
  asked for in the brief.
- `security-route` (a sensitive-file exposure only the security step, told the
  deployment fact, finds) needed its case fixed before it was stable: a live run
  ended `change-direction` because the verified finding contradicted the ticket's
  "any file under data/", so the security step and the verifier now state the
  Captain's policy in every finding.
- The Captain suite proves the standing rule is followed with stubbed launches,
  not the production fleet; four of its eight scenarios were not stable, mostly
  on the Captain pasting the engine's spec incompletely.
- Every workflow case passed three consecutive live runs on the final driver
  (one model, Sonnet 5.5): evidence, not a guarantee.
