#!/usr/bin/env bash
# workflows-e2e.sh - end-to-end workflow handoff through the REAL official dispatch
# path. For each step that launches a worker, this script plays the Captain: it
# asks bin/fm-workflow for the step's spec, scaffolds the brief with the real
# bin/fm-brief.sh, fills `## Firstmate spec` with that spec and nothing else, and
# launches the task with the unmodified official bin/fm-spawn.sh on an isolated
# tmux server into a real treehouse worktree. Only the `omp` executable is fake: it
# records the argv it was launched with, which is the worker's FIRST input. Scripted
# outcomes (verdict files, "done") are fed back to the engine, so BOTH workflows are
# driven end to end: QA failing then passing, review feedback then "QA needed", and
# plan -> build -> test -> review.
#
# Per launched worker this asserts: the role handoff is bin/fm-role-handoff's, verbatim,
# for the role the step binds; the role's autoloadSkills paths and no other skill path;
# the derived Workflow trace line; and the feedback block is EXACTLY the previous
# verdict's feedback list (or absent when the step has none).
#
# What this proves: the briefs a real spawn delivers carry the right role handoff and
# exactly the feedback of the previous step, in the order the definition says. What it
# cannot prove: that a model reads or applies any of it (tests/workflows-live.sh), or
# that the Captain chose the right workflow.
#
# SKIPs (never PASS) without tmux, treehouse, or an official FirstMate checkout at
# $FIRSTMATE_ROOT (default ~/Developer/tools/firstmate).
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HANDOFF="$CONFIG_ROOT/bin/fm-role-handoff"
W="$CONFIG_ROOT/bin/fm-workflow"
FM_ROOT="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"

if ! command -v tmux >/dev/null 2>&1 || ! command -v treehouse >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 \
   || [ ! -x "$FM_ROOT/bin/fm-spawn.sh" ] || [ ! -x "$FM_ROOT/bin/fm-brief.sh" ]; then
  printf 'SKIP - workflows e2e: needs tmux, treehouse, jq, and %s/bin/fm-{brief,spawn}.sh (never reported as PASS)\n\nWORKFLOWS E2E SKIPPED\n' "$FM_ROOT"
  exit 0
fi
shopt -u patsub_replacement 2>/dev/null || true

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$3', got '$2')"; fi; }
has() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3')" ;; esac; }
lacks() { case $2 in *"$3"*) fail "$1 (unexpected '$3')" ;; *) pass "$1" ;; esac; }
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-wf-e2e.XXXXXX") || exit 1
TMP=$(cd "$TMP" && pwd)
RUN=$$
SEAM_TMUX=$(mktemp -d /tmp/fm-wf-tmux.XXXXXX) || exit 1
cleanup() {
  TMUX_TMPDIR="$SEAM_TMUX" tmux kill-server >/dev/null 2>&1 || true
  sleep 0.3
  chmod -R u+w "$TMP" "$SEAM_TMUX" /tmp/fm-wf-e2e-"$RUN"-* /tmp/fm-wf-e2e-"$RUN"-*+* 2>/dev/null
  rm -rf "$TMP" "$SEAM_TMUX" /tmp/fm-wf-e2e-"$RUN"-* /tmp/fm-wf-e2e-"$RUN"-*+*
}
trap cleanup EXIT

export FM_CONFIG_ROOT="$CONFIG_ROOT" FM_SKILLS_ROOT="$TMP/home/.agents/skills"
home="$TMP/fm-home"
proj="$home/projects/e2e-proj"
mkdir -p "$home/state" "$home/config" "$home/data" "$TMP/home" "$TMP/bin" "$proj"
printf 'manual\n' > "$home/config/backlog-backend"
printf '# E2E project\n' > "$proj/AGENTS.md"
printf 'max_trees = 24\nroot = "./"\n' > "$proj/treehouse.toml"
git -C "$proj" init -q
git -C "$proj" add -A
git -C "$proj" -c user.email=t@example.invalid -c user.name=t commit -q -m init

cat > "$TMP/bin/omp" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = --help ] && { printf 'usage: omp [options] [prompt]\n'; exit 0; }
if [ "${1:-}" = models ]; then
  printf '{"models":[{"provider":"anthropic","id":"claude-opus-5-5","selector":"anthropic/claude-opus-5-5"},{"provider":"anthropic","id":"claude-sonnet-5-5","selector":"anthropic/claude-sonnet-5-5"}]}\n'
  exit 0
fi
printf '%s\n' "$@" > worker-argv.tmp
mv worker-argv.tmp worker-argv.txt
SH
chmod +x "$TMP/bin/omp"

OPUS=anthropic/claude-opus-5-5
SPAWN_ENV=(TMUX_TMPDIR="$SEAM_TMUX" PATH="$TMP/bin:$PATH" HOME="$TMP/home" FM_HOME="$home" FM_BACKEND=tmux)
N=0

