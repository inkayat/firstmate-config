#!/usr/bin/env bash
# retro.sh - offline automation for bin/fm-retro: the append-only retro log, the
# report and proposal readers, and the two evals (patterns, replay). No model,
# network, real home or repository is touched; everything lives under $T.
# shellcheck source=tests/fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixture.sh"

R="$FIX_SRC/bin/fm-retro"
export FM_HOME="$T/fm"
D="$FM_HOME/data"
CASES="$FIX_SRC/tests/evals/cases"
OUTS="$FIX_SRC/tests/evals/outputs"

run() { OUT=$("$@" 2>&1); RC=$?; }

# --- 1. record -----------------------------------------------------------------
run "$R" record --event finding --task t-rec --workflow build-test-review --version 1 --step review --run 2 \
  --role code-reviewer --severity BLOCKER --class stale-verdict --id REV-1 --what 'a "quoted" what' \
  --where 'bin/x:1' --layer qa --disposition open --commit abc123 --detail '{"k":1}'
check 'record exits 0' "$RC" 0
check 'record prints the path written' "$OUT" "$D/t-rec/retro.jsonl"
check 'record created exactly one line' "$(wc -l < "$D/t-rec/retro.jsonl" | tr -d ' ')" 1
check 'the line is a compact JSON object with integer ts' \
  "$(jq -sr 'length == 1 and (.[0] | type == "object" and (.ts | type == "number" and . == floor))' "$D/t-rec/retro.jsonl")" true
check 'record keeps fields and quoting' "$(jq -r '[.task, .event, .severity, .id, .what, .version, .run, .detail.k] | join("|")' "$D/t-rec/retro.jsonl")" \
  't-rec|finding|BLOCKER|REV-1|a "quoted" what|1|2|1'
check 'empty options are omitted' "$(jq -r 'has("outcome") or has("rootCause")' "$D/t-rec/retro.jsonl")" false
run "$R" record --event answer --task t-rec --id REV-1 --disposition fixed
check 'a second record appends' "$(wc -l < "$D/t-rec/retro.jsonl" | tr -d ' ')" 2
run "$R" record --event manual --what 'seen later'
check 'no task goes to the misc log' "$OUT" "$D/retro/misc.jsonl"
run "$R" record --event revert --task - --commit deadbee --class stale-verdict --layer qa
check 'task "-" goes to the misc log' "$(wc -l < "$D/retro/misc.jsonl" | tr -d ' ')" 2

run "$R" record --task t-rec
check 'event is required' "$RC" 1
has 'event is required (message)' "$OUT" '--event is required'
run "$R" record --event nonsense --task t-rec
check 'unknown event is refused' "$RC" 1
run "$R" record --event finding --task t-rec --severity HUGE
check 'bad severity is refused' "$RC" 1
run "$R" record --event finding --task t-rec --layer nowhere
check 'bad layer is refused' "$RC" 1
run "$R" record --event answer --task t-rec --disposition maybe
check 'bad disposition is refused' "$RC" 1
run "$R" record --event gate --task t-rec --detail '[1]'
check 'a non-object detail is refused' "$RC" 1
run "$R" record --event gate --task t-rec --detail 'not json'
check 'an invalid detail is refused' "$RC" 1
run "$R" record --event gate --task a/b
check 'a task id with a slash is refused' "$RC" 1
run "$R" record --event gate --task .hidden
check 'a task id with a leading dot is refused' "$RC" 1
check 'refused records wrote nothing' "$(wc -l < "$D/t-rec/retro.jsonl" | tr -d ' ')" 2
[ ! -e "$D/a" ] && [ ! -e "$D/.hidden" ] && ok 'refused task ids created no folder' || bad 'refused task ids created a folder'

