#!/usr/bin/env bash
# team.sh - bin/fm-team: team profile validation against the real role files'
# native upper bounds, per-task binding, and the delivery scope audit.
#
# Runs a disposable copy of this checkout's bin/fm-team, roles/, skills/ and
# teams/ (so a profile is judged against the real role frontmatter), a fixture
# FM_HOME, and disposable git repositories. Nothing under the operator's real
# FM_HOME, OMP agent root, or this checkout is written; the live binding
# directory is compared before and after.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIVE_BINDINGS="${HOME}/.firstmate/data/team-bindings"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$3', got '$2')"; fi; }
contains() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in '$2')" ;; esac; }
not_contains() { case $2 in *"$3"*) fail "$1 (unexpected '$3' in '$2')" ;; *) pass "$1" ;; esac; }

live_snapshot() {
  if [ -e "$LIVE_BINDINGS" ] || [ -L "$LIVE_BINDINGS" ]; then ls -laR "$LIVE_BINDINGS" 2>/dev/null
  else printf '%s absent\n' "$LIVE_BINDINGS"; fi
}
LIVE_BEFORE=$(live_snapshot)

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-team.XXXXXX") || exit 1
TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)
trap 'rm -rf "$TMP_ROOT"' EXIT

CFG="$TMP_ROOT/cfg"
mkdir -p "$CFG/bin"
cp "$CONFIG_ROOT/bin/fm-team" "$CFG/bin/fm-team" 2>/dev/null
cp -R "$CONFIG_ROOT/roles" "$CONFIG_ROOT/skills" "$CONFIG_ROOT/extensions" "$CFG/"
cp -R "$CONFIG_ROOT/teams" "$CFG/teams" 2>/dev/null || mkdir -p "$CFG/teams"
# Test-only role fixtures, written into this disposable copy only and never
# installed: a lead whose spawns list names four members that differ only in
# how they declare their own spawns, so the helper upper bound is judged on
# each declaration shape without granting any real role a new right.
fixture_role() {  # <role> <frontmatter lines...>
  local dir="$CFG/roles/$1"
  shift
  mkdir -p "$dir"
  { printf -- '---\nname: fm-%s\ndescription: "Test-only fixture role; never installed."\n' "${dir##*/}"
    printf '%s\n' "$@"; printf -- '---\nTest-only fixture.\n'; } > "$dir/ROLE.md"
}
fixture_role fixture-lead 'spawns:' '  - fm-fixture-listed' '  - fm-fixture-wild' '  - fm-fixture-empty' '  - fm-fixture-tasker'
fixture_role fixture-listed 'spawns:' '  - scout'
fixture_role fixture-wild 'spawns: "*"'
fixture_role fixture-empty 'spawns: []'
fixture_role fixture-tasker 'tools: [read, write, task]'
FMT="$CFG/bin/fm-team"
export FM_HOME="$TMP_ROOT/fm-home"
export FM_OMP_EXTENSIONS_ROOT="$TMP_ROOT/omp-extensions"
mkdir -p "$FM_HOME/data" "$FM_HOME/state"

# A valid profile written by hand (not read from teams/), so the validator is
# judged against a fixture whose verdict is known independently.
BASE="$TMP_ROOT/base.json"
cat > "$BASE" <<'JSON'
{
  "schema": "fm-team-profile.v1",
  "name": "web-feature",
  "description": "fixture",
  "lead": "fm-team-lead",
  "members": [
    {"agent": "fm-product-owner", "mode": "read-only"},
    {"agent": "fm-architecture", "mode": "read-only"},
    {"agent": "fm-backend-contract", "mode": "read-only"},
    {"agent": "fm-django-pro", "mode": "mutating", "paths": {"write": ["apps/api/**"]}, "talk_to": ["fm-frontend-master"]},
    {"agent": "fm-frontend-master", "mode": "mutating", "paths": {"write": ["apps/web/**", "README.md"]}, "talk_to": ["fm-django-pro"]},
    {"agent": "fm-qa", "mode": "read-only"},
    {"agent": "fm-code-reviewer", "mode": "read-only"}
  ],
  "workflow": {
    "phases": [
      {"name": "planning", "members": ["fm-product-owner", "fm-architecture", "fm-backend-contract"]},
      {"name": "implement", "members": ["fm-django-pro", "fm-frontend-master"]},
      {"name": "verify", "members": ["fm-qa", "fm-code-reviewer"]}
    ],
    "max_rework_rounds": 2
  },
  "ops": {"commit": "request", "push": "none", "merge": "none"}
}
JSON

