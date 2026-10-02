#!/usr/bin/env bash
# update.sh - fixture-based acceptance for `fm update`.
#
# Every scenario runs against throwaway local Git repositories: a bare
# "official FirstMate" remote plus a clone acting as FIRSTMATE_ROOT, and a bare
# firstmate-config remote plus a clone acting as the installed checkout. The
# real FIRSTMATE_ROOT and the real clone are never read or mutated: each run
# passes an explicit fixture FIRSTMATE_ROOT and a fixture HOME (so no machine
# env file is sourced), and no network remote is contacted. Each config
# fixture tracks a manifest generated from the real one with firstmate_repo
# pointed at the bare official fixture remote.
#
# Each fixture checkout carries a fake install.sh - never the real one, which
# needs the real toolchain (git/pi/omp/herdr) - that logs every invocation to
# WORKFLOW_LOG, records the official checkout's HEAD at install time to
# OFFICIAL_SEEN, and reconciles a single tracked "managed artifact" file into
# a fixture MACHINE_DIR. This proves fm-update fast-forwards the official
# checkout first, then invokes the *pulled* checkout's installer and verifier
# in sequence, and that a newly tracked artifact converges to the machine in
# the same `fm update` invocation, without touching the real machine.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0
pass(){ printf 'ok   - %s\n' "$1"; }
fail(){ printf 'FAIL - %s\n' "$1" >&2; failed=1; }
contains(){ case $2 in *"$3"*) pass "$1";; *) fail "$1 (missing '$3' in: $2)";; esac; }
lacks(){ case $2 in *"$3"*) fail "$1 (unexpected '$3' in: $2)";; *) pass "$1";; esac; }
equals(){ if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$3', got '$2')"; fi; }
nonzero(){ if [ "$2" -ne 0 ]; then pass "$1"; else fail "$1 (expected nonzero exit, got 0)"; fi; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-update-test.XXXXXX") || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT
HOME_FIXTURE="$TMP_ROOT/home"; mkdir -p "$HOME_FIXTURE"

git_q(){ git -C "$1" -c user.email=test@example.invalid -c user.name=Test "${@:2}"; }
head_of(){ git -C "$1" rev-parse HEAD; }
tracking_of(){ git -C "$1" rev-parse refs/remotes/origin/main; }

# A fresh official remote + FIRSTMATE_ROOT clone and a fresh config remote +
# installed-checkout clone per scenario. Prints the config clone; its official
# clone is "<config clone>-official".
make_pair(){ # <name>
  local remote="$TMP_ROOT/$1.git" clone="$TMP_ROOT/$1"
  local official_remote="$TMP_ROOT/$1-official.git" official_seed="$TMP_ROOT/$1-official-seed"
  git init -q --bare "$official_remote"
  git -C "$official_remote" symbolic-ref HEAD refs/heads/main
  git init -q "$official_seed"
  printf 'official instructions v1\n' > "$official_seed/AGENTS.md"
  git_q "$official_seed" add -A
  git_q "$official_seed" commit -q -m init
  git_q "$official_seed" branch -M main
  git_q "$official_seed" push -q "$official_remote" main
  git clone -q "$official_remote" "$clone-official"
  git_q "$clone-official" config user.email test@example.invalid
  git_q "$clone-official" config user.name Test

  git init -q --bare "$remote"
  local seed="$TMP_ROOT/$1-seed"
  git init -q "$seed"
  printf 'base\n' > "$seed/file.txt"
  # The seed is the installed-style checkout: it carries the real CLI files
  # plus a fake install.sh standing in for the real one.
  mkdir -p "$seed/bin" "$seed/firstmate"
  cp "$CONFIG_ROOT/bin/fm" "$CONFIG_ROOT/bin/fm-update" "$seed/bin/"
  cp "$CONFIG_ROOT/firstmate/fm-captain-lib.sh" "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh" "$seed/firstmate/"
  awk -F '\t' -v OFS='\t' -v url="$official_remote" '$1 == "firstmate_repo" { $2 = url } { print }' \
    "$CONFIG_ROOT/firstmate/stack-manifest.tsv" > "$seed/firstmate/stack-manifest.tsv"
  cat > "$seed/install.sh" <<'SH'
#!/usr/bin/env bash
set -u
root=$(cd "$(dirname "$0")" && pwd)
: "${MACHINE_DIR:?MACHINE_DIR is required}"
: "${WORKFLOW_LOG:?WORKFLOW_LOG is required}"
mkdir -p "$MACHINE_DIR"
marker="$root/managed-artifact.txt"
if [ "${1:-}" = --verify ]; then
  printf 'verify\n' >> "$WORKFLOW_LOG"
  [ "${FAIL_STAGE:-}" != verify ] || { printf 'fixture verify command failed\n' >&2; exit 9; }
  drift=0
  if [ -f "$marker" ]; then
    want=$(cat "$marker")
    have=$(cat "$MACHINE_DIR/launcher" 2>/dev/null || printf '')
    [ "$want" = "$have" ] || drift=$((drift + 1))
  fi
  [ "${FORCE_DRIFT:-}" != 1 ] || drift=$((drift + 1))
  printf 'verify: %s drift item(s), 0 failure(s)\n' "$drift"
  exit 0
fi
printf 'install\n' >> "$WORKFLOW_LOG"
git -C "$FIRSTMATE_ROOT" rev-parse HEAD > "$OFFICIAL_SEEN"
[ "${FAIL_STAGE:-}" != install ] || { printf 'fixture install failed\n' >&2; exit 7; }
changed=0
if [ -f "$marker" ]; then
  want=$(cat "$marker")
  have=$(cat "$MACHINE_DIR/launcher" 2>/dev/null || printf '')
  if [ "$want" != "$have" ]; then
    printf '%s' "$want" > "$MACHINE_DIR/launcher"
    changed=1
  fi
fi
printf 'install: %s change(s), 0 failure(s)\n' "$changed"
SH
  chmod +x "$seed/install.sh"
  git_q "$seed" add -A
  git_q "$seed" commit -q -m init
  git_q "$seed" branch -M main
  git_q "$seed" remote add origin "$remote"
  git_q "$seed" push -q origin main
  git clone -q "$remote" "$clone"
  git_q "$clone" config user.email test@example.invalid
  git_q "$clone" config user.name Test
  printf '%s\n' "$clone"
}

# Land a new config upstream commit without touching the checkout under test.
# An optional second argument becomes the content of a newly tracked
# managed-artifact.txt - the exact "old checkout -> new origin/main that adds
# a machine-local managed artifact" transition the regression covers.
advance_remote(){ # <name> [managed-artifact-content]
  local work="$TMP_ROOT/$1-push"
  rm -rf "$work"
  git clone -q "$TMP_ROOT/$1.git" "$work"
  printf 'upstream change\n' >> "$work/file.txt"
  [ -z "${2:-}" ] || printf '%s' "$2" > "$work/managed-artifact.txt"
  git_q "$work" add -A
  git_q "$work" commit -q -m 'upstream commit'
  git_q "$work" push -q origin main
  git -C "$work" rev-parse --short HEAD
}

# Land a new commit on a bare official remote's main; prints its full SHA.
advance_official(){ # <bare-remote> <label>
  local work="$TMP_ROOT/official-push-$2"
  rm -rf "$work"
  git clone -q "$1" "$work"
  printf 'official instructions %s\n' "$2" >> "$work/AGENTS.md"
  git_q "$work" commit -q -am "official $2"
  git_q "$work" push -q origin main
  git -C "$work" rev-parse HEAD
}

# OFFICIAL_ROOT overrides the FIRSTMATE_ROOT passed to one run.
run_update(){ # <clone> <machine_dir> <workflow_log> [fail_stage] [force_drift] [args...]
  local clone=$1 machine_dir=$2 workflow_log=$3 fail_stage=${4:-} force_drift=${5:-}
  shift; shift; shift; [ "$#" -eq 0 ] || shift; [ "$#" -eq 0 ] || shift
  : > "$workflow_log"; rm -f "$workflow_log.official"
  HOME="$HOME_FIXTURE" FM_HOME="$TMP_ROOT/fm-home" PATH="/usr/bin:/bin" \
    FIRSTMATE_ROOT="${OFFICIAL_ROOT:-$clone-official}" OFFICIAL_SEEN="$workflow_log.official" \
    MACHINE_DIR="$machine_dir" WORKFLOW_LOG="$workflow_log" \
    FAIL_STAGE="$fail_stage" FORCE_DRIFT="$force_drift" \
    "$clone/bin/fm" update "$@" 2>&1
}

# One refused run: nonzero, explained, neither checkout changed, no install.
expect_refusal(){ # <label> <clone> <expected-text>
  local clone=$2 official=${OFFICIAL_ROOT:-$2-official}
  local c_head c_status f_head f_status out status log="$TMP_ROOT/refusal.workflow"
  c_head=$(head_of "$clone"); c_status=$(git -C "$clone" status --porcelain)
  f_head=$(head_of "$official"); f_status=$(git -C "$official" status --porcelain)
  out=$(run_update "$clone" "$TMP_ROOT/refusal-machine" "$log"); status=$?
  nonzero "$1 exits nonzero" "$status"
  contains "$1 explains the refusal" "$out" "$3"
  contains "$1 says nothing was changed" "$out" 'nothing was changed'
  lacks "$1 is not a partial update" "$out" 'PARTIAL UPDATE'
  equals "$1 keeps the official HEAD" "$(head_of "$official")" "$f_head"
  equals "$1 keeps the official working tree" "$(git -C "$official" status --porcelain)" "$f_status"
  equals "$1 creates no official stash" "$(git -C "$official" stash list)" ''
  equals "$1 keeps the config HEAD" "$(head_of "$clone")" "$c_head"
  equals "$1 keeps the config working tree" "$(git -C "$clone" status --porcelain)" "$c_status"
  equals "$1 never runs install.sh" "$(cat "$log")" ''
}

# --- both checkouts, success paths ------------------------------------------

# 1. Both current: a safe no-op that still reconciles and verifies the
# machine (the exact gap Betao hit: a stale machine needs no separate
# manual ./install.sh even when the repository itself has nothing to pull).
clone=$(make_pair current)
machine="$TMP_ROOT/current-machine"; log="$TMP_ROOT/current.workflow"
out=$(run_update "$clone" "$machine" "$log"); status=$?
equals 'already-current exits 0' "$status" 0
contains 'already-current reports official no change' "$out" 'Official FirstMate already up to date'
contains 'already-current reports config no change' "$out" 'Already up to date: main'
equals 'already-current still runs install then verify' \
  "$(cat "$log")" "$(printf 'install\nverify')"
contains 'already-current verify reports 0 drift' "$out" 'verify: 0 drift item(s), 0 failure(s)'
contains 'already-current reports completion' "$out" \
  'fm update complete: official FirstMate already up to date; firstmate-config already up to date'
lacks 'already-current prints no restart note' "$out" 'end the Captain session'

# 2. Config ahead, official current: fast-forward, then install.sh +
# install.sh --verify run in the same invocation and reconcile a newly
# tracked managed artifact.
clone=$(make_pair ahead)
old=$(git -C "$clone" rev-parse --short HEAD)
machine="$TMP_ROOT/ahead-machine"; log="$TMP_ROOT/ahead.workflow"
new=$(advance_remote ahead 'ponytail-update-launcher-v2')
out=$(run_update "$clone" "$machine" "$log"); status=$?
equals 'fast-forward exits 0' "$status" 0
contains 'fast-forward reports the old commit' "$out" "$old"
contains 'fast-forward reports the new commit' "$out" "$new"
equals 'fast-forward moved HEAD to the remote tip' \
  "$(git -C "$clone" rev-parse --short HEAD)" "$new"
equals 'fast-forward runs install then verify in the same invocation' \
  "$(cat "$log")" "$(printf 'install\nverify')"
equals 'fast-forward reconciles the newly tracked managed artifact' \
  "$(cat "$machine/launcher" 2>/dev/null)" 'ponytail-update-launcher-v2'
contains 'fast-forward verify reports 0 drift after reconciling' \
  "$out" 'verify: 0 drift item(s), 0 failure(s)'

# 3. Both ahead: the official checkout is fast-forwarded first, then the
# config checkout, then install/verify; nothing is pushed, other official
# branches are untouched, and the Captain restart guidance is printed.
clone=$(make_pair both); official="$clone-official"
git_q "$official" switch -q -c local-work
printf 'local branch work\n' > "$official/local.txt"
git_q "$official" add local.txt
git_q "$official" commit -q -m 'unlanded work on another branch'
local_work=$(head_of "$official")
git_q "$official" switch -q main
f_new=$(advance_official "$TMP_ROOT/both-official.git" v2)
new=$(advance_remote both)
official_refs=$(git -C "$TMP_ROOT/both-official.git" for-each-ref)
config_refs=$(git -C "$TMP_ROOT/both.git" for-each-ref)
machine="$TMP_ROOT/both-machine"; log="$TMP_ROOT/both.workflow"
out=$(run_update "$clone" "$machine" "$log"); status=$?
equals 'both-ahead exits 0' "$status" 0
equals 'both-ahead moves the official checkout to its tip' "$(head_of "$official")" "$f_new"
contains 'both-ahead brings the new official instructions' "$(cat "$official/AGENTS.md")" 'official instructions v2'
equals 'both-ahead moves the config checkout to its tip' "$(git -C "$clone" rev-parse --short HEAD)" "$new"
equals 'both-ahead install already sees the updated official checkout' \
  "$(cat "$log.official" 2>/dev/null)" "$f_new"
equals 'both-ahead runs install then verify' "$(cat "$log")" "$(printf 'install\nverify')"
case $out in
  *'Updated official FirstMate main'*'Updated main'*) pass 'both-ahead updates official before config' ;;
  *) fail "both-ahead updates official before config (got: $out)" ;;
