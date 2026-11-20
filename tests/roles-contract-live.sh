#!/usr/bin/env bash
# roles-contract-live.sh - opt-in LIVE proof that a worker running a role follows the role's CONTRACT:
# it works inside its tool list, applies its working shape to a seeded fixture, and ends with the
# machine-readable block bin/fm-workflow parses - judged by a deterministic OUTSIDE check on the
# output (the fixture, the transcript, a hidden kit), never by the worker grading itself.
# (tests/roles-live.sh proves skills are read and applied, with a no-skill control; this proves the
# contracts of the roles the army added: lead, test-engineer, ui-qa, risk-classifier,
# finding-verifier, release-engineer, researcher, perf-engineer, improver.)
#
# Usage:
#   tests/roles-contract-live.sh                   offline self-test (a fake omp, canned good/bad workers
#                                                  graded by each case's real judge); live SKIPs
#   tests/roles-contract-live.sh selftest [case]   only the offline self-test
#   FM_CONTRACT_LIVE=1 tests/roles-contract-live.sh [case...]   run the live cases (default: all)
#
# Environment (live): the worker uses the operator's existing omp login in place; no credential is
# exported, copied or logged. Without a logged-in omp the live run SKIPs, never PASSes.
#   FM_CONTRACT_LIVE=1                   required opt-in
#   FM_CONTRACT_LIVE_MODEL               default anthropic/claude-sonnet-5-5
#   FM_CONTRACT_LIVE_THINKING            default medium
#   FM_CONTRACT_LIVE_BUDGET              optional total USD cap (a running tally is kept)
#   FM_CONTRACT_LIVE_RUN_CAP             optional per-run USD cap passed to omp --max-cost
#   FM_CONTRACT_LIVE_TIMEOUT             seconds per run (default 900)
#   FM_CONTRACT_LIVE_SKILL_SRC           read-only skill source: a directory of <skill>/SKILL.md. Default
#                                        ~/.agents/skills; to run with exactly what install.sh would link,
#                                        including pins the machine has not fetched yet:
#                                          tests/live-lib/pinned-skills.sh /tmp/pinned && \
#                                          FM_CONTRACT_LIVE_SKILL_SRC=/tmp/pinned/skills ...
# Isolation: each run gets a throwaway git repo OUTSIDE the tracked tree (mktemp), a fixture-local copy
# of the skills, its own session dir, a scrubbed environment (env -i), --no-skills --no-rules
# --no-context-files --no-extensions, and exactly the built-in tools the ROLE.md frontmatter lists
# (find and lsp are dropped: this OMP build does not offer them as built-ins). A case that lets a role
# spawn sub-agents gets project agents in <repo>/.omp/agents/fm-<role>.md (a copy of each ROLE.md).
# Artifacts (git-ignored): tests/live-artifacts/<stamp>/<case>/ - prompt, transcript, calls, final report,
# the parsed block, grade.txt; results.md at the top.
#
# Case file contract (tests/live-contract/<name>.sh, sourced in a subshell):
#   CASE_ROLE=<role>                 the role under test
#   CASE_BLOCK=result|verdict|risk|report|none   the machine-readable ending the role owes
#   CASE_PROMPT='...'                the Captain's intent (tiny)
#   CASE_AGENTS="a b"                roles installed as project agents (fm-a, fm-b) so a role with the task tool can spawn them
#   CASE_NEEDS="cmd ..."             commands that must exist, else the case SKIPs (never PASSes)
#   CASE_TIMEOUT=<seconds>           override the per-run timeout
#   case_setup                       create the fixture files in the cwd (the harness runs git init/commit around it)
#   case_aux <auxdir>                optional: hidden material the worker cannot reach from its cwd (a kit, an oracle)
#   case_serve <repo> <auxdir>       optional: start background services; print KEY=VALUE lines on stdout
#                                    (they are told to the worker and exported to case_grade); write each
#                                    service pid to <auxdir>/pids, the harness stops them
#   case_grade <repo> <run> <aux>    the OUTSIDE judge: 0 when the role's contract held; print the reason
#   case_canned good|bad <repo> <run> <aux>  offline stand-in worker: write $run/final.txt (+ $run/calls.tsv extras)
#                                    and edit the repo as such a worker would leave it. good must pass the whole
#                                    judge, bad must fail case_grade (self-test).
# Grader helpers (current run in $RUN/$REPO): final_has <ERE>, final_lacks <ERE>, call_has <ERE>,
#   called_agent <role>, tool_calls <tool>, block_json (the parsed final block), changed_files, skill_read <name>.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$CONFIG_ROOT/bin/fm-workflow"
HANDOFF="$CONFIG_ROOT/bin/fm-role-handoff"
CASES_DIR="${FM_CONTRACT_CASES_DIR:-$CONFIG_ROOT/tests/live-contract}"
ART_ROOT="$CONFIG_ROOT/tests/live-artifacts"
MODEL="${FM_CONTRACT_LIVE_MODEL:-anthropic/claude-sonnet-5-5}"
THINKING="${FM_CONTRACT_LIVE_THINKING:-medium}"
BUDGET="${FM_CONTRACT_LIVE_BUDGET:-}"
RUN_CAP="${FM_CONTRACT_LIVE_RUN_CAP:-}"
TIMEOUT="${FM_CONTRACT_LIVE_TIMEOUT:-900}"
SKILL_SRC="${FM_CONTRACT_LIVE_SKILL_SRC:-$HOME/.agents/skills}"
OMP_BIN="${FM_CONTRACT_LIVE_OMP:-omp}"
COST_ARGS=()
[ -z "$RUN_CAP" ] || COST_ARGS=(--max-cost "$RUN_CAP")
SYSTEM_PROMPT='You are a coding worker. Use your tools. Follow the Firstmate spec exactly, including every read-and-apply requirement, then finish with a short final report.'

