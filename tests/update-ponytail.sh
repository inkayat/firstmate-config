#!/usr/bin/env bash
# update-ponytail.sh - acceptance for scripts/update-ponytail.sh: the one
# sanctioned, human-invoked way to move firstmate-config's pinned Ponytail
# commit forward. Fully offline (a real local Git origin reached through a
# git `url.insteadOf` rewrite, never the network) and disposable.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi; }
contains() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in '$2')" ;; esac; }
not_contains() { case $2 in *"$3"*) fail "$1 (unexpectedly found '$3' in '$2')" ;; *) pass "$1" ;; esac; }
ordered() { case $2 in *"$3"*"$4"*) pass "$1" ;; *) fail "$1 (expected '$3' before '$4' in '$2')" ;; esac; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-update-ponytail.XXXXXX") || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT

# fixture setup must fail loudly, never silently, so a broken fixture (e.g. a
# git command git itself refuses, like an invalid ref name) can never leave a
# later assertion vacuously - and misleadingly - green.
set -e

SYS_BIN="$TMP_ROOT/sysbin"
mkdir -p "$SYS_BIN"
for _tool in bash git sed awk grep wc date find stat readlink basename dirname tr head cat mkdir env sort ln rm mv mktemp cp cut python3; do
  _p=$(command -v "$_tool" 2>/dev/null) || continue
  ln -s "$_p" "$SYS_BIN/$_tool"
done

# --- fixture: a disposable copy of the repo root files the updater/install.sh need
INST_CFG="$TMP_ROOT/inst-cfg"
mkdir -p "$INST_CFG/scripts" "$INST_CFG/firstmate" "$INST_CFG/skills" "$INST_CFG/bin"
cp "$CONFIG_ROOT/scripts/update-ponytail.sh" "$INST_CFG/scripts/update-ponytail.sh"
chmod +x "$INST_CFG/scripts/update-ponytail.sh"
cp "$CONFIG_ROOT/install.sh" "$INST_CFG/install.sh"
chmod +x "$INST_CFG/install.sh"
cp "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh" "$INST_CFG/firstmate/fm-stack-manifest.sh"
cp "$CONFIG_ROOT/firstmate/fm-vault-lib.sh" "$INST_CFG/firstmate/fm-vault-lib.sh"
printf '{}\n' > "$INST_CFG/firstmate/crew-dispatch.json"
printf '# captain notes\n' > "$INST_CFG/firstmate/captain.md"
: > "$INST_CFG/bin/fm"; chmod +x "$INST_CFG/bin/fm"
cat > "$INST_CFG/firstmate/stack-manifest.tsv" <<EOF
schema_version	1
firstmate_repo	$TMP_ROOT/unused-firstmate-origin
firstmate_validated_commit	0000000000000000000000000000000000000000
pi_min_version	0.85.1
pi_tested_version	0.85.1
omp_min_version	18.1.21
omp_tested_version	18.1.21
herdr_min_version	0.8.0
herdr_tested_version	0.8.0
EOF

INST_FAKE_BIN="$TMP_ROOT/inst-fake-bin"
mkdir -p "$INST_FAKE_BIN"
: > "$INST_FAKE_BIN/omp"; chmod +x "$INST_FAKE_BIN/omp"
: > "$INST_FAKE_BIN/herdr"; chmod +x "$INST_FAKE_BIN/herdr"
printf '#!/usr/bin/env bash\necho 0.85.1\n' > "$INST_FAKE_BIN/pi"; chmod +x "$INST_FAKE_BIN/pi"

# --- a real local origin standing in for DietrichGebert/ponytail, tagged the
#     way upstream actually tags releases (vX.Y.Z, verified via
#     `git ls-remote --tags` against the real repo): A=v1.0.0, B=v1.1.0
#     (latest stable), C=v1.2.0-rc.1 (prerelease - must never be a default
#     target, only reachable deliberately via --ref).
mk_ponytail_commit() { # <dir> <extra-line>
  printf '%s\n' "$2" >> "$1/README.md"
  git -C "$1" add -A
  git -C "$1" commit -q -m "commit $2"
}

