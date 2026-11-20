# Live workflow case (ix): delegated-build (implement -> deliver recorded), the no-mistakes composition.
# Problem: slugify(text, max_len=None) in a new textutil.py, fully specified in the ticket. The delivery path is no-mistakes, so
#   the workflow has NO independent qa, review or security step: the implementer works, commits and reports with the result block,
#   and delivery is RECORDED (the fixture has no remote and nothing is ever pushed; the driver tags workflow-delivered).
# Outside judge (deterministic): the engine path is exactly implement:done deliver:done and the workflow definition has no qa, review
#   or security step; the steps directory holds exactly one worker transcript (the implementer); the result block is valid, bound to
#   base..commit (the commit is the repository HEAD, past the fixture) and carries evidence; the hidden kit (the ticket rules, checked
#   over many inputs) and the project tests pass on the final repository; nothing was pushed (no remote exists).
# No loop and no control: the kit is the judge. Offline negative: a wrong implementation fails the hidden check.
CASE_WORKFLOW=delegated-build
CASE_TASK='Add slugify(text, max_len=None) in a new module textutil.py. It lowercases the text (ASCII), turns every run of characters that are not a-z or 0-9 into a single hyphen, and strips hyphens from both ends; an empty or all-punctuation text gives an empty string. With max_len given, the slug is cut to at most max_len characters and a hyphen left at the end by the cut is removed. Keep the change small and add tests under tests/.'
CASE_NO_CONTROL=1
CASE_EXPECT_PATH='^implement:done deliver:done$'
CASE_FORCE_AFTER=''
CASE_NEGATIVE='wrong => the final repository does not satisfy the hidden acceptance check'

case_setup() {
  mkdir -p tests
  cat > README.md <<'R'
# textutil
Small text helpers. Tests: python3 -m unittest discover -s tests
R
  cat > tests/test_smoke.py <<'R'
import unittest


class Smoke(unittest.TestCase):
    def test_python(self):
        self.assertEqual(1 + 1, 2)


if __name__ == "__main__":
    unittest.main()
R
}

case_kit_setup() {
  cat > "$1/kit.py" <<'R'
import random
import re
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
try:
    from textutil import slugify
except Exception as e:
    print("FAIL cannot import slugify from textutil.py: %r" % (e,))
    sys.exit(1)


def oracle(text, max_len=None):
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    if max_len is not None:
        s = s[:max_len].rstrip("-")
    return s


fixed = [("Hello, World!", None), ("  Multiple   spaces ", None), ("a--b", None), ("", None), ("---", None), ("Python 3.12", None),
         ("Hello, World!", 5), ("Hello, World!", 6), ("ab cd", 3), ("x", 0), ("The Quick Brown Fox", 9)]
rng = random.Random(7)
alphabet = "abcXYZ019 -_.,!"
cases = fixed + [("".join(rng.choice(alphabet) for _ in range(rng.randint(0, 14))), rng.choice([None, None, 0, 1, 3, 8])) for _ in range(300)]
bad = 0
for text, n in cases:
    try:
        got = slugify(text) if n is None else slugify(text, n)
    except Exception as e:
        got = "raised %r" % (e,)
    if got != oracle(text, n):
        bad += 1
        if bad <= 3:
            print("FAIL slugify(%r, %r) = %r, expected %r" % (text, n, got, oracle(text, n)))
if bad:
    print("FAIL %d of %d cases differ" % (bad, len(cases)))
    sys.exit(1)
print("ok   %d slugify cases match the specification" % len(cases))
R
}

case_kit_only() { python3 "$2/kit.py" "$1" >/dev/null 2>&1; } # <repo> <kit-dir>

case_hidden() { # <repo> <kit-dir>
  python3 "$2/kit.py" "$1" > "$RUN/hidden.last" 2>&1 || return 1
  ( cd "$1" && python3 -m unittest discover -s tests >/dev/null 2>&1 ) || { echo 'project tests fail' >> "$RUN/hidden.last"; return 1; }
}

case_assert() { # <run-dir> <repo>
  local st=$1/data/workflow.json head n
  jq -e '.definition.steps | keys | map(select(test("qa|review|security|ship"))) | length == 0' "$st" >/dev/null || { echo "the delegated-build definition carries an independent qa/review/security/ship step"; return 1; }
  jq -e '[.history[] | .step] == ["implement", "deliver"]' "$st" >/dev/null || { echo "the path is not exactly implement, deliver: $(jq -c '[.history[] | .step]' "$st")"; return 1; }
  n=$(find "$1/steps" -mindepth 1 -maxdepth 1 -type d -name '[0-9][0-9]-*' | wc -l | tr -d ' ')
  [ "$n" = 1 ] && [ -d "$(ls -d "$1"/steps/[0-9][0-9]-implement 2>/dev/null | head -1)" ] || { echo "expected exactly one worker (the implementer), found $n step directories"; return 1; }
  head=$(git -C "$2" rev-parse HEAD)
  jq -e --arg h "$head" '(.change.base // "") as $b | .history[0] | .valid == true and (.evidence | length) >= 1 and ((.commit // "") as $c | ($c | length) >= 7 and ($h | startswith($c))) and ($b | length) >= 7' "$st" >/dev/null \
    || { echo "the result block is not valid, evidence-carrying and bound to base..final head $head: $(jq -c '{change, h: (.history[0] | {valid, commit, evidence: (.evidence | length)})}' "$st")"; return 1; }
  [ "$head" != "$BASE0" ] || { echo "HEAD is still the fixture: nothing was implemented"; return 1; }
  [ -z "$(git -C "$2" remote)" ] || { echo "the fixture repository grew a remote"; return 1; }
  git -C "$2" rev-parse -q --verify refs/tags/workflow-delivered >/dev/null || { echo "delivery was not recorded (no workflow-delivered tag)"; return 1; }
}

case_canned() { # <role> <prompt-file> <cwd> (FAKE_MODE: wrong)
  local role=$1 prompt=$2 cwd=$3 base
  case $role in
    senior-fullstack)
      base=$(git -C "$cwd" rev-parse HEAD)
      if [ "${FAKE_MODE:-}" = wrong ]; then
        cat > "$cwd/textutil.py" <<'R'
def slugify(text, max_len=None):
    return text.lower().replace(" ", "-")
R
      else
        cat > "$cwd/textutil.py" <<'R'
import re


def slugify(text, max_len=None):
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    if max_len is not None:
        slug = slug[:max_len].rstrip("-")
    return slug
R
      fi
      cat > "$cwd/tests/test_textutil.py" <<'R'
import unittest
from textutil import slugify


class Slug(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(slugify("Hello, World!"), "hello-world")

    def test_cut(self):
        self.assertEqual(slugify("Hello, World!", 6), "hello")


if __name__ == "__main__":
    unittest.main()
R
      git -C "$cwd" add -A && git -C "$cwd" commit -q -m "textutil: slugify"
      canned_result "$cwd" "$base" 'Implemented slugify and committed it.' "$prompt" ;;
  esac
}
