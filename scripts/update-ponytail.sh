#!/usr/bin/env bash
# update-ponytail.sh - intentional, reviewable Ponytail version bump.
#
# firstmate-config pins Ponytail (the shared ponytail/ponytail-review skills
# AND the Pi package's own separate checkout) to one exact commit in
# skills/external.lock for reproducibility: install.sh never tracks
# upstream HEAD, so every machine converges on the same bits with
# `git pull && ./install.sh`. This script is the only sanctioned way to move
# that pin. It never runs automatically (install.sh never calls it) and it
# never commits, merges, pushes, or tags - it edits the tracked lock file and
# refreshes this machine's local caches to match, leaving a reviewable
# `git diff` for a human to inspect, test, and commit through the normal
# workflow.
#
# Target selection: Ponytail publishes versioned release tags (verified
# against the real upstream with `git ls-remote --tags`: vX.Y.Z, e.g.
# v1.0.0, v4.10.0). This script's default target is upstream's remote
# default-branch HEAD *never* - a branch tip moves under it on every
# upstream commit, silently turning a "pinned" reproducible install into
# an unpinned one. Instead it discovers every stable (non-prerelease,
# non-beta/rc) release tag, picks the highest by semantic version, and
# resolves that exact tag to its exact commit SHA. Human intent is the
# release version; machine desired state is always the exact SHA stored
# in the lock. If two tags normalize to the same highest version but
# point at different commits, or no stable release tag exists at all,
# discovery is ambiguous and this script refuses to guess: it reports the
# ambiguity and writes nothing.
#
# Usage:
#   scripts/update-ponytail.sh                  update to the latest stable release (mutates)
#   scripts/update-ponytail.sh --check           report only; never mutates
#   scripts/update-ponytail.sh --ref <tag|sha>   update to an exact tag or commit, for deliberate
#                                                 testing; never a branch name (mutates)
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$CONFIG_ROOT/skills/external.lock"
SKILL_CACHE="${FM_SKILL_CACHE:-$HOME/.local/share/firstmate-config/skills-src}"
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"

fail() { printf 'update-ponytail: %s\n' "$1" >&2; exit 1; }

CHECK=0
REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --ref)
      [ $# -ge 2 ] || fail "--ref requires a value (usage: update-ponytail.sh [--check] [--ref <tag-or-sha>])"
      REF=$2; shift 2 ;;
    *) fail "unknown argument: $1 (usage: update-ponytail.sh [--check] [--ref <tag-or-sha>])" ;;
  esac
done
[ "$CHECK" -eq 0 ] || [ -z "$REF" ] || fail "--check and --ref cannot be combined - --check only ever reports, --ref only ever names a deliberate mutating target"

[ -f "$LOCK" ] || fail "no $LOCK"

# --- one authoritative pin: both ponytail rows must already agree, on the
#     same repo, not only the same commit -----------------------------------
impl_repo=$(awk -F'\t' '$1=="ponytail:implement"{print $2}' "$LOCK")
impl_sha=$(awk -F'\t' '$1=="ponytail:implement"{print $3}' "$LOCK")
review_repo=$(awk -F'\t' '$1=="ponytail:review"{print $2}' "$LOCK")
review_sha=$(awk -F'\t' '$1=="ponytail:review"{print $3}' "$LOCK")
[ -n "$impl_repo" ] && [ -n "$impl_sha" ] || fail "no ponytail:implement row in $LOCK"
[ -n "$review_repo" ] && [ -n "$review_sha" ] || fail "no ponytail:review row in $LOCK"
[ "$impl_repo" = "$review_repo" ] || fail "ponytail:implement/ponytail:review repos differ in $LOCK ($impl_repo vs $review_repo)"
[ "$impl_sha" = "$review_sha" ] || fail "ponytail:implement/ponytail:review pins have drifted apart in $LOCK ($impl_sha vs $review_sha)"
CURRENT_PIN=$impl_sha
REMOTE_URL="https://github.com/$impl_repo.git"

