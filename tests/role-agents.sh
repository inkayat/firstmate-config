#!/usr/bin/env bash
# role-agents.sh - install.sh links every roles/<name>/ROLE.md into OMP's
# user agent root as fm-<name>.md, idempotently, never replaces an entry that
# is not ours, and links nothing into OMP's user extension root. It also owns
# install.sh's shared link representation (sections 3, 6-7): new links are
# relative, an existing absolute or relative link to the same owned source is
# left untouched, a wrong, broken or foreign link fails without being
# rewritten, and a source missing or outside its own tree is never linked.
#
# Runs only disposable copies of install.sh with this checkout's real role
# files (sections 1-5) or a one-skill/one-command/one-role fixture tree
# (sections 6-7), fixture HOMEs (Mac-style /Users/... and Linux-style
# /home/... paths under a temp dir - path simulation on this machine, not a
# run on Linux), FM_HOME, env file and agent root under that HOME, fake
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
: > "$CFG/bin/fm"; : > "$CFG/bin/ponytail-update"; chmod +x "$CFG/bin/fm" "$CFG/bin/ponytail-update"
for t in pi omp herdr; do : > "$TMP_ROOT/fake-bin/$t"; chmod +x "$TMP_ROOT/fake-bin/$t"; done
printf 'AGENTS\n' > "$TMP_ROOT/firstmate/AGENTS.md"
ROLES=$(cd "$CFG/roles" && for d in */; do [ -f "$d/ROLE.md" ] && printf '%s\n' "${d%/}"; done)

install_at() {  # <config root> <home> <skills root> [install.sh args...]
  local cfg=$1 ihome=$2 skills=$3
  shift 3
  PATH="$TMP_ROOT/fake-bin:/usr/bin:/bin" HOME="$ihome" FIRSTMATE_ROOT="$TMP_ROOT/firstmate" \
    FM_HOME="$ihome/.firstmate" FM_CONFIG_ENV="$ihome/.config/firstmate-config/env" \
    FM_SKILLS_ROOT="$skills" FM_COMMANDS_ROOT="$ihome/.agents/commands" \
    FM_OMP_AGENTS_ROOT="$ihome/.omp/agent/agents" FM_SKILL_CACHE="$ihome/.local/share/firstmate-config/skills-src" \
    FM_BIN_DIR="$ihome/.local/bin" \
    "$cfg/install.sh" "$@" 2>&1
}
install_fixture() {  # <home> [install.sh args...]
  local ihome=$1
  shift
  install_at "$CFG" "$ihome" "$ihome/.agents/skills" "$@"
}
# realp <path>: the fully resolved physical path, computed by Python rather
# than by anything install.sh does.
realp() { python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
agent_links() {  # <agents-dir>: "<entry> -> <resolved target>" for every symlink
  local e
  for e in "$1"/*; do [ -L "$e" ] && printf '%s -> %s\n' "${e##*/}" "$(realp "$e")"; done
}
# lstat_id <link>: link text, inode and mtime; any rewrite changes the last two.
lstat_id() { python3 -c 'import os, sys; s = os.lstat(sys.argv[1]); print(os.readlink(sys.argv[1]), s.st_ino, s.st_mtime_ns)' "$1"; }

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
expected=$(for r in $ROLES; do printf 'fm-%s.md -> %s\n' "$r" "$(realp "$CFG/roles/$r/ROLE.md")"; done)
check '2 one fm-<role>.md link per role file, and nothing else' "$(agent_links "$IH/.omp/agent/agents")" "$expected"
check '2 a link resolves to the role file content' "$(cat "$IH/.omp/agent/agents/fm-senior-fullstack.md")" "$(cat "$CONFIG_ROOT/roles/senior-fullstack/ROLE.md")"
out=$(install_fixture "$IH")
contains '2 rerun is idempotent' "$out" 'install: 0 change(s), 0 failure(s)'
out=$(install_fixture "$IH" --verify)
contains '2 verify after install: no drift' "$out" 'verify: 0 drift item(s), 0 failure(s)'

