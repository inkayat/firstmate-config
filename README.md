# firstmate-config

Private configuration for a stock FirstMate installation. Nothing here forks or
patches FirstMate: the official checkout stays byte-identical to upstream and
everything below reaches it through mechanisms upstream already exposes -
`FM_HOME`, `config/`, `data/captain.md`, `config/crew-dispatch.json`, Pi launch
arguments, and the normal global Agent Skills directory.

```text
Pi Captain -> FirstMate -> Herdr -> Pi / OMP
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
| `firstmate/primary-policy.md` | the captain's operating policy | read by the captain, path named from `data/captain.md` |
| `firstmate/captain.md` | first-run template for the captain's own notes | copied to `$FM_HOME/data/captain.md` **only when absent** |
| `firstmate/crew-dispatch.json` | which harness takes which kind of task | symlinked to `$FM_HOME/config/crew-dispatch.json` |
| `firstmate/captain-startup-models.tsv` | ordered Pi/FirstMate Captain startup model candidates | read by `bin/fm`, never installed as Pi's global default |
| `firstmate/fm-captain-lib.sh` | the one authoritative Captain model availability path | sourced by both `bin/fm` and `bin/fm-doctor` |
| `firstmate/stack-manifest.tsv` | the single source of truth for stack compatibility: official FirstMate repo/validated commit, Pi/OMP/Herdr min and tested versions | read by `install.sh` and `bin/fm-doctor` |
| `firstmate/fm-stack-manifest.sh` | the one parsing/comparison owner for `stack-manifest.tsv` | sourced by `install.sh`, `bin/fm-doctor`, and `bin/fm-version` |
| `firstmate/fm-verify-provenance.sh` | the one deterministic worktree-provenance classifier for verification evidence | sourced by `tests/worker-context.sh`; the shared worker skill `verification-provenance` documents its contract |
| `roles/*/ROLE.md` | generic role definitions quoted into worker briefs | read by the captain |
| `skills/*/SKILL.md` | our own global skills | symlinked into `~/.agents/skills/` |
| `skills/external.lock` | external skill packs, pinned by commit | cloned to a machine-local cache, symlinked into `~/.agents/skills/` |
| `install.sh` | idempotent installer | - |
| `tests/smoke.sh` | acceptance smoke | - |
| `tests/model-selection.sh` | captain startup model selection acceptance | - |
| `tests/multi-project-captain.sh` | multi-project resolution/isolation/routing acceptance | - |
| `tests/doctor.sh` | `fm doctor` acceptance: statuses, exit codes, JSON schema | - |
| `tests/stack-manifest.sh` | stack compatibility manifest acceptance: `install.sh`/`fm-doctor`/`fm-version` sharing one baseline | - |
| `tests/worker-context.sh` | delegated-worker context/skill-class acceptance, plus a `prepare`/`handoff`/`validate` CLI for a real live fixture run | - |

## Install

```sh
git clone https://github.com/inkayat/firstmate-config
cd firstmate-config
./install.sh
```

Then, from any directory:

```sh
fm
```

Rerunning `install.sh` is a reconcile, not a reinstall: it repairs symlinks,
refreshes pinned skills, and leaves anything you have edited by hand alone.
A missing official FirstMate checkout is cloned from `firstmate/stack-manifest.tsv`'s
`firstmate_repo` and pinned to its `firstmate_validated_commit`; an
already-present checkout is never touched, only its relationship to that
validated commit is reported (see `fm doctor` "Stack compatibility" below).

Verify an installation at any time:

```sh
tests/smoke.sh                     # launcher, install state, skills, herdr
tests/smoke.sh --live              # the same, plus a captain that is currently running
tests/multi-project-captain.sh     # project resolution, isolation, and routing
tests/doctor.sh                    # fm doctor: statuses, exit codes, JSON schema
tests/stack-manifest.sh            # stack compatibility manifest: install.sh/fm-doctor/fm-version
tests/worker-context.sh            # delegated-worker context/skill-class handoff fixtures
```

## fm version

```sh
fm version
fm version --json
```

Fast, read-only identity facts for bug reports: firstmate-config tag/commit/state, official FirstMate path/commit/state, Pi/OMP/Herdr versions, the validated FirstMate baseline commit from `firstmate/stack-manifest.tsv`, `FM_HOME`, platform, and architecture. Optional component versions are `unknown` when unavailable; this stays a compact identity report - compatibility verdicts (PASS/WARNING/FAIL) live only in `fm doctor`.

JSON schema (`--json`, `schema_version: 2`) has `firstmate_config`, `firstmate`, `components`, `stack_manifest` (`schema_version` and `firstmate_validated_commit`, both read from `firstmate/stack-manifest.tsv` - never a duplicated literal), `fm_home`, `platform`, and `architecture`.

## fm doctor

```sh
fm doctor             # human-readable architecture diagnostics
fm doctor --json       # the same report as machine-readable JSON
```

Read-only, cross-platform diagnostics for the whole
`Pi Captain -> FirstMate -> Herdr -> Pi/OMP` architecture. `fm doctor` never
installs, repairs, or restarts anything, never modifies `FM_HOME` or a
project, never touches routing or auth, and never makes a paid or live model
inference call - every availability probe it runs is the same cheap,
non-billable kind `bin/fm` already uses at startup (`pi auth check`, `pi
--list-models`, `pi list`, `claude auth status`, `herdr status --json`, `omp
models --json`), from the one authoritative Captain path both `bin/fm` and
`bin/fm-doctor` share: `firstmate/fm-captain-lib.sh`. Every Git probe it
makes (firstmate-config's and the official checkout's own version/commit/
dirty state) runs with `GIT_OPTIONAL_LOCKS=0`, so a diagnostic run never
writes an index refresh or ref lock into a repository it merely inspects.

It reports, in order: SYSTEM (this repository's and the official checkout's
path/version/commit/dirty state, whether `firstmate/stack-manifest.tsv`
loaded, the official checkout's relationship to that manifest's validated
commit, `FM_HOME`, OS, cwd, current Git project
root), LAUNCHER/PATH (every `fm` discoverable on `PATH`, precedence against
the one this repository installs, and the executable a plain `fm` currently
resolves to), CAPTAIN (the configured startup model chain's per-candidate
availability, selection, and fallback reason), RUNTIME (Herdr installation,
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
own harness catalog: `pi --list-models` for a `pi` lane, `omp models --json`
for an `omp` lane, never one harness's detector standing in for the other's,
plus Fable/Qwen's intentionally `DEFERRED` status), ROLES and SKILLS
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
`Pi Captain -> FirstMate -> Herdr -> Pi/OMP`: the official FirstMate
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
is usable (a missing Pi primary extension, an empty model chain, or every
candidate `UNAVAILABLE`), the `herdr` CLI is missing, explicitly reports
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
`fm` currently resolves to), `captain`, `runtime` (including a `heartbeat`
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
candidate to Pi with `--model` and `--thinking` only for the FirstMate Captain
process it starts.
It does not write Pi's standalone default and it does not affect worker routing.

Fallback is availability-only and tri-state: `AVAILABLE` and `UNKNOWN`
candidates remain eligible, while only an authoritative `UNAVAILABLE` result is
skipped.
An exact catalog entry and supported effort establish the model path but do not
alone prove authentication; an unrecognized broker result stays `UNKNOWN`
rather than becoming a false negative.
For `pi-claude-code-provider`, Pi's `auth check` does not load extension
providers, so the launcher uses the provider's zero-inference `claude auth
status` preflight and confirms the package is installed.
It never starts a paid model turn merely to probe availability.
The launcher prints the preferred candidate, selected candidate, selected
availability state, and fallback reason when it did not use the preferred
candidate.

## Multi-project captain

One `fm` launch starts one project-neutral Captain session: Pi always runs
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
`firstmate/primary-policy.md` section 2 ("Before delegating") is where that
gap is closed: every delegated task's `## Firstmate spec` carries an
explicit, compact handoff - the resolved project/subtree, which worktree-
relative instruction file wins at each scope, the exact project-local and
selected shared-worker skill paths each paired with a read-and-apply
requirement, and a pre-work requirement to report a missing, unreadable, or
conflicting path rather than silently substituting a different scope. It
never pastes a file or skill body into the brief, and it always resolves
paths against the worker's own isolated task worktree, never the primary
checkout the task started from.

