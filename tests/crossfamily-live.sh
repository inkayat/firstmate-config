#!/usr/bin/env bash
# crossfamily-live.sh - opt-in LIVE proof that the workflow mechanics (blocks, handoff, loops) hold when the steps of ONE workflow run on
# DIFFERENT model families, and a measurement of whether an independent family catches what the implementer's own family might miss.
#
# It is the mechanical Captain of tests/workflows-live.sh (ask bin/fm-workflow for the next step, launch ONE real worker with that step's spec,
# record its report, repeat) with one addition: every step's worker runs on the model and harness its PAIRING names, and the judge reads the
# model each step actually ran on from that step's own log (omp session jsonl, claude stream-json, codex rollout) and FAILS the case when any
# step ran on anything else (a silent fallback to another model is a failure, a log without a model is a failure).
#
# Cases (tests/live-crossfamily/; qa-loop and review-loop are snapshot copies of the seeded-defect fixtures of tests/live-workflows/ without the control
# run; a hidden kit and a hidden acceptance check are the deterministic judges, never a model):
#   qa-loop      the natural first implementation fails the hidden QA kit; QA must FAIL it, the implementer fixes from QA's feedback
#   review-loop  the QA kit passes, only the code-reviewer (handed the team checklist) catches the missing audit-trail call; the
#                finding-verifier confirms it; the implementer fixes from the verifier's confirmed list
#   caller-miss  HINT-FREE: the ticket applies an upstream patch that breaks a caller outside the patch (report.py); the reviewer and QA are handed no
#                checklist and no kit item for it, so whichever of them reads the callers catches it - or the defect escapes
# The steps the case measures (CASE_CATCH_STEP) CATCH the seeded defect when they fail the defective commit; the last gate (CASE_ESCAPE_STEP, default
# the last of them) passing it is an ESCAPE, a failure of the case.
#
# Pairings (route = <harness>:<model>; omp reaches both families under the operator's login; claude / codex are the real CLIs):
#   base-claude  every step on Claude (omp)                  base-codex  every step on Codex (omp)       (same-family baselines)
#   A   implementer Claude, every verification step Codex     B   implementer Codex, every verification step Claude        (omp)
#   C1  reviewer Claude, finding-verifier Codex, implementer Codex, qa/classify/ship Claude
#   C2  reviewer Codex, finding-verifier Claude, implementer Claude, qa/classify/ship Codex                                 (omp)
#   X1  implementer on the Claude Code CLI (claude -p), every verification step on the Codex CLI (codex exec)
#   X2  implementer on the Codex CLI, every verification step on the Claude Code CLI
# A pairing also names role pairs whose ACTUAL families (read from the logs) must differ (cross-family pairings) or match (baselines).
#
# Usage:
#   tests/crossfamily-live.sh                         offline self-test (fake omp / claude / codex stand-ins, no model); live SKIPs
#   tests/crossfamily-live.sh selftest                only the offline self-test
#   FM_XF_LIVE=1 tests/crossfamily-live.sh <pairing>:<case> [...]     e.g. A:review-loop base-codex:qa-loop
# Environment (live): the operator's existing logins are used IN PLACE (omp login; claude: keychain via the real HOME; codex: ~/.codex), nothing
# is exported, copied, logged or stored (artifacts are scrubbed). Workers run in a scrubbed environment (env -i) in throwaway directories and
# see only a sanitized copy of the checkout (no tests/, no .git); the claude worker runs --safe-mode (none of the operator's CLAUDE.md, hooks,
# skills, plugins, MCP), the codex worker runs with HOME a scratch directory, --ignore-user-config and --ignore-rules.
#   FM_XF_LIVE=1                 required opt-in
#   FM_XF_CLAUDE_OMP / FM_XF_CODEX_OMP / FM_XF_CLAUDE_CLI / FM_XF_CODEX_CLI    the model ids of the four routes
#                                (anthropic/claude-sonnet-5-5, openai-codex/gpt-6.2-sol, claude-sonnet-5-5, gpt-6.1-sol: the codex CLI refuses gpt-6.2-sol on a ChatGPT login)
#   FM_XF_THINKING (medium)  FM_XF_TIMEOUT (900 s per worker)  FM_XF_MAX_WORKERS (24)  FM_XF_BUDGET (total USD cap)  FM_XF_RUN_CAP (per-worker USD cap)
#   FM_XF_OMP / FM_XF_CLAUDE / FM_XF_CODEX    the binaries (offline self-test: fakes)
#   FM_XF_SKILL_SRC (default: every skill pinned in skills/external.lock, materialized into a temp dir by tests/live-lib/pinned-skills.sh, so a run sees what
#                  install.sh would link whatever this machine has installed)    FM_XF_ART (artifact root, default tests/live-artifacts/xf-<stamp>)
# Artifacts (git-ignored): <art>/<pairing>-<case>/ - state, per-step spec/prompt/route/models/final/calls, grade.md, summary.json; results.md at the top.
# What it cannot prove: that a Captain MODEL picks the workflow (the driver plays the Captain), or that PRs get opened (delivery is recorded, never
# performed). One run is evidence, not a guarantee; the flakiness of a pairing is only visible over repeated runs.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$CONFIG_ROOT/bin/fm-workflow"
CASES_DIR="$CONFIG_ROOT/tests/live-crossfamily"
THINKING="${FM_XF_THINKING:-medium}"
BUDGET="${FM_XF_BUDGET:-}"
RUN_CAP="${FM_XF_RUN_CAP:-}"
MAX_WORKERS="${FM_XF_MAX_WORKERS:-24}"
COST_ARGS=(); COST_ARGS_CLAUDE=()
[ -z "$RUN_CAP" ] || { COST_ARGS=(--max-cost "$RUN_CAP"); COST_ARGS_CLAUDE=(--max-budget-usd "$RUN_CAP"); }
SKILL_SRC="${FM_XF_SKILL_SRC:-}"
OMP_BIN="${FM_XF_OMP:-omp}"; CLAUDE_BIN="${FM_XF_CLAUDE:-claude}"; CODEX_BIN="${FM_XF_CODEX:-codex}"
WORKER_TIMEOUT="${FM_XF_TIMEOUT:-900}"
R_CLAUDE_OMP="omp:${FM_XF_CLAUDE_OMP:-anthropic/claude-sonnet-5-5}"; R_CODEX_OMP="omp:${FM_XF_CODEX_OMP:-openai-codex/gpt-6.2-sol}"
R_CLAUDE_CLI="claude:${FM_XF_CLAUDE_CLI:-claude-sonnet-5-5}"; R_CODEX_CLI="codex:${FM_XF_CODEX_CLI:-gpt-6.1-sol}"
SYSTEM_PROMPT='You are a coding worker. Use your tools. Follow the Firstmate spec exactly, including every read-and-apply requirement, then finish with a short final report.'
EXTRA_WORKER_ENV=''

# shellcheck source=tests/live-lib/session.sh
. "$CONFIG_ROOT/tests/live-lib/session.sh"
# shellcheck source=tests/live-lib/harness.sh
. "$CONFIG_ROOT/tests/live-lib/harness.sh"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }

SPENT=0
spent_add() { SPENT=$(python3 -c 'import sys; print("%.6f" % (float(sys.argv[1]) + float(sys.argv[2])))' "$SPENT" "$1"); }
over_budget() { [ -n "$BUDGET" ] && python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)' "$SPENT" "$BUDGET"; }

