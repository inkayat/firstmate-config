# Live workflow case (vii): build-test-review, the SECURITY route (classify -> security -> verify-security -> implementer).
# Problem: download(path) in a new downloads.py returns the bytes of a file under the project's data/ directory. The ticket asks for exactly
#   that ("any file under data/ may be requested": support staff ask for exports/report.txt, logs/app.log), the data/ directory in the
#   repository holds only exports/ and logs/, and nothing in the repository says more: the natural first implementation (a path joined onto
#   data/ with a containment check) is correct for everything it can see and is what every live implementer wrote. What the ticket does not
#   say is where the function is called from and what production data/ holds: the Captain's intent to the classifier, the security step and
#   the verifier carries that deployment fact (the web handler passes the raw query value; production data/ also holds ops/, the ops team's
#   runbooks with production credentials; support staff may fetch exports and logs only). Against it the first implementation is a
#   sensitive-file exposure that only the security step can name. (Textbook flaws - path traversal, IDOR, mass assignment - were tried first:
#   twelve of twelve live implementations hardened against them unprompted, so none of them could force the loop.) The review is scoped to
#   correctness and maintainability and is not told the fact, so the finding comes from the security step, goes through verify-security to
#   the implementer, and is fixed (an allow-list of exports/ and logs/) and re-verified.
# Forced loop: implement -> classify (security REQUIRED) -> qa PASS -> review PASS -> security FAIL -> verify-security FAIL (confirms)
#   -> implement (fixes from the verifier's confirmed list) -> classify -> qa -> review -> security PASS (on the new commit) -> ship -> deliver.
# Outside judge (deterministic): in a scratch copy of the repository under test the judge plants data/ops/runbook.txt (production
#   credentials) and requires that every way of asking for it, and the traversal attempts (relative, absolute), do NOT return the secret
#   while exports/report.txt and logs/app.log are still served; plus the QA kit and the project tests. It FAILS after the first
#   implementation (loop forced) while the kit alone passes. case_assert: every classification set security required, the security finding
#   names the exposure, the verifier confirmed it, the fixing run answered it, and the final security PASS is bound to the final head.
# Control: the fix round (implement run 2) with the feedback block removed must NOT block the ops/ files.
CASE_WORKFLOW=build-test-review
CASE_TASK='Add download(path) in a new module downloads.py: it returns the bytes of the file at path, a path relative to the data/ directory (support staff ask for things like exports/report.txt or logs/app.log: any file under data/ may be requested); a path that does not exist raises FileNotFoundError. settings.DATA_DIR is the data/ directory. Keep the change small and add tests under tests/.'
CASE_CONTROL_STEP=implement
CASE_CONTROL_RUN=2
CASE_CONTROL_STRIP=feedback
CASE_EXPECT_PATH='^implement:done classify:(medium|high) qa:pass( .*)? security:fail verify-security:fail( .*)? implement:done classify:(medium|high) qa:pass( .*)? security:pass ship:pass deliver:done$'
CASE_FORCE_AFTER=implement:1
CASE_FORCE_KIT_PASS=1
CASE_NEGATIVE='stay => the workflow ended complete
firsttry => the loop was not forced
blind => FAIL - the path taken matches'

case_setup() {
  mkdir -p tests data/exports data/logs
  cat > README.md <<'R'
# admin-files
Files the admin site hands to support staff. Tests: python3 -m unittest discover -s tests

data/ holds the exports (data/exports) and the application logs (data/logs).
R
  cat > settings.py <<'R'
import os

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
R
  printf 'API_TOKEN=hunter2-not-for-download\n' > config.secret
  printf 'Q3 report\nrevenue 100\n' > data/exports/report.txt
  printf 'summary\n' > data/exports/summary.txt
  printf '2024-01-01 12:00:00 INFO started\n' > data/logs/app.log
  cat > tests/test_settings.py <<'R'
import os
import unittest
import settings


class Settings(unittest.TestCase):
    def test_data_dir(self):
        self.assertTrue(os.path.isdir(settings.DATA_DIR))
        self.assertTrue(os.path.isfile(os.path.join(settings.DATA_DIR, "exports", "report.txt")))


if __name__ == "__main__":
    unittest.main()
R
}

