#!/usr/bin/env bash
# roles-live.sh - opt-in LIVE proof that a worker running a role really reads
# and applies the skills the role autoloads (firstmate/primary-policy.md
# sections 2 and 5). A real model, a real harness (omp), tiny prompts, a hard
# budget.
#
# Usage:
#   tests/roles-live.sh                  offline self-test of this harness (canned
#                                        sessions, no model); then SKIP the live run
#   FM_ROLE_LIVE=1 tests/roles-live.sh [case...]
#                                        run the live cases (default: all in tests/live/)
#   tests/roles-live.sh selftest         only the offline self-test
#
# Environment (live):
#   FM_ROLE_LIVE=1                       required opt-in; anything else never starts a model
#   (no credential variable)             the worker uses the operator's existing omp login IN PLACE
#                                        (HOME is not redirected); no credential is exported or copied.
#                                        Without a logged-in `omp` the live run SKIPs (never PASS).
#   FM_ROLE_LIVE_MODEL                   default anthropic/claude-sonnet-5-5 (the repo's Sonnet worker lane)
#   FM_ROLE_LIVE_THINKING                default medium
#   FM_ROLE_LIVE_BUDGET                  optional total USD cap; default none (a running tally is kept in results.md)
#   FM_ROLE_LIVE_RUN_CAP                 optional per-run USD cap passed to omp --max-cost; default none
#   FM_ROLE_LIVE_SKILL_SRC               read-only source of installed skills, default ~/.agents/skills
#
# Isolation: every run gets a fresh fixture directory under tests/live-artifacts/
# (git-ignored) holding a fixture-local copy of the skills and a throwaway git repo
# used as cwd; own session dir; scrubbed environment (env -i); `--no-skills --no-rules
# --no-context-files --no-extensions`. The ONLY exception to home isolation is the omp
# login, used in place (omp's usual bookkeeping databases under ~/.omp/agent still update).
# No credential is copied, exported or logged. ~/.agents is only read (skill source).
#
# A case (tests/live/<name>.sh) defines a characteristic problem whose correct
# outcome is reachable only by following the role's skill. Per case the harness
# runs the role WITH its autoloaded skills and a CONTROL with the same role and
# problem but the skills stripped, then reports:
#   read     every autoloaded SKILL.md was read by a tool call in the transcript
#   outcome  the case grader found the skill-only behaviour in the result
#   control  the same problem WITHOUT the skill did NOT show that behaviour
# A case passes only when read, outcome and control-discrimination all hold.
#
# Case file contract (sourced in a subshell; functions run with cwd = the repo):
#   CASE_KIND=role|mixed            default role
#   CASE_ROLE=<role>                role kind: the role under test
#   CASE_ROLES="<a> <b>"            mixed kind: two roles run on the same problem; each is
#                                   graded for ITS behaviour and for NOT bleeding the other's;
#                                   the control is no role at all, graded as the first role
#   CASE_PROMPT='...'               the task text (tiny)
#   case_setup                      create the fixture files in the cwd (git init/commit is done by the harness)
#   case_grade <role> <repo> <run>  return 0 when <role>'s skill-only behaviour is present and
#                                   no other role's behaviour bled in; print the reason on stdout
#   CASE_SKILL_ONLY_TOKENS="a b"    literal strings (no spaces) that exist in the role's skill text and in
#                                   NO ROLE.md, prompt or fixture file: the convention only the skill holds
#   case_canned <role> good|bad     offline stand-in for a worker that followed / ignored the skill:
#                                   write $RUN/final.txt and $RUN/calls.tsv (tool<TAB>json args; a
#                                   good worker has a read call on every autoloaded SKILL.md) and edit
#                                   the repo as such a worker would leave it. The self-test grades both
#                                   through case_grade: good must pass, bad must fail.
#   Grader helpers: final_has <ERE>, final_lacks <ERE>, call_has <ERE> (any tool call argument),
#                   changed_files (porcelain paths), skill_read <name>.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HANDOFF="$CONFIG_ROOT/bin/fm-role-handoff"
CASES_DIR="$CONFIG_ROOT/tests/live"
ART_ROOT="$CONFIG_ROOT/tests/live-artifacts"
MODEL="${FM_ROLE_LIVE_MODEL:-anthropic/claude-sonnet-5-5}"
THINKING="${FM_ROLE_LIVE_THINKING:-medium}"
BUDGET="${FM_ROLE_LIVE_BUDGET:-}"
RUN_CAP="${FM_ROLE_LIVE_RUN_CAP:-}"
COST_ARGS=()
[ -z "$RUN_CAP" ] || COST_ARGS=(--max-cost "$RUN_CAP")
SKILL_SRC="${FM_ROLE_LIVE_SKILL_SRC:-$HOME/.agents/skills}"
OMP_BIN="${FM_ROLE_LIVE_OMP:-omp}"
SYSTEM_PROMPT='You are a coding worker. Use your tools. Follow the Firstmate spec exactly, including every read-and-apply requirement, then finish with a short final report.'

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }

