#!/usr/bin/env bash
# board.sh - fixture-based acceptance for `fm-board` / `fm board`.
#
# Every scenario runs against an isolated FM_HOME under TMP_ROOT; nothing here
# ever touches the operator's real ~/.firstmate. Reconcile scenarios fake
# FIRSTMATE_ROOT with a stub bin/fm-crew-state.sh so no real no-mistakes,
# network, or forge access is required. `python3` is required to run
# `bin/fm-board` itself (see AGENTS.md); the suite skips with a clear message
# when it is absent rather than reporting a false pass or fail.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOARD="$CONFIG_ROOT/bin/fm-board"
FM="$CONFIG_ROOT/bin/fm"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$3', got '$2')"; fi; }
contains() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in '$2')" ;; esac; }
not_contains() { case $2 in *"$3"*) fail "$1 (unexpectedly found '$3' in '$2')" ;; *) pass "$1" ;; esac; }

if ! command -v python3 >/dev/null 2>&1; then
  printf 'board.sh: skipped entirely (no python3 on this machine to run fm-board)\n'
  exit 0
fi

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-board-test.XXXXXX") || exit 1
TMP_ROOT=$(cd "$TMP_ROOT" && pwd)
trap 'rm -rf "$TMP_ROOT"' EXIT

# =============================================================================
# Scenario 1: core CLI against an empty isolated home, no Firstmate ledger.
# =============================================================================
HOME1="$TMP_ROOT/home1"
mkdir -p "$HOME1"
run1() { FM_HOME="$HOME1" FIRSTMATE_ROOT="$TMP_ROOT/no-such-firstmate" PATH="/usr/bin:/bin" "$BOARD" "$@"; }

out=$(run1 add --project demo --title "First task" --id demo-task-1)
rc=$?
check '1 add: exit 0' "$rc" 0
contains '1 add: reports new id' "$out" 'demo-task-1'

out=$(run1 add --project demo --title "Duplicate id" --id demo-task-1)
rc=$?
if [ "$rc" -ne 0 ]; then pass '1 add: duplicate id fails nonzero'; else fail '1 add: duplicate id fails nonzero'; fi
contains '1 add: duplicate id error names the id' "$out$(run1 add --project demo --title "Duplicate id" --id demo-task-1 2>&1 1>/dev/null)" 'demo-task-1'

out=$(run1 show demo-task-1)
check '1 show: exit 0' $? 0
contains '1 show: has id' "$out" 'demo-task-1'
contains '1 show: has project' "$out" 'demo'
contains '1 show: default state is todo' "$out" 'todo'

out=$(run1 show no-such-task 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then pass '1 show: missing id fails nonzero'; else fail '1 show: missing id fails nonzero'; fi
contains '1 show: missing id error names the id' "$out" 'no-such-task'

out=$(run1 update demo-task-1 --agent "omp . claude-sonnet-5" --note "manual note")
check '2 update: exit 0' $? 0
out=$(run1 show demo-task-1)
contains '2 update: agent applied' "$out" 'omp . claude-sonnet-5'
contains '2 update: note applied' "$out" 'manual note'
contains '2 update: title preserved' "$out" 'First task'
contains '2 update: state preserved' "$out" 'todo'

out=$(run1 update no-such-task --agent x 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then pass '2 update: missing id fails nonzero'; else fail '2 update: missing id fails nonzero'; fi

out=$(run1 move demo-task-1 in_progress)
check '3 move: exit 0' $? 0
out=$(run1 show demo-task-1)
contains '3 move: state now in_progress' "$out" 'in_progress'

out=$(run1 move demo-task-1 waiting_review)
out=$(run1 show demo-task-1)
contains '3 move: state now waiting_review' "$out" 'waiting_review'

out=$(run1 move demo-task-1 "done")
out=$(run1 show demo-task-1)
contains '3 move: state now done' "$out" 'done'

out=$(run1 move demo-task-1 bogus-state 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then pass '3 move: invalid state fails nonzero'; else fail '3 move: invalid state fails nonzero'; fi
contains '3 move: invalid state names allowed states' "$out" 'todo'

out=$(run1 move no-such-task blocked 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then pass '3 move: missing id fails nonzero'; else fail '3 move: missing id fails nonzero'; fi

# A second, independent task in a different project; used for isolation and
# project filtering assertions below.
run1 add --project other --title "Second task" --id other-task-1 >/dev/null
run1 move other-task-1 blocked >/dev/null

out=$(run1 show demo-task-1)
contains '4 isolated update: task 1 unaffected by task 2 move' "$out" 'done'
not_contains '4 isolated update: task 1 does not mention task 2' "$out" 'other-task-1'

out=$(run1 list)
contains '5 list: shows task 1' "$out" 'demo-task-1'
contains '5 list: shows task 2' "$out" 'other-task-1'

out=$(run1 list --project demo)
contains '5 list --project: shows filtered task' "$out" 'demo-task-1'
not_contains '5 list --project: excludes other project' "$out" 'other-task-1'

out=$(run1 list --state blocked)
contains '5 list --state: shows blocked task' "$out" 'other-task-1'
not_contains '5 list --state: excludes non-blocked task' "$out" 'demo-task-1'

out=$(run1 summary)
contains '6 summary: mentions demo project' "$out" 'demo'
contains '6 summary: mentions other project' "$out" 'other'
not_contains '6 summary: is narrow (omits manual note text)' "$out" 'manual note'

json=$(run1 summary --json)
if python3 -c '
import json, sys
o = json.loads(sys.argv[1])
assert o["projects"]["demo"]["done"] == 1, o
assert o["projects"]["other"]["blocked"] == 1, o
assert o["total"]["done"] == 1, o
' "$json"; then pass '6 summary --json: schema matches counts'; else fail '6 summary --json: schema matches counts'; fi

json=$(run1 show demo-task-1 --json)
if python3 -c '
import json, sys
o = json.loads(sys.argv[1])
assert o["id"] == "demo-task-1", o
assert o["state"] == "done", o
assert o["project"] == "demo", o
assert "note" in o, o
' "$json"; then pass '7 show --json: narrow single-task object'; else fail '7 show --json: narrow single-task object'; fi

json=$(run1 list --json)
if python3 -c '
import json, sys
o = json.loads(sys.argv[1])
ids = sorted(t["id"] for t in o)
assert ids == ["demo-task-1", "other-task-1"], ids
assert "note" not in o[0], o
' "$json"; then pass '7 list --json: array of tasks without note field'; else fail '7 list --json: array of tasks without note field'; fi

out=$(run1 render)
check '8 render: exit 0' $? 0
if [ -f "$HOME1/data/board/board.html" ]; then pass '8 render: board.html materialized'; else fail '8 render: board.html materialized'; fi
if [ -f "$HOME1/data/board/board-data.js" ]; then pass '8 render: board-data.js generated'; else fail '8 render: board-data.js generated'; fi
data=$(cat "$HOME1/data/board/board-data.js")
contains '8 render: board-data.js embeds task id' "$data" 'demo-task-1'
contains '8 render: board-data.js embeds task title' "$data" 'First task'
if python3 -c '
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"BOARD_DATA\s*=\s*(\{.*\});", text, re.S)
assert m, text[:200]
import json
data = json.loads(m.group(1))
ids = sorted(t["id"] for t in data["tasks"])
assert ids == ["demo-task-1", "other-task-1"], ids
' "$HOME1/data/board/board-data.js"; then pass '8 render: board-data.js is valid embedded JSON'; else fail '8 render: board-data.js is valid embedded JSON'; fi

if [ -f "$HOME1/data/board/events.jsonl" ]; then pass '9 events: events.jsonl exists'; else fail '9 events: events.jsonl exists'; fi
events=$(cat "$HOME1/data/board/events.jsonl")
contains '9 events: records add' "$events" '"event": "add"'
contains '9 events: records move' "$events" '"event": "move"'

# Stable IDs: adding two tasks with the same title never collide or reuse.
run1 add --project demo --title "First task" --id demo-task-1-dup 2>/dev/null
out=$(run1 show demo-task-1-dup)
contains '10 stable ids: distinct explicit id addressable independently' "$out" 'demo-task-1-dup'
out=$(run1 show demo-task-1)
contains '10 stable ids: original task id never regenerated' "$out" 'demo-task-1'

# IDs are deterministic and explicit: no random or time-derived generation.
out=$(run1 add --project demo --title "No id given" 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then pass '10 stable ids: add without --id fails nonzero'; else fail '10 stable ids: add without --id fails nonzero'; fi
contains '10 stable ids: missing --id error is explicit' "$out" '--id'

out=$(run1 add --project demo --title "Bad Id" --id "Not Valid!" 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then pass '10 stable ids: invalid id characters rejected'; else fail '10 stable ids: invalid id characters rejected'; fi

# =============================================================================
# Scenario 2: preserve unknown/unrelated fields on a narrow update.
# =============================================================================
HOME2="$TMP_ROOT/home2"
mkdir -p "$HOME2"
run2() { FM_HOME="$HOME2" FIRSTMATE_ROOT="$TMP_ROOT/no-such-firstmate" PATH="/usr/bin:/bin" "$BOARD" "$@"; }
run2 add --project p --title "Task A" --id task-a >/dev/null
run2 add --project p --title "Task B" --id task-b >/dev/null
# Simulate a forward-compatible field this version of fm-board does not know
# about, written directly into state.json as a future version or operator
# might.
python3 - "$HOME2/data/board/state.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["tasks"]["task-a"]["future_field"] = "keep-me"
with open(path, "w") as f:
    json.dump(data, f)
PY
run2 update task-a --agent new-agent >/dev/null
json=$(run2 show task-a --json)
if python3 -c '
import json, sys
o = json.loads(sys.argv[1])
assert o["agent"] == "new-agent", o
' "$json"; then pass '11 preserve unrelated: narrow update applies the given field'; else fail '11 preserve unrelated: narrow update applies the given field'; fi
if python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
assert data["tasks"]["task-a"].get("future_field") == "keep-me", data["tasks"]["task-a"]
' "$HOME2/data/board/state.json"; then pass '11 preserve unrelated: unknown field survives in storage'; else fail '11 preserve unrelated: unknown field survives in storage'; fi
json=$(run2 show task-b --json)
if python3 -c '
import json, sys
o = json.loads(sys.argv[1])
assert o["agent"] is None, o
assert o["title"] == "Task B", o
' "$json"; then pass '11 preserve unrelated: sibling task untouched by update'; else fail '11 preserve unrelated: sibling task untouched by update'; fi

# =============================================================================
# Scenario 3: concurrent writers do not lose an update (practical locking).
# =============================================================================
HOME3="$TMP_ROOT/home3"
mkdir -p "$HOME3"
run3() { FM_HOME="$HOME3" FIRSTMATE_ROOT="$TMP_ROOT/no-such-firstmate" PATH="/usr/bin:/bin" "$BOARD" "$@"; }
pids=()
for i in $(seq 1 8); do
  run3 add --project concurrent --title "Concurrent $i" --id "concurrent-$i" >/dev/null 2>&1 &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
json=$(run3 list --project concurrent --json)
count=$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1])))' "$json")
check '12 concurrency: all 8 concurrent adds are persisted' "$count" 8

# =============================================================================
# Scenario 4: `fm-board open` shells out to the resolved viewer without an
# LLM, using whatever fake terminal-browser / lavish-axi stub is on PATH, and
# never regenerates the static HTML content itself between renders.
# =============================================================================
HOME4="$TMP_ROOT/home4"
mkdir -p "$HOME4"
FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_BIN"
RECORD="$TMP_ROOT/open-calls.log"
cat > "$FAKE_BIN/terminal-browser" <<SH
#!/usr/bin/env bash
printf 'terminal-browser %s\n' "\$*" >> "$RECORD"
SH
cat > "$FAKE_BIN/lavish-axi" <<SH
#!/usr/bin/env bash
printf 'lavish-axi %s\n' "\$*" >> "$RECORD"
SH
chmod +x "$FAKE_BIN/terminal-browser" "$FAKE_BIN/lavish-axi"
run4() { FM_HOME="$HOME4" FIRSTMATE_ROOT="$TMP_ROOT/no-such-firstmate" PATH="$FAKE_BIN:/usr/bin:/bin" "$BOARD" "$@"; }
run4 add --project demo --title "Open me" --id open-task >/dev/null

rm -f "$RECORD"
run4 open >/dev/null
contains '13 open: default path invokes terminal-browser' "$(cat "$RECORD")" 'terminal-browser open'
contains '13 open: default path targets board.html' "$(cat "$RECORD")" "$HOME4/data/board/board.html"

rm -f "$RECORD"
run4 open --lavish >/dev/null
contains '13 open --lavish: invokes lavish-axi' "$(cat "$RECORD")" 'lavish-axi'
contains '13 open --lavish: targets board.html' "$(cat "$RECORD")" "$HOME4/data/board/board.html"

html_before=$(cat "$HOME4/data/board/board.html")
run4 render >/dev/null
html_after=$(cat "$HOME4/data/board/board.html")
check '14 render: static HTML content is identical across re-renders' "$html_before" "$html_after"
# Lavish reloads its artifact whenever board.html changes on disk, which drops
# the page's open detail view; an unchanged template must not be rewritten.
html_stamp=$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$HOME4/data/board/board.html")
sleep 0.05
run4 render >/dev/null
check '14 render: unchanged board.html is not rewritten' "$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$HOME4/data/board/board.html")" "$html_stamp"

