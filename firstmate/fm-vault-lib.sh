#!/usr/bin/env bash
# fm-vault-lib.sh - the one owner of specialist skill vault pin parsing,
# commit-qualified cache path construction, and cache verification.
#
# Sourced by install.sh (step 10 and the machine-local env file), bin/fm-doctor
# (vault.pin / vault.no_global_leak) and bin/fm-version (identity only). Never
# duplicate the lock parsing, the path shape, or the verification states in a
# caller or a test: a fixture may write its own lock file, but it must read the
# resulting path and state back through these functions.
#
# Layout (immutable, one directory per exact pinned commit):
#
#   <cache-root>/<owner>-<repo>/<40-hex-commit>/
#
# A new pin never re-points an existing directory: it is cloned alongside, and
# every previously installed commit directory stays byte-stable, so an exact
# path already handed to a worker can never change underneath it. Old commit
# directories are simply left in place - there is no background cleanup,
# garbage collector, or retention policy here, by design.

# fm_vault_load <lock-file> <cache-root>
#   Sets FM_VAULT_REPO, FM_VAULT_COMMIT, FM_VAULT_DIR (the commit-qualified
#   directory) and FM_VAULT_CACHE_ROOT. Returns 0 on success, 1 when the lock
#   file is absent (the vault is optional), 2 when it is malformed.
#
#   The repo id and commit are validated before they are used to build a path:
#   both come from a tracked file, and a path segment assembled from unvalidated
#   file content is how "../.." ends up being a directory name.
fm_vault_load() {
  local lock=$1 cache_root=$2
  FM_VAULT_REPO=""
  FM_VAULT_COMMIT=""
  FM_VAULT_DIR=""
  FM_VAULT_CACHE_ROOT=$cache_root
  [ -f "$lock" ] || return 1
  FM_VAULT_REPO=$(awk -F'\t' '/^[^#]/ && NF >= 2 {print $1; exit}' "$lock")
  FM_VAULT_COMMIT=$(awk -F'\t' '/^[^#]/ && NF >= 2 {print $2; exit}' "$lock")
  # A tracked file's content becomes a path segment here, so validate both
  # fields first: "../.." is otherwise a perfectly good directory name.
  [[ $FM_VAULT_REPO =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || return 2
  [[ $FM_VAULT_COMMIT =~ ^[0-9a-f]{40}$ ]] || return 2
  FM_VAULT_DIR="$cache_root/$(printf '%s' "$FM_VAULT_REPO" | tr '/' '-')/$FM_VAULT_COMMIT"
  return 0
}

# fm_vault_verify <dir> <expected-commit>
#   Prints one state word and returns 0 only for `healthy`, 2 for
#   `unverified_catalog` (everything git-verifiable holds, but bun - an
#   optional tool - is not on PATH to run the vault's own parser), 1 otherwise.
#
#   States: absent | corrupt | dirty | wrong_revision | catalog_missing |
#           catalog_invalid | unverified_catalog | healthy
#
#   The catalog check deliberately delegates to the vault's own lookup surface
#   rather than reimplementing any schema knowledge here: `--category` parses
#   and validates the whole catalog and exits 0 when it is sound.
fm_vault_verify() {
  local dir=$1 want=$2 cur dirty
  [ -d "$dir/.git" ] || { printf absent; return 1; }
  cur=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
  [ -n "$cur" ] || { printf corrupt; return 1; }
  dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  [ "$dirty" = 0 ] || { printf dirty; return 1; }
  [ "$cur" = "$want" ] || { printf wrong_revision; return 1; }
  { [ -f "$dir/catalog.yaml" ] && [ -f "$dir/bin/lookup.ts" ]; } || { printf catalog_missing; return 1; }
  command -v bun >/dev/null 2>&1 || { printf unverified_catalog; return 2; }
  # bun resolves bunfig.toml/.env from its own process cwd, not from the
  # script path given to it, so running it unqualified would let the
  # caller's own cwd (e.g. `fm doctor` invoked inside a cloned third-party
  # repo) supply those files, including a `preload = [...]` that runs
  # arbitrary code and can even fake this very check by calling
  # process.exit(0) before the probe runs. A plain `cd "$dir"` is not
  # enough by itself:
  #   - with a relative $dir and an exported CDPATH, bash's cd builtin can
  #     land in a directory CDPATH matches instead of the one relative to
  #     cwd, even though the git checks above (which resolve $dir directly
  #     and never consult CDPATH) already verified the real one;
  #   - cd's default logical (-L) mode canonicalizes ".." textually rather
  #     than physically, so a $dir containing a symlink component followed
  #     by ".." can land somewhere other than what the physical git/test
  #     checks above just verified.
  # Disable CDPATH search, resolve physically (-P) exactly as the git
  # checks above do, and end option parsing so a leading "-" in $dir is
  # never taken as a cd option (not reachable today: callers only pass a
  # validated .../<40-hex> path, and install.sh's last-known-good read
  # requires basename == HEAD, so a bare "-" would already have failed as
  # wrong_revision before this line).
  ( CDPATH='' cd -P -- "$dir" && bun ./bin/lookup.ts --category __fm_vault_verify_probe__ ) >/dev/null 2>&1 ||
    { printf catalog_invalid; return 1; }
  printf healthy
}

# fm_vault_state_reason <state> <dir>
#   The one shared human explanation of a non-healthy state. Every caller
#   prefixes its own context; none of them invents its own wording.
fm_vault_state_reason() {
  case $1 in
    absent) printf '%s exists but is not a git checkout; this cache is install-managed - remove it and rerun ./install.sh' "$2" ;;
    corrupt) printf '%s is corrupt (not a readable git checkout); remove it and rerun ./install.sh' "$2" ;;
    dirty) printf '%s has local modification(s); this cache is install-managed and must never be hand-edited - remove it and rerun ./install.sh' "$2" ;;
    wrong_revision) printf '%s is not a checkout of the commit it is named for (an immutable commit directory is never re-pinned in place); remove it and rerun ./install.sh' "$2" ;;
    catalog_missing) printf '%s has no catalog.yaml / bin/lookup.ts; that is not the specialist skill vault - remove it and rerun ./install.sh' "$2" ;;
    catalog_invalid) printf '%s has a catalog its own bin/lookup.ts cannot parse; remove it and rerun ./install.sh' "$2" ;;
    unverified_catalog) printf '%s is at the pinned commit, but bun is not on PATH to verify its catalog parses' "$2" ;;
    *) printf '%s is in an unrecognized state (%s)' "$2" "$1" ;;
  esac
}
