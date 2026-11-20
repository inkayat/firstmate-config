# Live workflow case (ii): build-test-review, the review loop.
# Problem: rename_user(user_id, new_name) in store.py. The team's rule (known only from the
#   review checklist the Captain hands the REVIEWER, never the implementer): every function
#   that modifies stored data must record it with trail.append(action, target) from trail.py.
#   Nothing in the ticket says so, store.py never calls trail, and QA's kit only checks the
#   rename, so the natural implementation passes QA and only the code-reviewer finds the
#   missing audit entry.
# Forced loop: implement -> classify -> qa PASS -> review FAIL -> verify-review (confirms the finding) -> implement
#   (fixes from the verifier's confirmed list) -> classify -> qa -> review PASS -> ship PASS -> deliver.
# Control: the fix round (implement run 2) with the feedback block removed; the missing entry must stay missing.
CASE_WORKFLOW=build-test-review
CASE_TASK='Add rename_user(user_id, new_name) to store.py: it changes the user'"'"'s name and returns the updated user dict; an unknown user_id raises KeyError. Keep the change small and add tests under tests/.'
CASE_CONTROL_STEP=implement
CASE_CONTROL_RUN=2
CASE_CONTROL_STRIP=feedback
CASE_EXPECT_PATH='^implement:done classify:(low|medium|high) qa:pass review:fail verify-review:fail implement:done classify:(low|medium|high) qa:pass review:pass( security:pass)? ship:pass deliver:done$'
CASE_FORCE_AFTER=implement:1  # the QA kit passes but the hidden audit check must FAIL after the first implementation
CASE_FORCE_KIT_PASS=1         # ... and the QA kit alone passes at that point (QA must not be the one to catch it)

case_setup() {
  mkdir -p tests
  cat > README.md <<'R'
# admin
Tiny admin backend over in-memory data. Tests: python3 -m unittest discover -s tests
R
  cat > trail.py <<'R'
LOG = []


def append(action, target):
    LOG.append((action, target))
R
  cat > store.py <<'R'
USERS = {1: {"name": "alice", "active": True}, 2: {"name": "bob", "active": True}}


def get_user(user_id):
    return dict(USERS[user_id], id=user_id)


def deactivate_user(user_id):
    USERS[user_id]["active"] = False
    return get_user(user_id)
R
  cat > billing.py <<'R'
import trail

REFUNDS = []


def refund(order_id, cents):
    REFUNDS.append((order_id, cents))
    trail.append("refund", order_id)
R
  cat > tests/test_store.py <<'R'
import unittest
import store


class Users(unittest.TestCase):
    def test_get_user(self):
        self.assertEqual(store.get_user(1)["name"], "alice")


if __name__ == "__main__":
    unittest.main()
R
}

# The QA acceptance kit: the rename the ticket describes.
case_kit_setup() {
  cat > "$1/kit.py" <<'R'
import sys
sys.path.insert(0, sys.argv[1])
try:
    from store import rename_user
except Exception as e:
    print("FAIL cannot import rename_user from store.py: %r" % (e,))
    sys.exit(1)
bad = 0
try:
    got = rename_user(1, "alicia")
    if got.get("name") != "alicia" or got.get("id") != 1:
        raise AssertionError("expected the updated user with name 'alicia' and id 1, got %r" % (got,))
    print("ok   rename_user(1, 'alicia')")
except Exception as e:
    print("FAIL rename_user(1, 'alicia'): %r" % (e,))
    bad += 1
try:
    rename_user(99, "nobody")
    print("FAIL rename_user(99, ...) did not raise KeyError")
    bad += 1
except KeyError:
    print("ok   rename_user(99, ...) raises KeyError")
except Exception as e:
    print("FAIL rename_user(99, ...) raised %r instead of KeyError" % (e,))
    bad += 1
sys.exit(1 if bad else 0)
R
}

# Captain additions per step: QA gets the kit; the REVIEWER and the finding-VERIFIER get the team checklist (the implementer gets neither).
case_extra() { # <step> <role> <iteration> <kit-dir> <cwd> <data-dir>
  case $2 in
    qa) printf 'QA acceptance kit: run `python3 %s/kit.py .` from your working directory (it is the repository under test); it checks the rename the ticket describes. A failing expectation is a FAIL. Then do the rest of your QA as usual.\n' "$4" ;;
    code-reviewer) printf 'Team review checklist (the implementer was not given it; each violated rule is a finding at the stated severity): R1 (IMPORTANT) no bare `except:`. R2 (BLOCKER) every function that modifies stored data must record it with trail.append(action, target) from trail.py, as billing.refund does. R3 (OPTIONAL) no print() in library code.\n' ;;
    finding-verifier) printf 'Team review checklist the reviewer applied (the implementer was not given it; a finding that cites a violated rule below is a requirement, not an opinion): R1 (IMPORTANT) no bare `except:`. R2 (BLOCKER) every function that modifies stored data must record it with trail.append(action, target) from trail.py, as billing.refund does. R3 (OPTIONAL) no print() in library code.\n' ;;
  esac
}

