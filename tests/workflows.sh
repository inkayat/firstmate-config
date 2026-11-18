#!/usr/bin/env bash
# workflows.sh - offline automation for the workflow engine (bin/fm-workflow), the
# definitions under workflows/ and the verdict contract (firstmate/primary-policy.md
# section 8). No model, network or real home.
#
#   1. the shipped definitions validate, and validation rejects each defect (negative fixtures)
#   2. the verdict parser is strict: table of well-formed and malformed reports
#   3. the engine on scripted outcome sequences: straight through; QA fails twice then passes;
#      review feedback then "QA needed" then "QA not needed"; loop exhaustion escalates;
#      malformed verdict = FAIL; blocked escalates; plan-build-test-review
#   4. every step's role handoff is bin/fm-role-handoff's, bound through the role alias
#   5. trace derivation from the state file
#   6. the contract examples in the ROLE.md files parse, and the Captain-side documents carry the rules
# shellcheck source=tests/fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixture.sh"

W="$FIX_SRC/bin/fm-workflow"
export FM_CONFIG_ROOT="$FIX_SRC" FM_SKILLS_ROOT="$T/skills-root"
WF="$FIX_SRC/workflows"
S="$T/state"; mkdir -p "$S" "$T/fx"
POLICY="$FIX_SRC/firstmate/primary-policy.md"

# --- helpers ---------------------------------------------------------------------
OUT=''
adv() { OUT=$("$W" next "$@" 2>&1); RC=$?; }          # advance/inspect; JSON (or an error) in $OUT
o() { printf '%s' "$OUT" | jq -r "$1" 2>/dev/null; }    # a field of the last output
# report <file> <PASS|FAIL|BLOCKED> [id:SEVERITY:what]... - a worker report ending in the verdict block
report() {
  local f=$1 v=$2 items='[]' it
  shift 2
  for it in "$@"; do
    items=$(printf '%s' "$items" | jq -c --arg id "${it%%:*}" --arg sev "$(echo "$it" | cut -d: -f2)" --arg what "$(echo "$it" | cut -d: -f3-)" \
      '. + [{id: $id, severity: $sev, what: $what, where: "src/app.py:12"}]')
  done
  { printf 'I checked the change.\n\nSome notes.\n\n```verdict\n'; jq -n --arg v "$v" --argjson i "$items" '{verdict: $v, feedback: $i}'; printf '```\n'; } > "$f"
}
fb() { jq -c "$1" ; }                                    # compact a JSON value read on stdin
# expect_validate_fails <label> <jq edit of build-test-review> <needle>
expect_invalid() {
  local label=$1 edit=$2 needle=$3 d="$T/fx/$1" out rc
  d="$T/fx/$(printf '%s' "$label" | tr -c 'a-z0-9' '-')"
  mkdir -p "$d"
  jq "$edit" "$WF/build-test-review.json" > "$d/build-test-review.json"
  out=$("$W" validate "$d/build-test-review.json" 2>&1); rc=$?
  check "validate rejects $label: exit 1" "$rc" 1
  has "validate rejects $label: says why" "$out" "$needle"
}