That handoff also carries a target-discovery checkpoint (section 2, step
6): the worker keeps a small resolved-scope list seeded from the handoff,
and whenever it - or any bounded internal helper - discovers or selects a
concrete file/subtree not already on that list, it must re-run this same
resolution for the new target, read and apply any newly applicable
project-local skill, and report the checkpoint before substantive
reading, editing, reviewing, testing, or reliance on that target. This
repeats on every later scope change (A -> B), and a helper's unsupported
claim that no nested instruction exists never substitutes for the
worker's own independent re-resolution.

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
tests/worker-context.sh validate <worker-report> [<worktree>]  # validate a report; self-reported provenance alone fails closed
tests/worker-context.sh validate-local <worker-report> <worktree> -- <command> [args...]  # rerun verification through the worktree-bound local provenance runner, then validate
tests/worker-context.sh internal-prepare <directory>        # write a disposable bounded-internal-delegation canary fixture INSIDE your own real task worktree (a native bounded subagent always shares the parent session's cwd), print the path
tests/worker-context.sh internal-handoff <directory> <worktree>  # print the read-only task text for a real bounded internal subagent to run against that fixture
tests/worker-context.sh scope-prepare <directory>           # build a persistent target-discovery fixture repo at <directory>/repo (root scope only, two nested subtrees), print its path
tests/worker-context.sh scope-handoff <repo-dir>            # print the open-ended handoff for that fixture - covered scope is the root only, no nested target is named up front
tests/worker-context.sh scope-validate <worker-report> [<worktree>]  # validate the target-discovery checkpoint for a report against that fixture
```

`prepare` builds the fixture once; `handoff` prints the paths/precedence/
required-actions text to hand a real delegated worker - every path bare
and worktree-relative, never the source/primary checkout's absolute path
(which does not exist from the worker's side, since its own isolated
worktree is created later by `fm-spawn`), with an explicit instruction to
verify `pwd -P` against `git rev-parse --show-toplevel` first. It also
never prints a canary body marker, so a worker that only echoes it back
cannot pass `validate`;
`validate` proves, from that worker's own report, the expected worktree,
root-override authority, absence of the markers it must shadow, nested-
scope application, the project skill's body-only marker applied before
migrations are touched, the shared skill's body-only marker applied, and
project-local-over-conflicting-shared-skill authority. The official-
internal-skill proof is positive evidence, never mere name-omission: the
worker must report a resolved path for the required project skill (under
its own worktree), a resolved path for the selected shared skill (under
the real global root, never the worktree), its own harness-native skill-
catalog source roots/count, and an explicit zero count of catalog entries
under the official FirstMate distro root - a report that merely never
mentions the forbidden skill name fails this check, it does not pass it
for free. `validate` also proves bounded-internal-delegation scope/context
evidence and fails closed on self-reported verification-provenance labels;
`validate-local` is the passing local path because it reruns the command in
the expected worktree (see "Bounded internal delegation" and "Verification
provenance" below). Both print one PASS/FAIL/SKIP line per proof.

`scope-prepare`/`scope-handoff`/`scope-validate` are the same interface for
the target-discovery checkpoint (section 2, step 6): the fixture's launch
scope names only the repository root, so `scope-handoff` never names
either nested subtree's instruction or skill path - discovering them is
the task. `scope-validate` requires a `TARGET_SCOPE_CHECK` report naming
the discovered path, the resolved instruction/skill paths it names, and
the nested instruction's and skill's body-only markers, all before the
target is substantively touched; a later, different target requires its
own separate checkpoint, and a bounded internal helper's unsupported "no
nested instruction" claim never substitutes for the worker's own
re-resolution. This is the exact false-confidence failure a Betao
validation exposed: an internal scout selected a nested file, the parent
read and edited it without resolving its nested instruction, then
incorrectly reported none existed.

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
applicable rather than forced to acquire one. `tests/worker-context.sh`'s
live `validate` path is extended to require positive evidence for this -
the helper's identity, model/effort, purpose, read-only-versus-mutating
behavior, project/worktree scope, and inherited-context evidence - recorded
from the harness's own existing session metadata, never a new telemetry
mechanism. That evidence must be backed by a real, disposable canary
fixture (`internal-prepare`/`internal-handoff`, since a native bounded
subagent always shares its parent session's cwd - there is no separate
workspace to plant a fixture in) that the real subagent actually reads:
self-reported labels alone, with no matching canary content in the
report, fail the check.

## Verification provenance

Fresh, passing output is necessary but not sufficient: it must also be tied
to the assigned task worktree, never a shared container or artifact bound
to a different checkout. The shared worker skill `verification-provenance`
and its one deterministic classifier, `firstmate/fm-verify-provenance.sh`
(sourced by `tests/worker-context.sh`), reject evidence tied to a different
checkout and mark worker self-reports that merely name the expected checkout
as uncertain rather than guess a pass. The supported accepting path today is
the worktree-bound local runner (`fm-verify-provenance.sh run-local` /
`tests/worker-context.sh validate-local`), which reruns the verification
command after `cd`ing to the assigned worktree. Container-bind and artifact
evidence remain fail-closed unless a future trusted inspector/build
attestation observes them; there is no hardcoded container name, mount path,
or CI system.

## Routing in v0.1

Every lane below was probed directly and then again through a real
FirstMate -> Herdr -> worker lifecycle before it was written into
`firstmate/crew-dispatch.json`. Effort is never negotiated downward.

| Work | Harness | Model | Effort |
| --- | --- | --- | --- |
| small, surgical, quick question | Pi | `openai-codex/gpt-5.3-codex-spark` | low |
| ordinary analysis and review | Pi | `openai-codex/gpt-5.5` | medium |
| difficult, broad architecture | Pi | `openai-codex/gpt-6-astra` | xhigh |
| tenth-man, adversarial review | Pi | a strong model the work under review did not use | xhigh |
| ordinary implementation, debugging, refactors, tests | omp | `anthropic/claude-sonnet-5` | medium or high |
| hard, large or high-risk implementation | omp | `anthropic/claude-opus-5` or `openai-codex/gpt-6-astra` | xhigh |

Opus and Astra are peers, chosen per task on shape, blast radius, reasoning
needs and provider headroom - not by keyword and not by difficulty alone.

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
