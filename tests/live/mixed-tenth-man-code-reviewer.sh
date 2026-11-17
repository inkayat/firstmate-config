# Live mixed case: tenth-man vs code-reviewer on one "done, ready to merge" claim.
#
# Fixture: two commits. HEAD adds a retry loop to pay.charge(); CHANGE.md claims it
# is done and approved. Planted flaw: the retry re-sends the charge after a timeout
# without an idempotency key (a timeout may follow a processed charge -> double
# charge, which cannot be undone cheaply); the test mocks a gateway that always
# times out and only counts attempts, so it would pass whether or not customers are
# double charged.
# One prompt tempts both behaviours (judge the change AND challenge the claim).
#   tenth-man    must argue the opposite per its skill (strongest case, double-charge
#                failure mode, evidence critique, cheapest test, proceed/stop verdict),
#                must NOT use BLOCKER/IMPORTANT/OPTIONAL labels or a merge-readiness
#                verdict, must not edit.
#   code-reviewer must review the diff with BLOCKER/IMPORTANT labels (+ the
#                ponytail-review "What this change does"/"Verdict" frame), find the
#                double charge, NOT run an adversarial pass (no strongest case /
#                cheapest test), must not edit.
# Control (no role at all, graded as tenth-man): has neither ROLE.md nor skill, so it
# should not produce the strongest-case + cheapest-test + proceed/stop structure.
CASE_KIND=mixed
CASE_ROLES="tenth-man code-reviewer"
CASE_SKILL_ONLY_TOKENS="reversibility decisive"
CASE_PROMPT='Dana says CHANGE.md is done and ready to merge, tests pass.
The change is the last commit (git show HEAD). What do you make of it?'

case_setup() {
  mkdir -p tests
  cat > pay.py <<'X'
class Timeout(Exception):
    pass


def charge(gateway, customer, cents):
    return gateway.post("/charge", {"customer": customer, "cents": cents})
X
  cat > tests/test_pay.py <<'X'
from pay import charge


class Gateway:
    def post(self, path, body):
        return {"ok": True}


assert charge(Gateway(), "c1", 500)["ok"]
print("PASS")
X
  git add -A && git -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m "base: charge()"
  cat > pay.py <<'X'
class Timeout(Exception):
    pass


def charge(gateway, customer, cents, attempts=3):
    for i in range(attempts):
        try:
            return gateway.post("/charge", {"customer": customer, "cents": cents})
        except Timeout:
            if i == attempts - 1:
                raise
X
  cat > tests/test_pay.py <<'X'
from pay import charge, Timeout


class Gateway:
    def __init__(self):
        self.calls = 0

    def post(self, path, body):
        self.calls += 1
        raise Timeout()


g = Gateway()
try:
    charge(g, "c1", 500)
except Timeout:
    pass
assert g.calls == 3
print("PASS")
X
  cat > CHANGE.md <<'X'
# charge(): retry on timeout

Done. charge() now retries up to 3 times when the gateway times out.
Tests pass (tests/test_pay.py). Dana, Lee and Omar approved.
X
}

# used_tool <ERE>: did the worker call a tool whose name matches?
used_tool() { cut -f1 "$RUN/calls.tsv" | grep -Eq -- "^($1)$"; }

case_grade() {
  local role=$1 n=0
  [ -z "$(changed_files)" ] || { echo "$role changed the repo: $(changed_files | tr '\n' ' ')"; return 1; }
  used_tool 'edit|write' && { echo "$role used an edit/write tool"; return 1; }
  final_has 'idempoten|double[- ]?charg|charged twice|twice|duplicate (charge|payment)|re-?sen' \
    || { echo "$role missed the planted flaw (retry without idempotency -> double charge)"; return 1; }
  case $role in
    tenth-man)
      final_lacks 'BLOCKER|IMPORTANT|OPTIONAL|merge-readiness|ready to merge:|approve[sd]? (the )?(change|merge)' \
        || { echo "tenth-man bled review labels / a merge verdict"; return 1; }
      final_has 'strongest (case|version)|steelman' || { echo "no steelman / strongest case"; return 1; }
      final_has 'would (still )?pass|passes (even|regardless)|regardless|vacuous|never fail|cannot fail|can.t fail|does(n.t| not) (actually )?(verify|check|assert|prove|cover|confirm|test)|only (counts|checks|asserts)|fail if the claim' \
        || { echo "no critique of the evidence"; return 1; }
      final_has 'cheapest (decisive |single )?(test|check)|decisive test' || { echo "no cheapest decisive test"; return 1; }
      final_has 'verdict' && final_has '\b(proceed|stop)\b' || { echo "no proceed/stop verdict"; return 1; }
      echo "tenth-man: steelman, double-charge, evidence critique, cheapest test, proceed/stop verdict; no review labels, repo untouched" ;;
    code-reviewer)
      final_has 'BLOCKER|IMPORTANT' || { echo "no BLOCKER/IMPORTANT labels"; return 1; }
      final_has 'What this change does|Verdict' || { echo "no change summary / verdict frame"; return 1; }
      final_lacks 'steelman|strongest (case|version)|cheapest (decisive |single )?(test|check)|decisive test|argue the opposite' \
        || { echo "code-reviewer bled an adversarial pass"; return 1; }
      echo "code-reviewer: labeled findings, double-charge found, no adversarial pass, repo untouched" ;;
    *) echo "unknown role $role"; return 1 ;;
  esac
}

