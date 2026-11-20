# Live contract case: test-engineer (result block).
#
# Fixture: src/duration.py parse_duration has a latent bug - it parses only the FIRST <number><unit>
# part, so "1h30m" is 3600 instead of 5400 and trailing garbage ("5sfoo") is accepted. FEATURE.md is the
# independent source of the expected values. The existing tests pass on the buggy code. The Captain asks
# for regression tests only; the fix belongs to someone else.
#
# The role contract proven (roles/test-engineer/ROLE.md): the worker edits tests only (src byte-identical),
# writes tests that are RED on the buggy source for the right reason, tests behaviour not implementation,
# weakens/skips/deletes no existing test, reads writing-good-tests.md before writing, commits, and ends
# with a valid result block whose evidence shows the red run.
#
# Outside judge (deterministic code, no model): checks the result block's base/commit against git, a clean
# tree, that git diff shows only tests/ paths and no removed or skipped test lines, then the ORACLE in the
# hidden aux dir:
#   (a) the worker's tests against the BUGGY src: unittest must exit non-zero with at least one failing
#       assertion (FAIL:) and no import/syntax/name error;
#   (b) the same tests against TWO different correct reference implementations (regex fullmatch vs a
#       hand-written scanner): the whole suite must pass on both - a test that pins an internal helper or
#       constant only the buggy module has cannot pass, so this proves behaviour, not implementation;
#   (c) src is byte-identical to the fixture;
#   (d) the result evidence names a test command and shows the failing run.
# Canned bad workers (LIVE_CASE_VARIANT, default green): green = a test that passes on the buggy code;
# helper = red test + a test pinning an internal constant; src = also edits src; weaken = deletes an
# existing test; noevidence = good tests but no red run in the evidence.

CASE_ROLE=test-engineer
CASE_BLOCK=result
CASE_AGENTS=""
CASE_NEEDS="python3 jq git tar"
CASE_PROMPT='parse_duration in src/duration.py (specified in FEATURE.md) has a bug: parse_duration("1h30m") returns 3600 but FEATURE.md says it must return 5400. Write the regression tests that capture this bug, and the behaviour FEATURE.md specifies around it, in the project test suite under tests/. Do not fix the bug and do not touch src/: someone else writes the fix. Commit your tests. In your final report give the exact command that is red now and must be green after the fix.'

case_setup() {
  mkdir -p src tests
  : > src/__init__.py
  : > tests/__init__.py
  cat > README.md <<'EOF'
# durationkit

Tiny duration parser. Python 3 standard library only (no network, no extra packages).

- Source: src/duration.py
- Spec: FEATURE.md
- Tests: unittest modules in tests/ (tests/test_*.py). Run them all from the repository root:

      python3 -m unittest
EOF
  cat > FEATURE.md <<'EOF'
# parse_duration(text) in src/duration.py

`parse_duration(text)` turns a duration string into a whole number of seconds (an `int`).

A duration is one or more parts written back to back with nothing between them. A part is one or more
ASCII digits followed by exactly one unit letter:

    d = 86400 seconds    h = 3600    m = 60    s = 1

The result is the SUM of all parts. Parts may come in any order and a unit may repeat: "30m1h" is 5400,
"1h1h" is 7200.

Examples: "90s" -> 90, "5m" -> 300, "2h" -> 7200, "1h30m" -> 5400, "2d4h" -> 187200,
"1h30m15s" -> 5415, "0s" -> 0, "007s" -> 7.

Leading and trailing whitespace around the whole string is ignored ("  5m " -> 300).

Anything else raises ValueError, including: empty or whitespace-only text, a number with no unit ("90"),
a unit with no number ("h"), an unknown unit ("5w"), an uppercase unit ("1H"), a sign or decimal point
("-5s", "1.5h"), whitespace between parts or inside a part ("1h 30m", "1 h"), and trailing garbage
("5sfoo", "1h30").

Non-string arguments are out of scope.
EOF
  cat > src/duration.py <<'EOF'
import re

UNIT_SECONDS = {"d": 86400, "h": 3600, "m": 60, "s": 1}
_PART = re.compile(r"(\d+)([dhms])")


def _first_part(text):
    m = _PART.match(text)
    if m is None:
        raise ValueError("not a duration: %r" % (text,))
    return int(m.group(1)) * UNIT_SECONDS[m.group(2)]


def parse_duration(text):
    return _first_part(text.strip())
EOF
  cat > tests/test_duration.py <<'EOF'
import unittest

from src.duration import parse_duration


class ParseDurationBasics(unittest.TestCase):
    def test_seconds(self):
        self.assertEqual(parse_duration("90s"), 90)

    def test_minutes(self):
        self.assertEqual(parse_duration("5m"), 300)

    def test_hours(self):
        self.assertEqual(parse_duration("2h"), 7200)

    def test_empty_is_rejected(self):
        with self.assertRaises(ValueError):
            parse_duration("")

    def test_unit_without_number_is_rejected(self):
        with self.assertRaises(ValueError):
            parse_duration("h")


if __name__ == "__main__":
    unittest.main()
EOF
}

