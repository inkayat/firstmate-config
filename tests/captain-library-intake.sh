#!/usr/bin/env bash
# captain-library-intake.sh - one real, isolated Captain intake scenario for
# firstmate/primary-policy.md's capability assessment (section 2) and section 5
# "Capability library": does a real Captain, given a natural request and only
# its normal standing instructions, decide which capabilities the task needs,
# read just those Library shelves, and build the worker contract itself?
#
# Real, not mocked, following tests/captain-review-scenarios.sh: the Captain is
# the real omp harness on the exact model and effort `bin/fm --print-command`
# resolves through the real startup chain, started in a scratch local clone of
# official FirstMate (remote removed, never fetched) with a lab FM_HOME minted
# by that clone's bin/fm-lab-home.sh, this checkout as FM_CONFIG_ROOT (the lab
# data/captain.md is seeded from firstmate/captain.md exactly as install.sh
# seeds it), and AGENT_LIBRARY_ROOT naming the Library checkout under test. The
# request names no capability, no Library command and no expected output; the
# only scenario constraint is to stop before dispatch. Deviations from an
# interactive Captain, all disclosed in the output: print mode with JSON event
# output, no persisted session, and no extensions (the FirstMate primary
# supervision extensions would otherwise start fleet watching in a session
# that never dispatches).
#
# Assertions are structural, never on wording: a brief exists with a justified
# Required capabilities block naming real Library routes; the Captain's own
# printed trace for it passes tests/routing-trace.sh check --brief (route rule,
# Library lines against the brief, budget, no FirstMate-only report); the
# Captain's tool calls ran the policy's category-first lookup and none of the
# Library's whole-catalog, discovery, launch or promotion commands; and nothing
# was dispatched. Which capabilities it declares is the Captain's own call.
#
# Opt-in and honesty contract: real model calls and wall-clock minutes, so it
# runs only with FM_LIVE_LIBRARY_INTAKE=1; otherwise SKIPPED, never PASS. A
# missing prerequisite reports BLOCKED with the exact missing piece. One Captain
# session, bounded by omp --max-time and an outer timeout. HOME stays real only
# for omp's existing login; every HERDR_*/FM_TASK_* variable is removed and
# Herdr is never used. Everything this script creates is removed on exit.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIRSTMATE_ROOT_REAL="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"
LIB_ROOT="${AGENT_LIBRARY_ROOT:-}"
MAX_TIME="${FM_LIBRARY_INTAKE_MAX_TIME:-600}"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; failed=1; }
blocked() { printf 'BLOCKED - %s\n\nCAPTAIN LIBRARY INTAKE BLOCKED\n' "$1"; exit 1; }

if [ "${FM_LIVE_LIBRARY_INTAKE:-0}" != 1 ]; then
  printf 'SKIP - live Captain capability intake - not opted in (set FM_LIVE_LIBRARY_INTAKE=1)\n\nCAPTAIN LIBRARY INTAKE SKIPPED (opt-in required)\n'
  exit 0
