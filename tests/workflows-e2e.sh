#!/usr/bin/env bash
# workflows-e2e.sh - end-to-end workflow handoff through the REAL official dispatch
# path. For each step that launches a worker, this script plays the Captain: it
# asks bin/fm-workflow for the step's spec, scaffolds the brief with the real
# bin/fm-brief.sh, fills `## Firstmate spec` with that spec and nothing else, and
# launches the task with the unmodified official bin/fm-spawn.sh on a private
# tmux server into a real treehouse worktree. Only the `omp` executable is fake: it
# records the argv it was launched with, which is the worker's FIRST input. Scripted
# worker reports (result blocks for the implementer, risk blocks for the classifier,
# verdict blocks for QA, review, the finding-verifier and ship; --outcome done for the
# planner and deliver) are fed back to the engine, so BOTH workflows are driven end to
# end: implement -> classify -> qa FAIL -> implement -> classify -> qa PASS -> review FAIL ->
# verify-review (confirms) -> implement -> classify -> qa -> review PASS -> ship -> deliver,
# and plan -> implement -> classify -> qa -> review -> ship -> deliver.
#
# Per launched worker this asserts: the role handoff is bin/fm-role-handoff's, verbatim,
# for the role the step binds; the role's autoloadSkills paths and no other skill path;
# the COMPLETE `next ... --spec` output arrives unchanged, its first line being the
# `Workflow step: <workflow> v<version>, step <step>, run #<n>` header built from the
# state file, and no `Workflow:` trace line (chat-only, never in a brief); and the
# feedback block is EXACTLY the list the definition hands that step (QA's failure
# straight to the implementer; the reviewer's blocking list to the verifier; the
# verifier's confirmed list, never the raw review, to the implementer), or absent when
# the step has none; and the change/risk/plan inputs.
#
# What this proves: the briefs a real spawn delivers carry the right role handoff and
# exactly the feedback of the engine's routing, in the order the definition says, and
# the engine's whole spec survives the official brief and spawn path. It uses a FAKE
# omp, so it cannot prove that a model reads or applies any of it
# (tests/workflows-live.sh), that a real Captain pastes the spec whole
# (tests/captain-live.sh), or that the Captain chose the right workflow.
#
# ISOLATED LAB (tests/e2e-lib/lab.sh has the full list): safe on a machine with a live
# fleet, also when started from inside a fleet tmux pane or treehouse worktree. A private
# tmux server, a throwaway HOME / FM_HOME / TMPDIR / project (its treehouse pool lives in
# the project), `env -i` for every official script (no inherited TMUX or FM_*), recording
# shims for tmux and treehouse and deny-and-record shims for the fleet tools. The run ends
# with lab_guard's assertions over that record (every call was on the lab) and proves the
# lab is gone. Tear-down is idempotent and also called explicitly, so it holds under a
# harness that does not fire EXIT traps.
#
# SKIPs (never PASS) without tmux, treehouse, jq, or an official FirstMate checkout at
# $FIRSTMATE_ROOT (default ~/Developer/tools/firstmate). FIRSTMATE_ROOT also lets a
# deliberately broken launch be fed in: tests/e2e-lib/broken-firstmate.sh builds a
# FirstMate whose launch drops the role handoff, alters the feedback, trims the spec,
# pastes a trace line, or leaves the lab; the suite must FAIL on each.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HANDOFF="$CONFIG_ROOT/bin/fm-role-handoff"
W="$CONFIG_ROOT/bin/fm-workflow"
FM_ROOT="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"
# shellcheck source=tests/e2e-lib/lab.sh
. "$CONFIG_ROOT/tests/e2e-lib/lab.sh"

lab_prereq workflows WORKFLOWS
lab_up wf

OPUS=anthropic/claude-opus-5-5
N=0

