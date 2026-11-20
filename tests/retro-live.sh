#!/usr/bin/env bash
# retro-live.sh - proves bin/fm-retro (record / report / propose) on retro logs produced by REAL workflow runs.
# The logs are the retro.jsonl files that bin/fm-workflow appended while tests/workflows-live.sh drove real workers
# (tests/live-artifacts/<stamp>/<case>/data/retro.jsonl, git-ignored). The tool itself is deterministic: what is live
# here is the DATA (real findings, real classes, real escalations), not a model call.
#
# The judge is an independent oracle: a Python re-implementation of the definitions (it shares no code with the jq in
# bin/fm-retro) computes, straight from the JSON lines, the numbers `fm-retro report` must print and the classes
# `fm-retro propose` must propose, and every one is compared. It also checks that report/propose write nothing, that
# `record` appends exactly one well-formed line that the next report counts, and that a class seen in only one task is
# never proposed.
#
# Usage:
#   tests/retro-live.sh                     use every tests/live-artifacts/*/*/data/retro.jsonl; SKIP (never PASS) when there
#                                           is none (run FM_WORKFLOW_LIVE=1 tests/workflows-live.sh first)
#   tests/retro-live.sh <artifacts-dir>...  use the retro logs under these directories instead
#   tests/retro-live.sh selftest            the same pipeline over a SYNTHETIC log tree (not live) plus negative checks
#                                           that the oracle comparison really fails on a wrong report
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RETRO="$CONFIG_ROOT/bin/fm-retro"
ART_ROOT="$CONFIG_ROOT/tests/live-artifacts"
failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }

# oracle <root-data-dir> <report-file> <propose-file> <expect-reverts>: prints ok/FAIL lines.
oracle() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import glob, json, os, re, sys
root, report_f, propose_f, want_rev = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
report = open(report_f, encoding="utf-8").read()
propose = open(propose_f, encoding="utf-8").read()
recs, tasks = [], {}
for f in sorted(glob.glob(os.path.join(root, "*", "*.jsonl"))):
    task = os.path.basename(os.path.dirname(f))
    misc = os.path.basename(f) == "misc.jsonl"
    for line in open(f, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        d = json.loads(line)
        d["_task"] = None if misc else task
        d["_i"] = len(recs)
        recs.append(d)
        if not misc:
            tasks.setdefault(task, []).append(d)
out = []
def res(ok, text): out.append(("ok   - " if ok else "FAIL - ") + text)
def grab(pat):
    m = re.search(pat, report, re.M)
    return m.groups() if m else None

task_lines = [t for t in tasks]
res(grab(r"^fm-retro report: (\d+) task\(s\), (\d+) record\(s\)") == (str(len(task_lines)), str(len(recs))),
    "report header: %d task(s), %d record(s) (oracle) vs %s" % (len(task_lines), len(recs), grab(r"^fm-retro report: (\d+) task\(s\), (\d+) record\(s\)")))
# severities of finding events
sev = {s: sum(1 for r in recs if r["event"] == "finding" and r.get("severity") == s) for s in ("BLOCKER", "IMPORTANT", "OPTIONAL", "PRE-EXISTING")}
want = "findings by severity: " + ", ".join("%s=%d" % (s, sev[s]) for s in ("BLOCKER", "IMPORTANT", "OPTIONAL", "PRE-EXISTING"))
res(want in report, "severity histogram matches the log: %s" % want)
caps = sum(1 for r in recs if r["event"] == "round-cap")
res(grab(r"^round caps: (\d+)") == (str(caps),), "round caps: %d" % caps)
res(grab(r"^reverts: (\d+)") == (str(want_rev),), "reverts: %d (every record --event revert counts)" % want_rev)
done = [t for t, rs in tasks.items() if any(r["event"] in ("complete", "escalation", "closed") for r in rs)]
esc = [t for t, rs in tasks.items() if any(r["event"] == "escalation" for r in rs)]
res(grab(r"^escalation rate: (\d+)/(\d+)") == (str(len(esc)), str(len(done))), "escalation rate %d/%d" % (len(esc), len(done)))
nocls = sum(1 for r in recs if r["event"] == "finding" and r.get("class") is None)
res(grab(r"^findings without class: (\d+)") == (str(nocls),), "findings without a class: %d" % nocls)
dropped = sum(1 for r in recs if r["event"] == "dropped")
confirmed = sum(1 for r in recs if r["event"] == "confirmed")
vm = grab(r"^verification: (\S+) confirmed, (\S+) dropped of (\S+) raised")
res(vm is not None and vm[0] == (str(confirmed) if confirmed else "n/a") and vm[1] == (str(dropped) if dropped else "n/a"),
    "verification line: %d confirmed, %d dropped" % (confirmed, dropped))
# real findings: BLOCKER/IMPORTANT not later dropped by the verifier (same task and id); a revert counts as an IMPORTANT case
def real(r, i):
    if r["event"] == "revert":
        return True
    if r["event"] != "finding" or r.get("severity") not in ("BLOCKER", "IMPORTANT"):
        return False
    return not any(q["event"] == "dropped" and q["_task"] == r["_task"] and q.get("id") == r.get("id") and q["_i"] > r["_i"] for q in recs)
cases = {}
for r in recs:
    if real(r, r["_i"]) and r.get("class") is not None:
        key = r["_task"] if r["_task"] is not None else "revert-%s" % (r.get("commit") or r["_i"])
        cases.setdefault(r["class"], set()).add(key)
recurring = sorted(c for c, ks in cases.items() if len(ks) >= 2)
oneoff = sorted(c for c, ks in cases.items() if len(ks) < 2)
rec_lines = re.findall(r"^  (\S+) \([^)]*\): (\d+) tasks", report, re.M)
res(sorted(set(c for c, _ in rec_lines)) == recurring, "recurring classes in the report == oracle %s" % recurring)
res(len(grab(r"^one-off classes: (\d+)") or ()) == 1, "one-off classes line present (oracle one-off classes: %d)" % len(oneoff))
proposed = re.findall(r"^\[PROP-\d+\] class (\S+)", propose, re.M)
res(sorted(proposed) == recurring, "propose proposes exactly the recurring classes %s (got %s)" % (recurring, sorted(proposed)))
res(not any(c in proposed for c in oneoff), "no one-off class is proposed %s" % oneoff)
res("PROPOSALS ONLY" in propose, "propose says nothing is applied")
for c in recurring:
    m = re.search(r"^\[PROP-\d+\] class %s\n  evidence: (\d+) tasks" % re.escape(c), propose, re.M)
    res(m is not None and int(m.group(1)) == len(cases[c]), "proposal for %s cites %d distinct case(s) (oracle %d)" % (c, int(m.group(1)) if m else -1, len(cases[c])))
print("\n".join(out))
sys.exit(1 if any(o.startswith("FAIL") for o in out) else 0)
PY
}

