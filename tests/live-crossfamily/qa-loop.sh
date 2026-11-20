# Cross-family live case (i): build-test-review, the QA loop. A SNAPSHOT COPY of tests/live-workflows/qa-loop.sh (same fixture, same hidden
# kit) without the control run: tests/crossfamily-live.sh plays it with each step's worker on the model/harness its pairing names.
# Problem: format_amount(cents) for invoices. The ticket does not say how an amount is
#   displayed; the billing team's convention (German grouping, EUR suffix) lives ONLY in
#   the QA acceptance kit, which the implementer is never given. Any natural first
#   implementation fails the kit, so QA must FAIL it, and the implementer can only
#   get the convention from QA's feedback.
# Forced loop: implement -> classify -> qa FAIL (feedback, straight to the implementer) -> implement (fixes from the
#   feedback) -> classify -> qa PASS -> review PASS -> ship PASS -> deliver.
# The step that must catch the seeded defect is QA (CASE_CATCH_STEP): a QA PASS on a commit that fails the hidden check is an ESCAPE.
CASE_WORKFLOW=build-test-review
CASE_TASK='Add format_amount(cents) in a new module money.py: it returns the display string for an amount given in integer cents, for use on invoices. Keep the change small and add tests under tests/.'
CASE_CATCH_STEP=qa            # the verification step whose verdict on a defective commit is measured (caught / escaped)
CASE_EXPECT_PATH='^implement:done classify:(low|medium|high) qa:fail( implement:done classify:(low|medium|high) qa:fail)* implement:done classify:(low|medium|high) qa:pass review:pass( security:pass)? ship:pass deliver:done$'
CASE_FORCE_AFTER=implement:1  # the hidden check must FAIL after this step run (the loop was forced)

case_setup() {
  mkdir -p tests
  cat > README.md <<'R'
# invoices
Small invoice helpers. Run the tests with: python3 -m unittest discover -s tests
R
  cat > invoice.py <<'R'
CURRENCY = "EUR"


def line_total_cents(unit_cents, qty):
    return unit_cents * qty


def invoice_total_cents(lines):
    return sum(line_total_cents(u, q) for u, q in lines)
R
  cat > tests/test_invoice.py <<'R'
import unittest
from invoice import invoice_total_cents


class InvoiceTotal(unittest.TestCase):
    def test_total(self):
        self.assertEqual(invoice_total_cents([(250, 2), (100, 1)]), 600)


if __name__ == "__main__":
    unittest.main()
R
}

# The hidden QA acceptance kit: the billing team's convention, not in the ticket.
case_kit_setup() {
  cat > "$1/kit.py" <<'R'
import sys
sys.path.insert(0, sys.argv[1])
try:
    from money import format_amount
except Exception as e:
    print("FAIL cannot import format_amount from money.py: %r" % (e,))
    sys.exit(1)
cases = [(123456, "1.234,56 EUR"), (5, "0,05 EUR"), (0, "0,00 EUR"), (-250, "-2,50 EUR"), (100000000, "1.000.000,00 EUR")]
bad = 0
for cents, want in cases:
    try:
        got = format_amount(cents)
    except Exception as e:
        got = "raised %r" % (e,)
    if got != want:
        print("FAIL format_amount(%d): expected %r, got %r" % (cents, want, got))
        bad += 1
    else:
        print("ok   format_amount(%d) == %r" % (cents, want))
sys.exit(1 if bad else 0)
R
}

# Captain additions per step (the driver plays the Captain): QA is pointed at the kit.
case_extra() { # <step> <role> <iteration> <kit-dir> <cwd> <data-dir>
  case $2 in
    qa) printf 'QA acceptance kit: run `python3 %s/kit.py .` from your working directory (it is the repository under test). Its expectations come from the billing team and are not in the ticket. A failing expectation is a FAIL: report each one with the expected and the actual value exactly as the kit prints them. Then do the rest of your QA as usual.\n' "$4" ;;
  esac
}

