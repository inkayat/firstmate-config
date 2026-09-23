# firstmate-config

`firstmate-config` is an opinionated, reproducible configuration layer around
the official [FirstMate](https://github.com/kunchenguid/firstmate) checkout. It
selects the Captain runtime, worker routing, shared skills, and machine-local
layout without forking or patching FirstMate.

The official checkout remains upstream-clean. Tracked configuration lives here;
operational state, credentials, sessions, and project registries stay outside
the repository. The latest tagged baseline is `v0.3.0`; `main` may contain newer
reviewed configuration changes.

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
- Twenty-six-rule semantic task routing across ten dispatch categories
- Claude-heavy, capacity-aware everyday routing
- Opus 5.5 reserved for architecture, deep reasoning, and highest-stakes
  review; GPT-6 Sol is the everyday cross-family challenger, with Astra
  limited to each lane's most extreme, exceptional escalation
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

| Category | Active candidates | Intent |
| --- | --- | --- |
| `QUICK` | OMP · Claude Haiku 4.5 low, or GPT-6 Luna low | Tiny edits, mechanical cleanup, quick factual work |
| `EXPLORE` | OMP · Claude Haiku 4.5 low, or GPT-6 Luna low | Read-only reconnaissance inside a repository |
| `RESEARCH` | OMP · Claude Sonnet 5 medium | External docs, APIs, standards, and upstream source |
| `REVIEW` | OMP · Claude Sonnet 5 medium | Ordinary correctness and maintainability review |
| `ARCHITECTURE` | OMP · Claude Opus 5.5 high, escalating to Opus 5.5 + GPT-6 Sol xhigh peers, then GPT-6 Astra xhigh only when exceptional | Boundaries, data models, migrations, structural decisions |
| `TENTH-MAN` | Pi · GPT-6 Sol xhigh (Claude-authored work, escalating to GPT-6 Astra xhigh only when critical/unresolved), or OMP · Claude Opus 5.5 xhigh (Astra/OpenAI-authored work) | Independent adversarial challenge |
| `IMPLEMENT` | OMP · Claude Sonnet 5 medium | Normal features, fixes, refactors, and tests |
| `IMPLEMENT-LARGE` | OMP · Claude Sonnet 5 high | Broad, mostly settled implementation |
| `DEEP` | OMP · Claude Opus 5.5 xhigh, with GPT-6 Sol xhigh reached only as an explicit escalation/second hypothesis (Pi diagnosis / OMP implementation), and GPT-6 Astra xhigh as the last, most exceptional escalation | Hard root-cause and reasoning-heavy work |
| `UI/BROWSER` | OMP · Claude Sonnet 5 high, or Opus 5.5 high for deep code-plus-browser work | Browser-visible behavior and end-to-end flows |
| `DEFAULT` | OMP · Claude Sonnet 5 medium | Work with no more specific category |

Routing philosophy:

- Claude handles most everyday work because practical capacity is larger.
- ARCHITECTURE's exceptional escalation pairs Opus 5.5 with GPT-6 Sol at
  xhigh as active quota-resolved peers, with Astra reserved for a further
  ultra-exceptional single-candidate escalation; DEEP instead routes to
  Sol, and Astra as DEEP's last escalation, only through explicit
  single-candidate escalation rules, so neither can be picked ahead of
  Opus 5.5 by quota.
- TENTH-MAN enforces model-family diversity: a Claude-authored change is
  challenged by Pi + GPT-6 Sol, escalating to Pi + GPT-6 Astra only for the
  most critical or unresolved cases; an Astra/OpenAI-authored change is
  challenged by OMP + Opus 5.5.
- REVIEW escalates from Sonnet medium to Sonnet high for complex diffs, to
  Opus 5.5 high for release-critical or high-blast-radius work, and
  optionally to a Pi + GPT-6 Sol cross-family second reviewer for the
  highest-stakes cases.
- Opus 5.5 is a deliberate escalation for sustained execution, exceptional
  architecture, deep reasoning, and highest-stakes review - not a default.
- Haiku and Luna cover cheap, fast work where their lane is appropriate.

More-specific rules handle harder exploration, Pi-oriented research,
complex/high-risk review, exceptional architecture, sustained large
execution, delicate implementation, and the diagnosis/implementation split
for deep work. The complete conditions and overrides live in the tracked
routing file and
[`firstmate/primary-policy.md`](firstmate/primary-policy.md).

## Context and skills

The intended precedence is:

```text
project-native instructions
  > project-local skills
  > role/task policy
  > shared worker skills
  > optional specialist vault picks
```

Project-native context includes root and nested `AGENTS.override.md`,
`AGENTS.md`, and `CLAUDE.md` files. Project-local skills live under tracked
project directories such as `.agents/skills`, `.claude/skills`, or
`.agent/skills`. Shared worker skills are installed under
`~/.agents/skills` for Pi and OMP discovery.

An optional, private, curated, provenance-pinned specialist skill vault
(`skills/vault.lock`, `FM_SKILL_VAULT_ROOT`) supplements shared worker skills
on a per-task, explicit-pick basis - it is never globally registered and never
adds to the existing per-task skill budget. Each pinned commit is cached in
its own immutable, commit-qualified directory, so an exact path handed to a
worker never changes underneath it. See `firstmate/primary-policy.md`
"Specialist skill vault" for the consumption contract and `fm doctor`'s
`vault.*` checks for its pin health.

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
catalog carries `anthropic/claude-sonnet-5`; Pi exposes it only through the
Claude Code provider extension as `pi-claude-code-provider/sonnet`, which is
not an OMP model id and is never checked against OMP's catalog. Each TSV row
carries an optional third `harness` column (`omp`, `pi`, or blank for both);
a row whose harness column does not match the active Captain harness is
skipped entirely, never probed and never selected, so an OMP Captain can
never be launched with a Pi-only provider id and a Pi Captain never loses its
own Sonnet fallback.

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
| `fm update` | Fast-forward the `firstmate-config` checkout, then reconcile and verify this machine via its own `install.sh`; refuse dirty or diverged state |
| `fm board` / `fm board --lavish` | Open the persistent Kanban board (terminal-browser by default, Lavish with `--lavish`); render a deterministically refreshed, LLM-free data projection with the same static template, and keep re-rendering it while the viewer is open so a browser refresh shows current work |
| `ponytail-update` | Prepare and validate a local Ponytail pin update without committing or pushing |

`fm doctor --json` and `fm version --json` provide machine-readable output.

`bin/fm-board` owns the board's `add`/`update`/`move`/`list`/`show`/`summary`/`render` CLI. Its persistent files live under `$FM_HOME/data/board/` (`state.json`, append-only `events.jsonl`, generated `board-data.js`); actual FirstMate backlog and execution records (`data/backlog.md`, `state/home-summary.json`) remain authoritative, and the board is only their deterministic, LLM-free projection.

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