# report <file> <PASS|FAIL> [id:SEVERITY:what]... - a worker report ending in the verdict block
report() {
  local f=$1 v=$2 items='[]' it
  shift 2
  for it in "$@"; do
    items=$(printf '%s' "$items" | jq -c --arg id "${it%%:*}" --arg sev "$(echo "$it" | cut -d: -f2)" --arg what "$(echo "$it" | cut -d: -f3-)" \
      '. + [{id: $id, severity: $sev, what: $what, where: "src/app.py:12"}]')
  done
  { printf 'I checked the change.\n\n```verdict\n'; jq -n --arg v "$v" --argjson i "$items" '{verdict: $v, feedback: $i}'; printf '```\n'; } > "$f"
}
# the feedback block of a first input: the fenced json after the "- feedback:" line
feedback_block() { awk '/^- feedback:/ {f = 1; next} f && /^```json$/ {b = 1; next} f && b && /^```$/ {exit} f && b {print}' <<<"$1"; }

# launch <label> <workflow> <state> <expected-role> <expected-feedback-json|none> <expected-input-name:value>...
# Plays the Captain for one worker step and asserts what its first input carries.
launch() {
  local label=$1 wf=$2 state=$3 role=$4 want_fb=$5 first spec id brief body meta wt waited got trace
  shift 5
  N=$((N + 1))
  id="fm-wf-e2e-$RUN-$N"
  spec=$("$W" next "$wf" "$state" --spec) || { fail "$label: no spec: $spec"; return 1; }
  if ! scaffold=$(env "${SPAWN_ENV[@]}" "$FM_ROOT/bin/fm-brief.sh" "$id" projects/e2e-proj --mode local-only 2>&1); then
    fail "$label: real fm-brief.sh scaffold failed: $scaffold"; return 1
  fi
  brief="$home/data/$id/brief.md"
  body=$(cat "$brief")
  body=${body/'{TASK}'/"Workflow step $label (fixture)."}
  body=${body/'{FIRSTMATE_SPEC}'/$spec}
  printf '%s\n' "$body" > "$brief"
  if ! out=$(env "${SPAWN_ENV[@]}" timeout 90 "$FM_ROOT/bin/fm-spawn.sh" "$id" projects/e2e-proj \
      --mode local-only --yolo off --harness omp --model "$OPUS" --effort high 2>&1); then
    fail "$label: real fm-spawn failed: $out"; return 1
  fi
  meta=$(cat "$home/state/$id.meta" 2>/dev/null)
  wt=$(field "$meta" worktree)
  waited=0
  while [ ! -f "$wt/worker-argv.txt" ] && [ "$waited" -lt 150 ]; do sleep 0.1; waited=$((waited + 1)); done
  first=$(cat "$wt/worker-argv.txt" 2>/dev/null)
  if [ -z "$first" ]; then fail "$label: the fake worker recorded no first input"; return 1; fi
  has "$label: first input carries the role handoff of $role, verbatim" "$first" "$("$HANDOFF" "$role")"
  got=$(printf '%s\n' "$first" | grep -o "$FM_SKILLS_ROOT/[A-Za-z0-9_-]*/SKILL.md" | sed "s#^$FM_SKILLS_ROOT/\(.*\)/SKILL.md#\1#")
  check "$label: its skill paths are exactly $role's autoloadSkills" "$got" "$("$HANDOFF" --skills "$role")"
  check "$label: exactly one Assigned role field, the step's" "$(printf '%s\n' "$first" | grep -c '^Assigned role:')" 1
  has "$label: the Assigned role is $role" "$first" "Assigned role: $role"
  trace=$("$W" trace "$state")
  has "$label: the derived Workflow line is in the first input" "$first" "$trace"
  has "$label: the task text travels" "$first" "$TASK_TEXT"
  if [ "$want_fb" = none ]; then
    lacks "$label: no feedback input (none is open)" "$first" '- feedback:'
  else
    check "$label: the feedback block is exactly the previous step's list" \
      "$(feedback_block "$first" | jq -c . | tr -d '\n')" "$(printf '%s' "$want_fb" | jq -c .)"
    has "$label: the feedback is labelled verbatim" "$first" 'verbatim. Address or re-check every item by id'
  fi
  local pair
  for pair in "$@"; do has "$label: input ${pair%%:*} is ${pair#*:}" "$first" "- ${pair%%:*}: ${pair#*:}"; done
  return 0
}
fbj() { "$W" verdict "$1" | jq -c .feedback; }