# --- mirror upstream (branches + tags) once ---------------------------------
scratch=$(mktemp -d "${TMPDIR:-/tmp}/update-ponytail.XXXXXX") || fail "cannot create a scratch directory"
trap 'rm -rf "$scratch"' EXIT
git clone -q --no-single-branch "$REMOTE_URL" "$scratch/mirror" 2>/dev/null || fail "cannot clone $REMOTE_URL"
mirror="$scratch/mirror"
git -C "$mirror" fetch -q --tags "$REMOTE_URL" 2>/dev/null || true

# strict X.Y.Z predicate, shared by discovery and --ref stable-labeling: only
# digits and dots, and exactly three non-empty dot-separated fields. A glob
# such as [0-9]*.[0-9]*.[0-9]* is NOT sufficient here - its trailing `*`
# swallows any extra ".N" suffix, so a malformed four-part tag like
# "1.2.3.4" would wrongly pass. Run in a subshell so the temporary IFS/`set
# --` never leaks into the caller's own positional parameters.
is_stable_version() { # <core, without a leading v>
  case "$1" in
    # reject non-digit/dot chars, and a leading, trailing, or doubled dot
    # outright - bash's `set -- $1` under IFS=. silently drops a trailing
    # empty field ("1.2.3." would otherwise count as exactly 3 fields), so
    # this predicate never gets to rely on the split alone.
    ''|*[!0-9.]*|.*|*.|*..*) return 1 ;;
  esac
  # SC2086: intentional unquoted split on IFS=. into exactly 3 fields; $1 is
  # already validated above as digits-and-dots only, so no globbing/word
  # boundary can introduce anything but the digit groups themselves.
  # shellcheck disable=SC2086
  ( IFS=.; set -- $1; [ $# -eq 3 ] && [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] )
}

# --- every stable (non-prerelease) semver release tag, as
#     "<normalized-version>\t<tag>\t<commit>" ---------------------------------
list_stable_tags() {
  git -C "$mirror" for-each-ref --format="$(printf '%%(refname:short)\t%%(objectname)\t%%(*objectname)')" refs/tags |
  while IFS="$(printf '\t')" read -r tag sha peeled; do
    core=${tag#v}
    is_stable_version "$core" || continue
    commit=${peeled:-$sha}
    printf '%s\t%s\t%s\n' "$core" "$tag" "$commit"
  done
}
STABLE_TAGS=$(list_stable_tags)

# --- current version: does the tracked pin match a known stable release? ---
CURRENT_VERSION=unknown
if [ -n "$STABLE_TAGS" ]; then
  current_match=$(printf '%s\n' "$STABLE_TAGS" | awk -F'\t' -v s="$CURRENT_PIN" '$3==s{print $2; exit}')
  [ -z "$current_match" ] || CURRENT_VERSION=$current_match
fi

# --- latest stable release: highest semver among $STABLE_TAGS. A single
#     highest version must resolve to exactly one commit; ties across
#     different commits, or no stable tag at all, are ambiguous -------------
DISCOVERY=none
LATEST_STABLE_VERSION=""
LATEST_STABLE_TAG=""
LATEST_STABLE_PIN=""
if [ -n "$STABLE_TAGS" ]; then
  top_version=$(printf '%s\n' "$STABLE_TAGS" | cut -f1 | sort -t. -k1,1nr -k2,2nr -k3,3nr | head -n1)
  candidates=$(printf '%s\n' "$STABLE_TAGS" | awk -F'\t' -v v="$top_version" '$1==v')
  distinct_shas=$(printf '%s\n' "$candidates" | cut -f3 | sort -u)
  if [ "$(printf '%s\n' "$distinct_shas" | wc -l | tr -d ' ')" -gt 1 ]; then
    DISCOVERY=ambiguous
  else
    DISCOVERY=ok
    LATEST_STABLE_VERSION=v$top_version
    LATEST_STABLE_TAG=$(printf '%s\n' "$candidates" | cut -f2 | sort | head -n1)
    LATEST_STABLE_PIN=$distinct_shas
  fi
fi

# --- resolve the requested/default target -----------------------------------
if [ -n "$REF" ]; then
  case "$REF" in
    *'*'*|*'?'*|*'['*) fail "--ref $REF looks like a glob pattern; only an exact tag name or a full commit SHA is accepted" ;;
  esac
  case "$REF" in
    *[!0-9a-fA-F]*) is_hex=0 ;;
    *) is_hex=1 ;;
  esac
  all_tags=$(git -C "$mirror" for-each-ref --format="$(printf '%%(refname:short)\t%%(objectname)\t%%(*objectname)')" refs/tags)
  if [ "$is_hex" -eq 1 ] && [ "${#REF}" -eq 40 ]; then
    TARGET_PIN=$(git -C "$mirror" rev-parse --verify -q "$REF^{commit}" 2>/dev/null) || fail "--ref $REF is not a commit reachable in $impl_repo"
    tagmatch=$(printf '%s\n' "$all_tags" | awk -F'\t' -v s="$TARGET_PIN" '{c=($3==""?$2:$3)} c==s{print $1; exit}')
    if [ -n "$tagmatch" ]; then TARGET_VERSION=$tagmatch; else TARGET_VERSION="(none; raw commit, not a tagged release)"; fi
  else
    tagref=$(printf '%s\n' "$all_tags" | awk -F'\t' -v t="$REF" '$1==t{print $2"\t"$3; exit}')
    [ -n "$tagref" ] || fail "--ref $REF is not an exact tag or a full 40-character commit SHA in $impl_repo (branch names such as $REF are not accepted, to avoid recreating automatic branch tracking)"
    ref_sha=$(printf '%s' "$tagref" | cut -f1)
    ref_peeled=$(printf '%s' "$tagref" | cut -f2)
    TARGET_PIN=${ref_peeled:-$ref_sha}
    TARGET_VERSION=$REF
  fi
  case "$TARGET_VERSION" in
    "(none;"*) : ;;
    *) is_stable_version "${TARGET_VERSION#v}" || TARGET_VERSION="$TARGET_VERSION (not a stable release)" ;;
  esac
