#!/usr/bin/env bash
# Offline guards: never execute the update operation, even in fixtures.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME" "$TMP/config/bin" "$TMP/config/firstmate" "$TMP/source"
cp "$ROOT/bin/fm-update" "$TMP/config/bin/"
cp "$ROOT/firstmate/"{fm-stack-manifest.sh,stack-manifest.tsv} "$TMP/config/firstmate/"
git init -q -b selected "$TMP/source"
git -C "$TMP/source" config user.name Fixture
git -C "$TMP/source" config user.email fixture@example.invalid
printf fixture > "$TMP/source/AGENTS.md"
git -C "$TMP/source" add .
git -C "$TMP/source" commit -qm base
pin=$(git -C "$TMP/source" rev-parse HEAD)
# Real manifest loader owns parsing; fixture values differ intentionally from production.
awk -F '\t' -v OFS='\t' -v pin="$pin" '
$1=="firstmate_branch" {$2="selected"}
$1=="firstmate_validated_commit" {$2=pin}
{print}' "$ROOT/firstmate/stack-manifest.tsv" > "$TMP/config/firstmate/stack-manifest.tsv"
git -C "$TMP/source" remote add origin https://github.com/inkayat/firstmate.git
git -C "$TMP/source" remote add upstream https://github.com/kunchenguid/firstmate.git
git -C "$TMP/source" update-ref refs/remotes/origin/selected "$pin"
git -C "$TMP/source" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/selected
git -C "$TMP/source" config branch.selected.remote origin
git -C "$TMP/source" config branch.selected.merge refs/heads/selected
git init -q -b main "$TMP/config"
git -C "$TMP/config" config user.name Fixture
git -C "$TMP/config" config user.email fixture@example.invalid
git -C "$TMP/config" add .
git -C "$TMP/config" commit -qm config
git -C "$TMP/config" remote add origin https://example.invalid/config.git
git -C "$TMP/config" update-ref refs/remotes/origin/main HEAD
git -C "$TMP/config" config branch.main.remote origin
git -C "$TMP/config" config branch.main.merge refs/heads/main
mkdir -p "$TMP/guard-bin"
cat > "$TMP/guard-bin/git" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  case $arg in fetch|ls-remote|pull|push|merge|checkout|switch|clone)
    printf 'forbidden mutating/network Git command: %s\n' "$arg" >&2; exit 98 ;;
  esac
done
exec "$REAL_GIT" "$@"
SH
chmod +x "$TMP/guard-bin/git"
REAL_GIT=$(command -v git)
export REAL_GIT
check() { PATH="$TMP/guard-bin:$PATH" FIRSTMATE_ROOT="$TMP/source" FM_CONFIG_ENV=/dev/null bash "$TMP/config/bin/fm-update" --check; }
refuses() {
  local out
  if out=$(check 2>&1); then printf 'FAIL - %s accepted\n' "$1"; exit 1; fi
  case $out in *"$2"*) printf 'PASS - %s\n' "$1" ;; *) printf '%s\n' "$out"; exit 1 ;; esac
}
before=$(git -C "$TMP/source" show-ref)
out=$(check)
case $out in *'UPDATE_BRANCH: selected'*'UPDATE_TARGET: origin/selected'*'CHECK_ONLY: local refs; no fetch, update or install'*) ;; *) printf '%s\n' "$out"; exit 1 ;; esac
[ "$before" = "$(git -C "$TMP/source" show-ref)" ]
printf 'PASS - explicit nondefault fork branch resolves without network or writes\n'
git -C "$TMP/source" remote set-url origin https://github.com/kunchenguid/firstmate.git
refuses 'official origin is not an implicit fallback' 'expected exactly'
git -C "$TMP/source" remote set-url origin https://github.com/inkayat/firstmate.git
git -C "$TMP/source" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
refuses 'native bootstrap cannot follow fork default main' 'origin/HEAD'
git -C "$TMP/source" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/selected
git -C "$TMP/source" checkout -qb wrong
refuses 'wrong checked-out branch' "expected selected"
git -C "$TMP/source" checkout -q selected
git -C "$TMP/source" config branch.selected.merge refs/heads/main
refuses 'branch tracking does not silently select main' 'does not track'
git -C "$TMP/source" config branch.selected.merge refs/heads/selected
git -C "$TMP/source" config url.https://example.invalid/redirect.insteadOf https://github.com/inkayat/firstmate.git
refuses 'insteadOf source rewrite' 'rewritten'
git -C "$TMP/source" config --unset-all url.https://example.invalid/redirect.insteadOf
printf dirty > "$TMP/config/local"
refuses 'dirty config blocks source advancement' 'uncommitted'
rm "$TMP/config/local"
git -C "$TMP/config" checkout -q --detach
refuses 'detached config' 'detached HEAD'
git -C "$TMP/config" checkout -q main
printf dirty > "$TMP/source/untracked"
refuses 'dirty source remains untouched' 'uncommitted'
[ "$(cat "$TMP/source/untracked")" = dirty ]
rm "$TMP/source/untracked"
printf local > "$TMP/source/local"
git -C "$TMP/source" add .
git -C "$TMP/source" commit -qm local
refuses 'unlanded source commit' 'unlanded work'
git -C "$TMP/source" checkout -qb remote-tip "$pin"
printf remote > "$TMP/source/remote"
git -C "$TMP/source" add .
git -C "$TMP/source" commit -qm remote
git -C "$TMP/source" update-ref refs/remotes/origin/selected HEAD
git -C "$TMP/source" checkout -q selected
refuses 'diverged source history' 'diverged'
printf 'UPDATE SOURCE TESTS PASSED\n'