# git: refuse a tracked location, accept an ignored one
REPO="$T/repo"
mkdir -p "$REPO" && git -C "$REPO" init -q
FM_HOME="$REPO/fmh" run "$R" record --event manual --task t-git
check 'a log inside a git work tree is refused' "$RC" 1
has 'git refusal names the rule' "$OUT" 'outside a repository'
[ ! -e "$REPO/fmh" ] && ok 'a refused record leaves no directory behind' || bad 'a refused record created a directory'
printf 'fmh/\n' > "$REPO/.gitignore"
FM_HOME="$REPO/fmh" run "$R" record --event manual --task t-git
check 'a git-ignored log inside a work tree is accepted' "$RC" 0
check 'the ignored log was written' "$(wc -l < "$REPO/fmh/data/t-git/retro.jsonl" | tr -d ' ')" 1

# --- 2. report on a hand-built multi-task log -------------------------------------
H="$T/hand"
mkdir -p "$H/t1" "$H/t2" "$H/t3" "$H/t4"
cat > "$H/t1/retro.jsonl" <<'EOF'
{"ts":100,"task":"t1","workflow":"build-test-review","version":1,"event":"finding","step":"review","role":"code-reviewer","severity":"BLOCKER","class":"stale-verdict","id":"REV-1","layer":"qa","caughtBy":"code-reviewer","disposition":"open"}
{"ts":101,"task":"t1","event":"finding","step":"review","role":"code-reviewer","severity":"IMPORTANT","class":"missing-test","id":"REV-2","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":102,"task":"t1","event":"dropped","id":"REV-2","detail":{"reason":"not reproducible"}}
{"ts":103,"task":"t1","event":"answer","id":"REV-1","disposition":"rejected","detail":{"reason":"works as designed"}}
{"ts":104,"task":"t1","event":"gate","detail":{"gate":"g1","mode":"observe","status":"would-block"}}
{"ts":105,"task":"t1","event":"gate","detail":{"gate":"g2","mode":"observe","status":"would-block"}}
{"ts":106,"task":"t1","event":"complete","detail":{"rounds":{"qa":2,"review":1},"runs":{"build":3}}}
EOF
cat > "$H/t2/retro.jsonl" <<'EOF'
{"ts":200,"task":"t2","workflow":"build-test-review","version":1,"event":"finding","step":"review","role":"code-reviewer","severity":"IMPORTANT","class":"stale-verdict","id":"REV-1","layer":"qa","caughtBy":"code-reviewer","disposition":"open"}
{"ts":201,"task":"t2","event":"answer","id":"REV-1","disposition":"rejected","detail":{"reason":"disagree"}}
{"ts":202,"task":"t2","event":"finding","step":"review","role":"code-reviewer","severity":"IMPORTANT","class":"stale-verdict","id":"REV-1","layer":"qa","caughtBy":"code-reviewer","disposition":"open"}
{"ts":203,"task":"t2","event":"gate","detail":{"gate":"g1","mode":"enforce","status":"blocked"}}
{"ts":204,"task":"t2","event":"gate","detail":{"gate":"g1","mode":"enforce","status":"escaped"}}
{"ts":205,"task":"t2","event":"gate","detail":{"gate":"g2","mode":"observe","status":"would-block"}}
{"ts":206,"task":"t2","event":"complete","detail":{"rounds":{"qa":1}}}
EOF
cat > "$H/t3/retro.jsonl" <<'EOF'
{"ts":300,"task":"t3","workflow":"plan-build-test-review","version":2,"event":"finding","role":"planner","severity":"OPTIONAL","class":"naming","id":"N-1"}
{"ts":301,"task":"t3","event":"gate","detail":{"gate":"g2","mode":"observe","status":"would-block"}}
{"ts":302,"task":"t3","event":"change-direction","detail":{"text":"use another approach"}}
{"ts":303,"task":"t3","event":"escalation","detail":{"reason":"loop exhausted","loop":"qa"}}
EOF
cat > "$H/t4/retro.jsonl" <<'EOF'
{"ts":400,"task":"t4","workflow":"plan-build-test-review","version":2,"event":"closed"}
this line is not json
[1,2,3]
EOF
run "$R" report --root "$H"
check 'report exits 0' "$RC" 0
has 'report header counts tasks, records, skipped lines' "$OUT" 'fm-retro report: 4 task(s), 19 record(s), 2 skipped line(s)'
has 'rounds-to-pass mean and max' "$OUT" 'build-test-review: tasks 2, complete 2, escalated 0, closed 0, rounds-to-pass mean 2 max 3'
has 'a workflow without complete events has n/a rounds' "$OUT" 'plan-build-test-review: tasks 2, complete 0, escalated 1, closed 1, rounds-to-pass n/a'
has 'escalation rate' "$OUT" 'escalation rate: 1/4 (25%)'
has 'change-direction rate' "$OUT" 'change-direction rate: 1/4 (25%)'
has 'noise honors the re-raise rule' "$OUT" 'noise: 2/4 (50%)'
has 'verification line without confirmed events' "$OUT" 'verification: n/a confirmed, 1 dropped of 4 raised (BLOCKER|IMPORTANT findings)'
has 'round caps line' "$OUT" 'round caps: 0'
has 'disputed counts every rejected answer' "$OUT" 'disputed (rejected answers): 2/4'
has 'gate stats: mixed gate' "$OUT" 'g1: would-block 1, blocked 1, escaped 1'
has 'gate stats: observe-only gate' "$OUT" 'g2: would-block 3, blocked 0, escaped 0'
has 'a class in 2 tasks is recurring' "$OUT" 'stale-verdict (code-reviewer): 2 tasks, 3 findings, layers qa=3'
lacks 'a class in 1 task is not listed as recurring' "$OUT" 'missing-test ('
has 'dropped and OPTIONAL classes are not counted as one-off' "$OUT" 'one-off classes: 0'
has 'layer histogram counts real findings only' "$OUT" 'layers (should have been caught by): qa=3'
has 'severity counts' "$OUT" 'BLOCKER=1, IMPORTANT=3, OPTIONAL=1, PRE-EXISTING=0'
run "$R" report --root "$H" --workflow plan-build-test-review
has 'report --workflow filters' "$OUT" 'fm-retro report: 2 task(s), 5 record(s), 2 skipped line(s)'
run "$R" report --root "$H" --since 250
has 'report --since filters by ts' "$OUT" '2 task(s)'
mkdir -p "$T/emptyroot"
run "$R" report --root "$T/emptyroot"
check 'an empty root reports zeros' "$RC" 0
has 'empty root header' "$OUT" 'fm-retro report: 0 task(s), 0 record(s), 0 skipped line(s)'
has 'empty root says so' "$OUT" 'no records yet'