# --- 3. a link to another checkout's role file is not ours: refused untouched
# Name enumeration is no ownership proof, so a link resolving anywhere but this
# checkout's own role file is reported as a failure by verify and by a normal
# run alike, and neither rewrites it; removing it lets install.sh link it.
rm "$IH/.omp/agent/agents/fm-refactorist.md"
ln -s "$TMP_ROOT/old-checkout/roles/refactorist/ROLE.md" "$IH/.omp/agent/agents/fm-refactorist.md"
id_before=$(lstat_id "$IH/.omp/agent/agents/fm-refactorist.md")
out=$(install_fixture "$IH" --verify)
contains '3 verify refuses a link to another checkout' "$out" "FAIL    $IH/.omp/agent/agents/fm-refactorist.md points at $TMP_ROOT/old-checkout/roles/refactorist/ROLE.md, not $CFG/roles/refactorist/ROLE.md"
out=$(install_fixture "$IH"); rc=$?
if [ "$rc" -ne 0 ]; then pass '3 install with a refused link exits nonzero'; else fail '3 install with a refused link exits nonzero'; fi
contains '3 install refuses the same link' "$out" "FAIL    $IH/.omp/agent/agents/fm-refactorist.md points at"
check '3 install leaves the refused link untouched (text, inode, mtime)' "$(lstat_id "$IH/.omp/agent/agents/fm-refactorist.md")" "$id_before"
rm "$IH/.omp/agent/agents/fm-refactorist.md"
out=$(install_fixture "$IH")
check '3 once removed, install links the role again' "$(realp "$IH/.omp/agent/agents/fm-refactorist.md")" "$(realp "$CFG/roles/refactorist/ROLE.md")"

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
check '4 the other roles are still linked' "$(realp "$IF/.omp/agent/agents/fm-senior-fullstack.md")" "$(realp "$CFG/roles/senior-fullstack/ROLE.md")"
out=$(install_fixture "$IF" --verify)
contains '4 verify after install with foreign entries: no drift' "$out" 'verify: 0 drift item(s), 0 failure(s)'

# --- 5. no extension is installed ----------------------------------------------
if [ -e "$IH/.omp/agent/extensions" ]; then fail '5 install links nothing into the OMP extension root'; else pass '5 install links nothing into the OMP extension root'; fi

# --- 6. link representation: relative on creation, equivalence on reconcile -
# tree_state <dir>: every entry below it, never following a link.
tree_state() {
  python3 - "$1" <<'PY'
import os, sys
root = sys.argv[1]
for d, dirs, files in os.walk(root):
    dirs.sort()
    for n in sorted(dirs + files):
        p = os.path.join(d, n)
        s = os.lstat(p)
        print(os.path.relpath(p, root), oct(s.st_mode), s.st_ino, s.st_mtime_ns, os.readlink(p) if os.path.islink(p) else "")
PY
}
make_cfg() {  # <dir>: a disposable configuration tree with one skill, command and role
  mkdir -p "$1/bin" "$1/firstmate" "$1/skills/demo" "$1/commands" "$1/roles/demo"
  cp "$CONFIG_ROOT/install.sh" "$1/install.sh"
  cp "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh" "$CONFIG_ROOT/firstmate/stack-manifest.tsv" \
     "$CONFIG_ROOT/firstmate/crew-dispatch.json" "$CONFIG_ROOT/firstmate/captain.md" "$1/firstmate/"
  printf -- '---\nname: demo\ndescription: demo skill\n---\n' > "$1/skills/demo/SKILL.md"
  printf 'demo command\n' > "$1/commands/demo.md"
  printf -- '---\nname: fm-demo\ndescription: demo role\n---\n' > "$1/roles/demo/ROLE.md"
  : > "$1/bin/fm"; : > "$1/bin/ponytail-update"; chmod +x "$1/bin/fm" "$1/bin/ponytail-update"
}
old_mtime() { touch -h -t 200001010000 "$@"; }

