#!/usr/bin/env bash
# captain-live.sh - opt-in LIVE proof that a real model playing the Firstmate CAPTAIN, given THIS
# configuration's firstmate/captain.md + firstmate/primary-policy.md and the OFFICIAL Firstmate
# AGENTS.md, resolves the workflow with `bin/fm-workflow select` BEFORE it launches the first worker
# (primary policy section 8, "Forcing"), starts it with `bin/fm-workflow next`, hands the step's role
# handoff and spec to the worker, and obeys the closed list of exceptions (trivial-chore,
# question-or-diagnosis, captain-none) and the docs-only carve-out. Every scenario is judged by a
# deterministic OUTSIDE check on the stub invocation log, the workflow state files and the Captain's
# transcript, never by the Captain grading itself.
#
# WHAT THIS PROVES: given this policy + captain.md + the official AGENTS.md as context, in a sandbox
# FM home, a real Captain model (omp, a stated model) classifies a human task, runs select before the
# first fm-spawn, starts the engine, briefs the first step with the engine's spec, prints the derived
# Workflow trace line, launches no second step before a result is recorded, and takes the documented
# exceptions. WHAT IT DOES NOT PROVE: the full production fleet (a fleet supervisor, a wake daemon, a
# human in the loop, real workers, the real fm-spawn/treehouse/tmux/no-mistakes - those are stubs that
# only record), nor that a worker applies its role (tests/roles-live.sh and tests/roles-contract-live.sh
# cover that), nor behavior of other models. Worker launching is a recording stub: no worker model
# is ever started, no worker result ever arrives in the Captain's turn.
#
# Usage:
#   tests/captain-live.sh                      offline self-test (a fake omp + canned compliant/skipping
#                                              Captains judged by every scenario's real judge); live SKIPs
#   tests/captain-live.sh selftest [scenario]  only the offline self-test
#   FM_CAPTAIN_LIVE=1 tests/captain-live.sh [scenario...]   run the live scenarios (default: all)
#   FM_CAPTAIN_LIVE=1 FM_CAPTAIN_LIVE_CONTROL=1 tests/captain-live.sh [scenario...]
#                                              the NEGATIVE CONTROL: the same task with the standing rule
#                                              removed from the Captain's context; informational (the
#                                              rate at which select / next still run is reported, never
#                                              asserted)
#
# Environment (live): the Captain uses the operator's existing omp login in place; no credential is
# exported, copied or logged. Without a logged-in omp the live run SKIPs, never PASSes.
#   FM_CAPTAIN_LIVE=1                required opt-in
#   FM_CAPTAIN_LIVE_MODEL            default anthropic/claude-sonnet-5-5
#   FM_CAPTAIN_LIVE_THINKING         default medium
#   FM_CAPTAIN_LIVE_REPEAT           runs per scenario (default 1; use 3 or more for stability evidence)
#   FM_CAPTAIN_LIVE_BUDGET           optional total USD cap (a running tally is kept)
#   FM_CAPTAIN_LIVE_RUN_CAP          optional per-run USD cap passed to omp --max-cost
#   FM_CAPTAIN_LIVE_TIMEOUT          seconds per run (default 900)
#   FM_CAPTAIN_LIVE_AGENTS           the official Firstmate AGENTS.md (default $FIRSTMATE_ROOT/AGENTS.md, else
#                                    ~/Developer/tools/firstmate/AGENTS.md, else
#                                    ~/.firstmate/projects/firstmate/AGENTS.md); it is only COPIED
#   FM_CAPTAIN_LIVE_CONTROL=1        run the negative control instead of the real context
#   FM_CAPTAIN_LIVE_POLICY           what-if experiment only: a policy file used INSTEAD of firstmate/primary-policy.md
#                                    (to try a proposed wording before it is applied; results.md records it)
# Isolation: each run gets a throwaway FIRSTMATE_ROOT (cwd; AGENTS.md copy + recording stubs in bin/),
# FM_HOME (registry, fixture projects, data/) and FM_CONFIG_ROOT (a copy of roles/ workflows/ firstmate/
# with logging wrappers around the REAL bin/fm-workflow and bin/fm-role-handoff of this checkout), all
# under mktemp; a scrubbed environment (env -i), --no-skills --no-rules --no-context-files
# --no-extensions, and only the tools a Captain needs: read, grep, glob, bash (no edit, no write; a
# brief is filled through bash). The stubs log to a directory outside the Captain's cwd. TMPDIR is a
# private directory per run and the prompt's harness note says so: a Captain writes its scratch files
# (the spec it pastes into a brief) there, so several invocations of this suite can run at the same time.
# A command that names a FIXED /tmp path anyway is listed in the run's results.md row ("SHARED /tmp") and
# in shared-tmp.txt: two overlapping runs that both used one are not trusted and are re-run alone.
# Artifacts (git-ignored): tests/live-artifacts/<stamp>/<scenario>-rN/ - prompt, transcript, calls,
# events.jsonl (the ordered stub + engine invocations), the sandbox home, grade.txt; results.md on top.
#
# Scenario file contract (tests/live-captain/<name>.sh, sourced in a subshell):
#   SCN_PROJECT=<fixture project>          the project the human message is about
#   SCN_CONTROL=1                          also run in the negative control (a workflow scenario)
#   SCN_BAD="v1 v2"                        canned skipping/violating variants every one of which must be rejected
#   scn_prompt                             prints the human message
#   scn_judge                              the OUTSIDE judge: prints "ok - ..." / "FAIL - ..." rows (helpers below)
#   scn_canned <good|variant>              offline stand-in Captain: drives the sandbox with c_run / c_say
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$CONFIG_ROOT/tests/captain-live.sh"
W="$CONFIG_ROOT/bin/fm-workflow"
HANDOFF="$CONFIG_ROOT/bin/fm-role-handoff"
CASES_DIR="${FM_CAPTAIN_CASES_DIR:-$CONFIG_ROOT/tests/live-captain}"
ART_ROOT="$CONFIG_ROOT/tests/live-artifacts"
MODEL="${FM_CAPTAIN_LIVE_MODEL:-anthropic/claude-sonnet-5-5}"
THINKING="${FM_CAPTAIN_LIVE_THINKING:-medium}"
REPEAT="${FM_CAPTAIN_LIVE_REPEAT:-1}"
BUDGET="${FM_CAPTAIN_LIVE_BUDGET:-}"
RUN_CAP="${FM_CAPTAIN_LIVE_RUN_CAP:-}"
TIMEOUT="${FM_CAPTAIN_LIVE_TIMEOUT:-900}"
CONTROL="${FM_CAPTAIN_LIVE_CONTROL:-0}"
OMP_BIN="${FM_CAPTAIN_LIVE_OMP:-omp}"
COST_ARGS=()
[ -z "$RUN_CAP" ] || COST_ARGS=(--max-cost "$RUN_CAP")
EXTRA_ENV=()

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
skip() { printf 'SKIP - %s\n' "$1"; }

SPENT=0
spent_add() { SPENT=$(python3 -c 'import sys; print("%.6f" % (float(sys.argv[1]) + float(sys.argv[2])))' "$SPENT" "$1"); }
over_budget() { [ -n "$BUDGET" ] && python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)' "$SPENT" "$BUDGET"; }

find_agents_md() {
  local c
  for c in "${FM_CAPTAIN_LIVE_AGENTS:-}" "${FIRSTMATE_ROOT:-/nonexistent}/AGENTS.md" "$HOME/Developer/tools/firstmate/AGENTS.md" "$HOME/.firstmate/projects/firstmate/AGENTS.md"; do
    [ -n "$c" ] && [ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# ==================================================================================================
# 1. The sandbox: FIRSTMATE_ROOT (cwd) with the official AGENTS.md and recording stubs, FM_HOME with a
#    registry and fixture projects, FM_CONFIG_ROOT with the real engine behind logging wrappers.
# ==================================================================================================

# strip_policy <in> <out>: the negative-control policy - no standing rule, no section 8, no paragraph that
# names bin/fm-workflow or the forced workflow, no Workflow trace line. (Incidental mentions of the word
# "workflow" in sections 3-7 that instruct nothing stay; the control report counts what is left.)
strip_policy() {
  awk 'BEGIN { RS = ""; ORS = "\n\n" }
    /^## 8\. Workflows/ { exit }
    /A task running a workflow \(section 8\) adds one line/ { i = index($0, "- A task running a workflow"); print substr($0, 1, i - 2); next }
    /Standing rule|fm-workflow|forced workflow|Workflow: <workflow>|are a workflow, not one worker/ { next }
    { print }' "$1" > "$2"
}
# strip_captain <in> <out>: captain.md without the workflow paragraph (the standing request for the gates).
strip_captain() {
  awk '/Every non-trivial/ && !skip { i = index($0, "Every non-trivial"); print substr($0, 1, i - 1); skip = 1; if ($0 ~ /saying so\./) skip = 0; next }
       skip && /saying so\./ { skip = 0; next }
       !skip { print }' "$1" > "$2"
}

# with_official_header <stub> <name>: put the official script's header comment (its documentation) on top of the stub
with_official_header() {
  local src hdr
  src=$(dirname "${AGENTS_SRC:-/nonexistent/x}")/bin/$2
  [ -f "$src" ] || return 0
  hdr=$(awk 'NR == 1 { next } /^#/ { print; next } { exit }' "$src")
  { printf '#!/usr/bin/env bash\n%s\n#\n# (this home runs a recording stand-in for the script documented above)\n' "$hdr"; sed 1d "$1"; } > "$1.new" && mv "$1.new" "$1" && chmod +x "$1"
}

stub_lib() { # the logging library the stubs and wrappers source
  cat <<'STUB'
# sourced by sandbox stubs. LOGD is the directory holding this file.
LOGD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# fm_log <tool> <rc> <output> <extra-json> [args...]: one JSON line per invocation, in completion order.
fm_log() {
  local tool=$1 rc=$2 out=$3 extra=$4 args='[]' a
  shift 4
  for a in "$@"; do args=$(jq -cn --argjson cur "$args" --arg a "$a" '$cur + [$a]'); done
  jq -cn --arg t "$(date +%s)" --arg tool "$tool" --argjson rc "$rc" --arg out "${out:0:4000}" --arg cwd "$PWD" --argjson extra "$extra" --argjson args "$args" \
    '{t: ($t|tonumber), tool: $tool, rc: $rc, out: $out, cwd: $cwd, extra: $extra, args: $args}' >> "$LOGD/events.jsonl"
}
# fm_help "$@": --help prints the stub's leading comment block (the official script's header when it was found)
fm_help() { case ${1:-} in --help|-h) sed -n '2,/^[^#]/{/^#/p;}' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac; }
STUB
}

stub_wrapper() { # <real-script> : a logging wrapper that execs nothing but runs the real one and records it
  cat <<STUB
#!/usr/bin/env bash
. "$SCR/log/lib.sh"
errf=\$(mktemp "\${TMPDIR:-/tmp}/fm-cap-wrap.XXXXXX")
out=\$("$1" "\$@" 2>"\$errf"); rc=\$?
err=\$(cat "\$errf"); rm -f "\$errf"
[ -z "\$out" ] || printf '%s\n' "\$out"
[ -z "\$err" ] || printf '%s\n' "\$err" >&2
all=\$out
[ -z "\$err" ] || all="\$out"\$'\n'"\$err"
fm_log "\$(basename "\$0")" "\$rc" "\$all" '{}' "\$@"
exit "\$rc"
STUB
}

stub_spawn() {
  cat <<'STUB'
#!/usr/bin/env bash
# Sandbox stand-in for fm-spawn.sh: validates like the real one where it matters (mode and yolo for a ship,
# the brief exists, no placeholder left), records the invocation and the brief, answers plausibly, starts nothing.
SB=$(cd "$(dirname "$0")/../.." && pwd)
. "$SB/log/lib.sh"
fm_help "$@"
orig=("$@")
id=${1:-}; proj=''
[ "$#" -gt 1 ] && case $2 in -*) ;; *) proj=$2 ;; esac
refuse() { printf 'fm-spawn.sh: %s\n' "$1" >&2; fm_log fm-spawn.sh "$2" "$1" '{}' "${orig[@]}"; exit "$2"; }
[ -n "$id" ] || refuse 'usage: fm-spawn.sh <task-id> <project-dir> --mode <no-mistakes|direct-PR|local-only> --yolo <on|off> [...] | --scout' 2
case $id in -*) refuse 'usage: fm-spawn.sh <task-id> <project-dir> ...' 2 ;; esac
shift; [ -z "$proj" ] || shift
scout=0; mode=''; yolo=''
while [ "$#" -gt 0 ]; do
  case $1 in
    --scout) scout=1 ;;
    --mode) mode=${2:-}; shift ;;
    --yolo) yolo=${2:-}; shift ;;
    --harness|--model|--effort|--dispatch-override|--branch-prefix|--base-branch|--account|--backend|--hermes-profile) shift ;;
  esac
  shift