# variant <file> <python statements on p>: BASE with one mutation applied.
variant() {
  python3 - "$BASE" "$1" "$2" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
m = {a["agent"]: a for a in p["members"]}
exec(sys.argv[3])
json.dump(p, open(sys.argv[2], "w"))
PY
}
# refuses <label> <code> <python statements>: the mutated profile is refused
# with that code, and only after the base profile itself passed.
refuses() {
  local f="$TMP_ROOT/v-$RANDOM$RANDOM.json" out rc
  variant "$f" "$3"
  out=$("$FMT" validate "$f" 2>&1); rc=$?
  if [ "$rc" -ne 0 ] && case $out in *"refused ($2)"*) true ;; *) false ;; esac; then
    pass "$1"
  else
    fail "$1 (expected refused ($2), rc=$rc: $out)"
  fi
}

# --- 1. validation -----------------------------------------------------------
out=$("$FMT" validate "$BASE" 2>&1)
check '1 a valid profile passes' "$?" 0
contains '1 a valid profile reports its member count' "$out" '7 member(s)'

printf 'not json' > "$TMP_ROOT/garbage.json"
out=$("$FMT" validate "$TMP_ROOT/garbage.json" 2>&1)
contains '1 unparseable JSON is refused' "$out" 'refused (unreadable)'

refuses '1 unknown top-level key' unknown-key 'p["extra"] = 1'
refuses '1 unknown member key' unknown-key 'm["fm-qa"]["color"] = "red"'
refuses '1 unknown schema' bad-schema 'p["schema"] = "fm-team-profile.v2"'
refuses '1 unknown agent' unknown-agent 'm["fm-qa"]["agent"] = "fm-ghost"; p["workflow"]["phases"][2]["members"] = ["fm-ghost", "fm-code-reviewer"]'
refuses '1 a real role outside the lead spawns upper bound' exceeds-native-spawns \
  'm["fm-qa"]["agent"] = "fm-security-engineer"; p["workflow"]["phases"][2]["members"] = ["fm-security-engineer", "fm-code-reviewer"]'
refuses '1 duplicate member' duplicate-member 'p["members"].append(dict(m["fm-qa"]))'
refuses '1 lead that is not a role' unknown-agent 'p["lead"] = "fm-ghost-lead"'
refuses '1 lead role without a spawns list' bad-lead 'p["lead"] = "fm-senior-fullstack"'
refuses '1 unknown mode (unknown right)' bad-mode 'm["fm-qa"]["mode"] = "admin"'
refuses '1 mutating member whose role has no native write tool' exceeds-native-tools \
  'm["fm-qa"]["mode"] = "mutating"; m["fm-qa"]["paths"] = {"write": ["tests/**"]}'
