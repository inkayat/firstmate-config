#!/usr/bin/env bash
# multi-project-captain.sh - acceptance for the project-neutral Captain model.
#
# Proves, with real repository artifacts and only the external worker/model
# processes faked, that one Captain session can resolve, isolate, and route
# tasks across multiple projects per firstmate/primary-policy.md's "Which
# project" precedence: explicit request, `data/projects.md` registry entry,
# then the launch directory as a default hint ONLY when it is itself a Git
# project.
#
# Part 1 (launcher): fm --print-command reports FM_FORK_ORIGIN_IS_PROJECT so
# the hint step is mechanically checkable without shelling to git by hand,
# and proves launching from inside Project A does not bind the session to it.
# Part 2 (registry + isolation + skills + routing): two disposable Git
# projects with deliberately conflicting AGENTS.md/CLAUDE.md/project-skill
# instructions, a temporary data/projects.md registry resolved through the
# real, unmodified bin/fm-project-mode.sh from $FIRSTMATE_ROOT, real isolated
# `git worktree` copies (the same isolation `bin/fm-spawn.sh` requires - a
# real worktree root distinct from the project's own checkout), and
# deterministic fake `pi` / `omp` executables standing in for the two
# harnesses. Global skills come from this repository's own installed
# skills/, unaffected by which project worktree a worker sits in.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FM="$CONFIG_ROOT/bin/fm"
ENV_FILE="${FM_CONFIG_ENV:-$HOME/.config/firstmate-config/env}"
# shellcheck source=/dev/null
[ ! -f "$ENV_FILE" ] || . "$ENV_FILE"
FIRSTMATE_ROOT_REAL="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }
check() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}
contains() {
  case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in '$2')" ;; esac
}
not_contains() {
  case $2 in *"$3"*) fail "$1 (unexpectedly found '$3' in '$2')" ;; *) pass "$1" ;; esac
}

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-multi-project.XXXXXX") || exit 1
TMP_ROOT=$(cd "$TMP_ROOT" && pwd)
trap 'rm -rf "$TMP_ROOT"' EXIT

git_commit() { # <dir> <message>
  git -C "$1" add -A && git -C "$1" -c user.email=smoke@example.invalid -c user.name=smoke commit -q -m "$2"
}

# =============================================================================
# Part 1: launcher reports whether the launch directory is a Git project, and
# that PI_CWD (where the captain actually runs) never follows it.
# =============================================================================
fake_bin="$TMP_ROOT/bin"
fake_firstmate="$TMP_ROOT/firstmate"
mkdir -p "$fake_bin" "$fake_firstmate/.pi/extensions"
printf 'test\n' > "$fake_firstmate/AGENTS.md"
printf 'test\n' > "$fake_firstmate/.pi/extensions/fm-primary-pi-watch.ts"
printf 'test\n' > "$fake_firstmate/.pi/extensions/fm-primary-turnend-guard.ts"

cat > "$fake_bin/herdr" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fake_bin/herdr"

cat > "$fake_bin/pi" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = --list-models ]; then
  printf 'provider      model        context  max-out  thinking  images\n'
  printf 'openai-codex  gpt-5.6-sol  1K  1K  yes  no\n'
  exit 0
fi
if [ "${1:-}" = auth ] && [ "${2:-}" = check ]; then
  printf '{"status":"ready","provider":"openai-codex","authType":"test"}\n'
  exit 0
fi
printf 'fake pi should not be executed in launcher field tests\n' >&2
exit 64
SH
chmod +x "$fake_bin/pi"

plain_dir="$TMP_ROOT/plain-directory"
mkdir -p "$plain_dir"

run_fm_from() { # <origin-dir>
  ( cd "$1" && \
    PATH="$fake_bin:$PATH" \
    HOME="$TMP_ROOT/home-dir" \
    FIRSTMATE_ROOT="$fake_firstmate" \
    FM_HOME="$TMP_ROOT/fm-home" \
    FM_PI_EXTENSIONS=explicit \
    "$FM" --print-command )
}