# --- 3. propose ----------------------------------------------------------------
before=$(find "$T" | sort)
run "$R" propose --root "$H"
after=$(find "$T" | sort)
check 'propose exits 0' "$RC" 0
check 'propose first line is the banner' "$(printf '%s\n' "$OUT" | head -1)" \
  'PROPOSALS ONLY - nothing here is applied; each needs a worker PR and a human approval'
has 'a class in 2 tasks is proposed' "$OUT" '[PROP-1] class stale-verdict'
has 'proposal evidence names tasks' "$OUT" 't1, t2'
lacks 'a one-task class is not proposed' "$OUT" 'class missing-test'
lacks 'an OPTIONAL class is not proposed' "$OUT" 'class naming'
has 'layer maps to its artifact' "$OUT" 'layer qa: roles/qa/ROLE.md'
has 'proposal carries the disprove step' "$OUT" '2 of 3 refuting drops it'
has 'proposal carries the rollout rule' "$OUT" 'observe mode first'
has 'a gate with >=3 would-block and no blocks is a promotion candidate' "$OUT" 'gate-promotion candidate: g2'
lacks 'a gate that blocked is not a promotion candidate' "$OUT" 'gate-promotion candidate: g1'
has 'prune line is printed' "$OUT" 'prune: list rules with zero hits'
check 'propose wrote no file' "$after" "$before"
run "$R" propose --root "$H" --min-cases 3
has '--min-cases 3 proposes nothing here' "$OUT" 'no proposals: no class recurs in >= 3 distinct tasks yet'
lacks '--min-cases 3 has no class block' "$OUT" '[PROP-1]'
run "$R" propose --root "$H" --min-cases 1
lacks '--min-cases 1 still ignores an OPTIONAL class' "$OUT" 'class naming'
run "$R" propose --root "$T/emptyroot"
has 'propose on an empty root says no proposals' "$OUT" 'no proposals'