# --- pairings ---------------------------------------------------------------------------------------
# pairing_def <name>: sets P_ROUTES (role=route list, "*" default), P_DIFF / P_SAME (role pairs "a/b" whose actual families must differ / match), P_DESC.
# The roles are the engine's role names (build-test-review: senior-fullstack, risk-classifier, qa, code-reviewer, finding-verifier,
# security-engineer, release-engineer).
VERIFIERS='qa code-reviewer risk-classifier release-engineer finding-verifier'
pairs_vs_impl() { local r out=''; for r in $1; do out="$out senior-fullstack/$r"; done; printf '%s' "${out# }"; }
pairing_def() {
  P_ROUTES=''; P_DIFF=''; P_SAME=''; P_DESC=''
  case $1 in
    base-claude) P_ROUTES="*=$R_CLAUDE_OMP"; P_SAME=$(pairs_vs_impl "qa code-reviewer"); P_DESC='all steps Claude (omp)' ;;
    base-codex)  P_ROUTES="*=$R_CODEX_OMP"; P_SAME=$(pairs_vs_impl "qa code-reviewer"); P_DESC='all steps Codex (omp)' ;;
    A)  P_ROUTES="*=$R_CODEX_OMP,senior-fullstack=$R_CLAUDE_OMP"; P_DIFF=$(pairs_vs_impl "$VERIFIERS"); P_DESC='implementer Claude; qa, reviewer, classify, verifier, ship Codex (omp)' ;;
    B)  P_ROUTES="*=$R_CLAUDE_OMP,senior-fullstack=$R_CODEX_OMP"; P_DIFF=$(pairs_vs_impl "$VERIFIERS"); P_DESC='implementer Codex; qa, reviewer, classify, verifier, ship Claude (omp)' ;;
    C1) P_ROUTES="*=$R_CLAUDE_OMP,senior-fullstack=$R_CODEX_OMP,finding-verifier=$R_CODEX_OMP"; P_DIFF='code-reviewer/finding-verifier code-reviewer/senior-fullstack'
        P_DESC='reviewer, qa, classify, ship Claude; finding-verifier and implementer Codex (omp)' ;;
    C2) P_ROUTES="*=$R_CODEX_OMP,senior-fullstack=$R_CLAUDE_OMP,finding-verifier=$R_CLAUDE_OMP"; P_DIFF='code-reviewer/finding-verifier code-reviewer/senior-fullstack'
        P_DESC='reviewer, qa, classify, ship Codex; finding-verifier and implementer Claude (omp)' ;;
    X1) P_ROUTES="*=$R_CODEX_CLI,senior-fullstack=$R_CLAUDE_CLI"; P_DIFF=$(pairs_vs_impl "$VERIFIERS"); P_DESC='implementer on the Claude Code CLI; every verification step on the Codex CLI' ;;
    X2) P_ROUTES="*=$R_CLAUDE_CLI,senior-fullstack=$R_CODEX_CLI"; P_DIFF=$(pairs_vs_impl "$VERIFIERS"); P_DESC='implementer on the Codex CLI; every verification step on the Claude Code CLI' ;;
    selftest-samefamily) [ -n "${SELFTEST_MODE:-}" ] || return 1; P_ROUTES="*=$R_CLAUDE_OMP"; P_DIFF='senior-fullstack/qa'; P_DESC='(self-test) a pairing that claims independence and has none' ;;
    *) return 1 ;;
  esac
}
# family_of <model as the log spells it>: claude | codex | other
family_of() { case $1 in *claude*) printf claude ;; *gpt*|*codex*) printf codex ;; *) printf other ;; esac; }

# build_prompt <intent> <spec>: the brief a worker gets - the Captain's intent, then the Firstmate spec exactly as the engine printed it.
build_prompt() {
  printf '# Task\n\n## Captain'"'"'s intent\n%s\n\n## Firstmate spec\n%s\n\n' "$1" "$2"
  printf 'Pre-work: run pwd -P and git rev-parse --show-toplevel (they must match), then read every path named above with your file read tool before the first edit and before any shell work.\nApply each skill'"'"'s procedure step by step. Work only inside this repository, with no network and no package installs. Deliver results in your final message; create files only where the task names them. Be economical: aim for at most 30 tool calls. End with a short final report.\n'
}

# sealed_clone <dest>: a clone of the fixture repository with no way back to it.
sealed_clone() {
  git clone -q --no-hardlinks "$REPO" "$1" && git -C "$1" remote remove origin \
    && git -C "$1" config user.email live@example.invalid && git -C "$1" config user.name live
}

# --- the oracle's lifetime and the oracle-hunting detector (same rules as tests/workflows-live.sh) ----
kit_close() { [ -n "${KIT:-}" ] && [ -d "$KIT" ] && find "$KIT" -mindepth 1 -delete 2>/dev/null; return 0; }
kit_open() { kit_close; ! declare -F case_kit_setup >/dev/null || case_kit_setup "$KIT"; }
hidden_check() { local rc; kit_open; case_hidden "$@"; rc=$?; kit_close; return $rc; }
kit_only_check() { local rc; kit_open; case_kit_only "$@"; rc=$?; kit_close; return $rc; }
_H_PRE='(^|[^A-Za-z0-9_]|\\n)'; _H_MID='([^;&|\\]|\\")*([ "]|\\")'; _H_TAIL='(/+\*?)?([ "'"'"'\\;&|)]|$)'
_H_ROOTS='/|/var|/private|(/private)?/var/folders(/[A-Za-z0-9_*]+){0,2}(/T)?|\$TMPDIR|\$\{TMPDIR[^}]*\}'
# a bare `ls /tmp` is not a hunt (the kit directory is empty outside QA); find/fd/du/tree over /tmp still is
HUNT_RE='fm-wf-live-(kit|prompts|sessions)|(^|[^A-Za-z0-9_])kit\.(py|js)|(^|[/ ])kit/|tests/live[-/]|live-artifacts|'"${_H_PRE}(find|fd|du|tree)${_H_MID}(${_H_ROOTS}|/tmp)${_H_TAIL}|${_H_PRE}ls${_H_MID}(${_H_ROOTS})${_H_TAIL}"
hunt_scan() { # <step-dir>: the calls of that worker that look like a hunt for the oracle
  local f own
  own=$(basename "$1" | cut -c1-2 | sed 's/^0//')
  for f in "$1/calls.tsv" "$1/subcalls.tsv"; do
    [ -f "$f" ] && sed "s#fm-wf-live-prompts\\.[A-Za-z0-9]*/$own\\.md##g" "$f" | ( shopt -s nocasematch; while IFS= read -r l; do [[ $l =~ $HUNT_RE ]] && printf '%s\n' "${BASH_REMATCH[0]}"; done )
  done
  return 0
}
step_roles() { jq -r '. as $st | .history[] | select($st.definition.steps[.step].kind == "work") | $st.definition.roles[$st.definition.steps[.step].role]' "$STATE" 2>/dev/null; }
grade_hunt() { # ok/FAIL lines: no non-QA worker went looking for the oracle
  local d role hits roles i=0 n=0
  roles=$(step_roles)
  for d in "$RUN"/steps/[0-9][0-9]-*; do
    [ -d "$d" ] || continue
    i=$((i + 1)); role=$(printf '%s\n' "$roles" | sed -n "${i}p")
    [ "$role" != qa ] || continue
    n=$((n + 1)); hits=$(hunt_scan "$d")
    [ -z "$hits" ] || printf 'FAIL - worker %s (%s) went looking for the oracle: %s\n' "$(basename "$d" | cut -c1-2)" "$role" "$(printf '%s' "$hits" | head -1)"
  done
  printf 'ok   - no non-QA worker (%d checked) went looking for the oracle (kit dir, case files, artifacts, scratch scans)\n' "$n"
}

