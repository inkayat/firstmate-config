#!/usr/bin/env bash
# evals.sh - offline eval of the army against past failure patterns. A role or workflow
# change is scored here before it lands; nothing calls a model, the network or a real home.
#
#   1. the failure patterns (tests/evals/patterns.json): every pattern is still protected by the
#      roles and workflows as they are; the score is printed for the fixed test set and the tuning
#      set apart
#   2. mutations: a change that loses a pattern's protection fails the eval and names the pattern
#   3. replay (tests/evals/cases, outputs): recorded finder outputs scored against known-incident
#      fixtures - recall of raw findings, post-verification and the final review apart, tuning and
#      test sets never pooled, clean controls counted for false positives - against the recorded
#      baseline (a ratchet: it moves only by editing tests/evals/baseline.txt in a PR)
#   4. the self-improvement loop end to end on a fixture: two scripted workflow runs that hit the
#      same finding class are recorded by the engine, aggregated and turned into a PROPOSAL, and
#      nothing in the repository changes
# shellcheck source=tests/fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixture.sh"

R="$FIX_SRC/bin/fm-retro"
W="$FIX_SRC/bin/fm-workflow"
EV="$FIX_SRC/tests/evals"
export FM_CONFIG_ROOT="$FIX_SRC" FM_SKILLS_ROOT="$T/skills-root"

# --- 1. the failure patterns ---------------------------------------------------------------
out=$("$R" eval patterns 2>&1); rc=$?
check '1: every recorded failure pattern is still protected by the roles and workflows' "$rc" 0
nt=$(jq '[.patterns[] | select(.set == "test")] | length' "$EV/patterns.json")
nu=$(jq '[.patterns[] | select(.set == "tuning")] | length' "$EV/patterns.json")
has '1: the score is printed for the fixed test set and the tuning set apart' "$out" "score: test $nt/$nt, tuning $nu/$nu"
check '1: every pattern names its source and a description' "$(jq '[.patterns[] | select((.source | length) == 0 or (.pattern | length) == 0)] | length' "$EV/patterns.json")" 0
check '1: pattern ids are unique' "$(jq '[.patterns[].id] | length == (unique | length)' "$EV/patterns.json")" true
check '1: the fixed test set is larger than the tuning set (the tuning set stays small)' "$([ "$nt" -gt "$nu" ] && echo yes || echo no)" yes
check '1: patterns cover the article rules: convergence, delta-only, verified findings, commit binding, base-branch gates, human approval, change-direction, evidence, observe mode' \
  "$(jq -r '[.patterns[].source] | map(select(test("fifty review rounds|59%|verified by other agents|out-of-date commit|check that judges it|human one|change direction|show the output|observe mode"))) | length' "$EV/patterns.json")" 9