# 6.1 Mac-style HOME with a space, configuration under it: fresh links are
# relative from their own directory and resolve to the owned sources.
MH="$TMP_ROOT/mac/Users/al ice"
MC="$MH/.firstmate/projects/firstmate-config"
make_cfg "$MC"
out=$(install_at "$MC" "$MH" "$MH/.agents/skills")
check '6.1 fresh install exits 0' "$?" 0
check '6.1 new skill link is relative' "$(readlink "$MH/.agents/skills/demo")" '../../.firstmate/projects/firstmate-config/skills/demo'
check '6.1 new command link is relative' "$(readlink "$MH/.agents/commands/demo.md")" '../../.firstmate/projects/firstmate-config/commands/demo.md'
check '6.1 new role agent link is relative' "$(readlink "$MH/.omp/agent/agents/fm-demo.md")" '../../../.firstmate/projects/firstmate-config/roles/demo/ROLE.md'
check '6.1 new launcher link is relative' "$(readlink "$MH/.local/bin/fm")" '../../.firstmate/projects/firstmate-config/bin/fm'
check '6.1 new dispatch profile link is relative' "$(readlink "$MH/.firstmate/config/crew-dispatch.json")" '../projects/firstmate-config/firstmate/crew-dispatch.json'
check '6.1 the relative skill link resolves to the owned skill' "$(realp "$MH/.agents/skills/demo")" "$(realp "$MC/skills/demo")"
check '6.1 the relative role link serves the role file' "$(cat "$MH/.omp/agent/agents/fm-demo.md")" "$(cat "$MC/roles/demo/ROLE.md")"
before=$(tree_state "$TMP_ROOT/mac")
out=$(install_at "$MC" "$MH" "$MH/.agents/skills")
contains '6.1 second run reports zero changes' "$out" 'install: 0 change(s), 0 failure(s)'
check '6.1 second run mutates nothing (text, inode, mtime of every entry)' "$(tree_state "$TMP_ROOT/mac")" "$before"
out=$(install_at "$MC" "$MH" "$MH/.agents/skills" --verify)
contains '6.1 verify agrees: no drift' "$out" 'verify: 0 drift item(s), 0 failure(s)'

# 6.2 Linux-style HOME, nondefault skills root with a space, configuration
# outside HOME: still relative, and still valid after the whole tree moves.
LH="$TMP_ROOT/lin/home/alice"
LC="$TMP_ROOT/lin/opt/fm cfg"
make_cfg "$LC"
mkdir -p "$LH"
out=$(install_at "$LC" "$LH" "$LH/custom skills")
check '6.2 nondefault skills root: relative from the actual link directory' "$(readlink "$LH/custom skills/demo")" '../../../opt/fm cfg/skills/demo'
mv "$TMP_ROOT/lin" "$TMP_ROOT/lin-moved"
LH="$TMP_ROOT/lin-moved/home/alice"
LC="$TMP_ROOT/lin-moved/opt/fm cfg"
check '6.2 links survive relocating the whole tree' "$(cat "$LH/custom skills/demo/SKILL.md")" "$(cat "$LC/skills/demo/SKILL.md")"
# The env file legitimately records the moved configuration path; every link
# must stay exactly as it was.
links_state() { local d; for d in "$LH/custom skills" "$LH/.agents/commands" "$LH/.omp/agent/agents" "$LH/.local/bin" "$LH/.firstmate/config"; do tree_state "$d"; done; }
before=$(links_state)
out=$(install_at "$LC" "$LH" "$LH/custom skills")
case $out in *FAIL*|*'changed linked'*) fail "6.2 relocated rerun refuses and creates no link ($out)" ;; *) pass '6.2 relocated rerun refuses and creates no link' ;; esac
check '6.2 relocated rerun leaves every link untouched (text, inode, mtime)' "$(links_state)" "$before"

