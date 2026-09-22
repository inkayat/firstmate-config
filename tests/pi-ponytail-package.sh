#!/usr/bin/env bash
# pi-ponytail-package.sh - acceptance for install.sh step 9 (Pi Ponytail
# package): the reproducible fix for the real operator symptom of a Pi
# package export duplicating the two skills step 7 already installs as
# authoritative (ponytail, ponytail-review), plus ponytail's own
# defaultMode=off reconciliation.
#
# Fully offline and disposable: no real DietrichGebert/ponytail network
# clone. A real local Git repository stands in for it, reached through a
# git `url.<local>.insteadOf=https://github.com/...` rewrite in the
# fixture's own isolated $HOME/.gitconfig - install.sh's clone commands run
# unmodified, exactly as they do in production, just redirected.
#
# A fully hermetic system PATH: symlink only the exact utilities install.sh
# needs, never a whole real bin directory (mirrors tests/doctor.sh's own
# established pattern). SYS_BIN_NOPY carries no python3 at all: scenario 4
# below proves the managed Pi/ponytail JSON reconciliation fails loudly
# rather than silently skipping when no parser is available.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi; }
contains() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in '$2')" ;; esac; }
not_contains() { case $2 in *"$3"*) fail "$1 (unexpectedly found '$3' in '$2')" ;; *) pass "$1" ;; esac; }
link_target_real() {
  local target
  target=$(readlink "$1") || return 1
  printf '%s/%s\n' "$(cd "$(dirname "$target")" && pwd -P)" "$(basename "$target")"
}

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-pi-ponytail.XXXXXX") || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT

SYS_BIN="$TMP_ROOT/sysbin"
mkdir -p "$SYS_BIN"
for _tool in bash git sed awk grep wc date find stat readlink basename dirname tr head cat mkdir env sort ln rm mktemp cp python3; do
  _p=$(command -v "$_tool" 2>/dev/null) || continue
  ln -s "$_p" "$SYS_BIN/$_tool"
done
SYS_BIN_NOPY="$TMP_ROOT/sysbin-nopy"
mkdir -p "$SYS_BIN_NOPY"
for _tool in bash git sed awk grep wc date find stat readlink basename dirname tr head cat mkdir env sort ln rm mktemp cp; do
  _p=$(command -v "$_tool" 2>/dev/null) || continue
  ln -s "$_p" "$SYS_BIN_NOPY/$_tool"
done

# --- fixture: a disposable copy of install.sh under its own CONFIG_ROOT ----
INST_CFG="$TMP_ROOT/inst-cfg"
mkdir -p "$INST_CFG/bin" "$INST_CFG/firstmate" "$INST_CFG/skills"
cp "$CONFIG_ROOT/install.sh" "$INST_CFG/install.sh"
chmod +x "$INST_CFG/install.sh"
cp "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh" "$INST_CFG/firstmate/fm-stack-manifest.sh"
cp "$CONFIG_ROOT/firstmate/fm-vault-lib.sh" "$INST_CFG/firstmate/fm-vault-lib.sh"
printf '{}\n' > "$INST_CFG/firstmate/crew-dispatch.json"
printf '# captain notes\n' > "$INST_CFG/firstmate/captain.md"
: > "$INST_CFG/bin/fm"; chmod +x "$INST_CFG/bin/fm"
cp "$CONFIG_ROOT/bin/ponytail-update" "$INST_CFG/bin/ponytail-update"
chmod +x "$INST_CFG/bin/ponytail-update"
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

# --- a real local origin standing in for DietrichGebert/ponytail -----------
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
printf -- '---\nname: ponytail\n---\nfixture\n' > "$PT_ORIGIN/skills/ponytail/SKILL.md"
printf -- '---\nname: ponytail-review\n---\nfixture\n' > "$PT_ORIGIN/skills/ponytail-review/SKILL.md"
printf -- '---\nname: ponytail-audit\n---\nfixture\n' > "$PT_ORIGIN/skills/ponytail-audit/SKILL.md"
git -C "$PT_ORIGIN" add -A
git -C "$PT_ORIGIN" commit -q -m c1
PT_SHA=$(git -C "$PT_ORIGIN" rev-parse HEAD)

cat > "$INST_CFG/skills/external.lock" <<EOF
ponytail:implement	DietrichGebert/ponytail	$PT_SHA	skills/ponytail	ponytail
ponytail:review	DietrichGebert/ponytail	$PT_SHA	skills/ponytail-review	ponytail-review
EOF

