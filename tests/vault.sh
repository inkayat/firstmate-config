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
for _tool in bash git sed awk grep wc date find stat readlink basename dirname tr head cat mkdir env sort ln rm mv mktemp cp printf bun; do
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
cp "$CONFIG_ROOT/firstmate/fm-vault-lib.sh" "$INST_CFG/firstmate/fm-vault-lib.sh"
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
mkdir -p "$V_ORIGIN/bin"
printf '# fixture vault\n' > "$V_ORIGIN/README.md"
printf 'entries: {}\n' > "$V_ORIGIN/catalog.yaml"
printf '#!/usr/bin/env bun\n' > "$V_ORIGIN/bin/lookup.ts"
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

run_fake_install_cfg() { # <suffix> <config-root> [install.sh args...]
  local suffix=$1 cfg=$2; shift 2
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
  "$cfg/install.sh" "$@" 2>&1
}

run_fake_install() { # <suffix> [install.sh args...]
  local suffix=$1; shift
  run_fake_install_cfg "$suffix" "$INST_CFG" "$@"
}

# The cache layout is commit-qualified and immutable: one directory per exact
# pinned commit, never a mutable owner/repo checkout that gets re-pointed.
VAULT_CACHE_fresh="$TMP_ROOT/inst-vault-cache-fresh/test-owner-test-vault"
VAULT_DEST_fresh="$VAULT_CACHE_fresh/$V_SHA1"
VAULT_DEST2_fresh="$VAULT_CACHE_fresh/$V_SHA2"

# --- 1. Fresh run clones and pins to the exact commit -----------------------
out=$(run_fake_install fresh); code=$?
check '1 fresh run: exit code is 0' 0 "$code"
contains '1 fresh run: reports the vault step ran' "$out" '10. specialist skill vault'
contains '1 fresh run: reports the clone' "$out" "cloned $VAULT_REPO_ID"
check '1 vault cache: cloned at the pinned commit' "$V_SHA1" "$(git -C "$VAULT_DEST_fresh" rev-parse HEAD 2>/dev/null || printf '')"
check '1 vault cache: detached HEAD, never a branch' HEAD "$(git -C "$VAULT_DEST_fresh" symbolic-ref -q --short HEAD 2>/dev/null || printf HEAD)"
contains '1 env file: exports FM_SKILL_VAULT_ROOT at the commit-qualified cache path' \
  "$(cat "$TMP_ROOT/inst-env-fresh" 2>/dev/null)" "FM_SKILL_VAULT_ROOT=\"$VAULT_DEST_fresh\""
not_contains '1 env file: the old ambiguous FM_VAULT_ROOT name is gone' \
  "$(cat "$TMP_ROOT/inst-env-fresh" 2>/dev/null)" 'FM_VAULT_ROOT='
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

# --- 4. A new pin creates a separate immutable commit directory -------------
# Pinning a new commit never re-points an existing directory: it clones the new
# commit alongside, and the previous commit's directory is left exactly as it
# was (its own commit, clean tree), so an exact path already handed to a worker
# can never change its bytes underneath.
printf '%s\t%s\n' "$VAULT_REPO_ID" "$V_SHA2" > "$INST_CFG/skills/vault.lock"
out4=$(run_fake_install fresh); code4=$?
check '4 new pin: exit code is 0' 0 "$code4"
check '4 new pin: the new commit directory is at that exact commit' "$V_SHA2" "$(git -C "$VAULT_DEST2_fresh" rev-parse HEAD 2>/dev/null || printf '')"
check '4 new pin: the previous commit directory is still at its own commit' "$V_SHA1" "$(git -C "$VAULT_DEST_fresh" rev-parse HEAD 2>/dev/null || printf '')"
check '4 new pin: the previous commit directory is byte-stable (clean tree)' '' "$(git -C "$VAULT_DEST_fresh" status --porcelain 2>/dev/null)"
contains '4 new pin: env repoints to the new commit directory' \
  "$(cat "$TMP_ROOT/inst-env-fresh" 2>/dev/null)" "FM_SKILL_VAULT_ROOT=\"$VAULT_DEST2_fresh\""
printf '%s\t%s\n' "$VAULT_REPO_ID" "$V_SHA1" > "$INST_CFG/skills/vault.lock"

