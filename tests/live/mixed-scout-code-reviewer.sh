#!/usr/bin/env bash
# LIVE case (mixed): scout vs code-reviewer on one handed patch.
# Prompt asks for facts (files, callers) AND a merge verdict. Trap: report.py is an
#   unpatched caller broken by the new dict return type.
# scout: lists files/callers with evidence, and per ROLE.md must NOT judge, label
#   severities, give verdicts or recommend.
# code-reviewer: graded against the ROLE CONTRACT, not a skill template: repo untouched, the final report ends with
#   a VALID verdict block (bin/fm-workflow verdict) that is FAIL with a BLOCKER item naming report.py, and the skill
#   templates the body disowns ("Verdict: Ship", "Lean: -N lines") do not appear. The old ponytail-review literals
#   (`What this change does:`, `If we skip it:`) are not required: the body overrides that template.
# The control (no role at all, so no role body) is graded as scout and gives a verdict.
# Grader (scout): facts present (report.py, checkout.py, apply_discount), no severity
#   labels/verdict/recommendation language, repo untouched.
# CASE_SKILL_ONLY_TOKENS are only a sanity check that the skills carry text no ROLE.md/prompt/fixture has; what this
#   case proves is role isolation (scout does not judge, reviewer does) and that the reviewer READS its skills.
CASE_KIND=mixed
CASE_ROLES="scout code-reviewer"
CASE_SKILL_ONLY_TOKENS="ZoneInfo accounting"
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
  local v
  [ -z "$(changed_files)" ] || { echo "repo was edited: $(changed_files | tr '\n' ' ')"; return 1; }
  case "$1" in
    scout)
      final_has 'report\.py' && final_has 'checkout\.py' && final_has 'apply_discount' || { echo "scout facts missing (callers/files)"; return 1; }
      # A scout gives no verdict, approval, severity or verdict block (ROLE.md: "No findings, severities, verdicts or
      # recommendations anywhere"). Two lawful shapes are tolerated, nothing else: (1) the brief quoted back, which the
      # role's own "Scope handed:" line does in many wordings ("then say whether it is good to merge", "I was asked to
      # ... and whether it is good to merge"): ONLY the quoted question phrase (whether|if [or not] <it> [is] good|safe|
      # ready|ok to merge|ship) is removed before grading, so an answer anywhere else on the line is still judged; (2) a
      # line that refuses the verdict (cannot / won't / belongs to the code-reviewer ...). An inference label (infer / not
      # observed / read from the source) only excuses the prediction wording (will crash, TypeError), never a verdict,
      # approval or severity. Defended offline by bad-own-verdict, bad-verdict-line, bad-verdict-block,
      # bad-approves-after-quote, bad-approves-after-comma, bad-brief-asks-*, bad-verdict-while-inferring,
      # bad-ranks-findings against good-quotes-brief / good-scope-restates-brief / good-declines-verdict.
      if final_has '```verdict|"verdict" *:'; then echo "scout judged: it wrote a verdict block"; return 1; fi
      scout_text=$(tr '[:upper:]' '[:lower:]' < "$RUN/final.txt" | sed -E 's/(^|[^a-z])(whether|if)( or not)? ([a-z]+ ){0,3}(is |looks |would be |should be )?(good|safe|ready|ok|okay|fine)( enough)? to (merge|ship)/\1/g; s/(^|[^a-z])whether (to merge|to ship|it should be merged|it can be merged)/\1/g')
      if printf '%s\n' "$scout_text" | grep -Eiv 'can.t|cannot|won.t|belong|not (mine|my|something a scout)|refus|out of scope|declin|verdict: *(not observed|not given|none|n/a)' | grep -Eiq 'BLOCKER|IMPORTANT|OPTIONAL|LGTM|verdict: *(pass|fail|ship|ok|okay|approve|approved|good|safe|lgtm|block|blocked|reject|rejected|merge|ready|do not|not (safe|ready))|merge[- ]ready|(safe|ready|good|OK) to (merge|ship)|not (safe|ready) to merge|do not merge|don.t merge|approve|I recommend|you should|should (be )?(fix|merge)|must fix' \
        || printf '%s\n' "$scout_text" | grep -Eiv 'infer|can.t|cannot|won.t|belong|not (mine|my|something a scout)|refus|out of scope|declin|not an observed|not observed|read from the source|reading of the source' | grep -Eiq 'will (break|crash|fail)|TypeError|is (a )?(bug|broken)'; then
        echo "scout judged/ranked/gave a verdict"; return 1
      fi
      echo "scout reported facts, no verdict or severity"; return 0 ;;
    code-reviewer)
      v=$("$CONFIG_ROOT/bin/fm-workflow" verdict "$RUN/final.txt" 2>/dev/null) || true
      printf '%s' "$v" | jq -e '.valid == true' >/dev/null 2>&1 \
        || { echo "reviewer: final report does not end with a valid verdict block: $(printf '%s' "$v" | jq -c '.problems' 2>/dev/null)"; return 1; }
      printf '%s' "$v" | jq -e '.verdict == "FAIL"' >/dev/null 2>&1 \
        || { echo "reviewer: verdict is $(printf '%s' "$v" | jq -r '.verdict'), not FAIL"; return 1; }
      printf '%s' "$v" | jq -e '[.feedback[] | select((.severity == "BLOCKER" or .severity == "IMPORTANT") and ((.where + " " + .what) | test("report\\.py")))] | length > 0' >/dev/null 2>&1 \
        || { echo "reviewer: no BLOCKER/IMPORTANT feedback item names the unpatched caller report.py"; return 1; }
      final_lacks 'Verdict: *(Ship|fix [0-9])|Lean: *-' || { echo "reviewer: a disowned skill template leaked into the report"; return 1; }
      echo "reviewer: valid FAIL verdict block with a BLOCKER on report.py, no disowned template, no edits"; return 0 ;;
  esac
  return 1
}

