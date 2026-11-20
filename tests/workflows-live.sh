#!/usr/bin/env bash
# workflows-live.sh - opt-in LIVE proof that the workflows (workflows/*.json, engine bin/fm-workflow) drive
# real workers through their loops. For each characteristic problem in
# tests/live-workflows/, a thin driver plays the Captain MECHANICALLY: it asks
# bin/fm-workflow for the next step, launches one real worker (omp, a real model) per
# step with that step's spec, role handoff and inputs, records the outcome in the engine, and
# repeats until the workflow completes or escalates. Every work step names its output contract
# and the driver honours it: result (implementer, step-back) / verdict (qa, review, verify-review,
# security, verify-security, ship) / risk (classify) steps are recorded with --report <the worker's
# final report> and the engine parses the outcome from the fenced block that ends it; a report step
# (the planner) is recorded with --outcome done|blocked and the plan file as --report; the decision
# step (redirect) is answered mechanically with `escalate` unless the case names another choice (CASE_DECIDE_REDIRECT, and
# CASE_DECIDE for research-decide's decide step; both with CASE_DECIDE_REASON); deliver is recorded, never performed. A report step
# (researcher, architect) ends its report with `status: done|blocked|change-direction` on a line of its own; the driver records that.
# Workers see only a sanitized copy of the checkout (roles, bin, workflows, skills; no tests/, no .git), so they cannot read the
# judge. Then it grades from the engine's state, the transcripts and the final fixture repository.
#
# What this proves: roles, block contracts, handoff and loop mechanics hold with real
# workers: QA failing a change and the implementer fixing it from QA's feedback, a review
# finding that only the reviewer catches going through the finding-verifier back to the implementer
# (who gets the verifier's CONFIRMED list, not the raw review), a plan reaching every later step, and
# (control) the same fix round WITHOUT the forcing input not producing the fix. Every fix re-runs
# classify, qa and review. What it cannot prove: that a Captain MODEL chooses the right
# workflow (the driver picks the workflow named by the case), or judges a change of direction well
# (the driver always escalates), or that PRs get opened (the fixture has no remote; delivery is
# recorded, never performed). One run per case: evidence, not a guarantee.
#
# Usage:
#   tests/workflows-live.sh                 offline self-test (canned fake workers, no model); live SKIPs
#   FM_WORKFLOW_LIVE=1 tests/workflows-live.sh [case...]    run the live cases (default: all)
#   tests/workflows-live.sh selftest        only the offline self-test
#
# Environment (live): same in-place omp login rules as tests/roles-live.sh - HOME is not
# redirected, no credential is exported, copied, logged or stored (artifacts are scrubbed).
#   FM_WORKFLOW_LIVE=1                 required opt-in
#   FM_WORKFLOW_LIVE_MODEL             default anthropic/claude-sonnet-5-5
#   FM_WORKFLOW_LIVE_THINKING          default medium
#   FM_WORKFLOW_LIVE_BUDGET            optional total USD cap (default none; a running tally is kept)
#   FM_WORKFLOW_LIVE_RUN_CAP           optional per-worker USD cap passed to omp --max-cost
#   FM_WORKFLOW_LIVE_MAX_WORKERS       hard stop on workers per case (default 24)
#   FM_WORKFLOW_LIVE_TIMEOUT           seconds per worker (default 900)
#   FM_WORKFLOW_LIVE_SKILL_SRC         read-only source of installed skills (default ~/.agents/skills)
# Artifacts (git-ignored): tests/live-artifacts/<stamp>/<case>/ - state file, per-step spec,
# prompt, transcript, parsed calls/final/cost, grade.md; results.md at the top.
#
# Case file contract (tests/live-workflows/<case>.sh, sourced in a subshell):
#   CASE_WORKFLOW, CASE_TASK, CASE_EXPECT_PATH (ERE over "step:outcome step:outcome ..."; the outcome of
#   the classify step is its tier word, of a verdict step pass|fail, of the planner done),
#   CASE_CONTROL_STEP / CASE_CONTROL_RUN / CASE_CONTROL_STRIP (feedback|plan), CASE_FORCE_AFTER
#   (step:run whose hidden check must FAIL, or empty), CASE_FORCE_KIT_PASS (1: QA's kit alone passes then);
#   case_setup (cwd = the fixture repo), case_kit_setup <dir>, case_extra <step> <role> <iter> <kit> <cwd> <run>,
#   case_hidden <repo> <kit> (0 = acceptance satisfied), case_kit_only <repo> <kit>, case_assert <run> <repo>,
#   case_canned <role> <prompt> <cwd> (offline stand-in worker; tests/live-lib/canned.sh answers the roles
#   a case does not customise and builds the result/verdict/risk blocks).
#   CASE_NEEDS (tools that must be on PATH, else the case is SKIPPED, never passed), CASE_DECIDE_REDIRECT / CASE_DECIDE / CASE_DECIDE_REASON
#   (the mechanical answers to the redirect / other decision steps; default escalate), CASE_EXPECT_STATUS (default complete),
#   CASE_NO_CONTROL=1 (the hidden check is the judge), CASE_NEGATIVE (lines "<fake-mode> => <ERE>": the offline self-test plays a canned
#   worker that skips the property the case is built to catch (FAKE_MODE) and the case must FAIL with a grade.md line matching the ERE),
#   case_serve <repo> <aux> (optional: start services, background pids appended to <aux>/pids, print KEY=VALUE lines that go into every
#   worker environment and are readable by case_extra via svc_get KEY), case_stop <aux> (optional), case_canned_pre <role> <prompt> <cwd>
#   (consulted before canned.sh; return 1 for the roles it does not answer).
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$CONFIG_ROOT/bin/fm-workflow"
CASES_DIR="$CONFIG_ROOT/tests/live-workflows"
ART_ROOT="$CONFIG_ROOT/tests/live-artifacts"
MODEL="${FM_WORKFLOW_LIVE_MODEL:-anthropic/claude-sonnet-5-5}"
THINKING="${FM_WORKFLOW_LIVE_THINKING:-medium}"
BUDGET="${FM_WORKFLOW_LIVE_BUDGET:-}"
RUN_CAP="${FM_WORKFLOW_LIVE_RUN_CAP:-}"
MAX_WORKERS="${FM_WORKFLOW_LIVE_MAX_WORKERS:-24}"
COST_ARGS=()
[ -z "$RUN_CAP" ] || COST_ARGS=(--max-cost "$RUN_CAP")
SKILL_SRC="${FM_WORKFLOW_LIVE_SKILL_SRC:-$HOME/.agents/skills}"
OMP_BIN="${FM_WORKFLOW_LIVE_OMP:-omp}"
WORKER_TIMEOUT="${FM_WORKFLOW_LIVE_TIMEOUT:-900}"
SYSTEM_PROMPT='You are a coding worker. Use your tools. Follow the Firstmate spec exactly, including every read-and-apply requirement, then finish with a short final report.'

