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
| `roles/*/ROLE.md` | generic role definitions quoted into worker briefs | read by the captain |
| `skills/*/SKILL.md` | our own global skills | symlinked into `~/.agents/skills/` |
| `skills/external.lock` | external skill packs, pinned by commit | cloned to a machine-local cache, symlinked into `~/.agents/skills/` |
| `install.sh` | idempotent installer | - |
| `tests/smoke.sh` | acceptance smoke | - |
| `tests/model-selection.sh` | captain startup model selection acceptance | - |
| `tests/multi-project-captain.sh` | multi-project resolution/isolation/routing acceptance | - |
| `tests/doctor.sh` | `fm doctor` acceptance: statuses, exit codes, JSON schema | - |
| `tests/stack-manifest.sh` | stack compatibility manifest acceptance: `install.sh`/`fm-doctor`/`fm-version` sharing one baseline | - |

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
from it) is a genuine mandatory break - see "Exit codes" below. `stack.manifest`
itself (whether the manifest loaded at all) stays advisory.

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