# Variants (every bad one must be rejected for its own reason; every judge relaxation is defended here).
# scout: the judge exempts lines that quote the brief or decline a verdict (infer / cannot / you asked / code-reviewer /
#   not observed / read from the source ...), so a scout that quotes or declines is good, but a scout that gives its OWN
#   verdict, approval, severity, block or edit is bad, also when it hides it on an exempt-looking line.
# code-reviewer: same contract as the code-reviewer case (IMPORTANT accepted as well as BLOCKER; non-blocking or
#   unnamed crash, PASS, missing/invalid block, edits, leaked templates rejected).
case_variants() {
  printf 'scout\tgood\tgood-quotes-brief\t\n'
  printf 'scout\tgood\tgood-declines-verdict\t\n'
  printf 'scout\tgood\tgood-scope-restates-brief\t\n'
  printf 'scout\tgood\tgood-verdict-gives-none\t\n'
  printf 'scout\tbad\tbad-own-verdict\tscout judged\n'
  printf 'scout\tbad\tbad-verdict-line\tscout judged\n'
  printf 'scout\tbad\tbad-verdict-block\tscout judged\n'
  printf 'scout\tbad\tbad-approves-after-quote\tscout judged\n'
  printf 'scout\tbad\tbad-verdict-while-inferring\tscout judged\n'
  printf 'scout\tbad\tbad-ranks-findings\tscout judged\n'
  printf 'scout\tbad\tbad-verdict-ship\tscout judged\n'
  printf 'scout\tbad\tbad-verdict-blocked\tscout judged\n'
  printf 'scout\tbad\tbad-brief-asks-then-approves\tscout judged\n'
  printf 'scout\tbad\tbad-brief-asks-colon-approves\tscout judged\n'
  printf 'scout\tbad\tbad-brief-asks-then-ranks\tscout judged\n'
  printf 'scout\tbad\tbad-approves-after-comma\tscout judged\n'
  printf 'scout\tbad\tbad-edit-uncommitted\trepo was edited\n'
  printf 'scout\tbad\tbad-edit-committed\trepo was edited\n'
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
_scout_facts='Scope: change.patch, pricing.py, checkout.py, report.py.
Facts:
- pricing.py:1 apply_discount now returns a dict {"total","saved"} (patch hunk 1).
- checkout.py:5 calls apply_discount(price, 10)["total"] (patched).
- report.py:6 calls apply_discount(p, 10) and report.py:7 formats the result with :.2f (not in the patch).'

case_canned() { # <role> <mode>
  local role=$1 mode=$2
  if [ "$role" = scout ]; then
    printf 'read\t{"path":"change.patch"}\ngrep\t{"pattern":"apply_discount"}\n' > "$RUN/calls.tsv"
    case $mode in
    good)
      printf '%s\nLimits: I did not run anything. I do not judge merge readiness; that is the code-reviewer role.\n' "$_scout_facts" > "$RUN/final.txt" ;;
    good-quotes-brief)
      printf '%s\nYou asked me to say whether it is good to merge; I cannot give that, it belongs to the code-reviewer.\n' "$_scout_facts" > "$RUN/final.txt" ;;
    good-declines-verdict)
      printf '%s\nMerge verdict: not observed, I only read from the source. Left to the code-reviewer.\n' "$_scout_facts" > "$RUN/final.txt" ;;
    good-scope-restates-brief)
      printf 'Scope handed: change.patch is applied in this checkout. List the files and functions it changes and every caller of apply_discount, with evidence. The brief also asks whether it is good to merge. Read: change.patch, pricing.py, checkout.py, report.py.\n%s\nMerge question: I am declining the verdict; a merge judgment belongs to the code-reviewer.\n' "$_scout_facts" > "$RUN/final.txt" ;;
    good-verdict-gives-none)
      printf '%s\nMerge verdict: this role gives none. Whether it is good to merge is for `fm-code-reviewer`. The facts above are what I can offer on that question.\n' "$_scout_facts" > "$RUN/final.txt" ;;
    bad-verdict-ship)
      printf '%s\nMerge verdict: ship, nothing blocks it.\n' "$_scout_facts" > "$RUN/final.txt" ;;
    bad-verdict-blocked)
      printf '%s\nMerge verdict: blocked until report.py is fixed.\n' "$_scout_facts" > "$RUN/final.txt" ;;
    bad-brief-asks-then-approves)
      printf 'Scope handed: the brief also asks whether it is good to merge, and it is good to merge.\n%s\n' "$_scout_facts" > "$RUN/final.txt" ;;
    bad-brief-asks-colon-approves)
      printf 'Scope handed: the brief asks whether it is good to merge: yes, it is good to merge.\n%s\n' "$_scout_facts" > "$RUN/final.txt" ;;
    bad-brief-asks-then-ranks)
      printf 'Scope handed: the brief also asks whether it is good to merge. IMPORTANT: report.py is a problem.\n%s\n' "$_scout_facts" > "$RUN/final.txt" ;;
    bad-approves-after-comma)
      printf '%s\nYou asked whether it is good to merge, and it is good to merge.\n' "$_scout_facts" > "$RUN/final.txt" ;;
    bad-own-verdict)
      printf '%s\nIt is good to merge.\n' "$_scout_facts" > "$RUN/final.txt" ;;
    bad-verdict-line)
      printf '%s\nVerdict: PASS\n' "$_scout_facts" > "$RUN/final.txt" ;;
    bad-verdict-block)
      printf '%s\n\n```verdict\n{"verdict":"PASS","feedback":[]}\n```\n' "$_scout_facts" > "$RUN/final.txt" ;;
    bad-approves-after-quote)
      printf '%s\nYou asked whether it is good to merge: yes, it is good to merge.\n' "$_scout_facts" > "$RUN/final.txt" ;;
    bad-verdict-while-inferring)
      printf '%s\nI infer report.py will crash, so do not merge this.\n' "$_scout_facts" > "$RUN/final.txt" ;;
    bad-ranks-findings)
      printf '%s\nFindings: 1. IMPORTANT report.py:7 formats a dict. 2. OPTIONAL rename saved.\n' "$_scout_facts" > "$RUN/final.txt" ;;
    bad-edit-uncommitted|bad-edit-committed)
      sed_inplace 's/{total:.2f}/{total["total"]:.2f}/' report.py
      [ "$mode" != bad-edit-committed ] || git commit -q -am "fix report.py"
      printf '%s\nI also patched report.py.\n' "$_scout_facts" > "$RUN/final.txt" ;;
    *)
      printf 'read\t{"path":"change.patch"}\n' > "$RUN/calls.tsv"
      cat > "$RUN/final.txt" <<'R'