refuses '1 write paths on a read-only member' write-paths-on-read-only 'm["fm-code-reviewer"]["paths"] = {"write": ["docs/**"]}'
refuses '1 mutating member without write paths' missing-write-paths 'del m["fm-django-pro"]["paths"]'
refuses '1 unknown paths key' unknown-key 'm["fm-django-pro"]["paths"]["read"] = ["**"]'
refuses '1 write paths overlapping another member' overlapping-write-paths 'm["fm-frontend-master"]["paths"]["write"] = ["apps/**"]'
refuses '1 the same file owned twice' overlapping-write-paths 'm["fm-django-pro"]["paths"]["write"].append("README.md")'
refuses '1 path traversal in a write glob' bad-path 'm["fm-django-pro"]["paths"]["write"] = ["apps/../../etc/**"]'
refuses '1 absolute write glob' bad-path 'm["fm-django-pro"]["paths"]["write"] = ["/etc/**"]'
refuses '1 unsupported glob syntax' bad-path 'm["fm-django-pro"]["paths"]["write"] = ["apps/{api,web}/**"]'
refuses '1 home-relative write glob' bad-path 'm["fm-django-pro"]["paths"]["write"] = ["~/notes/**"]'
refuses '1 recipient that is not a member' unknown-recipient 'm["fm-django-pro"]["talk_to"] = ["fm-senior-fullstack"]'
refuses '1 agent://all recipient' unknown-recipient 'm["fm-django-pro"]["talk_to"] = ["agent://all"]'
refuses '1 all recipient' unknown-recipient 'm["fm-django-pro"]["talk_to"] = ["all"]'
refuses '1 recipients for a role without a native write tool' exceeds-native-tools 'm["fm-qa"]["talk_to"] = ["fm-django-pro"]'
refuses '1 helper spawn for a role whose tools exclude task' exceeds-native-spawns 'm["fm-architecture"]["spawn"] = ["scout"]'
refuses '1 helper spawn naming no agent' unknown-agent 'm["fm-django-pro"]["spawn"] = ["fm-ghost"]'
refuses '1 extra skill not managed by this repository' unmanaged-skill 'm["fm-django-pro"]["skills"] = ["not-a-skill"]'
refuses '1 extra skills over the per-task budget' skill-budget 'm["fm-frontend-master"]["skills"] = ["test-driven-development", "ponytail"]'
refuses '1 phase naming a non-member' unknown-member 'p["workflow"]["phases"][0]["members"].append("fm-senior-fullstack")'
refuses '1 member in no phase' unphased-member 'p["workflow"]["phases"][2]["members"] = ["fm-qa"]'
refuses '1 duplicate phase name' bad-workflow 'p["workflow"]["phases"][1]["name"] = "planning"'
refuses '1 more rework rounds than the role policy allows' bad-rework-rounds 'p["workflow"]["max_rework_rounds"] = 3'
refuses '1 merge right other than none' op-not-allowed 'p["ops"]["merge"] = "allowed"'
refuses '1 push right other than none' op-not-allowed 'p["ops"]["push"] = "request"'
refuses '1 commit right other than none/request' op-not-allowed 'p["ops"]["commit"] = "allowed"'
refuses '1 unknown right' unknown-right 'p["ops"]["deploy"] = "none"'
refuses '1 missing right' unknown-right 'del p["ops"]["merge"]'

variant "$TMP_ROOT/skill-ok.json" 'm["fm-django-pro"]["skills"] = ["test-driven-development"]'
"$FMT" validate "$TMP_ROOT/skill-ok.json" >/dev/null 2>&1
check '1 one extra managed skill within the budget passes' "$?" 0

