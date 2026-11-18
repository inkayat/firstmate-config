# Live workflow case (iii): plan-build-test-review.
# Problem: "add a late fee" is genuinely ambiguous (flat or percent, the rate, a grace period,
#   a cap). The planner must settle it in its assumptions and end the plan with a machine-readable
#   `decisions` block; the implementer, QA and the reviewer receive that plan. The grader reads
#   the planner's own decisions and checks that the final code behaves exactly as they say.
# Control: the implement step run WITHOUT the plan; its behaviour is graded against the same
#   decisions (a guess matches them all only by coincidence).
CASE_WORKFLOW=plan-build-test-review
CASE_TASK='Add a late fee for overdue invoices: implement late_fee_cents(amount_cents, days_overdue) in billing.py, returning the fee in whole cents. The business has not said how the fee works; settling that is part of the job. Add tests under tests/.'
CASE_CONTROL_STEP=implement
CASE_CONTROL_RUN=1
CASE_CONTROL_STRIP=plan
CASE_EXPECT_PATH='^plan:done implement:done( .*)? review:pass deliver:done$'
CASE_FORCE_AFTER=''           # no loop is forced here; the plan is

case_setup() {
  mkdir -p tests
  cat > README.md <<'R'
# billing
Invoice helpers. Run the tests with: python3 -m unittest discover -s tests
R
  cat > billing.py <<'R'
def invoice_total_cents(lines):
    return sum(unit * qty for unit, qty in lines)
R
  cat > tests/test_billing.py <<'R'
import unittest
from billing import invoice_total_cents


class Total(unittest.TestCase):
    def test_total(self):
        self.assertEqual(invoice_total_cents([(250, 2), (100, 1)]), 600)


if __name__ == "__main__":
    unittest.main()
R
}

case_extra() { # <step> <role> <iteration> <kit-dir> <cwd> <data-dir>
  case $2 in
    planner) printf 'Write the plan to %s/plan.md and report that path. State every assumption explicitly in an assumptions section. End the plan with exactly one fenced block tagged `decisions` holding a JSON object with exactly these keys, each resolved to one value: "fee_type" ("flat" or "percent"), "rate" (cents for a flat fee, a percentage number for a percent fee; a percent fee is rounded half up to whole cents), "grace_days" (an integer: no fee up to and including that many days overdue), "cap_cents" (an integer maximum fee, or null for no cap). The plan is the requirement the implementer, QA and the reviewer will work from.\n' "$6" ;;
  esac
}

# The planner's decisions, parsed from the last fenced `decisions` block of the plan.
case_decisions() { # <plan-file> -> JSON on stdout, or exit 1
  [ -s "$1" ] || return 1
  awk '/^```decisions[ \t]*$/ {b = 1; body = ""; next} b && /^```[ \t]*$/ {b = 0; last = body; next} b {body = body $0 "\n"} END {printf "%s", last}' "$1" \
    | jq -ce 'select(type == "object" and (.fee_type == "flat" or .fee_type == "percent") and (.rate | type == "number") and (.grace_days | type == "number") and (.cap_cents == null or (.cap_cents | type == "number")))'
}

# Hidden acceptance: the code behaves exactly as the plan decided, over a grid of inputs.
case_hidden() { # <repo> <kit-dir> [decisions-json]
  local dec=${3:-$(case_decisions "$DATA/plan.md")}
  [ -n "$dec" ] || { echo 'no parseable decisions block in the plan' > "$RUN/hidden.last"; return 1; }
  ( cd "$1" && DEC="$dec" python3 - <<'R'
import json, os
from decimal import Decimal, ROUND_HALF_UP
from billing import late_fee_cents
d = json.loads(os.environ["DEC"])
def expect(amount, days):
    if days <= d["grace_days"]:
        return 0
    if d["fee_type"] == "flat":
        fee = int(d["rate"])
    else:
        fee = int((Decimal(amount) * Decimal(str(d["rate"])) / 100).quantize(Decimal(1), rounding=ROUND_HALF_UP))
    if d["cap_cents"] is not None:
        fee = min(fee, int(d["cap_cents"]))
    return fee
bad = []
for amount in (0, 1000, 12345, 250000):
    for days in (0, 1, d["grace_days"], d["grace_days"] + 1, d["grace_days"] + 30, 400):
        got = late_fee_cents(amount, days)
        if got != expect(amount, days):
            bad.append((amount, days, expect(amount, days), got))
for b in bad[:5]:
    print("expected late_fee_cents(%d, %d) == %d, got %r" % b)
raise SystemExit(1 if bad else 0)
R
  ) > "$RUN/hidden.last" 2>&1
}

case_assert() { # <run-dir> <repo>
  local run=$1 dec plan=$DATA/plan.md st=$1/data/workflow.json
  dec=$(case_decisions "$plan") || { echo "the plan has no parseable decisions block"; return 1; }
  grep -qiE 'assum' "$plan" || { echo "the plan has no assumptions section"; return 1; }
  # the plan reached implement, qa and review
  local s
  for s in implement qa review; do
    jq -e --arg p "$plan" '[.history[] | select(.step == "'"$s"'")] | length >= 1' "$st" >/dev/null || { echo "step $s never ran"; return 1; }
    grep -qF "$plan" "$run"/steps/*-"$s"/prompt.md || { echo "the $s worker was never handed the plan path"; return 1; }
  done
}

case_canned() { # <role> <prompt-file> <cwd>
  local role=$1 prompt=$2 cwd=$3 plan
  case $role in
    planner)
      plan=$(sed -n 's#^Write the plan to \(.*/plan.md\) and report.*#\1#p' "$prompt" | head -1)
      mkdir -p "$(dirname "$plan")"
      printf '# Plan\n\n## Assumptions\n1. A flat fee after a grace period.\n\n```decisions\n{"fee_type":"flat","rate":750,"grace_days":3,"cap_cents":null}\n```\n' > "$plan"
      printf 'Wrote the plan to %s\n' "$plan" ;;
    senior-fullstack)
      plan=$(sed -n 's#^- plan: the report of step plan, at \(.*\)$#\1#p' "$prompt" | head -1)
      if [ -n "$plan" ] && [ -s "$plan" ]; then
        printf 'def invoice_total_cents(lines):\n    return sum(unit * qty for unit, qty in lines)\n\n\ndef late_fee_cents(amount_cents, days_overdue):\n    return 750 if days_overdue > 3 else 0\n' > "$cwd/billing.py"
      else
        printf 'def invoice_total_cents(lines):\n    return sum(unit * qty for unit, qty in lines)\n\n\ndef late_fee_cents(amount_cents, days_overdue):\n    return (amount_cents * 2 + 50) // 100 if days_overdue > 0 else 0\n' > "$cwd/billing.py"
      fi
      git -C "$cwd" add -A && git -C "$cwd" commit -q -m "billing: late fee"
      printf 'Implemented late_fee_cents and committed it.\n' ;;
    qa) printf 'Checked the plan decisions against the code.\n\n```verdict\n{"verdict":"PASS","feedback":[]}\n```\n' ;;
    code-reviewer) printf 'Matches the plan.\n\n```verdict\n{"verdict":"PASS","feedback":[]}\n```\n' ;;
  esac
}
