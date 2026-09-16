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
#
# Part 2 (real dispatch/spawn seam): two disposable Git projects with
# deliberately conflicting AGENTS.md/CLAUDE.md/project-skill instructions,
# registered in a temporary data/projects.md. `bin/fm-project-mode.sh` is
# exercised only for what it actually is - upstream's own registered-posture
# lookup, never a project resolver (its header and AGENTS.md section 7 own
# that distinction). The real, unmodified `bin/fm-spawn.sh` from
# $FIRSTMATE_ROOT then dispatches one task per project on the real `tmux`
# backend (an isolated `TMUX_TMPDIR` server, never the shared session) with
# real `treehouse`-pooled worktrees, resolving each project through
# upstream's own `projects/<name>` shorthand - the one project-name-to-path
# mechanism firstmate already provides, never a second resolver invented
# here. Only the two harness executables (`pi`, `omp`) are faked - a plain
# `cat`/`ls` reporting its own launch cwd, never a stand-in for either
# harness's own native instruction/skill loader. What this proves is real
# dispatch/isolation plumbing: which worktree `fm-spawn.sh` actually launched
# each lane into, and that one project's files never leak into the other's
# worktree. It does NOT exercise Pi's or OMP's own native context/skill
# discovery (trust gating, search-root precedence, override handling) -
# `tests/worker-context.sh` is the offline acceptance for that, against each
# harness's real installed loader/documentation. A third, unregistered
# project name is dispatched the same way and refused by that same real seam
# - the honest "ask, don't guess" signal, not a simulated one. A temporary
# $HOME fixture makes global-skill availability deterministic instead of
# depending on the operator's real installed skills.
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
# Task tmp dirs are fixed at /tmp/fm-<id> by fm-spawn.sh itself, outside
# TMPDIR, so they are cleaned up by task id rather than by TMP_ROOT removal.
SPAWN_TASK_IDS=""
cleanup() {
  if [ -n "${SPAWN_TMUX_TMPDIR:-}" ]; then
    TMUX_TMPDIR="$SPAWN_TMUX_TMPDIR" tmux kill-server >/dev/null 2>&1 || true
    # kill-server can return slightly before the pane's own shell finishes
    # flushing its history file, which transiently blocks removal.
    sleep 0.3
    rm -rf "$SPAWN_TMUX_TMPDIR"
  fi
  for id in $SPAWN_TASK_IDS; do rm -rf "/tmp/fm-$id"; done
  rm -rf "$TMP_ROOT" 2>/dev/null
  [ ! -e "$TMP_ROOT" ] || rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

git_commit() { # <dir> <message>
  git -C "$1" add -A && git -C "$1" -c user.email=smoke@example.invalid -c user.name=smoke commit -q -m "$2"
}

# =============================================================================
# Shared fixtures: two disposable Git projects with deliberately conflicting
# AGENTS.md/CLAUDE.md/project-local skills, laid out under a temporary
# firstmate home's projects/ - upstream's own flat project layout
# (.agents/skills/project-management/SKILL.md "Projects live flat under
# projects/") - so the real `projects/<name>` shorthand resolves them.
# =============================================================================
fm_home="$TMP_ROOT/fm-home"
mkdir -p "$fm_home/state" "$fm_home/data" "$fm_home/config" "$fm_home/projects"
printf 'manual\n' > "$fm_home/config/backlog-backend"

project_a="$fm_home/projects/project-a"
project_b="$fm_home/projects/project-b"
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
cat > "$project_a/treehouse.toml" <<'EOF'
max_trees = 4
root = "./"
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
cat > "$project_b/treehouse.toml" <<'EOF'
max_trees = 4
root = "./"
EOF
git -C "$project_b" init -q
git_commit "$project_b" 'init project B' >/dev/null 2>&1 || exit 1

cat > "$fm_home/data/projects.md" <<'EOF'
- project-a [local-only] - conflicting-instructions fixture A (added 2026-09-15)
- project-b [local-only] - conflicting-instructions fixture B (added 2026-09-15)
EOF

# =============================================================================
# Part 1: launcher reports whether the launch directory is a Git project, and
# that CAPTAIN_CWD (where the captain actually runs) never follows it. Launching
# from inside Project A here, with Project B dispatched for real in Part 2,
# is the proof that the launch directory never blocks dispatch elsewhere.
# =============================================================================
fake_bin="$TMP_ROOT/bin"
fake_firstmate="$TMP_ROOT/firstmate"
mkdir -p "$fake_bin" "$fake_firstmate/.pi/extensions"
printf 'test\n' > "$fake_firstmate/AGENTS.md"
printf 'test\n' > "$fake_firstmate/.pi/extensions/fm-primary-pi-watch.ts"
printf 'test\n' > "$fake_firstmate/.pi/extensions/fm-primary-turnend-guard.ts"
mkdir -p "$fake_firstmate/.omp/extensions"
printf 'test\n' > "$fake_firstmate/.omp/extensions/fm-primary-omp-watch.ts"
printf 'test\n' > "$fake_firstmate/.omp/extensions/fm-primary-turnend-guard.ts"
cat > "$fake_bin/omp" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = models ] || exit 64
printf '{"models":[{"provider":"openai-codex","id":"gpt-5.6-sol","reasoning":true,"thinking":["high"]}]}\n'
SH
chmod +x "$fake_bin/omp"

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
    FM_HOME="$TMP_ROOT/fm-home-launcher" \
    FM_PI_EXTENSIONS=explicit \
    "$FM" --print-command )
}