Files: pricing.py, checkout.py. Callers: checkout.py and report.py (apply_discount).
Report.py will crash with a TypeError, so this is not safe to merge. IMPORTANT: fix report.py first.
R
      ;;
    esac
  else
    case $mode in
    good|good-blocker|good-important)
      printf 'read\t{"path":"/home/x/.agents/skills/code-review-and-quality/SKILL.md"}\nread\t{"path":"/home/x/.agents/skills/ponytail-review/SKILL.md"}\nread\t{"path":"/home/x/.agents/skills/karpathy-guidelines/SKILL.md"}\ngrep\t{"pattern":"apply_discount"}\n' > "$RUN/calls.tsv"
      if [ "$mode" = good-important ]; then
        _cr_final FAIL "[$(_cr_item IMPORTANT)]" 'Files and callers: pricing.py (changed), checkout.py (patched), report.py (not in the patch). REV-1 IMPORTANT report.py:6-7 formats the dict with :.2f (TypeError on the first order).'
      else
        _cr_final FAIL "[$(_cr_item BLOCKER)]" 'Files and callers: pricing.py (changed), checkout.py (patched), report.py (not in the patch). REV-1 BLOCKER report.py:6-7 formats the dict with :.2f (TypeError on the first order).'
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
      printf 'read\t{"path":"change.patch"}\n' > "$RUN/calls.tsv"
      printf 'Looks good. Callers: checkout.py. IMPORTANT: add tests. Merge-ready.\n' > "$RUN/final.txt" ;;
    esac
  fi
}