# --- 3b. confirmed, round-cap and the format gate -------------------------------------
V="$T/ver"
mkdir -p "$V/v1" "$V/v2"
cat > "$V/v1/retro.jsonl" <<'EOF'
{"ts":10,"task":"v1","workflow":"build-test-review","event":"finding","role":"qa","severity":"BLOCKER","class":"malformed-report","id":"VERDICT-1","layer":"qa"}
{"ts":11,"task":"v1","event":"finding","role":"code-reviewer","severity":"IMPORTANT","class":"missing-test","id":"REV-1","layer":"review"}
{"ts":12,"task":"v1","event":"finding","role":"code-reviewer","severity":"OPTIONAL","class":"naming","id":"REV-2"}
{"ts":13,"task":"v1","event":"confirmed","role":"finding-verifier","severity":"IMPORTANT","class":"missing-test","id":"REV-1","disposition":"open"}
{"ts":14,"task":"v1","event":"dropped","id":"VERDICT-1","detail":{"reason":"not a defect"}}
{"ts":15,"task":"v1","event":"gate","detail":{"gate":"format","mode":"enforce","status":"blocked"}}
{"ts":16,"task":"v1","event":"round-cap","detail":{"loop":"review-fix","max":2,"to":"build"}}
EOF
cat > "$V/v2/retro.jsonl" <<'EOF'
{"ts":20,"task":"v2","workflow":"build-test-review","event":"finding","role":"code-reviewer","severity":"IMPORTANT","class":"missing-test","id":"REV-1","layer":"review"}
{"ts":21,"task":"v2","event":"confirmed","role":"finding-verifier","severity":"IMPORTANT","class":"missing-test","id":"REV-1","disposition":"open"}
{"ts":22,"task":"v2","event":"gate","detail":{"gate":"format","mode":"enforce","status":"blocked"}}
{"ts":23,"task":"v2","event":"round-cap","detail":{"loop":"review-fix","max":2,"to":"build"}}
{"ts":24,"task":"v2","event":"escalation","detail":{"reason":"x","loop":"qa"}}
EOF
run "$R" report --root "$V"
has 'confirmed is counted on its own line' "$OUT" 'verification: 2 confirmed, 1 dropped of 3 raised (BLOCKER|IMPORTANT findings)'
has 'round caps are counted' "$OUT" 'round caps: 2'
has 'noise denominator ignores confirmed' "$OUT" 'noise: 1/3 (33%)'
has 'the format gate counts like any gate' "$OUT" 'format: would-block 0, blocked 2, escaped 0'
has 'confirmed is not a raw finding in severity counts' "$OUT" 'BLOCKER=1, IMPORTANT=2, OPTIONAL=1, PRE-EXISTING=0'
has 'a dropped finding does not make its class recurring or one-off' "$OUT" 'one-off classes: 0'
has 'confirmed does not make a class recurring' "$OUT" 'missing-test (code-reviewer): 2 tasks, 2 findings'

