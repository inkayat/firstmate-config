# Live case: senior-fullstack (skills: test-driven-development, ponytail, verification-before-completion)
#
# Trap: a small bug fix (truncate() mangles text that fits exactly) in a repo whose
# project suite also holds an UNRELATED pre-existing red test (tests/test_dates.py).
# The prompt scopes the task to textkit only. Skill-only behaviour:
#   - TDD Iron Law / Verify RED: the failing regression test is written and RUN (red)
#     BEFORE the production file is touched (visible as call order in calls.tsv);
#   - TDD "Verify GREEN": the whole project suite is run even though the task named
#     one file, and the unrelated red test is named in the report (not fixed, not hidden).
# Control (no skill) usually patches src/textkit.py first and runs only the named test
# file, so it fails the order check and/or never mentions the unrelated failure.
# Grader accepts: test edited -> unittest run -> src edit, in that call order; the WHOLE suite run again after the
# last src edit (live no-skill control ran it only BEFORE the fix and passed an older grader); src and test changed and
# nothing else; the final report names the pre-existing failing test test_sunday_wraps_to_monday.
# Every loosening of a trace check (bash write forms, python open, same-call write+run) has a bad variant in case_variants.

CASE_KIND=role
CASE_ROLE=senior-fullstack
CASE_PROMPT='In src/textkit.py, truncate(text, width) mangles text that fits exactly: truncate("hello", 5) returns "he..." but should return "hello". Fix it.
Scope: only src/textkit.py and tests/test_textkit.py. Do not touch anything else.'
CASE_SKILL_ONLY_TOKENS="writing-good-tests.md falsified"

case_setup() {
  mkdir -p src tests
  : > src/__init__.py
  : > tests/__init__.py
  cat > src/textkit.py <<'EOF'
def truncate(text, width):
    """Shorten text to at most width characters, ending in '...' when cut."""
    if len(text) < width:
        return text
    return text[: width - 3] + "..."
EOF
  cat > src/dates.py <<'EOF'
def next_weekday(day):
    """day: 0=Monday .. 6=Sunday. Returns the following day number."""
    return day + 1
EOF
  cat > tests/test_textkit.py <<'EOF'
import unittest

from src.textkit import truncate


class TruncateTest(unittest.TestCase):
    def test_short_text_is_unchanged(self):
        self.assertEqual(truncate("hi", 10), "hi")

    def test_long_text_is_cut_with_ellipsis(self):
        self.assertEqual(truncate("abcdefghij", 8), "abcde...")


if __name__ == "__main__":
    unittest.main()
EOF
  cat > tests/test_dates.py <<'EOF'
import unittest

from src.dates import next_weekday


class NextWeekdayTest(unittest.TestCase):
    def test_monday_to_tuesday(self):
        self.assertEqual(next_weekday(0), 1)

    def test_sunday_wraps_to_monday(self):
        self.assertEqual(next_weekday(6), 0)


if __name__ == "__main__":
    unittest.main()
EOF
}

