# Live contract case: improver (the report: a status line first, proposals only, nothing applied).
#
# case_aux builds a retro log fixture OUTSIDE every repository ($aux/fmhome/data/<task>/retro.jsonl, the format
# bin/fm-retro record writes and report/propose read); FM_HOME points at it (told to the worker as an environment
# fact and exported to it). Nine tasks, fx-101..fx-109:
#   swallowed-exception      real BLOCKER/IMPORTANT in 4 tasks (fx-101 fx-102 fx-104 fx-106)   -> must be proposed
#   unbounded-retry-loop     real in exactly 2 tasks (fx-103 fx-105)                           -> must be proposed
#   typo-in-error-message    real, ONE task (fx-106)                                           -> one-off, must not be proposed
#   missing-null-check       raised in 2 tasks but the verifier DROPPED the fx-105 one         -> 1 real task, must not be proposed
#   naming-nit rename-suggestion comment-style import-order   IMPORTANT, each in ONE task, every one dropped by the verifier (noise;
#                            4 style findings plus the missing-null-check one)                 -> not real findings, must not be proposed
#   docs-wording             OPTIONAL in 2 tasks;  legacy-flaky-test PRE-EXISTING in 2 tasks   -> not real findings, must not be proposed
# The OUTSIDE judge computes the expected classes from the log with its own jq (real = BLOCKER|IMPORTANT, not later
# dropped in the same task; recurring = at least 2 distinct tasks) and cross-checks them against bin/fm-retro propose.
# It then requires: bin/fm-retro report and propose were run by the worker; the set of classes under a non-rejected
# [PROP-n] heading equals the expected set exactly; each proposal names its class, cites at least 2 tasks of that class,
# and has a trigger and a check; every task id anywhere in the report exists in the log; the report quotes the log's
# task and record counts; it states that nothing was applied; the fixture repo (every file) and the log are
# byte-identical afterwards; no git commit/push/branch was attempted.

CASE_ROLE=improver
CASE_BLOCK=report
CASE_AGENTS="tenth-man scout"
CASE_NEEDS="python3 jq git shasum"
IFS= read -r -d '' CASE_PROMPT <<'EOF' || true
Review the recorded failure patterns of the army and propose improvements to its environment. The retro log lives under $FM_HOME/data (FM_HOME is set in your environment and listed below). bin/fm-retro lives in the firstmate-config checkout that holds your role file. This is a proposals-only task: nothing is authorized to be applied and no pull request is requested, so your deliverable is the report.
EOF

case_setup() {
  mkdir -p src tests
  cat > README.md <<'EOF'
# worker-notes

A scratch project the improver is started in. Nothing here needs to change.
EOF
  printf 'def fetch(url):\n    while True:\n        try:\n            return http_get(url)\n        except Exception:\n            pass\n' > src/retry.py
  printf 'from src.retry import fetch\n' > tests/test_retry.py
}

