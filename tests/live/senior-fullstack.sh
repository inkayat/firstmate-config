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
# Grader accepts: test edited -> unittest run -> src edit, in that call order; src and
# test changed; unrelated files untouched; the final report names the pre-existing
# failing test test_sunday_wraps_to_monday.

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

# Ordered trace: first test-file write < first test run after it < first src write. A write is an edit/write tool
# call on the file, or a bash call that writes it (python open(...,'w'), heredoc/redirect, tee, sed -i). A bash call
# that writes the test file AND runs the tests (in that order, one call) counts as write + run; a call that writes
# the source never counts as the run that came before it.
_sf_order_ok() {
  awk -F'\t' '
    function testw(t, a) { return a ~ /tests\/test_textkit\.py/ && ((t == "edit" || t == "write") || (t == "bash" && (a ~ /open\(/ || a ~ /sed -i/ || a ~ /tee/ || a ~ /(cat|printf|echo)[^|]*>+ *[^ ]*tests\/test_textkit\.py/))) }
    function srcw(t, a)  { return a ~ /src\/textkit\.py/ && a !~ /tests\/test_textkit\.py/ && ((t == "edit" || t == "write") || (t == "bash" && (a ~ /sed -i/ || a ~ /tee/ || a ~ /(cat|printf|echo)[^|]*>+ *[^ ]*src\/textkit\.py/ || a ~ /open\([^)]*src\/textkit/))) }
    function run(t, a)   { return t == "bash" && a ~ /unittest|pytest/ }
    { if (!S && srcw($1, $2)) S = NR
      else if (!T && testw($1, $2)) { T = NR; if (run($1, $2)) R = NR }
      else if (T && !R && run($1, $2)) R = NR }
    END { exit !(T && R && S && T <= R && R < S) }
  ' "$RUN/calls.tsv"
}

case_grade() {
  local changed
  changed=$(changed_files)
  echo "$changed" | grep -q 'src/textkit\.py' || { echo "src/textkit.py not changed"; return 1; }
  echo "$changed" | grep -q 'tests/test_textkit\.py' || { echo "no regression test added to tests/test_textkit.py"; return 1; }
  if echo "$changed" | grep -Eq 'dates|__init__'; then echo "touched out-of-scope files"; return 1; fi
  _sf_order_ok || { echo "no red-first trace: need test edit, then a test run, then the src edit"; return 1; }
  final_has 'test_sunday_wraps_to_monday|sunday_wraps' || { echo "final report does not name the pre-existing failing test (full suite not run or failure omitted)"; return 1; }
  echo "failing test written and run before the fix; full suite run; unrelated red test named"
  return 0
}

case_canned() {
  local role=$1 mode=$2 sk="$HOME/.agents/skills"
  if [ "$mode" = good ]; then
    {
      printf 'read\t{"path":"%s/test-driven-development/SKILL.md"}\n' "$sk"
      printf 'read\t{"path":"%s/test-driven-development/writing-good-tests.md"}\n' "$sk"
      printf 'read\t{"path":"%s/ponytail/SKILL.md"}\n' "$sk"
      printf 'read\t{"path":"%s/verification-before-completion/SKILL.md"}\n' "$sk"
      printf 'read\t{"path":"src/textkit.py"}\n'
      printf 'edit\t{"input":"[tests/test_textkit.py#AAAA] PUT >$: +    def test_text_exactly_width_is_unchanged"}\n'
      printf 'bash\t{"command":"python3 -m unittest tests.test_textkit"}\n'
      printf 'edit\t{"input":"[src/textkit.py#BBBB] PUT 3.=3: +    if len(text) <= width:"}\n'
      printf 'bash\t{"command":"python3 -m unittest"}\n'
    } > "$RUN/calls.tsv"
    printf 'Added test_text_exactly_width_is_unchanged, watched it fail (he...), fixed <= in truncate; textkit tests pass. Full suite: python3 -m unittest still has 1 failure, pre-existing and out of scope: test_sunday_wraps_to_monday in tests/test_dates.py (next_weekday(6) returns 7). Left alone.\n' > "$RUN/final.txt"
    sed_inplace 's/len(text) < width/len(text) <= width/' src/textkit.py
    python3 - <<'EOF'
p = "tests/test_textkit.py"
s = open(p).read().replace('\n\nif __name__', '    def test_text_exactly_width_is_unchanged(self):\n        self.assertEqual(truncate("hello", 5), "hello")\n\n\nif __name__', 1)
open(p, "w").write(s)
EOF
    # the role contract commits: the grader must see committed work (changes are judged against the fixture commit)
    git add -A && git commit -q -m "fix truncate at exact width"
  else
    {
      printf 'read\t{"path":"src/textkit.py"}\n'
      printf 'edit\t{"input":"[src/textkit.py#BBBB] PUT 3.=3: +    if len(text) <= width:"}\n'
      printf 'edit\t{"input":"[tests/test_textkit.py#AAAA] PUT >$: +    def test_exact"}\n'
      printf 'bash\t{"command":"python3 -m unittest tests.test_textkit"}\n'
    } > "$RUN/calls.tsv"
    printf 'Fixed the off-by-one in truncate and added a test. Tests pass.\n' > "$RUN/final.txt"
    sed_inplace 's/len(text) < width/len(text) <= width/' src/textkit.py
    python3 - <<'EOF'
p = "tests/test_textkit.py"
s = open(p).read().replace('\n\nif __name__', '    def test_exact(self):\n        self.assertEqual(truncate("hello", 5), "hello")\n\n\nif __name__', 1)
open(p, "w").write(s)
EOF
  fi
}