fi
for tool in omp git bun python3; do command -v "$tool" >/dev/null 2>&1 || blocked "$tool is required and is not on PATH"; done
[ -x "$FIRSTMATE_ROOT_REAL/bin/fm-lab-home.sh" ] || blocked "no official FirstMate checkout at $FIRSTMATE_ROOT_REAL; set FIRSTMATE_ROOT"
[ -n "$LIB_ROOT" ] && [ -f "$LIB_ROOT/library/bin/agent-library.ts" ] || blocked 'AGENT_LIBRARY_ROOT must name an agent-library checkout'
[ -d "$HOME/.omp" ] || blocked 'no omp credential store at $HOME/.omp; omp must be logged in'

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-library-intake.XXXXXX") || exit 1
TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)
LAB_TMUX_DIR=''
cleanup() {
  for pid in $(pgrep -f "$TMP_ROOT" 2>/dev/null); do kill -9 "$pid" 2>/dev/null || true; done
  if [ -n "$LAB_TMUX_DIR" ]; then
    TMUX_TMPDIR="$LAB_TMUX_DIR" tmux kill-server >/dev/null 2>&1 || true
    "$SCRATCH/bin/fm-lab-home.sh" teardown "$LAB" >/dev/null 2>&1 || true
  fi
  chmod -R u+w "$TMP_ROOT" 2>/dev/null || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
OUT="${FM_LIBRARY_INTAKE_OUT:-$TMP_ROOT/out}"
mkdir -p "$OUT"

SCRATCH="$TMP_ROOT/firstmate"
git clone --no-hardlinks -q "$FIRSTMATE_ROOT_REAL" "$SCRATCH" || blocked "could not clone $FIRSTMATE_ROOT_REAL locally"
git -C "$SCRATCH" remote remove origin 2>/dev/null || true
LAB="$TMP_ROOT/fm-home"
"$SCRATCH/bin/fm-lab-home.sh" create "$LAB" >/dev/null || blocked 'fm-lab-home.sh could not mint the lab home'
LAB_TMUX_DIR=$("$SCRATCH/bin/fm-lab-home.sh" tmux-dir "$LAB") || blocked 'fm-lab-home.sh could not mint the lab tmux directory'
# Herdr is never reachable from this lab: a PATH-first guard refuses and logs
# any attempt instead of letting it reach the operator's real Herdr server.
mkdir -p "$TMP_ROOT/guard-bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/herdr-attempts.txt"\necho "herdr is disabled in this lab" >&2\nexit 1\n' "$OUT" > "$TMP_ROOT/guard-bin/herdr"
chmod +x "$TMP_ROOT/guard-bin/herdr"
cp "$CONFIG_ROOT/firstmate/captain.md" "$LAB/data/captain.md"
ln -s "$CONFIG_ROOT/firstmate/crew-dispatch.json" "$LAB/config/crew-dispatch.json"
printf 'manual\n' > "$LAB/config/backlog-backend"
printf 'tmux\n' > "$LAB/config/backend"
proj="$LAB/projects/export-service"
mkdir -p "$proj/tests"
printf '# export-service\n\nRun `python3 -m unittest` from the repository root.\n' > "$proj/AGENTS.md"
cat > "$proj/export.py" <<'PY'
def export_csv(rows):
    lines = ["id,name,notes"]
    for r in rows:
        lines.append(f"{r['id']},{r['name']},{r['notes']}")
    return "\n".join(lines)


def import_csv(text):
    out = []
    for line in text.splitlines()[1:]:
        parts = line.split(",")
        if len(parts) != 3:
            continue
        out.append({"id": parts[0], "name": parts[1], "notes": parts[2]})
    return out
PY
cat > "$proj/tests/test_export.py" <<'PY'
import unittest

from export import export_csv


class ExportTest(unittest.TestCase):
    def test_header(self):
        self.assertEqual(export_csv([]), "id,name,notes")
PY
git -C "$proj" init -q && git -C "$proj" add -A && git -C "$proj" -c user.email=t@example.invalid -c user.name=t commit -qm init
printf -- '- export-service [local-only] - CSV export job (added 2026-10-04)\n' > "$LAB/data/projects.md"
printf 'FIRSTMATE_ROOT="%s"\nFM_CONFIG_ROOT="%s"\nFM_HOME="%s"\nFM_BACKEND="tmux"\nexport FIRSTMATE_ROOT FM_CONFIG_ROOT FM_HOME FM_BACKEND\n' \
  "$SCRATCH" "$CONFIG_ROOT" "$LAB" > "$TMP_ROOT/env"

lib_fp() { (cd "$LIB_ROOT" && find . -type f -exec shasum -a 256 {} + | sort | shasum -a 256 | cut -d' ' -f1); }
LIB_FP_BEFORE=$(lib_fp)
SCRUB=(-u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_BIN_PATH
  -u FM_TASK_ID -u FM_TASK_INBOX -u FM_OMP_HARNESS -u CLAUDECODE -u PI_CODING_AGENT)

# The exact Captain launch the real launcher resolves for this lab.
resolved=$(cd "$TMP_ROOT" && env "${SCRUB[@]}" PATH="$TMP_ROOT/guard-bin:$PATH" FM_CONFIG_ENV="$TMP_ROOT/env" "$CONFIG_ROOT/bin/fm" --print-command 2>&1)
field() { printf '%s\n' "$resolved" | sed -n "s/^$1=//p" | tail -1; }
MODEL=$(field SELECTED_MODEL) EFFORT=$(field SELECTED_EFFORT) CWD=$(field CAPTAIN_CWD)
[ "$(field CAPTAIN_HARNESS)" = omp ] && [ "$(field SELECTED_AVAILABILITY)" = AVAILABLE ] && [ "$CWD" = "$SCRATCH" ] ||
  blocked "bin/fm --print-command did not resolve an available OMP Captain in the lab: $(printf '%s' "$resolved" | tr '\n' ' ')"
printf 'captain: omp %s %s (resolved by bin/fm --print-command), cwd scratch FirstMate clone, lab FM_HOME, Library %s\n' "$MODEL" "$EFFORT" "$LIB_ROOT"

REQUEST='A user just asked: "In the export-service project, the CSV export drops rows whose notes contain commas. Fix it, get the change reviewed, and make sure an integration test exercises the real export end to end."

Handle this intake exactly as you normally would under your standing instructions, up to the point where the task brief is ready to dispatch. This is a lab dry run: stop there - do not run fm-spawn or any other launch, worktree or dispatch command and do not edit the project. Leave each brief you would dispatch at data/<task-id>/brief.md in this FirstMate home, and end your reply with the exact block you would print before delegating each one.'
printf '%s\n' "$REQUEST" > "$OUT/request.txt"
start=$(date +%s)
(cd "$CWD" && env "${SCRUB[@]}" FIRSTMATE_ROOT="$SCRATCH" FM_HOME="$LAB" FM_BACKEND=tmux FM_CONFIG_ROOT="$CONFIG_ROOT" \
  FM_FORK_ORIGIN_CWD="$TMP_ROOT" FM_FORK_ORIGIN_IS_PROJECT=false FM_OMP_HARNESS=omp FM_TIMEOUT_MECHANISM_OVERRIDE=bash \
  AGENT_LIBRARY_ROOT="$LIB_ROOT" DISABLE_AUTOUPDATER=1 PATH="$TMP_ROOT/guard-bin:$PATH" TMUX_TMPDIR="$LAB_TMUX_DIR" \
  timeout $((MAX_TIME + 60)) omp --model "$MODEL" --thinking "$EFFORT" -p --no-session --no-extensions --mode json \
  --max-time "$MAX_TIME" "$REQUEST") > "$OUT/captain-events.jsonl" 2> "$OUT/captain-stderr.txt" < /dev/null
rc=$?
printf 'captain session: exit %s after %ss\n' "$rc" "$(( $(date +%s) - start ))"

# The Captain's own tool calls (`toolCall` items: name + arguments, never tool
# results, which would echo the policy text back) and its assistant text, from
# the JSON event stream. Events repeat across updates, so both are de-duplicated.
python3 - "$OUT/captain-events.jsonl" "$OUT" <<'PY'
import json, sys
events, out = sys.argv[1], sys.argv[2]
calls, texts = {}, {}
def walk(o, role=None):
    if isinstance(o, dict):
        role = o.get("role", role)
        if o.get("type") == "toolCall" and isinstance(o.get("arguments"), dict):
            # Streamed updates repeat a call with growing arguments: keep the fullest.
            key, args = o.get("id") or json.dumps(o, sort_keys=True), json.dumps(o["arguments"], sort_keys=True)
            if len(args) >= len(calls.get(key, ("", ""))[1]):
                calls[key] = (o.get("name"), args)
        if o.get("type") == "text" and role == "assistant" and isinstance(o.get("text"), str):
            texts[o["text"]] = True
        for v in o.values():
            walk(v, role)
    elif isinstance(o, list):
        for v in o:
            walk(v, role)
for line in open(events, errors="replace"):
    try:
        walk(json.loads(line))
    except ValueError:
        pass
final = [t for t in texts if "Routing:" in t]
open(out + "/captain-final-text.txt", "w").write(max(final, key=len) if final else "")
open(out + "/captain-tool-calls.txt", "w").write("".join(("%s %s" % c).replace("\n", " ") + "\n" for c in calls.values()))
PY
printf 'captain tool calls: %s\n' "$(grep -c . "$OUT/captain-tool-calls.txt")"

# --- Assertions ------------------------------------------------------------------
meta=$(find "$LAB/state" -name '*.meta' 2>/dev/null | head -1)
if [ -z "$meta" ]; then pass 'nothing was dispatched (no task metadata in the lab home)'; else fail "a task was dispatched: $meta"; fi
briefs=$(find "$LAB/data" -name brief.md 2>/dev/null | sort)
printf '%s\n' "$briefs" > "$OUT/briefs.txt"
for b in $briefs; do cp "$b" "$OUT/brief-$(basename "$(dirname "$b")").md"; done
if [ -n "$briefs" ]; then pass "the Captain wrote $(printf '%s\n' "$briefs" | grep -c .) brief(s)"; else fail 'the Captain wrote no brief'; fi
tools=$(cat "$OUT/captain-tool-calls.txt" 2>/dev/null)
if printf '%s\n' "$tools" | grep -q 'primary-policy\.md'; then
  pass "the Captain read primary-policy.md itself ($(printf '%s\n' "$tools" | grep -c 'primary-policy\.md') tool call(s) naming it)"
else
  fail 'no Captain tool call names primary-policy.md'
fi
if printf '%s\n' "$tools" | grep -E -q 'agent-library\.ts[^ ]* (firstmate|category)'; then
  pass 'the Captain ran the policy'"'"'s category-first Library lookup itself'
else
  fail 'no Captain tool call ran agent-library firstmate/category'
fi
if printf '%s\n' "$tools" | grep -E -q 'agent-library\.ts[^ ]* (find|show|compare|sync|update|import|use|run|recipe|promote)( |\\|"|$)'; then
  fail "the Captain ran a whole-catalog, discovery, launch or promotion Library command: $(printf '%s\n' "$tools" | grep -E 'agent-library\.ts[^ ]* (find|show|compare|sync|update|import|use|run|recipe|promote)' | head -1 | cut -c1-300)"
else
  pass 'no whole-catalog, discovery, launch or promotion Library command ran'
fi
if printf '%s\n' "$tools" | grep -q 'fm-spawn'; then fail 'a Captain tool call invoked fm-spawn'; else pass 'no Captain tool call invoked fm-spawn'; fi

# Each brief with Required capabilities must name real routes, each with a reason,
# and be matched by one of the Captain's own printed blocks under check --brief.
python3 - "$OUT/captain-final-text.txt" "$OUT" <<'PY'
import re, sys
text, out = open(sys.argv[1]).read(), sys.argv[2]
blocks, cur = [], None
for line in text.splitlines():
    s = line.strip().strip("`")
    if s.startswith("Routing:"):
        cur = [s]; blocks.append(cur)
    elif cur is not None and re.match(r"^(Skills:|No skill:|Library:)", s):
        cur.append(s)
    elif cur is not None and s:
        cur = None
for i, b in enumerate(blocks):
    open("%s/trace-%d.txt" % (out, i), "w").write("\n".join(b) + "\n")
print(len(blocks))
PY
nblocks=0
for t in "$OUT"/trace-*.txt; do [ -f "$t" ] && nblocks=$((nblocks + 1)); done
declared=0
for b in $briefs; do
  caps=$(awk '/^Required capabilities:/ {f=1; next} f && /^[ \t]/ {print $1} f && !/^[ \t]/ {f=0}' "$b")
  [ -n "$caps" ] || continue
  declared=$((declared + 1))
  for cap in $caps; do
    if python3 -c 'import json,sys; sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1]))["routes"] else 1)' "$LIB_ROOT/library/registry.json" "$cap"; then
      pass "$(basename "$(dirname "$b")"): declared capability $cap is a real Library route"
    else
      fail "$(basename "$(dirname "$b")"): declared capability $cap is not a Library route"
    fi
  done
  skills=$(awk '/^(Required project skill|Selected shared worker skill)/ {getline; gsub(/^[ \t]+|[ \t]+$/, ""); printf "%s%s", sep, $0; sep=","}' "$b")
  matched=''
  for t in "$OUT"/trace-*.txt; do
    [ -f "$t" ] || continue
    axes=$(sed -n 's/^Routing: [^|]*| role [^|]*| \([^|]*\) | \([^|]*\) | \([^|]*\) |.*/\1 \2 \3/p' "$t" | head -1)
    # shellcheck disable=SC2086
    set -- $axes
    [ "$#" -eq 3 ] || continue
    if bash "$CONFIG_ROOT/tests/routing-trace.sh" check "$t" "$1" "$2" "$3" "${skills:-none}" --brief "$b" > "$t.check-$(basename "$(dirname "$b")")" 2>&1; then
      matched=$t
      break
    fi
  done
  if [ -n "$matched" ]; then
    pass "$(basename "$(dirname "$b")"): the Captain's own printed block passes check --brief against the brief ($(grep -c '^Library:' "$matched") Library line(s))"
  else
    fail "$(basename "$(dirname "$b")"): none of the Captain's $nblocks printed block(s) passes check --brief against this brief (see $OUT/trace-*.check-*)"
  fi
done
if [ "$declared" -gt 0 ]; then pass "the Captain declared required capabilities in $declared brief(s), with no capability named in the request"; else fail 'no brief declares required capabilities'; fi
if [ "$(lib_fp)" = "$LIB_FP_BEFORE" ]; then pass 'the Library checkout is unchanged'; else fail 'the Library checkout changed'; fi
herdr_attempts=0
[ ! -f "$OUT/herdr-attempts.txt" ] || herdr_attempts=$(grep -c . "$OUT/herdr-attempts.txt")
pass "herdr guard: $herdr_attempts herdr call(s) attempted and refused inside the lab"
printf 'evidence: %s\n' "$OUT"

printf '\nCAPTAIN LIBRARY INTAKE %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
