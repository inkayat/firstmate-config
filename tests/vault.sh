#!/usr/bin/env bash
# vault.sh - acceptance for the optional specialist skill vault integration:
# install.sh step 10 (clone/pin/verify/refuse-drift) and bin/fm-doctor's
# vault.pin / vault.no_global_leak checks.
#
# Fully offline and disposable, mirroring tests/pi-ponytail-package.sh's own
# established pattern: no real inkayat/agent-skill-vault network clone. A
# real local Git repository stands in for it, reached through a git
# `url.<local>.insteadOf=https://github.com/...` rewrite in the fixture's
# own isolated $HOME/.gitconfig - install.sh's clone/fetch commands run
# unmodified, exactly as they do in production, just redirected.
#
# What this file does NOT cover: the vault's own selection/lookup behavior
# (category shortlists, explicit-id resolution, unsafe-status exclusion,
# provenance). That is the vault repository's own responsibility and test
# suite (`bun test` there); this file only proves firstmate-config pins,
# caches, and reports on the vault correctly, and never globally registers
# it - see firstmate/primary-policy.md "Specialist skill vault" for the
# consumption contract this integration exists to support.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi; }
contains() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in '$2')" ;; esac; }
not_contains() { case $2 in *"$3"*) fail "$1 (unexpectedly found '$3' in '$2')" ;; *) pass "$1" ;; esac; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-vault-test.XXXXXX") || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT

SYS_BIN="$TMP_ROOT/sysbin"
mkdir -p "$SYS_BIN"
for _tool in bash git sed awk grep wc date find stat readlink basename dirname tr head cat mkdir env sort ln rm mktemp cp printf; do
  _p=$(command -v "$_tool" 2>/dev/null) || continue
  ln -s "$_p" "$SYS_BIN/$_tool"
done

# =============================================================================
# A. install.sh step 10, end to end
# =============================================================================

INST_CFG="$TMP_ROOT/inst-cfg"
mkdir -p "$INST_CFG/bin" "$INST_CFG/firstmate" "$INST_CFG/skills"
cp "$CONFIG_ROOT/install.sh" "$INST_CFG/install.sh"
chmod +x "$INST_CFG/install.sh"
cp "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh" "$INST_CFG/firstmate/fm-stack-manifest.sh"
printf '{}\n' > "$INST_CFG/firstmate/crew-dispatch.json"
printf '# captain notes\n' > "$INST_CFG/firstmate/captain.md"
: > "$INST_CFG/bin/fm"; chmod +x "$INST_CFG/bin/fm"
: > "$INST_CFG/bin/ponytail-update"; chmod +x "$INST_CFG/bin/ponytail-update"
cat > "$INST_CFG/firstmate/stack-manifest.tsv" <<EOF
schema_version	1
firstmate_repo	https://example.invalid/firstmate.git
firstmate_validated_commit	0000000000000000000000000000000000000000
pi_min_version	0.1.0
pi_tested_version	0.1.0
omp_min_version	0.1.0
omp_tested_version	0.1.0
herdr_min_version	0.1.0
herdr_tested_version	0.1.0
EOF

INST_FAKE_BIN="$TMP_ROOT/inst-fake-bin"
mkdir -p "$INST_FAKE_BIN"
: > "$INST_FAKE_BIN/omp"; chmod +x "$INST_FAKE_BIN/omp"
: > "$INST_FAKE_BIN/herdr"; chmod +x "$INST_FAKE_BIN/herdr"
printf '#!/usr/bin/env bash\necho 0.1.0\n' > "$INST_FAKE_BIN/pi"; chmod +x "$INST_FAKE_BIN/pi"