out=$(run_fm_from "$project_a" 2>&1) || { fail "fm from Project A failed: $out"; out=''; }
check 'launching from inside Project A reports the hint as usable' true "$(field "$out" FM_FORK_ORIGIN_IS_PROJECT)"
check 'launch dir origin is Project A' "$project_a" "$(field "$out" FM_FORK_ORIGIN_CWD)"
check 'the captain still runs in the checkout, never Project A' "$fake_firstmate" "$(field "$out" CAPTAIN_CWD)"

out=$(run_fm_from "$plain_dir" 2>&1) || { fail "fm from a plain directory failed: $out"; out=''; }
check 'launch dir that is not a Git project reports the hint as unusable' false "$(field "$out" FM_FORK_ORIGIN_IS_PROJECT)"
check 'the captain still runs in the checkout from a plain launch directory' "$fake_firstmate" "$(field "$out" CAPTAIN_CWD)"

# =============================================================================
# Part 2a: data/projects.md through the real, unmodified fm-project-mode.sh -
# a registered-DELIVERY-POSTURE lookup only (its own header, and
# AGENTS.md section 7: "data/projects.md holds the captain's standing posture
# as context, not as this task's answer"). This is NOT project selection and
# is never asserted as such.
# =============================================================================
if [ ! -x "$FIRSTMATE_ROOT_REAL/bin/fm-project-mode.sh" ]; then
  fail "no fm-project-mode.sh at $FIRSTMATE_ROOT_REAL/bin; set FIRSTMATE_ROOT"
else
  resolve_posture() { # <project-name>
    FM_DATA_OVERRIDE="$fm_home/data" "$FIRSTMATE_ROOT_REAL/bin/fm-project-mode.sh" "$1" 2>/dev/null
  }
  check 'the real registry reports Project A registered posture' 'local-only off' "$(resolve_posture project-a)"
  check 'the real registry reports Project B registered posture' 'local-only off' "$(resolve_posture project-b)"
  check 'an unregistered name gets a conservative default posture, never a guessed one' 'no-mistakes off' "$(resolve_posture project-c)"
fi

# =============================================================================
# Part 2b: real project selection and isolation at the agent-owned seam -
# upstream's own `projects/<name>` shorthand in bin/fm-spawn.sh
# (resolve_project_dir_arg), never a resolver this repository invents.
# A registered name with a real clone under projects/<name> resolves and
# dispatches; an unregistered/ambiguous name has no such clone and the same
# real seam refuses rather than guessing - the actual "ask" signal.
# =============================================================================
if ! command -v tmux >/dev/null 2>&1; then
  fail 'tmux is required for the real dispatch-seam checks and is not on PATH'
elif ! command -v treehouse >/dev/null 2>&1; then
  fail 'treehouse is required for the real dispatch-seam checks and is not on PATH'
elif [ ! -x "$FIRSTMATE_ROOT_REAL/bin/fm-spawn.sh" ]; then
  fail "no fm-spawn.sh at $FIRSTMATE_ROOT_REAL/bin; set FIRSTMATE_ROOT"
