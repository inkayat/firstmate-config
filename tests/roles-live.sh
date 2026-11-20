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
#                                        run the live cases (default: all in tests/live/); the pre-flight self-test
#                                        covers just the cases it runs
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
#   CASE_BODY_PHRASE='<ERE>'        optional, role cases only: the role body carries this behaviour ON PURPOSE
#                                   (distilled from the skill), so a control without the skill may pass. When set:
#                                   (a) the self-test asserts the ERE matches roles/<role>/ROLE.md, so the claim is
#                                   checked and the flag cannot hide a gap, and it skips the "skill-only token must
#                                   not be in ROLE.md" check for the case (the tokens must still be in the skill text);
#                                   (b) live, a control that PASSES is reported 'passes (role body carries it)' and
#                                   does not fail the case; the read check and the outcome check stay mandatory and a
#                                   control that fails is still 'fails (good)'. Quote the ROLE.md line in the case comment.
#   CASE_CONTROL_INFORMATIONAL='<reason>'  optional, role cases only, exclusive with CASE_BODY_PHRASE: the no-skill control passes
#                                   on the model's OWN BASELINE (the body does not carry the rule either), so this case proves only
#                                   that the skill was READ and the OUTCOME is right, not that the skill is needed. Read and outcome
#                                   stay mandatory; a control that passes is NOT a failure but is reported 'passes (model baseline;
#                                   informational)' with the reason in the results table and the live line; the self-test requires the
#                                   reason to be non-empty; a control that fails is still 'fails (good)'.
#   case_canned <role> good|bad     offline stand-in for a worker that followed / ignored the skill:
#                                   write $RUN/final.txt and $RUN/calls.tsv (tool<TAB>json args) and edit
#                                   the repo as such a worker would leave it. After a good canned worker the
#                                   harness itself appends a read call for every skill the role autoloads that
#                                   is missing from calls.tsv (a worker that followed the handoff reads them all).
#                                   The self-test grades both through case_grade: good must pass, bad must fail.
#   case_variants                   optional: prints TAB-separated lines <role> <good|bad> <mode> <ERE>; the self-test runs
#                                   case_canned <role> <mode> for each and grades it with case_grade <role>. A good variant must
#                                   pass; a bad one must fail with a reason matching the ERE. Every grader relaxation needs a bad
#                                   variant here that the relaxed grader still rejects (and a good one for the lawful form it admits).
#   Grader helpers: final_has <ERE>, final_lacks <ERE>, call_has <ERE> (any tool call argument),
#                   changed_files / changed_tracked / added_files (paths changed, resp. tracked-changed, resp. added,
#                   relative to the fixture commit: committed + uncommitted + untracked-not-ignored, so a role that
#                   commits is graded like one that does not), unchanged_since_base <path...>, skill_read <name>,
#                   sed_inplace <script> <file...> (portable in-place sed for canned workers).
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
# The fixture commit is recorded by the harness in $RUN/base.sha (case_setup may make its own commits; the base is
# the state the worker was handed, not the first commit of the repo).
base_rev() { cat "$RUN/base.sha" 2>/dev/null || git -C "$REPO" rev-list --max-parents=0 HEAD | tail -n 1; }
changed_tracked() { git -C "$REPO" diff --no-renames --name-only "$(base_rev)" --; }
changed_files() { { changed_tracked; git -C "$REPO" ls-files --others --exclude-standard; } | sort -u; }
added_files() { { git -C "$REPO" diff --no-renames --name-only --diff-filter=A "$(base_rev)" --; git -C "$REPO" ls-files --others --exclude-standard; } | sort -u; }
unchanged_since_base() { git -C "$REPO" diff --no-renames --quiet "$(base_rev)" -- "$@"; }
sed_inplace() { # <sed-script> <file...>: GNU and BSD sed disagree on -i, so write through a temp file
  local script=$1 f tmp; shift
  for f in "$@"; do
    tmp=$(mktemp "${TMPDIR:-/tmp}/fm-sedi.XXXXXX") && sed -e "$script" "$f" > "$tmp" && cat "$tmp" > "$f"
    rm -f "$tmp"
  done
}
# load_case <case-file>: source a case with nothing left over from a previously loaded one.
load_case() {
  unset CASE_KIND CASE_ROLE CASE_ROLES CASE_PROMPT CASE_SKILL_ONLY_TOKENS CASE_BODY_PHRASE CASE_CONTROL_INFORMATIONAL CASE_MECHANISM
  unset -f case_setup case_grade case_canned case_mechanism_setup case_variants 2>/dev/null
  # shellcheck source=/dev/null
  . "$1"
}
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