# --- a real local origin standing in for inkayat/agent-skill-vault ---------
VAULT_REPO_ID="test-owner/test-vault"
V_ORIGIN="$TMP_ROOT/vault-origin"
mkdir -p "$V_ORIGIN"
git -C "$V_ORIGIN" init -q
git -C "$V_ORIGIN" config user.email t@example.invalid
git -C "$V_ORIGIN" config user.name t
printf '# fixture vault\n' > "$V_ORIGIN/README.md"
printf 'entries: {}\n' > "$V_ORIGIN/catalog.yaml"
git -C "$V_ORIGIN" add -A
git -C "$V_ORIGIN" commit -q -m c1
V_SHA1=$(git -C "$V_ORIGIN" rev-parse HEAD)
printf 'entries: {addy: {}}\n' > "$V_ORIGIN/catalog.yaml"
git -C "$V_ORIGIN" add -A
git -C "$V_ORIGIN" commit -q -m c2
V_SHA2=$(git -C "$V_ORIGIN" rev-parse HEAD)

printf '%s\t%s\n' "$VAULT_REPO_ID" "$V_SHA1" > "$INST_CFG/skills/vault.lock"

write_gitconfig() { # <home>
  cat > "$1/.gitconfig" <<EOF
[user]
	email = t@example.invalid
	name = t
[url "$V_ORIGIN"]
	insteadOf = https://github.com/$VAULT_REPO_ID.git
EOF
}

run_fake_install() { # <suffix> [install.sh args...]
  local suffix=$1; shift
  local home="$TMP_ROOT/inst-home-$suffix"
  mkdir -p "$home" "$TMP_ROOT/inst-dest-$suffix"
  write_gitconfig "$home"
  printf 'fixture\n' > "$TMP_ROOT/inst-dest-$suffix/AGENTS.md"
  PATH="$INST_FAKE_BIN:$SYS_BIN" \
  HOME="$home" \
  FIRSTMATE_ROOT="$TMP_ROOT/inst-dest-$suffix" \
  FM_HOME="$TMP_ROOT/inst-fm-home-$suffix" \
  FM_CONFIG_ENV="$TMP_ROOT/inst-env-$suffix" \
  FM_SKILLS_ROOT="$TMP_ROOT/inst-skills-$suffix" \
  FM_SKILL_CACHE="$TMP_ROOT/inst-skill-cache-$suffix" \
  FM_VAULT_CACHE="$TMP_ROOT/inst-vault-cache-$suffix" \
  FM_BIN_DIR="$TMP_ROOT/inst-bin-dir-$suffix" \
  PI_CODING_AGENT_DIR="$TMP_ROOT/inst-pi-agent-$suffix" \
  XDG_CONFIG_HOME="$TMP_ROOT/inst-xdg-$suffix" \
  "$INST_CFG/install.sh" "$@" 2>&1
}

VAULT_DEST_fresh="$TMP_ROOT/inst-vault-cache-fresh/test-owner-test-vault"

# --- 1. Fresh run clones and pins to the exact commit -----------------------
out=$(run_fake_install fresh); code=$?
check '1 fresh run: exit code is 0' 0 "$code"
contains '1 fresh run: reports the vault step ran' "$out" '10. specialist skill vault'
contains '1 fresh run: reports the clone' "$out" "cloned $VAULT_REPO_ID"
check '1 vault cache: cloned at the pinned commit' "$V_SHA1" "$(git -C "$VAULT_DEST_fresh" rev-parse HEAD 2>/dev/null || printf '')"
check '1 vault cache: detached HEAD, never a branch' HEAD "$(git -C "$VAULT_DEST_fresh" symbolic-ref -q --short HEAD 2>/dev/null || printf HEAD)"
contains '1 env file: exports FM_VAULT_ROOT at the cache path' \
  "$(cat "$TMP_ROOT/inst-env-fresh" 2>/dev/null)" "FM_VAULT_ROOT=\"$VAULT_DEST_fresh\""
not_contains '1 global skills: the vault is never symlinked into the shared skill root' \
  "$(ls "$TMP_ROOT/inst-skills-fresh" 2>/dev/null)" 'vault'

