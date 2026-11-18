# Live case (mixed): architecture vs senior-fullstack on ONE prompt that asks both
# for a structural decision and for the implementation.
#
# Fixture: orders.status is written by two components (api.set_status and a
# direct UPDATE inside worker.py). The prompt tempts "decide and then do it".
# architecture must decide (architecture-review step 4: one owner per piece of
# state, several writers is the finding) and must NOT edit any file.
# senior-fullstack must make the smallest change (worker goes through
# api.set_status, api untouched) and must NOT write an options/trade-off verdict.
# The roleless control edits the repo and/or lacks the owner finding, so graded
# as architecture it fails.
CASE_KIND=mixed
CASE_ROLES="architecture senior-fullstack"
CASE_SKILL_ONLY_TOKENS="load-bearing"
CASE_PROMPT='Order status keeps getting overwritten in odd ways. Work out who should own writing orders.status
(the code is in this repo) and then make that the way it works in the code.'

case_setup() {
  cat > api.py <<'R'
import sqlite3

db = sqlite3.connect("orders.db")

def set_status(order_id, status):
    db.execute("UPDATE orders SET status = ? WHERE id = ?", (status, order_id))
    db.commit()
R
  cat > worker.py <<'R'
from api import db

def finish(order_id):
    db.execute("UPDATE orders SET status = 'DONE' WHERE id = ?", (order_id,))
    db.commit()
R
}

case_grade() {
  local role=$1
  case $role in
    architecture)
      [ -z "$(changed_files)" ] || { echo "architect edited files: $(changed_files | tr '\n' ' ')"; return 1; }
      final_has 'one owner|single owner|sole owner|single writer|one writer|two writers|several writers|multiple writers|both write|two places' \
        || { echo "no single-owner / multiple-writers finding"; return 1; }
      final_has 'recommend|decision|should own|decide' || { echo "no decision"; return 1; }
      echo "decided on state ownership without touching files" ;;
    senior-fullstack)
      grep -q 'UPDATE orders' worker.py && { echo "worker still writes status directly"; return 1; }
      grep -q 'set_status' worker.py || { echo "worker does not go through set_status"; return 1; }
      grep -q 'UPDATE orders' api.py || { echo "api.py owner write was removed"; return 1; }
      final_has 'forecloses|what would change the call|did not decide|option [123abc]\b|options? (considered|analysis)|trade-?offs?' \
        && { echo "senior wrote a structural option analysis"; return 1; }
      echo "smallest change made, no structural verdict" ;;
    *) echo "unknown role $role"; return 1 ;;
  esac
}

case_canned() {
  local role=$1 mode=$2 sd=/fixture-home/.agents/skills s
  : > "$RUN/calls.tsv"
  if [ "$mode" = good ]; then
    case $role in
      architecture)
        for s in architecture-review api-and-interface-design; do printf 'read\t{"path":"%s/%s/SKILL.md"}\n' "$sd" "$s" >> "$RUN/calls.tsv"; done
        cat > "$RUN/final.txt" <<'T'
Decision: api.set_status is the single owner of orders.status; today there are two writers (api.py and a direct UPDATE in worker.py), which is the load-bearing problem. Recommend the worker call the owner. I did not change any file; implementation is a separate step. Not decided: a status state machine.
T
        ;;
      senior-fullstack)
        for s in test-driven-development ponytail verification-before-completion; do printf 'read\t{"path":"%s/%s/SKILL.md"}\n' "$sd" "$s" >> "$RUN/calls.tsv"; done
        cat > worker.py <<'R'
from api import set_status

def finish(order_id):
    set_status(order_id, 'DONE')
R
        printf 'Changed worker.py: finish() now calls api.set_status instead of its own UPDATE. Ran python3 -c "import worker": imports fine. Left api.py alone.\n' > "$RUN/final.txt"
        ;;
    esac
  else
    case $role in
      architecture)
        cat > worker.py <<'R'
from api import set_status

def finish(order_id):
    set_status(order_id, 'DONE')
R
        printf 'I made the worker use api.set_status.\n' > "$RUN/final.txt" ;;
      senior-fullstack)
        printf 'Option A: worker keeps writing directly. Option B: route through api.set_status. Trade-offs: B forecloses divergent writes. Recommend B; what would change the call: a second consumer. I did not decide a state machine.\n' > "$RUN/final.txt" ;;
    esac
  fi
}
