#!/usr/bin/env bash
# captain-review-scenarios.sh - real, isolated Captain scenarios for
# firstmate/primary-policy.md's "Independent review before merge" section
# (AGENTS.md section 7's task lifecycle owns the underlying dispatch this
# policy layers advisory guidance on top of).
#
# Four scenarios, matching the policy's own named cases:
#   A. A low-risk QUICK change may skip independent review, with a stated
#      reason.
#   B. A substantive IMPLEMENT change, with NO task-specific user review
#      request in its brief.
#   C. An IMPORTANT/BLOCKER finding withholds merge-readiness, is fixed,
#      then receives a targeted independent re-review - with the captain's
#      explicit authorization to request and hold review present in the
#      brief.
#   D. A premium/Opus implementer does not waive or replace independent
#      review by a separate, cheaper-model reviewer.
#
# This is real, not mocked: every dispatch below is a real, unmodified
# `bin/fm-spawn.sh` launch of the real `omp` harness on the real tmux
# backend, doing real work against a real disposable Git project, inside a
# real scratch clone of official FirstMate (local clone, remote removed -
# never a network fetch of the canonical checkout) and a real scratch
# FM_HOME per scenario. No fake agents, no fake reports, no reimplemented
# review logic: every finding printed below is the real worker's own real
# output, captured from its real tmux pane.
#
# Opt-in and honesty contract: this suite makes real, billable model calls
# and takes real wall-clock minutes, so it never runs by default. Without
# FM_LIVE_CAPTAIN_SCENARIOS=1 set, every scenario reports SKIPPED with an
# explicit reason - never PASS. A missing prerequisite (tmux, treehouse,
# omp, the official FirstMate checkout, or omp's own credential store)
# reports BLOCKED with the exact missing piece - also never PASS. This
# mirrors the platform's own honesty: firstmate-config's independent-review
# policy is advisory guidance with no trusted enforcement runner
# (primary-policy.md "Independent review before merge" says so directly),
# so this script proves real dispatch behavior against that advisory
# policy, never a mechanical policy gate it does not actually have.
#
# Real dispatches never pin an LLM worker's own incidental wording -
# assertions below are structural (a real commit landed on the expected
# branch, a real status line was appended with the expected machine-
# readable shape, a reviewer's own recorded task metadata carries a
# different model than the implementer's) never a `contains` match on a
# model's free-text explanation, which is expected to vary run to run.
#
# Scenario B's real, structural result is a genuine, disclosed policy
# conflict, not a bug in this script: official FirstMate's own AGENTS.md
# section 7 ("otherwise follow the faster path without adding an
# independent reviewer"; "A separate review or audit is allowed only when
# the captain explicitly requests that deliverable or the authorized task
# is a knowledge-only review") means a substantive IMPLEMENT task with no
# task-specific review request never gets a second dispatched reviewer in
# real practice - contradicting this configuration's own
# primary-policy.md, which calls that same shape of change
# review-required. This script never resolves that conflict (it cannot:
# official FirstMate is out of scope for this configuration, and inventing
# enforcement here would be pseudo-enforcement) - it reports scenario B as
# real, structural FAIL/BLOCKED evidence of the conflict, every time it is
# run live, until the two policies are reconciled by someone with standing
# to change one of them.
#
# Cleanup: every scratch directory and tmux socket this script creates is
# removed before it exits, success or failure (trap below) - nothing here
# is left behind in the worktree or under /tmp.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${FM_CONFIG_ENV:-$HOME/.config/firstmate-config/env}"
# shellcheck source=/dev/null
[ ! -f "$ENV_FILE" ] || . "$ENV_FILE"
FIRSTMATE_ROOT_REAL="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
skip() { printf 'SKIP - %s\n' "$1"; }
blocked() { printf 'BLOCKED - %s\n' "$1" >&2; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi; }
contains() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in '$2')" ;; esac; }
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }

