# Live workflow case (viii): research-decide (researcher -> architect options -> tenth-man challenge -> decide).
# Problem: should the service adopt the vendor library quillmq's at-least-once delivery mode in place of its hand-rolled retry loop
#   (worker.py)? quillmq is fictional, so a model cannot answer from memory: the ONLY primary source is the local vendor-docs/
#   directory (no network) for the pinned version (requirements.txt: quillmq==2.3.1). The questions mix answerable ones (does 2.3.1
#   have the mode, what is the message size limit - the preview 2.4 notes say 1 MiB, a version trap -, the redelivery behaviour, is there
#   exactly-once) with one the docs are silent on (p99 latency at 10k msgs/s), which must come back UNVERIFIED.
# The driver answers the `decide` decision step with CASE_DECIDE=adopt and a recorded reason (the redirect decision keeps its
#   default, escalate: nothing here may change direction).
# Outside judge (deterministic, code only): the engine state ends complete after decide:adopt with the reason recorded; every
#   vendor-docs path the research report cites exists in the fixture (and every cited :line is inside the file); every double-quoted
#   passage on a cited row is a verbatim substring of the cited file (grep -F, whitespace-normalised); the project version 2.3.1 and the
#   planted facts (256 KiB for 2.3.1, at_least_once, idempotent consumers) are in the report; the latency question is UNVERIFIED; the options
#   report names at most 3 options and exactly one recommendation; the challenge ended in a valid verdict block (the generic grader).
CASE_WORKFLOW=research-decide
CASE_TASK='Decide whether we should adopt the vendor library quillmq'"'"'s at-least-once delivery mode in place of the hand-rolled retry loop in worker.py. Research questions: (1) which quillmq version do we run and does it have an at-least-once delivery mode; (2) the maximum message size in that version; (3) what happens to a message whose consumer does not acknowledge it; (4) does quillmq offer exactly-once delivery; (5) the p99 delivery latency at 10k messages per second. The vendor documentation for the pinned version is in the local vendor-docs/ directory: it is the primary source, there is no network. Then propose options for the decision, challenge the recommendation, and hand the decision to the Captain. Do not change any file.'
CASE_NO_CONTROL=1
CASE_DECIDE=adopt
CASE_DECIDE_REASON='adopt quillmq at_least_once: the 2.3.1 docs confirm the mode and a 256 KiB limit that fits our payloads; consumers must be made idempotent'
CASE_EXPECT_PATH='^research:done options:done( challenge:fail options:done)* challenge:pass decide:adopt$'
CASE_FORCE_AFTER=''
CASE_NEGATIVE='nocite => does not exist in the fixture
four => options report names
guess => p99 latency question is not marked UNVERIFIED'

case_setup() {
  mkdir -p vendor-docs/quillmq tests
  cat > README.md <<'R'
# jobs
Background job runner. worker.py retries failed jobs by hand; see requirements.txt for the pinned queue library.
R
  printf 'quillmq==2.3.1\n' > requirements.txt
  cat > worker.py <<'R'
import time


def run_job(job, handler, attempts=3, delay=0.5):
    """Hand-rolled retry: the loop quillmq's at-least-once mode might replace."""
    for i in range(attempts):
        try:
            return handler(job)
        except Exception:
            if i == attempts - 1:
                raise
            time.sleep(delay)
R
  cat > vendor-docs/quillmq/README.md <<'R'
# quillmq

quillmq is a small in-process job queue for Python services.

Current stable release: 2.3.1. The 2.4 line is a preview and is not recommended for production.
Documentation in this directory describes the stable release unless a section says otherwise.
R
  cat > vendor-docs/quillmq/delivery.md <<'R'
# Delivery modes

quillmq supports two delivery modes, chosen per queue with the `delivery` option.

- `at_most_once` (the default): a message is handed to one consumer once. If the consumer fails, the message is lost.
- `at_least_once`: a message stays on the queue until the consumer acknowledges it. It was added in version 2.2.0.

With `at_least_once`, a message whose consumer does not acknowledge it within the visibility timeout (30 seconds by default, set with `visibility_timeout`) is delivered again.
Redelivery can therefore produce duplicates, so consumers must be idempotent.

quillmq does not provide exactly-once delivery in any mode.
R
  cat > vendor-docs/quillmq/limits.md <<'R'
# Limits (stable 2.3.x)

- Maximum message size: 256 KiB. Larger messages are rejected with `MessageTooLarge`.
- Maximum queue length: unbounded, limited by process memory.
- Maximum consumers per queue: 64.
R
  cat > vendor-docs/quillmq/CHANGELOG.md <<'R'
# Changelog

## 2.4.0 (preview, not released)
- Raise the maximum message size from 256 KiB to 1 MiB.
- Add a `dead_letter` queue option.

## 2.3.1
- Fix a crash when `visibility_timeout` is set to 0.

## 2.3.0
- Add the `visibility_timeout` option.

## 2.2.0
- Add the `at_least_once` delivery mode.
R
}

