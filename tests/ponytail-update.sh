#!/usr/bin/env bash
# ponytail-update.sh - offline acceptance for the top-level Ponytail workflow.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$CONFIG_ROOT/bin/ponytail-update"
REAL_GIT=$(command -v git)

[ -x "$HELPER" ] || { printf 'FAIL - missing executable %s\n' "$HELPER" >&2; exit 1; }

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi; }
contains() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3')" ;; esac; }
not_contains() { case $2 in *"$3"*) fail "$1 (unexpected '$3')" ;; *) pass "$1" ;; esac; }
nonzero() { if [ "$2" -ne 0 ]; then pass "$1"; else fail "$1"; fi; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ponytail-update-test.XXXXXX") || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/home"

FAKE_BIN="$TMP_ROOT/fake-bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/git" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_LOG"
exec "$REAL_GIT" "$@"
SH
chmod +x "$FAKE_BIN/git"

make_repo() { # <name> <OLD|NEW>
  local name=$1 pin=$2 bare="$TMP_ROOT/$1.git" seed="$TMP_ROOT/$1-seed" clone="$TMP_ROOT/$1-clone"
  "$REAL_GIT" init -q --bare "$bare"
  "$REAL_GIT" init -q -b main "$seed"
  "$REAL_GIT" -C "$seed" config user.email test@example.invalid
  "$REAL_GIT" -C "$seed" config user.name Test
  mkdir -p "$seed/bin" "$seed/scripts" "$seed/tests" "$seed/skills"
  cp "$HELPER" "$seed/bin/ponytail-update"
  chmod +x "$seed/bin/ponytail-update"
  printf '%s\n' "$pin" > "$seed/skills/external.lock"
  cat > "$seed/scripts/update-ponytail.sh" <<'SH'
#!/usr/bin/env bash
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
if [ "${1:-}" = --check ]; then
  printf 'check\n' >> "$WORKFLOW_LOG"
  pin=$(cat "$root/skills/external.lock")
  printf 'CURRENT_VERSION: %s\n' "$([ "$pin" = NEW ] && printf v2.0.0 || printf v1.0.0)"
  printf 'CURRENT_PIN: %s\n' "$pin"
  printf 'LATEST_STABLE_VERSION: v2.0.0\n'
  printf 'LATEST_STABLE_PIN: NEW\n'
  printf 'UPDATE_AVAILABLE: %s\n' "$([ "$pin" = NEW ] && printf false || printf true)"
  exit 0
fi
printf 'update\n' >> "$WORKFLOW_LOG"
[ "${FAIL_STAGE:-}" != updater ] || { printf 'fixture updater failed\n' >&2; exit 7; }
printf 'CURRENT_PIN: OLD\nCURRENT_VERSION: v1.0.0\nTARGET_VERSION: v2.0.0\nTARGET_PIN: NEW\n'
printf 'NEW\n' > "$root/skills/external.lock"
SH
  chmod +x "$seed/scripts/update-ponytail.sh"
  cat > "$seed/tests/update-ponytail.sh" <<'SH'
#!/usr/bin/env bash
printf 'test-update\n' >> "$WORKFLOW_LOG"
[ "${FAIL_STAGE:-}" != ponytail-test ] || { printf 'fixture Ponytail test failed\n' >&2; exit 8; }
SH
  cat > "$seed/tests/pi-ponytail-package.sh" <<'SH'
#!/usr/bin/env bash
printf 'test-pi\n' >> "$WORKFLOW_LOG"
SH
  chmod +x "$seed/tests/update-ponytail.sh" "$seed/tests/pi-ponytail-package.sh"
  cat > "$seed/install.sh" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = --verify ]; then
  printf 'verify\n' >> "$WORKFLOW_LOG"
  [ "${FAIL_STAGE:-}" != verify ] || { printf 'fixture verify failed\n' >&2; exit 9; }
  printf 'verify: 0 drift item(s), 0 failure(s)\n'
else
  printf 'install\n' >> "$WORKFLOW_LOG"
  printf 'install: 1 change(s), 0 failure(s)\n'
fi
SH
  chmod +x "$seed/install.sh"
  printf '# fixture firstmate-config\n' > "$seed/README.md"
  "$REAL_GIT" -C "$seed" add -A
  "$REAL_GIT" -C "$seed" commit -q -m initial
  "$REAL_GIT" -C "$seed" remote add origin "$bare"
  "$REAL_GIT" -C "$seed" push -q -u origin main
  "$REAL_GIT" --git-dir="$bare" symbolic-ref HEAD refs/heads/main
  "$REAL_GIT" clone -q "$bare" "$clone"
  "$REAL_GIT" -C "$clone" config user.email test@example.invalid
  "$REAL_GIT" -C "$clone" config user.name Test
  printf '%s\n' "$clone"
}