# 6.3 Existing correct links in other spellings are accepted untouched:
# absolute (today's installed form), relative, a harmless alias of a parent
# directory, a non-normalized relative spelling, and a chain through an alias
# that itself lives inside the configuration tree.
BH="$TMP_ROOT/mac2/Users/bob"
BC="$BH/.firstmate/projects/firstmate-config"
make_cfg "$BC"
mkdir -p "$BH/.agents/skills" "$BH/.agents/commands" "$BH/.omp/agent/agents" "$BH/.local/bin" "$BH/.firstmate/config" "$BC/aliases"
ln -s '../firstmate/crew-dispatch.json' "$BC/aliases/dispatch.json"
ln -s "$BC" "$BH/cfg-alias"
ln -s "$BC/skills/demo" "$BH/.agents/skills/demo"
ln -s '../../.firstmate/projects/firstmate-config/commands/demo.md' "$BH/.agents/commands/demo.md"
ln -s "$BH/cfg-alias/roles/demo/ROLE.md" "$BH/.omp/agent/agents/fm-demo.md"
ln -s '../../.firstmate/./projects/firstmate-config/bin/fm' "$BH/.local/bin/fm"
ln -s "$BC/aliases/dispatch.json" "$BH/.firstmate/config/crew-dispatch.json"
b_ids() { local l; for l in "$BH/.agents/skills/demo" "$BH/.agents/commands/demo.md" "$BH/.omp/agent/agents/fm-demo.md" "$BH/.local/bin/fm" "$BH/.firstmate/config/crew-dispatch.json"; do lstat_id "$l"; done; }
old_mtime "$BH/.agents/skills/demo" "$BH/.agents/commands/demo.md" "$BH/.omp/agent/agents/fm-demo.md" "$BH/.local/bin/fm" "$BH/.firstmate/config/crew-dispatch.json"
ids_before=$(b_ids)
out=$(install_at "$BC" "$BH" "$BH/.agents/skills" --verify)
contains '6.3 verify: correct absolute link is ok' "$out" "ok      $BH/.agents/skills/demo"
contains '6.3 verify: correct relative link is ok' "$out" "ok      $BH/.agents/commands/demo.md"
contains '6.3 verify: link through a parent-directory alias is ok' "$out" "ok      $BH/.omp/agent/agents/fm-demo.md"
contains '6.3 verify: non-normalized relative spelling is ok' "$out" "ok      $BH/.local/bin/fm"
contains '6.3 verify: chain through an alias inside the tree is ok' "$out" "ok      $BH/.firstmate/config/crew-dispatch.json"
out=$(install_at "$BC" "$BH" "$BH/.agents/skills")
check '6.3 install exits 0' "$?" 0
check '6.3 none of the five correct links is rewritten (text, inode, mtime)' "$(b_ids)" "$ids_before"
case $out in *FAIL*) fail "6.3 install refuses none of them ($out)" ;; *) pass '6.3 install refuses none of them' ;; esac

