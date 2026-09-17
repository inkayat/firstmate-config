# firstmate-config

Private configuration for a stock FirstMate installation. Nothing here forks or
patches FirstMate: the official checkout stays byte-identical to upstream and
everything below reaches it through mechanisms upstream already exposes -
`FM_HOME`, `config/`, `data/captain.md`, `config/crew-dispatch.json`, native
harness launch arguments, and the normal global Agent Skills directory.

```text
fm -> OMP Captain -> FirstMate -> Herdr -> Pi / OMP workers
```

No OpenCode, OmO, Orca, second orchestrator, custom lifecycle framework, or
resolver daemon. FirstMate is the only orchestrator and owns every lifecycle
mechanism: fleet lock, watcher, heartbeat, wake queue, spawn, teardown.

## Layout

| Path | What it is | Where it lands |
| --- | --- | --- |
| `bin/fm` | the launcher: `cd anywhere && fm` | symlinked onto `PATH` |
| `bin/fm-doctor` | read-only architecture diagnostics: `fm doctor` / `fm doctor --json` | invoked by `bin/fm doctor` |
| `bin/fm-version` | compact read-only identity/version summary: `fm version` / `fm version --json` | invoked by `bin/fm version` |
| `bin/fm-update` | fast-forward-only self-update of this checkout: `fm update` | invoked by `bin/fm update` |
| `bin/ponytail-update` | safe local Ponytail update/test/reconcile workflow: `ponytail-update` | symlinked onto `PATH` |
| `firstmate/primary-policy.md` | the captain's operating policy | read by the captain, path named from `data/captain.md` |
| `firstmate/captain.md` | first-run template for the captain's own notes | copied to `$FM_HOME/data/captain.md` **only when absent** |
| `firstmate/crew-dispatch.json` | which harness takes which kind of task | symlinked to `$FM_HOME/config/crew-dispatch.json` |
| `firstmate/captain-startup-models.tsv` | ordered Captain startup model candidates | read by `bin/fm`, never installed as a harness's global default |
| `firstmate/fm-captain-lib.sh` | the one Captain harness selector and native availability owner | sourced by `bin/fm`, `bin/fm-doctor`, and `bin/fm-version` |
| `firstmate/stack-manifest.tsv` | the single source of truth for stack compatibility: official FirstMate repo/validated commit, Pi/OMP/Herdr min and tested versions | read by `install.sh` and `bin/fm-doctor` |
| `firstmate/fm-stack-manifest.sh` | the one parsing/comparison owner for `stack-manifest.tsv` | sourced by `install.sh`, `bin/fm-doctor`, and `bin/fm-version` |
| `roles/*/ROLE.md` | generic role definitions quoted into worker briefs | read by the captain |
| `skills/*/SKILL.md` | our own global skills | symlinked into `~/.agents/skills/` |
| `skills/external.lock` | external skill packs, pinned by commit | cloned to a machine-local cache, symlinked into `~/.agents/skills/` |
| `scripts/update-ponytail.sh` | intentional, reviewable Ponytail version bump: moves the pinned commit forward, never runs automatically, never commits/pushes/merges/tags | run manually, see "Updating Ponytail" below |
| `install.sh` | idempotent installer | - |
| `tests/smoke.sh` | acceptance smoke | - |
| `tests/captain-harness.sh` | default OMP / explicit Pi launch and diagnostic contracts | - |
| `tests/model-selection.sh` | captain startup model selection acceptance | - |
| `tests/multi-project-captain.sh` | multi-project resolution/isolation/routing acceptance | - |
| `tests/doctor.sh` | `fm doctor` acceptance: statuses, exit codes, JSON schema | - |
| `tests/routing-taxonomy.sh` | eleven-category dispatch taxonomy acceptance: pinned routes, collision disambiguation, fixtures, retired-model reference scan | - |
| `tests/stack-manifest.sh` | stack compatibility manifest acceptance: `install.sh`/`fm-doctor`/`fm-version` sharing one baseline | - |
| `tests/worker-context.sh` | delegated-worker context/skill-class acceptance, plus a `prepare`/`handoff`/`validate` CLI for a real live fixture run | - |
| `tests/update.sh` | `fm update` acceptance: up-to-date, fast-forward, dirty and diverged refusals | - |
| `tests/pi-ponytail-package.sh` | Pi Ponytail package reconciliation acceptance: separate pinned checkout, skills-filter and `defaultMode` structural merges, idempotency, drift | - |
| `tests/update-ponytail.sh` | `scripts/update-ponytail.sh` acceptance: stable-release selection, prerelease exclusion, `--ref`, ambiguity refusal, idempotent pin advance, never-commits proof | - |
| `tests/ponytail-update.sh` | `ponytail-update` acceptance: fast-forward, safety refusals, short-circuit, full workflow, failure stops, forbidden Git actions | - |

