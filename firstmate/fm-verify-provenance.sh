#!/usr/bin/env bash
# fm-verify-provenance.sh - deterministic worktree-provenance classifier for
# verification (test/build/lint) evidence. Sourced by tests/worker-context.sh;
# also usable standalone: `fm-verify-provenance.sh classify <expected-worktree>
# <report-file>`.
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
# Self-reported evidence fields, one "LABEL: value" line each:
#   VERIFY_PROVENANCE_KIND        local | container-bind | artifact
#   VERIFY_EXECUTION_REALPATH     canonical host filesystem path where the
#     verification actually ran - local: the cwd's own
#     `git rev-parse --show-toplevel` (or `pwd -P` for a non-git command);
#     container-bind: the host-side bind-mount SOURCE directory's realpath,
#     never the in-container mount target; artifact: the source tree path
#     the artifact was built from.
#   VERIFY_ARTIFACT_SOURCE_COMMIT (artifact kind only) the commit the
#     artifact's source tree was built from.
#
# fm_provenance_classify <expected-worktree> <report-text> prints exactly one
# of:
#   worktree_local   - kind=local, reported realpath matches the expected
#                      worktree's own canonical realpath.
#   bind_correct     - kind=container-bind, reported realpath matches.
#   artifact_correct - kind=artifact, reported realpath matches AND the
#                      reported commit matches the expected worktree's
#                      current HEAD.
#   wrong_tree       - a kind and a realpath were both reported, but they do
#                      not resolve to the expected worktree (or, for
#                      artifact, the commit does not match) - the concrete
#                      failure mode a shared container or artifact bound to
#                      another checkout produces.
#   uncertain        - the kind or the realpath is missing, the kind is not
#                      one of the three recognized values, the expected
#                      worktree itself cannot be resolved, or (artifact only)
#                      either commit is unavailable to compare - never
#                      silently treated as a pass.
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

fm_provenance_classify() {  # <expected-worktree> <report-text>
  local expected=$1 report=$2 kind reported expected_real commit_reported commit_expected
  kind=$(_fvp_field "$report" VERIFY_PROVENANCE_KIND)
  reported=$(_fvp_field "$report" VERIFY_EXECUTION_REALPATH)
  [ -n "$kind" ] && [ -n "$reported" ] || { printf 'uncertain'; return 0; }

  expected_real=$(cd "$expected" 2>/dev/null && pwd -P) || { printf 'uncertain'; return 0; }
  reported=$(_fvp_canon "$reported")

  case $kind in
    local)
      [ "$reported" = "$expected_real" ] && printf 'worktree_local' || printf 'wrong_tree'
      ;;
    container-bind)
      [ "$reported" = "$expected_real" ] && printf 'bind_correct' || printf 'wrong_tree'
      ;;
    artifact)
      commit_reported=$(_fvp_field "$report" VERIFY_ARTIFACT_SOURCE_COMMIT)
      commit_expected=$(git -C "$expected" rev-parse HEAD 2>/dev/null) || commit_expected=
      if [ -z "$commit_reported" ] || [ -z "$commit_expected" ]; then
        printf 'uncertain'
      elif [ "$reported" = "$expected_real" ] && [ "$commit_reported" = "$commit_expected" ]; then
        printf 'artifact_correct'
      else
        printf 'wrong_tree'
      fi
      ;;
    *)
      printf 'uncertain'
      ;;
  esac
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
    *)
      printf 'usage: %s classify <expected-worktree> <report-file>\n' "$0" >&2
      exit 2
      ;;
  esac
fi