# --- the driver ------------------------------------------------------------------------------
# One worker step. Globals: RUN REPO DATA KIT STATE N ROUTES LAST_HIDDEN.
worker_step() { # <role> <step> <iteration> <output-contract: result|verdict|risk>
  local role=$1 step=$2 iter=$3 output=$4 sd spec extra intent cwd rc prev committer rep route outcome
  case $output in result|verdict|risk) ;; *) DRIVE_ERR="step $step has output $output, which this suite does not drive"; return 1 ;; esac
  route=$(route_for "$ROUTES" "$role"); [ -n "$route" ] || { DRIVE_ERR="no route for role $role"; return 1; }
  sd="$RUN/steps/$(printf '%02d' "$N")-$step"
  mkdir -p "$sd" "$RUN/runs/$step:$iter" "$SCR_SESSIONS/$N"
  printf '%s\n' "$route" > "$sd/route.txt"
  spec=$("$W" next "$CASE_WORKFLOW" "$STATE" --spec) || { DRIVE_ERR="no spec for step $step"; return 1; }
  printf '%s\n' "$spec" > "$sd/spec.txt"
  committer=$(jq -r --arg s "$step" '.definition.steps[$s].commits // false' "$STATE")
  if [ "$committer" = true ]; then cwd=$REPO; else cwd="$SCR_REPO/ws/$N"; sealed_clone "$cwd"; fi
  prev=$(git -C "$REPO" rev-parse HEAD)
  extra=$(case_extra "$step" "$role" "$iter" "$KIT" "$cwd" "$DATA" 2>/dev/null || true)
  if [ "$role" = qa ] && declare -F case_kit_setup >/dev/null; then
    extra="$extra
The acceptance kit is private to QA and is removed when you finish: in your report call it \"the acceptance kit\" and never write its path or its file name (later steps cannot run it); say what each of its checks showed instead."
  fi
  intent=$CASE_TASK
  [ -z "$extra" ] || intent="$intent

$extra"
  build_prompt "$intent" "$spec" > "$SCR_PROMPTS/$N.md"
  cp "$SCR_PROMPTS/$N.md" "$sd/prompt.md"
  printf '%s\n' "$prev" > "$RUN/runs/$step:$iter/base_head"
  cp "$sd/spec.txt" "$RUN/runs/$step:$iter/spec.txt"
  if over_budget; then DRIVE_ERR="budget $BUDGET USD reached (spent $SPENT)"; return 1; fi
  [ "$role" != qa ] || kit_open
  run_worker "$route" "$cwd" "$SCR_PROMPTS/$N.md" "$SCR_SESSIONS/$N" "$sd/stdout.txt" "$sd/stderr.txt"; rc=$?
  kit_close
  printf '%s\n' "$rc" > "$sd/rc"
  cp -r "$SCR_SESSIONS/$N" "$sd/session"
  parse_worker "$route" "$sd/session" "$sd"
  spent_add "$(cat "$sd/cost.txt")"
  [ -s "$sd/final.txt" ] || printf 'The worker produced no report (exit %s).\n' "$rc" > "$sd/final.txt"
  mkdir -p "$DATA/reports"; rep="$DATA/reports/$(printf '%02d' "$N")-$step.txt"; cp "$sd/final.txt" "$rep"
  if [ "$committer" = true ] && [ -n "$(git -C "$REPO" status --porcelain)" ]; then
    git -C "$REPO" add -A && git -C "$REPO" commit -q -m "driver: the worker left changes uncommitted" && printf 'yes\n' > "$sd/autocommit"
  fi
  "$W" next "$CASE_WORKFLOW" "$STATE" --report "$rep" > "$sd/next.json" 2>&1 || { DRIVE_ERR="engine refused the result of $step: $(cat "$sd/next.json")"; return 1; }
  if [ "$committer" = true ]; then
    hidden_check "$REPO" "$KIT" > /dev/null 2>&1; LAST_HIDDEN=$?; printf '%s\n' "$LAST_HIDDEN" > "$RUN/runs/$step:$iter/hidden.rc"
    cp "$RUN/hidden.last" "$RUN/runs/$step:$iter/hidden.txt" 2>/dev/null
    kit_only_check "$REPO" "$KIT" >/dev/null 2>&1; printf '%s\n' "$?" > "$RUN/runs/$step:$iter/kit.rc"
  fi
  # the measured steps on a commit that fails the hidden acceptance check: a step of CASE_CATCH_STEP that does not pass it CATCHES the defect; the
  # CASE_ESCAPE_STEP (default: the last of them) passing it is an ESCAPE
  if [ -n "${CASE_CATCH_STEP:-}" ] && [ "${LAST_HIDDEN:-0}" != 0 ]; then
    outcome=$(jq -r '.history[-1].outcome' "$STATE")
    case " $CASE_CATCH_STEP " in
      *" $step "*)
        if [ "$outcome" != pass ]; then printf '%s\t%s\t%s\n' "$step" "$role" "$route" >> "$RUN/caught.tsv"
        elif [ "$step" = "${CASE_ESCAPE_STEP:-${CASE_CATCH_STEP##* }}" ]; then printf '%s\t%s\t%s\n' "$step" "$role" "$route" >> "$RUN/escapes.tsv"; fi ;;
    esac
  fi
  return 0
}

decision_step() { # <step>: answered MECHANICALLY (escalate), as tests/workflows-live.sh does
  local step=$1 choice=escalate
  "$W" next "$CASE_WORKFLOW" "$STATE" --decide "$choice" --reason "mechanical rule: the live cases must not change direction" > "$RUN/steps/decision-$step.json" 2>&1 \
    || { DRIVE_ERR="engine refused the decision: $(cat "$RUN/steps/decision-$step.json")"; return 1; }
}