# --- 1. definitions and negative fixtures ---------------------------------------------
out=$("$W" validate build-test-review plan-build-test-review 2>&1); rc=$?
check 'validate accepts both shipped workflows' "$rc" 0
has 'validate reports build-test-review' "$out" 'build-test-review.json (v1, 6 steps'
has 'validate reports plan-build-test-review' "$out" 'plan-build-test-review.json (v1, 7 steps'
check 'the schema file is valid JSON' "$(jq -r .title "$WF/workflow.schema.json")" 'FirstMate workflow definition'
for f in "$WF"/*.json; do
  [ "$(basename "$f")" = workflow.schema.json ] && continue
  check "$(basename "$f"): name equals the file name" "$(jq -r .name "$f")" "$(basename "$f" .json)"
done
lst=$("$W" list)
has 'list names build-test-review' "$lst" 'build-test-review v1'
has 'list names plan-build-test-review' "$lst" 'plan-build-test-review v1'
has 'list shows the when guidance that selects a workflow' "$lst" 'when: A task that changes behavior'
lacks 'list does not list the schema file' "$lst" 'workflow.schema'

expect_invalid 'an unknown role' '.roles.qa = "ghost"' 'role alias "qa" -> "ghost": no such role'
expect_invalid 'an unreachable step' '.steps.orphan = {kind: "deliver", instruction: "x", on: {done: "@complete", blocked: "@escalate"}}' 'step orphan is unreachable'
expect_invalid 'a loop without onExhausted' 'del(.loops["qa-fix"].onExhausted)' 'missing required key "onExhausted"'
expect_invalid 'an onExhausted that is not escalate' '.loops["qa-fix"].onExhausted = "ignore"' 'must be one of escalate'
expect_invalid 'a loop with maxIterations 0' '.loops["qa-fix"].maxIterations = 0' 'must be >= 1'
expect_invalid 'a loop with an absurd maxIterations' '.loops["qa-fix"].maxIterations = 99' 'must be <= 20'
expect_invalid 'a transition to a step that does not exist' '.steps.qa.on.pass = "nowhere"' 'target "nowhere" is not a step'
expect_invalid 'a transition object without a target' '.steps.qa.on.pass = {loop: "qa-fix"}' 'is not one of the allowed forms'
expect_invalid 'an unrouted outcome' 'del(.steps.qa.on.blocked)' 'does not route the outcome(s) blocked'
expect_invalid 'an unknown outcome' '.steps.qa.on.maybe = "review"' 'routes unknown outcome(s) maybe'
expect_invalid 'a cycle that passes through no loop' '.steps.qa.on.fail = "implement"' 'form a cycle that passes through no loop'
expect_invalid 'a transition tagged with an undefined loop' '.steps.qa.on.fail.loop = "ghost"' 'loop "ghost" is not defined in loops'
expect_invalid 'a loop no transition uses' '.loops.extra = {maxIterations: 2, onExhausted: "escalate"}' 'loop "extra" is used by no transition'
expect_invalid 'a mistyped key' '.steps.qa.onn = {}' 'steps.qa.onn is an unknown key'
expect_invalid 'a deliver step that names a role' '.steps.deliver.role = "qa"' 'steps.deliver.role is not allowed here'
expect_invalid 'a work step without a role' 'del(.steps.qa.role)' 'steps.qa is missing required key "role"'
expect_invalid 'a work step bound to an alias that is not defined' '.steps.qa.role = "ghost"' 'role "ghost" is not an alias in roles'
expect_invalid 'a role alias no step uses' '.roles.extra = "qa"' 'role alias "extra" is used by no step'
expect_invalid 'a start step that does not exist' '.start = "nope"' 'start step "nope" is not a step'
expect_invalid 'a definition whose name differs from its file' '.name = "other"' 'must equal the file name'
expect_invalid 'an input that reads the report of a missing step' '.steps.qa.input += [{name: "x", from: "report", step: "ghost"}]' 'reads the report of "ghost"'
expect_invalid 'an input that takes feedback from a non-verdict step' '.steps.qa.input += [{name: "x", from: "feedback", steps: ["implement"]}]' 'is not a verdict step'
expect_invalid 'an input of an unknown kind' '.steps.qa.input += [{name: "x", from: "magic"}]' 'must be one of task, change, report, feedback'
expect_invalid 'no path to @complete' '.steps.deliver.on.done = "@escalate"' 'no reachable transition leads to @complete'
expect_invalid 'a decision with one choice' '.steps.requalify.on = {yes: "qa"}' 'a decision needs at least two choices'
expect_invalid 'a decision with no criteria' '.steps.requalify.criteria = []' 'needs at least 1 item'
expect_invalid 'a step name that is not kebab-case' '.steps["Bad_Name"] = .steps.deliver' 'key "Bad_Name" does not match'
expect_invalid 'a version below 1' '.version = 0' 'version must be >= 1'
expect_invalid 'a missing when' 'del(.when)' 'missing required key "when"'
printf '{ not json\n' > "$T/fx/bad.json"
check 'validate rejects a file that is not JSON' "$("$W" validate "$T/fx/bad.json" 2>&1 | grep -c 'not valid JSON')" 1
out=$("$W" validate no-such-workflow 2>&1); rc=$?
check 'validate of an unknown workflow fails' "$rc" 1
# One engine, no names in it: the definitions bind steps to roles only through the roles map.
check 'the engine hard-codes no step name or role name' "$(grep -vE '^[[:space:]]*#' "$W" | grep -nE '"(qa|implement|review|address-review|requalify|plan)"|senior-fullstack|code-reviewer|planner' || true)" ''

# --- 2. the verdict parser is strict ----------------------------------------------------
vt() { # <label> <report-file> <exit> <verdict> <valid>
  local out rc
  out=$("$W" verdict "$2" 2>&1); rc=$?
  check "verdict $1: exit $3" "$rc" "$3"
  check "verdict $1: $4, valid=$5" "$(printf '%s' "$out" | jq -r '"\(.verdict) \(.valid)"')" "$4 $5"
}
report "$T/v-pass.md" PASS
report "$T/v-pass-opt.md" PASS 'O-1:OPTIONAL:nit'
report "$T/v-fail.md" FAIL 'QA-1:BLOCKER:wrong total' 'QA-2:IMPORTANT:no error path'
report "$T/v-blocked.md" BLOCKED 'B-1:BLOCKER:the test runner is missing'
vt 'a well-formed PASS' "$T/v-pass.md" 0 PASS true
vt 'a PASS that only carries an OPTIONAL item' "$T/v-pass-opt.md" 0 PASS true
vt 'a well-formed FAIL' "$T/v-fail.md" 1 FAIL true
vt 'a well-formed BLOCKED' "$T/v-blocked.md" 3 BLOCKED true
check 'a FAIL keeps its feedback items verbatim' "$("$W" verdict "$T/v-fail.md" | jq -c '.feedback | map(.id)')" '["QA-1","QA-2"]'
vbad() { # <label> <content-with-printf-escapes> <needle>
  printf "$2" > "$T/v-bad.md"
  out=$("$W" verdict "$T/v-bad.md" 2>&1); rc=$?
  check "verdict $1: exit 1" "$rc" 1
  check "verdict $1: FAIL, invalid" "$(printf '%s' "$out" | jq -r '"\(.verdict) \(.valid)"')" 'FAIL false'
  has "verdict $1: the feedback item names the defect" "$(printf '%s' "$out" | jq -r '.feedback[0].what')" "$3"
  check "verdict $1: exactly one parser feedback item, VERDICT-1" "$(printf '%s' "$out" | jq -c '[.feedback[].id]')" '["VERDICT-1"]'
}
vbad 'a report with no fenced block' 'All good, ship it.\n' 'no fenced block'
vbad 'an empty report' '' 'the report is empty'
vbad 'a verdict in prose, not in a block' 'VERDICT: PASS\n' 'no fenced block'
vbad 'a block tagged json instead of verdict' '```json\n{"verdict":"PASS","feedback":[]}\n```\n' 'tagged "json", not "verdict"'
vbad 'text after the block' '```verdict\n{"verdict":"PASS","feedback":[]}\n```\nthanks!\n' 'text follows the last fenced block'
vbad 'a block that is never closed' '```verdict\n{"verdict":"PASS","feedback":[]}\n' 'never closed'
vbad 'invalid JSON in the block' '```verdict\n{"verdict":"PASS",\n```\n' 'not valid JSON'
vbad 'two JSON values in the block' '```verdict\n{"verdict":"PASS","feedback":[]}\n{"verdict":"FAIL","feedback":[]}\n```\n' 'exactly one JSON value'
vbad 'an empty block' '```verdict\n```\n' 'exactly one JSON value'
vbad 'a block holding an array' '```verdict\n[]\n```\n' 'not a JSON object'
vbad 'a lowercase verdict' '```verdict\n{"verdict":"pass","feedback":[]}\n```\n' 'exactly PASS, FAIL or BLOCKED'
vbad 'an unknown verdict word' '```verdict\n{"verdict":"MAYBE","feedback":[]}\n```\n' 'exactly PASS, FAIL or BLOCKED'
vbad 'a missing feedback array' '```verdict\n{"verdict":"PASS"}\n```\n' 'feedback must be an array'
vbad 'an item without where' '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"BLOCKER","what":"x"}]}\n```\n' 'feedback[0].where must be a non-empty string'
vbad 'an item with an empty what' '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"BLOCKER","what":" ","where":"f"}]}\n```\n' 'feedback[0].what must be a non-empty string'
vbad 'an unknown severity' '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"MAJOR","what":"x","where":"f"}]}\n```\n' 'severity must be BLOCKER, IMPORTANT or OPTIONAL'
vbad 'duplicate item ids' '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"BLOCKER","what":"x","where":"f"},{"id":"A","severity":"BLOCKER","what":"y","where":"f"}]}\n```\n' 'ids are not unique'
vbad 'a PASS carrying a BLOCKER' '```verdict\n{"verdict":"PASS","feedback":[{"id":"A","severity":"BLOCKER","what":"x","where":"f"}]}\n```\n' 'PASS verdict cannot carry'
vbad 'a FAIL with only OPTIONAL items' '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"OPTIONAL","what":"x","where":"f"}]}\n```\n' 'FAIL verdict needs at least one BLOCKER or IMPORTANT'
vbad 'a FAIL with no items' '```verdict\n{"verdict":"FAIL","feedback":[]}\n```\n' 'FAIL verdict needs at least one'
vbad 'a BLOCKED with no items' '```verdict\n{"verdict":"BLOCKED","feedback":[]}\n```\n' 'BLOCKED verdict needs at least one item'
printf 'notes\r\n```verdict\r\n{"verdict":"PASS","feedback":[]}\r\n```\r\n' > "$T/v-crlf.md"
vt 'a report with CRLF line endings' "$T/v-crlf.md" 0 PASS true
printf '```bash\nls\n```\n\ntext\n\n```verdict\n{"verdict":"PASS","feedback":[],"note":"extra keys are ignored"}\n```\n' > "$T/v-extra.md"
vt 'an earlier non-verdict block and an extra key' "$T/v-extra.md" 0 PASS true
out=$("$W" verdict "$T/no-such-report.md" 2>&1); rc=$?
check 'verdict of an unreadable file is a usage error, not a pass' "$rc" 2

# --- 3. the engine on scripted outcome sequences -------------------------------------------
# 3a. straight through
st=$S/straight.json
adv build-test-review "$st" --task 'TASK-A'
check '3a: starting prints the start step' "$(o .step)" implement
check '3a: the start step is a work step with the implementer role' "$(o '"\(.kind) \(.role) \(.roleName)"')" 'work implementer senior-fullstack'
check '3a: a start with no result flag is idempotent' "$("$W" next build-test-review "$st" | jq -r .iteration)" 1
adv build-test-review "$st" --outcome done --change 'base1..head1'
check '3a: implement done -> qa' "$(o .step)" qa
check '3a: qa receives the change as recorded' "$(o '.inputs[] | select(.name == "change") | .value')" 'base1..head1'
check '3a: qa has no feedback on its first run' "$(o '[.inputs[] | select(.name == "feedback")] | length')" 0
adv build-test-review "$st" --report "$T/v-pass.md"
check '3a: qa PASS -> review' "$(o .step)" review
adv build-test-review "$st" --report "$T/v-pass.md"
check '3a: review PASS -> deliver' "$(o .step)" deliver
check '3a: deliver is a step kind with no role' "$(o '"\(.kind) \(.role) \(.handoff)"')" 'deliver null null'
adv build-test-review "$st" --outcome done
check '3a: deliver done -> complete' "$(o .status)" complete
check '3a: loop counters are untouched on a straight run' "$(o '[.loops[].used] | add')" 0
adv build-test-review "$st" --outcome done
check '3a: a finished workflow refuses more results' "$RC" 1
has '3a: ... and says it is complete' "$OUT" 'workflow is complete'

# 3b. QA fails twice, then passes: feedback reaches the implementer verbatim, QA re-evaluates against it
st=$S/qa-loop.json
report "$T/qa1.md" FAIL 'QA-1:BLOCKER:total is wrong for 0 items' 'QA-2:IMPORTANT:no error path'
report "$T/qa2.md" FAIL 'QA-1:BLOCKER:still wrong for 0 items'
adv build-test-review "$st" --task 'TASK-B'
adv build-test-review "$st" --outcome done --change 'b..h1'
adv build-test-review "$st" --report "$T/qa1.md"
check '3b: qa FAIL -> implement again' "$(o '"\(.step) \(.iteration)"')" 'implement 2'
check '3b: the loop counter counts the fix round' "$(o '.loops["qa-fix"].used')" 1
want=$("$W" verdict "$T/qa1.md" | fb '.feedback')
check '3b: the implementer receives exactly the QA feedback list' "$(o '.inputs[] | select(.name == "feedback") | .items' | fb .)" "$want"
has '3b: the spec carries each feedback item verbatim' "$(printf '%s' "$OUT" | jq -r .spec)" '{"id":"QA-2","severity":"IMPORTANT","what":"no error path","where":"src/app.py:12"}'
check '3b: the implementer also gets the change to fix' "$(o '.inputs[] | select(.name == "change") | .value')" 'b..h1'
adv build-test-review "$st" --outcome done --change 'b..h2'
check '3b: after the fix, qa runs again' "$(o .step)" qa
check '3b: qa re-evaluates against the feedback it gave' "$(o '.inputs[] | select(.name == "feedback") | .items' | fb .)" "$want"
check '3b: qa sees the corrected change' "$(o '.inputs[] | select(.name == "change") | .value')" 'b..h2'
adv build-test-review "$st" --report "$T/qa2.md"
check '3b: a second FAIL goes back again' "$(o '"\(.step) \(.loops["qa-fix"].used)"')" 'implement 2'
want2=$("$W" verdict "$T/qa2.md" | fb '.feedback')
check '3b: the second round hands over only the latest feedback' "$(o '.inputs[] | select(.name == "feedback") | .items' | fb .)" "$want2"
adv build-test-review "$st" --outcome done --change 'b..h3'
adv build-test-review "$st" --report "$T/v-pass.md"
check '3b: qa PASS after two failures -> review' "$(o .step)" review
check '3b: the closed QA feedback is not handed to the review' "$(o '[.inputs[] | select(.name == "feedback")] | length')" 0
check '3b: two fix rounds are counted' "$(o '.loops["qa-fix"].used')" 2
check '3b: the review loop is untouched' "$(o '.loops["review-fix"].used')" 0

# 3c. review feedback -> address -> decision (QA needed) -> qa -> review of the delta -> deliver
st=$S/review-loop.json
report "$T/rev1.md" FAIL 'REV-1:IMPORTANT:the retry swallows the error' 'REV-2:OPTIONAL:rename x'
adv build-test-review "$st" --task 'TASK-C'
adv build-test-review "$st" --outcome done --change 'c..h1'
adv build-test-review "$st" --report "$T/v-pass.md"
adv build-test-review "$st" --report "$T/rev1.md"
check '3c: review FAIL -> address-review' "$(o '"\(.step) \(.role)"')" 'address-review implementer'
check '3c: the review-fix loop is counted, qa-fix is not' "$(o '"\(.loops["review-fix"].used) \(.loops["qa-fix"].used)"')" '1 0'
wantr=$("$W" verdict "$T/rev1.md" | fb '.feedback')
check '3c: the implementer receives exactly the review feedback' "$(o '.inputs[] | select(.name == "feedback") | .items' | fb .)" "$wantr"
adv build-test-review "$st" --outcome done --change 'c..h2'
check '3c: after the fix the orchestrator must decide' "$(o '"\(.step) \(.kind) \(.status)"')" 'requalify decision running'
check '3c: the decision states its question' "$(o .decision.question)" 'Does the change made in response to the review feedback require QA to run again before the review is repeated?'
check '3c: the decision states its criteria' "$(o '.decision.criteria | length')" 3
check '3c: the decision names its choices' "$(o '.decision.choices | join(",")')" 'yes,no'
check '3c: the decision shows what to look at (the review feedback verbatim)' "$(o '.inputs[] | select(.name == "feedback") | .items' | fb .)" "$wantr"
check '3c: a decision has no worker and no handoff' "$(o '"\(.role) \(.handoff)"')" 'null null'
adv build-test-review "$st" --decide yes
check '3c: a decision without a reason is refused' "$RC" 1
adv build-test-review "$st" --outcome done
check '3c: a decision step refuses --outcome' "$RC" 1
adv build-test-review "$st" --decide maybe --reason 'x'
check '3c: a choice the definition does not route is refused' "$RC" 1
has '3c: ... naming the routed choices' "$OUT" 'routes: yes, no'
check '3c: refused results do not move the workflow' "$("$W" next build-test-review "$st" | jq -r .step)" requalify
adv build-test-review "$st" --decide yes --reason 'the fix changed the retry logic'
check '3c: decision yes -> qa' "$(o .step)" qa
check '3c: qa checks the review feedback was fixed without a regression' "$(o '.inputs[] | select(.name == "feedback") | .items' | fb .)" "$wantr"
check '3c: the decision is recorded with its reason' "$(jq -c '.history[] | select(.step == "requalify") | [.outcome, .reason]' "$st")" '["yes","the fix changed the retry logic"]'
adv build-test-review "$st" --report "$T/v-pass.md"
check '3c: qa PASS -> review again' "$(o '"\(.step) \(.iteration)"')" 'review 2'
check '3c: the re-review is handed its own previous findings' "$(o '.inputs[] | select(.name == "feedback") | .items' | fb .)" "$wantr"
check '3c: ... and the corrected change (the delta)' "$(o '.inputs[] | select(.name == "change") | .value')" 'c..h2'
adv build-test-review "$st" --report "$T/v-pass.md"
check '3c: review PASS -> deliver' "$(o .step)" deliver
adv build-test-review "$st" --outcome done
check '3c: complete' "$(o .status)" complete

# 3d. review feedback -> address -> decision NO -> straight to the review of the delta
st=$S/review-noqa.json
adv build-test-review "$st" --task 'TASK-D'
adv build-test-review "$st" --outcome done --change 'd..h1'
adv build-test-review "$st" --report "$T/v-pass.md"
adv build-test-review "$st" --report "$T/rev1.md"
adv build-test-review "$st" --outcome done --change 'd..h2'
adv build-test-review "$st" --decide no --reason 'comment and naming only; the implementer ran the checks'
check '3d: decision no -> review without QA' "$(o '"\(.step) \(.iteration)"')" 'review 2'
check '3d: the review sees the findings it gave' "$(o '.inputs[] | select(.name == "feedback") | .items' | fb .)" "$wantr"
check '3d: qa ran once only' "$(jq '[.history[] | select(.step == "qa")] | length' "$st")" 1
adv build-test-review "$st" --report "$T/rev1.md"
check '3d: a second review FAIL loops again' "$(o '"\(.step) \(.loops["review-fix"].used)"')" 'address-review 2'
adv build-test-review "$st" --outcome done --change 'd..h3'
adv build-test-review "$st" --decide no --reason 'rename only'
adv build-test-review "$st" --report "$T/v-pass.md"
check '3d: the review PASS closes the findings -> deliver' "$(o .step)" deliver
check '3d: the history is the exact path taken' "$(jq -r '[.history[] | "\(.step):\(.outcome)"] | join(" ")' "$st")" \
  'implement:done qa:pass review:fail address-review:done requalify:no review:fail address-review:done requalify:no review:pass'

# 3e. loop exhaustion escalates (never a silent stop, never a silent pass)
st=$S/exhaust.json
adv build-test-review "$st" --task 'TASK-E'
adv build-test-review "$st" --outcome done --change 'e..h0'
for n in 1 2 3 4 5; do
  report "$T/ex$n.md" FAIL "QA-$n:BLOCKER:round $n still wrong"
  adv build-test-review "$st" --report "$T/ex$n.md"
  check "3e: qa FAIL #$n is sent back (counter $n/5)" "$(o '"\(.step) \(.status) \(.loops["qa-fix"].used)"')" "implement running $n"
  adv build-test-review "$st" --outcome done --change "e..h$n"
done
report "$T/ex6.md" FAIL 'QA-6:BLOCKER:round 6 still wrong'
adv build-test-review "$st" --report "$T/ex6.md"
check '3e: the sixth FAIL escalates' "$(o .status)" escalated
has '3e: the reason names the exhausted loop' "$(o .escalation.reason)" 'loop qa-fix is exhausted: its 5 iteration(s) are used'
check '3e: the escalation carries every accumulated feedback entry' "$(o '[.escalation.feedback[].items[].id] | join(" ")')" 'QA-1 QA-2 QA-3 QA-4 QA-5 QA-6'
check '3e: the counter is not pushed past the limit' "$(o '.loops["qa-fix"].used')" 5
has '3e: the escalation spec lists the accumulated feedback verbatim' "$(o .spec)" '{"id":"QA-6","severity":"BLOCKER","what":"round 6 still wrong","where":"src/app.py:12"}'
adv build-test-review "$st" --report "$T/v-pass.md"
check '3e: an escalated workflow cannot be passed along by a later PASS' "$RC" 1
check '3e: ... it stays escalated' "$("$W" next build-test-review "$st" | jq -r .status)" escalated
lacks '3e: deliver was never reached' "$(jq -r '[.history[].step] | join(" ")' "$st")" deliver

# 3f. a malformed verdict is a FAIL with a feedback item saying so
st=$S/malformed.json
adv build-test-review "$st" --task 'TASK-F'
adv build-test-review "$st" --outcome done --change 'f..h1'
printf 'Everything looks fine to me. Ship it!\n' > "$T/noverdict.md"
adv build-test-review "$st" --report "$T/noverdict.md"
check '3f: a report with no verdict is a FAIL: back to implement' "$(o '"\(.step) \(.loops["qa-fix"].used)"')" 'implement 1'
check '3f: the feedback item says the verdict is missing' "$(o '.inputs[] | select(.name == "feedback") | .items[0].id')" VERDICT-1
has '3f: ... and why' "$(o '.inputs[] | select(.name == "feedback") | .items[0].what')" 'no fenced block'
check '3f: the history marks the verdict invalid' "$(jq -r '.history[-1].verdict.valid' "$st")" false
adv build-test-review "$st" --outcome done --change 'f..h2'
adv build-test-review "$st" --outcome pass
check '3f: a verdict step refuses a caller-supplied outcome' "$RC" 1
has '3f: ... naming --report' "$OUT" 'takes its outcome from --report'
adv build-test-review "$st"
check '3f: ... and stays where it was' "$(o .step)" qa

# 3g. BLOCKED escalates with the blocking feedback
st=$S/blocked.json
adv build-test-review "$st" --task 'TASK-G'
adv build-test-review "$st" --outcome done --change 'g..h1'
adv build-test-review "$st" --report "$T/v-blocked.md"
check '3g: a BLOCKED verdict escalates' "$(o .status)" escalated
check '3g: the escalation carries the blocking item' "$(o '.escalation.feedback[0].items[0].id')" B-1
has '3g: the reason is the definition routing blocked to the captain' "$(o .escalation.reason)" 'step qa ended blocked'
st=$S/blocked-impl.json
adv build-test-review "$st" --task 'TASK-G2'
adv build-test-review "$st" --outcome blocked
check '3g: a blocked report step escalates' "$(o .status)" escalated
adv build-test-review "$st" --outcome finished
check '3g: an outcome the step does not route is refused on a finished workflow too' "$RC" 1

# 3h. plan-build-test-review: the plan travels to every later step
st=$S/plan.json
printf '# Plan\nAssumptions: ...\n' > "$T/plan.md"
adv plan-build-test-review "$st" --task 'TASK-H'
check '3h: the plan workflow starts at plan, with the planner role' "$(o '"\(.step) \(.role) \(.roleName)"')" 'plan planner planner'
adv plan-build-test-review "$st" --outcome done --report "$T/plan.md"
check '3h: plan done -> implement' "$(o .step)" implement
check '3h: implement receives the recorded plan report' "$(o '.inputs[] | select(.name == "plan") | .report')" "$T/plan.md"
adv plan-build-test-review "$st" --outcome done --change 'h..h1'
check '3h: qa is handed the plan too' "$(o '"\(.step) \(.inputs[] | select(.name == "plan") | .report)"')" "qa $T/plan.md"
adv plan-build-test-review "$st" --report "$T/v-pass.md"
check '3h: the reviewer is handed the plan too' "$(o '"\(.step) \(.inputs[] | select(.name == "plan") | .report)"')" "review $T/plan.md"
adv plan-build-test-review "$st" --report "$T/v-pass.md"
adv plan-build-test-review "$st" --outcome done
check '3h: the plan workflow completes' "$(o .status)" complete
st=$S/plan-blocked.json
adv plan-build-test-review "$st" --task 'TASK-H2'
adv plan-build-test-review "$st" --outcome blocked
check '3h: a planner that is blocked (open questions) escalates' "$(o .status)" escalated
adv build-test-review "$S/plan.json"
check 'a state file of another workflow is refused' "$RC" 1
has '... saying which workflow it belongs to' "$OUT" 'belongs to workflow plan-build-test-review'

# 3i. state handling
adv build-test-review "$S/nostate.json"
check 'starting without --task is refused' "$RC" 1
adv build-test-review "$S/nostate2.json" --outcome done
check 'recording a result before the workflow was started is refused' "$RC" 1
adv no-such-workflow "$S/nostate3.json" --task x
check 'starting an unknown workflow is refused' "$RC" 1
printf '{"a":1}\n' > "$S/notstate.json"
adv build-test-review "$S/notstate.json"
check 'a file that is not a workflow state is refused' "$RC" 1
# the state pins the definition it started with
mkdir -p "$T/wfroot-a"; cp "$WF/build-test-review.json" "$T/wfroot-a/"
export FM_WORKFLOWS_ROOT="$T/wfroot-a"
adv build-test-review "$S/pinned.json" --task 'TASK-P'
jq '.steps.implement.on.done = "review" | .version = 2' "$T/wfroot-a/build-test-review.json" > "$T/wfroot-a/x.json" && mv "$T/wfroot-a/x.json" "$T/wfroot-a/build-test-review.json"
adv build-test-review "$S/pinned.json" --outcome done --change 'p..h'
check 'a task in flight keeps the definition it started with (version 1 routes implement -> qa)' "$(o '"\(.step) \(.version)"')" 'qa 1'
unset FM_WORKFLOWS_ROOT
# a state file must not sit in a repository that would track it
mkdir -p "$T/repo-in-way"; git -C "$T/repo-in-way" init -q
adv build-test-review "$T/repo-in-way/workflow.json" --task x
check 'a state file inside a git work tree is refused' "$RC" 1
has '... pointing at the task data folder' "$OUT" "task's data folder"
printf 'workflow.json\n' > "$T/repo-in-way/.gitignore"
adv build-test-review "$T/repo-in-way/workflow.json" --task x
check 'a git-ignored state file (a task data folder) is accepted' "$RC" 0
check 'the state file is written in place, with no temp file left behind' "$(find "$S" -name '*.json.*' | wc -l | tr -d ' ')" 0

# --- 4. every step's handoff is fm-role-handoff's, through the role alias --------------------
st=$S/handoff.json
adv build-test-review "$st" --task 'TASK-I'
check '4: the implement spec contains bin/fm-role-handoff senior-fullstack verbatim' \
  "$(printf '%s' "$OUT" | jq -r .spec | grep -cxF -f <("$FIX_SRC/bin/fm-role-handoff" senior-fullstack))" "$("$FIX_SRC/bin/fm-role-handoff" senior-fullstack | grep -c .)"
check '4: the handoff field is exactly the role handoff' "$(o .handoff)" "$("$FIX_SRC/bin/fm-role-handoff" senior-fullstack)"
check '4: no spec line is a markdown heading (a heading would end the brief'"'"'s ## Firstmate spec section)' "$(printf '%s' "$OUT" | jq -r .spec | grep -c '^#' || true)" 0
adv build-test-review "$st" --outcome done --change 'i..h1'
check '4: qa gets the qa role handoff (its ROLE.md and its autoloadSkills)' "$(o .handoff)" "$("$FIX_SRC/bin/fm-role-handoff" qa)"
has '4: ... which names the skill the qa role loads' "$(o .handoff)" "$T/skills-root/verification-before-completion/SKILL.md"
adv build-test-review "$st" --report "$T/v-pass.md"
check '4: review gets the code-reviewer role handoff' "$(o .handoff)" "$("$FIX_SRC/bin/fm-role-handoff" code-reviewer)"
adv build-test-review "$st" --report "$T/rev1.md"
check '4: address-review binds the implementer alias again (same role, a fresh worker)' "$(o .handoff)" "$("$FIX_SRC/bin/fm-role-handoff" senior-fullstack)"
# changing the agent for a kind of work is one edit: the roles map
mkdir -p "$T/wfroot-b"
jq '.roles.implementer = "refactorist"' "$WF/build-test-review.json" > "$T/wfroot-b/build-test-review.json"
FM_WORKFLOWS_ROOT="$T/wfroot-b" adv build-test-review "$S/swap.json" --task 'TASK-J'
check '4: one edit to roles.implementer swaps the agent of both implementer steps' "$(o .handoff)" "$("$FIX_SRC/bin/fm-role-handoff" refactorist)"
check '4: ... and the step still reports its alias' "$(o '"\(.role) \(.roleName)"')" 'implementer refactorist'
# the role skill budget the roles lint enforces holds for the roles the workflows bind
for role in $(jq -r '.roles[]' "$WF"/build-test-review.json "$WF"/plan-build-test-review.json | sort -u); do
  [ "$("$FIX_SRC/bin/fm-role-handoff" --skills "$role" | grep -c .)" -le 3 ] && ok "4: role $role stays within the skill budget" || bad "4: role $role exceeds the skill budget"
done
check '4: the qa role loads exactly one skill' "$("$FIX_SRC/bin/fm-role-handoff" --skills qa)" verification-before-completion

# --- 5. trace derivation ---------------------------------------------------------------------
st=$S/trace.json
adv build-test-review "$st" --task 'TASK-T'
check '5: trace at the start' "$("$W" trace "$st")" 'Workflow: build-test-review v1 | step implement #1 | loops qa-fix 0/5, review-fix 0/5 | running'
adv build-test-review "$st" --outcome done --change 't..1'
adv build-test-review "$st" --report "$T/qa1.md"
adv build-test-review "$st" --outcome done --change 't..2'
adv build-test-review "$st" --report "$T/qa2.md"
check '5: trace after two QA failures' "$("$W" trace "$st")" 'Workflow: build-test-review v1 | step implement #3 | loops qa-fix 2/5, review-fix 0/5 | running'
check '5: the trace the engine prints is the derived one' "$(o .trace)" "$("$W" trace "$st")"
printf 'Routing: IMPLEMENT #1 | role senior-fullstack | omp | m | high | why: w\nAgent: senior-fullstack\nSkills: none\nWorkflow: build-test-review v1 | step implement #3 | loops qa-fix 2/5, review-fix 0/5 | running\n' > "$T/trace-ok.txt"
out=$("$W" trace "$st" "$T/trace-ok.txt"); rc=$?
check '5: a captured Workflow line that equals the derived one passes' "$rc" 0
sed 's#qa-fix 2/5#qa-fix 1/5#' "$T/trace-ok.txt" > "$T/trace-bad.txt"
out=$("$W" trace "$st" "$T/trace-bad.txt"); rc=$?
check '5: an invented loop counter fails the check' "$rc" 1
has '5: ... and the check prints the derived line' "$out" 'qa-fix 2/5'
# a QA worker's real trace block carries the Workflow line and still passes the routing-trace checker
printf 'Routing: REVIEW #1 | role qa | omp | anthropic/claude-sonnet-5-5 | high | why: qa step of a workflow\nAgent: qa\nSkills: verification-before-completion\nWorkflow: build-test-review v1 | step implement #3 | loops qa-fix 2/5, review-fix 0/5 | running\n' > "$T/trace-qa.txt"
out=$("$FIX_SRC/tests/routing-trace.sh" check "$T/trace-qa.txt" omp anthropic/claude-sonnet-5-5 high 2>&1); rc=$?
check '5: routing-trace check accepts a block that carries a Workflow line (qa routed as REVIEW)' "$rc" 0
check '5: the same block satisfies the Workflow line check' "$("$W" trace "$st" "$T/trace-qa.txt" >/dev/null; echo $?)" 0
printf 'Routing: x\n' > "$T/trace-none.txt"
"$W" trace "$st" "$T/trace-none.txt" >/dev/null; check '5: a trace block with no Workflow line fails the check' "$?" 1
adv build-test-review "$st" --outcome done --change 't..3'
adv build-test-review "$st" --report "$T/v-pass.md"
adv build-test-review "$st" --report "$T/v-pass.md"
adv build-test-review "$st" --outcome done
check '5: trace when complete' "$("$W" trace "$st")" 'Workflow: build-test-review v1 | step deliver #1 | loops qa-fix 2/5, review-fix 0/5 | complete'
check '5: trace of an escalated workflow' "$("$W" trace "$S/exhaust.json")" 'Workflow: build-test-review v1 | step qa #6 | loops qa-fix 5/5, review-fix 0/5 | escalated'

# --- 6. the contract examples and the Captain-side documents -------------------------------------
for role in qa code-reviewer; do
  ex="$T/example-$role.md"
  { printf 'report body\n\n'; awk '/^```verdict$/ {p = 1} p {print} /^```$/ && p {exit}' "$FIX_SRC/roles/$role/ROLE.md"; } > "$ex"
  out=$("$W" verdict "$ex"); rc=$?
  check "the verdict example in roles/$role/ROLE.md parses as a valid FAIL" "$(printf '%s' "$out" | jq -r '"\(.verdict) \(.valid)"')" 'FAIL true'
done
POL=$(cat "$POLICY")
has 'policy: section 8 owns workflows' "$POL" '## 8. Workflows'
has 'policy: the two workflows are named' "$POL" '`build-test-review`'
has 'policy: plan-build-test-review is named' "$POL" '`plan-build-test-review`'
has 'policy: the feedback list goes verbatim to the implementer' "$POL" 'verbatim'
has 'policy: the trace gains a Workflow line' "$POL" 'Workflow: <workflow> v<version> | step <step> #<run> | loops'
has 'policy: the Workflow line is derived from the state file' "$POL" 'bin/fm-workflow trace <state-file>'
has 'policy: the Captain still never merges' "$POL" 'never merges'
has 'policy: every step is a fresh worker' "$POL" 'fresh worker'
has 'policy: the state lives in the task data folder' "$POL" 'data/<task-id>/workflow.json'
has 'README documents the workflows' "$(cat "$FIX_SRC/README.md")" 'bin/fm-workflow'
check 'crew-dispatch.json still never mentions skills' "$(grep -ci skill "$FIX_SRC/firstmate/crew-dispatch.json")" 0

finish
