#!/usr/bin/env bash
# update.sh - fixture-based acceptance for `fm update`.
#
# Every scenario runs against throwaway local Git repositories (a bare "remote"
# plus a clone acting as the installed firstmate-config checkout), so the real
# clone is never mutated and no network remote is contacted.
#
# Each fixture checkout carries a fake install.sh - never the real one, which
# needs the real toolchain (git/pi/omp/herdr) - that logs every invocation to
# WORKFLOW_LOG and reconciles a single tracked "managed artifact" file into a
# fixture MACHINE_DIR. This proves fm-update actually invokes the *pulled*
# checkout's installer and verifier in sequence, and that a newly tracked
# artifact converges to the machine in the same `fm update` invocation,
# without ever touching the real machine or the real install.sh.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0
pass(){ printf 'ok   - %s\n' "$1"; }
fail(){ printf 'FAIL - %s\n' "$1" >&2; failed=1; }
contains(){ case $2 in *"$3"*) pass "$1";; *) fail "$1 (missing '$3' in: $2)";; esac; }
equals(){ [ "$2" = "$3" ] && pass "$1" || fail "$1 (expected '$3', got '$2')"; }
nonzero(){ [ "$2" -ne 0 ] && pass "$1" || fail "$1 (expected nonzero exit, got 0)"; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-update-test.XXXXXX") || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT
HOME_FIXTURE="$TMP_ROOT/home"; mkdir -p "$HOME_FIXTURE"

git_q(){ git -C "$1" -c user.email=test@example.invalid -c user.name=Test "${@:2}"; }

# A fresh remote + installed-checkout pair per scenario.
make_pair(){ # <name>
  local name=$1 remote="$TMP_ROOT/$1.git" clone="$TMP_ROOT/$1"
  git init -q --bare "$remote"
  local seed="$TMP_ROOT/$1-seed"
  git init -q "$seed"
  printf 'base\n' > "$seed/file.txt"
  # The seed is the installed-style checkout: it carries the real CLI files
  # plus a fake install.sh standing in for the real one.
  mkdir -p "$seed/bin" "$seed/firstmate"
  cp "$CONFIG_ROOT/bin/fm" "$CONFIG_ROOT/bin/fm-update" "$seed/bin/"
  cp "$CONFIG_ROOT/firstmate/fm-captain-lib.sh" "$seed/firstmate/"
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

# Land a new upstream commit without touching the checkout under test.
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

run_update(){ # <clone> <machine_dir> <workflow_log> [fail_stage] [force_drift]
  local clone=$1 machine_dir=$2 workflow_log=$3 fail_stage=${4:-} force_drift=${5:-}
  : > "$workflow_log"
  HOME="$HOME_FIXTURE" FM_HOME="$TMP_ROOT/fm-home" PATH="/usr/bin:/bin" \
    MACHINE_DIR="$machine_dir" WORKFLOW_LOG="$workflow_log" \
    FAIL_STAGE="$fail_stage" FORCE_DRIFT="$force_drift" \
    "$clone/bin/fm" update 2>&1
}

# 1. Already current: a safe no-op that still reconciles and verifies the
# machine (the exact gap Betao hit: a stale machine needs no separate
# manual ./install.sh even when the repository itself has nothing to pull).
clone=$(make_pair current)
machine="$TMP_ROOT/current-machine"; log="$TMP_ROOT/current.workflow"
out=$(run_update "$clone" "$machine" "$log"); status=$?
equals 'already-current exits 0' "$status" 0
contains 'already-current reports no change' "$out" 'Already up to date'
equals 'already-current still runs install then verify' \
  "$(cat "$log")" "$(printf 'install\nverify')"
contains 'already-current verify reports 0 drift' "$out" 'verify: 0 drift item(s), 0 failure(s)'

# 2. Remote ahead: fast-forward, then install.sh + install.sh --verify run in
# the same invocation and reconcile a newly tracked managed artifact.
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

# 3. Uncommitted local changes: refuse, change nothing, never touch install.sh.
clone=$(make_pair dirty)
before=$(git -C "$clone" rev-parse HEAD)
advance_remote dirty >/dev/null
printf 'local edit\n' >> "$clone/file.txt"
machine="$TMP_ROOT/dirty-machine"; log="$TMP_ROOT/dirty.workflow"
out=$(run_update "$clone" "$machine" "$log"); status=$?
nonzero 'dirty checkout exits nonzero' "$status"
contains 'dirty checkout explains the refusal' "$out" 'uncommitted'
equals 'dirty checkout keeps HEAD' "$(git -C "$clone" rev-parse HEAD)" "$before"
contains 'dirty checkout keeps the local edit' "$(cat "$clone/file.txt")" 'local edit'
equals 'dirty checkout never runs install.sh' "$(cat "$log")" ''

# 4. Diverged branch: refuse, no merge/rebase/reset, never touch install.sh.
clone=$(make_pair diverged)
advance_remote diverged >/dev/null
printf 'local commit\n' >> "$clone/file.txt"
git_q "$clone" commit -q -am 'local only commit'
before=$(git -C "$clone" rev-parse HEAD)
machine="$TMP_ROOT/diverged-machine"; log="$TMP_ROOT/diverged.workflow"
out=$(run_update "$clone" "$machine" "$log"); status=$?
nonzero 'diverged branch exits nonzero' "$status"
contains 'diverged branch explains the refusal' "$out" 'diverged'
equals 'diverged branch keeps HEAD' "$(git -C "$clone" rev-parse HEAD)" "$before"
equals 'diverged branch never runs install.sh' "$(cat "$log")" ''

# 5. Pull succeeds, install.sh fails: nonzero exit, but the repository still
# advanced (fm-update never re-implements install.sh's own logic to route
# around its failure).
clone=$(make_pair install-fail)
new=$(advance_remote install-fail)
machine="$TMP_ROOT/install-fail-machine"; log="$TMP_ROOT/install-fail.workflow"
out=$(run_update "$clone" "$machine" "$log" install); status=$?
nonzero 'install failure exits nonzero' "$status"
contains 'install failure names install.sh' "$out" 'install.sh failed'
equals 'install failure still advanced the repository' \
  "$(git -C "$clone" rev-parse --short HEAD)" "$new"
equals 'install failure runs install but never reaches verify' "$(cat "$log")" install

# 6. Pull and install succeed, install.sh --verify reports drift: nonzero exit.
clone=$(make_pair verify-drift)
advance_remote verify-drift >/dev/null
machine="$TMP_ROOT/verify-drift-machine"; log="$TMP_ROOT/verify-drift.workflow"
out=$(run_update "$clone" "$machine" "$log" '' 1); status=$?
nonzero 'post-install verify drift exits nonzero' "$status"
contains 'post-install verify drift explains the refusal' "$out" 'drift'
equals 'post-install verify drift runs install then verify' \
  "$(cat "$log")" "$(printf 'install\nverify')"

# 7. Pull and install succeed, install.sh --verify itself fails: nonzero exit.
clone=$(make_pair verify-fail)
advance_remote verify-fail >/dev/null
machine="$TMP_ROOT/verify-fail-machine"; log="$TMP_ROOT/verify-fail.workflow"
out=$(run_update "$clone" "$machine" "$log" verify); status=$?
nonzero 'verify command failure exits nonzero' "$status"
contains 'verify command failure names install.sh --verify' "$out" 'install.sh --verify'
equals 'verify command failure runs install then verify' \
  "$(cat "$log")" "$(printf 'install\nverify')"

[ "$failed" -eq 0 ] || exit 1
