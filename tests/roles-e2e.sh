#!/usr/bin/env bash
# roles-e2e.sh - end-to-end role handoff through the REAL official dispatch
# path: for EACH role, bin/fm-brief.sh scaffolds a brief, this script plays the
# Captain (fills the Firstmate spec with bin/fm-role-handoff <role> and nothing
# else), and the unmodified official bin/fm-spawn.sh launches the task on an
# isolated tmux server into a real treehouse worktree. Only the `omp`
# executable is fake: it records the argv it was really launched with, which is
# the worker's FIRST input. Per role, that input must contain the ROLE.md path
# and exactly the role's autoloadSkills paths, and nothing the Captain selected.
#
# What this proves: the brief a real spawn delivers carries exactly the role
# handoff. What it cannot prove: that a model reads or applies any of it (see
# tests/roles-live.sh for that), or that the Captain picked the right role.
#
# SKIPs (never PASS) without tmux, treehouse, or an official FirstMate checkout
# at $FIRSTMATE_ROOT (default ~/Developer/tools/firstmate).
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HANDOFF="$CONFIG_ROOT/bin/fm-role-handoff"
FM_ROOT="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"

if ! command -v tmux >/dev/null 2>&1 || ! command -v treehouse >/dev/null 2>&1 \
   || [ ! -x "$FM_ROOT/bin/fm-spawn.sh" ] || [ ! -x "$FM_ROOT/bin/fm-brief.sh" ]; then
  printf 'SKIP - roles e2e: needs tmux, treehouse, and %s/bin/fm-{brief,spawn}.sh (never reported as PASS)\n\nROLES E2E SKIPPED\n' "$FM_ROOT"
  exit 0
fi

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$3', got '$2')"; fi; }
has() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3')" ;; esac; }
lacks() { case $2 in *"$3"*) fail "$1 (unexpected '$3')" ;; *) pass "$1" ;; esac; }
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-roles-e2e.XXXXXX") || exit 1
TMP=$(cd "$TMP" && pwd)
RUN=$$
SEAM_TMUX=$(mktemp -d /tmp/fm-roles-tmux.XXXXXX) || exit 1
cleanup() {
  TMUX_TMPDIR="$SEAM_TMUX" tmux kill-server >/dev/null 2>&1 || true
  sleep 0.3
  chmod -R u+w "$TMP" "$SEAM_TMUX" /tmp/fm-roles-e2e-"$RUN"-* /tmp/fm-roles-e2e-"$RUN"-*+* 2>/dev/null
  rm -rf "$TMP" "$SEAM_TMUX" /tmp/fm-roles-e2e-"$RUN"-* /tmp/fm-roles-e2e-"$RUN"-*+*
}
trap cleanup EXIT

export FM_CONFIG_ROOT="$CONFIG_ROOT" FM_SKILLS_ROOT="$TMP/home/.agents/skills"
home="$TMP/fm-home"
proj="$home/projects/e2e-proj"
mkdir -p "$home/state" "$home/config" "$home/data" "$TMP/home" "$TMP/bin" "$proj"
printf 'manual\n' > "$home/config/backlog-backend"
printf '# E2E project\n' > "$proj/AGENTS.md"
printf 'max_trees = 24\nroot = "./"\n' > "$proj/treehouse.toml"
git -C "$proj" init -q
git -C "$proj" add -A
git -C "$proj" -c user.email=t@example.invalid -c user.name=t commit -q -m init

cat > "$TMP/bin/omp" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = --help ] && { printf 'usage: omp [options] [prompt]\n'; exit 0; }
if [ "${1:-}" = models ]; then
  printf '{"models":[{"provider":"anthropic","id":"claude-opus-5-5","selector":"anthropic/claude-opus-5-5"},{"provider":"anthropic","id":"claude-sonnet-5-5","selector":"anthropic/claude-sonnet-5-5"}]}\n'
  exit 0
fi
printf '%s\n' "$@" > worker-argv.tmp
mv worker-argv.tmp worker-argv.txt
SH
chmod +x "$TMP/bin/omp"

OPUS=anthropic/claude-opus-5-5
SPAWN_ENV=(TMUX_TMPDIR="$SEAM_TMUX" PATH="$TMP/bin:$PATH" HOME="$TMP/home" FM_HOME="$home" FM_BACKEND=tmux)
roles=$("$HANDOFF" --roles)
[ -n "$roles" ] || { fail 'no roles found'; exit 1; }

n=0
for role in $roles; do
  n=$((n + 1))
  id="fm-roles-e2e-$RUN-$n"
  want=$("$HANDOFF" --skills "$role")
  # 1. the real brief scaffold, then the Captain's fill: intent plus the role handoff only.
  if ! scaffold=$(env "${SPAWN_ENV[@]}" "$FM_ROOT/bin/fm-brief.sh" "$id" projects/e2e-proj --mode local-only 2>&1); then
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
  if ! out=$(env "${SPAWN_ENV[@]}" timeout 90 "$FM_ROOT/bin/fm-spawn.sh" "$id" projects/e2e-proj \
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
  printf 'Routing: %s | role %s | omp | %s | high | why: %s\nAgent: %s\nSkills: %s\n' \
    "$cat_n" "$role" "$OPUS" "$why" "$role" \
    "$(printf '%s' "$want" | paste -sd, - | sed 's/,/, /g; s/^$/none/')" > "$TMP/trace-$n.txt"
  if "$CONFIG_ROOT/tests/routing-trace.sh" check "$TMP/trace-$n.txt" omp "$OPUS" high --brief "$TMP/delivered-$n.txt" > "$TMP/check-$n.out" 2>&1; then
    pass "$role: the derived trace agrees with the delivered brief (check --brief)"
  else
    fail "$role: trace check against the delivered brief failed: $(grep FAIL "$TMP/check-$n.out" | head -3 | tr '\n' ' ')"
  fi
done
[ "$n" -eq "$(printf '%s\n' "$roles" | grep -c .)" ] && pass "all $n roles went through the real brief and spawn path" || fail 'not every role was dispatched'

printf '\nROLES E2E %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