PT_ORIGIN="$TMP_ROOT/ponytail-origin"
mkdir -p "$PT_ORIGIN/skills/ponytail" "$PT_ORIGIN/skills/ponytail-review" \
         "$PT_ORIGIN/skills/ponytail-audit" "$PT_ORIGIN/pi-extension"
git -C "$PT_ORIGIN" init -q
git -C "$PT_ORIGIN" config user.email t@example.invalid
git -C "$PT_ORIGIN" config user.name t
cat > "$PT_ORIGIN/package.json" <<'EOF'
{"name":"@dietrichgebert/ponytail","pi":{"extensions":["./pi-extension/index.js"],"skills":["./skills"]}}
EOF
printf 'export default {};\n' > "$PT_ORIGIN/pi-extension/index.js"
printf -- '---\nname: ponytail\n---\nfixture A\n' > "$PT_ORIGIN/skills/ponytail/SKILL.md"
printf -- '---\nname: ponytail-review\n---\nfixture A\n' > "$PT_ORIGIN/skills/ponytail-review/SKILL.md"
printf -- '---\nname: ponytail-audit\n---\nfixture\n' > "$PT_ORIGIN/skills/ponytail-audit/SKILL.md"
printf 'A\n' > "$PT_ORIGIN/README.md"
git -C "$PT_ORIGIN" add -A
git -C "$PT_ORIGIN" commit -q -m "commit A"
PT_SHA_A=$(git -C "$PT_ORIGIN" rev-parse HEAD)
git -C "$PT_ORIGIN" tag v1.0.0

mk_ponytail_commit "$PT_ORIGIN" B
PT_SHA_B=$(git -C "$PT_ORIGIN" rev-parse HEAD)
git -C "$PT_ORIGIN" tag -a -m "release v1.1.0" v1.1.0

mk_ponytail_commit "$PT_ORIGIN" C
PT_SHA_C=$(git -C "$PT_ORIGIN" rev-parse HEAD)
git -C "$PT_ORIGIN" tag v1.2.0-rc.1

# a malformed four-part tag on a commit AFTER the latest real stable release -
# a loose "digits and dots" predicate would wrongly treat this as newer.
mk_ponytail_commit "$PT_ORIGIN" D
PT_SHA_D=$(git -C "$PT_ORIGIN" rev-parse HEAD)
git -C "$PT_ORIGIN" tag v1.3.0.1

PT_DEFAULT_BRANCH=$(git -C "$PT_ORIGIN" symbolic-ref --short HEAD 2>/dev/null || printf main)

# --- a second origin: two tags normalizing to the SAME version (v1.1.0 and
#     1.1.0) pointing at DIFFERENT commits. Real ambiguity - never guess.
PT_ORIGIN_DUP="$TMP_ROOT/ponytail-origin-dup"
mkdir -p "$PT_ORIGIN_DUP/skills/ponytail" "$PT_ORIGIN_DUP/skills/ponytail-review" "$PT_ORIGIN_DUP/pi-extension"
git -C "$PT_ORIGIN_DUP" init -q
git -C "$PT_ORIGIN_DUP" config user.email t@example.invalid
git -C "$PT_ORIGIN_DUP" config user.name t
cp "$PT_ORIGIN/package.json" "$PT_ORIGIN_DUP/package.json"
printf 'export default {};\n' > "$PT_ORIGIN_DUP/pi-extension/index.js"
printf -- '---\nname: ponytail\n---\nfixture D1\n' > "$PT_ORIGIN_DUP/skills/ponytail/SKILL.md"
printf -- '---\nname: ponytail-review\n---\nfixture D1\n' > "$PT_ORIGIN_DUP/skills/ponytail-review/SKILL.md"
printf 'D1\n' > "$PT_ORIGIN_DUP/README.md"
git -C "$PT_ORIGIN_DUP" add -A
git -C "$PT_ORIGIN_DUP" commit -q -m "commit D1"
PT_DUP_SHA1=$(git -C "$PT_ORIGIN_DUP" rev-parse HEAD)
git -C "$PT_ORIGIN_DUP" tag v1.1.0
printf 'D2\n' >> "$PT_ORIGIN_DUP/README.md"
git -C "$PT_ORIGIN_DUP" add -A
git -C "$PT_ORIGIN_DUP" commit -q -m "commit D2"
git -C "$PT_ORIGIN_DUP" tag 1.1.0

