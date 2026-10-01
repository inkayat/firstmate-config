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
  may stay on Sonnet 5.5, trivial work on Haiku 4.5 or GPT-6 Luna; GPT-6 Sol
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
- Fast-forward-only `fm update` and deterministic, idempotent installation

## Routing

[`firstmate/crew-dispatch.json`](firstmate/crew-dispatch.json) is the source of
truth. Categories describe semantic fit, not a simple size ladder; explicit
Captain choices can override the table.

| Category | Sub-lanes | Intent |
| --- | --- | --- |
| `QUICK` | OMP · Claude Haiku 4.5 low, or GPT-6 Luna low | Tiny edits, mechanical cleanup, quick factual work |
| `EXPLORE` | Simple: OMP · Claude Haiku 4.5 low, or GPT-6 Luna low; hard: OMP · Claude Sonnet 5.5 medium | Read-only reconnaissance inside a repository |
| `RESEARCH` | Ordinary: OMP · Claude Sonnet 5.5 medium; substantial/decision-heavy: OMP · Claude Opus 5.5 high; Pi-tooling advantage: Pi · GPT-6 Sol medium | External docs, APIs, standards, and upstream source |
| `REVIEW` | Bounded: OMP · Claude Sonnet 5.5 high; substantive/cross-component: OMP · Claude Opus 5.5 high; critical/high-consequence: OMP · Claude Opus 5.5 xhigh, optionally plus a Pi · GPT-6 Sol xhigh cross-family second reviewer | Correctness and maintainability review |
| `ARCHITECTURE` | OMP · Claude Opus 5.5 high; very difficult: xhigh; GPT-6 Astra xhigh only when ultra-exceptional | Boundaries, data models, migrations, structural decisions |
| `TENTH-MAN` | Claude-authored work: Pi · GPT-6 Sol xhigh (GPT-6 Astra xhigh only when critical/unresolved after Sol); Astra/OpenAI-authored work: OMP · Claude Opus 5.5 xhigh | Independent adversarial challenge |
| `IMPLEMENT` | Small/bounded: OMP · Claude Sonnet 5.5 high; substantive: OMP · Claude Opus 5.5 high | Features, fixes, refactors, and tests |
| `IMPLEMENT-LARGE` | OMP · Claude Opus 5.5 high; reasoning-heavy: xhigh | Broad, mostly settled implementation |
| `DEEP` | Scout and ship: OMP · Claude Opus 5.5 xhigh, with GPT-6 Sol xhigh only as an explicit escalation/second hypothesis and GPT-6 Astra xhigh as the last escalation | Hard root-cause and reasoning-heavy work |
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
  challenged by Pi + GPT-6 Sol, escalating to Pi + GPT-6 Astra only for
  critical cases Sol leaves unresolved; an Astra/OpenAI-authored change is
  challenged by OMP + Opus 5.5.
- Sonnet 5, Opus 5, Fable 5.1, GPT-5.5, and GPT-5.6 Luna/Sol are retired.

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
result: `openai-codex/gpt-6-sol` medium, then a harness-scoped Claude Sonnet
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
FirstMate checkout, writes machine-local resolution, installs tracked skills
and slash commands (`~/.agents/skills`, `~/.agents/commands`), and links
commands into `~/.local/bin`. Running it again is the normal reconcile path
and is idempotent.

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
| `fm update` | Fast-forward the `firstmate-config` checkout, then reconcile and verify this machine via its own `install.sh`; refuse dirty or diverged state |
| `fm board` / `fm board --lavish` | Open the persistent Kanban board (terminal-browser by default, Lavish with `--lavish`); render a deterministically refreshed, LLM-free data projection with the same static template, keep re-rendering it while the viewer is open, and let the page re-read it every few seconds so transitions appear without a manual refresh |
| `fm bot ...` | Create, list, show, pause, resume, or remove home-local bot specs and dry-run which are due; never dispatches (`bin/fm-bot --help`) |
| `ponytail-update` | Prepare and validate a local Ponytail pin update without committing or pushing |

`fm doctor --json` and `fm version --json` provide machine-readable output.

`bin/fm-board` owns the board's `add`/`update`/`move`/`list`/`show`/`summary`/`render` CLI. Its persistent files live under `$FM_HOME/data/board/` (`state.json`, append-only `events.jsonl`, generated `board-data.js`); actual FirstMate backlog and execution records (`data/backlog.md`, `state/home-summary.json`) remain authoritative, and the board is only their deterministic, LLM-free projection.

Every card has a keyboard-reachable **Details** link (`board.html#task/<id>`) to that task's own detail view in the same page, in either viewer; **Back to board** or Escape returns to the board with focus on the card. At render time `bin/fm-board` adds one `fm-tasks-axi.sh show <id> --full` lookup per FirstMate task to `board-data.js` only (never `state.json`), plus the task's open decision and landed PR/report from `state/home-summary.json`, so the view shows body, notes, status and hold, dependencies, review context, worker summary, and links. A field its source reports as unset reads **None**; a field no source has (a manual row, a task the backlog no longer holds) reads as not available. Raw `.meta`/`.status` content is never shown. Under Lavish, turn **Annotate** off (⌘I / Ctrl+I) to follow links: in annotate mode Lavish captures clicks for annotations.

Board columns follow FirstMate's structured state, never hold prose: **Todo** is queued or deferred work (plain queued rows, dated or aged captain deferrals, non-captain holds); **In Progress** is a live child that is working; **Waiting Review** is a finished worker awaiting review or landing, a no-mistakes gate or needs-decision (`parked`), or a live captain call (`captain_actionable`); **Blocked** is an unresolved dependency or a child that is `blocked`/`paused`/`failed`/unknown; **Completed** is only a landed backlog row. Rows FirstMate stops publishing are retired whenever its summary surfaces are provably complete, including while one local-only task awaits approval (`terminal_in_flight`); `bin/fm-board`'s `CREW_STATE_TO_BOARD`, `_queued_state`, and `_retirement_protected` own the exact rules.