done
[ -n "${FM_HOME:-}" ] || refuse 'FM_HOME is not set' 1
if [ "$scout" -eq 0 ]; then
  case $mode in no-mistakes|direct-PR|local-only) ;; *) refuse "--mode <no-mistakes|direct-PR|local-only> is REQUIRED for a ship spawn" 2 ;; esac
  case $yolo in on|off) ;; *) refuse '--yolo <on|off> is REQUIRED for a ship spawn' 2 ;; esac
fi
[ -d "$proj" ] || refuse "project directory not found: ${proj:-<none>}" 1
brief=$FM_HOME/data/$id/brief.md
[ -f "$brief" ] || refuse "no brief at $brief; run bin/fm-brief.sh first" 1
if grep -qF -e '{TASK}' -e '{FIRSTMATE_SPEC}' "$brief"; then refuse 'brief still has an unfilled {TASK} / {FIRSTMATE_SPEC} placeholder' 1; fi
mkdir -p "$SB/log/briefs" "$FM_HOME/state"
n=$(ls "$SB/log/briefs" 2>/dev/null | wc -l | tr -d ' ')
cp "$brief" "$SB/log/briefs/$((n + 1))-$id.md"
states=$(ls "$FM_HOME"/data/*/workflow.json 2>/dev/null | jq -R . | jq -sc .)
printf 'mode=%s\n' "$mode" > "$FM_HOME/state/$id.meta"
out=$(printf 'spawned %s\nworktree: %s/worktrees/%s\nendpoint: sandbox-stub:%s\n(sandbox stub: no worker is running and none will report in this session)' "$id" "$SB" "$id" "$id")
printf '%s\n' "$out"
fm_log fm-spawn.sh 0 "$out" "$(jq -cn --arg b "$SB/log/briefs/$((n + 1))-$id.md" --arg id "$id" --arg mode "$mode" --argjson scout "$scout" --argjson states "${states:-[]}" '{brief: $b, id: $id, mode: $mode, scout: ($scout == 1), workflow_states_at_spawn: $states}')" "${orig[@]}"
STUB
}

stub_brief() {
  cat <<'STUB'
#!/usr/bin/env bash
# Sandbox stand-in for fm-brief.sh: scaffolds data/<id>/brief.md with the two placeholders to fill.
SB=$(cd "$(dirname "$0")/../.." && pwd)
. "$SB/log/lib.sh"
fm_help "$@"
orig=("$@")
id=${1:-}; repo=${2:-}
refuse() { printf 'fm-brief.sh: %s\n' "$1" >&2; fm_log fm-brief.sh "$2" "$1" '{}' "${orig[@]}"; exit "$2"; }
[ -n "$id" ] && [ -n "$repo" ] || refuse 'usage: fm-brief.sh <task-id> <repo-name> --mode <no-mistakes|direct-PR|local-only> | --scout' 2
shift 2
scout=0; mode=''
while [ "$#" -gt 0 ]; do
  case $1 in --scout) scout=1 ;; --mode) mode=${2:-}; shift ;; --branch-prefix|--base-branch|--forge|--shape|--pr) shift ;; esac
  shift
done
if [ "$scout" -eq 0 ]; then
  case $mode in no-mistakes|direct-PR|local-only) ;; *) refuse '--mode <no-mistakes|direct-PR|local-only> is REQUIRED for a ship brief' 2 ;; esac
fi
d=$FM_HOME/data/$id
mkdir -p "$d"
{
  printf '# Task %s\n\nProject: %s\n' "$id" "$repo"
  if [ "$scout" -eq 1 ]; then printf 'Kind: scout (deliverable: %s/report.md; no branch, no push, no PR)\n' "$d"
  else printf 'Delivery contract: mode=%s\nBranch: fm/%s\nIsolation: stop if launched in the primary checkout.\n' "$mode" "$id"; fi
  printf '\n# Task\n\n## Captain'"'"'s intent\n\n{TASK}\n\n## Firstmate spec\n\n{FIRSTMATE_SPEC}\n'
} > "$d/brief.md"
out="brief scaffolded: $d/brief.md (fill {TASK} and {FIRSTMATE_SPEC} before fm-spawn.sh)"
printf '%s\n' "$out"
fm_log fm-brief.sh 0 "$out" '{}' "${orig[@]}"
STUB
}

stub_generic() {
  cat <<'STUB'
#!/usr/bin/env bash
# Sandbox stand-in for Firstmate fleet machinery that this test does not run.
SB=$(cd "$(dirname "$0")/../.." && pwd)
. "$SB/log/lib.sh"
fm_help "$@"
name=$(basename "$0")
case $name in
  fm-session-start.sh) out=$(cat "$SB/log/digest.txt") ;;
  fm-crew-state.sh) out='no crewmates in flight (sandbox)' ;;
  fm-dispatch-resolve.sh) out='off - no dispatch resolver is configured in this home (FM_DISPATCH_PROVIDER unset); route by the intake in AGENTS.md section 4 and config/crew-dispatch.json' ;;
  *) out="ok: $name (sandbox stub: this test runs no fleet machinery, nothing was changed)" ;;
esac
printf '%s\n' "$out"
fm_log "$name" 0 "$out" '{}' "$@"
STUB
}

stub_project_mode() {
  cat <<'STUB'
#!/usr/bin/env bash
# Sandbox stand-in for fm-project-mode.sh: reads data/projects.md and answers like the real script.
SB=$(cd "$(dirname "$0")/../.." && pwd)
. "$SB/log/lib.sh"
fm_help "$@"
orig=("$@")
want=''; proj=''
for a in "$@"; do case $a in --branch-prefix|--forge|--pr) want=$a ;; *) proj=$a ;; esac; done
line=$(grep -E "^- ${proj} " "$FM_HOME/data/projects.md" 2>/dev/null | head -1)
if [ -z "$line" ]; then out_mode=no-mistakes; yolo=off
else
  tok=$(printf '%s' "$line" | sed -n 's/^- [^ ]* \[\([^]]*\)\].*/\1/p')
  out_mode=${tok%%+*}; [ -n "$out_mode" ] || out_mode=no-mistakes
  yolo=off; case $tok in *+yolo*) yolo=on ;; esac
fi
case $want in
  --branch-prefix) out='fm/' ;;
  --forge) out=none ;;
  --pr) out=auto ;;
  *) out="$out_mode $yolo" ;;
esac
printf '%s\n' "$out"
fm_log fm-project-mode.sh 0 "$out" '{}' "${orig[@]}"
STUB
}

