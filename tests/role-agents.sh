#!/usr/bin/env bash
# role-agents.sh - install.sh links every roles/<name>/ROLE.md into OMP's
# user agent root as fm-<name>.md, idempotently, never replaces an entry that
# is not ours, and links nothing into OMP's user extension root.
#
# Runs only a disposable copy of install.sh with this checkout's real role
# files, a fixture HOME (every default root resolves under it), FM_HOME, env
# file and agent root under that HOME, fake pi/omp/herdr on PATH, and no
# external.lock, so nothing is cloned or fetched and no live root is touched.
# The operator's live agent and extension roots are compared before and after.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIVE_AGENTS="$HOME/.omp/agent/agents"
LIVE_EXTENSIONS="$HOME/.omp/agent/extensions"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$3', got '$2')"; fi; }
contains() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in '$2')" ;; esac; }

live_snapshot() {
  local d
  for d in "$LIVE_AGENTS" "$LIVE_EXTENSIONS"; do
    if [ -e "$d" ] || [ -L "$d" ]; then ls -laT "$d" 2>/dev/null || ls -la --full-time "$d"
    else printf '%s absent\n' "$d"; fi
  done
}
LIVE_BEFORE=$(live_snapshot)

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-role-agents.XXXXXX") || exit 1
TMP_ROOT=$(cd "$TMP_ROOT" && pwd)
trap 'rm -rf "$TMP_ROOT"' EXIT

CFG="$TMP_ROOT/cfg"
mkdir -p "$CFG/bin" "$CFG/firstmate" "$CFG/skills" "$TMP_ROOT/fake-bin" "$TMP_ROOT/firstmate"
cp "$CONFIG_ROOT/install.sh" "$CFG/install.sh"
cp "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh" "$CONFIG_ROOT/firstmate/stack-manifest.tsv" \
   "$CONFIG_ROOT/firstmate/crew-dispatch.json" "$CONFIG_ROOT/firstmate/captain.md" "$CFG/firstmate/"
cp -R "$CONFIG_ROOT/roles" "$CFG/roles"
: > "$CFG/bin/fm"; : > "$CFG/bin/ponytail-update"; chmod +x "$CFG/bin/fm" "$CFG/bin/ponytail-update"
for t in pi omp herdr; do : > "$TMP_ROOT/fake-bin/$t"; chmod +x "$TMP_ROOT/fake-bin/$t"; done
printf 'AGENTS\n' > "$TMP_ROOT/firstmate/AGENTS.md"
ROLES=$(cd "$CFG/roles" && for d in */; do [ -f "$d/ROLE.md" ] && printf '%s\n' "${d%/}"; done)

install_fixture() {  # <home> [install.sh args...]
  local ihome=$1
  shift
  PATH="$TMP_ROOT/fake-bin:/usr/bin:/bin" HOME="$ihome" FIRSTMATE_ROOT="$TMP_ROOT/firstmate" \
    FM_HOME="$ihome/.firstmate" FM_CONFIG_ENV="$ihome/.config/firstmate-config/env" \
    FM_SKILLS_ROOT="$ihome/.agents/skills" FM_COMMANDS_ROOT="$ihome/.agents/commands" \
    FM_OMP_AGENTS_ROOT="$ihome/.omp/agent/agents" FM_SKILL_CACHE="$ihome/.local/share/firstmate-config/skills-src" \
    FM_BIN_DIR="$ihome/.local/bin" \
    "$CFG/install.sh" "$@" 2>&1
}
agent_links() {  # <agents-dir>: "<entry> -> <target>" for every symlink
  local e
  for e in "$1"/*; do [ -L "$e" ] && printf '%s -> %s\n' "${e##*/}" "$(readlink "$e")"; done
}

# --- 1. verify before install: every role is reported, nothing is written ---
IH="$TMP_ROOT/home"
mkdir -p "$IH"
out=$(install_fixture "$IH" --verify)
for r in $ROLES; do
  contains "1 verify reports the missing fm-$r link" "$out" "DRIFT   link $IH/.omp/agent/agents/fm-$r.md -> $CFG/roles/$r/ROLE.md"
