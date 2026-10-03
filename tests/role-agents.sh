#!/usr/bin/env bash
# role-agents.sh - install.sh links every roles/<name>/ROLE.md into OMP's
# user agent root as fm-<name>.md, and extensions/fm-team-policy.ts into
# OMP's user extension root, idempotently, and never replaces an entry that
# is not ours.
#
# Runs only a disposable copy of install.sh with this checkout's real role
# files and extension, a fixture HOME (every default root resolves under it),
# FM_HOME, env file, agent and extension roots under that HOME, fake
# pi/omp/herdr on PATH, and no external.lock, so nothing is cloned or fetched
# and no live root is touched. The operator's live agent and extension roots
# are compared before and after.
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
cp -R "$CONFIG_ROOT/extensions" "$CFG/extensions"
POLICY="$CFG/extensions/fm-team-policy.ts"
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
    FM_OMP_EXTENSIONS_ROOT="$ihome/.omp/agent/extensions" FM_BIN_DIR="$ihome/.local/bin" \
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
check '2 a link resolves to the role file content' "$(cat "$IH/.omp/agent/agents/fm-team-lead.md")" "$(cat "$CONFIG_ROOT/roles/team-lead/ROLE.md")"
out=$(install_fixture "$IH")
contains '2 rerun is idempotent' "$out" 'install: 0 change(s), 0 failure(s)'
out=$(install_fixture "$IH" --verify)
contains '2 verify after install: no drift' "$out" 'verify: 0 drift item(s), 0 failure(s)'

# --- 3. a link left by another firstmate-config checkout is ours: repointed -
rm "$IH/.omp/agent/agents/fm-qa.md"
ln -s "$TMP_ROOT/old-checkout/roles/qa/ROLE.md" "$IH/.omp/agent/agents/fm-qa.md"
out=$(install_fixture "$IH" --verify)
contains '3 verify reports a stale own link' "$out" "DRIFT   repoint $IH/.omp/agent/agents/fm-qa.md to $CFG/roles/qa/ROLE.md"
out=$(install_fixture "$IH")
check '3 install repoints a stale own link' "$(readlink "$IH/.omp/agent/agents/fm-qa.md")" "$CFG/roles/qa/ROLE.md"

# --- 4. foreign entries under an fm-<role> name are never replaced ----------
IF="$TMP_ROOT/home-foreign"
mkdir -p "$IF/.omp/agent/agents"
printf -- '---\nname: fm-qa\ndescription: my own qa\n---\nmine\n' > "$IF/.omp/agent/agents/fm-qa.md"
printf 'user target\n' > "$TMP_ROOT/user-reviewer.md"
ln -s "$TMP_ROOT/user-reviewer.md" "$IF/.omp/agent/agents/fm-code-reviewer.md"
printf -- '---\nname: helper\ndescription: unrelated\n---\n' > "$IF/.omp/agent/agents/helper.md"
qa_before=$(cat "$IF/.omp/agent/agents/fm-qa.md")
out=$(install_fixture "$IF")
check '4 install with foreign entries exits 0' "$?" 0
contains '4 a foreign regular file is reported' "$out" "$IF/.omp/agent/agents/fm-qa.md exists and is not one of ours"
check '4 a foreign regular file keeps its content' "$(cat "$IF/.omp/agent/agents/fm-qa.md")" "$qa_before"
contains '4 a foreign symlink is reported' "$out" "$IF/.omp/agent/agents/fm-code-reviewer.md exists and is not one of ours"
check '4 a foreign symlink keeps its target' "$(readlink "$IF/.omp/agent/agents/fm-code-reviewer.md")" "$TMP_ROOT/user-reviewer.md"
check '4 an unrelated user agent is untouched' "$(cat "$IF/.omp/agent/agents/helper.md")" "$(printf -- '---\nname: helper\ndescription: unrelated\n---')"
check '4 the other roles are still linked' "$(readlink "$IF/.omp/agent/agents/fm-team-lead.md")" "$CFG/roles/team-lead/ROLE.md"
out=$(install_fixture "$IF" --verify)
contains '4 verify after install with foreign entries: no drift' "$out" 'verify: 0 drift item(s), 0 failure(s)'

# --- 5. the team policy extension link ---------------------------------------
EXT_LINK="$IH/.omp/agent/extensions/fm-team-policy.ts"
check '5 install links the team policy extension' "$(readlink "$EXT_LINK")" "$POLICY"
check '5 the extension link resolves to the extension source' "$(cat "$EXT_LINK")" "$(cat "$CONFIG_ROOT/extensions/fm-team-policy.ts")"
IE="$TMP_ROOT/home-ext"
mkdir -p "$IE"
out=$(install_fixture "$IE" --verify)
contains '5 verify reports the missing extension link' "$out" "DRIFT   link $IE/.omp/agent/extensions/fm-team-policy.ts -> $POLICY"
if [ -e "$IE/.omp" ]; then fail '5 verify writes no extension root'; else pass '5 verify writes no extension root'; fi
rm "$EXT_LINK"
ln -s "$TMP_ROOT/old-checkout/extensions/fm-team-policy.ts" "$EXT_LINK"
out=$(install_fixture "$IH")
check '5 a stale own extension link is repointed' "$(readlink "$EXT_LINK")" "$POLICY"
out=$(install_fixture "$IH")
contains '5 rerun with the extension linked is idempotent' "$out" 'install: 0 change(s), 0 failure(s)'
IX="$TMP_ROOT/home-ext-foreign"
mkdir -p "$IX/.omp/agent/extensions"
printf '// my own policy\n' > "$IX/.omp/agent/extensions/fm-team-policy.ts"
printf '// herdr state\n' > "$IX/.omp/agent/extensions/herdr-omp-agent-state.ts"
mkdir -p "$TMP_ROOT/other-firstmate/.omp/extensions"
ln -s "$TMP_ROOT/other-firstmate/.omp/extensions" "$IX/.omp/agent/extensions/firstmate"
out=$(install_fixture "$IX")
check '5 install with a foreign extension exits 0' "$?" 0
contains '5 a foreign extension file is reported' "$out" "$IX/.omp/agent/extensions/fm-team-policy.ts exists and is not one of ours"
check '5 a foreign extension file keeps its content' "$(cat "$IX/.omp/agent/extensions/fm-team-policy.ts")" '// my own policy'
check '5 an unrelated user extension is untouched' "$(cat "$IX/.omp/agent/extensions/herdr-omp-agent-state.ts")" '// herdr state'
check '5 an unrelated extension directory link is untouched' "$(readlink "$IX/.omp/agent/extensions/firstmate")" "$TMP_ROOT/other-firstmate/.omp/extensions"
IY="$TMP_ROOT/home-ext-foreign-link"
mkdir -p "$IY/.omp/agent/extensions"
printf '// theirs\n' > "$TMP_ROOT/their-policy.ts"
ln -s "$TMP_ROOT/their-policy.ts" "$IY/.omp/agent/extensions/fm-team-policy.ts"
out=$(install_fixture "$IY")
contains '5 a foreign extension symlink is reported' "$out" "$IY/.omp/agent/extensions/fm-team-policy.ts exists and is not one of ours"
check '5 a foreign extension symlink keeps its target' "$(readlink "$IY/.omp/agent/extensions/fm-team-policy.ts")" "$TMP_ROOT/their-policy.ts"

# --- 6. no live writes ------------------------------------------------------
check '6 live OMP agent and extension roots unchanged' "$(live_snapshot)" "$LIVE_BEFORE"

exit "$failed"
