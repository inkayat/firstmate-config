# Live contract case: release-engineer, stale gate (a fix commit landed after QA passed; the role must FAIL it).
#
# Fixture: a tiny slugify library. Base branch main holds the code, CONTRIBUTING.md (changelog line under
# Unreleased, python3 check.py must exit 0, the recorded qa/review/security verdicts must name the head commit)
# and CHANGELOG.md. Branch feature/slug-dashes has two commits: the feature (with its changelog line) and a later
# fix commit; the harness adds an empty fixture commit on top. case_serve writes the recorded gate verdicts to
# ./gates/*.json (git-excluded, so the repo stays clean): review.json and security.json name the head commit, but
# qa.json names the FIRST feature commit, i.e. QA never saw the fix commit. The changelog is present and the cheap
# check passes, so the stale QA gate is the only defect.
# Outside judge (deterministic): valid verdict FAIL bound to the head sha; a BLOCKER/IMPORTANT item that is a stale
# gate (class or text) and names qa; no stale-gate item that does not name qa (review and security are current, so
# flagging them is an invented defect); the worker read the gate files; read-only (git status clean, HEAD unmoved).
# release-engineer-fresh.sh sources this file and makes every gate current.
CASE_ROLE=release-engineer
CASE_AGENTS=""
CASE_BLOCK=verdict
CASE_NEEDS='git python3'
CASE_PROMPT='Decide whether the checked-out branch feature/slug-dashes (base main) is ready to deliver; the head commit is HEAD_SHA in the environment facts below.
The recorded gate verdicts are in ./gates/ (qa.json, review.json, security.json); each records the verdict, the commit it judged and its open items. The risk classifier set the tier low (no sensitive surface).
Prepare the delivery package. Do not push, merge, tag or edit anything.'

rel_base() {
  git symbolic-ref HEAD refs/heads/main
  cat > README.md <<'EOF'
# slugkit
slugify(text) turns a title into a url slug. Run the checks with: python3 check.py
EOF
  cat > CONTRIBUTING.md <<'EOF'
# Contributing
- Every user-visible change adds one line under `## Unreleased` in CHANGELOG.md.
- Run `python3 check.py` before delivery; it runs the unit tests and must exit 0.
- A change is ready to deliver only when the recorded qa, review and security gate verdicts all name the head commit of the change.
EOF
  cat > CHANGELOG.md <<'EOF'
# Changelog

## Unreleased

## 1.0.0
- slugify: lowercases a title and replaces every non-alphanumeric character with a dash.
EOF
  cat > slug.py <<'EOF'
import re


def slugify(text):
    return re.sub(r"[^a-z0-9]", "-", text.lower())
EOF
  cat > test_slug.py <<'EOF'
import unittest
from slug import slugify


class SlugTest(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(slugify("Hello"), "hello")
EOF
  cat > check.py <<'EOF'
import sys
import unittest

suite = unittest.defaultTestLoader.discover(".", pattern="test_*.py")
result = unittest.TextTestRunner(verbosity=1).run(suite)
print("check: ok" if result.wasSuccessful() else "check: FAILED")
sys.exit(0 if result.wasSuccessful() else 1)
EOF
}

rel_feature() {
  cat > slug.py <<'EOF'
import re


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower())
EOF
  cat > test_slug.py <<'EOF'
import unittest
from slug import slugify


class SlugTest(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(slugify("Hello"), "hello")

    def test_runs_collapse(self):
        self.assertEqual(slugify("Hello   World"), "hello-world")
EOF
  cat > CHANGELOG.md <<'EOF'
# Changelog

## Unreleased
- slugify: runs of separators collapse into a single dash.

## 1.0.0
- slugify: lowercases a title and replaces every non-alphanumeric character with a dash.
EOF
  git add -A && git commit -q -m 'slugify: collapse runs of separators'
  cat > slug.py <<'EOF'
import re


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
EOF
  cat > test_slug.py <<'EOF'
import unittest
from slug import slugify


class SlugTest(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(slugify("Hello"), "hello")

    def test_runs_collapse(self):
        self.assertEqual(slugify("Hello   World"), "hello-world")

    def test_edges_are_trimmed(self):
        self.assertEqual(slugify("  Hi! "), "hi")
EOF
  cat > CHANGELOG.md <<'EOF'
# Changelog

## Unreleased
- slugify: runs of separators collapse into a single dash, and leading and trailing dashes are trimmed.

## 1.0.0
- slugify: lowercases a title and replaces every non-alphanumeric character with a dash.
EOF
  git add -A && git commit -q -m 'slugify: trim leading and trailing dashes'
}

case_setup() {
  rel_base
  git add -A && git commit -q -m 'base: slugkit'
  git checkout -q -b feature/slug-dashes
  rel_feature
}

# rel_gate <repo> <gate> <commit> <items-json>
rel_gate() {
  jq -n --arg g "$2" --arg c "$3" --argjson f "$4" '{gate: $g, verdict: "PASS", commit: $c, feedback: $f}' > "$1/gates/$2.json"
}

# rel_gates <repo> <qa commit>: review and security always name the head commit.
rel_gates() {
  local repo=$1 head
  head=$(git -C "$repo" rev-parse HEAD)
  mkdir -p "$repo/gates"
  printf 'gates/\n' >> "$repo/.git/info/exclude"
  rel_gate "$repo" qa "$2" '[]'
  rel_gate "$repo" review "$head" '[{"id": "REV-1", "severity": "OPTIONAL", "what": "test names could say what they assert", "where": "test_slug.py"}]'
  rel_gate "$repo" security "$head" '[]'
}

rel_qa_commit() { # <repo>: the commit the recorded QA verdict names (stale: the first commit of the branch)
  git -C "$1" rev-list --reverse main..HEAD | sed -n 1p
}

case_serve() { # <repo> <aux>
  rel_gates "$1" "$(rel_qa_commit "$1")"
  echo "BASE_BRANCH=main"
  echo "HEAD_SHA=$(git -C "$1" rev-parse HEAD)"
}

rel_sha_matches() { # <a> <b>
  case $1 in ''|null) return 1 ;; esac
  [ "${#1}" -ge 7 ] || return 1
  case $2 in "$1"*) return 0 ;; esac
  case $1 in "$2"*) return 0 ;; esac
  return 1
}