# --- 4b. A commit directory not at its own commit is refused, never re-pinned
git -C "$VAULT_DEST_fresh" checkout -q --detach "$V_SHA2"
verify4b=$(run_fake_install fresh --verify); code4bv=$?
if [ "$code4bv" -eq 0 ]; then fail '4b wrong revision verify: expected nonzero exit, got 0'; else pass '4b wrong revision verify: exit code is nonzero'; fi
contains '4b wrong revision verify: reported as a failure, never drift' "$verify4b" 'FAIL'
contains '4b wrong revision verify: names the immutable contract' "$verify4b" 'never re-pinned in place'
check '4b wrong revision verify: never repoints during --verify' "$V_SHA2" "$(git -C "$VAULT_DEST_fresh" rev-parse HEAD)"
real4b=$(run_fake_install fresh); code4br=$?
if [ "$code4br" -eq 0 ]; then fail '4b wrong revision real run: expected nonzero exit, got 0'; else pass '4b wrong revision real run: exit code is nonzero'; fi
not_contains '4b wrong revision real run: never reports a repair as a change' "$real4b" '  changed test-owner/test-vault'
check '4b wrong revision real run: never repoints in place' "$V_SHA2" "$(git -C "$VAULT_DEST_fresh" rev-parse HEAD)"
git -C "$VAULT_DEST_fresh" checkout -q --detach "$V_SHA1"

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
mkdir -p "$TMP_ROOT/inst-vault-cache-nongit/test-owner-test-vault/$V_SHA1"
printf 'precious\n' > "$TMP_ROOT/inst-vault-cache-nongit/test-owner-test-vault/$V_SHA1/precious.txt"
out8=$(run_fake_install nongit); code8=$?
if [ "$code8" -eq 0 ]; then fail '8 non-git cache dir: expected nonzero exit, got 0'; else pass '8 non-git cache dir: exit code is nonzero'; fi
contains '8 non-git cache dir: refuses without attempting a clone' "$out8" 'is not a git checkout'
contains '8 non-git cache dir: names it install-managed' "$out8" 'install-managed'
if [ -f "$TMP_ROOT/inst-vault-cache-nongit/test-owner-test-vault/$V_SHA1/precious.txt" ]; then
  pass '8 non-git cache dir: pre-existing content is never deleted'
else
  fail '8 non-git cache dir: pre-existing content is never deleted'
fi

# --- 9. Corrupt cache (.git present but not a readable checkout): diagnosed
#    as corrupt, never misreported as offline/wrong-pin --------------------
mkdir -p "$TMP_ROOT/inst-vault-cache-corrupt/test-owner-test-vault/$V_SHA1/.git"
printf 'garbage\n' > "$TMP_ROOT/inst-vault-cache-corrupt/test-owner-test-vault/$V_SHA1/.git/garbage"
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
if [ -e "$TMP_ROOT/inst-vault-cache-badorigin/test-owner-test-vault/$V_SHA1" ]; then
  fail '10 clone failure: no incomplete commit directory is ever left behind'
else
  pass '10 clone failure: no incomplete commit directory is ever left behind'
fi
not_contains '10 clone failure: leaves no staging directory behind either' \
  "$(find "$TMP_ROOT/inst-vault-cache-badorigin" -maxdepth 3 2>/dev/null | tr '\n' ' ')" '.incomplete'