write_fixture_projects() { # <projects-dir>
  local p=$1 d
  d=$p/duration-cli; mkdir -p "$d/tests"
  cat > "$d/duration.py" <<'PY'
"""Parse human durations such as 1h30m into seconds."""
import re

__version__ = "0.3.1"

UNITS = {"s": 1, "m": 60, "h": 1}
_PART = re.compile(r"(\d+)([smh])")


def parse_duration(text):
    total = 0
    for amount, unit in _PART.findall(text):
        total += int(amount) * UNITS[unit]
    return total
PY
  cat > "$d/cli.py" <<'PY'
import sys

from duration import parse_duration

if __name__ == "__main__":
    print(parse_duration(sys.argv[1]))
PY
  cat > "$d/tests/test_duration.py" <<'PY'
from duration import parse_duration


def test_seconds_and_minutes():
    assert parse_duration("45s") == 45
    assert parse_duration("2m") == 120
PY
  printf '# duration-cli\n\nConvert durations to seconds.\n\n## Usage\n\n    python cli.py 1h30m   # prints 5400\n\nSupported units: s, m, h.\nThe unit table:\ns = seconds, m = minutes, h = hours.\n' > "$d/README.md"
  d=$p/notes-cli; mkdir -p "$d/tests"
  cat > "$d/notes.py" <<'PY'
"""A tiny notes store: add and list notes kept in notes.json."""
import json
import os

PATH = os.environ.get("NOTES_FILE", "notes.json")


def _load():
    if not os.path.exists(PATH):
        return []
    with open(PATH) as handle:
        return json.load(handle)


def add(text):
    notes = _load()
    notes.append({"id": len(notes) + 1, "text": text})
    with open(PATH, "w") as handle:
        json.dump(notes, handle)


def list_notes():
    return sorted(_load(), key=lambda n: n["id"], reverse=True)
PY
  printf 'from notes import add, list_notes\n\n\ndef test_add_then_list(tmp_path, monkeypatch):\n    monkeypatch.setattr("notes.PATH", str(tmp_path / "n.json"))\n    add("a")\n    assert list_notes()[0]["text"] == "a"\n' > "$d/tests/test_notes.py"
  cat > "$d/cli.py" <<'PY'
import sys

from notes import add, list_notes


def main(argv):
    if len(argv) >= 2 and argv[0] == "add":
        add(" ".join(argv[1:]))
    elif argv == ["list"]:
        for note in list_notes():
            print("%d. %s" % (note["id"], note["text"]))
    else:
        print("usage: cli.py add <text> | cli.py list")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PY
  printf '# notes-cli\n\nPlain notes from the command line: `python cli.py add <text>` adds a note, `python cli.py list` lists the notes.\n' > "$d/README.md"
  d=$p/taskbook; mkdir -p "$d"
  printf '"""A single-user task list kept in a local file."""\n\n_TASKS = []\n\n\ndef add(title):\n    _TASKS.append({"title": title, "done": False})\n\n\ndef done(index):\n    _TASKS[index]["done"] = True\n' > "$d/tasks.py"
  printf '# taskbook\n\nA small local task list: add tasks, mark them done.\n' > "$d/README.md"
  for d in duration-cli notes-cli taskbook; do
    ( cd "$p/$d" && git init -q . && git config user.email live@example.invalid && git config user.name live \
      && printf '__pycache__/\n' > .gitignore && git add -A && git commit -q -m fixture && git remote add origin "https://example.invalid/live/$d.git" ) || return 1
  done
}

