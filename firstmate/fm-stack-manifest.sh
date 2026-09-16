#!/usr/bin/env bash
# fm-stack-manifest.sh - the one parsing/comparison owner for
# firstmate/stack-manifest.tsv, the single source of truth for stable
# compatibility information across OMP Captain -> official FirstMate ->
# Herdr -> Pi / OMP, on macOS and Betao/Omarchy Linux. Sourced by install.sh
# and bin/fm-doctor; never fork this parsing or the version-comparison
# logic between them - extend this file instead.
#
# Public interface:
#   stack_manifest_load <path>
#     Sets the SM_* globals below from a strict key<TAB>value manifest file.
#     Returns 1 and sets SM_LOAD_ERROR on: a missing file; a file missing any
#     required key; a duplicate required key (the first occurrence wins the
#     error, never a silent last-value overwrite); a schema_version other
#     than the one this parser supports; a firstmate_validated_commit that
#     is not a full 40-hex SHA; a min/tested tool version that is not plain
#     numeric dotted form; or a min version greater than its own tested
#     version. Every SM_* global is reset to empty first, so a failed load
#     can never leave a stale value from a previous call. Unknown keys are
#     ignored (forward-compatible) but can never overwrite a known field.
#   stack_version_extract <raw>
#     Prints the leading dot-separated numeric version (two or more integer
#     components, e.g. "0.85.1") found anywhere in <raw>, or nothing when
#     none is found. Matches this project's own "leading numeric semantic
#     version only" parsing policy for --version output.
#
#   stack_version_compare <a> <b>
#     Prints lt, eq, or gt: portable numeric comparison of two dot-separated
#     integer version strings, missing trailing components treated as 0.
#     Deliberately not `sort -V` - BSD sort (macOS) has no -V flag, so that
#     would not be portable across this project's own two target platforms.
#     This is the "lightweight existing mechanism": a dozen lines of pure
#     bash, no new dependency.
#
#   stack_component_compat <ver> <min> <tested>
#     Prints PASS, WARNING, FAIL, or UNKNOWN for one installed component
#     version against its manifest policy:
#       - <ver>, <min>, or <tested> empty (unparseable/unknown input) ->
#         UNKNOWN, never a guessed FAIL.
#       - <ver> below <min> -> FAIL (hard minimum violation).
#       - <ver> above <tested> -> WARNING (newer than validated; a newer
#         version must never automatically FAIL).
#       - otherwise (<min> <= <ver> <= <tested>) -> PASS.
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

# shellcheck disable=SC2034 # public interface: read by install.sh/fm-doctor after stack_manifest_load
SM_SCHEMA_VERSION=
SM_FIRSTMATE_REPO=
SM_FIRSTMATE_COMMIT=
SM_PI_MIN=
SM_PI_TESTED=
SM_OMP_MIN=
SM_OMP_TESTED=
SM_HERDR_MIN=
SM_HERDR_TESTED=
SM_LOAD_ERROR=

# The schema_version this parser understands. Bump this only alongside a
# parser change that actually reads a new/changed key; a tracked manifest
# whose schema_version disagrees fails closed rather than being guessed at.
SM_SUPPORTED_SCHEMA_VERSION=1

stack_manifest_load() { # <path>
  local file=$1 key value missing='' field seen=' ' name min tested
  SM_SCHEMA_VERSION=; SM_FIRSTMATE_REPO=; SM_FIRSTMATE_COMMIT=
  SM_PI_MIN=; SM_PI_TESTED=; SM_OMP_MIN=; SM_OMP_TESTED=
  SM_HERDR_MIN=; SM_HERDR_TESTED=; SM_LOAD_ERROR=

  if [ ! -f "$file" ]; then
    SM_LOAD_ERROR="manifest not found: $file"
    return 1
  fi

  while IFS="$(printf '\t')" read -r key value || [ -n "${key:-}" ]; do
    case ${key:-} in
      ''|\#*) continue ;;
      schema_version|firstmate_repo|firstmate_validated_commit|pi_min_version|pi_tested_version|omp_min_version|omp_tested_version|herdr_min_version|herdr_tested_version)
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
      firstmate_validated_commit) SM_FIRSTMATE_COMMIT=$value ;;
      pi_min_version) SM_PI_MIN=$value ;;
      pi_tested_version) SM_PI_TESTED=$value ;;
      omp_min_version) SM_OMP_MIN=$value ;;
      omp_tested_version) SM_OMP_TESTED=$value ;;
      herdr_min_version) SM_HERDR_MIN=$value ;;
      herdr_tested_version) SM_HERDR_TESTED=$value ;;
    esac
  done < "$file"

  for field in SM_SCHEMA_VERSION SM_FIRSTMATE_REPO SM_FIRSTMATE_COMMIT \
               SM_PI_MIN SM_PI_TESTED SM_OMP_MIN SM_OMP_TESTED \
               SM_HERDR_MIN SM_HERDR_TESTED; do
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

  if ! [[ $SM_FIRSTMATE_COMMIT =~ ^[0-9A-Fa-f]{40}$ ]]; then
    SM_LOAD_ERROR="manifest $file firstmate_validated_commit is not a full 40-hex SHA: $SM_FIRSTMATE_COMMIT"
    return 1
  fi

  for field in "pi:$SM_PI_MIN:$SM_PI_TESTED" "omp:$SM_OMP_MIN:$SM_OMP_TESTED" "herdr:$SM_HERDR_MIN:$SM_HERDR_TESTED"; do
    name=${field%%:*}; field=${field#*:}
    min=${field%%:*}; tested=${field#*:}
    if ! [[ $min =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
      SM_LOAD_ERROR="manifest $file ${name}_min_version is not plain numeric dotted form: $min"
      return 1
    fi
    if ! [[ $tested =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
      SM_LOAD_ERROR="manifest $file ${name}_tested_version is not plain numeric dotted form: $tested"
      return 1
    fi
    if [ "$(stack_version_compare "$min" "$tested")" = gt ]; then
      SM_LOAD_ERROR="manifest $file ${name}_min_version ($min) is greater than ${name}_tested_version ($tested)"
      return 1
    fi
  done

  return 0
}

stack_version_extract() { # <raw text>
  local raw=${1:-}
  if [[ $raw =~ ([0-9]+(\.[0-9]+)+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

stack_version_compare() { # <a> <b> -> lt|eq|gt
  local a=${1:-} b=${2:-}
  local -a pa pb
  IFS='.' read -r -a pa <<< "$a"
  IFS='.' read -r -a pb <<< "$b"
  local n=${#pa[@]} i ca cb
  [ "${#pb[@]}" -le "$n" ] || n=${#pb[@]}
  for ((i = 0; i < n; i++)); do
    ca=${pa[i]:-0}; cb=${pb[i]:-0}
    ca=$((10#$ca)); cb=$((10#$cb))
    if [ "$ca" -lt "$cb" ]; then printf lt; return; fi
    if [ "$ca" -gt "$cb" ]; then printf gt; return; fi
  done
  printf eq
}

stack_component_compat() { # <ver> <min> <tested> -> PASS|WARNING|FAIL|UNKNOWN
  local ver=${1:-} min=${2:-} tested=${3:-}
  if [ -z "$ver" ] || [ -z "$min" ] || [ -z "$tested" ]; then
    printf UNKNOWN
    return
  fi
  case $(stack_version_compare "$ver" "$min") in
    lt) printf FAIL; return ;;
  esac
  case $(stack_version_compare "$ver" "$tested") in
    gt) printf WARNING; return ;;
  esac
  printf PASS
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