# shellcheck source=tests/live-lib/session.sh
. "$CONFIG_ROOT/tests/live-lib/session.sh"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
skip() { printf 'SKIP - %s\n' "$1"; }

SPENT=0
spent_add() { SPENT=$(python3 -c 'import sys; print("%.6f" % (float(sys.argv[1]) + float(sys.argv[2])))' "$SPENT" "$1"); }
over_budget() { [ -n "$BUDGET" ] && python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)' "$SPENT" "$BUDGET"; }

# --- grader helpers (the current run: $RUN, $REPO) --------------------------------------------
final_has() { grep -Eiq -- "$1" "$RUN/final.txt"; }
final_lacks() { ! final_has "$1"; }
call_has() { cut -f2- "$RUN/calls.tsv" | grep -Eq -- "$1"; }
tool_calls() { awk -F'\t' -v t="$1" '$1 == t { n++ } END { print n + 0 }' "$RUN/calls.tsv"; }
called_agent() { awk -F'\t' '$1 == "task" { print $2 }' "$RUN/calls.tsv" | grep -Eq "\"agent\": ?\"fm-$1\""; }
changed_files() { git -C "$REPO" status --porcelain | sed 's/^...//'; }
skill_read() { awk -F'\t' -v p="/$1/SKILL.md" '($1 == "read" || $1 == "bash" || $1 == "grep") && index($2, p) { found = 1 } END { exit !found }' "$RUN/calls.tsv"; }
block_json() { cat "$RUN/block.json" 2>/dev/null; }
sub_calls() { cat "$RUN/subcalls.tsv" 2>/dev/null; }   # agent<TAB>tool<TAB>args of every sub-agent the worker spawned

case_var() { ( . "$CASE_FILE"; eval "printf '%s' \"\${$1:-}\"" ); }
have_fn() { ( . "$CASE_FILE"; declare -F "$1" >/dev/null ); }

# role_tools <role>: the omp --tools list for a role - its frontmatter tools minus the names this OMP build lacks.
role_tools() {
  awk '/^---$/ { n++; next } n == 1 && /^tools:/ { t = 1; next } n == 1 && t && /^  - / { sub(/^  - /, ""); print; next } n == 1 && t { t = 0 }' "$CONFIG_ROOT/roles/$1/ROLE.md" \
    | grep -vxE 'find|lsp' | paste -sd, -
}
role_skills() { FM_CONFIG_ROOT="$CONFIG_ROOT" "$HANDOFF" --skills "$1"; }

