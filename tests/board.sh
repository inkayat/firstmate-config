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
  *)           printf 'state: unknown . source: stub . no data\n' ;;
esac
SH
chmod +x "$FIRSTMATE6/bin/fm-crew-state.sh"

cat > "$HOME6/state/home-summary.json" <<'JSON'
{
  "schema": "fm-secondmate-home-summary.v1",
  "queued": [
    {"id": "q-todo-1", "repo": "proj-a", "title": "Queued task", "kind": "ship", "since": "2026-09-10"},
    {"id": "q-blocked-1", "repo": "proj-a", "title": "Held queued task", "kind": "scout", "since": "2026-09-11", "hold_kind": "captain", "captain_actionable": true, "hold_reason": "need confirmation"}
  ],
  "active_children": [
    {"id": "a-working-1", "repo": "proj-b", "kind": "ship", "name": "Working task", "doing": "harness busy"},
    {"id": "a-parked-1", "repo": "proj-b", "kind": "ship", "name": "Parked task"},
    {"id": "a-done-1", "repo": "proj-b", "kind": "ship", "name": "Finished impl task"}
  ],
  "endpoints": [],
  "holds": [
    {"id": "a-parked-1", "reason": "needs captain decision", "hold_kind": "captain"}
  ],
  "decisions_open": [
    {"id": "a-parked-1", "hold_kind": "captain"}
  ],
  "landed": [
    {"id": "l-done-1", "repo": "proj-c", "title": "Landed task", "kind": "ship", "completion": {"verb": "done", "date": "2026-09-15"}}
  ]
}
JSON

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
assert p["proj-a"]["todo"] == 1, p["proj-a"]
assert p["proj-a"]["blocked"] == 1, p["proj-a"]
assert p["proj-a"]["in_progress"] == 1, p["proj-a"]
assert p["proj-b"]["in_progress"] == 1, p["proj-b"]
assert p["proj-b"]["blocked"] == 1, p["proj-b"]
assert p["proj-b"]["waiting_review"] == 1, p["proj-b"]
assert p["proj-c"]["done"] == 1, p["proj-c"]
' "$summary_json"; then pass '16 reconcile: lifecycle mapping matches counts per project'; else fail '16 reconcile: lifecycle mapping matches counts per project'; fi

json=$(run6 show q-todo-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="todo", o' "$json"; then
  pass '16 reconcile: queued task (no hold) is todo'
else
  fail '16 reconcile: queued task (no hold) is todo'
fi

json=$(run6 show q-blocked-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="blocked", o; assert o["hold_reason"]=="need confirmation", o' "$json"; then
  pass '16 reconcile: queued task with captain hold is blocked'
else
  fail '16 reconcile: queued task with captain hold is blocked'
fi

json=$(run6 show a-working-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="in_progress", o; assert "claude-sonnet-5" in (o["agent"] or ""), o' "$json"; then
  pass '16 reconcile: crew-state working maps to in_progress with agent label'
else
  fail '16 reconcile: crew-state working maps to in_progress with agent label'
fi

json=$(run6 show a-parked-1 --json)
if python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert o["state"]=="blocked", o; assert o["captain_review"] is True, o' "$json"; then
  pass '16 reconcile: crew-state parked maps to blocked and flags captain review'
else
  fail '16 reconcile: crew-state parked maps to blocked and flags captain review'
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

[ "$failed" -eq 0 ] || exit 1
