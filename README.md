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
| `firstmate/primary-policy.md` | the captain's operating policy | read by the captain, path named from `data/captain.md` |
| `firstmate/captain.md` | first-run template for the captain's own notes | copied to `$FM_HOME/data/captain.md` **only when absent** |
| `firstmate/crew-dispatch.json` | which harness takes which kind of task | symlinked to `$FM_HOME/config/crew-dispatch.json` |
| `firstmate/captain-startup-models.tsv` | ordered Pi/FirstMate Captain startup model candidates | read by `bin/fm`, never installed as Pi's global default |
| `roles/*/ROLE.md` | generic role definitions quoted into worker briefs | read by the captain |
| `skills/*/SKILL.md` | our own global skills | symlinked into `~/.agents/skills/` |
| `skills/external.lock` | external skill packs, pinned by commit | cloned to a machine-local cache, symlinked into `~/.agents/skills/` |
| `install.sh` | idempotent installer | - |
| `tests/smoke.sh` | acceptance smoke | - |
| `tests/model-selection.sh` | captain startup model selection acceptance | - |
| `tests/multi-project-captain.sh` | multi-project resolution/isolation/routing acceptance | - |

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

Verify an installation at any time:

```sh
tests/smoke.sh                     # launcher, install state, skills, herdr
tests/smoke.sh --live              # the same, plus a captain that is currently running
tests/multi-project-captain.sh     # project resolution, isolation, and routing
```

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