# --- 2. Second run: idempotent, zero relevant changes ------------------------
out2=$(run_fake_install fresh); code2=$?
check '2 second run: exit code is 0' 0 "$code2"
not_contains '2 second run: no DRIFT lines' "$out2" 'DRIFT'
not_contains '2 second run: vault reports no change' "$out2" "cloned $VAULT_REPO_ID"
not_contains '2 second run: vault reports no re-pin' "$out2" 're-pinned'
contains '2 second run: install reports 0 change(s)' "$out2" 'install: 0 change(s), 0 failure(s)'

# --- 3. Offline: an already-valid cache never needs the network -------------
# Break the git redirect so any clone/fetch attempt would fail loudly, then
# rerun: a real run must still report `ok` purely from the local SHA match,
# proving install.sh never touches the network when the cache is already
# correct (also covers the disabled-origin --verify path).
BROKEN_HOME="$TMP_ROOT/inst-home-fresh"
sed -i.bak "s#$V_ORIGIN#$TMP_ROOT/no-such-origin#" "$BROKEN_HOME/.gitconfig"
out3=$(run_fake_install fresh --verify); code3=$?
check '3 offline verify: exit code is 0' 0 "$code3"
contains '3 offline verify: reports 0 drift item(s)' "$out3" '0 drift item(s), 0 failure(s)'
out3b=$(run_fake_install fresh); code3b=$?
check '3 offline real run: exit code is 0' 0 "$code3b"
contains '3 offline real run: reports 0 change(s)' "$out3b" 'install: 0 change(s), 0 failure(s)'
mv "$BROKEN_HOME/.gitconfig.bak" "$BROKEN_HOME/.gitconfig"

# --- 4. Wrong revision: --verify detects it; a real run re-pins -------------
git -C "$VAULT_DEST_fresh" checkout -q --detach "$V_SHA2"
verify4=$(run_fake_install fresh --verify); code4=$?
check '4 wrong revision verify: exit code is 0 (drift reported, never a failure)' 0 "$code4"
contains '4 wrong revision verify: reports DRIFT' "$verify4" 'DRIFT'
contains '4 wrong revision verify: names it is not pinned' "$verify4" "not pinned $V_SHA1"
check '4 wrong revision verify: never repoints during --verify' "$V_SHA2" "$(git -C "$VAULT_DEST_fresh" rev-parse HEAD)"
fix4=$(run_fake_install fresh); code4b=$?
check '4 wrong revision real run: exit code is 0' 0 "$code4b"
contains '4 wrong revision real run: reports re-pinned' "$fix4" 're-pinned'
check '4 wrong revision real run: cache is back at the pinned commit' "$V_SHA1" "$(git -C "$VAULT_DEST_fresh" rev-parse HEAD)"

# --- 5. Dirty cache: refused, never silently discarded ----------------------
printf 'hand-edited\n' >> "$VAULT_DEST_fresh/README.md"
verify5=$(run_fake_install fresh --verify); code5=$?
if [ "$code5" -eq 0 ]; then fail '5 dirty verify: expected nonzero exit (a real failure, not drift), got 0'; else pass '5 dirty verify: exit code is nonzero'; fi
contains '5 dirty verify: reported as a failure, not drift' "$verify5" 'FAIL'
contains '5 dirty verify: names it must never be hand-edited' "$verify5" 'must never be hand-edited'
real5=$(run_fake_install fresh); code5b=$?
if [ "$code5b" -eq 0 ]; then fail '5 dirty real run: expected nonzero exit, got 0'; else pass '5 dirty real run: exit code is nonzero'; fi
contains '5 dirty real run: still refuses rather than resetting' "$real5" 'must never be hand-edited'
contains '5 dirty cache: local edit is preserved, never silently discarded' \
  "$(cat "$VAULT_DEST_fresh/README.md")" 'hand-edited'
git -C "$VAULT_DEST_fresh" checkout -q -- README.md

