#!/usr/bin/env bash
# Run the real installer only inside an offline disposable HOME/config tree.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/cfg/bin" "$TMP/cfg/firstmate" "$TMP/bin" "$TMP/source"
cp "$ROOT/install.sh" "$TMP/cfg/"
cp "$ROOT/firstmate/"{fm-stack-manifest.sh,stack-manifest.tsv,crew-dispatch.json,captain.md} "$TMP/cfg/firstmate/"
cp -R "$ROOT/roles" "$ROOT/skills" "$ROOT/commands" "$TMP/cfg/"
rm "$TMP/cfg/skills/external.lock"
touch "$TMP/cfg/bin/fm" "$TMP/cfg/bin/ponytail-update" "$TMP/source/AGENTS.md"
for t in pi omp herdr; do printf '#!/bin/sh\nexit 99\n' > "$TMP/bin/$t"; chmod +x "$TMP/bin/$t"; done
run() {
  HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" FIRSTMATE_ROOT="$TMP/source" FM_HOME="$TMP/home/.firstmate" \
    FM_CONFIG_ENV="$TMP/home/env" FM_SKILLS_ROOT="$TMP/home/.agents/skills" FM_COMMANDS_ROOT="$TMP/home/.agents/commands" \
    FM_OMP_AGENTS_ROOT="$TMP/home/.omp/agent/agents" FM_SKILL_CACHE="$TMP/home/cache" FM_BIN_DIR="$TMP/home/bin" \
    bash "$TMP/cfg/install.sh" "$@"
}
mkdir -p "$TMP/home/.firstmate/config"
link="$TMP/home/.firstmate/config/workflows.md"
ln -s "$TMP/cfg/firstmate/workflows.md" "$link"
out=$(run --verify)
[ -L "$link" ]
case $out in *'DRIFT   remove obsolete managed workflow link'*) ;; *) printf 'FAIL - verify did not report legacy link\n'; exit 1 ;; esac
run >/dev/null
[ ! -L "$link" ]
# No invented broad deletion: same-name user files and foreign links survive.
printf 'user recipe\n' > "$link"
out=$(run)
[ "$(cat "$link")" = 'user recipe' ]
case $out in *'leaving it alone; inspect and remove obsolete workflow references manually'*) ;; *) exit 1 ;; esac
out2=$(run)
case $out2 in *'install: 0 change(s), 0 failure(s)'*) ;; *) printf '%s\n' "$out2"; exit 1 ;; esac
rm "$link"
ln -s "$TMP/user-workflows.md" "$link"
run >/dev/null
[ "$(readlink "$link")" = "$TMP/user-workflows.md" ]
rm "$link"
# Relative links to the exact removed managed source are also retired.
ln -s ../../../cfg/firstmate/workflows.md "$link"
run >/dev/null
[ ! -L "$link" ]
printf 'my edited catalogue\n' > "$TMP/cfg/firstmate/workflows.md"
printf 'Read firstmate/workflows.md and print Workflow: legacy\n' > "$TMP/home/.firstmate/data/captain.md"
out=$(run)
[ "$(cat "$TMP/cfg/firstmate/workflows.md")" = 'my edited catalogue' ]
[ "$(cat "$TMP/home/.firstmate/data/captain.md")" = 'Read firstmate/workflows.md and print Workflow: legacy' ]
case $out in *'captain.md still references the removed config workflow layer'*) ;; *) printf 'FAIL - missing actionable captain preference diagnostic\n'; exit 1 ;; esac
for role in "$ROOT"/roles/*/ROLE.md; do
  name=$(basename "$(dirname "$role")")
  cmp "$role" "$TMP/home/.omp/agent/agents/fm-$name.md"
done
cmp "$ROOT/skills/bot-builder/SKILL.md" "$TMP/home/.agents/skills/bot-builder/SKILL.md"
cmp "$ROOT/commands/bots.md" "$TMP/home/.agents/commands/bots.md"
cmp "$ROOT/skills/django-backend/SKILL.md" "$TMP/home/.agents/skills/django-backend/SKILL.md"
out=$(run --verify)
case $out in *'verify: 0 drift item(s), 0 failure(s)'*) ;; *) printf '%s\n' "$out"; exit 1 ;; esac
printf 'PASS - exact obsolete links retired; unknown content preserved; idempotent; all roles, bot skill/command and role default skill retained\n'