# build_sandbox <control 0|1>: sets SCR FMROOT FMHOME CFG LOGD AGENTS_SRC. Everything lives under mktemp.
build_sandbox() {
  local control=$1 f
  SCR=$(mktemp -d "${TMPDIR:-/tmp}/fm-captain-live.XXXXXX") || return 1
  SCR=${SCR//\/\//\/}   # no doubled slash (a TMPDIR ending in /): every path the Captain sees and the judge compares is canonical
  FMROOT=$SCR/fmroot; FMHOME=$SCR/home; CFG=$SCR/config; LOGD=$SCR/log
  mkdir -p "$FMROOT/bin" "$FMHOME/data" "$FMHOME/state" "$FMHOME/config" "$FMHOME/projects" "$CFG/bin" "$LOGD/briefs" "$SCR/session" "$SCR/worktrees" "$SCR/tmp"
  stub_lib > "$LOGD/lib.sh"
  : > "$LOGD/events.jsonl"
  # the official AGENTS.md (a copy) and its skills (content only)
  AGENTS_SRC=$(find_agents_md) || AGENTS_SRC=''
  if [ -n "$AGENTS_SRC" ]; then
    cp "$AGENTS_SRC" "$FMROOT/AGENTS.md"
    [ ! -d "$(dirname "$AGENTS_SRC")/.agents/skills" ] || { mkdir -p "$FMROOT/.agents"; cp -R "$(dirname "$AGENTS_SRC")/.agents/skills" "$FMROOT/.agents/skills" 2>/dev/null; }
  fi
  # the configuration (a REAL copy, symlinks dereferenced: strip_policy writes into it and must never write through a link into
  # this checkout; the engine behind the wrappers is this checkout's)
  cp -RL "$CONFIG_ROOT/roles" "$CONFIG_ROOT/workflows" "$CONFIG_ROOT/firstmate" "$CFG/"
  for f in "$CONFIG_ROOT"/bin/*; do [ -f "$f" ] && cp "$f" "$CFG/bin/$(basename "$f")"; done
  # the REAL engine (byte-identical copies of this checkout's bin/fm-workflow, bin/fm-role-handoff and the schema) lives
  # inside the sandbox, so nothing the Captain can read points at this checkout or its tests/
  mkdir -p "$LOGD/engine/bin" "$LOGD/engine/workflows"
  cp "$W" "$HANDOFF" "$LOGD/engine/bin/"
  cp "$CONFIG_ROOT/workflows/workflow.schema.json" "$LOGD/engine/workflows/"
  stub_wrapper "$LOGD/engine/bin/fm-workflow" > "$CFG/bin/fm-workflow"
  stub_wrapper "$LOGD/engine/bin/fm-role-handoff" > "$CFG/bin/fm-role-handoff"
  chmod +x "$CFG/bin/"*
  cp "$CONFIG_ROOT/firstmate/crew-dispatch.json" "$FMHOME/config/crew-dispatch.json"
  if [ "$control" = 1 ]; then
    strip_policy "$CONFIG_ROOT/firstmate/primary-policy.md" "$CFG/firstmate/primary-policy.md"
    strip_captain "$CONFIG_ROOT/firstmate/captain.md" "$CFG/firstmate/captain.md"
  fi
  [ -z "${FM_CAPTAIN_LIVE_POLICY:-}" ] || [ "$control" = 1 ] || cp "$FM_CAPTAIN_LIVE_POLICY" "$CFG/firstmate/primary-policy.md"
  cp "$CFG/firstmate/captain.md" "$FMHOME/data/captain.md"
  # the registry and the fixture projects
  cat > "$FMHOME/data/projects.md" <<'REG'
- duration-cli [direct-PR] - Duration parsing library and CLI (added 2026-11-01)
- taskbook [direct-PR] - Small local task list (added 2026-11-01)
- notes-cli [no-mistakes] - Plain notes from the command line (added 2026-11-01)
REG
  write_fixture_projects "$FMHOME/projects" || return 1
  # the stubs
  stub_spawn > "$FMROOT/bin/fm-spawn.sh"; stub_brief > "$FMROOT/bin/fm-brief.sh"; stub_project_mode > "$FMROOT/bin/fm-project-mode.sh"
  for f in fm-send.sh fm-control.sh fm-tasks-axi.sh fm-crew-state.sh fm-wake-drain.sh fm-captain-hold.sh fm-inbox.sh fm-bootstrap.sh fm-supervision-instructions.sh fm-lock.sh fm-session-start.sh fm-dispatch-resolve.sh; do
    stub_generic > "$FMROOT/bin/$f"
  done
  for f in fm-brief.sh fm-spawn.sh fm-dispatch-resolve.sh fm-project-mode.sh fm-send.sh fm-tasks-axi.sh; do with_official_header "$FMROOT/bin/$f" "$f"; done
  chmod +x "$FMROOT/bin/"*
  write_digest > "$LOGD/digest.txt"
}

write_digest() { # what bin/fm-session-start.sh prints at session open: its heading names the operational home (FM_HOME), then registry, captain.md, an empty fleet
  printf 'SESSION START - %s\n(bin/fm-session-start.sh, run once at session open; data/, state/, config/ and projects/ below are under that home)\nLOCK: acquired. WAKE QUEUE: empty. FLEET: no tasks in flight, no secondmates.\n\n== data/projects.md ==\n' "$FMHOME"
  cat "$FMHOME/data/projects.md"
  printf '\n== data/captain.md ==\n'
  cat "$FMHOME/data/captain.md"
  printf '\n== data/captain-shared.md == ABSENT\n== data/learnings.md == ABSENT\n== end of digest ==\n'
}

# sandbox_env: the environment the Captain runs in (one KEY=VALUE per line). TMPDIR is private to the run, so a
# mktemp / $TMPDIR scratch file of one Captain can never be another concurrent Captain's.
sandbox_env() {
  printf '%s\n' "FM_HOME=$FMHOME" "FM_CONFIG_ROOT=$CFG" "FIRSTMATE_ROOT=$FMROOT" "FM_FORK_ORIGIN_CWD=$FMROOT" "FM_FORK_ORIGIN_IS_PROJECT=false" "PATH=$FMROOT/bin:$PATH" "TMPDIR=$SCR/tmp"
}

build_prompt() { # <scenario file>: the session-open digest, the harness note, then the human message
  cat "$LOGD/digest.txt"
  printf '\n[Harness note, not from the captain: this sandbox home runs no wake daemon, watcher or supervision cycle, and bin/fm-spawn.sh here only records the launch - no worker will report back during this session. Other captain sessions run on this machine at the same time and share /tmp: put scratch files in $TMPDIR (private to this session), never at a fixed /tmp path. When you have done everything that can be done now (for delegated work: the first worker is launched and you have told the captain what you did), end your turn.]\n\n[The captain writes:]\n'
  ( . "$1"; scn_prompt )
  printf '\n'
}

build_context() { # AGENTS.md as the working-directory context file the harness would load
  printf '# Context files\n\nThe following context file was loaded from the working directory.\n\n## AGENTS.md (%s/AGENTS.md)\n\n' "$FMROOT"
  if [ -f "$FMROOT/AGENTS.md" ]; then cat "$FMROOT/AGENTS.md"; else printf '(no official Firstmate AGENTS.md was found on this machine; this run has none)\n'; fi
}

# ==================================================================================================
# 2. The session transcript: ordered calls and assistant text, cost
# ==================================================================================================
parse_captain_session() { # <session-dir> <run-dir>
  python3 - "$1" "$2" <<'PY'
import glob, json, os, sys
sess, out = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(os.path.join(sess, "**", "*.jsonl"), recursive=True))
calls, texts, final, cost = [], [], "", 0.0
for f in files:
    for line in open(f, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("type") == "model_usage":
            cost += float(((d.get("usage") or {}).get("cost") or {}).get("total") or 0)
        m = d.get("message") or {}
        if m.get("role") != "assistant":
            continue
        cost += float(((m.get("usage") or {}).get("cost") or {}).get("total") or 0)
        content = m.get("content")
        mine = []
        if isinstance(content, str):
            mine.append(content)
        else:
            for c in content or []:
                if c.get("type") == "toolCall":
                    args = json.dumps(c.get("arguments"), ensure_ascii=False)
                    calls.append((c.get("name", "?"), args.replace("\t", " ").replace("\n", " ")))
                elif c.get("type") == "text":
                    mine.append(c.get("text", ""))
        if mine:
            texts.append("\n".join(mine))
            final = "\n".join(mine)
open(os.path.join(out, "calls.tsv"), "w", encoding="utf-8").write("".join("%s\t%s\n" % c for c in calls))
open(os.path.join(out, "alltext.txt"), "w", encoding="utf-8").write("\n\n".join(texts) + "\n")
open(os.path.join(out, "final.txt"), "w", encoding="utf-8").write(final)
open(os.path.join(out, "cost.txt"), "w").write("%.6f\n" % cost)
PY
}

# ==================================================================================================
# 3. Judge helpers (the current run: RUN holds events.jsonl, alltext.txt, calls.tsv, home/; CFG is the
#    sandbox configuration, still on disk while judging). A scenario's scn_judge prints ok/FAIL rows.
# ==================================================================================================
ok()  { printf 'ok   - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1"; }
chk() { if [ "$1" = 0 ]; then ok "$2"; else bad "$3"; fi; }

jw() { FM_HOME="$RUN/home" FM_CONFIG_ROOT="$CFG" "$W" "$@"; }
ev_load() { EV=$(jq -sc 'to_entries | map(.value + {seq: (.key + 1)})' "$RUN/events.jsonl" 2>/dev/null); [ -n "$EV" ] || EV='[]'; }
evq() { printf '%s' "$EV" | jq -r "$@"; }
first_spawn_seq() { evq '[.[] | select(.tool == "fm-spawn.sh") | .seq] | (min // 0)'; }
n_launched() { evq '[.[] | select(.tool == "fm-spawn.sh" and .rc == 0)] | length'; }
n_next() { evq '[.[] | select(.tool == "fm-workflow" and .args[0] == "next")] | length'; }
state_files() { ls "$RUN"/home/data/*/workflow.json 2>/dev/null; }
n_states() { state_files | wc -l | tr -d ' '; }
brief_of() { # <n>: the n-th launched brief file in $RUN/briefs
  ls "$RUN"/briefs/* 2>/dev/null | sed -n "${1}p"
}
# last successful select before the first spawn (or at all when nothing was launched), as JSON
sel_before_spawn() {
  local fs; fs=$(first_spawn_seq)
  evq --argjson fs "$fs" '[.[] | select(.tool == "fm-workflow" and .args[0] == "select" and .rc == 0 and ($fs == 0 or .seq < $fs))] | (last // empty)'
}

j_select() { # <kind-ERE> <delivery|-> <out-ERE> <what>   the last successful select before the first spawn
  local sel kind del out fs
  sel=$(sel_before_spawn); fs=$(first_spawn_seq)
  if [ -z "$sel" ]; then
    if [ "$fs" != 0 ] && [ -n "$(evq '[.[] | select(.tool == "fm-workflow" and .args[0] == "select" and .rc == 0)] | (first // empty)')" ]; then
      bad "fm-workflow select ran only AFTER the first fm-spawn (seq $fs): the workflow was not resolved before launching"
    else bad "no successful fm-workflow select ran before the first worker launch ($4)"; fi
    return 1
  fi
  kind=$(printf '%s' "$sel" | jq -r '.args[1] // ""'); out=$(printf '%s' "$sel" | jq -r '.out')
  if printf '%s' "$kind" | grep -Eq "^($1)\$"; then ok "select ran before the first launch with kind '$kind' (seq $(printf '%s' "$sel" | jq -r .seq), first fm-spawn seq $fs)"
  else bad "select ran with kind '$kind', expected $1"; return 1; fi
  del=$(printf '%s' "$sel" | jq -r '.args as $a | ([range(0; ($a | length))] | map(select($a[.] == "--delivery")) | (first // -1)) as $i | if $i < 0 then "" else ($a[$i + 1] // "") end')
  if [ "$2" != - ]; then
    [ "$del" = "$2" ] && ok "select passed --delivery $del (the project's registered mode)" || { bad "select was passed --delivery '$del', expected $2"; return 1; }
  fi
  if printf '%s' "$out" | grep -Eq "$3"; then ok "select printed: $(printf '%s' "$out" | sed -n 1p | cut -c1-110)"
  else bad "select printed '$(printf '%s' "$out" | sed -n 1p | cut -c1-110)', expected /$3/"; return 1; fi
  return 0
}

j_no_state() { # no workflow state file and no fm-workflow next call
  local n; n=$(n_states)
  [ "$n" = 0 ] && ok "no workflow state file was created" || bad "$n workflow state file(s) were created: $(state_files | tr '\n' ' ')"
  n=$(n_next)
  [ "$n" = 0 ] && ok "no fm-workflow next call" || bad "$n fm-workflow next call(s) were made"
}

j_spawns() { # <min> <max> <what>
  local n; n=$(n_launched)
  if [ "$n" -ge "$1" ] && [ "$n" -le "$2" ]; then ok "$n worker launch(es) ($3)"; else bad "$n worker launches, expected $1 to $2 ($3)"; fi
}

j_brief_roles() { # <allowed-ERE|-> : every Assigned role in every launched brief is allowed; prints them
  local b roles r rc=0 shown=''
  for b in "$RUN"/briefs/*; do
    [ -f "$b" ] || continue
    roles=$(sed -n 's/^Assigned role: //p' "$b")
    [ -n "$roles" ] || { bad "brief $(basename "$b") has no 'Assigned role:' handoff block (the role handoff was not pasted)"; rc=1; continue; }
    for r in $roles; do
      shown="$shown $r"
      if [ "$1" != - ] && ! printf '%s' "$r" | grep -Eq "^($1)\$"; then bad "brief $(basename "$b") assigns role '$r', allowed: $1"; rc=1; fi
    done
  done
  [ "$rc" = 0 ] && ok "launched brief role handoff(s):${shown:- none}"
  return $rc
}

# ---- the workflow-run judge (scenarios 1, 2, 6, 8) -------------------------------------------------
# canon_paths <file> <sandbox-root>: the file with `/dir/../` hops collapsed and the macOS /private prefix of the sandbox root removed
canon_paths() {
  python3 - "$1" "$2" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
scr = sys.argv[2].rstrip("/")
t = t.replace("/private" + scr, scr)
while True:
    n = re.sub(r"/(?!\.\.)[^/\s]+/\.\./", "/", t)
    if n == t:
        break
    t = n
t = re.sub(r"(?<!:)//+", "/", t)
sys.stdout.write(t)
PY
}

# j_workflow <kind-ERE> <delivery> <workflow-ERE> <first-role-ERE|->
j_workflow() {
  local sel wf st stdir statewf next_ok fs spec exp_role role_in_brief b
  j_select "$1" "$2" "^workflow: ($3)\$|^workflow: ($3)[[:space:]]" 'a workflow kind' || return 1
  sel=$(sel_before_spawn)
  wf=$(printf '%s' "$sel" | jq -r '.out' | sed -n 's/^workflow: //p' | head -1)
  fs=$(first_spawn_seq)
  # the state file
  if [ "$(n_states)" != 1 ]; then bad "expected exactly one workflow state file, found $(n_states)"; return 1; fi
  st=$(state_files | head -1)
  statewf=$(jq -r '.workflow // empty' "$st" 2>/dev/null)
  [ "$statewf" = "$wf" ] && ok "state file $(basename "$(dirname "$st")")/workflow.json holds workflow $statewf (the one select printed)" || { bad "state file workflow '$statewf' differs from the selected '$wf'"; return 1; }
  [ -n "$(jq -r '.task // empty' "$st" 2>/dev/null)" ] && ok "state file records the captain's intent (--task): $(jq -r '.task' "$st" | cut -c1-80)" || bad "state file has no task text"
  next_ok=$(evq --arg wf "$wf" '[.[] | select(.tool == "fm-workflow" and .args[0] == "next" and .args[1] == $wf and .rc == 0 and (.args | index("--task"))) | select((.cwd // "") as $c | .args[2] as $p | (if ($p | startswith("/")) then $p else ($c + "/" + $p) end) | test("/data/[^/]+/workflow\\.json$"))] | (first // empty)')
  if [ -n "$next_ok" ]; then
    local nseq; nseq=$(printf '%s' "$next_ok" | jq -r .seq)
    if [ "$fs" = 0 ] || [ "$nseq" -lt "$fs" ]; then ok "fm-workflow next $wf <data>/workflow.json --task ... ran before the first launch (seq $nseq)"
    else bad "fm-workflow next ran at seq $nseq, after the first fm-spawn (seq $fs)"; fi
  else bad "no 'fm-workflow next $wf <FM_HOME>/data/<id>/workflow.json --task ...' call"; fi
  # no result recorded and still at the start step: a recorded result needs a worker report that cannot exist here
  local rec; rec=$(evq '[.[] | select(.tool == "fm-workflow" and .args[0] == "next" and ((.args | index("--report")) or (.args | index("--outcome")) or (.args | index("--decide"))))] | length')
  [ "$rec" = 0 ] && ok "no result was recorded (no --report/--outcome/--decide): the engine is still at its start step" || bad "$rec next call(s) recorded a result although no worker could have reported"
  # exactly one launch, the first step
  j_spawns 1 1 'only the start step may run before a recorded result' || return 1
  # the brief: role handoff + the engine's spec, verbatim
  local braw; braw=$(brief_of 1)
  [ -f "$braw" ] || { bad 'no launched brief captured'; return 1; }
  # a path is the same file whichever way a Captain spells it (a `..` hop, a /private symlink prefix); the checks below read
  # the brief with those spellings collapsed, so only the text of the spec is compared, never how a path was written
  b=$RUN/brief-canon.md; canon_paths "$braw" "$(dirname "$CFG")" > "$b"
  rm -rf "$RUN/.spec"; mkdir -p "$RUN/.spec/data/x"; cp "$st" "$RUN/.spec/data/x/workflow.json"
  spec=$(FM_HOME="$RUN/.spec" FM_CONFIG_ROOT="$CFG" "$W" next "$wf" "$RUN/.spec/data/x/workflow.json" --spec 2>/dev/null)
  printf '%s\n' "$spec" > "$RUN/spec.txt"
  exp_role=$(printf '%s\n' "$spec" | sed -n 's/^Assigned role: //p' | head -1)
  [ -n "$exp_role" ] || { bad 'could not derive the start step role from the engine (next --spec)'; return 1; }
  if [ "$4" != - ]; then printf '%s' "$exp_role" | grep -Eq "^($4)\$" && ok "the engine's start step role is $exp_role" || bad "the engine's start step role is '$exp_role', expected $4"; fi
  local rpath; rpath=$(printf '%s\n' "$spec" | grep -A1 '^Role source:' | sed -n 2p | sed 's/^ *//')
  if [ -n "$rpath" ] && grep -qF -- "$rpath" "$b"; then ok "the first worker's brief names the step role's ROLE.md ($(printf '%s' "$rpath" | sed 's#.*/roles/#roles/#'))"
  else bad "the first worker's brief does not contain the step role's ROLE.md path ($rpath)"; fi
  # the spec is pasted unchanged (primary policy section 8, Running 2): first the worker-facing body from its
  # Step instruction line on, then the whole output from its first line (the Workflow step header) to its last
  awk '/^Step instruction:/ { on = 1 } on { print }' "$RUN/spec.txt" > "$RUN/spec-body.txt"
  if python3 - "$RUN/spec-body.txt" "$b" <<'PY'
import sys
spec = open(sys.argv[1], encoding="utf-8").read()
brief = open(sys.argv[2], encoding="utf-8").read()
norm = lambda s: "\n".join(l.rstrip() for l in s.replace("\r\n", "\n").strip().split("\n"))
sys.exit(0 if spec.strip() and norm(spec) in norm(brief) else 1)
PY
  then ok "the brief carries the engine's spec body (Step instruction, Inputs, Output contract, role handoff) verbatim"; else bad "the brief does not contain the engine's spec body (from its Step instruction line on) verbatim"; fi
  if python3 - "$RUN/spec.txt" "$b" <<'PY'
import sys
spec = open(sys.argv[1], encoding="utf-8").read()
brief = open(sys.argv[2], encoding="utf-8").read()
norm = lambda s: "\n".join(l.rstrip() for l in s.replace("\r\n", "\n").strip().split("\n"))
sys.exit(0 if norm(spec) in norm(brief) else 1)
PY
  then ok "the brief carries the engine's WHOLE spec (next --spec) unchanged, from its first line to its last"; else bad "the brief does not contain the engine's whole spec (next --spec) unchanged: a header line (Workflow step ... / Step ... role ...) or any other line was left out, reworded or moved"; fi
  # the section 0 trace line is chat-only (policy section 0): the engine's spec has none, so none may be in the brief
  if grep -Eq '^[[:space:]>*`-]*Workflow: ' "$b"; then bad "the brief carries a section 0 'Workflow:' trace line, which is chat-only and never goes into a brief"; else ok "the brief carries no section 0 'Workflow:' trace line (it is chat-only)"; fi
  # only the step's role: no other role handoff
  local others; others=$(grep -oE '/roles/[a-z0-9-]+/ROLE\.md' "$b" | sort -u | grep -vF "/roles/$exp_role/ROLE.md" | tr '\n' ' ')
  [ -z "$others" ] && ok "the brief hands over the step's role only ($exp_role)" || bad "the brief also names other roles: $others"
  j_trace "$st" "$exp_role"
}

# j_trace <state> <role>: the Captain's section 0 block: the Workflow line equals the derived one; Agent and Skills agree
j_trace() {
  local st=$1 role=$2 line derived agent skills want got
  derived=$(jw trace "$st" 2>/dev/null)
  line=$(grep -E '^[[:space:]>*`-]*Workflow: ' "$RUN/alltext.txt" | sed -e 's/^[[:space:]>*`-]*//' -e 's/[[:space:]`*]*$//' | tail -1)
  if [ -z "$line" ]; then bad "the Captain printed no 'Workflow:' trace line (derived: $derived)"; else
    printf '%s\n' "$line" > "$RUN/.trace-block"
    if jw trace "$st" "$RUN/.trace-block" >/dev/null 2>&1; then ok "the Captain's trace line equals 'fm-workflow trace' (checked by the engine): $line"
    else bad "the Captain's trace line differs from the derived one: '$line' vs '$derived'"; fi
  fi
  agent=$(grep -E '^[[:space:]>*`-]*Agent: ' "$RUN/alltext.txt" | sed -e 's/^[[:space:]>*`-]*Agent: *//' -e 's/[[:space:]`*]*$//' | tail -1)
  [ "$agent" = "$role" ] && ok "trace 'Agent: $agent' names the assigned role" || bad "trace 'Agent:' is '${agent:-<none>}', expected $role"
  skills=$(grep -E '^[[:space:]>*`-]*Skills: ' "$RUN/alltext.txt" | sed -e 's/^[[:space:]>*`-]*Skills: *//' -e 's/[[:space:]`*]*$//' | tail -1)
  want=$(FM_CONFIG_ROOT="$CFG" "$HANDOFF" --skills "$role" 2>/dev/null | tr -s ' \n' '\n\n' | sed '/^$/d' | paste -sd, -)
  [ -n "$want" ] || want=none
  got=$(printf '%s' "$skills" | tr -s ', ' '\n\n' | sed '/^$/d' | paste -sd, -)
  [ "$got" = "$want" ] && ok "trace 'Skills:' equals the role's autoloadSkills ($want)" || bad "trace 'Skills:' is '${got:-<none>}', derived '$want'"
}

# j_exception <kind-ERE> <out-ERE> <spawn-min> <spawn-max> <role-ERE|->  : an exception: select, no state, no next
j_exception() {
  j_select "$1" - "$2" 'an exception kind' || { j_no_state; return 1; }
  j_no_state
  j_spawns "$3" "$4" 'the exception runs one worker, no workflow'
  [ "$(n_launched)" = 0 ] || j_brief_roles "$5"
}

# ==================================================================================================
# 4. Canned stand-in Captains for the offline self-test: they drive the sandbox through the same stubs
# ==================================================================================================
c_run() { # <command> : record a bash call in the fake session and run it in the sandbox
  jq -cn --arg c "$1" '{type: "message", message: {role: "assistant", content: [{type: "toolCall", name: "bash", arguments: {command: $c}}], usage: {cost: {total: 0.001}}}}' >> "$CS/s.jsonl"
  bash -c "$1" >> "$CS/out.log" 2>&1
}
c_say() {
  jq -cn --arg t "$1" '{type: "message", message: {role: "assistant", content: [{type: "text", text: $t}], usage: {cost: {total: 0.001}}}}' >> "$CS/s.jsonl"
}
c_fill() { # <id> <spec-file|-> : fill the scaffold the way a Captain does through bash
  local brief=$FM_HOME/data/$1/brief.md out line
  out=$(mktemp "${TMPDIR:-/tmp}/fm-cap-fill.XXXXXX")
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      '{TASK}') printf 'The captain asked for this change on the project (see the human message).\n' ;;
      '{FIRSTMATE_SPEC}') if [ "$2" = - ]; then printf 'Do the work and report what you ran.\n'; else cat "$2"; fi ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$brief" > "$out"
  cp "$out" "$brief"; rm -f "$out"
  jq -cn --arg c "cat > $brief <<EOF ... (brief filled)" '{type: "message", message: {role: "assistant", content: [{type: "toolCall", name: "bash", arguments: {command: $c}}], usage: {cost: {total: 0.001}}}}' >> "$CS/s.jsonl"
}
mode_flag() { case $1 in direct-pr) echo direct-PR ;; local-only) echo local-only ;; no-mistakes) echo no-mistakes ;; esac; }
canned_trace() { # <state> <role> [wrong]
  local st=$1 role=$2 line skills
  line=$("$FM_CONFIG_ROOT/bin/fm-workflow" trace "$st")
  [ "${3:-}" != wrong ] || line=$(printf '%s' "$line" | sed 's/step [a-z-]* #1/step review #1/')
  skills=$(FM_CONFIG_ROOT="$FM_CONFIG_ROOT" "$FM_CONFIG_ROOT/bin/fm-role-handoff" --skills "$role" | tr -s ' \n' '\n\n' | sed '/^$/d' | paste -sd, - | sed 's/,/, /g')
  [ -n "$skills" ] || skills=none
  c_say "Routing: IMPLEMENT | role $role | omp | anthropic/claude-sonnet-5-5 | medium | why: canned
Agent: $role
Skills: $skills
$line

Launched the first worker; waiting for its report."
}

