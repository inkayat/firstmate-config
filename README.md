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
tests/smoke.sh          # launcher, install state, skills, herdr
tests/smoke.sh --live   # the same, plus a captain that is currently running
```

## Captain startup model

`bin/fm` reads `firstmate/captain-startup-models.tsv` and passes the selected
candidate to Pi with `--model` and `--thinking` only for the FirstMate Captain
process it starts.
It does not write Pi's standalone default and it does not affect worker routing.

Fallback is availability-only: a candidate is skipped for missing auth,
unavailable model/provider, reliably reported quota exhaustion, or unsupported
configured effort.
The launcher prints the preferred candidate, selected candidate, and fallback
reason when it did not use the preferred candidate.

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