# --- a third origin with zero stable release tags: discovery must fail, not guess.
PT_ORIGIN_NOTAGS="$TMP_ROOT/ponytail-origin-notags"
mkdir -p "$PT_ORIGIN_NOTAGS/skills/ponytail" "$PT_ORIGIN_NOTAGS/skills/ponytail-review" "$PT_ORIGIN_NOTAGS/pi-extension"
git -C "$PT_ORIGIN_NOTAGS" init -q
git -C "$PT_ORIGIN_NOTAGS" config user.email t@example.invalid
git -C "$PT_ORIGIN_NOTAGS" config user.name t
cp "$PT_ORIGIN/package.json" "$PT_ORIGIN_NOTAGS/package.json"
printf 'export default {};\n' > "$PT_ORIGIN_NOTAGS/pi-extension/index.js"
printf -- '---\nname: ponytail\n---\nfixture N\n' > "$PT_ORIGIN_NOTAGS/skills/ponytail/SKILL.md"
printf -- '---\nname: ponytail-review\n---\nfixture N\n' > "$PT_ORIGIN_NOTAGS/skills/ponytail-review/SKILL.md"
printf 'N\n' > "$PT_ORIGIN_NOTAGS/README.md"
git -C "$PT_ORIGIN_NOTAGS" add -A
git -C "$PT_ORIGIN_NOTAGS" commit -q -m "commit N"
PT_NOTAGS_SHA=$(git -C "$PT_ORIGIN_NOTAGS" rev-parse HEAD)

write_lock() { # <dest> <sha>
  cat > "$1" <<EOF
ponytail:implement	DietrichGebert/ponytail	$2	skills/ponytail	ponytail
ponytail:review	DietrichGebert/ponytail	$2	skills/ponytail-review	ponytail-review
EOF
}

write_gitconfig() { # <home> <origin>
  cat > "$1/.gitconfig" <<EOF
[user]
	email = t@example.invalid
	name = t
[url "$2"]
	insteadOf = https://github.com/DietrichGebert/ponytail.git
EOF
}

# INST_CFG is a real git repo baselined at pin A, so the "never commits" test
# below can observe HEAD/refs/staged-vs-unstaged directly instead of reading
# the updater's own source text.
write_lock "$INST_CFG/skills/external.lock" "$PT_SHA_A"
git -C "$INST_CFG" init -q
git -C "$INST_CFG" config user.email t@example.invalid
git -C "$INST_CFG" config user.name t
git -C "$INST_CFG" add -A
git -C "$INST_CFG" commit -q -m baseline
INST_CFG_HEAD_BEFORE=$(git -C "$INST_CFG" rev-parse HEAD)
INST_CFG_LOG_COUNT_BEFORE=$(git -C "$INST_CFG" log --oneline | wc -l | tr -d ' ')
set +e

run_updater() { # <suffix> <origin> [args...]
  local_suffix=$1; local_origin=$2; shift 2
  home="$TMP_ROOT/home-$local_suffix"
  mkdir -p "$home"
  write_gitconfig "$home" "$local_origin"
  PATH="$SYS_BIN" HOME="$home" \
  FM_SKILL_CACHE="$TMP_ROOT/skill-cache-$local_suffix" \
  PI_CODING_AGENT_DIR="$TMP_ROOT/pi-agent-$local_suffix" \
  bash -c 'cd "$1" && "$1/scripts/update-ponytail.sh" "${@:2}"' _ "$INST_CFG" "$@" 2>&1
}