# A member role that declares no spawns cannot start a helper at all: the
# native trial recorded OMP refusing exactly this profile right
# (native-trial-report.md section 5, fm-django-pro spawning task:
# "Cannot spawn 'task'. Allowed: none (spawns disabled for this agent)").
refuses '1 helper spawn for a member role that declares no spawns (OMP disables it)' exceeds-native-spawns 'm["fm-django-pro"]["spawn"] = ["task"]'
helper_bound() {  # <label> <member agent> <spawn JSON list> <ok|refusal code>
  local f="$TMP_ROOT/h-$RANDOM$RANDOM.json" out rc
  python3 - "$f" "$2" "$3" <<'PY'
import json, sys
f, agent, spawn = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
json.dump({"schema": "fm-team-profile.v1", "name": "fixture-host", "lead": "fm-fixture-lead",
           "members": [{"agent": agent, "mode": "read-only", "spawn": spawn}],
           "workflow": {"phases": [{"name": "all", "members": [agent]}], "max_rework_rounds": 0},
           "ops": {"commit": "none", "push": "none", "merge": "none"}}, open(f, "w"))
PY
  out=$("$FMT" validate "$f" 2>&1); rc=$?
  if [ "$4" = ok ]; then check "$1" "$rc" 0
  elif [ "$rc" -ne 0 ] && case $out in *"refused ($4)"*) true ;; *) false ;; esac; then pass "$1"
  else fail "$1 (expected refused ($4), rc=$rc: $out)"; fi
}
helper_bound '1 counterfactual: a declared spawns list allows its helper' fm-fixture-listed '["scout"]' ok
helper_bound '1 a declared spawns list still bounds the helper' fm-fixture-listed '["task"]' exceeds-native-spawns
helper_bound '1 a declared spawns wildcard allows any known helper' fm-fixture-wild '["task"]' ok
helper_bound '1 a declared empty spawns list allows no helper' fm-fixture-empty '["scout"]' exceeds-native-spawns
helper_bound '1 tools including task without declared spawns grant no helper' fm-fixture-tasker '["scout"]' exceeds-native-spawns

variant "$TMP_ROOT/multi.json" 'p["extra"] = 1; p["ops"]["merge"] = "allowed"'
out=$("$FMT" validate "$TMP_ROOT/multi.json" 2>&1)
contains '1 every refusal is reported, not only the first (unknown key)' "$out" 'refused (unknown-key)'
contains '1 every refusal is reported, not only the first (merge)' "$out" 'refused (op-not-allowed)'

