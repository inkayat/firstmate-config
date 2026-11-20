#!/usr/bin/env bash
# pinned-skills.sh <dest-root> - materialize every skill pinned in skills/external.lock at
# its exact pinned commit, WITHOUT touching ~/.agents or any machine link:
#   <dest-root>/skills/<installed-name>/   one directory per pinned skill
#   <dest-root>/references/                addyosmani's shared references (their skills link ../../references)
# The live suites take <dest-root>/skills as their read-only skill source
# (FM_ROLE_LIVE_SKILL_SRC, FM_WORKFLOW_LIVE_SKILL_SRC, FM_CONTRACT_LIVE_SKILL_SRC), so a live run
# sees exactly what ./install.sh would link, including pins the machine has not fetched yet.
#
# Sources, first match wins: each colon-separated directory of FM_LIVE_PIN_CLONES, then the
# install cache (FM_SKILL_CACHE, default ~/.local/share/firstmate-config/skills-src), laid out as
# <owner>-<repo>/. A clone that lacks the pinned commit is not used; a repository found nowhere
# is cloned from GitHub into a temporary directory (the only network use, only here, never by a worker).
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK="${FM_LIVE_PIN_LOCK:-$ROOT/skills/external.lock}"
dest=${1:?usage: pinned-skills.sh <dest-root>}
cache=${FM_SKILL_CACHE:-$HOME/.local/share/firstmate-config/skills-src}
extra=${FM_LIVE_PIN_CLONES:-}
[ -f "$LOCK" ] || { echo "pinned-skills: no lock file $LOCK" >&2; exit 1; }
mkdir -p "$dest/skills"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/fm-pinned-skills.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

find_clone() { # <repo-dir-name> <commit> -> prints a clone holding the commit, or nothing
  local name=$1 commit=$2 root oldifs=$IFS
  IFS=:
  for root in $extra "$cache"; do
    IFS=$oldifs
    [ -n "$root" ] && [ -e "$root/$name/.git" ] && git -C "$root/$name" cat-file -e "$commit^{commit}" 2>/dev/null && { printf '%s' "$root/$name"; return 0; }
    IFS=:
  done
  IFS=$oldifs
  return 0
}

n=0
while IFS="$(printf '\t')" read -r id repo commit path name; do
  case $id in ''|'#'*) continue ;; esac
  dir=$(printf '%s' "$repo" | tr '/' '-')
  src=$(find_clone "$dir" "$commit")
  if [ -z "$src" ]; then
    src="$scratch/$dir"
    if [ ! -e "$src/.git" ]; then
      git clone -q "https://github.com/$repo.git" "$src" || { echo "pinned-skills: cannot clone $repo" >&2; exit 1; }
    fi
    git -C "$src" cat-file -e "$commit^{commit}" 2>/dev/null || { echo "pinned-skills: $repo has no commit $commit" >&2; exit 1; }
  fi
  rm -rf "${dest:?}/skills/$name"
  if [ "$path" = . ]; then
    mkdir -p "$dest/skills/$name"
    git -C "$src" archive --format=tar "$commit" | tar -x -C "$dest/skills/$name"
  else
    x="$scratch/x-$n"; mkdir -p "$x"
    git -C "$src" archive --format=tar "$commit" "$path" | tar -x -C "$x"
    mv "$x/$path" "$dest/skills/$name"
  fi
  [ -f "$dest/skills/$name/SKILL.md" ] || { echo "pinned-skills: $id has no SKILL.md at $path" >&2; exit 1; }
  case $repo in
    addyosmani/*) [ -d "$dest/references" ] || git -C "$src" archive --format=tar "$commit" references | tar -x -C "$dest" ;;
  esac
  n=$((n + 1))
done < "$LOCK"
printf 'pinned-skills: %s skills materialized under %s/skills\n' "$n" "$dest"