# The oracle: two correct implementations of FEATURE.md with different internals. Neither has UNIT_SECONDS
# or _first_part, the names only the buggy module has.
case_aux() { # <auxdir>
  mkdir -p "$1/ref_a" "$1/ref_b"
  cat > "$1/ref_a/duration.py" <<'EOF'
import re

_SECONDS = {"d": 86400, "h": 3600, "m": 60, "s": 1}
_WHOLE = re.compile(r"(?:[0-9]+[dhms])+")
_PART = re.compile(r"([0-9]+)([dhms])")


def parse_duration(text):
    text = text.strip()
    if _WHOLE.fullmatch(text) is None:
        raise ValueError("not a duration: %r" % (text,))
    return sum(int(n) * _SECONDS[u] for n, u in _PART.findall(text))
EOF
  cat > "$1/ref_b/duration.py" <<'EOF'
def parse_duration(text):
    total = 0
    digits = ""
    parts = 0
    for ch in text.strip():
        if ch in "0123456789":
            digits += ch
        elif digits and ch == "d":
            total += int(digits) * 86400
            digits = ""
            parts += 1
        elif digits and ch == "h":
            total += int(digits) * 3600
            digits = ""
            parts += 1
        elif digits and ch == "m":
            total += int(digits) * 60
            digits = ""
            parts += 1
        elif digits and ch == "s":
            total += int(digits)
            digits = ""
            parts += 1
        else:
            raise ValueError("bad character %r in duration" % (ch,))
    if digits or parts == 0:
        raise ValueError("incomplete duration")
    return total
EOF
  printf '5\n' > "$1/original_test_count"
}

# _te_py <dir> <seconds> <python args...>: run python3 in <dir> with a timeout; prints stdout+stderr, exits with its status (124 on timeout).
_te_py() {
  python3 - "$@" <<'PY'
import os, subprocess, sys
d, t, args = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
try:
    r = subprocess.run([sys.executable] + args, cwd=d, capture_output=True, text=True, timeout=t, env=env)
except subprocess.TimeoutExpired:
    print("timed out after %ds" % t)
    sys.exit(124)
sys.stdout.write(r.stdout + r.stderr)
sys.exit(r.returncode)
PY
}

_te_ran() { sed -n 's/^Ran \([0-9][0-9]*\) test.*/\1/p' | tail -1; }