# =============================================================================
# 1. --check: already at the latest stable release (v1.1.0 / B)
# =============================================================================
write_lock "$INST_CFG/skills/external.lock" "$PT_SHA_B"
out=$(run_updater uptodate "$PT_ORIGIN" --check); code=$?
check '1 up-to-date --check: exit code is 0' 0 "$code"
contains '1 up-to-date --check: reports CURRENT_PIN' "$out" "CURRENT_PIN: $PT_SHA_B"
contains '1 up-to-date --check: reports CURRENT_VERSION' "$out" 'CURRENT_VERSION: v1.1.0'
contains '1 up-to-date --check: reports LATEST_STABLE_VERSION' "$out" 'LATEST_STABLE_VERSION: v1.1.0'
contains '1 up-to-date --check: reports LATEST_STABLE_PIN equal to current' "$out" "LATEST_STABLE_PIN: $PT_SHA_B"
contains '1 up-to-date --check: UPDATE_AVAILABLE is false' "$out" 'UPDATE_AVAILABLE: false'
ordered '1 up-to-date --check: field order is CURRENT_VERSION then CURRENT_PIN' "$out" 'CURRENT_VERSION:' 'CURRENT_PIN:'
not_contains '1 up-to-date --check: the malformed four-part v1.3.0.1 tag is never a target' "$out" "$PT_SHA_D"
check '1 up-to-date --check: never mutates the lock file' "$PT_SHA_B" "$(awk -F'\t' '$1=="ponytail:implement"{print $3}' "$INST_CFG/skills/external.lock")"

# =============================================================================
# 2. --check: a newer stable release is available; the v1.2.0-rc.1
#    prerelease on a newer commit must be ignored (prerelease exclusion)
# =============================================================================
write_lock "$INST_CFG/skills/external.lock" "$PT_SHA_A"
out=$(run_updater ahead-check "$PT_ORIGIN" --check); code=$?
check '2 newer-stable --check: exit code is 0' 0 "$code"
contains '2 newer-stable --check: reports CURRENT_PIN' "$out" "CURRENT_PIN: $PT_SHA_A"
contains '2 newer-stable --check: reports CURRENT_VERSION' "$out" 'CURRENT_VERSION: v1.0.0'
contains '2 newer-stable --check: reports LATEST_STABLE_VERSION v1.1.0, not the v1.2.0-rc.1 prerelease' "$out" 'LATEST_STABLE_VERSION: v1.1.0'
contains '2 newer-stable --check: reports LATEST_STABLE_PIN as B, not C' "$out" "LATEST_STABLE_PIN: $PT_SHA_B"
not_contains '2 newer-stable --check: never targets the prerelease commit' "$out" "$PT_SHA_C"
not_contains '2 newer-stable --check: the malformed four-part v1.3.0.1 tag is never a target' "$out" "$PT_SHA_D"
contains '2 newer-stable --check: UPDATE_AVAILABLE is true' "$out" 'UPDATE_AVAILABLE: true'
check '2 newer-stable --check: never mutates the lock file' "$PT_SHA_A" "$(awk -F'\t' '$1=="ponytail:implement"{print $3}' "$INST_CFG/skills/external.lock")"

# =============================================================================
# 3. Full run: pin advances to the latest stable release, all four consumers
#    (lock:implement, lock:review, shared skill cache, Pi package checkout)
#    converge on the same commit, and a following install.sh --verify shows
#    no drift (also re-proves the existing Pi filtering/defaultMode regression)
# =============================================================================
write_lock "$INST_CFG/skills/external.lock" "$PT_SHA_A"

# Converge fully at the OLD pin first (settings.json filter + ponytail
# config), exactly as a real machine would already have done, so the
# update's effect on those unrelated files (or lack of it) is observable.
PATH="$INST_FAKE_BIN:$SYS_BIN" HOME="$TMP_ROOT/home-full" \
  FIRSTMATE_ROOT="$TMP_ROOT/inst-dest-full" FM_HOME="$TMP_ROOT/inst-fm-home-full" \
  FM_CONFIG_ENV="$TMP_ROOT/inst-env-full" FM_SKILLS_ROOT="$TMP_ROOT/inst-skills-full" \
  FM_SKILL_CACHE="$TMP_ROOT/skill-cache-full" FM_BIN_DIR="$TMP_ROOT/inst-bin-dir-full" \
  PI_CODING_AGENT_DIR="$TMP_ROOT/pi-agent-full" XDG_CONFIG_HOME="$TMP_ROOT/xdg-full" \
  bash -c 'mkdir -p "$1"; printf "fixture\n" > "$1/AGENTS.md"; "$2/install.sh" >/dev/null 2>&1' \
  _ "$TMP_ROOT/inst-dest-full" "$INST_CFG"