for f in "$CONFIG_ROOT"/teams/*.json; do
  [ -f "$f" ] || continue
  "$FMT" validate "$f" >/dev/null 2>&1
  check "1 tracked example $(basename "$f") validates" "$?" 0
done

# --- 2. binding and resolution -------------------------------------------------
# The fixture teams/ holds two hand-written profiles; roles/ are the real ones.
cp "$BASE" "$CFG/teams/web-feature.json"
variant "$CFG/teams/docs-only.json" 'p["name"] = "docs-only"; p["members"] = [dict(m["fm-frontend-master"], paths={"write": ["docs/**"]}, talk_to=[]), m["fm-code-reviewer"]]; p["workflow"]["phases"] = [{"name": "write", "members": ["fm-frontend-master"]}, {"name": "review", "members": ["fm-code-reviewer"]}]; p["ops"]["commit"] = "none"'
BIND="$FM_HOME/data/team-bindings"
BASE_SHA=0123456789abcdef0123456789abcdef01234567
roles_hash() { (cd "$CFG/roles" && shasum -a 256 */ROLE.md); }
ROLES_BEFORE=$(roles_hash)
AGENTS_FX="$TMP_ROOT/omp-agents"   # an installed OMP agent root, as install.sh links it
mkdir -p "$AGENTS_FX"
for r in "$CFG"/roles/*/ROLE.md; do ln -s "$r" "$AGENTS_FX/fm-$(basename "$(dirname "$r")").md"; done
AGENTS_BEFORE=$(cd "$AGENTS_FX" && for e in *; do printf '%s -> %s\n' "$e" "$(readlink "$e")"; done; cat ./*)
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"; }

out=$("$FMT" bind task-a --profile web-feature --base "$BASE_SHA" 2>&1)
check '2 bind exits 0' "$?" 0
contains '2 bind warns that an unlinked policy extension leaves the task audit-only' "$out" 'policy extension is not linked'
check '2 the snapshot is the profile byte for byte' "$(shasum -a 256 < "$BIND/task-a.profile.json")" "$(shasum -a 256 < "$CFG/teams/web-feature.json")"
check '2 the binding records the snapshot sha256' "$(field "$BIND/task-a.json" profile_sha256)" "$(shasum -a 256 < "$CFG/teams/web-feature.json" | cut -d' ' -f1)"
check '2 the binding records the base commit' "$(field "$BIND/task-a.json" base)" "$BASE_SHA"
check '2 the binding records the profile name' "$(field "$BIND/task-a.json" profile)" web-feature
check '2 an untracked profile has no approved commit' "$(field "$BIND/task-a.json" profile_commit)" None
check '2 binding files are private' "$(stat -f '%Lp' "$BIND/task-a.json" 2>/dev/null || stat -c '%a' "$BIND/task-a.json")" 600
out=$("$FMT" check task-a 2>&1)
check '2 check of a bound task exits 0' "$?" 0
contains '2 check reports the team and its profile' "$out" 'team: task-a profile=web-feature'

mkdir -p "$FM_OMP_EXTENSIONS_ROOT"
ln -s "$CFG/extensions/fm-team-policy.ts" "$FM_OMP_EXTENSIONS_ROOT/fm-team-policy.ts"
out=$("$FMT" bind task-b --profile docs-only --base "$BASE_SHA" 2>&1)
not_contains '2 bind does not warn once this checkout'"'"'s extension is linked' "$out" 'policy extension is not linked'
check '2 a second task binds its own profile' "$(field "$BIND/task-b.json" profile)" docs-only
check '2 binding a second task leaves the first snapshot alone' "$(shasum -a 256 < "$BIND/task-a.profile.json")" "$(shasum -a 256 < "$CFG/teams/web-feature.json")"
contains '2 the first task still resolves to its own profile' "$("$FMT" check task-a 2>&1)" 'profile=web-feature'
check '2 global role files are byte-identical after validate and bind' "$(roles_hash)" "$ROLES_BEFORE"
check '2 installed role agent links and content are unchanged' "$(cd "$AGENTS_FX" && for e in *; do printf '%s -> %s\n' "$e" "$(readlink "$e")"; done; cat ./*)" "$AGENTS_BEFORE"

bind_refuses() {  # <label> <code> <bind args...>
  local label=$1 code=$2 out rc before
  shift 2
  before=$(ls -A "$BIND" 2>/dev/null)
  out=$("$FMT" bind "$@" 2>&1); rc=$?
  if [ "$rc" -ne 0 ] && case $out in *"refused ($code)"*) true ;; *) false ;; esac; then pass "$label"
  else fail "$label (expected refused ($code), rc=$rc: $out)"; fi
  check "$label: nothing written" "$(ls -A "$BIND" 2>/dev/null)" "$before"
}
bind_refuses '2 a task id with a path separator' bad-task '../escape' --profile web-feature --base "$BASE_SHA"
bind_refuses '2 a profile name that traverses out of teams/' bad-profile task-c --profile ../roles/qa/ROLE --base "$BASE_SHA"
bind_refuses '2 a profile that does not exist' bad-profile task-c --profile ghost --base "$BASE_SHA"
bind_refuses '2 a base that is not a commit id' bad-base task-c --profile web-feature --base 'HEAD~1'
bind_refuses '2 an already bound task' already-bound task-a --profile docs-only --base "$BASE_SHA"
variant "$CFG/teams/broken.json" 'p["name"] = "broken"; p["ops"]["merge"] = "allowed"'
bind_refuses '2 an invalid profile is refused with the validator code' op-not-allowed task-c --profile broken --base "$BASE_SHA"
cp "$CFG/teams/web-feature.json" "$CFG/teams/renamed.json"
bind_refuses '2 a profile whose name differs from its file' bad-profile task-c --profile renamed --base "$BASE_SHA"
ln -s "$CFG/teams/web-feature.json" "$CFG/teams/linked.json"
bind_refuses '2 a symlinked profile' bad-profile task-c --profile linked --base "$BASE_SHA"
rm -f "$CFG/teams/broken.json" "$CFG/teams/renamed.json" "$CFG/teams/linked.json"

# Resolution: a genuine non-team task, a team task whose brief names a profile
# but whose binding is gone, and each way the bound snapshot can go wrong.
check_refuses() {  # <label> <code> <task>
  local out rc
  out=$("$FMT" check "$3" 2>&1); rc=$?
  if [ "$rc" -ne 0 ] && case $out in *"refused ($2)"*) true ;; *) false ;; esac; then pass "$1"
  else fail "$1 (expected refused ($2), rc=$rc: $out)"; fi
}
out=$("$FMT" check plain-task 2>&1)
check '2 a task with no binding and no team brief is not a team: exit 0' "$?" 0
contains '2 a task with no binding and no team brief is reported none' "$out" 'none: plain-task'
mkdir -p "$FM_HOME/data/lost-task"
printf '# Task\nRole: team-lead\nTeam profile: web-feature\n' > "$FM_HOME/data/lost-task/brief.md"
check_refuses '2 a team brief without a binding' team-binding-missing lost-task
mkdir -p "$FM_HOME/data/task-a"
printf 'Team profile: docs-only\n' > "$FM_HOME/data/task-a/brief.md"
check_refuses '2 a brief naming a different profile than the binding' team-binding-mismatch task-a
printf 'Team profile: web-feature\n' > "$FM_HOME/data/task-a/brief.md"
contains '2 a brief naming the bound profile resolves' "$("$FMT" check task-a 2>&1)" 'team: task-a'

for t in t-missing t-tampered t-corrupt t-badbind t-wrongtask t-linkbind; do
  "$FMT" bind "$t" --profile web-feature --base "$BASE_SHA" >/dev/null 2>&1
done
rm "$BIND/t-missing.profile.json"
check_refuses '2 a deleted snapshot' team-profile-missing t-missing
printf ' ' >> "$BIND/t-tampered.profile.json"
check_refuses '2 an edited snapshot (hash mismatch)' team-profile-tampered t-tampered
printf '{"schema": "fm-team-profile.v1"}' > "$BIND/t-corrupt.profile.json"
python3 - "$BIND/t-corrupt.json" "$(shasum -a 256 < "$BIND/t-corrupt.profile.json" | cut -d' ' -f1)" <<'PY'
import json, sys
b = json.load(open(sys.argv[1])); b["profile_sha256"] = sys.argv[2]; json.dump(b, open(sys.argv[1], "w"))
PY
check_refuses '2 a snapshot whose hash matches but which no longer validates' team-profile-corrupt t-corrupt
printf 'not json' > "$BIND/t-badbind.json"
check_refuses '2 an unreadable binding' team-binding-corrupt t-badbind
python3 - "$BIND/t-wrongtask.json" <<'PY'
import json, sys
b = json.load(open(sys.argv[1])); b["task"] = "task-a"; json.dump(b, open(sys.argv[1], "w"))
PY
check_refuses '2 a binding copied from another task' team-binding-mismatch t-wrongtask
mv "$BIND/t-linkbind.json" "$TMP_ROOT/t-linkbind.json" && ln -s "$TMP_ROOT/t-linkbind.json" "$BIND/t-linkbind.json"
check_refuses '2 a symlinked binding' team-binding-corrupt t-linkbind

# A later narrowing of a global role invalidates a bound profile at relaunch.
cp "$CFG/roles/team-lead/ROLE.md" "$TMP_ROOT/team-lead.ROLE.md"
grep -v '  - fm-django-pro' "$TMP_ROOT/team-lead.ROLE.md" > "$CFG/roles/team-lead/ROLE.md"
check_refuses '2 a role narrowed after binding fails the relaunch check' team-profile-corrupt task-a
cp "$TMP_ROOT/team-lead.ROLE.md" "$CFG/roles/team-lead/ROLE.md"

# The approved commit is recorded only for a tracked, unmodified profile.
git -C "$CFG" init -q && git -C "$CFG" add teams roles && \
  git -C "$CFG" -c user.name=t -c user.email=t@t commit -qm fixture
"$FMT" bind t-tracked --profile web-feature --base "$BASE_SHA" >/dev/null 2>&1
check '2 a tracked clean profile records its commit' "$(field "$BIND/t-tracked.json" profile_commit)" "$(git -C "$CFG" log -1 --format=%H -- teams/web-feature.json)"
printf '\n' >> "$CFG/teams/web-feature.json"
"$FMT" bind t-dirty --profile web-feature --base "$BASE_SHA" >/dev/null 2>&1
check '2 a locally modified profile records no commit' "$(field "$BIND/t-dirty.json" profile_commit)" None
git -C "$CFG" checkout -q -- teams/web-feature.json

# --- 3. delivery audit ----------------------------------------------------------
# Scope of the bound fixture profile: apps/api/** (django-pro) plus
# apps/web/** and README.md (frontend-master). Each case is a fresh copy of
# one template repository with exactly one kind of change.
G() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
TPL="$TMP_ROOT/tpl"
mkdir -p "$TPL/apps/api" "$TPL/apps/web" "$TPL/other"
printf 'a\n' > "$TPL/apps/api/a.py"; printf 'r\n' > "$TPL/apps/api/ren.py"
printf 'b\n' > "$TPL/apps/web/b.js"; printf 'readme\n' > "$TPL/README.md"
printf 'old\n' > "$TPL/old.txt"; printf 'keep\n' > "$TPL/other/keep.txt"
G "$TPL" init -q && G "$TPL" add -A && G "$TPL" commit -qm base
TPL_BASE=$(G "$TPL" rev-parse HEAD)
n=0
case_repo() {  # <shell commands run inside a fresh copy>; sets $task
  n=$((n + 1))
  task="audit-$n"
  local repo="$TMP_ROOT/case-$n"
  cp -R "$TPL" "$repo"
  (cd "$repo" && eval "$1") >/dev/null 2>&1
  "$FMT" bind "$task" --profile web-feature --base "$TPL_BASE" >/dev/null 2>&1
  printf 'worktree=%s\n' "$repo" > "$FM_HOME/state/$task.meta"
}
audit_refuses() {  # <label> <expected line fragment> <commands>
  local out rc
  case_repo "$3"
  out=$("$FMT" audit "$task" 2>&1); rc=$?
  if [ "$rc" -eq 1 ] && case $out in *"$2"*) true ;; *) false ;; esac; then pass "$1"
  else fail "$1 (expected rc 1 with '$2', rc=$rc: $out)"; fi
}
GC='git -c user.name=t -c user.email=t@t'

case_repo "printf 'a2\n' >> apps/api/a.py && $GC commit -qam c1
  printf 'n\n' > apps/web/new.js && git add apps/web/new.js
  printf 'more\n' >> README.md
  printf 'u\n' > 'apps/api/sp ace.py'
  git mv apps/api/ren.py apps/api/ren2.py
  rm apps/web/b.js
  ln -s ../web/new.js apps/api/link"
out=$("$FMT" audit "$task" 2>&1)
check '3 an all-in-scope candidate passes' "$?" 0
contains '3 binding identity is reported' "$out" "binding: $task profile=web-feature"
contains '3 committed change listed' "$out" 'ok committed:modified apps/api/a.py'
contains '3 staged addition listed' "$out" 'ok staged:added apps/web/new.js'
contains '3 unstaged change listed' "$out" 'ok unstaged:modified README.md'
contains '3 untracked file with a space listed' "$out" 'ok untracked:added apps/api/sp ace.py'
contains '3 rename source listed' "$out" 'ok staged:renamed-from apps/api/ren.py'
contains '3 rename target listed' "$out" 'ok staged:renamed-to apps/api/ren2.py'
contains '3 unstaged deletion listed' "$out" 'ok unstaged:deleted apps/web/b.js'
contains '3 an in-worktree symlink inside scope passes' "$out" 'ok untracked:added apps/api/link'
contains '3 summary counts every path' "$out" 'audit: 8 path(s), 0 refused'
contains '3 the report states the attribution limit' "$out" 'team-level final-tree scope only; no per-member attribution'

audit_refuses '3 committed change outside scope' 'refused committed:modified other/keep.txt (path-outside-scope)' \
  "printf x >> other/keep.txt && $GC commit -qam out"
audit_refuses '3 staged addition outside scope' 'refused staged:added other/new.txt (path-outside-scope)' \
  "printf n > other/new.txt && git add other/new.txt"
audit_refuses '3 unstaged change outside scope' 'refused unstaged:modified other/keep.txt (path-outside-scope)' \
  "printf x >> other/keep.txt"
audit_refuses '3 untracked file outside scope' 'refused untracked:added other/a b.txt (path-outside-scope)' \
  "printf n > 'other/a b.txt'"
audit_refuses '3 deletion outside scope' 'refused unstaged:deleted old.txt (path-outside-scope)' \
  "rm old.txt"
audit_refuses '3 staged deletion outside scope' 'refused staged:deleted old.txt (path-outside-scope)' \
  "git rm -q old.txt"
audit_refuses '3 rename out of scope into scope: the old path' 'refused staged:renamed-from old.txt (path-outside-scope)' \
  "git mv old.txt apps/api/old.txt"
audit_refuses '3 rename from scope to outside: the new path' 'refused staged:renamed-to other/ren.py (path-outside-scope)' \
  "git mv apps/api/ren.py other/ren.py"
audit_refuses '3 committed rename out of scope' 'refused committed:renamed-from old.txt (path-outside-scope)' \
  "git mv old.txt apps/web/old.txt && $GC commit -qm mv"
audit_refuses '3 untracked symlink to outside the worktree' 'refused untracked:added apps/api/evil (symlink-outside-worktree)' \
  "ln -s /etc/hosts apps/api/evil"
audit_refuses '3 committed symlink escaping the worktree' 'refused committed:added apps/api/up (symlink-outside-worktree)' \
  "ln -s ../../.. apps/api/up && git add apps/api/up && $GC commit -qm up && rm apps/api/up && git checkout -q -- apps/api/up"
audit_refuses '3 staged gitlink (submodule) inside scope' 'refused staged:added apps/api/sub (gitlink-change)' \
  "git update-index --add --cacheinfo 160000,$TPL_BASE,apps/api/sub"
audit_refuses '3 an out-of-scope file with a newline in its name, shown escaped' 'refused untracked:added "other/new\nline" (path-outside-scope)' \
  "printf n > \$'other/new\\nline'"

case_repo "printf x >> other/keep.txt"
printf ' ' >> "$BIND/$task.profile.json"
out=$("$FMT" audit "$task" 2>&1)
check '3 a tampered binding refuses the audit: exit 1' "$?" 1
contains '3 a tampered binding refuses the audit with its code' "$out" 'refused (team-profile-tampered)'
not_contains '3 a refused binding lists no paths' "$out" 'other/keep.txt'
out=$("$FMT" audit plain-task --worktree "$TPL" 2>&1)
check '3 auditing a non-team task is refused: exit 1' "$?" 1
contains '3 auditing a non-team task is refused with its code' "$out" 'refused (not-a-team-task)'
case_repo ":"
out=$("$FMT" audit "$task" --worktree "$TPL/apps" 2>&1)
contains '3 a worktree that is not a repository top level is refused' "$out" 'refused (bad-worktree)'
rm "$FM_HOME/state/$task.meta"
out=$("$FMT" audit "$task" 2>&1)
contains '3 no --worktree and no task meta is refused' "$out" 'refused (bad-worktree)'
"$FMT" bind audit-nobase --profile web-feature --base 1234567 >/dev/null 2>&1
out=$("$FMT" audit audit-nobase --worktree "$TPL" 2>&1)
contains '3 a base commit absent from the worktree is refused' "$out" 'refused (bad-base)'

# --- 9. no live writes -------------------------------------------------------
check '9 live team-bindings directory unchanged' "$(live_snapshot)" "$LIVE_BEFORE"

exit "$failed"