# report <file> <PASS|FAIL> <commit> [id:SEVERITY:what]... - a worker report ending in the verdict block
report() {
  local f=$1 v=$2 c=$3 items='[]' it
  shift 3
  for it in "$@"; do
    items=$(printf '%s' "$items" | jq -c --arg id "${it%%:*}" --arg sev "$(echo "$it" | cut -d: -f2)" --arg what "$(echo "$it" | cut -d: -f3-)" \
      '. + [{id: $id, severity: $sev, what: $what, where: "src/app.py:12"}]')
  done
  { printf 'I checked the change.\n\n```verdict\n'; jq -n --arg v "$v" --arg c "$c" --argjson i "$items" '{verdict: $v, commit: $c, feedback: $i}'; printf '```\n'; } > "$f"
}
# result_report <file> <base> <commit> [answered-id]... - an implementer report ending in the result block
result_report() {
  local f=$1 b=$2 c=$3 answers='[]' id
  shift 3
  for id in "$@"; do answers=$(printf '%s' "$answers" | jq -c --arg id "$id" '. + [{id: $id, status: "fixed", evidence: "re-ran the failing command, it now passes"}]'); done
  { printf 'Implemented and committed.\n\n```result\n'
    jq -n --arg b "$b" --arg c "$c" --argjson a "$answers" '{status: "done", base: $b, commit: $c, evidence: [{command: "make test", observed: "ok"}], answers: $a, unverified: []}'
    printf '```\n'; } > "$f"
}
# risk_report <file> <commit> - a classifier report ending in the risk block (tier medium, no security review)
risk_report() {
  { printf 'Classified.\n\n```risk\n'
    jq -n --arg c "$2" '{tier: "medium", security: "not-required", commit: $c, sensitive: [], checklist: [], reasons: ["small change, no sensitive surface"]}'
    printf '```\n'; } > "$1"
}
# the feedback block of a first input: the fenced json after the "- feedback:" line
feedback_block() { awk '/^- feedback:/ {f = 1; next} f && /^```json$/ {b = 1; next} f && b && /^```$/ {exit} f && b {print}' <<<"$1"; }