# --- 6. Absent skills/vault.lock: the vault step is a no-op -----------------
INST_CFG_NOLOCK="$TMP_ROOT/inst-cfg-nolock"
cp -R "$INST_CFG" "$INST_CFG_NOLOCK"
rm -f "$INST_CFG_NOLOCK/skills/vault.lock"
out6=$(HOME="$TMP_ROOT/inst-home-nolock" FIRSTMATE_ROOT="$TMP_ROOT/inst-dest-nolock" \
  FM_HOME="$TMP_ROOT/inst-fm-home-nolock" FM_CONFIG_ENV="$TMP_ROOT/inst-env-nolock" \
  FM_SKILLS_ROOT="$TMP_ROOT/inst-skills-nolock" FM_SKILL_CACHE="$TMP_ROOT/inst-skill-cache-nolock" \
  FM_VAULT_CACHE="$TMP_ROOT/inst-vault-cache-nolock" FM_BIN_DIR="$TMP_ROOT/inst-bin-dir-nolock" \
  PI_CODING_AGENT_DIR="$TMP_ROOT/inst-pi-agent-nolock" XDG_CONFIG_HOME="$TMP_ROOT/inst-xdg-nolock" \
  PATH="$INST_FAKE_BIN:$SYS_BIN" \
  bash -c 'mkdir -p "$FIRSTMATE_ROOT" "$HOME"; printf fixture > "$FIRSTMATE_ROOT/AGENTS.md"; git init -q "$HOME" >/dev/null 2>&1 || true; "$1/install.sh"' _ "$INST_CFG_NOLOCK" 2>&1); code6=$?
check '6 no lock: exit code is 0' 0 "$code6"
contains '6 no lock: skips the vault step' "$out6" 'no skills/vault.lock; skipping'
if [ -e "$TMP_ROOT/inst-vault-cache-nolock" ]; then fail '6 no lock: no cache directory is ever created'; else pass '6 no lock: no cache directory is ever created'; fi

# --- 7. Malformed lock: fails loudly, never silently ignored ---------------
INST_CFG_BAD="$TMP_ROOT/inst-cfg-bad"
cp -R "$INST_CFG" "$INST_CFG_BAD"
printf 'not-tab-separated-no-commit\n' > "$INST_CFG_BAD/skills/vault.lock"
out7=$(HOME="$TMP_ROOT/inst-home-bad" FIRSTMATE_ROOT="$TMP_ROOT/inst-dest-bad" \
  FM_HOME="$TMP_ROOT/inst-fm-home-bad" FM_CONFIG_ENV="$TMP_ROOT/inst-env-bad" \
  FM_SKILLS_ROOT="$TMP_ROOT/inst-skills-bad" FM_SKILL_CACHE="$TMP_ROOT/inst-skill-cache-bad" \
  FM_VAULT_CACHE="$TMP_ROOT/inst-vault-cache-bad" FM_BIN_DIR="$TMP_ROOT/inst-bin-dir-bad" \
  PI_CODING_AGENT_DIR="$TMP_ROOT/inst-pi-agent-bad" XDG_CONFIG_HOME="$TMP_ROOT/inst-xdg-bad" \
  PATH="$INST_FAKE_BIN:$SYS_BIN" \
  bash -c 'mkdir -p "$FIRSTMATE_ROOT" "$HOME"; printf fixture > "$FIRSTMATE_ROOT/AGENTS.md"; git init -q "$HOME" >/dev/null 2>&1 || true; "$1/install.sh"' _ "$INST_CFG_BAD" 2>&1); code7=$?
if [ "$code7" -eq 0 ]; then fail '7 malformed lock: expected nonzero exit, got 0'; else pass '7 malformed lock: exit code is nonzero'; fi
contains '7 malformed lock: names it malformed' "$out7" 'malformed'