# --- 3c. misc log and reverts, real-findings filter, odd rounds, id-less answers ------------
M="$T/misc"; mkdir -p "$M/m1" "$M/retro"
cat > "$M/m1/retro.jsonl" <<'EOF'
{"ts":1,"task":"m1","workflow":"build-test-review","event":"finding","severity":"IMPORTANT","class":"stale-verdict","id":"REV-1","layer":"qa","caughtBy":"code-reviewer"}
EOF
cat > "$M/retro/misc.jsonl" <<'EOF'
{"ts":2,"event":"revert","class":"stale-verdict","layer":"qa","commit":"aaa111","what":"reverted after a later fix"}
{"ts":3,"event":"revert","class":"lost-update","layer":"review","commit":"bbb222"}
{"ts":4,"event":"revert","class":"lost-update","layer":"review","commit":"ccc333"}
{"ts":5,"event":"manual","what":"seen in prod"}
EOF
run "$R" report --root "$M"
has 'misc records count as records but not as tasks' "$OUT" 'fm-retro report: 1 task(s), 5 record(s), 0 skipped line(s)'
has 'reverts are counted' "$OUT" 'reverts: 3'
has 'manual records are counted' "$OUT" 'manual records: 1'
has 'two reverts of a class are a recurring class' "$OUT" 'lost-update (unknown): 2 tasks, 2 findings, layers review=2'
run "$R" propose --root "$M"
has 'a class in a task plus a revert is proposed' "$OUT" 'class stale-verdict'
has 'evidence lists the revert record' "$OUT" 'revert-aaa111/-'
has 'evidence lists the finding too' "$OUT" 'm1/REV-1'
has 'a class in two reverts is proposed' "$OUT" 'class lost-update'
has 'evidence lists both reverts' "$OUT" 'revert-bbb222, revert-ccc333'
run "$R" report --root "$D"
has 'report reads the misc log written by record' "$OUT" 'reverts: 1'

B="$T/real"; mkdir -p "$B/b1" "$B/b2"
for t in b1 b2; do
  cat > "$B/$t/retro.jsonl" <<EOF
{"ts":1,"task":"$t","workflow":"build-test-review","event":"finding","severity":"IMPORTANT","class":"dropped-class","id":"D-1","layer":"review"}
{"ts":2,"task":"$t","event":"finding","severity":"PRE-EXISTING","class":"pre-class","id":"P-1","layer":"author"}
{"ts":3,"task":"$t","event":"finding","severity":"IMPORTANT","class":"real-class","id":"R-1","layer":"review"}
{"ts":4,"task":"$t","event":"dropped","id":"D-1","detail":{"reason":"not real"}}
EOF
done
run "$R" report --root "$B"
has 'only real findings make a class recurring' "$OUT" 'real-class (unknown): 2 tasks, 2 findings, layers review=2'
lacks 'a dropped class is not recurring' "$OUT" 'dropped-class ('
lacks 'a PRE-EXISTING class is not recurring' "$OUT" 'pre-class ('
has 'dropped and PRE-EXISTING classes are not even one-off' "$OUT" 'one-off classes: 0'
has 'the layer histogram uses real findings only' "$OUT" 'layers (should have been caught by): review=2'
has 'severity counts stay raw' "$OUT" 'BLOCKER=0, IMPORTANT=4, OPTIONAL=0, PRE-EXISTING=2'
run "$R" propose --root "$B"
has 'a real class in 2 tasks is proposed' "$OUT" 'class real-class'
lacks 'a class dropped in 2 tasks is not proposed' "$OUT" 'class dropped-class'
lacks 'a PRE-EXISTING class in 2 tasks is not proposed' "$OUT" 'class pre-class'

O="$T/odd"; mkdir -p "$O/o1"
cat > "$O/o1/retro.jsonl" <<'EOF'
{"ts":1,"task":"o1","workflow":"w","event":"complete","detail":{"rounds":3}}
{"ts":2,"task":"o1","event":"complete","detail":{"rounds":"x"}}
{"ts":3,"task":"o1","event":"complete","detail":{"rounds":null}}
{"ts":4,"task":"o1","event":"complete","detail":{"rounds":{"a":1,"b":{"c":5},"d":2}}}
{"ts":5,"task":"o1","event":"gate","detail":"oops"}
{"ts":6,"task":"o1","event":"round-cap","detail":7}
{"ts":7,"task":"o1","event":"answer","disposition":"rejected"}
{"ts":8,"task":"o1","event":"finding","severity":"IMPORTANT","class":"c1","layer":"qa"}
{"ts":9,"task":"o1","event":"finding","severity":"IMPORTANT","id":"X-1"}
EOF
run "$R" report --root "$O"
check 'odd detail shapes do not crash report' "$RC" 0
has 'odd rounds are summed or counted as 0' "$OUT" 'w: tasks 1, complete 1, escalated 0, closed 0, rounds-to-pass mean 1.5 max 3'
has 'an id-less rejected answer is never re-raised by an id-less finding' "$OUT" 'noise: 1/2 (50%)'
has 'findings without a class are visible' "$OUT" 'findings without class: 1'
run "$R" propose --root "$O"
check 'odd detail shapes do not crash propose' "$RC" 0

