# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- `README.md` is the project-level source of truth: layout, install, the multi-project Captain model, and routing. Read it first.
- The Captain's project-selection precedence ("which project", the launch-directory hint, and why a project's instructions/skills are never preloaded at startup) is owned by `firstmate/primary-policy.md` section 1; do not duplicate it here.
- Tests: `tests/smoke.sh` (launcher/install/herdr), `tests/model-selection.sh` (captain startup model chain), `tests/multi-project-captain.sh` (project resolution, worktree isolation, instruction/skill separation, Pi/OMP routing). Run all three after touching `bin/fm`, `firstmate/*.md`, or `install.sh`.
- `./install.sh --verify` is read-only and safe from a disposable worktree. Plain `./install.sh` (no `--verify`) repoints the *live machine's* symlinks (`~/.local/bin/fm`, `~/.agents/skills/*`, `~/.firstmate/config/crew-dispatch.json`) at whatever checkout you run it from - never run it from a task worktree, only from the machine's primary checkout. Because of this, `tests/smoke.sh` run from a worktree will always report installer drift against the primary checkout's path; that failure is expected there and is not a regression.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