# 6.4 Wrong, broken and foreign links, absolute and relative, are failures in
# verify AND in a normal run, and neither rewrites the link or touches what it
# points at: name enumeration is no ownership proof.
WH="$TMP_ROOT/lin2/home/carol"
WC="$WH/.firstmate/projects/firstmate-config"
make_cfg "$WC"
make_cfg "$TMP_ROOT/other"
mkdir -p "$WH/.agents/skills" "$WH/.agents/commands" "$WH/.omp/agent/agents" "$WH/.local/bin" "$WH/.firstmate/config" "$WH/wrong"
printf 'not ours\n' > "$WH/wrong/demo.md"
ln -s "$WC/firstmate/crew-dispatch.json" "$WH/my-alias"
ln -s "$TMP_ROOT/other/skills/demo" "$WH/.agents/skills/demo"
ln -s '../../wrong/demo.md' "$WH/.agents/commands/demo.md"
ln -s "$TMP_ROOT/missing/roles/demo/ROLE.md" "$WH/.omp/agent/agents/fm-demo.md"
ln -s '../../gone/bin/fm' "$WH/.local/bin/fm"
ln -s "$WH/my-alias" "$WH/.firstmate/config/crew-dispatch.json"
w_ids() { local l; for l in "$WH/.agents/skills/demo" "$WH/.agents/commands/demo.md" "$WH/.omp/agent/agents/fm-demo.md" "$WH/.local/bin/fm" "$WH/.firstmate/config/crew-dispatch.json" "$WH/my-alias"; do lstat_id "$l"; done; }
ids_before=$(w_ids)
other_before=$(tree_state "$TMP_ROOT/other"); wrong_before=$(tree_state "$WH/wrong"); home_before=$(tree_state "$WH")
out=$(install_at "$WC" "$WH" "$WH/.agents/skills" --verify)
contains '6.4 verify: wrong absolute link (to a foreign directory) fails' "$out" "FAIL    $WH/.agents/skills/demo points at $TMP_ROOT/other/skills/demo, not $WC/skills/demo"
contains '6.4 verify: wrong relative link fails' "$out" "FAIL    $WH/.agents/commands/demo.md points at ../../wrong/demo.md, not $WC/commands/demo.md"
contains '6.4 verify: broken absolute link fails' "$out" "FAIL    $WH/.omp/agent/agents/fm-demo.md points at $TMP_ROOT/missing/roles/demo/ROLE.md, not $WC/roles/demo/ROLE.md"
contains '6.4 verify: broken relative link fails' "$out" "FAIL    $WH/.local/bin/fm points at ../../gone/bin/fm, not $WC/bin/fm"
contains '6.4 verify: chain through a foreign alias outside the tree fails' "$out" "FAIL    $WH/.firstmate/config/crew-dispatch.json points at $WH/my-alias, not $WC/firstmate/crew-dispatch.json"
check '6.4 verify writes nothing' "$(tree_state "$WH")" "$home_before"
out=$(install_at "$WC" "$WH" "$WH/.agents/skills"); rc=$?
if [ "$rc" -ne 0 ]; then pass '6.4 install with refused links exits nonzero'; else fail '6.4 install with refused links exits nonzero'; fi
contains '6.4 install refuses the same links' "$out" "FAIL    $WH/.agents/skills/demo points at"
check '6.4 install rewrites none of the refused links (text, inode, mtime)' "$(w_ids)" "$ids_before"
check '6.4 the foreign directory a link pointed at is untouched, nothing nested' "$(tree_state "$TMP_ROOT/other")" "$other_before"
check '6.4 the foreign file a link pointed at is untouched' "$(tree_state "$WH/wrong")" "$wrong_before"
out=$(install_at "$WC" "$WH" "$WH/.agents/skills")
check '6.4 a second normal run still rewrites nothing' "$(w_ids)" "$ids_before"

# 6.5 An unexpected regular file or real directory at a link path is
# reported and left exactly as it was, with nothing written inside it.
UH="$TMP_ROOT/lin3/home/dave"
UC="$UH/.firstmate/projects/firstmate-config"
make_cfg "$UC"
mkdir -p "$UH/.agents/skills/demo" "$UH/.agents/commands"
printf 'my notes\n' > "$UH/.agents/skills/demo/notes.md"
printf 'my own command\n' > "$UH/.agents/commands/demo.md"
dir_before=$(tree_state "$UH/.agents")
out=$(install_at "$UC" "$UH" "$UH/.agents/skills")
check '6.5 install with unexpected entries exits 0' "$?" 0
contains '6.5 an unexpected directory is reported' "$out" "$UH/.agents/skills/demo exists and is not one of ours"
contains '6.5 an unexpected file is reported' "$out" "$UH/.agents/commands/demo.md exists and is not one of ours"
check '6.5 both are untouched, nothing nested inside the directory' "$(tree_state "$UH/.agents")" "$dir_before"