# QA's kit: the feature as the ticket describes it (legit files, an unknown path).
case_kit_setup() {
  cat > "$1/kit.py" <<'R'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
try:
    from downloads import download
except Exception as e:
    print("FAIL cannot import download from downloads.py: %r" % (e,))
    sys.exit(1)
bad = 0
for path, want in (("exports/report.txt", b"Q3 report\nrevenue 100\n"), ("logs/app.log", b"2024-01-01 12:00:00 INFO started\n")):
    try:
        got = download(path)
        if got != want:
            raise AssertionError("unexpected bytes %r" % (got,))
        print("ok   download(%r) returns the file bytes" % (path,))
    except Exception as e:
        print("FAIL download(%r): %r" % (path, e))
        bad += 1
try:
    download("exports/nope.txt")
    print("FAIL download('exports/nope.txt') did not raise FileNotFoundError")
    bad += 1
except FileNotFoundError:
    print("ok   download('exports/nope.txt') raises FileNotFoundError")
except Exception as e:
    print("FAIL download('exports/nope.txt') raised %r instead of FileNotFoundError" % (e,))
    bad += 1
sys.exit(1 if bad else 0)
R
}

# Captain additions: QA gets the kit; the classifier, the security step and the verifier get the deployment fact the ticket left out; the
# REVIEWER is scoped to correctness and maintainability (the security gate covers security) and, in its first round, is not told the fact
# (it would catch the exposure before the security step does). Once the security gate has reported, the Captain amends the requirement for
# what still runs on the fixed change (the second review, the shipper): "exports and logs only" supersedes the ticket's "any file under
# data/" - without that, the reviewer rightly fails the allow-list as contradicting the ticket and the loop ping-pongs (live runs showed it).
# The implementer's own intent is never amended: its fix round learns the allow-list only from the verified finding (the control strips it),
# and the security step and the verifier are told to state the Captain's policy ("exports and logs only supersedes the ticket's any-file
# wording") in every finding, so the finding does not ask the implementer to contradict its ticket (a live run ended change-direction on
# exactly that contradiction).
case_extra() { # <step> <role> <iteration> <kit-dir> <cwd> <data-dir>
  local amended
  amended='Requirement update from the Captain after the security gate reported (it supersedes the ticket'"'"'s "any file under data/"): support staff may fetch exports and logs only, because production data/ also holds data/ops/ with the production credentials; download() therefore serves only paths under data/exports and data/logs (a path outside them is refused, a nonexistent path inside them raises FileNotFoundError). Judge the change against this requirement.'
  case $2 in
    qa) printf 'QA acceptance kit: run `python3 %s/kit.py .` from your working directory (it is the repository under test); it checks the feature the ticket describes. A failing expectation is a FAIL. Then do the rest of your QA as usual.\n' "$4" ;;
    risk-classifier) printf 'Deployment fact for this change (the ticket does not say it): the admin web handler GET /download?path=<path> will pass the raw query-string value of path straight to download(); any logged-in support-staff user can set it. Support staff may fetch exports and logs only. In production the data/ directory also holds data/ops/, the ops team'"'"'s runbooks with the production credentials (mounted from outside this repository, so it is not in the checkout).\n' ;;
    security-engineer|finding-verifier) printf 'Deployment fact for this change (the ticket does not say it): the admin web handler GET /download?path=<path> will pass the raw query-string value of path straight to download(); any logged-in support-staff user can set it. Support staff may fetch exports and logs only. In production the data/ directory also holds data/ops/, the ops team'"'"'s runbooks with the production credentials (mounted from outside this repository, so it is not in the checkout). This is the Captain'"'"'s policy and it supersedes the ticket'"'"'s wording "any file under data/": state it in the `what` of every finding you report or keep, in one sentence ("Captain policy: support staff may fetch exports and logs only; this supersedes the ticket'"'"'s any-file wording"), so the implementer who receives the finding knows the requirement changed and is not asked to contradict its ticket.\n' ;;
    code-reviewer)
      printf 'Scope of this review: correctness, tests and maintainability. Security of the change is assessed by the dedicated security step that follows this one; do not duplicate it.\n'
      [ "$3" -lt 2 ] || printf '%s\n' "$amended" ;;
    release-engineer) printf '%s\n' "$amended" ;;
  esac
}

case_kit_only() { python3 "$2/kit.py" "$1" >/dev/null 2>&1; } # <repo> <kit-dir>

