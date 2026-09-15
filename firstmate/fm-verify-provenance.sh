#!/usr/bin/env bash
# fm-verify-provenance.sh - deterministic worktree-provenance classifier for
# verification (test/build/lint) evidence. Sourced by tests/worker-context.sh;
# also usable standalone:
#   fm-verify-provenance.sh classify <expected-worktree> <report-file>
#   fm-verify-provenance.sh run-local <expected-worktree> <report-file> -- <command> [args...]
#
# Problem this closes: a fresh, green test/build/lint run only counts as
# evidence for THIS task when it demonstrably ran against the assigned task
# worktree - not a shared container bound to a different checkout, and not an
# unprovable remote run silently accepted as a pass. The pinned shared skill
# `verification-before-completion` already requires fresh passing output;
# this adds the missing provenance half, generically and with no hardcoded
# container/path names (see skills/verification-provenance/SKILL.md for the
# worker-facing contract this classifier enforces).
#
# Worker-reported evidence fields, one "LABEL: value" line each:
#   VERIFY_PROVENANCE_KIND        local | container-bind | artifact
#   VERIFY_EXECUTION_REALPATH     canonical host filesystem path where the
#     verification claims to have run - local: the cwd's own
#     `git rev-parse --show-toplevel` (or `pwd -P` for a non-git command);
#     container-bind: the host-side bind-mount SOURCE directory's realpath,
#     never the in-container mount target; artifact: the source tree path
#     the artifact was built from.
#   VERIFY_ARTIFACT_SOURCE_COMMIT (artifact kind only) the commit the
#     artifact's source tree was built from.
#
# fm_provenance_classify <expected-worktree> <report-text> prints exactly one
# of:
#   wrong_tree - a kind and a realpath were both reported, but they do not
#                resolve to the expected worktree (or, for artifact, the
#                commit does not match).
#   uncertain  - the kind or realpath is missing/unrecognized, the expected
#                worktree cannot be resolved, or the worker's self-report is
#                apparently correct but not independently observed.
#
# The accepting outcomes below are produced only by Firstmate/caller-owned
# mechanisms that mechanically observe the verification boundary. Today this
# file intentionally ships only a local runner; container bind inspection and
# artifact identity remain fail-closed here rather than guessed from prose.
#   worktree_local   - run-local executed the command from the expected worktree
#                      and the worker report agrees.
#   bind_correct     - reserved for a future trusted container inspector.
#   artifact_correct - reserved for a future trusted artifact identity check.
set -u

_fvp_field() { printf '%s\n' "$1" | sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" | tail -1; }

# _fvp_canon <path> - realpath when the path exists locally (resolves
# symlinked prefixes such as macOS /tmp -> /private/tmp, matching
# bin/fm-spawn.sh's own PROJ_ABS_REAL canonicalization); the raw string
# otherwise, so a genuinely inaccessible remote path still compares as a
# literal rather than erroring.
_fvp_canon() {
  local p=$1
  if [ -d "$p" ]; then (cd "$p" 2>/dev/null && pwd -P) || printf '%s' "$p"; else printf '%s' "$p"; fi
}

_fvp_classify_with_observed() {  # <expected-worktree> <report-text> <observed-text>
  local expected=$1 report=$2 observed=$3
  local kind reported expected_real observed_kind observed_path commit_reported commit_expected
  kind=$(_fvp_field "$report" VERIFY_PROVENANCE_KIND)
  reported=$(_fvp_field "$report" VERIFY_EXECUTION_REALPATH)
  [ -n "$kind" ] && [ -n "$reported" ] || { printf 'uncertain'; return 0; }

  expected_real=$(cd "$expected" 2>/dev/null && pwd -P) || { printf 'uncertain'; return 0; }
  reported=$(_fvp_canon "$reported")

  _fvp_observed_matches() { # <kind>
    observed_kind=$(_fvp_field "$observed" FM_OBSERVED_PROVENANCE_KIND)
    observed_path=$(_fvp_field "$observed" FM_OBSERVED_EXECUTION_REALPATH)
    [ -n "$observed_kind" ] && [ -n "$observed_path" ] || return 2
    observed_path=$(_fvp_canon "$observed_path")
    [ "$observed_kind" = "$1" ] && [ "$observed_path" = "$expected_real" ] && [ "$observed_path" = "$reported" ]
  }

  case $kind in
    local)
      [ "$reported" = "$expected_real" ] || { printf 'wrong_tree'; return 0; }
      _fvp_observed_matches local
      case $? in 0) printf 'worktree_local' ;; 1) printf 'wrong_tree' ;; *) printf 'uncertain' ;; esac
      ;;
    container-bind)
      [ "$reported" = "$expected_real" ] && printf 'uncertain' || printf 'wrong_tree'
      ;;
    artifact)
      commit_reported=$(_fvp_field "$report" VERIFY_ARTIFACT_SOURCE_COMMIT)
      commit_expected=$(git -C "$expected" rev-parse HEAD 2>/dev/null) || commit_expected=
      if [ -z "$commit_reported" ] || [ -z "$commit_expected" ]; then
        printf 'uncertain'
      elif [ "$reported" != "$expected_real" ] || [ "$commit_reported" != "$commit_expected" ]; then
        printf 'wrong_tree'
      else
        printf 'uncertain'
      fi
      ;;
    *)
      printf 'uncertain'
      ;;
  esac
}

fm_provenance_classify() {  # <expected-worktree> <report-text>
  local expected=$1 report=$2
  _fvp_classify_with_observed "$expected" "$report" ''
}

fm_provenance_run_local() {  # <expected-worktree> <report-text> -- <command> [args...]
  local expected=$1 report=$2 expected_real observed classification rc
  shift 2
  [ "${1:-}" = -- ] || { printf 'usage: fm_provenance_run_local <expected-worktree> <report-text> -- <command> [args...]\n' >&2; return 2; }
  shift
  [ "$#" -gt 0 ] || { printf 'usage: fm_provenance_run_local <expected-worktree> <report-text> -- <command> [args...]\n' >&2; return 2; }

  expected_real=$(cd "$expected" 2>/dev/null && pwd -P) || { printf 'uncertain'; return 1; }
  (cd "$expected_real" && "$@") >&2
  rc=$?
  [ "$rc" -eq 0 ] || return "$rc"

  observed="FM_OBSERVED_PROVENANCE_KIND: local
FM_OBSERVED_EXECUTION_REALPATH: $expected_real"
  classification=$(_fvp_classify_with_observed "$expected_real" "$report" "$observed")
  printf '%s' "$classification"
  [ "$classification" = worktree_local ]
}

if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
  case "${1:-}" in
    classify)
      expected=${2:?"usage: $0 classify <expected-worktree> <report-file>"}
      report_file=${3:?"usage: $0 classify <expected-worktree> <report-file>"}
      report_text=$(cat "$report_file" 2>/dev/null || printf '')
      fm_provenance_classify "$expected" "$report_text"
      printf '\n'
      ;;
    run-local)
      expected=${2:?"usage: $0 run-local <expected-worktree> <report-file> -- <command> [args...]"}
      report_file=${3:?"usage: $0 run-local <expected-worktree> <report-file> -- <command> [args...]"}
      shift 3
      report_text=$(cat "$report_file" 2>/dev/null || printf '')
      fm_provenance_run_local "$expected" "$report_text" "$@"
      printf '\n'
      ;;
    *)
      printf 'usage: %s classify <expected-worktree> <report-file>\n' "$0" >&2
      printf '   or: %s run-local <expected-worktree> <report-file> -- <command> [args...]\n' "$0" >&2
      exit 2
      ;;
  esac
fi
