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
- Eleven-category semantic task routing
- Claude-heavy, capacity-aware everyday routing
- Fable 5.1 and Astra reserved for architecture and deep reasoning
- Multi-project operation with per-task project resolution
- Scoped `AGENTS.md` / `CLAUDE.md` context and project-local skills
- Reproducibly installed shared worker skills and external pins
- Browser/manual validation policy for user-visible work
- Read-only `fm doctor` and `fm version` diagnostics
- Fast-forward-only `fm update` and deterministic, idempotent installation

## Routing

[`firstmate/crew-dispatch.json`](firstmate/crew-dispatch.json) is the source of
truth. Categories describe semantic fit, not a simple size ladder; explicit
Captain choices can override the table.

| Category | Active candidates | Intent |
| --- | --- | --- |
| `QUICK` | OMP · Claude Haiku 4.5 low, or GPT-5.6 Luna low | Tiny edits, mechanical cleanup, quick factual work |
| `EXPLORE` | OMP · Claude Haiku 4.5 low | Read-only reconnaissance inside a repository |
| `RESEARCH` | OMP · Claude Sonnet 5 medium | External docs, APIs, standards, and upstream source |
| `REVIEW` | OMP · Claude Sonnet 5 medium | Ordinary correctness and maintainability review |
| `ARCHITECTURE` | Pi · GPT-6 Astra xhigh, or OMP · Claude Fable 5.1 xhigh | Boundaries, data models, migrations, structural decisions |
| `TENTH-MAN` | Pi · GPT-6 Astra xhigh | Independent adversarial challenge |
| `IMPLEMENT` | OMP · Claude Sonnet 5 medium | Normal features, fixes, refactors, and tests |
| `IMPLEMENT-LARGE` | OMP · Claude Sonnet 5 high | Broad, mostly settled implementation |
| `DEEP` | OMP · Claude Fable 5.1 xhigh, or GPT-6 Astra xhigh (Pi diagnosis / OMP implementation) | Hard root-cause and reasoning-heavy work |
| `UI/BROWSER` | OMP · Claude Sonnet 5 high | Browser-visible behavior and end-to-end flows |
| `DEFAULT` | OMP · Claude Sonnet 5 medium | Work with no more specific category |

Routing philosophy:

- Claude handles most everyday work because practical capacity is larger.
- Fable 5.1 and Astra share architecture and deep-reasoning work at xhigh.
- Astra remains the independent Tenth-Man lane.
- Opus is a deliberate escalation for sustained, large execution—not a default.
- Haiku and Luna cover cheap, fast work where their lane is appropriate.

More-specific rules handle harder exploration, Pi-oriented research, sustained
large execution, and the diagnosis/implementation split for deep work. The
complete conditions and overrides live in the tracked routing file and
[`firstmate/primary-policy.md`](firstmate/primary-policy.md).

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

Official FirstMate internal skills remain separate and are not installed as
shared worker skills. Context and skill selection are policy and handoff
mechanisms; they are not a formal proof of read order, compliance, or task
completion.

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
| `fm update` | Fast-forward the `firstmate-config` checkout; refuse dirty or diverged state |
| `ponytail-update` | Prepare and validate a local Ponytail pin update without committing or pushing |

`fm doctor --json` and `fm version --json` provide machine-readable output.

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
./install.sh
```

Prepare a Ponytail dependency update:

```sh
ponytail-update
git diff -- skills/external.lock
```

Review and commit that pin change through the normal Git workflow. Other
machines then converge with:

```sh
fm update
./install.sh
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
