# firstmate-config

A reproducible configuration layer for
[FirstMate](https://github.com/kunchenguid/firstmate), distributed through the
[inkayat fork](https://github.com/inkayat/firstmate) on `inkayat-main`: Captain
startup, worker routing, roles, shared skills, and machine-local setup.
Project instructions stay project-owned; credentials and operational state
stay outside this repository.

[Read the guide](https://inkayat.github.io/firstmate-config/) ·
[Releases](https://github.com/inkayat/firstmate-config/releases)

## Install

Use a persistent checkout: the installer links live commands and configuration
back to it. **Do not install from a disposable task worktree.**

Have `git`, `pi`, `omp`, and `herdr` on `PATH`; the installer checks them but
does not install them. `jq`, `treehouse`, `gh`, and `bun` are needed for full
fleet behavior. `python3` is needed for Pi Ponytail settings, board, and bot
commands. Configure provider authentication in the harness you intend to use;
the installer never stores credentials.

```sh
git clone https://github.com/inkayat/firstmate-config.git
cd firstmate-config
./install.sh
```

[`install.sh`](install.sh) creates the operational home, selects Herdr, links
skills, slash commands and OMP role agents, and installs `fm` and
`ponytail-update` links under `~/.local/bin`. Add that directory to `PATH`.
It also reconciles the pinned Pi Ponytail package, filters duplicate shared
skills, and sets Ponytail's `defaultMode` to `off`.

If FirstMate is missing, installation clones the manifest's fork branch at the
validated commit, tracks that branch, and preserves official as `upstream`.
An existing checkout is reported, never updated or switched by the installer.
Re-running installation reconciles machine state; foreign links are not overwritten.

Check the installation, then launch:

```sh
./install.sh --verify   # read-only drift report; inspect drift counts too
fm doctor              # read-only health diagnostics
fm --check             # resolve startup without launching the Captain
fm
```

`--check` and `--print-command` do not start a Captain, but their preflight can
create missing operational-home directories. See
[installation and first run](docs/install.html) for setup details.

## Daily commands

| Command | Purpose |
| --- | --- |
| `fm` | Start the Pi Captain, preferring GPT-6.1 Sol medium |
| `fm --harness omp` | Use OMP explicitly; harness fallback is not automatic |
| `fm --model claude` | Choose a model preset for this launch only; also accepts `codex` or `grok` |
| `fm --check` / `fm --print-command` | Inspect startup resolution / the resolved command without launching |
| `fm doctor` / `fm doctor --json` | Diagnose architecture, compatibility, routing and installation |
| `fm version` / `fm version --json` | Show stack identity and versions, not a health verdict |
| `fm update` | Fast-forward both checkouts, reconcile, and verify this machine |
| `fm board` / `fm board --lavish` | Open the task board in terminal-browser / Lavish |
| `fm bot --help` | Inspect bot spec, scheduling and filing commands; none dispatch workers |
| `ponytail-update` | Prepare an uncommitted Ponytail pin update **and apply it locally** |

Place `--harness pi` or `--harness omp` before a subcommand. Startup `--model`
and `--harness` flags work in either order; `--model` is not a subcommand option.
See the [CLI reference](docs/cli.html) for full usage.

### fm doctor

Doctor never repairs, restarts, or makes a paid inference call. Exit `0` means
the mandatory architecture is healthy, even if advisory findings remain; exit
`1` means a mandatory break. Check individual findings, not only the exit code.
Model availability means credentials/model configuration resolve, not that live
credentials or quota are guaranteed. [`bin/fm-doctor`](bin/fm-doctor) owns the
exact diagnostic and exit rules.

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
ordered chain: GPT-6.1 Sol medium, then a harness-specific Sonnet medium fallback.
There is no Astra startup candidate. Rows for a different harness are ignored. Only an
authoritative `UNAVAILABLE` skips a candidate; `UNKNOWN` remains eligible.
Launch output explains fallback decisions.

The Sonnet fallback is `anthropic/claude-sonnet-5-5` on OMP and the unversioned
`pi-claude-code-provider/sonnet` alias on Pi. Claude Code resolves that alias;
it is not a version-pinned Sonnet selector. Its availability uses the provider's
`claude auth status` preflight because Pi's broker does not load extension
providers. OMP diagnostics use `models --json --no-extensions` to avoid writing
FirstMate extension-load markers.

`fm --model codex|claude|grok` selects, respectively,
`openai-codex/gpt-6.1-sol`, `anthropic/claude-sonnet-5-5`, or `xai/grok-4.7`,
all at medium effort. A preset requires `AVAILABLE` for that exact model/effort.
Invalid, unavailable or unverifiable presets warn and use the unchanged default
chain on the same harness. Raw model ids are not accepted; nothing is persisted.
On Pi, the `claude` preset needs Anthropic credentials in Pi, not just the
subscription-backed fallback extension.

[`fm-captain-lib.sh`](firstmate/fm-captain-lib.sh) is the shared harness and
availability owner for startup and doctor. `fm version` shares harness selection
but does not probe availability.

### Stack compatibility

[`stack-manifest.tsv`](firstmate/stack-manifest.tsv) is the single source for
the distribution repository/explicit branch, official upstream, validated FirstMate commit, and Pi/OMP/Herdr minimum
and tested versions. The recorded minimums currently equal tested versions:
they are known-good points, not proof of a wider supported range.

Doctor treats versions below minimum and a FirstMate checkout behind or
diverged from the baseline as failures. Newer versions or a checkout ahead of
the baseline are warnings, not newly validated compatibility.

## Updating

Run from the installed setup:

```sh
fm update
```

[`bin/fm-update`](bin/fm-update) checks **both** checkouts before changing either,
then fast-forwards the FirstMate distribution's explicit `inkayat-main` branch,
fast-forwards firstmate-config, and runs that configuration checkout's
`install.sh` and `install.sh --verify`.

Both working trees must be clean and fast-forwardable with configured upstreams.
FirstMate must use the manifest's exact fork origin, check out `firstmate_branch`,
track `origin/inkayat-main`, and set local `origin/HEAD` to that same branch for
native bootstrap consistency. No unfinished Git operation or local-only commits
are accepted. `fm update --check` verifies local guards and prints the source,
branch, target and pin without fetching, updating or installing; remote freshness
is deliberately unverified. See [migration and refusals](docs/update.html).

For an old installation that cannot fetch its own replacement, use the
[one-time revision-bound bootstrap command](docs/update.html#migration).
It preflights both persistent checkouts, adopts only recognized clean legacy
layouts, preserves official as `upstream`, and reconciles at the inspected config
revision. If the new updater is already installed, `fm update --migrate` performs
that opt-in transition directly. After success, ordinary `fm update` is enough.
The follow-up is preparation-only until a concrete bootstrap commit is approved
and published; do not substitute a moving script URL or the older `d7e3fc7` commit.
Partial migration is reported explicitly, never rolled back or called complete.

Official updates are a separate human integration: fetch `upstream/main`, merge
it into a separate integration branch based on `inkayat-main`, test and review,
then publish the approved result to the fork. Normal `fm update` never merges
official or follows the fork's GitHub default `main`.

Updates never force, stash, reset, rebase, push, or update project/secondmate
checkouts. If the distribution checkout moved and a later stage fails, the command
reports `PARTIAL UPDATE`; there is no multi-repository rollback. Fix the stated
error and re-run. Only `fm update complete` means every stage succeeded.

A running Captain is not restarted or notified. Instructions and skills it has
already loaded stay as they are; end that session and run `fm` again to adopt
updates. Files a running session reads afterwards are the updated ones: a Pi
session whose own Ponytail mode is `lite`, `full` or `ultra` injects the new
Ponytail prompt on its next turn, although the default stays `off`. Landed source
or an isolated candidate is not evidence of installation or activation on a host.

For Ponytail pins, `ponytail-update` requires a clean `main`, pulls fast-forward
only, and, when a newer stable release exists, changes
[`skills/external.lock`](skills/external.lock), runs its validation suites, and
reconciles/verifies the local machine. It does not commit or push; review the pin
diff through the normal repository workflow. This is not a read-only command.

## Routing

[`crew-dispatch.json`](firstmate/crew-dispatch.json) owns ten semantic categories
and a DEFAULT catch-all. Substantive work prefers Opus 5.5, bounded work may use
Sonnet 5.5, and trivial work uses Haiku/Luna. GPT-6.1 Sol supplies cross-family
routes and implementation alternatives; Astra is reserved for narrow worker
escalations. Explicit Captain choices can override the profile.

Do not maintain a second routing table here: use the full `when`/`why` conditions
in the profile and [primary policy §3](firstmate/primary-policy.md#3-routing).
During the current debugging period, the Captain prints a short
`Routing:` / `Agent:` / `Skills:` block per actual worker/stage.
It is a diagnostic trace, not an enforcement or completion gate; see
[policy §0](firstmate/primary-policy.md#0-routing-agent-and-skill-trace-temporary-debugging-period).

## Context and skills

### Worker context and skill classes

Precedence is project-native instructions → project-local skills → role/task
policy → shared worker skills. Each task carries explicit instruction and skill
paths resolved against its own worktree; Pi and OMP native discovery alone do
not guarantee the same resolution.

Keep three populations distinct: official FirstMate internal skills are
Captain-only; this repository's shared worker skills are installed under
`~/.agents/skills`; project-local skills remain in their project's tracked
skill directories. [Primary policy §2](firstmate/primary-policy.md#2-before-delegating)
owns the handoff, including revisiting context when a new subtree is selected.

### Automatic role selection

[`roles/`](roles/) defines worker contracts and OMP agent definitions; installation
links them as `~/.omp/agent/agents/fm-<role>.md`. The Captain chooses the narrowest
fitting role; coherent mixed work stays with `senior-fullstack`. Role, skills and
route remain separate choices. The retained `tenth-man` role is for deliberate
adversarial challenge, not routine review. See [roles and skills](docs/roles-skills.html).

### Bounded internal delegation

Only FirstMate owns macro orchestration. OMP's native bounded `task` helpers may
work inside the same parent task/project/worktree and authority; the parent
retains verification and completion responsibility. Pi has no bundled equivalent.
[Policy §6](firstmate/primary-policy.md#6-orchestration-boundary) owns this boundary.

### Completion evidence limits

Context, roles, skill selection and passing fixture reports do not
prove native adoption, read order, application, sandboxing or task completion.
Workers report actual commands, observed outcomes and unverified limits;
browser-visible changes need relevant real-flow evidence.

The selected official FirstMate delivery path owns review, fixes and publication.
This configuration adds no automatic reviewer or trusted completion gate, and no
extra manual reviewer on top of `no-mistakes`. An explicitly requested separate
review is scoped and read-only; no selection grants publication authority.
See [primary policy §7](firstmate/primary-policy.md#7-completion).

## Machine-local state

| Location | Purpose |
| --- | --- |
| This checkout | Tracked policy, routing, roles, skills, commands and launchers |
| `FIRSTMATE_ROOT` (default `~/Developer/tools/firstmate`) | FirstMate distribution checkout |
| `FM_HOME` (default `~/.firstmate`) | Project registry, preferences, task/runtime/session state and local data |
| `~/.config/firstmate-config/env` | Machine-local path resolution |

### Boundaries

Do not commit credentials, host paths, project knowledge or runtime data here.
Official provenance remains separate from fork distribution; project instructions outrank global defaults.
Detailed file ownership and environment overrides are in the
[configuration reference](docs/config.html).

### Board columns

The board is a deterministic, LLM-free projection, not a competing task database.
Every row of FirstMate's complete local backlog is classified from structured
fields: **Todo** is queued, deferred or parked work; **In Progress** is a working
child; **Waiting Review** includes finished workers, parked gates/decisions and
live Captain calls; **Blocked** includes unresolved dependencies, external holds
and blocked, paused, failed or unknown children; **Completed** means a closed
backlog row only. A preserved task `.meta` never overrides a held or closed row.

FirstMate's records remain authoritative, read through the official full local
backlog/metadata inventory; the bounded summary stands in only when that is
unavailable. Absent FirstMate rows retire from provably complete summary
surfaces and, whenever the inventory is available, only once it lacks them too;
a truncated summary needs that inventory. Unknown or incomplete input retains
cards; manual cards survive.
`fm board` refreshes while its launched viewer runs, and the page reloads data
periodically. Use [`bin/fm-board`](bin/fm-board) directly for list/show/render and
manual-card commands. See [board usage and details](docs/board.html).

### Bots

Bots are **beta** home-local specs, not autonomous processes. Daily windows use
Europe/Stockholm time; optional intervals (`--every-hours N`, minimum two whole
hours) and selected remote branches (`--on-remote NAME --on-branch BRANCH`) are
implemented but opt-in. Creation does not activate the watcher: registration via
`fm bot check-install` is a separate explicit step. `fm bot file <id>` files a due
occurrence and prints a plan; only ordinary FirstMate dispatch starts a worker.
Permission levels are ceilings, never commit/push approvals.

Missed daily windows are not backfilled. Interval/remote occurrences are skipped
permanently while a predecessor is unfinished or uncertain, and require a
two-hour spacing after positively observed completion. Wall-clock limits are
advisory, not forced cancellation. Remote jobs carry a pinned commit artifact;
automatic worker checkout at that OID is not provided. Simulated-clock pilots
do not prove unattended consecutive-day operation or provider teardown. See
[bots, triggers and limits](docs/bots.html).

## Documentation

The [guide](docs/index.html) is plain HTML with no build step; open it locally or
use the hosted site. This README and linked command/configuration owners remain
authoritative when guide examples lag behind source.

- [Installation](docs/install.html) and [update/recovery](docs/update.html)
- [CLI](docs/cli.html), [configuration](docs/config.html), and [safety](docs/safety.html)
- [Dispatch details](docs/dispatch.html), [roles/skills](docs/roles-skills.html),
  [board](docs/board.html), and [bots](docs/bots.html)

Tagged versions are on [Releases](https://github.com/inkayat/firstmate-config/releases);
`main` may contain newer changes. Exploratory work is not an installed capability.