case_extra() { # <step> <role> <iteration> <kit-dir> <cwd> <data-dir>
  case $2 in
    researcher) printf 'Sources: there is no network and no web search for this task. Your primary sources are the local files under vendor-docs/ (the vendor documentation) and requirements.txt (the pinned version); cite them as path:line, quote non-obvious claims verbatim, and mark whatever the files do not answer as UNVERIFIED.\n' ;;
  esac
}

case_hidden() { # the fixture is the judge target: no step changes it
  [ -z "$(git -C "$1" status --porcelain)" ] && [ "$(git -C "$1" rev-parse HEAD)" = "$BASE0" ]
}
case_kit_only() { case_hidden "$1" "$2"; }

# the judge for the reports
research_judge() { # <run-dir> <repo>: prints FAIL lines
  local run=$1 repo=$2 rd od
  rd=$(ls -d "$run"/steps/[0-9][0-9]-research | head -1); od=$(ls -d "$run"/steps/[0-9][0-9]-options | tail -1)
  python3 - "$rd/final.txt" "$od/final.txt" "$repo" <<'R'
import os, re, sys
research, options, repo = (open(sys.argv[1], encoding="utf-8").read(), open(sys.argv[2], encoding="utf-8").read(), sys.argv[3])
bad = []
def norm(s):  # whitespace-normalised, markdown markers (heading #, list dashes, emphasis, code ticks) ignored; the words must match in order
    s = re.sub(r"[#*`>]", " ", s)
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"(^| )[-\u2013\u2014]( |$)", " ", s)
    return re.sub(r"\s+", " ", s).strip()
# a citation is any file-like token (name.md / name.txt / name.py, optionally with a path and :line, :a-b or :a,b): it resolves from the
# repository root, else by its unique base name under vendor-docs/; a token that resolves nowhere is a bad citation
docs = {}
for root, _, names in os.walk(os.path.join(repo, "vendor-docs")):
    for n in names:
        docs.setdefault(n, []).append(os.path.join(root, n))
def resolve(tok):  # every file the token can mean: from the repository root, and by base name under vendor-docs/ (README.md is ambiguous)
    out = []
    full = os.path.join(repo, tok)
    if os.path.isfile(full):
        out.append(full)
    for c in docs.get(os.path.basename(tok), []):
        if c not in out and (tok == os.path.basename(tok) or c.endswith("/" + tok.lstrip("./"))):
            out.append(c)
    return out