drive() {
  local s tmp=${TMPDIR:-/tmp}
  SCR_REPO=$(mktemp -d "$tmp/fm-wf-live-repo.XXXXXX"); SCR_KIT=$(mktemp -d "$tmp/fm-wf-live-kit.XXXXXX")
  SCR_DATA=$(mktemp -d "$tmp/fm-wf-live-data.XXXXXX"); SCR_HOME=$(mktemp -d "$tmp/fm-wf-live-home.XXXXXX")
  SCR_PROMPTS=$(mktemp -d "$tmp/fm-wf-live-prompts.XXXXXX"); SCR_SESSIONS=$(mktemp -d "$tmp/fm-wf-live-sessions.XXXXXX")
  REPO="$SCR_REPO/repo"; DATA=$SCR_DATA; KIT=$SCR_KIT; STATE="$DATA/workflow.json"; LAST_HIDDEN=0
  mkdir -p "$REPO" "$SCR_REPO/ws" "$RUN/steps" "$RUN/runs" "$SCR_HOME/.agents/skills"
  for s in "$SKILL_SRC"/*/; do s=$(basename "$s"); cp -rL "$SKILL_SRC/$s" "$SCR_HOME/.agents/skills/$s" 2>/dev/null; done
  [ ! -d "$(dirname "$SKILL_SRC")/references" ] || cp -rL "$(dirname "$SKILL_SRC")/references" "$SCR_HOME/.agents/references" 2>/dev/null
  printf '%s\n' "$CASE_FILE" > "$RUN/case.path"
  printf '%s\n' "$RUN" > "$SCR_PROMPTS/run.path"
  [ -z "${FAKE_MODE:-}" ] || printf '%s\n' "$FAKE_MODE" > "$RUN/fake.mode"
  ( cd "$REPO" && git init -q . && git config user.email live@example.invalid && git config user.name live \
    && printf '__pycache__/\n*.pyc\n' >> .git/info/exclude && case_setup && git add -A && git commit -q -m fixture ) || { DRIVE_ERR='fixture setup failed'; return 1; }
  # Workers must not reach the judge: the spec's role paths point into a SANITIZED copy of the checkout (no tests/, no .git).
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
        git -C "$REPO" tag -f workflow-delivered >/dev/null 2>&1
        "$W" next "$CASE_WORKFLOW" "$STATE" --outcome done >/dev/null || { DRIVE_ERR='engine refused delivery'; return 1; } ;;
    esac
  done
  return 0
}

# --- grading ---------------------------------------------------------------------------------
# Generic loop evidence, from the engine's state, the per-step artifacts and the final repository (as tests/workflows-live.sh).
grade_generic() {
  python3 - "$RUN" "$CASE_EXPECT_PATH" "${CASE_EXPECT_STATUS:-complete}" "${CASE_CATCH_STEP:-}" <<'PY'
import json, os, re, sys, glob
run, expect, want_status, catch = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
st = json.load(open(os.path.join(run, "data", "workflow.json")))
out = []
def res(ok, text): out.append(("ok   - " if ok else "FAIL - ") + text)
hist = st["history"]
path = " ".join("%s:%s" % (h["step"], h["outcome"]) for h in hist)
res(st["status"] == want_status, "the workflow ended %s" % want_status + ("" if st["status"] == want_status else " (status %s: %s)" % (st["status"], (st.get("escalation") or {}).get("reason"))))
res(re.search(expect, path) is not None, "the path taken matches the expected loop shape: %s" % path)
extra = sum(1 for h in hist if h["step"] == catch and h["outcome"] == "fail") - 1 if catch and " " not in catch else 0
if extra > 0:
    res(True, "extra review-fix rounds beyond the first: %d (the %s step failed %d times; the first failure is the seeded-defect catch)" % (extra, catch, extra + 1))
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
widx = [i for i, h in enumerate(hist) if steps[h["step"]]["kind"] == "work"]
for k, i in enumerate(widx):
    h = hist[i]
    if "feedback" in h and h["outcome"] != "pass" and k + 1 < len(widx) and k + 1 < len(dirs):
        spec = open(os.path.join(dirs[k + 1], "spec.txt"), encoding="utf-8").read()
        items = [it for it in h["feedback"] if h["outcome"] != "fail" or it["severity"] in ("BLOCKER", "IMPORTANT")]
        missing = [it["id"] for it in items if json.dumps(it, ensure_ascii=False, separators=(",", ":")) not in spec]
        res(not missing, "%s's %s feedback reached %s verbatim (%d item(s))%s" % (h["step"], h["outcome"], os.path.basename(dirs[k + 1]), len(items), "" if not missing else " - missing " + ",".join(missing)))
for name, used in st["loops"].items():
    res(used <= st["definition"]["loops"][name]["maxIterations"], "loop %s used %d of %d" % (name, used, st["definition"]["loops"][name]["maxIterations"]))
print("\n".join(out))
PY
}

# The model verdict: every work step's log must show the model and harness its route names - and nothing else. Any other model in the log (a
# fallback, a mixed run) fails; so does a log with no model at all (unverifiable).
grade_models() {
  local d i=0 role route want got bad roles
  roles=$(step_roles)
  for d in "$RUN"/steps/[0-9][0-9]-*; do
    [ -d "$d" ] || continue
    i=$((i + 1)); role=$(printf '%s\n' "$roles" | sed -n "${i}p")
    route=$(route_for "$ROUTES" "$role"); want=$(route_expected "$route")
    got=$(cat "$d/models.txt" 2>/dev/null)
    if [ -z "$got" ]; then printf 'FAIL - worker %s (%s) left no model in its log, so the route %s cannot be verified\n' "$(basename "$d" | cut -c1-2)" "$role" "$route"; continue; fi
    bad=$(printf '%s\n' "$got" | awk -v w="$want" '$0 != w' | tr '\t\n' ': ' | cut -c1-160)
    if [ -n "$bad" ]; then printf 'FAIL - worker %s (%s) ran on %s per its log, but its route is %s\n' "$(basename "$d" | cut -c1-2)" "$role" "$bad" "$route"
    else printf 'ok   - worker %s (%s) ran on %s per its log (harness %s)\n' "$(basename "$d" | cut -c1-2)" "$role" "${route#*:}" "${route%%:*}"; fi
  done
}
# role -> the model its first worker's log shows (empty when the role never ran)
role_model() { # <role>
  local d i=0 role roles
  roles=$(step_roles)
  for d in "$RUN"/steps/[0-9][0-9]-*; do
    [ -d "$d" ] || continue
    i=$((i + 1)); role=$(printf '%s\n' "$roles" | sed -n "${i}p")
    [ "$role" = "$1" ] || continue
    head -1 "$d/models.txt" 2>/dev/null | cut -f2; return 0
  done
}
grade_families() { # P_DIFF / P_SAME role pairs, judged on the families the LOGS show
  local p a b ma mb
  for p in $P_DIFF $P_SAME; do
    a=${p%/*}; b=${p#*/}; ma=$(role_model "$a"); mb=$(role_model "$b")
    { [ -n "$ma" ] && [ -n "$mb" ]; } || continue
    case " $P_DIFF " in
      *" $p "*) [ "$(family_of "$ma")" != "$(family_of "$mb")" ] \
        && printf 'ok   - independence: %s (%s) and %s (%s) ran on different families per the logs\n' "$a" "$(family_of "$ma")" "$b" "$(family_of "$mb")" \
        || printf 'FAIL - independence: %s and %s ran on the SAME family (%s) per the logs, but this pairing is cross-family\n' "$a" "$b" "$(family_of "$ma")" ;;
      *) [ "$(family_of "$ma")" = "$(family_of "$mb")" ] \
        && printf 'ok   - baseline: %s and %s ran on the same family (%s) per the logs\n' "$a" "$b" "$(family_of "$ma")" \
        || printf 'FAIL - baseline: %s (%s) and %s (%s) ran on different families per the logs, but this pairing is a same-family baseline\n' "$a" "$(family_of "$ma")" "$b" "$(family_of "$mb")" ;;
    esac
  done
}

# preflight_route <route>: one trivial worker run on the route; the model must come back as named. Cached per artifact root.
preflight_route() {
  local route=$1 key d p
  key=$(printf '%s' "$route" | tr -c 'A-Za-z0-9' '_')
  [ ! -f "$ART/.pre-$key" ] || return 0
  d=$(mktemp -d "${TMPDIR:-/tmp}/fm-wf-live-pre.XXXXXX"); mkdir -p "$d/repo" "$d/sess"
  SCR_HOME=$d; printf '# Task\n\nRun the shell command `echo READY` in the current directory, then end with a final report that says the single word READY.\n' > "$d/p.md"
  run_worker "$route" "$d/repo" "$d/p.md" "$d/sess" "$d/out" "$d/err"
  parse_worker "$route" "$d/sess" "$d"
  if grep -q READY "$d/final.txt" 2>/dev/null && [ "$(cat "$d/models.txt" 2>/dev/null)" = "$(route_expected "$route")" ]; then
    : > "$ART/.pre-$key"; rm -rf "$d"; return 0
  fi
  p="route $route cannot run here: final=[$(head -c 160 "$d/final.txt" 2>/dev/null)] models=[$(tr '\t\n' ': ' < "$d/models.txt" 2>/dev/null)] stderr=[$(head -c 200 "$d/err" 2>/dev/null)]"
  rm -rf "$d"; PREFLIGHT_ERR=$p; return 1
}