# =============================================================================
# Scenario 5: `fm board` dispatches through bin/fm into bin/fm-board open.
# =============================================================================
HOME5="$TMP_ROOT/home5"
FIRSTMATE5="$TMP_ROOT/firstmate5"
mkdir -p "$HOME5" "$FIRSTMATE5"
cat > "$FIRSTMATE5/AGENTS.md" <<'EOF'
stub
EOF
run5() { HOME="$TMP_ROOT/userhome5" FM_HOME="$HOME5" FIRSTMATE_ROOT="$FIRSTMATE5" PATH="$FAKE_BIN:/usr/bin:/bin" "$FM" "$@"; }
mkdir -p "$TMP_ROOT/userhome5"
rm -f "$RECORD"
out=$(run5 board 2>&1)
contains '15 fm board: dispatches into terminal-browser open' "$(cat "$RECORD" 2>/dev/null)" 'terminal-browser open'

# =============================================================================
# Scenario 6: reconcile projects Firstmate's own authoritative state onto the
# board, deterministically and without touching unrelated/manual tasks.
# =============================================================================
HOME6="$TMP_ROOT/home6"
FIRSTMATE6="$TMP_ROOT/firstmate6"
mkdir -p "$HOME6/state" "$FIRSTMATE6/bin"
CREW_CALLS="$TMP_ROOT/crew-calls.log"

cat > "$FIRSTMATE6/bin/fm-crew-state.sh" <<SH
#!/usr/bin/env bash
id="\$1"
printf '%s\n' "\$id" >> "$CREW_CALLS"
case "\$id" in
  a-working-1) printf 'state: working . source: stub . harness busy\n' ;;
  a-parked-1)  printf 'state: parked . source: stub . needs-decision\n' ;;
  a-done-1)    printf 'state: done . source: stub . checks green\n' ;;
  a-blocked-1) printf 'state: blocked . source: stub . daemon socket refused\n' ;;
  *)           printf 'state: unknown . source: stub . backend target gone\n' ;;
esac
SH
chmod +x "$FIRSTMATE6/bin/fm-crew-state.sh"

cat > "$HOME6/state/home-summary.json" <<'JSON'
{
  "schema": "fm-secondmate-home-summary.v1",
  "queued": [
    {"id": "q-todo-1", "repo": "proj-a", "title": "Queued task", "kind": "ship", "since": "2026-09-10"},
    {"id": "q-blocked-1", "repo": "proj-a", "title": "Live captain call", "kind": "scout", "since": "2026-09-11", "hold_kind": "captain", "hold_bucket": "live", "captain_actionable": true, "hold_reason": "need confirmation"},
    {"id": "q-deferred-1", "repo": "proj-a", "title": "Captain deferred until a date", "kind": "scout", "since": "2026-09-11", "hold_kind": "captain", "hold_bucket": "dated", "hold_until": "2099-01-01", "captain_actionable": false, "hold_reason": "revisit later"},
    {"id": "q-future-1", "repo": "proj-a", "title": "Kept in Todo", "kind": "ship", "since": "2026-09-11", "hold_kind": "future", "captain_actionable": false, "hold_reason": "not a priority"},
    {"id": "q-dep-1", "repo": "proj-a", "title": "Waits on another task", "kind": "ship", "since": "2026-09-12", "blocked_by": "q-todo-1", "blocked_by_ids": ["q-todo-1"], "unresolved_blocker_ids": ["q-todo-1"], "captain_actionable": false}
  ],
  "active_children": [
    {"id": "a-working-1", "repo": "proj-b", "kind": "ship", "name": "Working task", "doing": "harness busy"}
  ],
  "endpoints": [
    {"id": "a-working-1", "state": "working", "source": "pane"},
    {"id": "a-parked-1", "state": "parked", "source": "run-step"},
    {"id": "a-done-1", "state": "done", "source": "status-log"},
    {"id": "a-blocked-1", "state": "blocked", "source": "status-log"},
    {"id": "a-gone-1", "state": "unknown", "source": "none"}
  ],
  "holds": [
    {"id": "a-parked-1", "reason": "needs captain decision"}
  ],
  "decisions_open": [
    {"id": "a-parked-1", "key": "a-parked-1", "verb": "needs-decision", "summary": "needs captain decision", "source": "status"}
  ],
  "landed": [
    {"id": "l-done-1", "repo": "proj-c", "title": "Landed task", "kind": "ship", "completion": {"verb": "done", "date": "2026-09-15"}}
  ]
}
JSON

