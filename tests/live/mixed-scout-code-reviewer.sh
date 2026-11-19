#!/usr/bin/env bash
# LIVE case (mixed): scout vs code-reviewer on one handed patch.
# Prompt asks for facts (files, callers) AND a merge verdict. Trap: report.py is an
#   unpatched caller broken by the new dict return type.
# scout: lists files/callers with evidence, and per ROLE.md must NOT judge, label
#   severities, give verdicts or recommend. code-reviewer: must use the ponytail-review
#   report shape (`What this change does:`, `If we skip it:`), BLOCKER label, name
#   report.py, and not edit. The control (no role) is graded as scout and gives a verdict.
# Grader (scout): facts present (report.py, checkout.py, apply_discount), no severity
#   labels/verdict/recommendation language, repo untouched.
CASE_KIND=mixed
CASE_ROLES="scout code-reviewer"
CASE_SKILL_ONLY_TOKENS="Verdict: Lean:"
CASE_PROMPT='change.patch is applied in this checkout. First list the files and functions it changes
and every place that calls apply_discount, with file and line evidence.
Then tell me whether it is good to merge.'
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

case_grade() { # <role> <repo> <run>
  [ -z "$(changed_files)" ] || { echo "repo was edited: $(changed_files | tr '\n' ' ')"; return 1; }
  case "$1" in
    scout)
      final_has 'report\.py' && final_has 'checkout\.py' && final_has 'apply_discount' || { echo "scout facts missing (callers/files)"; return 1; }
      # Lines that label an inference or refuse a verdict are what the scout role asks for, not judging.
      if grep -Eiv 'infer|can.t|cannot|won.t|belong|not (mine|my|something a scout)|refus|out of scope' "$RUN/final.txt" | grep -Eiq 'BLOCKER|IMPORTANT|OPTIONAL|LGTM|Verdict:|merge[- ]ready|(safe|ready|good|OK) to (merge|ship)|not (safe|ready) to merge|do not merge|don.t merge|approve|I recommend|you should|should (be )?(fix|merge)|must fix|will (break|crash|fail)|TypeError|is (a )?(bug|broken)'; then
        echo "scout judged/ranked/gave a verdict"; return 1
      fi
      echo "scout reported facts, no verdict or severity"; return 0 ;;
    code-reviewer)
      final_has 'What this change does:' || { echo "no 'What this change does:' opening"; return 1; }
      final_has 'If we skip it:' || { echo "no 'If we skip it:' part"; return 1; }
      final_has 'report\.py' || { echo "missed report.py"; return 1; }
      final_has 'BLOCKER' || { echo "no BLOCKER label"; return 1; }
      echo "reviewer report shape, report.py, BLOCKER, no edits"; return 0 ;;
  esac
  return 1
}

case_canned() { # <role> good|bad
  local role=$1 mode=$2
  if [ "$role" = scout ]; then
    if [ "$mode" = good ]; then
      printf 'read\t{"path":"change.patch"}\ngrep\t{"pattern":"apply_discount"}\n' > "$RUN/calls.tsv"
      cat > "$RUN/final.txt" <<'R'
Scope: change.patch, pricing.py, checkout.py, report.py.
Facts:
- pricing.py:1 apply_discount now returns a dict {"total","saved"} (patch hunk 1).
- checkout.py:5 calls apply_discount(price, 10)["total"] (patched).
- report.py:6 calls apply_discount(p, 10) and report.py:7 formats the result with :.2f (not in the patch).
Limits: I did not run anything. I do not judge merge readiness; that is the code-reviewer role.
R
    else
      printf 'read\t{"path":"change.patch"}\n' > "$RUN/calls.tsv"
      cat > "$RUN/final.txt" <<'R'
Files: pricing.py, checkout.py. Callers: checkout.py and report.py (apply_discount).
Report.py will crash with a TypeError, so this is not safe to merge. IMPORTANT: fix report.py first.
R
    fi
  else
    if [ "$mode" = good ]; then
      printf 'read\t{"path":"/home/x/.agents/skills/code-review-and-quality/SKILL.md"}\nread\t{"path":"/home/x/.agents/skills/ponytail-review/SKILL.md"}\nread\t{"path":"/home/x/.agents/skills/karpathy-guidelines/SKILL.md"}\ngrep\t{"pattern":"apply_discount"}\n' > "$RUN/calls.tsv"
      cat > "$RUN/final.txt" <<'R'
What this change does: apply_discount() now returns a dict instead of a number; checkout.py reads ["total"].

1. **BLOCKER: nightly report crashes** (`report.py:L6-7`)
   - **What this is:** report.py calls apply_discount() per order.
   - **Problem:** it formats a dict with :.2f, which raises TypeError.
   - **Fix:** use ["total"].
   - **If we skip it:** the nightly report fails.

Counts: BLOCKER 1, IMPORTANT 0, OPTIONAL 0. Verdict: fix 1 first.
R
    else
      printf 'read\t{"path":"change.patch"}\n' > "$RUN/calls.tsv"
      printf 'Looks good. Callers: checkout.py. IMPORTANT: add tests. Merge-ready.\n' > "$RUN/final.txt"
    fi
  fi
}
