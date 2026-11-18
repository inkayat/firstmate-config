#!/usr/bin/env bash
# install-launch.sh - install.sh and `fm` against a synthetic
# HOME: what a fresh machine gets, what it must not get, idempotent reconcile,
# foreign-link refusal, and a Captain launch from an unrelated directory.
# shellcheck source=tests/fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixture.sh"

target() { (cd "$(dirname "$1")" && cd -P "$(dirname "$(readlink "$1")")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$(readlink "$1")")"); }

# --- fresh install ------------------------------------------------------------
install_world; status=$?
check 'fresh install succeeds' "$status" 0
has 'fresh install reports no failure' "$(cat "$T/install.out")" 'install: '
check 'official FirstMate cloned from the manifest origin' "$(git -C "$OFFICIAL" remote get-url origin)" "$OFFICIAL_REMOTE"
check 'official checkout is on main' "$(git -C "$OFFICIAL" symbolic-ref --short HEAD)" main
check 'official main tracks origin/main' "$(git -C "$OFFICIAL" rev-parse --abbrev-ref '@{upstream}')" origin/main
has 'env file points the config root at standalone config' "$(cat "$HOME/.config/firstmate-config/env")" "FM_CONFIG_ROOT=\"$FMC\""
check 'fm launcher links into standalone config' "$(target "$HOME/.local/bin/fm")" "$FMC/bin/fm"
check 'routing profile links into standalone config' "$(target "$FMHOME/config/crew-dispatch.json")" "$FMC/firstmate/crew-dispatch.json"
check 'role agent links into standalone config' "$(target "$HOME/.omp/agent/agents/fm-senior-fullstack.md")" "$FMC/roles/senior-fullstack/ROLE.md"
check 'config-owned shared skill links into standalone config' "$(target "$HOME/.agents/skills/architecture-review")" "$FMC/skills/architecture-review"
check 'pinned external skill is linked' "$(cat "$HOME/.agents/skills/demo-method/SKILL.md" | tail -1)" 'Read ../../references/checklist.md'
check 'external skill ancestor reference resolves from the shared root' \
  "$(cat "$HOME/.agents/skills/demo-method/../../references/checklist.md" 2>&1)" checklist
check 'runtime backend is herdr' "$(cat "$FMHOME/config/backend")" herdr
has 'captain file seeded with the policy pointer' "$(cat "$FMHOME/data/captain.md")" '$FM_CONFIG_ROOT/firstmate/primary-policy.md'
check 'install never drives herdr (no root Herdr installer)' "$(cat "$HERDR_LOG" 2>/dev/null)" ''

# --- removed personal additions ----------------------------------------------
for gone in "$HOME/.local/bin/ponytail-update" "$HOME/.agents/commands/bots.md" "$HOME/.agents/skills/bot-builder" "$HOME/.agents/commands/tlw.md" "$HOME/.pi/agent/prompts/tlw.md"; do
  check "not installed: ${gone#"$HOME"/}" "$([ -e "$gone" ] || [ -L "$gone" ] && printf present || printf absent)" absent
done
for sub in board bot doctor version; do
  out=$("$HOME/.local/bin/fm" "$sub" 2>&1); status=$?
  check "fm $sub is not a command" "$status" 1
  has "fm $sub is rejected as unknown" "$out" "unknown argument '$sub'"
done

# --- idempotent reconcile ------------------------------------------------------
check 'second install changes nothing' "$("$FMC/install.sh" 2>&1 | tail -1)" 'install: 0 change(s), 0 failure(s)'
check 'verify reports no drift' "$("$FMC/install.sh" --verify 2>&1 | tail -1)" 'verify: 0 drift item(s), 0 failure(s)'

# --- captain file is machine-owned ---------------------------------------------
printf 'my own preferences\n' > "$FMHOME/data/captain.md"
"$FMC/install.sh" > /dev/null 2>&1
check 'existing captain file is never overwritten' "$(cat "$FMHOME/data/captain.md")" 'my own preferences'

# --- launch from an unrelated project directory ---------------------------------
project="$T/some-project"
git init -q "$project/repo" && mkdir -p "$project/repo/sub"
(cd "$project/repo/sub" && CLAUDECODE=1 "$HOME/.local/bin/fm" > "$T/launch.out" 2>&1); status=$?
check 'fm launches from another directory' "$status" 0
log=$(cat "$HARNESS_LOG")
has 'Captain runs in the official checkout' "$log" "cwd=$(cd "$OFFICIAL" && pwd -P)"
has 'Captain defaults to Pi' "$log" 'bin=pi'
has 'Captain gets the config root in standalone config' "$log" "FM_CONFIG_ROOT=$FMC"
has 'launch directory passes through as a hint' "$log" "FM_FORK_ORIGIN_CWD=$project/repo/sub"
has 'launch directory is recognized as a Git project' "$log" 'FM_FORK_ORIGIN_IS_PROJECT=true'
has 'operational home is passed' "$log" "FM_HOME=$FMHOME"
has 'startup model chain is applied' "$log" 'args=--model openai-codex/gpt-6.2-sol --thinking medium'
has 'parent harness markers are scrubbed' "$log" 'CLAUDECODE=unset'
policy=$(sed -n 's/^FM_CONFIG_ROOT=//p' "$HARNESS_LOG")
check 'captain policy pointer resolves for the launched Captain' "$([ -f "$policy/firstmate/primary-policy.md" ] && printf yes)" yes
check 'captain role pointer resolves for the launched Captain' "$([ -f "$policy/roles/senior-fullstack/ROLE.md" ] && printf yes)" yes

(cd "$T" && "$HOME/.local/bin/fm" --harness omp > /dev/null 2>&1)
log=$(cat "$HARNESS_LOG")
has 'explicit OMP harness is honored' "$log" 'bin=omp'
has 'OMP Captain is marked for FirstMate' "$log" 'FM_OMP_HARNESS=omp'
has 'non-project launch directory is only a hint' "$log" 'FM_FORK_ORIGIN_IS_PROJECT=false'

# --- foreign links are refused, never rewritten ----------------------------------
rm "$HOME/.local/bin/fm"
ln -s "$T/old-config/bin/fm" "$HOME/.local/bin/fm"
out=$("$FMC/install.sh" 2>&1); status=$?
check 'install fails on a foreign fm link' "$status" 1
has 'install names the foreign link' "$out" "$HOME/.local/bin/fm points at $T/old-config/bin/fm"
check 'foreign fm link is left untouched' "$(readlink "$HOME/.local/bin/fm")" "$T/old-config/bin/fm"

finish
