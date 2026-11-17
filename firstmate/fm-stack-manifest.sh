#!/usr/bin/env bash
# fm-stack-manifest.sh - the one parsing owner for firstmate/stack-manifest.tsv,
# the single source of the official FirstMate repository, branch and validated
# commit. Sourced by install.sh and bin/fm-update; never fork this parsing
# between them - extend this file instead.
#
# Public interface:
#   stack_manifest_load <path>
#     Sets the SM_* globals below from a strict key<TAB>value manifest file.
#     Returns 1 and sets SM_LOAD_ERROR on: a missing file; a file missing any
#     required key; a duplicate required key (the first occurrence wins the
#     error, never a silent last-value overwrite); a schema_version other
#     than the one this parser supports; an invalid branch name; or a
#     firstmate_validated_commit that is not a full 40-hex SHA. Every SM_*
#     global is reset to empty first, so a failed load can never leave a stale
#     value from a previous call. Unknown keys are ignored but can never
#     overwrite a known field.
#
#   stack_commit_relation <repo> <baseline-full-sha>
#     Prints exact, descendant, ancestor, diverged, or unknown: reasons from
#     the local Git graph only, never fetches, never guesses.
#       - exact: <repo>'s HEAD is the baseline commit.
#       - descendant: HEAD is a descendant of the baseline (newer,
#         unvalidated).
#       - ancestor: HEAD is an ancestor of the baseline (older than the
#         validated baseline).
#       - diverged: neither is an ancestor of the other.
#       - unknown: HEAD cannot be resolved, or the baseline commit is not
#         present in <repo>'s local object graph (this function never
#         fetches to find out).

# shellcheck disable=SC2034 # public interface: read by install.sh/fm-update after stack_manifest_load
SM_SCHEMA_VERSION=
SM_FIRSTMATE_REPO=
SM_FIRSTMATE_BRANCH=
SM_FIRSTMATE_COMMIT=
SM_LOAD_ERROR=

# The schema_version this parser understands. Bump this only alongside a
# parser change that actually reads a new/changed key; a tracked manifest
# whose schema_version disagrees fails closed rather than being guessed at.
SM_SUPPORTED_SCHEMA_VERSION=4

stack_manifest_load() { # <path>
  local file=$1 key value missing='' field seen=' '
  SM_SCHEMA_VERSION=; SM_FIRSTMATE_REPO=; SM_FIRSTMATE_BRANCH=; SM_FIRSTMATE_COMMIT=; SM_LOAD_ERROR=

  if [ ! -f "$file" ]; then
    SM_LOAD_ERROR="manifest not found: $file"
    return 1
  fi

  while IFS="$(printf '\t')" read -r key value || [ -n "${key:-}" ]; do
    case ${key:-} in
      ''|\#*) continue ;;
      schema_version|firstmate_repo|firstmate_branch|firstmate_validated_commit)
        case $seen in
          *" $key "*)
            SM_LOAD_ERROR="manifest $file has duplicate key: $key"
            return 1
            ;;
        esac
        seen="$seen$key "
        ;;
    esac
    case ${key:-} in
      schema_version) SM_SCHEMA_VERSION=$value ;;
      firstmate_repo) SM_FIRSTMATE_REPO=$value ;;
      firstmate_branch) SM_FIRSTMATE_BRANCH=$value ;;
      firstmate_validated_commit) SM_FIRSTMATE_COMMIT=$value ;;
    esac
  done < "$file"

  for field in SM_SCHEMA_VERSION SM_FIRSTMATE_REPO SM_FIRSTMATE_BRANCH SM_FIRSTMATE_COMMIT; do
    [ -n "${!field}" ] || missing="$missing ${field#SM_}"
  done
  if [ -n "$missing" ]; then
    SM_LOAD_ERROR="manifest $file missing required key(s):$missing"
    return 1
  fi

  if [ "$SM_SCHEMA_VERSION" != "$SM_SUPPORTED_SCHEMA_VERSION" ]; then
    SM_LOAD_ERROR="manifest $file has unsupported schema_version '$SM_SCHEMA_VERSION' (this parser supports only $SM_SUPPORTED_SCHEMA_VERSION)"
    return 1
  fi
  if ! git check-ref-format "refs/heads/$SM_FIRSTMATE_BRANCH" >/dev/null 2>&1; then
    SM_LOAD_ERROR="manifest $file firstmate_branch is not a valid branch: $SM_FIRSTMATE_BRANCH"
    return 1
  fi

  if ! [[ $SM_FIRSTMATE_COMMIT =~ ^[0-9A-Fa-f]{40}$ ]]; then
    SM_LOAD_ERROR="manifest $file firstmate_validated_commit is not a full 40-hex SHA: $SM_FIRSTMATE_COMMIT"
    return 1
  fi

  return 0
}

stack_commit_relation() { # <repo> <baseline-full-sha> -> exact|descendant|ancestor|diverged|unknown
  local repo=$1 baseline=${2:-} head
  [ -n "$baseline" ] || { printf unknown; return; }
  head=$(git -C "$repo" rev-parse HEAD 2>/dev/null) || { printf unknown; return; }
  if [ "$head" = "$baseline" ]; then printf exact; return; fi
  git -C "$repo" cat-file -e "$baseline^{commit}" 2>/dev/null || { printf unknown; return; }
  if git -C "$repo" merge-base --is-ancestor "$baseline" HEAD 2>/dev/null; then
    printf descendant; return
  fi
  if git -C "$repo" merge-base --is-ancestor HEAD "$baseline" 2>/dev/null; then
    printf ancestor; return
  fi
  printf diverged
}