elif [ "$CHECK" -eq 1 ]; then
  : # --check reports LATEST_STABLE_*, computed above; no TARGET_* needed
else
  case $DISCOVERY in
    none) fail "$impl_repo has no stable release tags (vX.Y.Z, excluding prerelease/beta/rc); refusing to guess a target - inspect upstream manually" ;;
    ambiguous) fail "$impl_repo has multiple tags for version v$top_version pointing at different commits; refusing to guess a target - inspect upstream manually" ;;
  esac
  TARGET_VERSION=$LATEST_STABLE_TAG
  TARGET_PIN=$LATEST_STABLE_PIN
fi

# =============================================================================
# --check: non-mutating report, exits nonzero only when discovery is ambiguous
# =============================================================================
if [ "$CHECK" -eq 1 ]; then
  printf 'CURRENT_VERSION: %s\n' "$CURRENT_VERSION"
  printf 'CURRENT_PIN: %s\n' "$CURRENT_PIN"
  case $DISCOVERY in
    ok)
      printf 'LATEST_STABLE_VERSION: %s\n' "$LATEST_STABLE_VERSION"
      printf 'LATEST_STABLE_PIN: %s\n' "$LATEST_STABLE_PIN"
      if [ "$CURRENT_PIN" = "$LATEST_STABLE_PIN" ]; then
        printf 'UPDATE_AVAILABLE: false\n'
      else
        printf 'UPDATE_AVAILABLE: true\n'
      fi
      exit 0
      ;;
    ambiguous)
      printf 'LATEST_STABLE_VERSION: ambiguous\n'
      printf 'LATEST_STABLE_PIN: ambiguous\n'
      printf 'UPDATE_AVAILABLE: ambiguous\n'
      fail "$impl_repo has multiple tags for version v$top_version pointing at different commits; refusing to guess - inspect upstream manually"
      ;;
    none)
      printf 'LATEST_STABLE_VERSION: none\n'
      printf 'LATEST_STABLE_PIN: none\n'
      printf 'UPDATE_AVAILABLE: ambiguous\n'
      fail "$impl_repo has no stable release tags (vX.Y.Z, excluding prerelease/beta/rc); refusing to guess - inspect upstream manually"
      ;;
  esac
fi