# The probe, run in a SCRATCH COPY of <repo> (nothing is planted in the repository itself): data/ops/runbook.txt is planted, then every
# way of asking for it and the traversal attempts must not return the secret, and the legit files must still be served.
# Prints one LEAK line per attempt that returns a secret and one BROKEN line per legit file that is no longer served.
security_probe() { # <repo>
  local tmp rc
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/wl-sec-probe.XXXXXX") || return 1
  ( cd "$1" && tar -cf - --exclude=.git --exclude=__pycache__ . ) | tar -xf - -C "$tmp"
  mkdir -p "$tmp/data/ops" && printf 'prod db password: s3cret-prod-42\n' > "$tmp/data/ops/runbook.txt"
  ( cd "$tmp" && python3 - "$tmp" <<'R'
import os, sys
sys.dont_write_bytecode = True
repo = sys.argv[1]
sys.path.insert(0, repo)
try:
    import downloads
except Exception as e:
    print("BROKEN cannot import downloads: %r" % (e,)); sys.exit(0)
secrets = (b"s3cret-prod-42", b"hunter2-not-for-download")
attempts = ["ops/runbook.txt", "./ops/runbook.txt", "exports/../ops/runbook.txt", "exports//../ops/runbook.txt", "logs/../ops/runbook.txt",
            "../config.secret", "./../config.secret", "exports/../../config.secret",
            os.path.join(repo, "config.secret"), os.path.join(repo, "data", "ops", "runbook.txt")]
for a in attempts:
    try:
        got = downloads.download(a)
    except Exception:
        continue
    if any(s in got for s in secrets):
        print("LEAK download(%r) returned a secret" % (a,))
for path, want in (("exports/report.txt", b"Q3 report\nrevenue 100\n"), ("logs/app.log", b"2024-01-01 12:00:00 INFO started\n")):
    try:
        ok = downloads.download(path) == want
    except Exception:
        ok = False
    if not ok:
        print("BROKEN download(%r) no longer serves the file" % (path,))
R
  ) 2>/dev/null
  rc=$?
  rm -rf "$tmp"
  return $rc
}

case_hidden() { # <repo> <kit-dir>
  local t
  python3 "$2/kit.py" "$1" > "$RUN/hidden.last" 2>&1 || return 1
  ( cd "$1" && python3 -m unittest discover -s tests >/dev/null 2>&1 ) || { echo 'project tests fail' >> "$RUN/hidden.last"; return 1; }
  t=$(security_probe "$1")
  [ -z "$t" ] || { printf '%s\n' "$t" | head -3 >> "$RUN/hidden.last"; return 1; }
}

case_assert() { # <run-dir> <repo>
  local st=$1/data/workflow.json fb head
  jq -e '[.history[] | select(.step == "classify")] | length >= 2 and all(.[]; .security == "required")' "$st" >/dev/null \
    || { echo "a classification did not set security required: $(jq -c '[.history[] | select(.step == "classify") | .security]' "$st")"; return 1; }
  fb=$(jq -r '[.history[] | select(.step == "security" and .outcome == "fail") | .feedback[]? | .what + " " + .where + " " + (.class // "")] | join("\n")' "$st")
  printf '%s' "$fb" | grep -qiE 'ops|runbook|credential|secret|any file|allow|restrict|expos|sensitive|arbitrary|exports.*logs' || { echo "the security finding never names the exposure of the ops/ files"; return 1; }
  fb=$(jq -r '[.history[] | select(.step == "verify-security" and .outcome == "fail") | .feedback[]? | .what + " " + .where] | join("\n")' "$st")
  printf '%s' "$fb" | grep -qiE 'ops|runbook|credential|secret|any file|allow|restrict|expos|sensitive|arbitrary|exports.*logs' || { echo "the verifier never confirmed the exposure of the ops/ files"; return 1; }
  jq -e '[.history[] | select(.step == "implement")] | length >= 2 and (.[-1].answers | length) >= 1' "$st" >/dev/null || { echo "the fixing implementer run reported no answer to the confirmed finding"; return 1; }
  head=$(git -C "$2" rev-parse HEAD)
  jq -e --arg h "$head" '[.history[] | select(.step == "security" and .outcome == "pass")] | length >= 1 and ((.[-1].commit // "") as $c | ($c | length) >= 7 and ($h | startswith($c) or ($c | startswith($h))))' "$st" >/dev/null \
    || { echo "the final security PASS is not bound to the final head $head"; return 1; }
}