SETTINGS_BEFORE=$(cat "$TMP_ROOT/pi-agent-full/settings.json" 2>/dev/null)
CONFIG_BEFORE=$(cat "$TMP_ROOT/xdg-full/ponytail/config.json" 2>/dev/null)
out=$(run_updater full "$PT_ORIGIN"); code=$?
check '3 full run: exit code is 0' 0 "$code"
contains '3 full run: reports CURRENT_PIN' "$out" "CURRENT_PIN: $PT_SHA_A"
contains '3 full run: reports CURRENT_VERSION' "$out" 'CURRENT_VERSION: v1.0.0'
contains '3 full run: reports TARGET_VERSION' "$out" 'TARGET_VERSION: v1.1.0'
contains '3 full run: reports TARGET_PIN (exact tag-to-SHA resolution)' "$out" "TARGET_PIN: $PT_SHA_B"
check '3 full run: updates skills/external.lock ponytail:implement' "$PT_SHA_B" "$(awk -F'\t' '$1=="ponytail:implement"{print $3}' "$INST_CFG/skills/external.lock")"
check '3 full run: updates skills/external.lock ponytail:review' "$PT_SHA_B" "$(awk -F'\t' '$1=="ponytail:review"{print $3}' "$INST_CFG/skills/external.lock")"

SKILL_CACHE_DIR="$TMP_ROOT/skill-cache-full/DietrichGebert-ponytail"
PI_PKG_DIR="$TMP_ROOT/pi-agent-full/git/github.com/DietrichGebert/ponytail"
check '3 full run: refreshes the shared skill cache to the target commit' "$PT_SHA_B" "$(git -C "$SKILL_CACHE_DIR" rev-parse HEAD 2>/dev/null || printf '')"
check '3 full run: refreshes the Pi package checkout to the same commit' "$PT_SHA_B" "$(git -C "$PI_PKG_DIR" rev-parse HEAD 2>/dev/null || printf '')"

# Rerunning install.sh (with the same disposable roots the updater just used)
# must now converge with zero relevant drift: the lock's pin, the shared
# cache, and the Pi package checkout all already agree.
verify_out=$(PATH="$INST_FAKE_BIN:$SYS_BIN" HOME="$TMP_ROOT/home-full" \
  FIRSTMATE_ROOT="$TMP_ROOT/inst-dest-full" FM_HOME="$TMP_ROOT/inst-fm-home-full" \
  FM_CONFIG_ENV="$TMP_ROOT/inst-env-full" FM_SKILLS_ROOT="$TMP_ROOT/inst-skills-full" \
  FM_SKILL_CACHE="$TMP_ROOT/skill-cache-full" FM_BIN_DIR="$TMP_ROOT/inst-bin-dir-full" \
  PI_CODING_AGENT_DIR="$TMP_ROOT/pi-agent-full" XDG_CONFIG_HOME="$TMP_ROOT/xdg-full" \
  bash -c 'mkdir -p "$1"; printf "fixture\n" > "$1/AGENTS.md"; "$2/install.sh" --verify' \
  _ "$TMP_ROOT/inst-dest-full" "$INST_CFG" 2>&1)
contains '3 full run: a following install.sh --verify reports 0 drift, 0 failures' "$verify_out" '0 drift item(s), 0 failure(s)'
check '3 full run: preserves settings.json (skills filter untouched)' "$SETTINGS_BEFORE" "$(cat "$TMP_ROOT/pi-agent-full/settings.json" 2>/dev/null)"
check '3 full run: preserves ponytail config.json (defaultMode untouched)' "$CONFIG_BEFORE" "$(cat "$TMP_ROOT/xdg-full/ponytail/config.json" 2>/dev/null)"
contains '3 full run: preserved config.json still has defaultMode off' "$CONFIG_BEFORE" '"defaultMode": "off"'