write_gitconfig() { # <home>
  cat > "$1/.gitconfig" <<EOF
[user]
	email = t@example.invalid
	name = t
[url "$PT_ORIGIN"]
	insteadOf = https://github.com/DietrichGebert/ponytail.git
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
  FM_BIN_DIR="$TMP_ROOT/inst-bin-dir-$suffix" \
  PI_CODING_AGENT_DIR="$TMP_ROOT/inst-pi-agent-$suffix" \
  XDG_CONFIG_HOME="$TMP_ROOT/inst-xdg-$suffix" \
  "$INST_CFG/install.sh" "$@" 2>&1
}

mkdir -p "$TMP_ROOT/inst-bin-dir-fresh"
printf 'leave me alone\n' > "$TMP_ROOT/inst-bin-dir-fresh/unrelated"
INST_CFG_REAL=$(cd "$INST_CFG" && pwd -P)

# =============================================================================
# 1. Fresh run converges: separate pinned clone, settings filter, config off
# =============================================================================
out=$(run_fake_install fresh); code=$?
check '1 fresh run: exit code is 0' 0 "$code"
contains '1 fresh run: reports the Pi Ponytail package step ran' "$out" '9. Pi Ponytail package'
check '1 launcher: ponytail-update is linked to the tracked helper' \
  "$INST_CFG_REAL/bin/ponytail-update" "$(link_target_real "$TMP_ROOT/inst-bin-dir-fresh/ponytail-update" 2>/dev/null || printf '')"
check '1 launcher: unrelated bin file is preserved' 'leave me alone' \
  "$(cat "$TMP_ROOT/inst-bin-dir-fresh/unrelated" 2>/dev/null)"

PI_PKG_DIR="$TMP_ROOT/inst-pi-agent-fresh/git/github.com/DietrichGebert/ponytail"
SKILL_CACHE_DIR="$TMP_ROOT/inst-skill-cache-fresh/DietrichGebert-ponytail"
PI_SETTINGS="$TMP_ROOT/inst-pi-agent-fresh/settings.json"
PT_CONFIG="$TMP_ROOT/inst-xdg-fresh/ponytail/config.json"

check '1 pi package: cloned at the pinned commit' "$PT_SHA" "$(git -C "$PI_PKG_DIR" rev-parse HEAD 2>/dev/null || printf '')"

if [ -L "$PI_PKG_DIR" ]; then
  fail '1 pi package checkout: is a real directory, not a symlink into the shared skill cache'
elif [ -d "$PI_PKG_DIR" ] && [ -d "$SKILL_CACHE_DIR" ]; then
  inode_a=$(stat -f '%i' "$PI_PKG_DIR" 2>/dev/null || stat -c '%i' "$PI_PKG_DIR" 2>/dev/null)
  inode_b=$(stat -f '%i' "$SKILL_CACHE_DIR" 2>/dev/null || stat -c '%i' "$SKILL_CACHE_DIR" 2>/dev/null)
  if [ "$inode_a" = "$inode_b" ]; then
    fail '1 pi package checkout: physically distinct from the shared skill cache clone'
  else
    pass '1 pi package checkout: physically distinct from the shared skill cache clone'
  fi
else
  fail '1 pi package checkout: both the package clone and the shared skill cache clone must exist'
fi

contains '1 pi settings: package entry has the skills filter' \
  "$(cat "$PI_SETTINGS" 2>/dev/null)" '"-skills/ponytail/SKILL.md"'
contains '1 pi settings: filter also covers ponytail-review' \
  "$(cat "$PI_SETTINGS" 2>/dev/null)" '"-skills/ponytail-review/SKILL.md"'
not_contains '1 pi settings: audit/debt/gain/help are never filtered out' \
  "$(cat "$PI_SETTINGS" 2>/dev/null)" 'ponytail-audit'
contains '1 ponytail config: defaultMode is off' "$(cat "$PT_CONFIG" 2>/dev/null)" '"defaultMode": "off"'

# =============================================================================
# 2. Second run: zero relevant changes (idempotent)
# =============================================================================
out2=$(run_fake_install fresh); code2=$?
check '2 second run: exit code is 0' 0 "$code2"
not_contains '2 second run: no DRIFT lines' "$out2" 'DRIFT'
not_contains '2 second run: pi package clone reports no change' "$out2" 'pi package git:github.com/DietrichGebert/ponytail pinned to'
not_contains '2 second run: pi settings reports no change' "$out2" 'skills filter in'
not_contains '2 second run: ponytail config reports no change' "$out2" 'set defaultMode=off'
contains '2 second run: install reports 0 change(s)' "$out2" 'install: 0 change(s), 0 failure(s)'

# A missing or wrong managed launcher is reported without replacing unrelated
# files or mutating anything in --verify mode.
rm "$TMP_ROOT/inst-bin-dir-fresh/ponytail-update"
launcher_verify=$(run_fake_install fresh --verify)
contains '2 missing launcher: verify reports drift' "$launcher_verify" 'ponytail-update'
check '2 missing launcher: verify stays read-only' '' \
  "$(readlink "$TMP_ROOT/inst-bin-dir-fresh/ponytail-update" 2>/dev/null || printf '')"