esac
contains 'both-ahead reports completion' "$out" 'fm update complete: official FirstMate'
contains 'both-ahead explains the Captain must be restarted' "$out" 'end the Captain session, then run fm again'
contains 'both-ahead says secondmates were not updated' "$out" 'Secondmates and projects were not updated'
lacks 'both-ahead is not a partial update' "$out" 'PARTIAL UPDATE'
equals 'both-ahead leaves other official branches alone' "$(git -C "$official" rev-parse local-work)" "$local_work"
equals 'both-ahead never writes to the official remote' "$(git -C "$TMP_ROOT/both-official.git" for-each-ref)" "$official_refs"
equals 'both-ahead never writes to the config remote' "$(git -C "$TMP_ROOT/both.git" for-each-ref)" "$config_refs"
out=$(run_update "$clone" "$machine" "$log"); status=$?
equals 'both-ahead second run exits 0' "$status" 0
contains 'both-ahead second run reports official current' "$out" 'Official FirstMate already up to date'

# --- config refusals: checked before the official checkout changes ----------

# 4. Uncommitted config changes, official ahead: refuse, change neither.
clone=$(make_pair dirty)
advance_remote dirty >/dev/null
advance_official "$TMP_ROOT/dirty-official.git" v2 >/dev/null
printf 'local edit\n' >> "$clone/file.txt"
expect_refusal 'dirty config checkout' "$clone" 'uncommitted'
contains 'dirty config checkout keeps the local edit' "$(cat "$clone/file.txt")" 'local edit'

