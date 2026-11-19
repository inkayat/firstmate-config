#!/usr/bin/env bash
# update.sh - `fm update` against private local remotes: official FirstMate is
# fast-forwarded before config, the pulled config is reconciled, unsafe
# states are refused before anything moves, and a late failure is reported as
# a partial update. Each scenario runs in its own fresh synthetic world.
set -u

if [ "${1:-}" != --scenario ]; then
  failed=0
  for s in happy dirty_config dirty_official diverged_config fork_origin missing_tip unlanded_official partial; do
    printf '# %s\n' "$s"
    bash "${BASH_SOURCE[0]}" --scenario "$s" || failed=1
  done
  [ "$failed" -eq 0 ] && printf 'ALL PASS\n'
  exit "$failed"
fi

# shellcheck source=tests/fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixture.sh"
install_world || { cat "$T/install.out" >&2; bad 'fixture install'; finish; }

for repo in "$OFFICIAL" "$CONFIG"; do
  printf '#!/bin/sh\nprintf "%%s\\n" %s >> "%s"\n' "$(basename "$repo")" "$T/order.log" > "$repo/.git/hooks/post-merge"
  chmod +x "$repo/.git/hooks/post-merge"
done
official_before=$(git -C "$OFFICIAL" rev-parse HEAD)
config_before=$(git -C "$CONFIG" rev-parse HEAD)
run_update() { (cd "$T" && "$HOME/.local/bin/fm" update > "$T/update.out" 2>&1); }
official_unchanged() { check "$1: official checkout not moved" "$(git -C "$OFFICIAL" rev-parse HEAD)" "$official_before"; }
config_unchanged() { check "$1: config checkout not moved" "$(git -C "$CONFIG" rev-parse HEAD)" "$config_before"; }

case $2 in
  happy)
    push_change "$OFFICIAL_REMOTE" AGENTS.md 'official firstmate v2'
    push_change "$CONFIG_REMOTE" roles/new-role/ROLE.md $'---\nname: fm-new-role\ndescription: fixture\n---'
    run_update; status=$?
    check 'update succeeds' "$status" 0
    check 'official is fast-forwarded before config' "$(tr '\n' ' ' < "$T/order.log")" 'firstmate firstmate-config '
    check 'official reaches its remote tip' "$(git -C "$OFFICIAL" rev-parse HEAD)" "$(remote_tip "$OFFICIAL_REMOTE")"
    check 'config reaches its remote tip' "$(git -C "$CONFIG" rev-parse HEAD)" "$(remote_tip "$CONFIG_REMOTE")"
    check 'pulled config is reconciled in the same run' \
      "$(cd "$HOME/.omp/agent/agents" && cd -P "$(dirname "$(readlink fm-new-role.md)")" && pwd -P)" "$FMC/roles/new-role"
    has 'update reports completion' "$(cat "$T/update.out")" 'fm update complete'
    check 'update never drives herdr (no root Herdr installer)' "$(cat "$HERDR_LOG" 2>/dev/null)" ''
    run_update; status=$?
    check 'a repeated update is a clean no-op' "$status" 0
    check 'repeated update does not merge either checkout again' "$(tr '\n' ' ' < "$T/order.log")" 'firstmate firstmate-config '
    ;;
  dirty_config)
    push_change "$OFFICIAL_REMOTE" AGENTS.md 'official firstmate v2'
    printf 'scratch\n' > "$CONFIG/untracked-note"
    run_update; status=$?
    check 'dirty config is refused' "$status" 1
    has 'refusal names the dirty path' "$(cat "$T/update.out")" 'untracked-note'
    official_unchanged 'dirty config'
    check 'dirty file is kept' "$(cat "$CONFIG/untracked-note")" scratch
    ;;
  dirty_official)
    push_change "$CONFIG_REMOTE" note 'upstream'
    printf 'local edit\n' >> "$OFFICIAL/AGENTS.md"
    run_update; status=$?
    check 'dirty official is refused' "$status" 1
    config_unchanged 'dirty official'
    has 'local official edit is kept' "$(cat "$OFFICIAL/AGENTS.md")" 'local edit'
    ;;
  diverged_config)
    push_change "$OFFICIAL_REMOTE" AGENTS.md 'official firstmate v2'
    push_change "$CONFIG_REMOTE" note 'upstream'
    printf 'local\n' > "$CONFIG/local-note"
    git -C "$CONFIG" add -A && git -C "$CONFIG" commit -qm local
    local_head=$(git -C "$CONFIG" rev-parse HEAD)
    run_update; status=$?
    check 'diverged config is refused' "$status" 1
    has 'refusal says diverged' "$(cat "$T/update.out")" 'diverged'
    official_unchanged 'diverged config'
    check 'local config commit is kept' "$(git -C "$CONFIG" rev-parse HEAD)" "$local_head"
    ;;
  fork_origin)
    push_change "$CONFIG_REMOTE" note 'upstream'
    git -C "$OFFICIAL" remote set-url origin https://github.com/inkayat/firstmate.git
    run_update; status=$?
    check 'a fork origin is refused' "$status" 1
    has 'refusal names the official origin' "$(cat "$T/update.out")" "expected exactly $OFFICIAL_REMOTE"
    official_unchanged 'fork origin'
    config_unchanged 'fork origin'
    ;;
  missing_tip)
    push_change "$CONFIG_REMOTE" note 'upstream'
    git -C "$OFFICIAL_REMOTE" update-ref -d refs/heads/main
    run_update; status=$?
    check 'a missing official main is refused' "$status" 1
    official_unchanged 'missing tip'
    config_unchanged 'missing tip'
    ;;
  unlanded_official)
    push_change "$CONFIG_REMOTE" note 'upstream'
    printf 'mine\n' > "$OFFICIAL/local-work"
    git -C "$OFFICIAL" add -A && git -C "$OFFICIAL" commit -qm 'unlanded work'
    official_before=$(git -C "$OFFICIAL" rev-parse HEAD)
    run_update; status=$?
    check 'unlanded official work is refused' "$status" 1
    has 'refusal names unlanded work' "$(cat "$T/update.out")" 'unlanded work'
    official_unchanged 'unlanded official'
    config_unchanged 'unlanded official'
    ;;
  partial)
    push_change "$OFFICIAL_REMOTE" AGENTS.md 'official firstmate v2'
    rm "$HOME/.agents/skills/demo-local"
    ln -s "$T/elsewhere" "$HOME/.agents/skills/demo-local"
    run_update; status=$?
    check 'a failed reconcile fails the update' "$status" 1
    has 'failure after the official move is a partial update' "$(cat "$T/update.out")" 'PARTIAL UPDATE'
    check 'official move is kept, not rolled back' "$(git -C "$OFFICIAL" rev-parse HEAD)" "$(remote_tip "$OFFICIAL_REMOTE")"
    check 'foreign skill link is left untouched' "$(readlink "$HOME/.agents/skills/demo-local")" "$T/elsewhere"
    ;;
esac
finish