# 6.6 Terminal "." / ".." spellings of the same owned skill directory are
# accepted untouched (absolute and relative), while an alias loop inside the
# tree is refused without hanging.
DH="$TMP_ROOT/dots/Users/hana"
DC="$DH/.firstmate/projects/firstmate-config"
make_cfg "$DC"
mkdir -p "$DC/skills/demo2/child" "$DC/aliases" "$DH/.agents/skills" "$DH/.agents/commands"
printf -- '---\nname: demo2\ndescription: second demo skill\n---\n' > "$DC/skills/demo2/SKILL.md"
ln -s loop2 "$DC/aliases/loop1"
ln -s loop1 "$DC/aliases/loop2"
ln -s "$DC/skills/demo/." "$DH/.agents/skills/demo"
ln -s '../../.firstmate/projects/firstmate-config/skills/demo2/child/..' "$DH/.agents/skills/demo2"
ln -s "$DC/aliases/loop1" "$DH/.agents/commands/demo.md"
old_mtime "$DH/.agents/skills/demo" "$DH/.agents/skills/demo2" "$DH/.agents/commands/demo.md"
d_ids() { local l; for l in "$DH/.agents/skills/demo" "$DH/.agents/skills/demo2" "$DH/.agents/commands/demo.md"; do lstat_id "$l"; done; }
ids_before=$(d_ids)
out=$(install_at "$DC" "$DH" "$DH/.agents/skills" --verify)
contains '6.6 verify: absolute ".../skills/demo/." is ok' "$out" "ok      $DH/.agents/skills/demo"
contains '6.6 verify: relative ".../skills/demo2/child/.." is ok' "$out" "ok      $DH/.agents/skills/demo2"
contains '6.6 verify: an alias loop inside the tree fails' "$out" "FAIL    $DH/.agents/commands/demo.md points at $DC/aliases/loop1, not $DC/commands/demo.md"
out=$(install_at "$DC" "$DH" "$DH/.agents/skills")
out=$(install_at "$DC" "$DH" "$DH/.agents/skills")
case $out in *"FAIL    $DH/.agents/skills/demo"*) fail '6.6 install accepts both dot spellings' ;; *) pass '6.6 install accepts both dot spellings' ;; esac
check '6.6 a second run rewrites none of the three links (text, inode, mtime)' "$(d_ids)" "$ids_before"

# 6.7 Every link_to caller refuses on its own: a single wrong link at a time
# (own skill, external pinned skill, command, role, launcher, dispatch
# profile) makes verify and a normal run exit nonzero with that one FAIL,
# and leaves the link and the foreign content it points at untouched. The
# summary's failure figure is install.sh's existing 0/1 flag, not a count.
XC="$TMP_ROOT/single/cfg"
make_cfg "$XC"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
single_cache() { # <home>: a pinned external skill checkout in the home's skill cache; prints its commit
  local c="$1/.local/share/firstmate-config/skills-src/o-ext"
  mkdir -p "$c/skills/ext"
  printf -- '---\nname: ext\ndescription: external\n---\n' > "$c/skills/ext/SKILL.md"
  git -C "$c" init -q && git -C "$c" add -A && git -C "$c" commit -qm pin && git -C "$c" rev-parse HEAD
}
ext_sha=$(single_cache "$TMP_ROOT/single/probe")
printf 'ext\to/ext\t%s\tskills/ext\text\n' "$ext_sha" > "$XC/skills/external.lock"
for case in skill external command role launcher dispatch; do
  h="$TMP_ROOT/single/home-$case"
  [ "$(single_cache "$h")" = "$ext_sha" ] || fail "6.7 $case: fixture cache pins the same commit"
  out=$(install_at "$XC" "$h" "$h/.agents/skills"); rc=$?
  check "6.7 $case: a clean install exits 0" "$rc" 0
  foreign="$TMP_ROOT/single/foreign-$case"
  case $case in
    skill)    l="$h/.agents/skills/demo";  mkdir -p "$foreign"; printf 'mine\n' > "$foreign/SKILL.md"; t=$foreign ;;
    external) l="$h/.agents/skills/ext";   mkdir -p "$foreign"; printf 'mine\n' > "$foreign/SKILL.md"; t=$foreign ;;
    command)  l="$h/.agents/commands/demo.md"; mkdir -p "$foreign"; printf 'mine\n' > "$foreign/demo.md"; t="$foreign/demo.md" ;;
    role)     l="$h/.omp/agent/agents/fm-demo.md"; mkdir -p "$foreign/roles/demo"; printf 'mine\n' > "$foreign/roles/demo/ROLE.md"; t="$foreign/roles/demo/ROLE.md" ;;
    launcher) l="$h/.local/bin/fm";        mkdir -p "$foreign"; printf 'mine\n' > "$foreign/fm"; t="$foreign/fm" ;;
    dispatch) l="$h/.firstmate/config/crew-dispatch.json"; mkdir -p "$foreign"; printf '{}\n' > "$foreign/d.json"; t="$foreign/d.json" ;;
  esac
  rm "$l"; ln -s "$t" "$l"
  l_before=$(lstat_id "$l"); f_before=$(tree_state "$foreign")
  out=$(install_at "$XC" "$h" "$h/.agents/skills" --verify); rc=$?
  if [ "$rc" -ne 0 ]; then pass "6.7 $case: verify exits nonzero"; else fail "6.7 $case: verify exits nonzero"; fi
  contains "6.7 $case: verify names the one refused link" "$out" "FAIL    $l points at $t"
  contains "6.7 $case: verify summary carries the failure" "$out" 'verify: 0 drift item(s), 1 failure(s)'
  out=$(install_at "$XC" "$h" "$h/.agents/skills"); rc=$?
  if [ "$rc" -ne 0 ]; then pass "6.7 $case: install exits nonzero"; else fail "6.7 $case: install exits nonzero"; fi
  contains "6.7 $case: install summary carries the failure" "$out" 'install: 0 change(s), 1 failure(s)'
  check "6.7 $case: the refused link is untouched (text, inode, mtime)" "$(lstat_id "$l")" "$l_before"
  check "6.7 $case: the foreign content is untouched" "$(tree_state "$foreign")" "$f_before"
