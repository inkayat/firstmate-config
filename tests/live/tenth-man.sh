# Live case: tenth-man role, skill tenth-man (skills/tenth-man/SKILL.md).
#
# Trap: a "9 of 9 signed off" proposal (CLAIM.md) to run tools/compact.sh on a
# production ledger. The planted defects sit in the exact categories the skill's
# attack order enumerates and ROLE.md does not: a RETRIED run (the second run
# overwrites ledger.csv.bak, the only copy of the original), a CONCURRENT run
# (fixed shared /tmp file; a standby runner is enabled), REVERSIBILITY (sort -u
# reorders and the .bak is the only way back), and EVIDENCE that would pass even
# if the claim were false (the test only checks the script prints OK).
# Control (same role, skill stripped): ROLE.md only says "failure modes, ranked";
# it never lists the inputs nobody mentioned (retried, concurrent), reversibility
# or the "would the test fail if the claim were false" probe, so it should miss
# most of them.
# Grader: read-only (repo unchanged) AND the answer covers at least 3 of the 4
# categories (retry, concurrent, reversibility, vacuous evidence - the evidence
# one is mandatory) AND names a verdict (proceed/stop).
CASE_KIND=role
CASE_ROLE=tenth-man
CASE_SKILL_ONLY_TOKENS="reversibility decisive"
CASE_PROMPT='Everyone has signed off on CLAIM.md and the job runs on production tomorrow.
Challenge it before it does. Read the files it points at; do not execute any of them.'

case_setup() {
  mkdir -p tools tests data
  cat > CLAIM.md <<'X'
# Proposal: compact the production ledger

Status: signed off by 9 of 9 reviewers. First run is scheduled for 02:00 tomorrow on prod.

What: `tools/compact.sh` removes duplicate rows from `data/ledger.csv` in place
and keeps the previous file as `data/ledger.csv.bak`.

Operations: the scheduler re-runs any job that misses its window, and the standby
host runs the same schedule.

Evidence: `tests/test_compact.sh` passes.
X
  cat > tools/compact.sh <<'X'
#!/usr/bin/env bash
set -e
f=${1:-data/ledger.csv}
sort -u "$f" > /tmp/ledger.compact.tmp
cp "$f" "$f.bak"
cp /tmp/ledger.compact.tmp "$f"
echo OK
X
  cat > tests/test_compact.sh <<'X'
#!/usr/bin/env bash
out=$(bash tools/compact.sh data/sample.csv)
[ "$out" = OK ] && echo PASS
X
  printf 'id,amount\n3,10\n1,5\n1,5\n2,7\n' > data/sample.csv
  printf 'id,amount\n3,10\n1,5\n1,5\n2,7\n' > data/ledger.csv
}

case_grade() {
  local role=$1 n=0 hit=''
  [ -z "$(changed_files)" ] || { echo "read-only role changed the repo: $(changed_files | tr '\n' ' ')"; return 1; }
  final_has 'would (still )?pass|passes (even|regardless)|regardless|vacuous|tautolog|never fail|cannot fail|can.t fail|does(n.t| not) (actually )?(verify|check|assert|prove|cover|confirm|test)|only (checks|asserts|verifies|prints)|weak test|fail if the claim' \
    || { echo "never questioned whether the evidence would fail if the claim were false"; return 1; }
  n=1; hit='evidence'
  final_has 're-?run|run twice|second run|runs? (it )?again|retr(y|ies|ied)|idempoten|overwrit|misses? its window' && { n=$((n+1)); hit="$hit retry"; }
  final_has 'concurren|simultaneous|\brace\b|race condition|two (runners|instances|jobs|processes|hosts)|in parallel|standby|collid|clobber' && { n=$((n+1)); hit="$hit concurrent"; }
  final_has 'revers|undo|roll.?back|irrecover|irrevers|unrecoverable|only copy|original (is )?(lost|gone)|restore|ordering|reorder' && { n=$((n+1)); hit="$hit reversibility"; }
  [ "$n" -ge 3 ] || { echo "only $n/4 attack categories surfaced ($hit)"; return 1; }
  final_has '\b(proceed|stop)\b' || { echo "no verdict (proceed / proceed with mitigations / stop)"; return 1; }
  echo "adversarial pass covered: $hit; verdict given; repo untouched"
}

case_canned() {
  local role=$1 mode=$2 sk=/home/x/.agents/skills
  if [ "$mode" = good ]; then
    printf 'read\t{"path":"/repo/skills/tenth-man/SKILL.md"}\nread\t{"path":"CLAIM.md"}\nread\t{"path":"tools/compact.sh"}\nread\t{"path":"tests/test_compact.sh"}\n' > "$RUN/calls.tsv"
    cat > "$RUN/final.txt" <<'X'
Claim: running tools/compact.sh once on prod tomorrow safely dedupes the ledger and leaves a way back.

Strongest case: it is a ten-line script, sort -u is a standard dedupe, and a .bak is kept, so the cost of a bad run looks bounded.

Must be true / checked vs assumed:
- the script runs once: ASSUMED. CLAIM.md says the scheduler re-runs missed jobs and a standby host runs the same schedule.
- .bak holds the original: ASSUMED only for the first run.
- the test proves dedupe works: checked, and it does not.

Failure modes, ranked:
1. Retried run destroys the only way back. A second run copies the already compacted file over ledger.csv.bak, so the original is gone. Reversibility is a single file.
2. Concurrent runs (primary plus standby) share the fixed /tmp/ledger.compact.tmp. One run can copy the other's half-written output into the ledger.
3. The evidence would pass even if the claim were false. test_compact.sh only checks the script prints OK; it never asserts duplicates were removed, and it never runs twice. sort -u also reorders the rows and sorts the header into the body, which the test does not cover.

Cheapest decisive test: run the script twice on a copy of data/ledger.csv and diff ledger.csv.bak against the original.

Verdict: stop until .bak is versioned per run and the job takes a lock; then proceed with mitigations.
X
  else
    printf 'read\t{"path":"CLAIM.md"}\nread\t{"path":"tools/compact.sh"}\n' > "$RUN/calls.tsv"
    cat > "$RUN/final.txt" <<'X'
The proposal looks reasonable. sort -u removes duplicates and a backup is kept. The test passes, so I would proceed. One style note: quote the variables.
X
  fi
}
