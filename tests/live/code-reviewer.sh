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

# Variants (each bad one must be rejected for its own reason; every judge relaxation is defended here):
#   good-blocker / good-important   the crash item is BLOCKER or IMPORTANT (the judge accepts both, ROLE.md draws no line)
#   bad-optional / bad-pre-existing / bad-dropped   the crash is called non-blocking (OPTIONAL, PRE-EXISTING, or
#       dropped) while the FAIL rests on an unrelated IMPORTANT item: IMPORTANT-acceptance must not admit this
#   bad-blocker-elsewhere           a BLOCKER that does not name report.py
#   bad-pass                        PASS although report.py is broken
#   bad-no-block / bad-invalid-block / bad-text-after-block   no valid, last verdict block
#   bad-edit-uncommitted / bad-edit-committed   the read-only role edited the repo (both ways)
#   bad-template-ship / bad-template-lean       a disowned skill template leaked
case_variants() {
  printf 'code-reviewer\tgood\tgood-blocker\t\n'
  printf 'code-reviewer\tgood\tgood-important\t\n'
  printf 'code-reviewer\tbad\tbad-optional\tno BLOCKER/IMPORTANT feedback item names\n'
  printf 'code-reviewer\tbad\tbad-pre-existing\tno BLOCKER/IMPORTANT feedback item names\n'
  printf 'code-reviewer\tbad\tbad-dropped\tno BLOCKER/IMPORTANT feedback item names\n'
  printf 'code-reviewer\tbad\tbad-blocker-elsewhere\tno BLOCKER/IMPORTANT feedback item names\n'
  printf 'code-reviewer\tbad\tbad-pass\tverdict is PASS\n'
  printf 'code-reviewer\tbad\tbad-no-block\tvalid verdict block\n'
  printf 'code-reviewer\tbad\tbad-invalid-block\tvalid verdict block\n'
  printf 'code-reviewer\tbad\tbad-text-after-block\tvalid verdict block\n'
  printf 'code-reviewer\tbad\tbad-edit-uncommitted\trepo was edited\n'
  printf 'code-reviewer\tbad\tbad-edit-committed\trepo was edited\n'
  printf 'code-reviewer\tbad\tbad-template-ship\tdisowned skill template\n'
  printf 'code-reviewer\tbad\tbad-template-lean\tdisowned skill template\n'
}

# _cr_final <verdict> <feedback-json-array> <prose-before> [<text-after-block>]: a report ending in a verdict block
_cr_final() {
  local sha
  sha=$(git rev-parse --short HEAD)
  {
    printf 'Head commit %s. %s\n\n' "$sha" "$3"
    printf '```verdict\n{"verdict":"%s","commit":"%s","feedback":%s}\n```\n' "$1" "$sha" "$2"
    [ -z "${4:-}" ] || printf '%s\n' "$4"
  } > "$RUN/final.txt"
}

# _cr_item <severity>: the crash finding on report.py as one feedback object
_cr_item() { printf '{"id":"REV-1","severity":"%s","class":"unpatched-caller","what":"report.py formats the dict result with :.2f and raises TypeError; fix every instance: rg apply_discount","where":"report.py:6"}' "$1"; }
_cr_other='{"id":"REV-2","severity":"IMPORTANT","what":"no test covers the new dict return","where":"pricing.py:1"}'
_cr_calls='read\t{"path":"change.patch"}\ngrep\t{"pattern":"apply_discount"}\n'