# --- 2. mutations: losing a protection fails the eval -------------------------------------------
CFG="$T/cfg"
fresh_cfg() { rm -rf "$CFG"; mkdir -p "$CFG"; cp -R "$FIX_SRC/roles" "$FIX_SRC/workflows" "$CFG/"; mkdir -p "$CFG/tests"; cp -R "$EV" "$CFG/tests/evals"; }
mutant() { # <label> <pattern-id> <workflow-file-or-"-"> <jq-edit>   (a workflow mutation)
  fresh_cfg
  jq "$4" "$CFG/workflows/$3.json" > "$CFG/w" && mv "$CFG/w" "$CFG/workflows/$3.json"
  out=$("$R" eval patterns --config-root "$CFG" 2>&1); rc=$?
  check "2: a change that $1 fails the eval" "$rc" 1
  has "2: ... and names pattern $2" "$out" "FAIL - $2"
}
mutant 'lets an unverified review finding go straight back to the implementer' P-003 build-test-review '.steps.review.on.fail = "implement"'
mutant 'raises the review round cap to 5' P-001 build-test-review '.loops["review-fix"].maxIterations = 5'
mutant 'sends an exhausted loop to the captain with no step-back' P-001 build-test-review '.loops["qa-fix"].onExhausted = "escalate"'
mutant 'drops the early change-direction outcome from QA' P-008 build-test-review 'del(.steps.qa.on["change-direction"])'
mutant 'ships a gate in enforce mode' P-018 build-test-review '.gates.commit = "enforce"'
mutant 'ships a gate in enforce mode in bug-fix' P-018 bug-fix '.gates.commit = "enforce"'
mutant 'ships a gate in enforce mode in ui-build-verify-review' P-018 ui-build-verify-review '.gates.evidence = "enforce"'
mutant 'deletes every gate of the delegated build (a vacuous gate check must not pass)' P-013 delegated-build 'del(.gates)'
mutant 'lets a reviewer in on top of no-mistakes' P-013 delegated-build '.roles.reviewer = "code-reviewer"'
mutant 'lets the fixer also write the regression test' P-010 bug-fix '.roles.tester = "senior-fullstack"'
mutant 'removes the security gate from the review route' P-007 build-test-review '.steps.review.on.pass = "ship"'
mutant 'removes the delta from the re-review' P-002 build-test-review '.steps.review.input |= map(select(.from != "delta"))'
mutant 'removes the browser verification before review' P-012 ui-build-verify-review '.steps.qa.on.pass = "review"'
fresh_cfg; sed -i.bak '/BASE/d' "$CFG/roles/qa/ROLE.md"; rm -f "$CFG/roles/qa/ROLE.md.bak"
out=$("$R" eval patterns --config-root "$CFG" 2>&1); rc=$?
check '2: a role body that stops reading its rules from the base branch fails the eval' "$rc" 1
has '2: ... and names pattern P-005' "$out" 'FAIL - P-005'
fresh_cfg; sed -i.bak 's/^  - bash$/  - bash\n  - task/' "$CFG/roles/scout/ROLE.md"; rm -f "$CFG/roles/scout/ROLE.md.bak"
out=$("$R" eval patterns --config-root "$CFG" 2>&1); rc=$?
check '2: a leaf role that gains the task tool fails the eval' "$rc" 1
has '2: ... and names pattern P-014' "$out" 'FAIL - P-014'
fresh_cfg; sed -i.bak 's/^  - bash$/  - bash\n  - edit/' "$CFG/roles/improver/ROLE.md"; rm -f "$CFG/roles/improver/ROLE.md.bak"
out=$("$R" eval patterns --config-root "$CFG" 2>&1); rc=$?
check '2: an improver that gains the edit tool fails the eval' "$rc" 1
has '2: ... and names pattern P-017' "$out" 'FAIL - P-017'
fresh_cfg; sed -i.bak 's/^  - bash$/  - bash\n  - write/' "$CFG/roles/improver/ROLE.md"; rm -f "$CFG/roles/improver/ROLE.md.bak"
out=$("$R" eval patterns --config-root "$CFG" 2>&1); rc=$?
check '2: an improver that gains the write tool fails the eval too' "$rc" 1
has '2: ... and names pattern P-017' "$out" 'FAIL - P-017'
# every role-body check can fail: delete the lines its regex matches and its pattern must fail
role_checks=$(jq -r '.patterns[] | .id as $id | .checks[] | select(.kind == "role") | [$id, .role, .regex] | @tsv' "$EV/patterns.json")
while IFS="$(printf '\t')" read -r pid prole pre; do
  fresh_cfg
  grep -vE -- "$pre" "$CFG/roles/$prole/ROLE.md" > "$CFG/r" ; mv "$CFG/r" "$CFG/roles/$prole/ROLE.md"
  out=$("$R" eval patterns --config-root "$CFG" 2>&1)
  has "2: deleting what $pid checks in roles/$prole fails the eval" "$out" "FAIL - $pid"
done <<EOF
$role_checks
EOF
fresh_cfg
out=$("$R" eval patterns --config-root "$CFG" 2>&1); rc=$?
check '2: the unchanged copy still passes (the mutants fail because of their change)' "$rc" 0