done
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE

# --- 7. equivalence never blesses a destination the source tree does not own
# 7.1 The configuration's skills directory is an alias for a directory outside
# it: the expected source escapes its tree, so it is unavailable - a link
# straight to the outside copy is refused untouched, and no link (absolute
# or otherwise) is created for it.
EA="$TMP_ROOT/esc-a/home/erin"
EAC="$EA/.firstmate/projects/firstmate-config"
make_cfg "$EAC"
mkdir -p "$TMP_ROOT/outside-a"
mv "$EAC/skills" "$TMP_ROOT/outside-a/skills"
ln -s "$TMP_ROOT/outside-a/skills" "$EAC/skills"
mkdir -p "$EA/.agents/skills"
ln -s "$TMP_ROOT/outside-a/skills/demo" "$EA/.agents/skills/demo"
ea_before=$(lstat_id "$EA/.agents/skills/demo")
out=$(install_at "$EAC" "$EA" "$EA/.agents/skills" --verify)
contains '7.1 parent-alias escape: verify reports the source unavailable, not ok' "$out" "FAIL    $EAC/skills/demo is missing or outside its own tree; not linking $EA/.agents/skills/demo"
out=$(install_at "$EAC" "$EA" "$EA/.agents/skills"); rc=$?
if [ "$rc" -ne 0 ]; then pass '7.1 parent-alias escape: install exits nonzero'; else fail '7.1 parent-alias escape: install exits nonzero'; fi
check '7.1 parent-alias escape: the existing link is untouched' "$(lstat_id "$EA/.agents/skills/demo")" "$ea_before"
EA2="$TMP_ROOT/esc-a/home/erin2"
mkdir -p "$EA2"
out=$(install_at "$EAC" "$EA2" "$EA2/.agents/skills")
contains '7.1 parent-alias escape: a fresh install refuses the source' "$out" "FAIL    $EAC/skills/demo is missing or outside its own tree; not linking $EA2/.agents/skills/demo"
if [ -e "$EA2/.agents/skills/demo" ] || [ -L "$EA2/.agents/skills/demo" ]; then fail '7.1 parent-alias escape: no link is created'; else pass '7.1 parent-alias escape: no link is created'; fi
check '7.1 parent-alias escape: sources inside the tree are still linked relative' "$(readlink "$EA2/.agents/commands/demo.md")" '../../../erin/.firstmate/projects/firstmate-config/commands/demo.md'