# --- 8. Pre-existing non-git directory at the cache path: refused, never
#    deleted (an unverified directory must never be rm -rf'd on the way to
#    a fresh clone) -----------------------------------------------------
mkdir -p "$TMP_ROOT/inst-vault-cache-nongit/test-owner-test-vault"
printf 'precious\n' > "$TMP_ROOT/inst-vault-cache-nongit/test-owner-test-vault/precious.txt"
out8=$(run_fake_install nongit); code8=$?
if [ "$code8" -eq 0 ]; then fail '8 non-git cache dir: expected nonzero exit, got 0'; else pass '8 non-git cache dir: exit code is nonzero'; fi
contains '8 non-git cache dir: refuses without attempting a clone' "$out8" 'is not a git checkout'
contains '8 non-git cache dir: names it install-managed' "$out8" 'install-managed'
if [ -f "$TMP_ROOT/inst-vault-cache-nongit/test-owner-test-vault/precious.txt" ]; then
  pass '8 non-git cache dir: pre-existing content is never deleted'
else
  fail '8 non-git cache dir: pre-existing content is never deleted'
fi

# --- 9. Corrupt cache (.git present but not a readable checkout): diagnosed
#    as corrupt, never misreported as offline/wrong-pin --------------------
mkdir -p "$TMP_ROOT/inst-vault-cache-corrupt/test-owner-test-vault/.git"
printf 'garbage\n' > "$TMP_ROOT/inst-vault-cache-corrupt/test-owner-test-vault/.git/garbage"
verify9=$(run_fake_install corrupt --verify); code9v=$?
if [ "$code9v" -eq 0 ]; then fail '9 corrupt cache verify: expected nonzero exit, got 0'; else pass '9 corrupt cache verify: exit code is nonzero'; fi
contains '9 corrupt cache verify: diagnosed as corrupt' "$verify9" 'is corrupt'
not_contains '9 corrupt cache verify: never misdiagnosed as offline/wrong-pin' "$verify9" 'offline, or the pin is wrong'
real9=$(run_fake_install corrupt); code9r=$?
if [ "$code9r" -eq 0 ]; then fail '9 corrupt cache real run: expected nonzero exit, got 0'; else pass '9 corrupt cache real run: exit code is nonzero'; fi
contains '9 corrupt cache real run: diagnosed as corrupt' "$real9" 'is corrupt'
not_contains '9 corrupt cache real run: never misdiagnosed as offline/wrong-pin' "$real9" 'offline, or the pin is wrong'

# --- 10. Clone failure surfaces git's own stderr, never silently swallowed -
BADORIGIN_HOME="$TMP_ROOT/inst-home-badorigin"
mkdir -p "$BADORIGIN_HOME" "$TMP_ROOT/inst-dest-badorigin"
cat > "$BADORIGIN_HOME/.gitconfig" <<EOF
[user]
	email = t@example.invalid
	name = t
[url "$TMP_ROOT/no-such-origin-at-all"]
	insteadOf = https://github.com/$VAULT_REPO_ID.git
EOF
printf 'fixture\n' > "$TMP_ROOT/inst-dest-badorigin/AGENTS.md"
out10=$(PATH="$INST_FAKE_BIN:$SYS_BIN" HOME="$BADORIGIN_HOME" FIRSTMATE_ROOT="$TMP_ROOT/inst-dest-badorigin" \
  FM_HOME="$TMP_ROOT/inst-fm-home-badorigin" FM_CONFIG_ENV="$TMP_ROOT/inst-env-badorigin" \
  FM_SKILLS_ROOT="$TMP_ROOT/inst-skills-badorigin" FM_SKILL_CACHE="$TMP_ROOT/inst-skill-cache-badorigin" \
  FM_VAULT_CACHE="$TMP_ROOT/inst-vault-cache-badorigin" FM_BIN_DIR="$TMP_ROOT/inst-bin-dir-badorigin" \
  PI_CODING_AGENT_DIR="$TMP_ROOT/inst-pi-agent-badorigin" XDG_CONFIG_HOME="$TMP_ROOT/inst-xdg-badorigin" \
  "$INST_CFG/install.sh" 2>&1); code10=$?
if [ "$code10" -eq 0 ]; then fail '10 clone failure: expected nonzero exit, got 0'; else pass '10 clone failure: exit code is nonzero'; fi
contains '10 clone failure: reports could not clone' "$out10" 'could not clone'
contains "10 clone failure: git's own stderr is visible, never swallowed" "$out10" 'fatal:'