# --- observable "never commits" proof: HEAD/refs unchanged, diff unstaged
INST_CFG_HEAD_AFTER=$(git -C "$INST_CFG" rev-parse HEAD)
INST_CFG_LOG_COUNT_AFTER=$(git -C "$INST_CFG" log --oneline | wc -l | tr -d ' ')
check '3 full run: HEAD is unchanged (no commit was made)' "$INST_CFG_HEAD_BEFORE" "$INST_CFG_HEAD_AFTER"
check '3 full run: commit count is unchanged' "$INST_CFG_LOG_COUNT_BEFORE" "$INST_CFG_LOG_COUNT_AFTER"
status_out=$(git -C "$INST_CFG" status --porcelain -- skills/external.lock)
check '3 full run: the lock change is an unstaged working-tree modification' ' M skills/external.lock' "$status_out"
diff_out=$(git -C "$INST_CFG" diff -- skills/external.lock)
contains '3 full run: a reviewable git diff shows the old pin removed' "$diff_out" "-ponytail:implement	DietrichGebert/ponytail	$PT_SHA_A"
contains '3 full run: a reviewable git diff shows the new pin added' "$diff_out" "+ponytail:implement	DietrichGebert/ponytail	$PT_SHA_B"
staged_out=$(git -C "$INST_CFG" diff --cached --stat)
check '3 full run: nothing is staged for commit' '' "$staged_out"

# =============================================================================
# 3b. Unknown/extra arguments: rejected, never treated as a mutating update
# =============================================================================
write_lock "$INST_CFG/skills/external.lock" "$PT_SHA_A"
lock_before_bad_args=$(cat "$INST_CFG/skills/external.lock")
out_bad1=$(run_updater badarg1 "$PT_ORIGIN" --bogus); code_bad1=$?
if [ "$code_bad1" -eq 0 ]; then fail '3b unknown flag: expected nonzero exit, got 0'; else pass '3b unknown flag: exit code is nonzero'; fi
contains '3b unknown flag: names the bad argument' "$out_bad1" 'unknown argument: --bogus'
check '3b unknown flag: never mutates the lock file' "$lock_before_bad_args" "$(cat "$INST_CFG/skills/external.lock")"

out_bad2=$(run_updater badarg2 "$PT_ORIGIN" --ref); code_bad2=$?
if [ "$code_bad2" -eq 0 ]; then fail '3b --ref missing value: expected nonzero exit, got 0'; else pass '3b --ref missing value: exit code is nonzero'; fi
contains '3b --ref missing value: names the problem' "$out_bad2" '--ref requires a value'
check '3b --ref missing value: never mutates the lock file' "$lock_before_bad_args" "$(cat "$INST_CFG/skills/external.lock")"

out_bad3=$(run_updater badarg3 "$PT_ORIGIN" --check --ref v1.1.0); code_bad3=$?
if [ "$code_bad3" -eq 0 ]; then fail '3b --check with --ref: expected nonzero exit, got 0'; else pass '3b --check with --ref: exit code is nonzero'; fi
contains '3b --check with --ref: names the conflict' "$out_bad3" '--check and --ref cannot be combined'
check '3b --check with --ref: never mutates the lock file' "$lock_before_bad_args" "$(cat "$INST_CFG/skills/external.lock")"

# =============================================================================
# 4. --ref <tag>: deliberate testing against a non-stable (prerelease) tag,
#    resolved exactly, clearly labeled as not a stable release
# =============================================================================
write_lock "$INST_CFG/skills/external.lock" "$PT_SHA_A"
out=$(run_updater ref-prerelease "$PT_ORIGIN" --ref v1.2.0-rc.1); code=$?
check '4 --ref prerelease tag: exit code is 0' 0 "$code"
contains '4 --ref prerelease tag: resolves the exact tag to its exact SHA' "$out" "TARGET_PIN: $PT_SHA_C"
contains '4 --ref prerelease tag: labels the target as not a stable release' "$out" 'not a stable release'
check '4 --ref prerelease tag: updates the lock to the resolved commit' "$PT_SHA_C" "$(awk -F'\t' '$1=="ponytail:implement"{print $3}' "$INST_CFG/skills/external.lock")"

# =============================================================================
# 5. --ref <full-sha>: deliberate testing against an exact commit SHA
# =============================================================================
write_lock "$INST_CFG/skills/external.lock" "$PT_SHA_A"
out=$(run_updater ref-sha "$PT_ORIGIN" --ref "$PT_SHA_B"); code=$?
check '5 --ref full SHA: exit code is 0' 0 "$code"
contains '5 --ref full SHA: resolves to the requested commit' "$out" "TARGET_PIN: $PT_SHA_B"
contains '5 --ref full SHA: recognizes it as the tagged v1.1.0 release' "$out" 'TARGET_VERSION: v1.1.0'
check '5 --ref full SHA: updates the lock to the resolved commit' "$PT_SHA_B" "$(awk -F'\t' '$1=="ponytail:implement"{print $3}' "$INST_CFG/skills/external.lock")"