# shellcheck source=tests/live-lib/session.sh
. "$CONFIG_ROOT/tests/live-lib/session.sh"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }

SPENT=0
spent_add() { SPENT=$(python3 -c 'import sys; print("%.6f" % (float(sys.argv[1]) + float(sys.argv[2])))' "$SPENT" "$1"); }
over_budget() { [ -n "$BUDGET" ] && python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)' "$SPENT" "$BUDGET"; }

# build_prompt <intent> <spec>: the brief a worker gets - the Captain's intent, then the
# Firstmate spec exactly as the engine printed it (it carries the role handoff).
build_prompt() {
  printf '# Task\n\n## Captain'"'"'s intent\n%s\n\n## Firstmate spec\n%s\n\n' "$1" "$2"
  printf 'Pre-work: run pwd -P and git rev-parse --show-toplevel (they must match), then read every path named above with your file read tool before the first edit and before any shell work.\nApply each skill'"'"'s procedure step by step. Work only inside this repository, with no network and no package installs. Deliver results in your final message; create files only where the task names them. Be economical: aim for at most 30 tool calls. End with a short final report.\n'
}

# run_omp <cwd> <prompt-file> <session-dir> <stdout> <stderr>
run_omp() {
  ( cd "$1" && env -i HOME="$HOME" PATH="$PATH" TERM=dumb LANG=C.UTF-8 OMP_SKIP_SETUP=1 PYTHONDONTWRITEBYTECODE=1 ${SVC_ENV_LINES:-} \
      timeout "$WORKER_TIMEOUT" "$OMP_BIN" -p --model "$MODEL" --thinking "$THINKING" --no-extensions --no-skills --no-rules --no-context-files \
      --no-lsp --no-pty --no-title --tools read,grep,glob,bash,edit,write --system-prompt "$SYSTEM_PROMPT" \
      --session-dir "$3" ${COST_ARGS[@]+"${COST_ARGS[@]}"} --auto-approve --cwd "$1" "@$2" > "$4" 2> "$5" )
}

# sealed_clone <dest> [<rev>]: a clone of the fixture repository with no way back to it. With a <rev> the
# clone's history ends at that commit: branches, tags and every later object are gone, so a worker started
# from an earlier state cannot find what happened after it (the control must not see the main run's fix).
sealed_clone() {
  git clone -q --no-hardlinks "$REPO" "$1" && git -C "$1" remote remove origin \
    && git -C "$1" config user.email live@example.invalid && git -C "$1" config user.name live || return 1
  [ -n "${2:-}" ] || return 0
  git -C "$1" checkout -q -B "$(git -C "$1" symbolic-ref --short HEAD)" "$2" && { git -C "$1" tag -l | xargs -r git -C "$1" tag -d >/dev/null; } \
    && git -C "$1" for-each-ref --format='%(refname)' refs/remotes | xargs -r -n1 git -C "$1" update-ref -d \
    && git -C "$1" reflog expire --expire=now --all && git -C "$1" gc -q --prune=now
}