done
if [ -e "$IH/.omp" ]; then fail '1 verify writes nothing'; else pass '1 verify writes nothing'; fi

# --- 2. install links every role; rerun and verify are clean ----------------
out=$(install_fixture "$IH")
check '2 install exits 0' "$?" 0
expected=$(for r in $ROLES; do printf 'fm-%s.md -> %s\n' "$r" "$CFG/roles/$r/ROLE.md"; done)
check '2 one fm-<role>.md link per role file, and nothing else' "$(agent_links "$IH/.omp/agent/agents")" "$expected"
check '2 a link resolves to the role file content' "$(cat "$IH/.omp/agent/agents/fm-senior-fullstack.md")" "$(cat "$CONFIG_ROOT/roles/senior-fullstack/ROLE.md")"
out=$(install_fixture "$IH")
contains '2 rerun is idempotent' "$out" 'install: 0 change(s), 0 failure(s)'
out=$(install_fixture "$IH" --verify)
contains '2 verify after install: no drift' "$out" 'verify: 0 drift item(s), 0 failure(s)'

# --- 3. a link left by another firstmate-config checkout is ours: repointed -
rm "$IH/.omp/agent/agents/fm-refactorist.md"
ln -s "$TMP_ROOT/old-checkout/roles/refactorist/ROLE.md" "$IH/.omp/agent/agents/fm-refactorist.md"
out=$(install_fixture "$IH" --verify)
contains '3 verify reports a stale own link' "$out" "DRIFT   repoint $IH/.omp/agent/agents/fm-refactorist.md to $CFG/roles/refactorist/ROLE.md"
out=$(install_fixture "$IH")
check '3 install repoints a stale own link' "$(readlink "$IH/.omp/agent/agents/fm-refactorist.md")" "$CFG/roles/refactorist/ROLE.md"

# --- 4. foreign entries under an fm-<role> name are never replaced ----------
IF="$TMP_ROOT/home-foreign"
mkdir -p "$IF/.omp/agent/agents"
printf -- '---\nname: fm-refactorist\ndescription: my own refactorist\n---\nmine\n' > "$IF/.omp/agent/agents/fm-refactorist.md"
printf 'user target\n' > "$TMP_ROOT/user-reviewer.md"
ln -s "$TMP_ROOT/user-reviewer.md" "$IF/.omp/agent/agents/fm-code-reviewer.md"
printf -- '---\nname: helper\ndescription: unrelated\n---\n' > "$IF/.omp/agent/agents/helper.md"
own_before=$(cat "$IF/.omp/agent/agents/fm-refactorist.md")
out=$(install_fixture "$IF")
check '4 install with foreign entries exits 0' "$?" 0
contains '4 a foreign regular file is reported' "$out" "$IF/.omp/agent/agents/fm-refactorist.md exists and is not one of ours"
check '4 a foreign regular file keeps its content' "$(cat "$IF/.omp/agent/agents/fm-refactorist.md")" "$own_before"
contains '4 a foreign symlink is reported' "$out" "$IF/.omp/agent/agents/fm-code-reviewer.md exists and is not one of ours"
check '4 a foreign symlink keeps its target' "$(readlink "$IF/.omp/agent/agents/fm-code-reviewer.md")" "$TMP_ROOT/user-reviewer.md"
check '4 an unrelated user agent is untouched' "$(cat "$IF/.omp/agent/agents/helper.md")" "$(printf -- '---\nname: helper\ndescription: unrelated\n---')"
check '4 the other roles are still linked' "$(readlink "$IF/.omp/agent/agents/fm-senior-fullstack.md")" "$CFG/roles/senior-fullstack/ROLE.md"
out=$(install_fixture "$IF" --verify)
contains '4 verify after install with foreign entries: no drift' "$out" 'verify: 0 drift item(s), 0 failure(s)'

# --- 5. no extension is installed ----------------------------------------------
if [ -e "$IH/.omp/agent/extensions" ]; then fail '5 install links nothing into the OMP extension root'; else pass '5 install links nothing into the OMP extension root'; fi

# --- 6. no live writes ------------------------------------------------------
check '6 live OMP agent and extension roots unchanged' "$(live_snapshot)" "$LIVE_BEFORE"

exit "$failed"