# --- 11. A commit directory missing the expected catalog surface is refused -
# Verification is not just "some clean git checkout at that sha": it must be
# the vault, i.e. carry the catalog and the lookup surface the selection
# policy reads. A same-sha checkout of something else must never be issued.
NOCAT_ORIGIN="$TMP_ROOT/vault-origin-nocat"
mkdir -p "$NOCAT_ORIGIN"
git -C "$NOCAT_ORIGIN" init -q
git -C "$NOCAT_ORIGIN" config user.email t@example.invalid
git -C "$NOCAT_ORIGIN" config user.name t
printf 'not the vault\n' > "$NOCAT_ORIGIN/README.md"
git -C "$NOCAT_ORIGIN" add -A
git -C "$NOCAT_ORIGIN" commit -q -m nocat
NOCAT_SHA=$(git -C "$NOCAT_ORIGIN" rev-parse HEAD)
INST_CFG_NOCAT="$TMP_ROOT/inst-cfg-nocat"
cp -R "$INST_CFG" "$INST_CFG_NOCAT"
printf '%s\t%s\n' "$VAULT_REPO_ID" "$NOCAT_SHA" > "$INST_CFG_NOCAT/skills/vault.lock"
mkdir -p "$TMP_ROOT/inst-vault-cache-nocat/test-owner-test-vault"
git clone -q "$NOCAT_ORIGIN" "$TMP_ROOT/inst-vault-cache-nocat/test-owner-test-vault/$NOCAT_SHA"
git -C "$TMP_ROOT/inst-vault-cache-nocat/test-owner-test-vault/$NOCAT_SHA" checkout -q --detach "$NOCAT_SHA"
out11=$(HOME="$TMP_ROOT/inst-home-nocat" FIRSTMATE_ROOT="$TMP_ROOT/inst-dest-nocat" \
  FM_HOME="$TMP_ROOT/inst-fm-home-nocat" FM_CONFIG_ENV="$TMP_ROOT/inst-env-nocat" \
  FM_SKILLS_ROOT="$TMP_ROOT/inst-skills-nocat" FM_SKILL_CACHE="$TMP_ROOT/inst-skill-cache-nocat" \
  FM_VAULT_CACHE="$TMP_ROOT/inst-vault-cache-nocat" FM_BIN_DIR="$TMP_ROOT/inst-bin-dir-nocat" \
  PI_CODING_AGENT_DIR="$TMP_ROOT/inst-pi-agent-nocat" XDG_CONFIG_HOME="$TMP_ROOT/inst-xdg-nocat" \
  PATH="$INST_FAKE_BIN:$SYS_BIN" \
  bash -c 'mkdir -p "$FIRSTMATE_ROOT" "$HOME"; printf fixture > "$FIRSTMATE_ROOT/AGENTS.md"; "$1/install.sh"' _ "$INST_CFG_NOCAT" 2>&1); code11=$?
if [ "$code11" -eq 0 ]; then fail '11 missing catalog surface: expected nonzero exit, got 0'; else pass '11 missing catalog surface: exit code is nonzero'; fi
contains '11 missing catalog surface: names catalog.yaml' "$out11" 'catalog.yaml'

# --- 12. A commit directory whose catalog does not parse is refused ---------
# The vault's own lookup surface is the parser; a cache whose catalog it
# rejects is never reported as usable (skipped where bun is unavailable,
# exactly as install.sh treats bun as an optional tool).
if command -v bun >/dev/null 2>&1; then
  BADCAT_ORIGIN="$TMP_ROOT/vault-origin-badcat"
  mkdir -p "$BADCAT_ORIGIN/bin"
  git -C "$BADCAT_ORIGIN" init -q
  git -C "$BADCAT_ORIGIN" config user.email t@example.invalid
  git -C "$BADCAT_ORIGIN" config user.name t
  printf 'entries: [\n' > "$BADCAT_ORIGIN/catalog.yaml"
  printf 'throw new Error("catalog.yaml failed validation");\n' > "$BADCAT_ORIGIN/bin/lookup.ts"
  git -C "$BADCAT_ORIGIN" add -A
  git -C "$BADCAT_ORIGIN" commit -q -m badcat
  BADCAT_SHA=$(git -C "$BADCAT_ORIGIN" rev-parse HEAD)
  INST_CFG_BADCAT="$TMP_ROOT/inst-cfg-badcat"
  cp -R "$INST_CFG" "$INST_CFG_BADCAT"
  printf '%s\t%s\n' "$VAULT_REPO_ID" "$BADCAT_SHA" > "$INST_CFG_BADCAT/skills/vault.lock"
  mkdir -p "$TMP_ROOT/inst-vault-cache-badcat/test-owner-test-vault"
  git clone -q "$BADCAT_ORIGIN" "$TMP_ROOT/inst-vault-cache-badcat/test-owner-test-vault/$BADCAT_SHA"
  git -C "$TMP_ROOT/inst-vault-cache-badcat/test-owner-test-vault/$BADCAT_SHA" checkout -q --detach "$BADCAT_SHA"
  out12=$(HOME="$TMP_ROOT/inst-home-badcat" FIRSTMATE_ROOT="$TMP_ROOT/inst-dest-badcat" \
    FM_HOME="$TMP_ROOT/inst-fm-home-badcat" FM_CONFIG_ENV="$TMP_ROOT/inst-env-badcat" \
    FM_SKILLS_ROOT="$TMP_ROOT/inst-skills-badcat" FM_SKILL_CACHE="$TMP_ROOT/inst-skill-cache-badcat" \
    FM_VAULT_CACHE="$TMP_ROOT/inst-vault-cache-badcat" FM_BIN_DIR="$TMP_ROOT/inst-bin-dir-badcat" \
    PI_CODING_AGENT_DIR="$TMP_ROOT/inst-pi-agent-badcat" XDG_CONFIG_HOME="$TMP_ROOT/inst-xdg-badcat" \
    PATH="$INST_FAKE_BIN:$SYS_BIN" \
    bash -c 'mkdir -p "$FIRSTMATE_ROOT" "$HOME"; printf fixture > "$FIRSTMATE_ROOT/AGENTS.md"; "$1/install.sh"' _ "$INST_CFG_BADCAT" 2>&1); code12=$?
  if [ "$code12" -eq 0 ]; then fail '12 unparseable catalog: expected nonzero exit, got 0'; else pass '12 unparseable catalog: exit code is nonzero'; fi
  contains '12 unparseable catalog: names the unparseable catalog' "$out12" 'catalog'