# canned_workflow <variant> <id> <project> <kind> <delivery> <expected-workflow> <task>
canned_workflow() {
  local v=$1 id=$2 proj=$3 kind=$4 del=$5 expwf=$6 task=$7 st wf selout role m spec
  st=$FM_HOME/data/$id/workflow.json; m=$(mode_flag "$del"); wf=$expwf
  W_=$FM_CONFIG_ROOT/bin/fm-workflow
  case $v in
    no-select) : ;;
    select-late) : ;;
    wrong-delivery) case $del in no-mistakes) del=direct-pr ;; *) del=no-mistakes ;; esac
      c_run "$W_ select $kind --delivery $del"
      wf=$("$W_" select "$kind" --delivery "$del" | sed -n 's/^workflow: //p'); [ -n "$wf" ] || wf=$expwf ;;
    *) c_run "$W_ select $kind --delivery $del" ;;
  esac
  if [ "$v" = good-relative-path ]; then c_run "cd $FM_HOME && $W_ next $wf data/$id/workflow.json --task '$task'"
  elif [ "$v" != no-next ] && [ "$v" != select-late ]; then c_run "$W_ next $wf $st --task '$task'"; fi
  if [ "$v" = select-late ]; then c_run "$W_ next $wf $st --task '$task'"; fi
  local specroot=$FM_CONFIG_ROOT
  case $v in
    good-dotdot-config) specroot=$FIRSTMATE_ROOT/../config ;;
    good-doubleslash-config) specroot=$(dirname "$FIRSTMATE_ROOT")//config ;;
    bad-other-config-root) cp -R "$FM_CONFIG_ROOT" "$FM_CONFIG_ROOT/../config2"; specroot=$FM_CONFIG_ROOT/../config2 ;;
  esac
  if [ -f "$st" ]; then FM_CONFIG_ROOT=$specroot "$W_" next "$wf" "$st" --spec > "$FM_HOME/data/spec-$id.txt" 2>/dev/null; spec=$FM_HOME/data/spec-$id.txt
    role=$(sed -n 's/^Assigned role: //p' "$spec" | head -1)
  else role=senior-fullstack; "$FM_CONFIG_ROOT/bin/fm-role-handoff" "$role" > "$FM_HOME/data/spec-$id.txt"; spec=$FM_HOME/data/spec-$id.txt; fi
  c_run "$FIRSTMATE_ROOT/bin/fm-brief.sh $id $proj --mode $m"
  if [ "$v" = brief-no-handoff ]; then c_fill "$id" -
  elif [ "$v" = spec-header-trimmed ]; then sed 1,4d "$spec" > "$spec.trim"; c_fill "$id" "$spec.trim"
  elif [ "$v" = spec-title-dropped ]; then sed 1d "$spec" > "$spec.trim"; c_fill "$id" "$spec.trim"
  elif [ "$v" = spec-step-line-dropped ]; then grep -v '^Step [a-z0-9-]*, role ' "$spec" > "$spec.trim"; c_fill "$id" "$spec.trim"
  elif [ "$v" = spec-reworded ]; then sed 's/^Step instruction:/Instruction:/' "$spec" > "$spec.trim"; c_fill "$id" "$spec.trim"
  elif [ "$v" = trace-in-brief ]; then { "$FM_CONFIG_ROOT/bin/fm-workflow" trace "$st"; cat "$spec"; } > "$spec.trim"; c_fill "$id" "$spec.trim"
  else c_fill "$id" "$spec"; fi
  c_run "$FIRSTMATE_ROOT/bin/fm-spawn.sh $id $FM_HOME/projects/$proj --mode $m --yolo off --harness omp --model anthropic/claude-sonnet-5-5 --effort medium"
  if [ "$v" = select-late ]; then c_run "$W_ select $kind --delivery $del"; fi
  if [ "$v" = second-step ]; then
    c_run "$FIRSTMATE_ROOT/bin/fm-brief.sh $id-2 $proj --mode $m"; c_fill "$id-2" "$spec"
    c_run "$FIRSTMATE_ROOT/bin/fm-spawn.sh $id-2 $FM_HOME/projects/$proj --mode $m --yolo off"
  fi
  if [ "$v" = no-trace ]; then c_say "Launched the first worker; waiting for its report."
  elif [ -f "$st" ]; then
    if [ "$v" = trace-wrong ]; then canned_trace "$st" "$role" wrong; else canned_trace "$st" "$role"; fi
  else c_say "Launched the worker."; fi
}