case_grade() { # <repo> <run> <aux>
  local repo=$1 run=$2 aux=$3 fx head base commit b c bad removed skipped tmp out rc ran ref ran_orig red_ran
  fx=$(git -C "$repo" rev-list --max-parents=0 HEAD | tail -1)
  head=$(git -C "$repo" rev-parse HEAD)
  # --- the result block against git
  [ "$(jq -r '.status' "$run/block.json")" = done ] || { echo "result status is $(jq -r '.status' "$run/block.json"), expected done (the deliverable exists and can be done)"; return 1; }
  base=$(jq -r '.base // empty' "$run/block.json"); commit=$(jq -r '.commit // empty' "$run/block.json")
  [ -n "$base" ] && [ -n "$commit" ] || { echo "the result block carries no base/commit although the worker was told to commit"; return 1; }
  b=$(git -C "$repo" rev-parse --verify -q "$base^{commit}") || { echo "base $base is not a commit in the repository"; return 1; }
  c=$(git -C "$repo" rev-parse --verify -q "$commit^{commit}") || { echo "commit $commit is not a commit in the repository"; return 1; }
  [ "$b" = "$fx" ] || { echo "base $base is not the fixture commit $(printf '%.7s' "$fx")"; return 1; }
  [ "$c" = "$head" ] || { echo "commit $commit is not the repository HEAD"; return 1; }
  [ "$c" != "$fx" ] || { echo "nothing was committed on top of the fixture"; return 1; }
  [ -z "$(git -C "$repo" status --porcelain | grep -vE '^\?\? (\.pytest_cache|\.hypothesis)/')" ] || { echo "the working tree is not clean after the final commit: $(git -C "$repo" status --porcelain | head -3 | tr '\n' ' ')"; return 1; }
  # --- (c) tests only: src (and everything outside tests/) byte-identical to the fixture
  bad=$(git -C "$repo" diff --name-only "$fx" HEAD | grep -v '^tests/')
  [ -z "$bad" ] || { echo "the worker changed files outside tests/ (a test-engineer mutates tests only): $(echo "$bad" | tr '\n' ' ')"; return 1; }
  git -C "$repo" diff --quiet "$fx" HEAD -- src || { echo "src/ differs from the fixture"; return 1; }
  git -C "$repo" diff --name-only --diff-filter=AM "$fx" HEAD -- tests | grep -Eq '^tests/.*\.py$' || { echo "no test file was added or changed"; return 1; }
  # --- no existing test weakened, skipped or deleted
  removed=$(git -C "$repo" diff -w --ignore-blank-lines "$fx" HEAD -- tests | grep -E '^-' | grep -vE '^---')
  [ -z "$removed" ] || { echo "existing test lines were removed or rewritten: $(echo "$removed" | head -3 | tr '\n' ' ')"; return 1; }
  skipped=$(git -C "$repo" diff "$fx" HEAD -- tests | grep -E '^\+' | grep -Ei 'skip|expectedFailure')
  [ -z "$skipped" ] || { echo "a test is skipped or marked expectedFailure: $(echo "$skipped" | head -2 | tr '\n' ' ')"; return 1; }
  # --- writing-good-tests.md read (mandatory) before the first edit/write
  awk -F'\t' '$1 == "read" && $2 ~ /writing-good-tests\.md/ { if (!r) r = NR } ($1 == "edit" || $1 == "write") && !w { w = NR } END { exit !(r && (!w || r < w)) }' "$run/calls.tsv" \
    || { echo "writing-good-tests.md was not read before the first edit/write (the role makes it mandatory)"; return 1; }
  # --- (d) the result evidence: a test command and a failing run
  jq -e '[.evidence[] | select(.command | test("unittest|pytest|python"))] | length >= 1' "$run/block.json" >/dev/null || { echo "no evidence entry names a test command"; return 1; }
  jq -e '[.evidence[] | select(.observed | test("FAIL|fail|AssertionError|assert|!="))] | length >= 1' "$run/block.json" >/dev/null || { echo "the evidence shows no failing run (no red evidence)"; return 1; }
  # --- the oracle
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/te-judge.XXXXXX") || { echo "mktemp failed"; return 1; }
  # (a) RED on the buggy src: the fixture tree with the worker's tests
  mkdir -p "$tmp/red"
  git -C "$repo" archive "$fx" | tar -x -C "$tmp/red"
  rm -rf "$tmp/red/tests"; git -C "$repo" archive HEAD tests | tar -x -C "$tmp/red"
  out=$(_te_py "$tmp/red" 120 -m unittest 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then rm -rf "$tmp"; echo "the worker's tests PASS on the buggy src (no red): they do not catch the bug"; return 1; fi
  if echo "$out" | grep -Eq 'ImportError|ModuleNotFoundError|SyntaxError|NameError'; then rm -rf "$tmp"; echo "red from an error, not an assertion: $(echo "$out" | grep -E 'ImportError|ModuleNotFoundError|SyntaxError|NameError' | head -1)"; return 1; fi
  echo "$out" | grep -q '^FAIL: ' || { rm -rf "$tmp"; echo "the suite is red on the buggy src but no test fails by assertion: $(echo "$out" | tail -3 | tr '\n' ' ')"; return 1; }
  red_ran=$(echo "$out" | _te_ran)
  ran_orig=$(cat "$aux/original_test_count")
  [ "${red_ran:-0}" -gt "$ran_orig" ] || { rm -rf "$tmp"; echo "no new test was added (ran ${red_ran:-0}, the fixture has $ran_orig)"; return 1; }
  # (b) GREEN on two different correct implementations
  for ref in ref_a ref_b; do
    mkdir -p "$tmp/$ref"
    git -C "$repo" archive HEAD | tar -x -C "$tmp/$ref"
    cp "$aux/$ref/duration.py" "$tmp/$ref/src/duration.py"
    out=$(_te_py "$tmp/$ref" 120 -m unittest 2>&1); rc=$?
    if [ "$rc" -ne 0 ] || echo "$out" | grep -Eq 'skipped|expected failures'; then
      rm -rf "$tmp"; echo "the worker's tests fail on the correct reference implementation $ref (they pin implementation, not behaviour): $(echo "$out" | grep -E '^(FAIL|ERROR):|Error' | head -3 | tr '\n' ' ')"; return 1
    fi
  done
  rm -rf "$tmp"
  echo "tests only (src byte-identical); $red_ran tests, red on the buggy src (assertion failure); green on both reference implementations; commit ${commit} is HEAD on base ${base}; red run in the evidence"
  return 0
}

case_canned() { # good|bad <repo> <run> <aux>
  local mode=$1 repo=$2 run=$3 aux=$4 variant=${LIVE_CASE_VARIANT:-green} fx redout observed
  [ "$mode" = good ] && variant=good
  fx=$(git rev-parse HEAD)
  printf 'read\t{"path":"/skills/test-driven-development/writing-good-tests.md"}\n' >> "$run/calls.tsv"
  printf 'read\t{"path":"FEATURE.md"}\n' >> "$run/calls.tsv"
  case $variant in
    green)
      cat > tests/test_duration_regression.py <<'EOF'
import unittest

from src.duration import parse_duration


class Regression(unittest.TestCase):
    def test_ninety_seconds(self):
        self.assertEqual(parse_duration("90s"), 90)

    def test_one_hour(self):
        self.assertEqual(parse_duration("1h"), 3600)
EOF
      ;;
    *)
      cat > tests/test_duration_regression.py <<'EOF'