# =============================================================================
# 6. --ref <branch-name>: rejected. --ref accepts only an exact tag or a full
#    commit SHA, never a branch, so it cannot recreate automatic branch
#    tracking through the back door.
# =============================================================================
write_lock "$INST_CFG/skills/external.lock" "$PT_SHA_A"
lock_before_branch=$(cat "$INST_CFG/skills/external.lock")
out=$(run_updater ref-branch "$PT_ORIGIN" --ref "$PT_DEFAULT_BRANCH"); code=$?
if [ "$code" -eq 0 ]; then fail '6 --ref branch name: expected nonzero exit, got 0'; else pass '6 --ref branch name: exit code is nonzero'; fi
contains '6 --ref branch name: refuses branch names' "$out" 'branch'
check '6 --ref branch name: never mutates the lock file' "$lock_before_branch" "$(cat "$INST_CFG/skills/external.lock")"

# =============================================================================
# 7. Ambiguous release discovery: two tags normalize to the same highest
#    version (v1.1.0 and 1.1.0) but resolve to DIFFERENT commits. Refuse to
#    guess in both --check and default (mutating) mode; never write.
# =============================================================================
write_lock "$INST_CFG/skills/external.lock" "$PT_DUP_SHA1"
lock_before_dup=$(cat "$INST_CFG/skills/external.lock")

out_dup_check=$(run_updater dup-check "$PT_ORIGIN_DUP" --check); code_dup_check=$?
if [ "$code_dup_check" -eq 0 ]; then fail '7 duplicate-version --check: expected nonzero exit, got 0'; else pass '7 duplicate-version --check: exit code is nonzero'; fi
contains '7 duplicate-version --check: UPDATE_AVAILABLE is ambiguous' "$out_dup_check" 'UPDATE_AVAILABLE: ambiguous'
check '7 duplicate-version --check: never mutates the lock file' "$lock_before_dup" "$(cat "$INST_CFG/skills/external.lock")"

out_dup_default=$(run_updater dup-default "$PT_ORIGIN_DUP"); code_dup_default=$?
if [ "$code_dup_default" -eq 0 ]; then fail '7 duplicate-version default: expected nonzero exit, got 0'; else pass '7 duplicate-version default: exit code is nonzero'; fi
contains '7 duplicate-version default: reports refusal to guess' "$out_dup_default" 'refus'
check '7 duplicate-version default: never mutates the lock file' "$lock_before_dup" "$(cat "$INST_CFG/skills/external.lock")"

# =============================================================================
# 8. No stable release tags at all: discovery must fail, never guess a
#    prerelease or default-branch HEAD as a substitute target.
# =============================================================================
write_lock "$INST_CFG/skills/external.lock" "$PT_NOTAGS_SHA"
lock_before_notags=$(cat "$INST_CFG/skills/external.lock")

out_notags_check=$(run_updater notags-check "$PT_ORIGIN_NOTAGS" --check); code_notags_check=$?
if [ "$code_notags_check" -eq 0 ]; then fail '8 no-stable-tags --check: expected nonzero exit, got 0'; else pass '8 no-stable-tags --check: exit code is nonzero'; fi
contains '8 no-stable-tags --check: UPDATE_AVAILABLE is ambiguous' "$out_notags_check" 'UPDATE_AVAILABLE: ambiguous'
contains '8 no-stable-tags --check: reports CURRENT_VERSION honestly as unknown' "$out_notags_check" 'CURRENT_VERSION: unknown'
check '8 no-stable-tags --check: never mutates the lock file' "$lock_before_notags" "$(cat "$INST_CFG/skills/external.lock")"