# Endpoint rows carry no repo/name; the archive lookup supplies identity.
cat > "$FIRSTMATE6/bin/fm-tasks-axi.sh" <<'SH'
#!/usr/bin/env bash
printf 'task:\n  id: %s\n  title: Endpoint task %s\n  repo: proj-b\n' "$2" "$2"
SH
chmod +x "$FIRSTMATE6/bin/fm-tasks-axi.sh"

for id in a-working-1 a-parked-1 a-done-1; do
  cat > "$HOME6/state/$id.meta" <<META
harness=omp
model=anthropic/claude-sonnet-5
effort=medium
META
done

run6() { FM_HOME="$HOME6" FIRSTMATE_ROOT="$FIRSTMATE6" PATH="/usr/bin:/bin" "$BOARD" "$@"; }
run6 add --project proj-a --title "Manual verification task" --id manual-task-1 >/dev/null
run6 move manual-task-1 in_progress >/dev/null

summary_json=$(run6 summary --json)
if python3 -c '
import json, sys
o = json.loads(sys.argv[1])
p = o["projects"]
assert p["proj-a"]["todo"] == 3, p["proj-a"]
assert p["proj-a"]["blocked"] == 1, p["proj-a"]
assert p["proj-a"]["waiting_review"] == 1, p["proj-a"]
assert p["proj-a"]["in_progress"] == 1, p["proj-a"]
assert p["proj-b"]["in_progress"] == 1, p["proj-b"]
assert p["proj-b"]["blocked"] == 2, p["proj-b"]
assert p["proj-b"]["waiting_review"] == 2, p["proj-b"]
assert p["proj-c"]["done"] == 1, p["proj-c"]
' "$summary_json"; then pass '16 reconcile: lifecycle mapping matches counts per project'; else fail '16 reconcile: lifecycle mapping matches counts per project'; fi