else
  # Deterministic HOME fixture: the only global skill either worker can ever
  # see, never the operator's real ~/.agents/skills.
  spawn_home="$TMP_ROOT/spawn-home"
  mkdir -p "$spawn_home/.agents/skills/global-demo"
  printf -- '---\nname: global-demo\n---\nAvailable to every project.\n' > "$spawn_home/.agents/skills/global-demo/SKILL.md"

  worker_bin="$TMP_ROOT/worker-bin"
  mkdir -p "$worker_bin"
  # The only faked pieces: the two harness executables. --help must return
  # immediately (fm-spawn.sh probes it before launch to detect --tui-mode);
  # any other invocation is the real launch, so it reports exactly what the
  # real launched process can see, from its own real cwd.
  cat > "$worker_bin/report" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = --help ]; then
  printf 'usage: report [options] [prompt]\n'
  exit 0
fi
{
  printf 'HARNESS=%s\n' "$(basename "$0")"
  printf 'AGENTS=%s\n' "$(cat AGENTS.md 2>/dev/null)"
  printf 'CLAUDE=%s\n' "$(cat CLAUDE.md 2>/dev/null)"
  printf 'SKILLS=%s\n' "$(ls .agents/skills 2>/dev/null | tr '\n' ',')"
  if [ -f "$HOME/.agents/skills/global-demo/SKILL.md" ]; then
    printf 'GLOBAL_SKILL=present\n'
  else
    printf 'GLOBAL_SKILL=missing\n'
  fi
} > worker-report.txt
SH
  chmod +x "$worker_bin/report"
  cp "$worker_bin/report" "$worker_bin/pi"
  cp "$worker_bin/report" "$worker_bin/omp"

  mk_brief() { # <task-id>
    mkdir -p "$fm_home/data/$1"
    cat > "$fm_home/data/$1/brief.md" <<EOF
# Task

## Captain's intent
Fixture acceptance task $1.

## Firstmate spec
Deterministic fixture worker; no real work is performed.
EOF
  }
  mk_brief task-mpc-a
  mk_brief task-mpc-b
  mk_brief task-mpc-c
  SPAWN_TASK_IDS="task-mpc-a task-mpc-b task-mpc-c"

  # A short, directly-/tmp-rooted socket dir: macOS's sockaddr_un limit
  # (~104 bytes) is shorter than TMP_ROOT's own path under a long per-process
  # $TMPDIR, so the tmux socket needs its own short home, cleaned by name in
  # cleanup() regardless of TMP_ROOT.
  SPAWN_TMUX_TMPDIR=$(mktemp -d /tmp/fm-mpc-tmux.XXXXXX) || exit 1

  run_spawn() { # <task-id> <project-shorthand> <harness>
    TMUX_TMPDIR="$SPAWN_TMUX_TMPDIR" \
    PATH="$worker_bin:$PATH" \
    HOME="$spawn_home" \
    FM_HOME="$fm_home" \
    FM_BACKEND=tmux \
    timeout 60 "$FIRSTMATE_ROOT_REAL/bin/fm-spawn.sh" "$1" "$2" \
      --mode local-only --yolo off --harness "$3" --model fixture-model --effort low
  }

  # Neither pi nor omp gets a busy/composer confirmation wait in fm-spawn.sh
  # (that gate is kimi/rovo/agy-only), so it returns as soon as the launch
  # text and Enter are sent - before the fake worker's own fork+exec+write
  # is guaranteed to land. Poll briefly for the report rather than racing it.
  wait_for_report() { # <path>
    local path=$1 waited=0
    while [ ! -s "$path" ] && [ "$waited" -lt 100 ]; do
      sleep 0.1
      waited=$((waited + 1))
    done
  }

  # The fake-pi lane dispatches to Project A.
  spawn_a_out=$(run_spawn task-mpc-a projects/project-a pi 2>&1)
  spawn_a_status=$?
  if [ "$spawn_a_status" -ne 0 ]; then
    fail "real spawn of task-mpc-a (Project A, pi) failed: $spawn_a_out"
  else
    contains 'the real spawn reports the pi harness for Project A' "$spawn_a_out" 'harness=pi'
    meta_a=$(cat "$fm_home/state/task-mpc-a.meta" 2>/dev/null)
    check 'the real spawn records the pi harness for Project A in task metadata' pi "$(field "$meta_a" harness)"
    wt_a=$(field "$meta_a" worktree)
    check 'the real spawn resolved Project A by its registered project name' "$project_a" "$(field "$meta_a" project)"
    if [ -z "$wt_a" ] || [ "$wt_a" = "$project_a" ]; then
      fail "Project A's real spawn worktree is missing or is the project checkout itself: '$wt_a'"
    else
      check 'Project A task worktree is a real, distinct worktree root' "$wt_a" "$(git -C "$wt_a" rev-parse --show-toplevel 2>/dev/null)"
    fi
    wait_for_report "$wt_a/worker-report.txt"
    report_a=$(cat "$wt_a/worker-report.txt" 2>/dev/null)
    contains "Project A's dispatched worktree cwd contains Project A's own AGENTS.md rule (dispatch/isolation, not pi native discovery)" "$report_a" 'ALWAYS use tabs'
    not_contains "Project A's dispatched worktree cwd never contains Project B's conflicting AGENTS.md rule" "$report_a" 'ALWAYS use spaces'
    contains "Project A's dispatched worktree cwd contains Project A's own project-local skill" "$report_a" 'only-in-a'
    not_contains "Project B's local skill never reaches Project A's dispatched worktree cwd" "$report_a" 'only-in-b'
    contains "the global skill fixture is visible from Project A's dispatched worktree cwd" "$report_a" 'GLOBAL_SKILL=present'
  fi

  # The fake-omp lane dispatches to Project B.
  spawn_b_out=$(run_spawn task-mpc-b projects/project-b omp 2>&1)
  spawn_b_status=$?
  if [ "$spawn_b_status" -ne 0 ]; then
    fail "real spawn of task-mpc-b (Project B, omp) failed: $spawn_b_out"
  else
    contains 'the real spawn reports the omp harness for Project B' "$spawn_b_out" 'harness=omp'
    meta_b=$(cat "$fm_home/state/task-mpc-b.meta" 2>/dev/null)
    check 'the real spawn records the omp harness for Project B in task metadata' omp "$(field "$meta_b" harness)"
    wt_b=$(field "$meta_b" worktree)
    check 'the real spawn resolved Project B by its registered project name' "$project_b" "$(field "$meta_b" project)"
    if [ -z "$wt_b" ] || [ "$wt_b" = "$project_b" ]; then
      fail "Project B's real spawn worktree is missing or is the project checkout itself: '$wt_b'"
    else
      check 'Project B task worktree is a real, distinct worktree root' "$wt_b" "$(git -C "$wt_b" rev-parse --show-toplevel 2>/dev/null)"
    fi
    wait_for_report "$wt_b/worker-report.txt"
    report_b=$(cat "$wt_b/worker-report.txt" 2>/dev/null)
    contains "Project B's dispatched worktree cwd contains Project B's own AGENTS.md rule (dispatch/isolation, not omp native discovery)" "$report_b" 'ALWAYS use spaces'
    not_contains "Project B's dispatched worktree cwd never contains Project A's conflicting AGENTS.md rule" "$report_b" 'ALWAYS use tabs'
    contains "Project B's dispatched worktree cwd contains Project B's own project-local skill" "$report_b" 'only-in-b'
    not_contains "Project A's local skill never reaches Project B's dispatched worktree cwd" "$report_b" 'only-in-a'
    contains "the global skill fixture is visible from Project B's dispatched worktree cwd" "$report_b" 'GLOBAL_SKILL=present'
  fi

  if [ -n "${wt_a:-}" ] && [ -n "${wt_b:-}" ] && [ "$wt_a" = "$wt_b" ]; then
    fail 'Project A and Project B were dispatched into the same worktree'
  else
    pass 'Project A and Project B were dispatched into distinct isolated worktrees'
  fi

  # An unregistered/ambiguous project name has no real clone to resolve
  # against, so the same real seam refuses rather than guessing - this is
  # the honest mechanical half of "ask, don't guess"; deciding to actually
  # ask the captain is the agent-owned half this shell test cannot drive.
  spawn_c_out=$(run_spawn task-mpc-c projects/project-c pi 2>&1)
  spawn_c_status=$?
  if [ "$spawn_c_status" -eq 0 ]; then
    fail "spawn against an unregistered project unexpectedly succeeded: $spawn_c_out"
  else
    pass 'dispatching an unregistered project name is refused by the real spawn seam'
    contains 'the refusal names the missing project directory, not a guessed one' "$spawn_c_out" 'project-c'
  fi
  if [ -e "$fm_home/state/task-mpc-c.meta" ]; then
    fail 'an unregistered project must not produce task metadata'
  else
    pass 'an unregistered project leaves no task metadata behind'
  fi
fi

printf '\nMULTI-PROJECT CAPTAIN %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