# run_case <pairing> <case-file>: drives, grades; appends a results row; returns 0 when everything held
run_case() {
  local pairing=$1 case_file=$2 name ok=1 g hidden_final force_text cost0 row_path loops caught esc models r arc d
  name="$pairing-$(basename "$case_file" .sh)"
  pairing_def "$pairing" || { fail "no such pairing: $pairing"; return 1; }
  ROUTES=$P_ROUTES
  RUN="$ART/$name"; mkdir -p "$RUN"
  # shellcheck source=/dev/null
  . "$case_file"
  CASE_FILE=$case_file; DRIVE_ERR=''
  trap 'rm -rf "${SCR_REPO:-}" "${SCR_KIT:-}" "${SCR_DATA:-}" "${SCR_HOME:-}" "${SCR_PROMPTS:-}" "${SCR_SESSIONS:-}" "${SCR_CFG:-}"' EXIT
  [ ! -f "$ART/.spent" ] || SPENT=$(cat "$ART/.spent")
  cost0=$SPENT
  printf '# %s: case %s (workflow %s), pairing %s: %s\nroutes: %s\n\n' "$name" "$(basename "$case_file" .sh)" "$CASE_WORKFLOW" "$pairing" "$P_DESC" "$ROUTES" > "$RUN/grade.md"
  if [ -z "${SELFTEST_MODE:-}" ]; then
    for r in $(printf '%s' "$ROUTES" | tr ',' '\n' | sed 's/^[^=]*=//' | sort -u); do
      PREFLIGHT_ERR=''
      preflight_route "$r" || { printf 'SKIP - live %s: %s; never reported as PASS\n' "$name" "$PREFLIGHT_ERR"; printf '| %s | %s | SKIP (%s) | - | - | - | - | 0 | 0.00 | SKIP |\n' "$pairing" "$(basename "$case_file" .sh)" "$r" >> "$ART/results.md"; return 0; }
    done
  fi
  if ! drive; then printf 'FAIL - the driver stopped: %s\n' "$DRIVE_ERR" >> "$RUN/grade.md"; ok=0; fi
  [ ! -s "${STATE:-}" ] || { mkdir -p "$RUN/data"; cp -r "$DATA"/. "$RUN/data"/; cp -r "$REPO" "$RUN/repo"; }
  caught='n/a'; esc=0; models=''; loops=''
  if [ -s "$STATE" ]; then
    g=$({ grade_generic; grade_hunt; grade_models; grade_families; } 2>&1); printf '%s\n' "$g" >> "$RUN/grade.md"
    case $g in *"FAIL - "*) ok=0 ;; esac
    row_path=$(jq -r '[.history[] | "\(.step):\(.outcome)"] | join(" ")' "$STATE")
    loops=$(jq -r '.loops | to_entries | map("\(.key)=\(.value)") | join(" ")' "$STATE")
    if [ -n "${CASE_FORCE_AFTER:-}" ]; then
      if [ "$(cat "$RUN/runs/$CASE_FORCE_AFTER/hidden.rc" 2>/dev/null)" = 0 ] || [ ! -f "$RUN/runs/$CASE_FORCE_AFTER/hidden.rc" ]; then
        printf 'FAIL - the loop was not forced: the hidden check already held after %s (the implementer got it right unaided; nothing was there to catch)\n' "$CASE_FORCE_AFTER" >> "$RUN/grade.md"; ok=0; force_text='NOT forced'
      else printf 'ok   - the loop was forced: the hidden check FAILED after %s: %s\n' "$CASE_FORCE_AFTER" "$(tr '\n' ' ' < "$RUN/runs/$CASE_FORCE_AFTER/hidden.txt" | cut -c1-200)" >> "$RUN/grade.md"; force_text='forced'; fi
      if [ "${CASE_FORCE_KIT_PASS:-0}" = 1 ]; then
        if [ "$(cat "$RUN/runs/$CASE_FORCE_AFTER/kit.rc" 2>/dev/null)" = 0 ]; then printf 'ok   - QA'"'"'s kit alone passed that implementation (only the reviewer can catch the flaw)\n' >> "$RUN/grade.md"
        else printf 'FAIL - QA'"'"'s kit did not pass the first implementation, so QA (not the reviewer) would catch the problem\n' >> "$RUN/grade.md"; ok=0; fi
      fi
    else force_text='-'; fi
    if [ -s "$RUN/escapes.tsv" ]; then
      esc=$(wc -l < "$RUN/escapes.tsv" | tr -d ' '); caught="ESCAPED ($(head -1 "$RUN/escapes.tsv" | awk -F'\t' '{printf "%s by %s on %s", $1, $2, $3}'))"
      printf 'FAIL - ESCAPE: the %s step PASSED a commit that fails the hidden acceptance check (%s): the seeded defect was not caught\n' "$(head -1 "$RUN/escapes.tsv" | cut -f1)" "$(awk -F'\t' '{printf "%s on %s; ", $2, $3}' "$RUN/escapes.tsv")" >> "$RUN/grade.md"; ok=0
    elif [ -s "$RUN/caught.tsv" ]; then
      caught="caught by $(head -1 "$RUN/caught.tsv" | awk -F'\t' '{printf "%s on %s", $2, $3}')"
      printf 'ok   - the seeded defect was caught by the %s step (%s)\n' "$(head -1 "$RUN/caught.tsv" | cut -f1)" "$(head -1 "$RUN/caught.tsv" | awk -F'\t' '{printf "%s on %s", $2, $3}')" >> "$RUN/grade.md"
    fi
    if [ "${CASE_EXPECT_STATUS:-complete}" != complete ]; then hidden_final='n/a'
    elif hidden_check "$REPO" "$KIT" >/dev/null 2>&1; then hidden_final=pass; printf 'ok   - the final repository satisfies the hidden acceptance check\n' >> "$RUN/grade.md"
    else hidden_final=FAIL; ok=0; printf 'FAIL - the final repository does not satisfy the hidden acceptance check: %s\n' "$(tr '\n' ' ' < "$RUN/hidden.last" | cut -c1-300)" >> "$RUN/grade.md"; fi
    kit_open; g=$(case_assert "$RUN" "$REPO" 2>&1); arc=$?; kit_close
    [ "$arc" -eq 0 ] && printf 'ok   - case-specific loop evidence holds\n' >> "$RUN/grade.md" || { printf 'FAIL - %s\n' "$g" >> "$RUN/grade.md"; ok=0; }
    models=$(for d in "$RUN"/steps/[0-9][0-9]-*; do [ -d "$d" ] || continue; printf '%s=%s ' "$(basename "$d" | cut -c4-)" "$(tr '\t\n' ': ' < "$d/models.txt")"; done)
  else
    row_path='(no state)'; force_text='-'; hidden_final='-'
  fi
  local workers cost; workers=$(find "$RUN/steps" -mindepth 1 -maxdepth 1 -type d -name '[0-9][0-9]-*' 2>/dev/null | wc -l | tr -d ' ')
  cost=$(python3 -c 'import sys; print("%.2f" % (float(sys.argv[1]) - float(sys.argv[2])))' "$SPENT" "$cost0")
  printf '| %s | %s | %s | %s | %s / hidden %s | %s | %s | %s | %s | %s |\n' "$pairing" "$(basename "$case_file" .sh)" "$(printf '%s' "$row_path" | sed 's/|/\\|/g')" "$loops" \
    "$force_text" "${hidden_final:--}" "$caught" "$(printf '%s' "$models" | sed 's/|/\\|/g')" "$workers" "$cost" "$([ "$ok" -eq 1 ] && echo PASS || echo FAIL)" >> "$ART/results.md"
  jq -n --arg pairing "$pairing" --arg case "$(basename "$case_file" .sh)" --arg routes "$ROUTES" --arg path "${row_path:-}" --arg loops "$loops" --arg caught "$caught" \
    --argjson escapes "$esc" --arg forced "${force_text:--}" --arg hidden "${hidden_final:--}" --arg models "$models" --arg cost "$cost" --arg verdict "$([ "$ok" -eq 1 ] && echo PASS || echo FAIL)" \
    '{pairing: $pairing, case: $case, routes: $routes, path: $path, loops: $loops, caught: $caught, escapes: $escapes, forced: $forced, hidden: $hidden, models: $models, usd: $cost, verdict: $verdict}' > "$RUN/summary.json"
  printf '%s' "$SPENT" > "$ART/.spent"
  [ "$ok" -eq 1 ] && pass "live $name: mechanics held across the pairing and every step ran on its intended model per its log" || fail "live $name: see $RUN/grade.md ($(grep -c '^FAIL' "$RUN/grade.md") failing assertion(s))"
  [ "$ok" -eq 1 ]
}