# canned_exception <variant> <id> <project> <select-args...> -- <role> <scout 0|1> <task>
canned_exception() {
  local v=$1 id=$2 proj=$3; shift 3
  local sargs=() role scout task m=direct-PR W_=$FM_CONFIG_ROOT/bin/fm-workflow
  while [ "$1" != -- ]; do sargs+=("$1"); shift; done
  shift; role=$1; scout=$2; task=$3
  case $v in
    no-select) : ;;
    select-late) : ;;
    *) c_run "$W_ select $(printf '%q ' "${sargs[@]}")" ;;
  esac
  if [ "$v" = start-workflow ]; then c_run "$W_ next bug-fix $FM_HOME/data/$id/workflow.json --task '$task'"; fi
  [ "$v" != wrong-role ] || role=qa
  if [ "$scout" = 1 ]; then c_run "$FIRSTMATE_ROOT/bin/fm-brief.sh $id $proj --scout"; else c_run "$FIRSTMATE_ROOT/bin/fm-brief.sh $id $proj --mode $m"; fi
  "$FM_CONFIG_ROOT/bin/fm-role-handoff" "$role" > "$FM_HOME/data/spec-$id.txt"
  if [ "$v" = no-handoff ]; then c_fill "$id" -; else c_fill "$id" "$FM_HOME/data/spec-$id.txt"; fi
  if [ "$scout" = 1 ]; then c_run "$FIRSTMATE_ROOT/bin/fm-spawn.sh $id $FM_HOME/projects/$proj --scout --harness omp --model anthropic/claude-sonnet-5-5 --effort medium"
  else c_run "$FIRSTMATE_ROOT/bin/fm-spawn.sh $id $FM_HOME/projects/$proj --mode $m --yolo off --harness omp --model anthropic/claude-sonnet-5-5 --effort medium"; fi
  if [ "$v" = select-late ]; then c_run "$W_ select $(printf '%q ' "${sargs[@]}")"; fi
  if [ "$v" = second-worker ]; then
    c_run "$FIRSTMATE_ROOT/bin/fm-brief.sh $id-2 $proj --scout"; c_fill "$id-2" "$FM_HOME/data/spec-$id.txt"
    c_run "$FIRSTMATE_ROOT/bin/fm-spawn.sh $id-2 $FM_HOME/projects/$proj --scout"
  fi
  c_say "Launched the worker; waiting for its report."
}

# __canned <scenario file> <variant> <session-dir>: the fake omp's whole behavior
canned_main() {
  local scn=$1 variant=$2
  CS=$3; mkdir -p "$CS"; : > "$CS/s.jsonl"; : > "$CS/out.log"
  . "$scn"
  scn_canned "$variant"
}