json=$(run6 show q-todo-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="todo", o' "$json"; then
  pass '16 reconcile: queued task (no hold) is todo'
else
  fail '16 reconcile: queued task (no hold) is todo'
fi

json=$(run6 show q-blocked-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="waiting_review", o; assert o["captain_review"] is True, o; assert o["hold_reason"]=="need confirmation", o' "$json"; then
  pass '16 reconcile: live captain call (captain_actionable hold) waits on the captain'
else
  fail '16 reconcile: live captain call (captain_actionable hold) waits on the captain'
fi

json=$(run6 show q-deferred-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="todo", o; assert o["captain_review"] is False, o; assert o["hold_reason"].startswith("until 2099-01-01"), o' "$json"; then
  pass '16 reconcile: dated captain deferral stays todo, never blocked'
else
  fail '16 reconcile: dated captain deferral stays todo, never blocked'
fi

json=$(run6 show q-future-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="todo", o; assert o["hold_reason"]=="not a priority", o' "$json"; then
  pass '16 reconcile: non-captain (future) hold stays todo'
else
  fail '16 reconcile: non-captain (future) hold stays todo'
fi

json=$(run6 show q-dep-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="blocked", o; assert "q-todo-1" in o["hold_reason"], o' "$json"; then
  pass '16 reconcile: unresolved dependency blocker is blocked and names the blocker'
else
  fail '16 reconcile: unresolved dependency blocker is blocked and names the blocker'
fi

json=$(run6 show a-working-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="in_progress", o; assert "claude-sonnet-5" in (o["agent"] or ""), o' "$json"; then
  pass '16 reconcile: crew-state working maps to in_progress with agent label'
else
  fail '16 reconcile: crew-state working maps to in_progress with agent label'
fi

json=$(run6 show a-parked-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="waiting_review", o; assert o["captain_review"] is True, o; assert o["hold_reason"]=="needs captain decision", o' "$json"; then
  pass '16 reconcile: crew-state parked (decision/gate pending) is waiting_review, not blocked'
else
  fail '16 reconcile: crew-state parked (decision/gate pending) is waiting_review, not blocked'
fi

json=$(run6 show a-blocked-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="blocked", o; assert o["project"]=="proj-b", o; assert "socket refused" in o["running"], o' "$json"; then
  pass '16 reconcile: crew-state blocked is blocked with its detail'
else
  fail '16 reconcile: crew-state blocked is blocked with its detail'
fi

json=$(run6 show a-gone-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="blocked", o; assert "target gone" in o["running"], o' "$json"; then
  pass '16 reconcile: unknown/gone child is never shown as in_progress'
else
  fail '16 reconcile: unknown/gone child is never shown as in_progress'
fi

json=$(run6 show a-done-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="waiting_review", o; assert o["captain_review"] is True, o' "$json"; then
  pass '16 reconcile: crew-state done maps to waiting_review, never board done'
else
  fail '16 reconcile: crew-state done maps to waiting_review, never board done'
fi

json=$(run6 show l-done-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="done", o' "$json"; then
  pass '16 reconcile: landed task is board done'
else
  fail '16 reconcile: landed task is board done'
fi

json=$(run6 show manual-task-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="in_progress", o; assert o["project"]=="proj-a", o' "$json"; then
  pass '16 reconcile: manual task untouched by reconcile'
else
  fail '16 reconcile: manual task untouched by reconcile'
fi

run6 update a-working-1 --note "captain asked for X" >/dev/null
run6 summary >/dev/null
json=$(run6 show a-working-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["note"]=="captain asked for X", o' "$json"; then
  pass '16 reconcile: manual note survives a later reconcile'
else
  fail '16 reconcile: manual note survives a later reconcile'
fi

rm -f "$CREW_CALLS"
run6 show a-working-1 >/dev/null
calls=$(sort -u "$CREW_CALLS" 2>/dev/null | tr '\n' ' ')
check '17 narrow reconcile: show only calls crew-state for the requested id' "$calls" 'a-working-1 '

# =============================================================================
# Scenario 7: landed entries carry no `repo` (the real
# fm-secondmate-home-summary.v1 shape) - a completed task must still group
# under its actual project, never under "".
# =============================================================================
HOME7="$TMP_ROOT/home7"
FIRSTMATE7="$TMP_ROOT/firstmate7"
mkdir -p "$HOME7/state" "$FIRSTMATE7/bin"
TASKS_AXI_CALLS="$TMP_ROOT/tasks-axi-calls.log"

cat > "$FIRSTMATE7/bin/fm-crew-state.sh" <<SH
#!/usr/bin/env bash
printf 'state: working . source: stub . busy\n'
SH
chmod +x "$FIRSTMATE7/bin/fm-crew-state.sh"

# Archived-task lookup fallback, consulted only when the board has no
# previously known project for a landed id.
cat > "$FIRSTMATE7/bin/fm-tasks-axi.sh" <<SH
#!/usr/bin/env bash
printf '%s %s\n' "\$1" "\$2" >> "$TASKS_AXI_CALLS"
case "\$2" in
  archived-fresh-1) printf 'id: archived-fresh-1\nrepo: proj-fresh\nstatus: landed\n' ;;
  *) printf 'id: %s\nstatus: landed\n' "\$2" ;;
esac
SH
chmod +x "$FIRSTMATE7/bin/fm-tasks-axi.sh"

run7() { FM_HOME="$HOME7" FIRSTMATE_ROOT="$FIRSTMATE7" PATH="/usr/bin:/bin" "$BOARD" "$@"; }

# Version A: cross-1 is active, with a repo, proving the normal projected path.
cat > "$HOME7/state/home-summary.json" <<'JSON'
{
  "schema": "fm-secondmate-home-summary.v1",
  "queued": [],
  "active_children": [
    {"id": "cross-1", "repo": "proj-cross", "kind": "ship", "name": "Cross task"}
  ],
  "endpoints": [],
  "holds": [],
  "decisions_open": [],
  "landed": []
}
JSON
run7 show cross-1 --json >/dev/null

# Version B: cross-1 lands (real shape: landed entries carry no `repo`), and a
# never-before-seen archived task appears only in `landed`, also without
# `repo` - the "fresh board" case.
cat > "$HOME7/state/home-summary.json" <<'JSON'
{
  "schema": "fm-secondmate-home-summary.v1",
  "queued": [],
  "active_children": [],
  "endpoints": [],
  "holds": [],
  "decisions_open": [],
  "landed": [
    {"id": "cross-1", "title": "Cross task", "kind": "ship", "completion": {"date": "2026-09-16"}},
    {"id": "archived-fresh-1", "title": "Archived fresh task", "kind": "ship", "completion": {"date": "2026-09-16"}}
  ]
}
JSON
rm -f "$TASKS_AXI_CALLS"
run7 show cross-1 --json >/dev/null
run7 show archived-fresh-1 --json >/dev/null

json=$(run7 show cross-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="done", o; assert o["project"]=="proj-cross", o' "$json"; then
  pass '18 landed without repo: previously projected task keeps its known project'
else
  fail '18 landed without repo: previously projected task keeps its known project'
fi

json=$(run7 show archived-fresh-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="done", o; assert o["project"]=="proj-fresh", o' "$json"; then
  pass '18 landed without repo: fresh board resolves archived project via fm-tasks-axi.sh'
else
  fail '18 landed without repo: fresh board resolves archived project via fm-tasks-axi.sh'
fi

calls=$(sort -u "$TASKS_AXI_CALLS" 2>/dev/null | tr '\n' ' ')
check '18 landed without repo: archive lookup skipped when project already known' "$calls" 'show archived-fresh-1 '

# =============================================================================
# Scenario 8: endpoint entries carry no `repo`/`name` (the real
# fm-secondmate-home-summary.v1 shape for review-ready work, e.g.
# `uw-m0-foundation`) - such a task must still group under its actual
# project with its actual title, never "Unassigned"/the bare id, and an
# already-corrupted board record (project="", title=id from a prior buggy
# reconcile) must self-heal on the next ordinary reconciliation.
# =============================================================================
HOME8="$TMP_ROOT/home8"
FIRSTMATE8="$TMP_ROOT/firstmate8"
mkdir -p "$HOME8/state" "$FIRSTMATE8/bin"
TASKS_AXI_CALLS8="$TMP_ROOT/tasks-axi-calls8.log"

cat > "$FIRSTMATE8/bin/fm-crew-state.sh" <<SH
#!/usr/bin/env bash
printf 'state: done . source: stub . checks green\n'
SH
chmod +x "$FIRSTMATE8/bin/fm-crew-state.sh"

cat > "$FIRSTMATE8/bin/fm-tasks-axi.sh" <<SH
#!/usr/bin/env bash
printf '%s %s\n' "\$1" "\$2" >> "$TASKS_AXI_CALLS8"
case "\$2" in
  uw-m0-foundation) printf 'id: uw-m0-foundation\nrepo: universal-wishlist\ntitle: M0-01 monorepo foundation and product contracts\nstatus: waiting_review\n' ;;
  *) printf 'id: %s\nstatus: waiting_review\n' "\$2" ;;
esac
SH
chmod +x "$FIRSTMATE8/bin/fm-tasks-axi.sh"

cat > "$HOME8/state/home-summary.json" <<'JSON'
{
  "schema": "fm-secondmate-home-summary.v1",
  "queued": [],
  "active_children": [],
  "endpoints": [
    {"id": "uw-m0-foundation", "state": "done"}
  ],
  "holds": [],
  "decisions_open": [],
  "landed": []
}
JSON

run8() { FM_HOME="$HOME8" FIRSTMATE_ROOT="$FIRSTMATE8" PATH="/usr/bin:/bin" "$BOARD" "$@"; }

# Fresh board, never seen this id before: reconcile must recover both
# project and title via the single fm-tasks-axi.sh lookup.
json=$(run8 show uw-m0-foundation --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["project"]=="universal-wishlist", o; assert o["title"]=="M0-01 monorepo foundation and product contracts", o' "$json"; then
  pass '19 endpoint without repo/name: fresh board resolves durable project and title'
else
  fail '19 endpoint without repo/name: fresh board resolves durable project and title'
fi

summary_json=$(run8 summary --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["projects"]["universal-wishlist"]["waiting_review"]==1, o' "$summary_json"; then
  pass '19 endpoint without repo/name: task groups under its real project, not Unassigned'
else
  fail '19 endpoint without repo/name: task groups under its real project, not Unassigned'
fi

calls8=$(wc -l < "$TASKS_AXI_CALLS8" | tr -d ' ')
check '19 endpoint without repo/name: at most one archive lookup per reconcile' "$calls8" '1'

# Simulate the exact `uw-m0-foundation` corruption (a prior buggy reconcile
# already stomped project to "" and title to the bare id) and prove an
# ordinary reconciliation repairs it with no manual state edit.
python3 - "$HOME8/data/board/state.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["tasks"]["uw-m0-foundation"]["project"] = ""
data["tasks"]["uw-m0-foundation"]["title"] = "uw-m0-foundation"
with open(path, "w") as f:
    json.dump(data, f)
PY
json=$(run8 show uw-m0-foundation --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["project"]=="universal-wishlist", o; assert o["title"]=="M0-01 monorepo foundation and product contracts", o' "$json"; then
  pass '20 endpoint without repo/name: corrupted card self-heals via ordinary reconcile'
else
  fail '20 endpoint without repo/name: corrupted card self-heals via ordinary reconcile'
fi

# =============================================================================
# Scenario 9: a browser refresh only re-reads board-data.js, so while the viewer
# `fm-board open` launched is still running, the on-disk projection must follow
# Firstmate's state; the refresh loop must end as soon as the viewer exits.
# The stub viewer blocks like the real interactive path (terminal-browser open
# takes over the pane until the browser closes).
# =============================================================================
HOME9="$TMP_ROOT/home9"
mkdir -p "$HOME9/state"
BLOCK_BIN="$TMP_ROOT/blocking-bin"
mkdir -p "$BLOCK_BIN"
VIEWER_GATE="$TMP_ROOT/close-viewer"
cat > "$BLOCK_BIN/terminal-browser" <<SH
#!/usr/bin/env bash
while [ ! -e "$VIEWER_GATE" ]; do sleep 0.1; done
SH
chmod +x "$BLOCK_BIN/terminal-browser"
summary9() {
  cat > "$HOME9/state/home-summary.json" <<JSON
{"queued": [{"id": "live-1", "repo": "demo", "title": "$1", "kind": "ship", "since": "2026-09-20"}],
 "active_children": [], "endpoints": [], "holds": [], "decisions_open": [], "landed": []}
JSON
}
file_contains_within() { # <file> <needle> <tenths-of-a-second>
  local i=0
  while [ "$i" -lt "$3" ]; do
    case $(cat "$1" 2>/dev/null) in *"$2"*) return 0 ;; esac
    sleep 0.1; i=$((i + 1))
  done
  return 1
}
summary9 "Title before"
FM_HOME="$HOME9" FIRSTMATE_ROOT="$TMP_ROOT/no-such-firstmate" PATH="$BLOCK_BIN:/usr/bin:/bin" "$BOARD" open >/dev/null 2>&1 &
OPEN_PID=$!
if file_contains_within "$HOME9/data/board/board-data.js" "Title before" 50; then pass '21 open: projection rendered before the viewer starts'; else fail '21 open: projection rendered before the viewer starts'; fi
summary9 "Title after"
if file_contains_within "$HOME9/data/board/board-data.js" "Title after" 50; then pass '21 open: projection follows Firstmate state while the viewer is open'; else fail '21 open: projection follows Firstmate state while the viewer is open'; fi
touch "$VIEWER_GATE"
i=0
while kill -0 "$OPEN_PID" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
if kill -0 "$OPEN_PID" 2>/dev/null; then fail '21 open: exits promptly once the viewer closes'; kill "$OPEN_PID" 2>/dev/null; else pass '21 open: exits promptly once the viewer closes'; fi
wait "$OPEN_PID" 2>/dev/null

# =============================================================================
# Scenario 10: absent Firstmate rows retire from a complete summary. Partial
# summaries alone cannot prove deletion; Scenario 13 adds an authoritative
# inventory read to distinguish deleted rows from omitted-but-existing work.
# =============================================================================
HOME10="$TMP_ROOT/home10"; FIRSTMATE10="$TMP_ROOT/firstmate10"
mkdir -p "$HOME10/state" "$FIRSTMATE10/bin"
printf '#!/usr/bin/env bash\nprintf "state: working . source: stub . harness busy\\n"\n' > "$FIRSTMATE10/bin/fm-crew-state.sh"
printf '#!/usr/bin/env bash\nprintf "error: not found\\ncode: NOT_FOUND\\n"; exit 1\n' > "$FIRSTMATE10/bin/fm-tasks-axi.sh"
chmod +x "$FIRSTMATE10/bin/"*
run10() { FM_HOME="$HOME10" FIRSTMATE_ROOT="$FIRSTMATE10" PATH="/usr/bin:/bin" "$BOARD" "$@"; }
summary10() {  # <valid> <omitted-json> <active-id-or-empty> <landed-id-or-empty>
  local active='' landed=''
  [ -n "$3" ] && active="{\"id\": \"$3\", \"repo\": \"proj-r\", \"kind\": \"ship\", \"name\": \"Active task\"}"
  [ -n "$4" ] && landed="{\"id\": \"$4\", \"title\": \"Landed task\", \"kind\": \"ship\", \"completion\": {\"verb\": \"merged\", \"date\": \"2026-09-20\"}}"
  cat > "$HOME10/state/home-summary.json" <<JSON
{"schema": "fm-secondmate-home-summary.v1", "valid": $1, "omitted": $2,
 "queued": [{"id": "q-live-1", "repo": "proj-r", "title": "Queued live", "kind": "ship", "since": "2026-09-20"}],
 "active_children": [$active], "endpoints": [$active], "holds": [], "decisions_open": [], "landed": [$landed]}
JSON
}
state_of10() { run10 list --json | python3 -c 'import json,sys; ts={t["id"]:t for t in json.load(sys.stdin)}; t=ts.get(sys.argv[1]); print(t["state"] if t else "absent")' "$1"; }

# v1: a-1 active, l-1 landed; manual m-1 in progress.
summary10 true '[]' a-1 l-1
run10 add --project proj-r --title "Manual row" --id m-1 >/dev/null; run10 move m-1 in_progress >/dev/null
run10 list >/dev/null
check '22 retire: v1 projects a-1 in_progress' "$(state_of10 a-1)" in_progress
check '22 retire: v1 projects l-1 done' "$(state_of10 l-1)" done

# v2: a-1 finished, landed, and was pruned from the backlog before any board
# command ran; l-1 aged out of the landed window. Both vanish from every
# surface of a valid, untruncated ledger (the real home shape after tasks-axi
# prune / landed-window aging).
summary10 true '[]' '' ''
run10 list >/dev/null
check '22 retire: id absent from a complete valid ledger is retired' "$(state_of10 a-1)" absent
check '22 retire: aged-out landed row is retired' "$(state_of10 l-1)" absent
check '22 retire: manual row never retired' "$(state_of10 m-1)" in_progress
check '22 retire: still-present row kept' "$(state_of10 q-live-1)" todo
if run10 show a-1 >/dev/null 2>&1; then fail '22 retire: show of a retired id fails nonzero'; else pass '22 retire: show of a retired id fails nonzero'; fi
if grep -q '"event": "retire"' "$HOME10/data/board/events.jsonl"; then pass '22 retire: retirement recorded in events.jsonl'; else fail '22 retire: retirement recorded in events.jsonl'; fi

# Partial/unknown publications without an authoritative inventory cannot retire.
summary10 true '[]' a-1 ''; run10 list >/dev/null
summary10 false '[]' '' ''; run10 list >/dev/null
check '23 guard: invalid ledger with no invalidity kind retires nothing' "$(state_of10 a-1)" in_progress
summary10 true '[{"surface": "landed", "count": 3}]' '' ''; run10 list >/dev/null
check '23 guard: truncated ledger without authoritative inventory retires nothing' "$(state_of10 a-1)" in_progress
python3 - "$HOME10/state/home-summary.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.pop('valid')
d['omitted'] = []
json.dump(d, open(p, 'w'))
PY
run10 list >/dev/null
check '23 guard: ledger without a valid flag retires nothing' "$(state_of10 a-1)" in_progress

# narrow reconcile (show) retires only the id it was asked about, leaving
# other stale ids for the next full reconcile.
summary10 true '[]' '' ''
summary10 true '[]' a-2 ''; run10 show a-2 >/dev/null
summary10 true '[]' '' ''
if run10 show a-1 >/dev/null 2>&1; then fail '24 narrow: show retires the requested stale id'; else pass '24 narrow: show retires the requested stale id'; fi
found_a2=$(python3 -c 'import json; print("a-2" in json.load(open("'"$HOME10"'/data/board/state.json"))["tasks"])')
check '24 narrow: show leaves other stale ids for the full reconcile' "$found_a2" True

# =============================================================================
# Scenario 11: the live-board regression. A local-only task that finished and
# awaits captain approval stays in-flight with a terminal child state, so the
# real producer publishes valid:false / terminal_in_flight for days while every
# surface is still complete. That must not freeze stale cards: ids absent from
# every surface are retired, the invalidity's own ids are protected, and a
# surface-hiding invalidity (unstructured_current) still retires nothing.
# =============================================================================
ledger10() {  # <valid> <invalidity-kind-or-empty> <invalidity-ids-csv> <active-ids-csv>
  python3 - "$HOME10/state/home-summary.json" "$@" <<'PY'
import json, sys
path, valid, kind, inv_ids, active = sys.argv[1:6]
ids = lambda csv: [i for i in csv.split(",") if i]
children = [{"id": i, "repo": "proj-r", "kind": "ship", "name": "Task " + i} for i in ids(active)]
json.dump({"schema": "fm-secondmate-home-summary.v1", "valid": valid == "true",
           "invalidity": {"kind": kind or None, "ids": ids(inv_ids)}, "omitted": [],
           "queued": [], "active_children": children,
           "endpoints": [{"id": c["id"], "state": "working"} for c in children],
           "holds": [], "decisions_open": [], "landed": []}, open(path, "w"))
PY
}
ledger10 true '' '' s-1,o-1,u-1,done-wait-1; run10 list >/dev/null
ledger10 false terminal_in_flight done-wait-1 done-wait-1,o-1,u-1; run10 list >/dev/null
check '25 terminal_in_flight: stale id absent from every surface is retired' "$(state_of10 s-1)" absent
check '25 terminal_in_flight: the finished-awaiting-approval task stays' "$(state_of10 done-wait-1)" in_progress
ledger10 false orphan_in_flight o-1 done-wait-1,u-1; run10 list >/dev/null
check '25 orphan_in_flight: the orphaned in-flight id is protected' "$(state_of10 o-1)" in_progress
ledger10 false unstructured_current '' done-wait-1; run10 list >/dev/null
check '25 unstructured_current: surface-hiding invalidity retires nothing' "$(state_of10 u-1)" in_progress

# An unchanged projection is not rewritten: a re-render loop neither grows
# events.jsonl nor bumps updated_at, so `updated` shows the last transition.
ledger10 true '' '' done-wait-1; run10 list >/dev/null
before_events=$(wc -l < "$HOME10/data/board/events.jsonl")
before_ts=$(run10 show done-wait-1 --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["updated_at"])')
sleep 1
run10 list >/dev/null; run10 render >/dev/null
check '26 idempotent: unchanged ledger appends no event' "$(wc -l < "$HOME10/data/board/events.jsonl")" "$before_events"
check '26 idempotent: unchanged ledger keeps updated_at' "$(run10 show done-wait-1 --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["updated_at"])')" "$before_ts"

# =============================================================================
# Scenario 12: the rendered projection carries each task's own details for the
# page's detail view: one full authoritative backlog lookup per FirstMate task
# (decoded body/hold/dependency/link text, `-`/`none` sentinels become empty
# strings), plus its open decision and landed PR/report context. A task with
# no backlog record (pruned, or a manual row) has `backlog: null` - missing,
# never an empty record. Raw worker .meta/.status content never reaches the
# page, and details follow a backlog edit while the viewer is open.
# =============================================================================
HOME12="$TMP_ROOT/home12"; FIRSTMATE12="$TMP_ROOT/firstmate12"
mkdir -p "$HOME12/state" "$HOME12/data" "$FIRSTMATE12/bin"
TASKS_AXI_CALLS12="$TMP_ROOT/tasks-axi-calls12.log"
printf '#!/usr/bin/env bash\nprintf "state: working . source: stub . harness busy\\n"\n' > "$FIRSTMATE12/bin/fm-crew-state.sh"
printf 'Initial body\n' > "$HOME12/data/backlog.md"
cat > "$FIRSTMATE12/bin/fm-tasks-axi.sh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TASKS_AXI_CALLS12"
case "\$1 \$2" in
  "show d-queued-1") cat <<'OUT'
task:
  id: d-queued-1
  title: Detailed queued task
  state: queued
  blocked: yes
  blocked_by: d-landed-1
  held: yes
  hold_reason: "Waiting on \"captain\" call:\nline two"
  hold_kind: captain
  hold_until: "-"
  kind: ship
  repo: proj-d
  priority: "-"
  created: 2026-09-20
  closed: "-"
  deps: none
  links: "report:data/d-queued-1/report.md"
  body: "First line <b>not html</b>\n\nSecond paragraph"
OUT
  ;;
  "show d-active-1") printf 'task:\n  id: d-active-1\n  title: Active task\n  repo: proj-d\n  deps: d-queued-1\n  body: "%s"\n' "\$(cat "\$FM_HOME/data/backlog.md")" ;;
  *) printf 'error: "Task not found in this backlog"\ncode: NOT_FOUND\n'; exit 1 ;;
esac
SH
chmod +x "$FIRSTMATE12/bin/"*
cat > "$HOME12/state/home-summary.json" <<'JSON'
{"valid": true, "omitted": [],
 "queued": [{"id": "d-queued-1", "repo": "proj-d", "title": "Detailed queued task", "kind": "ship", "since": "2026-09-20", "hold_kind": "captain", "captain_actionable": true, "hold_reason": "Waiting on captain"},
            {"id": "d-active-1", "repo": "proj-d", "title": "Active task", "kind": "ship", "since": "2026-09-21"}],
 "active_children": [], "endpoints": [{"id": "d-active-1", "state": "parked"}],
 "holds": [], "decisions_open": [{"id": "d-active-1", "verb": "needs-decision", "summary": "approve the commit", "reason": "verified locally"}],
 "landed": [{"id": "d-landed-1", "repo": "proj-d", "title": "Landed task", "kind": "ship", "pr_url": "https://example.test/pr/1", "report_path": "data/d-landed-1/report.md", "local_note": null, "completion": {"verb": "merged", "date": "2026-09-22"}}]}
JSON
printf 'harness=omp\nmodel=anthropic/claude-opus-5-5\nworktree=/private/worktree/d-active-1\n' > "$HOME12/state/d-active-1.meta"
printf 'working [at=1]: private status line d-active-1\n' > "$HOME12/state/d-active-1.status"
run12() { FM_HOME="$HOME12" FIRSTMATE_ROOT="$FIRSTMATE12" PATH="/usr/bin:/bin" "$BOARD" "$@"; }
run12 add --project proj-d --title "Manual row" --id d-manual-1 --note "manual note text" >/dev/null
run12 render >/dev/null
if python3 - "$HOME12/data/board/board-data.js" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
tasks = {t["id"]: t for t in json.loads(text[text.index("{"):text.rindex("}") + 1])["tasks"]}
q = tasks["d-queued-1"]["details"]["backlog"]
assert q["body"] == "First line <b>not html</b>\n\nSecond paragraph", q
assert q["hold_reason"] == 'Waiting on "captain" call:\nline two', q
assert q["blocked_by"] == "d-landed-1" and q["links"] == "report:data/d-queued-1/report.md", q
assert q["deps"] == "" and q["hold_until"] == "" and q["priority"] == "", q
a = tasks["d-active-1"]["details"]
assert a["backlog"]["body"] == "Initial body" and a["backlog"]["deps"] == "d-queued-1", a
assert a["decision"] == {"verb": "needs-decision", "summary": "approve the commit", "reason": "verified locally"}, a
assert a["landed"] is None, a
l = tasks["d-landed-1"]["details"]
assert l["backlog"] is None, l
assert l["landed"]["pr_url"] == "https://example.test/pr/1" and l["landed"]["report_path"] == "data/d-landed-1/report.md", l
assert l["landed"]["completion"] == {"verb": "merged", "date": "2026-09-22"}, l
assert tasks["d-manual-1"]["details"]["backlog"] is None, tasks["d-manual-1"]
assert tasks["d-manual-1"]["note"] == "manual note text", tasks["d-manual-1"]
PY
then pass '27 details: backlog record decoded, empty vs missing kept distinct, decision/landed context attached'; else fail '27 details: backlog record decoded, empty vs missing kept distinct, decision/landed context attached'; fi
data12=$(cat "$HOME12/data/board/board-data.js")
not_contains '27 details: raw .meta content never reaches the page' "$data12" '/private/worktree/d-active-1'
not_contains '27 details: raw .status content never reaches the page' "$data12" 'private status line'
not_contains '27 details: manual rows are never looked up in the backlog' "$(cat "$TASKS_AXI_CALLS12")" 'd-manual-1'

VIEWER_GATE12="$TMP_ROOT/close-viewer12"
BLOCK_BIN12="$TMP_ROOT/blocking-bin12"; mkdir -p "$BLOCK_BIN12"
printf '#!/usr/bin/env bash\nwhile [ ! -e "%s" ]; do sleep 0.1; done\n' "$VIEWER_GATE12" > "$BLOCK_BIN12/terminal-browser"
chmod +x "$BLOCK_BIN12/terminal-browser"
FM_HOME="$HOME12" FIRSTMATE_ROOT="$FIRSTMATE12" PATH="$BLOCK_BIN12:/usr/bin:/bin" "$BOARD" open >/dev/null 2>&1 &
OPEN_PID12=$!
file_contains_within "$HOME12/data/board/board-data.js" "Initial body" 50 >/dev/null
sleep 1.2
printf 'Edited body\n' > "$HOME12/data/backlog.md"
if file_contains_within "$HOME12/data/board/board-data.js" "Edited body" 50; then pass '28 details: a backlog edit reaches the open board'; else fail '28 details: a backlog edit reaches the open board'; fi
touch "$VIEWER_GATE12"
wait "$OPEN_PID12" 2>/dev/null

# =============================================================================
# Scenario 13: truncation is not deletion, but must not retain genuinely removed
# rows forever. The official snapshot's contribution-input mode publishes the
# complete local backlog + metadata inventory without observing workers.
# Breaks caught: treating omission as absence; ignoring authoritative absence;
# accepting an unavailable/partial inventory; losing narrow-show or idempotence.
# =============================================================================
HOME13="$TMP_ROOT/home13"; FIRSTMATE13="$TMP_ROOT/firstmate13"
mkdir -p "$HOME13/state" "$FIRSTMATE13/bin"
cat > "$FIRSTMATE13/bin/fm-fleet-snapshot.sh" <<'SH'
#!/usr/bin/env bash
[ "$#" = 1 ] && [ "$1" = --contribution-input ] || exit 64
cat "$FM_HOME/inventory.json"
[ ! -e "$FM_HOME/inventory-failed" ]
SH
chmod +x "$FIRSTMATE13/bin/fm-fleet-snapshot.sh"
run13() { FM_HOME="$HOME13" FIRSTMATE_ROOT="$FIRSTMATE13" PATH="/usr/bin:/bin" "$BOARD" "$@"; }
seed13() {
  cat > "$HOME13/state/home-summary.json" <<'JSON'
{"valid":true,"omitted":[],"queued":[
 {"id":"removed-list","repo":"proj-r","title":"Removed from backlog"},
 {"id":"removed-show","repo":"proj-r","title":"Removed requested row"},
 {"id":"kept-queued","repo":"proj-q","title":"Omitted queued task"},
 {"id":"kept-held","repo":"proj-h","title":"Omitted captain hold","hold_kind":"captain","hold_reason":"captain decision pending","captain_actionable":true},
 {"id":"kept-live","repo":"proj-l","title":"Omitted live task"},
 {"id":"protected","repo":"proj-p","title":"Inventory mismatch"}
],"endpoints":[],"active_children":[],"landed":[],"holds":[],"decisions_open":[]}
JSON
  # These cards predate the inventory below: seed them through the
  # summary-only path, as an older reconcile would have.
  touch "$HOME13/inventory-failed"; run13 list >/dev/null; rm -f "$HOME13/inventory-failed"
}
partial13() {
  cat > "$HOME13/state/home-summary.json" <<'JSON'
{"valid":false,"invalidity":{"kind":"orphan_in_flight","ids":["protected"]},
 "omitted":[{"surface":"queued","count":83},{"surface":"endpoints","count":63},{"surface":"decisions_open","count":1}],
 "queued":[],"endpoints":[{"id":"seen-active","repo":"proj-a","name":"Active task","state":"working"}],
 "active_children":[],"landed":[],"holds":[],"decisions_open":[]}
JSON
}
# The official parser's record shape: every structured row carries its
# normalized current_role and hold fields alongside identity.
inventory13='{"backlog":{"present":true,"records":[
 {"structured":true,"id":"kept-queued","state":"queued","current_role":"queued","title":"Omitted queued task","repo":"proj-q","kind":null,"since":null,
  "hold_kind":null,"hold_reason":null,"hold_until":null,"hold_bucket":null,"captain_actionable":false,"blocked_by_ids":[],"unresolved_blocker_ids":[],"blocked_reason":null},
 {"structured":true,"id":"kept-held","state":"in_flight","current_role":"held","title":"Omitted captain hold","repo":"proj-h","kind":null,"since":null,
  "hold_kind":"captain","hold_reason":"captain decision pending","hold_until":null,"hold_bucket":"live","captain_actionable":true,"blocked_by_ids":[],"unresolved_blocker_ids":[],"blocked_reason":null}
]},"tasks":[{"id":"kept-live","kind":"ship"}]}'
printf '%s\n' "$inventory13" > "$HOME13/inventory.json"
seed13
run13 add --project manual --title "Manual row" --id kept-manual --note "keep this" >/dev/null
cp "$HOME13/data/board/state.json" "$HOME13/before.json"
partial13
out=$(run13 show removed-show --json 2>&1); rc=$?
check '29 truncated show: authoritative deletion returns missing' "$rc" 1
if python3 - "$HOME13/data/board/state.json" <<'PY'
import json, sys
tasks = json.load(open(sys.argv[1]))["tasks"]
assert "removed-show" not in tasks, tasks
assert "removed-list" in tasks, tasks
PY
then pass '29 truncated show: only requested deleted row retires'; else fail '29 truncated show: only requested deleted row retires'; fi
json=$(run13 list --json)
if python3 - "$json" "$HOME13/before.json" "$HOME13/data/board/state.json" "$HOME13/data/board/events.jsonl" <<'PY'
import json, sys
listed = {t["id"]: t for t in json.loads(sys.argv[1])}
assert set(listed) == {"kept-queued","kept-held","kept-live","protected","seen-active","kept-manual"}, listed
assert listed["seen-active"]["state"] == "in_progress", listed
before, after = [json.load(open(p))["tasks"] for p in sys.argv[2:4]]
for tid in ("kept-queued", "kept-held", "kept-live", "protected", "kept-manual"):
    assert after[tid] == before[tid], (tid, before[tid], after[tid])
events = [json.loads(line) for line in open(sys.argv[4])]
assert [e["ids"] for e in events if e["event"] == "retire"] == [["removed-show"], ["removed-list"]], events
PY
then pass '29 truncated list: deletes only absent rows; preserves omitted/manual/protected identity and records events'; else fail '29 truncated list: deletes only absent rows; preserves omitted/manual/protected identity and records events'; fi
cp "$HOME13/data/board/state.json" "$HOME13/after.json"
cp "$HOME13/data/board/events.jsonl" "$HOME13/events-before.jsonl"
run13 list >/dev/null
run13 show kept-held >/dev/null
if cmp -s "$HOME13/after.json" "$HOME13/data/board/state.json" && cmp -s "$HOME13/events-before.jsonl" "$HOME13/data/board/events.jsonl"; then
  pass '29 truncated idempotence: unchanged state and events remain byte-identical'
else fail '29 truncated idempotence: unchanged state and events remain byte-identical'; fi

# Unknown, malformed, missing, unstructured, or failed authoritative reads
# cannot prove absence. Each starts from the same genuinely stale card.
for bad in 'not json' '{}' 'null' \
  '{"backlog":{"present":false,"records":[]},"tasks":[]}' \
  '{"backlog":{"present":true},"tasks":[]}' \
  '{"backlog":{"present":true,"records":[]} }' \
  '{"backlog":{"present":true,"records":[{"structured":false,"id":null}]},"tasks":[]}' \
  '{"backlog":{"present":true,"records":[{"structured":true}]},"tasks":[]}' \
  '{"backlog":{"present":true,"records":[]},"tasks":{}}' \
  '{"backlog":{"present":true,"records":[{"structured":true,"id":"kept-queued","state":"unknown"}]},"tasks":[]}' \
  '{"backlog":{"present":true,"records":[],"omitted":[{"count":1}]},"tasks":[]}' \
  '{"backlog":{"present":true,"records":[]},"tasks":[{}]}'; do
  seed13; partial13
  printf '%s\n' "$bad" > "$HOME13/inventory.json"
  json=$(run13 show removed-list --json)
  if python3 -c 'import json,sys; assert json.loads(sys.argv[1])["id"]=="removed-list"' "$json"; then
    pass "30 incomplete inventory retains absent card: $bad"
  else fail "30 incomplete inventory retains absent card: $bad"; fi
done
printf '%s\n' "$inventory13" > "$HOME13/inventory.json"
touch "$HOME13/inventory-failed"
check '30 failed inventory retains absent card despite valid-looking stdout' "$(run13 show removed-list --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')" removed-list
rm "$HOME13/inventory-failed"
chmod -x "$FIRSTMATE13/bin/fm-fleet-snapshot.sh"
check '30 unreadable inventory command retains absent card' "$(run13 show removed-list --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')" removed-list
chmod +x "$FIRSTMATE13/bin/fm-fleet-snapshot.sh"
mv "$HOME13/inventory.json" "$HOME13/inventory-saved.json"
check '30 missing inventory retains absent card' "$(run13 show removed-list --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')" removed-list

# Even a usable inventory must not bypass surface-hiding/unknown summary guards.
cp "$HOME13/inventory-saved.json" "$HOME13/inventory.json"
for kind in missing_backlog unstructured_current unknown ''; do
  partial13
  python3 - "$HOME13/state/home-summary.json" "$kind" <<'PY'
import json, sys
path, kind = sys.argv[1:]
ledger = json.load(open(path))
ledger["invalidity"] = {"kind": kind, "ids": []}
json.dump(ledger, open(path, "w"))
PY
  check "31 unsafe summary retains absent card: $kind" "$(run13 show removed-list --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')" removed-list
done
printf 'not json\n' > "$HOME13/state/home-summary.json"
check '31 corrupt summary retains absent card' "$(run13 show removed-list --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')" removed-list
mv "$HOME13/state/home-summary.json" "$HOME13/summary-corrupt.json"
check '31 missing summary retains absent card' "$(run13 show removed-list --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')" removed-list

# =============================================================================
# Scenario 14: full sync from the complete authoritative backlog. The published
# summary bounds every surface, lists every task .meta as an endpoint whatever
# its backlog row says, and its `landed` selects Recently-Landed deliveries
# only. Breaks caught: rows outside a bounded surface never created or
# refreshed; a preserved child overriding a held or closed backlog row; a
# closed row that is not a landed delivery never reaching Completed; reopened
# work stuck in Completed; external holds shown as Todo; crew state consulted
# for preserved non-live children; losing narrow show, idempotence or manual
# rows. Inventory records use the official parser's
# (`fm-fleet-snapshot.sh --contribution-input`) real field shape.
# =============================================================================
HOME14="$TMP_ROOT/home14"; FIRSTMATE14="$TMP_ROOT/firstmate14"
CREW_CALLS14="$TMP_ROOT/crew-calls14.log"
mkdir -p "$HOME14/state" "$HOME14/data/board" "$FIRSTMATE14/bin"
cat > "$FIRSTMATE14/bin/fm-fleet-snapshot.sh" <<'SH'
#!/usr/bin/env bash
[ "$#" = 1 ] && [ "$1" = --contribution-input ] || exit 64
[ ! -e "$FM_HOME/inventory-failed" ] || exit 1
cat "$FM_HOME/inventory.json"
SH
cat > "$FIRSTMATE14/bin/fm-crew-state.sh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$CREW_CALLS14"
case "\$1" in
  w-working-1|held-working-1) printf 'state: working . source: pane . harness busy\n' ;;
  w-done-1) printf 'state: done . source: status-log . checks green\n' ;;
  w-orphan-1) printf 'state: unknown . source: none . no metadata for w-orphan-1\n' ;;
  *) printf 'state: unknown . source: none . backend target gone\n' ;;
esac
SH
chmod +x "$FIRSTMATE14/bin/"*
run14() { FM_HOME="$HOME14" FIRSTMATE_ROOT="$FIRSTMATE14" PATH="/usr/bin:/bin" "$BOARD" "$@"; }

# Truncated, invalid publication: endpoints are the alphabetical first metas
# (preserved children of held/closed rows), the actual workers are cut.
cat > "$HOME14/state/home-summary.json" <<'JSON'
{"schema":"fm-secondmate-home-summary.v1","valid":false,
 "invalidity":{"kind":"orphan_in_flight","ids":["w-orphan-1"]},
 "omitted":[{"surface":"queued","count":9},{"surface":"endpoints","count":3}],
 "active_children":[
  {"id":"held-working-1","kind":"ship","state":"working","repo":"proj-h","name":"Resumed held task","source":"pane","doing":"harness busy"},
  {"id":"w-working-1","kind":"ship","state":"working","repo":"proj-w","name":"Working worker","source":"pane","doing":"harness busy"}],
 "endpoints":[
  {"id":"done-preserved-1","state":"done","source":"status-log"},
  {"id":"held-captain-1","state":"unknown","source":"none"},
  {"id":"held-parked-1","state":"unknown","source":"none"}],
 "queued":[
  {"id":"held-parked-1","repo":"proj-h","title":"Delivered and parked","kind":"scout","since":"2026-10-20","hold_kind":"parked","hold_reason":"preserve evidence","captain_actionable":false,"blocked_by_ids":[],"unresolved_blocker_ids":[]}],
 "holds":[],"landed":[],
 "decisions_open":[{"id":"held-captain-1","key":"held-captain-1","verb":"captain-hold","summary":"Held for the captain","reason":"pick one","source":"backlog"}]}
JSON
python3 - "$HOME14/inventory.json" <<'PY'
import json, sys
def rec(tid, state, role, title, repo, **extra):
    r = {"structured": True, "id": tid, "state": state, "current_role": role, "title": title,
         "repo": repo, "kind": "ship", "since": "2026-10-01", "hold_kind": None,
         "hold_reason": None, "hold_until": None, "hold_bucket": None, "hold_age_days": None,
         "captain_actionable": False, "blocked_by_ids": [], "unresolved_blocker_ids": [],
         "blocked_reason": None, "requires_child_metadata": role == "worker",
         "report_path": None, "pr_url": None, "local_note": None,
         "completion": {"verb": None, "date": None}}
    r.update(extra)
    return r
records = [
    rec("q-new-1", "queued", "queued", "Never published queued task", "proj-q"),
    rec("q-call-1", "queued", "queued", "Live captain call", "proj-q", hold_kind="captain",
        hold_reason="pick a vendor", hold_bucket="live", captain_actionable=True),
    rec("q-aged-1", "queued", "queued", "Aged captain hold", "proj-q", hold_kind="captain",
        hold_reason="old question", hold_bucket="aged", hold_age_days=20),
    rec("q-external-1", "queued", "queued", "Waits on upstream", "proj-q", hold_kind="external",
        hold_reason="upstream fix pending"),
    rec("q-dep-1", "queued", "queued", "Needs q-new-1", "proj-q", blocked_by_ids=["q-new-1"],
        unresolved_blocker_ids=["q-new-1"]),
    rec("held-parked-1", "in_flight", "held", "Delivered and parked", "proj-h", kind="scout",
        since="2026-10-20", hold_kind="parked", hold_reason="preserve evidence"),
    rec("held-captain-1", "in_flight", "held", "Held for the captain", "proj-h", hold_kind="captain",
        hold_reason="pick one", hold_bucket="live", captain_actionable=True),
    rec("held-working-1", "in_flight", "held", "Resumed held task", "proj-h", hold_kind="future",
        hold_reason="later"),
    rec("w-working-1", "in_flight", "worker", "Working worker", "proj-w"),
    rec("w-done-1", "in_flight", "worker", "Finished worker", "proj-w"),
    rec("w-orphan-1", "in_flight", "worker", "Worker without metadata", "proj-w"),
    rec("done-preserved-1", "done", "done", "Accepted review", "proj-d", kind="scout",
        report_path="data/done-preserved-1/report.md", completion={"verb": "reported", "date": "2026-10-27"}),
    rec("done-ship-report-1", "done", "done", "Published with a report", "proj-d",
        report_path="data/done-ship-report-1/report.md", completion={"verb": "reported", "date": "2026-10-27"}),
    rec("done-captain-1", "done", "done", "Answered captain call", "proj-d", kind="captain",
        hold_kind="captain", hold_reason="answered", completion={"verb": "done", "date": "2026-10-26"}),
    rec("reopened-1", "queued", "queued", "Reopened task", "proj-r"),
]
metas = ["done-preserved-1", "held-captain-1", "held-parked-1", "held-working-1", "w-done-1", "w-working-1"]
json.dump({"backlog": {"path": "data/backlog.md", "present": True, "records": records},
           "tasks": [{"id": i, "kind": "ship", "pr": {"url": "", "head": ""}, "merge_authority": "attended"}
                     for i in metas]}, open(sys.argv[1], "w"))
PY
# Cards an older reconcile left behind: frozen outside the bounded window, a
# preserved child's state over a held/closed row, a reopened row still done.
seed14() {
  python3 - "$HOME14/data/board/state.json" <<'PY'
import json, sys
def card(tid, project, title, state, review=False, source="firstmate", note=None):
    return {"id": tid, "project": project, "title": title, "state": state, "agent": None,
            "kind": "ship", "source": source, "since": None, "running": None,
            "captain_review": review, "hold_reason": None, "note": note,
            "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z"}
cards = [card("q-aged-1", "proj-q", "Aged captain hold", "waiting_review", True),
         card("w-done-1", "proj-w", "Finished worker", "in_progress"),
         card("done-preserved-1", "proj-d", "Accepted review", "waiting_review", True),
         card("done-ship-report-1", "proj-d", "Published with a report", "todo"),
         card("reopened-1", "proj-r", "Reopened task", "done"),
         card("held-parked-1", "proj-h", "Delivered and parked", "blocked"),
         card("manual-14", "proj-m", "Manual row", "in_progress", source="manual", note="keep me")]
json.dump({"schema": "fm-board.v1", "tasks": {c["id"]: c for c in cards}}, open(sys.argv[1], "w"))
PY
}
seed14
rm -f "$CREW_CALLS14"
json=$(run14 list --json)
if python3 - "$json" <<'PY'
import json, sys
got = {t["id"]: (t["state"], t["captain_review"]) for t in json.loads(sys.argv[1])}
want = {
    "q-new-1": ("todo", False), "q-call-1": ("waiting_review", True), "q-aged-1": ("todo", False),
    "q-external-1": ("blocked", False), "q-dep-1": ("blocked", False),
    "held-parked-1": ("todo", False), "held-captain-1": ("waiting_review", True),
    "held-working-1": ("in_progress", False), "w-working-1": ("in_progress", False),
    "w-done-1": ("waiting_review", True), "w-orphan-1": ("blocked", False),
    "done-preserved-1": ("done", False), "done-ship-report-1": ("done", False),
    "done-captain-1": ("done", False), "reopened-1": ("todo", False),
    "manual-14": ("in_progress", False),
}
bad = {k: (got.get(k), v) for k, v in want.items() if got.get(k) != v}
assert not bad and set(got) == set(want), (bad, sorted(set(got) ^ set(want)))
PY
then pass '32 full sync: every backlog row takes the column its authoritative record and live child give it'
else fail '32 full sync: every backlog row takes the column its authoritative record and live child give it'; fi
json=$(run14 show q-new-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert (o["project"], o["title"], o["source"]) == ("proj-q", "Never published queued task", "firstmate"), o' "$json"; then
  pass '32 full sync: a row never published in a bounded surface carries its backlog identity'
else fail '32 full sync: a row never published in a bounded surface carries its backlog identity'; fi
json=$(run14 show manual-14 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert (o["state"], o["note"], o["source"]) == ("in_progress", "keep me", "manual"), o' "$json"; then
  pass '32 full sync: manual row untouched'
else fail '32 full sync: manual row untouched'; fi
check '32 full sync: crew state consulted only for live in-flight children' \
  "$(sort -u "$CREW_CALLS14" 2>/dev/null | tr '\n' ' ')" 'held-working-1 w-done-1 w-orphan-1 w-working-1 '

rm -f "$CREW_CALLS14"
run14 show w-done-1 >/dev/null
check '33 full sync narrow: show consults crew state for the requested id only' "$(sort -u "$CREW_CALLS14" 2>/dev/null | tr '\n' ' ')" 'w-done-1 '
cp "$HOME14/data/board/state.json" "$HOME14/after.json"
cp "$HOME14/data/board/events.jsonl" "$HOME14/events-after.jsonl"
run14 list >/dev/null
if cmp -s "$HOME14/after.json" "$HOME14/data/board/state.json" && cmp -s "$HOME14/events-after.jsonl" "$HOME14/data/board/events.jsonl"; then
  pass '33 full sync idempotence: unchanged inputs leave state and events byte-identical'
else fail '33 full sync idempotence: unchanged inputs leave state and events byte-identical'; fi

# Without a usable inventory the summary still names held rows in `queued`;
# a preserved child must not override that hold there either.
seed14
touch "$HOME14/inventory-failed"
check '34 summary only: a queued held row keeps its hold over a preserved dead child' \
  "$(run14 show held-parked-1 --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')" todo
rm -f "$HOME14/inventory-failed"

# A complete, valid summary need not list a closed non-delivery row; the
# inventory still has it, so it is neither retired nor recreated (which would
# drop the note an operator put on the card).
run14 list >/dev/null
run14 update done-ship-report-1 --note "operator note" >/dev/null
python3 - "$HOME14/state/home-summary.json" <<'PY'
import json, sys
path = sys.argv[1]
ledger = json.load(open(path))
ledger.update(valid=True, invalidity={"kind": None, "ids": []}, omitted=[])
json.dump(ledger, open(path, "w"))
PY
json=$(run14 show done-ship-report-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert (o["state"], o["note"]) == ("done", "operator note"), o' "$json"; then
  pass '35 complete summary: a row the inventory still has is not retired'
else fail '35 complete summary: a row the inventory still has is not retired'; fi

[ "$failed" -eq 0 ] || exit 1
