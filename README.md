# firstmate-config

**[Read the guide](https://inkayat.github.io/firstmate-config/)** — the
navigable documentation site for installation, CLI, configuration, dispatch,
safety, and updates.

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
- Role files that double as OMP agent definitions and load their own default
  skills (`autoloadSkills`):
  - core roles;
  - an open set of specialists (`security-engineer`, `code-reviewer`,
    `refactorist`, `django-pro`, `frontend-master`);
  - team roles (`team-lead`, `product-owner`, `backend-contract`, `qa`) for an
    opt-in, single-task OMP team: planning, then parallel implementation,
    QA, and review. `install.sh` links every role file into OMP's user agent
    root as `fm-<role>` (`firstmate/primary-policy.md` sections 4-5)
- Optional per-task team profiles (`teams/<name>.json`): members, write
  scopes, message recipients, helper spawns, workflow, and commit/push/merge
  limits, applied in OMP sessions by this repository's own policy extension
  and checked at delivery by `fm team audit` ("Team profiles" below)
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
first run, update and recovery, architecture and startup, roles, skills, and
team mode, dispatch routing, safety boundaries, configuration, the CLI, the
task board, and bots. It is plain HTML with no build step; preview it locally by opening
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

`fm --model codex|claude` (either order with `--harness`) replaces the chain
for one launch with a preset: `codex` is `openai-codex/gpt-6.1-sol` at
medium, `claude` is `anthropic/claude-sonnet-5-5` (Sonnet 5.5) at high. Both
ids are exact and version-pinned in OMP's native catalog and in Pi's built-in
registry; Pi's `pi-claude-code-provider/sonnet` is an unversioned alias and is
never used for this preset, so on Pi `claude` needs Anthropic credentials
configured in Pi itself. The preset is used only when that same availability
path reports its exact model and effort `AVAILABLE` on the selected harness.
Any other value, or an unavailable or unverifiable preset, warns
(`REQUESTED_MODEL_FALLBACK` in `--check`) and launches the unchanged chain -
default model and effort - on the same harness; a raw model id is never passed
through. Nothing is persisted, and chain/runtime blockers still stop the
launch.

The Sonnet fallback step is harness-scoped because the two harnesses expose
Claude Sonnet under different, non-interchangeable ids: OMP's own native
catalog carries `anthropic/claude-sonnet-5-5`; Pi's chain step instead uses
the Claude Code provider extension's subscription-backed
`pi-claude-code-provider/sonnet` alias, which is
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
FirstMate checkout, writes machine-local resolution, installs tracked skills
and slash commands (`~/.agents/skills`, `~/.agents/commands`), links each role
file as an OMP agent (`~/.omp/agent/agents/fm-<role>.md`) and the team policy
extension into OMP's user extension root
(`~/.omp/agent/extensions/fm-team-policy.ts`), and links commands into
`~/.local/bin`. Running it again is the normal reconcile path and is
idempotent.

Read-only drift check:

```sh
./install.sh --verify
```

## Daily commands

| Command | Purpose |
| --- | --- |
| `fm` | Start the OMP Captain from any directory |
| `fm --harness pi` | Start the Captain with the explicit Pi fallback |
| `fm --model codex\|claude [--harness pi]` | Start this Captain on GPT-6.1 Sol (medium) or Sonnet 5.5 (high), either flag order; any other value or an unavailable preset warns and uses the default startup chain |
| `fm doctor` | Run read-only architecture, compatibility, routing, and installation diagnostics |
| `fm version` | Print compact stack identity and version information |
| `fm update` | Fast-forward the official FirstMate checkout (`FIRSTMATE_ROOT`), then the `firstmate-config` checkout, then reconcile and verify this machine via its own `install.sh`; check both checkouts before changing either, refuse anything that is not a clean, plain fast-forward, and report a failure after the official stage as a partial update |
| `fm board` / `fm board --lavish` | Open the persistent Kanban board (terminal-browser by default, Lavish with `--lavish`); render a deterministically refreshed, LLM-free data projection with the same static template, keep re-rendering it while the viewer is open, and let the page re-read it every few seconds so transitions appear without a manual refresh |
| `fm bot ...` | Create, list, show, pause, resume, or remove home-local bot specs and dry-run which are due; never dispatches (`bin/fm-bot --help`) |
| `fm team ...` | Validate a team profile, bind one to a task, check a binding, or audit a team task's changed paths against its scope; never spawns, commits, or merges (`bin/fm-team --help`) |
| `ponytail-update` | Prepare and validate a local Ponytail pin update without committing or pushing |

`fm doctor --json` and `fm version --json` provide machine-readable output.

`bin/fm-board` owns the board's `add`/`update`/`move`/`list`/`show`/`summary`/`render` CLI. Its persistent files live under `$FM_HOME/data/board/` (`state.json`, append-only `events.jsonl`, generated `board-data.js`); actual FirstMate backlog and execution records (`data/backlog.md`, `state/home-summary.json`) remain authoritative, and the board is only their deterministic, LLM-free projection.

Every card has a keyboard-reachable **Details** link (`board.html#task/<id>`) to that task's own detail view in the same page, in either viewer; **Back to board** or Escape returns to the board with focus on the card. At render time `bin/fm-board` adds one `fm-tasks-axi.sh show <id> --full` lookup per FirstMate task to `board-data.js` only (never `state.json`), plus the task's open decision and landed PR/report from `state/home-summary.json`, so the view shows body, notes, status and hold, dependencies, review context, worker summary, and links. A field its source reports as unset reads **None**; a field no source has (a manual row, a task the backlog no longer holds) reads as not available. Raw `.meta`/`.status` content is never shown. Under Lavish, turn **Annotate** off (⌘I / Ctrl+I) to follow links: in annotate mode Lavish captures clicks for annotations.

Board columns follow FirstMate's structured state, never hold prose: **Todo** is queued or deferred work (plain queued rows, dated or aged captain deferrals, non-captain holds); **In Progress** is a live child that is working; **Waiting Review** is a finished worker awaiting review or landing, a no-mistakes gate or needs-decision (`parked`), or a live captain call (`captain_actionable`); **Blocked** is an unresolved dependency or a child that is `blocked`/`paused`/`failed`/unknown; **Completed** is only a landed backlog row. Rows FirstMate stops publishing are retired whenever its summary surfaces are provably complete, including while one local-only task awaits approval (`terminal_in_flight`); `bin/fm-board`'s `CREW_STATE_TO_BOARD`, `_queued_state`, and `_retirement_protected` own the exact rules.

`bin/fm-bot` owns bot specs at `$FM_HOME/data/bots/<name>.md` (machine-local, never tracked) and their dry `due` evaluation. A bot is a spec plus one watcher check, never a process: `fm-bot check-install` writes `$FM_HOME/state/bots.check.sh` and binds it with the official `bin/fm-check-register.sh bots`, and that check prints `bot due: <name>-<YYYYMMDD> spec=… level=…` while a bot is inside its Europe/Stockholm window and its dated task id is not yet in the backlog, so filing that id silences it for the day; each filing is also kept in a durable `$FM_HOME/data/bots/.filed/<name>` marker, because the backlog prunes done rows into an archive `fm-tasks-axi.sh show` does not search, so a task finished and pruned the same day stays silent. The dispatch seam, `fm bot file <name>-<YYYYMMDD>`, records that marker at filing time, before anything is dispatched, so a task filed, finished, and pruned between two watcher polls still cannot re-fire; a dated id filed any other way (a raw `fm-tasks-axi.sh add`) is only seen at the next poll and keeps that gap. `file` refuses anything but today's due id, prints the dispatch plan for the effective level (kind, delivery, role file, route, the routine fields, and the stop rule), files and holds an invalid bot for the captain instead, and never spawns; `firstmate/primary-policy.md` section 8 is the Captain's instruction to use it. Missed windows are not backfilled, and 02:xx times are refused because of DST. Each spec stores and validates its routine - role, project, route, schedule, scope, access (`none` or a `secret:<ref>` name, never a secret), notify, wall-clock and optional candidate/file/line limits, excluded paths - for the Captain and workers to apply; fm-bot itself enforces only the schedule and the level gate. A spec's `level` (`local-proposal` < `local-commit` < `push`) is only an upper bound, never an authorization. `local-proposal`, the default, needs only an active, well-formed spec. `local-commit` and `push` need captain authorization words with their own scope, an authorized-on date and an unexpired `expires`, file and line limits, and a registered project whose posture allows the level (`local-only` at most `local-commit`); `push` also needs excluded paths, one remote, a branch prefix, one push per run, a non-`+yolo` project, and the authorization quoted verbatim in `$FM_HOME/data/captain.md` naming the bot and project. `create` refuses any gate failure; `due` re-checks the gate every time and runs an elevated bot whose gate fails that day at `local-proposal` with the reason. `fm bot list` shows each bot's last run, the newest `<name>-<YYYYMMDD>` id the backlog lists or the marker holds. Commits and pushes stay gated by FirstMate's own per-action captain approval.

`skills/bot-builder` is the Captain's guide for "bot oluştur" / "create a bot": it collects the routine and level, refuses missing pieces (an elevated level without the captain's exact words, scope, and expiry; a mapped role with no `roles/<role>/ROLE.md`), and writes the spec only through `fm bot create`; it never activates the watcher check or dispatches. `commands/bots.md` is the read-only `/bots` prompt over `fm bot list`/`show`. `install.sh` step 7 links every `commands/*.md` into `~/.agents/commands` (OMP turns each into a slash command) the same way it links `skills/*` into `~/.agents/skills`, so both reach a primary Captain session only once they land on main and the primary checkout's `install.sh` runs; until then a primary Captain session cannot load `/bots` or `bot-builder`. `tests/bot-builder-trial.sh` (opt-in, `FM_LIVE_BOT_TRIAL=1`, real billable `omp` sessions) is evidence for the skill and command interaction only: it copies both into a disposable sandbox project's own `.agents/skills` and `.agents/commands` and runs a plain OMP session there against a disposable trial home, not a primary Captain session.