advance_remote() { # <name>
  local name=$1 bare="$TMP_ROOT/$1.git" work="$TMP_ROOT/$1-upstream"
  "$REAL_GIT" clone -q "$bare" "$work"
  "$REAL_GIT" -C "$work" config user.email test@example.invalid
  "$REAL_GIT" -C "$work" config user.name Test
  printf 'upstream\n' > "$work/upstream.txt"
  "$REAL_GIT" -C "$work" add upstream.txt
  "$REAL_GIT" -C "$work" commit -q -m upstream
  "$REAL_GIT" -C "$work" push -q origin main
}

run_helper() { # <name> <clone> [failure-stage]
  local name=$1 clone=$2 stage=${3:-}
  : > "$TMP_ROOT/$name.workflow"
  : > "$TMP_ROOT/$name.gitlog"
  PATH="$FAKE_BIN:/usr/bin:/bin" HOME="$TMP_ROOT/home" \
    REAL_GIT="$REAL_GIT" GIT_LOG="$TMP_ROOT/$name.gitlog" \
    WORKFLOW_LOG="$TMP_ROOT/$name.workflow" FAIL_STAGE="$stage" \
    FM_CONFIG_ROOT="$clone" FM_CONFIG_ENV="$TMP_ROOT/no-env" \
    "$HELPER" 2>&1
}

# 1. Clean main, remote fast-forward, update available: full workflow.
clone=$(make_repo available OLD)
advance_remote available
out=$(run_helper available "$clone"); code=$?
check 'available update exits 0' 0 "$code"
check 'available update runs the exact workflow' \
  "$(printf 'check\nupdate\ntest-update\ntest-pi\ninstall\nverify\ncheck')" \
  "$(cat "$TMP_ROOT/available.workflow")"
check 'available update advances the tracked pin' NEW "$(cat "$clone/skills/external.lock")"
check 'available update fast-forwards main first' upstream "$(cat "$clone/upstream.txt" 2>/dev/null)"
contains 'available update reports applied state' "$out" 'UPDATE_APPLIED: true'
contains 'available update reports passing tests' "$out" 'TESTS_RESULT: passed'
contains 'available update reports install success' "$out" 'INSTALL_RESULT: passed'
contains 'available update reports verify success' "$out" 'VERIFY_RESULT: passed'
contains 'available update reports final version' "$out" 'FINAL_VERSION: v2.0.0'
contains 'available update reports final pin' "$out" 'FINAL_PIN: NEW'
contains 'available update reports final availability' "$out" 'FINAL_UPDATE_AVAILABLE: false'
contains 'available update prints review command' "$out" 'git diff -- skills/external.lock'
check 'available update leaves HEAD uncommitted' OLD \
  "$("$REAL_GIT" -C "$clone" show HEAD:skills/external.lock)"

# 2. Already current: only the read-only check runs.
clone=$(make_repo current NEW)
out=$(run_helper current "$clone"); code=$?
check 'current pin exits 0' 0 "$code"
check 'current pin runs only one check' check "$(cat "$TMP_ROOT/current.workflow")"
check 'current pin stays unchanged' NEW "$(cat "$clone/skills/external.lock")"
contains 'current pin reports no application' "$out" 'UPDATE_APPLIED: false'
contains 'current pin reports final availability' "$out" 'FINAL_UPDATE_AVAILABLE: false'