contract_line() { # <block kind>
  case $1 in
    result)  printf 'Output contract: end your final report with the fenced `result` block your role file defines (status, evidence with each command and what it printed, answers, unverified; base and commit when you committed).\n' ;;
    verdict) printf 'Output contract: end your final report with the fenced `verdict` block your role file defines, naming the head commit you judged.\n' ;;
    risk)    printf 'Output contract: end your final report with the fenced `risk` block your role file defines.\n' ;;
    report)  printf 'Output contract: the first line of your final report is `status: done`, `status: blocked` or `status: change-direction`.\n' ;;
    *) : ;;
  esac
}

build_prompt() { # <role> <intent> <skills-root> <block> <env-lines>
  printf '# Task\n\n## Captain'"'"'s intent\n%s\n' "$2"
  [ -z "$5" ] || printf '\nEnvironment facts for this task:\n%s\n' "$5"
  printf '\n## Firstmate spec\n'
  FM_CONFIG_ROOT="${WORKER_ROOT:-$CONFIG_ROOT}" FM_SKILLS_ROOT="$3" "$HANDOFF" "$1"
  contract_line "$4"
  printf 'Pre-work: run pwd -P and git rev-parse --show-toplevel (they must match), then read every path named above with your file read tool before the first edit and before any shell work.\nApply each skill'"'"'s procedure step by step. Work only inside this repository, with no network and no package installs. Deliver results in your final message; create files only where the task names them. Be economical: aim for at most 30 tool calls. End with a short final report.\n'
}

stop_services() { # <aux>
  local p
  [ -f "$1/pids" ] || return 0
  while read -r p; do [ -z "$p" ] || kill "$p" 2>/dev/null || true; done < "$1/pids"
}

# judge_run: the generic contract checks, then the case's own outside judge. Prints "ok/FAIL - ..." rows; returns 0 when all hold.
judge_run() { # <role> <block> ; uses RUN REPO AUX
  local role=$1 block=$2 ok=0 s tools bad t g
  if call_has "/roles/$role/ROLE.md"; then echo "ok   - the worker read its ROLE.md"; else echo "FAIL - the worker never read roles/$role/ROLE.md"; ok=1; fi
  for s in $(role_skills "$role"); do
    if skill_read "$s"; then echo "ok   - the worker read the role skill $s"; else echo "FAIL - the worker never read the role skill $s"; ok=1; fi
  done
  # only the tools the role lists were used
  tools=",$(role_tools "$role"),wait,"
  bad=''
  for t in $(cut -f1 "$RUN/calls.tsv" | sort -u); do case $tools in *",$t,"*) ;; *) bad="$bad $t" ;; esac; done
  if [ -z "$bad" ]; then echo "ok   - every tool call stayed inside the role's tool list ($(role_tools "$role"))"; else echo "FAIL - tool calls outside the role's list:$bad"; ok=1; fi
  case $block in
    result|verdict|risk)
      "$W" "$block" "$RUN/final.txt" > "$RUN/block.json" 2>/dev/null
      if jq -e '.valid == true' "$RUN/block.json" >/dev/null 2>&1; then echo "ok   - the final report ends with a valid $block block ($(jq -r '.outcome // .verdict // .tier' "$RUN/block.json"))"
      else echo "FAIL - the final report has no valid $block block: $(jq -r '.problems | join("; ")' "$RUN/block.json" 2>/dev/null | cut -c1-200)"; ok=1; fi ;;
    report)
      if sed -n '/./{p;q;}' "$RUN/final.txt" | grep -Eq '^status: (done|blocked|change-direction)$'; then echo "ok   - the report opens with its status line"
      else echo "FAIL - the report's first line is not a status line: $(sed -n '/./{p;q;}' "$RUN/final.txt" | cut -c1-80)"; ok=1; fi ;;
  esac
  g=$( . "$CASE_FILE"; [ ! -f "$AUX/env" ] || { set -a; . "$AUX/env"; set +a; }; cd "$REPO" && case_grade "$REPO" "$RUN" "$AUX" 2>&1 ); local rc=$?
  if [ "$rc" -eq 0 ]; then echo "ok   - outside judge: $g"; else echo "FAIL - outside judge: $g"; ok=1; fi
  return $ok
}