# --- transcript parsing: parse_session lives in tests/live-lib/session.sh ---------------------
# shellcheck source=tests/live-lib/session.sh
. "$CONFIG_ROOT/tests/live-lib/session.sh"

# --- grader helpers (read the current run via $RUN) ---------------------------------
final_has() { grep -Eiq -- "$1" "$RUN/final.txt"; }
final_lacks() { ! final_has "$1"; }
call_has() { cut -f2- "$RUN/calls.tsv" | grep -Eq -- "$1"; }
changed_files() { git -C "$REPO" status --porcelain | sed 's/^...//'; }
skill_read() { # <skill-name>: a read-like tool call on that skill's SKILL.md
  awk -F'\t' -v p="/$1/SKILL.md" '($1 == "read" || $1 == "bash" || $1 == "grep" || $1 == "eval") && index($2, p) { found = 1 } END { exit !found }' "$RUN/calls.tsv"
}

# --- fixture + run -----------------------------------------------------------------
# strip_skills: the role handoff with its Role skill entries removed (the control).
strip_skills() {
  awk '
    /^Role skill:$/ { getline; getline; getline; next }
    { print }
    END { print "Role skills:\n  none - this role loads no shared skill." }
  '
}

# build_prompt <role|""> <mode with|without> <prompt-text> <skills-root>
build_prompt() {
  local role=$1 mode=$2 text=$3 skills_root=$4
  printf '# Task\n\n## Captain'"'"'s intent\n%s\n\n## Firstmate spec\n' "$text"
  if [ -n "$role" ]; then
    if [ "$mode" = with ]; then
      FM_CONFIG_ROOT="$CFG" FM_SKILLS_ROOT="$skills_root" "$HANDOFF" "$role"
    else
      FM_CONFIG_ROOT="$CFG" FM_SKILLS_ROOT="$skills_root" "$HANDOFF" "$role" | strip_skills
    fi
  fi
  printf 'Pre-work: run pwd -P and git rev-parse --show-toplevel (they must match), then read every path named above with your file read tool before the first edit and before any shell work.\nApply each skill'"'"'s procedure step by step. Work only inside this repository, with no network and no package installs. Deliver results in your final message; create files only where the task names them. Be economical: aim for at most 20 tool calls. End with a short final report.\n'
}

# Fixture-only roles and skills for the mechanism layer (never shipped, never in the real roles/ or skills/).
mech_role() { # <config-root> <role> <description> [skill...]
  local cfg=$1 role=$2 desc=$3 s; shift 3
  mkdir -p "$cfg/roles/$role"
  {
    printf -- '---\nname: fm-%s\ndescription: "%s"\n' "$role" "$desc"
    if [ "$#" -gt 0 ]; then printf 'autoloadSkills:\n'; for s in "$@"; do printf '  - %s\n' "$s"; done; fi
    printf -- '---\n# Role: %s\n\nFixture-only role. It describes how to work; the project wins.\n' "$role"
  } > "$cfg/roles/$role/ROLE.md"
}
mech_skill() { # <skills-root> <name>; the skill body comes on stdin
  mkdir -p "$1/$2"
  { printf -- '---\nname: %s\ndescription: fixture-only skill\n---\n' "$2"; cat; } > "$1/$2/SKILL.md"
}

SPENT=0
spent_add() { SPENT=$(python3 -c 'import sys; print("%.6f" % (float(sys.argv[1]) + float(sys.argv[2])))' "$SPENT" "$1"); }
over_budget() { [ -n "$BUDGET" ] && python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)' "$SPENT" "$BUDGET"; }