out_notags_default=$(run_updater notags-default "$PT_ORIGIN_NOTAGS"); code_notags_default=$?
if [ "$code_notags_default" -eq 0 ]; then fail '8 no-stable-tags default: expected nonzero exit, got 0'; else pass '8 no-stable-tags default: exit code is nonzero'; fi
contains '8 no-stable-tags default: names the absence of stable tags' "$out_notags_default" 'no stable release tag'
check '8 no-stable-tags default: never mutates the lock file' "$lock_before_notags" "$(cat "$INST_CFG/skills/external.lock")"

# =============================================================================
# 9. A prerelease-only/untagged current pin (v1.2.0-rc.1, commit C) is
#    reported honestly as CURRENT_VERSION: unknown even though the repo DOES
#    have stable releases - and the malformed four-part v1.3.0.1 tag (on a
#    later commit D) never becomes the discovered target.
# =============================================================================
write_lock "$INST_CFG/skills/external.lock" "$PT_SHA_C"
out=$(run_updater prerelease-current "$PT_ORIGIN" --check); code=$?
check '9 prerelease-only current pin: exit code is 0' 0 "$code"
contains '9 prerelease-only current pin: reports CURRENT_VERSION honestly as unknown' "$out" 'CURRENT_VERSION: unknown'
contains '9 prerelease-only current pin: still discovers the real latest stable release' "$out" 'LATEST_STABLE_VERSION: v1.1.0'
contains '9 prerelease-only current pin: LATEST_STABLE_PIN is B, not the malformed tag D' "$out" "LATEST_STABLE_PIN: $PT_SHA_B"
not_contains '9 prerelease-only current pin: the malformed four-part v1.3.0.1 tag is never a target' "$out" "$PT_SHA_D"
contains '9 prerelease-only current pin: UPDATE_AVAILABLE is true' "$out" 'UPDATE_AVAILABLE: true'

# =============================================================================
# 10. --ref exactness: no glob/prefix matching, and a full SHA is normalized
#     through rev-parse so an uppercase hex string cannot end up stored and
#     then mismatch git's own lowercase HEAD output downstream.
# =============================================================================
write_lock "$INST_CFG/skills/external.lock" "$PT_SHA_A"
lock_before_ref_exact=$(cat "$INST_CFG/skills/external.lock")

out_wild=$(run_updater ref-wildcard "$PT_ORIGIN" --ref 'v1.1.*'); code_wild=$?
if [ "$code_wild" -eq 0 ]; then fail '10 --ref wildcard: expected nonzero exit, got 0'; else pass '10 --ref wildcard: exit code is nonzero'; fi
contains '10 --ref wildcard: names the glob pattern as the problem' "$out_wild" 'glob pattern'
check '10 --ref wildcard: never mutates the lock file' "$lock_before_ref_exact" "$(cat "$INST_CFG/skills/external.lock")"

out_prefix=$(run_updater ref-prefix "$PT_ORIGIN" --ref v1.1); code_prefix=$?
if [ "$code_prefix" -eq 0 ]; then fail '10 --ref prefix (not exact): expected nonzero exit, got 0'; else pass '10 --ref prefix (not exact): exit code is nonzero'; fi
contains '10 --ref prefix (not exact): reports it is not an exact tag or SHA' "$out_prefix" 'not an exact tag'
check '10 --ref prefix (not exact): never mutates the lock file' "$lock_before_ref_exact" "$(cat "$INST_CFG/skills/external.lock")"

PT_SHA_B_UPPER=$(printf '%s' "$PT_SHA_B" | tr 'a-f' 'A-F')
out_upper=$(run_updater ref-upper-sha "$PT_ORIGIN" --ref "$PT_SHA_B_UPPER"); code_upper=$?
check '10 --ref uppercase SHA: exit code is 0' 0 "$code_upper"
contains '10 --ref uppercase SHA: normalizes TARGET_PIN to lowercase' "$out_upper" "TARGET_PIN: $PT_SHA_B"
not_contains '10 --ref uppercase SHA: never reports the uppercase form' "$out_upper" "TARGET_PIN: $PT_SHA_B_UPPER"
check '10 --ref uppercase SHA: lock stores the canonical lowercase SHA' "$PT_SHA_B" "$(awk -F'\t' '$1=="ponytail:implement"{print $3}' "$INST_CFG/skills/external.lock")"

printf '\nUPDATE PONYTAIL TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
