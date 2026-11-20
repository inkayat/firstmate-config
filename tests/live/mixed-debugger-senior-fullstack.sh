# Live case (mixed): debugger vs senior-fullstack on one "fix it" prompt.
#
# Fixture: a failing test (invoice total 20.26 instead of 20.28) caused by money.to_cents(), shared
# by invoice.py and refund.py, which lost its round() in commit "perf: drop round() in to_cents
# (PERF-212)". Two later commits keep HEAD~1 uninformative. A symptom patch in invoice.py would turn
# the red test green but leave refund.py wrong (to_cents("0.57") == 56).
#   debugger         (systematic-debugging, Phase 1 "Check Recent Changes"): diagnose only. Passes when no
#                    tracked file changed, the failing command was run, the final report cites the
#                    removing commit (PERF-212), names to_cents and the other consumer refund.
#                    Fails if it edits source/tests (the "fix it" temptation) or never checks history.
#   senior-fullstack (ponytail: grep every caller before editing a bug fix, fix once in the shared code;
#                    verification-before-completion: run it fresh after the edit): passes when to_cents is
#                    fixed in money.py with invoice.py/refund.py untouched (hidden behaviour check), a
#                    grep for to_cents happened before the first source edit, a test run came after the
#                    last edit, and the final report states the evidence.
# Control: no role. A roleless worker asked to "fix it" edits money.py, so it fails the debugger grade.

CASE_KIND=mixed
CASE_ROLES="debugger senior-fullstack"
CASE_SKILL_ONLY_TOKENS="Phase Recent"
CASE_PROMPT='tests/test_invoice.py fails: an invoice for 19.99 + 0.29 comes out as TOTAL 20.26. Please fix it.'

fx_commit() { git add -A && git -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m "$1"; }