# --- 3. replay against the recorded baseline -------------------------------------------------------
out=$("$R" eval replay "$EV/cases" "$EV/outputs" --min-final-recall 0.3 --max-control-fp 0 2>&1); rc=$?
check '3: replay passes its thresholds on the shipped fixtures' "$rc" 0
check '3: the replay result equals the recorded baseline (a ratchet: edit baseline.txt in a PR to move it)' "$out" "$(cat "$EV/baseline.txt")"
has '3: tuning and test recall are scored apart' "$out" 'tuning: recall'
has '3: ... the test set apart' "$out" 'test: recall'
has '3: a bug lost between raw and verified is flagged' "$out" 'LOST: verdict-no-commit-binding between raw and verified'
has '3: a bug lost between verified and final is flagged' "$out" 'LOST: loop-without-limit between verified and final'
has '3: clean controls are counted for false positives' "$out" 'control findings raw 1, verified 0, final 0'
out=$("$R" eval replay "$EV/cases" "$EV/outputs" --min-final-recall 0.9 2>&1); rc=$?
check '3: a final-recall threshold the fixtures do not meet exits 1' "$rc" 1
check '3: the tuning set and the fixed test set share no case' "$(for f in "$EV"/cases/*/case.json; do jq -r '[.set, .id] | @tsv' "$f"; done | awk -F'\t' '$1 != "control" {print $2}' | sort | uniq -d | wc -l | tr -d ' ')" 0
check '3: there are clean controls (merged-stable changes) against over-flagging' "$(for f in "$EV"/cases/*/case.json; do jq -r '.set' "$f"; done | grep -c control)" 2
check '3: every case has a recorded output' "$(for f in "$EV"/cases/*/case.json; do id=$(jq -r .id "$f"); [ -f "$EV/outputs/$id.json" ] || echo "$id"; done | wc -l | tr -d ' ')" 0

# --- 4. the loop end to end on a fixture -------------------------------------------------------------
export FM_HOME="$T/fmhome"; D="$FM_HOME/data"; mkdir -p "$D/task-one" "$D/task-two"
BTR=build-test-review
run_task() { # <task> <class>: implement, classify, QA fails with the class, fix, ... complete
  local task=$1 cls=$2 st="$D/$1/workflow.json" f n=0
  rep() { n=$((n + 1)); f="$T/ev-$task-$n.md"; printf '%s' "$1" > "$f"; "$W" next $BTR "$st" --report "$f" >/dev/null || return 1; }
  "$W" next $BTR "$st" --task "demo $task" >/dev/null
  rep $'```result\n{"status":"done","base":"aaaaaaa","commit":"bbbbbbb","evidence":[{"command":"bash t.sh","observed":"PASS"}]}\n```\n'
  rep $'```risk\n{"tier":"medium","security":"not-required","commit":"bbbbbbb","reasons":["x"]}\n```\n'
  rep "\`\`\`verdict
{\"verdict\":\"FAIL\",\"commit\":\"bbbbbbb\",\"feedback\":[{\"id\":\"QA-1\",\"severity\":\"BLOCKER\",\"class\":\"$cls\",\"what\":\"the retry hides the timeout\",\"where\":\"src/app.py:12\",\"layer\":\"author\"}]}
\`\`\`
"
}
run_task task-one swallowed-error
run_task task-two swallowed-error
before=$(git -C "$FIX_SRC" status --porcelain | wc -l | tr -d ' ')
rep_out=$("$R" report --root "$D" 2>&1)
has '4: the report aggregates both tasks' "$rep_out" 'fm-retro report: 2 task(s)'
has '4: ... shows the recurring class (two distinct tasks) per role' "$rep_out" 'swallowed-error'
has '4: ... and which layer should have caught it' "$rep_out" 'author'
prop=$("$R" propose --root "$D" 2>&1)
has '4: propose states that it only proposes' "$prop" 'PROPOSALS ONLY'
has '4: ... names the recurring class with its two tasks as evidence' "$prop" 'swallowed-error'
has '4: ... points at the artifact to change for that layer' "$prop" 'senior-fullstack'
has '4: ... requires three skeptics to try to disprove it' "$prop" 'fm-tenth-man'
has '4: ... starts the rule in observe mode' "$prop" 'observe mode first'
has '4: ... and needs a human in a PR' "$prop" 'human'
check '4: nothing in the repository changed (proposals are never applied)' "$(git -C "$FIX_SRC" status --porcelain | wc -l | tr -d ' ')" "$before"
check '4: a class seen in only one task is not proposed' "$(FM_HOME="$T/fmhome" "$R" propose --root "$D" --min-cases 3 2>&1 | grep -c 'no proposals')" 1

finish