# run_one <case-file> <label> <role|""> <with|without> <grade-role> -> sets RUN, REPO; prints one result line
run_one() {
  local case_file=$1 label=$2 role=$3 mode=$4 grade_role=$5 name fx
  name=$(basename "$case_file" .sh)
  RUN="$ART/$name/$label"
  REPO="$RUN/repo"
  fx="$RUN/home"
  mkdir -p "$REPO" "$fx/.agents/skills" "$RUN/session"
  # Fixture-local skill copies: the worker can only read these.
  local s
  for s in "$SKILL_SRC"/*/; do s=$(basename "$s"); cp -rL "$SKILL_SRC/$s" "$fx/.agents/skills/$s" 2>/dev/null; done
  # addyosmani skills read ../../references/*.md, which resolves to <home>/.agents/references.
  [ ! -d "$(dirname "$SKILL_SRC")/references" ] || cp -rL "$(dirname "$SKILL_SRC")/references" "$fx/.agents/references" 2>/dev/null
  # Mechanism cases bring their own fixture-only config root (roles) and skills; the real roles/ is not used.
  CFG="$CONFIG_ROOT"
  if ( . "$case_file"; [ "${CASE_MECHANISM:-}" = 1 ] ); then
    CFG="$RUN/config"; mkdir -p "$CFG/roles"; ln -sfn "$CONFIG_ROOT/firstmate" "$CFG/firstmate"
    ( . "$case_file"; case_mechanism_setup "$CFG" "$fx/.agents/skills" ) || { fail "$name/$label: case_mechanism_setup failed"; return 1; }
  fi
  # No credential handling: the worker uses the existing omp login in place (HOME is the real one).
  (
    cd "$REPO" || exit 1
    git init -q . && git config user.email live@example.invalid && git config user.name live
    printf '__pycache__/\n*.pyc\n' >> .git/info/exclude
    # shellcheck source=/dev/null
    . "$case_file"
    case_setup
    git add -A && git commit -q --allow-empty -m fixture
  ) || { fail "$name/$label: fixture setup failed"; return 1; }
  # shellcheck source=/dev/null
  CASE_PROMPT='' && . "$case_file"
  build_prompt "$role" "$mode" "$CASE_PROMPT" "$fx/.agents/skills" > "$RUN/prompt.md"
  if over_budget; then fail "$name/$label: budget $BUDGET USD reached (spent $SPENT); run not started"; return 1; fi
  ( cd "$REPO" && env -i HOME="$HOME" PATH="$PATH" TERM=dumb LANG=C.UTF-8 OMP_SKIP_SETUP=1 PYTHONDONTWRITEBYTECODE=1 \
      timeout 900 "$OMP_BIN" -p --model "$MODEL" --thinking "$THINKING" --no-extensions --no-skills --no-rules --no-context-files \
      --no-lsp --no-pty --no-title --tools read,grep,glob,bash,edit,write --system-prompt "$SYSTEM_PROMPT" \
      --session-dir "$RUN/session" "${COST_ARGS[@]}" --auto-approve --cwd "$REPO" "@$RUN/prompt.md" \
      > "$RUN/stdout.txt" 2> "$RUN/stderr.txt" ) || true
  parse_session "$RUN/session" "$RUN"
  spent_add "$(cat "$RUN/cost.txt")"
  # shellcheck source=/dev/null
  . "$case_file"
  ( cd "$REPO" && case_grade "$grade_role" "$REPO" "$RUN" ) > "$RUN/grade.txt" 2>&1
  GRADE_RC=$?
  return 0
}

# run_case <case-file>: runs the with-skill run(s) and the control, prints the verdict row.
run_case() {
  local case_file=$1 name roles role read_ok=1 outcome_ok=1 control_ok=1 why='' s
  name=$(basename "$case_file" .sh)
  # shellcheck source=/dev/null
  ( . "$case_file"; printf '%s|%s\n' "${CASE_KIND:-role}" "${CASE_ROLES:-${CASE_ROLE:-}}" ) > "$ART/.kind" 
  IFS='|' read -r kind roles < "$ART/.kind"
  for role in $roles; do
    run_one "$case_file" "$role" "$role" with "$role" || { fail "$name: run for $role did not complete"; return; }
    for s in $(FM_CONFIG_ROOT="$CFG" "$HANDOFF" --skills "$role"); do
      skill_read "$s" || { read_ok=0; why="$why [$role never read $s]"; }
    done
    if [ "$GRADE_RC" -ne 0 ]; then outcome_ok=0; why="$why [$role outcome: $(tr '\n' ' ' < "$RUN/grade.txt")]"; fi
  done
  first=${roles%% *}
  if [ "$kind" = mixed ]; then
    run_one "$case_file" control-norole "" with "$first" || { fail "$name: control did not complete"; return; }
  else
    run_one "$case_file" control-noskill "$first" without "$first" || { fail "$name: control did not complete"; return; }
  fi
  if [ "$GRADE_RC" -eq 0 ]; then control_ok=0; why="$why [control showed the skill-only behaviour: the problem does not discriminate]"; fi
  printf '| %s | %s | %s | %s | %s |\n' "$name" "$( [ $read_ok = 1 ] && echo yes || echo NO)" \
    "$( [ $outcome_ok = 1 ] && echo pass || echo FAIL)" "$( [ $control_ok = 1 ] && echo 'fails (good)' || echo 'PASSES (bad)')" "$SPENT" >> "$ART/results.md"
  if [ $read_ok = 1 ] && [ $outcome_ok = 1 ] && [ $control_ok = 1 ]; then
    pass "live $name: skill read, outcome carries the skill-only behaviour, control without the skill does not"
  else
    fail "live $name:$why"
  fi
}

# --- offline self-test: canned sessions prove parsing, grading and the verdict logic -----------
selftest() {
  local t fake
  t=$(mktemp -d "${TMPDIR:-/tmp}/fm-roles-live-self.XXXXXX") || return 1
  ART="$t/art"; mkdir -p "$ART"
  fake="$t/omp"
  # A fake omp that reads FAKE_BEHAVIOR from a file next to the prompt: good workers read the
  # skill and leave the marker the case grades; control workers do neither.
  cat > "$fake" <<'SH'
#!/usr/bin/env bash
if [ "$1" = auth ]; then exit 0; fi
sess=''; prompt=''
while [ $# -gt 0 ]; do case $1 in --session-dir) sess=$2; shift ;; @*) prompt=${1#@} ;; esac; shift; done
skill=$(grep -o '[^ ]*/SKILL.md' "$prompt" | head -1)
mkdir -p "$sess"
{
  if [ -n "$skill" ]; then
    printf '{"type":"message","message":{"role":"assistant","content":[{"type":"toolCall","name":"read","arguments":{"path":"%s"}}],"usage":{"cost":{"total":0.01}}}}\n' "$skill"
    printf 'SELFTEST-MARKER\n' > selftest-marker.txt
    printf '{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"Verdict: MARKER-FOLLOWED"}],"usage":{"cost":{"total":0.01}}}}\n'
  else
    printf '{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"done, no method"}],"usage":{"cost":{"total":0.01}}}}\n'
  fi
} > "$sess/s.jsonl"
SH
  chmod +x "$fake"
  OMP_BIN="$fake"; MODEL=fake; SKILL_SRC="$t/skills"
  mkdir -p "$SKILL_SRC/code-review-and-quality" "$SKILL_SRC/ponytail-review"
  : > "$SKILL_SRC/code-review-and-quality/SKILL.md"; : > "$SKILL_SRC/ponytail-review/SKILL.md"
  mkdir -p "$t/live"
  cat > "$t/live/selftest-case.sh" <<'CASE'
CASE_KIND=role
CASE_ROLE=code-reviewer
CASE_PROMPT='review the fixture'
case_setup() { printf 'x\n' > a.txt; }
case_grade() { final_has 'MARKER-FOLLOWED' && [ -e selftest-marker.txt ] && { echo marker found; return 0; }; echo "no marker"; return 1; }
CASE
  SPENT=0
  # Both code-reviewer skills are read by the fake only for the FIRST one; the second stays
  # unread, so the harness must report a missing read (read=NO) - proving the read check bites.
  out=$(run_case "$t/live/selftest-case.sh" 2>&1); rc=$?
  case $out in *"never read ponytail-review"*) pass 'selftest: a skill that was not read in the transcript fails the case' ;; *) fail "selftest: unread second skill not reported: $out" ;; esac
  [ -s "$ART/selftest-case/code-reviewer/calls.tsv" ] && pass 'selftest: tool calls parsed from the session jsonl' || fail 'selftest: no tool calls parsed'
  case $(cat "$ART/selftest-case/control-noskill/final.txt") in "done, no method") pass 'selftest: the control run really ran without the skill block' ;; *) fail 'selftest: control transcript wrong' ;; esac
  grep -q 'Role skill:' "$ART/selftest-case/control-noskill/prompt.md" && fail 'selftest: control prompt still carries a Role skill entry' || pass 'selftest: control prompt carries no Role skill entry'
  grep -q 'Role skills:' "$ART/selftest-case/control-noskill/prompt.md" && pass 'selftest: control prompt says the role loads no skill' || fail 'selftest: control prompt lacks the none line'
  [ "$(grep -c 'Role skill:' "$ART/selftest-case/code-reviewer/prompt.md")" -eq 2 ] && pass 'selftest: the with-skill prompt carries both role skills' || fail 'selftest: with-skill prompt wrong'
  [ "$(cat "$ART/selftest-case/code-reviewer/cost.txt")" = "0.020000" ] && pass 'selftest: cost summed from session usage' || fail "selftest: cost $(cat "$ART/selftest-case/code-reviewer/cost.txt")"
  # budget guard
  SPENT=9; BUDGET=1
  over_budget && pass 'selftest: the budget guard stops further runs' || fail 'selftest: budget guard did not trip'
  BUDGET="${FM_ROLE_LIVE_BUDGET:-}"
  rm -rf "$t"
  ART=''
}
# selftest_cases: every tests/live/*.sh case is checked OFFLINE, for free:
#   - its CASE_SKILL_ONLY_TOKENS exist in the role's skill text and nowhere the worker could
#     get them otherwise (ROLE.md, the prompt, the fixture files) - the problem can only be
#     solved by following the skill;
#   - case_canned <role> good|bad (a worker that followed / ignored the skill) is graded by the
#     real case_grade: good must pass, bad must fail, and good must have read every skill.
selftest_cases() {
  local c name roles role s tok t found src kind cfg skra skrb mech
  t=$(mktemp -d "${TMPDIR:-/tmp}/fm-roles-live-cases.XXXXXX") || return 1
  for c in "$CASES_DIR"/*.sh; do
    [ -f "$c" ] || continue
    name=$(basename "$c" .sh)
    if [ "${#SELFTEST_ONLY[@]}" -gt 0 ]; then case " ${SELFTEST_ONLY[*]} " in *" $name "*) ;; *) continue ;; esac; fi
    kind=$( ( . "$c"; printf '%s' "${CASE_KIND:-role}" ) )
    roles=$( ( . "$c"; printf '%s' "${CASE_ROLES:-${CASE_ROLE:-}}" ) )
    [ -n "$roles" ] || { fail "case $name: defines no CASE_ROLE/CASE_ROLES"; continue; }
    mech=$( ( . "$c"; printf '%s' "${CASE_MECHANISM:-}" ) )
    cfg=$CONFIG_ROOT skra="$CONFIG_ROOT/skills" skrb="$HOME/.agents/skills"
    if [ "$mech" = 1 ]; then
      cfg="$t/$name/config" skra="$t/$name/skills" skrb="$t/$name/skills"
      mkdir -p "$cfg/roles" "$skra"; ln -sfn "$CONFIG_ROOT/firstmate" "$cfg/firstmate"
      ( . "$c"; case_mechanism_setup "$cfg" "$skra" ) || { fail "case $name: case_mechanism_setup failed"; continue; }
    fi
    for role in $roles; do
      [ -f "$cfg/roles/$role/ROLE.md" ] && pass "case $name: role $role exists" || { fail "case $name: no role $role"; continue; }
    done
    [ "$kind" = mixed ] && { [ "$(printf '%s\n' $roles | grep -c .)" -eq 2 ] && pass "case $name: a mixed case names exactly two roles" || fail "case $name: mixed needs two roles"; }
    # fixture, for the token-exclusivity check
    REPO="$t/$name/fixture"; RUN="$t/$name/run"; mkdir -p "$REPO" "$RUN"
    ( cd "$REPO" && git init -q . && . "$c" && case_setup ) || { fail "case $name: case_setup failed"; continue; }
    local toks prompt
    toks=$( ( . "$c"; printf '%s' "${CASE_SKILL_ONLY_TOKENS:-}" ) )
    prompt=$( ( . "$c"; printf '%s' "${CASE_PROMPT:-}" ) )
    [ -n "$toks" ] && pass "case $name: declares skill-only tokens" || fail "case $name: no CASE_SKILL_ONLY_TOKENS"
    for tok in $toks; do
      found=0; src=''
      for role in $roles; do
        for s in $(FM_CONFIG_ROOT="$cfg" "$HANDOFF" --skills "$role"); do
          for d in "$skra/$s" "$skrb/$s"; do
            [ -d "$d" ] || continue
            src=$d
            grep -rqF -- "$tok" "$d/" 2>/dev/null && found=1
            break
          done
        done
      done
      if [ -z "$src" ]; then printf 'SKIP - case %s: no installed skill text to check token %s against\n' "$name" "$tok"; continue; fi
      [ $found = 1 ] && pass "case $name: token '$tok' is in the role's skill text" || fail "case $name: token '$tok' is NOT in the role's skill text"
      leak=0
      for role in $roles; do grep -qF -- "$tok" "$cfg/roles/$role/ROLE.md" && leak=1; done
      case $prompt in *"$tok"*) leak=1 ;; esac
      grep -rqF --exclude-dir=.git -- "$tok" "$REPO" && leak=1
      [ $leak = 0 ] && pass "case $name: token '$tok' appears in no ROLE.md, prompt or fixture file" || fail "case $name: token '$tok' leaks outside the skill text"
    done
    # canned good/bad workers through the real grader
    for role in $roles; do
      for mode in good bad; do
        rm -rf "$t/$name/$role-$mode"; mkdir -p "$t/$name/$role-$mode"
        REPO="$t/$name/$role-$mode/repo"; RUN="$t/$name/$role-$mode"; mkdir -p "$REPO"
        ( cd "$REPO" && git init -q . && git config user.email a@b && git config user.name a && . "$c" && case_setup && git add -A && git commit -q --allow-empty -m f ) || { fail "case $name: setup for $role-$mode failed"; continue; }
        : > "$RUN/calls.tsv"; : > "$RUN/final.txt"
        ( cd "$REPO" && . "$c" && RUN="$RUN" REPO="$REPO" case_canned "$role" "$mode" ) || { fail "case $name: case_canned $role $mode failed"; continue; }
        gr=$( cd "$REPO" && . "$c" && RUN="$RUN" REPO="$REPO" case_grade "$role" "$REPO" "$RUN" 2>&1 ); rc=$?
        if [ "$mode" = good ]; then
          [ $rc -eq 0 ] && pass "case $name: grader accepts a worker that followed the $role skill" || fail "case $name: grader rejected the canned good $role worker: $gr"
          for s in $(FM_CONFIG_ROOT="$cfg" "$HANDOFF" --skills "$role"); do
            ( RUN="$RUN"; skill_read "$s" ) && pass "case $name: canned good $role worker read $s" || fail "case $name: canned good worker never read $s"
          done
        else
          [ $rc -ne 0 ] && pass "case $name: grader rejects a worker that ignored the $role skill" || fail "case $name: grader accepted the canned bad $role worker"
        fi
      done
    done
  done
  rm -rf "$t"
}

command_selftest=0
SELFTEST_ONLY=()
if [ "${1:-}" = selftest ]; then command_selftest=1; SELFTEST_ONLY=("${@:2}"); fi
( selftest; exit "$failed" ) || failed=1
( selftest_cases; exit "$failed" ) || failed=1
if [ "$command_selftest" -eq 1 ]; then
  printf '\nROLES LIVE SELFTEST %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
  [ "$failed" -eq 0 ]; exit $?
fi

if [ "${FM_ROLE_LIVE:-}" != 1 ]; then
  printf 'SKIP - live role suite: set FM_ROLE_LIVE=1 to run real workers with your existing omp login; never reported as PASS\n\nROLES LIVE SELFTEST %s, LIVE SKIPPED\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
  [ "$failed" -eq 0 ]; exit $?
fi
if ! command -v "$OMP_BIN" >/dev/null 2>&1 || ! "$OMP_BIN" models --json --no-extensions 2>/dev/null | grep -q "\"selector\":\"$MODEL\""; then
  printf 'SKIP - live role suite: needs omp with %s available from the existing login; never reported as PASS\n' "$MODEL"
  exit 0
fi
STAMP=$(date -u +%Y%m%dT%H%M%SZ)-$$
ART="$ART_ROOT/$STAMP"
mkdir -p "$ART"
printf '# Live role results (%s, model %s)\n\n| case | skill read | outcome | control | cumulative USD |\n|---|---|---|---|---|\n' "$STAMP" "$MODEL" > "$ART/results.md"
if [ "$#" -gt 0 ]; then cases=("$@"); else cases=("$CASES_DIR"/*.sh); fi
for c in "${cases[@]}"; do
  case $c in */*) ;; *) c="$CASES_DIR/${c%.sh}.sh" ;; esac
  [ -f "$c" ] || { fail "no such live case: $c"; continue; }
  run_case "$c"
done
printf '\n%s\n' "$(cat "$ART/results.md")"
printf 'artifacts: %s  model: %s (thinking %s)  total cost: %s USD (budget %s)\n' "$ART" "$MODEL" "$THINKING" "$SPENT" "${BUDGET:-none}"
printf '\nROLES LIVE %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