if [ "${FM_LIVE_CAPTAIN_SCENARIOS:-0}" != 1 ]; then
  skip 'A: low-risk QUICK may skip review with a stated reason - live run not opted in (set FM_LIVE_CAPTAIN_SCENARIOS=1)'
  skip 'B: substantive IMPLEMENT, no task-specific review request - live run not opted in (set FM_LIVE_CAPTAIN_SCENARIOS=1)'
  skip 'C: IMPORTANT/BLOCKER finding -> fix -> targeted re-review - live run not opted in (set FM_LIVE_CAPTAIN_SCENARIOS=1)'
  skip 'D: premium/Opus implementer does not waive independent review - live run not opted in (set FM_LIVE_CAPTAIN_SCENARIOS=1)'
  printf '\nCAPTAIN REVIEW SCENARIOS SKIPPED (opt-in required)\n'
  exit 0
fi

for tool in tmux treehouse omp git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    blocked "$tool is required for a live run and is not on PATH"
    printf '\nCAPTAIN REVIEW SCENARIOS BLOCKED\n'
    exit 1
  fi
done
if [ ! -x "$FIRSTMATE_ROOT_REAL/bin/fm-spawn.sh" ]; then
  blocked "no fm-spawn.sh at $FIRSTMATE_ROOT_REAL/bin; set FIRSTMATE_ROOT"
  printf '\nCAPTAIN REVIEW SCENARIOS BLOCKED\n'
  exit 1
fi
if [ ! -d "$HOME/.omp" ]; then
  blocked 'no real omp credential store at $HOME/.omp; omp must be logged in for a live run'
  printf '\nCAPTAIN REVIEW SCENARIOS BLOCKED\n'
  exit 1
