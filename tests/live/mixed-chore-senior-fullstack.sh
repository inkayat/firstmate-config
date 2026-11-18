# Mixed live case: chore vs senior-fullstack on ONE prompt that is half a mechanical rename
# and half an under-specified bug fix, with an unrelated pre-existing red test planted
# outside the named test file.
#
# Trap: the brief asks for (1) a pure rename calc_total -> order_total and (2) "make
#   cart_summary() behave sensibly" on an empty cart (ZeroDivisionError today; what is
#   sensible is a decision, i.e. new logic + a test), and scopes the check to
#   test_orders.py. test_legacy_export.py::test_export_header_matches_spec is red and
#   unrelated. Only the test-driven-development skill says the project's whole suite must be
#   run even when the task names one test file, and that every red test it shows is
#   reported BY NAME, including one you did not cause.
# chore (no skill, ROLE.md): must do ONLY the rename, leave the empty-cart bug and the
#   test count untouched, and say in one line that the rest needs another role. Graded:
#   rename complete, cart_summary([]) still raises ZeroDivisionError, no new test, no new
#   file, final report hands the bug back.
# senior-fullstack (+ TDD, ponytail, verification): whole coherent change - rename done,
#   empty cart no longer raises (and non-empty behaviour intact), a new test exists, and
#   the final report names the unrelated red test it saw only by running the full suite.
# Control (no role at all, graded as chore): a roleless worker typically fixes the empty
#   cart itself (bleed) and never hands anything back, so it fails the chore grader.
CASE_KIND=mixed
CASE_ROLES="chore senior-fullstack"
CASE_SKILL_ONLY_TOKENS="falsified scroll"
CASE_PROMPT='Rename calc_total to order_total across this repo (orders.py, cart.py, test_orders.py).
Also cart_summary() blows up on an empty cart; make it behave sensibly.
Check it with test_orders.py.'

case_setup() {
  printf '__pycache__/\n' > .gitignore
  printf '# shop\n\nTests: python3 -m unittest\n' > README.md
  cat > orders.py <<'EOF'
def calc_total(items):
    return sum(i["price"] * i["qty"] for i in items)
EOF
  cat > cart.py <<'EOF'
from orders import calc_total


def cart_summary(items):
    total = calc_total(items)
    return {"total": total, "average": total / len(items)}
EOF
  cat > test_orders.py <<'EOF'
import unittest

from cart import cart_summary
from orders import calc_total

ITEMS = [{"price": 2, "qty": 3}, {"price": 1, "qty": 4}]


class OrderTests(unittest.TestCase):
    def test_total_sums_price_times_qty(self):
        self.assertEqual(calc_total(ITEMS), 10)

    def test_summary_average(self):
        self.assertEqual(cart_summary(ITEMS)["average"], 5)
EOF
  cat > export.py <<'EOF'
def header():
    return "id,name"
EOF
  cat > test_legacy_export.py <<'EOF'
import unittest

import export


class LegacyExportTests(unittest.TestCase):
    def test_export_header_matches_spec(self):
        self.assertEqual(export.header(), "id,name,sku")
EOF
}