# 5. Diverged config branch, official ahead: refuse, change neither.
clone=$(make_pair diverged)
advance_remote diverged >/dev/null
advance_official "$TMP_ROOT/diverged-official.git" v2 >/dev/null
printf 'local commit\n' >> "$clone/file.txt"
git_q "$clone" commit -q -am 'local only commit'
expect_refusal 'diverged config branch' "$clone" 'diverged'

# 6. Detached config checkout, official ahead: refuse, change neither.
clone=$(make_pair config-detached)
advance_official "$TMP_ROOT/config-detached-official.git" v2 >/dev/null
git -C "$clone" checkout -q --detach
expect_refusal 'detached config checkout' "$clone" 'detached HEAD'

# --- install/verify failures --------------------------------------------------

# 7. Pull succeeds, install.sh fails: nonzero exit, but the repository still
# advanced (fm-update never re-implements install.sh's own logic to route
# around its failure). Official current, so this is not a partial update.
clone=$(make_pair install-fail)
new=$(advance_remote install-fail)
machine="$TMP_ROOT/install-fail-machine"; log="$TMP_ROOT/install-fail.workflow"
out=$(run_update "$clone" "$machine" "$log" install); status=$?
nonzero 'install failure exits nonzero' "$status"
contains 'install failure names install.sh' "$out" 'install.sh failed'
equals 'install failure still advanced the repository' \
  "$(git -C "$clone" rev-parse --short HEAD)" "$new"