stage_tree() { # <dest-data-dir> <retro.jsonl>... : one task directory per log
  local dest=$1 f n=0 name
  shift
  mkdir -p "$dest"
  for f in "$@"; do
    n=$((n + 1))
    case $f in
      */live-artifacts/*) name=$(printf '%s' "$f" | sed 's#.*/live-artifacts/##; s#/data/retro.jsonl$##; s#[/ ]#.#g') ;;
      *) name="task$n" ;;
    esac
    case $name in ''|.*) name="task$n" ;; esac
    mkdir -p "$dest/$name" && cp "$f" "$dest/$name/retro.jsonl"
  done
}

checksum_tree() { find "$1" -type f -print0 | sort -z | xargs -0 cat | cksum; }

# run_pipeline <label> <retro.jsonl>...
run_pipeline() {
  local label=$1 t home data n before after rep prop rev out rc
  shift
  t=$(mktemp -d "${TMPDIR:-/tmp}/fm-retro-live.XXXXXX") || return 1
  home="$t/home"; data="$home/data"
  stage_tree "$data" "$@"
  n=$(find "$data" -name retro.jsonl | wc -l | tr -d ' ')
  before=$(checksum_tree "$data")
  rep="$t/report.txt"; prop="$t/propose.txt"
  FM_HOME="$home" "$RETRO" report --root "$data" > "$rep" 2>&1 || fail "$label: report exited non-zero: $(head -3 "$rep")"
  FM_HOME="$home" "$RETRO" propose --root "$data" > "$prop" 2>&1 || fail "$label: propose exited non-zero: $(head -3 "$prop")"
  after=$(checksum_tree "$data")
  [ "$before" = "$after" ] && pass "$label: report and propose wrote nothing ($n log(s) unchanged)" || fail "$label: report/propose changed the log tree"
  out=$(oracle "$data" "$rep" "$prop" 0); rc=$?
  printf '%s\n' "$out"
  [ "$rc" -eq 0 ] || failed=1
  # record: exactly one well-formed line appended, counted by the next report
  FM_HOME="$home" "$RETRO" record --event revert --task - --class stale-verdict-after-fix --layer ci --commit abc1234 --what 'a merged PR was reverted' > "$t/record.out" 2>&1; rc=$?
  [ "$rc" -eq 0 ] && pass "$label: record --event revert accepted" || fail "$label: record refused: $(cat "$t/record.out")"
  [ "$(cat "$data"/retro/misc.jsonl 2>/dev/null | wc -l | tr -d ' ')" = 1 ] && jq -e '.event == "revert" and .class == "stale-verdict-after-fix" and .layer == "ci" and .commit == "abc1234"' "$data/retro/misc.jsonl" >/dev/null 2>&1 \
    && pass "$label: record appended exactly one well-formed JSON line" || fail "$label: the recorded line is missing or malformed"
  FM_HOME="$home" "$RETRO" report --root "$data" > "$t/report2.txt" 2>&1
  FM_HOME="$home" "$RETRO" propose --root "$data" > "$t/propose2.txt" 2>&1
  out=$(oracle "$data" "$t/report2.txt" "$t/propose2.txt" 1); rc=$?
  printf '%s\n' "$out" | sed 's/^\(ok   - \|FAIL - \)/\1after record: /'
  [ "$rc" -eq 0 ] && pass "$label: after the revert record, report and propose still equal the oracle (reverts 1)" || fail "$label: after the record, report/propose differ from the oracle"
  RP_LAST_DIR=$t
}

