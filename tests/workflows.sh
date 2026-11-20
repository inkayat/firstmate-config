#!/usr/bin/env bash
# workflows.sh - offline automation for the workflow engine (bin/fm-workflow), the
# definitions under workflows/, the final-block contracts (verdict, result, risk) and the
# forcing rule (firstmate/primary-policy.md section 8). No model, network or real home.
#
#   1. the shipped definitions validate, and validation rejects each defect (negative fixtures)
#   2. the three block parsers are strict: tables of well-formed and malformed reports
#   3. the engine on scripted outcome sequences: straight through; QA failing then passing;
#      review findings verified before they go back; refuted findings; the round cap and the
#      step-back; change of direction (redirect: reshape, close, escalate); malformed blocks;
#      conditional security routing by risk tier; gates in observe and enforce mode; every
#      workflow end to end
#   4. every step's role handoff is bin/fm-role-handoff's, bound through the role alias
#   5. trace derivation from the state file
#   6. retro records, the contract examples in the ROLE.md files and the Captain-side documents
#   7. the army check, the call graph, the role manifest and the forcing rule (selection)
# shellcheck source=tests/fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixture.sh"

W="$FIX_SRC/bin/fm-workflow"
export FM_CONFIG_ROOT="$FIX_SRC" FM_SKILLS_ROOT="$T/skills-root"
WF="$FIX_SRC/workflows"
S="$T/state"; mkdir -p "$S" "$T/fx"
POLICY="$FIX_SRC/firstmate/primary-policy.md"

# --- helpers ---------------------------------------------------------------------
OUT=''
FN=0
adv() { OUT=$("$W" next "$@" 2>&1); RC=$?; }          # advance/inspect; JSON (or an error) in $OUT
o() { printf '%s' "$OUT" | jq -r "$1" 2>/dev/null; }    # a field of the last output
fb() { jq -c "$1" ; }                                    # compact a JSON value read on stdin
nf() { FN=$((FN + 1)); printf '%s/rep-%s.md' "$T" "$FN"; }   # a fresh report file name
# items spec: id:SEVERITY:what[:class] ...
items_json() {
  local items='[]' it
  for it in "$@"; do
    items=$(printf '%s' "$items" | jq -c --arg id "$(echo "$it" | cut -d: -f1)" --arg sev "$(echo "$it" | cut -d: -f2)" --arg what "$(echo "$it" | cut -d: -f3)" --arg cls "$(echo "$it" | cut -d: -f4)" \
      '. + [{id: $id, severity: $sev, what: $what, where: "src/app.py:12"} + (if $cls != "" then {class: $cls} else {} end)]')
  done
  printf '%s' "$items"
}
# vreport <file> <PASS|FAIL|BLOCKED|CHANGE-DIRECTION> <commit|-> [id:SEVERITY:what[:class]]... - a worker report ending in the verdict block
vreport() {
  local f=$1 v=$2 c=$3
  shift 3
  { printf 'I checked the change.\n\nSome notes.\n\n```verdict\n'
    jq -n --arg v "$v" --arg c "$c" --argjson i "$(items_json "$@")" '{verdict: $v, feedback: $i} + (if $c != "-" then {commit: $c} else {} end)'
    printf '```\n'; } > "$f"
}
# report <file> <PASS|FAIL|BLOCKED> [items...] - a verdict report for the current head $CUR
CUR=bbbbbbb
report() { local f=$1 v=$2; shift 2; vreport "$f" "$v" "$CUR" "$@"; }
# rres <file> <done|blocked|change-direction> <base> <commit> [answers-json] [evidence-json] - a result report
EV_DEFAULT='[{"command":"bash tests/run.sh","observed":"PASS"}]'
rres() {
  { printf 'Work report.\n\n```result\n'
    jq -n --arg s "$2" --arg b "$3" --arg c "$4" --argjson a "${5:-[]}" --argjson e "${6:-$EV_DEFAULT}" \
      '{status: $s, evidence: $e, answers: $a, unverified: []} + (if $c != "-" then {base: $b, commit: $c} else {} end)
       + (if $s == "blocked" then {blocker: "the service is down"} elif $s == "change-direction" then {direction: "the premise is wrong: the cache is not the bottleneck"} else {} end)'
    printf '```\n'; } > "$1"
}
# krisk <file> <tier> <security> <commit> [sensitive-json] - a risk report
krisk() {
  { printf 'Classified.\n\n```risk\n'
    jq -n --arg t "$2" --arg s "$3" --arg c "$4" --argjson sens "${5:-[]}" '{tier: $t, security: $s, commit: $c, sensitive: $sens, checklist: [], reasons: ["quoted from the diff"]}'
    printf '```\n'; } > "$1"
}
# step helpers: <wf> <state> ...
st_impl() { local f; f=$(nf); rres "$f" done "$3" "$4" "${5:-[]}"; adv "$1" "$2" --report "$f"; }
st_risk() { local f; f=$(nf); krisk "$f" "$3" "$4" "$5" "${6:-[]}"; adv "$1" "$2" --report "$f"; }
st_vd() { local f w=$1 s=$2 v=$3 c=$4; shift 4; f=$(nf); vreport "$f" "$v" "$c" "$@"; adv "$w" "$s" --report "$f"; }
# pipeline up to a point: start, implement (aaaaaaa..bbbbbbb), classify <tier> <security>
st_start() { adv "$1" "$2" --task "${3:-TASK}"; }
st_to_qa() { st_start "$1" "$2" "${5:-TASK}"; st_impl "$1" "$2" aaaaaaa bbbbbbb; st_risk "$1" "$2" "${3:-medium}" "${4:-not-required}" bbbbbbb; }
# expect_invalid <label> <jq edit of build-test-review> <needle>
expect_invalid() {
  local label=$1 edit=$2 needle=$3 d out rc
  d="$T/fx/$(printf '%s' "$label" | tr -c 'a-z0-9' '-')"
  mkdir -p "$d"
  jq "$edit" "$WF/build-test-review.json" > "$d/build-test-review.json"
  out=$("$W" validate "$d/build-test-review.json" 2>&1); rc=$?
  check "validate rejects $label: exit 1" "$rc" 1
  has "validate rejects $label: says why" "$out" "$needle"
}