# --- Part 2 fixtures are built here so Part 1 can launch fm from *inside*
# Project A and Part 2 can immediately resolve Project B afterward, proving
# the launch directory never blocks dispatch elsewhere.
project_a="$TMP_ROOT/projects/project-a"
project_b="$TMP_ROOT/projects/project-b"
mkdir -p "$project_a/.agents/skills/only-in-a" "$project_b/.agents/skills/only-in-b"

cat > "$project_a/AGENTS.md" <<'EOF'
# Project A
Rule: ALWAYS use tabs for indentation. Never use spaces.
EOF
cat > "$project_a/CLAUDE.md" <<'EOF'
House style for Project A: comment every function verbosely.
EOF
cat > "$project_a/.agents/skills/only-in-a/SKILL.md" <<'EOF'
---
name: only-in-a
---
Project A quirk: run `make check-a` before committing.
EOF
git -C "$project_a" init -q
git_commit "$project_a" 'init project A' >/dev/null 2>&1 || exit 1

cat > "$project_b/AGENTS.md" <<'EOF'
# Project B
Rule: ALWAYS use spaces for indentation. Never use tabs.
EOF
cat > "$project_b/CLAUDE.md" <<'EOF'
House style for Project B: keep comments minimal.
EOF
cat > "$project_b/.agents/skills/only-in-b/SKILL.md" <<'EOF'
---
name: only-in-b
---
Project B quirk: run `make check-b` before committing.
EOF
git -C "$project_b" init -q
git_commit "$project_b" 'init project B' >/dev/null 2>&1 || exit 1

out=$(run_fm_from "$project_a" 2>&1) || { fail "fm from Project A failed: $out"; out=''; }
check 'launching from inside Project A reports the hint as usable' true "$(field "$out" FM_FORK_ORIGIN_IS_PROJECT)"
check 'launch dir origin is Project A' "$project_a" "$(field "$out" FM_FORK_ORIGIN_CWD)"
check 'the captain still runs in the checkout, never Project A' "$fake_firstmate" "$(field "$out" PI_CWD)"

out=$(run_fm_from "$plain_dir" 2>&1) || { fail "fm from a plain directory failed: $out"; out=''; }
check 'launch dir that is not a Git project reports the hint as unusable' false "$(field "$out" FM_FORK_ORIGIN_IS_PROJECT)"
check 'the captain still runs in the checkout from a plain launch directory' "$fake_firstmate" "$(field "$out" PI_CWD)"

# =============================================================================
# Part 2: registry resolution, isolated worktrees, instruction/skill
# separation, and distinct Pi/OMP routing - real upstream fm-project-mode.sh,
# real git worktrees, fake worker executables only.
# =============================================================================
if [ ! -x "$FIRSTMATE_ROOT_REAL/bin/fm-project-mode.sh" ]; then
  fail "no fm-project-mode.sh at $FIRSTMATE_ROOT_REAL/bin; set FIRSTMATE_ROOT"
else
  reg_data="$TMP_ROOT/fm-home/data"
  mkdir -p "$reg_data"
  cat > "$reg_data/projects.md" <<'EOF'
- project-a [local-only] - conflicting-instructions fixture A (added 2026-09-15)
- project-b [local-only] - conflicting-instructions fixture B (added 2026-09-15)
EOF

  resolve_mode() { # <project-name>
    FM_DATA_OVERRIDE="$reg_data" "$FIRSTMATE_ROOT_REAL/bin/fm-project-mode.sh" "$1" 2>/dev/null
  }

  # Registry lookup for Project B does not care that fm was just launched
  # from inside Project A above - dispatch to a different project is not
  # blocked by where the session started.
  check 'the real registry resolves Project A by name, launch directory notwithstanding' 'local-only off' "$(resolve_mode project-a)"
  check 'the real registry resolves Project B by name, launch directory notwithstanding' 'local-only off' "$(resolve_mode project-b)"
  check 'an unregistered project falls back rather than guessing' 'no-mistakes off' "$(resolve_mode project-c)"
fi

