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
| `fm` | Start the Pi Captain from any directory, preferring GPT-6.1 Sol medium |
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
ordered chain: GPT-6.1 Sol medium, then a harness-specific Sonnet medium fallback.
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
`openai-codex/gpt-6.1-sol`, `anthropic/claude-sonnet-5-5`, or `xai/grok-4.7`,
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
Sonnet 5.5, and trivial work uses Haiku/Luna. GPT-6.1 Sol supplies cross-family
routes and implementation alternatives; Astra is reserved for narrow worker
escalations. Explicit Captain choices can override the profile.

Do not maintain a second routing table here: use the full `when`/`why` conditions
in the profile and [primary policy §3](firstmate/primary-policy.md#3-routing).
During the current debugging period, the Captain prints a short
`Routing:` / `Agent:` / `Skills:` block per actual worker/stage.
It is a diagnostic trace, not an enforcement or completion gate; see
[policy §0](firstmate/primary-policy.md#0-routing-agent-and-skill-trace-temporary-debugging-period)
and its checker [`tests/routing-trace.sh`](tests/routing-trace.sh).

## Context and skills

### Worker context and skill classes

Precedence is project-native instructions → project-local skills → role/task
policy → shared worker skills. Each task carries explicit instruction, role and
skill paths resolved against its own worktree, including the role's
`autoloadSkills` defaults; Pi and OMP native discovery alone do not guarantee
the same resolution. Official FirstMate delivers those paths and read-and-apply
requirements, not role or skill bodies: nothing is inlined before the first
model call, a missing path does not refuse the launch, and no selection record
is written.

Keep three populations distinct: official FirstMate internal skills are
Captain-only; this configuration's shared worker skills are installed under
`~/.agents/skills`; project-local skills remain in their project's tracked
skill directories. [Primary policy §2](firstmate/primary-policy.md#2-before-delegating)
owns the handoff, including revisiting context when a new subtree is selected.

### Automatic role selection

[`roles/`](roles/) defines worker contracts and OMP agent definitions;
installation links them as `~/.omp/agent/agents/fm-<role>.md`. The Captain
chooses the narrowest fitting role; coherent mixed work stays with
`senior-fullstack`. Role, skills and route remain separate choices. The
`tenth-man` role is for deliberate adversarial challenge, not routine review.

### Bounded internal delegation

Only FirstMate owns macro orchestration. OMP's native bounded `task` helpers may
work inside the same parent task/project/worktree and authority; the parent
retains verification and completion responsibility. Pi has no bundled equivalent.
[Policy §6](firstmate/primary-policy.md#6-orchestration-boundary) owns this
boundary; [`tests/worker-context.sh`](tests/worker-context.sh) validates fixture
reports against it.

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
```

`tests/routing-trace.sh` also contains a real spawn seam;
`tests/worker-context.sh` includes native loader/documentation probes. Inspect
their headers before execution; they are not part of the synthetic-only
commands above. Live delegated handoff and Linux/Omarchy adoption require
separate evidence.