# --- A. build-test-review: QA fails then passes, review feedback, QA needed, review passes -------
WFA=build-test-review
SA="$home/data/fm-wf-e2e-$RUN-wfA/workflow.json"
TASK_TEXT='Add a --json flag to the cli list command (e2e task A)'
report "$TMP/qa1.md" FAIL 'QA-1:BLOCKER:--json prints tabs, not JSON' 'QA-2:IMPORTANT:exit code is 0 on a bad flag'
report "$TMP/rev1.md" FAIL 'REV-1:IMPORTANT:the retry swallows the error' 'REV-2:OPTIONAL:rename x'
report "$TMP/pass.md" PASS
"$W" next "$WFA" "$SA" --task "$TASK_TEXT" >/dev/null
launch 'A1 implement' "$WFA" "$SA" senior-fullstack none 'task:'"$TASK_TEXT"
"$W" next "$WFA" "$SA" --outcome done --change 'base1..head1' >/dev/null
launch 'A2 qa' "$WFA" "$SA" qa none 'change:base1..head1'
"$W" next "$WFA" "$SA" --report "$TMP/qa1.md" >/dev/null
want=$(fbj "$TMP/qa1.md")
launch 'A3 implement (fix of QA feedback)' "$WFA" "$SA" senior-fullstack "$want" 'change:base1..head1'
"$W" next "$WFA" "$SA" --outcome done --change 'base1..head2' >/dev/null
launch 'A4 qa (re-evaluates against its feedback)' "$WFA" "$SA" qa "$want" 'change:base1..head2'
"$W" next "$WFA" "$SA" --report "$TMP/pass.md" >/dev/null
launch 'A5 review' "$WFA" "$SA" code-reviewer none 'change:base1..head2'
"$W" next "$WFA" "$SA" --report "$TMP/rev1.md" >/dev/null
wantr=$(fbj "$TMP/rev1.md")
launch 'A6 address-review' "$WFA" "$SA" senior-fullstack "$wantr" 'change:base1..head2'
"$W" next "$WFA" "$SA" --outcome done --change 'base1..head3' >/dev/null
check 'A: the orchestrator decides after the fix (no worker for it)' "$("$W" next "$WFA" "$SA" | jq -r '"\(.step) \(.kind)"')" 'requalify decision'
"$W" next "$WFA" "$SA" --decide yes --reason 'the fix changed the retry logic' >/dev/null
launch 'A7 qa (after review feedback)' "$WFA" "$SA" qa "$wantr" 'change:base1..head3'
"$W" next "$WFA" "$SA" --report "$TMP/pass.md" >/dev/null
launch 'A8 review (the delta, with its own findings)' "$WFA" "$SA" code-reviewer "$wantr" 'change:base1..head3'
"$W" next "$WFA" "$SA" --report "$TMP/pass.md" >/dev/null
check 'A: both passed, so the next step is delivery by Firstmate (no worker, no role)' "$("$W" next "$WFA" "$SA" | jq -r '"\(.step) \(.kind) \(.role)"')" 'deliver deliver null'
"$W" next "$WFA" "$SA" --outcome done >/dev/null
check 'A: the workflow is complete' "$("$W" next "$WFA" "$SA" | jq -r .status)" complete
check 'A: eight workers were launched for the scripted path' "$N" 8
check 'A: the state file sits in the task data folder and nowhere in the repository' "$(git -C "$CONFIG_ROOT" status --porcelain | grep -c workflow.json)" 0

# --- B. plan-build-test-review: the plan reaches every later step ---------------------------
WFB=plan-build-test-review
SB="$home/data/fm-wf-e2e-$RUN-wfB/workflow.json"
TASK_TEXT='Make the report page export CSV (e2e task B)'
printf '# Plan\nAssumptions: comma separated.\n' > "$home/data/plan-b.md"
N0=$N
"$W" next "$WFB" "$SB" --task "$TASK_TEXT" >/dev/null
launch 'B1 plan' "$WFB" "$SB" planner none 'task:'"$TASK_TEXT"
"$W" next "$WFB" "$SB" --outcome done --report "$home/data/plan-b.md" >/dev/null
launch 'B2 implement (receives the plan)' "$WFB" "$SB" senior-fullstack none "plan:the report of step plan, at $home/data/plan-b.md"
"$W" next "$WFB" "$SB" --outcome done --change 'b1..b2' >/dev/null
launch 'B3 qa (receives the plan)' "$WFB" "$SB" qa none "plan:the report of step plan, at $home/data/plan-b.md" 'change:b1..b2'
"$W" next "$WFB" "$SB" --report "$TMP/pass.md" >/dev/null
launch 'B4 review (receives the plan)' "$WFB" "$SB" code-reviewer none "plan:the report of step plan, at $home/data/plan-b.md"
"$W" next "$WFB" "$SB" --report "$TMP/pass.md" >/dev/null
"$W" next "$WFB" "$SB" --outcome done >/dev/null
check 'B: the plan workflow completes' "$("$W" next "$WFB" "$SB" | jq -r .status)" complete
check 'B: four workers were launched' "$((N - N0))" 4

printf '\nWORKFLOWS E2E %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