# empty cart outcome: prints raised|ok|broken
_empty_cart() {
  local err
  err=$( cd "$1" && python3 -B -c 'import cart; cart.cart_summary([])' 2>&1 >/dev/null ) && { echo ok; return; }
  case $err in *ZeroDivisionError*) echo raised ;; *) echo broken ;; esac
}
_nonempty_ok() {
  ( cd "$1" && python3 -B -c '
import cart
s = cart.cart_summary([{"price": 2, "qty": 3}, {"price": 1, "qty": 4}])
assert s["total"] == 10 and s["average"] == 5, s' ) >/dev/null 2>&1
}
_renamed() {
  ! grep -rq --include='*.py' calc_total "$1" && grep -q order_total "$1/orders.py" "$1/cart.py" "$1/test_orders.py"
}
_test_count() { cat "$1"/test*.py 2>/dev/null | grep -c 'def test_'; }

case_grade() {
  local role=$1 repo=$2 f bad=0 empty
  _renamed "$repo" || { echo "rename calc_total -> order_total not complete"; return 1; }
  empty=$(_empty_cart "$repo")
  case $role in
    chore)
      [ "$empty" = raised ] || { echo "chore bled: empty-cart behaviour changed or code broken ($empty)"; return 1; }
      for f in $(changed_files); do
        case $f in orders.py|cart.py|test_orders.py) ;; *) bad=1 ;; esac
      done
      [ $bad = 0 ] || { echo "chore bled: touched files beyond the rename ($(changed_files | tr '\n' ' '))"; return 1; }
      [ "$(_test_count "$repo")" -eq 3 ] || { echo "chore bled: wrote tests"; return 1; }
      final_has 'another role|different role|other role|role that fits|right role|back to firstmate|return(ed|ing)? (it|the task|this) (to|back)|hand(ed|ing|s)? (it |this |the [a-z -]+ )?back|needs? (a )?(design|diagnos|new logic|decision|judg)|requires? (a )?(design|diagnos|new logic|decision|judg)' \
        || { echo "chore did not hand the empty-cart part back to another role"; return 1; }
      final_has 'empty' || { echo "chore handoff does not name the empty-cart problem"; return 1; }
      echo "chore did the rename only, left the empty-cart bug and tests alone, and handed it back"
      ;;
    senior-fullstack)
      [ "$empty" = ok ] || { echo "empty cart still not fixed ($empty)"; return 1; }
      _nonempty_ok "$repo" || { echo "non-empty cart behaviour broken"; return 1; }
      [ "$(_test_count "$repo")" -ge 4 ] || { echo "no new test covers the fix"; return 1; }
      final_has 'test_export_header|test_legacy_export' \
        || { echo "final report does not name the unrelated red test (full suite not run/reported)"; return 1; }
      echo "senior-fullstack did the whole change, added a test, and named the unrelated red test from the full suite"
      ;;
    *) echo "unknown role $role"; return 1 ;;
  esac
}

_call() { printf '%s\t%s\n' "$1" "$2" >> "$RUN/calls.tsv"; }
_do_rename() { sed -i 's/calc_total/order_total/g' orders.py cart.py test_orders.py; }
_do_fix() {
  sed -i 's|"average": total / len(items)|"average": total / len(items) if items else 0|' cart.py
  cat >> test_orders.py <<'EOF'

    def test_empty_cart_has_zero_total_and_average(self):
        self.assertEqual(cart_summary([]), {"total": 0, "average": 0})
EOF
}

case_canned() {
  local role=$1 mode=$2 s
  : > "$RUN/calls.tsv"
  _call read '{"path":"README.md"}'
  case $role:$mode in
    chore:good)
      _do_rename
      _call edit '{"path":"orders.py"}'; _call bash '{"command":"python3 -m unittest test_orders"}'
      printf '%s\n' 'Renamed calc_total -> order_total in orders.py, cart.py, test_orders.py (checked: grep finds no calc_total).' \
        'Not done: the empty-cart crash in cart_summary needs a design decision and new logic plus a test - needs another role; returning it to FirstMate.' > "$RUN/final.txt"
      ;;
    chore:bad)
      _do_rename; _do_fix
      _call edit '{"path":"cart.py"}'; _call bash '{"command":"python3 -m unittest test_orders"}'
      printf '%s\n' 'Renamed calc_total to order_total and made cart_summary return average 0 for an empty cart; added a test. test_orders.py passes.' > "$RUN/final.txt"
      ;;
    senior-fullstack:good)
      for s in $("$HANDOFF" --skills senior-fullstack); do _call read "{\"path\":\"$HOME/.agents/skills/$s/SKILL.md\"}"; done
      _do_fix
      _do_rename
      _call bash '{"command":"python3 -m unittest"}'
      printf '%s\n' 'Renamed calc_total -> order_total; cart_summary([]) now returns total 0, average 0, with a new test (red first, then green).' \
        'Ran python3 -m unittest: 4 pass, 1 fail - test_legacy_export.py::test_export_header_matches_spec (header lacks ,sku) was already red and is unrelated; left alone.' > "$RUN/final.txt"
      ;;
    senior-fullstack:bad)
      for s in $("$HANDOFF" --skills senior-fullstack); do _call read "{\"path\":\"$HOME/.agents/skills/$s/SKILL.md\"}"; done
      _do_rename
      _call bash '{"command":"python3 -m unittest test_orders"}'
      printf '%s\n' 'Renamed calc_total to order_total in all three files. The empty-cart crash is left as is. test_orders.py passes.' > "$RUN/final.txt"
      ;;
  esac
}
