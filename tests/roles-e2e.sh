#!/usr/bin/env bash
# roles-e2e.sh - end-to-end role handoff through the REAL official dispatch
# path: for EACH role, bin/fm-brief.sh scaffolds a brief, this script plays the
# Captain (fills the Firstmate spec with bin/fm-role-handoff <role> and nothing
# else), and the unmodified official bin/fm-spawn.sh launches the task on a private
# tmux server into a real treehouse worktree. Only the `omp`
# executable is fake: it records the argv it was really launched with, which is
# the worker's FIRST input. Per role, that input must contain the ROLE.md path
# and exactly the role's autoloadSkills paths, and nothing the Captain selected.
#
# What this proves: the brief a real spawn delivers carries exactly the role
# handoff. It uses a FAKE omp, so it cannot prove that a model reads or applies
# any of it (see tests/roles-live.sh for that), or that the Captain picked the
# right role.
#
# ISOLATED LAB (tests/e2e-lib/lab.sh has the full list): safe on a machine with a live
# fleet, also when started from inside a fleet tmux pane or treehouse worktree. A private
# tmux server, a throwaway HOME / FM_HOME / TMPDIR / project (its treehouse pool lives in
# the project), `env -i` for every official script (no inherited TMUX or FM_*), recording
# shims for tmux and treehouse and deny-and-record shims for the fleet tools. The run ends
# with lab_guard's assertions over that record (every call was on the lab) and proves the
# lab is gone. Tear-down is idempotent and also called explicitly, so it holds under a
# harness that does not fire EXIT traps.
#
# SKIPs (never PASS) without tmux, treehouse, jq, or an official FirstMate checkout at
# $FIRSTMATE_ROOT (default ~/Developer/tools/firstmate). FIRSTMATE_ROOT also lets a
# deliberately broken launch be fed in: tests/e2e-lib/broken-firstmate.sh builds a
# FirstMate whose launch drops the role handoff, selects an extra skill, or leaves the
# lab; the suite must FAIL on each.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HANDOFF="$CONFIG_ROOT/bin/fm-role-handoff"
FM_ROOT="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"
# shellcheck source=tests/e2e-lib/lab.sh
. "$CONFIG_ROOT/tests/e2e-lib/lab.sh"

lab_prereq roles ROLES
lab_up roles

OPUS=anthropic/claude-opus-5-5
roles=$("$HANDOFF" --roles)
[ -n "$roles" ] || { fail 'no roles found'; lab_finish ROLES; exit 1; }

n=0
for role in $roles; do
  n=$((n + 1))
  id="fm-roles-e2e-$RUN-$n"
  want=$("$HANDOFF" --skills "$role")
  # 1. the real brief scaffold, then the Captain's fill: intent plus the role handoff only.
  if ! scaffold=$(lab_run "$FM_ROOT/bin/fm-brief.sh" "$id" projects/e2e-proj --mode local-only 2>&1); then
    fail "$role: real fm-brief.sh scaffold failed: $scaffold"; continue
  fi
  brief="$home/data/$id/brief.md"
  body=$(cat "$brief")
  intent="Fixture task for role $role; nothing here selects a skill."
  spec=$("$HANDOFF" "$role")
  body=${body/'{TASK}'/$intent}
  body=${body/'{FIRSTMATE_SPEC}'/$spec}
  printf '%s\n' "$body" > "$brief"
  # 2. the real spawn.
  if ! out=$(lab_run ${LAB_TMO[@]+"${LAB_TMO[@]}"} "$FM_ROOT/bin/fm-spawn.sh" "$id" projects/e2e-proj \
      --mode local-only --yolo off --harness omp --model "$OPUS" --effort high 2>&1); then
    fail "$role: real fm-spawn failed: $out"; continue
  fi
  meta=$(cat "$home/state/$id.meta" 2>/dev/null)
  wt=$(field "$meta" worktree)
  waited=0
  while [ ! -f "$wt/worker-argv.txt" ] && [ "$waited" -lt 150 ]; do sleep 0.1; waited=$((waited + 1)); done
  first=$(cat "$wt/worker-argv.txt" 2>/dev/null)
  if [ -z "$first" ]; then fail "$role: the fake worker recorded no first input"; continue; fi

  # 3. the worker's first input carries exactly the role handoff.
  has "$role: first input names the role" "$first" "Assigned role: $role"
  has "$role: first input carries the ROLE.md path with a read-and-apply requirement" "$first" "Role source:
  $CONFIG_ROOT/roles/$role/ROLE.md
Requirement:
  Read and apply this role file in full"
  got=$(printf '%s\n' "$first" | grep -o "$FM_SKILLS_ROOT/[A-Za-z0-9_-]*/SKILL.md" | sed "s#^$FM_SKILLS_ROOT/\(.*\)/SKILL.md#\1#")
  check "$role: first input names exactly the role's autoloadSkills paths, in order" "$got" "$want"
  check "$role: every skill path is a Role skill entry with its requirement" \
    "$(printf '%s\n' "$first" | grep -c '^Role skill:$')" "$(printf '%s' "$want" | grep -c .)"
  # The official scaffold's own completion-gate line names one FirstMate-internal
  # skill under $FM_ROOT/.agents/skills; that is not a Captain selection.
  check "$role: the first input names no other SKILL.md path (besides the scaffold's own FirstMate-internal one)" \
    "$(printf '%s\n' "$first" | grep -o '[^ ]*SKILL\.md' | tr -d '`' | grep -v "^$FM_SKILLS_ROOT/" | grep -vc "^$FM_ROOT/.agents/skills/")" 0
  lacks "$role: nothing selected by the Captain (no Selected shared worker skill)" "$first" 'Selected shared worker skill'
  lacks "$role: nothing selected by the Captain (no Required project skill)" "$first" 'Required project skill'
  if [ -z "$want" ]; then
    has "$role: a skill-less role says it loads none" "$first" 'Role skills:
  none'
  fi
  # 4. the derived trace agrees with what was really delivered. A role fixed to
  #    a category the fake spawn did not use is checked as a named override.
  printf '%s\n' "$first" > "$TMP/delivered-$n.txt"
  case $role in
    architecture) cat_n='ARCHITECTURE #1' why='e2e fixture' ;;
    tenth-man) cat_n='TENTH-MAN #1' why='captain override - e2e fixture spawns every role on one route' ;;
    *) cat_n='IMPLEMENT #2' why='e2e fixture' ;;
  esac
  skills_line=$(printf '%s' "$want" | paste -sd, - | sed 's/,/, /g')
  [ -n "$skills_line" ] || skills_line=none   # BSD paste prints nothing at all for empty input
  printf 'Routing: %s | role %s | omp | %s | high | why: %s\nAgent: %s\nSkills: %s\n' \
    "$cat_n" "$role" "$OPUS" "$why" "$role" "$skills_line" > "$TMP/trace-$n.txt"
  if "$CONFIG_ROOT/tests/routing-trace.sh" check "$TMP/trace-$n.txt" omp "$OPUS" high --brief "$TMP/delivered-$n.txt" > "$TMP/check-$n.out" 2>&1; then
    pass "$role: the derived trace agrees with the delivered brief (check --brief)"
  else
    fail "$role: trace check against the delivered brief failed: $(grep FAIL "$TMP/check-$n.out" | head -3 | tr '\n' ' ')"
  fi
done
[ "$n" -eq "$(printf '%s\n' "$roles" | grep -c .)" ] && pass "all $n roles went through the real brief and spawn path" || fail 'not every role was dispatched'

lab_finish ROLES