printf 'CURRENT_PIN: %s\n' "$CURRENT_PIN"
printf 'CURRENT_VERSION: %s\n' "$CURRENT_VERSION"
printf 'TARGET_VERSION: %s\n' "$TARGET_VERSION"
printf 'TARGET_PIN: %s\n' "$TARGET_PIN"

if [ "$CURRENT_PIN" = "$TARGET_PIN" ]; then
  printf 'update-ponytail: already at %s; nothing to do\n' "$TARGET_VERSION"
  exit 0
fi

# --- sanity-check the target commit's tree before touching anything tracked
for f in skills/ponytail/SKILL.md skills/ponytail-review/SKILL.md package.json; do
  git -C "$mirror" cat-file -e "$TARGET_PIN:$f" 2>/dev/null \
    || fail "$TARGET_PIN is missing $f; refusing to update the pin"
done

# --- update the one tracked source of truth ---------------------------------
tmp_lock=$(mktemp "${TMPDIR:-/tmp}/external.lock.XXXXXX") || fail "cannot create a temp file"
if awk -F'\t' -v OFS='\t' -v repo="$impl_repo" -v cur="$CURRENT_PIN" -v tgt="$TARGET_PIN" \
  '$2==repo && $3==cur {$3=tgt} {print}' "$LOCK" > "$tmp_lock"; then
  mv "$tmp_lock" "$LOCK" || fail "cannot write $LOCK"
else
  fail "cannot rewrite $LOCK"
fi

# --- refresh the shared skill cache and the Pi package's own separate
#     checkout to the same commit (never edit files inside either clone)
refresh() { # <dir>
  mkdir -p "$(dirname "$1")"
  if [ -d "$1/.git" ]; then
    git -C "$1" fetch -q "$REMOTE_URL" 2>/dev/null || fail "cannot fetch $REMOTE_URL into $1"
  else
    git clone -q "$REMOTE_URL" "$1" || fail "cannot clone $REMOTE_URL into $1"
  fi
  git -C "$1" checkout -q "$TARGET_PIN" || fail "cannot check out $TARGET_PIN in $1"
}
refresh "$SKILL_CACHE/$(printf '%s' "$impl_repo" | tr '/' '-')"
refresh "$PI_AGENT_DIR/git/github.com/$impl_repo"

# --- validation is authoritative, not informational: confirm the one
#     tracked pin, the shared skill cache, and the Pi package checkout all
#     now agree on TARGET_PIN before reporting success
new_impl_sha=$(awk -F'\t' '$1=="ponytail:implement"{print $3}' "$LOCK")
new_review_sha=$(awk -F'\t' '$1=="ponytail:review"{print $3}' "$LOCK")
cache_dir="$SKILL_CACHE/$(printf '%s' "$impl_repo" | tr '/' '-')"
pkg_dir="$PI_AGENT_DIR/git/github.com/$impl_repo"
cache_head=$(git -C "$cache_dir" rev-parse HEAD 2>/dev/null || printf '')
pkg_head=$(git -C "$pkg_dir" rev-parse HEAD 2>/dev/null || printf '')
[ "$new_impl_sha" = "$TARGET_PIN" ] || fail "$LOCK ponytail:implement is $new_impl_sha, not $TARGET_PIN after the update"
[ "$new_review_sha" = "$TARGET_PIN" ] || fail "$LOCK ponytail:review is $new_review_sha, not $TARGET_PIN after the update"
[ "$cache_head" = "$TARGET_PIN" ] || fail "$cache_dir is at $cache_head, not $TARGET_PIN after refresh"
[ "$pkg_head" = "$TARGET_PIN" ] || fail "$pkg_dir is at $pkg_head, not $TARGET_PIN after refresh"

printf 'update-ponytail: pinned %s to %s (%s, was %s)\n' "$impl_repo" "$TARGET_PIN" "$TARGET_VERSION" "$CURRENT_PIN"
printf 'update-ponytail: shared skill cache and Pi package checkout both verified at %s\n' "$TARGET_PIN"
printf "update-ponytail: this never commits/pushes/merges - review 'git diff -- skills/external.lock', run the tests, then commit through the normal workflow\n"
