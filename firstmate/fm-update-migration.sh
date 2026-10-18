#!/usr/bin/env bash
# Sourced only by fm-update's explicit --migrate / --bootstrap modes.
# No second updater: preflight known layouts, adopt source, then return to the
# existing fast-forward/reconcile/verify path. Bash 3.2 compatible.

migration_clean_root() { # <path>
  local root=$1 top dir op
  top=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) || die "$root is not a Git checkout"
  [ "$(cd "$root" && pwd -P)" = "$(cd "$top" && pwd -P)" ] || die "$root is not a physical Git root"
  dir=$(git -C "$root" rev-parse --absolute-git-dir) || die "cannot resolve Git directory: $root"
  for op in MERGE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG sequencer; do
    [ ! -e "$dir/$op" ] || die "$root has an unfinished Git operation ($op)"
  done
  [ -z "$(git -C "$root" status --porcelain --untracked-files=all)" ] || die "$root has uncommitted/untracked work; preserve it manually"
  [ -z "$(git -C "$root" ls-files --others --ignored --exclude-standard)" ] || die "$root has ignored untracked content; preserve it outside the checkout before migration"
}

migration_url() { # <root> <remote> <expected>
  local root=$1 remote=$2 expected=$3 configured effective
  configured=$(git -C "$root" config --get-all "remote.$remote.url") || die "$root has no $remote URL"
  [ "$configured" = "$expected" ] || die "$root $remote is '$configured', expected exactly $expected; preserve and resolve remotes manually"
  effective=$(git -C "$root" remote get-url "$remote") || die "cannot resolve $root $remote"
  [ "$effective" = "$expected" ] || die "$root $remote is rewritten to '$effective'; expected $expected"
  [ -z "$(git -C "$root" config --get-all "remote.$remote.pushurl" || true)" ] || die "$root $remote has explicit push URLs; preserve and resolve this custom layout manually"
}