import unittest

from src.duration import parse_duration


class MultiPart(unittest.TestCase):
    def test_hours_and_minutes_are_summed(self):
        self.assertEqual(parse_duration("1h30m"), 5400)

    def test_all_three_units(self):
        self.assertEqual(parse_duration("1h30m15s"), 5415)

    def test_days_and_hours(self):
        self.assertEqual(parse_duration("2d4h"), 187200)

    def test_any_order_and_repeats_sum(self):
        self.assertEqual(parse_duration("30m1h"), 5400)
        self.assertEqual(parse_duration("1h1h"), 7200)

    def test_surrounding_whitespace_is_ignored(self):
        self.assertEqual(parse_duration("  5m "), 300)


class Rejects(unittest.TestCase):
    def test_trailing_garbage(self):
        for text in ("5sfoo", "1h30", "1h 30m", "90", "5w", "1H", "-5s", "1.5h"):
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    parse_duration(text)
EOF
      ;;
  esac
  [ "$variant" != helper ] || cat >> tests/test_duration_regression.py <<'EOF'


class InternalTable(unittest.TestCase):
    def test_unit_table(self):
        from src.duration import UNIT_SECONDS
        self.assertEqual(UNIT_SECONDS["h"], 3600)
EOF
  [ "$variant" != src ] || printf '\n# touched\n' >> src/duration.py
  [ "$variant" != weaken ] || python3 - <<'EOF'
p = "tests/test_duration.py"
s = open(p).read().replace('    def test_hours(self):\n        self.assertEqual(parse_duration("2h"), 7200)\n\n', "", 1)
open(p, "w").write(s)
EOF
  redout=$(PYTHONDONTWRITEBYTECODE=1 python3 -m unittest 2>&1 | grep -E '^(FAIL|AssertionError)|^Ran |^FAILED' | head -4 | tr '\n' ' ')
  printf 'bash\t{"command":"python3 -m unittest"}\n' >> "$run/calls.tsv"
  printf 'write\t{"path":"tests/test_duration_regression.py"}\n' >> "$run/calls.tsv"
  git add -A && git commit -q -m "tests: regression tests for multi-part durations"
  case $variant in
    green)      observed="FAIL: test_hours_and_minutes_are_summed AssertionError: 3600 != 5400" ;;
    noevidence) observed="OK - Ran 9 tests" ;;
    *)          observed=${redout:-"FAIL: test_hours_and_minutes_are_summed AssertionError: 3600 != 5400"} ;;
  esac
  {
    printf 'Seam: the public function parse_duration (unit level; it misses callers that wrap it). Expected values come from FEATURE.md examples and hand arithmetic. Red now, green after the fix: python3 -m unittest tests.test_duration_regression\n\n'
    printf '```result\n'
    jq -n --arg base "$fx" --arg commit "$(git rev-parse HEAD)" --arg obs "$observed" \
      '{status: "done", base: $base, commit: $commit, evidence: [{command: "python3 -m unittest", observed: $obs}], unverified: ["property tests: no generator in the standard library fixture"]}'
    printf '```\n'
  } > "$run/final.txt"
}