# ==================================================================================================
# 5. Running one scenario (live or canned) and judging it
# ==================================================================================================
# run_one <scenario-file> <label> <control 0|1>: builds the sandbox, runs the Captain, parses, judges.
# Sets RUNROW (the results row), LAST_VERDICT (PASS|FAIL|INFO).
run_one() {
  local scn=$1 label=$2 control=$3 rc t g jrc name proj prompt_file t0 secs shared
  name=$(basename "$scn" .sh)
  build_sandbox "$control" || { fail "$label: sandbox setup failed"; LAST_VERDICT=FAIL; return 1; }
  RUN=$ART/$label; mkdir -p "$RUN"
  prompt_file=$RUN/prompt.md
  build_prompt "$scn" > "$prompt_file"
  build_context > "$RUN/context.md"
  ENVARR=(); while IFS= read -r t; do ENVARR+=("$t"); done < <(sandbox_env)
  t0=$(date +%s)
  ( cd "$FMROOT" && env -i HOME="$HOME" TERM=dumb LANG=C.UTF-8 OMP_SKIP_SETUP=1 PYTHONDONTWRITEBYTECODE=1 \
      "${ENVARR[@]}" ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} \
      timeout "$TIMEOUT" "$OMP_BIN" -p --model "$MODEL" --thinking "$THINKING" --no-extensions --no-skills --no-rules --no-context-files \
      --no-lsp --no-pty --no-title --tools read,grep,glob,bash --append-system-prompt "$RUN/context.md" \
      --session-dir "$SCR/session" ${COST_ARGS[@]+"${COST_ARGS[@]}"} --auto-approve --cwd "$FMROOT" "@$prompt_file" \
      > "$RUN/stdout.txt" 2> "$RUN/stderr.txt" ); rc=$?
  secs=$(( $(date +%s) - t0 ))
  printf '%s\n' "$rc" > "$RUN/rc"
  cp -R "$SCR/session" "$RUN/session" 2>/dev/null
  cp "$LOGD/events.jsonl" "$RUN/events.jsonl"
  mkdir -p "$RUN/briefs"; cp "$LOGD"/briefs/* "$RUN/briefs/" 2>/dev/null
  mkdir -p "$RUN/home"; cp -R "$FMHOME/data" "$FMHOME/state" "$RUN/home/" 2>/dev/null
  parse_captain_session "$RUN/session" "$RUN"
  shared=$(scan_shared_tmp "$RUN/calls.tsv" "$SCR")
  [ -z "$shared" ] || printf '%s\n' "$shared" > "$RUN/shared-tmp.txt"
  spent_add "$(cat "$RUN/cost.txt")"
  [ -s "$RUN/final.txt" ] || printf 'The Captain produced no message (omp exit %s).\n' "$rc" > "$RUN/final.txt"
  ev_load
  if [ "$rc" = 143 ] || [ "$rc" = 137 ]; then
    printf 'INVALID - omp was killed by a signal (exit %s) before the Captain finished: an infrastructure event, not Captain behavior; not judged and re-run\n' "$rc" > "$RUN/grade.txt"; LAST_VERDICT=INVALID
  elif [ "$control" = 1 ]; then
    control_report "$name" > "$RUN/grade.txt"; LAST_VERDICT=INFO
  else
    g=$( . "$scn"; scn_judge 2>&1 )
    printf '%s\n' "$g" > "$RUN/grade.txt"
    if printf '%s\n' "$g" | grep -q '^FAIL'; then LAST_VERDICT=FAIL; else LAST_VERDICT=PASS; fi
  fi
  RUNROW=$(printf '| %s | %s | %s | %s | %s | %s | %s | %s |' "$label" "$LAST_VERDICT" "$(n_launched)" "$(wc -l < "$RUN/calls.tsv" | tr -d ' ')" "$(cat "$RUN/cost.txt")" "$SPENT" "$secs" "${shared:+SHARED /tmp: $(printf '%s' "$shared" | head -1)}")
  rm -rf "$SCR"
}

# scan_shared_tmp <calls.tsv> <scr>: prints the fixed /tmp paths (outside this run's private directory) the Captain
# named in a command. A fixed /tmp path is shared with every concurrent Captain on the machine, so a run that used
# one is flagged in results.md: when two runs overlap in time and both used the same path, neither is trusted.
scan_shared_tmp() {
  python3 - "$1" "$2" <<'PY'
import re, sys
calls, scr = sys.argv[1], sys.argv[2].rstrip("/")
seen = []
for line in open(calls, encoding="utf-8", errors="replace"):
    for m in re.finditer(r"(?<![\w./$~-])(?:/private)?/tmp/[\w.+-]+(?:/[\w.+-]+)*", line):
        p = m.group(0)
        if not p.startswith(scr) and p not in seen:
            seen.append(p)
print("\n".join(seen))
PY
}

# control_report <scenario>: what the Captain did WITHOUT the standing rule (informational)
control_report() {
  local sel nxt st sp
  sel=$(evq '[.[] | select(.tool == "fm-workflow" and .args[0] == "select")] | length')
  nxt=$(n_next); st=$(n_states); sp=$(n_launched)
  printf 'control run: select calls %s, next calls %s, workflow state files %s, launches %s, any fm-workflow call %s\n' "$sel" "$nxt" "$st" "$sp" "$(evq '[.[] | select(.tool == "fm-workflow")] | length')"
  printf 'bash commands naming fm-workflow: %s\n' "$(grep -c 'fm-workflow' "$RUN/calls.tsv")"
}

# ==================================================================================================
# 6. Offline self-test
# ==================================================================================================
selftest_fake_omp() { # the harness mechanics through a fake omp: tools flag, context, prompt, env, stubs, control strip
  local t fake name scn rc
  t=$(mktemp -d "${TMPDIR:-/tmp}/fm-captain-live-self.XXXXXX") || return 1
  fake=$t/omp
  cat > "$fake" <<'SH'
#!/usr/bin/env bash
sess=''; prompt=''; tools=''; cwd=''; ctx=''
while [ $# -gt 0 ]; do case $1 in --session-dir) sess=$2; shift ;; --tools) tools=$2; shift ;; --cwd) cwd=$2; shift ;; --append-system-prompt) ctx=$2; shift ;; @*) prompt=${1#@} ;; esac; shift; done
mkdir -p "$sess"
printf '%s\n' "$tools" > "$sess/tools-seen"
cp "$ctx" "$sess/context-seen"; cp "$prompt" "$sess/prompt-seen"
printf '%s\n%s\n%s\n%s\n' "$PWD" "$FM_HOME" "$FM_CONFIG_ROOT" "$TMPDIR" > "$sess/env-seen"
ls "$FIRSTMATE_ROOT/bin" > "$sess/bin-seen"
out=$("$FIRSTMATE_ROOT/bin/fm-spawn.sh" nope 2>&1); echo "$out" > "$sess/spawn-usage-seen"
printf '{"type":"message","message":{"role":"assistant","content":[{"type":"toolCall","name":"bash","arguments":{"command":"true"}}],"usage":{"cost":{"total":0.01}}}}\n{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"Workflow: x\\nfake"}],"usage":{"cost":{"total":0.02}}}}\n' > "$sess/s.jsonl"
SH
  chmod +x "$fake"
  name=selftest-fake; scn=$t/$name.sh
  printf 'SCN_PROJECT=duration-cli\nscn_prompt() { printf "do the thing\\n"; }\nscn_judge() { echo "ok   - fake judge"; }\n' > "$scn"
  OMP_BIN=$fake; ART=$t/art; mkdir -p "$ART"; SPENT=0
  ( run_one "$scn" "$name" 0 ) > "$t/out.txt" 2>&1
  local S=$ART/$name/session
  [ "$(cat "$S/tools-seen")" = "read,grep,glob,bash" ] && pass 'selftest: the Captain gets exactly read, grep, glob, bash (no edit, no write)' || fail "selftest: tools were $(cat "$S/tools-seen" 2>/dev/null)"
  grep -q 'FAIL' "$t/out.txt" && fail "selftest: fake run failed: $(cat "$t/out.txt")" || pass 'selftest: a fake omp runs through the whole pipeline'
  printf '#!/bin/sh\nkill -TERM $$\n' > "$t/omp-kill"; chmod +x "$t/omp-kill"
  ( OMP_BIN=$t/omp-kill; run_one "$scn" selftest-kill 0 ) > "$t/out-kill.txt" 2>&1
  grep -q '^INVALID' "$ART/selftest-kill/grade.txt" && ! grep -q '^\(ok\|FAIL\)' "$ART/selftest-kill/grade.txt" && pass 'selftest: a Captain killed by a signal is INVALID, not judged and never a PASS' || fail "selftest: killed Captain graded: $(cat "$ART/selftest-kill/grade.txt" 2>/dev/null)"
  [ "$(cat "$ART/$name/cost.txt")" = "0.030000" ] && pass 'selftest: cost is summed from the session usage' || fail "selftest: cost $(cat "$ART/$name/cost.txt")"
  if find_agents_md >/dev/null; then
    grep -q 'You are the first mate' "$S/context-seen" && pass 'selftest: the official AGENTS.md is in the Captain context' || fail 'selftest: AGENTS.md missing from the context'
  else skip 'selftest: no official AGENTS.md on this machine (the live run would carry none)'; fi
  grep -q 'code-changing' "$S/prompt-seen" && grep -q 'fm-workflow select' "$S/prompt-seen" && grep -q 'duration-cli \[direct-PR\]' "$S/prompt-seen" && pass 'selftest: the session digest carries captain.md and the project registry' || fail 'selftest: digest incomplete'
  grep -q 'do the thing' "$S/prompt-seen" && grep -q 'bin/fm-spawn.sh here only records' "$S/prompt-seen" && pass 'selftest: the prompt ends with the human message after the harness note' || fail 'selftest: prompt shape'
  [ "$(sed -n 2p "$S/env-seen")" != "" ] && [ "$(sed -n 1p "$S/env-seen")" != "$CONFIG_ROOT" ] && pass 'selftest: the Captain runs in the sandbox with FM_HOME and FM_CONFIG_ROOT set' || fail 'selftest: sandbox env'
  [ "$(sed -n 4p "$S/env-seen")" = "$(dirname "$(sed -n 2p "$S/env-seen")")/tmp" ] && grep -q 'put scratch files in \$TMPDIR' "$S/prompt-seen" && pass 'selftest: the Captain gets a private TMPDIR and the prompt says to use it' || fail "selftest: private TMPDIR: $(sed -n 4p "$S/env-seen")"
  grep -qF "SESSION START - $(sed -n 2p "$S/env-seen")" "$S/prompt-seen" && pass 'selftest: the session digest heading names the operational home (FM_HOME), as the real bin/fm-session-start.sh does' || fail 'selftest: the digest does not name FM_HOME'
  local ct=$t/calls-shared.tsv sh_
  printf 'bash\t{"command": "cat > /tmp/spec.txt <<EOF"}\nbash\t{"command": "cat > $TMPDIR/spec.txt; cat /var/x/T/fm-captain-live.AbC/tmp/s.txt"}\nbash\t{"command": "f=$(mktemp /tmp/brief.XXXXXX); cat ../tmp-notes"}\n' > "$ct"
  sh_=$(scan_shared_tmp "$ct" /var/x/T/fm-captain-live.AbC | tr '\n' ' ')
  [ "$sh_" = '/tmp/spec.txt /tmp/brief.XXXXXX ' ] && pass 'selftest: a fixed /tmp path is flagged, $TMPDIR and the run private directory are not' || fail "selftest: shared /tmp scan printed: $sh_"
  printf 'Role source:\n  /private/var/x/T/s/fmroot/../config/roles/planner/ROLE.md\nother /var/x/T/s//config/roles/qa/ROLE.md and ../x kept https://e.invalid/a\n' > "$ct"
  sh_=$(canon_paths "$ct" /var/x/T/s | tr '\n' '|')
  [ "$sh_" = 'Role source:|  /var/x/T/s/config/roles/planner/ROLE.md|other /var/x/T/s/config/roles/qa/ROLE.md and ../x kept https://e.invalid/a|' ] && pass 'selftest: canon_paths collapses a dotdot hop, a doubled slash and the /private prefix of the sandbox, and nothing else (URLs keep their //)' || fail "selftest: canon_paths printed: $sh_"
  for f in fm-spawn.sh fm-brief.sh fm-send.sh fm-project-mode.sh fm-dispatch-resolve.sh fm-session-start.sh; do grep -qx "$f" "$S/bin-seen" && pass "selftest: stub $f is on the sandbox bin" || fail "selftest: stub $f missing"; done
  grep -q 'REQUIRED' "$S/spawn-usage-seen" && pass 'selftest: the fm-spawn stub refuses an incomplete spawn' || fail 'selftest: spawn stub usage'
  # the stub semantics: placeholders are refused, a filled brief is accepted, the project mode answers
  build_sandbox 0 || fail 'selftest: sandbox build'
  local env_ out
  env_=$(sandbox_env)
  out=$( cd "$FMROOT" && env FM_HOME="$FMHOME" "$FMROOT/bin/fm-brief.sh" t1 duration-cli --mode direct-PR 2>&1 )
  out=$( cd "$FMROOT" && env FM_HOME="$FMHOME" "$FMROOT/bin/fm-spawn.sh" t1 "$FMHOME/projects/duration-cli" --mode direct-PR --yolo off 2>&1 ); rc=$?
  [ "$rc" = 1 ] && printf '%s' "$out" | grep -q placeholder && pass 'selftest: fm-spawn refuses a brief with unfilled placeholders' || fail "selftest: placeholder refusal rc=$rc $out"
  out=$( cd "$FMROOT" && env FM_HOME="$FMHOME" "$FMROOT/bin/fm-spawn.sh" t1 "$FMHOME/projects/duration-cli" --mode direct-PR 2>&1 ); rc=$?
  [ "$rc" = 2 ] && pass 'selftest: fm-spawn requires --yolo for a ship spawn' || fail "selftest: yolo requirement rc=$rc"
  [ "$(env FM_HOME="$FMHOME" "$FMROOT/bin/fm-project-mode.sh" notes-cli)" = 'no-mistakes off' ] && [ "$(env FM_HOME="$FMHOME" "$FMROOT/bin/fm-project-mode.sh" duration-cli)" = 'direct-PR off' ] && pass 'selftest: fm-project-mode answers from the registry' || fail 'selftest: project mode'
  [ "$(git -C "$FMHOME/projects/duration-cli" log --oneline | wc -l | tr -d ' ')" = 1 ] && pass 'selftest: the fixture projects are git repositories' || fail 'selftest: fixture repo'
  out=$( cd "$FMROOT" && env FM_HOME="$FMHOME" FM_CONFIG_ROOT="$CFG" "$CFG/bin/fm-workflow" select bugfix --delivery direct-pr )
  [ "$(printf '%s' "$out" | sed -n 1p)" = 'workflow: bug-fix' ] && [ "$(jq -r 'select(.tool=="fm-workflow") | .out' "$LOGD/events.jsonl" | sed -n 1p)" = 'workflow: bug-fix' ] && pass 'selftest: the REAL engine runs behind a logging wrapper that records its result' || fail "selftest: wrapper: $out"
  rm -rf "$SCR"
  # the negative control strips the rule and nothing else it should keep
  build_sandbox 1 || fail 'selftest: control sandbox build'
  if grep -Eq 'fm-workflow|Standing rule|MUST run a workflow|## 8\. Workflows' "$CFG/firstmate/primary-policy.md" "$CFG/firstmate/captain.md"; then fail 'selftest: the control context still names fm-workflow or the standing rule'; else pass 'selftest: the control context has no standing rule, no section 8, no fm-workflow'; fi
  grep -q '^## 7\. Completion' "$CFG/firstmate/primary-policy.md" && grep -q 'Evidence over reassurance' "$CFG/firstmate/captain.md" && grep -q 'Role handoff' "$CFG/firstmate/primary-policy.md" && pass 'selftest: the control keeps the rest of the policy and captain.md' || fail 'selftest: the control stripped too much'
  grep -q 'code-changing' "$FMHOME/data/captain.md" && fail 'selftest: control digest still has the workflow paragraph' || pass 'selftest: the control digest (data/captain.md) has no workflow paragraph'
  if grep -rlF "$CONFIG_ROOT" "$SCR" 2>/dev/null | grep -q .; then fail "selftest: the sandbox still names this checkout ($CONFIG_ROOT): $(grep -rlF "$CONFIG_ROOT" "$SCR" | head -3 | tr '\n' ' ')"; else pass 'selftest: nothing in the sandbox names this checkout or its tests/ (the Captain cannot be pointed at the judge)'; fi
  rm -rf "$SCR"
  rm -rf "$t"; ART=''
}

selftest_scenarios() { # every scenario's real judge on a canned compliant and canned violating Captain
  local scn name v mode g rc t
  t=$(mktemp -d "${TMPDIR:-/tmp}/fm-captain-live-scn.XXXXXX") || return 1
  fake_canned_omp "$t/omp"
  for scn in "$CASES_DIR"/*.sh; do
    [ -f "$scn" ] || continue
    name=$(basename "$scn" .sh)
    [ "${#ONLY[@]}" -eq 0 ] || case " ${ONLY[*]} " in *" $name "*) ;; *) continue ;; esac
    ( . "$scn"; declare -F scn_prompt >/dev/null && declare -F scn_judge >/dev/null && declare -F scn_canned >/dev/null && [ -n "${SCN_PROJECT:-}" ] && [ -n "${SCN_BAD:-}" ] ) && pass "scenario $name: defines its prompt, judge, canned Captain and bad variants" || { fail "scenario $name: incomplete scenario file"; continue; }
    for v in good $(. "$scn"; printf '%s' "$SCN_BAD"); do
      ART=$t/art-$name-$v; mkdir -p "$ART"; SPENT=0
      OMP_BIN=$t/omp; EXTRA_ENV=("FM_CAPTAIN_CANNED_SCN=$scn" "FM_CAPTAIN_CANNED_VARIANT=$v" "FM_CAPTAIN_CANNED_SELF=$SELF")
      ( run_one "$scn" "$name-$v" 0 ) > "$t/out.txt" 2>&1
      g=$(cat "$ART/$name-$v/grade.txt" 2>/dev/null)
      if [ "${v#good}" != "$v" ]; then
        [ -n "$g" ] && ! printf '%s\n' "$g" | grep -q '^FAIL' && pass "scenario $name: a compliant canned Captain ($v) passes the whole judge ($(printf '%s\n' "$g" | grep -c '^ok') checks)" || fail "scenario $name: the compliant canned Captain ($v) was rejected: $(printf '%s\n' "$g" | grep '^FAIL' | tr '\n' ' ') $(cat "$t/out.txt")"
      else
        printf '%s\n' "$g" | grep -q '^FAIL' && pass "scenario $name: the judge rejects the '$v' Captain ($(printf '%s\n' "$g" | grep -m1 '^FAIL' | cut -c1-100))" || fail "scenario $name: the judge ACCEPTED the '$v' Captain: $g"
      fi
      rm -rf "$ART"
    done
  done
  rm -rf "$t"; ART=''; EXTRA_ENV=()
}

fake_canned_omp() { # <path>: a fake omp that replays a canned Captain through the sandbox
  cat > "$1" <<'SH'
#!/usr/bin/env bash
sess=''
while [ $# -gt 0 ]; do case $1 in --session-dir) sess=$2; shift ;; esac; shift; done
exec bash "$FM_CAPTAIN_CANNED_SELF" __canned "$FM_CAPTAIN_CANNED_SCN" "$FM_CAPTAIN_CANNED_VARIANT" "$sess"
SH
  chmod +x "$1"
}

ONLY=()
if [ "${1:-}" = __canned ]; then canned_main "$2" "$3" "$4"; exit 0; fi
command_selftest=0
if [ "${1:-}" = selftest ]; then command_selftest=1; ONLY=("${@:2}"); fi
if [ "${FM_CAPTAIN_LIVE_SKIP_SELFTEST:-}" != 1 ] || [ "$command_selftest" -eq 1 ]; then
  ( selftest_fake_omp; exit "$failed" ) || failed=1
  ( selftest_scenarios; exit "$failed" ) || failed=1
fi
if [ "$command_selftest" -eq 1 ]; then
  printf '\nCAPTAIN LIVE SELFTEST %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
  [ "$failed" -eq 0 ]; exit $?
fi
if [ "${FM_CAPTAIN_LIVE:-}" != 1 ]; then
  printf 'SKIP - live Captain suite: set FM_CAPTAIN_LIVE=1 to run a real Captain model with your existing omp login; never reported as PASS\n\nCAPTAIN LIVE SELFTEST %s, LIVE SKIPPED\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
  [ "$failed" -eq 0 ]; exit $?
fi
if ! command -v "$OMP_BIN" >/dev/null 2>&1 || ! "$OMP_BIN" models --json --no-extensions 2>/dev/null | grep -q "\"selector\":\"$MODEL\""; then
  printf 'SKIP - live Captain suite: needs omp with %s available from the existing login; never reported as PASS\n' "$MODEL"
  exit 0
fi
AGENTS_USED=$(find_agents_md) || AGENTS_USED='NONE FOUND (this run has no official AGENTS.md)'
STAMP=$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM
ART="$ART_ROOT/$STAMP"
mkdir -p "$ART"
printf '# Live Captain results (%s, model %s, thinking %s, %s)\n\nofficial AGENTS.md: %s\nconfig checkout: %s\n\n| run | verdict | launches | tool calls | run USD | cumulative USD | secs | note |\n|---|---|---|---|---|---|---|---|\n' "$STAMP" "$MODEL" "$THINKING" "$([ "$CONTROL" = 1 ] && echo 'NEGATIVE CONTROL: standing rule removed' || echo "real context${FM_CAPTAIN_LIVE_POLICY:+, WHAT-IF POLICY OVERRIDE: $FM_CAPTAIN_LIVE_POLICY}")" "$AGENTS_USED" "$CONFIG_ROOT" > "$ART/results.md"
if [ "$#" -gt 0 ]; then cases=("$@"); else cases=("$CASES_DIR"/*.sh); fi
for c in "${cases[@]}"; do
  case $c in */*) ;; *) c="$CASES_DIR/${c%.sh}.sh" ;; esac
  [ -f "$c" ] || { fail "no such scenario: $c"; continue; }
  name=$(basename "$c" .sh)
  if [ "$CONTROL" = 1 ] && [ "$(. "$c"; printf '%s' "${SCN_CONTROL:-0}")" != 1 ]; then skip "$name: not a workflow scenario, not part of the negative control"; continue; fi
  i=1
  while [ "$i" -le "$REPEAT" ]; do
    if over_budget; then fail "$name: budget $BUDGET USD reached (spent $SPENT); run not started"; break; fi
    label=$name-r$i; [ "$CONTROL" != 1 ] || label=control-$name-r$i
    attempt=0; vlabel=$label
    while :; do
      run_one "$c" "$vlabel" "$CONTROL"
      printf '%s\n' "$RUNROW" >> "$ART/results.md"
      [ "$LAST_VERDICT" = INVALID ] && [ "$attempt" -lt 2 ] || break
      attempt=$((attempt + 1)); vlabel=$label-again$attempt
    done
    if [ "$LAST_VERDICT" = INVALID ]; then fail "live $label: INVALID three times (omp killed by a signal each time)"
    elif [ "$CONTROL" = 1 ]; then printf 'info - %s: %s\n' "$label" "$(head -1 "$ART/$vlabel/grade.txt")"
    elif [ "$LAST_VERDICT" = PASS ]; then pass "live $label: $(grep -c '^ok' "$ART/$vlabel/grade.txt") checks held ($(n_launched) launch(es), $(cat "$ART/$vlabel/cost.txt") USD)"
    else fail "live $label: $(grep '^FAIL' "$ART/$vlabel/grade.txt" | cut -c1-160 | tr '\n' ' ')"; fi
    rm -rf "$SCR"
    i=$((i + 1))
  done
done
printf '\n%s\n' "$(cat "$ART/results.md")"
printf 'artifacts: %s  model: %s (thinking %s)  total cost: %s USD (budget %s)\n' "$ART" "$MODEL" "$THINKING" "$SPENT" "${BUDGET:-none}"
printf '\nCAPTAIN LIVE %s\n' "$([ "$CONTROL" = 1 ] && echo 'CONTROL (informational)' || ([ "$failed" -eq 0 ] && echo PASS || echo FAIL))"
[ "$CONTROL" = 1 ] || [ "$failed" -eq 0 ]