fi

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-captain-scenarios.XXXXXX") || exit 1
TMP_ROOT=$(cd "$TMP_ROOT" && pwd)
SOCKET_LOG="$TMP_ROOT/.sockets"
: > "$SOCKET_LOG"
cleanup() {
  # tmux kill-server alone does not reliably terminate the real omp
  # process running inside each pane on this platform (observed directly:
  # omp survived kill-server and kept running/writing real cache state
  # after the script that spawned it had already exited) - so every real
  # worker process whose own command line names this exact disposable
  # TMP_ROOT is force-killed directly first, by PID, before the tmux
  # servers and directories are torn down. Socket paths are read from a
  # file this cleanup itself owns (SOCKET_LOG), never a shell array:
  # spawn_worker is invoked via command substitution at every call site
  # (`X_WT=$(spawn_worker ...)`), which bash runs in a forked subshell,
  # so an array append inside spawn_worker would be silently discarded
  # the moment that subshell exits and never reach this function at all.
  for pid in $(pgrep -f "$TMP_ROOT" 2>/dev/null); do
    kill -9 "$pid" 2>/dev/null || true
  done
  while IFS= read -r sock; do
    [ -n "$sock" ] || continue
    TMUX_TMPDIR="$sock" tmux kill-server >/dev/null 2>&1 || true
    # Belt-and-suspenders: kill-server itself is observed to sometimes
    # leave the tmux server process alive (rare but real on this
    # platform); find any process still holding a file open under this
    # exact socket dir and force-kill it directly too.
    for pid in $(lsof -t +D "$sock" 2>/dev/null); do
      kill -9 "$pid" 2>/dev/null || true
    done
    rm -rf "$sock"
  done < "$SOCKET_LOG"
  chmod -R u+w "$TMP_ROOT" 2>/dev/null || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

# A real, local, offline clone of official FirstMate with the remote
# removed - never a network fetch of the canonical checkout, and never
# written to (each spawn below gets its own scratch FM_HOME/projects
# clone of the disposable target project, not this checkout).
SCRATCH_FIRSTMATE="$TMP_ROOT/firstmate-scratch"
git clone --no-hardlinks -q "$FIRSTMATE_ROOT_REAL" "$SCRATCH_FIRSTMATE" || {
  blocked "could not clone $FIRSTMATE_ROOT_REAL locally"
  printf '\nCAPTAIN REVIEW SCENARIOS BLOCKED\n'
  exit 1
}
git -C "$SCRATCH_FIRSTMATE" remote remove origin 2>/dev/null || true

# new_scratch_home <scenario-name> -> path to a fresh, isolated FM_HOME.
# Deliberately does NOT override HOME: omp resolves its own real
# credential/session store from $HOME/.omp, and a scratch HOME override
# hides that store, so every dispatch would fail with "No API key found"
# despite the real machine being logged in (confirmed the hard way -
# omp itself also does not tolerate a symlinked $HOME/.omp, replacing it
# with a fresh, uncredentialed real directory at startup). Project
# resolution is scoped by FM_HOME's own `projects/<name>` shorthand, not
# by HOME, so real HOME carries no isolation cost here: these scenarios
# never touch project or skill discovery, only real dispatch/review
# behavior.
new_scratch_home() { # <name>
  local dir="$TMP_ROOT/$1"
  mkdir -p "$dir/fm-home/state" "$dir/fm-home/data" "$dir/fm-home/config" "$dir/fm-home/projects"
  printf '%s' "$dir"
}

# new_scratch_project <dir> -> a tiny, real, disposable Git project with
# one trivial source file, registered at fm-home/projects/scratch-target
# so bin/fm-spawn.sh's own real `projects/<name>` shorthand resolves it -
# never a second project resolver invented here.
new_scratch_project() { # <scenario-dir>
  local proj="$1/fm-home/projects/scratch-target"
  mkdir -p "$proj"
  cat > "$proj/scratch.py" <<'PY'
def add(a, b):
    return a + b
PY
  git -C "$proj" init -q
  git -C "$proj" -c user.email=t@example.invalid -c user.name=t add -A
  git -C "$proj" -c user.email=t@example.invalid -c user.name=t commit -qm init
  git -C "$proj" branch -m main
}

# spawn_worker <scenario-dir> <task-id> <model> <effort> <brief-body> ->
# writes the brief, dispatches the real, unmodified fm-spawn.sh on an
# isolated tmux socket (never the shared/live session) with the real
# ambient HOME (see new_scratch_home), and prints the resolved worktree
# path on success or empty on failure. The worktree path is read back
# from the task's own real state/<id>.meta (one key=value per line, the
# same file `fm doctor`/other real dispatches key off), never parsed out
# of fm-spawn.sh's single-line human summary, which packs
# harness=/kind=/mode=/yolo=/window=/worktree= onto one line no `field()`
# anchor can isolate.
spawn_worker() { # <dir> <task-id> <model> <effort> <brief-file>
  local dir=$1 id=$2 model=$3 effort=$4 brief=$5
  mkdir -p "$dir/fm-home/data/$id"
  cp "$brief" "$dir/fm-home/data/$id/brief.md"
  local sock; sock=$(mktemp -d "/tmp/fm-cap-$id.XXXXXX") || return 1
  printf '%s\n' "$sock" >> "$SOCKET_LOG"
  local out
  out=$(TMUX_TMPDIR="$sock" FM_HOME="$dir/fm-home" FM_BACKEND=tmux \
    timeout 180 "$SCRATCH_FIRSTMATE/bin/fm-spawn.sh" "$id" projects/scratch-target \
    --mode local-only --yolo off --harness omp --model "$model" --effort "$effort" 2>&1)
  local rc=$?
  [ "$rc" -eq 0 ] || { fail "spawn of $id failed: $out"; return 1; }
  field "$(cat "$dir/fm-home/state/$id.meta" 2>/dev/null)" worktree
}

# wait_for_status <status-file> <timeout-seconds> -> polls (bounded, never
# infinite) for the worker's own durable status-file append, exactly the
# convention this task's own worker role contract uses.
wait_for_status() { # <status-file> <timeout>
  local f=$1 budget=$2 waited=0
  while [ ! -s "$f" ] && [ "$waited" -lt "$budget" ]; do
    sleep 5
    waited=$((waited + 5))
  done
  [ -s "$f" ]
}

# =============================================================================
# A. QUICK, low-risk: may skip review with a stated reason.
# =============================================================================
A_DIR=$(new_scratch_home scenario-a)
new_scratch_project "$A_DIR"
A_STATUS="$A_DIR/status"
cat > "$TMP_ROOT/brief-a.md" <<EOF
# Task

## Captain's intent
Add a one-line docstring to the \`add\` function in \`scratch.py\` explaining
what it returns. Narrowly scoped, purely cosmetic: no behavior change, no
new tests, no other files touched.

## Firstmate spec
Project: scratch-target, from its clean default branch base. Delivery
local-only, yolo off. Add a single docstring line inside add() stating it
returns the sum of a and b. Commit on branch fm/scen-a with message
"Document add()". Then append \`done [at=<epoch>]: docstring added\` to
'$A_STATUS' (substitute <epoch> with the real Unix time from \`date +%s\`)
and stop. In your final chat reply only, state one sentence on whether an
independent review is warranted here and why.
EOF
A_WT=$(spawn_worker "$A_DIR" scen-a anthropic/claude-haiku-4-5 low "$TMP_ROOT/brief-a.md")
if [ -n "$A_WT" ] && wait_for_status "$A_STATUS" 240; then
  check 'A: real worker committed on the expected branch' fm/scen-a "$(git -C "$A_WT" branch --show-current)"
  check 'A: exactly one real commit landed on top of main' 1 "$(git -C "$A_WT" rev-list --count main.. 2>/dev/null || printf 0)"
  contains 'A: status file carries a real done line' "$(cat "$A_STATUS")" 'done [at='
else
  fail 'A: real worker never produced a status file within budget'
fi

# =============================================================================
# B. Substantive IMPLEMENT, NO task-specific review request in the brief.
#    Structural, policy-level result (not model-output-dependent): official
#    FirstMate AGENTS.md section 7 means no second reviewer is dispatched
#    here in real practice, which conflicts with this configuration's own
#    primary-policy.md "review required for substantive IMPLEMENT work".
#    This scenario deliberately reports that conflict as FAIL/BLOCKED - see
#    this file's header. It is never "fixed" by dispatching a reviewer
#    anyway, which would smuggle authorization the brief never carried.
# =============================================================================
B_DIR=$(new_scratch_home scenario-b)
new_scratch_project "$B_DIR"
B_STATUS="$B_DIR/status"
cat > "$TMP_ROOT/brief-b.md" <<EOF
# Task

## Captain's intent
Implement interval merging: add merge_intervals(intervals) to scratch.py -
take a list of (start, end) integer tuples and return merged
non-overlapping intervals, sorted by start, merging on overlap or touch.

## Firstmate spec
Project: scratch-target, from its clean default branch base. Delivery
local-only, yolo off. Implement merge_intervals in scratch.py; keep add
unchanged. Commit on branch fm/scen-b with message "Add merge_intervals".
Then append \`done [at=<epoch>]: merge_intervals implemented\` to
'$B_STATUS' (substitute <epoch> with the real Unix time from \`date +%s\`)
and stop.
EOF
B_WT=$(spawn_worker "$B_DIR" scen-b anthropic/claude-sonnet-5 medium "$TMP_ROOT/brief-b.md")
if [ -n "$B_WT" ] && wait_for_status "$B_STATUS" 240; then
  check 'B: real worker committed a substantive change on the expected branch' fm/scen-b "$(git -C "$B_WT" branch --show-current)"
  contains 'B: the real diff adds real new behavior (not a no-op)' "$(git -C "$B_WT" diff main -- scratch.py)" 'def merge_intervals'
  fail 'B: no task-specific review request was given (by design) - official FirstMate AGENTS.md section 7 means no second reviewer is dispatched here, contradicting primary-policy.md own review-required clause for substantive IMPLEMENT work; see this file header for the disclosed, unresolved policy conflict'
else
  fail 'B: real worker never produced a status file within budget'
fi

# =============================================================================
# C. Explicit review request; a real, deliberately seeded BLOCKER; fix;
#    targeted independent re-review of the corrected delta.
#    The implementer is explicitly instructed to use a naive, unambiguous
#    comma split with no quote-awareness at all - a disclosed, intentional
#    defect (the same mutation-testing technique used to prove a review
#    pipeline actually catches something), never presented to the
#    reviewer, who receives only the true requirement and the real diff.
# =============================================================================
C_DIR=$(new_scratch_home scenario-c-impl)
new_scratch_project "$C_DIR"
C_STATUS="$C_DIR/status"
cat > "$TMP_ROOT/brief-c-impl.md" <<EOF
# Task

## Captain's intent
Implement a CSV row parser: add parse_csv_row(line) to scratch.py that
splits one CSV text row into a list of field strings on comma boundaries.

## Firstmate spec
Project: scratch-target, from its clean default branch base. Delivery
local-only, yolo off. Implement parse_csv_row in scratch.py as exactly
this one line of logic: return line.split(','). Do not add quote
handling, do not use the csv module, do not add any other special-casing.
Keep add unchanged. Commit on branch fm/scen-c with message
"Add parse_csv_row". Then append
\`done [at=<epoch>]: parse_csv_row implemented\` to '$C_STATUS'
(substitute <epoch> with the real Unix time from \`date +%s\`) and stop.
Implement this exactly as specified even if it looks naive.
EOF
C_WT=$(spawn_worker "$C_DIR" scen-c-impl anthropic/claude-sonnet-5 medium "$TMP_ROOT/brief-c-impl.md")
if [ -z "$C_WT" ] || ! wait_for_status "$C_STATUS" 240; then
  fail 'C: real implementer never produced a status file within budget'
else
  CR_DIR=$(new_scratch_home scenario-c-review)
  git clone -q "$C_WT" "$CR_DIR/fm-home/projects/scratch-target"
  git -C "$CR_DIR/fm-home/projects/scratch-target" checkout -q fm/scen-c
  git -C "$CR_DIR/fm-home/projects/scratch-target" branch -m main
  git -C "$CR_DIR/fm-home/projects/scratch-target" remote remove origin 2>/dev/null || true
  CR_STATUS="$CR_DIR/status"
  cat > "$TMP_ROOT/brief-c-review.md" <<EOF
# Task

## Captain's intent
Independent read-only review, explicitly requested by the captain before
this change is considered mergeable. parse_csv_row is already committed;
review it against: "splits one CSV text row into fields; a field may be
double-quoted and may then contain literal commas that must NOT be
treated as separators (example: a,"b,c",d -> ['a', 'b,c', 'd'])."

## Firstmate spec
Project: scratch-target (already checked out at the implementer's commit;
read-only review only, implement/commit nothing). Trace parse_csv_row
against the example above and at least one more quoted-comma input you
choose. Report BLOCKER/IMPORTANT/OPTIONAL findings. Append exactly one
line to '$CR_STATUS' as
\`done [at=<epoch>]: <N> BLOCKER, <M> IMPORTANT, <K> OPTIONAL\`
(substitute <epoch>/N/M/K for real values) and stop.
EOF
  CR_WT=$(spawn_worker "$CR_DIR" scen-c-review anthropic/claude-sonnet-5 medium "$TMP_ROOT/brief-c-review.md")
  if [ -z "$CR_WT" ] || ! wait_for_status "$CR_STATUS" 240; then
    fail 'C: real reviewer never produced a status file within budget'
  else
    CR_LINE=$(cat "$CR_STATUS")
    BLOCKERS=$(printf '%s' "$CR_LINE" | sed -n 's/.*: \([0-9]*\) BLOCKER.*/\1/p')
    IMPORTANTS=$(printf '%s' "$CR_LINE" | sed -n 's/.*BLOCKER, \([0-9]*\) IMPORTANT.*/\1/p')
    if [ "${BLOCKERS:-0}" -ge 1 ] || [ "${IMPORTANTS:-0}" -ge 1 ]; then
      pass "C: the real independent reviewer found a real finding on the seeded defect ($CR_LINE)"
    else
      fail "C: the real independent reviewer found no BLOCKER/IMPORTANT on a deliberately unquoted comma split ($CR_LINE)"
    fi

    CF_DIR=$(new_scratch_home scenario-c-fix)
    git clone -q "$C_WT" "$CF_DIR/fm-home/projects/scratch-target"
    git -C "$CF_DIR/fm-home/projects/scratch-target" checkout -q fm/scen-c
    git -C "$CF_DIR/fm-home/projects/scratch-target" branch -m main
    git -C "$CF_DIR/fm-home/projects/scratch-target" remote remove origin 2>/dev/null || true
    CF_STATUS="$CF_DIR/status"
    cat > "$TMP_ROOT/brief-c-fix.md" <<EOF
# Task

## Captain's intent
Fix a real reviewer finding on parse_csv_row in scratch.py: it has no
quote-awareness and shreds any quoted field containing a comma.

## Firstmate spec
Project: scratch-target (already checked out at the buggy commit). Fix
parse_csv_row so a double-quoted field's embedded commas are preserved
and surrounding quotes are stripped, while still splitting normally on
commas outside quotes (any correct approach, including the csv module, is
fine). Keep add unchanged. Commit on branch fm/scen-c-fix with message
"Fix parse_csv_row: handle quoted commas". Then append
\`done [at=<epoch>]: parse_csv_row fixed\` to '$CF_STATUS' (substitute
<epoch> for the real Unix time from \`date +%s\`) and stop.
EOF
    CF_WT=$(spawn_worker "$CF_DIR" scen-c-fix anthropic/claude-sonnet-5 medium "$TMP_ROOT/brief-c-fix.md")
    if [ -z "$CF_WT" ] || ! wait_for_status "$CF_STATUS" 240; then
      fail 'C: real fix worker never produced a status file within budget'
    else
      check 'C: the fix landed a real commit on the fix branch' fm/scen-c-fix "$(git -C "$CF_WT" branch --show-current)"

      CRR_DIR=$(new_scratch_home scenario-c-rereview)
      git clone -q "$CF_WT" "$CRR_DIR/fm-home/projects/scratch-target"
      git -C "$CRR_DIR/fm-home/projects/scratch-target" checkout -q fm/scen-c-fix
      git -C "$CRR_DIR/fm-home/projects/scratch-target" branch -m main
      git -C "$CRR_DIR/fm-home/projects/scratch-target" remote remove origin 2>/dev/null || true
      CRR_STATUS="$CRR_DIR/status"
      cat > "$TMP_ROOT/brief-c-rereview.md" <<EOF
# Task

## Captain's intent
Targeted independent re-review of the SAME parse_csv_row change, now with
a fix commit on top. Original finding: no quote-awareness, shreds quoted
fields containing commas. Requirement unchanged: quoted commas must not
be treated as separators.

## Firstmate spec
Project: scratch-target (already checked out at the fix commit; read-only
re-review only). Re-trace the fix against the original failing inputs
plus at least one you choose - verify, do not assume. Append one line to
'$CRR_STATUS' as
\`done [at=<epoch>]: original_finding=<resolved|unresolved>, <N> new BLOCKER, <M> new IMPORTANT, <K> new OPTIONAL\`
(substitute <epoch>/N/M/K for real values) and stop.
EOF
      spawn_worker "$CRR_DIR" scen-c-rereview anthropic/claude-sonnet-5 medium "$TMP_ROOT/brief-c-rereview.md" >/dev/null
      if wait_for_status "$CRR_STATUS" 240; then
        contains 'C: the targeted re-review confirms the original finding is resolved' "$(cat "$CRR_STATUS")" 'original_finding=resolved'
      else
        fail 'C: real targeted re-review never produced a status file within budget'
      fi
    fi
  fi
fi

# =============================================================================
# D. A premium/Opus implementer does not waive or replace independent
#    review: the reviewer must be a real, distinct worker AND, per section
#    3's own routing (REVIEW stays Sonnet, never escalated merely because
#    the implementer was premium), a genuinely different, cheaper model.
# =============================================================================
D_DIR=$(new_scratch_home scenario-d-impl)
new_scratch_project "$D_DIR"
D_STATUS="$D_DIR/status"
cat > "$TMP_ROOT/brief-d-impl.md" <<EOF
# Task

## Captain's intent
Implement order-preserving de-duplication: dedupe_preserve_order(items) in
scratch.py returns each distinct hashable element of items exactly once,
in first-occurrence order. The captain explicitly asks for an independent
review before this is considered mergeable.

## Firstmate spec
Project: scratch-target, from its clean default branch base. Delivery
local-only, yolo off. Implement dedupe_preserve_order; keep add unchanged.
Commit on branch fm/scen-d with message "Add dedupe_preserve_order". Then
append \`done [at=<epoch>]: dedupe_preserve_order implemented\` to
'$D_STATUS' (substitute <epoch> for the real Unix time from \`date +%s\`)
and stop.
EOF
D_WT=$(spawn_worker "$D_DIR" scen-d-impl anthropic/claude-opus-5-5 xhigh "$TMP_ROOT/brief-d-impl.md")
if [ -z "$D_WT" ] || ! wait_for_status "$D_STATUS" 300; then
  fail 'D: real premium implementer never produced a status file within budget'
else
  D_META=$(cat "$D_DIR/fm-home/state/scen-d-impl.meta" 2>/dev/null)
  D_MODEL=$(field "$D_META" model)
  check 'D: the real implementer actually ran on the premium model' anthropic/claude-opus-5-5 "$D_MODEL"

  DR_DIR=$(new_scratch_home scenario-d-review)
  git clone -q "$D_WT" "$DR_DIR/fm-home/projects/scratch-target"
  git -C "$DR_DIR/fm-home/projects/scratch-target" checkout -q fm/scen-d
  git -C "$DR_DIR/fm-home/projects/scratch-target" branch -m main
  git -C "$DR_DIR/fm-home/projects/scratch-target" remote remove origin 2>/dev/null || true
  DR_STATUS="$DR_DIR/status"
  cat > "$TMP_ROOT/brief-d-review.md" <<EOF
# Task

## Captain's intent
Independent read-only review of dedupe_preserve_order in scratch.py,
already committed. Requirement: return each distinct hashable element of
items exactly once, in first-occurrence order.

## Firstmate spec
Project: scratch-target (already checked out at the implementer's commit;
read-only review only). Report BLOCKER/IMPORTANT/OPTIONAL findings. Append
one line to '$DR_STATUS' as
\`done [at=<epoch>]: <N> BLOCKER, <M> IMPORTANT, <K> OPTIONAL\`
(substitute <epoch>/N/M/K for real values) and stop.
EOF
  spawn_worker "$DR_DIR" scen-d-review anthropic/claude-sonnet-5 medium "$TMP_ROOT/brief-d-review.md" >/dev/null
  if wait_for_status "$DR_STATUS" 240; then
    DR_META=$(cat "$DR_DIR/fm-home/state/scen-d-review.meta" 2>/dev/null)
    DR_MODEL=$(field "$DR_META" model)
    check 'D: the real reviewer ran on the routed REVIEW model, never re-escalated to the implementer premium model' anthropic/claude-sonnet-5 "$DR_MODEL"
    if [ "$D_MODEL" != "$DR_MODEL" ]; then
      pass 'D: implementer and reviewer are real, distinct models - the premium implementer never waived independent review'
    else
      fail 'D: implementer and reviewer ran on the same model - premium implementer effectively self-reviewed'
    fi
    contains 'D: the real reviewer produced a real done line' "$(cat "$DR_STATUS")" 'done [at='
  else
    fail 'D: real reviewer never produced a status file within budget'
  fi
fi

printf '\nCAPTAIN REVIEW SCENARIOS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo 'FAIL (see B above - a disclosed policy conflict, not a script defect)')"
[ "$failed" -eq 0 ]