# =============================================================================
# B. bin/fm-doctor: vault.pin / vault.no_global_leak state coverage
# =============================================================================

DOC="$CONFIG_ROOT/bin/fm-doctor"
DOC_HOME="$TMP_ROOT/doc-home"
mkdir -p "$DOC_HOME"

run_doc() { # <vault-lock-file-or-empty> <vault-cache-dir> <skills-root-dir> [--json]
  local lock=$1 cache=$2 sroot=$3; shift 3
  FM_VAULT_LOCK="$lock" FM_VAULT_CACHE="$cache" FM_SKILLS_ROOT="$sroot" \
    HOME="$DOC_HOME" FIRSTMATE_ROOT="$TMP_ROOT/doc-no-firstmate" FM_HOME="$TMP_ROOT/doc-fm-home" \
    "$DOC" "$@" 2>&1
}

NO_LOCK="$TMP_ROOT/doc-no-such-lock"

# --- B1. No skills/vault.lock at all -> NOT_APPLICABLE ----------------------
out=$(run_doc "$NO_LOCK" "$TMP_ROOT/doc-cache-b1" "$TMP_ROOT/doc-skills-b1")
contains 'B1 no lock: vault.pin is NOT_APPLICABLE' "$out" 'NOT_APPLICABLE vault.pin'
contains 'B1 no lock: no_global_leak is NOT_APPLICABLE' "$out" 'NOT_APPLICABLE vault.no_global_leak'

# --- fixture lock used by every remaining doctor scenario -------------------
DOC_LOCK="$TMP_ROOT/doc-vault.lock"
DOC_SHA="1111111111111111111111111111111111111111"
printf 'test-owner/test-vault\t%s\n' "$DOC_SHA" > "$DOC_LOCK"

# --- B2. Lock present, cache absent -> FAIL absent ---------------------------
out=$(run_doc "$DOC_LOCK" "$TMP_ROOT/doc-cache-absent" "$TMP_ROOT/doc-skills-b2")
contains 'B2 absent cache: vault.pin is FAIL' "$out" 'FAIL          vault.pin'
contains 'B2 absent cache: names it absent' "$out" 'cache absent'

# --- a real local checkout at the exact pinned SHA, for the healthy case ----
DOC_CACHE_HEALTHY="$TMP_ROOT/doc-cache-healthy/test-owner-test-vault"
mkdir -p "$DOC_CACHE_HEALTHY"
git -C "$DOC_CACHE_HEALTHY" init -q
git -C "$DOC_CACHE_HEALTHY" config user.email t@example.invalid
git -C "$DOC_CACHE_HEALTHY" config user.name t
printf 'fixture\n' > "$DOC_CACHE_HEALTHY/README.md"
mkdir -p "$DOC_CACHE_HEALTHY/bin"
printf '#!/usr/bin/env bun\n' > "$DOC_CACHE_HEALTHY/bin/lookup.ts"
git -C "$DOC_CACHE_HEALTHY" add -A
GIT_AUTHOR_DATE='2026-01-01T00:00:00' GIT_COMMITTER_DATE='2026-01-01T00:00:00' \
  git -C "$DOC_CACHE_HEALTHY" commit -q -m fixture
# Doctor derives the cache directory name from the lock's repo id
# (owner/repo -> owner-repo), exactly as install.sh does; this fixture's
# commit is whatever content produced above, and the lock below is written
# to match it exactly, not the other way around, so no hash needs faking.
DOC_HEALTHY_SHA=$(git -C "$DOC_CACHE_HEALTHY" rev-parse HEAD)
DOC_LOCK_HEALTHY="$TMP_ROOT/doc-vault-healthy.lock"
printf 'test-owner/test-vault\t%s\n' "$DOC_HEALTHY_SHA" > "$DOC_LOCK_HEALTHY"

