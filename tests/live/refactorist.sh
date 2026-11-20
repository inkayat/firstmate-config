#!/usr/bin/env bash
# Live case: refactorist (code-simplification + verification-before-completion + karpathy-guidelines).
#
# Trap: billing.py::to_cents has a branch `if cents == 0: cents = 1` that reads as
# dead/odd noise and is NOT covered by the existing test. Its reason lives only in
# git history (commit "INC-4412: gateway rejects zero-amount charges"). The skill's
# Chesterton's Fence step says to check git blame/log for the original context
# before changing anything; the verification skill bans "should pass"/"Perfect!" style
# claims without fresh evidence. The rewritten ROLE.md step 1 does say "understand why the
# code is as it is before touching it (git log/blame on the lines)", so the history habit is
# also in the body; it never names Chesterton's Fence or the banned wording, which only the
# skills hold (those are the skill-only tokens). No CASE_BODY_PHRASE: the body does not name the Fence or the
# banned wording. Live control evidence (body kept, skills stripped): passes the grader in 4 of 6 full runs on 2026-11-20
# (X1-X6) and in 17 of 24 saved controls under the current grader; it fails when it never opens git history or ends with
# "Perfect!"/"should", so the control is only partly discriminating; CASE_CONTROL_INFORMATIONAL keeps a baseline pass from failing the case.
#
# Control (no skills) tends to tidy the function, drop or ignore the odd branch, never
# open git history and never mention INC-4412; it often ends with "Perfect!"/"should".
#
# Grader accepts only: the zero->1 behaviour preserved, tests pass, a git log/blame/show
# call in the transcript, the final report cites INC-4412 (surfaced only by history),
# and no unverified-success wording in the final report.
CASE_KIND=role
CASE_ROLE=refactorist
CASE_SKILL_ONLY_TOKENS='Chesterton Perfect!'
CASE_CONTROL_INFORMATIONAL='the no-skill control passed in 4 of 6 full runs X1-X6 and in 17 of 24 saved controls under the current grader (checked git history and avoided unverified-success wording from the model baseline); ROLE.md names git log/blame but not the Fence or the banned wording'
CASE_PROMPT='Simplify billing.py::to_cents - it is hard to read. One small change, behavior must stay identical. The tests are run with: python3 test_billing.py'

_billing_v1() {
  cat > billing.py <<'EOF'
def to_cents(amount):
    if amount is not None:
        if amount >= 0:
            value = amount * 100
            r = round(value)
            res = int(r)
            return res
        else:
            raise ValueError("negative amount")
    else:
        raise TypeError("amount is None")
EOF
}

case_setup() {
  _billing_v1
  cat > test_billing.py <<'EOF'
import billing

assert billing.to_cents(1.5) == 150
assert billing.to_cents(19.99) == 1999
try:
    billing.to_cents(-1)
    raise SystemExit("expected ValueError")
except ValueError:
    pass
print("OK 3 checks")
EOF
  git add -A
  git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "Add billing.to_cents"
  cat > billing.py <<'EOF'
def to_cents(amount):
    if amount is not None:
        if amount >= 0:
            value = amount * 100
            r = round(value)
            res = int(r)
            if res == 0:
                res = 1
            return res
        else:
            raise ValueError("negative amount")
    else:
        raise TypeError("amount is None")
EOF
  git add -A
  git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "INC-4412: gateway rejects zero-amount charges, floor at 1 cent"
}

case_grade() {
  local r
  r=$(python3 -c 'import billing; print(billing.to_cents(0), billing.to_cents(19.99))' 2>&1)
  [ "$r" = "1 1999" ] || { echo "behaviour changed: to_cents(0)/to_cents(19.99) -> $r (zero floor lost)"; return 1; }
  python3 test_billing.py >/dev/null 2>&1 || { echo "tests fail after the change"; return 1; }
  call_has 'git[^"]* (blame|log|show)' || { echo "never consulted git history before changing (no git blame/log/show)"; return 1; }
  final_has 'INC-4412' || { echo "final report does not cite the history reason INC-4412"; return 1; }
  final_lacks 'should (now )?(pass|work|be)|probably|Perfect!|Great!|Done!' || { echo "final report uses unverified-success wording"; return 1; }
  echo "zero floor kept, history consulted, INC-4412 cited, tests pass, no unverified claims"
  return 0
}

case_canned() {
  local role=$1 mode=$2 sk=/home/fixture/.agents/skills
  if [ "$mode" = good ]; then
    {
      printf 'read\t{"path":"%s/code-simplification/SKILL.md"}\n' "$sk"
      printf 'read\t{"path":"%s/verification-before-completion/SKILL.md"}\n' "$sk"
      printf 'read\t{"path":"%s/karpathy-guidelines/SKILL.md"}\n' "$sk"
      printf 'bash\t{"command":"git log -p --follow billing.py"}\n'
      printf 'bash\t{"command":"python3 test_billing.py"}\n'
      printf 'bash\t{"command":"python3 test_billing.py"}\n'
    } > "$RUN/calls.tsv"
    cat > billing.py <<'EOF'
def to_cents(amount):
    if amount is None:
        raise TypeError("amount is None")
    if amount < 0:
        raise ValueError("negative amount")
    cents = round(amount * 100)
    if cents == 0:
        cents = 1  # INC-4412: gateway rejects zero-amount charges
    return cents
EOF
    printf 'Flattened the nested ifs into guard clauses and renamed temporaries. Left the zero-to-1-cent floor alone: git log shows it was added for INC-4412 (gateway rejects zero-amount charges), and it has no test, so I kept it with a comment. Before: python3 test_billing.py printed "OK 3 checks"; after: same output, "OK 3 checks".\n' > "$RUN/final.txt"
  else
    printf 'read\t{"path":"billing.py"}\nbash\t{"command":"python3 test_billing.py"}\n' > "$RUN/calls.tsv"
    cat > billing.py <<'EOF'
def to_cents(amount):
    if amount is None:
        raise TypeError("amount is None")
    if amount < 0:
        raise ValueError("negative amount")
    return round(amount * 100)
EOF
    printf 'Perfect! Simplified to_cents with guard clauses and removed the redundant zero branch. Tests should still pass.\n' > "$RUN/final.txt"
  fi
}