run "$R" record --event finding --task t-need --layer qa
check 'a finding without --class is refused' "$RC" 1
has 'the missing class flag is named' "$OUT" '--class is required'
run "$R" record --event finding --task t-need --class c
check 'a finding without --layer is refused' "$RC" 1
has 'the missing layer flag is named' "$OUT" '--layer is required'
run "$R" record --event revert --class c
check 'a revert without --layer is refused' "$RC" 1
[ ! -e "$D/t-need" ] && ok 'refused records created no folder' || bad 'a refused record created a folder'
run "$R" propose --root "$V"
has 'round caps in 2 tasks give a candidate' "$OUT" 'round caps recur on loop review-fix'
run "$R" propose --root "$V" --min-cases 5
has 'a round-cap candidate does not depend on --min-cases' "$OUT" 'round caps recur on loop review-fix'
run "$R" propose --root "$H"
lacks 'no round-cap candidate without round caps' "$OUT" 'round caps recur'
run "$R" record --event confirmed --task t-conf --severity IMPORTANT --id REV-1
check 'record accepts confirmed' "$RC" 0
run "$R" record --event round-cap --task t-conf --detail '{"loop":"qa","max":2,"to":"build"}'
check 'record accepts round-cap' "$RC" 0

# --- 4. eval replay on the shipped fixtures -----------------------------------------
run "$R" eval replay "$CASES" "$OUTS"
check 'replay on the shipped fixtures exits 0' "$RC" 0
has 'tuning recall is scored apart' "$OUT" 'tuning: recall raw 2/2, verified 1/2, final 1/2'
has 'test recall is scored apart' "$OUT" 'test: recall raw 2/3, verified 2/3, final 1/3'
has 'a bug lost at verification is flagged' "$OUT" 'LOST: verdict-no-commit-binding between raw and verified'
has 'a bug lost at final review is flagged' "$OUT" 'LOST: loop-without-limit between verified and final'
has 'control false positives per stage' "$OUT" 'control findings raw 1, verified 0, final 0 (false positives; max allowed unlimited)'
run "$R" eval replay "$CASES" "$OUTS" --min-final-recall 0.3
check 'final recall 1/3 meets 0.3' "$RC" 0
run "$R" eval replay "$CASES" "$OUTS" --min-final-recall 0.5
check 'final recall 1/3 misses 0.5' "$RC" 1
has 'the threshold miss is named' "$OUT" 'below --min-final-recall'
run "$R" eval replay "$CASES" "$OUTS" --max-control-fp 0
check 'zero final control findings meets --max-control-fp 0' "$RC" 0
# a control whose false positive survives to the final stage
CF="$T/replay"; mkdir -p "$CF/cases" "$CF/outputs"
cp -R "$CASES/." "$CF/cases/"; cp -R "$OUTS/." "$CF/outputs/"
jq '.final = [{"what":"heading level skips","where":"README.md"}]' "$OUTS/control-docs-typo-merged.json" > "$CF/outputs/control-docs-typo-merged.json"
run "$R" eval replay "$CF/cases" "$CF/outputs" --max-control-fp 0
check 'a surviving control false positive exceeds the cap' "$RC" 1
has 'the control overrun is named' "$OUT" 'exceed --max-control-fp 0'
# missing output
rm "$CF/outputs/loop-without-limit.json"
run "$R" eval replay "$CF/cases" "$CF/outputs"
check 'a missing outputs file fails' "$RC" 1
has 'a missing outputs file is named' "$OUT" 'no recorded output for loop-without-limit'
# the same case id in two sets
cp "$OUTS/loop-without-limit.json" "$CF/outputs/loop-without-limit.json"
mkdir -p "$CF/cases/loop-copy"
jq '.set = "tuning"' "$CASES/loop-without-limit/case.json" > "$CF/cases/loop-copy/case.json"
cp "$OUTS/loop-without-limit.json" "$CF/outputs/loop-copy.json"
run "$R" eval replay "$CF/cases" "$CF/outputs"
check 'a duplicate case id fails' "$RC" 1
has 'a duplicate case id is named' "$OUT" 'case id loop-without-limit appears in two sets'
# a test case needs at least 2 keywords; a where regex narrows what describes the bug; thresholds are 0..1
CG="$T/replay2"; mkdir -p "$CG/cases" "$CG/outputs"
cp -R "$CASES/." "$CG/cases/"; cp -R "$OUTS/." "$CG/outputs/"
jq '.keywords = ["loop"]' "$CASES/loop-without-limit/case.json" > "$CG/cases/loop-without-limit/case.json"
run "$R" eval replay "$CG/cases" "$CG/outputs"
check 'a test case with one keyword fails' "$RC" 1
has 'the keyword rule is named' "$OUT" 'loop-without-limit: a tuning or test case needs at least 2 keywords'
cp "$CASES/loop-without-limit/case.json" "$CG/cases/loop-without-limit/case.json"
jq '.where = "^nowhere/"' "$CASES/loop-without-limit/case.json" > "$CG/cases/loop-without-limit/case.json"
run "$R" eval replay "$CG/cases" "$CG/outputs"
has 'a where that does not match loses the bug and counts its findings as noise' "$OUT" 'test: recall raw 1/3, verified 1/3, final 1/3; noise: raw 4, verified 2, final 1 non-matching findings'
run "$R" eval replay "$CASES" "$OUTS" --min-final-recall 2
check 'a min-final-recall above 1 is an error' "$RC" 1
has 'the recall range is named' "$OUT" 'between 0 and 1'
run "$R" eval replay "$CASES" "$OUTS" --min-final-recall abc
check 'a non-numeric min-final-recall is an error' "$RC" 1
has 'noise per set is printed (shipped tuning)' "$(run "$R" eval replay "$CASES" "$OUTS"; printf '%s' "$OUT")" 'tuning: recall raw 2/2, verified 1/2, final 1/2; noise: raw 1, verified 1, final 0 non-matching findings'
has 'noise per set is printed (shipped test)' "$(run "$R" eval replay "$CASES" "$OUTS"; printf '%s' "$OUT")" 'test: recall raw 2/3, verified 2/3, final 1/3; noise: raw 3, verified 1, final 1 non-matching findings'

