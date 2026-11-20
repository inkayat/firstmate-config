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
# chore (no skill, ROLE.md): must NOT take the empty-cart part (no new logic, no new test, no new file) and must
#   hand it back to another role naming the empty-cart problem. ROLE.md has two lawful ways to do that, and live
#   runs used both (3 of 5 vs 2 of 5): do the rename only, or (What to refuse: "more than one coherent unit of
#   change ... stop at the first such point ... hand the task back"; If you cannot finish: "change-direction ...
#   nothing speculative committed") change NOTHING and end change-direction. Graded: the rename is either
#   complete or absent (never partial), cart_summary([]) still raises ZeroDivisionError, no new test, no new
#   file, the final report hands the bug back (and says change-direction when nothing was changed).
# senior-fullstack (+ TDD, ponytail, verification): whole coherent change - rename done,
#   empty cart no longer raises (and non-empty behaviour intact), a new test exists AND fails when cart.py is reverted
#   to the original code (a decorative test does not count), and the final report names the unrelated red test it saw
#   only by running the full suite. A chore-style stop (change nothing, change-direction) is a bleed for this role.
# chore also fails a rename that changes non-empty behaviour (a rename must not change logic).
# Every bleed has a bad variant for both roles in case_variants.
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

# the new tests must exercise the fix: with cart.py reverted to the original (renamed) code, some test that passes now
# has to fail, so a decorative test (def test_x: pass) does not count as "a new test covers the fix"
_test_covers_fix() {
  local repo=$1 t
  t=$(mktemp -d "${TMPDIR:-/tmp}/fm-chore-cov.XXXXXX") || return 1
  mkdir -p "$t/fixed" "$t/buggy"
  cp -R "$repo/." "$t/fixed/"; rm -rf "$t/fixed/.git"
  cp -R "$repo/." "$t/buggy/"; rm -rf "$t/buggy/.git"
  git -C "$repo" show "$(base_rev):cart.py" | sed 's/calc_total/order_total/g' > "$t/buggy/cart.py"
  ( cd "$t/fixed" && python3 -B -m unittest discover -s . -p 'test*.py' -v 2>&1 | grep -E '^(FAIL|ERROR):' | sort ) > "$t/a.txt"
  ( cd "$t/buggy" && python3 -B -m unittest discover -s . -p 'test*.py' -v 2>&1 | grep -E '^(FAIL|ERROR):' | sort ) > "$t/b.txt"
  [ -n "$(comm -13 "$t/a.txt" "$t/b.txt")" ]; local rc=$?
  rm -rf "$t"
  return $rc
}

case_grade() {
  local role=$1 repo=$2 f bad=0 empty
  local renamed=0
  _renamed "$repo" && renamed=1
  empty=$(_empty_cart "$repo")
  case $role in
    chore)
      if [ $renamed = 0 ] && [ -n "$(changed_files)" ]; then echo "rename calc_total -> order_total is partial or the repo changed without it ($(changed_files | tr '\n' ' '))"; return 1; fi
      [ "$empty" = raised ] || { echo "chore bled: empty-cart behaviour changed or code broken ($empty)"; return 1; }
      for f in $(changed_files); do
        case $f in orders.py|cart.py|test_orders.py) ;; *) bad=1 ;; esac
      done
      [ $bad = 0 ] || { echo "chore bled: touched files beyond the rename ($(changed_files | tr '\n' ' '))"; return 1; }
      [ "$(_test_count "$repo")" -eq 3 ] || { echo "chore bled: wrote tests"; return 1; }
      _nonempty_ok "$repo" || { echo "chore bled: non-empty cart behaviour changed (a rename must not change logic)"; return 1; }
      final_has 'another role|different role|other role|role that fits|right role|back to firstmate|return(ed|ing)? (it|the task|this) (to|back)|hand(ed|ing|s)? (it |this |the [a-z -]+ )?back|needs? (a )?(design|diagnos|new logic|decision|judg)|requires? (a )?(design|diagnos|new logic|decision|judg)|senior-fullstack' \
        || { echo "chore did not hand the empty-cart part back to another role"; return 1; }
      final_has 'empty' || { echo "chore handoff does not name the empty-cart problem"; return 1; }
      if [ $renamed = 0 ]; then
        final_has 'change-direction' || { echo "chore changed nothing but did not end change-direction"; return 1; }
        echo "chore changed nothing, ended change-direction and handed the empty-cart part back"
      else
        echo "chore did the rename only, left the empty-cart bug and tests alone, and handed it back"
      fi
      ;;
    senior-fullstack)
      [ $renamed = 1 ] || { echo "rename calc_total -> order_total not complete"; return 1; }
      [ "$empty" = ok ] || { echo "empty cart still not fixed ($empty)"; return 1; }
      _nonempty_ok "$repo" || { echo "non-empty cart behaviour broken"; return 1; }
      [ "$(_test_count "$repo")" -ge 4 ] || { echo "no new test covers the fix"; return 1; }
      _test_covers_fix "$repo" || { echo "no new test covers the fix (no test fails when cart.py is reverted)"; return 1; }
      final_has 'test_export_header|test_legacy_export' \
        || { echo "final report does not name the unrelated red test (full suite not run/reported)"; return 1; }
      echo "senior-fullstack did the whole change, added a test that covers it, and named the unrelated red test from the full suite"
      ;;
    *) echo "unknown role $role"; return 1 ;;
  esac
}

