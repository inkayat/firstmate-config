#!/usr/bin/env bash
# LIVE case: code-reviewer (skills code-review-and-quality, ponytail-review).
# Trap: the patch changes apply_discount()'s return type and fixes checkout.py, but
#   report.py (not in the patch) still formats a float. The ponytail-review skill
#   alone defines the report shape: it opens with `What this change does:` and gives
#   every finding a `If we skip it:` part (ROLE.md only names BLOCKER/IMPORTANT/OPTIONAL).
# Control (role, no skills) writes a plain BLOCKER/IMPORTANT list with neither marker.
# Grader accepts: both skill markers, the missed caller report.py named, a BLOCKER
#   label, and an unchanged repo (read-only role).
CASE_KIND=role
CASE_ROLE=code-reviewer
CASE_SKILL_ONLY_TOKENS="Verdict: Lean:"
CASE_PROMPT='change.patch is applied in this checkout. Review it before I merge it tonight.
Give me your review.'
# Shared fixture: change.patch changes apply_discount() from returning a float to
# returning a dict and updates checkout.py, but report.py (not in the patch) still
# formats the result as a float -> TypeError at runtime.
_fixture() {
  cat > README.md <<'R'
# shop
Nightly job: report.py prints the discounted price of every order. Checkout runs per request.
R
  cat > pricing.py <<'R'
def apply_discount(price, pct):
    saved = round(price * pct / 100, 2)
    return {"total": round(price - saved, 2), "saved": saved}
R
  cat > checkout.py <<'R'
from pricing import apply_discount


def checkout_total(price):
    return apply_discount(price, 10)["total"]
R
  cat > report.py <<'R'
from pricing import apply_discount


def report(prices):
    for p in prices:
        total = apply_discount(p, 10)
        print(f"{p:.2f} -> {total:.2f}")
R
  cat > change.patch <<'R'
diff --git a/pricing.py b/pricing.py
--- a/pricing.py
+++ b/pricing.py
@@ -1,3 +1,4 @@
 def apply_discount(price, pct):
-    return round(price - price * pct / 100, 2)
+    saved = round(price * pct / 100, 2)
+    return {"total": round(price - saved, 2), "saved": saved}
diff --git a/checkout.py b/checkout.py
--- a/checkout.py
+++ b/checkout.py
@@ -2,3 +2,3 @@
 
 def checkout_total(price):
-    return apply_discount(price, 10)
+    return apply_discount(price, 10)["total"]
R
}

case_setup() { _fixture; }

case_grade() {
  [ -z "$(changed_files)" ] || { echo "repo was edited: $(changed_files | tr '\n' ' ')"; return 1; }
  final_has 'What this change does:' || { echo "no 'What this change does:' opening"; return 1; }
  final_has 'If we skip it:' || { echo "no 'If we skip it:' part on findings"; return 1; }
  final_has 'report\.py' || { echo "missed the unpatched caller report.py"; return 1; }
  final_has 'BLOCKER' || { echo "no BLOCKER label"; return 1; }
  echo "skill report shape present, caller report.py found, BLOCKER label, repo untouched"
}

case_canned() { # <role> good|bad
  local mode=$2
  if [ "$mode" = good ]; then
    printf 'read\t{"path":"/home/x/.agents/skills/code-review-and-quality/SKILL.md"}\nread\t{"path":"/home/x/.agents/skills/ponytail-review/SKILL.md"}\ngrep\t{"pattern":"apply_discount"}\n' > "$RUN/calls.tsv"
    cat > "$RUN/final.txt" <<'R'
What this change does: apply_discount() now returns a dict with total and saved instead of a number. checkout.py is updated to read ["total"].

1. **BLOCKER: nightly report crashes** (`report.py:L6-7`)
   - **What this is:** report.py calls apply_discount() for every order.
   - **Problem:** It still treats the result as a number. f"{total:.2f}" on a dict raises TypeError.
   - **Fix:** Use apply_discount(p, 10)["total"] in report.py.
   - **If we skip it:** The nightly report fails on the first order.

Counts: BLOCKER 1, IMPORTANT 0, OPTIONAL 0.
Verdict: fix 1 first, not merge-ready.
R
  else
    printf 'read\t{"path":"change.patch"}\nread\t{"path":"pricing.py"}\n' > "$RUN/calls.tsv"
    cat > "$RUN/final.txt" <<'R'
Review: the dict return is fine for checkout.py.
IMPORTANT: add a test for apply_discount. OPTIONAL: rename saved.
Counts: BLOCKER 0, IMPORTANT 1, OPTIONAL 1. Verdict: merge-ready.
R
  fi
}