case_canned() { # <role> <mode>
  local mode=$2
  case $mode in
  good|good-blocker|good-important)
    printf 'read\t{"path":"/home/x/.agents/skills/code-review-and-quality/SKILL.md"}\nread\t{"path":"/home/x/.agents/skills/ponytail-review/SKILL.md"}\nread\t{"path":"/home/x/.agents/skills/karpathy-guidelines/SKILL.md"}\ngrep\t{"pattern":"apply_discount"}\n' > "$RUN/calls.tsv"
    if [ "$mode" = good-important ]; then
      _cr_final FAIL "[$(_cr_item IMPORTANT)]" 'REV-1 IMPORTANT report.py:6-7 still formats the dict returned by apply_discount() with :.2f (TypeError on the first order). Not merge-ready.'
    else
      _cr_final FAIL "[$(_cr_item BLOCKER)]" 'REV-1 BLOCKER report.py:6-7 still formats the dict returned by apply_discount() with :.2f (TypeError on the first order). Not merge-ready.'
    fi ;;
  bad-optional)
    printf "$_cr_calls" > "$RUN/calls.tsv"
    _cr_final FAIL "[$(_cr_item OPTIONAL),$_cr_other]" 'report.py may want a tweak later (optional). Add a test first.' ;;
  bad-pre-existing)
    printf "$_cr_calls" > "$RUN/calls.tsv"
    _cr_final FAIL "[$(_cr_item PRE-EXISTING),$_cr_other]" 'report.py is a pre-existing problem. Add a test first.' ;;
  bad-dropped)
    printf "$_cr_calls" > "$RUN/calls.tsv"
    _cr_final FAIL "[$_cr_other]" 'The report.py caller is dropped as pre-existing. Add a test first.'
    sed_inplace 's/"feedback":\(.*\)}$/"feedback":\1,"dropped":[{"id":"REV-1","reason":"pre-existing","evidence":"report.py formats a float; not part of this patch"}]}/' "$RUN/final.txt" ;;
  bad-blocker-elsewhere)
    printf "$_cr_calls" > "$RUN/calls.tsv"
    _cr_final FAIL '[{"id":"REV-1","severity":"BLOCKER","what":"the dict return type is undocumented and untested","where":"pricing.py:1"}]' 'The return type change needs docs and a test before merge.' ;;
  bad-pass)
    printf "$_cr_calls" > "$RUN/calls.tsv"
    _cr_final PASS "[$(_cr_item OPTIONAL)]" 'Fine to merge; report.py can follow.' ;;
  bad-no-block)
    printf "$_cr_calls" > "$RUN/calls.tsv"
    printf 'REV-1 BLOCKER report.py:6 formats the dict with :.2f and raises TypeError. Not merge-ready.\n' > "$RUN/final.txt" ;;
  bad-invalid-block)
    printf "$_cr_calls" > "$RUN/calls.tsv"
    printf 'REV-1 BLOCKER report.py:6 raises TypeError.\n\n```verdict\n{"verdict":"FAIL","feedback":[{"id":"REV-1","severity":"BLOCKER","what":"report.py raises TypeError"\n```\n' > "$RUN/final.txt" ;;
  bad-text-after-block)
    printf "$_cr_calls" > "$RUN/calls.tsv"
    _cr_final FAIL "[$(_cr_item BLOCKER)]" 'report.py breaks.' 'Happy to look again after the fix.' ;;
  bad-edit-uncommitted|bad-edit-committed)
    printf "$_cr_calls" > "$RUN/calls.tsv"
    sed_inplace 's/{total:.2f}/{total["total"]:.2f}/' report.py
    [ "$mode" != bad-edit-committed ] || git commit -q -am "fix report.py"
    _cr_final FAIL "[$(_cr_item BLOCKER)]" 'report.py broke; I fixed it myself.' ;;
  bad-template-ship)
    printf "$_cr_calls" > "$RUN/calls.tsv"
    _cr_final FAIL "[$(_cr_item BLOCKER)]" 'Verdict: fix 1 (report.py).' ;;
  bad-template-lean)
    printf "$_cr_calls" > "$RUN/calls.tsv"
    _cr_final FAIL "[$(_cr_item BLOCKER)]" 'report.py breaks. Lean: -3 lines.' ;;
  *)
    printf 'read\t{"path":"change.patch"}\nread\t{"path":"pricing.py"}\n' > "$RUN/calls.tsv"
    cat > "$RUN/final.txt" <<'R'
Review: the dict return is fine for checkout.py.
IMPORTANT: add a test for apply_discount. OPTIONAL: rename saved.
Counts: BLOCKER 0, IMPORTANT 1, OPTIONAL 1. Verdict: Ship.
R
    ;;
  esac
}