migration_prepare() {
  local tool_root=$1 config_repo=https://github.com/inkayat/firstmate-config.git
  local origin branch tracking target current existing previous_ref tool_target config_tip tool
  local source_ref source_oid official_ref local_branch
  for tool in git pi omp herdr; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required on PATH before migration"
  done
  # Paths may be symlinks, but must resolve to separate, non-nested Git roots.
  migration_clean_root "$tool_root"
  migration_clean_root "$CONFIG_ROOT"
  migration_clean_root "$FIRSTMATE_ROOT"
  CONFIG_ROOT=$(cd "$CONFIG_ROOT" && pwd -P)
  FIRSTMATE_ROOT=$(cd "$FIRSTMATE_ROOT" && pwd -P)
  if [ "$BOOTSTRAP" -eq 1 ] && [ "$(cd "$tool_root" && pwd -P)" = "$CONFIG_ROOT" ]; then
    die 'bootstrap source must be separate from the persistent config target; use --migrate for an installed new updater'
  fi
  case "$CONFIG_ROOT/" in "$FIRSTMATE_ROOT/"*) die 'config and FirstMate roots overlap' ;; esac
  case "$FIRSTMATE_ROOT/" in "$CONFIG_ROOT/"*) die 'config and FirstMate roots overlap' ;; esac
  [ -f "$FIRSTMATE_ROOT/AGENTS.md" ] || die 'FirstMate root has no AGENTS.md'
  migration_url "$tool_root" origin "$config_repo"
  migration_url "$CONFIG_ROOT" origin "$config_repo"
  [ "$(git_c symbolic-ref --quiet --short HEAD)" = main ] || die 'config must be on main for migration'
  [ "$(git_c config branch.main.remote)" = origin ] && [ "$(git_c config branch.main.merge)" = refs/heads/main ] || die 'config main must track origin/main'
  origin=$(git_f config --get-all remote.origin.url) || die 'FirstMate has no origin'
  case $origin in
    "$SM_FIRSTMATE_REPO"|"$SM_FIRSTMATE_UPSTREAM_REPO") migration_url "$FIRSTMATE_ROOT" origin "$origin" ;;
    *) die "unrecognized FirstMate origin '$origin'; preserve and resolve remotes manually" ;;
  esac
  if git_f config --get-all remote.upstream.url >/dev/null; then
    migration_url "$FIRSTMATE_ROOT" upstream "$SM_FIRSTMATE_UPSTREAM_REPO"
  fi
  branch=$(git_f symbolic-ref --quiet --short HEAD) || die 'FirstMate is detached'
  case $branch in main|"$SM_FIRSTMATE_BRANCH") ;; *) die "unrecognized FirstMate branch '$branch'" ;; esac
  tracking=$(git_f config "branch.$branch.remote") || die "FirstMate $branch has no tracking remote"
  case "$tracking:$(git_f config "branch.$branch.merge")" in
    "origin:refs/heads/$branch") ;;
    upstream:refs/heads/main)
      [ "$branch" = main ] || die 'unrecognized branch tracking'
      migration_url "$FIRSTMATE_ROOT" upstream "$SM_FIRSTMATE_UPSTREAM_REPO"
      ;;
    *) die 'unrecognized branch tracking; resolve manually' ;;
  esac
  # Only explicit fork branch and config main are fetched. Official is never
  # fetched/merged; FETCH_HEAD is read immediately before the next fetch.
  [ "$(git_f ls-remote --get-url "$SM_FIRSTMATE_REPO")" = "$SM_FIRSTMATE_REPO" ] || die 'fork distribution URL is rewritten; resolve Git URL configuration before migration'
  git_f fetch --quiet --no-tags "$SM_FIRSTMATE_REPO" "refs/heads/$SM_FIRSTMATE_BRANCH" || die 'cannot fetch fork distribution branch'
  target=$(git_f rev-parse 'FETCH_HEAD^{commit}') || die 'missing fetched distribution commit'
  git_f merge-base --is-ancestor "$SM_FIRSTMATE_COMMIT" "$target" || die 'fork branch does not contain validated commit'
  current=$(git_f rev-parse HEAD)
  git_f merge-base --is-ancestor "$current" "$target" || die "FirstMate HEAD $current has unlanded/diverged work relative to $target"
  if git_f show-ref --verify --quiet "refs/heads/$SM_FIRSTMATE_BRANCH"; then
    existing=$(git_f rev-parse "refs/heads/$SM_FIRSTMATE_BRANCH")
    git_f merge-base --is-ancestor "$existing" "$target" || die 'existing distribution branch has unlanded/diverged work'
    local target_tracking
    target_tracking=$(git_f config "branch.$SM_FIRSTMATE_BRANCH.remote" || true)
    [ -z "$target_tracking" ] || { [ "$target_tracking" = origin ] && [ "$(git_f config "branch.$SM_FIRSTMATE_BRANCH.merge")" = "refs/heads/$SM_FIRSTMATE_BRANCH" ]; } || die 'existing distribution branch has conflicting tracking'
  fi
  if previous_ref=$(git_f rev-parse --verify "refs/remotes/origin/$SM_FIRSTMATE_BRANCH" 2>/dev/null); then
    git_f merge-base --is-ancestor "$previous_ref" "$target" || die 'existing distribution tracking ref conflicts with fetched branch'
  fi
  tool_target=$(git -C "$tool_root" rev-parse HEAD) || die 'cannot resolve bootstrap revision'
  git_c fetch --quiet --no-tags origin refs/heads/main:refs/remotes/origin/main || die 'cannot fetch config main'
  config_tip=$(git_c rev-parse origin/main)
  git_c merge-base --is-ancestor "$tool_target" "$config_tip" || die 'bootstrap revision is not published on config origin/main'
  git_c merge-base --is-ancestor HEAD "$tool_target" || die 'config has unlanded/diverged work or is newer than bootstrap revision; use a reviewed newer bootstrap'
  # shellcheck disable=SC2034 # result consumed by the sourcing updater
  MIGRATION_CONFIG_TARGET=$tool_target
  printf 'Migration preflight passed: config %s -> %s; FirstMate %s -> %s\n' "$(git_c rev-parse HEAD)" "$tool_target" "$current" "$target"
  # From here failures can leave a partial migration. Announce each completed
  # mutation, retain all branch tips, and never imply atomic rollback.
  MIGRATION_PROGRESS='preflight passed; source adoption started'
  trap 'die "migration interrupted; inspect both repositories before retrying"' INT TERM
  if [ "$origin" = "$SM_FIRSTMATE_UPSTREAM_REPO" ]; then
    # Keep origin present throughout adoption. Each intermediate layout is
    # already accepted by preflight; unrelated missing origins still refuse.
    if ! git_f config --get-all remote.upstream.url >/dev/null; then
      git_f remote add upstream "$SM_FIRSTMATE_UPSTREAM_REPO" || die 'cannot preserve official connection as upstream'
    fi
    # Preserve existing official branch connections; the selected distribution
    # branch keeps origin tracking throughout its explicit fork cutover.
    while read -r source_ref source_oid; do
      case $source_ref in ''|refs/remotes/origin/HEAD) continue ;; esac
      official_ref="refs/remotes/upstream/${source_ref#refs/remotes/origin/}"
      if ! git_f show-ref --verify --quiet "$official_ref"; then
        git_f update-ref "$official_ref" "$source_oid" '' || die 'cannot preserve official tracking ref'
      fi
    done <<< "$(git_f for-each-ref --format='%(refname) %(objectname)' refs/remotes/origin/)"
    while IFS= read -r local_branch; do
      if [ "$local_branch" != "$SM_FIRSTMATE_BRANCH" ] && [ "$(git_f config "branch.$local_branch.remote")" = origin ]; then
        git_f config "branch.$local_branch.remote" upstream || die 'cannot preserve official branch tracking'
      fi
    done <<< "$(git_f for-each-ref --format='%(refname:strip=2)' refs/heads/)"
    git_f remote set-url origin "$SM_FIRSTMATE_REPO" || die 'cannot select fork origin'
  elif ! git_f config --get-all remote.upstream.url >/dev/null; then
    git_f remote add upstream "$SM_FIRSTMATE_UPSTREAM_REPO" || die 'cannot add official upstream'
  fi
  MIGRATION_PROGRESS="fork origin selected; official retained as upstream; FirstMate HEAD still $current"
  printf '%s\n' "$MIGRATION_PROGRESS"
  git_f update-ref "refs/remotes/origin/$SM_FIRSTMATE_BRANCH" "$target" || die 'cannot record fetched fork branch'
  if git_f show-ref --verify --quiet "refs/heads/$SM_FIRSTMATE_BRANCH"; then
    git_f checkout --quiet "$SM_FIRSTMATE_BRANCH" || die 'cannot switch to existing distribution branch'
  else
    git_f checkout --quiet -b "$SM_FIRSTMATE_BRANCH" "$target" || die 'cannot create distribution branch'
  fi
  git_f merge --ff-only --quiet "$target" || die 'cannot fast-forward distribution branch'
  git_f branch --set-upstream-to="origin/$SM_FIRSTMATE_BRANCH" "$SM_FIRSTMATE_BRANCH" >/dev/null || die 'cannot set distribution tracking'
  git_f remote set-head origin "$SM_FIRSTMATE_BRANCH" || die 'cannot set native origin/HEAD'
  MIGRATION_PROGRESS="FirstMate on $SM_FIRSTMATE_BRANCH at $target; fork origin and official upstream selected; config still $(git_c rev-parse HEAD)"
  printf '%s\n' "$MIGRATION_PROGRESS"
}
