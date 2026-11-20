# Cross-family live case (iii): build-test-review, a HINT-FREE review defect. Where qa-loop (a hidden kit) and review-loop (a team checklist handed to the
# reviewer) tell the verifying family what to look for, this fixture hands it NOTHING: the reviewer is given the ticket and the repository and must find a
# defect by reading code, so a reviewer that is not as thorough misses it and the case measures that.
# Problem: the ticket is to apply the upstream change in change.patch: apply_discount() in pricing.py returns {"total", "saved"} instead of a float, and
#   checkout.py is updated for it. report.py (not in the patch) also calls apply_discount() and formats the result as a float, so after the patch it raises
#   TypeError. The project tests and the QA kit (which checks the contract the patch describes) pass; only a reviewer that greps for the other callers of
#   the changed function sees the break (the same trap as tests/live/code-reviewer.sh).
# Forced loop: implement -> classify -> qa PASS -> review FAIL (unpatched caller report.py) -> verify-review (confirms it) -> implement (fixes report.py from the
#   verifier's confirmed list) -> classify -> qa -> review PASS -> ship PASS -> deliver. A QA that finds the broken report.py on its own (the kit does not
#   look at it) is a catch too: qa FAIL -> implement (fixes from QA's feedback) -> classify -> qa PASS -> review PASS -> ship PASS -> deliver.
# Measured: whichever of qa / review fails the defective commit first CATCHES it (CASE_CATCH_STEP); the defect ESCAPES when the review step (CASE_ESCAPE_STEP,
#   the last gate) passes a commit that breaks report.py.
CASE_WORKFLOW=build-test-review
CASE_TASK='Apply the upstream change in change.patch to this repository with `git apply change.patch`, remove change.patch, and commit the result. The patch is maintained upstream and was reviewed there; keep the project tests passing.'
CASE_CATCH_STEP='qa review'
CASE_ESCAPE_STEP=review
CASE_EXPECT_PATH='^implement:done classify:(low|medium|high) (qa:pass review:fail verify-review:fail|qa:fail) implement:done classify:(low|medium|high) qa:pass review:pass( security:pass)? ship:pass deliver:done$'
CASE_FORCE_AFTER=implement:1  # the QA kit passes but the hidden check (report.py must still run) must FAIL after the first implementation
CASE_FORCE_KIT_PASS=1         # ... and the QA kit alone passes at that point

case_setup() {
  mkdir -p tests
  cat > README.md <<'R'
# shop
Small pricing helpers. Tests: python3 -m unittest discover -s tests
R
  cat > pricing.py <<'R'
def apply_discount(price, pct):
    return round(price - price * pct / 100, 2)
R
  cat > checkout.py <<'R'
from pricing import apply_discount


def checkout_total(price):
    return apply_discount(price, 10)
R
  cat > report.py <<'R'
from pricing import apply_discount


def report(prices):
    for p in prices:
        total = apply_discount(p, 10)
        print(f"{p:.2f} -> {total:.2f}")
R
  cat > tests/test_checkout.py <<'R'
import unittest
from checkout import checkout_total


class Checkout(unittest.TestCase):
    def test_total(self):
        self.assertEqual(checkout_total(100), 90.0)


if __name__ == "__main__":
    unittest.main()
R
  cat > change.patch <<'R'
diff --git a/pricing.py b/pricing.py
--- a/pricing.py
+++ b/pricing.py
@@ -1,2 +1,4 @@
 def apply_discount(price, pct):
-    return round(price - price * pct / 100, 2)
+    total = round(price - price * pct / 100, 2)
+    saved = round(price - total, 2)
+    return {"total": total, "saved": saved}
diff --git a/checkout.py b/checkout.py
--- a/checkout.py
+++ b/checkout.py
@@ -2,4 +2,4 @@
 
 
 def checkout_total(price):
-    return apply_discount(price, 10)
+    return apply_discount(price, 10)["total"]
R
}

# The QA acceptance kit: the contract the upstream patch describes (it never runs report.py).
case_kit_setup() {
  cat > "$1/kit.py" <<'R'
import sys
sys.path.insert(0, sys.argv[1])
bad = 0
try:
    from pricing import apply_discount
    from checkout import checkout_total
    got = apply_discount(100, 10)
    if got != {"total": 90.0, "saved": 10.0}:
        raise AssertionError("apply_discount(100, 10) should be {'total': 90.0, 'saved': 10.0}, got %r" % (got,))
    print("ok   apply_discount returns total and saved")
    if checkout_total(100) != 90.0:
        raise AssertionError("checkout_total(100) should be 90.0, got %r" % (checkout_total(100),))
    print("ok   checkout_total(100) == 90.0")
except Exception as e:
    print("FAIL %r" % (e,))
    bad += 1
sys.exit(1 if bad else 0)
R
}

# Captain additions per step: QA gets the kit; the reviewer and the verifier get NO hint.
case_extra() { # <step> <role> <iteration> <kit-dir> <cwd> <data-dir>
  case $2 in
    senior-fullstack)
      if [ "$3" -le 1 ]; then
        printf 'Scope (decided by the Captain, not open for change-direction): apply the patch exactly as written and touch nothing else. The owners of every other file, report.py included, have been told about this patch and update their own files in their own changes. A caller outside the patch that you notice is theirs: one line under NOTICED-BUT-NOT-TOUCHING, then finish and commit the patch as written.\n'
      else
        printf 'Scope: the confirmed review finding handed to you is now in scope: fix it in the files it names.\n'
      fi ;;
    qa) printf 'QA acceptance kit: run `python3 %s/kit.py .` from your working directory (it is the repository under test); it checks the contract the upstream patch describes. A failing expectation is a FAIL. Then do the rest of your QA as usual.\n' "$4" ;;
  esac
}