# 3. Local main ahead of origin/main is safe: pull stays ff-only and the
# read-only no-update path leaves the local commit untouched.
clone=$(make_repo local-ahead NEW)
printf 'local commit\n' > "$clone/local.txt"
"$REAL_GIT" -C "$clone" add local.txt
"$REAL_GIT" -C "$clone" commit -q -m local
local_head=$("$REAL_GIT" -C "$clone" rev-parse HEAD)
out=$(run_helper local-ahead "$clone"); code=$?
check 'local-ahead main exits 0' 0 "$code"
check 'local-ahead main runs only one check' check "$(cat "$TMP_ROOT/local-ahead.workflow")"
check 'local-ahead main keeps its commit' "$local_head" "$("$REAL_GIT" -C "$clone" rev-parse HEAD)"
check 'local-ahead main stays clean' '' "$("$REAL_GIT" -C "$clone" status --porcelain)"

# 3. Dirty tree: refuse before fetch or workflow commands.
clone=$(make_repo dirty OLD)
printf 'dirty\n' >> "$clone/README.md"
out=$(run_helper dirty "$clone"); code=$?
nonzero 'dirty tree exits nonzero' "$code"
contains 'dirty tree explains refusal' "$out" 'working tree is dirty'
check 'dirty tree runs no update workflow' '' "$(cat "$TMP_ROOT/dirty.workflow")"
not_contains 'dirty tree never pulls' "$(cat "$TMP_ROOT/dirty.gitlog")" ' pull '

# 4. Non-main branch: refuse before workflow commands.
clone=$(make_repo branch OLD)
"$REAL_GIT" -C "$clone" checkout -q -b topic
out=$(run_helper branch "$clone"); code=$?
nonzero 'non-main branch exits nonzero' "$code"
contains 'non-main branch explains refusal' "$out" "must be on main"
check 'non-main branch runs no update workflow' '' "$(cat "$TMP_ROOT/branch.workflow")"

# 5. Diverged main: fetch, then refuse before pull or workflow commands.
clone=$(make_repo diverged OLD)
advance_remote diverged
printf 'local\n' > "$clone/local.txt"
"$REAL_GIT" -C "$clone" add local.txt
"$REAL_GIT" -C "$clone" commit -q -m local
out=$(run_helper diverged "$clone"); code=$?
nonzero 'diverged main exits nonzero' "$code"
contains 'diverged main explains refusal' "$out" 'cannot fast-forward'
check 'diverged main runs no update workflow' '' "$(cat "$TMP_ROOT/diverged.workflow")"
not_contains 'diverged main never pulls' "$(cat "$TMP_ROOT/diverged.gitlog")" ' pull '

# 6. Mutating updater failure stops immediately.
clone=$(make_repo updater-fail OLD)
out=$(run_helper updater-fail "$clone" updater); code=$?
nonzero 'updater failure exits nonzero' "$code"
check 'updater failure stops before tests and install' "$(printf 'check\nupdate')" "$(cat "$TMP_ROOT/updater-fail.workflow")"

# 7. Ponytail test failure stops before the second test and install.
clone=$(make_repo test-fail OLD)
out=$(run_helper test-fail "$clone" ponytail-test); code=$?
nonzero 'Ponytail test failure exits nonzero' "$code"
check 'Ponytail test failure stops before install' "$(printf 'check\nupdate\ntest-update')" "$(cat "$TMP_ROOT/test-fail.workflow")"

# 8. Install verification failure is nonzero and prevents final check.
clone=$(make_repo verify-fail OLD)
out=$(run_helper verify-fail "$clone" verify); code=$?
nonzero 'install verify failure exits nonzero' "$code"
check 'install verify failure prevents final check' \
  "$(printf 'check\nupdate\ntest-update\ntest-pi\ninstall\nverify')" \
  "$(cat "$TMP_ROOT/verify-fail.workflow")"

# 9. The helper invokes no commit, merge, push, tag, or branch mutation.
gitlog=$(cat "$TMP_ROOT/available.gitlog")
not_contains 'helper never invokes git commit' "$gitlog" ' commit '
not_contains 'helper never invokes git merge' "$gitlog" ' merge '
not_contains 'helper never invokes git push' "$gitlog" ' push '
not_contains 'helper never invokes git tag' "$gitlog" ' tag '
not_contains 'helper never invokes branch creation or deletion' "$gitlog" ' branch '

printf '\nPONYTAIL UPDATE HELPER TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
