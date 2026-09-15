#!/usr/bin/env bash
# version.sh - fixture-based acceptance for `fm version` / `fm version --json`.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FM="$CONFIG_ROOT/bin/fm"
failed=0
pass(){ printf 'ok   - %s\n' "$1"; }
fail(){ printf 'FAIL - %s\n' "$1" >&2; failed=1; }
contains(){ case $2 in *"$3"*) pass "$1";; *) fail "$1 (missing '$3')";; esac; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-version-test.XXXXXX") || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT
FAKE_BIN="$TMP_ROOT/bin"; mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/pi" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { printf 'pi 9.9.9\n'; exit 0; }
exit 64
SH
cat > "$FAKE_BIN/omp" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { printf 'omp 8.8.8\n'; exit 0; }
exit 64
SH
cat > "$FAKE_BIN/herdr" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { printf 'herdr 7.7.7\n'; exit 0; }
exit 64
SH
chmod +x "$FAKE_BIN/pi" "$FAKE_BIN/omp" "$FAKE_BIN/herdr"

make_repo(){
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email test@example.invalid
  git -C "$1" config user.name Test
  printf '%s\n' base > "$1/file.txt"
  git -C "$1" add file.txt
  git -C "$1" commit -q -m init
  git -C "$1" tag v1.2.3
}

CONFIG_FIXTURE="$TMP_ROOT/config"; FIRSTMATE_FIXTURE="$TMP_ROOT/firstmate"; HOME_FIXTURE="$TMP_ROOT/home"
make_repo "$CONFIG_FIXTURE"; make_repo "$FIRSTMATE_FIXTURE"; mkdir -p "$HOME_FIXTURE"
mkdir -p "$CONFIG_FIXTURE/bin" "$CONFIG_FIXTURE/firstmate"
cp "$CONFIG_ROOT/bin/fm" "$CONFIG_FIXTURE/bin/fm"
cp "$CONFIG_ROOT/bin/fm-version" "$CONFIG_FIXTURE/bin/fm-version"
cp "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh" "$CONFIG_FIXTURE/firstmate/fm-stack-manifest.sh"
cp "$CONFIG_ROOT/firstmate/stack-manifest.tsv" "$CONFIG_FIXTURE/firstmate/stack-manifest.tsv"

# shellcheck source=firstmate/fm-stack-manifest.sh
. "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh"
stack_manifest_load "$CONFIG_ROOT/firstmate/stack-manifest.tsv"
MANIFEST_COMMIT=$SM_FIRSTMATE_COMMIT

run_version(){ HOME="$HOME_FIXTURE" FIRSTMATE_ROOT="$FIRSTMATE_FIXTURE" FM_HOME="$TMP_ROOT/fm-home" PATH="$FAKE_BIN:/usr/bin:/bin" "$CONFIG_FIXTURE/bin/fm" version "$@"; }

out=$(run_version)
contains 'human includes config tag' "$out" 'firstmate-config: v1.2.3'
contains 'human includes firstmate path' "$out" "official FirstMate: $FIRSTMATE_FIXTURE"
contains 'human includes pi version' "$out" 'Pi: pi 9.9.9'
contains 'human includes fm home' "$out" "FM_HOME: $TMP_ROOT/fm-home"
contains 'human includes the validated FirstMate baseline from the shared manifest' "$out" "Validated FirstMate baseline: $MANIFEST_COMMIT"

printf 'dirty\n' >> "$CONFIG_FIXTURE/file.txt"
out=$(run_version)
contains 'dirty config is reported' "$out" 'firstmate-config: v1.2.3'
contains 'dirty config state is reported' "$out" 'dirty'
git -C "$CONFIG_FIXTURE" checkout -q -- file.txt
printf 'dirty\n' >> "$FIRSTMATE_FIXTURE/file.txt"
out=$(run_version)
contains 'dirty official firstmate is reported' "$out" 'official FirstMate:'
contains 'dirty official state is reported' "$out" 'dirty'

rm -f "$FAKE_BIN/omp"
out=$(run_version)
contains 'missing optional version is unknown' "$out" 'OMP: unknown'

json=$(run_version --json)
if command -v python3 >/dev/null 2>&1; then
  printf '%s' "$json" | MANIFEST_COMMIT="$MANIFEST_COMMIT" python3 -c 'import json,os,sys; o=json.load(sys.stdin); assert o["schema_version"]==2; assert o["firstmate_config"]["tag"]=="v1.2.3"; assert o["firstmate"]["path"]; assert o["components"]["omp"]=="unknown"; assert o["fm_home"]; assert o["stack_manifest"]["firstmate_validated_commit"]==os.environ["MANIFEST_COMMIT"]' && pass 'json schema is valid' || fail 'json schema is valid'
else
  contains 'json has schema version' "$json" '"schema_version":2'
fi
contains 'json carries the shared manifest'"'"'s validated commit, not a duplicated literal' "$json" "\"firstmate_validated_commit\":\"$MANIFEST_COMMIT\""

[ "$failed" -eq 0 ] || exit 1