# --- 1. definitions and negative fixtures ---------------------------------------------
ALL='build-test-review plan-build-test-review bug-fix refactor ui-build-verify-review research-decide delegated-build'
# shellcheck disable=SC2086
out=$("$W" validate $ALL 2>&1); rc=$?
check 'validate accepts every shipped workflow' "$rc" 0
has 'validate reports build-test-review' "$out" 'build-test-review.json (v2, 11 steps'
has 'validate reports plan-build-test-review' "$out" 'plan-build-test-review.json (v2, 12 steps'
has 'validate reports bug-fix' "$out" 'bug-fix.json (v1, 13 steps'
has 'validate reports delegated-build' "$out" 'delegated-build.json (v1, 3 steps'
check 'the schema file is valid JSON' "$(jq -r .title "$WF/workflow.schema.json")" 'FirstMate workflow definition'
for f in "$WF"/*.json; do
  case $(basename "$f") in workflow.schema.json|selection.json) continue ;; esac
  check "$(basename "$f"): name equals the file name" "$(jq -r .name "$f")" "$(basename "$f" .json)"
  check "$(basename "$f"): the review and verification loops cap at 3 rounds" "$(jq -r '[.loops[] | select(.onExhausted | type == "object") | .maxIterations] | unique | map(tostring) | join(",")' "$f")" "$(jq -e '[.loops[] | select(.onExhausted | type == "object")] | length > 0' "$f" >/dev/null && echo 3 || echo '')"
  check "$(basename "$f"): every report, result and verdict step routes change-direction (a wrong approach is raised early)" \
    "$(jq -r '[.steps | to_entries[] | select(.value.kind == "work" and .value.output != "risk") | select(.value.on | has("change-direction") | not) | .key] | join(",")' "$f")" ''
done
lst=$("$W" list)
for w in $ALL; do has "list names $w" "$lst" "$w v"; done
has 'list shows the when guidance that selects a workflow' "$lst" 'when: A task that changes behavior'
lacks 'list does not list the schema file' "$lst" 'workflow.schema'
lacks 'list does not list the selection table' "$lst" 'selection'

expect_invalid 'an unknown role' '.roles.qa = "ghost"' 'role alias "qa" -> "ghost": no such role'
expect_invalid 'a role that cannot produce the step output' '.roles.qa = "scout"' 'role "scout" cannot produce output "verdict"'
expect_invalid 'an unreachable step' '.steps.orphan = {kind: "deliver", instruction: "x", on: {done: "@complete", blocked: "@escalate"}}' 'step orphan is unreachable'
expect_invalid 'a loop without onExhausted' 'del(.loops["qa-fix"].onExhausted)' 'missing required key "onExhausted"'
expect_invalid 'an onExhausted that is not escalate' '.loops["qa-fix"].onExhausted = "ignore"' 'is not one of the allowed forms'
expect_invalid 'an onExhausted step-back that does not exist' '.loops["qa-fix"].onExhausted = {to: "nowhere"}' 'target "nowhere" is not a step'
expect_invalid 'a loop with maxIterations 0' '.loops["qa-fix"].maxIterations = 0' 'must be >= 1'
expect_invalid 'a loop with an absurd maxIterations' '.loops["qa-fix"].maxIterations = 99' 'must be <= 20'
expect_invalid 'a transition to a step that does not exist' '.steps.qa.on.pass = "nowhere"' 'target "nowhere" is not a step'
expect_invalid 'a transition object without a target' '.steps.qa.on.pass = {loop: "qa-fix"}' 'is not one of the allowed forms'
expect_invalid 'an unrouted outcome' 'del(.steps.qa.on.blocked)' 'does not route the outcome(s) blocked'
expect_invalid 'an unrouted change-direction' 'del(.steps.qa.on["change-direction"])' 'does not route the outcome(s) change-direction'
expect_invalid 'an unknown outcome' '.steps.qa.on.maybe = "review"' 'routes unknown outcome(s) maybe'
expect_invalid 'a cycle that passes through no loop' '.steps.qa.on.fail = "implement"' 'form a cycle that passes through no loop'
expect_invalid 'a transition tagged with an undefined loop' '.steps.qa.on.fail.loop = "ghost"' 'loop "ghost" is not defined in loops'
expect_invalid 'a loop no transition uses' '.loops.extra = {maxIterations: 2, onExhausted: "escalate"}' 'loop "extra" is used by no transition'
expect_invalid 'a loop that resets a loop that does not exist' '.loops.direction.resets = ["ghost"]' 'resets "ghost", which is not another defined loop'
expect_invalid 'a loop that resets itself' '.loops.direction.resets = ["direction"]' 'resets "direction", which is not another defined loop'
expect_invalid 'a step-back step that routes done back into the build (it would bypass the round cap)' '.steps["step-back"].on.done = "implement"' 'its step-back step "step-back" routes done to "implement"'
expect_invalid 'an input that reads the decision of a step that is not a decision step' '.steps.qa.input += [{name: "d", from: "decision", step: "implement"}]' 'which is not a decision step'
expect_invalid 'a mistyped key' '.steps.qa.onn = {}' 'steps.qa.onn is an unknown key'
expect_invalid 'a deliver step that names a role' '.steps.deliver.role = "qa"' 'steps.deliver.role is not allowed here'
expect_invalid 'a work step without a role' 'del(.steps.qa.role)' 'steps.qa is missing required key "role"'
expect_invalid 'a work step bound to an alias that is not defined' '.steps.qa.role = "ghost"' 'role "ghost" is not an alias in roles'
expect_invalid 'a role alias no step uses' '.roles.extra = "qa"' 'role alias "extra" is used by no step'
expect_invalid 'a start step that does not exist' '.start = "nope"' 'start step "nope" is not a step'
expect_invalid 'a definition whose name differs from its file' '.name = "other"' 'must equal the file name'
expect_invalid 'an input that reads the report of a missing step' '.steps.qa.input += [{name: "x", from: "report", step: "ghost"}]' 'reads the report of "ghost"'
expect_invalid 'an input that takes feedback from a non-verdict step' '.steps.qa.input += [{name: "x", from: "feedback", steps: ["implement"]}]' 'is not a verdict step'
expect_invalid 'an input of an unknown kind' '.steps.qa.input += [{name: "x", from: "magic"}]' 'must be one of task, change, delta, report, feedback'
expect_invalid 'a risk input with no risk step' '.steps.classify.output = "result" | .roles.classifier = "senior-fullstack" | .steps.classify.on = {done: "qa", blocked: "@escalate", "change-direction": "redirect"}' 'reads the risk classification, but no step has output risk'
expect_invalid 'no path to @complete' '.steps.deliver.on.done = "@escalate"' 'no reachable transition leads to @complete'
expect_invalid 'a decision with one choice' '.steps.redirect.on = {reshape: {to: "implement", loop: "direction"}}' 'a decision needs at least two choices'
expect_invalid 'a decision with no criteria' '.steps.redirect.criteria = []' 'needs at least 1 item'
expect_invalid 'a step name that is not kebab-case' '.steps["Bad_Name"] = .steps.deliver' 'key "Bad_Name" does not match'
expect_invalid 'a version below 1' '.version = 0' 'version must be >= 1'
expect_invalid 'a missing when' 'del(.when)' 'missing required key "when"'
expect_invalid 'commits on a step that is not a result step' '.steps.qa.commits = true' 'commits only applies to a work step with output result'
expect_invalid 'verifies on a step that is not a verdict step' '.steps.implement.verifies = ["qa"]' 'verifies only applies to a work step with output verdict'
expect_invalid 'verifies a step that is not a verdict step' '.steps["verify-review"].verifies = ["implement"]' 'verifies "implement", which is not a verdict step'
expect_invalid 'a verifier that takes no feedback from what it verifies' '.steps["verify-review"].input |= map(select(.name != "feedback"))' 'verifies steps it takes no feedback from'
expect_invalid 'a change input with no committing step' '.steps.implement.commits = false | del(.steps.implement.commits)' 'reads the change, but no step of this workflow commits'
expect_invalid 'a when on an attribute that does not exist' '.steps.review.on.pass[0].when = {colour: ["red"]}' 'is not one of the allowed forms'
expect_invalid 'a when with an impossible value' '.steps.review.on.pass[0].when = {security: ["maybe"]}' 'when security cannot be "maybe"'
expect_invalid 'a list of alternatives whose last one has a when' '.steps.review.on.pass[1].when = {security: ["required"]}' 'the last alternative must have no when'
expect_invalid 'a list of alternatives whose first one has no when' '.steps.review.on.pass[0] |= del(.when)' 'only the last alternative may omit when'
expect_invalid 'a when outside a list' '.steps.qa.on.pass = {to: "review", when: {security: ["required"]}}' 'when is only meaningful in a list of alternatives'
expect_invalid 'an unknown gate' '.gates.vibes = "enforce"' 'must be one of evidence, answers, commit, coverage'
expect_invalid 'a gate mode that is neither observe nor enforce' '.gates.commit = "maybe"' 'must be one of observe, enforce'
printf '{ not json\n' > "$T/fx/bad.json"
check 'validate rejects a file that is not JSON' "$("$W" validate "$T/fx/bad.json" 2>&1 | grep -c 'not valid JSON')" 1
out=$("$W" validate no-such-workflow 2>&1); rc=$?
check 'validate of an unknown workflow fails' "$rc" 1
# One engine, no names in it: the definitions bind steps to roles only through the roles map.
check 'the engine hard-codes no step name or role name' "$(grep -vE '^[[:space:]]*#' "$W" | grep -vE 'layer must be|is not a known mode' | grep -nE '"(qa|implement|review|classify|ship|plan|security|verify-review|step-back|redirect)"|senior-fullstack|code-reviewer|planner|risk-classifier|finding-verifier' || true)" ''

# --- 2. the block parsers are strict -------------------------------------------------------
vt() { # <label> <report-file> <exit> <verdict> <valid>
  local out rc
  out=$("$W" verdict "$2" 2>&1); rc=$?
  check "verdict $1: exit $3" "$rc" "$3"
  check "verdict $1: $4, valid=$5" "$(printf '%s' "$out" | jq -r '"\(.verdict) \(.valid)"')" "$4 $5"
}
report "$T/v-pass.md" PASS
report "$T/v-pass-opt.md" PASS 'O-1:OPTIONAL:nit' 'P-1:PRE-EXISTING:an old bug'
report "$T/v-fail.md" FAIL 'QA-1:BLOCKER:wrong total' 'QA-2:IMPORTANT:no error path'
report "$T/v-blocked.md" BLOCKED 'B-1:BLOCKER:the test runner is missing'
report "$T/v-direction.md" CHANGE-DIRECTION 'D-1:IMPORTANT:the cache is not the bottleneck'
vt 'a well-formed PASS' "$T/v-pass.md" 0 PASS true
vt 'a PASS that carries OPTIONAL and PRE-EXISTING items' "$T/v-pass-opt.md" 0 PASS true
vt 'a well-formed FAIL' "$T/v-fail.md" 1 FAIL true
vt 'a well-formed BLOCKED' "$T/v-blocked.md" 3 BLOCKED true
vt 'a well-formed CHANGE-DIRECTION' "$T/v-direction.md" 4 CHANGE-DIRECTION true
check 'a FAIL keeps its feedback items verbatim' "$("$W" verdict "$T/v-fail.md" | jq -c '.feedback | map(.id)')" '["QA-1","QA-2"]'
check 'a verdict keeps the commit it judged' "$("$W" verdict "$T/v-fail.md" | jq -r .commit)" "$CUR"
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
vbad 'a lowercase verdict' '```verdict\n{"verdict":"pass","feedback":[]}\n```\n' 'exactly PASS, FAIL, BLOCKED or CHANGE-DIRECTION'
vbad 'an unknown verdict word' '```verdict\n{"verdict":"MAYBE","feedback":[]}\n```\n' 'exactly PASS, FAIL, BLOCKED or CHANGE-DIRECTION'
vbad 'a missing feedback array' '```verdict\n{"verdict":"PASS"}\n```\n' 'feedback must be an array'
vbad 'an item without where' '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"BLOCKER","what":"x"}]}\n```\n' 'feedback[0].where must be a non-empty string'
vbad 'an item with an empty what' '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"BLOCKER","what":" ","where":"f"}]}\n```\n' 'feedback[0].what must be a non-empty string'
vbad 'an unknown severity' '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"MAJOR","what":"x","where":"f"}]}\n```\n' 'severity must be BLOCKER, IMPORTANT, OPTIONAL or PRE-EXISTING'
vbad 'duplicate item ids' '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"BLOCKER","what":"x","where":"f"},{"id":"A","severity":"BLOCKER","what":"y","where":"f"}]}\n```\n' 'ids are not unique'
vbad 'a PASS carrying a BLOCKER' '```verdict\n{"verdict":"PASS","feedback":[{"id":"A","severity":"BLOCKER","what":"x","where":"f"}]}\n```\n' 'PASS verdict cannot carry'
vbad 'a FAIL with only OPTIONAL items' '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"OPTIONAL","what":"x","where":"f"}]}\n```\n' 'FAIL verdict needs at least one BLOCKER or IMPORTANT'
vbad 'a FAIL with only PRE-EXISTING items' '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"PRE-EXISTING","what":"x","where":"f"}]}\n```\n' 'FAIL verdict needs at least one BLOCKER or IMPORTANT'
vbad 'a FAIL with no items' '```verdict\n{"verdict":"FAIL","feedback":[]}\n```\n' 'FAIL verdict needs at least one'
vbad 'a BLOCKED with no items' '```verdict\n{"verdict":"BLOCKED","feedback":[]}\n```\n' 'BLOCKED verdict needs at least one item'
vbad 'a CHANGE-DIRECTION with no items' '```verdict\n{"verdict":"CHANGE-DIRECTION","feedback":[]}\n```\n' 'CHANGE-DIRECTION verdict needs at least one item'
vbad 'a commit that is not a sha' '```verdict\n{"verdict":"PASS","commit":"HEAD","feedback":[]}\n```\n' 'commit must be a hex commit sha'
vbad 'a class that is not kebab-case' '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"BLOCKER","what":"x","where":"f","class":"Swallowed Error"}]}\n```\n' 'class must be a short kebab-case name'
vbad 'an unknown layer' '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"BLOCKER","what":"x","where":"f","layer":"vibes"}]}\n```\n' 'layer must be author, qa, review, security, ci, spec or checklist'
vbad 'a dropped entry with an unknown reason' '```verdict\n{"verdict":"PASS","feedback":[],"dropped":[{"id":"A","reason":"felt wrong","evidence":"x"}]}\n```\n' 'dropped[0].reason must be'
vbad 'a dropped entry without evidence' '```verdict\n{"verdict":"PASS","feedback":[],"dropped":[{"id":"A","reason":"style-only"}]}\n```\n' 'dropped[0].evidence must be a non-empty string'
vbad 'an id that is both confirmed and dropped' '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"BLOCKER","what":"x","where":"f"}],"dropped":[{"id":"A","reason":"style-only","evidence":"e"}]}\n```\n' 'appears twice across feedback and dropped'
printf 'notes\r\n```verdict\r\n{"verdict":"PASS","feedback":[]}\r\n```\r\n' > "$T/v-crlf.md"
vt 'a report with CRLF line endings' "$T/v-crlf.md" 0 PASS true
printf '```bash\nls\n```\n\ntext\n\n```verdict\n{"verdict":"PASS","feedback":[],"note":"extra keys are ignored"}\n```\n' > "$T/v-extra.md"
vt 'an earlier non-verdict block and an extra key' "$T/v-extra.md" 0 PASS true
printf '```verdict\n{"verdict":"FAIL","feedback":[{"id":"A","severity":"IMPORTANT","what":"x","where":"f","class":"swallowed-error","rootCause":"retry hides it","layer":"author"}],"dropped":[]}\n```\n' > "$T/v-fields.md"
check 'a verdict keeps class, rootCause and layer on an item' "$("$W" verdict "$T/v-fields.md" | jq -c '.feedback[0] | [.class, .rootCause, .layer]')" '["swallowed-error","retry hides it","author"]'
out=$("$W" verdict "$T/no-such-report.md" 2>&1); rc=$?
check 'verdict of an unreadable file is a usage error, not a pass' "$rc" 2

rt() { # <label> <printf-content> <exit> <needle-or-empty>
  printf "$2" > "$T/r-t.md"
  out=$("$W" result "$T/r-t.md" 2>&1); rc=$?
  check "result $1: exit $3" "$rc" "$3"
  [ -z "$4" ] || has "result $1: names the defect" "$(printf '%s' "$out" | jq -r '.problems | join("; ")')" "$4"
}
rt 'a well-formed done' '```result\n{"status":"done","base":"aaaaaaa","commit":"bbbbbbb","evidence":[{"command":"c","observed":"o"}],"answers":[{"id":"A","status":"fixed","evidence":"e"},{"id":"B","status":"rejected","reason":"r"}],"unverified":["x"]}\n```\n' 0 ''
rt 'a done that changed nothing (no base, no commit)' '```result\n{"status":"done","evidence":[{"command":"c","observed":"o"}]}\n```\n' 0 ''
rt 'a well-formed blocked' '```result\n{"status":"blocked","blocker":"the service is down"}\n```\n' 0 ''
rt 'a well-formed change-direction' '```result\n{"status":"change-direction","direction":"the cache is not the bottleneck"}\n```\n' 0 ''
rt 'a missing block' 'done!\n' 1 'no fenced block'
rt 'a block tagged verdict' '```verdict\n{"verdict":"PASS","feedback":[]}\n```\n' 1 'tagged "verdict", not "result"'
rt 'an unknown status' '```result\n{"status":"finished"}\n```\n' 1 'status must be exactly done, blocked or change-direction'
rt 'a base without a commit' '```result\n{"status":"done","base":"aaaaaaa"}\n```\n' 1 'base and commit go together'
rt 'a commit that is not a sha' '```result\n{"status":"done","base":"aaaaaaa","commit":"main"}\n```\n' 1 'commit must be a hex commit sha'
rt 'evidence without observed output' '```result\n{"status":"done","evidence":[{"command":"c"}]}\n```\n' 1 'evidence[0].observed must be a non-empty string'
rt 'a fixed answer without evidence' '```result\n{"status":"done","answers":[{"id":"A","status":"fixed"}]}\n```\n' 1 'is fixed: evidence must be a non-empty string'
rt 'a rejected answer without a reason' '```result\n{"status":"done","answers":[{"id":"A","status":"rejected"}]}\n```\n' 1 'is rejected: reason must be a non-empty string'
rt 'duplicate answer ids' '```result\n{"status":"done","answers":[{"id":"A","status":"fixed","evidence":"e"},{"id":"A","status":"fixed","evidence":"e"}]}\n```\n' 1 'answers ids are not unique'
rt 'a blocked without a blocker' '```result\n{"status":"blocked"}\n```\n' 1 'a blocked result needs blocker'
rt 'a change-direction without a direction' '```result\n{"status":"change-direction"}\n```\n' 1 'a change-direction result needs direction'
check 'result keeps the evidence and the answers' "$(printf '```result\n{"status":"done","evidence":[{"command":"c","observed":"o"}],"answers":[{"id":"A","status":"fixed","evidence":"e"}]}\n```\n' > "$T/r-t.md"; "$W" result "$T/r-t.md" | jq -c '[(.evidence | length), (.answers | map(.id))]')" '[1,["A"]]'

kt() { # <label> <printf-content> <exit> <needle-or-empty>
  printf "$2" > "$T/k-t.md"
  out=$("$W" risk "$T/k-t.md" 2>&1); rc=$?
  check "risk $1: exit $3" "$rc" "$3"
  [ -z "$4" ] || has "risk $1: names the defect" "$(printf '%s' "$out" | jq -r '.problems | join("; ")')" "$4"
}
kt 'a well-formed low' '```risk\n{"tier":"low","security":"not-required","commit":"bbbbbbb","reasons":["docs only"]}\n```\n' 0 ''
kt 'a well-formed high' '```risk\n{"tier":"high","security":"required","commit":"bbbbbbb","sensitive":["ci-workflow"],"checklist":["R-3"],"reasons":["edits a workflow file"]}\n```\n' 0 ''
kt 'a blocked classification' '```risk\n{"tier":"blocked","reasons":["the base branch cannot be read"]}\n```\n' 0 ''
kt 'an unknown tier' '```risk\n{"tier":"extreme","security":"required","commit":"bbbbbbb","reasons":["x"]}\n```\n' 1 'tier must be exactly low, medium, high or blocked'
kt 'a missing security field' '```risk\n{"tier":"low","commit":"bbbbbbb","reasons":["x"]}\n```\n' 1 'security must be required or not-required'
kt 'a missing commit' '```risk\n{"tier":"low","security":"not-required","reasons":["x"]}\n```\n' 1 'commit must be the hex sha'
kt 'no reasons' '```risk\n{"tier":"low","security":"not-required","commit":"bbbbbbb","reasons":[]}\n```\n' 1 'reasons must be a non-empty array'
kt 'a sensitive surface on a low tier' '```risk\n{"tier":"low","security":"not-required","commit":"bbbbbbb","sensitive":["auth"],"reasons":["x"]}\n```\n' 1 'a sensitive surface means tier medium or high and a required security review'
kt 'a sensitive surface without a security review' '```risk\n{"tier":"medium","security":"not-required","commit":"bbbbbbb","sensitive":["auth"],"reasons":["x"]}\n```\n' 1 'a sensitive surface means'
kt 'a high tier without a security review' '```risk\n{"tier":"high","security":"not-required","commit":"bbbbbbb","reasons":["x"]}\n```\n' 1 'a high tier requires a security review'

# --- 3. the engine on scripted outcome sequences -------------------------------------------
BTR=build-test-review
mkdir -p "$S/a" "$S/b" "$S/c" "$S/d" "$S/e" "$S/f" "$S/g" "$S/h" "$S/i"

# 3a. straight through, security not required
st=$S/a/workflow.json
adv $BTR "$st" --task 'TASK-A'
check '3a: starting prints the start step' "$(o .step)" implement
check '3a: the start step is a work step with the implementer role' "$(o '"\(.kind) \(.role) \(.roleName) \(.output)"')" 'work implementer senior-fullstack result'
check '3a: a start with no result flag is idempotent' "$("$W" next $BTR "$st" | jq -r .iteration)" 1
st_impl $BTR "$st" aaaaaaa bbbbbbb
check '3a: implement done -> classify' "$(o .step)" classify
check '3a: classify receives the change the engine tracks' "$(o '.inputs[] | select(.name == "change") | .value')" 'aaaaaaa..bbbbbbb'
st_risk $BTR "$st" low not-required bbbbbbb
check '3a: classify low -> qa' "$(o .step)" qa
check '3a: qa receives the risk classification (the tier is the change, not the author)' "$(o '.inputs[] | select(.name == "risk") | .attrs.tier')" low
check '3a: qa has no feedback on its first run and no delta yet' "$(o '[.inputs[] | select(.name == "feedback" or .name == "delta")] | length')" 0
st_vd $BTR "$st" PASS bbbbbbb
check '3a: qa PASS -> review' "$(o .step)" review
st_vd $BTR "$st" PASS bbbbbbb
check '3a: review PASS with no security need -> ship (the security gate is skipped)' "$(o .step)" ship
check '3a: ship is a work step bound to release-engineer' "$(o '"\(.kind) \(.roleName)"')" 'work release-engineer'
st_vd $BTR "$st" PASS bbbbbbb
check '3a: ship PASS -> deliver' "$(o .step)" deliver
check '3a: deliver is a step kind with no role' "$(o '"\(.kind) \(.role) \(.handoff)"')" 'deliver null null'
has '3a: the delivery spec carries the verification stamp' "$(o .spec)" 'Verification stamp'
has '3a: ... listing qa at the commit it ran on' "$(o .spec)" '- qa: pass at commit bbbbbbb (run 1)'
has '3a: a low tier needs no human approval' "$(o .spec)" 'Required human approvals before merge: 0'
has '3a: the delivery never merges' "$(o .spec)" 'never merges'
check '3a: no spec carries the section 0 routing trace line (the Captain pastes the whole spec unchanged and prints the trace line separately)' "$(printf '%s\n' "$(o .spec)" | grep -c '^Workflow: ')" 0
has '3a: the delivery spec opens by naming workflow, version, step and run' "$(o .spec)" 'Workflow step: build-test-review v2, step deliver, run #1, delivery performed by Firstmate'
adv $BTR "$st" --outcome done
check '3a: deliver done -> complete' "$(o .status)" complete
check '3a: loop counters are untouched on a straight run' "$(o '[.loops[].used] | add')" 0
check '3a: the history is the exact path taken (no security step)' "$(jq -r '[.history[] | "\(.step):\(.outcome)"] | join(" ")' "$st")" 'implement:done classify:low qa:pass review:pass ship:pass deliver:done'
adv $BTR "$st" --outcome done
check '3a: a finished workflow refuses more results' "$RC" 1
has '3a: ... and says it is complete' "$OUT" 'workflow is complete'

# 3b. QA fails twice, then passes: feedback reaches the implementer verbatim, every fix is classified again
st=$S/b/workflow.json
report "$T/qa1.md" FAIL 'QA-1:BLOCKER:total is wrong for 0 items:off-by-one' 'QA-2:IMPORTANT:no error path'
CUR=ccccccc; report "$T/qa2.md" FAIL 'QA-1:BLOCKER:still wrong for 0 items'; CUR=bbbbbbb
st_to_qa $BTR "$st" medium not-required 'TASK-B'
st_vd $BTR "$st" FAIL bbbbbbb 'QA-1:BLOCKER:total is wrong for 0 items:off-by-one' 'QA-2:IMPORTANT:no error path'
check '3b: qa FAIL -> implement again' "$(o '"\(.step) \(.iteration)"')" 'implement 2'
check '3b: the loop counter counts the fix round' "$(o '.loops["qa-fix"].used')" 1
want=$(items_json 'QA-1:BLOCKER:total is wrong for 0 items:off-by-one' 'QA-2:IMPORTANT:no error path')
check '3b: the implementer receives exactly the QA feedback list' "$(o '.inputs[] | select(.name == "feedback") | .items' | fb .)" "$want"
has '3b: the spec carries each feedback item verbatim' "$(o .spec)" '{"id":"QA-2","severity":"IMPORTANT","what":"no error path","where":"src/app.py:12"}'
check '3b: the implementer also gets the change to fix' "$(o '.inputs[] | select(.name == "change") | .value')" 'aaaaaaa..bbbbbbb'
st_impl $BTR "$st" bbbbbbb ccccccc
check '3b: after the fix the change is classified again (a new commit invalidates the old classification)' "$(o '"\(.step) \(.iteration)"')" 'classify 2'
check '3b: the change range spans the whole work, from the first base' "$(o '.inputs[] | select(.name == "change") | .value')" 'aaaaaaa..ccccccc'
st_risk $BTR "$st" medium not-required ccccccc
check '3b: then qa runs again' "$(o .step)" qa
check '3b: qa re-evaluates against the feedback it gave' "$(o '.inputs[] | select(.name == "feedback") | .items' | fb .)" "$want"
check '3b: qa is handed the delta since the previous result (diff-only re-verification)' "$(o '.inputs[] | select(.name == "delta") | .value')" 'bbbbbbb..ccccccc'
st_vd $BTR "$st" FAIL ccccccc 'QA-1:BLOCKER:still wrong for 0 items'
check '3b: a second FAIL goes back again' "$(o '"\(.step) \(.loops["qa-fix"].used)"')" 'implement 2'
check '3b: the second round hands over only the latest feedback' "$(o '.inputs[] | select(.name == "feedback") | .items' | fb .)" "$(items_json 'QA-1:BLOCKER:still wrong for 0 items')"
st_impl $BTR "$st" ccccccc ddddddd
st_risk $BTR "$st" medium not-required ddddddd
st_vd $BTR "$st" PASS ddddddd
check '3b: qa PASS after two failures -> review' "$(o .step)" review
check '3b: the closed QA feedback is not handed to the review' "$(o '[.inputs[] | select(.name == "feedback")] | length')" 0
check '3b: the first review after QA fix rounds gets the whole change, with no delta (it never saw the earlier commits)' "$(o '[.inputs[] | select(.name == "delta")] | length')" 0
check '3b: two fix rounds are counted' "$(o '.loops["qa-fix"].used')" 2
check '3b: the review loop is untouched' "$(o '.loops["review-fix"].used')" 0

# 3c. review findings: raw -> verified -> implementer; OPTIONAL and PRE-EXISTING are notes, not feedback
st=$S/c/workflow.json
st_to_qa $BTR "$st" medium not-required 'TASK-C'
st_vd $BTR "$st" PASS bbbbbbb
st_vd $BTR "$st" FAIL bbbbbbb 'REV-1:IMPORTANT:the retry swallows the error:swallowed-error' 'REV-2:OPTIONAL:rename x' 'REV-3:PRE-EXISTING:the old loader leaks a handle' 'REV-4:BLOCKER:wrong sign on refunds'
check '3c: review FAIL -> verify-review (a second worker, before the implementer hears anything)' "$(o '"\(.step) \(.roleName)"')" 'verify-review finding-verifier'
check '3c: no fix round is spent yet' "$(o '[.loops[].used] | add')" 0
check '3c: the verifier receives only the blocking findings, verbatim' "$(o '.inputs[] | select(.name == "feedback") | .items | map(.id)' | fb .)" '["REV-1","REV-4"]'
st_vd $BTR "$st" FAIL bbbbbbb 'REV-1:IMPORTANT:the retry swallows the error:swallowed-error'
check '3c: verify-review FAIL -> implement (loop review-fix)' "$(o '"\(.step) \(.loops["review-fix"].used)"')" 'implement 1'
check '3c: the implementer receives the CONFIRMED list, not the reviewer raw list' "$(o '.inputs[] | select(.name == "feedback") | .items | map(.id)' | fb .)" '["REV-1"]'
check '3c: the OPTIONAL and PRE-EXISTING items are recorded as notes, not sent back' "$(jq -c '[.notes[].items[].id]' "$st")" '["REV-2","REV-3"]'
st_impl $BTR "$st" bbbbbbb ccccccc '[{"id":"REV-1","status":"fixed","evidence":"bash tests/run.sh: retry now surfaces the error"}]'
st_risk $BTR "$st" medium not-required ccccccc
check '3c: after the fix qa runs again, with the confirmed finding to re-check' "$(o '"\(.step) \(.inputs[] | select(.name == "feedback") | .items[0].id)"')" 'qa REV-1'
st_vd $BTR "$st" PASS ccccccc
check '3c: the re-review is handed the confirmed findings and the delta' "$(o '"\(.step) \(.inputs[] | select(.name == "feedback") | .items[0].id) \(.inputs[] | select(.name == "delta") | .value)"')" 'review REV-1 bbbbbbb..ccccccc'
has '3c: ... and the findings already posted, so none is repeated' "$(o .spec)" 'every finding recorded by review, verify-review'
check '3c: the review instruction says re-reviews cover the delta only' "$(o '.instruction | contains("Run 2 and later review only the delta")')" true
st_vd $BTR "$st" PASS ccccccc
check '3c: review PASS closes the findings -> ship' "$(o .step)" ship
st_vd $BTR "$st" PASS ccccccc
check '3c: the delivery spec lists the non-blocking notes verbatim' "$(o '.spec | contains("rename x") and contains("the old loader leaks a handle")')" true
adv $BTR "$st" --outcome done
check '3c: complete' "$(o .status)" complete
check '3c: the history is the exact path taken' "$(jq -r '[.history[] | "\(.step):\(.outcome)"] | join(" ")' "$st")" \
  'implement:done classify:medium qa:pass review:fail verify-review:fail implement:done classify:medium qa:pass review:pass ship:pass deliver:done'

# 3d. the verifier refutes every finding: nothing goes back, the run goes on
st=$S/d/workflow.json
st_to_qa $BTR "$st" medium not-required 'TASK-D'
st_vd $BTR "$st" PASS bbbbbbb
st_vd $BTR "$st" FAIL bbbbbbb 'REV-1:IMPORTANT:a style opinion presented as a bug' 'REV-2:IMPORTANT:cannot happen: the caller validates'
printf 'verified\n\n```verdict\n{"verdict":"PASS","commit":"bbbbbbb","feedback":[],"dropped":[{"id":"REV-1","reason":"style-only","evidence":"no behaviour differs: ran the suite with and without"},{"id":"REV-2","reason":"not-reproducible","evidence":"the caller rejects the input at src/app.py:12; ran it"}]}\n```\n' > "$T/ver-all.md"
adv $BTR "$st" --report "$T/ver-all.md"
check '3d: verify-review PASS (every finding refuted) -> ship, no implementer round' "$(o '"\(.step) \(.loops["review-fix"].used)"')" 'ship 0'
check '3d: the dropped findings and their reasons are kept in the history' "$(jq -c '[.history[] | select(.step == "verify-review") | .dropped[] | [.id, .reason]]' "$st")" '[["REV-1","style-only"],["REV-2","not-reproducible"]]'
check '3d: the raw review feedback is closed once verified' "$(jq -c '[.feedback[] | select(.open)] | length' "$st")" 0

# 3e. the round cap: three fix rounds, then the author steps back instead of a fourth
st=$S/e/workflow.json
st_to_qa $BTR "$st" medium not-required 'TASK-E'
head=bbbbbbb
for n in 1 2 3; do
  st_vd $BTR "$st" FAIL "$head" "QA-$n:BLOCKER:round $n still wrong"
  check "3e: qa FAIL #$n is sent back (counter $n/3)" "$(o '"\(.step) \(.status) \(.loops["qa-fix"].used)"')" "implement running $n"
  nh="c${n}c${n}c${n}c"; st_impl $BTR "$st" "$head" "$nh"; st_risk $BTR "$st" medium not-required "$nh"; head=$nh
done
st_vd $BTR "$st" FAIL "$head" 'QA-4:BLOCKER:round 4 still wrong'
check '3e: the fourth FAIL is not a fourth round: the author steps back' "$(o '"\(.step) \(.status) \(.role)"')" 'step-back running implementer'
check '3e: the counter is not pushed past the cap' "$(o '.loops["qa-fix"].used')" 3
has '3e: the step-back spec says the round cap was reached' "$(o .spec)" 'ROUND CAP REACHED'
has '3e: ... and forbids another round' "$(o .spec)" 'Do not fix anything and do not start another round'
has '3e: ... and tells the author to leave `answers` empty (nothing is fixed; only fixed or rejected is accepted there)' "$(o .spec)" 'leave `answers` empty ("answers": [])'
check '3e: the step-back is handed every accumulated finding, open and closed' "$(o '.inputs[] | select(.name == "accumulated") | .entries | map(.items[0].id) | join(" ")')" 'QA-1 QA-2 QA-3 QA-4'
rres "$T/sb-done.md" done - - '[]' '[{"command":"git log","observed":"the class returns because the parser trusts the caller"}]'
adv $BTR "$st" --report "$T/sb-done.md"
check '3e: step-back done (the approach stands) -> the captain decides: escalated, never a silent pass' "$(o .status)" escalated
has '3e: the escalation tells the captain the cap is reached' "$(o .spec)" 'The round cap is reached'
has '3e: ... and lists the accumulated feedback verbatim' "$(o .spec)" '{"id":"QA-4","severity":"BLOCKER","what":"round 4 still wrong","where":"src/app.py:12"}'
adv $BTR "$st" --report "$T/v-pass.md"
check '3e: an escalated workflow cannot be passed along by a later PASS' "$RC" 1
check '3e: ... it stays escalated' "$("$W" next $BTR "$st" | jq -r .status)" escalated
lacks '3e: deliver was never reached' "$(jq -r '[.history[].step] | join(" ")' "$st")" deliver
# the other branch of the step-back: the approach is wrong -> change direction, not a fourth round
st=$S/e/second.json
st_to_qa $BTR "$st" medium not-required 'TASK-E2'
head=bbbbbbb
for n in 1 2 3; do
  st_vd $BTR "$st" FAIL "$head" "QA-$n:BLOCKER:round $n still wrong"
  nh="d${n}d${n}d${n}d"; st_impl $BTR "$st" "$head" "$nh"; st_risk $BTR "$st" medium not-required "$nh"; head=$nh
done
st_vd $BTR "$st" FAIL "$head" 'QA-4:BLOCKER:round 4 still wrong'
rres "$T/sb-cd.md" change-direction - -
adv $BTR "$st" --report "$T/sb-cd.md"
check '3e: step-back change-direction -> redirect, a decision for the orchestrator' "$(o '"\(.step) \(.kind) \(.decision.choices | join(","))"')" 'redirect decision reshape,close,escalate'
has '3e: the decision shows the wrong premise the worker reported' "$(o .spec)" 'the premise is wrong: the cache is not the bottleneck'
adv $BTR "$st" --decide reshape --reason 'a different route to the same outcome: query the index instead of the cache'
check '3e: reshape -> implement again, inside the direction loop' "$(o '"\(.step) \(.loops.direction.used)"')" 'implement 1'
check '3e: the reshaped implement receives the direction' "$(o '.inputs[] | select(.name == "direction") | .direction.step')" step-back
check '3e: a reshape starts the QA and review rounds afresh (the reshaped approach is not exhausted at once)' "$(o '"\(.loops["qa-fix"].used) \(.loops["review-fix"].used)"')" '0 0'
check '3e: ... and the findings of the abandoned approach are closed, not handed to the reshaped implement' "$(o '[.inputs[] | select(.name == "feedback")] | length')" 0
st_impl $BTR "$st" "$head" eeeeeee
st_risk $BTR "$st" medium not-required eeeeeee
st_vd $BTR "$st" FAIL eeeeeee 'QA-5:BLOCKER:the new route also fails'
check '3e: once the reshaped step has reported, the direction is consumed (a later fix round does not see it)' "$(o '[.inputs[] | select(.name == "direction")] | length')" 0
check '3e: ... and a failure after the reshape is an ordinary first round, not the cap' "$(o '"\(.step) \(.loops["qa-fix"].used)"')" 'implement 1'

# 3f. change of direction from a verdict, from a result and from a report; close and escalate
st=$S/f/workflow.json
st_to_qa $BTR "$st" medium not-required 'TASK-F'
st_vd $BTR "$st" CHANGE-DIRECTION bbbbbbb 'D-1:IMPORTANT:the acceptance cannot be met by a cache - the data is per-user'
check '3f: a QA CHANGE-DIRECTION goes to the orchestrator at once, not into a fix loop' "$(o '"\(.step) \(.kind) \(.loops["qa-fix"].used)"')" 'redirect decision 0'
check '3f: the decision input carries the reviewer items verbatim' "$(o '.inputs[] | select(.name == "direction") | .direction.items[0].id')" D-1
adv $BTR "$st" --decide close --reason 'the goal is not reachable by this route; reported to the captain'
check '3f: close -> the workflow is closed, nothing is delivered' "$(o .status)" closed
has '3f: the closed spec says nothing is delivered' "$(o .spec)" 'nothing is delivered'
check '3f: the trace of a closed workflow' "$("$W" trace "$st")" 'Workflow: build-test-review v2 | step redirect #1 | loops qa-fix 0/3, review-fix 0/3, direction 0/2 | closed'
adv $BTR "$st" --decide escalate --reason 'again'
check '3f: a closed workflow refuses more results' "$RC" 1
st=$S/f/second.json
st_start $BTR "$st" 'TASK-F2'
rres "$T/res-cd.md" change-direction - -
adv $BTR "$st" --report "$T/res-cd.md"
check '3f: an implementer result with status change-direction -> redirect (raised early)' "$(o '"\(.step) \(.kind)"')" 'redirect decision'
check '3f: the direction text travels to the decision' "$(o '.inputs[] | select(.name == "direction") | .direction.text')" 'the premise is wrong: the cache is not the bottleneck'
adv $BTR "$st" --decide reshape --reason 'x'
adv $BTR "$st" --decide escalate --reason 'x'
check '3f: a decision step refuses a choice the definition does not route (state unchanged by the refusal)' "$RC" 1
rres "$T/res-cd2.md" change-direction - -
adv $BTR "$st" --report "$T/res-cd2.md"
adv $BTR "$st" --decide reshape --reason 'second reshape'
check '3f: a second reshape is allowed (direction 2/2)' "$(o '"\(.step) \(.loops.direction.used)"')" 'implement 2'
adv $BTR "$st" --report "$T/res-cd2.md"
adv $BTR "$st" --decide reshape --reason 'third reshape'
check '3f: a third reshape is not taken: the direction loop is exhausted -> escalated' "$(o .status)" escalated
has '3f: ... naming the loop' "$(o .escalation.reason)" 'loop direction is exhausted'

# 3g. malformed blocks and BLOCKED
st=$S/g/workflow.json
st_start $BTR "$st" 'TASK-G'
printf 'Everything looks fine. Ship it!\n' > "$T/noresult.md"
adv $BTR "$st" --report "$T/noresult.md"
check '3g: a result report with no block is sent back, not accepted and not a verdict (same step, run 2)' "$(o '"\(.step) \(.iteration) \(.status)"')" 'implement 2 running'
has '3g: the next spec shows why the report was refused' "$(o .spec)" 'Your previous report for this step was refused'
has '3g: ... naming the defect' "$(o .spec)" 'no fenced block'
adv $BTR "$st" --report "$T/noresult.md"
check '3g: refused twice -> still running, third run' "$(o '"\(.step) \(.iteration) \(.status)"')" 'implement 3 running'
adv $BTR "$st" --report "$T/noresult.md"
check '3g: refused a third time -> the step ends blocked and escalates' "$(o .status)" escalated
check '3g: the history records two refusals and the blocked outcome' "$(jq -r '[.history[] | .outcome] | join(" ")' "$st")" 'redo redo blocked'
st=$S/g/second.json
st_start $BTR "$st" 'TASK-G2'
adv $BTR "$st" --outcome done
check '3g: a result step refuses a caller-supplied outcome' "$RC" 1
has '3g: ... naming --report' "$OUT" 'takes its outcome from --report'
st_impl $BTR "$st" aaaaaaa bbbbbbb
printf 'Classified it: medium.\n' > "$T/norisk.md"
adv $BTR "$st" --report "$T/norisk.md"
check '3g: a risk report with no block is sent back too' "$(o '"\(.step) \(.iteration)"')" 'classify 2'
st_risk $BTR "$st" medium not-required bbbbbbb
printf 'Everything looks fine to me. Ship it!\n' > "$T/noverdict.md"
adv $BTR "$st" --report "$T/noverdict.md"
check '3g: a report with no verdict is a FAIL: back to implement' "$(o '"\(.step) \(.loops["qa-fix"].used)"')" 'implement 1'
check '3g: the feedback item says the verdict is missing' "$(o '.inputs[] | select(.name == "feedback") | .items[0].id')" VERDICT-1
has '3g: ... and why' "$(o '.inputs[] | select(.name == "feedback") | .items[0].what')" 'no fenced block'
check '3g: the history marks the verdict invalid' "$(jq -r '.history[-1].valid' "$st")" false
st=$S/g/third.json
st_to_qa $BTR "$st" medium not-required 'TASK-G3'
st_vd $BTR "$st" BLOCKED bbbbbbb 'B-1:BLOCKER:the test runner is missing'
check '3g: a BLOCKED verdict escalates' "$(o .status)" escalated
check '3g: the escalation carries the blocking item' "$(o '.escalation.feedback[0].items[0].id')" B-1
has '3g: the reason is the definition routing blocked to the captain' "$(o .escalation.reason)" 'step qa ended blocked'
st=$S/g/fourth.json
st_start $BTR "$st" 'TASK-G4'
rres "$T/res-blocked.md" blocked - -
adv $BTR "$st" --report "$T/res-blocked.md"
check '3g: a blocked result escalates' "$(o .status)" escalated
st=$S/g/fifth.json
st_start $BTR "$st" 'TASK-G5'
st_impl $BTR "$st" aaaaaaa bbbbbbb
krisk "$T/risk-blocked.md" blocked - - 2>/dev/null; printf 'x\n\n```risk\n{"tier":"blocked","reasons":["the base branch cannot be read"]}\n```\n' > "$T/risk-blocked.md"
adv $BTR "$st" --report "$T/risk-blocked.md"
check '3g: a blocked classification escalates' "$(o .status)" escalated

# 3h. conditional security routing: the change sets the tier, security can block, approvals scale with risk
st=$S/h/workflow.json
st_to_qa $BTR "$st" high required 'TASK-H'
check '3h: a high tier records two required human approvals' "$(jq -r .attrs.approvals "$st")" 2
st_vd $BTR "$st" PASS bbbbbbb
st_vd $BTR "$st" PASS bbbbbbb
check '3h: review PASS with a security review required -> security (not ship)' "$(o '"\(.step) \(.roleName)"')" 'security security-engineer'
st_vd $BTR "$st" FAIL bbbbbbb 'SEC-1:BLOCKER:the token is logged:secret-in-log' 'SEC-2:OPTIONAL:tighten the regex'
check '3h: a blocking security finding goes to its own verifier first' "$(o .step)" verify-security
check '3h: the verifier receives the security findings that block' "$(o '.inputs[] | select(.name == "feedback") | .items | map(.id)' | fb .)" '["SEC-1"]'
st_vd $BTR "$st" FAIL bbbbbbb 'SEC-1:BLOCKER:the token is logged:secret-in-log'
check '3h: a confirmed security finding goes to the implementer' "$(o '"\(.step) \(.loops["review-fix"].used)"')" 'implement 1'
st_impl $BTR "$st" bbbbbbb ccccccc '[{"id":"SEC-1","status":"fixed","evidence":"grep -r token src: no log line left"}]'
st_risk $BTR "$st" high required ccccccc '["secrets"]'
st_vd $BTR "$st" PASS ccccccc
st_vd $BTR "$st" PASS ccccccc
check '3h: security runs again on the new commit' "$(o .step)" security
st_vd $BTR "$st" PASS ccccccc
check '3h: security PASS -> ship' "$(o .step)" ship
st_vd $BTR "$st" PASS ccccccc
has '3h: the delivery states the two human approvals no agent verdict can satisfy' "$(o .spec)" 'Required human approvals before merge: 2 (risk tier high'
has '3h: ... and that an agent verdict never satisfies one' "$(o .spec)" 'never satisfies one'
adv $BTR "$st" --outcome done
check '3h: complete' "$(o .status)" complete

# 3i. gates: observe mode logs would-block and lets the result through
st=$S/i/workflow.json
st_start $BTR "$st" 'TASK-I'
rres "$T/res-noev.md" done aaaaaaa bbbbbbb '[]' '[]'
adv $BTR "$st" --report "$T/res-noev.md"
check '3i: observe: a done result with no evidence is let through (classify next)' "$(o .step)" classify
check '3i: ... and the would-block is logged on the history entry' "$(jq -c '.history[0].gates | map([.gate, .mode, .status])' "$st")" '[["evidence","observe","would-block"]]'
has '3i: ... and shown to the next worker as an observation, not an order' "$(o .spec)" 'Gate observations on the last recorded result'
st_risk $BTR "$st" medium not-required bbbbbbb
st_vd $BTR "$st" PASS aaaaaaa
check '3i: observe: a verdict naming an older commit is let through, logged as stale' "$(jq -c '.history[-1].gates | map([.gate, .status])' "$st")" '[["commit","would-block"]]'
st_vd $BTR "$st" FAIL bbbbbbb 'REV-1:IMPORTANT:real one' 'REV-2:IMPORTANT:another real one'
printf 'ver\n\n```verdict\n{"verdict":"FAIL","commit":"bbbbbbb","feedback":[{"id":"REV-1","severity":"IMPORTANT","what":"real","where":"f:1"}],"dropped":[]}\n```\n' > "$T/ver-miss.md"
adv $BTR "$st" --report "$T/ver-miss.md"
check '3i: observe: a verifier that leaves a finding unaccounted for is let through, logged' "$(jq -c '.history[-1].gates | map([.gate, .status])' "$st")" '[["coverage","would-block"]]'
has '3i: ... naming the missing id' "$(jq -r '.history[-1].gates[0].problems[0]' "$st")" 'finding REV-2 is in neither feedback nor dropped'
st_impl $BTR "$st" bbbbbbb ccccccc '[]'
check '3i: observe: a fix that leaves a handed id unanswered is let through, logged' "$(jq -c '.history[-1].gates | map(.gate)' "$st")" '["answers"]'
# enforce: the step is sent back with the problems; after two blocks of one gate the third is let through (escaped)
mkdir -p "$T/wfroot-enf" "$S/enf"
jq '.gates.commit = "enforce" | .gates.evidence = "enforce"' "$WF/build-test-review.json" > "$T/wfroot-enf/build-test-review.json"
export FM_WORKFLOWS_ROOT="$T/wfroot-enf"
st=$S/enf/workflow.json
st_start $BTR "$st" 'TASK-ENF'
adv $BTR "$st" --report "$T/res-noev.md"
check '3i: enforce: a done result with no evidence is sent back (same step, run 2), not accepted' "$(o '"\(.step) \(.iteration)"')" 'implement 2'
has '3i: ... the spec carries the GATE-evidence item' "$(o .spec)" '"id":"GATE-evidence"'
adv $BTR "$st" --report "$T/res-noev.md"
check '3i: enforce: sent back a second time (run 3)' "$(o '"\(.step) \(.iteration)"')" 'implement 3'
adv $BTR "$st" --report "$T/res-noev.md"
check '3i: enforce: a gate that blocked twice is let through the third time (never wedges a run)' "$(o .step)" classify
check '3i: ... recorded as escaped' "$(jq -c '.history[-1].gates | map([.gate, .status])' "$st")" '[["evidence","escaped"]]'
st_risk $BTR "$st" medium not-required bbbbbbb
st_vd $BTR "$st" PASS aaaaaaa
check '3i: enforce: a stale pass is sent back to be re-run on the head (qa run 2)' "$(o '"\(.step) \(.iteration)"')" 'qa 2'
has '3i: ... saying a new commit invalidates a pass' "$(o .spec)" 'a new commit invalidates a pass'
st_vd $BTR "$st" FAIL bbbbbbb 'QA-1:IMPORTANT:wrong output'
adv $BTR "$st" --report "$T/res-noev.md"
check '3i: enforce: blocks are counted per step visit, so a later fix round is enforced again (not escaped at once)' "$(jq -c '[.history[-1].gates[] | select(.gate == "evidence") | .status]' "$st")" '["blocked"]'
unset FM_WORKFLOWS_ROOT

# 3i2. a malformed verifier report is sent back; the reviewer's findings are never lost
st=$S/i2a/workflow.json
st_to_qa $BTR "$st" medium not-required 'TASK-I2'
st_vd $BTR "$st" PASS bbbbbbb
st_vd $BTR "$st" FAIL bbbbbbb 'REV-1:BLOCKER:the migration drops a column'
check '3i2: a review FAIL goes to the verifier' "$(o .step)" verify-review
printf 'I looked at it and nothing seems wrong.\n' > "$T/ver-bad.md"
adv $BTR "$st" --report "$T/ver-bad.md"
check '3i2: a verifier with no verdict block is sent back (same step, run 2), not passed as a FAIL' "$(o '"\(.step) \(.iteration)"')" 'verify-review 2'
check '3i2: ... and the reviewer finding stays open (never closed or lost)' "$(jq -c '[.feedback[] | select(.step == "review") | .open]' "$st")" '[true]'
check '3i2: ... and nothing is recorded as confirmed for the malformed report' "$(jq -s '[.[] | select(.event == "confirmed")] | length' "$(dirname "$st")/retro.jsonl")" 0
st_vd $BTR "$st" FAIL bbbbbbb 'REV-1:BLOCKER:the migration drops a column'
check '3i2: a valid verdict afterwards confirms it and goes to the implementer' "$(o '"\(.step) \(.loops["review-fix"].used)"')" 'implement 1'
check '3i2: the confirmed item is the reviewer one' "$(o '.inputs[] | select(.name == "feedback") | .items | map(.id)' | fb .)" '["REV-1"]'
st=$S/i2b/workflow.json
st_to_qa $BTR "$st" medium not-required 'TASK-I3'
st_vd $BTR "$st" PASS bbbbbbb
st_vd $BTR "$st" FAIL bbbbbbb 'REV-1:BLOCKER:the migration drops a column'
adv $BTR "$st" --report "$T/ver-bad.md"; adv $BTR "$st" --report "$T/ver-bad.md"
check '3i2: the verifier is sent back twice' "$(o '"\(.step) \(.iteration)"')" 'verify-review 3'
adv $BTR "$st" --report "$T/ver-bad.md"
check '3i2: a third malformed report is blocked -> escalated to the captain' "$(o .status)" escalated

# 3j. plan-build-test-review: the plan travels to every later step
PBTR=plan-build-test-review
st=$S/h/plan.json
printf '# Plan\nAssumptions: ...\n' > "$T/plan.md"
adv $PBTR "$st" --task 'TASK-J'
check '3j: the plan workflow starts at plan, with the planner role (a report step)' "$(o '"\(.step) \(.role) \(.roleName) \(.output)"')" 'plan planner planner report'
adv $PBTR "$st" --outcome done --report "$T/plan.md"
check '3j: plan done -> implement' "$(o .step)" implement
check '3j: implement receives the recorded plan report' "$(o '.inputs[] | select(.name == "plan") | .report')" "$T/plan.md"
st_impl $PBTR "$st" aaaaaaa bbbbbbb
st_risk $PBTR "$st" low not-required bbbbbbb
check '3j: qa is handed the plan too' "$(o '"\(.step) \(.inputs[] | select(.name == "plan") | .report)"')" "qa $T/plan.md"
st_vd $PBTR "$st" PASS bbbbbbb
check '3j: the reviewer is handed the plan too' "$(o '"\(.step) \(.inputs[] | select(.name == "plan") | .report)"')" "review $T/plan.md"
st_vd $PBTR "$st" PASS bbbbbbb
st_vd $PBTR "$st" PASS bbbbbbb
adv $PBTR "$st" --outcome done
check '3j: the plan workflow completes' "$(o .status)" complete
st=$S/h/plan2.json
adv $PBTR "$st" --task 'TASK-J2'
adv $PBTR "$st" --outcome blocked
check '3j: a planner that is blocked (open questions) escalates' "$(o .status)" escalated
st=$S/h/plan3.json
adv $PBTR "$st" --task 'TASK-J3'
adv $PBTR "$st" --outcome change-direction --report "$T/plan.md"
check '3j: a planner that finds the request premise wrong raises change-direction early -> redirect' "$(o '"\(.step) \(.kind)"')" 'redirect decision'
adv $PBTR "$st" --decide reshape --reason 're-plan the narrower request'
check '3j: reshape re-plans (back to the plan step)' "$(o .step)" plan
check '3j: the re-plan receives the direction with the planner report path' "$(o '.inputs[] | select(.name == "direction") | .direction.report')" "$T/plan.md"
adv $BTR "$S/h/plan.json"
check 'a state file of another workflow is refused' "$RC" 1
has '... saying which workflow it belongs to' "$OUT" 'belongs to workflow plan-build-test-review'

# 3k. the other workflows, end to end on scripted outcomes
# bug-fix: diagnose -> regression-test -> fix, the regression test is the gate
BF=bug-fix
st=$S/i/bugfix.json
adv $BF "$st" --task 'TASK-BF'
check '3k: bug-fix starts with the debugger diagnosing' "$(o '"\(.step) \(.roleName) \(.output)"')" 'diagnose debugger report'
printf 'status: done\nroot cause: the retry swallows the timeout\n' > "$T/diag.md"
adv $BF "$st" --outcome done --report "$T/diag.md"
check '3k: diagnosis -> a failing regression test written by the test-engineer' "$(o '"\(.step) \(.roleName)"')" 'regression-test test-engineer'
check '3k: the test-engineer receives the diagnosis' "$(o '.inputs[] | select(.name == "diagnosis") | .report')" "$T/diag.md"
st_impl $BF "$st" aaaaaaa bbbbbbb
check '3k: regression test done -> fix (the implementer, not the test author)' "$(o '"\(.step) \(.roleName)"')" 'fix senior-fullstack'
has '3k: the fix instruction forbids editing the regression test' "$(o .spec)" 'Do not edit that test'
check '3k: the fix receives the regression-test report' "$(o '.inputs[] | select(.name == "regression-test") | .step')" regression-test
st_impl $BF "$st" bbbbbbb ccccccc
check '3k: fix done -> classify (the whole change since the test base)' "$(o '"\(.step) \(.inputs[] | select(.name == "change") | .value)"')" 'classify aaaaaaa..ccccccc'
st_risk $BF "$st" medium not-required ccccccc
has '3k: qa treats a later edit of the regression test as a finding' "$(o .spec)" 'any change to it after its commit is an IMPORTANT finding'
check '3k: qa receives the regression-test report' "$(o '.inputs[] | select(.name == "regression-test") | .step')" regression-test
st_vd $BF "$st" PASS ccccccc
st_vd $BF "$st" PASS ccccccc
st_vd $BF "$st" PASS ccccccc
adv $BF "$st" --outcome done
check '3k: bug-fix completes' "$(o .status)" complete
adv $BF "$S/i/bugfix2.json" --task 'TASK-BF2'
adv $BF "$S/i/bugfix2.json" --outcome change-direction --report "$T/diag.md"
adv $BF "$S/i/bugfix2.json" --decide close --reason 'works as designed'
check '3k: a diagnosis that finds no defect raises change-direction and the task closes' "$(o .status)" closed
# refactor
RF=refactor
st=$S/i/refactor.json
adv $RF "$st" --task 'TASK-RF'
check '3k: refactor starts with the refactorist as the implementer' "$(o '"\(.step) \(.roleName)"')" 'refactor refactorist'
st_impl $RF "$st" aaaaaaa bbbbbbb
st_risk $RF "$st" low not-required bbbbbbb
has '3k: refactor qa is told behavior must be unchanged' "$(o .spec)" 'behavior must be unchanged'
# ui
UI=ui-build-verify-review
st=$S/i/ui.json
st_to_qa $UI "$st" medium not-required 'TASK-UI'
st_vd $UI "$st" PASS bbbbbbb
check '3k: ui: qa PASS -> a real-browser verification by ui-qa, before the review' "$(o '"\(.step) \(.roleName)"')" 'ui-verify ui-qa'
st_vd $UI "$st" FAIL bbbbbbb 'UI-1:BLOCKER:the submit button stays disabled after a valid form'
check '3k: ui verification FAIL -> the implementer (qa-fix loop)' "$(o '"\(.step) \(.loops["qa-fix"].used)"')" 'implement 1'
st_impl $UI "$st" bbbbbbb ccccccc
st_risk $UI "$st" medium not-required ccccccc
st_vd $UI "$st" PASS ccccccc
check '3k: ui: the browser step re-runs with the failing step to re-drive' "$(o '"\(.step) \(.inputs[] | select(.name == "feedback") | .items[0].id)"')" 'ui-verify UI-1'
st_vd $UI "$st" PASS ccccccc
check '3k: ui: browser PASS -> review' "$(o .step)" review
# research-decide
RD=research-decide
st=$S/i/research.json
adv $RD "$st" --task 'TASK-RD'
check '3k: research-decide starts with the researcher' "$(o '"\(.step) \(.roleName)"')" 'research researcher'
printf 'status: done\nfindings...\n' > "$T/research.md"; printf 'status: done\noptions...\n' > "$T/options.md"
adv $RD "$st" --outcome done --report "$T/research.md"
check '3k: research -> options by the architecture role' "$(o '"\(.step) \(.roleName)"')" 'options architecture'
adv $RD "$st" --outcome done --report "$T/options.md"
check '3k: options -> challenge by tenth-man, a verdict step' "$(o '"\(.step) \(.roleName) \(.output)"')" 'challenge tenth-man verdict'
report "$T/ch-fail.md" FAIL 'C-1:IMPORTANT:the recommendation ignores the migration cost' ; sed -i.bak 's/"commit": "bbbbbbb",//' "$T/ch-fail.md"; rm -f "$T/ch-fail.md.bak"
adv $RD "$st" --report "$T/ch-fail.md"
check '3k: a failed challenge sends the options back (loop refine)' "$(o '"\(.step) \(.loops.refine.used)"')" 'options 1'
adv $RD "$st" --outcome done --report "$T/options.md"
report "$T/ch-pass.md" PASS; adv $RD "$st" --report "$T/ch-pass.md"
check '3k: a passed challenge -> a decision for the orchestrator' "$(o '"\(.step) \(.kind) \(.decision.choices | join(","))"')" 'decide decision adopt,amend,reject,escalate'
adv $RD "$st" --decide adopt --reason 'survived the challenge; within the authority granted'
check '3k: adopt -> complete (no code changed, no delivery)' "$(o .status)" complete
st=$S/i/research3.json
adv $RD "$st" --task 'TASK-RD3'; adv $RD "$st" --outcome done --report "$T/research.md"; adv $RD "$st" --outcome done --report "$T/options.md"; adv $RD "$st" --report "$T/ch-pass.md"
adv $RD "$st" --decide amend --reason 'drop option B and add a rollback path'
check '3k: amend -> options again (loop refine)' "$(o '"\(.step) \(.loops.refine.used)"')" 'options 1'
check '3k: the stated amend reason reaches the options step (it is not an identical blind re-run)' "$(o '.inputs[] | select(.name == "amendment") | .reason')" 'drop option B and add a rollback path'
st=$S/i/research2.json
adv $RD "$st" --task 'TASK-RD2'; adv $RD "$st" --outcome done --report "$T/research.md"; adv $RD "$st" --outcome done --report "$T/options.md"; adv $RD "$st" --report "$T/ch-pass.md"
adv $RD "$st" --decide reject --reason 'not worth doing'
check '3k: reject -> closed' "$(o .status)" closed
# delegated-build: no second reviewer on top of no-mistakes
DB=delegated-build
st=$S/i/delegated.json
adv $DB "$st" --task 'TASK-DB'
check '3k: delegated-build starts at implement' "$(o '"\(.step) \(.roleName)"')" 'implement senior-fullstack'
st_impl $DB "$st" aaaaaaa bbbbbbb
check '3k: implement done -> deliver (no QA, no review, no gate worker)' "$(o '"\(.step) \(.kind)"')" 'deliver deliver'
has '3k: delivery goes through no-mistakes' "$(o .spec)" 'Deliver through no-mistakes'
has '3k: ... and says it adds no reviewer' "$(o .spec)" 'Add no reviewer or gate of your own'
adv $DB "$st" --outcome done
check '3k: delegated-build completes' "$(o .status)" complete
check '3k: delegated-build binds no reviewer role' "$(jq -r '[.roles[]] | join(",")' "$WF/delegated-build.json")" senior-fullstack
check '3k: delegated-build never blocks anything: every gate is observe' "$(jq -r '[.gates[]] | unique | join(",")' "$WF/delegated-build.json")" observe

# 3l. state handling
adv $BTR "$S/nostate.json"
check 'starting without --task is refused' "$RC" 1
adv $BTR "$S/nostate2.json" --report "$T/v-pass.md"
check 'recording a result before the workflow was started is refused' "$RC" 1
adv no-such-workflow "$S/nostate3.json" --task x
check 'starting an unknown workflow is refused' "$RC" 1
printf '{"a":1}\n' > "$S/notstate.json"
adv $BTR "$S/notstate.json"
check 'a file that is not a workflow state is refused' "$RC" 1
jq 'del(.engine)' "$S/a/workflow.json" > "$S/old-engine.json"
adv $BTR "$S/old-engine.json"
check 'a state file from before this engine is refused with an instruction' "$RC" 1
has '... naming the engine marker' "$OUT" 'predates engine'
# the state pins the definition it started with
mkdir -p "$T/wfroot-a"; cp "$WF/build-test-review.json" "$T/wfroot-a/"
export FM_WORKFLOWS_ROOT="$T/wfroot-a"
adv $BTR "$S/pinned.json" --task 'TASK-P'
jq '.steps.implement.on.done = "qa" | .version = 3' "$T/wfroot-a/build-test-review.json" > "$T/wfroot-a/x.json" && mv "$T/wfroot-a/x.json" "$T/wfroot-a/build-test-review.json"
st_impl $BTR "$S/pinned.json" aaaaaaa bbbbbbb
check 'a task in flight keeps the definition it started with (version 2 routes implement -> classify)' "$(o '"\(.step) \(.version)"')" 'classify 2'
unset FM_WORKFLOWS_ROOT
# a state file must not sit in a repository that would track it
mkdir -p "$T/repo-in-way"; git -C "$T/repo-in-way" init -q
adv $BTR "$T/repo-in-way/workflow.json" --task x
check 'a state file inside a git work tree is refused' "$RC" 1
has '... pointing at the task data folder' "$OUT" "task's data folder"
printf 'workflow.json\nretro.jsonl\n' > "$T/repo-in-way/.gitignore"
adv $BTR "$T/repo-in-way/workflow.json" --task x
check 'a git-ignored state file (a task data folder) is accepted' "$RC" 0
check 'the state file is written in place, with no temp file left behind' "$(find "$S" -name '*.json.*' | wc -l | tr -d ' ')" 0

# --- 4. every step's handoff is fm-role-handoff's, through the role alias --------------------
st=$S/handoff.json; mkdir -p "$S/handoff"; st=$S/handoff/workflow.json
adv $BTR "$st" --task 'TASK-I'
check '4: the implement spec contains bin/fm-role-handoff senior-fullstack verbatim' \
  "$(printf '%s' "$OUT" | jq -r .spec | grep -cxF -f <("$FIX_SRC/bin/fm-role-handoff" senior-fullstack))" "$("$FIX_SRC/bin/fm-role-handoff" senior-fullstack | grep -c .)"
check '4: the handoff field is exactly the role handoff' "$(o .handoff)" "$("$FIX_SRC/bin/fm-role-handoff" senior-fullstack)"
check '4: no spec line is a markdown heading (a heading would end the brief ## Firstmate spec section)' "$(printf '%s' "$OUT" | jq -r .spec | grep -c '^#' || true)" 0
st_impl $BTR "$st" aaaaaaa bbbbbbb
check '4: classify gets the risk-classifier role handoff (no skills)' "$(o .handoff)" "$("$FIX_SRC/bin/fm-role-handoff" risk-classifier)"
st_risk $BTR "$st" medium not-required bbbbbbb
check '4: qa gets the qa role handoff (its ROLE.md and its autoloadSkills)' "$(o .handoff)" "$("$FIX_SRC/bin/fm-role-handoff" qa)"
has '4: ... which names the skill the qa role loads' "$(o .handoff)" "$T/skills-root/verification-before-completion/SKILL.md"
st_vd $BTR "$st" PASS bbbbbbb
check '4: review gets the code-reviewer role handoff' "$(o .handoff)" "$("$FIX_SRC/bin/fm-role-handoff" code-reviewer)"
st_vd $BTR "$st" FAIL bbbbbbb 'REV-1:IMPORTANT:x'
check '4: verify-review gets the finding-verifier role handoff' "$(o .handoff)" "$("$FIX_SRC/bin/fm-role-handoff" finding-verifier)"
st_vd $BTR "$st" FAIL bbbbbbb 'REV-1:IMPORTANT:x'
check '4: the fix round binds the implementer alias again (same role, a fresh worker)' "$(o .handoff)" "$("$FIX_SRC/bin/fm-role-handoff" senior-fullstack)"
# changing the agent for one task is --role at start; for every task it is one edit of the roles map in a PR
adv $BTR "$S/swap.json" --task 'TASK-J' --role implementer=lead
check '4: --role implementer=lead at start swaps the agent of every implementer step of this task (lead for a big step)' "$(o .handoff)" "$("$FIX_SRC/bin/fm-role-handoff" lead)"
check '4: ... and the step still reports its alias' "$(o '"\(.role) \(.roleName)"')" 'implementer lead'
out=$("$W" next $BTR "$S/swap.json" --role implementer=scout 2>&1); rc=$?
check '4: --role on an existing state file is refused (the embedded definition is never edited mid-task)' "$rc" 1
has '4: ... saying why' "$out" 'only applies when the state file is created'
out=$("$W" next $BTR "$S/swap2.json" --task x --role implementer=scout 2>&1); rc=$?
check '4: --role with a role that cannot produce a result block is refused at start' "$rc" 1
check '4: ... and writes no state file' "$([ -e "$S/swap2.json" ] && echo yes || echo no)" no
out=$("$W" next $BTR "$S/swap3.json" --task x --role nonsense=lead 2>&1); rc=$?
check '4: --role naming an alias the workflow does not have is refused' "$rc" 1
has '4: ... naming the alias' "$out" 'no role alias "nonsense"'
# the role skill budget the roles lint enforces holds for the roles the workflows bind
for role in $(jq -r '.roles[]' "$WF"/*.json 2>/dev/null | sort -u); do
  [ "$("$FIX_SRC/bin/fm-role-handoff" --skills "$role" | grep -c .)" -le 3 ] && ok "4: role $role stays within the skill budget" || bad "4: role $role exceeds the skill budget"
done
check '4: the qa role loads exactly one skill' "$("$FIX_SRC/bin/fm-role-handoff" --skills qa)" verification-before-completion

# --- 5. trace derivation ---------------------------------------------------------------------
mkdir -p "$S/t"; st=$S/t/workflow.json
adv $BTR "$st" --task 'TASK-T'
check '5: trace at the start' "$("$W" trace "$st")" 'Workflow: build-test-review v2 | step implement #1 | loops qa-fix 0/3, review-fix 0/3, direction 0/2 | running'
st_impl $BTR "$st" aaaaaaa bbbbbbb; st_risk $BTR "$st" medium not-required bbbbbbb
st_vd $BTR "$st" FAIL bbbbbbb 'QA-1:BLOCKER:x'
st_impl $BTR "$st" bbbbbbb ccccccc; st_risk $BTR "$st" medium not-required ccccccc
st_vd $BTR "$st" FAIL ccccccc 'QA-1:BLOCKER:x'
check '5: trace after two QA failures' "$("$W" trace "$st")" 'Workflow: build-test-review v2 | step implement #3 | loops qa-fix 2/3, review-fix 0/3, direction 0/2 | running'
check '5: the trace the engine prints is the derived one' "$(o .trace)" "$("$W" trace "$st")"
printf 'Routing: IMPLEMENT #1 | role senior-fullstack | omp | m | high | why: w\nAgent: senior-fullstack\nSkills: none\nWorkflow: build-test-review v2 | step implement #3 | loops qa-fix 2/3, review-fix 0/3, direction 0/2 | running\n' > "$T/trace-ok.txt"
out=$("$W" trace "$st" "$T/trace-ok.txt"); rc=$?
check '5: a captured Workflow line that equals the derived one passes' "$rc" 0
sed 's#qa-fix 2/3#qa-fix 1/3#' "$T/trace-ok.txt" > "$T/trace-bad.txt"
out=$("$W" trace "$st" "$T/trace-bad.txt"); rc=$?
check '5: an invented loop counter fails the check' "$rc" 1
has '5: ... and the check prints the derived line' "$out" 'qa-fix 2/3'
printf 'Routing: REVIEW #1 | role qa | omp | anthropic/claude-sonnet-5-5 | high | why: qa step of a workflow\nAgent: qa\nSkills: verification-before-completion\nWorkflow: build-test-review v2 | step implement #3 | loops qa-fix 2/3, review-fix 0/3, direction 0/2 | running\n' > "$T/trace-qa.txt"
out=$("$FIX_SRC/tests/routing-trace.sh" check "$T/trace-qa.txt" omp anthropic/claude-sonnet-5-5 high 2>&1); rc=$?
check '5: routing-trace check accepts a block that carries a Workflow line (qa routed as REVIEW)' "$rc" 0
check '5: the same block satisfies the Workflow line check' "$("$W" trace "$st" "$T/trace-qa.txt" >/dev/null; echo $?)" 0
printf 'Routing: x\n' > "$T/trace-none.txt"
"$W" trace "$st" "$T/trace-none.txt" >/dev/null; check '5: a trace block with no Workflow line fails the check' "$?" 1
check '5: trace of an escalated workflow' "$("$W" trace "$S/e/workflow.json")" 'Workflow: build-test-review v2 | step step-back #1 | loops qa-fix 3/3, review-fix 0/3, direction 0/2 | escalated'

# --- 6. retro records, the contract examples and the Captain-side documents ---------------------------
RET="$S/c/retro.jsonl"
check '6: the engine appends one retro record per finding next to the state file' "$(jq -rs '[.[] | select(.event == "finding")] | length' "$RET")" 4
check '6: records name task, workflow, step, role and the finding class' "$(jq -rc 'select(.id == "REV-1" and .event == "finding") | [.task, .workflow, .step, .role, .class, .severity]' "$RET")" '["c","build-test-review","review","code-reviewer","swallowed-error","IMPORTANT"]'
check '6: the verifier confirmations are their own event, not new findings' "$(jq -rs '[.[] | select(.event == "confirmed") | .id] | join(",")' "$RET")" 'REV-1'
check '6: the implementer answers are recorded' "$(jq -rc 'select(.event == "answer") | [.id, .disposition, .role]' "$RET")" '["REV-1","fixed","senior-fullstack"]'
check '6: completion is recorded with the rounds' "$(jq -rc 'select(.event == "complete") | .detail.rounds["review-fix"]' "$RET")" 1
check '6: the retro log lives in the task data folder, never in the repository' "$(git -C "$FIX_SRC" status --porcelain | grep -c retro.jsonl)" 0
check '6: gate observations are recorded' "$(jq -rs '[.[] | select(.event == "gate")] | length' "$S/i/retro.jsonl")" 5
check '6: an escalation is recorded for each escalated run' "$(jq -rs '[.[] | select(.event == "escalation")] | length' "$S/g/retro.jsonl")" 4
check '6: a change of direction is recorded each time one is raised' "$(jq -rs '[.[] | select(.event == "change-direction")] | length' "$S/f/retro.jsonl")" 4
check '6: a refuted finding is recorded as dropped, with its reason' "$(jq -rc 'select(.event == "dropped") | [.id, .detail.reason]' "$S/d/retro.jsonl" | tr '\n' ' ')" '["REV-1","style-only"] ["REV-2","not-reproducible"] '
check '6: a malformed verdict is recorded with the class malformed-report' "$(jq -rc 'select(.class == "malformed-report") | .id' "$S/g/retro.jsonl" | head -1)" VERDICT-1
check '6: fm-retro reads what the engine wrote (the self-improvement loop, end to end on the fixture)' "$("$FIX_SRC/bin/fm-retro" report --root "$S" 2>&1 | head -1 | sed 's/[0-9][0-9]* task/N task/; s/[0-9][0-9]* record/N record/; s/[0-9][0-9]* skipped/N skipped/')" 'fm-retro report: N task(s), N record(s), N skipped line(s)'
has '6: ... and reports the verification funnel' "$("$FIX_SRC/bin/fm-retro" report --root "$S" 2>&1)" 'verification:'
has '6: ... and proposes only, never applies' "$("$FIX_SRC/bin/fm-retro" propose --root "$S" --min-cases 1 2>&1 | head -1)" 'PROPOSALS ONLY'
# every role that ends in a machine-read block carries an example the engine accepts
for role in $(jq -r '.roles | to_entries[] | select(.value.outputs | map(. == "verdict" or . == "result" or . == "risk") | any) | .key' "$FIX_SRC/roles/manifest.json"); do
  for kind in $(jq -r --arg r "$role" '.roles[$r].outputs[] | select(. == "verdict" or . == "result" or . == "risk")' "$FIX_SRC/roles/manifest.json"); do
    ex="$T/example-$role-$kind.md"
    { printf 'report body\n\n'; awk -v tag="$kind" '$0 == "```" tag {p = 1} p {print} /^```$/ && p {exit}' "$FIX_SRC/roles/$role/ROLE.md"; } > "$ex"
    out=$("$W" "$kind" "$ex" 2>/dev/null)
    check "the $kind example in roles/$role/ROLE.md parses as a valid $kind block" "$(printf '%s' "$out" | jq -r '.valid')" true
  done
done
POL=$(cat "$POLICY")
has 'policy: section 8 owns workflows' "$POL" '## 8. Workflows'
for w in $ALL; do has "policy: $w is named" "$POL" "\`$w\`"; done
has 'policy: the feedback list goes verbatim to the implementer' "$POL" 'verbatim'
has 'policy: the trace gains a Workflow line' "$POL" 'Workflow: <workflow> v<version> | step <step> #<run> | loops'
has 'policy: the Workflow line is derived from the state file' "$POL" 'bin/fm-workflow trace <state-file>'
has 'policy: the Captain still never merges' "$POL" 'never merges'
has 'policy: every step is a fresh worker' "$POL" 'fresh worker'
has 'policy: the state lives in the task data folder' "$POL" 'data/<task-id>/workflow.json'
has 'README documents the workflows' "$(cat "$FIX_SRC/README.md")" 'bin/fm-workflow'
check 'crew-dispatch.json still never mentions skills' "$(grep -ci skill "$FIX_SRC/firstmate/crew-dispatch.json")" 0

# --- 7. the army check, the call graph, the role manifest and the forcing rule ----------------------
out=$("$W" check 2>&1); rc=$?
check '7: the army check passes on the shipped repository' "$rc" 0
has '7: ... workflows validate' "$out" 'ok   - workflow bug-fix validates'
has '7: ... the call graph has one level' "$out" 'the call graph has one level'
has '7: ... every role is reachable or documented adhoc' "$out" 'every role is reachable from a workflow or documented adhoc'
has '7: ... the selection table resolves' "$out" 'resolves to an existing workflow or a closed exception'
ARMY="$T/army"
fresh_army() { rm -rf "$ARMY"; mkdir -p "$ARMY/firstmate"; cp -R "$FIX_SRC/roles" "$FIX_SRC/workflows" "$ARMY/"; cp "$FIX_SRC/firstmate/fm-roles-lib.sh" "$ARMY/firstmate/"; }
army_fails() { # <label> <needle>
  local out rc
  out=$(FM_CONFIG_ROOT="$ARMY" "$W" check 2>&1); rc=$?
  check "army check $1: exit 1" "$rc" 1
  has "army check $1: says why" "$out" "$2"
}
fresh_army; jq 'del(.roles.scout)' "$ARMY/roles/manifest.json" > "$ARMY/m" && mv "$ARMY/m" "$ARMY/roles/manifest.json"
army_fails 'a role missing from the manifest' 'role scout has a ROLE.md but no entry in roles/manifest.json'
fresh_army; jq '.roles.ghost = .roles.scout' "$ARMY/roles/manifest.json" > "$ARMY/m" && mv "$ARMY/m" "$ARMY/roles/manifest.json"
army_fails 'a manifest role with no ROLE.md' 'lists ghost, which has no roles/ghost/ROLE.md'
fresh_army; jq '.roles.qa.spawns = ["scout"]' "$ARMY/roles/manifest.json" > "$ARMY/m" && mv "$ARMY/m" "$ARMY/roles/manifest.json"
army_fails 'a manifest spawn the frontmatter does not carry' 'role qa: frontmatter spawns [] differ from roles/manifest.json [fm-scout]'
fresh_army; jq '.roles.scout.spawns = ["qa"]' "$ARMY/roles/manifest.json" > "$ARMY/m" && mv "$ARMY/m" "$ARMY/roles/manifest.json"
army_fails 'a role that calls a role that calls others (recursion beyond one level)' 'nothing recurses beyond one level'
fresh_army; jq '.roles.lead.spawns += ["ghost"]' "$ARMY/roles/manifest.json" > "$ARMY/m" && mv "$ARMY/m" "$ARMY/roles/manifest.json"
army_fails 'a call to a role that does not exist' 'calls ghost, which is not a role'
fresh_army; jq '.roles.planner.spawns += ["planner"]' "$ARMY/roles/manifest.json" > "$ARMY/m" && mv "$ARMY/m" "$ARMY/roles/manifest.json"
army_fails 'a role that calls itself' 'calls itself'
fresh_army; sed -i.bak '/^  - task$/d' "$ARMY/roles/lead/ROLE.md"; rm -f "$ARMY/roles/lead/ROLE.md.bak"
army_fails 'a spawning role whose tools lack task' 'role lead: calls sub-agents but its tools lack task'
fresh_army; sed -i.bak 's/^  - bash$/  - bash\n  - task/' "$ARMY/roles/scout/ROLE.md"; rm -f "$ARMY/roles/scout/ROLE.md.bak"
army_fails 'a leaf role whose tools include task' 'role scout: calls no sub-agent, so its tools must not include task'
fresh_army; sed -i.bak 's/^  - bash$/  - bash\n  - edit/' "$ARMY/roles/qa/ROLE.md"; rm -f "$ARMY/roles/qa/ROLE.md.bak"
army_fails 'a read-only role whose tools include edit' 'role qa: mutates none but its tools include edit or write'
fresh_army; jq '.roles.chore |= del(.adhoc)' "$ARMY/roles/manifest.json" > "$ARMY/m" && mv "$ARMY/m" "$ARMY/roles/manifest.json"
army_fails 'a role no workflow reaches and nothing documents as adhoc' 'manifest role chore: no workflow binds it'
fresh_army; jq '.roles.qa.adhoc = "reason"' "$ARMY/roles/manifest.json" > "$ARMY/m" && mv "$ARMY/m" "$ARMY/roles/manifest.json"
army_fails 'a role marked adhoc that a workflow binds' 'manifest role qa: marked adhoc'
fresh_army; jq '.roles.qa.outputs = ["report"]' "$ARMY/roles/manifest.json" > "$ARMY/m" && mv "$ARMY/m" "$ARMY/roles/manifest.json"
army_fails 'a bound role whose manifest outputs cannot produce its step output' 'cannot produce output "verdict"'
fresh_army; rm "$ARMY/roles/manifest.json"
army_fails 'no manifest at all' 'roles/manifest.json is missing'
fresh_army; jq '.kinds.feature.workflow = "ghost-flow"' "$ARMY/workflows/selection.json" > "$ARMY/m" && mv "$ARMY/m" "$ARMY/workflows/selection.json"
army_fails 'a kind pointing at a workflow that does not exist' 'kind feature: workflow ghost-flow does not exist'
fresh_army; jq 'del(.kinds.feature.workflow)' "$ARMY/workflows/selection.json" > "$ARMY/m" && mv "$ARMY/m" "$ARMY/workflows/selection.json"
army_fails 'a code-changing, non-trivial kind with no workflow' 'kind feature'
fresh_army; jq '.exceptions["vibes"] = "x"' "$ARMY/workflows/selection.json" > "$ARMY/m" && mv "$ARMY/m" "$ARMY/workflows/selection.json"
army_fails 'an exception added to the closed list' 'the exceptions list is closed'
fresh_army; jq 'del(.kinds.bugfix)' "$ARMY/workflows/selection.json" > "$ARMY/m" && mv "$ARMY/m" "$ARMY/workflows/selection.json"
army_fails 'a workflow that no kind selects' 'workflow bug-fix is selected by no kind'
# the forcing rule: every non-trivial code-changing kind of task resolves to a workflow, under every delivery mode
SEL="$WF/selection.json"
for kind in $(jq -r '.kinds | to_entries[] | select(.value.changesCode == true and (.value.exception | not)) | .key' "$SEL"); do
  for mode in direct-pr local-only no-mistakes; do
    out=$("$W" select "$kind" --delivery "$mode" 2>&1); rc=$?
    check "7: select $kind --delivery $mode exits 0" "$rc" 0
    case $(printf '%s\n' "$out" | head -1) in
      "workflow: "*) ok "7: select $kind --delivery $mode resolves to a workflow: $(printf '%s\n' "$out" | head -1)" ;;
      *) bad "7: select $kind --delivery $mode resolves to no workflow: $out" ;;
    esac
    wfn=$(printf '%s\n' "$out" | head -1 | sed 's/^workflow: //')
    [ -f "$WF/$wfn.json" ] && ok "7: ... and $wfn exists" || bad "7: ... but $wfn does not exist"
  done
  check "7: no-mistakes selects delegated-build for $kind (no second reviewer on top of it)" "$("$W" select "$kind" --delivery no-mistakes | head -1)" 'workflow: delegated-build'
done
check '7: a feature resolves to build-test-review' "$("$W" select feature --delivery direct-pr | head -1)" 'workflow: build-test-review'
check '7: an unclear feature resolves to plan-build-test-review' "$("$W" select feature-unclear --delivery direct-pr | head -1)" 'workflow: plan-build-test-review'
check '7: a bugfix resolves to bug-fix' "$("$W" select bugfix --delivery local-only | head -1)" 'workflow: bug-fix'
check '7: a refactor resolves to refactor' "$("$W" select refactor --delivery direct-pr | head -1)" 'workflow: refactor'
check '7: a UI change resolves to ui-build-verify-review' "$("$W" select ui --delivery direct-pr | head -1)" 'workflow: ui-build-verify-review'
check '7: a decision resolves to research-decide' "$("$W" select decision | head -1)" 'workflow: research-decide'
check '7: a trivial chore is the first exception' "$("$W" select trivial | head -1 | cut -d' ' -f1-2)" 'none: trivial-chore'
check '7: a pure question is the second exception' "$("$W" select question | head -1 | cut -d' ' -f1-2)" 'none: question-or-diagnosis'
check '7: an explicit captain choice of none is the third exception, and states the choice' "$("$W" select feature --none 'captain chose no workflow' | head -1)" 'none: captain-none - captain chose no workflow'
out=$("$W" select feature 2>&1); rc=$?
check '7: a kind whose workflow depends on the delivery path is refused without --delivery (no silent second reviewer on a no-mistakes task)' "$rc" 2
has '7: ... telling the captain to pass it' "$out" 'pass --delivery'
check '7: a documentation-only task is outside the rule, not an exception' "$("$W" select docs | head -1 | cut -d' ' -f1-2)" 'none: out-of-scope'
out=$("$W" select nonsense --none x 2>&1); rc=$?
check '7: --none still validates the kind' "$rc" 2
check '7: the one kind outside the rule is docs' "$(jq -r '.kinds | to_entries[] | select(.value.outOfScope) | .key' "$SEL")" docs
check '7: the exceptions are exactly the closed list' "$(jq -r '.exceptions | keys | join(",")' "$SEL")" 'captain-none,question-or-diagnosis,trivial-chore'
out=$("$W" select nonsense 2>&1); rc=$?
check '7: an unknown kind is refused (not silently no workflow)' "$rc" 2
has '7: ... listing the kinds' "$out" 'kinds:'
out=$("$W" select feature --delivery vibes 2>&1); rc=$?
check '7: an unknown delivery mode is refused' "$rc" 2
has '7: the table prints every kind' "$("$W" select)" 'feature-unclear: workflow plan-build-test-review'
for exc in trivial-chore question-or-diagnosis captain-none; do has "policy section 8 names the exception $exc" "$POL" "\`$exc\`"; done
has 'policy section 8 states the forcing rule' "$POL" 'MUST run a workflow'
has 'policy section 8 resolves the workflow with bin/fm-workflow select' "$POL" 'bin/fm-workflow select'
has 'policy section 8 composes the forced workflow with no-mistakes without a second reviewer' "$POL" 'delegated-build'

finish