equals 'install failure runs install but never reaches verify' "$(cat "$log")" install
lacks 'install failure with official current is not partial' "$out" 'PARTIAL UPDATE'
lacks 'install failure never claims completion' "$out" 'fm update complete'

# 8. Official advanced, then install.sh fails: reported as a PARTIAL UPDATE.
clone=$(make_pair partial-install)
f_old=$(git -C "$clone-official" rev-parse --short HEAD)
f_new=$(advance_official "$TMP_ROOT/partial-install-official.git" v2)
advance_remote partial-install >/dev/null
machine="$TMP_ROOT/partial-install-machine"; log="$TMP_ROOT/partial-install.workflow"
out=$(run_update "$clone" "$machine" "$log" install); status=$?
nonzero 'partial install failure exits nonzero' "$status"
contains 'partial install failure names install.sh' "$out" 'install.sh failed'
contains 'partial install failure is reported as partial' "$out" \
  "PARTIAL UPDATE: official FirstMate was fast-forwarded ($f_old -> ${f_new:0:${#f_old}})"
contains 'partial install failure explains the Captain restart' "$out" 'end the Captain session'
lacks 'partial install failure never claims completion' "$out" 'fm update complete'
equals 'partial install failure keeps the official fast-forward' "$(head_of "$clone-official")" "$f_new"