# --- 5. eval patterns on a fixture config root ------------------------------------------
CR="$T/cfg"
mkdir -p "$CR/workflows" "$CR/roles/qa" "$CR/tests/evals"
cat > "$CR/workflows/wf.json" <<'EOF'
{"name":"wf","loops":{"qa-fix":{"maxIterations":2}}}
EOF
cat > "$CR/roles/qa/ROLE.md" <<'EOF'
---
name: fm-qa
description: "verifier"
autoloadSkills:
  - verification-before-completion
tools:
  - read
  - bash
spawns:
  - fm-scout
---
# Role: qa

Bind every verdict to the commit it judged.
EOF
cat > "$CR/tests/evals/patterns.json" <<'EOF'
{"version":1,"patterns":[
 {"id":"P-001","set":"test","source":"incident","pattern":"verdict not bound to a commit",
  "checks":[{"kind":"workflow","workflow":"wf","jq":".loops[\"qa-fix\"].maxIterations <= 3"},
            {"kind":"role","role":"qa","regex":"commit it judged"},
            {"kind":"role-frontmatter","role":"qa","jq":"(.skills | index(\"verification-before-completion\")) != null and (.spawns == [\"fm-scout\"]) and .name == \"fm-qa\""}]},
 {"id":"P-002","set":"tuning","source":"incident","pattern":"qa may edit the change",
  "checks":[{"kind":"role-frontmatter","role":"qa","jq":"(.tools | index(\"edit\")) == null"},
            {"kind":"role","role":"qa","regex":"never edits the change"}]}
]}
EOF
run "$R" eval patterns --config-root "$CR"
check 'a failing pattern exits 1' "$RC" 1
has 'a passing pattern is ok' "$OUT" 'ok - P-001 [test] verdict not bound to a commit'
has 'a failing pattern is FAIL' "$OUT" 'FAIL - P-002 [tuning] qa may edit the change'
has 'the failing check is named' "$OUT" 'body does not match /never edits the change/'
lacks 'the passing check of a failing pattern is not blamed' "$OUT" 'frontmatter: jq did not output true'
has 'the score line' "$OUT" 'score: test 1/1, tuning 0/1'
sed -i.bak 's/Bind every verdict/Bind every verdict; qa never edits the change; bind every verdict/' "$CR/roles/qa/ROLE.md" && rm "$CR/roles/qa/ROLE.md.bak"
run "$R" eval patterns --config-root "$CR"
check 'all patterns passing exits 0' "$RC" 0
has 'the score line when all pass' "$OUT" 'score: test 1/1, tuning 1/1'
sed -i.bak 's/^  - bash/  - edit/' "$CR/roles/qa/ROLE.md" && rm "$CR/roles/qa/ROLE.md.bak"
run "$R" eval patterns --config-root "$CR"
check 'a frontmatter change that loses protection fails' "$RC" 1
has 'the frontmatter check is named' "$OUT" 'role qa frontmatter: jq did not output true'
run env FM_CONFIG_ROOT="$CR" "$R" eval patterns --file "$CR/tests/evals/patterns.json"
check 'FM_CONFIG_ROOT locates roles and workflows' "$RC" 1
has 'FM_CONFIG_ROOT run still scores' "$OUT" 'score: test 1/1, tuning 0/1'
run "$R" eval patterns --config-root "$T/nonexistent"
check 'a missing patterns file is an error' "$RC" 1
# empty checks and bad sets fail loudly
cat > "$CR/tests/evals/empty.json" <<'EOF'
{"version":1,"patterns":[
 {"id":"P-009","set":"test","source":"x","pattern":"empty regex","checks":[{"kind":"role","role":"qa","regex":""}]},
 {"id":"P-010","set":"test","source":"x","pattern":"empty jq","checks":[{"kind":"workflow","workflow":"wf","jq":""}]},
 {"id":"P-012","set":"tuning","source":"x","pattern":"empty frontmatter jq","checks":[{"kind":"role-frontmatter","role":"qa","jq":""}]}]}
EOF
run "$R" eval patterns --config-root "$CR" --file "$CR/tests/evals/empty.json"
check 'empty checks fail their patterns' "$RC" 1
has 'an empty regex is an empty check' "$OUT" 'empty check: role qa has no regex'
has 'an empty workflow jq is an empty check' "$OUT" 'empty check: workflow wf has no jq program'
has 'an empty frontmatter jq is an empty check' "$OUT" 'empty check: role qa frontmatter has no jq program'
cat > "$CR/tests/evals/badset.json" <<'EOF'
{"version":1,"patterns":[{"id":"P-011","set":"holdout","source":"x","pattern":"p","checks":[{"kind":"role","role":"qa","regex":"x"}]}]}
EOF
run "$R" eval patterns --config-root "$CR" --file "$CR/tests/evals/badset.json"
check 'a set other than test or tuning is an error' "$RC" 1
has 'the bad set names the pattern id' "$OUT" 'pattern P-011: set must be exactly test or tuning'

finish