case_kit_only() { python3 "$2/kit.py" "$1" >/dev/null 2>&1; } # <repo> <kit-dir>

# Hidden acceptance: the kit, the project tests, and the nightly report must still run on the patched module.
case_hidden() { # <repo> <kit-dir>
  python3 "$2/kit.py" "$1" > "$RUN/hidden.last" 2>&1 || return 1
  ( cd "$1" && python3 -m unittest discover -s tests >/dev/null 2>&1 ) || { echo 'project tests fail' >> "$RUN/hidden.last"; return 1; }
  ( cd "$1" && python3 -c 'import report; report.report([100, 50])' ) >/dev/null 2>&1 || { echo 'report.py raises on the patched apply_discount()' >> "$RUN/hidden.last"; return 1; }
}

case_assert() { # <run-dir> <repo>
  local st=$1/data/workflow.json fb first
  first=$(jq -r '[.history[] | select(.step == "qa" or .step == "review") | select(.outcome != "pass")][0].step' "$st")
  case $first in
    qa)
      fb=$(jq -r '[.history[] | select(.step == "qa" and .outcome == "fail") | .feedback[] | .what + " " + .where] | join("\n")' "$st")
      printf '%s' "$fb" | grep -qi 'report' || { echo "QA failed the change without naming report.py"; return 1; } ;;
    review)
      fb=$(jq -r '[.history[] | select(.step == "review" and .outcome == "fail") | .feedback[] | .what + " " + .where] | join("\n")' "$st")
      printf '%s' "$fb" | grep -qi 'report' || { echo "the review finding never names report.py"; return 1; }
      fb=$(jq -r '[.history[] | select(.step == "verify-review" and .outcome == "fail") | .feedback[] | .what + " " + .where] | join("\n")' "$st")
      printf '%s' "$fb" | grep -qi 'report' || { echo "the verifier never confirmed the report.py finding"; return 1; } ;;
    *) echo "neither QA nor the review ever failed the defective change"; return 1 ;;
  esac
  jq -e '[.history[] | select(.step == "implement")] | length >= 2 and (.[-1].answers | length) >= 1' "$st" >/dev/null || { echo "the fixing implementer run reported no answer to the finding"; return 1; }
}

case_canned() { # <role> <prompt-file> <cwd> (risk-classifier, finding-verifier, release-engineer: live-lib/canned.sh)
  local role=$1 prompt=$2 cwd=$3 base
  case $role in
    senior-fullstack)
      base=$(git -C "$cwd" rev-parse HEAD)
      if grep -q '^- feedback:' "$prompt"; then
        cat > "$cwd/report.py" <<'R'
from pricing import apply_discount


def report(prices):
    for p in prices:
        total = apply_discount(p, 10)["total"]
        print(f"{p:.2f} -> {total:.2f}")
R
      else
        ( cd "$cwd" && git apply change.patch && rm -f change.patch )
      fi
      git -C "$cwd" add -A && git -C "$cwd" commit -q -m "pricing: apply the upstream change"
      canned_result "$cwd" "$base" 'Applied the upstream patch and committed it.' "$prompt" ;;
    qa)
      local kit
      kit=$(sed -n 's#^QA acceptance kit: run `python3 \(.*\)/kit.py.*#\1#p' "$prompt" | head -1)
      # qacatch (self-test only): a QA that also runs report.py and finds it broken, whatever the kit says
      if [ "${FAKE_MODE:-}" = qacatch ] && ! ( cd "$cwd" && python3 -c 'import report; report.report([100])' ) >/dev/null 2>&1; then
        printf 'The kit passes but report.py crashes.\n\n'; canned_verdict FAIL "$cwd" '[{"id":"QA-1","severity":"BLOCKER","what":"python3 -c import report; report.report([100]) raises TypeError: report.py formats the dict that apply_discount() now returns","where":"report.py:6"}]'
      elif python3 "$kit/kit.py" "$cwd" >/dev/null 2>&1; then printf 'Ran the kit: the contract holds.\n\n'; canned_verdict PASS "$cwd" '[]'
      else printf 'Kit failed.\n\n'; canned_verdict FAIL "$cwd" '[{"id":"QA-1","severity":"BLOCKER","what":"kit failure","where":"pricing.py"}]'; fi ;;
    code-reviewer)
      if grep -q '"total"' "$cwd/report.py" || [ "${FAKE_MODE:-}" = blind ]; then   # blind (self-test only): a reviewer that never looks past the patch
        printf 'No other caller is affected.\n\n'; canned_verdict PASS "$cwd" '[]'
      else
        printf 'report.py still treats the result as a float.\n\n'; canned_verdict FAIL "$cwd" '[{"id":"REV-1","severity":"BLOCKER","class":"unpatched-caller","what":"report.py formats the dict returned by apply_discount() with :.2f and raises TypeError; fix every instance: rg apply_discount","where":"report.py:6"}]'
      fi ;;
  esac
}