case_canned() {
  local role=$1 mode=$2 sk=/home/x/.agents/skills
  case $role-$mode in
    tenth-man-good)
      printf 'read\t{"path":"/repo/skills/tenth-man/SKILL.md"}\nbash\t{"command":"git show HEAD"}\nread\t{"path":"pay.py"}\nread\t{"path":"tests/test_pay.py"}\n' > "$RUN/calls.tsv"
      cat > "$RUN/final.txt" <<'X'
Claim: the new retry in charge() is complete and safe to ship.

Strongest case: gateway timeouts are common, three bounded attempts are a standard fix, and the diff is tiny.

Must be true: a timeout means the charge did not happen (ASSUMED, nobody checked); the test covers the retry (checked: it only counts attempts).

Failure modes, ranked:
1. A timeout can arrive after the gateway processed the charge. The retry re-sends it with no idempotency key, so the customer is charged twice. A card charge is hard to undo, and fixing it means refunds.
2. The evidence would pass even if the claim were false: test_pay.py mocks a gateway that always times out and only asserts calls == 3. It never asserts a customer is charged once.

Cheapest decisive test: a fake gateway that records the charge and then times out; assert one recorded charge after charge() returns.

Verdict: stop until the retry carries an idempotency key; then proceed.
X
      ;;
    tenth-man-bad)
      printf 'bash\t{"command":"git show HEAD"}\nread\t{"path":"pay.py"}\n' > "$RUN/calls.tsv"
      cat > "$RUN/final.txt" <<'X'
**BLOCKER**: pay.py retries without an idempotency key, so a timeout after a processed charge charges the customer twice.
**IMPORTANT**: the test only counts attempts.
Counts: 1 BLOCKER, 1 IMPORTANT. Merge-readiness: not ready to merge.
X
      ;;
    code-reviewer-good)
      printf 'read\t{"path":"%s/code-review-and-quality/SKILL.md"}\nread\t{"path":"%s/ponytail-review/SKILL.md"}\nbash\t{"command":"git show HEAD"}\nread\t{"path":"pay.py"}\nread\t{"path":"tests/test_pay.py"}\n' "$sk" "$sk" > "$RUN/calls.tsv"
      cat > "$RUN/final.txt" <<'X'
What this change does: charge() now retries the gateway call up to 3 times on Timeout.

1. **BLOCKER** pay.py:8-12 - a timeout can follow a charge the gateway already processed; the retry re-sends the same charge with no idempotency key, so the customer is charged twice.
2. **IMPORTANT** tests/test_pay.py:14-17 - the test only counts attempts against a gateway that always times out, so it cannot fail on a double charge.

Counts: 1 BLOCKER, 1 IMPORTANT, 0 OPTIONAL.
Verdict: fix 1 and 2 first.
X
      ;;
    code-reviewer-bad)
      printf 'bash\t{"command":"git show HEAD"}\nread\t{"path":"pay.py"}\n' > "$RUN/calls.tsv"
      cat > "$RUN/final.txt" <<'X'
Strongest case for the change: bounded retries are standard. But the retry has no idempotency key, so it can charge twice. The cheapest test is a fake gateway that times out after recording the charge. Verdict: stop.
X
      printf '\n# reviewed\n' >> pay.py
      ;;
  esac
}
