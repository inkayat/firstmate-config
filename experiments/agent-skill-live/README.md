# Temporary live-observation preparation

This package prepares inputs only. It does not run the deferred implementation,
review or documentation assignments, define a workflow, or change routing.

## Starter payload

`starter/` alone is the portable project. It contains a small authenticated
Django/DRF + SQLite API, synthetic seed command, initial migration, functional
baseline tests, pinned requirements and a neutral setup README. It deliberately
has no due-date feature or overdue filtering. It has no agent instructions or
project-local skills. The eventual `docs/task-api.md` is not created here.

From a frozen config checkout, export into a **new empty** destination outside
that checkout. The supervising FirstMate provisions its unused local project;
this package does not register projects or allocate worktrees.

```sh
FROZEN=/path/to/frozen/firstmate-config
STARTER_COMMIT=<starter-package-commit>
DEST=/path/to/new/task-api-sandbox
mkdir "$DEST"
git -C "$FROZEN" archive "$STARTER_COMMIT:experiments/agent-skill-live/starter" | tar -x -C "$DEST"
git -C "$DEST" init -b main
git -C "$DEST" add .
git -C "$DEST" commit -m "Initialize synthetic Task API"
```

Then follow `$DEST/README.md` using its own virtual environment and database.
Expected top level: `.gitignore`, `README.md`, `requirements.txt`, `manage.py`,
`sandbox/`, `tasks/`. No parent config policies, observer notes, task files,
source additions, databases, virtual environments or run evidence are exported.
The same archive command works on macOS and Omarchy/Linux with Python, Git and tar.

## Deferred task text

`future-tasks/A-implementation.txt` is the first natural task input, for a later
fresh session. Keep `B-review.txt` and `C-documentation.txt` until their actual
inputs exist. B requires a real immutable artifact from A; it intentionally
contains no invented revision. `observer.md` is operator-only evaluation material,
not worker input. Do not copy anything except the selected natural task text
into the later assignment. No acceptance task has been executed in preparation.