scrub_artifacts() { # redact anything credential-like from the text artifacts, then count what is left
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

# --- offline self-test: the whole driver with fake omp / claude / codex stand-ins ---------------------
selftest() {
  local t c name out rc pairing cs want mode s
  t=$(mktemp -d "${TMPDIR:-/tmp}/fm-xf-self.XXXXXX") || return 1
  # one canned worker (fw.sh <harness> <model> <prompt-file> <cwd> <omp-session-dir>) that prints / writes the transcript its harness would
  cat > "$t/fw.sh" <<'SH'
#!/usr/bin/env bash
harness=$1; model=$2; prompt=$3; cwd=$4; sess=${5:-}
role=$(sed -n 's/^Assigned role: //p' "$prompt" | head -1)
run=$(cat "$XF_FAKE_RUNFILE")
# shellcheck disable=SC1090
. "$(cat "$run/case.path")"
FAKE_MODE=$(cat "$run/fake.mode" 2>/dev/null)
# shellcheck disable=SC1090
. "$(dirname "$(cat "$run/case.path")")/../live-lib/canned.sh"
final=$(cd "$cwd" && { canned_common "$role" "$prompt" "$cwd" || case_canned "$role" "$prompt" "$cwd"; })
rolefile=$(grep -A1 '^Role source:' "$prompt" | tail -1 | tr -d ' ')
# the model the LOG will show (the fake stands in for a worker that was silently moved to another model, or that records none)
models=$model
case $FAKE_MODE in
  swap-$role) models=other/impostor-model ;;
  mixed-$role) models="$model other/impostor-model" ;;
  nomodel-$role) models='' ;;
esac
case $harness in
  omp)
    mkdir -p "$sess"
    {
      # one assistant message per model the log is to show (a tool call each), then the final text on the first; no model at all = fields absent
      for m in ${models:-NONE}; do
        jq -nc --arg p "$rolefile" --arg m "$m" '{type: "message", message: ({role: "assistant", content: [{type: "toolCall", name: "read", arguments: {path: $p}}], usage: {cost: {total: 0.01}}}
          + (if $m == "NONE" then {} else {provider: ($m | split("/")[0]), model: ($m | split("/")[1:] | join("/"))} end))}'
      done
      jq -nc --arg t "$final" --arg m "${models%% *}" '{type: "message", message: ({role: "assistant", content: [{type: "text", text: $t}], usage: {cost: {total: 0.01}}}
        + (if $m == "" then {} else {provider: ($m | split("/")[0]), model: ($m | split("/")[1:] | join("/"))} end))}'
    } > "$sess/s.jsonl" ;;
  claude)
    {
      jq -nc --arg m "${models%% *}" '{type: "system", subtype: "init"} + (if $m == "" then {} else {model: $m} end)'
      for m in ${models:-NONE}; do
        jq -nc --arg p "$rolefile" --arg m "$m" '{type: "assistant", message: ({role: "assistant", content: [{type: "tool_use", name: "Read", input: {file_path: $p}}]} + (if $m == "NONE" then {} else {model: $m} end))}'
      done
      jq -nc --arg t "$final" '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: $t}]}}'
      jq -nc --arg t "$final" --arg ms "$models" '{type: "result", subtype: "success", is_error: false, result: $t, total_cost_usd: 0.01, modelUsage: ($ms | split(" ") | map(select(. != "")) | map({key: ., value: {}}) | from_entries)}'
    } ;;
  codex)
    tid="fake-$$-$RANDOM"
    {
      jq -nc --arg i "$tid" '{type: "thread.started", thread_id: $i}'
      jq -nc --arg c "/bin/zsh -lc 'cat $rolefile'" '{type: "item.completed", item: {type: "command_execution", command: $c, aggregated_output: "", exit_code: 0, status: "completed"}}'
      jq -nc --arg t "$final" '{type: "item.completed", item: {type: "agent_message", text: $t}}'
      jq -nc '{type: "turn.completed", usage: {input_tokens: 1, output_tokens: 1}}'
    }
    d="$CODEX_HOME/sessions/2026/11/20"; mkdir -p "$d"
    {
      jq -nc '{type: "session_meta", payload: {model_provider: "openai"}}'
      for m in $models; do jq -nc --arg m "$m" '{type: "turn_context", payload: {model: $m}}'; done
    } > "$d/rollout-2026-11-20T00-00-00-$tid.jsonl" ;;
esac
SH
  chmod +x "$t/fw.sh"
  cat > "$t/omp" <<'SH'