# 9. Pull and install succeed, install.sh --verify reports drift: nonzero exit.
clone=$(make_pair verify-drift)
advance_remote verify-drift >/dev/null
machine="$TMP_ROOT/verify-drift-machine"; log="$TMP_ROOT/verify-drift.workflow"
out=$(run_update "$clone" "$machine" "$log" '' 1); status=$?
nonzero 'post-install verify drift exits nonzero' "$status"
contains 'post-install verify drift explains the refusal' "$out" 'drift'
equals 'post-install verify drift runs install then verify' \
  "$(cat "$log")" "$(printf 'install\nverify')"

# 10. Official advanced, then verify drift: also a PARTIAL UPDATE.
clone=$(make_pair partial-drift)
advance_official "$TMP_ROOT/partial-drift-official.git" v2 >/dev/null
machine="$TMP_ROOT/partial-drift-machine"; log="$TMP_ROOT/partial-drift.workflow"
out=$(run_update "$clone" "$machine" "$log" '' 1); status=$?
nonzero 'partial verify drift exits nonzero' "$status"
contains 'partial verify drift names the drift' "$out" 'reported drift'
contains 'partial verify drift is reported as partial' "$out" 'PARTIAL UPDATE'
lacks 'partial verify drift never claims completion' "$out" 'fm update complete'