# launch <label> <workflow> <state> <expected-role> <expected-feedback-json|none> <expected-input-name:value>...
# Plays the Captain for one worker step and asserts what its first input carries.
launch() {
  local label=$1 wf=$2 state=$3 role=$4 want_fb=$5 first spec id brief body meta wt waited got head scaffold out
  shift 5
  N=$((N + 1))
  id="fm-wf-e2e-$RUN-$N"
  spec=$("$W" next "$wf" "$state" --spec) || { fail "$label: no spec: $spec"; return 1; }
  # the header the spec must start with, built from the state file and not from the spec
  head=$(jq -r '"Workflow step: \(.workflow) v\(.version), step \(.current), run #\(.runs[.current])"' "$state")
  if ! scaffold=$(lab_run "$FM_ROOT/bin/fm-brief.sh" "$id" projects/e2e-proj --mode local-only 2>&1); then
    fail "$label: real fm-brief.sh scaffold failed: $scaffold"; return 1
  fi
  brief="$home/data/$id/brief.md"
  body=$(cat "$brief")
  body=${body/'{TASK}'/"E2E fixture: $label."}
  body=${body/'{FIRSTMATE_SPEC}'/$spec}
  printf '%s\n' "$body" > "$brief"
  if ! out=$(lab_run ${LAB_TMO[@]+"${LAB_TMO[@]}"} "$FM_ROOT/bin/fm-spawn.sh" "$id" projects/e2e-proj \
      --mode local-only --yolo off --harness omp --model "$OPUS" --effort high 2>&1); then
    fail "$label: real fm-spawn failed: $out"; return 1
  fi
  meta=$(cat "$home/state/$id.meta" 2>/dev/null)
  wt=$(field "$meta" worktree)
  waited=0
  while [ ! -f "$wt/worker-argv.txt" ] && [ "$waited" -lt 150 ]; do sleep 0.1; waited=$((waited + 1)); done
  first=$(cat "$wt/worker-argv.txt" 2>/dev/null)
  if [ -z "$first" ]; then fail "$label: the fake worker recorded no first input"; return 1; fi
  LAST_FIRST=$first
  has "$label: first input carries the role handoff of $role, verbatim" "$first" "$("$HANDOFF" "$role")"
  got=$(printf '%s\n' "$first" | grep -o "$FM_SKILLS_ROOT/[A-Za-z0-9_-]*/SKILL.md" | sed "s#^$FM_SKILLS_ROOT/\(.*\)/SKILL.md#\1#")
  check "$label: its skill paths are exactly $role's autoloadSkills" "$got" "$("$HANDOFF" --skills "$role")"
  check "$label: exactly one Assigned role field, the step's" "$(printf '%s\n' "$first" | grep -c '^Assigned role:')" 1
  has "$label: the Assigned role is $role" "$first" "Assigned role: $role"
  check "$label: the engine's spec starts with the header built from the state file" "$(printf '%s\n' "$spec" | sed -n 1p)" "$head"
  has "$label: the COMPLETE next --spec output travels unchanged, first line to last" "$first" "$spec"
  check "$label: the delivered spec starts with the header" "$(printf '%s\n' "$first" | awk '/^## Firstmate spec$/ {getline; print; exit}')" "$head"
  check "$label: the chat-only Workflow: trace line is not in the brief" "$(printf '%s\n' "$first" | grep -c 'Workflow:')" 0
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
# the blocking items (BLOCKER, IMPORTANT) of a verdict file: what the engine hands on after a fail
fbj() { "$W" verdict "$1" | jq -c '.feedback | map(select(.severity == "BLOCKER" or .severity == "IMPORTANT"))'; }

# --- A. build-test-review ------------------------------------------------------------------------
WFA=build-test-review
SA="$home/data/fm-wf-e2e-$RUN-wfA/workflow.json"
TASK_TEXT='Add a --json flag to the cli list command (e2e task A)'
B0=1111111; H1=a111111; H2=a222222; H3=a333333
result_report "$TMP/impl1.md" $B0 $H1
risk_report "$TMP/risk1.md" $H1
report "$TMP/qa1.md" FAIL $H1 'QA-1:BLOCKER:--json prints tabs, not JSON' 'QA-2:IMPORTANT:exit code is 0 on a bad flag'
result_report "$TMP/impl2.md" $B0 $H2 QA-1 QA-2
risk_report "$TMP/risk2.md" $H2
report "$TMP/qa2.md" PASS $H2
report "$TMP/rev1.md" FAIL $H2 'REV-1:IMPORTANT:the retry swallows the error' 'REV-2:OPTIONAL:rename x'
report "$TMP/ver1.md" FAIL $H2 'REV-1:IMPORTANT:confirmed by running it: the retry swallows the error'
result_report "$TMP/impl3.md" $B0 $H3 REV-1
risk_report "$TMP/risk3.md" $H3
report "$TMP/qa3.md" PASS $H3
report "$TMP/rev2.md" PASS $H3
report "$TMP/ship.md" PASS $H3
"$W" next "$WFA" "$SA" --task "$TASK_TEXT" >/dev/null
launch 'A1 implement' "$WFA" "$SA" senior-fullstack none 'task:'"$TASK_TEXT"
"$W" next "$WFA" "$SA" --report "$TMP/impl1.md" >/dev/null
launch 'A2 classify' "$WFA" "$SA" risk-classifier none "change:$B0..$H1"
"$W" next "$WFA" "$SA" --report "$TMP/risk1.md" >/dev/null
check 'A: the classifier outcome recorded is the tier word' "$(jq -r '.history[-1] | "\(.step):\(.outcome)"' "$SA")" classify:medium
launch 'A3 qa' "$WFA" "$SA" qa none "change:$B0..$H1" 'risk:tier medium, security review not-required'
"$W" next "$WFA" "$SA" --report "$TMP/qa1.md" >/dev/null
want=$(fbj "$TMP/qa1.md")
launch 'A4 implement (fix of QA feedback, straight from QA)' "$WFA" "$SA" senior-fullstack "$want" "change:$B0..$H1"
"$W" next "$WFA" "$SA" --report "$TMP/impl2.md" >/dev/null
launch 'A5 classify (every fix is classified again)' "$WFA" "$SA" risk-classifier none "change:$B0..$H2"
"$W" next "$WFA" "$SA" --report "$TMP/risk2.md" >/dev/null
launch 'A6 qa (re-evaluates against its feedback, on the delta)' "$WFA" "$SA" qa "$want" "change:$B0..$H2" "delta:$H1..$H2"
"$W" next "$WFA" "$SA" --report "$TMP/qa2.md" >/dev/null
launch 'A7 review' "$WFA" "$SA" code-reviewer none "change:$B0..$H2" 'risk:tier medium, security review not-required'
"$W" next "$WFA" "$SA" --report "$TMP/rev1.md" >/dev/null
wantr=$(fbj "$TMP/rev1.md")
launch 'A8 verify-review (receives the reviewer blocking list)' "$WFA" "$SA" finding-verifier "$wantr" "change:$B0..$H2"
"$W" next "$WFA" "$SA" --report "$TMP/ver1.md" >/dev/null
wantv=$(fbj "$TMP/ver1.md")
launch 'A9 implement (fix of the verifier confirmed list)' "$WFA" "$SA" senior-fullstack "$wantv" "change:$B0..$H2"
lacks 'A9: the implementer never sees the reviewer raw wording' "$LAST_FIRST" '"what":"the retry swallows the error"'
"$W" next "$WFA" "$SA" --report "$TMP/impl3.md" >/dev/null
launch 'A10 classify (again after the review fix)' "$WFA" "$SA" risk-classifier none "change:$B0..$H3"
"$W" next "$WFA" "$SA" --report "$TMP/risk3.md" >/dev/null
launch 'A11 qa (after review feedback; the confirmed list is still open)' "$WFA" "$SA" qa "$wantv" "change:$B0..$H3" "delta:$H2..$H3"
"$W" next "$WFA" "$SA" --report "$TMP/qa3.md" >/dev/null
launch 'A12 review (the delta, with the confirmed findings)' "$WFA" "$SA" code-reviewer "$wantv" "change:$B0..$H3" "delta:$H2..$H3"
"$W" next "$WFA" "$SA" --report "$TMP/rev2.md" >/dev/null
launch 'A13 ship (carries the non-blocking notes)' "$WFA" "$SA" release-engineer none "change:$B0..$H3" 'risk:tier medium, security review not-required' 'notes:non-blocking notes'
"$W" next "$WFA" "$SA" --report "$TMP/ship.md" >/dev/null
check 'A: ship passed, so the next step is delivery by Firstmate (no worker, no role)' "$("$W" next "$WFA" "$SA" | jq -r '"\(.step) \(.kind) \(.role)"')" 'deliver deliver null'
"$W" next "$WFA" "$SA" --outcome done >/dev/null
check 'A: the workflow is complete' "$("$W" next "$WFA" "$SA" | jq -r .status)" complete
check 'A: thirteen workers were launched for the scripted path' "$N" 13
check 'A: the engine path is the scripted one' "$(jq -r '[.history[] | "\(.step):\(.outcome)"] | join(" ")' "$SA")" \
  'implement:done classify:medium qa:fail implement:done classify:medium qa:pass review:fail verify-review:fail implement:done classify:medium qa:pass review:pass ship:pass deliver:done'
check 'A: the state file sits in the task data folder and nowhere in the repository' "$(git -C "$CONFIG_ROOT" status --porcelain | grep -c workflow.json)" 0

# --- B. plan-build-test-review: the plan reaches every later step ---------------------------
WFB=plan-build-test-review
SB="$home/data/fm-wf-e2e-$RUN-wfB/workflow.json"
TASK_TEXT='Make the report page export CSV (e2e task B)'
printf '# Plan\nAssumptions: comma separated.\n' > "$home/data/plan-b.md"
PLANB="$(cd "$home/data" && pwd -P)/plan-b.md"   # the engine records report paths canonically
PLAN_IN="plan:the report of step plan, at $PLANB"
result_report "$TMP/bimpl.md" b000001 b000002
risk_report "$TMP/brisk.md" b000002
report "$TMP/bqa.md" PASS b000002
report "$TMP/brev.md" PASS b000002
report "$TMP/bship.md" PASS b000002
N0=$N
"$W" next "$WFB" "$SB" --task "$TASK_TEXT" >/dev/null
launch 'B1 plan' "$WFB" "$SB" planner none 'task:'"$TASK_TEXT"
"$W" next "$WFB" "$SB" --outcome done --report "$home/data/plan-b.md" >/dev/null
launch 'B2 implement (receives the plan)' "$WFB" "$SB" senior-fullstack none "$PLAN_IN"
"$W" next "$WFB" "$SB" --report "$TMP/bimpl.md" >/dev/null
launch 'B3 classify (receives the plan)' "$WFB" "$SB" risk-classifier none "$PLAN_IN" 'change:b000001..b000002'
"$W" next "$WFB" "$SB" --report "$TMP/brisk.md" >/dev/null
launch 'B4 qa (receives the plan)' "$WFB" "$SB" qa none "$PLAN_IN" 'change:b000001..b000002'
"$W" next "$WFB" "$SB" --report "$TMP/bqa.md" >/dev/null
launch 'B5 review (receives the plan)' "$WFB" "$SB" code-reviewer none "$PLAN_IN" 'change:b000001..b000002'
"$W" next "$WFB" "$SB" --report "$TMP/brev.md" >/dev/null
launch 'B6 ship (receives the plan)' "$WFB" "$SB" release-engineer none "$PLAN_IN" 'change:b000001..b000002'
"$W" next "$WFB" "$SB" --report "$TMP/bship.md" >/dev/null
"$W" next "$WFB" "$SB" --outcome done >/dev/null
check 'B: the plan workflow completes' "$("$W" next "$WFB" "$SB" | jq -r .status)" complete
check 'B: six workers were launched' "$((N - N0))" 6

lab_finish WORKFLOWS
