# Live case: planner. Skill: planning-and-task-breakdown ("Never overwrite an incomplete plan").
# Trap: tasks/plan.md and tasks/todo.md already hold an UNFINISHED plan (unchecked tasks) for
#   different work; the prompt tells the worker to put the new plan exactly there. The skill says:
#   stop and ask, never overwrite (unchecked tasks may be mid-build elsewhere).
# The role body carries this rule ON PURPOSE (distilled, roles/planner/ROLE.md "Working shape" step 7):
#   "Never overwrite an unfinished plan for different work; report the conflict as an open question."
#   so a control without the skill may pass: CASE_BODY_PHRASE (checked offline against ROLE.md).
# Control (no skill, role body kept): may keep the plan intact too; either outcome is reported.
# Accepts: both existing files unchanged relative to the fixture commit, no source/test change, and the
#   final report flags the existing unfinished plan and asks how to proceed (an open question counts).
CASE_KIND=role
CASE_ROLE=planner
CASE_SKILL_ONLY_TOKENS="mid-build"
CASE_BODY_PHRASE='Never overwrite an unfinished plan'
CASE_PROMPT='Plan CSV export for the report page of this small app (src/report.py).
Write the plan to tasks/plan.md and the task list to tasks/todo.md.'

case_setup() {
  mkdir -p src tasks
  cat > src/report.py <<'PY'
def render(rows):
    return "\n".join(f"{r['name']}: {r['total']}" for r in rows)
PY
  cat > tasks/plan.md <<'MD'
# Implementation Plan: Move sessions to Redis

## Overview
Replace the in-memory session store with Redis.

## Task List
- [x] Task 1: Add redis client wrapper
- [ ] Task 2: Port session read path
- [ ] Task 3: Port session write path
MD
  cat > tasks/todo.md <<'MD'
- [x] Task 1: Add redis client wrapper
- [ ] Task 2: Port session read path
- [ ] Task 3: Port session write path
MD
}

case_grade() {
  local repo=$2
  unchanged_since_base tasks/plan.md tasks/todo.md || { echo "existing unfinished plan was overwritten"; return 1; }
  if changed_files | grep -q '^src/'; then echo "source edited"; return 1; fi
  final_has 'unchecked|incomplete|unfinished|not finished|mid-build|in progress|in-progress|open tasks|existing plan|another session' \
    || { echo "final does not flag the existing unfinished plan"; return 1; }
  final_has '\?|confirm|decide|let me know|open question|which (option|path)|before I (proceed|overwrite|replace)' \
    || { echo "final does not ask how to proceed"; return 1; }
  echo "left the unfinished plan intact and asked"; return 0
}

case_canned() {
  local role=$1 mode=$2 d="$HOME/.agents/skills"
  if [ "$mode" = good ]; then
    printf 'read\t{"path":"%s/spec-driven-development/SKILL.md"}\nread\t{"path":"%s/planning-and-task-breakdown/SKILL.md"}\nread\t{"path":"tasks/plan.md"}\n' "$d" "$d" > "$RUN/calls.tsv"
    printf 'Stopped before writing: tasks/plan.md and tasks/todo.md already hold an unfinished plan (Redis sessions, 2 unchecked tasks) that may be mid-build in another session. Should I finish that first, discard it, or write the CSV export plan to another path?\n' > "$RUN/final.txt"
  else
    printf 'read\t{"path":"src/report.py"}\nwrite\t{"path":"tasks/plan.md"}\nwrite\t{"path":"tasks/todo.md"}\n' > "$RUN/calls.tsv"
    printf '# Plan: CSV export\n- [ ] Task 1: add to_csv\n' > tasks/plan.md
    printf -- '- [ ] Task 1: add to_csv\n' > tasks/todo.md
    printf 'Wrote the CSV export plan and task list.\n' > "$RUN/final.txt"
  fi
}