# prepare <case-file> <label> <skills-src>: sets SCR REPO AUX RUN HOMEFX ENVLINES. The fixture lives outside the tracked tree.
prepare() {
  local case_file=$1 name=$2 role r s
  CASE_FILE=$case_file
  role=$(case_var CASE_ROLE)
  SCR=$(mktemp -d "${TMPDIR:-/tmp}/fm-contract-live.XXXXXX") || return 1
  REPO="$SCR/repo"; AUX="$SCR/aux"; HOMEFX="$SCR/home"
  mkdir -p "$REPO" "$AUX" "$HOMEFX/.agents/skills" "$SCR/session" "$SCR/config"
  # The worker sees a SANITIZED copy of the checkout (roles, bin, firstmate, workflows, skills lock, top-level docs) - never
  # tests/, so it cannot read the judge, the fixtures or another case's oracle. Role paths in its brief point into the copy.
  WORKER_ROOT="$SCR/config"
  ( cd "$CONFIG_ROOT" && tar -cf - roles bin firstmate workflows skills REVIEW.md README.md AGENTS.md 2>/dev/null ) | tar -xf - -C "$WORKER_ROOT"
  for s in "$SKILL_SRC"/*/; do s=$(basename "$s"); cp -rL "$SKILL_SRC/$s" "$HOMEFX/.agents/skills/$s" 2>/dev/null; done
  [ ! -d "$(dirname "$SKILL_SRC")/references" ] || cp -rL "$(dirname "$SKILL_SRC")/references" "$HOMEFX/.agents/references" 2>/dev/null
  (
    cd "$REPO" || exit 1
    git init -q . && git config user.email live@example.invalid && git config user.name live
    printf '__pycache__/\n*.pyc\n.omp/\n' >> .git/info/exclude
    # shellcheck source=/dev/null
    . "$case_file"
    case_setup
    for r in ${CASE_AGENTS:-}; do mkdir -p .omp/agents && cp "$WORKER_ROOT/roles/$r/ROLE.md" ".omp/agents/fm-$r.md"; done
    git add -A && git commit -q --allow-empty -m fixture
  ) || return 1
  ! have_fn case_aux || ( . "$case_file"; case_aux "$AUX" ) || return 1
  ENVLINES=''
  if have_fn case_serve; then
    ENVLINES=$( . "$case_file"; case_serve "$REPO" "$AUX" ) || return 1
    printf '%s\n' "$ENVLINES" > "$AUX/env"
  fi
  RUN="$ART/$name"; mkdir -p "$RUN"
}

run_live_one() { # <case-file>
  local case_file=$1 name role block timeout need prompt rc t g
  name=$(basename "$case_file" .sh)
  CASE_FILE=$case_file
  role=$(case_var CASE_ROLE); block=$(case_var CASE_BLOCK); timeout=$(case_var CASE_TIMEOUT); [ -n "$timeout" ] || timeout=$TIMEOUT
  [ -n "$role" ] && [ -f "$CONFIG_ROOT/roles/$role/ROLE.md" ] || { fail "$name: CASE_ROLE '$role' is not a role"; return; }
  for need in $(case_var CASE_NEEDS); do command -v "$need" >/dev/null 2>&1 || { skip "$name: needs $need on PATH; never reported as PASS"; printf '| %s | %s | SKIP (needs %s) | - | - |\n' "$name" "$role" "$need" >> "$ART/results.md"; return; }; done
  if over_budget; then fail "$name: budget $BUDGET USD reached (spent $SPENT); run not started"; return; fi
  prepare "$case_file" "$name" || { fail "$name: fixture setup failed"; return; }
  prompt=$(build_prompt "$role" "$(case_var CASE_PROMPT)" "$HOMEFX/.agents/skills" "$block" "$ENVLINES")
  printf '%s\n' "$prompt" > "$RUN/prompt.md"
  ( cd "$REPO" && env -i HOME="$HOME" PATH="$PATH" TERM=dumb LANG=C.UTF-8 OMP_SKIP_SETUP=1 PYTHONDONTWRITEBYTECODE=1 $ENVLINES \
      timeout "$timeout" "$OMP_BIN" -p --wait-async --model "$MODEL" --thinking "$THINKING" --no-extensions --no-skills --no-rules --no-context-files \
      --no-lsp --no-pty --no-title --tools "$(role_tools "$role")" --system-prompt "$SYSTEM_PROMPT" \
      --session-dir "$SCR/session" ${COST_ARGS[@]+"${COST_ARGS[@]}"} --auto-approve --cwd "$REPO" "@$RUN/prompt.md" \
      > "$RUN/stdout.txt" 2> "$RUN/stderr.txt" ); rc=$?
  printf '%s\n' "$rc" > "$RUN/rc"
  stop_services "$AUX"
  cp -r "$SCR/session" "$RUN/session"
  parse_session "$RUN/session" "$RUN"
  spent_add "$(cat "$RUN/cost.txt")"
  [ -s "$RUN/final.txt" ] || printf 'The worker produced no report (omp exit %s).\n' "$rc" > "$RUN/final.txt"
  g=$(judge_run "$role" "$block" 2>&1); jrc=$?
  printf '%s\n' "$g" > "$RUN/grade.txt"
  printf '| %s | %s | %s | %s | %s | %s |\n' "$name" "$role" "$( [ $jrc -eq 0 ] && echo PASS || echo FAIL )" "$(wc -l < "$RUN/calls.tsv" | tr -d ' ')" "$(cat "$RUN/cost.txt")" "$SPENT" >> "$ART/results.md"
  if [ $jrc -eq 0 ]; then pass "live $name ($role): contract held ($(wc -l < "$RUN/calls.tsv" | tr -d ' ') tool calls, $(cat "$RUN/cost.txt") USD)"
  else fail "live $name ($role): $(grep '^FAIL' "$RUN/grade.txt" | tr '\n' ' ')"; fi
  rm -rf "$SCR"
}

# --- offline self-test --------------------------------------------------------------------------
# canned_base <role>: the calls a worker that followed the handoff leaves (ROLE.md and every skill read).
canned_base() {
  local role=$1 s
  : > "$RUN/calls.tsv"
  printf 'read\t{"path":"%s/roles/%s/ROLE.md"}\n' "$CONFIG_ROOT" "$role" >> "$RUN/calls.tsv"
  for s in $(role_skills "$role"); do printf 'read\t{"path":"/skills/%s/SKILL.md"}\n' "$s" >> "$RUN/calls.tsv"; done
}

selftest_fake_omp() { # the harness mechanics, through a fake omp: tools flag, prompt, agents, cost, services, judge
  local t fake name
  t=$(mktemp -d "${TMPDIR:-/tmp}/fm-contract-live-self.XXXXXX") || return 1
  fake="$t/omp"
  cat > "$fake" <<'SH'
#!/usr/bin/env bash
sess=''; prompt=''; tools=''; cwd=''
while [ $# -gt 0 ]; do case $1 in --session-dir) sess=$2; shift ;; --tools) tools=$2; shift ;; --cwd) cwd=$2; shift ;; @*) prompt=${1#@} ;; esac; shift; done
mkdir -p "$sess"
printf '%s\n' "$tools" > "$sess/tools-seen"
ls "$cwd/.omp/agents" > "$sess/agents-seen" 2>/dev/null
printf '{"type":"message","message":{"role":"assistant","content":[{"type":"toolCall","name":"read","arguments":{"path":"/x/roles/scout/ROLE.md"}}],"usage":{"cost":{"total":0.01}}}}\n{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"status: done\\nfake"}],"usage":{"cost":{"total":0.02}}}}\n' > "$sess/s.jsonl"
cp "$prompt" "$sess/prompt-seen"
SH
  chmod +x "$fake"
  name=selftest-fake
  mkdir -p "$t/cases"
  cat > "$t/cases/$name.sh" <<'CASE'
CASE_ROLE=scout
CASE_BLOCK=report
CASE_AGENTS="qa"
CASE_PROMPT='list the files'
case_setup() { printf 'x\n' > a.txt; }
case_serve() { echo "APP_URL=http://127.0.0.1:1"; }
case_grade() { echo "fake judge"; return 0; }
CASE
  OMP_BIN="$fake"; CASES_DIR="$t/cases"; ART="$t/art"; mkdir -p "$ART"; SPENT=0
  ( run_live_one "$t/cases/$name.sh" ) > "$t/out.txt" 2>&1
  [ "$(cat "$ART/$name/session/tools-seen")" = "read,grep,glob,bash" ] && pass 'selftest: omp was started with exactly the role tools (find and lsp dropped)' || fail "selftest: omp tools were $(cat "$ART/$name/session/tools-seen")"
  [ "$(cat "$ART/$name/session/agents-seen")" = "fm-qa.md" ] && pass 'selftest: CASE_AGENTS installs the role as a project agent (.omp/agents/fm-qa.md)' || fail 'selftest: project agent not installed'
  grep -q 'FAIL' "$t/out.txt" && fail "selftest: fake run reported a failure: $(cat "$t/out.txt")" || pass 'selftest: a fake worker that read its ROLE.md and ended with a status line passes through the live pipeline'
  [ "$(cat "$ART/$name/cost.txt")" = "0.030000" ] && pass 'selftest: cost is summed from the session usage' || fail "selftest: cost $(cat "$ART/$name/cost.txt")"
  grep -q 'APP_URL=http://127.0.0.1:1' "$ART/$name/prompt.md" && pass 'selftest: the service environment is told to the worker' || fail 'selftest: no environment facts in the prompt'
  grep -q 'Output contract: the first line of your final report is `status: done`' "$ART/$name/prompt.md" && pass 'selftest: the prompt carries the output contract of the block kind' || fail 'selftest: no output contract line'
  grep -q 'roles/scout/ROLE.md' "$ART/$name/prompt.md" && pass 'selftest: the prompt carries the role handoff (the ROLE.md path)' || fail 'selftest: no role handoff'
  [ "$(role_tools scout)" = "read,grep,glob,bash" ] && pass 'selftest: the --tools list is the role frontmatter list minus find/lsp' || fail "selftest: scout tools $(role_tools scout)"
  [ "$(role_tools lead)" = "read,grep,glob,bash,edit,write,todo,task" ] && pass 'selftest: lead keeps todo and task' || fail "selftest: lead tools $(role_tools lead)"
  # a worker that edits with a tool outside its list fails the generic check
  RUN="$t/judge"; REPO="$t/jrepo"; AUX="$t/jaux"; mkdir -p "$RUN" "$REPO" "$AUX"; CASE_FILE="$t/cases/$name.sh"
  . "$CASE_FILE"
  canned_base scout; printf 'edit\t{"path":"a.txt"}\n' >> "$RUN/calls.tsv"; printf 'status: done\nx\n' > "$RUN/final.txt"
  judge_run scout report 2>&1 | grep -q 'FAIL - tool calls outside the role' && pass 'selftest: a leaf role that calls edit is caught by the tool check' || fail 'selftest: tool check did not bite'
  canned_base scout; printf 'no status line here\n' > "$RUN/final.txt"
  judge_run scout report 2>&1 | grep -q 'FAIL - the report.s first line is not a status line' && pass 'selftest: a report without its status line is caught' || fail 'selftest: status-line check did not bite'
  canned_base risk-classifier; printf 'prose only\n' > "$RUN/final.txt"
  judge_run risk-classifier risk 2>&1 | grep -q 'FAIL - the final report has no valid risk block' && pass 'selftest: a missing risk block is caught' || fail 'selftest: block check did not bite'
  rm -rf "$t"
  ART=''
}

selftest_cases() { # every case's real judge, on a canned good and a canned bad worker
  local c name role block mode t rc g s
  t=$(mktemp -d "${TMPDIR:-/tmp}/fm-contract-live-cases.XXXXXX") || return 1
  for c in "$CASES_DIR"/*.sh; do
    [ -f "$c" ] || continue
    name=$(basename "$c" .sh)
    [ "${#ONLY[@]}" -eq 0 ] || case " ${ONLY[*]} " in *" $name "*) ;; *) continue ;; esac
    CASE_FILE=$c
    role=$(case_var CASE_ROLE); block=$(case_var CASE_BLOCK)
    [ -f "$CONFIG_ROOT/roles/$role/ROLE.md" ] && pass "case $name: role $role exists" || { fail "case $name: no role '$role'"; continue; }
    case $block in result|verdict|risk|report|none) pass "case $name: block kind $block" ;; *) fail "case $name: CASE_BLOCK must be result|verdict|risk|report|none"; continue ;; esac
    [ -n "$(case_var CASE_PROMPT)" ] && pass "case $name: has a prompt" || fail "case $name: no CASE_PROMPT"
    for fn in case_setup case_grade case_canned; do have_fn "$fn" && pass "case $name: defines $fn" || fail "case $name: missing $fn"; done
    for mode in good bad; do
      rm -rf "$t/$name-$mode"; mkdir -p "$t/$name-$mode"
      ART="$t/$name-$mode/art"; mkdir -p "$ART"
      SKILL_SRC_SAVE=$SKILL_SRC; SKILL_SRC="$t/no-skills"; mkdir -p "$SKILL_SRC"
      prepare "$c" "$name-$mode" || { fail "case $name: fixture setup failed ($mode)"; SKILL_SRC=$SKILL_SRC_SAVE; continue; }
      SKILL_SRC=$SKILL_SRC_SAVE
      canned_base "$role"
      ( . "$c"; cd "$REPO" && case_canned "$mode" "$REPO" "$RUN" "$AUX" ) || { fail "case $name: case_canned $mode failed"; stop_services "$AUX"; continue; }
      [ -f "$RUN/final.txt" ] || : > "$RUN/final.txt"
      g=$(judge_run "$role" "$block" 2>&1); rc=$?
      stop_services "$AUX"
      if [ "$mode" = good ]; then
        [ $rc -eq 0 ] && pass "case $name: a worker that follows the $role contract passes the whole judge" || fail "case $name: the canned good $role worker failed: $(printf '%s' "$g" | grep '^FAIL' | tr '\n' ' ')"
      else
        printf '%s' "$g" | grep -q 'FAIL - outside judge' && pass "case $name: the outside judge rejects a worker that broke the $role contract" || fail "case $name: the outside judge accepted a bad $role worker: $g"
      fi
      rm -rf "$SCR"
    done
  done
  rm -rf "$t"; ART=''
}

ONLY=()
command_selftest=0
if [ "${1:-}" = selftest ]; then command_selftest=1; ONLY=("${@:2}"); fi
( selftest_fake_omp; exit "$failed" ) || failed=1
( selftest_cases; exit "$failed" ) || failed=1
if [ "$command_selftest" -eq 1 ]; then
  printf '\nROLES CONTRACT LIVE SELFTEST %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
  [ "$failed" -eq 0 ]; exit $?
fi
if [ "${FM_CONTRACT_LIVE:-}" != 1 ]; then
  printf 'SKIP - live contract suite: set FM_CONTRACT_LIVE=1 to run real workers with your existing omp login; never reported as PASS\n\nROLES CONTRACT LIVE SELFTEST %s, LIVE SKIPPED\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
  [ "$failed" -eq 0 ]; exit $?
fi
if ! command -v "$OMP_BIN" >/dev/null 2>&1 || ! "$OMP_BIN" models --json --no-extensions 2>/dev/null | grep -q "\"selector\":\"$MODEL\""; then
  printf 'SKIP - live contract suite: needs omp with %s available from the existing login; never reported as PASS\n' "$MODEL"
  exit 0
fi
STAMP=$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM
ART="$ART_ROOT/$STAMP"
mkdir -p "$ART"
printf '# Live role-contract results (%s, model %s)\n\n| case | role | contract | tool calls | run USD | cumulative USD |\n|---|---|---|---|---|---|\n' "$STAMP" "$MODEL" > "$ART/results.md"
if [ "$#" -gt 0 ]; then cases=("$@"); else cases=("$CASES_DIR"/*.sh); fi
for c in "${cases[@]}"; do
  case $c in */*) ;; *) c="$CASES_DIR/${c%.sh}.sh" ;; esac
  [ -f "$c" ] || { fail "no such live case: $c"; continue; }
  run_live_one "$c"
done
printf '\n%s\n' "$(cat "$ART/results.md")"
printf 'artifacts: %s  model: %s (thinking %s)  total cost: %s USD (budget %s)\n' "$ART" "$MODEL" "$THINKING" "$SPENT" "${BUDGET:-none}"
printf '\nROLES CONTRACT LIVE %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