#!/usr/bin/env bash
sess=''; prompt=''; cwd=''; model=''
while [ $# -gt 0 ]; do case $1 in --session-dir) sess=$2; shift ;; --cwd) cwd=$2; shift ;; --model) model=$2; shift ;; @*) prompt=${1#@} ;; esac; shift; done
exec "$XF_FAKE_FW" omp "$model" "$prompt" "$cwd" "$sess"
SH
  cat > "$t/claude" <<'SH'
#!/usr/bin/env bash
model=''
while [ $# -gt 0 ]; do case $1 in --model) model=$2; shift ;; esac; shift; done
p=$(mktemp "${TMPDIR:-/tmp}/fm-xf-fakeprompt.XXXXXX"); cat > "$p"
"$XF_FAKE_FW" claude "$model" "$p" "$PWD"; rc=$?; rm -f "$p"; exit $rc
SH
  cat > "$t/codex" <<'SH'
#!/usr/bin/env bash
model=''; cwd=''
while [ $# -gt 0 ]; do case $1 in -m) model=$2; shift ;; -C) cwd=$2; shift ;; esac; shift; done
p=$(mktemp "${TMPDIR:-/tmp}/fm-xf-fakeprompt.XXXXXX"); cat > "$p"
"$XF_FAKE_FW" codex "$model" "$p" "$cwd"; rc=$?; rm -f "$p"; exit $rc
SH
  chmod +x "$t/omp" "$t/claude" "$t/codex"
  OMP_BIN=$t/omp; CLAUDE_BIN=$t/claude; CODEX_BIN=$t/codex; SKILL_SRC="$t/skills"; SELFTEST_MODE=1
  export CODEX_HOME="$t/codexhome"; mkdir -p "$CODEX_HOME"
  EXTRA_WORKER_ENV="XF_FAKE_RUNFILE=$t/runpath XF_FAKE_FW=$t/fw.sh"
  mkdir -p "$SKILL_SRC"
  for s in test-driven-development ponytail verification-before-completion code-review-and-quality ponytail-review karpathy-guidelines spec-driven-development planning-and-task-breakdown; do
    mkdir -p "$SKILL_SRC/$s"; : > "$SKILL_SRC/$s/SKILL.md"
  done
  st_run() { # <pairing> <case> [fake-mode]: one case run; sets ST_RC, ST_GRADE (grade.md path), ST_ART
    ST_ART="$t/art-$1-$2-${3:-good}"; ART=$ST_ART; mkdir -p "$ART"; SPENT=0; FAKE_MODE=${3:-}
    printf '| h |\n|---|\n' > "$ART/results.md"
    printf '%s\n' "$ART/$1-$2" > "$t/runpath"
    ( run_case "$1" "$CASES_DIR/$2.sh" ) > "$ART/out.txt" 2>&1; ST_RC=$?
    unset FAKE_MODE; ST_GRADE="$ART/$1-$2/grade.md"
  }
  # unit: the route table and the family map
  [ "$(route_for '*=omp:a/b,qa=claude:c' qa)" = claude:c ] && [ "$(route_for '*=omp:a/b,qa=claude:c' code-reviewer)" = omp:a/b ] && [ -z "$(route_for 'qa=claude:c' ship)" ] \
    && pass 'selftest: route_for picks the exact role, then the default, else nothing' || fail 'selftest: route_for is wrong'
  [ "$(family_of anthropic/claude-sonnet-5-5)" = claude ] && [ "$(family_of openai-codex/gpt-6.2-sol)" = codex ] && [ "$(family_of claude-sonnet-5-5)" = claude ] && [ "$(family_of gpt-6.1-sol)" = codex ] \
    && pass 'selftest: family_of maps the four routes of the live pairings' || fail 'selftest: family_of is wrong'
  # good runs: every pairing on the cases it is used with, the three harnesses included
  for cs in A:qa-loop A:review-loop B:review-loop C1:review-loop C2:review-loop base-claude:qa-loop base-codex:review-loop X1:qa-loop X1:review-loop X2:review-loop \
            A:caller-miss B:caller-miss C1:caller-miss base-claude:caller-miss X2:caller-miss; do
    pairing=${cs%%:*}; name=${cs#*:}
    st_run "$pairing" "$name"
    [ "$ST_RC" -eq 0 ] && pass "selftest $pairing/$name: canned workers on the pairing's routes complete the workflow; every loop, model and family assertion holds" \
      || { fail "selftest $pairing/$name: the canned good run did not pass"; grep -h FAIL "$ST_GRADE" "$ST_ART/out.txt" 2>/dev/null | head -5; }
    [ "$(jq -r .verdict "$ST_ART/$pairing-$name/summary.json" 2>/dev/null)" = PASS ] && jq -e '.caught | startswith("caught by")' "$ST_ART/$pairing-$name/summary.json" >/dev/null 2>&1 \
      && pass "selftest $pairing/$name: the summary records the defect as caught" || fail "selftest $pairing/$name: no caught defect in the summary"
  done
  # the routes really reach the harnesses: X1 ran claude for the implementer and codex for the rest (read back from the logs the driver parsed)
  c="$t/art-X1-review-loop-good/X1-review-loop/steps"
  { [ "$(cat "$c"/01-implement/models.txt)" = "$(printf 'claude\t%s' "${R_CLAUDE_CLI#*:}")" ] && [ "$(cat "$c"/03-qa/models.txt)" = "$(printf 'codex\t%s' "${R_CODEX_CLI#*:}")" ] \
    && [ -s "$c/01-implement/session/claude.jsonl" ] && [ -s "$c/03-qa/session/rollout.jsonl" ]; } \
    && pass 'selftest: the claude route is parsed from the claude stream, the codex route from its event stream and rollout' || fail 'selftest: the harness logs of X1 are not what the routes say'
  # negative: a step that ran on the wrong model must FAIL the case, whatever the harness and however it went wrong
  for cs in 'A review-loop swap-qa ran on omp:other/impostor-model' 'A review-loop mixed-code-reviewer ran on omp:other/impostor-model' \
            'A review-loop swap-senior-fullstack ran on omp:other/impostor-model' 'A review-loop nomodel-qa left no model in its log' \
            'X1 review-loop swap-senior-fullstack ran on claude:other/impostor-model' 'X1 qa-loop swap-qa ran on codex:other/impostor-model' 'X2 review-loop nomodel-code-reviewer left no model in its log' \
            'B qa-loop swap-risk-classifier ran on omp:other/impostor-model'; do
    set -- $cs; pairing=$1; name=$2; mode=$3; shift 3; want=$*
    st_run "$pairing" "$name" "$mode"
    [ "$ST_RC" -ne 0 ] && grep -qF -- "$want" "$ST_GRADE" \
      && pass "selftest $pairing/$name: a worker that ran on the wrong model ($mode) fails the case (grade: $want)" \
      || { fail "selftest $pairing/$name: the $mode run was not rejected for its model (rc $ST_RC, wanted: $want)"; grep -h 'ran on\|no model' "$ST_GRADE" | head -3; }
  done
  # negative: the independent family is what the pairing claims, judged on the logs: a cross-family pairing that is not fails
  st_run selftest-samefamily review-loop
  [ "$ST_RC" -ne 0 ] && grep -q 'independence: senior-fullstack and qa ran on the SAME family' "$ST_GRADE" \
    && pass 'selftest: a pairing that claims cross-family and ran on one family fails the independence check' || fail 'selftest: the same-family pairing was not rejected'
  # negative: a verification step that passes the seeded defect is an ESCAPE and fails the case, for each measured step
  for cs in 'A review-loop' 'base-claude review-loop' 'B qa-loop' 'base-codex qa-loop' 'A caller-miss' 'base-codex caller-miss'; do
    set -- $cs; st_run "$1" "$2" blind
    [ "$ST_RC" -ne 0 ] && grep -q 'FAIL - ESCAPE: the ' "$ST_GRADE" && grep -q 'ESCAPED' "$ST_ART/results.md" 2>/dev/null \
      && pass "selftest $1/$2: a blind verifier that passes the seeded defect is an ESCAPE and fails the case" || fail "selftest $1/$2: the blind verifier was not flagged as an escape (rc $ST_RC)"
  done
  # a QA that finds the hint-free defect on its own (the kit does not look at it) is a catch by QA, and the case passes
  st_run B caller-miss qacatch
  [ "$ST_RC" -eq 0 ] && jq -e '.caught | startswith("caught by qa")' "$ST_ART/B-caller-miss/summary.json" >/dev/null 2>&1 \
    && pass 'selftest B/caller-miss: a QA that finds report.py broken on its own is recorded as the catcher, and the qa-fix path passes' || fail "selftest B/caller-miss: the qacatch run was not a pass caught by qa (rc $ST_RC)"
  # a QA whose feedback never says what the kit expected leaves the implementer guessing: the qa-loop evidence check rejects it
  st_run A qa-loop vagueqa
  [ "$ST_RC" -ne 0 ] && grep -q "QA's feedback never quotes an expected amount" "$ST_GRADE" \
    && pass 'selftest A/qa-loop: a QA whose feedback never quotes an expected amount fails the case' || fail "selftest A/qa-loop: the vague QA feedback was not rejected (rc $ST_RC)"
  # negative: an implementer that is right at once (nothing to catch) is reported as not forced
  st_run A qa-loop firsttry
  [ "$ST_RC" -ne 0 ] && grep -q 'the loop was not forced' "$ST_GRADE" && pass 'selftest: an implementer that gets it right at once fails the case as "not forced"' || fail 'selftest: the not-forced case was not flagged'
  # review-loop loop shape: one or two review-fix loops pass (the A:review-loop run of 2026-11-20 took two); a missed first review, a first
  # review that does not name the seeded defect, and a third loop all fail
  local rl_path rl_ok rl_two rl_miss rl_three rl_st
  rl_path=$( . "$CASES_DIR/review-loop.sh"; printf '%s' "$CASE_EXPECT_PATH" )
  rl_ok='implement:done classify:low qa:pass review:fail verify-review:fail implement:done classify:medium qa:pass review:pass security:pass ship:pass deliver:done'
  rl_two='implement:done classify:low qa:pass review:fail verify-review:fail implement:done classify:medium qa:pass review:fail verify-review:fail implement:done classify:medium qa:pass review:pass security:pass ship:pass deliver:done'
  rl_miss='implement:done classify:low qa:pass review:pass security:pass ship:pass deliver:done'
  rl_three="${rl_two/ review:pass/ review:fail verify-review:fail implement:done classify:low qa:pass review:pass}"
  printf '%s\n%s\n%s\n%s\n' "$rl_ok" "$rl_two" "$rl_miss" "$rl_three" | python3 -c '
import re, sys
exp = sys.argv[1]; l = sys.stdin.read().splitlines()
sys.exit(0 if [re.search(exp, x) is not None for x in l] == [True, True, False, False] else 1)' "$rl_path" \
    && pass 'selftest review-loop: the loop-shape regex accepts one or two review-fix loops and rejects a missed seeded defect and a third loop' || fail 'selftest review-loop: the loop-shape regex is off'
  rl_st="$t/rl-state"; mkdir -p "$rl_st/data"
  jq -n '{history: [{step:"review",outcome:"fail",feedback:[{what:"style nit",where:"store.py"}]},{step:"verify-review",outcome:"fail",feedback:[{what:"style nit",where:"store.py"}]},{step:"implement",outcome:"done",answers:[1]},{step:"review",outcome:"fail",feedback:[{what:"R2 trail missing",where:"store.py"}]}]}' > "$rl_st/data/workflow.json"
  [ -n "$( . "$CASES_DIR/review-loop.sh"; case_assert "$rl_st" "$rl_st" 2>&1 )" ] \
    && pass 'selftest review-loop: a seeded defect first named only in the SECOND review is not credited to the first review' || fail 'selftest review-loop: the first-review catch is not enforced'
  # the oracle-hunting detector (the copy in this suite) flags a hunt and leaves ordinary calls alone
  mkdir -p "$t/hunt/01-bad" "$t/hunt/02-good"
  printf 'bash\t{"command": "find / -name kit.py 2>/dev/null"}\nbash\t{"command": "cat /x/tests/live-crossfamily/qa-loop.sh"}\nbash\t{"command": "find /tmp -maxdepth 2"}\nbash\t{"command": "cat /tmp/kit/expected.json"}\n' > "$t/hunt/01-bad/calls.tsv"
  printf 'bash\t{"command": "python3 -m unittest discover -s tests"}\nread\t{"path": "/tmp/fm-wf-live-cfg.X/roles/qa/ROLE.md"}\nbash\t{"command": "git log --oneline"}\nbash\t{"command": "node /tmp/t.js; ls /tmp | head -20"}\n' > "$t/hunt/02-good/calls.tsv"
  [ "$(hunt_scan "$t/hunt/01-bad" | wc -l | tr -d ' ')" = 4 ] && [ -z "$(hunt_scan "$t/hunt/02-good")" ] && pass 'selftest: the oracle-hunting detector flags a hunt and leaves ordinary calls alone' || fail 'selftest: the hunting detector is off'
  # the scrubber
  mkdir -p "$t/scrub"
  printf 'token sk-abcdefghijklmnopqrstuvwxyz0123456789 and Authorization: Bearer abcdefghijklmnopqrstuvwx and "api_key": "abcdefghijklmnopqrstuvwxyz"\n' > "$t/scrub/a.txt"
  [ "$(scrub_artifacts "$t/scrub")" = 0 ] && ! grep -q 'abcdefghijklmnopqrstuvwx' "$t/scrub/a.txt" && pass 'selftest: credential-like strings are scrubbed from artifacts' || fail 'selftest: the scrubber left a credential-like string'
  rm -rf "$t"
  ART=''
}

command_selftest=0
if [ "${1:-}" = selftest ]; then command_selftest=1; fi
command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || { printf 'SKIP - crossfamily live: needs jq, python3 and git\n'; exit 0; }
# the offline self-test runs first (minutes); a batch of live runs that already ran it sets FM_XF_SKIP_SELFTEST=1 so it is not repeated per run
if [ "${FM_XF_SKIP_SELFTEST:-}" != 1 ] || [ "$command_selftest" -eq 1 ]; then ( selftest; exit "$failed" ) || failed=1; fi
if [ "$command_selftest" -eq 1 ]; then
  printf '\nCROSSFAMILY LIVE SELFTEST %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
  [ "$failed" -eq 0 ]; exit $?
fi
if [ "${FM_XF_LIVE:-}" != 1 ] || [ "$#" -eq 0 ]; then
  printf 'SKIP - live cross-family suite: set FM_XF_LIVE=1 and name <pairing>:<case> (pairings base-claude base-codex A B C1 C2 X1 X2; cases qa-loop review-loop caller-miss); never reported as PASS\n\nCROSSFAMILY LIVE SELFTEST %s, LIVE SKIPPED\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
  [ "$failed" -eq 0 ]; exit $?
fi
STAMP=$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM
ART="${FM_XF_ART:-$CONFIG_ROOT/tests/live-artifacts/xf-$STAMP}"
mkdir -p "$ART"
if ! command -v "$OMP_BIN" >/dev/null 2>&1; then printf 'SKIP - needs omp on PATH; never reported as PASS\n'; exit 0; fi
if [ -z "$SKILL_SRC" ]; then
  PIN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fm-xf-pinned.XXXXXX")
  bash "$CONFIG_ROOT/tests/live-lib/pinned-skills.sh" "$PIN_DIR" >/dev/null 2>"$ART/pinned-skills.err" || { printf 'SKIP - cannot materialize the pinned skills (%s); never reported as PASS\n' "$(head -c 200 "$ART/pinned-skills.err")"; rm -rf "$PIN_DIR"; exit 0; }
  SKILL_SRC="$PIN_DIR/skills"
fi
printf '# Cross-family live results (%s, thinking %s)\n\n| pairing | case | path taken (engine state) | loops used | forced / hidden check | seeded defect | models per step (from the logs) | workers | USD | verdict |\n|---|---|---|---|---|---|---|---|---|---|\n' "$STAMP" "$THINKING" > "$ART/results.md"
for a in "$@"; do
  pairing=${a%%:*}; cname=${a#*:}
  [ -f "$CASES_DIR/$cname.sh" ] || { fail "no such live case: $cname"; continue; }
  ( run_case "$pairing" "$CASES_DIR/$cname.sh" ) || failed=1
done
[ -z "${PIN_DIR:-}" ] || rm -rf "$PIN_DIR"
leftover=$(scrub_artifacts "$ART")
printf '\n%s\n' "$(cat "$ART/results.md")"
printf 'artifacts: %s  total cost: %s USD (budget %s; codex CLI cost is not reported and counts as 0)  credential-like strings left after scrubbing: %s\n' "$ART" "$(cat "$ART/.spent" 2>/dev/null || echo 0)" "${BUDGET:-none}" "$leftover"
printf '\nCROSSFAMILY LIVE %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