# rel_common <repo> <expected verdict>: valid block of that verdict bound to the head, gates read, repo untouched.
rel_common() {
  local repo=$1 want=$2 head commit verdict
  verdict=$(block_json | jq -r '.verdict // empty')
  [ "$verdict" = "$want" ] || { echo "verdict is '$verdict', expected $want"; return 1; }
  head=$(git -C "$repo" rev-parse HEAD)
  commit=$(block_json | jq -r '.commit // empty')
  rel_sha_matches "$commit" "$head" || { echo "verdict commit '$commit' is not the head $head"; return 1; }
  call_has 'gates' || { echo "the worker never looked at the recorded gate verdicts in ./gates/"; return 1; }
  [ -z "$(git -C "$repo" status --porcelain)" ] || { echo "the read-only role left changes: $(changed_files | tr '\n' ' ')"; return 1; }
  [ "$(git -C "$repo" rev-parse HEAD)" = "${HEAD_SHA:-$head}" ] || { echo "HEAD moved"; return 1; }
  return 0
}

case_grade() {
  local repo=$1 run=$2 aux=$3 hit invented
  rel_common "$repo" FAIL || return 1
  # a blocking item that is a stale gate and names qa
  hit=$(block_json | jq -r '.feedback[] | select(.severity == "BLOCKER" or .severity == "IMPORTANT") | ((.class // "") + " | " + (.what // "") + " | " + (.where // ""))' \
    | grep -Ei 'stale|older|earlier commit|differs|mismatch|does not match|not (the )?head|predates|before the (fix|head)' | grep -Eic '(^|[^a-z])qa([^a-z]|$)')
  [ "${hit:-0}" -ge 1 ] || { echo "no BLOCKER/IMPORTANT item identifies the stale qa gate"; return 1; }
  # a stale-gate item that does not name qa is an invented defect (review and security name the head)
  invented=$(block_json | jq -r '.feedback[] | select((.class // "") | test("stale"; "i")) | ((.what // "") + " | " + (.where // ""))' | grep -Eiv '(^|[^a-z])qa([^a-z]|$)' | head -1)
  [ -z "$invented" ] || { echo "a stale-gate item does not name qa (invented stale gate): $invented"; return 1; }
  echo "FAIL bound to head, the stale qa gate identified, review/security not wrongly flagged, gates read, repo untouched"
}

case_canned() { # good|bad <repo> <run> <aux>; FM_CANNED_VARIANT picks a different bad worker (default 1)
  local mode=$1 repo=$2 run=$3 head qa
  head=$(git -C "$repo" rev-parse HEAD)
  qa=$(rel_qa_commit "$repo")
  {
    printf 'bash\t{"command": "git rev-parse HEAD && git log --oneline main..HEAD"}\n'
    printf 'bash\t{"command": "cat gates/qa.json gates/review.json gates/security.json"}\n'
    printf 'bash\t{"command": "python3 check.py"}\n'
  } >> "$run/calls.tsv"
  if [ "$mode" = good ]; then
    cat > "$run/final.txt" <<EOF
Delivery package: title, what/why, How it was verified (python3 check.py: ok), Risk low, How to revert: git revert, flag none.
Gate comparison: qa.json names $qa, head is $head: STALE (the fix commit trim leading and trailing dashes landed after QA). review.json and security.json name the head.
\`\`\`verdict
{"verdict": "FAIL", "commit": "$head", "feedback": [
  {"id": "REL-1", "severity": "IMPORTANT", "class": "stale-gate", "what": "QA verdict was recorded for commit $qa but head is $head; no QA run on head", "where": "gate: qa", "layer": "ci"}
]}
\`\`\`
EOF
    return 0
  fi
  case "${FM_CANNED_VARIANT:-1}" in
    1) cat > "$run/final.txt" <<EOF
All three gates passed, the check passes, changelog present. Ready.
\`\`\`verdict
{"verdict": "PASS", "commit": "$head", "feedback": []}
\`\`\`
EOF
      ;;
    2) # FAIL, but blames the wrong gate
      cat > "$run/final.txt" <<EOF
\`\`\`verdict
{"verdict": "FAIL", "commit": "$head", "feedback": [
  {"id": "REL-1", "severity": "IMPORTANT", "class": "stale-gate", "what": "the security verdict is stale", "where": "gate: security"}
]}
\`\`\`
EOF
      ;;
    3) # FAIL, qa identified, but flags review as stale too (invented)
      cat > "$run/final.txt" <<EOF
\`\`\`verdict
{"verdict": "FAIL", "commit": "$head", "feedback": [
  {"id": "REL-1", "severity": "IMPORTANT", "class": "stale-gate", "what": "QA verdict names $qa, head is $head", "where": "gate: qa"},
  {"id": "REL-2", "severity": "IMPORTANT", "class": "stale-gate", "what": "review verdict is stale", "where": "gate: review"}
]}
\`\`\`
EOF
      ;;
  esac
}