else
  pass '12 unparseable catalog: skipped (bun not on PATH)'
fi

# --- 13. A failed vault step never publishes the vault root ----------------
# The env file is the handoff surface: a worker resolves its skill path under
# FM_SKILL_VAULT_ROOT. A commit directory that does not verify must therefore
# never be published there, even though its path is perfectly derivable from
# the lock.
INVALID_CACHE="$TMP_ROOT/inst-vault-cache-invalid/test-owner-test-vault/$V_SHA1"
mkdir -p "$INVALID_CACHE/.git"
printf 'garbage\n' > "$INVALID_CACHE/.git/garbage"
out13=$(run_fake_install invalid); code13=$?
if [ "$code13" -eq 0 ]; then fail '13 invalid cache: expected nonzero exit, got 0'; else pass '13 invalid cache: exit code is nonzero'; fi
contains '13 invalid cache: the env file exists' "$(cat "$TMP_ROOT/inst-env-invalid" 2>/dev/null)" 'FM_SKILL_VAULT_ROOT='
not_contains '13 invalid cache: the unverified commit directory is never published' \
  "$(cat "$TMP_ROOT/inst-env-invalid" 2>/dev/null)" "FM_SKILL_VAULT_ROOT=\"$INVALID_CACHE\""
contains '13 invalid cache: the vault root is left unset instead' \
  "$(cat "$TMP_ROOT/inst-env-invalid" 2>/dev/null)" 'FM_SKILL_VAULT_ROOT=""'

# --- 14. A failed NEW pin preserves the last known-good vault root ---------
# Pin A is installed and published; pin B's directory is then planted corrupt.
# The failing run must keep pointing workers at the still-valid pin A rather
# than at B or at nothing.
GOOD_A="$TMP_ROOT/inst-vault-cache-lastgood/test-owner-test-vault/$V_SHA1"
INST_CFG_LASTGOOD="$TMP_ROOT/inst-cfg-lastgood"
cp -R "$INST_CFG" "$INST_CFG_LASTGOOD"
out14a=$(run_fake_install_cfg lastgood "$INST_CFG_LASTGOOD"); code14a=$?
check '14 last known-good: first install exit code is 0' 0 "$code14a"
contains '14 last known-good: pin A is published' \
  "$(cat "$TMP_ROOT/inst-env-lastgood" 2>/dev/null)" "FM_SKILL_VAULT_ROOT=\"$GOOD_A\""
printf '%s\t%s\n' "$VAULT_REPO_ID" "$V_SHA2" > "$INST_CFG_LASTGOOD/skills/vault.lock"
BAD_B="$TMP_ROOT/inst-vault-cache-lastgood/test-owner-test-vault/$V_SHA2"
mkdir -p "$BAD_B/.git"
printf 'garbage\n' > "$BAD_B/.git/garbage"
out14b=$(run_fake_install_cfg lastgood "$INST_CFG_LASTGOOD"); code14b=$?
if [ "$code14b" -eq 0 ]; then fail '14 last known-good: failing run expected nonzero exit, got 0'; else pass '14 last known-good: failing run exit code is nonzero'; fi
not_contains '14 last known-good: the invalid new pin is never published' \
  "$(cat "$TMP_ROOT/inst-env-lastgood" 2>/dev/null)" "FM_SKILL_VAULT_ROOT=\"$BAD_B\""
contains '14 last known-good: the previously verified root is preserved' \
  "$(cat "$TMP_ROOT/inst-env-lastgood" 2>/dev/null)" "FM_SKILL_VAULT_ROOT=\"$GOOD_A\""