# --- B3. Lock present, cache present, clean, matching -> PASS healthy ------
out=$(run_doc "$DOC_LOCK_HEALTHY" "$TMP_ROOT/doc-cache-healthy" "$TMP_ROOT/doc-skills-b3")
contains 'B3 healthy: vault.pin is PASS' "$out" 'PASS          vault.pin'
contains 'B3 healthy: no_global_leak is PASS' "$out" 'PASS          vault.no_global_leak'
json=$(run_doc "$DOC_LOCK_HEALTHY" "$TMP_ROOT/doc-cache-healthy" "$TMP_ROOT/doc-skills-b3" --json)
contains 'B3 healthy JSON: state is healthy' "$json" '"state":"healthy"'
contains 'B3 healthy JSON: pinned_commit is the exact SHA' "$json" "\"pinned_commit\":\"$DOC_HEALTHY_SHA\""

# --- B3b. Healthy commit/clean but missing bin/lookup.ts: FAIL, never PASS -
DOC_CACHE_NOLOOKUP="$TMP_ROOT/doc-cache-nolookup/test-owner-test-vault"
mkdir -p "$DOC_CACHE_NOLOOKUP"
git -C "$DOC_CACHE_NOLOOKUP" init -q
git -C "$DOC_CACHE_NOLOOKUP" config user.email t@example.invalid
git -C "$DOC_CACHE_NOLOOKUP" config user.name t
printf 'fixture\n' > "$DOC_CACHE_NOLOOKUP/README.md"
git -C "$DOC_CACHE_NOLOOKUP" add -A
GIT_AUTHOR_DATE='2026-01-01T00:00:00' GIT_COMMITTER_DATE='2026-01-01T00:00:00' \
  git -C "$DOC_CACHE_NOLOOKUP" commit -q -m fixture
DOC_NOLOOKUP_SHA=$(git -C "$DOC_CACHE_NOLOOKUP" rev-parse HEAD)
DOC_LOCK_NOLOOKUP="$TMP_ROOT/doc-vault-nolookup.lock"
printf 'test-owner/test-vault\t%s\n' "$DOC_NOLOOKUP_SHA" > "$DOC_LOCK_NOLOOKUP"
out=$(run_doc "$DOC_LOCK_NOLOOKUP" "$TMP_ROOT/doc-cache-nolookup" "$TMP_ROOT/doc-skills-b3b")
contains 'B3b missing lookup surface: vault.pin is FAIL' "$out" 'FAIL          vault.pin'
contains 'B3b missing lookup surface: names the lookup surface' "$out" 'lookup.ts'
json=$(run_doc "$DOC_LOCK_NOLOOKUP" "$TMP_ROOT/doc-cache-nolookup" "$TMP_ROOT/doc-skills-b3b" --json)
not_contains 'B3b missing lookup surface JSON: never falsely healthy' "$json" '"state":"healthy"'

# --- B4. Lock present, cache present, clean, wrong revision -> FAIL --------
out=$(run_doc "$DOC_LOCK" "$TMP_ROOT/doc-cache-healthy" "$TMP_ROOT/doc-skills-b4")
contains 'B4 wrong revision: vault.pin is FAIL' "$out" 'FAIL          vault.pin'
contains 'B4 wrong revision: names the pinned commit it expected' "$out" "${DOC_SHA:0:12}"
json=$(run_doc "$DOC_LOCK" "$TMP_ROOT/doc-cache-healthy" "$TMP_ROOT/doc-skills-b4" --json)
contains 'B4 wrong revision JSON: state is wrong_revision' "$json" '"state":"wrong_revision"'

# --- B5. Lock present, cache present, dirty -> FAIL, never PASS ------------
printf 'dirty\n' >> "$DOC_CACHE_HEALTHY/README.md"
out=$(run_doc "$DOC_LOCK_HEALTHY" "$TMP_ROOT/doc-cache-healthy" "$TMP_ROOT/doc-skills-b5")
contains 'B5 dirty: vault.pin is FAIL' "$out" 'FAIL          vault.pin'
contains 'B5 dirty: names it must never be hand-edited' "$out" 'must never be hand-edited'
json=$(run_doc "$DOC_LOCK_HEALTHY" "$TMP_ROOT/doc-cache-healthy" "$TMP_ROOT/doc-skills-b5" --json)
contains 'B5 dirty JSON: state is dirty' "$json" '"state":"dirty"'
git -C "$DOC_CACHE_HEALTHY" checkout -q -- README.md