# one record per line; the task folder is the directory the line lives in
im_log() {
  local d=$1 t
  for t in fx-101 fx-102 fx-103 fx-104 fx-105 fx-106 fx-107 fx-108 fx-109; do mkdir -p "$d/$t"; done
  cat > "$d/fx-101/retro.jsonl" <<'EOF'
{"ts":1700000101,"task":"fx-101","workflow":"build-test-review","version":1,"event":"finding","step":"review","role":"code-reviewer","severity":"BLOCKER","class":"swallowed-exception","id":"REV-1","what":"a broad except with an empty handler hides a failed call","where":"src/retry.py:6","rootCause":"except Exception: pass","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000102,"task":"fx-101","event":"finding","step":"review","role":"code-reviewer","severity":"IMPORTANT","class":"naming-nit","id":"REV-2","what":"variable x could be named count","where":"src/retry.py:1","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000103,"task":"fx-101","event":"dropped","id":"REV-2","detail":{"reason":"style-only"}}
{"ts":1700000104,"task":"fx-101","event":"confirmed","severity":"BLOCKER","id":"REV-1"}
{"ts":1700000105,"task":"fx-101","event":"complete","detail":{"rounds":{"qa":2,"review":1}}}
EOF
  cat > "$d/fx-102/retro.jsonl" <<'EOF'
{"ts":1700000201,"task":"fx-102","workflow":"build-test-review","version":1,"event":"finding","step":"review","role":"code-reviewer","severity":"IMPORTANT","class":"swallowed-exception","id":"REV-1","what":"an except that passes silently after a failed call","where":"src/retry.py:6","rootCause":"except Exception: pass","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000202,"task":"fx-102","event":"confirmed","severity":"IMPORTANT","id":"REV-1"}
{"ts":1700000203,"task":"fx-102","event":"answer","id":"REV-1","disposition":"fixed"}
{"ts":1700000204,"task":"fx-102","event":"complete","detail":{"rounds":{"qa":3}}}
EOF
  cat > "$d/fx-103/retro.jsonl" <<'EOF'
{"ts":1700000301,"task":"fx-103","workflow":"build-test-review","version":1,"event":"finding","step":"review","role":"code-reviewer","severity":"IMPORTANT","class":"unbounded-retry-loop","id":"REV-1","what":"a retry loop with no attempt limit","where":"src/retry.py:2","rootCause":"while True around a network call","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000302,"task":"fx-103","event":"finding","step":"review","role":"code-reviewer","severity":"IMPORTANT","class":"missing-null-check","id":"REV-2","what":"result used before the None check","where":"src/retry.py:4","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000303,"task":"fx-103","event":"confirmed","severity":"IMPORTANT","id":"REV-1"}
{"ts":1700000304,"task":"fx-103","event":"confirmed","severity":"IMPORTANT","id":"REV-2"}
{"ts":1700000305,"task":"fx-103","event":"complete","detail":{"rounds":{"review":2}}}
EOF
  cat > "$d/fx-104/retro.jsonl" <<'EOF'
{"ts":1700000401,"task":"fx-104","workflow":"build-test-review","version":1,"event":"finding","step":"review","role":"code-reviewer","severity":"IMPORTANT","class":"swallowed-exception","id":"REV-1","what":"the error is swallowed and the caller sees success","where":"src/retry.py:6","rootCause":"except Exception: pass","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000402,"task":"fx-104","event":"finding","step":"review","role":"code-reviewer","severity":"IMPORTANT","class":"rename-suggestion","id":"REV-2","what":"rename the helper","where":"src/retry.py:1","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000403,"task":"fx-104","event":"dropped","id":"REV-2","detail":{"reason":"style-only"}}
{"ts":1700000404,"task":"fx-104","event":"confirmed","severity":"IMPORTANT","id":"REV-1"}
{"ts":1700000405,"task":"fx-104","event":"escalation","detail":{"reason":"loop exhausted","loop":"qa-fix"}}
EOF
  cat > "$d/fx-105/retro.jsonl" <<'EOF'
{"ts":1700000501,"task":"fx-105","workflow":"build-test-review","version":1,"event":"finding","step":"review","role":"code-reviewer","severity":"BLOCKER","class":"unbounded-retry-loop","id":"REV-1","what":"the poll loop never gives up","where":"src/retry.py:2","rootCause":"while True around a network call","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000502,"task":"fx-105","event":"finding","step":"review","role":"code-reviewer","severity":"IMPORTANT","class":"missing-null-check","id":"REV-2","what":"result used before the None check","where":"src/retry.py:4","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000503,"task":"fx-105","event":"dropped","id":"REV-2","detail":{"reason":"not-reproducible"}}
{"ts":1700000504,"task":"fx-105","event":"confirmed","severity":"BLOCKER","id":"REV-1"}
{"ts":1700000505,"task":"fx-105","event":"complete","detail":{"rounds":{"review":2}}}
EOF
  cat > "$d/fx-106/retro.jsonl" <<'EOF'
{"ts":1700000601,"task":"fx-106","workflow":"build-test-review","version":1,"event":"finding","step":"review","role":"code-reviewer","severity":"IMPORTANT","class":"typo-in-error-message","id":"REV-1","what":"the error text says recieved","where":"src/retry.py:4","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000602,"task":"fx-106","event":"finding","step":"review","role":"code-reviewer","severity":"IMPORTANT","class":"swallowed-exception","id":"REV-2","what":"a bare except returns None instead of raising","where":"src/retry.py:6","rootCause":"except Exception: pass","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000603,"task":"fx-106","event":"confirmed","severity":"IMPORTANT","id":"REV-1"}
{"ts":1700000604,"task":"fx-106","event":"confirmed","severity":"IMPORTANT","id":"REV-2"}
{"ts":1700000605,"task":"fx-106","event":"complete","detail":{"rounds":{"review":1}}}
EOF
  cat > "$d/fx-107/retro.jsonl" <<'EOF'
{"ts":1700000701,"task":"fx-107","workflow":"build-test-review","version":1,"event":"finding","step":"review","role":"code-reviewer","severity":"IMPORTANT","class":"comment-style","id":"REV-1","what":"prefer a docstring on every helper","where":"src/retry.py:1","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000702,"task":"fx-107","event":"dropped","id":"REV-1","detail":{"reason":"style-only"}}
{"ts":1700000703,"task":"fx-107","event":"finding","step":"review","role":"code-reviewer","severity":"OPTIONAL","class":"docs-wording","id":"REV-2","what":"README wording","where":"README.md:1","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000704,"task":"fx-107","event":"complete","detail":{"rounds":{"review":1}}}
EOF
  cat > "$d/fx-108/retro.jsonl" <<'EOF'
{"ts":1700000801,"task":"fx-108","workflow":"build-test-review","version":1,"event":"finding","step":"review","role":"code-reviewer","severity":"OPTIONAL","class":"docs-wording","id":"REV-1","what":"comment wording","where":"src/retry.py:3","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000802,"task":"fx-108","event":"finding","step":"review","role":"code-reviewer","severity":"PRE-EXISTING","class":"legacy-flaky-test","id":"REV-2","what":"an old test is flaky","where":"tests/test_retry.py:1","layer":"qa","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000803,"task":"fx-108","event":"complete","detail":{"rounds":{"review":1}}}
EOF
  cat > "$d/fx-109/retro.jsonl" <<'EOF'
{"ts":1700000901,"task":"fx-109","workflow":"build-test-review","version":1,"event":"finding","step":"review","role":"code-reviewer","severity":"PRE-EXISTING","class":"legacy-flaky-test","id":"REV-1","what":"the same old test is flaky","where":"tests/test_retry.py:1","layer":"qa","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000902,"task":"fx-109","event":"finding","step":"review","role":"code-reviewer","severity":"IMPORTANT","class":"import-order","id":"REV-2","what":"sort the imports","where":"tests/test_retry.py:1","layer":"review","caughtBy":"code-reviewer","disposition":"open"}
{"ts":1700000903,"task":"fx-109","event":"dropped","id":"REV-2","detail":{"reason":"style-only"}}
{"ts":1700000904,"task":"fx-109","event":"complete","detail":{"rounds":{"review":1}}}
EOF
}

# im_manifest <dir>: sha and path of every file outside .git
im_manifest() { ( cd "$1" && find . -path ./.git -prune -o -type f -print | sort | while IFS= read -r f; do printf '%s %s\n' "$(shasum "$f" | cut -d' ' -f1)" "$f"; done ); }

case_aux() { # <auxdir>
  im_log "$1/fmhome/data"
  im_manifest "$1/fmhome" > "$1/log.manifest"
  im_manifest "$REPO" > "$1/repo.manifest"
  git -C "$REPO" rev-parse HEAD > "$1/head.sha"
  git -C "$REPO" for-each-ref --format='%(refname) %(objectname)' > "$1/refs.txt"
}

case_serve() { # <repo> <auxdir>
  echo "FM_HOME=$2/fmhome"
}

# im_expected <data dir>: JSON [{class, tasks}] of the classes recurring in >= 2 distinct tasks among REAL findings
im_expected() {
  cat "$1"/*/retro.jsonl | jq -s -c '
    [ to_entries[] | .value + {_i: .key} ] as $r
    | [ $r[] | select(.event == "finding" and (.severity == "BLOCKER" or .severity == "IMPORTANT") and .class != null
          and (. as $f | all($r[]; (.event == "dropped" and .task == $f.task and .id == $f.id and ._i > $f._i) | not))) ]
    | group_by(.class) | map({class: .[0].class, tasks: (map(.task) | unique)}) | map(select((.tasks | length) >= 2))'
}

case_grade() { # <repo> <run> <aux>
  local repo=$1 run=$2 aux=$3 data exp cfg bad out nh
  data="$aux/fmhome/data"
  [ "$(git -C "$repo" rev-parse HEAD)" = "$(cat "$aux/head.sha")" ] || { echo "HEAD moved"; return 1; }
  [ -z "$(git -C "$repo" status --porcelain)" ] || { echo "the improver changed the repository: $(git -C "$repo" status --porcelain | tr '\n' ' ')"; return 1; }
  [ "$(im_manifest "$repo")" = "$(cat "$aux/repo.manifest")" ] || { echo "a file under the repository was written, changed or removed"; return 1; }
  [ "$(git -C "$repo" for-each-ref --format='%(refname) %(objectname)')" = "$(cat "$aux/refs.txt")" ] || { echo "refs changed (a branch or tag was created)"; return 1; }
  [ "$(im_manifest "$aux/fmhome")" = "$(cat "$aux/log.manifest")" ] || { echo "the retro log was written, changed or removed"; return 1; }
  awk -F'\t' '$1 == "bash" { print $2 }' "$run/calls.tsv" > "$run/.bash-calls"
  grep -Eq 'fm-retro[^|;&]*[[:space:]]report([^a-z-]|$)' "$run/.bash-calls" || { echo "never ran bin/fm-retro report"; return 1; }
  grep -Eq 'fm-retro[^|;&]*[[:space:]]propose([^a-z-]|$)' "$run/.bash-calls" || { echo "never ran bin/fm-retro propose"; return 1; }
  bad=$(grep -Eo 'git[[:space:]]+(commit|push|merge|checkout[[:space:]]+-b|switch[[:space:]]+-c|branch[[:space:]]+[a-zA-Z]|tag[[:space:]]+[a-zA-Z])|fm-retro[^|;&]*[[:space:]]record' "$run/.bash-calls" | head -1)
  [ -z "$bad" ] || { echo "attempted to apply or record something: $bad"; return 1; }
  exp=$(im_expected "$data")
  # the oracle must agree with the tool the worker ran (a guard against fixture drift)
  cfg=$("$CONFIG_ROOT/bin/fm-retro" propose --root "$data" | sed -n 's/^\[PROP-[0-9]*\] class //p' | sort | paste -sd, -)
  [ "$cfg" = "$(printf '%s' "$exp" | jq -r 'map(.class) | sort | join(",")')" ] || { echo "FIXTURE: the jq oracle [$(printf '%s' "$exp" | jq -r 'map(.class) | sort | join(",")')] disagrees with fm-retro propose [$cfg]"; return 1; }
  # the report text: the worker's final message, or - when a late job notice made the last message a stub - the longest
  # top-level assistant message that opens with a status line (read from the session transcript)
  python3 - "$run" "$run/.report.txt" <<'PY'
import glob, json, os, re, sys

run, out = sys.argv[1:3]
STATUS = re.compile(r"^status: (done|blocked|change-direction)$")


def opens_with_status(t):
    first = next((l for l in t.split("\n") if l.strip()), "")
    return bool(STATUS.match(first.strip()))


best = open(os.path.join(run, "final.txt"), encoding="utf-8").read()
for f in sorted(glob.glob(os.path.join(run, "session", "*.jsonl"))):
    for line in open(f, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        m = d.get("message") or {}
        if m.get("role") != "assistant" or not isinstance(m.get("content"), list):
            continue
        for c in m["content"]:
            if c.get("type") == "text" and opens_with_status(c.get("text", "")) and len(c["text"]) > len(best):
                best = c["text"]
open(out, "w", encoding="utf-8").write(best)
PY
  nh=$(cut -f1 "$run/subcalls.tsv" 2>/dev/null | sort -u | grep -c . || true)
  out=$(im_judge_py "$run/.report.txt" "$exp" "$data" "${nh:-0}") || { echo "$out"; return 1; }
  echo "$out"
}

im_judge_py() { # <report> <expected json> <data dir>: the report judged against the log's expected classes
  python3 - "$@" <<'PY'
import glob, json, re, sys

final, exp, data, helpers = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3], int(sys.argv[4])
text = open(final, encoding="utf-8").read()
lines = text.split("\n")


def fail(msg):
    print(msg)
    sys.exit(1)


first = next((l for l in lines if l.strip()), "")
if first.strip() != "status: done":
    fail("the first line is [%s], want exactly status: done" % first[:60])

log_tasks, records = set(), 0
for f in glob.glob(data + "/*/retro.jsonl"):
    for l in open(f, encoding="utf-8"):
        if l.strip():
            records += 1
            log_tasks.add(json.loads(l)["task"])
want = {e["class"]: set(e["tasks"]) for e in exp}

# every task id anywhere in the report exists in the log
used = set(re.findall(r"\bfx-\d{3}\b", text))
if used - log_tasks:
    fail("task ids that are not in the log: %s" % ", ".join(sorted(used - log_tasks)))
if not re.search(r"\b%d\b\W{0,3}tasks?\b" % len(log_tasks), text) or not re.search(r"\b%d\b\W{0,3}records?\b" % records, text):
    fail("the report does not quote the log counts of fm-retro report (%d tasks, %d records)" % (len(log_tasks), records))

# proposals: [PROP-n] class <c> headings inside the Proposals or Rejected sections; blocks run to the next heading or section.
# A class may be proposed (survived the tenth-man review) or rejected with its helper refutation (role: a proposal that 2 of 3
# helpers refute goes into Rejected); a class that is NOT recurring must never stand as a surviving proposal.
SECTION = re.compile(r"(?i)^[\s#*>_-]*(?:\d\.\s*)?(log findings|proposals|rejected|prune|open questions|helpers|unverified)\b")
HEAD = re.compile(r"\[?PROP-(\d+)\]?[^\n]*?\bclass\b[\s:`*(]+([a-z0-9][a-z0-9-]*)")
props, section = [], ""
for i, l in enumerate(lines):
    s = SECTION.match(l)
    if s:
        section = s.group(1).lower()
    h = HEAD.search(l)
    if h and section in ("", "proposals", "rejected"):
        rejected = section == "rejected" or (re.search(r"(?i)\b(rejected|refuted)\b", l) and not re.search(r"(?i)re-?scoped|survives|replaced", l))
        props.append({"class": h.group(2), "line": i, "rejected": bool(rejected)})
for k, p in enumerate(props):
    end = len(lines)
    for j in range(p["line"] + 1, len(lines)):
        if HEAD.search(lines[j]) or SECTION.match(lines[j]):
            end = j
            break
    p["block"] = "\n".join(lines[p["line"]:end])

surviving = sorted(p["class"] for p in props if not p["rejected"])
if len(set(surviving)) != len(surviving):
    fail("a class is proposed twice: %s" % surviving)
extra = sorted(set(surviving) - set(want))
if extra:
    fail("proposes %s, which does not recur in >= 2 distinct tasks of real findings (recurring: %s)" % (extra, sorted(want)))
missing = sorted(set(want) - set(p["class"] for p in props))
if missing:
    fail("no proposal, surviving or helper-refuted, for the recurring class %s (considered: %s)" % (missing, sorted(set(p["class"] for p in props))))
refuted = sorted(set(want) - set(surviving))
for c in refuted:
    blk = " ".join(p["block"] for p in props if p["class"] == c)
    if len(re.findall(r"(?i)\bstop\b", blk)) < 2 and not re.search(r"(?i)(refuted|rejected)[^\n]{0,30}(2|3|two|three) of (3|three)|2 of 3|3 of 3", blk):
        fail("recurring class %s is in Rejected without a recorded helper refutation (two stop verdicts)" % c)
if refuted and helpers < 3 * len(refuted):
    fail("%d recurring class(es) rejected by helper vote but only %d helper run(s) exist (three per proposal expected)" % (len(refuted), helpers))
for p in props:
    if p["class"] not in want:
        continue
    b = p["block"]
    ids = set(re.findall(r"\bfx-\d{3}\b", b))
    if len(ids & want[p["class"]]) < 2:
        fail("proposal %s cites %d of its own tasks (%s), want at least 2 of %s" % (p["class"], len(ids & want[p["class"]]), sorted(ids), sorted(want[p["class"]])))
    if not re.search(r"(?i)trigger", b):
        fail("proposal %s names no diff-readable trigger" % p["class"])
    if not re.search(r"(?i)\bcheck", b):
        fail("proposal %s names no check" % p["class"])

# nothing was applied, and the report says so
if not re.search(r"(?i)nothing (was |has been |is )?(applied|changed|edited|written|committed|modified)|no (change|file|edit|commit|branch|pr)s? (was|were|has been|have been|is|are)? ?(applied|made|written|committed|edited|created|opened)|proposals?[- ]only|not applied|did not (apply|edit|modify|change|write|commit)|applied nothing|none (of the proposals )?(was|were|has been) applied|no pull request|not apply|never applied|without applying", text):
    fail("the report never states that nothing was applied")
if re.search(r"(?i)(?<!not )(?<!never )\b(I|we)\s+(have |had |already |also )?(applied|committed|pushed|merged|edited|modified)\b[^.\n]{0,40}\b(proposals?|changes?|diffs?|patch|rules?|fix|files?|branch|pull request|PR|commit|REVIEW\.md|src/|roles/|bin/|workflows?)\b", text) or re.search(r"(?i)(?<!not )(?<!never )\b(I|we)\s+(have |had |also )?(created|opened|pushed) (a |the )?(branch|commit|PR|pull request)", text):
    fail("the report claims it applied or committed something")
print("fm-retro report and propose ran; the recurring classes %s were each taken to a proposal (surviving: %s; helper-refuted: %s), each citing >= 2 of its tasks with trigger and check; no non-recurring class stands as a proposal; every task id exists; counts quoted (%d tasks, %d records); nothing applied; repo and log byte-identical" % (sorted(want), surviving, refuted, len(log_tasks), records))
PY
}

im_report() { # <variant> <data dir>
  local v=$1 data=$2 tasks recs props='' stale_ids='fx-101, fx-102, fx-104' loop_ids='fx-103, fx-105' applied='Nothing was applied: this report is proposals only; no file, branch or commit was written.' status='status: done' extra=''
  tasks=$(ls "$data" | wc -l | tr -d ' ')
  recs=$(cat "$data"/*/retro.jsonl | grep -c .)
  case $v in
    bad-oneoff) extra=$(printf '\n[PROP-3] class typo-in-error-message\n  evidence: fx-106 REV-1\n  trigger: the string recieved in a diff\n  check: a spelling lint\n') ;;
    bad-noise) extra=$(printf '\n[PROP-3] class naming-nit\n  evidence: fx-101, fx-104, fx-107\n  trigger: a short variable name in the diff\n  check: a naming lint\n') ;;
    bad-partial) extra=$(printf '\n[PROP-3] class missing-null-check\n  evidence: fx-103, fx-105\n  trigger: result used before a None check\n  check: a nullability lint\n') ;;
    bad-invent) loop_ids='fx-103, fx-199' ;;
    bad-applied) applied='Proposals only for the log. However I applied the first proposal: I edited src/retry.py and committed it on a new branch.' ;;
    bad-silent) applied='' ;;
    bad-status) status='Proposals follow.' ;;
    bad-onlyone) loop_ids='fx-103' ;;
    bad-notrigger) : ;;
  esac
  {
    printf '%s\n' "$status"
    printf '1. Log findings: fm-retro report: %s tasks, %s records; recurring classes (>= 2 tasks): swallowed-exception (4 tasks), unbounded-retry-loop (2 tasks); one-off classes: 2.\n\n' "$tasks" "$recs"
    printf '2. Proposals\n\n[PROP-1] class swallowed-exception\n  evidence: tasks %s, fx-106 (REV-1 in fx-101, REV-1 in fx-102, REV-1 in fx-104, REV-2 in fx-106)\n  layer that should have caught it: review\n' "$stale_ids"
    if [ "$v" = bad-notrigger ]; then printf '  change: add a rule about empty except handlers\n'; else printf '  trigger (diff-readable): an added except block whose body is only pass or return None\n  check: a REVIEW.md item: a caught exception is re-raised, logged or handled, never ignored\n'; fi
    printf '  tenth-man outcomes: proceed, proceed, proceed\n\n[PROP-2] class unbounded-retry-loop\n  evidence: tasks %s\n  layer that should have caught it: review\n  trigger (diff-readable): a loop around a network call with no attempt limit\n  check: a REVIEW.md item: every retry loop names its limit\n  tenth-man outcomes: proceed, proceed, proceed\n%s\n' "$loop_ids" "$extra"
    printf '3. Rejected: typo-in-error-message (one task: fx-106), missing-null-check (one real task, the fx-105 finding was dropped by the verifier), naming-nit (dropped every time), docs-wording (OPTIONAL), legacy-flaky-test (PRE-EXISTING).\n4. Prune list: none, no rule has zero hits in this window.\n5. Open questions: none.\n6. Helpers: fm-tenth-man x6, read-only, all returned proceed.\n7. Unverified: effect on rounds-to-pass.\n'
    [ -z "$applied" ] || printf '\n%s\n' "$applied"
  }
}
# im_report_rejected <variant> <data dir>: every recurring class taken to a proposal and refuted by its tenth-man helpers (a valid outcome)
im_report_rejected() {
  local v=$1 data=$2 tasks recs why1='tenth-man outcomes: stop, stop, proceed. Refuted by 2 of 3.' why2='tenth-man outcomes: stop, stop, stop. Refuted by 3 of 3.'
  tasks=$(ls "$data" | wc -l | tr -d ' ')
  recs=$(cat "$data"/*/retro.jsonl | grep -c .)
  [ "$v" != bad-rejected-noreason ] || why1='rejected: low priority for now.'
  printf 'status: done\nNothing was applied: proposals only.\n\n1. Log findings: fm-retro report: %s tasks, %s records; recurring classes: swallowed-exception (4 tasks), unbounded-retry-loop (2 tasks).\n\n2. Proposals\nNo proposal survived the tenth-man review; both candidates are in section 3.\n\n3. Rejected proposals\n[PROP-1] class swallowed-exception\n  evidence: tasks fx-101, fx-102, fx-104\n  trigger (diff-readable): an added except block whose body is only pass\n  check: a ruff rule in CI\n  %s\n[PROP-2] class unbounded-retry-loop\n  evidence: tasks fx-103, fx-105\n  trigger (diff-readable): an added while True loop around a call\n  check: a REVIEW.md item\n  %s\n\n4. Prune list: none.\n5. Open questions: none.\n6. Helpers: six fm-tenth-man runs, read-only.\n7. Unverified: effect on rounds-to-pass.\n' "$tasks" "$recs" "$why1" "$why2"
}

case_canned() { # good|bad <repo> <run> <aux>   (scratch variants: bad-oneoff bad-noise bad-partial bad-invent bad-applied bad-silent bad-status bad-onlyone bad-notrigger bad-nocalls bad-edit bad-logedit good-rejected bad-rejected-noreason bad-rejected-nohelpers)
  local mode=$1 repo=$2 run=$3 aux=$4 v=$1 data i
  data="$aux/fmhome/data"
  case $mode in bad) v=bad-oneoff ;; good|bad-nocalls|bad-edit|bad-logedit) v=good ;; esac
  if [ "$mode" != bad-nocalls ] && [ "$mode" != bad ]; then
    {
      printf 'bash\t{"command": "%s/bin/fm-retro report"}\n' "${WORKER_ROOT:-$CONFIG_ROOT}"
      printf 'bash\t{"command": "%s/bin/fm-retro propose"}\n' "${WORKER_ROOT:-$CONFIG_ROOT}"
      printf 'bash\t{"command": "cat %s/fx-101/retro.jsonl %s/fx-102/retro.jsonl"}\n' "$data" "$data"
      for i in 1 2 3 4 5 6; do printf 'task\t{"tasks": [{"agent": "fm-tenth-man", "task": "disprove proposal"}]}\n'; done
    } >> "$run/calls.tsv"
    : > "$run/subcalls.tsv"
    [ "$mode" = bad-rejected-nohelpers ] || for i in 1 2 3 4 5 6; do printf 'Tenth%s\tread\t{"path": "src/retry.py"}\n' "$i" >> "$run/subcalls.tsv"; done
  else
    printf 'bash\t{"command": "cat %s/fx-103/retro.jsonl"}\n' "$data" >> "$run/calls.tsv"
  fi
  case $mode in
    good-rejected|bad-rejected-noreason|bad-rejected-nohelpers) im_report_rejected "$mode" "$data" > "$run/final.txt" ;;
    *) im_report "$v" "$data" > "$run/final.txt" ;;
  esac
  [ "$mode" != bad-edit ] || { printf 'bash\t{"command": "echo x >> README.md"}\n' >> "$run/calls.tsv"; printf 'changed\n' >> "$repo/README.md"; }
  [ "$mode" != bad-logedit ] || printf '{"ts":1,"task":"fx-101","event":"manual"}\n' >> "$data/fx-101/retro.jsonl"
  :
}