cited = set()
for line in research.splitlines():
    files = []
    for m in re.finditer(r"(?<![A-Za-z0-9_])((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_-][A-Za-z0-9_.-]*\.(?:md|txt|py))(?::(\d+(?:[-,]\d+)*))?", line):
        tok, ln = m.group(1), m.group(2)
        cands = resolve(tok)
        if not cands:
            bad.append("the cited path does not exist in the fixture: %s" % tok)
            continue
        files.extend(cands)
        cited.update(c for c in cands if "vendor-docs" in c)
        if ln and not any(all(1 <= int(x) <= len(open(c, encoding="utf-8").read().splitlines()) for x in re.split(r"[-,]", ln)) for c in cands):
            bad.append("the cited line %s is outside %s" % (ln, tok))
    blob = norm(" ".join(open(f, encoding="utf-8").read() for f in files))
    for q in re.findall(r"[\"\u201c]([^\"\u201d]{20,})[\"\u201d]", line) if files else []:
        if "..." in q or "\u2026" in q:
            continue
        if norm(q) not in blob:
            bad.append("a quoted passage is not verbatim in the cited file: %r" % q[:80])
if len(cited) < 3:
    bad.append("the research report cites only %d vendor-docs file(s); at least 3 are needed" % len(cited))
if "2.3.1" not in research:
    bad.append("the report never states the pinned version 2.3.1 (requirements.txt)")
if "at_least_once" not in research:
    bad.append("the report never names the at_least_once mode")
if not re.search(r"256 ?KiB|262144|256 ?KB", research):
    bad.append("the report does not give the 2.3.1 message size limit (256 KiB)")
if not re.search(r"idempotent", research, re.I):
    bad.append("the report never says consumers must be idempotent (redelivery duplicates)")
if re.search(r"(?<!not )(?<!no )(?<!not provide )(offers?|supports?|provides?) exactly-once", research, re.I) and not re.search(r"(does not|doesn.t|no|not|never|without) [^.\n]{0,40}exactly-once|exactly-once[^.\n]{0,40}(not|no|never)", research, re.I):
    bad.append("the report claims exactly-once delivery, which the docs rule out")
unv = [l for l in research.splitlines() if re.search(r"UNVERIFIED", l)]
unv_text = "\n".join(research.splitlines()[i] for i, l in enumerate(research.splitlines()) if "UNVERIFIED" in l)
tail = research[research.find("UNVERIFIED"):] if "UNVERIFIED" in research else ""
if not re.search(r"latency|p99", tail, re.I):
    bad.append("the p99 latency question is not marked UNVERIFIED (the docs are silent on it)")
# an option is DEFINED by a line that starts with its label (a list item or heading "A. ...", "Option B: ...", a table row "| C |"); a mention of
# a label in prose (for example a dropped option of the research report) is not an option on offer. A report that defines its options in one
# "Options:" line falls back to the labels named on that line.
labels = {a or b for a, b in re.findall(r"(?m)^[ \t#*|>-]*\**(?:Option ([A-Z0-9])|([A-D]))\**[:.)|]\**[ \t]", options)}
if not labels:
    labels = set(re.findall(r"\bOption ([A-Z0-9])\b", "\n".join(l for l in options.splitlines() if re.match(r"[ \t#*|>-]*\**Options?\b", l))))
if not 1 <= len(labels) <= 3:
    bad.append("the options report names %d option(s) %s (1 to 3 allowed)" % (len(labels), sorted(labels)))
recs = re.findall(r"(?mi)^[ \t#*|>-]*\**recommendation\**[:\s]", options)
if len(recs) != 1:
    bad.append("the options report has %d Recommendation line(s) (exactly 1 needed)" % len(recs))
print("\n".join(bad))
R
}

case_assert() { # <run-dir> <repo>
  local st=$1/data/workflow.json bad
  bad=$(research_judge "$1" "$2")
  [ -z "$bad" ] || { printf '%s\n' "$bad" | tr '\n' ';'; return 1; }
  jq -e --arg r "$CASE_DECIDE_REASON" '[.history[] | select(.step == "decide" and .outcome == "adopt")] | length == 1 and (.[0] | tojson | contains($r))' "$st" >/dev/null \
    || jq -e --arg r "$CASE_DECIDE_REASON" 'tojson | contains($r)' "$st" >/dev/null \
    || { echo "the decision reason is not recorded in the engine state"; return 1; }
  [ "$(cat "$1/steps/decision-decide.choice" 2>/dev/null)" = adopt ] || { echo "the driver did not answer the decide step with adopt"; return 1; }
  jq -e '[.history[] | select(.step == "challenge")] | length >= 1 and all(.[]; .valid == true)' "$st" >/dev/null || { echo "the challenge did not end in a valid verdict block"; return 1; }
}