# --- 15. Removing skills/vault.lock disables the vault for real ------------
# Last-known-good exists to survive a broken candidate for a vault that is
# still configured. A deliberately disabled vault is the opposite case: with
# no lock there is nothing to publish, so a stale root must not keep the vault
# reachable through the environment.
GOOD_15="$TMP_ROOT/inst-vault-cache-nolock15/test-owner-test-vault/$V_SHA1"
INST_CFG_NOLOCK15="$TMP_ROOT/inst-cfg-nolock15"
cp -R "$INST_CFG" "$INST_CFG_NOLOCK15"
out15a=$(run_fake_install_cfg nolock15 "$INST_CFG_NOLOCK15"); code15a=$?
check '15 lock removed: first install exit code is 0' 0 "$code15a"
contains '15 lock removed: the configured vault root is published first' \
  "$(cat "$TMP_ROOT/inst-env-nolock15" 2>/dev/null)" "FM_SKILL_VAULT_ROOT=\"$GOOD_15\""
rm -f "$INST_CFG_NOLOCK15/skills/vault.lock"
out15b=$(run_fake_install_cfg nolock15 "$INST_CFG_NOLOCK15"); code15b=$?
check '15 lock removed: reconcile exit code is 0' 0 "$code15b"
contains '15 lock removed: the vault step reports it is unconfigured' "$out15b" 'no skills/vault.lock; skipping'
contains '15 lock removed: the vault root is cleared' \
  "$(cat "$TMP_ROOT/inst-env-nolock15" 2>/dev/null)" 'FM_SKILL_VAULT_ROOT=""'
not_contains '15 lock removed: the stale root is never preserved' \
  "$(cat "$TMP_ROOT/inst-env-nolock15" 2>/dev/null)" "FM_SKILL_VAULT_ROOT=\"$GOOD_15\""
check '15 lock removed: the cached commit directory itself is left alone' \
  "$V_SHA1" "$(git -C "$GOOD_15" rev-parse HEAD 2>/dev/null || printf '')"
doc15=$(FM_VAULT_LOCK="$INST_CFG_NOLOCK15/skills/vault.lock" FM_VAULT_CACHE="$TMP_ROOT/inst-vault-cache-nolock15" \
  FM_SKILLS_ROOT="$TMP_ROOT/doc-skills-15" HOME="$TMP_ROOT/doc-home-15" \
  FIRSTMATE_ROOT="$TMP_ROOT/doc-no-firstmate" FM_HOME="$TMP_ROOT/doc-fm-home" "$CONFIG_ROOT/bin/fm-doctor" 2>&1)
contains '15 lock removed: doctor reports the vault as not configured' "$doc15" 'NOT_APPLICABLE vault.pin'

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
# Built in a scratch directory first: the cache path is commit-qualified
# (<cache>/<owner-repo>/<exact-commit>), so the directory can only be named
# once the fixture's own commit exists. The lock below is written to match
# that commit exactly, not the other way around, so no hash needs faking.
doc_build_vault() { # <scratch-dir>
  mkdir -p "$1/bin"
  git -C "$1" init -q
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name t
  printf 'fixture\n' > "$1/README.md"
  printf 'entries: {}\n' > "$1/catalog.yaml"
  printf '#!/usr/bin/env bun\n' > "$1/bin/lookup.ts"
  git -C "$1" add -A
  GIT_AUTHOR_DATE='2026-01-01T00:00:00' GIT_COMMITTER_DATE='2026-01-01T00:00:00' \
    git -C "$1" commit -q -m fixture
  git -C "$1" rev-parse HEAD
}

DOC_BUILD_HEALTHY="$TMP_ROOT/doc-build-healthy"
DOC_HEALTHY_SHA=$(doc_build_vault "$DOC_BUILD_HEALTHY")
DOC_CACHE_HEALTHY_ROOT="$TMP_ROOT/doc-cache-healthy"
DOC_CACHE_HEALTHY="$DOC_CACHE_HEALTHY_ROOT/test-owner-test-vault/$DOC_HEALTHY_SHA"
mkdir -p "$(dirname "$DOC_CACHE_HEALTHY")"
mv "$DOC_BUILD_HEALTHY" "$DOC_CACHE_HEALTHY"
DOC_LOCK_HEALTHY="$TMP_ROOT/doc-vault-healthy.lock"
printf 'test-owner/test-vault\t%s\n' "$DOC_HEALTHY_SHA" > "$DOC_LOCK_HEALTHY"