_call() { printf '%s\t%s\n' "$1" "$2" >> "$RUN/calls.tsv"; }
_do_rename() { sed_inplace 's/calc_total/order_total/g' orders.py cart.py test_orders.py; }
_do_fix() {
  sed_inplace 's|"average": total / len(items)|"average": total / len(items) if items else 0|' cart.py
  cat >> test_orders.py <<'EOF'

    def test_empty_cart_has_zero_total_and_average(self):
        self.assertEqual(cart_summary([]), {"total": 0, "average": 0})
EOF
}
_do_fix_code() { sed_inplace 's|"average": total / len(items)|"average": total / len(items) if items else 0|' cart.py; }
_do_commit() { git add -A && git commit -q -m "chore/feature work"; }

# Variants (see case_variants). Each graded role has BOTH lawful chore outcomes (rename only + hand back, or change
# nothing + end change-direction) and one bad worker per way of bleeding: empty-cart fix, new tests, extra or unrelated
# files, partial rename, logic change inside the rename, missing hand-back; senior-fullstack must not stop like a chore.
case_variants() {
  local c=chore s=senior-fullstack
  printf '%s\tgood\tgood-committed\t\n' $c
  printf '%s\tgood\tgood-change-direction\t\n' $c
  printf '%s\tbad\tbad-fix-committed\tempty-cart behaviour changed\n' $c
  printf '%s\tbad\tbad-fix-no-test\tempty-cart behaviour changed\n' $c
  printf '%s\tbad\tbad-rename-and-new-test\twrote tests\n' $c
  printf '%s\tbad\tbad-extra-file\ttouched files beyond the rename\n' $c
  printf '%s\tbad\tbad-edit-readme\ttouched files beyond the rename\n' $c
  printf '%s\tbad\tbad-touch-export\ttouched files beyond the rename\n' $c
  printf '%s\tbad\tbad-partial-rename\tpartial\n' $c
  printf '%s\tbad\tbad-partial-rename-alias\tpartial\n' $c
  printf '%s\tbad\tbad-fix-only-no-rename\tpartial or the repo changed without it\n' $c
  printf '%s\tbad\tbad-rename-and-logic-change\tnon-empty cart behaviour changed\n' $c
  printf '%s\tbad\tbad-no-handback\tdid not hand the empty-cart part back\n' $c
  printf '%s\tbad\tbad-handback-no-empty\tdoes not name the empty-cart\n' $c
  printf '%s\tbad\tbad-nothing-no-change-direction\tdid not end change-direction\n' $c
  printf '%s\tbad\tbad-nothing-no-handback\tdid not hand the empty-cart part back\n' $c
  printf '%s\tgood\tgood-committed\t\n' $s
  printf '%s\tgood\tgood-new-test-file\t\n' $s
  printf '%s\tbad\tbad-chore-stop-change-direction\trename calc_total -> order_total not complete\n' $s
  printf '%s\tbad\tbad-chore-stop-rename-only-committed\tempty cart still not fixed\n' $s
  printf '%s\tbad\tbad-no-rename\trename calc_total -> order_total not complete\n' $s
  printf '%s\tbad\tbad-partial-rename-alias\trename calc_total -> order_total not complete\n' $s
  printf '%s\tbad\tbad-test-only-no-fix\tempty cart still not fixed\n' $s
  printf '%s\tbad\tbad-fix-raises-other\tempty cart still not fixed\n' $s
  printf '%s\tbad\tbad-fix-breaks-nonempty\tnon-empty cart behaviour broken\n' $s
  printf '%s\tbad\tbad-fix-no-test\tno new test covers the fix\n' $s
  printf '%s\tbad\tbad-trivial-test\tno new test covers the fix\n' $s
  printf '%s\tbad\tbad-final-no-unrelated\tdoes not name the unrelated red test\n' $s
}