# run_one <case-file> <label> <role|""> <with|without> <grade-role> -> sets RUN, REPO, CFG; prints one result line
# Everything the worker can reach lives in a scratch dir OUTSIDE the checkout (fixture repo, skill copies, and a
# SANITIZED copy of the config root: roles, bin, firstmate, workflows, skills lock, top-level docs - never tests/), so
# the worker cannot read the judge, the fixtures or another run's grade. After grading, the repo is copied back into
# $RUN/repo for inspection and the scratch dir is removed.
run_one() {
  local case_file=$1 label=$2 role=$3 mode=$4 grade_role=$5 name fx scr wcfg
  name=$(basename "$case_file" .sh)
  RUN="$ART/$name/$label"
  scr=$(mktemp -d "${TMPDIR:-/tmp}/fm-roles-live.XXXXXX") || { fail "$name/$label: no scratch dir"; return 1; }
  REPO="$scr/repo"
  fx="$scr/home"
  wcfg="$scr/config"
  rm -rf "$RUN"
  mkdir -p "$REPO" "$fx/.agents/skills" "$RUN/session" "$wcfg"
  # Fixture-local skill copies: the worker can only read these.
  local s
  for s in "$SKILL_SRC"/*/; do s=$(basename "$s"); cp -rL "$SKILL_SRC/$s" "$fx/.agents/skills/$s" 2>/dev/null; done
  # addyosmani skills read ../../references/*.md, which resolves to <home>/.agents/references.
  [ ! -d "$(dirname "$SKILL_SRC")/references" ] || cp -rL "$(dirname "$SKILL_SRC")/references" "$fx/.agents/references" 2>/dev/null
  # Mechanism cases bring their own fixture-only config root (roles) and skills; the real roles/ is not used.
  local mech=0
  ( load_case "$case_file"; [ "${CASE_MECHANISM:-}" = 1 ] ) && mech=1
  if [ $mech = 1 ]; then
    mkdir -p "$wcfg/roles"; ln -sfn "$CONFIG_ROOT/firstmate" "$wcfg/firstmate"
    ( load_case "$case_file"; case_mechanism_setup "$wcfg" "$fx/.agents/skills" ) || { rm -rf "$scr"; fail "$name/$label: case_mechanism_setup failed"; return 1; }
  else
    ( cd "$CONFIG_ROOT" && tar -cf - roles bin firstmate workflows skills REVIEW.md README.md AGENTS.md 2>/dev/null ) | tar -xf - -C "$wcfg"
  fi
  CFG="$wcfg"
  # No credential handling: the worker uses the existing omp login in place (HOME is the real one).
  (
    cd "$REPO" || exit 1
    git init -q . && git config user.email live@example.invalid && git config user.name live
    printf '__pycache__/\n*.pyc\n' >> .git/info/exclude
    load_case "$case_file"
    case_setup
    git add -A && git commit -q --allow-empty -m fixture
    git rev-parse HEAD > "$RUN/base.sha"
  ) || { rm -rf "$scr"; fail "$name/$label: fixture setup failed"; return 1; }
  load_case "$case_file"
  build_prompt "$role" "$mode" "$CASE_PROMPT" "$fx/.agents/skills" > "$RUN/prompt.md"
  if over_budget; then rm -rf "$scr"; fail "$name/$label: budget $BUDGET USD reached (spent $SPENT); run not started"; return 1; fi
  ( cd "$REPO" && env -i HOME="$HOME" PATH="$PATH" TERM=dumb LANG=C.UTF-8 OMP_SKIP_SETUP=1 PYTHONDONTWRITEBYTECODE=1 \
      timeout 900 "$OMP_BIN" -p --model "$MODEL" --thinking "$THINKING" --no-extensions --no-skills --no-rules --no-context-files \
      --no-lsp --no-pty --no-title --tools read,grep,glob,bash,edit,write --system-prompt "$SYSTEM_PROMPT" \
      --session-dir "$RUN/session" ${COST_ARGS[@]+"${COST_ARGS[@]}"} --auto-approve --cwd "$REPO" "@$RUN/prompt.md" \
      > "$RUN/stdout.txt" 2> "$RUN/stderr.txt" ) || true
  parse_session "$RUN/session" "$RUN"
  spent_add "$(cat "$RUN/cost.txt")"
  load_case "$case_file"
  ( cd "$REPO" && case_grade "$grade_role" "$REPO" "$RUN" ) > "$RUN/grade.txt" 2>&1
  GRADE_RC=$?
  # keep the evidence, drop the scratch; later steps (run_case's skill list) use the real config root, or the fixture
  # config of a mechanism case, both of which now live under $RUN or the checkout
  cp -R "$REPO" "$RUN/repo" 2>/dev/null
  if [ $mech = 1 ]; then rm -rf "$RUN/config"; cp -R "$wcfg" "$RUN/config" 2>/dev/null; CFG="$RUN/config"; else CFG="$CONFIG_ROOT"; fi
  REPO="$RUN/repo"
  rm -rf "$scr"
  return 0
}

# run_case <case-file>: runs the with-skill run(s) and the control, prints the verdict row.
run_case() {
  local case_file=$1 name roles role read_ok=1 outcome_ok=1 control_ok=1 why='' s body control_col='fails (good)' info
  name=$(basename "$case_file" .sh)
  ( load_case "$case_file"; printf '%s|%s|%s\n' "${CASE_KIND:-role}" "${CASE_ROLES:-${CASE_ROLE:-}}" "${CASE_BODY_PHRASE:+body}" ) > "$ART/.kind"
  IFS='|' read -r kind roles body < "$ART/.kind"
  ( load_case "$case_file"; printf '%s' "${CASE_CONTROL_INFORMATIONAL:-}" ) > "$ART/.info"
  info=$(cat "$ART/.info")
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
  if [ "$GRADE_RC" -eq 0 ]; then
    if [ -n "$body" ]; then
      control_col='passes (role body carries it)'
    elif [ -n "$info" ]; then
      control_col="passes (model baseline; informational: $info)"
    else
      control_ok=0; control_col='PASSES (bad)'
      why="$why [control showed the skill-only behaviour: the problem does not discriminate]"
    fi
  fi
  printf '| %s | %s | %s | %s | %s |\n' "$name" "$( [ $read_ok = 1 ] && echo yes || echo NO)" \
    "$( [ $outcome_ok = 1 ] && echo pass || echo FAIL)" "$control_col" "$SPENT" >> "$ART/results.md"
  if [ $read_ok = 1 ] && [ $outcome_ok = 1 ] && [ $control_ok = 1 ]; then
    if [ -n "$body" ]; then
      pass "live $name: skill read, outcome carries the behaviour; control without the skill: $control_col"
    elif [ "$control_col" != 'fails (good)' ] && [ -n "$info" ]; then
      pass "live $name: skill read, outcome right; control without the skill: passes (model baseline; informational) - $info"
    else
      pass "live $name: skill read, outcome carries the skill-only behaviour, control without the skill does not"
    fi
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
  mkdir -p "$SKILL_SRC/code-review-and-quality" "$SKILL_SRC/ponytail-review" "$SKILL_SRC/karpathy-guidelines"
  : > "$SKILL_SRC/code-review-and-quality/SKILL.md"; : > "$SKILL_SRC/ponytail-review/SKILL.md"; : > "$SKILL_SRC/karpathy-guidelines/SKILL.md"
  mkdir -p "$t/live"
  cat > "$t/live/selftest-case.sh" <<'CASE'
CASE_KIND=role
CASE_ROLE=code-reviewer
CASE_PROMPT='review the fixture'
case_setup() { printf 'x\n' > a.txt; }
case_grade() { final_has 'MARKER-FOLLOWED' && [ -e selftest-marker.txt ] && { echo marker found; return 0; }; echo "no marker"; return 1; }
CASE
  SPENT=0
  # The fake reads only the FIRST code-reviewer skill; the others stay unread, so the
  # harness must report a missing read (read=NO) - proving the read check bites.
  out=$(run_case "$t/live/selftest-case.sh" 2>&1); rc=$?
  case $out in *"never read ponytail-review"*) pass 'selftest: a skill that was not read in the transcript fails the case' ;; *) fail "selftest: unread second skill not reported: $out" ;; esac
  [ -s "$ART/selftest-case/code-reviewer/calls.tsv" ] && pass 'selftest: tool calls parsed from the session jsonl' || fail 'selftest: no tool calls parsed'
  case $(cat "$ART/selftest-case/control-noskill/final.txt") in "done, no method") pass 'selftest: the control run really ran without the skill block' ;; *) fail 'selftest: control transcript wrong' ;; esac
  grep -q 'Role skill:' "$ART/selftest-case/control-noskill/prompt.md" && fail 'selftest: control prompt still carries a Role skill entry' || pass 'selftest: control prompt carries no Role skill entry'
  grep -q 'Role skills:' "$ART/selftest-case/control-noskill/prompt.md" && pass 'selftest: control prompt says the role loads no skill' || fail 'selftest: control prompt lacks the none line'
  [ "$(grep -c 'Role skill:' "$ART/selftest-case/code-reviewer/prompt.md")" -eq 3 ] && pass 'selftest: the with-skill prompt carries all three role skills' || fail 'selftest: with-skill prompt wrong'
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
#     solved by following the skill; a case with CASE_BODY_PHRASE (the role body carries the
#     behaviour on purpose) instead must have that ERE match every graded ROLE.md, and is exempt
#     from the ROLE.md half of this check only;
#   - case_canned <role> good|bad (a worker that followed / ignored the skill) is graded by the
#     real case_grade: good must pass, bad must fail. The harness completes a good worker's reads
#     (a read call on every autoloaded SKILL.md missing from its calls.tsv) before grading.
selftest_cases() {
  local c name roles role s tok t found src kind cfg skra skrb mech body leak gr rc infoset infoval
  t=$(mktemp -d "${TMPDIR:-/tmp}/fm-roles-live-cases.XXXXXX") || return 1
  for c in "$CASES_DIR"/*.sh; do
    [ -f "$c" ] || continue
    name=$(basename "$c" .sh)
    if [ "${#SELFTEST_ONLY[@]}" -gt 0 ]; then case " ${SELFTEST_ONLY[*]} " in *" $name "*) ;; *) continue ;; esac; fi
    kind=$( ( load_case "$c"; printf '%s' "${CASE_KIND:-role}" ) )
    roles=$( ( load_case "$c"; printf '%s' "${CASE_ROLES:-${CASE_ROLE:-}}" ) )
    [ -n "$roles" ] || { fail "case $name: defines no CASE_ROLE/CASE_ROLES"; continue; }
    mech=$( ( load_case "$c"; printf '%s' "${CASE_MECHANISM:-}" ) )
    body=$( ( load_case "$c"; printf '%s' "${CASE_BODY_PHRASE:-}" ) )
    cfg=$CONFIG_ROOT skra="$CONFIG_ROOT/skills" skrb=$SKILL_SRC
    if [ "$mech" = 1 ]; then
      cfg="$t/$name/config" skra="$t/$name/skills" skrb="$t/$name/skills"
      mkdir -p "$cfg/roles" "$skra"; ln -sfn "$CONFIG_ROOT/firstmate" "$cfg/firstmate"
      ( load_case "$c"; case_mechanism_setup "$cfg" "$skra" ) || { fail "case $name: case_mechanism_setup failed"; continue; }
    fi
    for role in $roles; do
      [ -f "$cfg/roles/$role/ROLE.md" ] && pass "case $name: role $role exists" || { fail "case $name: no role $role"; continue; }
    done
    [ "$kind" = mixed ] && { [ "$(printf '%s\n' $roles | grep -c .)" -eq 2 ] && pass "case $name: a mixed case names exactly two roles" || fail "case $name: mixed needs two roles"; }
    if [ -n "$body" ]; then
      [ "$kind" = mixed ] && fail "case $name: CASE_BODY_PHRASE is for role cases (a mixed control has no role body at all)"
      for role in $roles; do
        grep -Eq -- "$body" "$cfg/roles/$role/ROLE.md" \
          && pass "case $name: CASE_BODY_PHRASE matches roles/$role/ROLE.md (the body carries the behaviour)" \
          || fail "case $name: CASE_BODY_PHRASE '$body' does NOT match roles/$role/ROLE.md: the body does not carry the behaviour"
      done
    fi
    infoset=$( ( load_case "$c"; printf '%s' "${CASE_CONTROL_INFORMATIONAL+set}" ) )
    if [ -n "$infoset" ]; then
      infoval=$( ( load_case "$c"; printf '%s' "${CASE_CONTROL_INFORMATIONAL:-}" ) )
      [ -n "$infoval" ] && pass "case $name: CASE_CONTROL_INFORMATIONAL carries a reason" || fail "case $name: CASE_CONTROL_INFORMATIONAL is set but the reason is empty"
      [ "$kind" = mixed ] && fail "case $name: CASE_CONTROL_INFORMATIONAL is for role cases (a mixed control has no role body at all)"
      [ -z "$body" ] || fail "case $name: CASE_CONTROL_INFORMATIONAL and CASE_BODY_PHRASE are exclusive: the body either carries the rule or the baseline does"
    fi
    # fixture, for the token-exclusivity check
    REPO="$t/$name/fixture"; RUN="$t/$name/run"; mkdir -p "$REPO" "$RUN"
    ( cd "$REPO" && git init -q . && load_case "$c" && case_setup ) || { fail "case $name: case_setup failed"; continue; }
    local toks prompt
    toks=$( ( load_case "$c"; printf '%s' "${CASE_SKILL_ONLY_TOKENS:-}" ) )
    prompt=$( ( load_case "$c"; printf '%s' "${CASE_PROMPT:-}" ) )
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
      if [ -z "$body" ]; then for role in $roles; do grep -qF -- "$tok" "$cfg/roles/$role/ROLE.md" && leak=1; done; fi
      case $prompt in *"$tok"*) leak=1 ;; esac
      grep -rqF --exclude-dir=.git -- "$tok" "$REPO" && leak=1
      if [ -n "$body" ]; then
        [ $leak = 0 ] && pass "case $name: token '$tok' appears in no prompt or fixture file (ROLE.md exempt: CASE_BODY_PHRASE)" || fail "case $name: token '$tok' leaks into the prompt or fixture"
      else
        [ $leak = 0 ] && pass "case $name: token '$tok' appears in no ROLE.md, prompt or fixture file" || fail "case $name: token '$tok' leaks outside the skill text"
      fi
    done
    # canned good/bad workers through the real grader, then the case's named variants
    for role in $roles; do
      selftest_canned "$c" "$t" "$name" "$cfg" "$role" good good
      selftest_canned "$c" "$t" "$name" "$cfg" "$role" bad bad
    done
    # case_variants prints one line per extra canned worker: <role> TAB <good|bad> TAB <mode passed to case_canned> TAB <ERE the rejection must match>.
    # Every grader relaxation needs a bad variant here that the relaxed grader still rejects, for the reason named.
    if ( load_case "$c"; declare -F case_variants >/dev/null ); then
      while IFS="$(printf '\t')" read -r role kind mode why; do
        [ -n "$mode" ] || continue
        case " $roles " in *" $role "*) ;; *) fail "case $name: case_variants names role '$role', which the case does not run"; continue ;; esac
        case $kind in good|bad) ;; *) fail "case $name: case_variants line [$role $kind $mode] must say good or bad"; continue ;; esac
        selftest_canned "$c" "$t" "$name" "$cfg" "$role" "$mode" "$kind" "$why"
      done <<EOF
$( load_case "$c"; case_variants )
EOF
    fi
  done
  rm -rf "$t"
}

# selftest_canned <case-file> <tmpdir> <name> <config-root> <role> <mode> <good|bad> [reason ERE]: one canned worker through the real grader.
# A good worker must pass (and, in mode good, have read every skill); a bad one must fail, for the reason when one is given.
selftest_canned() {
  local c=$1 t=$2 name=$3 cfg=$4 role=$5 mode=$6 expect=$7 why=${8:-} s gr rc
  rm -rf "$t/$name/$role-$mode"; mkdir -p "$t/$name/$role-$mode"
  REPO="$t/$name/$role-$mode/repo"; RUN="$t/$name/$role-$mode"; mkdir -p "$REPO"
  ( cd "$REPO" && git init -q . && git config user.email a@b && git config user.name a && load_case "$c" && case_setup && git add -A && git commit -q --allow-empty -m f && git rev-parse HEAD > "$RUN/base.sha" ) || { fail "case $name: setup for $role-$mode failed"; return; }
  : > "$RUN/calls.tsv"; : > "$RUN/final.txt"
  ( cd "$REPO" && load_case "$c" && RUN="$RUN" REPO="$REPO" case_canned "$role" "$mode" ) || { fail "case $name: case_canned $role $mode failed"; return; }
  if [ "$expect" = good ]; then
    for s in $(FM_CONFIG_ROOT="$cfg" "$HANDOFF" --skills "$role"); do
      ( RUN="$RUN"; skill_read "$s" ) || printf 'read\t{"path":"/fixture-home/.agents/skills/%s/SKILL.md"}\n' "$s" >> "$RUN/calls.tsv"
    done
  fi
  gr=$( cd "$REPO" && load_case "$c" && RUN="$RUN" REPO="$REPO" case_grade "$role" "$REPO" "$RUN" 2>&1 ); rc=$?
  if [ "$expect" = good ]; then
    [ $rc -eq 0 ] && pass "case $name: grader accepts a worker that followed the $role skill ($mode)" || fail "case $name: grader rejected the canned $mode $role worker: $gr"
    for s in $(FM_CONFIG_ROOT="$cfg" "$HANDOFF" --skills "$role"); do
      ( RUN="$RUN"; skill_read "$s" ) && pass "case $name: canned $mode $role worker read $s" || fail "case $name: canned $mode worker never read $s"
    done
  elif [ $rc -eq 0 ]; then
    fail "case $name: grader accepted the canned $mode $role worker"
  elif [ -n "$why" ] && ! printf '%s' "$gr" | grep -E -i -q -- "$why"; then
    fail "case $name: the bad $role worker $mode was rejected, but not for its reason /$why/: $(printf '%s' "$gr" | cut -c1-200)"
  else
    pass "case $name: grader rejects a worker that ignored the $role skill ($mode): $(printf '%s' "$gr" | tr '\n' ' ' | cut -c1-110)"
  fi
}

command_selftest=0
SELFTEST_ONLY=()
if [ "${1:-}" = selftest ]; then command_selftest=1; SELFTEST_ONLY=("${@:2}")
else for a in "$@"; do SELFTEST_ONLY+=("$(basename "${a%.sh}")"); done   # a live run's pre-flight selftest covers just the cases it will run
fi
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
STAMP=$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM
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