# 11. Pull and install succeed, install.sh --verify itself fails: nonzero exit.
clone=$(make_pair verify-fail)
advance_remote verify-fail >/dev/null
machine="$TMP_ROOT/verify-fail-machine"; log="$TMP_ROOT/verify-fail.workflow"
out=$(run_update "$clone" "$machine" "$log" verify); status=$?
nonzero 'verify command failure exits nonzero' "$status"
contains 'verify command failure names install.sh --verify' "$out" 'install.sh --verify'
equals 'verify command failure runs install then verify' \
  "$(cat "$log")" "$(printf 'install\nverify')"

# --- official refusals: config is ahead in each, and stays untouched --------

# 12. Missing FIRSTMATE_ROOT.
clone=$(make_pair missing)
advance_remote missing >/dev/null
log="$TMP_ROOT/missing.workflow"
c_head=$(head_of "$clone")
out=$(OFFICIAL_ROOT="$TMP_ROOT/does-not-exist" run_update "$clone" "$TMP_ROOT/missing-machine" "$log"); status=$?
nonzero 'missing official checkout exits nonzero' "$status"
contains 'missing official checkout explains the refusal' "$out" 'does not exist; nothing was changed'
equals 'missing official checkout keeps the config HEAD' "$(head_of "$clone")" "$c_head"
equals 'missing official checkout never runs install.sh' "$(cat "$log")" ''

# 13. FIRSTMATE_ROOT is a subdirectory of a checkout, not its root.
clone=$(make_pair subdir)
advance_remote subdir >/dev/null
mkdir -p "$clone-official/nested"; printf 'x\n' > "$clone-official/nested/AGENTS.md"
git_q "$clone-official" add -A; git_q "$clone-official" commit -q -m nested
OFFICIAL_ROOT="$clone-official/nested" expect_refusal 'subdirectory official checkout' "$clone" 'not the root of a checkout'

# 14. A Git root without AGENTS.md is not an official FirstMate checkout.
clone=$(make_pair no-agents)
advance_remote no-agents >/dev/null
git_q "$clone-official" rm -q AGENTS.md; git_q "$clone-official" commit -q -m 'drop AGENTS.md'
expect_refusal 'official checkout without AGENTS.md' "$clone" 'has no AGENTS.md'

# 15. Unexpected official origin: refuse before contacting it.
clone=$(make_pair wrong-remote)
advance_remote wrong-remote >/dev/null
git init -q --bare "$TMP_ROOT/impostor.git"
git_q "$clone-official" push -q "$TMP_ROOT/impostor.git" main
advance_official "$TMP_ROOT/impostor.git" impostor >/dev/null
git -C "$clone-official" remote set-url origin "$TMP_ROOT/impostor.git"
tracking=$(tracking_of "$clone-official")
expect_refusal 'unexpected official origin' "$clone" 'expected exactly'
equals 'unexpected official origin is never fetched' "$(tracking_of "$clone-official")" "$tracking"

# 16. Configured URL matches but insteadOf redirects fetches elsewhere.
clone=$(make_pair rewritten)
advance_remote rewritten >/dev/null
git -C "$clone-official" config "url.$TMP_ROOT/impostor.git.insteadOf" "$TMP_ROOT/rewritten-official.git"
tracking=$(tracking_of "$clone-official")
expect_refusal 'insteadOf-rewritten official origin' "$clone" 'rewritten'
equals 'insteadOf-rewritten official origin is never fetched' "$(tracking_of "$clone-official")" "$tracking"