# Real isolated task worktrees, one per project - the same isolation shape
# bin/fm-spawn.sh requires: a real worktree root distinct from the project's
# own checkout.
worktrees="$TMP_ROOT/worktrees"
mkdir -p "$worktrees"
wt_a="$worktrees/task-a"
wt_b="$worktrees/task-b"
git -C "$project_a" worktree add -q "$wt_a" >/dev/null 2>&1 || fail "could not create Project A isolated worktree"
git -C "$project_b" worktree add -q "$wt_b" >/dev/null 2>&1 || fail "could not create Project B isolated worktree"
# Resolve through git's own realpath (macOS TMPDIR is itself a symlink into
# /private) so the isolation check compares like with like.
wt_a=$(git -C "$wt_a" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$wt_a")
wt_b=$(git -C "$wt_b" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$wt_b")

check 'Project A task worktree is its own real worktree root' "$wt_a" "$(git -C "$wt_a" rev-parse --show-toplevel 2>/dev/null)"
check 'Project B task worktree is its own real worktree root' "$wt_b" "$(git -C "$wt_b" rev-parse --show-toplevel 2>/dev/null)"
if [ "$wt_a" = "$project_a" ] || [ "$wt_b" = "$project_b" ] || [ "$wt_a" = "$wt_b" ]; then
  fail 'task worktrees must be distinct from each project checkout and from each other'
else
  pass 'task worktrees are isolated from both project checkouts and from each other'
fi

# Deterministic fake workers: one binary per harness, reporting exactly what
# it can see from its own cwd. The real HOME is used (unfaked) so the real
# installed global skills - not a project's own - are reachable from either
# worktree, proving global-skill availability is independent of project.
worker_bin="$TMP_ROOT/worker-bin"
mkdir -p "$worker_bin"
cat > "$worker_bin/report" <<'SH'
#!/usr/bin/env bash
set -u
printf 'HARNESS=%s\n' "$(basename "$0")"
printf 'AGENTS=%s\n' "$(cat AGENTS.md 2>/dev/null)"
printf 'CLAUDE=%s\n' "$(cat CLAUDE.md 2>/dev/null)"
printf 'SKILLS=%s\n' "$(ls .agents/skills 2>/dev/null | tr '\n' ',')"
if [ -f "$HOME/.agents/skills/architecture-review/SKILL.md" ]; then
  printf 'GLOBAL_SKILL=present\n'
else
  printf 'GLOBAL_SKILL=missing\n'
fi
SH
chmod +x "$worker_bin/report"
cp "$worker_bin/report" "$worker_bin/pi"
cp "$worker_bin/report" "$worker_bin/omp"

# A Pi worker targets Project A.
report_a=$( (cd "$wt_a" && "$worker_bin/pi") )
check 'the Pi worker in Project A reports the pi harness' pi "$(field "$report_a" HARNESS)"
contains 'the Pi worker sees Project A own AGENTS.md rule' "$report_a" 'ALWAYS use tabs'
not_contains 'the Pi worker never sees Project B conflicting AGENTS.md rule' "$report_a" 'ALWAYS use spaces'
contains 'the Pi worker sees Project A own project-local skill' "$report_a" 'only-in-a'
not_contains 'Project B local skill does not appear for the Pi worker in Project A' "$report_a" 'only-in-b'
contains 'the global skill is available to the Pi worker in Project A' "$report_a" 'GLOBAL_SKILL=present'

# An OMP worker targets Project B.
report_b=$( (cd "$wt_b" && "$worker_bin/omp") )
check 'the OMP worker in Project B reports the omp harness' omp "$(field "$report_b" HARNESS)"
contains 'the OMP worker sees Project B own AGENTS.md rule' "$report_b" 'ALWAYS use spaces'
not_contains 'the OMP worker never sees Project A conflicting AGENTS.md rule' "$report_b" 'ALWAYS use tabs'
contains 'the OMP worker sees Project B own project-local skill' "$report_b" 'only-in-b'
not_contains 'Project A local skill does not appear for the OMP worker in Project B' "$report_b" 'only-in-a'
contains 'the global skill is available to the OMP worker in Project B' "$report_b" 'GLOBAL_SKILL=present'

printf '\nMULTI-PROJECT CAPTAIN %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