selftest() {
  local t d i out
  t=$(mktemp -d "${TMPDIR:-/tmp}/fm-retro-live-self.XXXXXX") || return 1
  # a SYNTHETIC tree (clearly not live): three tasks, class A in two, class B in one, a dropped finding that must not count
  mk() { # <file> <task> <class-of-blocker> <extra-line>
    {
      printf '{"event":"finding","step":"review","run":1,"role":"code-reviewer","caughtBy":"code-reviewer","outcome":"fail","severity":"BLOCKER","class":"%s","id":"REV-1","what":"w","where":"f:1","layer":"author","disposition":"open","commit":"c1","ts":1,"task":"%s","workflow":"build-test-review","version":2}\n' "$3" "$2"
      [ -z "$4" ] || printf '%s\n' "$4"
      printf '{"event":"complete","step":"deliver","run":1,"outcome":"done","detail":{"rounds":{"qa-fix":0,"review-fix":1},"runs":{}},"ts":2,"task":"%s","workflow":"build-test-review","version":2}\n' "$2"
    } > "$1"
  }
  mkdir -p "$t/a" "$t/b" "$t/c"
  mk "$t/a/retro.jsonl" ta cls-a ''
  mk "$t/b/retro.jsonl" tb cls-a '{"event":"finding","step":"review","run":1,"role":"code-reviewer","caughtBy":"code-reviewer","outcome":"fail","severity":"IMPORTANT","class":"cls-dropped","id":"REV-2","what":"w","where":"f:2","layer":"qa","disposition":"open","commit":"c1","ts":1,"task":"tb","workflow":"build-test-review","version":2}
{"event":"dropped","step":"verify-review","run":1,"role":"finding-verifier","id":"REV-2","disposition":"dropped","detail":{"reason":"not-reproducible","evidence":"ran it"},"ts":1,"task":"tb","workflow":"build-test-review","version":2}'
  mk "$t/c/retro.jsonl" tc cls-b ''
  run_pipeline 'selftest (synthetic logs, not live)' "$t/a/retro.jsonl" "$t/b/retro.jsonl" "$t/c/retro.jsonl"
  # the oracle must FAIL on a wrong report: feed it a report from a tree with one log fewer
  d=$RP_LAST_DIR
  mkdir -p "$t/short/ta" && cp "$t/a/retro.jsonl" "$t/short/ta/retro.jsonl"
  FM_HOME="$t/shorthome" "$RETRO" report --root "$t/short" > "$t/short.rep" 2>&1
  FM_HOME="$t/shorthome" "$RETRO" propose --root "$t/short" > "$t/short.prop" 2>&1
  out=$(oracle "$d/home/data" "$t/short.rep" "$t/short.prop" 0 2>&1); i=$?
  [ "$i" -ne 0 ] && printf '%s' "$out" | grep -q 'FAIL - report header' && pass 'selftest: the oracle comparison fails on a report built from different logs' || fail 'selftest: the oracle accepted a wrong report'
  # the recurring class is cls-a only; the dropped finding class and the one-off must not be proposed
  grep -q '^\[PROP-1\] class cls-a$' "$d/propose.txt" && ! grep -q 'cls-dropped\|cls-b' "$d/propose.txt" && pass 'selftest: only the class seen in two tasks (not the dropped one, not the one-off) is proposed' || fail 'selftest: wrong proposals'
  rm -rf "$t" "$d"
}

if [ "${1:-}" = selftest ]; then
  command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || { printf 'SKIP - retro live: needs jq and python3\n'; exit 0; }
  selftest
  printf '\nRETRO LIVE SELFTEST %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
  [ "$failed" -eq 0 ]; exit $?
fi
command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || { printf 'SKIP - retro live: needs jq and python3\n'; exit 0; }
if [ "$#" -gt 0 ]; then dirs=("$@"); else dirs=("$ART_ROOT"); fi
logs=()
for d in "${dirs[@]}"; do
  while IFS= read -r f; do logs+=("$f"); done <<EOF
$(find "$d" -path '*/data/retro.jsonl' -type f 2>/dev/null | sort)
EOF
done
if [ "${#logs[@]}" -eq 0 ]; then
  printf 'SKIP - retro live: no retro.jsonl from a live workflow run under %s; run FM_WORKFLOW_LIVE=1 tests/workflows-live.sh first (never reported as PASS)\n' "${dirs[*]}"
  exit 0
fi
printf '# retro logs from real runs: %s\n' "${#logs[@]}"
run_pipeline "live logs" "${logs[@]}"
printf '\n--- fm-retro report over the real logs ---\n'
cat "$RP_LAST_DIR/report2.txt"
printf '\n--- fm-retro propose over the real logs ---\n'
cat "$RP_LAST_DIR/propose2.txt"
rm -rf "$RP_LAST_DIR"
printf '\nRETRO LIVE %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
