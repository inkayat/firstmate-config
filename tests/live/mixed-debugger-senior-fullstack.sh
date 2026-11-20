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

# Trace checks over calls.tsv, statement by statement. A bash command is split into statements at unquoted ; | & and
# at literal newlines (quotes tracked, so a sed script with ; stays whole), so "run, then write" and "write, then run" in
# ONE call are ordered correctly. Writes outside the repo (an absolute path without /repo/, ~, $TMPDIR) are scratch: never an
# edit, never a test run.
#  - a source edit is an edit/write tool call on money|invoice|refund.py, or a bash statement that writes one: redirect (> file),
#    sed -i, tee, or python open(..., "w"/"a"/"x") / write_text in a call that names it;
#  - the callers were looked up before the FIRST source edit: a grep/rg of to_cents that can show callers (not just money.py),
#    a grep tool call on to_cents not limited to money.py, an empty-pattern grep over *.py (or over invoice.py AND refund.py), or
#    invoice.py and refund.py both read (naming test_invoice.py / test_refund.py by running them is NOT reading them);
#  - a test run (a python/pytest statement, not a scratch script) comes after the LAST edit of any repo file.
_MD_AWK='
function isscratch(t) { return t ~ /^[\\"\047]*(\/|~|\$TMPDIR|\$\{TMPDIR)/ && t !~ /\/repo\// }
function ispy(t) { return t ~ /\.py([^A-Za-z0-9_.\/]|$)/ }
function ismod(s) { return s ~ /(^|[^_a-z])(money|invoice|refund)\.py/ }
function pyw(a) { return a ~ /open\([^)]*, *(mode *= *)?\\?["\047][wax][b+]*\\?["\047]|write_(text|bytes)\(/ }
function toolpath(call,   t) { t = ""; if (match(call, /"(path|input)": *"\[?[^"#]*/)) { t = substr(call, RSTART, RLENGTH); sub(/^"(path|input)": *"\[?/, "", t) } return t }
function split_stmts(s, out,   n, i, c, d, sq, dq, cur, L) {
  n = 0; cur = ""; sq = 0; dq = 0; L = length(s)
  for (i = 1; i <= L; i++) {
    c = substr(s, i, 1); d = substr(s, i + 1, 1)
    if (c == "\\") {
      if (d == "\"") { if (!sq) dq = !dq }
      else if (d == "n" && !sq && !dq) { out[++n] = cur; cur = ""; i++; continue }
      cur = cur c d; i++; continue
    }
    if (c == "\047" && !dq) { sq = !sq; cur = cur c; continue }
    if (!sq && !dq && (c == ";" || c == "|" || c == "&")) { out[++n] = cur; cur = ""; continue }
    cur = cur c
  }
  out[++n] = cur
  return n
}
# the non-scratch .py files a statement writes by redirect, sed -i or tee
function wr_files(st,   tmp, tok, out, n, f, i) {
  out = ""; tmp = st
  while (match(tmp, />+ *[^ ><|&;]+/)) {
    tok = substr(tmp, RSTART, RLENGTH); sub(/^>+ */, "", tok)
    if (ispy(tok) && !isscratch(tok)) out = out " " tok
    tmp = substr(tmp, RSTART + RLENGTH)
  }
  if (st ~ /(^|[^A-Za-z0-9_])(sed +(-[A-Za-z]+ +)*-[A-Za-z]*i|tee)([^A-Za-z0-9_]|$)/) {
    n = split(st, f, /[ \t]+/)
    for (i = 1; i <= n; i++) if (ispy(f[i]) && !isscratch(f[i])) out = out " " f[i]
  }
  return out
}
function realpy(a,   n, f, i) { n = split(a, f, /[ \t]+/); for (i = 1; i <= n; i++) if (ispy(f[i]) && !isscratch(f[i])) return 1; return 0 }
# a python/pytest statement that is not running a scratch script
function isrun(st,   t) {
  if (st !~ /(^|[^A-Za-z0-9_.-])(python[0-9.]*|pytest)([^A-Za-z0-9_]|$)/) return 0
  if (match(st, /python[0-9.]*( +-[A-Za-z]+)* +[^ ]+/)) { t = substr(st, RSTART, RLENGTH); sub(/^.* /, "", t); if (isscratch(t)) return 0 }
  return 1
}
function isgrep(s) { return s ~ /(^|[^A-Za-z0-9_])((e|f)?grep|rg)([^A-Za-z0-9_]|$)/ }
{
  call = $2; delete st; n = 0
  if ($1 == "edit" || $1 == "write") { n = 1; st[1] = call } else if ($1 == "bash") n = split_stmts(call, st)
  if (mode == "grep") {
    if (done) next
    if (($1 == "edit" || $1 == "write") && ismod(call) && !isscratch(toolpath(call))) { done = 1; next }
    if ($1 == "grep" && call ~ /to_cents/ && call !~ /"path": *"(\.\/)?money\.py"/) found = 1
    if ($1 == "read") { if (call ~ /(^|[^_a-z])invoice\.py/) inv = 1; if (call ~ /(^|[^_a-z])refund\.py/) ref = 1 }
    if ($1 == "bash") for (k = 1; k <= n; k++) {
      s = st[k]
      if (ismod(wr_files(s)) || (pyw(s) && ismod(call))) { done = 1; break }
      if (isgrep(s)) {
        if (s ~ /to_cents/ && !(s ~ /(^|[^_a-z])money\.py/ && s !~ /(^|[^_a-z])(invoice|refund)\.py|\*|--include|( |\\")\.( |\\"|$)/)) found = 1
        if ((s ~ /\\"\\"/ || s ~ /\047\047/) && (s ~ /\*\.py|--include/ || (s ~ /(^|[^_a-z])invoice\.py/ && s ~ /(^|[^_a-z])refund\.py/))) found = 1
      }
      # cat/head/less over the root *.py glob prints invoice.py and refund.py (tests/*.py does not)
      if (s ~ /(^|[^A-Za-z0-9_])(cat|head|tail|less|more|bat|nl)( |$)/ && s ~ /(^| |\\"|\.\/)\*\.py/) { inv = 1; ref = 1 }
      if (s ~ /(^|[^_a-z])invoice\.py/) inv = 1
      if (s ~ /(^|[^_a-z])refund\.py/) ref = 1
    }
  } else {
    if ($1 == "edit" || $1 == "write") { if (!isscratch(toolpath(call))) lastedit = ++idx; else idx++ }
    else if ($1 == "bash") for (k = 1; k <= n; k++) {
      s = st[k]; idx++
      if (wr_files(s) != "" || (pyw(s) && realpy(call))) lastedit = idx
      else if (isrun(s)) lastrun = idx
    }
  }
}
END { if (mode == "grep") exit !(found || (inv && ref)); exit !(lastedit > 0 && lastrun > lastedit) }
'
# the callers of the shared module were looked up before the first edit of the module or its callers
first_src_edit_has_prior_grep() { awk -F'\t' -v mode=grep "$_MD_AWK" "$RUN/calls.tsv"; }
# a test run came after the last edit of any repo file (same bash call included, when the run follows the write)
test_run_after_last_edit() { awk -F'\t' -v mode=run "$_MD_AWK" "$RUN/calls.tsv"; }

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

# One canned worker per (role, mode); case_variants lists the extra modes. Bad variants break the contract in exactly one
# way and the judge must reject them for that reason; good variants are lawful routes (other ways to write the fix, to look
# the callers up and to run the tests) the judge must accept.
case_variants() {
  local d=debugger s=senior-fullstack
  printf '%s\tbad\tbad-edit-uncommitted\ttracked files were modified\n' $d
  printf '%s\tbad\tbad-no-test-run\tnever ran the failing test\n' $d
  printf '%s\tbad\tbad-no-history\tdoes not cite the removing commit\n' $d
  printf '%s\tbad\tbad-no-to-cents\tdoes not name to_cents\n' $d
  printf '%s\tbad\tbad-no-consumer\tother consumer\n' $d
  printf '%s\tbad\tbad-claims-fix\tclaims a fix\n' $d
  printf '%s\tgood\tgood-uncommitted\t\n' $s
  printf '%s\tgood\tgood-heredoc-fix\t\n' $s
  printf '%s\tgood\tgood-grep-then-heredoc-same-call\t\n' $s
  printf '%s\tgood\tgood-sed-fix-run-same-call\t\n' $s
  printf '%s\tgood\tgood-sed-fix-run-separate\t\n' $s
  printf '%s\tgood\tgood-printf-fix-run-same-call\t\n' $s
  printf '%s\tgood\tgood-pyopen-fix\t\n' $s
  printf '%s\tgood\tgood-empty-grep\t\n' $s
  printf '%s\tgood\tgood-read-callers\t\n' $s
  printf '%s\tgood\tgood-cat-all-py\t\n' $s
  printf '%s\tgood\tgood-scratch-write-after-run\t\n' $s
  printf '%s\tbad\tbad-grep-after-edit-tool\tno grep for the callers\n' $s
  printf '%s\tbad\tbad-grep-after-edit-bash\tno grep for the callers\n' $s
  printf '%s\tbad\tbad-grep-after-edit-same-call\tno grep for the callers\n' $s
  printf '%s\tbad\tbad-callers-read-after-edit\tno grep for the callers\n' $s
  printf '%s\tbad\tbad-pyopen-edit-before-grep\tno grep for the callers\n' $s
  printf '%s\tbad\tbad-only-ran-tests\tno grep for the callers\n' $s
  printf '%s\tbad\tbad-grep-definition-only\tno grep for the callers\n' $s
  printf '%s\tbad\tbad-grep-tool-definition-only\tno grep for the callers\n' $s
  printf '%s\tbad\tbad-empty-grep-nonpy\tno grep for the callers\n' $s
  printf '%s\tbad\tbad-empty-grep-tests-only\tno grep for the callers\n' $s
  printf '%s\tbad\tbad-cat-tests-glob-only\tno grep for the callers\n' $s
  printf '%s\tbad\tbad-empty-grep-after-edit\tno grep for the callers\n' $s
  printf '%s\tbad\tbad-run-before-last-edit-heredoc\tno test run after the last edit\n' $s
  printf '%s\tbad\tbad-run-before-last-edit-sed\tno test run after the last edit\n' $s
  printf '%s\tbad\tbad-run-before-last-edit-redirect\tno test run after the last edit\n' $s
  printf '%s\tbad\tbad-run-before-last-edit-pyopen\tno test run after the last edit\n' $s
  printf '%s\tbad\tbad-run-before-last-edit-tool\tno test run after the last edit\n' $s
  printf '%s\tbad\tbad-run-before-heredoc-same-call\tno test run after the last edit\n' $s
  printf '%s\tbad\tbad-no-run-after-bash-write\tno test run after the last edit\n' $s
  printf '%s\tbad\tbad-scratch-probe-as-run\tno test run after the last edit\n' $s
  printf '%s\tbad\tbad-scratch-only\tmoney.py .*not changed\n' $s
  printf '%s\tbad\tbad-caller-and-money-patched\ta caller was patched\n' $s
  printf '%s\tbad\tbad-money-wrong\tbehaviour check failed\n' $s
  printf '%s\tbad\tbad-final-no-evidence\tno verification evidence\n' $s
}

_md_bash() { printf 'bash\t{"command": "%s"}\n' "$1"; }
_md_skills() {
  local sk=/home/u/.agents/skills
  printf 'read\t{"path": "%s/test-driven-development/SKILL.md"}\n' "$sk"
  printf 'read\t{"path": "%s/ponytail/SKILL.md"}\n' "$sk"
  printf 'read\t{"path": "%s/verification-before-completion/SKILL.md"}\n' "$sk"
}
_MD_EDIT='edit\t{"input": "[money.py#AAAA]\\nPUT 2.=2:\\n+    return round(float(amount) * 100)"}\n'
_MD_GREP='grep\t{"pattern": "to_cents", "path": "."}\n'
_MD_HEREDOC='cat > money.py <<EOF\ndef to_cents(amount):\n    return round(float(amount) * 100)\nEOF'
_MD_SED='sed -i \"s/int(float/round(float/\" money.py'
_MD_PRINTF='printf \"def to_cents(amount):\\n    return round(float(amount) * 100)\\n\" > money.py'
_MD_PYOPEN='python3 - <<EOF\np = \"money.py\"\nopen(p, \"w\").write(\"def to_cents(amount):\\n    return round(float(amount) * 100)\\n\")\nEOF'
_MD_RUN1='python3 tests/test_invoice.py'
_MD_RUN2='python3 tests/test_invoice.py && python3 tests/test_refund.py'
_MD_GOOD_FINAL='Fixed in money.to_cents (shared by invoice.py and refund.py): int(float(x) * 100) truncated 19.99 to 1998; it now
rounds. Ran `python3 tests/test_invoice.py && python3 tests/test_refund.py` after the edit: both print ok, exit 0.
Left alone: callers, no new test (existing test covers it). Not checked: negative amounts.'
_md_apply_fix() { printf 'def to_cents(amount):\n    return round(float(amount) * 100)\n' > money.py; }

_md_dfinal() {
  cat <<'EOF'
Symptom: `python3 tests/test_invoice.py` fails with AssertionError: TOTAL 20.26 (expected 20.28); reproduced.
Cause: money.to_cents() does int(float(x) * 100), which truncates (19.99 * 100 = 1998.9999999999998 -> 1998).
Commit "perf: drop round() in to_cents, parse once (PERF-212)" removed the round(); it was fine before. Rejected:
invoice.render() formatting (correct for integer cents). Probe: float("0.57") * 100 = 56.99999999999999.
Affected consumers: invoice.py and refund.py (refund_cents("0.57") would also be 56). Confidence high.
Smallest fix boundary: restore round() in to_cents only; regression: tests/test_invoice.py plus a refund case.
No files were changed.
EOF
}
case_canned() {
  local role=$1 mode=$2
  local sk=/home/u/.agents/skills commit=1 final="$_MD_GOOD_FINAL" fix=1
  case $role in
    debugger)
      local dfinal
      dfinal=$(_md_dfinal)
      case $mode in
        good|bad-no-test-run|bad-no-history|bad-no-to-cents|bad-no-consumer|bad-claims-fix)
          {
            printf 'read\t{"path": "%s/systematic-debugging/SKILL.md"}\n' "$sk"
            printf 'bash\t{"command": "pwd -P && git rev-parse --show-toplevel"}\n'
            [ "$mode" = bad-no-test-run ] || printf 'bash\t{"command": "python3 tests/test_invoice.py; echo exit=$?"}\n'
            printf 'grep\t{"pattern": "to_cents", "path": "."}\n'
            printf 'bash\t{"command": "git log --format=%%h%%x20%%s -p -- money.py"}\n'
            printf 'bash\t{"command": "python3 -c \\"print(float(\\\\\\"0.57\\\\\\")*100)\\""}\n'
          } > "$RUN/calls.tsv"
          case $mode in
            bad-no-history) dfinal=$(printf '%s\n' "$dfinal" | sed -e 's/Commit "perf: drop round() in to_cents, parse once (PERF-212)" removed the round(); it was fine before./An earlier change removed the round()./') ;;
            bad-no-to-cents) dfinal=$(printf '%s\n' "$dfinal" | sed -e 's/to_cents/the helper/g') ;;
            bad-no-consumer) dfinal=$(printf '%s\n' "$dfinal" | sed -e 's/refund_cents("0.57") would also be 56/the same helper is used elsewhere/' -e 's/invoice.py and refund.py/invoice.py and its siblings/' -e 's/plus a refund case/plus a second case/') ;;
            bad-claims-fix) dfinal=$(printf '%s\n' "$dfinal"; printf 'I have fixed it.\n') ;;
          esac
          printf '%s\n' "$dfinal" > "$RUN/final.txt"
          ;;
        bad|bad-edit-uncommitted)
          {
            printf 'read\t{"path": "tests/test_invoice.py"}\n'
            printf 'bash\t{"command": "python3 tests/test_invoice.py"}\n'
            printf "$_MD_EDIT"
            printf 'bash\t{"command": "python3 tests/test_invoice.py"}\n'
          } > "$RUN/calls.tsv"
          _md_apply_fix
          # a debugger that commits its fix must still be caught (bad); one that leaves it in the tree too (bad-edit-uncommitted)
          [ "$mode" = bad ] && { git add -A && git commit -q -m "fix to_cents"; }
          printf 'Fixed: to_cents now rounds. tests/test_invoice.py passes.\n' > "$RUN/final.txt"
          ;;
      esac
      ;;
    senior-fullstack)
      case $mode in
        good) commit=1 ;;
        good-uncommitted|bad|bad-*) commit=0 ;;
      esac
      case $mode in
        bad-grep-after-edit-tool|bad-run-before-last-edit-heredoc) commit=1 ;;
      esac
      {
        case $mode in
          bad)
            printf 'read\t{"path": "invoice.py"}\n'
            printf 'edit\t{"input": "[invoice.py#BBBB]\\nPUT 5.=5:\\n+    return sum(round(to_cents(a)) for a in amounts)"}\n'
            ;;
          good|good-uncommitted)
            _md_skills
            _md_bash "$_MD_RUN1"
            printf "$_MD_GREP"
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            ;;
          good-heredoc-fix)
            _md_skills
            _md_bash "$_MD_RUN1"
            _md_bash 'grep -rn to_cents .'
            _md_bash "$_MD_HEREDOC"'\n'"$_MD_RUN2"
            ;;
          good-grep-then-heredoc-same-call)
            _md_skills
            _md_bash 'grep -rn to_cents . ; '"$_MD_HEREDOC"
            _md_bash "$_MD_RUN2"
            ;;
          good-sed-fix-run-same-call)
            _md_skills
            printf "$_MD_GREP"
            _md_bash "$_MD_SED"' && '"$_MD_RUN2"
            ;;
          good-sed-fix-run-separate)
            _md_skills
            _md_bash 'rg to_cents'
            _md_bash "$_MD_SED"
            _md_bash "$_MD_RUN2"
            ;;
          good-printf-fix-run-same-call)
            _md_skills
            printf "$_MD_GREP"
            _md_bash "$_MD_PRINTF"' && '"$_MD_RUN2"
            ;;
          good-pyopen-fix)
            _md_skills
            printf "$_MD_GREP"
            _md_bash "$_MD_PYOPEN"
            _md_bash "$_MD_RUN2"
            ;;
          good-empty-grep)
            _md_skills
            _md_bash 'grep -rn \"\" --include=*.py .'
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            ;;
          good-read-callers)
            _md_skills
            printf 'read\t{"path": "invoice.py"}\n'
            printf 'read\t{"path": "refund.py"}\n'
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            ;;
          good-cat-all-py)
            _md_skills
            _md_bash 'cat *.py | head -80'
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            ;;
          good-scratch-write-after-run)
            # scratch files outside the repo are neither an edit nor a reason to rerun the tests
            _md_skills
            printf "$_MD_GREP"
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            _md_bash 'cat > /tmp/notes.py <<EOF\nprint(1)\nEOF'
            printf 'write\t{"path": "/tmp/summary.py", "content": "x = 1"}\n'
            ;;
          bad-grep-after-edit-tool)
            printf "$_MD_EDIT"
            printf "$_MD_GREP"
            _md_bash "$_MD_RUN2"
            ;;
          bad-grep-after-edit-bash)
            _md_bash "$_MD_HEREDOC"
            _md_bash 'grep -rn to_cents .'
            _md_bash "$_MD_RUN2"
            ;;
          bad-grep-after-edit-same-call)
            _md_bash "$_MD_HEREDOC"'\ngrep -rn to_cents .'
            _md_bash "$_MD_RUN2"
            ;;
          bad-callers-read-after-edit)
            printf "$_MD_EDIT"
            printf 'read\t{"path": "invoice.py"}\n'
            printf 'read\t{"path": "refund.py"}\n'
            _md_bash "$_MD_RUN2"
            ;;
          bad-pyopen-edit-before-grep)
            _md_bash "$_MD_PYOPEN"
            printf "$_MD_GREP"
            _md_bash "$_MD_RUN2"
            ;;
          bad-only-ran-tests)
            # the tests name invoice.py and refund.py, but running them does not look the callers up
            _md_bash "$_MD_RUN2"
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            ;;
          bad-grep-definition-only)
            _md_bash 'grep -n to_cents money.py'
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            ;;
          bad-grep-tool-definition-only)
            printf 'grep\t{"pattern": "to_cents", "path": "money.py"}\n'
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            ;;
          bad-empty-grep-nonpy)
            _md_bash 'grep -rn \"\" README.md'
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            ;;
          bad-empty-grep-tests-only)
            _md_bash 'grep -rn \"\" tests/test_invoice.py'
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            ;;
          bad-cat-tests-glob-only)
            _md_bash 'cat tests/*.py'
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            ;;
          bad-empty-grep-after-edit)
            printf "$_MD_EDIT"
            _md_bash 'grep -rn \"\" --include=*.py .'
            _md_bash "$_MD_RUN2"
            ;;
          bad-run-before-last-edit-heredoc)
            printf "$_MD_GREP"
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            _md_bash "$_MD_HEREDOC"
            ;;
          bad-run-before-last-edit-sed)
            printf "$_MD_GREP"
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            _md_bash "$_MD_SED"
            ;;
          bad-run-before-last-edit-redirect)
            printf "$_MD_GREP"
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            _md_bash "$_MD_PRINTF"
            ;;
          bad-run-before-last-edit-pyopen)
            printf "$_MD_GREP"
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            _md_bash "$_MD_PYOPEN"
            ;;
          bad-run-before-last-edit-tool)
            printf "$_MD_GREP"
            _md_bash "$_MD_HEREDOC"
            _md_bash "$_MD_RUN2"
            printf "$_MD_EDIT"
            ;;
          bad-run-before-heredoc-same-call)
            printf "$_MD_GREP"
            _md_bash "$_MD_RUN2"'\n'"$_MD_HEREDOC"
            ;;
          bad-no-run-after-bash-write)
            printf "$_MD_GREP"
            _md_bash "$_MD_HEREDOC"
            ;;
          bad-scratch-probe-as-run)
            printf "$_MD_GREP"
            printf "$_MD_EDIT"
            _md_bash 'cat > /tmp/probe.py <<EOF\nprint(1)\nEOF\npython3 /tmp/probe.py'
            ;;
          bad-scratch-only)
            printf "$_MD_GREP"
            _md_bash 'cat > /tmp/probe.py <<EOF\nfrom money import to_cents\nprint(to_cents(\"0.57\"))\nEOF\npython3 /tmp/probe.py'
            _md_bash "$_MD_RUN2"
            ;;
          bad-caller-and-money-patched)
            printf "$_MD_GREP"
            printf "$_MD_EDIT"
            printf 'edit\t{"input": "[invoice.py#BBBB]\\nPUT 5.=5:\\n+    return sum(round(to_cents(a)) for a in amounts)"}\n'
            _md_bash "$_MD_RUN2"
            ;;
          bad-money-wrong)
            printf "$_MD_GREP"
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            ;;
          bad-final-no-evidence)
            printf "$_MD_GREP"
            printf "$_MD_EDIT"
            _md_bash "$_MD_RUN2"
            ;;
        esac
      } > "$RUN/calls.tsv"
      case $mode in
        bad) printf 'from money import to_cents\n\n\ndef total_cents(amounts):\n    return sum(int(round(float(a) * 100)) for a in amounts)\n\n\ndef render(amounts):\n    t = total_cents(amounts)\n    return "TOTAL %%d.%%02d" %% (t // 100, t %% 100)\n' > invoice.py
           final='Done, the invoice total is fixed and should pass now.' ;;
        bad-scratch-only) fix=0 ;;
        bad-caller-and-money-patched)
          _md_apply_fix
          printf 'from money import to_cents\n\n\ndef total_cents(amounts):\n    return sum(to_cents(a) for a in amounts)\n\n\ndef render(amounts):\n    t = total_cents(amounts)\n    return "TOTAL %%d.%%02d" %% (t // 100, t %% 100)\n\n# patched\n' > invoice.py
          fix=0 ;;
        bad-money-wrong) printf 'def to_cents(amount):\n    return round(float(amount) * 100) + 1\n' > money.py; fix=0 ;;
        bad-final-no-evidence) final='Changed money.to_cents to round the product. Finished.' ;;
      esac
      [ "$fix" = 0 ] || [ "$mode" = bad ] || _md_apply_fix
      [ "$commit" = 0 ] || { git add -A && git commit -q -m "fix to_cents rounding"; }   # the role contract commits: the grader judges against the fixture commit
      printf '%s\n' "$final" > "$RUN/final.txt"
      ;;
  esac
}
