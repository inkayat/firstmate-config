---
name: bot-builder
description: Create, inspect, pause, resume, or remove a FirstMate bot - a scheduled daily routine that runs one role against one project (e.g. "bot oluştur", "create a bot", "make a nightly security bot", "list my bots"). Collects the routine, schedule, and permission level, refuses missing pieces, and writes the spec with `fm bot`; never activates or dispatches anything.
---

# Bot builder

A bot is a spec under `$FM_HOME/data/bots/<name>.md` that `fm bot` writes and
validates. It is not a process and it does not run anything by itself: the
one watcher check (`fm bot check-install`) only reports which bots are due,
and Firstmate dispatches ordinary tasks from those reports. This skill only
writes and manages specs.

`fm bot` is the only writer. Never create, edit, or delete a spec file by
hand, and never write `$FM_HOME/data/captain.md` from here.

## Hard limits

- Never run `fm bot check-install`, `fm-check-register.sh`, or any dispatch
  (`fm-spawn.sh`, `fm-tasks-axi.sh add`) from this skill. Activating the
  watcher check is a separate, explicit captain instruction.
- Never invent authorization. Authorization words are the captain's own
  words, quoted exactly from this conversation. If the captain has not said
  them, ask; do not paraphrase a request into an approval.
- Never pick a level higher than the captain asked for. `local-proposal` is
  the default.
- Never substitute a different role because the mapped one is missing. When
  `fm bot create` refuses with `unknown-role`, name the missing
  `roles/<role>/ROLE.md` and ask the captain which existing role to use.

## 1. Collect the routine

Ask in one batch for whatever is missing; do not create a partial spec.

| Field | Flag | Rule |
| --- | --- | --- |
| name | positional | lowercase letters, digits, hyphens, at most 40 |
| project | `--project` | the registered project name |
| role | `--role` | see the mapping below; `fm bot create` checks that `roles/<role>/ROLE.md` exists in the firstmate-config checkout |
| route | `--route "CATEGORY #N"` | an existing rule in `firstmate/crew-dispatch.json` (primary-policy.md section 3 owns which fits) |
| schedule | `--days`, `--at`, `--until` | Europe/Stockholm wall clock; `daily` or `mon,tue,...`; `--until` on the same day; never 02:xx |
| scope | `--scope` | one line: what the bot looks at and what it produces |
| wall-clock | `--wall-clock-min` | minutes per run |
| access | `--access` | `none` (default) or `secret:<reference-name>` - a reference, never a secret |
| notify | `--notify` | `report` (default) or `needs-decision-on-high` |
| limits | `--max-candidates`, `--max-files`, `--max-lines`, `--exclude` | optional at local-proposal |
| level | `--level` | `local-proposal` (default), `local-commit`, or `push` |

Role mapping (`fm bot create` is the existence check - do not pre-check with
your own path guesses; a refusal with `unknown-role` means stop and ask):

| Routine | Role | Typical route |
| --- | --- | --- |
| small refactor proposals | `refactorist` | `EXPLORE #2` |
| static security review | `security-engineer` | `REVIEW #2` |
| code review of recent changes | `code-reviewer` | `REVIEW #2` |
| structural or boundary review | `architecture` | `ARCHITECTURE #1` |
| adversarial check of a plan or claim | `tenth-man` | `TENTH-MAN #1` |
| ordinary delivery work | `senior-fullstack` | `IMPLEMENT #1` |

An explicit role or route from the captain wins over this table.

## 2. Permission level

- **`local-proposal`** - report and proposals only. Needs nothing beyond the
  routine above: no authorization words, no dates.
- **`local-commit`** - local branch changes, committed only after the
  captain's per-commit approval. Additionally needs, from the captain:
  - `--authorization "<captain's exact words>"`
  - `--authorization-scope "<what those words cover>"`
  - `--authorized-on YYYY-MM-DD` (the day the captain said it)
  - `--expires YYYY-MM-DD` (the captain's date; ask - never default one)
  - `--max-files N --max-lines N`
- **`push`** - everything `local-commit` needs, plus `--exclude PATH` (one or
  more), `--push-remote <remote>`, `--push-branch-prefix bot/<name>/`, and
  `--push-max-per-run 1`. The authorization words must name both the bot and
  the project, and must already appear verbatim in the captain's standing
  rules (`$FM_HOME/data/captain.md`); if they do not, stop and tell the
  captain - `fm bot create` will refuse it.

The project's registered posture caps the level (`local-only` allows at most
`local-commit`; `push` needs a project without `+yolo`). The level is an upper
bound, never an authorization: commits and pushes still need Firstmate's
normal per-action captain approval.

## 3. Create

Run `fm bot create <name> ...` with every collected flag. On refusal,
`fm bot` prints `refused (<code>): <reason>`; relay the reason, ask for what
is missing, and retry. Do not loosen a field to make it pass.

On success, run `fm bot show <name>` and report: name, level, role, project,
schedule (Europe/Stockholm), next window, and that the bot will not run until
the watcher check is activated.

## Other requests

- "list bots" / `/bots`: `fm bot list`.
- One bot's details: `fm bot show <name>`.
- What would run now: `fm bot due` (dry; never dispatches).
- Pause, resume, remove: `fm bot pause|resume|remove <name>`, only for the bot
  the captain named.
