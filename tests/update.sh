#!/usr/bin/env bash
# update.sh - fixture-based acceptance for `fm update`.
#
# Every scenario runs against throwaway local Git repositories (a bare "remote"
# plus a clone acting as the installed firstmate-config checkout), so the real
# clone is never mutated and no network remote is contacted.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0
pass(){ printf 'ok   - %s\n' "$1"; }
fail(){ printf 'FAIL - %s\n' "$1" >&2; failed=1; }
contains(){ case $2 in *"$3"*) pass "$1";; *) fail "$1 (missing '$3' in: $2)";; esac; }
equals(){ [ "$2" = "$3" ] && pass "$1" || fail "$1 (expected '$3', got '$2')"; }

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
  git_q "$seed" add file.txt
  git_q "$seed" commit -q -m init
  git_q "$seed" branch -M main
  git_q "$seed" remote add origin "$remote"
  git_q "$seed" push -q origin main
  git clone -q "$remote" "$clone"
  git_q "$clone" config user.email test@example.invalid
  git_q "$clone" config user.name Test
  # The clone is the installed-style checkout: it carries the real CLI files.
  mkdir -p "$clone/bin" "$clone/firstmate"
  cp "$CONFIG_ROOT/bin/fm" "$CONFIG_ROOT/bin/fm-update" "$clone/bin/"
  cp "$CONFIG_ROOT/firstmate/fm-captain-lib.sh" "$clone/firstmate/"
  git_q "$clone" add -A
  git_q "$clone" commit -q -m 'install cli'
  git_q "$clone" push -q origin main
  printf '%s\n' "$clone"
}

# Land a new upstream commit without touching the checkout under test.
advance_remote(){ # <name>
  local work="$TMP_ROOT/$1-push"
  rm -rf "$work"
  git clone -q "$TMP_ROOT/$1.git" "$work"
  printf 'upstream change\n' >> "$work/file.txt"
  git_q "$work" commit -q -am 'upstream commit'
  git_q "$work" push -q origin main
  git -C "$work" rev-parse --short HEAD
}

run_update(){ # <clone> [args...]
  HOME="$HOME_FIXTURE" FM_HOME="$TMP_ROOT/fm-home" PATH="/usr/bin:/bin" \
    "$1/bin/fm" update "${@:2}" 2>&1
}

# 1. Already current.
clone=$(make_pair current)
out=$(run_update "$clone"); status=$?
equals 'already-current exits 0' "$status" 0
contains 'already-current reports no change' "$out" 'Already up to date'

# 2. Remote ahead: fast-forward.
clone=$(make_pair ahead)
old=$(git -C "$clone" rev-parse --short HEAD)
new=$(advance_remote ahead)
out=$(run_update "$clone"); status=$?
equals 'fast-forward exits 0' "$status" 0
contains 'fast-forward reports the old commit' "$out" "$old"
contains 'fast-forward reports the new commit' "$out" "$new"
equals 'fast-forward moved HEAD to the remote tip' \
  "$(git -C "$clone" rev-parse --short HEAD)" "$new"

# 3. Uncommitted local changes: refuse, change nothing.
clone=$(make_pair dirty)
before=$(git -C "$clone" rev-parse HEAD)
advance_remote dirty >/dev/null
printf 'local edit\n' >> "$clone/file.txt"
out=$(run_update "$clone"); status=$?
[ "$status" -ne 0 ] && pass 'dirty checkout exits nonzero' || fail 'dirty checkout exits nonzero'
contains 'dirty checkout explains the refusal' "$out" 'uncommitted'
equals 'dirty checkout keeps HEAD' "$(git -C "$clone" rev-parse HEAD)" "$before"
contains 'dirty checkout keeps the local edit' "$(cat "$clone/file.txt")" 'local edit'

# 4. Diverged branch: refuse, no merge/rebase/reset.
clone=$(make_pair diverged)
advance_remote diverged >/dev/null
printf 'local commit\n' >> "$clone/file.txt"
git_q "$clone" commit -q -am 'local only commit'
before=$(git -C "$clone" rev-parse HEAD)
out=$(run_update "$clone"); status=$?
[ "$status" -ne 0 ] && pass 'diverged branch exits nonzero' || fail 'diverged branch exits nonzero'
contains 'diverged branch explains the refusal' "$out" 'diverged'
equals 'diverged branch keeps HEAD' "$(git -C "$clone" rev-parse HEAD)" "$before"

[ "$failed" -eq 0 ] || exit 1