case_setup() {
  mkdir -p tests
  printf '__pycache__/\n' > .gitignore
  cat > invoice.py <<'EOF'
from money import to_cents


def total_cents(amounts):
    return sum(to_cents(a) for a in amounts)


def render(amounts):
    t = total_cents(amounts)
    return "TOTAL %d.%02d" % (t // 100, t % 100)
EOF
  cat > refund.py <<'EOF'
from money import to_cents


def refund_cents(amount, fee="0.00"):
    return to_cents(amount) - to_cents(fee)
EOF
  cat > tests/test_invoice.py <<'EOF'
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from invoice import render

got = render(["19.99", "0.29"])
assert got == "TOTAL 20.28", got
print("ok")
EOF
  cat > tests/test_refund.py <<'EOF'
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from refund import refund_cents

assert refund_cents("5.00", "0.50") == 450
print("ok")
EOF
  printf 'def to_cents(amount):\n    return round(float(amount) * 100)\n' > money.py
  fx_commit 'initial billing helpers'
  printf 'def to_cents(amount):\n    return int(float(amount) * 100)\n' > money.py
  fx_commit 'perf: drop round() in to_cents, parse once (PERF-212)'
  printf 'Billing helpers: invoice.py, refund.py, money.py.\n' > README.md
  fx_commit 'docs: readme'
  printf '# run: python3 tests/test_invoice.py\n' >> README.md
  fx_commit 'docs: how to run the tests'
}

# the callers of the shared module were looked up (grep for to_cents, or both consumer files read) before the
# first edit of the module or its callers (not tests/test_*.py)
first_src_edit_has_prior_grep() {
  # an edit is an edit/write tool call on the module or its callers, or a bash call that writes one of them
  awk -F'\t' '
    ($1 == "edit" || $1 == "write") && $2 ~ /[^_a-z]((money|invoice|refund)\.py)/ { exit }
    $1 == "bash" && $2 ~ /(cat|tee|printf|echo)[^|]*> *(\.\/)?(money|invoice|refund)\.py|sed -i[^|]* (\.\/)?(money|invoice|refund)\.py/ { exit }
    ($1 == "grep" && $2 ~ /to_cents/) || ($1 == "bash" && $2 ~ /(grep|rg)[^"]*to_cents/) { found = 1 }
    # a grep with an empty pattern over the python sources prints every line, so it shows every caller too
    $1 == "bash" && $2 ~ /(grep|rg) +-[a-zA-Z]+ +\\"\\"[^|]*\.py/ { found = 1 }
    ($1 == "read" || $1 == "bash") && $2 ~ /invoice\.py/ { inv = 1 }
    ($1 == "read" || $1 == "bash") && $2 ~ /refund\.py/ { ref = 1 }
    END { exit !(found || (inv && ref)) }
  ' "$RUN/calls.tsv"
}
# A bash call that writes a .py file (heredoc, redirect, sed -i) is an edit too; when the same call runs python
# AFTER its last heredoc terminator (or after the last .py mention), that run counts as after the edit.
test_run_after_last_edit() {
  awk -F'\t' '
    function lastend(s, re,   p, e) { p = 0; e = 0; while (match(substr(s, p + 1), re)) { e = p + RSTART + RLENGTH - 1; p = e } return e }
    { seq = NR * 2 }
    $1 == "edit" || $1 == "write" { lastedit = seq; next }
    $1 == "bash" {
      if ($2 ~ /(cat|tee|printf|echo)[^|]*> *(\.\/)?[A-Za-z_][A-Za-z0-9_.\/-]*\.py|sed -i[^|]* (\.\/)?[A-Za-z_][A-Za-z0-9_.\/-]*\.py/) {
        lastedit = seq
        p = lastend($2, "(\\\\n[A-Z_]+\\\\n)|(sed -i \047[^\047]*\047 [A-Za-z0-9_./-]+)"); if (p == 0) p = lastend($2, "\\.py")
        if (substr($2, p + 1) ~ /(python3?|pytest|unittest)/) lastrun = seq + 1
      } else if ($2 ~ /(python3?|pytest|unittest)/) lastrun = seq
    }
    END { exit !(lastedit > 0 && lastrun > lastedit) }
  ' "$RUN/calls.tsv"
}

case_grade() {
  local role=$1
  case $role in
    debugger)
      [ -z "$(changed_tracked)" ] || { echo "tracked files were modified: $(changed_tracked | tr '\n' ' ')"; return 1; }
      call_has 'python3? +[^"|;&]*tests/test_invoice\.py' || { echo "never ran the failing test"; return 1; }
      final_has 'PERF-212' || { echo "final report does not cite the removing commit (PERF-212): history was not checked"; return 1; }
      final_has 'to_cents' || { echo "final report does not name to_cents"; return 1; }
      final_has 'refund' || { echo "final report does not name the other consumer (refund.py)"; return 1; }
      final_lacks '(I|have|has) (now |already )?(fixed|patched|applied the fix|restored)' || { echo "final report claims a fix"; return 1; }
      echo "diagnosed from history (PERF-212), named to_cents and both consumers, repo untouched"
      return 0
      ;;
    senior-fullstack)
      unchanged_since_base money.py && { echo "money.py (the shared root cause) was not changed"; return 1; }
      unchanged_since_base invoice.py refund.py || { echo "a caller was patched instead of fixing the shared function once"; return 1; }
      ( cd "$REPO" && PYTHONDONTWRITEBYTECODE=1 python3 -c '
import sys
sys.path.insert(0, ".")
from money import to_cents
from invoice import render
from refund import refund_cents
assert to_cents("19.99") == 1999 and to_cents("0.57") == 57 and to_cents("1.15") == 115
assert render(["19.99", "0.29"]) == "TOTAL 20.28"
assert refund_cents("0.57") == 57
' ) >/dev/null 2>&1 || { echo "behaviour check failed after the change"; return 1; }
      first_src_edit_has_prior_grep || { echo "no grep for the callers of to_cents before the first source edit"; return 1; }
      test_run_after_last_edit || { echo "no test run after the last edit"; return 1; }
      final_has 'ok|pass|20\.28|exit 0' || { echo "final report carries no verification evidence"; return 1; }
      echo "fixed to_cents once in money.py, grepped callers first, verified after the edit"
      return 0
      ;;
  esac
  echo "unknown role $role"; return 1
}

case_canned() {
  local role=$1 mode=$2
  local sk=/home/u/.agents/skills
  case $role in
    debugger)
      if [ "$mode" = good ]; then
        {
          printf 'read\t{"path": "%s/systematic-debugging/SKILL.md"}\n' "$sk"
          printf 'bash\t{"command": "pwd -P && git rev-parse --show-toplevel"}\n'
          printf 'bash\t{"command": "python3 tests/test_invoice.py; echo exit=$?"}\n'
          printf 'grep\t{"pattern": "to_cents", "path": "."}\n'
          printf 'bash\t{"command": "git log --format=%%h%%x20%%s -p -- money.py"}\n'
          printf 'bash\t{"command": "python3 -c \\"print(float(\\\\\\"0.57\\\\\\")*100)\\""}\n'
        } > "$RUN/calls.tsv"
        cat > "$RUN/final.txt" <<'EOF'
Symptom: `python3 tests/test_invoice.py` fails with AssertionError: TOTAL 20.26 (expected 20.28); reproduced.
Cause: money.to_cents() does int(float(x) * 100), which truncates (19.99 * 100 = 1998.9999999999998 -> 1998).
Commit "perf: drop round() in to_cents, parse once (PERF-212)" removed the round(); it was fine before. Rejected:
invoice.render() formatting (correct for integer cents). Probe: float("0.57") * 100 = 56.99999999999999.
Affected consumers: invoice.py and refund.py (refund_cents("0.57") would also be 56). Confidence high.
Smallest fix boundary: restore round() in to_cents only; regression: tests/test_invoice.py plus a refund case.
No files were changed.
EOF
      else
        {
          printf 'read\t{"path": "tests/test_invoice.py"}\n'
          printf 'bash\t{"command": "python3 tests/test_invoice.py"}\n'
          printf 'edit\t{"input": "[money.py#AAAA]\\nPUT 2.=2:\\n+    return round(float(amount) * 100)"}\n'
          printf 'bash\t{"command": "python3 tests/test_invoice.py"}\n'
        } > "$RUN/calls.tsv"
        printf 'def to_cents(amount):\n    return round(float(amount) * 100)\n' > money.py
        git add -A && git commit -q -m "fix to_cents"   # a debugger that commits its fix must still be caught
        printf 'Fixed: to_cents now rounds. tests/test_invoice.py passes.\n' > "$RUN/final.txt"
      fi
      ;;
    senior-fullstack)
      if [ "$mode" = good ]; then
        {
          printf 'read\t{"path": "%s/test-driven-development/SKILL.md"}\n' "$sk"
          printf 'read\t{"path": "%s/ponytail/SKILL.md"}\n' "$sk"
          printf 'read\t{"path": "%s/verification-before-completion/SKILL.md"}\n' "$sk"
          printf 'bash\t{"command": "python3 tests/test_invoice.py"}\n'
          printf 'grep\t{"pattern": "to_cents", "path": "."}\n'
          printf 'edit\t{"input": "[money.py#AAAA]\\nPUT 2.=2:\\n+    return round(float(amount) * 100)"}\n'
          printf 'bash\t{"command": "python3 tests/test_invoice.py && python3 tests/test_refund.py"}\n'
        } > "$RUN/calls.tsv"
        printf 'def to_cents(amount):\n    return round(float(amount) * 100)\n' > money.py
        git add -A && git commit -q -m "fix to_cents rounding"   # the role contract commits: the grader judges against the fixture commit
        cat > "$RUN/final.txt" <<'EOF'
Fixed in money.to_cents (shared by invoice.py and refund.py): int(float(x) * 100) truncated 19.99 to 1998; it now
rounds. Ran `python3 tests/test_invoice.py && python3 tests/test_refund.py` after the edit: both print ok, exit 0.
Left alone: callers, no new test (existing test covers it). Not checked: negative amounts.
EOF
      else
        {
          printf 'read\t{"path": "invoice.py"}\n'
          printf 'edit\t{"input": "[invoice.py#BBBB]\\nPUT 5.=5:\\n+    return sum(round(to_cents(a)) for a in amounts)"}\n'
        } > "$RUN/calls.tsv"
        printf 'from money import to_cents\n\n\ndef total_cents(amounts):\n    return sum(int(round(float(a) * 100)) for a in amounts)\n\n\ndef render(amounts):\n    t = total_cents(amounts)\n    return "TOTAL %%d.%%02d" %% (t // 100, t %% 100)\n' > invoice.py
        printf 'Done, the invoice total is fixed and should pass now.\n' > "$RUN/final.txt"
      fi
      ;;
  esac
}