case_kit_only() { python3 "$2/kit.py" "$1" >/dev/null 2>&1; } # <repo> <kit-dir>

# Hidden acceptance: the kit, the project tests, and the audit entry the team rule requires.
case_hidden() { # <repo> <kit-dir>
  python3 "$2/kit.py" "$1" > "$RUN/hidden.last" 2>&1 || return 1
  ( cd "$1" && python3 -m unittest discover -s tests >/dev/null 2>&1 ) || { echo 'project tests fail' >> "$RUN/hidden.last"; return 1; }
  ( cd "$1" && python3 - <<'R'
import store, trail
trail.LOG.clear()
store.rename_user(2, "robert")
assert any(t == 2 for _, t in trail.LOG), trail.LOG
R
  ) >/dev/null 2>&1 || { echo 'AUDIT: rename_user left no trail.append(action, target) entry for the user it modified' >> "$RUN/hidden.last"; return 1; }
}

case_assert() { # <run-dir> <repo>
  local st=$1/data/workflow.json fb
  fb=$(jq -r '[.history[] | select(.step == "review" and .outcome == "fail") | .feedback[] | .what + " " + .where] | join("\n")' "$st")
  printf '%s' "$fb" | grep -qiE 'trail|audit|R2' || { echo "the review finding never names the missing trail entry"; return 1; }
  fb=$(jq -r '[.history[] | select(.step == "verify-review" and .outcome == "fail") | .feedback[] | .what + " " + .where] | join("\n")' "$st")
  printf '%s' "$fb" | grep -qiE 'trail|audit|R2' || { echo "the verifier never confirmed the missing trail entry"; return 1; }
  jq -e '[.history[] | select(.step == "implement")] | length >= 2 and (.[-1].answers | length) >= 1' "$st" >/dev/null || { echo "the fixing implementer run reported no answer to the confirmed finding"; return 1; }
}

case_canned() { # <role> <prompt-file> <cwd> (risk-classifier, finding-verifier, release-engineer: live-lib/canned.sh)
  local role=$1 prompt=$2 cwd=$3 base
  case $role in
    senior-fullstack)
      base=$(git -C "$cwd" rev-parse HEAD)
      if grep -q '^- feedback:' "$prompt"; then
        cat >> "$cwd/store.py" <<'R'


def rename_user(user_id, new_name):
    USERS[user_id]["name"] = new_name
    trail.append("rename_user", user_id)
    return get_user(user_id)
R
        { printf 'import trail\n'; cat "$cwd/store.py"; } > "$cwd/store.py.new" && mv "$cwd/store.py.new" "$cwd/store.py"
      else
        cat >> "$cwd/store.py" <<'R'


def rename_user(user_id, new_name):
    USERS[user_id]["name"] = new_name
    return get_user(user_id)
R
      fi
      git -C "$cwd" add -A && git -C "$cwd" commit -q -m "store: rename_user"
      canned_result "$cwd" "$base" 'Implemented rename_user and committed it.' "$prompt" ;;
    qa)
      local kit
      kit=$(sed -n 's#^QA acceptance kit: run `python3 \(.*\)/kit.py.*#\1#p' "$prompt" | head -1)
      if python3 "$kit/kit.py" "$cwd" >/dev/null 2>&1; then printf 'Ran the kit: the rename passes.\n\n'; canned_verdict PASS "$cwd" '[]'
      else printf 'Kit failed.\n\n'; canned_verdict FAIL "$cwd" '[{"id":"QA-1","severity":"BLOCKER","what":"kit failure","where":"store.py"}]'; fi ;;
    code-reviewer)
      if grep -q 'trail.append' "$cwd/store.py"; then
        printf 'R2 holds.\n\n'; canned_verdict PASS "$cwd" '[]'
      else
        printf 'R2 is violated.\n\n'; canned_verdict FAIL "$cwd" '[{"id":"REV-1","severity":"BLOCKER","what":"R2: rename_user modifies stored data but never calls trail.append(action, target); billing.refund does","where":"store.py:rename_user"}]'
      fi ;;
  esac
}