run_fake_install fresh >/dev/null
ln -sfn "$TMP_ROOT/wrong-ponytail-update" "$TMP_ROOT/inst-bin-dir-fresh/ponytail-update"
launcher_verify=$(run_fake_install fresh --verify)
contains '2 wrong launcher: verify reports drift' "$launcher_verify" 'ponytail-update'
check '2 wrong launcher: verify does not repoint it' "$TMP_ROOT/wrong-ponytail-update" \
  "$(readlink "$TMP_ROOT/inst-bin-dir-fresh/ponytail-update")"
run_fake_install fresh >/dev/null
check '2 launcher repair: real install restores the tracked helper' \
  "$INST_CFG_REAL/bin/ponytail-update" "$(link_target_real "$TMP_ROOT/inst-bin-dir-fresh/ponytail-update")"
check '2 launcher repair: unrelated bin file remains untouched' 'leave me alone' \
  "$(cat "$TMP_ROOT/inst-bin-dir-fresh/unrelated")"

# =============================================================================
# 3. Managed drift: --verify detects it; a real run corrects it
# =============================================================================
python3 - "$PI_SETTINGS" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["packages"] = ["git:github.com/DietrichGebert/ponytail"]
with open(path, "w") as f:
    json.dump(data, f)
PY
python3 - "$PT_CONFIG" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["defaultMode"] = "full"
with open(path, "w") as f:
    json.dump(data, f)
PY

verify_out=$(run_fake_install fresh --verify); verify_code=$?
check '3 verify: exit code is 0 (drift is reported, never a process failure)' 0 "$verify_code"
contains '3 verify: reports the pi settings drift' "$verify_out" 'DRIFT'
contains '3 verify: names the skills filter drift' "$verify_out" 'skills filter'
contains '3 verify: names the ponytail config drift' "$verify_out" 'defaultMode'
not_contains '3 verify: summary is never falsely 0 drift item(s)' "$verify_out" '0 drift item(s), 0 failure(s)'
not_contains '3 verify: never writes during --verify' "$(cat "$PI_SETTINGS")" '"skills"'

fix_out=$(run_fake_install fresh); fix_code=$?
check '3 real run after drift: exit code is 0' 0 "$fix_code"
contains '3 real run after drift: reports the skills filter change' "$fix_out" 'skills filter in'
contains '3 real run after drift: reports the defaultMode change' "$fix_out" 'set defaultMode=off'
contains '3 real run after drift: fixes the pi settings filter' "$(cat "$PI_SETTINGS")" '"-skills/ponytail/SKILL.md"'
contains '3 real run after drift: fixes ponytail defaultMode' "$(cat "$PT_CONFIG")" '"defaultMode": "off"'

verify_out2=$(run_fake_install fresh --verify); verify_code2=$?
check '3 verify after fix: exit code is 0' 0 "$verify_code2"
contains '3 verify after fix: reports 0 drift item(s)' "$verify_out2" '0 drift item(s), 0 failure(s)'

# =============================================================================
# 4. Missing python3: a mandatory managed step fails loudly, never skips
# =============================================================================
home_nopy="$TMP_ROOT/inst-home-nopy"
mkdir -p "$home_nopy" "$TMP_ROOT/inst-dest-nopy"
write_gitconfig "$home_nopy"
printf 'fixture\n' > "$TMP_ROOT/inst-dest-nopy/AGENTS.md"
out_nopy=$(PATH="$INST_FAKE_BIN:$SYS_BIN_NOPY" HOME="$home_nopy" FIRSTMATE_ROOT="$TMP_ROOT/inst-dest-nopy" \
  FM_HOME="$TMP_ROOT/inst-fm-home-nopy" FM_CONFIG_ENV="$TMP_ROOT/inst-env-nopy" \
  FM_SKILLS_ROOT="$TMP_ROOT/inst-skills-nopy" FM_SKILL_CACHE="$TMP_ROOT/inst-skill-cache-nopy" \
  FM_BIN_DIR="$TMP_ROOT/inst-bin-dir-nopy" \
  PI_CODING_AGENT_DIR="$TMP_ROOT/inst-pi-agent-nopy" XDG_CONFIG_HOME="$TMP_ROOT/inst-xdg-nopy" \
  "$INST_CFG/install.sh" 2>&1); code_nopy=$?
if [ "$code_nopy" -eq 0 ]; then fail '4 no python3: expected nonzero exit, got 0'; else pass '4 no python3: exit code is nonzero (never a silent skip)'; fi
contains '4 no python3: names python3 as the actionable requirement' "$out_nopy" 'python3 is required'

printf '\nPI PONYTAIL PACKAGE TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