# --- B3. Lock present, cache present, clean, matching -> PASS healthy ------
out=$(run_doc "$DOC_LOCK_HEALTHY" "$TMP_ROOT/doc-cache-healthy" "$TMP_ROOT/doc-skills-b3")
contains 'B3 healthy: vault.pin is PASS' "$out" 'PASS          vault.pin'
contains 'B3 healthy: no_global_leak is PASS' "$out" 'PASS          vault.no_global_leak'
json=$(run_doc "$DOC_LOCK_HEALTHY" "$TMP_ROOT/doc-cache-healthy" "$TMP_ROOT/doc-skills-b3" --json)
contains 'B3 healthy JSON: state is healthy' "$json" '"state":"healthy"'
contains 'B3 healthy JSON: pinned_commit is the exact SHA' "$json" "\"pinned_commit\":\"$DOC_HEALTHY_SHA\""

# --- B3b. Healthy commit/clean but missing the catalog surface: FAIL -------
DOC_BUILD_NOLOOKUP="$TMP_ROOT/doc-build-nolookup"
mkdir -p "$DOC_BUILD_NOLOOKUP"
git -C "$DOC_BUILD_NOLOOKUP" init -q
git -C "$DOC_BUILD_NOLOOKUP" config user.email t@example.invalid
git -C "$DOC_BUILD_NOLOOKUP" config user.name t
printf 'fixture\n' > "$DOC_BUILD_NOLOOKUP/README.md"
git -C "$DOC_BUILD_NOLOOKUP" add -A
GIT_AUTHOR_DATE='2026-01-01T00:00:00' GIT_COMMITTER_DATE='2026-01-01T00:00:00' \
  git -C "$DOC_BUILD_NOLOOKUP" commit -q -m fixture
DOC_NOLOOKUP_SHA=$(git -C "$DOC_BUILD_NOLOOKUP" rev-parse HEAD)
DOC_CACHE_NOLOOKUP="$TMP_ROOT/doc-cache-nolookup/test-owner-test-vault/$DOC_NOLOOKUP_SHA"
mkdir -p "$(dirname "$DOC_CACHE_NOLOOKUP")"
mv "$DOC_BUILD_NOLOOKUP" "$DOC_CACHE_NOLOOKUP"
DOC_LOCK_NOLOOKUP="$TMP_ROOT/doc-vault-nolookup.lock"
printf 'test-owner/test-vault\t%s\n' "$DOC_NOLOOKUP_SHA" > "$DOC_LOCK_NOLOOKUP"
out=$(run_doc "$DOC_LOCK_NOLOOKUP" "$TMP_ROOT/doc-cache-nolookup" "$TMP_ROOT/doc-skills-b3b")
contains 'B3b missing lookup surface: vault.pin is FAIL' "$out" 'FAIL          vault.pin'
contains 'B3b missing lookup surface: names the lookup surface' "$out" 'lookup.ts'
json=$(run_doc "$DOC_LOCK_NOLOOKUP" "$TMP_ROOT/doc-cache-nolookup" "$TMP_ROOT/doc-skills-b3b" --json)
not_contains 'B3b missing lookup surface JSON: never falsely healthy' "$json" '"state":"healthy"'

# --- B4. A commit directory whose checkout is not that commit -> FAIL ------
# The directory name is the expected commit, so a checkout at any other
# commit is corruption of an immutable directory, never ordinary drift.
DOC_CACHE_WRONGREV="$TMP_ROOT/doc-cache-wrongrev/test-owner-test-vault/$DOC_SHA"
mkdir -p "$(dirname "$DOC_CACHE_WRONGREV")"
cp -R "$DOC_CACHE_HEALTHY" "$DOC_CACHE_WRONGREV"
out=$(run_doc "$DOC_LOCK" "$TMP_ROOT/doc-cache-wrongrev" "$TMP_ROOT/doc-skills-b4")
contains 'B4 wrong revision: vault.pin is FAIL' "$out" 'FAIL          vault.pin'
contains 'B4 wrong revision: names the pinned commit it expected' "$out" "${DOC_SHA:0:12}"
json=$(run_doc "$DOC_LOCK" "$TMP_ROOT/doc-cache-wrongrev" "$TMP_ROOT/doc-skills-b4" --json)
contains 'B4 wrong revision JSON: state is wrong_revision' "$json" '"state":"wrong_revision"'

