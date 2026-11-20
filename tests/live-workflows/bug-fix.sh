# Live workflow case (iv): bug-fix, root cause not symptom.
# Problem: after a customer cancels a PARTIALLY SHIPPED order, Stock.available() goes up by more than what was
#   returned. The root cause is in orders.py: Order.cancel() releases the full ordered quantity, shipped units
#   included. A symptom fix (clamping Stock.release so `reserved` never goes below zero) makes the single-order
#   report disappear but is still wrong as soon as ANOTHER order holds a reservation on the same sku; the hidden
#   kit has that two-order scenario. The ticket states the expected behaviour but not where the defect is.
# Workflow shape (bug-fix): diagnose (debugger, report) -> regression-test (test-engineer commits a failing test)
#   -> fix (senior-fullstack, may not touch that test) -> classify -> qa -> review -> ship -> deliver.
# Judged OUTSIDE the workers: the engine's state (path), the fixture history (the tester commit touches only tests/
#   and is RED at its own commit; the fix commit touches no test file and everything is GREEN there), and a hidden
#   kit that includes the two-order scenario a clamp cannot satisfy. No control run: the hidden kit is the judge.
CASE_WORKFLOW=bug-fix
CASE_TASK='Bug report: when a customer cancels an order that was already partly shipped, the stock number shown to buyers (Stock.available) goes UP by more than the units that came back. Today sku "widget" showed 6 available with only 3 on hand after such a cancellation. Cancelling must give back only the units that were not shipped. Reproduce it, find the root cause and fix it.'
CASE_NO_CONTROL=1
CASE_EXPECT_PATH='^diagnose:done regression-test:done fix:done classify:(low|medium|high) .*ship:pass deliver:done$'
CASE_FORCE_AFTER=''           # not a forced loop: the bug is the forcing function

case_setup() {
  mkdir -p tests
  cat > README.md <<'R'
# shop
Tiny stock and order bookkeeping. Tests: python3 -m unittest discover -s tests
R
  cat > stock.py <<'R'
class OutOfStock(Exception):
    pass


class Stock:
    def __init__(self):
        self.on_hand = {}
        self.reserved = {}

    def add(self, sku, qty):
        self.on_hand[sku] = self.on_hand.get(sku, 0) + qty

    def available(self, sku):
        return self.on_hand.get(sku, 0) - self.reserved.get(sku, 0)

    def reserve(self, sku, qty):
        if self.available(sku) < qty:
            raise OutOfStock(sku)
        self.reserved[sku] = self.reserved.get(sku, 0) + qty

    def release(self, sku, qty):
        self.reserved[sku] = self.reserved.get(sku, 0) - qty

    def ship(self, sku, qty):
        self.on_hand[sku] -= qty
        self.reserved[sku] -= qty
R
  cat > orders.py <<'R'
class Order:
    def __init__(self, stock, lines):
        self.stock = stock
        self.lines = dict(lines)
        self.shipped = {}
        for sku, qty in self.lines.items():
            stock.reserve(sku, qty)

    def ship(self, sku, qty):
        self.stock.ship(sku, qty)
        self.shipped[sku] = self.shipped.get(sku, 0) + qty

    def cancel(self):
        for sku, qty in self.lines.items():
            self.stock.release(sku, qty)
R
  cat > tests/test_orders.py <<'R'
import unittest
from stock import Stock, OutOfStock
from orders import Order


class Orders(unittest.TestCase):
    def test_reserve_reduces_available(self):
        s = Stock(); s.add("widget", 10)
        Order(s, {"widget": 4})
        self.assertEqual(s.available("widget"), 6)

    def test_out_of_stock(self):
        s = Stock(); s.add("widget", 3)
        with self.assertRaises(OutOfStock):
            Order(s, {"widget": 4})

    def test_cancel_unshipped_order_restores_stock(self):
        s = Stock(); s.add("widget", 10)
        o = Order(s, {"widget": 4})
        o.cancel()
        self.assertEqual(s.available("widget"), 10)


if __name__ == "__main__":
    unittest.main()
R
}