`bin/fm-bot` owns bot specs at `$FM_HOME/data/bots/<name>.md` (machine-local, never tracked) and their dry `due` evaluation. A bot is a spec plus one watcher check, never a process: `fm-bot check-install` writes `$FM_HOME/state/bots.check.sh` and binds it with the official `bin/fm-check-register.sh bots`, and that check prints `bot due: <name>-<YYYYMMDD> spec=… level=…` while a bot is inside its Europe/Stockholm window and its dated task id is not yet in the backlog, so filing that id silences it for the day; each filing is also kept in a durable `$FM_HOME/data/bots/.filed/<name>` marker, because the backlog prunes done rows into an archive `fm-tasks-axi.sh show` does not search, so a task finished and pruned the same day stays silent. The dispatch seam, `fm bot file <name>-<YYYYMMDD>`, records that marker at filing time, before anything is dispatched, so a task filed, finished, and pruned between two watcher polls still cannot re-fire; a dated id filed any other way (a raw `fm-tasks-axi.sh add`) is only seen at the next poll and keeps that gap. `file` refuses anything but today's due id, prints the dispatch plan for the effective level (kind, delivery, role file, route, the routine fields, and the stop rule), files and holds an invalid bot for the captain instead, and never spawns; `firstmate/primary-policy.md` section 8 is the Captain's instruction to use it. Missed windows are not backfilled, and 02:xx times are refused because of DST. Each spec stores and validates its routine - role, project, route, schedule, scope, access (`none` or a `secret:<ref>` name, never a secret), notify, wall-clock and optional candidate/file/line limits, excluded paths - for the Captain and workers to apply; fm-bot itself enforces only the schedule and the level gate. A spec's `level` (`local-proposal` < `local-commit` < `push`) is only an upper bound, never an authorization. `local-proposal`, the default, needs only an active, well-formed spec. `local-commit` and `push` need captain authorization words with their own scope, an authorized-on date and an unexpired `expires`, file and line limits, and a registered project whose posture allows the level (`local-only` at most `local-commit`); `push` also needs excluded paths, one remote, a branch prefix, one push per run, a non-`+yolo` project, and the authorization quoted verbatim in `$FM_HOME/data/captain.md` naming the bot and project. `create` refuses any gate failure; `due` re-checks the gate every time and runs an elevated bot whose gate fails that day at `local-proposal` with the reason. `fm bot list` shows each bot's last run, the newest `<name>-<YYYYMMDD>` id the backlog lists or the marker holds. Commits and pushes stay gated by FirstMate's own per-action captain approval.

`skills/bot-builder` is the Captain's guide for "bot oluştur" / "create a bot": it collects the routine and level, refuses missing pieces (an elevated level without the captain's exact words, scope, and expiry; a mapped role with no `roles/<role>/ROLE.md`), and writes the spec only through `fm bot create`; it never activates the watcher check or dispatches. `commands/bots.md` is the read-only `/bots` prompt over `fm bot list`/`show`. `install.sh` step 7 links every `commands/*.md` into `~/.agents/commands` (OMP turns each into a slash command) the same way it links `skills/*` into `~/.agents/skills`, so both reach a primary Captain session only once they land on main and the primary checkout's `install.sh` runs; until then a primary Captain session cannot load `/bots` or `bot-builder`. `tests/bot-builder-trial.sh` (opt-in, `FM_LIVE_BOT_TRIAL=1`, real billable `omp` sessions) is evidence for the skill and command interaction only: it copies both into a disposable sandbox project's own `.agents/skills` and `.agents/commands` and runs a plain OMP session there against a disposable trial home, not a primary Captain session.

`tests/bot-pilot.sh` (opt-in, `FM_LIVE_BOT_PILOT=1`, real billable `omp` workers) is the P8 pilot, simulated end to end in a disposable lab: a lab `FM_HOME` from the official `bin/fm-lab-home.sh`, a disposable sandbox repository, and an isolated non-default Herdr session that only the official `bin/fm-herdr-lab.sh` provisions, drives, and tears down. Over nine simulated Stockholm days (sweeping every 5 minutes through the registered check's official snapshot run, across the 2026-10-25 DST change) it plays Firstmate's part - `fm bot file`, a brief from the printed plan, done-and-prune or a captain hold - and asserts one due line, one filing, and one dated report per local-proposal morning with no branch, file, or commit change, and two local-commit runs that each stop uncommitted on their dated bot branch at `needs-decision [key=commit-approval]`. It does not prove real elapsed days, a live `fm-watch.sh` loop, a Captain session, `fm-spawn`/treehouse dispatch, the approve-then-commit step, or `push`. Two P9 residuals are not proof of a real role or permission: the pilot's `roles/refactorist/ROLE.md` is a labelled stand-in in its disposable config copy, and the local-commit bot's authorization is an explicit fixture-only placeholder, never captain words; P9 must re-run with the real refactorist role and a real captain authorization.

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

Update the tracked configuration and reconcile installed state:

```sh
fm update
```

`fm update` fast-forwards the checkout to its remote tip (refusing a dirty or
diverged checkout, exactly as before) and then runs that checkout's own
`./install.sh` followed by `./install.sh --verify`, so machine-local state
never lags behind the tracked repository. A separate manual `./install.sh` is
no longer required after a successful `fm update`; run it directly only when
diagnosing installed state without pulling.

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