`tests/bot-pilot.sh` (opt-in, `FM_LIVE_BOT_PILOT=1`, real billable `omp` workers) is the P8 pilot, simulated end to end in a disposable lab: a lab `FM_HOME` from the official `bin/fm-lab-home.sh`, a disposable sandbox repository, and an isolated non-default Herdr session that only the official `bin/fm-herdr-lab.sh` provisions, drives, and tears down. Over nine simulated Stockholm days (sweeping every 5 minutes through the registered check's official snapshot run, across the 2026-10-25 DST change) it plays Firstmate's part - `fm bot file`, a brief from the printed plan, done-and-prune or a captain hold - and asserts one due line, one filing, and one dated report per local-proposal morning with no branch, file, or commit change, and two local-commit runs that each stop uncommitted on their dated bot branch at `needs-decision [key=commit-approval]`. It does not prove real elapsed days, a live `fm-watch.sh` loop, a Captain session, `fm-spawn`/treehouse dispatch, the approve-then-commit step, or `push`. Its workers read this checkout's real `roles/refactorist/ROLE.md`; the local-commit bot's authorization is an explicit fixture-only placeholder, never captain words, so the pilot proves nothing about a real permission.

`ponytail-update` checks the latest stable Ponytail release. If an update is
available, it updates `skills/external.lock`, shows the diff, runs the Ponytail
validation suites, reconciles the machine, verifies installed state, and checks
again. It does not commit, merge, push, create branches, or tag releases.

## Team profiles

A team task - a brief naming the `team-lead` role - may carry a team profile,
`teams/<name>.json`. `bin/fm-team validate` checks it against the real role
frontmatter, so a profile only narrows what the global role files already
allow and never rewrites one. `teams/web-feature.json` is a proposed example,
not a captain-selected team.

| Profile field | What it limits | Where it is applied |
| --- | --- | --- |
| `members[].agent` | who the lead may spawn, inside the lead role's own `spawns` list | policy extension, `before_subagent_spawn` |
| `members[].mode`, `paths.write` | `read-only`, or `mutating` with repository-relative write globs; no two members own an overlapping glob | policy extension (write, edit, apply_patch, ast_edit targets, normalized and symlink-resolved) and `fm team audit` |
| `members[].talk_to` | which members a member may message (`agent://all` is never allowed); a member may always message the lead | policy extension, `write agent://<id>` |
| `members[].spawn` | helpers a member may spawn, inside its role's declared `spawns` list; a role without one allows no helper (no shipped member role declares one), and helpers are read-only | policy extension |
| `members[].skills` | extra shared skills the lead names in that member's brief, counted against the per-task budget of three with the role's `autoloadSkills`; `autoloadSkills` themselves cannot be removed per task | advisory |
| `workflow` | ordered phases and at most two rework rounds; the lead coordinates them | advisory (`team-lead` role) |
| `ops` | `commit: none\|request`, `push: none`, `merge: none` - limits, never authority | policy extension (best-effort command patterns); FirstMate's guarded merge path |

The flow uses existing owners only:

1. At intake the Captain runs `fm team bind <task> --profile <name> --base <commit>`
   and writes a `Team profile: <name>` line in the brief. The binding and a
   byte-for-byte snapshot land in `$FM_HOME/data/team-bindings/`; the task
   never reads `teams/` again.
2. `install.sh` links `extensions/fm-team-policy.ts` into
   `~/.omp/agent/extensions`, so OMP loads it into every session. It acts only
   when the session's `FM_TASK_ID` (set by the official `fm-spawn`) is bound
   or its brief names a profile; everywhere else it is a no-op. A bound task
   whose binding or snapshot is missing, corrupt, tampered, or mismatched
   refuses everything but reads.
3. Before a relaunch, `fm team check <task>` re-validates the snapshot against
   the current roles.
4. Before review or landing, `fm team audit <task>` lists every committed,
   staged, unstaged, untracked, deleted, and renamed path, and refuses paths
   outside the team scope, symlinks leaving the worktree, and gitlinks.

Limits, stated plainly: `bash` (and anything it runs) can still write any
file, read anything, and use every credential the user account holds,
including the machine's `gh` login; the command patterns behind `ops` are best
effort and miss `eval`'d strings, scripts, and aliases. The binding,
snapshot, and brief are writable by the same user, so the sha256 is a
consistency check, not authorization: rewriting all three, or deleting the
binding and the brief line together, goes undetected. The audit proves
team-level final-tree scope only - not which member wrote a path, not writes
that were reverted, not writes outside the worktree, and not ignored files.
There is no OS sandbox, worker-specific credential, or branch protection.
The extension's decisions are proven against synthetic OMP hook events
(`tests/team-policy.sh`); a live OMP team session loading it has not been
exercised.

## Machine-local state

`FM_HOME` defaults to `~/.firstmate` and holds operational data that does not
belong in Git, including:

- the project registry and per-project delivery posture
- Captain preferences and local learnings
- authentication, session, runtime, and task state
- machine-specific tool or browser knowledge
- per-task team bindings and profile snapshots (`data/team-bindings/`)

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