# 7.2 The skill entry itself is a symlink to an outside directory: its own
# final component is never followed, so a link straight to that outside
# directory is refused untouched, while a fresh link goes through the owned entry.
EB="$TMP_ROOT/esc-b/home/frank"
EBC="$EB/.firstmate/projects/firstmate-config"
make_cfg "$EBC"
mkdir -p "$TMP_ROOT/outside-b"
mv "$EBC/skills/demo" "$TMP_ROOT/outside-b/demo"
ln -s "$TMP_ROOT/outside-b/demo" "$EBC/skills/demo"
mkdir -p "$EB/.agents/skills"
ln -s "$TMP_ROOT/outside-b/demo" "$EB/.agents/skills/demo"
eb_before=$(lstat_id "$EB/.agents/skills/demo")
out=$(install_at "$EBC" "$EB" "$EB/.agents/skills" --verify)
contains '7.2 final-component escape: link to the outside target fails, not ok' "$out" "FAIL    $EB/.agents/skills/demo points at $TMP_ROOT/outside-b/demo, not $EBC/skills/demo"
out=$(install_at "$EBC" "$EB" "$EB/.agents/skills")
check '7.2 final-component escape: install leaves that link untouched' "$(lstat_id "$EB/.agents/skills/demo")" "$eb_before"
rm "$EB/.agents/skills/demo"
out=$(install_at "$EBC" "$EB" "$EB/.agents/skills")
check '7.2 a fresh link names the owned entry, not its outside target' "$(readlink "$EB/.agents/skills/demo")" '../../.firstmate/projects/firstmate-config/skills/demo'
# A terminal "." through that outside-pointing entry is the outside directory,
# not the owned entry: still refused untouched.
EB2="$TMP_ROOT/esc-b/home/frank2"
mkdir -p "$EB2/.agents/skills"
ln -s "$EBC/skills/demo/." "$EB2/.agents/skills/demo"
eb2_before=$(lstat_id "$EB2/.agents/skills/demo")
out=$(install_at "$EBC" "$EB2" "$EB2/.agents/skills")
contains '7.2 final-component escape spelled with a terminal "." is refused' "$out" "FAIL    $EB2/.agents/skills/demo points at $EBC/skills/demo/., not $EBC/skills/demo"
check '7.2 final-component escape spelled with a terminal "." is left untouched' "$(lstat_id "$EB2/.agents/skills/demo")" "$eb2_before"

# 7.3 Link text identical to the expected path is not healthy when that source
# is missing: verify and install both fail and nothing is written.
MH3="$TMP_ROOT/miss/home/gail"
MC3="$MH3/.firstmate/projects/firstmate-config"
make_cfg "$MC3"
rm "$MC3/bin/ponytail-update"
mkdir -p "$MH3/.local/bin"
ln -s "$MC3/bin/ponytail-update" "$MH3/.local/bin/ponytail-update"
m_before=$(lstat_id "$MH3/.local/bin/ponytail-update")
out=$(install_at "$MC3" "$MH3" "$MH3/.agents/skills" --verify)
case $out in *"ok      $MH3/.local/bin/ponytail-update"*) fail '7.3 exact text to a missing source is not ok' ;; *) pass '7.3 exact text to a missing source is not ok' ;; esac
contains '7.3 verify reports the missing source' "$out" "FAIL    $MC3/bin/ponytail-update is missing or outside its own tree; not linking $MH3/.local/bin/ponytail-update"
out=$(install_at "$MC3" "$MH3" "$MH3/.agents/skills")
check '7.3 install leaves that link untouched' "$(lstat_id "$MH3/.local/bin/ponytail-update")" "$m_before"

# --- 8. no live writes ------------------------------------------------------
check '8 live OMP agent and extension roots unchanged' "$(live_snapshot)" "$LIVE_BEFORE"

exit "$failed"