# --- B5. Lock present, cache present, dirty -> FAIL, never PASS ------------
printf 'dirty\n' >> "$DOC_CACHE_HEALTHY/README.md"
out=$(run_doc "$DOC_LOCK_HEALTHY" "$DOC_CACHE_HEALTHY_ROOT" "$TMP_ROOT/doc-skills-b5")
contains 'B5 dirty: vault.pin is FAIL' "$out" 'FAIL          vault.pin'
contains 'B5 dirty: names it must never be hand-edited' "$out" 'must never be hand-edited'
json=$(run_doc "$DOC_LOCK_HEALTHY" "$DOC_CACHE_HEALTHY_ROOT" "$TMP_ROOT/doc-skills-b5" --json)
contains 'B5 dirty JSON: state is dirty' "$json" '"state":"dirty"'
git -C "$DOC_CACHE_HEALTHY" checkout -q -- README.md

# --- B6. Lock present, cache present, corrupt (not a git checkout) --------
DOC_CACHE_CORRUPT="$TMP_ROOT/doc-cache-corrupt/test-owner-test-vault/$DOC_SHA"
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
out=$(run_doc "$DOC_LOCK_HEALTHY" "$DOC_CACHE_HEALTHY_ROOT" "$LEAK_SKILLS")
contains 'B7 leak: no_global_leak is FAIL' "$out" 'FAIL          vault.no_global_leak'
contains 'B7 leak: names the leaking entry' "$out" 'some-vault-skill'
contains 'B7 leak: names it must never be globally registered' "$out" 'must never be globally registered'

# --- B8. no_global_leak: the vault path named in OMP's own skills config ---
mkdir -p "$DOC_HOME/.omp/agent"
printf 'skills:\n  customDirectories:\n    - %s\n' "$DOC_CACHE_HEALTHY" > "$DOC_HOME/.omp/agent/config.yml"
out=$(run_doc "$DOC_LOCK_HEALTHY" "$DOC_CACHE_HEALTHY_ROOT" "$TMP_ROOT/doc-skills-b8")
contains 'B8 omp config leak: no_global_leak is FAIL' "$out" 'FAIL          vault.no_global_leak'
contains 'B8 omp config leak: names the omp config path' "$out" "$DOC_HOME/.omp/agent/config.yml"
rm -f "$DOC_HOME/.omp/agent/config.yml"

# --- B8b. no_global_leak: the vault path in OMP config using the ~/-relative
#    form OMP itself expands at load time, not just the absolute path -----
DOC_CACHE_TILDE_ROOT="$DOC_HOME/vault-cache-tilde"
cp -R "$DOC_CACHE_HEALTHY_ROOT" "$DOC_CACHE_TILDE_ROOT"
mkdir -p "$DOC_HOME/.omp/agent"
printf 'skills:\n  customDirectories:\n    - ~/vault-cache-tilde/test-owner-test-vault/%s\n' "$DOC_HEALTHY_SHA" > "$DOC_HOME/.omp/agent/config.yml"
out=$(run_doc "$DOC_LOCK_HEALTHY" "$DOC_CACHE_TILDE_ROOT" "$TMP_ROOT/doc-skills-b8b")
contains 'B8b omp config tilde leak: no_global_leak is FAIL' "$out" 'FAIL          vault.no_global_leak'
contains 'B8b omp config tilde leak: names the omp config path' "$out" "$DOC_HOME/.omp/agent/config.yml"
rm -f "$DOC_HOME/.omp/agent/config.yml"
rm -rf "$DOC_CACHE_TILDE_ROOT"

# --- B8c. no_global_leak: an OMP custom directory that is a SYMLINK ALIAS
#    resolving into the vault cache. The config file never contains the
#    vault path in any textual form, so only canonical resolution of the
#    configured path can see it; a verbatim text match reports PASS and
#    silently ships every vault entry into global discovery. -------------
OMP_ALIAS="$DOC_HOME/omp-skills-alias"
ln -sfn "$DOC_CACHE_HEALTHY" "$OMP_ALIAS"
mkdir -p "$DOC_HOME/.omp/agent"
printf 'skills:\n  customDirectories:\n    - %s\n' "$OMP_ALIAS" > "$DOC_HOME/.omp/agent/config.yml"
out=$(run_doc "$DOC_LOCK_HEALTHY" "$DOC_CACHE_HEALTHY_ROOT" "$TMP_ROOT/doc-skills-b8c")
contains 'B8c omp symlink alias: no_global_leak is FAIL' "$out" 'FAIL          vault.no_global_leak'
contains 'B8c omp symlink alias: names the omp config path' "$out" "$DOC_HOME/.omp/agent/config.yml"
rm -f "$DOC_HOME/.omp/agent/config.yml"
rm -f "$OMP_ALIAS"