## Install

```sh
git clone https://github.com/inkayat/firstmate-config
cd firstmate-config
./install.sh
```

Later, on that machine or any other clone, `fm update` fast-forwards this
checkout to its remote tip. It refuses - changing nothing - when the checkout
has uncommitted changes or its branch has diverged; it never stashes, resets,
merges, or rebases. Re-run `./install.sh` after an update that changed the
installed layout.

Then, from any directory:

```sh
fm
ponytail-update
```

`fm` starts OMP directly from the official FirstMate checkout; Pi is not an
intermediate process. `fm --harness omp` makes that choice explicit.
`fm --harness pi` retains the previous Pi startup path as an explicit fallback.
Place the selector before diagnostics too: `fm --harness pi --print-command`,
`fm --harness pi doctor --json`, or `fm --harness pi version`.

OMP auto-discovers the official `.omp/extensions/fm-primary-omp-watch.ts` and
`.omp/extensions/fm-primary-turnend-guard.ts`. The launcher never copies them,
passes `-e`, or applies `.omp/fm-worker-overlay.yml`: that overlay is upstream's
unattended-worker posture, not Captain configuration. Pi alone retains its
trust-aware extension mode (`FM_PI_EXTENSIONS=auto|explicit|discover`).
Both paths scrub inherited harness identity markers. Only at the OMP exec
boundary, the launcher sets `FM_OMP_HARNESS=omp` and the stock
`FM_TIMEOUT_MECHANISM_OVERRIDE=bash`. FirstMate's native Bash timeout keeps the
deadline and process-group cleanup while removing the external `timeout` process
from its startup chain: genuine OMP is then eighth, rather than ninth, in the
stock detector's eight-process ancestry window. The marker alone cannot fix that
depth limit because its validation uses the same bound. This is a stock timeout
selection, not a shell-watcher fallback; the native OMP extensions still own
supervision. Pi's launch path sets neither variable.

Herdr and `FM_HOME` keep their existing roles, state, registries, and lifecycle
ownership. No global model, auth, or settings files are rewritten.
`FM_OMP_BIN` and `FM_PI_BIN` select executables,
not worker routing.

Rerunning `install.sh` is a reconcile, not a reinstall: it repairs symlinks,
refreshes pinned skills, and leaves anything you have edited by hand alone.
A missing official FirstMate checkout is cloned from `firstmate/stack-manifest.tsv`'s
`firstmate_repo` and pinned to its `firstmate_validated_commit`; an
already-present checkout is never touched, only its relationship to that
validated commit is reported (see `fm doctor` "Stack compatibility" below).

Verify an installation at any time:

```sh
tests/smoke.sh                     # launcher, install state, skills, herdr
tests/captain-harness.sh           # OMP default, explicit harnesses, native availability
tests/smoke.sh --live              # the same, plus a captain that is currently running
tests/multi-project-captain.sh     # project resolution, isolation, and routing
tests/doctor.sh                    # fm doctor: statuses, exit codes, JSON schema
tests/routing-taxonomy.sh          # eleven-category dispatch taxonomy: pinned routes, collisions, fixtures
tests/stack-manifest.sh            # stack compatibility manifest: install.sh/fm-doctor/fm-version
tests/worker-context.sh            # delegated-worker context/skill-class handoff fixtures
tests/update.sh                    # fm update: up-to-date, fast-forward, dirty/diverged refusal
tests/ponytail-update.sh           # ponytail-update: safe full workflow and failure boundaries
tests/pi-ponytail-package.sh       # Pi Ponytail package: separate pinned checkout, settings/config merge, drift
tests/update-ponytail.sh           # scripts/update-ponytail.sh: stable-release selection, --ref, ambiguity refusal
```

