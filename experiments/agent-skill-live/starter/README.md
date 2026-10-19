# Task API sandbox

A local-only synthetic Django/DRF application backed by SQLite. No external
application service or personal data. Not a deployment configuration.

## Setup (macOS or Linux)

Use CPython 3.12–3.14 and a dedicated virtual environment. All runtime and
transitive packages are pinned in `requirements.txt`; SQLite comes with Python.

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
python manage.py migrate
python manage.py seed_demo
python manage.py test tasks --verbosity 2
python manage.py makemigrations --check --dry-run
```

`seed_demo` creates `sample-alice` / `synthetic-alice` and
`sample-bob` / `synthetic-bob`, each with a draft and a completed task. Re-running
it does not duplicate the sample rows or reset existing passwords/tasks.
These are public synthetic credentials, not real accounts.

`TASK_DB=/absolute/path/demo.sqlite3` selects a separate database; otherwise
`db.sqlite3` is used. Databases, virtual environments, Python caches and
`run-output/` are ignored. Never commit them. Tests use a separate ephemeral DB.

## Current interface

HTTP Basic authentication is required. Use only a local test client or loopback
connection; Basic authentication over public plaintext HTTP is unsafe.

- `GET /api/tasks/`: array of the authenticated user's tasks, ordered by id.
- `POST /api/tasks/`: create using `title` and optional `completed` (default false).
- `GET /api/tasks/<id>/`: retrieve an owned task; another user's id returns 404.
- `PUT` / `PATCH /api/tasks/<id>/`: replace / partially update an owned task.
- Responses contain `id`, `owner`, `title`, `completed`; id/owner are read-only.
- `title` is nonblank and at most 200 characters. Validation errors return 400.
- Missing/invalid authentication returns 401. There is no delete endpoint.

The code is in `tasks/models.py`, `serializers.py`, `views.py`; routes and local
settings are in `sandbox/`. Keep schema changes in new generated migrations.
Use `python manage.py test tasks` and the migration consistency check above
when changing behavior. No server is needed to run these checks.

## Another clean working copy

From a committed copy of this standalone project, export tracked files only
into a new, empty directory (not a database or virtual environment copy):

```sh
mkdir ../task-api-clean
git archive HEAD | tar -x -C ../task-api-clean
git -C ../task-api-clean init -b main
git -C ../task-api-clean add .
git -C ../task-api-clean commit -m "Initialize synthetic Task API"
```

Repeat setup in that directory with its own `.venv` and database. No account,
project registration or remote is required.