# --- B6. Lock present, cache present, corrupt (not a git checkout) --------
DOC_CACHE_CORRUPT="$TMP_ROOT/doc-cache-corrupt/test-owner-test-vault"
mkdir -p "$DOC_CACHE_CORRUPT/.git"
out=$(run_doc "$DOC_LOCK" "$TMP_ROOT/doc-cache-corrupt" "$TMP_ROOT/doc-skills-b6")
contains 'B6 corrupt: vault.pin is FAIL' "$out" 'FAIL          vault.pin'
contains 'B6 corrupt: names it corrupt' "$out" 'corrupt'
json=$(run_doc "$DOC_LOCK" "$TMP_ROOT/doc-cache-corrupt" "$TMP_ROOT/doc-skills-b6" --json)
contains 'B6 corrupt JSON: state is corrupt' "$json" '"state":"corrupt"'

# --- B7. no_global_leak: a stray global symlink into the vault cache -------
LEAK_SKILLS="$TMP_ROOT/doc-skills-b7"
mkdir -p "$LEAK_SKILLS"
ln -s "$DOC_CACHE_HEALTHY" "$LEAK_SKILLS/some-vault-skill"
out=$(run_doc "$DOC_LOCK_HEALTHY" "$TMP_ROOT/doc-cache-healthy" "$LEAK_SKILLS")
contains 'B7 leak: no_global_leak is FAIL' "$out" 'FAIL          vault.no_global_leak'
contains 'B7 leak: names the leaking entry' "$out" 'some-vault-skill'
contains 'B7 leak: names it must never be globally registered' "$out" 'must never be globally registered'

# --- B8. no_global_leak: the vault path named in OMP's own skills config ---
mkdir -p "$DOC_HOME/.omp/agent"
printf 'skills:\n  customDirectories:\n    - %s\n' "$DOC_CACHE_HEALTHY" > "$DOC_HOME/.omp/agent/config.yml"
out=$(run_doc "$DOC_LOCK_HEALTHY" "$TMP_ROOT/doc-cache-healthy" "$TMP_ROOT/doc-skills-b8")
contains 'B8 omp config leak: no_global_leak is FAIL' "$out" 'FAIL          vault.no_global_leak'
contains 'B8 omp config leak: names the omp config path' "$out" "$DOC_HOME/.omp/agent/config.yml"
rm -f "$DOC_HOME/.omp/agent/config.yml"

# --- B8b. no_global_leak: the vault path in OMP config using the ~/-relative
#    form OMP itself expands at load time, not just the absolute path -----
DOC_CACHE_TILDE_ROOT="$DOC_HOME/vault-cache-tilde"
cp -R "$TMP_ROOT/doc-cache-healthy" "$DOC_CACHE_TILDE_ROOT"
mkdir -p "$DOC_HOME/.omp/agent"
printf 'skills:\n  customDirectories:\n    - ~/vault-cache-tilde/test-owner-test-vault\n' > "$DOC_HOME/.omp/agent/config.yml"
out=$(run_doc "$DOC_LOCK_HEALTHY" "$DOC_CACHE_TILDE_ROOT" "$TMP_ROOT/doc-skills-b8b")
contains 'B8b omp config tilde leak: no_global_leak is FAIL' "$out" 'FAIL          vault.no_global_leak'
contains 'B8b omp config tilde leak: names the omp config path' "$out" "$DOC_HOME/.omp/agent/config.yml"
rm -f "$DOC_HOME/.omp/agent/config.yml"
rm -rf "$DOC_CACHE_TILDE_ROOT"

printf '\nVAULT TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