# The hidden acceptance kit (QA only): the reported scenario, the two-order scenario a clamp cannot satisfy, and a
# fully shipped order.
case_kit_setup() {
  cat > "$1/kit.py" <<'R'
import sys
sys.path.insert(0, sys.argv[1])
from stock import Stock
from orders import Order
bad = 0
def check(name, got, want):
    global bad
    if got != want:
        print("FAIL %s: expected %r, got %r" % (name, want, got)); bad += 1
    else:
        print("ok   %s == %r" % (name, want))

s = Stock(); s.add("widget", 10)
o = Order(s, {"widget": 5}); o.ship("widget", 3); o.cancel()
check("single order: available after cancelling a partly shipped order", s.available("widget"), 7)

s = Stock(); s.add("widget", 10)
a = Order(s, {"widget": 5}); b = Order(s, {"widget": 4})
a.ship("widget", 3); a.cancel()
check("two orders: available after A (3 of 5 shipped) is cancelled, B still holds 4", s.available("widget"), 3)
check("two orders: reserved is exactly B's 4", s.reserved["widget"], 4)

s = Stock(); s.add("widget", 10)
c = Order(s, {"widget": 2}); c.ship("widget", 2); c.cancel()
check("fully shipped order: cancel changes nothing", (s.on_hand["widget"], s.available("widget")), (8, 8))
sys.exit(1 if bad else 0)
R
}

# The Captain's addition for QA: the kit.
case_extra() { # <step> <role> <iteration> <kit-dir> <cwd> <data-dir>
  case $2 in
    qa) printf 'QA acceptance kit: run `python3 %s/kit.py .` from your working directory (it is the repository under test). It replays the reported scenarios. A failing expectation is a FAIL: report each one with the expected and the actual value exactly as the kit prints them. Then do the rest of your QA as usual.\n' "$4" ;;
  esac
}

case_hidden() { # <repo> <kit-dir>
  python3 "$2/kit.py" "$1" > "$RUN/hidden.last" 2>&1 || return 1
  ( cd "$1" && python3 -m unittest discover -s tests >/dev/null 2>&1 ) || { echo 'project tests fail' >> "$RUN/hidden.last"; return 1; }
}