# --- the oracle's lifetime and the oracle-hunting detector ------------------------------------------
# The QA kit (the hidden oracle) is materialized into $KIT only while a QA worker runs it, or the driver itself runs case_hidden /
# case_kit_only / case_assert, and removed right after; a worker that follows a path from QA's feedback or searches the disk finds an
# empty directory.
kit_close() { [ -n "${KIT:-}" ] && [ -d "$KIT" ] && find "$KIT" -mindepth 1 -delete 2>/dev/null; return 0; }
kit_open() { kit_close; ! declare -F case_kit_setup >/dev/null || case_kit_setup "$KIT"; }
hidden_check() { local rc; kit_open; case_hidden "$@"; rc=$?; kit_close; return $rc; }
kit_only_check() { local rc; kit_open; case_kit_only "$@"; rc=$?; kit_close; return $rc; }
# What counts as going looking for the oracle (any worker but QA, whose job is to run its kit): the kit directory or its file names, the
# case files and judges of this repository, the artifact tree, or a scan of the scratch parent / the filesystem root.
HUNT_RE='fm-wf-live-(kit|prompts|sessions|ctl)|(^|[^A-Za-z0-9_])kit\.(py|js)|tests/live[-/]|live-artifacts|(^|[^A-Za-z0-9_])(find|ls|fd|du|tree)[^;&|]*[ "]((/|/var|/var/folders[^ "]*|/private[^ "]*|/tmp|/tmp/|\$TMPDIR|\$\{TMPDIR[^ "]*)[ "]|/var/folders|/private/var)'
hunt_scan() { # <step-dir>: the calls of that worker that look like a hunt for the oracle
  local f
  for f in "$1/calls.tsv" "$1/subcalls.tsv"; do [ -f "$f" ] && grep -aiE "$HUNT_RE" "$f" | cut -c1-220; done
  return 0
}
grade_hunt() { # ok/FAIL lines: no non-QA worker went looking for the oracle
  local d role hits roles i=0 n=0
  roles=$(jq -r '. as $st | .history[] | select($st.definition.steps[.step].kind == "work") | $st.definition.roles[$st.definition.steps[.step].role]' "$STATE" 2>/dev/null)
  for d in "$RUN"/steps/[0-9][0-9]-*; do
    [ -d "$d" ] || continue
    i=$((i + 1)); role=$(printf '%s\n' "$roles" | sed -n "${i}p")
    [ "$role" != qa ] || continue
    n=$((n + 1)); hits=$(hunt_scan "$d")
    [ -z "$hits" ] || printf 'FAIL - worker %s (%s) went looking for the oracle: %s\n' "$(basename "$d" | cut -c1-2)" "$role" "$(printf '%s' "$hits" | head -1)"
  done
  printf 'ok   - no non-QA worker (%d checked) went looking for the oracle (kit dir, case files, artifacts, scratch scans)\n' "$n"
}
# --- the driver ------------------------------------------------------------------------
# One worker step. Globals: RUN REPO DATA KIT STATE BASE0 N.
worker_step() { # <role> <step> <iteration> <output-contract: result|verdict|risk|report>
  local role=$1 step=$2 iter=$3 output=$4 sd spec extra intent cwd rc head prev outcome committer rep
  sd="$RUN/steps/$(printf '%02d' "$N")-$step"
  mkdir -p "$sd" "$RUN/runs/$step:$iter" "$SCR_SESSIONS/$N"
  spec=$("$W" next "$CASE_WORKFLOW" "$STATE" --spec) || { DRIVE_ERR="no spec for step $step"; return 1; }
  printf '%s\n' "$spec" > "$sd/spec.txt"
  # a step the definition lets commit (commits: true) works IN the task repository; every other step - verdicts, the
  # classification, reports, the step-back - works in its own sealed clone and can change nothing the task keeps
  committer=$(jq -r --arg s "$step" '.definition.steps[$s].commits // false' "$STATE")
  if [ "$committer" = true ]; then cwd=$REPO; else cwd="$SCR_REPO/ws/$N"; sealed_clone "$cwd"; fi
  prev=$(git -C "$REPO" rev-parse HEAD)
  extra=$(case_extra "$step" "$role" "$iter" "$KIT" "$cwd" "$DATA" 2>/dev/null || true)
  intent=$CASE_TASK
  [ -z "$extra" ] || intent="$intent

$extra"
  build_prompt "$intent" "$spec" > "$SCR_PROMPTS/$N.md"
  cp "$SCR_PROMPTS/$N.md" "$sd/prompt.md"
  printf '%s\n' "$prev" > "$RUN/runs/$step:$iter/base_head"
  cp "$sd/spec.txt" "$RUN/runs/$step:$iter/spec.txt"
  printf '%s\n' "$intent" > "$RUN/runs/$step:$iter/intent.txt"
  if over_budget; then DRIVE_ERR="budget $BUDGET USD reached (spent $SPENT)"; return 1; fi
  [ "$role" != qa ] || kit_open   # the oracle exists on disk only while a QA worker runs it
  run_omp "$cwd" "$SCR_PROMPTS/$N.md" "$SCR_SESSIONS/$N" "$sd/stdout.txt" "$sd/stderr.txt"; rc=$?
  kit_close
  printf '%s\n' "$rc" > "$sd/rc"
  cp -r "$SCR_SESSIONS/$N" "$sd/session"
  parse_session "$sd/session" "$sd"
  spent_add "$(cat "$sd/cost.txt")"
  [ -s "$sd/final.txt" ] || printf 'The worker produced no report (omp exit %s).\n' "$rc" > "$sd/final.txt"
  # the report file the engine records (and later steps are handed to read) lives in the scratch data folder, never in the artifacts
  mkdir -p "$DATA/reports"; rep="$DATA/reports/$(printf '%02d' "$N")-$step.txt"; cp "$sd/final.txt" "$rep"
  if [ "$committer" = true ] && [ -n "$(git -C "$REPO" status --porcelain)" ]; then
    git -C "$REPO" add -A && git -C "$REPO" commit -q -m "driver: the worker left changes uncommitted" && printf 'yes\n' > "$sd/autocommit"
  fi
  case $output in
    result|verdict|risk)
      # the outcome is parsed by the engine from the final fenced block of the worker's own report
      "$W" next "$CASE_WORKFLOW" "$STATE" --report "$rep" > "$sd/next.json" 2>&1 || { DRIVE_ERR="engine refused the result of $step: $(cat "$sd/next.json")"; return 1; } ;;
    *)
      if [ "$role" = planner ]; then
        if [ "$rc" -eq 0 ] && [ -s "$DATA/plan.md" ]; then outcome=done; else outcome=blocked; fi
        "$W" next "$CASE_WORKFLOW" "$STATE" --outcome "$outcome" --report "$DATA/plan.md" > "$sd/next.json" 2>&1 \
          || "$W" next "$CASE_WORKFLOW" "$STATE" --outcome blocked > "$sd/next.json" 2>&1 \
          || { DRIVE_ERR="engine refused the result of $step: $(cat "$sd/next.json")"; return 1; }
      else
        outcome=done; [ "$rc" -eq 0 ] || outcome=blocked
        # a report step ends with its status on a first line: status: done|blocked|change-direction (the researcher, the architect)
        if [ "$rc" -eq 0 ]; then
          case $(grep -m1 -iE '^[*`# ]*status: *(done|blocked|change-direction)' "$sd/final.txt" | tr 'A-Z' 'a-z') in
            *"status: blocked"*) outcome=blocked ;; *"status: change-direction"*) outcome=change-direction ;;
          esac
        fi
        "$W" next "$CASE_WORKFLOW" "$STATE" --outcome "$outcome" --report "$rep" > "$sd/next.json" 2>&1 || { DRIVE_ERR="engine refused the result of $step: $(cat "$sd/next.json")"; return 1; }
      fi ;;
  esac
  if [ "$committer" = true ]; then
    # the hidden acceptance check after every committing step (it is what the cases force and grade)
    hidden_check "$REPO" "$KIT" > /dev/null 2>&1; printf '%s\n' "$?" > "$RUN/runs/$step:$iter/hidden.rc"
    cp "$RUN/hidden.last" "$RUN/runs/$step:$iter/hidden.txt" 2>/dev/null
    kit_only_check "$REPO" "$KIT" >/dev/null 2>&1; printf '%s\n' "$?" > "$RUN/runs/$step:$iter/kit.rc"
  fi
  return 0
}

# A decision step is answered MECHANICALLY with the choice the case names: the `redirect` decision (a worker raised a change of
# direction) with CASE_DECIDE_REDIRECT, every other decision (research-decide's `decide`) with CASE_DECIDE; both default to
# `escalate`, so a case that does not expect a decision never changes direction. A Captain model would judge.
decision_step() { # <step>
  local step=$1 choice reason
  if [ "$step" = redirect ]; then choice=${CASE_DECIDE_REDIRECT:-escalate}; else choice=${CASE_DECIDE:-escalate}; fi
  reason=${CASE_DECIDE_REASON:-"mechanical rule: the live cases must not change direction, so a raised change of direction is escalated to the human"}
  "$W" next "$CASE_WORKFLOW" "$STATE" --decide "$choice" --reason "$reason" > "$RUN/steps/decision-$step.json" 2>&1 \
    || { DRIVE_ERR="engine refused the decision: $(cat "$RUN/steps/decision-$step.json")"; return 1; }
  printf '%s\n' "$choice" > "$RUN/steps/decision-$step.choice"
}

# Services a case needs while its workers run (case hook): case_serve <repo> <aux-dir> starts them (background pids appended to
# <aux-dir>/pids, logs in <aux-dir>) and prints KEY=VALUE lines (no spaces in a value); the lines are put in every worker's
# environment (a worker's bash sees APP_URL=... and a unique CHROME_DEVTOOLS_AXI_SESSION=...) and are readable by case_extra
# through svc_get KEY. case_stop <aux-dir> (optional) stops what the pids cannot (a browser session).
svc_get() { printf '%s\n' "${SVC_ENV_LINES:-}" | sed -n "s/^$1=//p" | head -1; }
svc_stop() {
  local p
  [ -n "${SCR_AUX:-}" ] || return 0
  ! declare -F case_stop >/dev/null || case_stop "$SCR_AUX" >/dev/null 2>&1
  if [ -f "$SCR_AUX/pids" ]; then while read -r p; do kill "$p" >/dev/null 2>&1; done < "$SCR_AUX/pids"; : > "$SCR_AUX/pids"; fi
  return 0
}

