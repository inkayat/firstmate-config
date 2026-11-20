#!/usr/bin/env bash
# LIVE case: code-reviewer (skills code-review-and-quality, ponytail-review, karpathy-guidelines).
# Trap: the patch changes apply_discount()'s return type and fixes checkout.py, but
#   report.py (not in the patch) still formats a float -> TypeError at runtime.
#
# Graded against the ROLE CONTRACT (roles/code-reviewer/ROLE.md), not a skill template:
#   - repo untouched (read-only role; changes are judged against the fixture commit);
#   - the final report ends with a VALID verdict block (bin/fm-workflow verdict: .valid true) whose verdict is FAIL
#     and whose BLOCKER (or IMPORTANT) feedback item names the unpatched caller report.py. The role contract makes both
#     blocking (FAIL = at least one BLOCKER/IMPORTANT) and ROLE.md does not draw the line between them; 1 of 5 live runs
#     called the crash IMPORTANT, so the judge accepts either rather than grading severity taste;
#   - the skill templates the body disowns do NOT appear: "Verdict: Ship"/"Verdict: fix N" and "Lean: -N lines"
#     (ROLE.md: 'Their output templates (groups, numbering, "Verdict: Ship", "Lean: -N lines", "Not checked:") do not
#     apply: the Final report section is the only shape').
# The old grader demanded ponytail-review's literal `What this change does:` / `If we skip it:`. The rewritten body
# overrides that template on purpose, so a worker that follows its role correctly no longer writes them.
#
# The role body carries this behaviour ON PURPOSE, so the control (role body, no skills) may pass; CASE_BODY_PHRASE
# is checked against ROLE.md offline. The lines that carry it (roles/code-reviewer/ROLE.md):
#   Working shape 5: "Look where grep stops: ... other readers of the same bytes ... Never invent a caller"
#   Working shape 8: "Flag the CLASS of a bug and put the grep that finds every instance in `what`"
#   Final report:    "Then exactly one fenced `verdict` block as the last thing, nothing after its closing fence"
# The skills are still autoloaded and must still be READ (read check stays mandatory).
CASE_KIND=role
CASE_ROLE=code-reviewer
CASE_SKILL_ONLY_TOKENS="Verdict: Lean:"
CASE_BODY_PHRASE='exactly one fenced `verdict` block as the last thing'
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
  local v
  [ -z "$(changed_files)" ] || { echo "repo was edited: $(changed_files | tr '\n' ' ')"; return 1; }
  v=$("$CONFIG_ROOT/bin/fm-workflow" verdict "$RUN/final.txt" 2>/dev/null) || true
  printf '%s' "$v" | jq -e '.valid == true' >/dev/null 2>&1 \
    || { echo "final report does not end with a valid verdict block: $(printf '%s' "$v" | jq -c '.problems' 2>/dev/null)"; return 1; }
  printf '%s' "$v" | jq -e '.verdict == "FAIL"' >/dev/null 2>&1 \
    || { echo "verdict is $(printf '%s' "$v" | jq -r '.verdict'), not FAIL, for a change that breaks report.py"; return 1; }
  printf '%s' "$v" | jq -e '[.feedback[] | select((.severity == "BLOCKER" or .severity == "IMPORTANT") and ((.where + " " + .what) | test("report\\.py")))] | length > 0' >/dev/null 2>&1 \
    || { echo "no BLOCKER/IMPORTANT feedback item names the unpatched caller report.py"; return 1; }
  final_lacks 'Verdict: *(Ship|fix [0-9])|Lean: *-' || { echo "a disowned skill template (Verdict: Ship / Lean: -N lines) leaked into the report"; return 1; }
  echo "valid FAIL verdict block with a BLOCKER on report.py, no disowned skill template, repo untouched"
}

case_canned() { # <role> good|bad
  local mode=$2 sha
  sha=$(git rev-parse --short HEAD)
  if [ "$mode" = good ]; then
    printf 'read\t{"path":"/home/x/.agents/skills/code-review-and-quality/SKILL.md"}\nread\t{"path":"/home/x/.agents/skills/ponytail-review/SKILL.md"}\nread\t{"path":"/home/x/.agents/skills/karpathy-guidelines/SKILL.md"}\ngrep\t{"pattern":"apply_discount"}\n' > "$RUN/calls.tsv"
    {
      printf 'Head commit %s. Standards axis: no project rules documented. Spec axis: the change breaks a caller it does not touch.\n\n' "$sha"
      printf '**REV-1 BLOCKER** report.py:6-7 still formats the dict returned by apply_discount() with :.2f (TypeError on the first order; read, and grep shows three uses).\n\n'
      printf 'Counts: BLOCKER 1, IMPORTANT 0, OPTIONAL 0. Not merge-ready: fix REV-1 first.\n\n'
      printf '```verdict\n'
      printf '{"verdict":"FAIL","commit":"%s","feedback":[{"id":"REV-1","severity":"BLOCKER","class":"unpatched-caller","what":"report.py formats the dict result with :.2f and raises TypeError; fix every instance: rg apply_discount","where":"report.py:6"}]}\n' "$sha"
      printf '```\n'
    } > "$RUN/final.txt"
  else
    printf 'read\t{"path":"change.patch"}\nread\t{"path":"pricing.py"}\n' > "$RUN/calls.tsv"
    cat > "$RUN/final.txt" <<'R'
Review: the dict return is fine for checkout.py.
IMPORTANT: add a test for apply_discount. OPTIONAL: rename saved.
Counts: BLOCKER 0, IMPORTANT 1, OPTIONAL 1. Verdict: Ship.
R
  fi
}