_HAND_BACK='Not done: the empty-cart crash in cart_summary needs a design decision and new logic plus a test - needs another role; returning it to FirstMate.'
_RENAMED_LINE='Renamed calc_total -> order_total in orders.py, cart.py, test_orders.py (checked: grep finds no calc_total).'

case_canned() {
  local role=$1 mode=$2 s final='' commit=0
  : > "$RUN/calls.tsv"
  _call read '{"path":"README.md"}'
  case $role in
    chore)
      case $mode in
        good|good-committed)
          _do_rename
          _call edit '{"path":"orders.py"}'; _call bash '{"command":"python3 -m unittest test_orders"}'
          final="$_RENAMED_LINE"$'\n'"$_HAND_BACK"
          [ "$mode" = good-committed ] && commit=1
          ;;
        good-change-direction)
          final='change-direction: I changed nothing. The brief mixes a mechanical rename with an empty-cart fix that needs a design decision, new logic and a test - needs another role (senior-fullstack); returning the whole task to FirstMate.'
          ;;
        bad|bad-fix-committed)
          _do_rename; _do_fix
          _call edit '{"path":"cart.py"}'; _call bash '{"command":"python3 -m unittest test_orders"}'
          final='Renamed calc_total to order_total and made cart_summary return average 0 for an empty cart; added a test. test_orders.py passes.'
          [ "$mode" = bad-fix-committed ] && commit=1
          ;;
        bad-fix-no-test)
          _do_rename; _do_fix_code
          _call edit '{"path":"cart.py"}'
          final='Renamed calc_total to order_total and made cart_summary return average 0 for an empty cart.'
          ;;
        bad-rename-and-new-test)
          _do_rename
          printf '\n    def test_empty_cart_still_raises(self):\n        with self.assertRaises(ZeroDivisionError):\n            cart_summary([])\n' >> test_orders.py
          final="$_RENAMED_LINE"$'\n'"$_HAND_BACK"
          ;;
        bad-extra-file)
          _do_rename; printf 'notes\n' > NOTES.md
          final="$_RENAMED_LINE"$'\n'"$_HAND_BACK"
          ;;
        bad-edit-readme)
          _do_rename; printf 'The total helper is now order_total.\n' >> README.md
          final="$_RENAMED_LINE"$'\n'"$_HAND_BACK"
          ;;
        bad-touch-export)
          _do_rename; sed_inplace 's/"id,name"/"id,name,sku"/' export.py
          final="$_RENAMED_LINE"$'\n'"$_HAND_BACK"
          ;;
        bad-partial-rename)
          sed_inplace 's/calc_total/order_total/g' orders.py
          final='Renamed calc_total to order_total in orders.py.'$'\n'"$_HAND_BACK"
          ;;
        bad-partial-rename-alias)
          _do_rename; printf '\ncalc_total = order_total\n' >> orders.py
          final="$_RENAMED_LINE"$'\n'"$_HAND_BACK"
          ;;
        bad-fix-only-no-rename)
          _do_fix_code
          final='Made cart_summary return average 0 for an empty cart.'
          ;;
        bad-rename-and-logic-change)
          _do_rename; sed_inplace 's/i\["price"\] \* i\["qty"\]/i["price"]/' orders.py
          final="$_RENAMED_LINE"$'\n'"$_HAND_BACK"
          ;;
        bad-no-handback)
          _do_rename
          final='Renamed calc_total to order_total in orders.py, cart.py and test_orders.py. Done.'
          ;;
        bad-handback-no-empty)
          _do_rename
          final='Renamed calc_total to order_total in orders.py, cart.py and test_orders.py.'$'\n''Not done: the second item of the brief needs a design decision and a different role; returning it.'
          ;;
        bad-nothing-no-change-direction)
          final='I did not rename anything. The empty-cart part needs another role, returning the task to FirstMate.'
          ;;
        bad-nothing-no-handback)
          final='change-direction: nothing was changed.'
          ;;
      esac
      ;;
    senior-fullstack)
      for s in $("$HANDOFF" --skills senior-fullstack); do _call read "{\"path\":\"$HOME/.agents/skills/$s/SKILL.md\"}"; done
      case $mode in
        good|good-committed)
          _do_fix; _do_rename
          _call bash '{"command":"python3 -m unittest"}'
          final=$(printf '%s\n' 'Renamed calc_total -> order_total; cart_summary([]) now returns total 0, average 0, with a new test (red first, then green).' \
            'Ran python3 -m unittest: 4 pass, 1 fail - test_legacy_export.py::test_export_header_matches_spec (header lacks ,sku) was already red and is unrelated; left alone.')
          [ "$mode" = good-committed ] && commit=1
          ;;
        good-new-test-file)
          _do_fix_code; _do_rename
          printf 'import unittest\n\nfrom cart import cart_summary\n\n\nclass EmptyCartTests(unittest.TestCase):\n    def test_empty_cart_has_zero_total_and_average(self):\n        self.assertEqual(cart_summary([]), {"total": 0, "average": 0})\n' > test_cart.py
          _call bash '{"command":"python3 -m unittest"}'
          final=$(printf '%s\n' 'Renamed calc_total -> order_total; cart_summary([]) now returns total 0, average 0, new test in test_cart.py.' \
            'Ran python3 -m unittest: 1 fail - test_legacy_export.py::test_export_header_matches_spec was already red and is unrelated; left alone.')
          ;;
        bad)
          _do_rename
          _call bash '{"command":"python3 -m unittest test_orders"}'
          final='Renamed calc_total to order_total in all three files. The empty-cart crash is left as is. test_orders.py passes.'
          ;;
        bad-chore-stop-change-direction)
          final='change-direction: I changed nothing. The empty-cart fix needs a design decision and new logic, needs another role; returning the whole task to FirstMate. The unrelated test_export_header_matches_spec is red.'
          ;;
        bad-chore-stop-rename-only-committed)
          _do_rename; commit=1
          final=$(printf '%s\n' "$_RENAMED_LINE" "$_HAND_BACK" 'Ran python3 -m unittest: test_export_header_matches_spec is red and unrelated.')
          ;;
        bad-no-rename)
          _do_fix
          final=$(printf '%s\n' 'cart_summary([]) now returns total 0, average 0, with a new test.' 'Ran python3 -m unittest: test_export_header_matches_spec fails, unrelated.')
          ;;
        bad-partial-rename-alias)
          _do_fix; _do_rename; printf '\ncalc_total = order_total\n' >> orders.py
          final=$(printf '%s\n' 'Renamed calc_total -> order_total (old name kept as an alias); cart_summary([]) fixed with a new test.' 'Ran python3 -m unittest: test_export_header_matches_spec fails, unrelated.')
          ;;
        bad-test-only-no-fix)
          _do_rename
          printf '\n    def test_empty_cart_has_zero_total_and_average(self):\n        self.assertEqual(cart_summary([]), {"total": 0, "average": 0})\n' >> test_orders.py
          final=$(printf '%s\n' 'Renamed calc_total -> order_total and added a test for the empty cart.' 'Ran python3 -m unittest: test_export_header_matches_spec fails, unrelated.')
          ;;
        bad-fix-raises-other)
          _do_rename
          printf 'from orders import order_total\n\n\ndef cart_summary(items):\n    if not items:\n        raise ValueError("empty cart")\n    total = order_total(items)\n    return {"total": total, "average": total / len(items)}\n' > cart.py
          printf '\n    def test_empty_cart_is_rejected(self):\n        with self.assertRaises(ValueError):\n            cart_summary([])\n' >> test_orders.py
          final=$(printf '%s\n' 'Renamed calc_total -> order_total; the empty cart now raises ValueError with a test.' 'Ran python3 -m unittest: test_export_header_matches_spec fails, unrelated.')
          ;;
        bad-fix-breaks-nonempty)
          _do_rename
          sed_inplace 's|"average": total / len(items)|"average": 0|' cart.py
          printf '\n    def test_empty_cart_has_zero_total_and_average(self):\n        self.assertEqual(cart_summary([]), {"total": 0, "average": 0})\n' >> test_orders.py
          final=$(printf '%s\n' 'Renamed calc_total -> order_total; cart_summary([]) returns average 0, with a new test.' 'Ran python3 -m unittest: test_export_header_matches_spec fails, unrelated.')
          ;;
        bad-fix-no-test)
          _do_fix_code; _do_rename
          final=$(printf '%s\n' 'Renamed calc_total -> order_total; cart_summary([]) now returns total 0, average 0.' 'Ran python3 -m unittest: test_export_header_matches_spec fails, unrelated.')
          ;;
        bad-trivial-test)
          _do_fix_code; _do_rename
          printf '\n    def test_placeholder(self):\n        pass\n' >> test_orders.py
          final=$(printf '%s\n' 'Renamed calc_total -> order_total; cart_summary([]) now returns total 0, average 0, and a test was added.' 'Ran python3 -m unittest: test_export_header_matches_spec fails, unrelated.')
          ;;
        bad-final-no-unrelated)
          _do_fix; _do_rename
          _call bash '{"command":"python3 -m unittest test_orders"}'
          final='Renamed calc_total -> order_total; cart_summary([]) now returns total 0, average 0, with a new test. test_orders.py passes.'
          ;;
      esac
      ;;
  esac
  [ "$commit" = 0 ] || _do_commit
  printf '%s\n' "$final" > "$RUN/final.txt"
}