case_canned() { # <role> <prompt-file> <cwd> (FAKE_MODE: nocite | four | guess)
  local role=$1 prompt=$2 cwd=$3 a b c d
  case $role in
    researcher)
      a=$(grep -n 'Current stable release' "$cwd/vendor-docs/quillmq/README.md" | cut -d: -f1)
      b=$(grep -n 'at_least_once`: a message' "$cwd/vendor-docs/quillmq/delivery.md" | cut -d: -f1)
      c=$(grep -n 'Maximum message size' "$cwd/vendor-docs/quillmq/limits.md" | cut -d: -f1)
      d=$(grep -n 'visibility timeout' "$cwd/vendor-docs/quillmq/delivery.md" | cut -d: -f1)
      printf 'status: done\nQuestion: adopt at_least_once? | feeds decision: adopt or keep the retry loop\nStack/versions: quillmq 2.3.1 (requirements.txt:1)\nAnswer: yes, 2.3.1 has at_least_once.\nFindings:\n| claim | source | version | confidence |\n'
      if [ "${FAKE_MODE:-}" = nocite ]; then
        printf '| 2.3.1 has at_least_once, limit 256 KiB, consumers must be idempotent | vendor-docs/quillmq/missing.md:3 "this passage is not in any file" | 2.3.1 | high |\n'
      else
        printf '| pinned version 2.3.1 | vendor-docs/quillmq/README.md:%s "Current stable release: 2.3.1." | 2.3.1 | high |\n' "$a"
        printf '| at_least_once exists since 2.2.0 | vendor-docs/quillmq/delivery.md:%s "a message stays on the queue until the consumer acknowledges it." | 2.3.1 | high |\n' "$b"
        printf '| limit is 256 KiB | vendor-docs/quillmq/limits.md:%s "Maximum message size: 256 KiB." | 2.3.1 | high |\n' "$c"
        printf '| redelivery after 30 s; consumers must be idempotent | vendor-docs/quillmq/delivery.md:%s | 2.3.1 | high |\n' "$d"
      fi
      if [ "${FAKE_MODE:-}" = guess ]; then printf 'p99 latency at 10k msgs/s is about 4 ms (high confidence).\nUNVERIFIED: none\n'
      else printf 'UNVERIFIED: the p99 delivery latency at 10k msgs/s (the docs say nothing about latency)\n'; fi
      printf 'Would change my mind: a benchmark | Cheapest experiment: load test\nOpen questions: none\nProposed beyond brief: none\nWritten to: returned inline\n' ;;
    architecture)
      printf 'status: done\nDecision: adopt at_least_once.\nConstraints: quillmq 2.3.1 (requirements.txt:1)\nCriteria: C1 delivery guarantee C2 deletability C3 duplicates handled\n'
      printf 'Options: Option A (adopt at_least_once; cost low; buys redelivery; forecloses nothing), Option B (keep the retry loop in worker.py)'
      if [ "${FAKE_MODE:-}" = four ]; then printf ', Option C (own queue), Option D (a hosted broker)'; fi
      printf '\nRecommendation: Option A - B keeps hand-rolled retry code.\nFirst step: switch the queue to at_least_once.\nBets: latency unverified -> load test\nOpen questions: none\nProposed beyond brief: none\n' ;;
    tenth-man)
      printf 'Claim: adopt at_least_once. No material objection; watch duplicate handling.\n\n```verdict\n'
      jq -nc '{verdict: "PASS", feedback: [{id: "TM-1", severity: "OPTIONAL", what: "make consumers idempotent before switching (docs: redelivery duplicates)", where: "options report, recommendation"}]}'
      printf '```\n' ;;
  esac
}