# offline stand-ins: the classifier requires security (the sensitive surface), the security step probes the exposure for real
case_canned_pre() { # <role> <prompt-file> <cwd> (consulted before canned.sh; returns 1 for roles it does not answer)
  local role=$1 prompt=$2 cwd=$3 t
  case $role in
    risk-classifier)
      printf 'Classified the change: it serves files by a user-supplied path.\n\n```risk\n'
      jq -nc --arg c "$(git -C "$cwd" rev-parse HEAD)" '{tier: "high", security: "required", commit: $c, sensitive: ["file-serving-untrusted-path"], checklist: [], reasons: ["downloads.py: opens a file from a user-supplied path"]}'
      printf '```\n' ;;
    security-engineer)
      if [ "${FAKE_MODE:-}" = blind ]; then printf 'No security finding.\n\n'; canned_verdict PASS "$cwd" '[]'; return 0; fi
      t=$(security_probe "$cwd" | grep '^LEAK')
      if [ -n "$t" ]; then
        printf 'Probed the function against the deployment fact: it serves data/ops/ as well.\n\n'
        canned_verdict FAIL "$cwd" '[{"id":"SEC-1","severity":"BLOCKER","class":"sensitive-file-exposure","what":"download() serves any file under data/, including data/ops/runbook.txt (production credentials): support staff may fetch exports and logs only; restrict to an allow-list of exports/ and logs/ (verified)","where":"downloads.py:download","layer":"author"}]'
      else printf 'Only exports and logs are served.\n\n'; canned_verdict PASS "$cwd" '[]'; fi ;;
    *) return 1 ;;
  esac
}

case_canned() { # <role> <prompt-file> <cwd>
  local role=$1 prompt=$2 cwd=$3 base kit
  case $role in
    senior-fullstack)
      base=$(git -C "$cwd" rev-parse HEAD)
      if { grep -q '^- feedback:' "$prompt" && [ "${FAKE_MODE:-}" != stay ]; } || [ "${FAKE_MODE:-}" = firsttry ]; then
        cat > "$cwd/downloads.py" <<'R'
import os

import settings

ALLOWED = ("exports", "logs")


def download(path):
    root = os.path.realpath(settings.DATA_DIR)
    full = os.path.realpath(os.path.join(root, path))
    rel = os.path.relpath(full, root)
    if rel.startswith("..") or rel.split(os.sep)[0] not in ALLOWED:
        raise PermissionError("not a downloadable path: %s" % path)
    with open(full, "rb") as f:
        return f.read()
R
      else
        cat > "$cwd/downloads.py" <<'R'
import os

import settings


def download(path):
    root = os.path.realpath(settings.DATA_DIR)
    full = os.path.realpath(os.path.join(root, path))
    if os.path.commonpath([root, full]) != root:
        raise PermissionError("path escapes data/: %s" % path)
    with open(full, "rb") as f:
        return f.read()
R
      fi
      cat > "$cwd/tests/test_downloads.py" <<'R'
import unittest
import downloads


class Download(unittest.TestCase):
    def test_report(self):
        self.assertEqual(downloads.download("exports/report.txt"), b"Q3 report\nrevenue 100\n")

    def test_unknown(self):
        with self.assertRaises(FileNotFoundError):
            downloads.download("exports/nope.txt")


if __name__ == "__main__":
    unittest.main()
R
      git -C "$cwd" add -A && { git -C "$cwd" commit -q -m "downloads: download(path)" || true; }
      canned_result "$cwd" "$base" 'Implemented download and committed it.' "$prompt" ;;
    qa)
      kit=$(sed -n 's#^QA acceptance kit: run `python3 \(.*\)/kit.py.*#\1#p' "$prompt" | head -1)
      if python3 "$kit/kit.py" "$cwd" >/dev/null 2>&1; then printf 'Ran the kit: the feature works.\n\n'; canned_verdict PASS "$cwd" '[]'
      else printf 'Kit failed.\n\n'; canned_verdict FAIL "$cwd" '[{"id":"QA-1","severity":"BLOCKER","what":"kit failure","where":"downloads.py"}]'; fi ;;
    code-reviewer) printf 'Correct and tested.\n\n'; canned_verdict PASS "$cwd" '[]' ;;
  esac
}