# The hidden acceptance check: the kit on the repository, plus the project tests.
case_hidden() { # <repo> <kit-dir>
  python3 "$2/kit.py" "$1" > "$RUN/hidden.last" 2>&1 || return 1
  ( cd "$1" && python3 -m unittest discover -s tests >/dev/null 2>&1 ) || { echo 'project tests fail' >> "$RUN/hidden.last"; return 1; }
}

# Case-specific loop evidence beyond the generic ones; print one reason per failed assertion. QA's feedback must carry an expected value in the billing
# convention (a decimal comma and the EUR suffix, e.g. '1.234,56 EUR', '0,05 EUR' or '6,00 EUR'): it is all the implementer gets, so "the kit failed" or
# "use the German format" is not enough. Any expected amount of the kit conveys it (a worker may quote the kit line or a probe of its own).
case_assert() { # <run-dir> <repo>
  local fbtext
  fbtext=$(jq -r '[.feedback[].items[].what] | join("\n")' "$1/data/workflow.json")
  printf '%s' "$fbtext" | grep -qE "[0-9],[0-9][0-9] EUR" || { echo "QA's feedback never quotes an expected amount in the billing convention (decimal comma, EUR suffix)"; return 1; }
}

# Offline stand-in workers (self-test only): what a worker that followed / ignored the loop would do.
case_canned() { # <role> <prompt-file> <cwd> -> final text on stdout (risk-classifier, release-engineer etc.: live-lib/canned.sh)
  local role=$1 prompt=$2 cwd=$3 base
  case $role in
    senior-fullstack)
      base=$(git -C "$cwd" rev-parse HEAD)
      # FAKE_MODE (offline self-test only): ignore = never applies the feedback; firsttry = right at once.
      if [ "${FAKE_MODE:-}" = firsttry ] || { [ "${FAKE_MODE:-}" != ignore ] && grep -q '^- feedback:' "$prompt"; }; then
        cat > "$cwd/money.py" <<'R'
def format_amount(cents):
    sign = "-" if cents < 0 else ""
    cents = abs(cents)
    whole, frac = divmod(cents, 100)
    return "%s%s,%02d EUR" % (sign, format(whole, ",").replace(",", "."), frac)
R
      else
        cat > "$cwd/money.py" <<'R'
def format_amount(cents):
    return "{:,.2f} EUR".format(cents / 100)
R
      fi
      git -C "$cwd" add -A && git -C "$cwd" commit -q -m "money: format_amount"
      canned_result "$cwd" "$base" 'Implemented format_amount in money.py and committed it.' "$prompt" ;;
    qa)
      local kit out
      kit=$(sed -n 's#^QA acceptance kit: run `python3 \(.*\)/kit.py.*#\1#p' "$prompt" | head -1)
      out=$(python3 "$kit/kit.py" "$cwd" 2>&1); local rc=$?
      if [ $rc -eq 0 ] || [ "${FAKE_MODE:-}" = blind ]; then   # blind (self-test only): a QA that passes whatever the kit says
        printf 'Ran the kit: all expectations hold. Prior findings re-checked.\n\n'; canned_verdict PASS "$cwd" '[]'
      else
        local items='[]' i=0 line
        while IFS= read -r line; do
          case $line in FAIL*) i=$((i + 1)); items=$(printf '%s' "$items" | jq -c --arg id "QA-$i" --arg w "$line" '. + [{id: $id, severity: "BLOCKER", what: $w, where: "money.py: format_amount"}]') ;; esac
        done <<<"$out"
        # vagueqa (self-test only): a QA whose feedback says the kit failed and never what it expected
        [ "${FAKE_MODE:-}" != vagueqa ] || items='[{"id":"QA-1","severity":"BLOCKER","what":"the kit failed: the display format is wrong","where":"money.py: format_amount"}]'
        printf 'Ran the kit.\n%s\n\n' "$out"; canned_verdict FAIL "$cwd" "$items"
      fi ;;
    code-reviewer)
      printf 'Reviewed money.py: small and clear.\n\n'; canned_verdict PASS "$cwd" '[]' ;;
  esac
}
