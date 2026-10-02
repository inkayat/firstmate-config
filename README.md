# firstmate-config

`firstmate-config` is an opinionated, reproducible configuration layer around
the official [FirstMate](https://github.com/kunchenguid/firstmate) checkout. It
selects the Captain runtime, worker routing, shared skills, and machine-local
layout without forking or patching FirstMate.

The official checkout remains upstream-clean. Tracked configuration lives here;
operational state, credentials, sessions, and project registries stay outside
the repository. See [GitHub Releases](https://github.com/inkayat/firstmate-config/releases)
for the latest tagged version; `main` may contain newer reviewed changes.

## Architecture

```text
fm
 └─ OMP Captain
     └─ FirstMate
         └─ Herdr
             ├─ Pi workers
             └─ OMP workers
```

OMP is the default Captain harness. Pi remains an explicit fallback:

```sh
fm --harness pi
```

The Captain harness and worker routing are separate decisions. FirstMate owns
task lifecycle and delegation; Herdr provides the runtime; the tracked routing
policy chooses worker harness, model, effort, and role by task semantics.

## Highlights

- OMP-first Captain with an explicit Pi fallback
- Semantic task routing across eleven dispatch categories
- Opus 5.5-biased routing: substantive work lands on Opus 5.5, bounded work
  may stay on Sonnet 5.5, trivial work on Haiku 4.5 or GPT-6 Luna; GPT-6.1 Sol
  is the everyday cross-family challenger, with Astra limited to each
  lane's most extreme, exceptional escalation
- Temporary routing/skill trace in the Captain chat during the debugging
  period (`firstmate/primary-policy.md` section 0)
- Multi-project operation with per-task project resolution
- Scoped `AGENTS.md` / `CLAUDE.md` context and project-local skills
- Reproducibly installed shared worker skills and external pins
- Browser/manual validation policy for user-visible work
- Independent review before merge for substantive or risky Captain-dispatched
  mutating work - advisory only, distinct from `no-mistakes`'s own automated
  pipeline gate (see `firstmate/primary-policy.md` "Independent review
  before merge")
- Read-only `fm doctor` and `fm version` diagnostics
- Fast-forward-only `fm update` (official FirstMate checkout, then this repository) and deterministic, idempotent installation

## Documentation

A small, navigable guide lives in [`docs/`](docs/index.html): installation and
first run, update and recovery, architecture and startup, roles and skills,
dispatch routing, safety boundaries, configuration, the CLI, and the task
board. It is plain HTML with no build step; preview it locally by opening
`docs/index.html` in a browser. This README and the files it links remain the
source of truth.

## Routing

[`firstmate/crew-dispatch.json`](firstmate/crew-dispatch.json) is the source of
truth. Categories describe semantic fit, not a simple size ladder; explicit
Captain choices can override the table.

| Category | Sub-lanes | Intent |
| --- | --- | --- |
| `QUICK` | OMP · Claude Haiku 4.5 low, or GPT-6 Luna low | Tiny edits, mechanical cleanup, quick factual work |
| `EXPLORE` | Simple: OMP · Claude Haiku 4.5 low, or GPT-6 Luna low; hard: OMP · Claude Sonnet 5.5 medium | Read-only reconnaissance inside a repository |
| `RESEARCH` | Ordinary: OMP · Claude Sonnet 5.5 medium; substantial/decision-heavy: OMP · Claude Opus 5.5 high; Pi-tooling advantage: Pi · GPT-6.1 Sol medium | External docs, APIs, standards, and upstream source |
| `REVIEW` | Bounded: OMP · Claude Sonnet 5.5 high; substantive/cross-component: OMP · Claude Opus 5.5 high; critical/high-consequence: OMP · Claude Opus 5.5 xhigh, optionally plus a Pi · GPT-6.1 Sol xhigh cross-family second reviewer | Correctness and maintainability review |
| `ARCHITECTURE` | OMP · Claude Opus 5.5 high; very difficult: xhigh; GPT-6 Astra xhigh only when ultra-exceptional | Boundaries, data models, migrations, structural decisions |
| `TENTH-MAN` | Claude-authored work: Pi · GPT-6.1 Sol xhigh (GPT-6 Astra xhigh only when critical/unresolved after Sol); Astra/OpenAI-authored work: OMP · Claude Opus 5.5 xhigh | Independent adversarial challenge |
| `IMPLEMENT` | Small/bounded: OMP · Claude Sonnet 5.5 high; substantive: OMP · Claude Opus 5.5 high | Features, fixes, refactors, and tests |
| `IMPLEMENT-LARGE` | OMP · Claude Opus 5.5 high; reasoning-heavy: xhigh | Broad, mostly settled implementation |
| `DEEP` | Scout and ship: OMP · Claude Opus 5.5 xhigh, with GPT-6.1 Sol xhigh only as an explicit escalation/second hypothesis and GPT-6 Astra xhigh as the last escalation | Hard root-cause and reasoning-heavy work |
| `UI/BROWSER` | Normal: OMP · Claude Sonnet 5.5 high; complex/cross-layer: OMP · Claude Opus 5.5 high | Browser-visible behavior and end-to-end flows |
| `DEFAULT` | OMP · Claude Opus 5.5 high (debugging period) | Work with no more specific category |

Routing philosophy:

- Substantive work - meaningful new behavior, nontrivial refactors,
  multi-component work, or real cross-component regression risk - goes to
  Opus 5.5. When unsure between Sonnet 5.5 and Opus 5.5 for substantive work,
  choose Opus 5.5.
- Small, bounded work may stay on Sonnet 5.5; trivial work on Haiku 4.5 or
  GPT-6 Luna.
- Sub-lanes are separate same-category rules, never new categories and
  never quota peers: only QUICK and simple EXPLORE pair Haiku with Luna, so
  nothing is picked ahead of an Opus 5.5 primary by quota.
- TENTH-MAN enforces model-family diversity: a Claude-authored change is
  challenged by Pi + GPT-6.1 Sol, escalating to Pi + GPT-6 Astra only for
  critical cases Sol leaves unresolved; an Astra/OpenAI-authored change is
  challenged by OMP + Opus 5.5.
- Sonnet 5, Opus 5, Fable 5.1, GPT-5.5, GPT-5.6 Luna/Sol, and GPT-6 Sol are
  retired.

The complete conditions live in the tracked routing file and
[`firstmate/primary-policy.md`](firstmate/primary-policy.md).

During the debugging period the Captain prints a short `Routing:` /
`Skills:` block before each delegation and a `Skill evidence:` block after
each worker finishes (primary-policy.md section 0).
`tests/routing-trace.sh check` compares a captured block with the real
spawn axes, the matched rule's route (`#n`), the brief's selected skills,
and the worker transcript. Evidence citations are lexical matches only, so
it prints their transcript context for the Captain to read; it cannot prove
the category/rule choice or that a skill was applied.

## Context and skills

The intended precedence is:

```text
project-native instructions
  > project-local skills
  > role/task policy
  > shared worker skills
```

Project-native context includes root and nested `AGENTS.override.md`,
`AGENTS.md`, and `CLAUDE.md` files. Project-local skills live under tracked
project directories such as `.agents/skills`, `.claude/skills`, or
`.agent/skills`. Shared worker skills are installed under
`~/.agents/skills` for Pi and OMP discovery.

firstmate-config directly manages its own shared/core skills, installed
under `~/.agents/skills` by `install.sh`. Project-local skills remain
project-owned, living under each project's own tracked directories. The
standalone [`agent-skill-vault`](https://github.com/inkayat/agent-skill-vault)
repository is a separate, manually curated skill collection; promoting one
of its skills into this repository's shared set is a deliberate, explicit
decision.

Official FirstMate internal skills remain separate and are not installed as
shared worker skills. Context and skill selection are policy and handoff
mechanisms; they are not a formal proof of read order, compliance, or task
completion.

## Captain startup model

`firstmate/captain-startup-models.tsv` is the ordered list of Captain startup
candidates, tried in order and skipped on any authoritative `UNAVAILABLE`
result: `openai-codex/gpt-6.1-sol` medium, then a harness-scoped Claude Sonnet
step, then `openai-codex/gpt-6-astra` xhigh. `bin/fm`, `fm doctor`, and
`fm version` all resolve this chain through the one shared availability path
in `firstmate/fm-captain-lib.sh`.

The Sonnet fallback step is harness-scoped because the two harnesses expose
Claude Sonnet under different, non-interchangeable ids: OMP's own native
catalog carries `anthropic/claude-sonnet-5-5`; Pi exposes it only through the
Claude Code provider extension as `pi-claude-code-provider/sonnet`, which is
not an OMP model id and is never checked against OMP's catalog. Each TSV row
carries an optional third `harness` column (`omp`, `pi`, or blank for both);
a row whose harness column does not match the active Captain harness is
skipped entirely, never probed and never selected, so an OMP Captain can
never be launched with a Pi-only provider id and a Pi Captain never loses its
own Sonnet fallback.

The Pi id stays the unversioned alias: `pi-claude-code-provider` exposes only
the `sonnet`, `fable`, `opus`, and `haiku` aliases and passes them to Claude
Code, whose own alias table decides the served Sonnet version. It moves to
Sonnet 5.5 when the installed Claude Code does, with no change here.

Pi's own `auth check` does not load extension providers and reports
`invalid_state` for `pi-claude-code-provider` even when the provider is
perfectly usable, so availability for that one provider is checked through
the provider's own zero-inference `claude auth status` preflight instead of
the broker - see `firstmate/fm-captain-lib.sh` for the exact detector. Do not
add a second detector or a paid probe for it.

## Install

```sh
git clone https://github.com/inkayat/firstmate-config.git
cd firstmate-config
./install.sh
```

The installer checks the local toolchain, creates or verifies the official
FirstMate checkout, writes machine-local resolution, installs tracked skills,
and links commands into `~/.local/bin`. Running it again is the normal reconcile
path and is idempotent.

Read-only drift check:

```sh
./install.sh --verify
```

## Daily commands

| Command | Purpose |
| --- | --- |
| `fm` | Start the OMP Captain from any directory |
| `fm --harness pi` | Start the Captain with the explicit Pi fallback |
| `fm doctor` | Run read-only architecture, compatibility, routing, and installation diagnostics |
| `fm version` | Print compact stack identity and version information |
| `fm update` | Fast-forward the official FirstMate checkout (`FIRSTMATE_ROOT`), then the `firstmate-config` checkout, then reconcile and verify this machine via its own `install.sh`; check both checkouts before changing either, refuse anything that is not a clean, plain fast-forward, and report a failure after the official stage as a partial update |
| `fm board` / `fm board --lavish` | Open the persistent Kanban board (terminal-browser by default, Lavish with `--lavish`); render a deterministically refreshed, LLM-free data projection with the same static template, keep re-rendering it while the viewer is open, and let the page re-read it every few seconds so transitions appear without a manual refresh |
| `ponytail-update` | Prepare and validate a local Ponytail pin update without committing or pushing |

`fm doctor --json` and `fm version --json` provide machine-readable output.

`bin/fm-board` owns the board's `add`/`update`/`move`/`list`/`show`/`summary`/`render` CLI. Its persistent files live under `$FM_HOME/data/board/` (`state.json`, append-only `events.jsonl`, generated `board-data.js`); actual FirstMate backlog and execution records (`data/backlog.md`, `state/home-summary.json`) remain authoritative, and the board is only their deterministic, LLM-free projection.

Every card has a keyboard-reachable **Details** link (`board.html#task/<id>`) to that task's own detail view in the same page, in either viewer; **Back to board** or Escape returns to the board with focus on the card. At render time `bin/fm-board` adds one `fm-tasks-axi.sh show <id> --full` lookup per FirstMate task to `board-data.js` only (never `state.json`), plus the task's open decision and landed PR/report from `state/home-summary.json`, so the view shows body, notes, status and hold, dependencies, review context, worker summary, and links. A field its source reports as unset reads **None**; a field no source has (a manual row, a task the backlog no longer holds) reads as not available. Raw `.meta`/`.status` content is never shown. Under Lavish, turn **Annotate** off (⌘I / Ctrl+I) to follow links: in annotate mode Lavish captures clicks for annotations.

Board columns follow FirstMate's structured state, never hold prose: **Todo** is queued or deferred work (plain queued rows, dated or aged captain deferrals, non-captain holds); **In Progress** is a live child that is working; **Waiting Review** is a finished worker awaiting review or landing, a no-mistakes gate or needs-decision (`parked`), or a live captain call (`captain_actionable`); **Blocked** is an unresolved dependency or a child that is `blocked`/`paused`/`failed`/unknown; **Completed** is only a landed backlog row. Rows FirstMate stops publishing are retired whenever its summary surfaces are provably complete, including while one local-only task awaits approval (`terminal_in_flight`); `bin/fm-board`'s `CREW_STATE_TO_BOARD`, `_queued_state`, and `_retirement_protected` own the exact rules.

`ponytail-update` checks the latest stable Ponytail release. If an update is
available, it updates `skills/external.lock`, shows the diff, runs the Ponytail
validation suites, reconciles the machine, verifies installed state, and checks
again. It does not commit, merge, push, create branches, or tag releases.

## Machine-local state

`FM_HOME` defaults to `~/.firstmate` and holds operational data that does not
belong in Git, including:

- the project registry and per-project delivery posture
- Captain preferences and local learnings
- authentication, session, runtime, and task state
- machine-specific tool or browser knowledge

`~/.config/firstmate-config/env` records local path resolution. Credentials,
host-specific paths, runtime records, and project data are not tracked here.

## Updating

Update the official FirstMate checkout and the tracked configuration, then
reconcile installed state:

```sh
fm update
```

`fm update` runs in this order:

1. Check both checkouts before changing either: local state first, then
   origin's default branch for the official checkout and a fetch of both
   remotes (only remote-tracking refs move; the official side fetches only its
   default branch and never prunes). Each checkout must equal, or be a plain
   fast-forward behind, its upstream.
2. Fast-forward the official FirstMate checkout (`FIRSTMATE_ROOT`) with
   `git merge --ff-only`.
3. Fast-forward the `firstmate-config` checkout to its remote tip.
4. Run that checkout's own `./install.sh`, then `./install.sh --verify`.

It refuses in step 1, changing neither working tree, when:

- `FIRSTMATE_ROOT` is missing, is not the root of a Git checkout, or has no
  `AGENTS.md`
- the official checkout's `origin` has a configured or effective
  (`insteadOf`-rewritten) URL that is not exactly `firstmate_repo` from
  `firstmate/stack-manifest.tsv`
- the official checkout is detached, on a branch other than origin's default
  branch, or that branch does not track `origin/<default>`; or origin's
  default branch cannot be determined or fetched as a fast-forward
- the official checkout has uncommitted or untracked changes, an unfinished
  merge, rebase, cherry-pick, revert, or bisect, or local commits not on
  `origin/<default>` (ahead or diverged)
- the `firstmate-config` checkout is dirty, diverged, detached, has no
  upstream, or cannot be fetched

After step 2 has moved the official checkout, any later failure (fast-forward,
`install.sh`, `install.sh --verify` failure or drift) exits nonzero with a
`PARTIAL UPDATE` line naming the official commits that landed; there is no
multi-repository rollback, so fix the reported error and re-run `fm update`.
Only a run that ends with `fm update complete` updated everything.

Nothing is forced, stashed, reset, merged, rebased, or pushed, and no branch
or file is deleted (the only pruning is `fm update`'s existing `fetch --prune`
of stale `firstmate-config` remote-tracking refs). Secondmates and projects
are never updated. A separate manual `./install.sh`
is not required after a successful `fm update`; run it directly only when
diagnosing installed state without pulling.

A running Captain keeps the instructions, skills, and launch-time wiring it
loaded at startup and is not restarted or notified: to adopt an official
update, restart it through the official procedure (end the Captain session,
then run `fm` again). Once the official checkout moves past the validated
baseline commit, `fm doctor` and `install.sh` report it as ahead of that
baseline (`WARNING`, not drift) until `firstmate/stack-manifest.tsv` is moved.

Prepare a Ponytail dependency update:

```sh
ponytail-update
git diff -- skills/external.lock
```

Review and commit that pin change through the normal Git workflow. Other
machines then converge with:

```sh
fm update
```

## Roadmap

Everything in this section is planned or exploratory; none of it describes
current runtime behavior.

### v0.4 — Optional Team Mode / multi-agent deliberation (planned)

- explicit opt-in Team Mode
- architecture-team and deep-team recipes
- parallel, independent scouts and critics
- Tenth-Man as the adversarial reviewer
- Captain-owned synthesis and final decisions
- bounded delegation with no recursive team explosion

Team Mode is intended to compose the existing routing system, not replace it.

### Later (exploratory)

- richer agentic recipes
- independent compliance and review specialists within a broader agentic system
- routing and decision observability
- a local Qwen lane when the 4090 environment is available and worth enabling
- model/provider routing refinements based on observed usage

## Design principles

- Keep official FirstMate upstream-clean.
- Prefer configuration and native extension points over forks.
- Let project context outrank global defaults.
- Route by task semantics, not keywords alone.
- Pin external dependencies, but update them explicitly and visibly.
- Add machinery only after real usage demonstrates the need.