# --- B8d. no_global_leak: a configured path that cannot be resolved at all
#    is UNKNOWN, never PASS - and never disturbs the rest of the report --
mkdir -p "$DOC_HOME/.omp/agent"
printf 'skills:\n  customDirectories:\n    - %s\n' "$DOC_HOME/no-such-omp-skills" > "$DOC_HOME/.omp/agent/config.yml"
out=$(run_doc "$DOC_LOCK_HEALTHY" "$DOC_CACHE_HEALTHY_ROOT" "$TMP_ROOT/doc-skills-b8d")
contains 'B8d unresolvable omp path: no_global_leak is UNKNOWN' "$out" 'UNKNOWN       vault.no_global_leak'
not_contains 'B8d unresolvable omp path: never reported as PASS' "$out" 'PASS          vault.no_global_leak'
contains 'B8d unresolvable omp path: the pin check is unaffected' "$out" 'PASS          vault.pin'
json=$(run_doc "$DOC_LOCK_HEALTHY" "$DOC_CACHE_HEALTHY_ROOT" "$TMP_ROOT/doc-skills-b8d" --json)
contains 'B8d unresolvable omp path JSON: names the unresolved path' "$json" "$DOC_HOME/no-such-omp-skills"
rm -f "$DOC_HOME/.omp/agent/config.yml"

# --- B8e. no_global_leak: the vault path in FLOW-SEQUENCE YAML, the other
#    shape OMP accepts for the same key (customDirectories: ["…"]). A
#    block-list-only extractor reports PASS and ships the whole vault into
#    global discovery. -----------------------------------------------------
mkdir -p "$DOC_HOME/.omp/agent"
printf 'skills:\n  customDirectories: ["%s"]\n' "$DOC_CACHE_HEALTHY" > "$DOC_HOME/.omp/agent/config.yml"
out=$(run_doc "$DOC_LOCK_HEALTHY" "$DOC_CACHE_HEALTHY_ROOT" "$TMP_ROOT/doc-skills-b8e")
contains 'B8e omp flow-sequence leak: no_global_leak is FAIL' "$out" 'FAIL          vault.no_global_leak'
contains 'B8e omp flow-sequence leak: names the omp config path' "$out" "$DOC_HOME/.omp/agent/config.yml"
rm -f "$DOC_HOME/.omp/agent/config.yml"

# --- B8f. no_global_leak: a SYMLINK ALIAS inside flow-sequence YAML, where
#    neither the shape nor the text gives the vault away ------------------
OMP_ALIAS="$DOC_HOME/omp-flow-alias"
ln -sfn "$DOC_CACHE_HEALTHY" "$OMP_ALIAS"
mkdir -p "$DOC_HOME/.omp/agent" "$DOC_HOME/outside-skills"
printf 'skills:\n  customDirectories: ["%s", "%s"]\n' "$DOC_HOME/outside-skills" "$OMP_ALIAS" > "$DOC_HOME/.omp/agent/config.yml"
out=$(run_doc "$DOC_LOCK_HEALTHY" "$DOC_CACHE_HEALTHY_ROOT" "$TMP_ROOT/doc-skills-b8f")
contains 'B8f omp flow-sequence alias leak: no_global_leak is FAIL' "$out" 'FAIL          vault.no_global_leak'
rm -f "$DOC_HOME/.omp/agent/config.yml"
rm -f "$OMP_ALIAS"

# --- B8g. no_global_leak: healthy external paths, in both YAML shapes, stay
#    PASS - the fix must not turn ordinary configuration into a finding ----
mkdir -p "$DOC_HOME/.omp/agent" "$DOC_HOME/outside-skills"
printf 'skills:\n  customDirectories: ["%s"]\n  includeSkills:\n    - %s\n' \
  "$DOC_HOME/outside-skills" "$DOC_HOME/outside-skills" > "$DOC_HOME/.omp/agent/config.yml"
out=$(run_doc "$DOC_LOCK_HEALTHY" "$DOC_CACHE_HEALTHY_ROOT" "$TMP_ROOT/doc-skills-b8g")
contains 'B8g healthy external path: no_global_leak is PASS' "$out" 'PASS          vault.no_global_leak'
rm -f "$DOC_HOME/.omp/agent/config.yml"

printf '\nVAULT TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