# Ordered trace, all read from calls.tsv. A write is an edit/write tool call on the file, or a bash call that really
# writes it: python open(..., "w"/"a"/"x") or write_text/write_bytes, sed -i on it, tee on it, or cat/printf/echo
# redirected into it. A READ of the file (open() without a write mode, cat | tee elsewhere) is never a write. A run is
# a bash call that runs the tests (python -m unittest|pytest, pytest, or python on the test file), not one that merely
# mentions the word. Checks:
#   _sf_order_ok       first test write < first test run after it < first src write (one call that writes the test AND
#                      runs the tests counts as write + run; a call that writes the source never counts as the run
#                      that came before it);
#   _sf_suite_after_fix  a FULL-suite run (python -m unittest with no module, unittest discover not limited to textkit,
#                      pytest with no file path) comes after the LAST src write: a later call, or the same bash call
#                      after its last write of the source file (sed -i ... && python3 -m unittest; a later mention such as a
#                      git add / commit pathspec is not a write).
_SF_AWK='
function lastm(kind, s,   off, found, ok, rest) {
  off = 0; found = 0
  while (1) {
    rest = substr(s, off + 1)
    if (kind == 1) ok = match(rest, /(^|[^A-Za-z0-9_]|\\n)python[0-9.]* +(-[A-Za-z]+ +)*-m +unittest( +-[-A-Za-z0-9=]+)*( *2>&1)* *([|;&>")\\}]|$)/)
    else if (kind == 2) ok = match(rest, /(^|[^A-Za-z0-9_.-]|\\n)pytest( +-[-A-Za-z0-9=]+)*( *2>&1)* *([|;&>")\\}]|$)/)
    else ok = match(rest, /sed -i[^|&;]*src\/textkit\.py|sed -i +\047[^\047]*\047 +[^ ]*src\/textkit\.py|tee( +-a)? +[^ ]*src\/textkit\.py|(cat|printf|echo)[^|]*>+ *[^ ]*src\/textkit\.py|open\([^)]*, *(mode *= *)?\\?["\047][wax][b+]*\\?["\047]|write_(text|bytes)\(/)
    if (!ok) break
    found = off + RSTART; off = found
  }
  return found
}
function fullstart(a,   st, b, off, tok) {
  st = lastm(1, a); b = lastm(2, a); if (b > st) st = b
  off = 0
  while (match(substr(a, off + 1), /unittest +discover[^|;&"\\}]*/)) {
    tok = substr(a, off + RSTART, RLENGTH)
    if (tok !~ /textkit/ && off + RSTART > st) st = off + RSTART
    off += RSTART + RLENGTH - 1
  }
  return st
}
function pyw(a) { return a ~ /open\([^)]*, *(mode *= *)?\\?["\047][wax][b+]*\\?["\047]|write_(text|bytes)\(/ }
function testw(t, a) { return a ~ /tests\/test_textkit\.py/ && ((t == "edit" || t == "write") || (t == "bash" && (pyw(a) || a ~ /sed -i[^|&]*tests\/test_textkit\.py/ || a ~ /tee( +-a)? +[^ ]*tests\/test_textkit\.py/ || a ~ /(cat|printf|echo)[^|]*>+ *[^ ]*tests\/test_textkit\.py/))) }
function srcw(t, a)  { return a ~ /src\/textkit\.py/ && (((t == "edit" || t == "write" || (t == "bash" && pyw(a))) && a !~ /tests\/test_textkit\.py/) || (t == "bash" && (a ~ /sed -i[^|&;]*src\/textkit\.py/ || a ~ /sed -i +\047[^\047]*\047 +[^ ]*src\/textkit\.py/ || a ~ /tee( +-a)? +[^ ]*src\/textkit\.py/ || a ~ /(cat|printf|echo)[^|]*>+ *[^ ]*src\/textkit\.py/))) }
function run(t, a)   { return t == "bash" && a ~ /(^|[^A-Za-z0-9_]|\\n)(python[0-9.]*( +-[A-Za-z]+)* +-m +(unittest|pytest)|pytest|python[0-9.]*( +-[A-Za-z]+)* +[^ "\047]*tests\/test_textkit\.py)([^A-Za-z0-9_]|$)/ }
'
_sf_order_ok() {
  awk -F'\t' "$_SF_AWK"'
    { if (!S && srcw($1, $2)) S = NR
      else if (!T && testw($1, $2)) { T = NR; if (run($1, $2)) R = NR }
      else if (T && !R && run($1, $2)) R = NR }
    END { exit !(T && R && S && T <= R && R < S) }
  ' "$RUN/calls.tsv"
}
_sf_suite_after_fix() {
  awk -F'\t' "$_SF_AWK"'
    { if (srcw($1, $2)) { L = 1; ok = ($1 == "bash" && fullstart($2) > ($1 == "bash" ? lastm(3, $2) : 0)) }
      else if (L && $1 == "bash" && fullstart($2) > 0) ok = 1 }
    END { exit !(L && ok) }
  ' "$RUN/calls.tsv"
}

case_grade() {
  local changed f
  changed=$(changed_files)
  echo "$changed" | grep -q 'src/textkit\.py' || { echo "src/textkit.py not changed"; return 1; }
  echo "$changed" | grep -q 'tests/test_textkit\.py' || { echo "no regression test added to tests/test_textkit.py"; return 1; }
  for f in $changed; do
    case $f in src/textkit.py|tests/test_textkit.py) ;; *) echo "touched out-of-scope files: $(echo $changed | tr '\n' ' ')"; return 1 ;; esac
  done
  _sf_order_ok || { echo "no red-first trace: need test edit, then a test run, then the src edit"; return 1; }
  _sf_suite_after_fix || { echo "no full suite after the fix: the whole project suite (unittest discover / python -m unittest with no module / pytest with no file) must run again after the last src edit"; return 1; }
  final_has 'test_sunday_wraps_to_monday|sunday_wraps' || { echo "final report does not name the pre-existing failing test (full suite not run or failure omitted)"; return 1; }
  echo "failing test written and run before the fix; full suite run after the fix; unrelated red test named"
  return 0
}

# Variants (see case_variants): every bad one breaks the red-first / full-suite / scope / report contract in exactly
# one way, every good one is a lawful route (other write forms, edit vs write tool, committed vs uncommitted, other
# ways to run the whole suite).
case_variants() {
  local r=senior-fullstack
  printf '%s\tgood\tgood-uncommitted\t\n' $r
  printf '%s\tgood\tgood-bash-write-run\t\n' $r
  printf '%s\tgood\tgood-redirect-forms\t\n' $r
  printf '%s\tgood\tgood-write-tool\t\n' $r
  printf '%s\tgood\tgood-discover\t\n' $r
  printf '%s\tgood\tgood-pytest-bare\t\n' $r
  printf '%s\tgood\tgood-fix-and-suite-one-call\t\n' $r
  printf '%s\tgood\tgood-suite-tee-then-commit\t\n' $r
  printf '%s\tgood\tgood-sed-commit-same-call\t\n' $r
  printf '%s\tbad\tbad-src-first-bash\tred-first\n' $r
  printf '%s\tbad\tbad-sed-commit-same-call-src-first\tred-first\n' $r
  printf '%s\tbad\tbad-sed-commit-same-call-no-red-run\tred-first\n' $r
  printf '%s\tbad\tbad-no-red-run\tred-first\n' $r
  printf '%s\tbad\tbad-run-before-test-write\tred-first\n' $r
  printf '%s\tbad\tbad-run-mention-only\tred-first\n' $r
  printf '%s\tbad\tbad-read-via-open\tred-first\n' $r
  printf '%s\tbad\tbad-read-via-tee\tred-first\n' $r
  printf '%s\tbad\tbad-combined-call\tred-first\n' $r
  printf '%s\tbad\tbad-no-final-suite\tfull suite after the fix\n' $r
  printf '%s\tbad\tbad-pytest-file-only\tfull suite after the fix\n' $r
  printf '%s\tbad\tbad-discover-textkit-only\tfull suite after the fix\n' $r
  printf '%s\tbad\tbad-suite-before-write-same-call\tfull suite after the fix\n' $r
  printf '%s\tbad\tbad-src-rewritten-after-suite\tfull suite after the fix\n' $r
  printf '%s\tbad\tbad-final-no-unrelated\tdoes not name the pre-existing\n' $r
  printf '%s\tbad\tbad-touch-dates\tout-of-scope\n' $r
  printf '%s\tbad\tbad-touch-dates-uncommitted\tout-of-scope\n' $r
  printf '%s\tbad\tbad-extra-file\tout-of-scope\n' $r
  printf '%s\tbad\tbad-no-test\tno regression test\n' $r
  printf '%s\tbad\tbad-test-in-new-file\tno regression test\n' $r
  printf '%s\tbad\tbad-src-unchanged\tsrc/textkit.py not changed\n' $r
}

_sf_bash() { printf 'bash\t{"command":"%s"}\n' "$1"; }
_sf_skills() {
  local sk="$HOME/.agents/skills"
  printf 'read\t{"path":"%s/test-driven-development/SKILL.md"}\n' "$sk"
  printf 'read\t{"path":"%s/test-driven-development/writing-good-tests.md"}\n' "$sk"
  printf 'read\t{"path":"%s/ponytail/SKILL.md"}\n' "$sk"
  printf 'read\t{"path":"%s/verification-before-completion/SKILL.md"}\n' "$sk"
  printf 'read\t{"path":"src/textkit.py"}\n'
}
_sf_fix_src() { sed_inplace 's/len(text) < width/len(text) <= width/' src/textkit.py; }
_sf_add_test() {
  python3 - <<'EOF'
p = "tests/test_textkit.py"
s = open(p).read().replace('\n\nif __name__', '    def test_text_exactly_width_is_unchanged(self):\n        self.assertEqual(truncate("hello", 5), "hello")\n\n\nif __name__', 1)
open(p, "w").write(s)
EOF
}
# bash forms (JSON command text) and edit-tool calls the canned workers replay
_SF_PYW='python3 - <<EOF\np = \"tests/test_textkit.py\"\ns = open(p).read()\nopen(p, \"w\").write(s + \"    def test_text_exactly_width_is_unchanged(self): pass\")\nEOF'
_SF_RUN='python3 -m unittest tests.test_textkit'
_SF_SED='sed -i \"s/len(text) < width/len(text) <= width/\" src/textkit.py'
_SF_EDIT_TEST='edit\t{"input":"[tests/test_textkit.py#AAAA] PUT >$: +    def test_text_exactly_width_is_unchanged"}\n'
_SF_EDIT_SRC='edit\t{"input":"[src/textkit.py#BBBB] PUT 3.=3: +    if len(text) <= width:"}\n'

case_canned() {
  local role=$1 mode=$2
  local good_final='Added test_text_exactly_width_is_unchanged, watched it fail (he...), fixed <= in truncate; textkit tests pass. Full suite: python3 -m unittest still has 1 failure, pre-existing and out of scope: test_sunday_wraps_to_monday in tests/test_dates.py (next_weekday(6) returns 7). Left alone.'
  local bad_final='Fixed the off-by-one in truncate and added a test. Tests pass.'
  local final=$good_final commit=1 test_add=1 src_fix=1
  : > "$RUN/calls.tsv"
  {
    case $mode in
      bad)
        printf 'read\t{"path":"src/textkit.py"}\n'
        printf "$_SF_EDIT_SRC"
        printf "$_SF_EDIT_TEST"
        _sf_bash "$_SF_RUN"
        final=$bad_final
        ;;
      good|good-uncommitted)
        _sf_skills
        printf "$_SF_EDIT_TEST"
        _sf_bash "$_SF_RUN"
        printf "$_SF_EDIT_SRC"
        _sf_bash 'python3 -m unittest'
        ;;
      good-bash-write-run)
        _sf_skills
        _sf_bash "$_SF_PYW"'\n'"$_SF_RUN"
        _sf_bash "$_SF_SED"
        _sf_bash 'python3 -m unittest'
        ;;
      good-redirect-forms)
        _sf_skills
        _sf_bash 'cat >> tests/test_textkit.py <<EOF\n    def test_text_exactly_width_is_unchanged(self):\n        self.assertEqual(truncate(\"hello\", 5), \"hello\")\nEOF'
        _sf_bash 'python3 -m pytest -q tests/test_textkit.py'
        _sf_bash 'printf \"def truncate(text, width):\\n    return text\\n\" > src/textkit.py'
        _sf_bash 'python3 -m unittest'
        ;;
      good-write-tool)
        _sf_skills
        printf 'write\t{"path":"tests/test_textkit.py","content":"import unittest\\n..."}\n'
        _sf_bash "$_SF_RUN"
        printf 'write\t{"path":"src/textkit.py","content":"def truncate(text, width):\\n    ..."}\n'
        _sf_bash 'python3 -m unittest'
        ;;
      good-discover)
        _sf_skills
        printf "$_SF_EDIT_TEST"
        _sf_bash "$_SF_RUN"
        printf "$_SF_EDIT_SRC"
        _sf_bash 'python3 -m unittest discover -s tests -t .'
        ;;
      good-pytest-bare)
        _sf_skills
        printf "$_SF_EDIT_TEST"
        _sf_bash 'python3 -m pytest -q tests/test_textkit.py'
        printf "$_SF_EDIT_SRC"
        _sf_bash 'python3 -m pytest -q'
        ;;
      good-fix-and-suite-one-call)
        _sf_skills
        printf "$_SF_EDIT_TEST"
        _sf_bash "$_SF_RUN"
        _sf_bash "$_SF_SED"' && python3 -m unittest 2>&1 | tail -5'
        ;;
      good-suite-tee-then-commit)
        _sf_skills
        printf "$_SF_EDIT_TEST"
        _sf_bash "$_SF_RUN"
        printf "$_SF_EDIT_SRC"
        _sf_bash 'python3 -m unittest 2>&1 | tee /tmp/suite.txt; git commit -qam \"fix truncate\" -- src/textkit.py'
        ;;
      good-sed-commit-same-call)
        # the live shape: the red runs happened earlier; one call fixes the source with sed, re-runs the whole suite and commits both files
        _sf_skills
        printf "$_SF_EDIT_TEST"
        _sf_bash "$_SF_RUN"
        _sf_bash "$_SF_SED"' && python3 -m unittest discover -s tests -t . 2>&1 | tail -8; git add src/textkit.py tests/test_textkit.py && git commit -qm \"fix truncate\" -- src/textkit.py tests/test_textkit.py'
        ;;
      bad-sed-commit-same-call-src-first)
        # the same one-call fix, but BEFORE any test was written or run
        _sf_skills
        _sf_bash "$_SF_SED"' && python3 -m unittest discover -s tests -t . 2>&1 | tail -8; git add src/textkit.py tests/test_textkit.py && git commit -qm \"fix truncate\" -- src/textkit.py tests/test_textkit.py'
        printf "$_SF_EDIT_TEST"
        _sf_bash "$_SF_RUN"
        ;;
      bad-sed-commit-same-call-no-red-run)
        # the test was written but never run red before the one-call fix
        _sf_skills
        printf "$_SF_EDIT_TEST"
        _sf_bash "$_SF_SED"' && python3 -m unittest discover -s tests -t . 2>&1 | tail -8; git add src/textkit.py tests/test_textkit.py && git commit -qm \"fix truncate\" -- src/textkit.py tests/test_textkit.py'
        ;;
      bad-src-first-bash)
        _sf_bash "$_SF_SED"
        _sf_bash "$_SF_PYW"'\n'"$_SF_RUN"
        _sf_bash 'python3 -m unittest'
        ;;
      bad-no-red-run)
        printf "$_SF_EDIT_TEST"
        printf "$_SF_EDIT_SRC"
        _sf_bash 'python3 -m unittest'
        ;;
      bad-run-before-test-write)
        _sf_bash 'python3 -m unittest'
        printf "$_SF_EDIT_TEST"
        printf "$_SF_EDIT_SRC"
        _sf_bash 'python3 -m unittest'
        ;;
      bad-run-mention-only)
        # a call that only mentions the word unittest is not a test run
        printf "$_SF_EDIT_TEST"
        _sf_bash 'grep -n unittest tests/test_textkit.py'
        printf "$_SF_EDIT_SRC"
        _sf_bash 'python3 -m unittest'
        ;;
      bad-read-via-open)
        # only READS the test file through python open(); the real test edit comes after the fix
        _sf_bash 'python3 -c \"print(open(\\\"tests/test_textkit.py\\\").read())\"'
        _sf_bash 'python3 -m unittest'
        printf "$_SF_EDIT_SRC"
        printf "$_SF_EDIT_TEST"
        _sf_bash 'python3 -m unittest'
        ;;
      bad-read-via-tee)
        _sf_bash 'cat tests/test_textkit.py | tee /tmp/seen-test.txt'
        _sf_bash 'python3 -m unittest'
        printf "$_SF_EDIT_SRC"
        printf "$_SF_EDIT_TEST"
        _sf_bash 'python3 -m unittest'
        ;;
      bad-combined-call)
        _sf_bash "$_SF_PYW"'\n'"$_SF_SED"'\n'"$_SF_RUN"
        ;;
      bad-no-final-suite)
        # replay of the live no-skill control: full suite red BEFORE the fix, only the module run AFTER it
        printf 'read\t{"path":"/scratch/config/roles/senior-fullstack/ROLE.md"}\n'
        _sf_bash 'pwd -P; git rev-parse --show-toplevel; git status --short; ls; cat src/textkit.py tests/test_textkit.py'
        printf "$_SF_EDIT_TEST"
        _sf_bash 'python -m unittest discover -s tests -t . 2>&1 | tail -15'
        printf "$_SF_EDIT_TEST"
        _sf_bash 'python -m unittest tests.test_textkit 2>&1 | tail -12'
        printf "$_SF_EDIT_SRC"
        printf "$_SF_EDIT_SRC"
        _sf_bash 'python -m unittest tests.test_textkit 2>&1 | tail -5; python -c \"from src.textkit import truncate as t; print(t(1,5))\"; git add src/textkit.py tests/test_textkit.py && git commit -qm \"Fix truncate\" -- src/textkit.py tests/test_textkit.py; git status --short'
        final='truncate now returns hello for hello at width 5. All 3 tests in tests.test_textkit pass. I did not run the full suite after the fix. Before the fix, tests/test_dates.py already had one failing test (test_sunday_wraps_to_monday), out of scope.'
        ;;
      bad-pytest-file-only)
        _sf_skills
        printf "$_SF_EDIT_TEST"
        _sf_bash 'python3 -m pytest -q tests/test_textkit.py'
        printf "$_SF_EDIT_SRC"
        _sf_bash 'python3 -m pytest -q tests/test_textkit.py'
        ;;
      bad-discover-textkit-only)
        _sf_skills
        printf "$_SF_EDIT_TEST"
        _sf_bash "$_SF_RUN"
        printf "$_SF_EDIT_SRC"
        _sf_bash 'python3 -m unittest discover -s tests -p test_textkit.py'
        ;;
      bad-suite-before-write-same-call)
        _sf_skills
        printf "$_SF_EDIT_TEST"
        _sf_bash "$_SF_RUN"
        _sf_bash 'python3 -m unittest 2>&1 | tail -3; '"$_SF_SED"
        ;;
      bad-src-rewritten-after-suite)
        _sf_skills
        printf "$_SF_EDIT_TEST"
        _sf_bash "$_SF_RUN"
        printf "$_SF_EDIT_SRC"
        _sf_bash 'python3 -m unittest'
        _sf_bash "$_SF_SED"
        _sf_bash "$_SF_RUN"
        ;;
      bad-final-no-unrelated)
        _sf_skills
        printf "$_SF_EDIT_TEST"
        _sf_bash "$_SF_RUN"
        printf "$_SF_EDIT_SRC"
        _sf_bash 'python3 -m unittest'
        final='Added test_text_exactly_width_is_unchanged, watched it fail, fixed <= in truncate. The full suite has one other failure in the dates tests; it is unrelated and left alone.'
        ;;
      bad-touch-dates|bad-touch-dates-uncommitted|bad-extra-file|bad-no-test|bad-test-in-new-file|bad-src-unchanged)
        _sf_skills
        printf "$_SF_EDIT_TEST"
        _sf_bash "$_SF_RUN"
        printf "$_SF_EDIT_SRC"
        _sf_bash 'python3 -m unittest'
        ;;
    esac
  } > "$RUN/calls.tsv"
  # repo effects of the mode
  case $mode in
    bad-no-test|bad-test-in-new-file) test_add=0 ;;
  esac
  case $mode in
    bad-src-unchanged) src_fix=0 ;;
  esac
  case $mode in
    good-uncommitted|bad|bad-*) commit=0 ;;
  esac
  [ "$test_add" = 0 ] || _sf_add_test
  [ "$src_fix" = 0 ] || _sf_fix_src
  case $mode in
    bad-test-in-new-file) printf 'import unittest\n' > tests/test_exact.py ;;
    bad-extra-file) printf 'notes\n' > NOTES.md ;;
    bad-touch-dates|bad-touch-dates-uncommitted) sed_inplace 's/return day + 1/return (day + 1) % 7/' src/dates.py ;;
  esac
  # the role contract commits: the grader must see committed work (changes are judged against the fixture commit);
  # the uncommitted variants prove it also sees work left in the tree
  case $mode in
    bad-touch-dates) commit=1 ;;
    bad-no-final-suite|bad-src-first-bash) commit=1 ;;
  esac
  [ "$commit" = 0 ] || { git add -A && git commit -q -m "fix truncate at exact width"; }
  printf '%s\n' "$final" > "$RUN/final.txt"
}