# 17. No official origin remote at all.
clone=$(make_pair no-origin)
advance_remote no-origin >/dev/null
git -C "$clone-official" remote remove origin
expect_refusal 'missing official origin' "$clone" "no 'origin' remote"

# 18. Dirty official tracked file, then untracked file.
clone=$(make_pair official-dirty)
advance_remote official-dirty >/dev/null
advance_official "$TMP_ROOT/official-dirty-official.git" v2 >/dev/null
printf 'local edit\n' >> "$clone-official/AGENTS.md"
expect_refusal 'dirty official tracked file' "$clone" 'uncommitted'
contains 'dirty official tracked file keeps the local edit' "$(cat "$clone-official/AGENTS.md")" 'local edit'
git -C "$clone-official" checkout -q -- AGENTS.md
printf 'scratch\n' > "$clone-official/untracked.txt"
expect_refusal 'untracked official file' "$clone" 'uncommitted'

# 19. Detached official HEAD.
clone=$(make_pair official-detached)
advance_remote official-detached >/dev/null
advance_official "$TMP_ROOT/official-detached-official.git" v2 >/dev/null
git -C "$clone-official" checkout -q --detach
expect_refusal 'detached official HEAD' "$clone" 'detached HEAD'

# 20. Official checkout on a branch other than origin's default branch.
clone=$(make_pair other-branch)
advance_remote other-branch >/dev/null
advance_official "$TMP_ROOT/other-branch-official.git" v2 >/dev/null
git_q "$clone-official" switch -q -c topic
expect_refusal 'non-default official branch' "$clone" "expected origin's default branch 'main'"

# 21. Official default branch without an upstream.
clone=$(make_pair no-upstream)
advance_remote no-upstream >/dev/null
advance_official "$TMP_ROOT/no-upstream-official.git" v2 >/dev/null
git -C "$clone-official" branch -q --unset-upstream
expect_refusal 'missing official upstream' "$clone" 'does not track origin/main'

# 22. Official local commits not on origin (ahead only): unlanded work.
clone=$(make_pair official-ahead)
advance_remote official-ahead >/dev/null
printf 'local commit\n' >> "$clone-official/AGENTS.md"
git_q "$clone-official" commit -q -am 'local only commit'
expect_refusal 'unlanded official commit' "$clone" 'unlanded work'

# 23. Official checkout diverged from origin.
clone=$(make_pair official-diverged)
advance_remote official-diverged >/dev/null
advance_official "$TMP_ROOT/official-diverged-official.git" v2 >/dev/null
printf 'local file\n' > "$clone-official/local.txt"
git_q "$clone-official" add local.txt
git_q "$clone-official" commit -q -m 'local only commit'
expect_refusal 'diverged official branch' "$clone" 'diverged'

# 24. Unfinished official merge (MERGE_HEAD present).
clone=$(make_pair merging)
advance_remote merging >/dev/null
git_q "$clone-official" switch -q -c side
printf 'side\n' > "$clone-official/side.txt"
git_q "$clone-official" add side.txt; git_q "$clone-official" commit -q -m side
git_q "$clone-official" switch -q main
git_q "$clone-official" merge -q --no-ff --no-commit side >/dev/null 2>&1
expect_refusal 'unfinished official merge' "$clone" 'unfinished Git operation (MERGE_HEAD)'

# --- CLI surface ----------------------------------------------------------------

# 25. Unknown argument and --help.
clone=$(make_pair args)
log="$TMP_ROOT/args.workflow"
out=$(run_update "$clone" "$TMP_ROOT/args-machine" "$log" '' '' --bogus); status=$?
nonzero 'unknown argument exits nonzero' "$status"
contains 'unknown argument is named' "$out" "unknown argument '--bogus'"
out=$(run_update "$clone" "$TMP_ROOT/args-machine" "$log" '' '' --help); status=$?
equals 'help exits 0' "$status" 0
contains 'help prints usage' "$out" 'Usage: fm update'

[ "$failed" -eq 0 ] || exit 1