## Updating Ponytail

firstmate-config intentionally pins Ponytail (the shared `ponytail`/
`ponytail-review` skills and the Pi package's own separate checkout) to one
exact commit in `skills/external.lock`, for the same reason every other
external pin in this repository is a commit and not a branch: an unpinned
global skill or package changes the behavior of every project on every
machine without a diff. `install.sh` only ever reconciles machines to that
tracked pin; it never tracks or adopts upstream's latest commit itself.

**Normal convergence** (every machine, every day): `git pull` then
`./install.sh`. Nothing about Ponytail changes unless the pin itself changed
in this repository.

**Intentional upgrade** (deliberate, reviewed, occasional):

```sh
ponytail-update                    # fast-forward main, check, update, test, install, verify, and check again
git diff -- skills/external.lock   # review the prepared one-line pin change
git commit -m 'skills: bump ponytail pin' -- skills/external.lock
```

`ponytail-update` refuses a dirty tree, a branch other than `main`, and any
local history that cannot fast-forward to `origin/main`. If the tracked pin is
already current, it stops after the read-only check. It never commits, merges,
rebases, pushes, creates or deletes branches, or tags; a successful update
leaves `skills/external.lock` changed and uncommitted for review.

Then push/merge through the normal workflow, and on every other machine:
`git pull && ./install.sh`.

`scripts/update-ponytail.sh` never commits, merges, pushes, or tags - it only
edits the tracked lock file and refreshes this machine's local Ponytail
caches (the shared skill clone and the Pi package's own separate checkout)
to match, leaving a reviewable `git diff` for a human. Its default target is
never upstream's default-branch HEAD and never a bare tag name resolved
loosely: it discovers every stable release tag (`vX.Y.Z`, excluding
prerelease/beta/rc tags such as `v1.2.0-rc.1`), picks the highest by
semantic version, and resolves that exact tag to its exact commit SHA -
human intent is the release version, machine desired state is always the
SHA. If the highest version has tags pointing at different commits, or no
stable release tag exists at all, it refuses to guess and fails with an
actionable error instead of silently picking one. `--ref <tag-or-sha>`
targets an exact tag or a full commit SHA for deliberate testing - never a
branch name, so it cannot recreate automatic branch tracking through the
back door.

A manually updated Pi package checkout (for example from `pi update`) is
not itself authoritative: the next `./install.sh` run reconciles it back to
`skills/external.lock`'s tracked commit, exactly like any other managed
drift.

## fm version

```sh
fm version
fm version --json
```

Fast, read-only identity facts for bug reports: firstmate-config tag/commit/state, official FirstMate path/commit/state, selected Captain harness, Pi/OMP/Herdr versions, the validated FirstMate baseline commit from `firstmate/stack-manifest.tsv`, `FM_HOME`, platform, and architecture. Unavailable component versions are `unknown`; this stays a compact identity report - compatibility verdicts (PASS/WARNING/FAIL) live only in `fm doctor`.

JSON schema (`--json`, `schema_version: 2`) has `firstmate_config`, `firstmate`, `components`, `captain_harness`, `stack_manifest` (`schema_version` and `firstmate_validated_commit`, both read from `firstmate/stack-manifest.tsv` - never a duplicated literal), `fm_home`, `platform`, and `architecture`.

## fm doctor

```sh
fm doctor             # human-readable architecture diagnostics
fm doctor --json       # the same report as machine-readable JSON
```

Read-only, cross-platform diagnostics for the whole
`OMP Captain -> FirstMate -> Herdr -> Pi/OMP` architecture. `fm doctor` never
installs, repairs, or restarts anything, never modifies `FM_HOME` or a
project, never touches routing or auth, and never makes a paid or live model
inference call - every availability probe it runs is the same cheap,
non-billable kind `bin/fm` already uses at startup (`pi auth check`, `pi
--list-models`, `pi list`, `claude auth status`, `herdr status --json`, `omp
models --json --no-extensions`), from the one authoritative Captain path both
commands share: `firstmate/fm-captain-lib.sh`. Every Git probe it
makes (firstmate-config's and the official checkout's own version/commit/
dirty state) runs with `GIT_OPTIONAL_LOCKS=0`, so a diagnostic run never
writes an index refresh or ref lock into a repository it merely inspects.

It reports, in order: SYSTEM (this repository's and the official checkout's
path/version/commit/dirty state, whether `firstmate/stack-manifest.tsv`
loaded, the official checkout's relationship to that manifest's validated
commit, `FM_HOME`, OS, cwd, current Git project
root), LAUNCHER/PATH (every `fm` discoverable on `PATH`, precedence against
the one this repository installs, and the executable a plain `fm` currently
resolves to), CAPTAIN (selected harness, its executable and required extensions,
the startup chain's per-candidate availability, selection, and fallback reason), RUNTIME (Herdr installation,
client/server health and protocol compatibility, fleet lock, watcher,
heartbeat, wake queue, and task-record metadata - an in-flight count plus an
honest stale/dead classification (`NOT_APPLICABLE` with nothing in flight,
`UNKNOWN` otherwise: no safe bulk read-only classifier exists upstream
without duplicating FirstMate's own per-task lifecycle logic) - read-only,
via upstream's own `fm-lock.sh status` and `fm-supervision-lib.sh` when
available, `UNKNOWN` otherwise), HARNESSES (Pi/omp installation, version and
its compatibility against `firstmate/stack-manifest.tsv`'s tested/minimum
policy for that component, readable config), ROUTING (`crew-dispatch.json` structural validity via real
JSON parsing only - `jq`, then `python3`, whichever is actually on the
machine; with neither installed, validity is reported `UNKNOWN`, never a
false `PASS` and never a brace-balance or field-scan standing in for a real
parse - and cheap per-lane model availability discovered through each lane's
own harness catalog: `pi --list-models` for a `pi` lane, OMP's native
`models --json --no-extensions` for an `omp` lane, never one harness's detector
standing in for the other's, plus Fable/Qwen's intentionally `DEFERRED` status), ROLES and SKILLS
(readable role files; global skill installation count, missing entries,
broken links, unreadable `SKILL.md`), and PROJECTS (registered names from
FirstMate's own `data/projects.md` via `fm-project-mode.sh`, the confident current project
when the working directory is that project's own registered clone under
`$FM_HOME/projects` - matched by real canonical path, never by directory
basename, so an unrelated checkout that happens to share a project's
directory name is never misidentified - and, for that project only,
presence, never contents, of `AGENTS.override.md`, `AGENTS.md`, `CLAUDE.md`,
and project-local skill directories).

Every finding uses exactly one of: `PASS`, `WARNING`, `FAIL`, `DEFERRED`,
`BLOCKED_AUTH`, `BLOCKED_QUOTA`, `NOT_APPLICABLE`, `UNKNOWN`. A blocked status
is used only on reliable evidence; uncertainty is `UNKNOWN`, never a guessed
failure.

**Stack compatibility.** `firstmate/stack-manifest.tsv` is the single
source of truth for what "compatible" means across
`OMP Captain -> FirstMate -> Herdr -> Pi/OMP`: the official FirstMate
repo/validated commit, and a min/tested version policy per component
(`firstmate/fm-stack-manifest.sh` is the one parsing/comparison owner,
shared with `install.sh` and `fm version`). For each component:
an installed version exactly matching, or falling between, the policy's
minimum and tested bounds is `PASS`; a version newer than tested but still
meeting the minimum is `WARNING` (unvalidated, never an automatic `FAIL`);
a version below the minimum is `FAIL`; a version that cannot be parsed is
`UNKNOWN`, never a guessed verdict. The official FirstMate checkout's
commit is classified the same way from local Git-graph evidence alone
(`git merge-base --is-ancestor`, never a fetch): exactly the validated
commit is `PASS`; a descendant (newer) is `WARNING`; an ancestor (older) or
a diverged history is `FAIL`; a baseline commit absent from local history
is `UNKNOWN`. `harnesses.pi_version`, `harnesses.omp_version`,
`runtime.herdr_version`, and `firstmate.commit_compat` are advisory in the
`WARNING`/`UNKNOWN` case (they move the top-level `status` off `PASS` but
never the `exit_code`), but a hard-minimum `FAIL` (an installed version
below its component's minimum) or a known-incompatible `firstmate.commit_compat`
`FAIL` (the official checkout behind the validated baseline, or diverged
from it) is a genuine mandatory break - see "Exit codes" below. A missing or
invalid `stack.manifest` (unparseable, missing a required key, or failing
the loader's own value validation) is itself a mandatory break too: every
other stack-compatibility check depends on it having loaded.

**Exit codes.** `0` when the mandatory architecture is healthy, even with
`WARNING`, `DEFERRED`, or non-mandatory `BLOCKED_*`/`FAIL` findings present
(an unauthenticated routing lane, a missing role file, an unreadable skill -
none of these are mandatory). Nonzero only for a genuine mandatory break:
the official FirstMate checkout is missing or broken, or at a commit behind
the validated baseline or diverged from it (`firstmate.commit_compat`
`FAIL`), `crew-dispatch.json` or
the captain startup model chain is invalid, no configured Captain candidate
is usable (a missing selected harness executable or primary extension, an empty
model chain, or every candidate `UNAVAILABLE`), the `herdr` CLI is missing, explicitly reports
`compatible: false`, or its server is definitively stopped or unreachable
(`running: false`, or the status query itself fails outright with no
output), Pi, omp, or Herdr installed below its
`firstmate/stack-manifest.tsv` minimum version (`harnesses.pi_version`,
`harnesses.omp_version`, or `runtime.herdr_version` `FAIL`), or a different
`fm` on `PATH` shadows (resolves before)
the one this repository installs. The top-level JSON `status` field is the
worst individual check status found anywhere, which can differ from
`exit_code` - a real but non-mandatory problem can make `status` non-`PASS`
while `exit_code` stays `0`.

**JSON schema** (`--json`, `schema_version: 1`): a single object with
`schema_version`, `status`, `exit_code`, `timestamp`, `system` (including
`fm_home`), `firstmate` (this repository and the official checkout, each with
its own `commit`), `launcher` (including `resolved`, the executable a plain
`fm` resolves to, and `expected`, the one this repository installs), `captain`
(including `harness`), `runtime` (including a `heartbeat`
object distinct from `watcher`, and `task_metadata.staleness`:
`NOT_APPLICABLE`/`UNKNOWN`, never a guessed `PASS`/`FAIL`), `harnesses`,
`routing` (including
`parse_method` - `jq`, `python3`, or `none` when neither is installed -
and `valid: null` rather than `true`/`false` whenever `parse_method` is
`none`), `roles`, `skills`, `projects`, and `checks` - an array of
`{id, status, summary, detail?}` rows, one per finding named above. Rendering
this schema never depends on `jq`, `python3`, or any optional tool. Parsing
`crew-dispatch.json` itself requires a real parser, `jq` or `python3`,
whichever is actually installed; with neither present, `fm-doctor` reports
`routing.crew_dispatch_valid` as `UNKNOWN` rather than guessing.

## Captain startup model

`bin/fm` reads `firstmate/captain-startup-models.tsv` and passes the selected
exact candidate with `--model` and `--thinking` only to the Captain it starts.
The ordered chain remains Sol/high, `pi-claude-code-provider/sonnet`/high,
then Astra/xhigh. On installed OMP 18.1.21, Sol and Astra are native supported
selectors; the Pi-only Sonnet provider is absent and is skipped if reached.
It is never translated to a different Sonnet provider/model. Explicit Pi uses
the same chain with its original provider/auth preflights.

Fallback is availability-only and tri-state: `AVAILABLE` and `UNKNOWN`
candidates remain eligible; only authoritative `UNAVAILABLE` results are
skipped. OMP's native JSON listing filters to resolvable credentials or keyless
auth; it does not prove live credential validity or quota. The exact effort
must appear in the catalog's supported efforts, never silently clamped.
An absent candidate or unsupported effort is `UNAVAILABLE`; failed or
unparseable catalog output is `UNKNOWN`. JSON parsing uses `jq`, then
`python3`; with neither present it reports `UNKNOWN`.

The OMP catalog probe runs at the official cwd with `--no-extensions`: unlike
the actual Captain launch, a diagnostic must not execute extension factories
that write FirstMate load markers. This probe covers native/configured model
providers, not extension-registered providers. For Pi's
`pi-claude-code-provider`, `auth check` does not load extension providers,
so the shared detector uses zero-inference `claude auth status` and confirms
the package is installed. Neither path starts a paid turn to probe availability.
The launcher reports preferred and selected candidates, availability state,
and the fallback reason. Worker routing and standalone defaults are unchanged.

## Multi-project captain

One `fm` launch starts one project-neutral Captain session: its harness always runs
from the official checkout, never from wherever `fm` was invoked, so no
project's `AGENTS.md`, `CLAUDE.md`, or project-local skills are ever
preloaded as global authority. `firstmate/primary-policy.md` section 1
("Which project") resolves the target independently for every delegated
task, in order:

1. an explicit path or project name in the request
2. a name in FirstMate's own `data/projects.md` registry
   (`bin/fm-project-mode.sh`) - the only project database this configuration
   uses
3. the launch directory (`FM_FORK_ORIGIN_CWD`) as a default-project hint,
   used only when `bin/fm` reports `FM_FORK_ORIGIN_IS_PROJECT=true` for it

The captain asks when a project is still ambiguous after those three steps.
Launching `fm` from inside one project never binds the session to it or
blocks dispatch to another; concurrent tasks may target different projects,
each in its own isolated task worktree, with no local context crossing
between them. See `tests/multi-project-captain.sh` for the acceptance
evidence.

## Worker context and skill classes

Pi and OMP do not share one native discovery contract - their instruction
search roots, `AGENTS.override.md` support, and skill precedence differ.
`firstmate/primary-policy.md` section 2 ("Before delegating") addresses that
gap through an explicit, compact handoff in each task's `## Firstmate spec`:
the resolved project/subtree, which worktree-relative instruction file wins
at each scope, the exact project-local and selected shared-worker skill
paths with read-and-apply requirements, and a request to report a missing,
unreadable, or conflicting path rather than substitute a different scope.
The handoff never pastes a file or skill body into the brief, and it resolves
paths against the worker's own isolated task worktree, never the primary
checkout the task started from.

For open-ended discovery and later subtree changes, the worker and any
bounded internal helper are instructed to revisit the same resolution for
the new target and read newly applicable instructions and project-local
skills. The parent remains responsible for checking a helper's findings.
This is advisory context guidance, not a pre-tool barrier: this
configuration does not prevent early access or mechanically establish
instruction-read order, skill application, or successful task completion.

Three skill populations exist and are never interchangeable:

- **Official FirstMate internal skills** (`$FIRSTMATE_ROOT/.agents/skills/*`)
  are Captain/FirstMate-only. `metadata.internal: true` hides them from
  installers such as skills.sh, not from a harness's own native loader when
  it happens to run inside the official checkout - so they are never named
  as a selected shared worker skill in a brief, and `fm doctor`'s
  `skills.no_official_internal_leak` check reports, as static evidence,
  whether any shared skill this repository installs resolves into that tree.
- **firstmate-config shared worker skills** (`skills/*/SKILL.md` and the
  pinned packs in `skills/external.lock`) are symlinked into the normal
  shared root (`~/.agents/skills`) and are visible to both Pi and OMP by
  their native global-skill discovery.
- **Project-local skills** live under the project's own tracked directories
  (`.claude/skills`, `.agents/skills`, `.agent/skills`) inside the worktree
  the task actually runs in. A gitignored or uncommitted file from a
  different clone, or a relative link pointing outside the worktree, is not
  guaranteed to travel with it.

`tests/worker-context.sh` is the offline acceptance for this contract: a
disposable fixture repository with deliberately conflicting root/nested/
override instructions, a project-local skill fixture with a body-only
canary, a project-local-vs-shared-skill name collision, and an
official-internal-skill negative check, plus a real, zero-inference probe
of Pi's installed native resource loader against that fixture (pre-
implementation evidence, not a substitute for a live delegated Pi/OMP run).

It also exposes a small CLI - the externally usable prepare/validate
interface for Firstmate's own live fixture runs, independent of the
default offline suite:

```sh
tests/worker-context.sh                                   # default: run the offline suite
tests/worker-context.sh prepare <directory>                # build a persistent fixture repo at <directory>/repo, print its path
tests/worker-context.sh handoff <repo-dir>                  # print the compact, no-body Firstmate-spec handoff for that fixture
tests/worker-context.sh validate <worker-report> [<worktree>]  # check fixture-report evidence; not a task-completion gate
tests/worker-context.sh internal-prepare <directory>        # write a disposable bounded-internal-delegation canary fixture INSIDE your own real task worktree (a native bounded subagent always shares the parent session's cwd), print the path
tests/worker-context.sh internal-handoff <directory> <worktree>  # print the read-only task text for a real bounded internal subagent to run against that fixture
tests/worker-context.sh scope-prepare <directory>           # build a second, open-ended fixture repo at <directory>/repo: root-only launch scope plus two independent nested candidates
tests/worker-context.sh scope-handoff <repo-dir>             # print the open-ended handoff (task: "Find a small refactoring opportunity."); never names a candidate up front
tests/worker-context.sh scope-validate <worker-report> [<worktree>]  # advisory check: did the independently selected candidate's own instruction/skill get applied? never checks read order, tool order, or completion

`prepare` builds the fixture once; `handoff` prints the paths/precedence/
required-actions text to hand a real delegated worker - every path bare
and worktree-relative, never the source/primary checkout's absolute path
(which does not exist from the worker's side, since its own isolated
worktree is created later by `fm-spawn`), with an explicit instruction to
verify `pwd -P` against `git rev-parse --show-toplevel` first. It also
never prints a canary body marker, so echoing the handoff alone cannot
satisfy `validate`. The validator checks the report for the expected
worktree, root/nested authority, project/shared skill content and origins,
project-local-over-shared precedence, and bounded-helper context evidence.
Official-internal-skill isolation requires reported catalog source
roots/count and an explicit zero count under the official FirstMate distro
root, not just omission of a forbidden name. It prints one PASS/FAIL/SKIP
line per report check.

These are fixture-report checks, not independent observations of tool
access. A hand-written report can satisfy them; report order does not
prove instruction-read order, and a PASS does not authorize completion.
Live acceptance needs corroborating harness session evidence. The offline
suite exercises the handoff and report parser, plus the native-loader
checks above; it is not a runtime policy-enforcement test.

`scope-prepare`/`scope-handoff`/`scope-validate` cover the open-ended case:
a task that begins with only root-scope context and later requires
discovering a nested subtree's own instructions and project-local skill,
proven without naming that subtree up front. It proves discovery still
works and applied context remains available after a worker independently
selects a candidate - never that any particular read order, tool order,
or checkpoint was observed. An earlier version of this same fixture tried
to gate access on a strict before/after order and was abandoned; this one
deliberately does not restore that gating.

## Bounded internal delegation

Firstmate owns macro orchestration (project, role, harness, model/effort,
task lifecycle, worktree ownership); `firstmate/primary-policy.md` section 6
draws that line and the bounded exception to it. A harness may perform
bounded micro orchestration - a task-local scout, researcher, reviewer, or
helper - through its own native mechanism, never through Firstmate's
dispatch scripts, always inside the same parent task, project, and
worktree, and never as a substitute for the parent's own responsibility for
implementation, verification, and completion. omp's bundled `task` tool
(bounded by `task.maxRecursionDepth` and the tracked `.omp/fm-worker-
overlay.yml` posture overlay in the official checkout) is the currently
verified native mechanism; Pi ships no equivalent today (verified: its
bundled tool set has no task/agent/subagent tool), so it stays not
applicable rather than forced to acquire one. For live acceptance,
`tests/worker-context.sh validate` checks the reported helper identity,
purpose, read-only behavior, scope, and inherited context; the handoff also
requests its model/effort. Corroborate those claims with the harness's
existing session metadata, never a new telemetry mechanism.
`internal-prepare`/`internal-handoff` provide a disposable canary fixture
inside the parent's task worktree for a native, non-isolated helper.
The validator requires matching canary content in the report, but cannot
independently establish which process read it or whether it edited files.

## Completion evidence limits

Workers still report the commands they ran and what they observed, following
the project's verification requirements and selected shared skills such as
`verification-before-completion`. This configuration provides no trusted
verification runner, provenance attestation, or hard completion gate.
Fixture validation is not connected to a FirstMate completion hook.
Local commands, Docker and other execution environments remain available;
their output must be assessed against the actual task changes rather than
treated as automatically trusted evidence.

## Routing in v0.1

Every category below was probed directly and then again through a real
FirstMate -> Herdr -> worker lifecycle before it was written into
`firstmate/crew-dispatch.json`. Effort is never negotiated downward.

Every delegated task maps to exactly one of eleven dispatch categories -
a semantic-fit classification, not a size ladder - before harness, model,
and effort are chosen. `firstmate/crew-dispatch.json` is the authoritative
source: its fourteen `rules` entries (ten distinct `category` values;
EXPLORE, RESEARCH, IMPLEMENT-LARGE, and DEEP each span two more-specific
rules sharing the same category value) plus its `default` entry carry the
full natural-language `when`/`why` text this table compresses, including
the disambiguating rule for every pair of categories a task could
plausibly straddle. `firstmate/primary-policy.md` section 3 carries the
same table for the captain, plus the Claude-heavy/GPT-deliberate rationale,
the `use`-array-versus-separate-rule-versus-documented-override
distinction, the Opus-versus-Astra (execution versus reasoning)
distinction, role and scout/ship mapping, and model catalog adoption notes.

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

This is each category's active primary route only - not a primary/fallback
pair. FirstMate resolves a rule's `use` array through its own quota-array
procedure, so that array holds only genuinely interchangeable candidates
(QUICK's Haiku/Luna pair is the one case here). Genuine semantic
escalations - EXPLORE's harder-reasoning rule (Sonnet), RESEARCH's
Pi-tooling-better rule (`openai-codex/gpt-5.6-sol` on Pi), IMPLEMENT-LARGE's
sustained-execution rule (Opus), and DEEP's diagnosis-versus-implementation
split - are separate `rules` entries sharing the same category value
instead. `anthropic/claude-opus-5` for ARCHITECTURE, TENTH-MAN, and DEEP's
implementation rule is a documented availability/semantic override the
captain reaches for deliberately, never encoded in either rule's `use`
array alongside Astra: the two are not proven interchangeable.

Opus and Astra are never a shared candidate array; capacity on this fleet
is roughly Claude 20 against GPT 5 (about 4:1, not 20:1). Scout versus ship
is chosen per task, not fixed per category: EXPLORE, RESEARCH, REVIEW,
ARCHITECTURE, and TENTH-MAN are commonly scouts; QUICK, IMPLEMENT,
IMPLEMENT-LARGE, UI/BROWSER, and the implementation form of DEEP are
commonly ships.

`openai-codex/gpt-5.6-luna` is adopted as QUICK's genuinely-interchangeable
OMP array peer: OMP's native catalog reports its explicit per-level effort
support; Pi's own catalog reports only a bare `thinking: yes/no` column,
never a per-level enumeration, so Pi-side effort checks still rely on
FirstMate's existing, unchanged "any requested effort once `thinking` reads
yes" detector. `openai-codex/gpt-5.6-sol` remains the Captain-startup-only
candidate (see "Captain startup model" above) and is also RESEARCH's
Pi-tooling-better route and the named tenth-man-independence override -
the same model, two separate, independently matched uses, never confused
with each other. `openai-codex/gpt-5.5` is retired from worker routing
entirely: no active route, fallback, or lane anywhere in this
configuration uses it.

Deferred to a later release, and absent from this configuration: Pi with
`anthropic/claude-fable-5-1`, and the local Qwen/Ollama lane.

## Boundaries

- **Official FirstMate** lives at `$FIRSTMATE_ROOT` (default
  `~/Developer/tools/firstmate`) and is never modified. Update it with
  `git pull` in that checkout.
- **Machine-local state** lives in `$FM_HOME` (default `~/.firstmate`) and in
  `~/.config/firstmate-config/env`. Neither is tracked here. No credentials,
  provider endpoints, or host paths belong in this repository.
- **Project repositories** are never modified by anything here. A project's own
  `AGENTS.override.md`, `AGENTS.md`, `CLAUDE.md`, and project-local skills
  outrank every role and global skill this repository installs.
- **Stack compatibility** is tracked exclusively in `firstmate/stack-manifest.tsv`:
  the official FirstMate repo/validated commit and Pi/OMP/Herdr min/tested
  versions - nothing else. No auth, credentials, machine paths, Betao
  settings, project registry, Portail data, runtime task state, or Captain
  model routing belongs there; those stay owned by the mechanisms above.