# Case-specific evidence, from the fixture history and the per-step records of the run.
case_assert() { # <run-dir> <repo>
  local run=$1 repo=$2 base t f tmp files diag
  base=$(cat "$run/runs/regression-test:1/base_head" 2>/dev/null)
  t=$(cat "$run/runs/fix:1/base_head" 2>/dev/null)
  f=$(cat "$run/runs/classify:1/base_head" 2>/dev/null)
  [ -n "$base" ] && [ -n "$t" ] && [ -n "$f" ] || { echo "the per-step head records are missing (regression-test:1, fix:1, classify:1)"; return 1; }
  [ "$base" != "$t" ] || { echo "the tester committed nothing"; return 1; }
  files=$(git -C "$repo" diff --name-only "$base" "$t")
  [ -n "$files" ] || { echo "the regression-test step changed no file"; return 1; }
  case $(printf '%s\n' "$files" | grep -v '^tests/' | head -1) in '') ;; *) echo "the tester touched non-test files: $(printf '%s\n' "$files" | grep -v '^tests/' | tr '\n' ' ')"; return 1 ;; esac
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/fm-bugfix-judge.XXXXXX")
  git -C "$repo" archive "$t" | tar -x -C "$tmp"
  if ( cd "$tmp" && python3 -m unittest discover -s tests >/dev/null 2>&1 ); then rm -rf "$tmp"; echo "the regression test is not RED at the tester's commit (the whole suite passes on the buggy code)"; return 1; fi
  rm -rf "$tmp"; tmp=$(mktemp -d "${TMPDIR:-/tmp}/fm-bugfix-judge.XXXXXX")
  git -C "$repo" archive "$f" | tar -x -C "$tmp"
  if ! ( cd "$tmp" && python3 -m unittest discover -s tests >/dev/null 2>&1 ); then rm -rf "$tmp"; echo "the suite is not green at the fix commit"; return 1; fi
  rm -rf "$tmp"
  files=$(git -C "$repo" diff --name-only "$t" "$f")
  case $(printf '%s\n' "$files" | grep '^tests/' | head -1) in '') ;; *) echo "the fix step touched a test file: $(printf '%s\n' "$files" | grep '^tests/' | tr '\n' ' ')"; return 1 ;; esac
  [ -n "$files" ] || { echo "the fix step changed nothing"; return 1; }
  diag=$(ls "$run"/steps/*-diagnose/final.txt 2>/dev/null | head -1)
  grep -Eiq 'cancel' "$diag" && grep -Eiq 'ship' "$diag" || { echo "the diagnosis does not name Order.cancel and the shipped units as the cause"; return 1; }
  return 0
}

# Offline stand-in workers (self-test only).
case_canned() { # <role> <prompt-file> <cwd> -> final text on stdout
  local role=$1 prompt=$2 cwd=$3 base
  case $role in
    debugger)
      printf 'status: done\n\nReproduced: stock 10, order of 5, ship 3, cancel -> available 6. Root cause: Order.cancel() releases the full ordered quantity including the 3 shipped units, so reserved goes negative. Stock.release is only the amplifier.\n' ;;
    test-engineer)
      base=$(git -C "$cwd" rev-parse HEAD)
      cat > "$cwd/tests/test_cancel_partial.py" <<'R'
import unittest
from stock import Stock
from orders import Order


class CancelPartlyShipped(unittest.TestCase):
    def test_other_orders_reservation_survives(self):
        s = Stock(); s.add("widget", 10)
        a = Order(s, {"widget": 5}); Order(s, {"widget": 4})
        a.ship("widget", 3); a.cancel()
        self.assertEqual(s.available("widget"), 3)


if __name__ == "__main__":
    unittest.main()
R
      git -C "$cwd" add -A && git -C "$cwd" commit -q -m "tests: cancel after partial ship"
      canned_result "$cwd" "$base" 'Added a regression test: red on the current code.' "$prompt" ;;
    senior-fullstack)
      base=$(git -C "$cwd" rev-parse HEAD)
      if [ "${FAKE_MODE:-}" = clamp ]; then
        # offline self-test only: the SYMPTOM fix (clamp Stock.release at zero) that the two-order scenario catches
        python3 - "$cwd/stock.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("self.reserved[sku] = self.reserved.get(sku, 0) - qty", "self.reserved[sku] = max(0, self.reserved.get(sku, 0) - qty)")
open(p, "w").write(s)
PY
      else
        cat > "$cwd/orders.py" <<'R'
class Order:
    def __init__(self, stock, lines):
        self.stock = stock
        self.lines = dict(lines)
        self.shipped = {}
        for sku, qty in self.lines.items():
            stock.reserve(sku, qty)

    def ship(self, sku, qty):
        self.stock.ship(sku, qty)
        self.shipped[sku] = self.shipped.get(sku, 0) + qty

    def cancel(self):
        for sku, qty in self.lines.items():
            self.stock.release(sku, qty - self.shipped.get(sku, 0))
R
      fi
      git -C "$cwd" add -A && git -C "$cwd" commit -q -m "orders: cancel releases only the unshipped units"
      canned_result "$cwd" "$base" 'Fixed the cause in Order.cancel.' "$prompt" ;;
    qa)
      local kit out rc
      kit=$(sed -n 's#^QA acceptance kit: run `python3 \(.*\)/kit.py.*#\1#p' "$prompt" | head -1)
      out=$(python3 "$kit/kit.py" "$cwd" 2>&1); rc=$?
      if [ $rc -eq 0 ]; then printf 'Ran the kit: every scenario holds.\n\n'; canned_verdict PASS "$cwd" '[]'
      else printf 'Ran the kit.\n%s\n\n' "$out"; canned_verdict FAIL "$cwd" '[{"id":"QA-1","severity":"BLOCKER","what":"kit failed","where":"orders.py"}]'; fi ;;
    code-reviewer)
      printf 'Reviewed the fix: small and targeted.\n\n'; canned_verdict PASS "$cwd" '[]' ;;
  esac
}