drive() {
  local s
  # Everything a worker can reach from its working directory lives in scratch directories OUTSIDE the
  # artifacts and the config repository: the repo and its clones, and (each in its own directory, so
  # `ls ..` shows nothing else) the QA kit, the data folder, the skills home and the prompts/sessions.
  # Only what the spec and the Captain's intent hand a worker is reachable; the artifacts are copied
  # out after the run.
  local tmp=${TMPDIR:-/tmp}
  SCR_REPO=$(mktemp -d "$tmp/fm-wf-live-repo.XXXXXX"); SCR_KIT=$(mktemp -d "$tmp/fm-wf-live-kit.XXXXXX")
  SCR_DATA=$(mktemp -d "$tmp/fm-wf-live-data.XXXXXX"); SCR_HOME=$(mktemp -d "$tmp/fm-wf-live-home.XXXXXX")
  SCR_PROMPTS=$(mktemp -d "$tmp/fm-wf-live-prompts.XXXXXX"); SCR_SESSIONS=$(mktemp -d "$tmp/fm-wf-live-sessions.XXXXXX"); SCR_AUX=$(mktemp -d "$tmp/fm-wf-live-aux.XXXXXX")
  REPO="$SCR_REPO/repo"; DATA=$SCR_DATA; KIT=$SCR_KIT; STATE="$DATA/workflow.json"; SVC_ENV_LINES=''
  mkdir -p "$REPO" "$SCR_REPO/ws" "$RUN/steps" "$RUN/runs" "$SCR_HOME/.agents/skills"
  for s in "$SKILL_SRC"/*/; do s=$(basename "$s"); cp -rL "$SKILL_SRC/$s" "$SCR_HOME/.agents/skills/$s" 2>/dev/null; done
  [ ! -d "$(dirname "$SKILL_SRC")/references" ] || cp -rL "$(dirname "$SKILL_SRC")/references" "$SCR_HOME/.agents/references" 2>/dev/null
  printf '%s\n' "$CASE_FILE" > "$RUN/case.path"
  printf '%s\n' "$RUN" > "$SCR_PROMPTS/run.path"
  [ -z "${FAKE_MODE:-}" ] || printf '%s\n' "$FAKE_MODE" > "$RUN/fake.mode"
  ( cd "$REPO" && git init -q . && git config user.email live@example.invalid && git config user.name live \
    && printf '__pycache__/\n*.pyc\n' >> .git/info/exclude && case_setup && git add -A && git commit -q -m fixture ) || { DRIVE_ERR='fixture setup failed'; return 1; }
  BASE0=$(git -C "$REPO" rev-parse HEAD)
  # the kit directory stays EMPTY between the moments the oracle is needed (kit_open / kit_close): nothing for a worker to find
  if declare -F case_serve >/dev/null; then
    SVC_ENV_LINES=$(case_serve "$REPO" "$SCR_AUX") || { DRIVE_ERR='the case services did not start'; return 1; }
    printf '%s\n' "$SVC_ENV_LINES" > "$SCR_AUX/env"
  fi
  # Workers must not reach the judge: the spec's role paths point into a SANITIZED copy of the checkout (no tests/, no .git);
  # the engine binary itself still runs from the real checkout.
  SCR_CFG=$(mktemp -d "$tmp/fm-wf-live-cfg.XXXXXX")
  ( cd "$CONFIG_ROOT" && tar -cf - $(ls -d roles bin firstmate workflows skills REVIEW.md README.md AGENTS.md 2>/dev/null) ) | tar -xf - -C "$SCR_CFG" || { DRIVE_ERR='cannot build the sanitized config copy'; return 1; }
  export FM_CONFIG_ROOT="$SCR_CFG" FM_SKILLS_ROOT="$SCR_HOME/.agents/skills"
  "$W" next "$CASE_WORKFLOW" "$STATE" --task "$CASE_TASK" > "$RUN/start.json" 2>&1 || { DRIVE_ERR="cannot start the workflow: $(cat "$RUN/start.json")"; return 1; }
  N=0
  local out status kind step iter role output
  while :; do
    out=$("$W" next "$CASE_WORKFLOW" "$STATE") || { DRIVE_ERR='engine error'; return 1; }
    status=$(printf '%s' "$out" | jq -r .status)
    [ "$status" = running ] || break
    kind=$(printf '%s' "$out" | jq -r .kind); step=$(printf '%s' "$out" | jq -r .step); iter=$(printf '%s' "$out" | jq -r .iteration)
    case $kind in
      work)
        N=$((N + 1))
        [ "$N" -le "$MAX_WORKERS" ] || { DRIVE_ERR="worker cap $MAX_WORKERS reached"; return 1; }
        role=$(printf '%s' "$out" | jq -r .roleName); output=$(printf '%s' "$out" | jq -r .output)
        worker_step "$role" "$step" "$iter" "$output" || return 1 ;;
      decision) decision_step "$step" || return 1 ;;
      deliver)
        # The fixture has no remote: delivery is recorded, never performed.
        git -C "$REPO" tag -f workflow-delivered >/dev/null 2>&1
        "$W" next "$CASE_WORKFLOW" "$STATE" --outcome done >/dev/null || { DRIVE_ERR='engine refused delivery'; return 1; } ;;
    esac
  done
  return 0
}

# --- grading ---------------------------------------------------------------------------------
# Generic loop evidence, from the engine's state, the per-step artifacts and the final repository.
grade_generic() { # -> lines "ok - ..." / "FAIL - ..." on stdout
  python3 - "$RUN" "$CASE_EXPECT_PATH" "${CASE_EXPECT_STATUS:-complete}" <<'PY'
import json, os, re, sys, glob
run, expect, want_status = sys.argv[1], sys.argv[2], sys.argv[3]
st = json.load(open(os.path.join(run, "data", "workflow.json")))
out = []
def res(ok, text): out.append(("ok   - " if ok else "FAIL - ") + text)
hist = st["history"]
path = " ".join("%s:%s" % (h["step"], h["outcome"]) for h in hist)
res(st["status"] == want_status, "the workflow ended %s" % want_status + ("" if st["status"] == want_status else " (status %s: %s)" % (st["status"], (st.get("escalation") or {}).get("reason"))))
res(re.search(expect, path) is not None, "the path taken matches the expected loop shape: %s" % path)
res(all(h["valid"] for h in hist if "valid" in h), "every worker ended its report with a valid result/verdict/risk block (no parser-FAIL, no redo)")
steps = st["definition"]["steps"]
work = [h for h in hist if steps[h["step"]]["kind"] == "work"]
dirs = sorted(d for d in glob.glob(os.path.join(run, "steps", "[0-9][0-9]-*")))
res(len(dirs) == len(work), "one worker transcript per work step (%d)" % len(work))
roles = st["definition"]["roles"]
for h, d in zip(work, dirs):
    role = roles[steps[h["step"]]["role"]]
    calls = open(os.path.join(d, "calls.tsv"), encoding="utf-8").read() if os.path.exists(os.path.join(d, "calls.tsv")) else ""
    res("/roles/%s/ROLE.md" % role in calls, "%s (%s): the worker read its ROLE.md" % (os.path.basename(d), role))
    prompt = open(os.path.join(d, "prompt.md"), encoding="utf-8").read()
    spec = open(os.path.join(d, "spec.txt"), encoding="utf-8").read().rstrip("\n")
    res(spec in prompt, "%s: the worker's input carries the engine's spec verbatim (role handoff included)" % os.path.basename(d))
# feedback travelled verbatim: after every non-pass verdict, the next worker's spec holds each item the engine
# hands on as recorded (a fail hands on its BLOCKER/IMPORTANT items: QA -> implementer, review -> verify-review,
# verify-review -> implementer; the implementer never receives the reviewer's raw list)
widx = [i for i, h in enumerate(hist) if steps[h["step"]]["kind"] == "work"]
for k, i in enumerate(widx):
    h = hist[i]
    if "feedback" in h and h["outcome"] != "pass" and k + 1 < len(widx) and k + 1 < len(dirs):
        spec = open(os.path.join(dirs[k + 1], "spec.txt"), encoding="utf-8").read()
        items = [it for it in h["feedback"] if h["outcome"] != "fail" or it["severity"] in ("BLOCKER", "IMPORTANT")]
        missing = [it["id"] for it in items if json.dumps(it, ensure_ascii=False, separators=(",", ":")) not in spec]
        res(not missing, "%s's %s feedback reached %s verbatim (%d item(s))%s" % (h["step"], h["outcome"], os.path.basename(dirs[k + 1]), len(items), "" if not missing else " - missing " + ",".join(missing)))
# loop counters never exceed their limits
for name, used in st["loops"].items():
    res(used <= st["definition"]["loops"][name]["maxIterations"], "loop %s used %d of %d" % (name, used, st["definition"]["loops"][name]["maxIterations"]))
print("\n".join(out))
PY
}

strip_input() { # <strip: feedback|plan> <spec-file> -> the spec without that input, on stdout
  case $1 in
    feedback) awk '/^- feedback:/ {skip = 1; next} skip && /^```json$/ {inb = 1; next} skip && inb && /^```$/ {skip = 0; inb = 0; next} skip && inb {next} {print}' "$2" ;;
    plan) grep -v '^- plan:' "$2" ;;
  esac
}

# The control: one worker run of the forced step with the forcing input removed. It must NOT satisfy the hidden check.
run_control() { # sets CONTROL_RC (hidden check rc), CONTROL_NOTE
  local src="$RUN/runs/$CASE_CONTROL_STEP:$CASE_CONTROL_RUN" sd="$RUN/steps/control" cwd spec intent
  CONTROL_RC=''; CONTROL_NOTE=''
  [ -d "$src" ] || { CONTROL_NOTE="the run $CASE_CONTROL_STEP:$CASE_CONTROL_RUN never happened"; return 1; }
  # The control worker, like every worker, sees only its own sealed clone: no origin, no artifacts, no sibling data.
  SCR_CTL=$(mktemp -d "${TMPDIR:-/tmp}/fm-wf-live-ctl.XXXXXX"); cwd="$SCR_CTL/repo"
  mkdir -p "$sd" "$SCR_SESSIONS/control"
  sealed_clone "$cwd" "$(cat "$src/base_head")" || { CONTROL_NOTE='cannot clone the control repository'; return 1; }
  spec=$(strip_input "$CASE_CONTROL_STRIP" "$src/spec.txt")
  intent=$(cat "$src/intent.txt")
  build_prompt "$intent" "$spec" > "$SCR_PROMPTS/control.md"
  cp "$SCR_PROMPTS/control.md" "$sd/prompt.md"
  over_budget && { CONTROL_NOTE='budget reached'; return 1; }
  run_omp "$cwd" "$SCR_PROMPTS/control.md" "$SCR_SESSIONS/control" "$sd/stdout.txt" "$sd/stderr.txt"
  cp -r "$SCR_SESSIONS/control" "$sd/session"
  parse_session "$sd/session" "$sd"
  spent_add "$(cat "$sd/cost.txt")"
  [ -z "$(git -C "$cwd" status --porcelain)" ] || { git -C "$cwd" add -A && git -C "$cwd" commit -q -m "driver: control left changes uncommitted"; }
  hidden_check "$cwd" "$KIT" >/dev/null 2>&1; CONTROL_RC=$?
  cp "$RUN/hidden.last" "$sd/hidden.txt" 2>/dev/null
  return 0
}

run_case() { # <case-file>: drives, grades, controls; appends a results row; returns 0 when everything held
  local case_file=$1 name ok=1 g hidden_final control_text force_text cost0 row_path need
  name=$(basename "$case_file" .sh)
  RUN="$ART/$name"; mkdir -p "$RUN"
  # shellcheck source=/dev/null
  . "$case_file"
  CASE_FILE=$case_file; DRIVE_ERR=''
  trap 'svc_stop; rm -rf "${SCR_REPO:-}" "${SCR_KIT:-}" "${SCR_DATA:-}" "${SCR_HOME:-}" "${SCR_PROMPTS:-}" "${SCR_SESSIONS:-}" "${SCR_CTL:-}" "${SCR_AUX:-}" "${SCR_CFG:-}"' EXIT
  [ ! -f "$ART/.spent" ] || SPENT=$(cat "$ART/.spent")
  cost0=$SPENT
  # a case that needs a tool this machine lacks is SKIPPED (never reported as a pass); the offline self-test plays its workers
  # with canned stand-ins and needs none
  if [ -z "${SELFTEST_MODE:-}" ]; then
    for need in ${CASE_NEEDS:-}; do
      command -v "$need" >/dev/null 2>&1 || { printf 'SKIP - live %s: needs %s on PATH; never reported as PASS\n' "$name" "$need"; printf '| %s | %s | SKIP (needs %s) | - | - | 0 | 0.00 |\n' "$name" "$CASE_WORKFLOW" "$need" >> "$ART/results.md"; return 0; }
    done
  fi
  printf '# case %s (workflow %s)\n\n' "$name" "$CASE_WORKFLOW" > "$RUN/grade.md"
  if ! drive; then
    printf 'FAIL - the driver stopped: %s\n' "$DRIVE_ERR" >> "$RUN/grade.md"; ok=0
  fi
  svc_stop
  [ ! -d "${SCR_AUX:-}" ] || cp -r "$SCR_AUX" "$RUN/aux" 2>/dev/null
  [ ! -s "${STATE:-}" ] || { mkdir -p "$RUN/data"; cp -r "$DATA"/. "$RUN/data"/; cp -r "$REPO" "$RUN/repo"; }
  if [ -s "$STATE" ]; then
    g=$({ grade_generic; grade_hunt; } 2>&1); printf '%s\n' "$g" >> "$RUN/grade.md"
    case $g in *"FAIL - "*) ok=0 ;; esac
    row_path=$(jq -r '[.history[] | "\(.step):\(.outcome)"] | join(" ")' "$STATE")
    # forced: the first implementation must have failed the hidden check (the loop was forced, not hoped for)
    if [ -n "${CASE_FORCE_AFTER:-}" ]; then
      if [ "$(cat "$RUN/runs/$CASE_FORCE_AFTER/hidden.rc" 2>/dev/null)" = 0 ] || [ ! -f "$RUN/runs/$CASE_FORCE_AFTER/hidden.rc" ]; then
        printf 'FAIL - the loop was not forced: the hidden check already held after %s\n' "$CASE_FORCE_AFTER" >> "$RUN/grade.md"; ok=0; force_text='NOT forced'
      else printf 'ok   - the loop was forced: the hidden check FAILED after %s: %s\n' "$CASE_FORCE_AFTER" "$(tr '\n' ' ' < "$RUN/runs/$CASE_FORCE_AFTER/hidden.txt" | cut -c1-200)" >> "$RUN/grade.md"; force_text='forced'; fi
      if [ "${CASE_FORCE_KIT_PASS:-0}" = 1 ]; then
        if [ "$(cat "$RUN/runs/$CASE_FORCE_AFTER/kit.rc" 2>/dev/null)" = 0 ]; then printf 'ok   - QA'"'"'s kit alone passed that implementation (only the reviewer can catch the flaw)\n' >> "$RUN/grade.md"
        else printf 'FAIL - QA'"'"'s kit did not pass the first implementation, so QA (not the reviewer) would catch the problem\n' >> "$RUN/grade.md"; ok=0; fi
      fi
    else force_text='plan-driven'; fi
    if [ "${CASE_EXPECT_STATUS:-complete}" != complete ]; then hidden_final='n/a (stopped by design)'
    elif hidden_check "$REPO" "$KIT" >/dev/null 2>&1; then hidden_final=pass; printf 'ok   - the final repository satisfies the hidden acceptance check\n' >> "$RUN/grade.md"
    else hidden_final=FAIL; ok=0; printf 'FAIL - the final repository does not satisfy the hidden acceptance check: %s\n' "$(tr '\n' ' ' < "$RUN/hidden.last" | cut -c1-300)" >> "$RUN/grade.md"; fi
    kit_open; g=$(case_assert "$RUN" "$REPO" 2>&1); arc=$?; kit_close
    [ "$arc" -eq 0 ] && printf 'ok   - case-specific loop evidence holds\n' >> "$RUN/grade.md" || { printf 'FAIL - %s\n' "$g" >> "$RUN/grade.md"; ok=0; }
    # control
    if [ "${CASE_NO_CONTROL:-0}" = 1 ]; then control_text='n/a (the hidden kit is the judge)'
    elif run_control; then
      if [ "$CONTROL_RC" -ne 0 ]; then control_text='fails (good)'; printf 'ok   - control: the same step WITHOUT the %s did not satisfy the hidden check: %s\n' "$CASE_CONTROL_STRIP" "$(tr '\n' ' ' < "$RUN/steps/control/hidden.txt" | cut -c1-200)" >> "$RUN/grade.md"
      else control_text='PASSES (bad)'; ok=0; printf 'FAIL - control: the same step without the %s ALSO satisfied the hidden check, so the problem does not discriminate\n' "$CASE_CONTROL_STRIP" >> "$RUN/grade.md"; fi
    else control_text="not run: $CONTROL_NOTE"; ok=0; printf 'FAIL - control did not run: %s\n' "$CONTROL_NOTE" >> "$RUN/grade.md"; fi
    if [ -d "$RUN/steps/control" ] && [ -n "$(hunt_scan "$RUN/steps/control")" ]; then ok=0; printf 'FAIL - the control worker went looking for the oracle: %s\n' "$(hunt_scan "$RUN/steps/control" | head -1)" >> "$RUN/grade.md"; fi
  else
    row_path='(no state)'; force_text='-'; hidden_final='-'; control_text='-'
  fi
  local workers; workers=$(find "$RUN/steps" -mindepth 1 -maxdepth 1 -type d -name '[0-9][0-9]-*' 2>/dev/null | wc -l | tr -d ' ')
  local cost; cost=$(python3 -c 'import sys; print("%.2f" % (float(sys.argv[1]) - float(sys.argv[2])))' "$SPENT" "$cost0")
  printf '| %s | %s | %s | %s | %s | %s | %s |\n' "$name" "$CASE_WORKFLOW" "$(printf '%s' "$row_path" | sed 's/|/\\|/g')" "$force_text / hidden $hidden_final" "$control_text" "$workers + control" "$cost" >> "$ART/results.md"
  printf '%s' "$SPENT" > "$ART/.spent"
  [ "$ok" -eq 1 ] && pass "live $name: the loops happened as the engine's state and the transcripts show, and the control did not produce the fix" || fail "live $name: see $RUN/grade.md ($(grep -c '^FAIL' "$RUN/grade.md") failing assertion(s))"
  [ "$ok" -eq 1 ]
}

scrub_artifacts() { # redact anything credential-like from the text artifacts, then count what is left
  # python3, not sed -i: BSD sed (macOS) has neither GNU -i without a suffix nor the I flag, and the scrub must work everywhere
  find "$1" -type f \( -name '*.jsonl' -o -name '*.txt' -o -name '*.md' -o -name '*.tsv' -o -name '*.json' \) -not -path '*/.git/*' -print0 \
    | xargs -0 python3 -c '
import re, sys
pats = [(re.compile(r"sk-[A-Za-z0-9_-]{16,}"), "[redacted]"),
        (re.compile(r"(Bearer|Basic) [A-Za-z0-9._~+/=-]{16,}"), r"\1 [redacted]"),
        (re.compile(r"(\"?(api[_-]?key|access[_-]?token|refresh[_-]?token|authorization|client[_-]?secret)\"?[ \t]*[:=][ \t]*\"?)[A-Za-z0-9._~+/=-]{16,}", re.I), r"\1[redacted]")]
for p in sys.argv[1:]:
    try:
        s = open(p, encoding="utf-8", errors="surrogateescape").read()
    except OSError:
        continue
    t = s
    for rx, rep in pats:
        t = rx.sub(rep, t)
    if t != s:
        open(p, "w", encoding="utf-8", errors="surrogateescape").write(t)
' 
  find "$1" -type f -not -path '*/.git/*' -print0 | xargs -0 -r grep -IlE 'sk-[A-Za-z0-9_-]{16,}|(Bearer|Basic) [A-Za-z0-9._~+/=-]{16,}' 2>/dev/null | wc -l | tr -d ' '
}

# --- offline self-test: the whole driver with canned fake workers --------------------------------
selftest() {
  local t fake c name rc out leftover
  t=$(mktemp -d "${TMPDIR:-/tmp}/fm-wf-live-self.XXXXXX") || return 1
  fake="$t/omp"
  cat > "$fake" <<'SH'
#!/usr/bin/env bash
# fake omp: plays the worker role named in the prompt with the case's canned behaviour.
sess=''; prompt=''; cwd=''
while [ $# -gt 0 ]; do case $1 in --session-dir) sess=$2; shift ;; --cwd) cwd=$2; shift ;; @*) prompt=${1#@} ;; esac; shift; done
role=$(sed -n 's/^Assigned role: //p' "$prompt" | head -1)
run=$(cat "$(dirname "$prompt")/run.path")
# shellcheck disable=SC1090
. "$(cat "$run/case.path")"
FAKE_MODE=$(cat "$run/fake.mode" 2>/dev/null)
# shellcheck disable=SC1090
. "$(dirname "$(cat "$run/case.path")")/../live-lib/canned.sh"
final=$(cd "$cwd" && { { declare -F case_canned_pre >/dev/null && case_canned_pre "$role" "$prompt" "$cwd"; } || canned_common "$role" "$prompt" "$cwd" || case_canned "$role" "$prompt" "$cwd"; })
rolefile=$(grep -A1 '^Role source:' "$prompt" | tail -1 | tr -d ' ')
mkdir -p "$sess"
{
  jq -nc --arg p "$rolefile" '{type: "message", message: {role: "assistant", content: [{type: "toolCall", name: "read", arguments: {path: $p}}], usage: {cost: {total: 0.01}}}}'
  jq -nc --arg t "$final" '{type: "message", message: {role: "assistant", content: [{type: "text", text: $t}], usage: {cost: {total: 0.01}}}}'
} > "$sess/s.jsonl"
SH
  chmod +x "$fake"
  OMP_BIN=$fake; MODEL=fake; SKILL_SRC="$t/skills"; SELFTEST_MODE=1
  mkdir -p "$SKILL_SRC"
  local s
  for s in test-driven-development ponytail verification-before-completion code-review-and-quality ponytail-review karpathy-guidelines spec-driven-development planning-and-task-breakdown; do
    mkdir -p "$SKILL_SRC/$s"; : > "$SKILL_SRC/$s/SKILL.md"
  done
  for c in "$CASES_DIR"/*.sh; do
    name=$(basename "$c" .sh)
    [ "${#SELFTEST_ONLY[@]}" -eq 0 ] || case " ${SELFTEST_ONLY[*]} " in *" $name "*) ;; *) continue ;; esac
    ART="$t/art-$name"; mkdir -p "$ART"; SPENT=0
    printf '| case | workflow | path | forced / hidden | control | workers | USD |\n|---|---|---|---|---|---|---|\n' > "$ART/results.md"
    out=$(run_case "$c" 2>&1); rc=$?
    [ "$rc" -eq 0 ] && pass "selftest $name: the driver runs the whole workflow with canned workers; every loop assertion and the control hold" \
      || { fail "selftest $name: the canned good run did not pass: $out"; cat "$ART/$name/grade.md" 2>/dev/null | grep FAIL; }
    [ "$(jq -r .status "$ART/$name/data/workflow.json" 2>/dev/null)" = "$( . "$c"; printf '%s' "${CASE_EXPECT_STATUS:-complete}" )" ] && pass "selftest $name: the engine state ends as the case expects" || fail "selftest $name: state not as expected"
    grep -q 'forced\|plan-driven' "$ART/results.md" && pass "selftest $name: results row written" || fail "selftest $name: no results row"
  done
  # per-case negative controls: a case lists CASE_NEGATIVE lines "<fake-mode> => <ERE>"; the canned worker then skips the property
  # the case is built to catch (FAKE_MODE), and the case must FAIL with a grade.md line matching the ERE
  local neg mode want
  for c in "$CASES_DIR"/*.sh; do
    name=$(basename "$c" .sh)
    [ "${#SELFTEST_ONLY[@]}" -eq 0 ] || case " ${SELFTEST_ONLY[*]} " in *" $name "*) ;; *) continue ;; esac
    neg=$( . "$c"; printf '%s' "${CASE_NEGATIVE:-}" )
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      mode=${line%% => *}; want=${line#* => }
      ART="$t/art-$name-$mode"; mkdir -p "$ART"; SPENT=0; FAKE_MODE=$mode
      printf '| h |\n|---|\n' > "$ART/results.md"
      out=$(run_case "$c" 2>&1); rc=$?
      unset FAKE_MODE
      [ "$rc" -ne 0 ] && grep -qE "$want" "$ART/$name/grade.md" \
        && pass "selftest $name: a worker that does the wrong thing ($mode) fails the case with: $want" \
        || fail "selftest $name: the $mode negative control was not caught (rc $rc, wanted /$want/)"
    done <<NEG
$neg
NEG
  done
  # negative controls of the harness itself, on the QA-loop case
  if [ -f "$CASES_DIR/qa-loop.sh" ] && { [ "${#SELFTEST_ONLY[@]}" -eq 0 ] || case " ${SELFTEST_ONLY[*]} " in *" qa-loop "*) true ;; *) false ;; esac; }; then
    c="$CASES_DIR/qa-loop.sh"
    for mode in ignore firsttry; do
      ART="$t/art-qa-$mode"; mkdir -p "$ART"; SPENT=0; FAKE_MODE=$mode
      printf '| h |\n|---|\n' > "$ART/results.md"
      out=$(run_case "$c" 2>&1); rc=$?
      unset FAKE_MODE
      case $mode in
        ignore)
          [ "$rc" -ne 0 ] && grep -q 'the workflow ended complete (status escalated' "$ART/qa-loop/grade.md" \
            && pass 'selftest: an implementer that ignores QA feedback ends in an escalation, and the grader fails the case' \
            || fail "selftest: an ignoring implementer was not caught (rc $rc)" ;;
        firsttry)
          [ "$rc" -ne 0 ] && grep -q 'the loop was not forced' "$ART/qa-loop/grade.md" \
            && pass 'selftest: an implementation that satisfies the hidden check at once fails the case as "loop not forced"' \
            || fail "selftest: a first-try-correct implementation was not flagged as unforced (rc $rc)" ;;
      esac
    done
  fi
  # negative controls on the later cases: a symptom fix is caught by the two-order scenario; an implementer that is right at
  # once cannot force the round cap
  if [ -f "$CASES_DIR/bug-fix.sh" ] && { [ "${#SELFTEST_ONLY[@]}" -eq 0 ] || case " ${SELFTEST_ONLY[*]} " in *" bug-fix "*) true ;; *) false ;; esac; }; then
    ART="$t/art-bugfix-clamp"; mkdir -p "$ART"; SPENT=0; FAKE_MODE=clamp
    printf '| h |\n|---|\n' > "$ART/results.md"
    out=$(run_case "$CASES_DIR/bug-fix.sh" 2>&1); rc=$?
    unset FAKE_MODE
    [ "$rc" -ne 0 ] && grep -q 'FAIL - ' "$ART/bug-fix/grade.md" \
      && pass 'selftest: a symptom fix (clamping Stock.release) is rejected by the bug-fix case judge' \
      || fail "selftest: the clamp fix was not caught by the bug-fix case (rc $rc)"
  fi
  if [ -f "$CASES_DIR/round-cap.sh" ] && { [ "${#SELFTEST_ONLY[@]}" -eq 0 ] || case " ${SELFTEST_ONLY[*]} " in *" round-cap "*) true ;; *) false ;; esac; }; then
    ART="$t/art-roundcap-firsttry"; mkdir -p "$ART"; SPENT=0; FAKE_MODE=firsttry
    printf '| h |\n|---|\n' > "$ART/results.md"
    out=$(run_case "$CASES_DIR/round-cap.sh" 2>&1); rc=$?
    unset FAKE_MODE
    [ "$rc" -ne 0 ] && grep -q 'the loop was not forced' "$ART/round-cap/grade.md" \
      && pass 'selftest: an implementer that is right at once does not force the round cap, and the case fails as "loop not forced"' \
      || fail "selftest: a first-try-correct implementer was not flagged by the round-cap case (rc $rc)"
  fi
  # a sealed clone at an earlier commit cannot reach anything later (the control must not see the main run's fix)
  REPO="$t/sealsrc"; git init -q "$REPO" && git -C "$REPO" config user.email a@b && git -C "$REPO" config user.name a
  printf 1 > "$REPO/f" && git -C "$REPO" add -A && git -C "$REPO" commit -q -m first && first=$(git -C "$REPO" rev-parse HEAD)
  printf 2 > "$REPO/f" && git -C "$REPO" commit -qam 'later fix (REV-1)' && later=$(git -C "$REPO" rev-parse HEAD) && git -C "$REPO" tag delivered
  sealed_clone "$t/sealed" "$first"
  [ "$(git -C "$t/sealed" log --all --format=%s | tr '\n' ' ')" = 'first ' ] && ! git -C "$t/sealed" cat-file -e "$later" 2>/dev/null \
    && [ -z "$(git -C "$t/sealed" remote)" ] && [ -z "$(git -C "$t/sealed" tag -l)" ] \
    && pass 'selftest: a sealed clone at an earlier commit has no origin, no tag, and no later commit' || fail 'selftest: the sealed clone still reaches later history'
  # the oracle-hunting detector: it flags every way of looking for the kit, and leaves ordinary work alone
  mkdir -p "$t/hunt/bad" "$t/hunt/good"
  printf 'bash\t{"command": "find / -name kit.py 2>/dev/null"}\nbash\t{"command": "ls -dt /var/folders/x6/T/fm-wf-live-kit.abc"}\nread\t{"path": "/tmp/fm-wf-live-kit.Ab12/kit.py"}\nbash\t{"command": "cat /Users/x/firstmate-config/tests/live-workflows/qa-loop.sh"}\nbash\t{"command": "ls /tmp"}\nbash\t{"command": "ls -la /"}\n' > "$t/hunt/bad/calls.tsv"
  printf 'read\t{"path": "/tmp/fm-wf-live-cfg.X/roles/senior-fullstack/ROLE.md"}\nbash\t{"command": "python3 -m unittest discover -s tests"}\nwrite\t{"path": "tests/test_kit.py"}\nbash\t{"command": "ls /tmp/fm-wf-live-repo.X/ws/3/app"}\nbash\t{"command": "git log --oneline"}\nbash\t{"command": "find . -name *.py"}\n' > "$t/hunt/good/calls.tsv"
  [ "$(hunt_scan "$t/hunt/bad" | wc -l | tr -d ' ')" = 6 ] && [ -z "$(hunt_scan "$t/hunt/good")" ] \
    && pass 'selftest: the oracle-hunting detector flags find /, a scratch ls, kit paths and case files, and leaves ordinary calls alone' \
    || fail "selftest: the hunting detector is off (bad: $(hunt_scan "$t/hunt/bad" | wc -l | tr -d ' ') of 6; good: $(hunt_scan "$t/hunt/good" | wc -l | tr -d ' ') of 0)"
  # the scrubber
  mkdir -p "$t/scrub"
  printf 'token sk-abcdefghijklmnopqrstuvwxyz0123456789 and Authorization: Bearer abcdefghijklmnopqrstuvwx and "api_key": "abcdefghijklmnopqrstuvwxyz"\n' > "$t/scrub/a.txt"
  leftover=$(scrub_artifacts "$t/scrub")
  [ "$leftover" = 0 ] && ! grep -q 'abcdefghijklmnopqrstuvwx' "$t/scrub/a.txt" && pass 'selftest: credential-like strings are scrubbed from artifacts' || fail 'selftest: the scrubber left a credential-like string'
  rm -rf "$t"
  ART=''
}

command_selftest=0
SELFTEST_ONLY=()
if [ "${1:-}" = selftest ]; then command_selftest=1; SELFTEST_ONLY=("${@:2}"); fi
command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || { printf 'SKIP - workflows live: needs jq, python3 and git\n'; exit 0; }
( selftest; exit "$failed" ) || failed=1
if [ "$command_selftest" -eq 1 ]; then
  printf '\nWORKFLOWS LIVE SELFTEST %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
  [ "$failed" -eq 0 ]; exit $?
fi
if [ "${FM_WORKFLOW_LIVE:-}" != 1 ]; then
  printf 'SKIP - live workflow suite: set FM_WORKFLOW_LIVE=1 to run real workers with your existing omp login; never reported as PASS\n\nWORKFLOWS LIVE SELFTEST %s, LIVE SKIPPED\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
  [ "$failed" -eq 0 ]; exit $?
fi
if ! command -v "$OMP_BIN" >/dev/null 2>&1 || ! "$OMP_BIN" models --json --no-extensions 2>/dev/null | grep -q "\"selector\":\"$MODEL\""; then
  printf 'SKIP - live workflow suite: needs omp with %s available from the existing login; never reported as PASS\n' "$MODEL"
  exit 0
fi
STAMP=$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM
ART="$ART_ROOT/$STAMP"
mkdir -p "$ART"
printf '# Live workflow results (%s, model %s, thinking %s)\n\n| case | workflow | path taken (engine state) | loop forced / hidden check | control (forcing input removed) | workers | USD |\n|---|---|---|---|---|---|---|\n' "$STAMP" "$MODEL" "$THINKING" > "$ART/results.md"
if [ "$#" -gt 0 ]; then cases=("$@"); else cases=("$CASES_DIR"/*.sh); fi
for c in "${cases[@]}"; do
  case $c in */*) ;; *) c="$CASES_DIR/${c%.sh}.sh" ;; esac
  [ -f "$c" ] || { fail "no such live case: $c"; continue; }
  ( run_case "$c" ) || failed=1
done
leftover=$(scrub_artifacts "$ART")
printf '\n%s\n' "$(cat "$ART/results.md")"
printf 'artifacts: %s  model: %s (thinking %s)  total cost: %s USD (budget %s)  credential-like strings left after scrubbing: %s\n' "$ART" "$MODEL" "$THINKING" "$(cat "$ART/.spent" 2>/dev/null || echo 0)" "${BUDGET:-none}" "$leftover"
printf '\nWORKFLOWS LIVE %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
