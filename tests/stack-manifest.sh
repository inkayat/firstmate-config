#!/usr/bin/env bash
# stack-manifest.sh - fixture-based acceptance for firstmate/stack-manifest.tsv,
# firstmate/fm-stack-manifest.sh (the one parsing/comparison owner), and the
# compatibility surfaces install.sh, bin/fm-doctor, and bin/fm-version build
# on top of it.
#
# Five sections:
#   A. Unit tests of the shared library's pure functions, called directly -
#      no process spawn, no fixture tool binaries.
#   B. bin/fm-doctor end to end, against a disposable copy of fm-doctor under
#      its own fake CONFIG_ROOT (mirrors tests/doctor.sh scenario 7's own
#      established pattern), a real local Git repository standing in for
#      FIRSTMATE_ROOT (so firstmate.commit_compat has real Git-graph
#      evidence to reason from), and fake pi/omp/herdr binaries whose
#      reported --version output is configurable per scenario.
#   C. install.sh end to end, against a disposable copy of install.sh under
#      its own fake CONFIG_ROOT, cloning from a real *local* Git repository
#      (a file:// origin, never the network) so the clone-and-pin path is
#      exercised for real without any network dependency.
#   D. Cross-cutting proofs: install.sh and fm-doctor consuming the exact
#      same tracked manifest, `fm version` surfacing that manifest's
#      identity, and path independence (no OS-specific path assumption
#      baked into the parsing/comparison logic).
#   E. The Agent Library lifecycle (install.sh step 10, --verify,
#      --library-rollback, fm doctor and fm version) against a real file://
#      Library origin: real receipts, real lstat identities, real flock
#      contention between separate processes, and real fetch/auth failures.
#      Its only test doubles sit at external boundaries: a python3 wrapper
#      whose sitecustomize injects a failure or a process death at one named
#      os.replace/flock call, and a git wrapper that blocks, corrupts or
#      refuses one named git operation.
#
# Every scenario is offline and disposable: no real Portail repository, no
# paid inference or quota, no network access (local Git origins only, never
# https://github.com/...), and no machine-specific absolute path baked into
# an assertion - production expected values (the real FirstMate repo/commit,
# the real tested component versions) are always read dynamically from the
# tracked firstmate/stack-manifest.tsv through firstmate/fm-stack-manifest.sh,
# never duplicated as separate literals here.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The runner's own Library variables must never reach a fixture: every
# scenario below names its own data home explicitly.
unset AGENT_LIBRARY_ROOT XDG_DATA_HOME

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi; }
contains() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in '$2')" ;; esac; }
not_contains() { case $2 in *"$3"*) fail "$1 (unexpectedly found '$3' in '$2')" ;; *) pass "$1" ;; esac; }

# shellcheck source=firstmate/fm-stack-manifest.sh
. "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-stack-manifest-test.XXXXXX") || exit 1
TMP_ROOT=$(cd "$TMP_ROOT" && pwd)
trap 'rm -rf "$TMP_ROOT"' EXIT

SYS_BIN="$TMP_ROOT/sysbin"
mkdir -p "$SYS_BIN"
for _tool in bash git uname sed awk grep wc date find stat readlink basename dirname tr head cat mkdir env python3 ln cp mv rm chmod mktemp sort; do
  _p=$(command -v "$_tool" 2>/dev/null) && ln -sf "$_p" "$SYS_BIN/$_tool"
done

# =============================================================================
# A. Unit tests: firstmate/fm-stack-manifest.sh's pure functions
# =============================================================================

check 'extract: leading version from "pi 9.9.9"' '9.9.9' "$(stack_version_extract 'pi 9.9.9')"
check 'extract: leading version from slash-joined "omp/18.1.21"' '18.1.21' "$(stack_version_extract 'omp/18.1.21')"
check 'extract: leading version from "herdr 0.8.0"' '0.8.0' "$(stack_version_extract 'herdr 0.8.0')"
check 'extract: no digits at all -> empty, never guessed' '' "$(stack_version_extract 'no digits here')"
check 'extract: a single bare integer is not a version (needs >=2 components)' '' "$(stack_version_extract 'build 5')"

check 'compare: 9.9.9 > 0.85.1' gt "$(stack_version_compare 9.9.9 0.85.1)"
check 'compare: 0.85.1 == 0.85.1' eq "$(stack_version_compare 0.85.1 0.85.1)"
check 'compare: 0.10.0 < 0.85.1' lt "$(stack_version_compare 0.10.0 0.85.1)"
check 'compare: missing trailing components treated as 0 (1.2 == 1.2.0)' eq "$(stack_version_compare 1.2 1.2.0)"
check 'compare: leading zero does not become octal (0.08.0 == 0.8.0)' eq "$(stack_version_compare 0.08.0 0.8.0)"

check 'component_compat: exact match is PASS' PASS "$(stack_component_compat 0.85.1 0.85.1 0.85.1)"
check 'component_compat: newer than tested is WARNING, never a guessed FAIL' WARNING "$(stack_component_compat 9.9.9 0.85.1 0.85.1)"
check 'component_compat: below minimum is FAIL' FAIL "$(stack_component_compat 0.10.0 0.85.1 0.85.1)"
check 'component_compat: between min and tested is PASS' PASS "$(stack_component_compat 0.85.1 0.80.0 0.90.0)"
check 'component_compat: empty version is UNKNOWN, never a guessed FAIL' UNKNOWN "$(stack_component_compat '' 0.85.1 0.85.1)"
check 'component_compat: missing policy bound is UNKNOWN' UNKNOWN "$(stack_component_compat 0.85.1 '' 0.85.1)"

stack_manifest_load "$CONFIG_ROOT/firstmate/stack-manifest.tsv" && pass 'manifest_load: the real tracked manifest loads' || fail "manifest_load: the real tracked manifest failed to load: $SM_LOAD_ERROR"
REAL_SM_FIRSTMATE_REPO=$SM_FIRSTMATE_REPO
REAL_SM_FIRSTMATE_COMMIT=$SM_FIRSTMATE_COMMIT
check 'manifest_load: real firstmate_repo is a github.com URL' 'https://github.com/kunchenguid/firstmate.git' "$REAL_SM_FIRSTMATE_REPO"
check 'manifest_load: real firstmate_validated_commit is a full 40-hex SHA' 40 "${#REAL_SM_FIRSTMATE_COMMIT}"

stack_manifest_load "$TMP_ROOT/no-such-manifest.tsv" && fail 'manifest_load: a missing file must not report success' || pass 'manifest_load: a missing file reports failure'
contains 'manifest_load: missing-file error names the path' "$SM_LOAD_ERROR" "$TMP_ROOT/no-such-manifest.tsv"

MALFORMED="$TMP_ROOT/malformed.tsv"
printf 'schema_version\t1\nfirstmate_repo\thttps://example.invalid/x.git\n' > "$MALFORMED"
stack_manifest_load "$MALFORMED" && fail 'manifest_load: a manifest missing required keys must not report success' || pass 'manifest_load: a manifest missing required keys reports failure'
contains 'manifest_load: malformed-file error names a missing key' "$SM_LOAD_ERROR" 'PI_MIN'

# --- value validation: schema pin, commit format, numeric versions, min<=
#     tested, duplicate required keys, and unknown keys never overwriting a
#     known field. mkmanifest below writes a complete, otherwise-valid
#     manifest so each scenario below corrupts exactly one thing.
VALID_COMMIT=$(printf 'a%.0s' {1..40})
mkmanifest() { # <path> <schema> <repo> <commit> <pi_min> <pi_tested> <omp_min> <omp_tested> <herdr_min> <herdr_tested>
  local _out=$1
  printf 'schema_version\t%s\nfirstmate_repo\t%s\nfirstmate_validated_commit\t%s\npi_min_version\t%s\npi_tested_version\t%s\nomp_min_version\t%s\nomp_tested_version\t%s\nherdr_min_version\t%s\nherdr_tested_version\t%s\n' \
    "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" > "$_out"
}

UNSUPPORTED_SCHEMA="$TMP_ROOT/unsupported-schema.tsv"
mkmanifest "$UNSUPPORTED_SCHEMA" 99 https://example.invalid/x.git "$VALID_COMMIT" 0.85.1 0.85.1 18.1.21 18.1.21 0.8.0 0.8.0
stack_manifest_load "$UNSUPPORTED_SCHEMA" && fail 'manifest_load: an unsupported schema_version must not report success' || pass 'manifest_load: an unsupported schema_version reports failure'
contains 'manifest_load: unsupported schema_version error names the field' "$SM_LOAD_ERROR" 'schema_version'

BAD_COMMIT="$TMP_ROOT/bad-commit.tsv"
mkmanifest "$BAD_COMMIT" 1 https://example.invalid/x.git deadbeef 0.85.1 0.85.1 18.1.21 18.1.21 0.8.0 0.8.0
stack_manifest_load "$BAD_COMMIT" && fail 'manifest_load: a non-40-hex firstmate_validated_commit must not report success' || pass 'manifest_load: a non-40-hex firstmate_validated_commit reports failure'
contains 'manifest_load: bad-commit error names the field' "$SM_LOAD_ERROR" 'firstmate_validated_commit'

BAD_VERSION="$TMP_ROOT/bad-version.tsv"
mkmanifest "$BAD_VERSION" 1 https://example.invalid/x.git "$VALID_COMMIT" latest 0.85.1 18.1.21 18.1.21 0.8.0 0.8.0
stack_manifest_load "$BAD_VERSION" && fail 'manifest_load: a non-numeric tool version must not report success' || pass 'manifest_load: a non-numeric tool version reports failure'
contains 'manifest_load: non-numeric version error names the field' "$SM_LOAD_ERROR" 'pi_min_version'

BAD_RANGE="$TMP_ROOT/bad-range.tsv"
mkmanifest "$BAD_RANGE" 1 https://example.invalid/x.git "$VALID_COMMIT" 9.9.9 0.1.0 18.1.21 18.1.21 0.8.0 0.8.0
stack_manifest_load "$BAD_RANGE" && fail 'manifest_load: pi_min_version greater than pi_tested_version must not report success' || pass 'manifest_load: pi_min_version greater than pi_tested_version reports failure'
contains 'manifest_load: min>tested error names the field' "$SM_LOAD_ERROR" 'pi_min_version'

DUP_KEY="$TMP_ROOT/dup-key.tsv"
printf 'schema_version\t1\nschema_version\t1\nfirstmate_repo\thttps://example.invalid/x.git\nfirstmate_validated_commit\t%s\npi_min_version\t0.85.1\npi_tested_version\t0.85.1\nomp_min_version\t18.1.21\nomp_tested_version\t18.1.21\nherdr_min_version\t0.8.0\nherdr_tested_version\t0.8.0\n' "$VALID_COMMIT" > "$DUP_KEY"
stack_manifest_load "$DUP_KEY" && fail 'manifest_load: a duplicate required key must not report success' || pass 'manifest_load: a duplicate required key reports failure'
contains 'manifest_load: duplicate-key error names the key' "$SM_LOAD_ERROR" 'duplicate'

EXTRA_KEY="$TMP_ROOT/extra-key.tsv"
printf 'schema_version\t1\nfirstmate_repo\thttps://example.invalid/x.git\nfirstmate_validated_commit\t%s\npi_min_version\t0.85.1\npi_tested_version\t0.85.1\nomp_min_version\t18.1.21\nomp_tested_version\t18.1.21\nherdr_min_version\t0.8.0\nherdr_tested_version\t0.8.0\nfuture_unknown_key\tsome-value\n' "$VALID_COMMIT" > "$EXTRA_KEY"
stack_manifest_load "$EXTRA_KEY" && pass 'manifest_load: an unknown future key is ignored, load still succeeds' || fail "manifest_load: an unknown future key incorrectly broke load: $SM_LOAD_ERROR"
check 'manifest_load: unknown key never overwrites a known field (pi_min_version)' 0.85.1 "$SM_PI_MIN"

# --- E28: the optional Agent Library pin (library_repo/commit/tree plus the
#          distribution-only library_ref). mklib writes the valid base
#          manifest plus exactly the extra rows given, one per argument.
LIB_C40=0123456789abcdef0123456789abcdef01234567
LIB_T40=89abcdef0123456789abcdef0123456789abcdef
mklib() { # <path> [<key>\t<value> ...]
  local _out=$1; shift
  mkmanifest "$_out" 1 https://example.invalid/x.git "$VALID_COMMIT" 0.85.1 0.85.1 18.1.21 18.1.21 0.8.0 0.8.0
  [ "$#" -eq 0 ] || printf '%s\n' "$@" >> "$_out"
}
LIB_OK="$TMP_ROOT/lib-ok.tsv"
mklib "$LIB_OK" "library_repo	https://example.invalid/lib.git" "library_commit	$LIB_C40" "library_tree	$LIB_T40" "library_ref	refs/tags/lib-v1"
stack_manifest_load "$LIB_OK" && pass 'E28 manifest_load: a complete Library pin loads' || fail "E28 manifest_load: a complete Library pin failed to load: $SM_LOAD_ERROR"
check 'E28 manifest_load: library_repo is parsed' https://example.invalid/lib.git "${SM_LIBRARY_REPO-}"
check 'E28 manifest_load: library_commit is parsed' "$LIB_C40" "${SM_LIBRARY_COMMIT-}"
check 'E28 manifest_load: library_tree is parsed' "$LIB_T40" "${SM_LIBRARY_TREE-}"
check 'E28 manifest_load: library_ref is parsed' refs/tags/lib-v1 "${SM_LIBRARY_REF-}"
LIB_NONE="$TMP_ROOT/lib-none.tsv"
mklib "$LIB_NONE"
stack_manifest_load "$LIB_NONE" && pass 'E28 manifest_load: no Library rows at all still loads' || fail "E28 manifest_load: a manifest without Library rows failed: $SM_LOAD_ERROR"
check 'E28 manifest_load: a later load without Library rows never keeps a stale library_commit' '' "${SM_LIBRARY_COMMIT-}"
check 'E28 manifest_load: a later load without Library rows never keeps a stale library_repo' '' "${SM_LIBRARY_REPO-}"
LIB_SHA256="$TMP_ROOT/lib-sha256.tsv"
mklib "$LIB_SHA256" "library_repo	https://example.invalid/lib.git" "library_commit	$LIB_C40$(printf 'c%.0s' {1..24})" "library_tree	$LIB_T40$(printf 'd%.0s' {1..24})"
stack_manifest_load "$LIB_SHA256" && pass 'E28 manifest_load: a 64-hex (sha256 repository) commit and tree load' || fail "E28 manifest_load: a 64-hex pin failed: $SM_LOAD_ERROR"
lib_rejects() { # <label> <expected error fragment> <rows...>
  local _label=$1 _frag=$2 _f="$TMP_ROOT/lib-bad.tsv"; shift 2
  mklib "$_f" "$@"
  if stack_manifest_load "$_f"; then fail "E28 manifest_load: $_label must not load"; else contains "E28 manifest_load: $_label is a load error naming the problem" "$SM_LOAD_ERROR" "$_frag"; fi
}
lib_rejects 'repo and commit without a tree' 'library_repo, library_commit and library_tree together' "library_repo	https://example.invalid/lib.git" "library_commit	$LIB_C40"
lib_rejects 'a tree alone' 'library_repo, library_commit and library_tree together' "library_tree	$LIB_T40"
lib_rejects 'a library_ref without the pin' 'library_repo, library_commit and library_tree together' "library_ref	refs/tags/lib-v1"
lib_rejects 'an abbreviated commit' 'library_commit' "library_repo	https://example.invalid/lib.git" "library_commit	0123456" "library_tree	$LIB_T40"
lib_rejects 'an uppercase commit' 'library_commit' "library_repo	https://example.invalid/lib.git" "library_commit	$(printf 'A%.0s' {1..40})" "library_tree	$LIB_T40"
lib_rejects 'a tree that is not hex' 'library_tree' "library_repo	https://example.invalid/lib.git" "library_commit	$LIB_C40" "library_tree	HEAD"
lib_rejects 'a 64-hex tree for a 40-hex commit' 'library_tree' "library_repo	https://example.invalid/lib.git" "library_commit	$LIB_C40" "library_tree	$LIB_T40$(printf 'd%.0s' {1..24})"
lib_rejects 'a duplicate library_commit' 'duplicate key: library_commit' "library_repo	https://example.invalid/lib.git" "library_commit	$LIB_C40" "library_commit	$LIB_C40" "library_tree	$LIB_T40"
lib_rejects 'a library_ref outside refs/tags/' 'library_ref' "library_repo	https://example.invalid/lib.git" "library_commit	$LIB_C40" "library_tree	$LIB_T40" "library_ref	refs/heads/main"
lib_rejects 'a library_repo with whitespace' 'library_repo' "library_repo	https://example.invalid/my lib.git" "library_commit	$LIB_C40" "library_tree	$LIB_T40"
lib_rejects 'a library_repo carrying URL credentials' 'credentials' "library_repo	https://someone:fm-secret-token@example.invalid/lib.git" "library_commit	$LIB_C40" "library_tree	$LIB_T40"
not_contains 'E28 manifest_load: the credential error never echoes the secret' "$SM_LOAD_ERROR" 'fm-secret-token'

# stack_commit_relation: a small synthetic Git graph exercising every outcome.
REL_REPO="$TMP_ROOT/rel-repo"
mkdir -p "$REL_REPO"
git -C "$REL_REPO" init -q
git -C "$REL_REPO" config user.email t@example.invalid
git -C "$REL_REPO" config user.name t
printf a > "$REL_REPO/f"; git -C "$REL_REPO" add -A; git -C "$REL_REPO" commit -q -m c1
REL_C1=$(git -C "$REL_REPO" rev-parse HEAD)
printf b > "$REL_REPO/f"; git -C "$REL_REPO" add -A; git -C "$REL_REPO" commit -q -m c2
REL_C2=$(git -C "$REL_REPO" rev-parse HEAD)
git -C "$REL_REPO" checkout -qb diverged "$REL_C1"
printf c > "$REL_REPO/g"; git -C "$REL_REPO" add -A; git -C "$REL_REPO" commit -q -m c3
REL_C3=$(git -C "$REL_REPO" rev-parse HEAD)

git -C "$REL_REPO" checkout -q "$REL_C2"
check 'commit_relation: HEAD is the baseline -> exact' exact "$(stack_commit_relation "$REL_REPO" "$REL_C2")"
check 'commit_relation: HEAD is a descendant of the baseline -> descendant' descendant "$(stack_commit_relation "$REL_REPO" "$REL_C1")"

git -C "$REL_REPO" checkout -q "$REL_C1"
check 'commit_relation: HEAD is an ancestor of the baseline -> ancestor (behind)' ancestor "$(stack_commit_relation "$REL_REPO" "$REL_C2")"

git -C "$REL_REPO" checkout -q "$REL_C3"
check 'commit_relation: neither is an ancestor of the other -> diverged' diverged "$(stack_commit_relation "$REL_REPO" "$REL_C2")"
check 'commit_relation: baseline object absent from local history -> unknown, never fetched or guessed' unknown "$(stack_commit_relation "$REL_REPO" deadbeefdeadbeefdeadbeefdeadbeefdeadbeef)"
check 'commit_relation: not a Git repository at all -> unknown' unknown "$(stack_commit_relation "$TMP_ROOT" "$REL_C2")"

# =============================================================================
# B. bin/fm-doctor end to end
# =============================================================================

DOC_CFG="$TMP_ROOT/doc-cfg"
mkdir -p "$DOC_CFG/bin" "$DOC_CFG/firstmate" \
  "$DOC_CFG/roles/senior-fullstack" "$DOC_CFG/roles/architecture" "$DOC_CFG/roles/tenth-man"
cp "$CONFIG_ROOT/bin/fm-doctor" "$DOC_CFG/bin/fm-doctor"
ln -s "$CONFIG_ROOT/bin/fm" "$DOC_CFG/bin/fm"
chmod +x "$DOC_CFG/bin/fm-doctor"
cp "$CONFIG_ROOT/firstmate/fm-captain-lib.sh" "$DOC_CFG/firstmate/fm-captain-lib.sh"
cp "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh" "$DOC_CFG/firstmate/fm-stack-manifest.sh"
cp "$CONFIG_ROOT/firstmate/captain-startup-models.tsv" "$DOC_CFG/firstmate/captain-startup-models.tsv"
cp "$CONFIG_ROOT/firstmate/crew-dispatch.json" "$DOC_CFG/firstmate/crew-dispatch.json"
for r in senior-fullstack architecture tenth-man; do
  printf -- '---\nname: fm-%s\ndescription: fixture role\n---\n# role\n' "$r" > "$DOC_CFG/roles/$r/ROLE.md"
done

DOC_LAUNCHER_OK="$TMP_ROOT/doc-launcher-ok"
mkdir -p "$DOC_LAUNCHER_OK"
ln -s "$CONFIG_ROOT/bin/fm" "$DOC_LAUNCHER_OK/fm"

DOC_FAKE_BIN="$TMP_ROOT/doc-fake-bin"
mkdir -p "$DOC_FAKE_BIN"
cat > "$DOC_FAKE_BIN/pi" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  --version) printf '%s\n' "${FM_TEST_PI_VERSION:-0.85.1}"; exit 0 ;;
  list) printf 'User packages:\n  npm:pi-claude-code-provider\n'; exit 0 ;;
  --list-models)
    m=${2:-}
    printf 'provider      model        context  max-out  thinking  images\n'
    printf '%s  %s  1K  1K  yes  no\n' "${m%%/*}" "${m#*/}"
    exit 0 ;;
  auth)
    if [ "${2:-}" = check ]; then printf '{"status":"ready","provider":"test","authType":"test"}\n'; exit 0; fi
    exit 64 ;;
  *) exit 64 ;;
esac
SH
chmod +x "$DOC_FAKE_BIN/pi"
cat > "$DOC_FAKE_BIN/claude" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = auth ] && [ "${2:-}" = status ]; then
  printf '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"max"}\n'
  exit 0
fi
exit 64
SH
chmod +x "$DOC_FAKE_BIN/claude"
cat > "$DOC_FAKE_BIN/omp" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  --version) printf 'omp/%s\n' "${FM_TEST_OMP_VERSION:-18.1.21}"; exit 0 ;;
  models) printf '{"models":[{"provider":"openai-codex","id":"gpt-6.1-sol","thinking":["medium","high"]},{"provider":"pi-claude-code-provider","id":"sonnet","thinking":["high"]},{"provider":"anthropic","id":"claude-sonnet-5-5","thinking":["high"]},{"provider":"anthropic","id":"claude-opus-5-5","thinking":["high","xhigh"]},{"provider":"openai-codex","id":"gpt-6-astra","thinking":["xhigh"]},{"provider":"anthropic","id":"claude-haiku-4-5","thinking":["low"]},{"provider":"openai-codex","id":"gpt-6-luna","thinking":["low"]}]}\n'; exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$DOC_FAKE_BIN/omp"
cat > "$DOC_FAKE_BIN/herdr" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = status ] && [ "${2:-}" = --json ]; then
  printf '{"client":{"version":"%s","protocol":19},"server":{"running":true,"version":"%s","protocol":19,"compatible":true}}\n' \
    "${FM_TEST_HERDR_VERSION:-0.8.0}" "${FM_TEST_HERDR_VERSION:-0.8.0}"
  exit 0
fi
exit 0
SH
chmod +x "$DOC_FAKE_BIN/herdr"

# A real local Git repository standing in for FIRSTMATE_ROOT: a main line
# (DOC_C1 -> DOC_C2) plus a sibling branch (DOC_C3, a child of DOC_C1 that
# diverges from DOC_C2), so every stack_commit_relation outcome is
# reachable by simply checking out a different commit before each scenario.
DOC_FMROOT="$TMP_ROOT/doc-fmroot"
mkdir -p "$DOC_FMROOT/.pi/extensions" "$DOC_FMROOT/.omp/extensions" "$DOC_FMROOT/bin"
printf 'fixture\n' > "$DOC_FMROOT/AGENTS.md"
printf 'fixture\n' > "$DOC_FMROOT/.pi/extensions/fm-primary-pi-watch.ts"
printf 'fixture\n' > "$DOC_FMROOT/.pi/extensions/fm-primary-turnend-guard.ts"
printf 'fixture\n' > "$DOC_FMROOT/.omp/extensions/fm-primary-omp-watch.ts"
printf 'fixture\n' > "$DOC_FMROOT/.omp/extensions/fm-primary-turnend-guard.ts"
cat > "$DOC_FMROOT/bin/fm-supervision-lib.sh" <<'SH'
fm_supervision_status() { # <state-dir> [grace]
  local state=$1
  FM_SUP_IN_FLIGHT=0
  for m in "$state"/*.meta; do [ -e "$m" ] || continue; FM_SUP_IN_FLIGHT=$((FM_SUP_IN_FLIGHT + 1)); done
  FM_SUP_NEEDED=false
  [ "$FM_SUP_IN_FLIGHT" -eq 0 ] || FM_SUP_NEEDED=true
  FM_SUP_WATCHER_FRESH=false
  FM_SUP_BEACON_DESC=never
  if [ -e "$state/.last-watcher-beat" ]; then FM_SUP_BEACON_DESC=fresh; FM_SUP_WATCHER_FRESH=true; fi
  FM_SUP_QUEUE_PENDING=false
  [ -s "$state/.wake-queue" ] && FM_SUP_QUEUE_PENDING=true
  return 0
}
SH
git -C "$DOC_FMROOT" init -q
git -C "$DOC_FMROOT" config user.email t@example.invalid
git -C "$DOC_FMROOT" config user.name t
git -C "$DOC_FMROOT" add -A
git -C "$DOC_FMROOT" commit -q -m c1
DOC_C1=$(git -C "$DOC_FMROOT" rev-parse HEAD)
printf marker > "$DOC_FMROOT/marker-v2"
git -C "$DOC_FMROOT" add -A
git -C "$DOC_FMROOT" commit -q -m c2
DOC_C2=$(git -C "$DOC_FMROOT" rev-parse HEAD)
git -C "$DOC_FMROOT" checkout -qb diverged "$DOC_C1"
printf marker > "$DOC_FMROOT/marker-v3"
git -C "$DOC_FMROOT" add -A
git -C "$DOC_FMROOT" commit -q -m c3
DOC_C3=$(git -C "$DOC_FMROOT" rev-parse HEAD)

# write_doc_manifest <baseline-commit> - the real tested versions by default;
# every scenario below overrides only the one field it is testing.
write_doc_manifest() {
  cat > "$DOC_CFG/firstmate/stack-manifest.tsv" <<EOF
schema_version	1
firstmate_repo	https://example.invalid/firstmate.git
firstmate_validated_commit	$1
pi_min_version	0.85.1
pi_tested_version	0.85.1
omp_min_version	18.1.21
omp_tested_version	18.1.21
herdr_min_version	0.8.0
herdr_tested_version	0.8.0
EOF
}

run_fake_doctor() {
  PATH="${DOC_RUN_PATH:-$DOC_LAUNCHER_OK:$DOC_FAKE_BIN:$SYS_BIN}" \
  HOME="$TMP_ROOT/doc-home" \
  FIRSTMATE_ROOT="$DOC_FMROOT" \
  FM_HOME="$TMP_ROOT/doc-fm-home" \
  FM_CONFIG_ENV="$TMP_ROOT/doc-no-env" \
  FM_SKILLS_ROOT="$TMP_ROOT/doc-home/.agents/skills" \
  FM_TEST_PI_VERSION="${FM_TEST_PI_VERSION:-0.85.1}" \
  FM_TEST_OMP_VERSION="${FM_TEST_OMP_VERSION:-18.1.21}" \
  FM_TEST_HERDR_VERSION="${FM_TEST_HERDR_VERSION:-0.8.0}" \
  "$DOC_CFG/bin/fm-doctor"
}

# --- B0: a missing or invalid mandatory manifest is a genuine mandatory
#         FAIL (nonzero exit), never silently advisory -------------------
rm -f "$DOC_CFG/firstmate/stack-manifest.tsv"
out=$(run_fake_doctor); code=$?
if [ "$code" -eq 0 ]; then fail 'B0a missing manifest: expected nonzero exit (mandatory), got 0'; else pass 'B0a missing manifest: exit code is nonzero (mandatory)'; fi
contains 'B0a missing manifest: reports FAIL' "$out" 'FAIL          stack.manifest'

printf 'schema_version\t1\nfirstmate_repo\thttps://example.invalid/x.git\n' > "$DOC_CFG/firstmate/stack-manifest.tsv"
out=$(run_fake_doctor); code=$?
if [ "$code" -eq 0 ]; then fail 'B0b malformed manifest (missing required keys): expected nonzero exit (mandatory), got 0'; else pass 'B0b malformed manifest (missing required keys): exit code is nonzero (mandatory)'; fi
contains 'B0b malformed manifest: reports FAIL' "$out" 'FAIL          stack.manifest'

# --- B1: exact validated stack -> every stack check PASSes, DOCTOR PASS ----
write_doc_manifest "$DOC_C2"
git -C "$DOC_FMROOT" checkout -q "$DOC_C2"
out=$(run_fake_doctor); code=$?
check 'B1 exact stack: exit code is 0' 0 "$code"
contains 'B1 exact stack: overall status is PASS' "$out" 'DOCTOR PASS exit=0'
contains 'B1 exact stack: stack manifest loaded' "$out" 'PASS          stack.manifest'
contains 'B1 exact stack: FirstMate commit matches the baseline' "$out" 'PASS          firstmate.commit_compat'
contains 'B1 exact stack: Pi version matches the tested baseline' "$out" 'PASS          harnesses.pi_version'
contains 'B1 exact stack: omp version matches the tested baseline' "$out" 'PASS          harnesses.omp_version'
contains 'B1 exact stack: herdr version matches the tested baseline' "$out" 'PASS          runtime.herdr_version'

# --- B2: Pi newer than tested but still compatible -> WARNING, never FAIL --
FM_TEST_PI_VERSION=9.9.9
out=$(run_fake_doctor); code=$?
unset FM_TEST_PI_VERSION
check 'B2 Pi newer than tested: exit code stays 0 (non-mandatory)' 0 "$code"
contains 'B2 Pi newer than tested: reports WARNING, never a guessed FAIL' "$out" 'WARNING       harnesses.pi_version'
not_contains 'B2 Pi newer than tested: never reports FAIL' "$out" 'FAIL          harnesses.pi_version'

# --- B3: a mandatory component below the required minimum -> FAIL, and this
#         is a genuine mandatory break (nonzero exit), not merely advisory.
FM_TEST_PI_VERSION=0.10.0
out=$(run_fake_doctor); code=$?
unset FM_TEST_PI_VERSION
if [ "$code" -eq 0 ]; then fail 'B3a Pi below minimum: expected nonzero exit (mandatory), got 0'; else pass 'B3a Pi below minimum: exit code is nonzero (mandatory)'; fi
contains 'B3a Pi below minimum: reports FAIL' "$out" 'FAIL          harnesses.pi_version'
contains 'B3a Pi below minimum: names the required minimum' "$out" 'below the required minimum 0.85.1'

FM_TEST_OMP_VERSION=0.1.0
out=$(run_fake_doctor); code=$?
unset FM_TEST_OMP_VERSION
if [ "$code" -eq 0 ]; then fail 'B3b omp below minimum: expected nonzero exit (mandatory), got 0'; else pass 'B3b omp below minimum: exit code is nonzero (mandatory)'; fi
contains 'B3b omp below minimum: reports FAIL' "$out" 'FAIL          harnesses.omp_version'

FM_TEST_HERDR_VERSION=0.1.0
out=$(run_fake_doctor); code=$?
unset FM_TEST_HERDR_VERSION
if [ "$code" -eq 0 ]; then fail 'B3c herdr below minimum: expected nonzero exit (mandatory), got 0'; else pass 'B3c herdr below minimum: exit code is nonzero (mandatory)'; fi
contains 'B3c herdr below minimum: reports FAIL' "$out" 'FAIL          runtime.herdr_version'

# --- B4: unparseable Pi version -> UNKNOWN, never a guessed FAIL -----------
FM_TEST_PI_VERSION=nightly-build
out=$(run_fake_doctor); code=$?
unset FM_TEST_PI_VERSION
check 'B4 unparseable Pi version: exit code stays 0' 0 "$code"
contains 'B4 unparseable Pi version: reports UNKNOWN, never a guessed FAIL' "$out" 'UNKNOWN       harnesses.pi_version'
not_contains 'B4 unparseable Pi version: never falsely reports FAIL' "$out" 'FAIL          harnesses.pi_version'
not_contains 'B4 unparseable Pi version: never falsely reports PASS' "$out" 'PASS          harnesses.pi_version'

# --- B5: wrong FirstMate commit, every Git-graph relation -------------------
write_doc_manifest "$DOC_C1"
git -C "$DOC_FMROOT" checkout -q "$DOC_C2"
out=$(run_fake_doctor); code=$?
check 'B5a FirstMate ahead of baseline (descendant): exit code stays 0' 0 "$code"
contains 'B5a FirstMate ahead of baseline: reports WARNING (unvalidated, never auto-FAIL)' "$out" 'WARNING       firstmate.commit_compat'

write_doc_manifest "$DOC_C2"
git -C "$DOC_FMROOT" checkout -q "$DOC_C1"
out=$(run_fake_doctor); code=$?
if [ "$code" -eq 0 ]; then fail 'B5b FirstMate behind baseline: expected nonzero exit (mandatory), got 0'; else pass 'B5b FirstMate behind baseline (ancestor): exit code is nonzero (mandatory)'; fi
contains 'B5b FirstMate behind baseline: reports FAIL' "$out" 'FAIL          firstmate.commit_compat'

git -C "$DOC_FMROOT" checkout -q "$DOC_C3"
out=$(run_fake_doctor); code=$?
if [ "$code" -eq 0 ]; then fail 'B5c FirstMate diverged from baseline: expected nonzero exit (mandatory), got 0'; else pass 'B5c FirstMate history diverged from baseline: exit code is nonzero (mandatory)'; fi
contains 'B5c FirstMate history diverged from baseline: reports FAIL' "$out" 'FAIL          firstmate.commit_compat'

write_doc_manifest deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
git -C "$DOC_FMROOT" checkout -q "$DOC_C1"
out=$(run_fake_doctor); code=$?
check 'B5d baseline commit missing from local history: exit code stays 0' 0 "$code"
contains 'B5d baseline commit missing from local history: reports UNKNOWN, never guessed' "$out" 'UNKNOWN       firstmate.commit_compat'
not_contains 'B5d baseline commit missing from local history: never falsely reports FAIL' "$out" 'FAIL          firstmate.commit_compat'

# --- B6: a missing mandatory tool (herdr) stays a mandatory FAIL -----------
write_doc_manifest "$DOC_C1"
git -C "$DOC_FMROOT" checkout -q "$DOC_C1"
DOC_NO_HERDR="$TMP_ROOT/doc-fake-bin-no-herdr"
mkdir -p "$DOC_NO_HERDR"
ln -sf "$DOC_FAKE_BIN/pi" "$DOC_NO_HERDR/pi"
ln -sf "$DOC_FAKE_BIN/claude" "$DOC_NO_HERDR/claude"
ln -sf "$DOC_FAKE_BIN/omp" "$DOC_NO_HERDR/omp"
DOC_RUN_PATH="$DOC_LAUNCHER_OK:$DOC_NO_HERDR:$SYS_BIN"
out=$(run_fake_doctor); code=$?
unset DOC_RUN_PATH
if [ "$code" -eq 0 ]; then fail 'B6 missing herdr: expected nonzero exit, got 0'; else pass 'B6 missing herdr: exit code is nonzero (still mandatory)'; fi
contains 'B6 missing herdr: reports FAIL' "$out" 'FAIL          runtime.herdr_cli'

# =============================================================================
# C. install.sh end to end (offline: a local file-path Git origin, never the
#    network)
# =============================================================================

INST_CFG="$TMP_ROOT/inst-cfg"
mkdir -p "$INST_CFG/bin" "$INST_CFG/firstmate" "$INST_CFG/skills"
cp "$CONFIG_ROOT/install.sh" "$INST_CFG/install.sh"
chmod +x "$INST_CFG/install.sh"
cp "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh" "$INST_CFG/firstmate/fm-stack-manifest.sh"
printf '{}\n' > "$INST_CFG/firstmate/crew-dispatch.json"
printf '# captain notes\n' > "$INST_CFG/firstmate/captain.md"
# Both launchers install.sh links exist in a real checkout; a missing one is
# an installer failure (never a dangling link).
: > "$INST_CFG/bin/fm"; : > "$INST_CFG/bin/ponytail-update"; chmod +x "$INST_CFG/bin/fm" "$INST_CFG/bin/ponytail-update"

INST_FAKE_BIN="$TMP_ROOT/inst-fake-bin"
mkdir -p "$INST_FAKE_BIN"
: > "$INST_FAKE_BIN/pi"; chmod +x "$INST_FAKE_BIN/pi"
: > "$INST_FAKE_BIN/omp"; chmod +x "$INST_FAKE_BIN/omp"
: > "$INST_FAKE_BIN/herdr"; chmod +x "$INST_FAKE_BIN/herdr"

# A real local origin repository (offline clone source): two commits.
INST_ORIGIN="$TMP_ROOT/inst-origin"
mkdir -p "$INST_ORIGIN"
git -C "$INST_ORIGIN" init -q
git -C "$INST_ORIGIN" config user.email t@example.invalid
git -C "$INST_ORIGIN" config user.name t
printf 'AGENTS\n' > "$INST_ORIGIN/AGENTS.md"
git -C "$INST_ORIGIN" add -A
git -C "$INST_ORIGIN" commit -q -m c1
INST_C1=$(git -C "$INST_ORIGIN" rev-parse HEAD)
printf 'AGENTS2\n' >> "$INST_ORIGIN/AGENTS.md"
git -C "$INST_ORIGIN" add -A
git -C "$INST_ORIGIN" commit -q -m c2
INST_C2=$(git -C "$INST_ORIGIN" rev-parse HEAD)

write_inst_manifest() { # <baseline-commit>
  cat > "$INST_CFG/firstmate/stack-manifest.tsv" <<EOF
schema_version	1
firstmate_repo	$INST_ORIGIN
firstmate_validated_commit	$1
pi_min_version	0.85.1
pi_tested_version	0.85.1
omp_min_version	18.1.21
omp_tested_version	18.1.21
herdr_min_version	0.8.0
herdr_tested_version	0.8.0
EOF
}

run_fake_install() { # <suffix> [install.sh args...]
  local suffix=$1; shift
  PATH="$INST_FAKE_BIN:$SYS_BIN" \
  HOME="$TMP_ROOT/inst-home-$suffix" \
  FIRSTMATE_ROOT="$TMP_ROOT/inst-dest-$suffix" \
  FM_HOME="$TMP_ROOT/inst-fm-home-$suffix" \
  FM_CONFIG_ENV="$TMP_ROOT/inst-env-$suffix" \
  FM_SKILLS_ROOT="$TMP_ROOT/inst-skills-$suffix" \
  FM_SKILL_CACHE="$TMP_ROOT/inst-skill-cache-$suffix" \
  FM_BIN_DIR="$TMP_ROOT/inst-bin-dir-$suffix" \
  "$INST_CFG/install.sh" "$@" 2>&1
}

# --- C1: fresh clone is pinned to the manifest baseline, then idempotent --
write_inst_manifest "$INST_C1"
out=$(run_fake_install c1); code=$?
check 'C1 fresh clone: exit code is 0' 0 "$code"
contains 'C1 fresh clone: reports the pinned commit' "$out" "pinned to $INST_C1"
head_after_clone=$(git -C "$TMP_ROOT/inst-dest-c1" rev-parse HEAD 2>/dev/null || printf '')
check 'C1 fresh clone: HEAD is actually pinned to the baseline commit' "$INST_C1" "$head_after_clone"

out2=$(run_fake_install c1); code2=$?
check 'C1 rerun: exit code is 0' 0 "$code2"
contains 'C1 rerun: 0 change(s), idempotent' "$out2" 'install: 0 change(s), 0 failure(s)'
contains 'C1 rerun: existing checkout matches the baseline' "$out2" "matches the validated baseline commit $INST_C1"

# --- C1b: a stale FM_SKILL_VAULT_ROOT from a pre-removal install is dropped
#          by the next reconcile - the generated env is fully rewritten, so
#          an old exported value can never keep leaking into a worker's
#          environment after this machine's vault integration is removed.
cat > "$TMP_ROOT/inst-env-c1" <<EOF
# Written by firstmate-config/install.sh. Machine-local: never commit this.
FIRSTMATE_ROOT="$TMP_ROOT/inst-dest-c1"
FM_CONFIG_ROOT="$INST_CFG"
FM_HOME="$TMP_ROOT/inst-fm-home-c1"
FM_BACKEND="herdr"
FM_SKILL_VAULT_ROOT="$TMP_ROOT/stale-vault-cache/some-owner-some-repo/deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
export FIRSTMATE_ROOT FM_CONFIG_ROOT FM_HOME FM_BACKEND FM_SKILL_VAULT_ROOT
EOF
out_c1b=$(run_fake_install c1); code_c1b=$?
check 'C1b stale vault env: reconcile exit code is 0' 0 "$code_c1b"
not_contains 'C1b stale vault env: the rewritten env file no longer exports FM_SKILL_VAULT_ROOT' \
  "$(cat "$TMP_ROOT/inst-env-c1" 2>/dev/null)" 'FM_SKILL_VAULT_ROOT'
if (. "$TMP_ROOT/inst-env-c1"; [ -z "${FM_SKILL_VAULT_ROOT:-}" ]); then
  pass 'C1b stale vault env: sourcing the rewritten env leaves FM_SKILL_VAULT_ROOT unset'
else
  fail 'C1b stale vault env: sourcing the rewritten env still exports FM_SKILL_VAULT_ROOT'
fi

verify_out=$(run_fake_install c1 --verify)
contains 'C1 verify: reports 0 drift item(s)' "$verify_out" '0 drift item(s), 0 failure(s)'

# --- C2: interrupted pin never reported as success, and is cleaned up ------
BAD_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
write_inst_manifest "$BAD_SHA"
out=$(run_fake_install c2); code=$?
if [ "$code" -eq 0 ]; then fail 'C2 pin failure: expected nonzero exit, got 0'; else pass 'C2 pin failure: exit code is nonzero'; fi
contains 'C2 pin failure: reports it could not clone and pin' "$out" "could not clone"
contains 'C2 pin failure: names the requested baseline commit' "$out" "$BAD_SHA"
[ -e "$TMP_ROOT/inst-dest-c2" ] && fail 'C2 pin failure: a half-cloned checkout was left behind' || pass 'C2 pin failure: the half-cloned checkout was cleaned up'

out2=$(run_fake_install c2); code2=$?
if [ "$code2" -eq 0 ]; then fail 'C2 rerun after failure: expected nonzero exit, got 0'; else pass 'C2 rerun after failure: exit code stays nonzero (retries, never a false success)'; fi
contains 'C2 rerun after failure: attempts the clone again, not "already present"' "$out2" 'could not clone'

# --- C3: an existing checkout is left untouched, only its relationship to --
#         the baseline is reported (never rewound, fast-forwarded, or reset)
C3_DEST="$TMP_ROOT/inst-dest-c3"
git clone -q "$INST_ORIGIN" "$C3_DEST"
git -C "$C3_DEST" checkout -q "$INST_C2"
write_inst_manifest "$INST_C1"
head_before=$(git -C "$C3_DEST" rev-parse HEAD)
out=$(PATH="$INST_FAKE_BIN:$SYS_BIN" HOME="$TMP_ROOT/inst-home-c3" FIRSTMATE_ROOT="$C3_DEST" \
  FM_HOME="$TMP_ROOT/inst-fm-home-c3" FM_CONFIG_ENV="$TMP_ROOT/inst-env-c3" \
  FM_SKILLS_ROOT="$TMP_ROOT/inst-skills-c3" FM_SKILL_CACHE="$TMP_ROOT/inst-skill-cache-c3" \
  FM_BIN_DIR="$TMP_ROOT/inst-bin-dir-c3" "$INST_CFG/install.sh" --verify)
head_after=$(git -C "$C3_DEST" rev-parse HEAD)
contains 'C3 existing checkout ahead of baseline: reports it, never silently' "$out" 'ahead of the validated baseline commit'
check 'C3 existing checkout ahead of baseline: HEAD is never moved (install.sh never updates it)' "$head_before" "$head_after"

# =============================================================================
# D. Cross-cutting: shared baseline consumption, fm-version, path independence
# =============================================================================

# --- D1: install.sh (--verify, no clone attempted) and fm-doctor's own
#         stack.manifest check both name the exact same tracked FirstMate
#         repo/commit, read dynamically from firstmate/stack-manifest.tsv -
#         never a duplicated literal in this test.
stack_manifest_load "$CONFIG_ROOT/firstmate/stack-manifest.tsv"
verify_out=$(HOME="$TMP_ROOT/d1-home" FIRSTMATE_ROOT="$TMP_ROOT/no-such-real-checkout" FM_HOME="$TMP_ROOT/d1-fm-home" \
  FM_CONFIG_ENV="$TMP_ROOT/d1-no-env" FM_SKILLS_ROOT="$TMP_ROOT/d1-skills" \
  "$CONFIG_ROOT/install.sh" --verify 2>&1)
contains 'D1 install.sh --verify names the tracked manifest'"'"'s FirstMate origin' "$verify_out" "$SM_FIRSTMATE_REPO"
contains 'D1 install.sh --verify names the tracked manifest'"'"'s validated commit' "$verify_out" "$SM_FIRSTMATE_COMMIT"

# --- D2: `fm version --json` surfaces the same tracked manifest identity ---
version_json=$(HOME="$TMP_ROOT/d2-home" FM_CONFIG_ENV="$TMP_ROOT/d2-no-env" "$CONFIG_ROOT/bin/fm-version" --json)
contains 'D2 fm version: JSON schema_version is 4 (specialist_skill_vault field removed)' "$version_json" '"schema_version":4'
contains 'D2 fm version: carries the tracked manifest'"'"'s validated commit' "$version_json" "\"firstmate_validated_commit\":\"$SM_FIRSTMATE_COMMIT\""
version_human=$(HOME="$TMP_ROOT/d2-home" FM_CONFIG_ENV="$TMP_ROOT/d2-no-env" "$CONFIG_ROOT/bin/fm-version")
contains 'D2 fm version: human output names the validated baseline' "$version_human" "Validated FirstMate baseline: $SM_FIRSTMATE_COMMIT"
not_contains 'D2 fm version: never prints a compatibility verdict (identity report, not a health check)' "$version_human" 'PASS'
not_contains 'D2 fm version: never prints WARNING (identity report, not a health check)' "$version_human" 'WARNING'

# --- D3: path independence - the loader carries no OS/location assumption -
# Copy the same tracked manifest content into two structurally unrelated
# directory layouts (one deep and POSIX-conventional like a Betao/Omarchy
# service path, one with a space in a path segment, neither resembling this
# machine's own $CONFIG_ROOT) and confirm identical parsed values.
D3_A="$TMP_ROOT/srv/firstmate-config-mirror/deploy/current"
D3_B="$TMP_ROOT/mnt/data disk/firstmate config copy"
mkdir -p "$D3_A" "$D3_B"
cp "$CONFIG_ROOT/firstmate/stack-manifest.tsv" "$D3_A/stack-manifest.tsv"
cp "$CONFIG_ROOT/firstmate/stack-manifest.tsv" "$D3_B/stack-manifest.tsv"
stack_manifest_load "$D3_A/stack-manifest.tsv"
D3_A_COMMIT=$SM_FIRSTMATE_COMMIT; D3_A_PI_TESTED=$SM_PI_TESTED
stack_manifest_load "$D3_B/stack-manifest.tsv"
D3_B_COMMIT=$SM_FIRSTMATE_COMMIT; D3_B_PI_TESTED=$SM_PI_TESTED
check 'D3 path independence: identical validated commit from two unrelated directory layouts' "$D3_A_COMMIT" "$D3_B_COMMIT"
check 'D3 path independence: identical Pi tested version from two unrelated directory layouts' "$D3_A_PI_TESTED" "$D3_B_PI_TESTED"
check 'D3 path independence: matches the real tracked manifest'"'"'s commit' "$REAL_SM_FIRSTMATE_COMMIT" "$D3_A_COMMIT"

# fm-doctor itself, with FIRSTMATE_ROOT under a deliberately non-macOS-style
# absolute path (mimicking a Betao/Omarchy service layout), still classifies
# the Git-graph relationship correctly - no path assumption leaks into
# stack_commit_relation.
D3_FMROOT="$TMP_ROOT/srv/firstmate-config-mirror/deploy/current/firstmate"
mkdir -p "$D3_FMROOT/.pi/extensions" "$D3_FMROOT/.omp/extensions" "$D3_FMROOT/bin"
cp -R "$DOC_FMROOT/.git" "$D3_FMROOT/.git" 2>/dev/null || true
printf 'fixture\n' > "$D3_FMROOT/AGENTS.md"
printf 'fixture\n' > "$D3_FMROOT/.pi/extensions/fm-primary-pi-watch.ts"
printf 'fixture\n' > "$D3_FMROOT/.pi/extensions/fm-primary-turnend-guard.ts"
printf 'fixture\n' > "$D3_FMROOT/.omp/extensions/fm-primary-omp-watch.ts"
printf 'fixture\n' > "$D3_FMROOT/.omp/extensions/fm-primary-turnend-guard.ts"
cp "$DOC_FMROOT/bin/fm-supervision-lib.sh" "$D3_FMROOT/bin/fm-supervision-lib.sh"
git -C "$D3_FMROOT" checkout -q "$DOC_C1"
check 'D3 path independence: commit_relation is unaffected by an unconventional absolute path' exact "$(stack_commit_relation "$D3_FMROOT" "$DOC_C1")"

# =============================================================================
# E. Agent Library lifecycle: install.sh step 10, --verify, --library-rollback,
#    fm doctor and fm version, against a real local Library origin
# =============================================================================
# Per fixture HOME, step 10 owns (XDG_DATA_HOME unset unless LIB_XDG is set):
#   D = $HOME/.local/share       pointer D/agent-library -> .agent-library/<c>
#                                versions D/.agent-library/<commit>/
#   S = D/firstmate-config       lock anchor S/agent-library.lock, receipt
#                                S/agent-library.receipt, source cache
#                                S/skills-src/agent-library.git
# Every expected value is a literal, a fixture fact, or real Git's own answer
# (rev-parse, write-tree) - never something computed by the code under test.
E_UTIL="$TMP_ROOT/e-util"
mkdir -p "$E_UTIL"
# snap.py <root>: one line per entry (lstat mode, inode, mtime, size, link
# text or content sha256). The Library source cache is a Git object store
# that a fetch legitimately grows, so it is left out (checked on its own).
cat > "$E_UTIL/snap.py" <<'PY'
import hashlib, os, stat, sys
root, out = sys.argv[1], []
for dp, dns, fns in os.walk(root):
    dns[:] = [d for d in dns if d != "agent-library.git"]
    for n in dns + [f for f in fns if f != "agent-library.git"]:
        p = os.path.join(dp, n)
        st = os.lstat(p)
        if stat.S_ISLNK(st.st_mode):
            what = "link:" + os.readlink(p)
        elif stat.S_ISREG(st.st_mode):
            with open(p, "rb") as f:
                what = "sha:" + hashlib.sha256(f.read()).hexdigest()
        else:
            what = "dir"
        out.append("\t".join([os.path.relpath(p, root), oct(st.st_mode), str(st.st_ino), str(st.st_mtime_ns), str(st.st_size), what]))
print("\n".join(sorted(out)))
PY
# snapdiff.py <before> <after>: "+ path", "- path", "~ path" (changed entry).
cat > "$E_UTIL/snapdiff.py" <<'PY'
import sys
def load(p):
    with open(p) as f:
        return dict(l.rstrip("\n").split("\t", 1) for l in f if l.strip())
a, b = load(sys.argv[1]), load(sys.argv[2])
for k in sorted(set(a) | set(b)):
    if k not in a: print("+ " + k)
    elif k not in b: print("- " + k)
    elif a[k] != b[k]: print("~ " + k)
PY
# lockhelper.py ex|sh <anchor> <ready-file> <release-file>: a separate process
# that takes a real flock on the anchor, creates <ready-file>, and holds the
# lock until <release-file> exists (a file, not a FIFO, so a helper that died
# early can never wedge the test that releases it).
# lockhelper.py try <anchor>: exit 0 when an exclusive lock is free right
# now, 3 when another process holds it.
cat > "$E_UTIL/lockhelper.py" <<'PY'
import fcntl, os, sys, time
mode, anchor = sys.argv[1], sys.argv[2]
fd = os.open(anchor, os.O_RDWR)
if mode == "try":
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit(3)
    sys.exit(0)
fcntl.flock(fd, fcntl.LOCK_EX if mode == "ex" else fcntl.LOCK_SH)
open(sys.argv[3], "w").close()
for _ in range(1200):
    if os.path.exists(sys.argv[4]):
        break
    time.sleep(0.05)
PY
# reseal.py <receipt> <python statement over r>: edits a receipt and recomputes
# body_sha256 as the receipt format defines it (sha256 of the compact,
# key-sorted JSON of every other field), so a semantic rule is what refuses
# it rather than the checksum.
cat > "$E_UTIL/reseal.py" <<'PY'
import hashlib, json, sys
p = sys.argv[1]
with open(p) as f:
    r = json.load(f)
exec(sys.argv[2])
body = {k: v for k, v in r.items() if k != "body_sha256"}
r["body_sha256"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
with open(p, "w") as f:
    json.dump(r, f)
PY
snap() { python3 "$E_UTIL/snap.py" "$1"; }
snapdiff() { python3 "$E_UTIL/snapdiff.py" "$1" "$2"; }
rfield() { python3 -c 'import json, sys; r = json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }
lmeta() { python3 -c 'import os, stat, sys; s = os.lstat(sys.argv[1]); print("%s %o nlink=%d size=%d" % ("link" if stat.S_ISLNK(s.st_mode) else "dir" if stat.S_ISDIR(s.st_mode) else "file" if stat.S_ISREG(s.st_mode) else "other", stat.S_IMODE(s.st_mode), s.st_nlink, s.st_size))' "$1"; }
lident() { python3 -c 'import os, sys; s = os.lstat(sys.argv[1]); print(s.st_dev, s.st_ino)' "$1"; }
filesha() { python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
wait_for() { local i=0; while [ ! -e "$1" ]; do i=$((i + 1)); [ "$i" -lt 600 ] || return 1; sleep 0.05; done; }

# The disposable config root: install.sh and the shared library, no
# skills/external.lock (so steps 7 and 9 never clone anything).
LIB_CFG="$TMP_ROOT/lib-cfg"
mkdir -p "$LIB_CFG/bin" "$LIB_CFG/firstmate" "$LIB_CFG/skills"
cp "$CONFIG_ROOT/install.sh" "$LIB_CFG/install.sh"
chmod +x "$LIB_CFG/install.sh"
cp "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh" "$LIB_CFG/firstmate/fm-stack-manifest.sh"
printf '{}\n' > "$LIB_CFG/firstmate/crew-dispatch.json"
printf '# captain notes\n' > "$LIB_CFG/firstmate/captain.md"
: > "$LIB_CFG/bin/fm"; : > "$LIB_CFG/bin/ponytail-update"; chmod +x "$LIB_CFG/bin/fm" "$LIB_CFG/bin/ponytail-update"
LIB_FM="$TMP_ROOT/lib-official"
mkdir -p "$LIB_FM"
printf 'AGENTS\n' > "$LIB_FM/AGENTS.md"

# The Library origin: commit A (an executable, a symlink, nested skills) and
# commit B (one file changed, one skill added), tagged lib-a and lib-b.
LIB_ORIGIN="$TMP_ROOT/lib-origin"
mkdir -p "$LIB_ORIGIN/library/bin" "$LIB_ORIGIN/bin" "$LIB_ORIGIN/docs" "$LIB_ORIGIN/skills/x"
git -C "$LIB_ORIGIN" init -q
lgit() { git -C "$LIB_ORIGIN" -c user.email=t@example.invalid -c user.name=t "$@"; }
printf '// fixture Library A\n' > "$LIB_ORIGIN/library/bin/agent-library.ts"
printf '#!/bin/sh\necho tool A\n' > "$LIB_ORIGIN/bin/tool.sh"
chmod 755 "$LIB_ORIGIN/bin/tool.sh"
printf 'readme A\n' > "$LIB_ORIGIN/docs/readme.md"
ln -s readme.md "$LIB_ORIGIN/docs/link"
printf -- '---\nname: x\n---\nskill x\n' > "$LIB_ORIGIN/skills/x/SKILL.md"
lgit add -A; lgit commit -q -m A; lgit tag lib-a
printf '// fixture Library B\n' > "$LIB_ORIGIN/library/bin/agent-library.ts"
mkdir -p "$LIB_ORIGIN/skills/y"
printf -- '---\nname: y\n---\nskill y\n' > "$LIB_ORIGIN/skills/y/SKILL.md"
lgit add -A; lgit commit -q -m B; lgit tag lib-b
LIB_A=$(git -C "$LIB_ORIGIN" rev-parse 'lib-a^{commit}'); LIB_TA=$(git -C "$LIB_ORIGIN" rev-parse 'lib-a^{tree}')
LIB_B=$(git -C "$LIB_ORIGIN" rev-parse 'lib-b^{commit}'); LIB_TB=$(git -C "$LIB_ORIGIN" rev-parse 'lib-b^{tree}')

# git_tree_of <dir>: the tree id real Git computes for <dir>'s content.
git_tree_of() {
  local idx="$TMP_ROOT/e-oracle.index"
  rm -f "$idx"
  GIT_INDEX_FILE="$idx" git --git-dir="$LIB_ORIGIN/.git" --work-tree="$1" add -A -f . >/dev/null 2>&1
  GIT_INDEX_FILE="$idx" git --git-dir="$LIB_ORIGIN/.git" write-tree
  rm -f "$idx"
}

# write_lib_manifest [<commit> <tree> [<ref> [<repo>]]]: no argument writes a
# manifest with no Library rows at all.
write_lib_manifest() {
  {
    printf 'schema_version\t1\nfirstmate_repo\t%s\nfirstmate_validated_commit\t%s\n' "$LIB_FM" "$VALID_COMMIT"
    printf 'pi_min_version\t0.85.1\npi_tested_version\t0.85.1\nomp_min_version\t18.1.21\nomp_tested_version\t18.1.21\nherdr_min_version\t0.8.0\nherdr_tested_version\t0.8.0\n'
    if [ "$#" -ge 2 ]; then
      printf 'library_repo\t%s\nlibrary_commit\t%s\nlibrary_tree\t%s\n' "${4:-file://$LIB_ORIGIN}" "$1" "$2"
      [ -z "${3:-}" ] || printf 'library_ref\t%s\n' "$3"
    fi
  } > "$LIB_CFG/firstmate/stack-manifest.tsv"
}

# run_lib <home> [install.sh args...]: the copied install.sh against one
# fixture HOME. LIB_XDG sets XDG_DATA_HOME, LIB_PATH replaces PATH, LIB_RUN_CFG
# replaces the config root, GIT_CONFIG_NOSYSTEM keeps this machine's system
# Git config (and any credential helper in it) out of every fixture fetch, and
# GIT_ALLOW_PROTOCOL limits Git to file:// and the loopback http:// server
# E31 starts, so no fixture can ever reach a network remote.
run_lib() {
  local h=$1; shift
  local -a xdg=()
  [ -z "${LIB_XDG:-}" ] || xdg=("XDG_DATA_HOME=$LIB_XDG")
  env ${xdg[@]+"${xdg[@]}"} GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file:http PATH="${LIB_PATH:-$INST_FAKE_BIN:$SYS_BIN}" HOME="$h" \
    XDG_CONFIG_HOME="$h/.config" FIRSTMATE_ROOT="$LIB_FM" FM_HOME="$h/.firstmate" \
    FM_CONFIG_ENV="$h/.config/firstmate-config/env" \
    "${LIB_RUN_CFG:-$LIB_CFG}/install.sh" "$@" 2>&1
}
# lib_settle <home>: steps 1-9 settled with no Library pin, so a later snapshot
# diff shows step 10's own effects only.
lib_settle() { mkdir -p "$1"; write_lib_manifest; run_lib "$1" >/dev/null; }
# lib_fresh <home>: settled, then pin A installed.
lib_fresh() {
  local o
  lib_settle "$1"
  write_lib_manifest "$LIB_A" "$LIB_TA"
  o=$(run_lib "$1") || fail "fixture: installing pin A into $1 failed: $o"
}

# The git boundary double: first on LIB_PATH, it hands every call to the real
# git except the one operation FM_GITWRAP names (fixture-only; production code
# has no hook):
#   auth-fail   fetch fails exactly like an HTTPS credential refusal
#   refuse-sha  a fetch by raw object id is refused like a server that does
#               not allow unadvertised objects; a fetch by ref passes
#   inject      ls-tree of the pinned commit gains one extra file entry, so
#               the export no longer matches the pinned tree
#   bump        after a real fetch, a lock-ignoring writer rewrites the
#               receipt at the next generation with a valid checksum
#   barrier     the first cat-file --batch records its parent (the step-10
#               python3 process) and blocks until FM_GITWRAP_DIR/release
#               exists, while that process holds the lock
REAL_GIT=$(command -v git)
GITWRAP="$E_UTIL/gitwrap"
mkdir -p "$GITWRAP"
cat > "$GITWRAP/git" <<SH
#!/usr/bin/env bash
real='$REAL_GIT'
util='$E_UTIL'
SH
cat >> "$GITWRAP/git" <<'SH'
case " $* " in
  *" fetch "*) op=fetch ;;
  *" ls-tree "*) op=ls-tree ;;
  *" cat-file --batch "*) op=cat-file ;;
  *) op=other ;;
esac
case ${FM_GITWRAP:-}:$op in
  auth-fail:fetch)
    printf "fatal: Authentication failed for 'https://example.invalid/private.git/'\n" >&2
    exit 128 ;;
  refuse-sha:fetch)
    last=${!#}
    if [[ $last =~ ^[0-9a-f]{40}$ ]]; then
      printf 'refused %s\n' "$last" >> "$FM_GITWRAP_DIR/log"
      printf 'error: Server does not allow request for unadvertised object %s\n' "$last" >&2
      exit 128
    fi ;;
  inject:ls-tree)
    "$real" "$@" | python3 -c 'import sys; d = sys.stdin.buffer.read(); meta = d.split(b"\0")[0].split(b"\t")[0]; sys.stdout.buffer.write(d + meta + b"\tinjected-by-fixture.txt\0")'
    exit "${PIPESTATUS[0]}" ;;
  bump:fetch)
    "$real" "$@"; rc=$?
    python3 "$util/reseal.py" "$FM_GITWRAP_RECEIPT" 'r["generation"] += 1'
    exit "$rc" ;;
  barrier:cat-file)
    if mkdir "$FM_GITWRAP_DIR/taken" 2>/dev/null; then
      printf '%s\n' "$PPID" > "$FM_GITWRAP_DIR/pid"
      : > "$FM_GITWRAP_DIR/reached"
      while [ ! -e "$FM_GITWRAP_DIR/release" ]; do sleep 0.05; done
    fi ;;
esac
exec "$real" "$@"
SH
chmod +x "$GITWRAP/git"
WRAP_PATH="$GITWRAP:$INST_FAKE_BIN:$SYS_BIN"

# The interpreter boundary double: a python3 first on SHIM_PATH that adds a
# fixture-only sitecustomize to the real interpreter. Step 10 runs as plain
# `python3 -`, so the real interpreter loads it at startup. With FAULT_AT,
# FAULT and FAULT_LOG set it wraps only os.replace (and, for lock-swap,
# fcntl.flock; for receipt-1-durable, the directory sync) and fires once at
# the named point, appending "<point> <effect>" to FAULT_LOG so a fault that
# never fired cannot pass vacuously:
#   receipt-1-before   the 1st receipt write of the run, before it is published
#   receipt-1          right after the rename publishing the 1st receipt write
#   receipt-1-durable  right after the directory sync that makes it durable
#   receipt-2          the 2nd receipt write of the run (the pending record)
#   switch             the rename onto D/agent-library, before it happens
#   finalize           the first receipt write after that rename returned
#   lock-swap          renames FAULT_SWAP_SRC over FAULT_SWAP_DST between the
#                      anchor's open and its exclusive flock
# FAULT=enospc raises ENOSPC instead of the call; FAULT=die exits the
# process with status 137 on the spot, with no cleanup or output;
# FAULT=sigint|sigterm sends that real signal to the process itself, so its
# own handling (KeyboardInterrupt, the SIGTERM handler) runs from there.
SHIM="$E_UTIL/shim"
mkdir -p "$SHIM/bin" "$SHIM/py"
cat > "$SHIM/bin/python3" <<SH
#!/bin/sh
PYTHONPATH='$SHIM/py'\${PYTHONPATH:+":\$PYTHONPATH"}
export PYTHONPATH
exec '$(command -v python3)' "\$@"
SH
chmod +x "$SHIM/bin/python3"
cat > "$SHIM/py/sitecustomize.py" <<'PY'
import errno, fcntl, os, signal, stat
AT, EFFECT, LOG = os.environ.get("FAULT_AT"), os.environ.get("FAULT"), os.environ.get("FAULT_LOG")
if AT and EFFECT and LOG:
    state = {"receipts": 0, "switched": False, "swapped": False, "armed": False, "fired": False}
    def fire(point):
        state["fired"] = True
        with open(LOG, "a") as f:
            f.write("%s %s\n" % (point, EFFECT))
        if EFFECT == "die":
            os._exit(137)
        if EFFECT in ("sigint", "sigterm"):
            os.kill(os.getpid(), signal.SIGINT if EFFECT == "sigint" else signal.SIGTERM)
            return
        raise OSError(errno.ENOSPC, os.strerror(errno.ENOSPC))
    real_replace = os.replace
    def replace(src, dst, *a, **k):
        name = os.path.basename(os.fsdecode(dst))
        if name == "agent-library.receipt":
            state["receipts"] += 1
            if AT == "receipt-1-before" and state["receipts"] == 1:
                fire(AT)
            if AT == "receipt-2" and state["receipts"] == 2:
                fire(AT)
            if AT == "finalize" and state["switched"]:
                fire(AT)
        if name == "agent-library" and AT == "switch":
            fire(AT)
        result = real_replace(src, dst, *a, **k)
        if name == "agent-library":
            state["switched"] = True
        if name == "agent-library.receipt" and state["receipts"] == 1:
            state["armed"] = True
            if AT == "receipt-1":
                fire(AT)
        return result
    os.replace = replace
    if AT == "receipt-1-durable":
        def after_sync(fd):
            if state["armed"] and not state["fired"] and stat.S_ISDIR(os.fstat(fd).st_mode):
                fire(AT)
        real_fsync, real_fcntl = os.fsync, fcntl.fcntl
        def fsync(fd):
            result = real_fsync(fd)
            after_sync(fd)
            return result
        def fcntl_(fd, cmd, *a):
            result = real_fcntl(fd, cmd, *a)
            if cmd == getattr(fcntl, "F_FULLFSYNC", None):
                after_sync(fd)
            return result
        os.fsync, fcntl.fcntl = fsync, fcntl_
    if AT == "lock-swap":
        real_flock = fcntl.flock
        def flock(fd, op):
            if op & fcntl.LOCK_EX and not state["swapped"]:
                state["swapped"] = True
                os.rename(os.environ["FAULT_SWAP_SRC"], os.environ["FAULT_SWAP_DST"])
                with open(LOG, "a") as f:
                    f.write("lock-swap renamed\n")
            return real_flock(fd, op)
        fcntl.flock = flock
PY
SHIM_PATH="$SHIM/bin:$INST_FAKE_BIN:$SYS_BIN"
# lib_fault <home> <point> <effect> [install.sh args...]: one run under the shim.
lib_fault() {
  local h=$1 at=$2 effect=$3; shift 3
  rm -f "$TMP_ROOT/fault.log"
  FAULT_AT=$at FAULT=$effect FAULT_LOG="$TMP_ROOT/fault.log" LIB_PATH=$SHIM_PATH run_lib "$h" "$@"
}
fired() { cat "$TMP_ROOT/fault.log" 2>/dev/null; }

# --- E1: fresh install - exactly these entries, nothing left behind --------
H1="$TMP_ROOT/e1-home"; D1="$H1/.local/share"
lib_settle "$H1"
out=$(run_lib "$H1")
contains 'E1 setup: with no pin in the manifest, step 10 is skipped with a warning' "$out" 'no Agent Library pin'
snap "$H1" > "$TMP_ROOT/e1.before"
write_lib_manifest "$LIB_A" "$LIB_TA"
out=$(run_lib "$H1"); code=$?
check 'E1 fresh install: exit code is 0' 0 "$code"
contains 'E1 fresh install: reports the installed pin' "$out" "Agent Library ${LIB_A:0:12} installed at $D1/agent-library"
snap "$H1" > "$TMP_ROOT/e1.after"
E1_EXPECTED=$(printf '%s\n' '~ .local' '+ .local/share' '+ .local/share/.agent-library' \
  "+ .local/share/.agent-library/$LIB_A" "+ .local/share/.agent-library/$LIB_A/bin" "+ .local/share/.agent-library/$LIB_A/bin/tool.sh" \
  "+ .local/share/.agent-library/$LIB_A/docs" "+ .local/share/.agent-library/$LIB_A/docs/link" "+ .local/share/.agent-library/$LIB_A/docs/readme.md" \
  "+ .local/share/.agent-library/$LIB_A/library" "+ .local/share/.agent-library/$LIB_A/library/bin" "+ .local/share/.agent-library/$LIB_A/library/bin/agent-library.ts" \
  "+ .local/share/.agent-library/$LIB_A/skills" "+ .local/share/.agent-library/$LIB_A/skills/x" "+ .local/share/.agent-library/$LIB_A/skills/x/SKILL.md" \
  '+ .local/share/agent-library' '+ .local/share/firstmate-config' '+ .local/share/firstmate-config/agent-library.lock' \
  '+ .local/share/firstmate-config/agent-library.receipt' '+ .local/share/firstmate-config/skills-src')
check 'E1 fresh install: created exactly the pointer, the version, S, the lock anchor, the receipt and the cache parent; only .local'"'"'s own metadata changed; no staging, temp pointer or receipt temp left behind' \
  "$E1_EXPECTED" "$(snapdiff "$TMP_ROOT/e1.before" "$TMP_ROOT/e1.after")"
check 'E1 fresh install: the pointer is a relative symlink naming the pinned version' ".agent-library/$LIB_A" "$(readlink "$D1/agent-library" 2>/dev/null)"
check 'E1 fresh install: the installed version rebuilds the pinned tree (real git write-tree)' "$LIB_TA" "$(git_tree_of "$D1/.agent-library/$LIB_A")"
check 'E1 fresh install: the executable keeps its mode' 'file 755 nlink=1 size=22' "$(lmeta "$D1/.agent-library/$LIB_A/bin/tool.sh" 2>/dev/null)"
check 'E1 fresh install: the symlink keeps its text' readme.md "$(readlink "$D1/.agent-library/$LIB_A/docs/link" 2>/dev/null)"
check 'E1 fresh install: the lock anchor is an empty private regular file' 'file 600 nlink=1 size=0' "$(lmeta "$D1/firstmate-config/agent-library.lock" 2>/dev/null)"
check 'E1 fresh install: S is private' 'dir 700' "$(lmeta "$D1/firstmate-config" 2>/dev/null | cut -d' ' -f1-2)"
check 'E1 fresh install: the versions directory is private' 'dir 700' "$(lmeta "$D1/.agent-library" 2>/dev/null | cut -d' ' -f1-2)"
check 'E1 fresh install: the receipt is private' 'file 600' "$(lmeta "$D1/firstmate-config/agent-library.receipt" 2>/dev/null | cut -d' ' -f1-2)"
E1_R="$D1/firstmate-config/agent-library.receipt"
check 'E1 fresh install: the receipt is at generation 3 (version, pending, finalize)' 3 "$(rfield "$E1_R" 'r["generation"]' 2>/dev/null)"
check 'E1 fresh install: the receipt pointer is the live pointer identity' ".agent-library/$LIB_A $(lident "$D1/agent-library" 2>/dev/null)" \
  "$(rfield "$E1_R" '"%s %s %s" % (r["pointer"]["text"], r["pointer"]["dev"], r["pointer"]["ino"])' 2>/dev/null)"
check 'E1 fresh install: the receipt records exactly the pinned version with its tree and identity' "$LIB_A $LIB_A $LIB_TA $(lident "$D1/.agent-library/$LIB_A" 2>/dev/null)" \
  "$(rfield "$E1_R" '" ".join("%s %s %s %s %s" % (v["name"], v["commit"], v["tree"], v["dev"], v["ino"]) for v in r["versions"])' 2>/dev/null)"
check 'E1 fresh install: no previous version and nothing pending' 'None False' "$(rfield "$E1_R" '"%s %s" % (r["previous"], "pending" in r)' 2>/dev/null)"
check 'E1 fresh install: the source cache is a bare Git repository' true \
  "$(git --git-dir="$D1/firstmate-config/skills-src/agent-library.git" rev-parse --is-bare-repository 2>/dev/null)"

# --- E2: second run - no rewrite of anything, verify 0 drift ---------------
snap "$H1" > "$TMP_ROOT/e2.before"
out=$(run_lib "$H1"); code=$?
check 'E2 no-op rerun: exit code is 0' 0 "$code"
contains 'E2 no-op rerun: zero changes' "$out" 'install: 0 change(s), 0 failure(s)'
contains 'E2 no-op rerun: the pinned Library is reported current' "$out" "ok      Agent Library ${LIB_A:0:12}"
out=$(run_lib "$H1" --verify)
contains 'E2 verify: 0 drift' "$out" 'verify: 0 drift item(s), 0 failure(s)'
snap "$H1" > "$TMP_ROOT/e2.after"
check 'E2 no-op rerun and verify: every entry identical (bytes, inode, mtime), receipt and pointer included' '' "$(snapdiff "$TMP_ROOT/e2.before" "$TMP_ROOT/e2.after")"

# --- E7/E8: state step 10 never recorded is never adopted --------------------
# A refused run may create only S and its lock anchor.
LOCK_ONLY=$(printf '%s\n' '~ .local/share' '+ .local/share/firstmate-config' '+ .local/share/firstmate-config/agent-library.lock')
H7="$TMP_ROOT/e7-home"; D7="$H7/.local/share"
lib_settle "$H7"
mkdir -p "$D7/.agent-library"
cp -R "$D1/.agent-library/$LIB_A" "$D7/.agent-library/$LIB_A"
ln -s ".agent-library/$LIB_A" "$D7/agent-library"
snap "$H7" > "$TMP_ROOT/e7.before"
write_lib_manifest "$LIB_A" "$LIB_TA"
out=$(run_lib "$H7"); code=$?
if [ "$code" -eq 0 ]; then fail 'E7 foreign same-shaped symlink: expected nonzero exit, got 0'; else pass 'E7 foreign same-shaped symlink: exit code is nonzero'; fi
contains 'E7 foreign same-shaped symlink: refused as unknown state' "$out" 'unknown state'
snap "$H7" > "$TMP_ROOT/e7.after"
check 'E7 foreign same-shaped symlink: pointer and version untouched, no receipt created (only the lock anchor appears)' "$LOCK_ONLY" "$(snapdiff "$TMP_ROOT/e7.before" "$TMP_ROOT/e7.after")"
out=$(run_lib "$H7" --verify)
contains 'E7 verify: reports the unknown state as a failure' "$out" 'FAIL    '
snap "$H7" > "$TMP_ROOT/e7.verify"
check 'E7 verify: writes nothing' '' "$(snapdiff "$TMP_ROOT/e7.after" "$TMP_ROOT/e7.verify")"

for e8 in dir file; do
  H8="$TMP_ROOT/e8-$e8-home"; D8="$H8/.local/share"
  lib_settle "$H8"
  mkdir -p "$D8"
  if [ "$e8" = dir ]; then mkdir "$D8/agent-library"; printf 'mine\n' > "$D8/agent-library/note"; else printf 'mine\n' > "$D8/agent-library"; fi
  snap "$H8" > "$TMP_ROOT/e8.before"
  write_lib_manifest "$LIB_A" "$LIB_TA"
  out=$(run_lib "$H8"); code=$?
  if [ "$code" -eq 0 ]; then fail "E8 foreign $e8 at the pointer path: expected nonzero exit, got 0"; else pass "E8 foreign $e8 at the pointer path: exit code is nonzero"; fi
  contains "E8 foreign $e8 at the pointer path: refused as unknown state" "$out" 'unknown state'
  snap "$H8" > "$TMP_ROOT/e8.after"
  check "E8 foreign $e8 at the pointer path: untouched, nothing nested or created but the lock" "$LOCK_ONLY" "$(snapdiff "$TMP_ROOT/e8.before" "$TMP_ROOT/e8.after")"
done

# --- E18/E25: a real second process holding the lock -----------------------
H18="$TMP_ROOT/e18-home"; D18="$H18/.local/share"
lib_fresh "$H18"
ANCHOR18="$D18/firstmate-config/agent-library.lock"
rm -f "$TMP_ROOT/e18.ready" "$TMP_ROOT/e18.release"
python3 "$E_UTIL/lockhelper.py" ex "$ANCHOR18" "$TMP_ROOT/e18.ready" "$TMP_ROOT/e18.release" &
helper=$!
if wait_for "$TMP_ROOT/e18.ready"; then
  snap "$H18" > "$TMP_ROOT/e18.before"
  out=$(run_lib "$H18"); code=$?
  if [ "$code" -eq 0 ]; then fail 'E18 lock held: expected nonzero exit, got 0'; else pass 'E18 lock held: exit code is nonzero'; fi
  contains 'E18 lock held: names the held lock' "$out" 'another installer holds the Agent Library lock'
  out=$(run_lib "$H18" --verify); code=$?
  contains 'E25 verify during an update: reports update in progress as drift, never ok' "$out" 'DRIFT   Agent Library update in progress'
  contains 'E25 verify during an update: exactly that one drift item and no failure' "$out" 'verify: 1 drift item(s), 0 failure(s)'
  check 'E25 verify during an update: exit status follows the drift contract (0)' 0 "$code"
  snap "$H18" > "$TMP_ROOT/e18.after"
  check 'E18/E25 lock held: neither the refused install nor verify wrote anything' '' "$(snapdiff "$TMP_ROOT/e18.before" "$TMP_ROOT/e18.after")"
else
  fail 'E18 lock held: the helper never acquired the lock'
fi
: > "$TMP_ROOT/e18.release"; wait "$helper"
out=$(run_lib "$H18"); code=$?
check 'E18 lock released: the next install succeeds' 0 "$code"

# A concurrent shared holder (another verify) never blocks verification.
rm -f "$TMP_ROOT/e18.ready" "$TMP_ROOT/e18.release"
python3 "$E_UTIL/lockhelper.py" sh "$ANCHOR18" "$TMP_ROOT/e18.ready" "$TMP_ROOT/e18.release" &
helper=$!
if wait_for "$TMP_ROOT/e18.ready"; then
  out=$(run_lib "$H18" --verify)
  contains 'E25 concurrent read-only verification: a shared holder does not block verify' "$out" 'verify: 0 drift item(s), 0 failure(s)'
else
  fail 'E25 concurrent read-only verification: the shared helper never acquired the lock'
fi
: > "$TMP_ROOT/e18.release"; wait "$helper"

# --- E20: a foreign or changed lock anchor is refused, never replaced -------
H20="$TMP_ROOT/e20-home"; D20="$H20/.local/share"; S20="$D20/firstmate-config"
lib_settle "$H20"
mkdir -p "$S20"
printf 'not a lock\n' > "$TMP_ROOT/e20-target"
ln -s "$TMP_ROOT/e20-target" "$S20/agent-library.lock"
write_lib_manifest "$LIB_A" "$LIB_TA"
out=$(run_lib "$H20"); code=$?
if [ "$code" -eq 0 ]; then fail 'E20 symlinked anchor: expected nonzero exit, got 0'; else pass 'E20 symlinked anchor: exit code is nonzero'; fi
contains 'E20 symlinked anchor: refused' "$out" 'lock anchor'
check 'E20 symlinked anchor: left as it was' "$TMP_ROOT/e20-target" "$(readlink "$S20/agent-library.lock" 2>/dev/null)"
check 'E20 symlinked anchor: its target was never written' 'not a lock' "$(cat "$TMP_ROOT/e20-target")"
[ ! -e "$D20/agent-library" ] && [ ! -e "$S20/agent-library.receipt" ] && pass 'E20 symlinked anchor: nothing installed' || fail 'E20 symlinked anchor: something was installed'
rm "$S20/agent-library.lock"; mkdir "$S20/agent-library.lock"
out=$(run_lib "$H20"); code=$?
if [ "$code" -eq 0 ]; then fail 'E20 directory anchor: expected nonzero exit, got 0'; else pass 'E20 directory anchor: exit code is nonzero'; fi
check 'E20 directory anchor: left as it was' 'dir' "$(lmeta "$S20/agent-library.lock" | cut -d' ' -f1)"
rmdir "$S20/agent-library.lock"
H20H="$TMP_ROOT/e20h-home"; D20H="$H20H/.local/share"
lib_fresh "$H20H"
id20=$(lident "$D20H/firstmate-config/agent-library.lock")
ln "$D20H/firstmate-config/agent-library.lock" "$TMP_ROOT/e20-hardlink"
out=$(run_lib "$H20H"); code=$?
if [ "$code" -eq 0 ]; then fail 'E20 hard-linked anchor: expected nonzero exit, got 0'; else pass 'E20 hard-linked anchor: exit code is nonzero'; fi
contains 'E20 hard-linked anchor: refused' "$out" 'lock anchor'
check 'E20 hard-linked anchor: the anchor is never unlinked or recreated' "$id20" "$(lident "$D20H/firstmate-config/agent-library.lock")"
out=$(run_lib "$H20H" --verify)
contains 'E20 hard-linked anchor: verify refuses it too' "$out" 'lock anchor'
rm "$TMP_ROOT/e20-hardlink"
if [ "$(id -u)" -eq 0 ]; then
  chown 1 "$D20H/firstmate-config/agent-library.lock"
  out=$(run_lib "$H20H"); code=$?
  if [ "$code" -eq 0 ]; then fail 'E20 anchor of another owner: expected nonzero exit, got 0'; else pass 'E20 anchor of another owner: refused'; fi
  chown 0 "$D20H/firstmate-config/agent-library.lock"
else
  printf 'skip - E20 anchor of another owner: needs root to create; not run, not counted as passed\n'
fi

# --- E21-E24: a missing or damaged receipt is refused, never rewritten -----
H21="$TMP_ROOT/e21-home"; D21="$H21/.local/share"; R21="$D21/firstmate-config/agent-library.receipt"
lib_fresh "$H21"
cp "$R21" "$TMP_ROOT/e21.receipt.good"
receipt_refused() { # <label> <expected fragment>
  local before after o c
  before=$(snap "$H21")
  o=$(run_lib "$H21"); c=$?
  if [ "$c" -eq 0 ]; then fail "$1: install expected nonzero exit, got 0"; else pass "$1: install exits nonzero"; fi
  contains "$1: install names the refusal" "$o" "$2"
  o=$(run_lib "$H21" --verify)
  contains "$1: verify reports it as a failure" "$o" "$2"
  after=$(snap "$H21")
  check "$1: pointer, versions and receipt bytes unchanged; nothing recreated" "$before" "$after"
}
rm "$R21"
receipt_refused 'E21 receipt missing' 'unknown state'
[ ! -e "$R21" ] && pass 'E21 receipt missing: no receipt was recreated' || fail 'E21 receipt missing: a receipt was recreated'
head -c "$(( $(wc -c < "$TMP_ROOT/e21.receipt.good") / 2 ))" "$TMP_ROOT/e21.receipt.good" > "$R21"
receipt_refused 'E22 receipt truncated' 'is invalid'
for e23 in 'not JSON' 'wrong schema' 'missing field' 'mistyped generation' 'pointer names no version' 'pending prior is not the pointer' 'previous is the current version' 'unknown extra field'; do
  cp "$TMP_ROOT/e21.receipt.good" "$R21"
  case $e23 in
    'not JSON') printf 'garbage\n' > "$R21" ;;
    'wrong schema') python3 "$E_UTIL/reseal.py" "$R21" 'r["schema"] = "fm-agent-library-receipt.v0"' ;;
    'missing field') python3 "$E_UTIL/reseal.py" "$R21" 'del r["previous"]' ;;
    'mistyped generation') python3 "$E_UTIL/reseal.py" "$R21" 'r["generation"] = str(r["generation"])' ;;
    'pointer names no version') python3 "$E_UTIL/reseal.py" "$R21" 'r["pointer"]["text"] = ".agent-library/" + "f" * 40' ;;
    'pending prior is not the pointer') python3 "$E_UTIL/reseal.py" "$R21" 'r["pending"] = {"kind": "update", "version": r["versions"][0]["name"], "temp_name": ".agent-library-pointer.tmp-1", "text": r["pointer"]["text"], "dev": 1, "ino": 1, "prior": None}' ;;
    'previous is the current version') python3 "$E_UTIL/reseal.py" "$R21" 'r["previous"] = r["versions"][0]["name"]' ;;
    'unknown extra field') python3 "$E_UTIL/reseal.py" "$R21" 'r["rollback"] = r["versions"][0]["name"]' ;;
  esac
  receipt_refused "E23 receipt invalid ($e23)" 'is invalid'
done
cp "$TMP_ROOT/e21.receipt.good" "$R21"
python3 -c 'import json, sys; p = sys.argv[1]; r = json.load(open(p)); r["generation"] += 1; json.dump(r, open(p, "w"))' "$R21"
receipt_refused 'E24 receipt corrupt (field edited, checksum not recomputed)' 'is invalid'
cp "$TMP_ROOT/e21.receipt.good" "$R21"
out=$(run_lib "$H21"); code=$?
check 'E21-E24: the restored receipt is accepted again (refusals were not sticky state)' 0 "$code"

# --- E27: verify on a HOME no installer ever touched creates nothing ---------
H27="$TMP_ROOT/e27-home"
lib_settle "$H27"
snap "$H27" > "$TMP_ROOT/e27.before"
write_lib_manifest "$LIB_A" "$LIB_TA"
out=$(run_lib "$H27" --verify)
contains 'E27 verify with no anchor: reports the pin as not installed (drift)' "$out" "DRIFT   Agent Library ${LIB_A:0:12} is not installed"
snap "$H27" > "$TMP_ROOT/e27.after"
check 'E27 verify with no anchor: creates no S, anchor or receipt' '' "$(snapdiff "$TMP_ROOT/e27.before" "$TMP_ROOT/e27.after")"

# --- E3: pin bump A -> B, A retained, then a no-op ---------------------------
H3="$TMP_ROOT/e3-home"; D3L="$H3/.local/share"; R3="$D3L/firstmate-config/agent-library.receipt"
lib_fresh "$H3"
ptr3=$(lident "$D3L/agent-library"); a3=$(lident "$D3L/.agent-library/$LIB_A"); a3snap=$(snap "$D3L/.agent-library/$LIB_A")
write_lib_manifest "$LIB_B" "$LIB_TB"
out=$(run_lib "$H3"); code=$?
check 'E3 pin bump: exit code is 0' 0 "$code"
contains 'E3 pin bump: reports B installed with A retained' "$out" "Agent Library ${LIB_B:0:12} installed at $D3L/agent-library (previous ${LIB_A:0:12} retained)"
check 'E3 pin bump: the pointer names B' ".agent-library/$LIB_B" "$(readlink "$D3L/agent-library")"
[ "$(lident "$D3L/agent-library")" != "$ptr3" ] && pass 'E3 pin bump: the pointer was replaced by one rename (a new inode)' || fail 'E3 pin bump: the pointer inode did not change'
check 'E3 pin bump: B rebuilds its pinned tree (real git write-tree)' "$LIB_TB" "$(git_tree_of "$D3L/.agent-library/$LIB_B")"
check 'E3 pin bump: A is retained with the same identity' "$a3" "$(lident "$D3L/.agent-library/$LIB_A")"
check 'E3 pin bump: A is retained untouched (every entry identical)' "$a3snap" "$(snap "$D3L/.agent-library/$LIB_A")"
check 'E3 pin bump: receipt previous is A, both versions owned, generation +3' "$LIB_A $LIB_A,$LIB_B 6" \
  "$(rfield "$R3" '"%s %s %s" % (r["previous"], ",".join(v["name"] for v in r["versions"]), r["generation"])')"
snap "$H3" > "$TMP_ROOT/e3.before"
out=$(run_lib "$H3")
contains 'E3 rerun after the bump: zero changes' "$out" 'install: 0 change(s), 0 failure(s)'
out=$(run_lib "$H3" --verify)
contains 'E3 verify after the bump: 0 drift' "$out" 'verify: 0 drift item(s), 0 failure(s)'
snap "$H3" > "$TMP_ROOT/e3.after"
check 'E3 rerun after the bump: nothing rewritten' '' "$(snapdiff "$TMP_ROOT/e3.before" "$TMP_ROOT/e3.after")"

# --- E4: the manifest tree is not the commit's tree --------------------------
H4="$TMP_ROOT/e4-home"
lib_settle "$H4"
snap "$H4" > "$TMP_ROOT/e4.before"
write_lib_manifest "$LIB_A" "$LIB_TB"
out=$(run_lib "$H4"); code=$?
if [ "$code" -eq 0 ]; then fail 'E4 corrupt export (tree mismatch): expected nonzero exit, got 0'; else pass 'E4 corrupt export (tree mismatch): exit code is nonzero'; fi
contains 'E4 corrupt export (tree mismatch): names both trees' "$out" "pinned commit ${LIB_A:0:12} has tree ${LIB_TA:0:12} but the manifest pins ${LIB_TB:0:12}"
snap "$H4" > "$TMP_ROOT/e4.after"
check 'E4 corrupt export: refused before staging - only the lock anchor and the source cache were written' \
  "$(printf '%s\n' '~ .local' '+ .local/share' '+ .local/share/firstmate-config' '+ .local/share/firstmate-config/agent-library.lock' '+ .local/share/firstmate-config/skills-src')" \
  "$(snapdiff "$TMP_ROOT/e4.before" "$TMP_ROOT/e4.after")"

# --- E5: the staged export does not rebuild the pinned tree ------------------
H5="$TMP_ROOT/e5-home"
lib_fresh "$H5"
snap "$H5" > "$TMP_ROOT/e5.before"
write_lib_manifest "$LIB_B" "$LIB_TB"
out=$(FM_GITWRAP=inject LIB_PATH=$WRAP_PATH run_lib "$H5"); code=$?
if [ "$code" -eq 0 ]; then fail 'E5 corrupt staged tree: expected nonzero exit, got 0'; else pass 'E5 corrupt staged tree: exit code is nonzero'; fi
contains 'E5 corrupt staged tree: names the mismatch' "$out" "the staged export of ${LIB_B:0:12} rebuilds tree"
snap "$H5" > "$TMP_ROOT/e5.after"
check 'E5 corrupt staged tree: only its own staging directory came and went (the versions directory'"'"'s metadata); pointer, A and receipt byte-identical' \
  '~ .local/share/.agent-library' "$(snapdiff "$TMP_ROOT/e5.before" "$TMP_ROOT/e5.after")"

# --- E6: an installed version edited after install ---------------------------
H6="$TMP_ROOT/e6-home"; D6="$H6/.local/share"
lib_fresh "$H6"
printf 'tampered\n' >> "$D6/.agent-library/$LIB_A/docs/readme.md"
snap "$H6" > "$TMP_ROOT/e6.before"
out=$(run_lib "$H6"); code=$?
if [ "$code" -eq 0 ]; then fail 'E6 corrupt installed version: expected nonzero exit, got 0'; else pass 'E6 corrupt installed version: install exits nonzero'; fi
contains 'E6 corrupt installed version: install names it' "$out" "Agent Library version ${LIB_A:0:12} at $D6/.agent-library/$LIB_A no longer rebuilds its pinned tree"
out=$(run_lib "$H6" --verify)
contains 'E6 corrupt installed version: verify fails it too' "$out" 'no longer rebuilds its pinned tree'
snap "$H6" > "$TMP_ROOT/e6.after"
check 'E6 corrupt installed version: nothing re-blessed or repaired' '' "$(snapdiff "$TMP_ROOT/e6.before" "$TMP_ROOT/e6.after")"

# --- E8: a foreign version directory where the pin would go -----------------
H8C="$TMP_ROOT/e8c-home"; D8C="$H8C/.local/share"
lib_fresh "$H8C"
mkdir "$D8C/.agent-library/$LIB_B"; printf 'mine\n' > "$D8C/.agent-library/$LIB_B/note"
snap "$H8C" > "$TMP_ROOT/e8c.before"
write_lib_manifest "$LIB_B" "$LIB_TB"
out=$(run_lib "$H8C"); code=$?
if [ "$code" -eq 0 ]; then fail 'E8 foreign version directory: expected nonzero exit, got 0'; else pass 'E8 foreign version directory: exit code is nonzero'; fi
contains 'E8 foreign version directory: never adopted or reused' "$out" "$D8C/.agent-library/$LIB_B exists but the receipt does not record it"
snap "$H8C" > "$TMP_ROOT/e8c.after"
check 'E8 foreign version directory: untouched, nothing nested, pointer still A' '' "$(snapdiff "$TMP_ROOT/e8c.before" "$TMP_ROOT/e8c.after")"

# --- E9: a changed inode is a different object, whatever its name or bytes ---
for e9 in version pointer; do
  H9="$TMP_ROOT/e9-$e9-home"; D9="$H9/.local/share"
  lib_fresh "$H9"
  if [ "$e9" = version ]; then
    cp -R "$D9/.agent-library/$LIB_A" "$D9/.agent-library/copy"; rm -rf "${D9:?}/.agent-library/$LIB_A"; mv "$D9/.agent-library/copy" "$D9/.agent-library/$LIB_A"
  else
    rm "$D9/agent-library"; ln -s ".agent-library/$LIB_A" "$D9/agent-library"
  fi
  snap "$H9" > "$TMP_ROOT/e9.before"
  out=$(run_lib "$H9"); code=$?
  if [ "$code" -eq 0 ]; then fail "E9 $e9 replaced by an identical copy: expected nonzero exit, got 0"; else pass "E9 $e9 replaced by an identical copy: exit code is nonzero"; fi
  contains "E9 $e9 replaced by an identical copy: refused as not receipt-owned" "$out" 'is not the receipt-owned'
  out=$(run_lib "$H9" --verify)
  contains "E9 $e9 replaced by an identical copy: verify fails it too" "$out" 'is not the receipt-owned'
  snap "$H9" > "$TMP_ROOT/e9.after"
  check "E9 $e9 replaced by an identical copy: untouched" '' "$(snapdiff "$TMP_ROOT/e9.before" "$TMP_ROOT/e9.after")"
done

# --- E17: a lock-ignoring writer changes the receipt mid-run -----------------
H17="$TMP_ROOT/e17-home"; D17="$H17/.local/share"; R17="$D17/firstmate-config/agent-library.receipt"
lib_fresh "$H17"
ptr17=$(lident "$D17/agent-library")
write_lib_manifest "$LIB_B" "$LIB_TB"
out=$(FM_GITWRAP=bump FM_GITWRAP_RECEIPT="$R17" LIB_PATH=$WRAP_PATH run_lib "$H17"); code=$?
if [ "$code" -eq 0 ]; then fail 'E17 generation drift: expected nonzero exit, got 0'; else pass 'E17 generation drift: exit code is nonzero'; fi
contains 'E17 generation drift: names the interference' "$out" 'changed during this run (generation 3 -> 4)'
check 'E17 generation drift: the pointer is unchanged' "$ptr17" "$(lident "$D17/agent-library")"
check 'E17 generation drift: no further receipt write (still the interfering generation 4, A only)' "4 $LIB_A" \
  "$(rfield "$R17" '"%s %s" % (r["generation"], ",".join(v["name"] for v in r["versions"]))')"
[ ! -e "$D17/.agent-library/$LIB_B" ] && pass 'E17 generation drift: B was never given its version name' || fail 'E17 generation drift: an unrecorded B version was left behind'
check 'E17 generation drift: no staging directory left behind' "$LIB_A" "$(ls -A "$D17/.agent-library")"

# --- E19: two real installers overlapping on one HOME -----------------------
H19="$TMP_ROOT/e19-home"; D19="$H19/.local/share"; B19="$TMP_ROOT/e19-barrier"
lib_fresh "$H19"
mkdir -p "$B19"
write_lib_manifest "$LIB_B" "$LIB_TB"
FM_GITWRAP=barrier FM_GITWRAP_DIR="$B19" LIB_PATH=$WRAP_PATH run_lib "$H19" > "$TMP_ROOT/e19.first" 2>&1 &
first=$!
if wait_for "$B19/reached"; then
  python3 "$E_UTIL/lockhelper.py" try "$D19/firstmate-config/agent-library.lock"
  check 'E19 overlap: installer #1 holds the lock while blocked mid-export' 3 "$?"
  out=$(run_lib "$H19"); code=$?
  if kill -0 "$first" 2>/dev/null && [ ! -e "$B19/release" ]; then pass 'E19 overlap: installer #2 ran to completion while #1 was still alive inside its locked run'; else fail 'E19 overlap: installer #1 was not alive and locked during #2'; fi
  if [ "$code" -eq 0 ]; then fail 'E19 overlap: installer #2 expected nonzero exit, got 0'; else pass 'E19 overlap: installer #2 exits nonzero (no false PASS)'; fi
  contains 'E19 overlap: installer #2 is refused on the held lock' "$out" 'another installer holds the Agent Library lock'
  out=$(run_lib "$H19" --verify)
  contains 'E19 overlap: verify during the overlap reports update in progress' "$out" 'DRIFT   Agent Library update in progress'
else
  fail 'E19 overlap: installer #1 never reached the export barrier'
fi
: > "$B19/release"
wait "$first"; code=$?
check 'E19 overlap: installer #1 commits after release (exit 0)' 0 "$code"
check 'E19 overlap: one writer lifecycle - pointer B, versions A and B once each, generation 6, nothing pending' "$LIB_A,$LIB_B 6 False .agent-library/$LIB_B" \
  "$(rfield "$D19/firstmate-config/agent-library.receipt" '"%s %s %s %s" % (",".join(v["name"] for v in r["versions"]), r["generation"], "pending" in r, r["pointer"]["text"])')"
check 'E19 overlap: exactly the two versions, no staging leftovers' "$(printf '%s\n' "$LIB_A" "$LIB_B" | sort)" \
  "$(find "$D19/.agent-library" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort)"
out=$(run_lib "$H19" --verify)
contains 'E19 overlap: verify afterwards reports 0 drift' "$out" 'verify: 0 drift item(s), 0 failure(s)'

# --- actual process death: SIGKILL of the step-10 process mid-export ---------
HK="$TMP_ROOT/kill-home"; DK="$HK/.local/share"; BK="$TMP_ROOT/kill-barrier"; RK="$DK/firstmate-config/agent-library.receipt"
lib_fresh "$HK"
mkdir -p "$BK"
ptrk=$(lident "$DK/agent-library"); rk=$(filesha "$RK")
write_lib_manifest "$LIB_B" "$LIB_TB"
FM_GITWRAP=barrier FM_GITWRAP_DIR="$BK" LIB_PATH=$WRAP_PATH run_lib "$HK" > "$TMP_ROOT/kill.out" 2>&1 &
killed=$!
if wait_for "$BK/reached"; then
  kill -9 "$(cat "$BK/pid")"
  wait "$killed"; code=$?
  if [ "$code" -eq 0 ]; then fail 'process death: install.sh expected nonzero exit, got 0'; else pass 'process death: install.sh exits nonzero when its step-10 process is SIGKILLed'; fi
  contains 'process death: reported as a death before any result, never success' "$(cat "$TMP_ROOT/kill.out")" 'exited with status 137 before reporting a result'
  python3 "$E_UTIL/lockhelper.py" try "$DK/firstmate-config/agent-library.lock"
  check 'process death: the kernel released the dead process'"'"'s lock' 0 "$?"
  check 'process death: the known-good pointer A is untouched' "$ptrk" "$(lident "$DK/agent-library")"
  check 'process death: the receipt is byte-identical' "$rk" "$(filesha "$RK")"
  if compgen -G "$DK/.agent-library/.staging-*" >/dev/null; then pass 'process death: its staging directory stays behind, unrecorded and never active'; else fail 'process death: expected the killed run'"'"'s staging directory'; fi
else
  fail 'process death: the installer never reached the export barrier'
  kill "$killed" 2>/dev/null; wait "$killed"
fi
: > "$BK/release"
out=$(run_lib "$HK"); code=$?
check 'process death: the next run completes the pin bump' 0 "$code"
check 'process death: the next run activated B' ".agent-library/$LIB_B" "$(readlink "$DK/agent-library")"

# --- E31: a fetch or auth failure leaves the known-good Library active -------
H31="$TMP_ROOT/e31-home"
lib_fresh "$H31"
write_lib_manifest "$LIB_B" "$LIB_TB"
snap "$H31" > "$TMP_ROOT/e31.before"
out=$(FM_GITWRAP=auth-fail LIB_PATH=$WRAP_PATH run_lib "$H31"); code=$?
if [ "$code" -eq 0 ]; then fail 'E31 auth refusal: expected nonzero exit, got 0'; else pass 'E31 auth refusal: install.sh exits nonzero (so fm update fails)'; fi
contains 'E31 auth refusal: a named fetch error' "$out" "cannot fetch the pinned Agent Library ${LIB_B:0:12}"
contains 'E31 auth refusal: carries the auth cause' "$out" 'Authentication failed'
contains 'E31 auth refusal: says the installed Library stays active' "$out" "the installed Library ${LIB_A:0:12} stays active and unchanged"
write_lib_manifest "$LIB_B" "$LIB_TB" '' "file://$TMP_ROOT/no-such-origin"
out=$(run_lib "$H31"); code=$?
if [ "$code" -eq 0 ]; then fail 'E31 unreachable origin: expected nonzero exit, got 0'; else pass 'E31 unreachable origin: exit code is nonzero'; fi
contains 'E31 unreachable origin: a named fetch error' "$out" "cannot fetch the pinned Agent Library ${LIB_B:0:12}"
snap "$H31" > "$TMP_ROOT/e31.after"
check 'E31 fetch failures: pointer A, versions and receipt byte- and inode-identical; no staging left' '' "$(snapdiff "$TMP_ROOT/e31.before" "$TMP_ROOT/e31.after")"
H31F="$TMP_ROOT/e31f-home"; D31F="$H31F/.local/share"
lib_settle "$H31F"
write_lib_manifest "$LIB_A" "$LIB_TA"
out=$(FM_GITWRAP=auth-fail LIB_PATH=$WRAP_PATH run_lib "$H31F"); code=$?
if [ "$code" -eq 0 ]; then fail 'E31 auth refusal on a fresh HOME: expected nonzero exit, got 0'; else pass 'E31 auth refusal on a fresh HOME: exit code is nonzero'; fi
contains 'E31 auth refusal on a fresh HOME: says nothing was installed' "$out" 'nothing was installed'
[ ! -e "$D31F/agent-library" ] && [ ! -e "$D31F/.agent-library" ] && [ ! -e "$D31F/firstmate-config/agent-library.receipt" ] \
  && pass 'E31 auth refusal on a fresh HOME: no Library root, versions or receipt created (runtime discovery finds no Library)' \
  || fail 'E31 auth refusal on a fresh HOME: Library state was created'

# A real HTTP auth refusal over loopback: the fixture credential helper's
# secret is offered to the server (so this is not vacuous) and appears in no
# output, receipt, cache or other file under the fixture HOME.
SECRET31=fm-fixture-secret-7Q2w
cat > "$E_UTIL/cred-helper.sh" <<SH
#!/bin/sh
[ "\$1" = get ] && printf 'username=fm-fixture-user\npassword=$SECRET31\n'
cat >/dev/null
SH
chmod +x "$E_UTIL/cred-helper.sh"
cat > "$E_UTIL/authserver.py" <<'PY'
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(sys.argv[2], "a") as f:
            f.write("%s %s\n" % (self.path, self.headers.get("Authorization", "-")))
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="fixture"')
        self.send_header("Content-Length", "0")
        self.end_headers()
    do_POST = do_GET
    def log_message(self, *args):
        pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(sys.argv[1] + ".tmp", "w") as f:
    f.write(str(srv.server_address[1]))
import os; os.rename(sys.argv[1] + ".tmp", sys.argv[1])
srv.serve_forever()
PY
python3 "$E_UTIL/authserver.py" "$TMP_ROOT/auth.port" "$TMP_ROOT/auth.log" &
authsrv=$!
if wait_for "$TMP_ROOT/auth.port"; then
  printf '[credential]\n\thelper = %s\n' "$E_UTIL/cred-helper.sh" > "$H31/.gitconfig"
  write_lib_manifest "$LIB_B" "$LIB_TB" '' "http://127.0.0.1:$(cat "$TMP_ROOT/auth.port")/private.git"
  out=$(run_lib "$H31"); code=$?
  if [ "$code" -eq 0 ]; then fail 'E31 real HTTP auth refusal: expected nonzero exit, got 0'; else pass 'E31 real HTTP auth refusal: exit code is nonzero'; fi
  contains 'E31 real HTTP auth refusal: names the fetch failure' "$out" "cannot fetch the pinned Agent Library ${LIB_B:0:12}"
  contains 'E31 real HTTP auth refusal: the helper credential really was offered' "$(cat "$TMP_ROOT/auth.log")" "Basic $(printf 'fm-fixture-user:%s' "$SECRET31" | base64)"
  not_contains 'E31 credential leakage: the secret is not in the install output' "$out" "$SECRET31"
  out=$(run_lib "$H31" --verify)
  not_contains 'E31 credential leakage: the secret is not in the verify output' "$out" "$SECRET31"
  leaks=$(grep -rl --exclude=.gitconfig "$SECRET31" "$H31" 2>/dev/null)
  check 'E31 credential leakage: no file under the fixture HOME (receipt, cache, FETCH_HEAD, env) holds the secret' '' "$leaks"
  rm -f "$H31/.gitconfig"
  snap "$H31" > "$TMP_ROOT/e31.after2"
  check 'E31 real HTTP auth refusal: the known-good Library is still untouched' '' "$(snapdiff "$TMP_ROOT/e31.before" "$TMP_ROOT/e31.after2")"
else
  fail 'E31 real HTTP auth refusal: the loopback server never started'
fi
kill "$authsrv" 2>/dev/null; wait "$authsrv" 2>/dev/null

# --- E28: the library_ref fallback still installs only the exact pin --------
H28="$TMP_ROOT/e28-home"; D28="$H28/.local/share"; B28="$TMP_ROOT/e28-wrap"
lib_settle "$H28"
mkdir -p "$B28"
write_lib_manifest "$LIB_A" "$LIB_TA" refs/tags/lib-b
out=$(FM_GITWRAP=refuse-sha FM_GITWRAP_DIR="$B28" LIB_PATH=$WRAP_PATH run_lib "$H28"); code=$?
if [ "$code" -eq 0 ]; then fail 'E28 ref fallback to the wrong commit: expected nonzero exit, got 0'; else pass 'E28 ref fallback to the wrong commit: refused (a tag is never trusted as the pin)'; fi
contains 'E28 ref fallback to the wrong commit: names the missing pin' "$out" "refs/tags/lib-b did not provide ${LIB_A:0:12}"
[ ! -e "$D28/agent-library" ] && pass 'E28 ref fallback to the wrong commit: nothing installed' || fail 'E28 ref fallback to the wrong commit: something was installed'
write_lib_manifest "$LIB_A" "$LIB_TA" refs/tags/lib-a
out=$(FM_GITWRAP=refuse-sha FM_GITWRAP_DIR="$B28" LIB_PATH=$WRAP_PATH run_lib "$H28"); code=$?
check 'E28 ref fallback: the exact pin installs through the tag when the SHA fetch is refused' 0 "$code"
contains 'E28 ref fallback: the SHA fetch really was refused first' "$(cat "$B28/log")" "refused $LIB_A"
check 'E28 ref fallback: the installed version rebuilds the pinned tree' "$LIB_TA" "$(git_tree_of "$D28/.agent-library/$LIB_A")"

# --- portability: a relocated XDG_DATA_HOME with a space, Linux-style HOME ---
# (path simulation on this machine, not a Linux runtime)
HX="$TMP_ROOT/home/fixture-user"; XX="$TMP_ROOT/mnt/xdg data"
lib_settle "$HX"
write_lib_manifest "$LIB_A" "$LIB_TA"
out=$(LIB_XDG="$XX" run_lib "$HX"); code=$?
check 'portability: install under a relocated XDG_DATA_HOME with a space succeeds' 0 "$code"
check 'portability: the pointer lives under XDG_DATA_HOME and is relative' ".agent-library/$LIB_A" "$(readlink "$XX/agent-library")"
[ ! -e "$HX/.local/share/agent-library" ] && pass 'portability: with XDG_DATA_HOME set, nothing is installed under HOME/.local/share' || fail 'portability: the HOME default was written despite XDG_DATA_HOME'
out=$(LIB_XDG="$XX" run_lib "$HX" --verify)
contains 'portability: verify under the relocated root reports 0 drift' "$out" 'verify: 0 drift item(s), 0 failure(s)'
out=$(LIB_XDG=relative/data run_lib "$HX"); code=$?
if [ "$code" -eq 0 ]; then fail 'portability: a relative XDG_DATA_HOME must be refused'; else contains 'portability: a relative XDG_DATA_HOME is refused, never resolved against the cwd' "$out" 'is not absolute'; fi

# --- E10: failure before the switch - the known-good pointer never moves -----
H10="$TMP_ROOT/e10-home"; D10="$H10/.local/share"; R10="$D10/firstmate-config/agent-library.receipt"
lib_fresh "$H10"
ptr10=$(lident "$D10/agent-library")
write_lib_manifest "$LIB_B" "$LIB_TB"
out=$(lib_fault "$H10" receipt-2 enospc); code=$?
if [ "$code" -eq 0 ]; then fail 'E10 pre-switch failure: expected nonzero exit, got 0'; else pass 'E10 pre-switch failure: exit code is nonzero'; fi
check 'E10 pre-switch failure: the fault fired at the pending write' 'receipt-2 enospc' "$(fired)"
check 'E10 pre-switch failure: pointer A intact and active (same text, same inode)' ".agent-library/$LIB_A $ptr10" "$(readlink "$D10/agent-library") $(lident "$D10/agent-library")"
check 'E10 pre-switch failure: its own temp pointer and receipt temp were removed' '' \
  "$(find "$D10" "$D10/firstmate-config" -maxdepth 1 -name '*.tmp-*')"
check 'E10 pre-switch failure: the receipt is write #1 (B recorded as an inactive owned version, pointer A, nothing pending)' "4 $LIB_A,$LIB_B .agent-library/$LIB_A False" \
  "$(rfield "$R10" '"%s %s %s %s" % (r["generation"], ",".join(v["name"] for v in r["versions"]), r["pointer"]["text"], "pending" in r)')"
out=$(FM_GITWRAP=auth-fail LIB_PATH=$WRAP_PATH run_lib "$H10"); code=$?
check 'E10 rerun: completes the switch by reusing the recorded B, with no fetch (a fetch would have failed here)' 0 "$code"
check 'E10 rerun: pointer B, previous A, generation +2' ".agent-library/$LIB_B $LIB_A 6" \
  "$(rfield "$R10" '"%s %s %s" % (r["pointer"]["text"], r["previous"], r["generation"])')"

# --- E11/E12: failure or death after the switch, before finalize -------------
e11_prepare() { # <home>: pin A installed, the manifest bumped to B
  lib_fresh "$1"
  write_lib_manifest "$LIB_B" "$LIB_TB"
}
e11_state() { e11_prepare "$1"; lib_fault "$1" finalize "$2"; }
for e11 in enospc die; do
  H11="$TMP_ROOT/e11-$e11-home"; D11="$H11/.local/share"; R11="$D11/firstmate-config/agent-library.receipt"
  e11_prepare "$H11"
  out=$(lib_fault "$H11" finalize "$e11"); code=$?
  label="E11 post-switch finalize failure ($e11)"; [ "$e11" = enospc ] || label='E12 death after the switch'
  if [ "$code" -eq 0 ]; then fail "$label: expected nonzero exit, got 0"; else pass "$label: install.sh exits nonzero"; fi
  check "$label: the fault fired at finalize" "finalize $e11" "$(fired)"
  check "$label: the live pointer is already the verified B, with its temp symlink's inode" ".agent-library/$LIB_B $(rfield "$R11" '"%s %s" % (r["pending"]["dev"], r["pending"]["ino"])' 2>/dev/null)" \
    "$(readlink "$D11/agent-library") $(lident "$D11/agent-library")"
  check "$label: the receipt still holds write #2 (pending update to B, pointer A)" "5 update $LIB_B .agent-library/$LIB_A" \
    "$(rfield "$R11" '"%s %s %s %s" % (r["generation"], r["pending"]["kind"], r["pending"]["version"], r["pointer"]["text"])' 2>/dev/null)"
  [ -d "$D11/.agent-library/$LIB_A" ] && pass "$label: A is retained" || fail "$label: A is gone"
  if [ "$e11" = enospc ]; then
    contains "$label: reported honestly - B already active, A retained, switch pending" "$out" "already names the verified Agent Library ${LIB_B:0:12}, the previous version is retained, and the receipt still records the switch as pending"
    not_contains "$label: never claims the old version stayed active" "$out" 'stays active'
  else
    contains "$label: a death before any result is reported as a failure" "$out" 'exited with status 137 before reporting a result'
    python3 "$E_UTIL/lockhelper.py" try "$D11/firstmate-config/agent-library.lock"
    check "$label: the dead process's lock was released by the kernel" 0 "$?"
  fi
  out=$(run_lib "$H11" --verify)
  contains "$label: verify reports the pending finalize as drift" "$out" 'DRIFT   Agent Library receipt finalize pending'
  ptr11=$(lident "$D11/agent-library")
  out=$(run_lib "$H11"); code=$?
  check "E13 pending recovery after $e11: the rerun exits 0" 0 "$code"
  contains "E13 pending recovery after $e11: reports completing the switch" "$out" "completed the interrupted switch of $D11/agent-library to ${LIB_B:0:12}"
  check "E13 pending recovery after $e11: finalized - pointer B (not re-switched), previous A, pending gone, generation +1" "$ptr11 .agent-library/$LIB_B $LIB_A False 6" \
    "$(lident "$D11/agent-library") $(rfield "$R11" '"%s %s %s %s" % (r["pointer"]["text"], r["previous"], "pending" in r, r["generation"])')"
  snap "$H11" > "$TMP_ROOT/e13.before"
  out=$(run_lib "$H11")
  contains "E13 pending recovery after $e11: a further run is a no-op" "$out" 'install: 0 change(s), 0 failure(s)'
  out=$(run_lib "$H11" --verify)
  contains "E13 pending recovery after $e11: verify reports 0 drift" "$out" 'verify: 0 drift item(s), 0 failure(s)'
  snap "$H11" > "$TMP_ROOT/e13.after"
  check "E13 pending recovery after $e11: nothing rewritten afterwards" '' "$(snapdiff "$TMP_ROOT/e13.before" "$TMP_ROOT/e13.after")"
done

# --- E13: death before the rename - pending recorded, old pointer kept --------
H13="$TMP_ROOT/e13-home"; D13="$H13/.local/share"; R13="$D13/firstmate-config/agent-library.receipt"
lib_fresh "$H13"
ptr13=$(lident "$D13/agent-library")
write_lib_manifest "$LIB_B" "$LIB_TB"
lib_fault "$H13" switch die >/dev/null
check 'E13 death before the rename: the fault fired at the switch' 'switch die' "$(fired)"
check 'E13 death before the rename: pending is recorded and the pointer is still A' "True $ptr13" "$(rfield "$R13" '"pending" in r') $(lident "$D13/agent-library")"
temp13="$D13/$(rfield "$R13" 'r["pending"]["temp_name"]')"
check 'E13 death before the rename: the temp symlink is the one pending records' "$(rfield "$R13" '"%s %s %s" % (r["pending"]["text"], r["pending"]["dev"], r["pending"]["ino"])')" "$(readlink "$temp13") $(lident "$temp13")"
out=$(run_lib "$H13"); code=$?
check 'E13 old-pointer recovery: the rerun exits 0' 0 "$code"
contains 'E13 old-pointer recovery: reports dropping the switch that never happened' "$out" "dropped an interrupted switch to ${LIB_B:0:12}"
[ ! -e "$temp13" ] && [ ! -L "$temp13" ] && pass 'E13 old-pointer recovery: its own temp symlink was removed (identity matched pending)' || fail 'E13 old-pointer recovery: the temp symlink is still there'
check 'E13 old-pointer recovery: then the normal update to B completed (drop, pending, finalize)' ".agent-library/$LIB_B $LIB_A False 8" \
  "$(rfield "$R13" '"%s %s %s %s" % (r["pointer"]["text"], r["previous"], "pending" in r, r["generation"])')"

# --- E14: pending recorded, then the pointer replaced by a foreign symlink ---
H14="$TMP_ROOT/e14-home"; D14="$H14/.local/share"
e11_state "$H14" enospc >/dev/null
rm "$D14/agent-library"; ln -s ".agent-library/$LIB_B" "$D14/agent-library"
snap "$H14" > "$TMP_ROOT/e14.before"
out=$(run_lib "$H14"); code=$?
if [ "$code" -eq 0 ]; then fail 'E14 pending foreign state: expected nonzero exit, got 0'; else pass 'E14 pending foreign state: exit code is nonzero'; fi
contains 'E14 pending foreign state: refused, not adopted' "$out" 'is not the receipt-owned pointer'
out=$(run_lib "$H14" --library-rollback); code=$?
if [ "$code" -eq 0 ]; then fail 'E14 pending foreign state: rollback expected nonzero exit, got 0'; else pass 'E14 pending foreign state: rollback refuses too'; fi
snap "$H14" > "$TMP_ROOT/e14.after"
check 'E14 pending foreign state: untouched' '' "$(snapdiff "$TMP_ROOT/e14.before" "$TMP_ROOT/e14.after")"

# --- E15: verified rollback, no hold; the next update returns to the pin ----
H15="$TMP_ROOT/e15-home"; D15="$H15/.local/share"; R15="$D15/firstmate-config/agent-library.receipt"
lib_fresh "$H15"
out=$(run_lib "$H15" --library-rollback); code=$?
if [ "$code" -eq 0 ]; then fail 'E15 rollback with no retained previous version: expected nonzero exit, got 0'; else contains 'E15 rollback with no retained previous version: refused' "$out" 'no retained previous Agent Library version'; fi
write_lib_manifest "$LIB_B" "$LIB_TB"
run_lib "$H15" >/dev/null
a15=$(lident "$D15/.agent-library/$LIB_A"); b15=$(lident "$D15/.agent-library/$LIB_B"); ptr15=$(lident "$D15/agent-library")
out=$(run_lib "$H15" --library-rollback); code=$?
check 'E15 rollback: exit code is 0' 0 "$code"
contains 'E15 rollback: reports the switch back to A and that the next update returns to the pin' "$out" "back to the retained Agent Library ${LIB_A:0:12} (from ${LIB_B:0:12}); the next install.sh or fm update returns it to the pin ${LIB_B:0:12}"
not_contains 'E15 rollback: runs step 10 alone' "$out" '1. toolchain'
check 'E15 rollback: pointer A by a fresh rename, previous B, generation +2, no rollback field' ".agent-library/$LIB_A $LIB_B 8 [\"body_sha256\", \"generation\", \"pointer\", \"previous\", \"schema\", \"versions\", \"versions_dir\"]" \
  "$(readlink "$D15/agent-library") $(rfield "$R15" '"%s %s %s" % (r["previous"], r["generation"], json.dumps(sorted(r)))')"
[ "$(lident "$D15/agent-library")" != "$ptr15" ] && pass 'E15 rollback: the pointer was replaced by one rename' || fail 'E15 rollback: the pointer inode did not change'
check 'E15 rollback: A and B keep their identities' "$a15 $b15" "$(lident "$D15/.agent-library/$LIB_A") $(lident "$D15/.agent-library/$LIB_B")"
out=$(run_lib "$H15" --verify)
contains 'E15 rolled back: verify reports installed != pin as drift, never 0 drift' "$out" "DRIFT   Agent Library installed ${LIB_A:0:12} != pin ${LIB_B:0:12}"
out=$(FM_GITWRAP=auth-fail LIB_PATH=$WRAP_PATH run_lib "$H15"); code=$?
check 'E15 next update: returns to the pin with no fetch (a fetch would have failed here)' 0 "$code"
check 'E15 next update: pointer B, previous A, B reused with the same identity' ".agent-library/$LIB_B $LIB_A $b15" \
  "$(readlink "$D15/agent-library") $(rfield "$R15" 'r["previous"]') $(lident "$D15/.agent-library/$LIB_B")"
out=$(run_lib "$H15" --verify)
contains 'E15 next update: verify reports 0 drift' "$out" 'verify: 0 drift item(s), 0 failure(s)'
printf 'tampered\n' >> "$D15/.agent-library/$LIB_A/docs/readme.md"
snap "$H15" > "$TMP_ROOT/e15.before"
out=$(run_lib "$H15" --library-rollback); code=$?
if [ "$code" -eq 0 ]; then fail 'E15 rollback to a corrupted previous version: expected nonzero exit, got 0'; else contains 'E15 rollback to a corrupted previous version: refused' "$out" 'no longer rebuilds its pinned tree'; fi
snap "$H15" > "$TMP_ROOT/e15.after"
check 'E15 rollback to a corrupted previous version: untouched' '' "$(snapdiff "$TMP_ROOT/e15.before" "$TMP_ROOT/e15.after")"
H15I="$TMP_ROOT/e15i-home"; D15I="$H15I/.local/share"
lib_fresh "$H15I"
write_lib_manifest "$LIB_B" "$LIB_TB"
run_lib "$H15I" >/dev/null
cp -R "$D15I/.agent-library/$LIB_A" "$D15I/.agent-library/copy"; rm -rf "${D15I:?}/.agent-library/$LIB_A"; mv "$D15I/.agent-library/copy" "$D15I/.agent-library/$LIB_A"
snap "$H15I" > "$TMP_ROOT/e15i.before"
out=$(run_lib "$H15I" --library-rollback); code=$?
if [ "$code" -eq 0 ]; then fail 'E15 rollback to an inode-changed previous version: expected nonzero exit, got 0'; else contains 'E15 rollback to an inode-changed previous version: refused' "$out" 'is not the receipt-owned version'; fi
snap "$H15I" > "$TMP_ROOT/e15i.after"
check 'E15 rollback to an inode-changed previous version: untouched' '' "$(snapdiff "$TMP_ROOT/e15i.before" "$TMP_ROOT/e15i.after")"
H15P="$TMP_ROOT/e15p-home"
e11_state "$H15P" enospc >/dev/null
snap "$H15P" > "$TMP_ROOT/e15p.before"
out=$(run_lib "$H15P" --library-rollback); code=$?
if [ "$code" -eq 0 ]; then fail 'E15 rollback with a pending switch: expected nonzero exit, got 0'; else contains 'E15 rollback with a pending switch: refused until a normal run recovers it' "$out" 'an interrupted switch is recorded'; fi
snap "$H15P" > "$TMP_ROOT/e15p.after"
check 'E15 rollback with a pending switch: untouched' '' "$(snapdiff "$TMP_ROOT/e15p.before" "$TMP_ROOT/e15p.after")"

# --- I1: a real SIGINT/SIGTERM around the receipt write that records a version
# The step-10 process sends itself a genuine signal at one of three
# boundaries of the write that records the new version: just before it is
# published (nothing committed yet), right after the rename published it, or
# right after the directory sync made it durable (both committed, but before
# the run has noted it). Interruption cleanup may remove only what no
# published receipt records: a committed version must survive, the active
# version must stay, and update, verify and rollback must keep working.
no_pointer() { [ ! -e "$1/agent-library" ] && [ ! -L "$1/agent-library" ]; }
for sig in sigint sigterm; do
  for point in receipt-1-before receipt-1 receipt-1-durable; do
    h="$TMP_ROOT/i1-fresh-$sig-$point-home"; d="$h/.local/share"; r="$d/firstmate-config/agent-library.receipt"
    label="I1 first install, $sig at $point"
    lib_settle "$h"
    write_lib_manifest "$LIB_A" "$LIB_TA"
    out=$(lib_fault "$h" "$point" "$sig"); code=$?
    check "$label: the real signal was delivered there" "$point $sig" "$(fired)"
    if [ "$code" -eq 0 ]; then fail "$label: the interrupted run must exit nonzero"; else pass "$label: the interrupted run exits nonzero"; fi
    if no_pointer "$d"; then pass "$label: no pointer was published"; else fail "$label: a pointer was published"; fi
    if [ "$point" = receipt-1-before ]; then
      if [ ! -e "$r" ] && [ ! -e "$d/.agent-library" ]; then pass "$label: nothing was committed, so its own export and versions directory are removed"; else fail "$label: uncommitted state was left behind"; fi
    else
      check "$label: the committed version A survives with the identity the published receipt records" \
        "$(rfield "$r" '"%s %s" % (r["versions"][0]["dev"], r["versions"][0]["ino"])' 2>/dev/null)" "$(lident "$d/.agent-library/$LIB_A" 2>/dev/null)"
      check "$label: so does the recorded versions directory" \
        "$(rfield "$r" '"%s %s" % (r["versions_dir"]["dev"], r["versions_dir"]["ino"])' 2>/dev/null)" "$(lident "$d/.agent-library" 2>/dev/null)"
      check "$label: the published receipt is write #1 (A recorded, nothing active yet)" "1 $LIB_A None" \
        "$(rfield "$r" '"%s %s %s" % (r["generation"], ",".join(v["name"] for v in r["versions"]), r["pointer"])' 2>/dev/null)"
    fi
    out=$(run_lib "$h"); code=$?
    check "$label: the next install completes A" "0 .agent-library/$LIB_A" "$code $(readlink "$d/agent-library" 2>/dev/null)"
    contains "$label: verify then reports 0 drift" "$(run_lib "$h" --verify)" 'verify: 0 drift item(s), 0 failure(s)'
    out=$(run_lib "$h" --library-rollback); code=$?
    if [ "$code" -eq 0 ]; then fail "$label: rollback with no earlier version must refuse"; else contains "$label: rollback truthfully reports that no previous version is retained yet" "$out" 'no retained previous Agent Library version'; fi
    write_lib_manifest "$LIB_B" "$LIB_TB"
    run_lib "$h" >/dev/null
    out=$(run_lib "$h" --library-rollback); code=$?
    check "$label: once B is installed over A, a real rollback returns to the retained A" "0 .agent-library/$LIB_A" "$code $(readlink "$d/agent-library" 2>/dev/null)"

    h="$TMP_ROOT/i1-update-$sig-$point-home"; d="$h/.local/share"; r="$d/firstmate-config/agent-library.receipt"
    label="I1 update A->B, $sig at $point"
    lib_fresh "$h"
    ptr=$(lident "$d/agent-library"); a=$(lident "$d/.agent-library/$LIB_A")
    write_lib_manifest "$LIB_B" "$LIB_TB"
    out=$(lib_fault "$h" "$point" "$sig"); code=$?
    check "$label: the real signal was delivered there" "$point $sig" "$(fired)"
    if [ "$code" -eq 0 ]; then fail "$label: the interrupted run must exit nonzero"; else pass "$label: the interrupted run exits nonzero"; fi
    check "$label: the active version A is untouched (pointer text and inode, version identity)" ".agent-library/$LIB_A $ptr $a" \
      "$(readlink "$d/agent-library") $(lident "$d/agent-library") $(lident "$d/.agent-library/$LIB_A")"
    if [ "$point" = receipt-1-before ]; then
      check "$label: nothing committed - the receipt is unchanged and B's export is removed" "3 $LIB_A absent" \
        "$(rfield "$r" '"%s %s" % (r["generation"], ",".join(v["name"] for v in r["versions"]))') $([ -e "$d/.agent-library/$LIB_B" ] && echo present || echo absent)"
    else
      check "$label: the committed B survives with the identity the published receipt records" \
        "$(rfield "$r" "' '.join('%s %s' % (v['dev'], v['ino']) for v in r['versions'] if v['name'] == '$LIB_B')" 2>/dev/null)" "$(lident "$d/.agent-library/$LIB_B" 2>/dev/null)"
      check "$label: the published receipt is write #1 (A and B recorded, A active)" "4 $LIB_A,$LIB_B .agent-library/$LIB_A" \
        "$(rfield "$r" '"%s %s %s" % (r["generation"], ",".join(v["name"] for v in r["versions"]), r["pointer"]["text"])' 2>/dev/null)"
    fi
    check "$label: no staging directory is left behind" '' "$(find "$d/.agent-library" -maxdepth 1 -name '.staging-*')"
    out=$(run_lib "$h"); code=$?
    check "$label: the next update completes B with A as previous" "0 .agent-library/$LIB_B $LIB_A" \
      "$code $(readlink "$d/agent-library" 2>/dev/null) $(rfield "$r" 'r["previous"]' 2>/dev/null)"
    contains "$label: verify then reports 0 drift" "$(run_lib "$h" --verify)" 'verify: 0 drift item(s), 0 failure(s)'
    out=$(run_lib "$h" --library-rollback); code=$?
    check "$label: a real rollback returns to the retained A" "0 .agent-library/$LIB_A" "$code $(readlink "$d/agent-library" 2>/dev/null)"
  done
done

# --- E20: the anchor swapped between open and flock --------------------------
H20S="$TMP_ROOT/e20s-home"; D20S="$H20S/.local/share"
lib_fresh "$H20S"
: > "$TMP_ROOT/e20s-replacement"
swap20=$(lident "$TMP_ROOT/e20s-replacement")
out=$(FAULT_SWAP_SRC="$TMP_ROOT/e20s-replacement" FAULT_SWAP_DST="$D20S/firstmate-config/agent-library.lock" lib_fault "$H20S" lock-swap swap); code=$?
check 'E20 anchor swapped between open and flock: the swap happened' 'lock-swap renamed' "$(fired)"
if [ "$code" -eq 0 ]; then fail 'E20 anchor swapped between open and flock: expected nonzero exit, got 0'; else contains 'E20 anchor swapped between open and flock: refused' "$out" 'changed while it was being locked'; fi
check 'E20 anchor swapped between open and flock: the swapped-in file is left in place, never unlinked or recreated' "$swap20" "$(lident "$D20S/firstmate-config/agent-library.lock")"

# --- E30: the interpreter double never touches step 9 -----------------------
PT_ORIGIN="$TMP_ROOT/pt-origin"
mkdir -p "$PT_ORIGIN/skills/ponytail" "$PT_ORIGIN/skills/ponytail-review"
printf -- '---\nname: ponytail\n---\n' > "$PT_ORIGIN/skills/ponytail/SKILL.md"
printf -- '---\nname: ponytail-review\n---\n' > "$PT_ORIGIN/skills/ponytail-review/SKILL.md"
git -C "$PT_ORIGIN" init -q
git -C "$PT_ORIGIN" -c user.email=t@example.invalid -c user.name=t add -A
git -C "$PT_ORIGIN" -c user.email=t@example.invalid -c user.name=t commit -q -m pt
PT_SHA=$(git -C "$PT_ORIGIN" rev-parse HEAD)
LIB_CFG9="$TMP_ROOT/lib-cfg9"
cp -R "$LIB_CFG" "$LIB_CFG9"
printf 'ponytail\tDietrichGebert/ponytail\t%s\tskills/ponytail\tponytail\n' "$PT_SHA" > "$LIB_CFG9/skills/external.lock"
write_lib_manifest "$LIB_A" "$LIB_TA"
cp "$LIB_CFG/firstmate/stack-manifest.tsv" "$LIB_CFG9/firstmate/stack-manifest.tsv"
for e30 in plain shim; do
  mkdir -p "$TMP_ROOT/e30-$e30-home"
  printf '[url "file://%s"]\n\tinsteadOf = https://github.com/DietrichGebert/ponytail.git\n' "$PT_ORIGIN" > "$TMP_ROOT/e30-$e30-home/.gitconfig"
done
out_plain=$(LIB_RUN_CFG=$LIB_CFG9 run_lib "$TMP_ROOT/e30-plain-home")
out_shim=$(LIB_RUN_CFG=$LIB_CFG9 lib_fault "$TMP_ROOT/e30-shim-home" switch enospc)
contains 'E30 step 9 ran in the plain run' "$out_plain" 'set defaultMode=off'
contains 'E30 step 9 ran under the interpreter double' "$out_shim" 'set defaultMode=off'
contains 'E30 step 9 under the double still writes the skills filter' "$out_shim" 'changed git:github.com/DietrichGebert/ponytail skills filter'
check 'E30 the double fired only for step 10' 'switch enospc' "$(fired)"
check 'E30 Pi settings are byte-identical with and without the double' "$(cat "$TMP_ROOT/e30-plain-home/.pi/agent/settings.json")" "$(cat "$TMP_ROOT/e30-shim-home/.pi/agent/settings.json")"
check 'E30 ponytail config is byte-identical with and without the double' "$(cat "$TMP_ROOT/e30-plain-home/.config/ponytail/config.json")" "$(cat "$TMP_ROOT/e30-shim-home/.config/ponytail/config.json")"

# --- E16: the lifecycle never writes AGENT_LIBRARY_ROOT, and an operator's
#          explicit root is never touched or replaced by it ----------------
H16="$TMP_ROOT/e16-home"; D16="$H16/.local/share"
lib_settle "$H16"
for f in .zshrc .bashrc .profile .bash_profile .zprofile; do printf '# fixture profile %s\n' "$f" > "$H16/$f"; done
prof16=$(for f in .zshrc .bashrc .profile .bash_profile .zprofile; do filesha "$H16/$f"; done)
mkdir -p "$TMP_ROOT/e16-explicit/library/bin"
printf '// operator Library\n' > "$TMP_ROOT/e16-explicit/library/bin/agent-library.ts"
explicit16=$(snap "$TMP_ROOT/e16-explicit")
write_lib_manifest "$LIB_A" "$LIB_TA"
out=$(AGENT_LIBRARY_ROOT="$TMP_ROOT/e16-explicit" run_lib "$H16"); code=$?
check 'E16 explicit AGENT_LIBRARY_ROOT exported: install still succeeds' 0 "$code"
check 'E16 explicit AGENT_LIBRARY_ROOT exported: the pinned Library goes to the portable root' ".agent-library/$LIB_A" "$(readlink "$D16/agent-library")"
check 'E16 explicit AGENT_LIBRARY_ROOT exported: the operator'"'"'s root is untouched' "$explicit16" "$(snap "$TMP_ROOT/e16-explicit")"
check 'E16 profiles are byte-identical' "$prof16" "$(for f in .zshrc .bashrc .profile .bash_profile .zprofile; do filesha "$H16/$f"; done)"
not_contains 'E16 the generated env file never sets AGENT_LIBRARY_ROOT' "$(cat "$H16/.config/firstmate-config/env")" 'AGENT_LIBRARY_ROOT'
check 'E16 no file under HOME (outside the Library content) names AGENT_LIBRARY_ROOT' '' \
  "$(grep -rl --exclude-dir=.agent-library --exclude-dir=agent-library.git AGENT_LIBRARY_ROOT "$H16" 2>/dev/null)"

# --- E26/E29: fm doctor and fm version tell every state apart, read-only -----
cp "$CONFIG_ROOT/bin/fm-version" "$DOC_CFG/bin/fm-version"
chmod +x "$DOC_CFG/bin/fm-version"
mkdir -p "$E_UTIL/bunbin"
printf '#!/bin/sh\nexit 0\n' > "$E_UTIL/bunbin/bun"
chmod +x "$E_UTIL/bunbin/bun"
write_doc_lib_manifest() { # [<commit> <tree>]
  write_doc_manifest "$DOC_C1"
  [ "$#" -eq 0 ] || printf 'library_repo\tfile://%s\nlibrary_commit\t%s\nlibrary_tree\t%s\n' "$LIB_ORIGIN" "$1" "$2" >> "$DOC_CFG/firstmate/stack-manifest.tsv"
}
git -C "$DOC_FMROOT" checkout -q "$DOC_C1"
# LIB_BUN puts a bun executable on PATH (the Library's runtime prerequisite).
run_lib_doctor() {
  local h=$1; shift
  PATH="$DOC_LAUNCHER_OK:$DOC_FAKE_BIN:${LIB_BUN:+$E_UTIL/bunbin:}$SYS_BIN" HOME="$h" FIRSTMATE_ROOT="$DOC_FMROOT" \
    FM_HOME="$TMP_ROOT/doc-fm-home" FM_CONFIG_ENV="$TMP_ROOT/doc-no-env" FM_SKILLS_ROOT="$TMP_ROOT/doc-home/.agents/skills" \
    FM_TEST_PI_VERSION=0.85.1 FM_TEST_OMP_VERSION=18.1.21 FM_TEST_HERDR_VERSION=0.8.0 "$DOC_CFG/bin/fm-doctor" "$@"
}
run_lib_version() {
  local h=$1; shift
  PATH="$DOC_FAKE_BIN:${LIB_BUN:+$E_UTIL/bunbin:}$SYS_BIN" HOME="$h" FIRSTMATE_ROOT="$DOC_FMROOT" \
    FM_HOME="$TMP_ROOT/doc-fm-home" FM_CONFIG_ENV="$TMP_ROOT/doc-no-env" "$DOC_CFG/bin/fm-version" "$@"
}
jget() { python3 -c 'import json, sys; o = json.load(sys.stdin); print(eval(sys.argv[1]))' "$1" 2>/dev/null; }
# row <status> <check id> [<summary start>]: fm-doctor's own text row layout.
row() { if [ "$#" -ge 3 ]; then printf '%-13s %-32s %s' "$1" "$2" "$3"; else printf '%-13s %s' "$1" "$2"; fi; }
# lib_report <label> <home> <doctor status> <doctor fragment> <version fragment> <state>
lib_report() {
  local label=$1 h=$2 before o c
  before=$(snap "$h")
  o=$(run_lib_doctor "$h"); c=$?
  contains "E29 doctor, $label: library.install is $3" "$o" "$(row "$3" library.install)"
  contains "E29 doctor, $label: says why" "$o" "$4"
  if [ "$3" = FAIL ]; then
    if [ "$c" -eq 0 ]; then fail "E29 doctor, $label: a FAIL must exit nonzero"; else pass "E29 doctor, $label: FAIL is paired with a nonzero exit"; fi
  else
    check "E29 doctor, $label: exit code 0" 0 "$c"
  fi
  check "E29 doctor --json, $label: agent_library.install.state" "$6" "$(run_lib_doctor "$h" --json | jget 'o["agent_library"]["install"]["state"]')"
  o=$(run_lib_version "$h")
  contains "E29 version, $label: names the state" "$o" "$5"
  not_contains "E29 version, $label: an identity report, never PASS" "$o" 'PASS'
  not_contains "E29 version, $label: an identity report, never WARNING" "$o" 'WARNING'
  check "E29 version --json, $label: agent_library.installed.state" "$6" "$(run_lib_version "$h" --json | jget 'o["agent_library"]["installed"]["state"]')"
  check "E29, $label: doctor and version wrote nothing" "$before" "$(snap "$h")"
}
write_doc_lib_manifest "$LIB_A" "$LIB_TA"
lib_report 'not installed' "$H27" WARNING "Agent Library ${LIB_A:0:12} is not installed" 'Agent Library installed: none' not_installed
lib_report 'healthy and pinned' "$H1" PASS "Agent Library ${LIB_A:0:12} at $D1/agent-library (pinned, receipt-owned, tree verified)" \
  "Agent Library installed: $LIB_A (pinned, receipt-owned, tree verified)" healthy
lib_report 'installed but different from the pin' "$H3" WARNING "Agent Library installed ${LIB_B:0:12} != pin ${LIB_A:0:12}" \
  "Agent Library installed: $LIB_B (differs from the pin $LIB_A)" differs
lib_report 'invalid ownership' "$H7" FAIL 'unknown state' 'Agent Library installed: invalid ownership' ownership
lib_report 'corrupt installed version' "$H6" FAIL 'no longer rebuilds its pinned tree' 'Agent Library installed: corrupt receipt or state' corrupt
python3 -c 'import json, sys; p = sys.argv[1]; r = json.load(open(p)); r["generation"] += 1; json.dump(r, open(p, "w"))' "$R21"
lib_report 'corrupt receipt' "$H21" FAIL 'is invalid (checksum mismatch)' 'Agent Library installed: corrupt receipt or state' corrupt
cp "$TMP_ROOT/e21.receipt.good" "$R21"
write_doc_lib_manifest "$LIB_B" "$LIB_TB"
lib_report 'update incomplete (finalize pending)' "$H15P" WARNING 'receipt finalize pending' 'Agent Library installed: update incomplete (receipt finalize pending)' pending
write_doc_lib_manifest "$LIB_A" "$LIB_TA"
rm -f "$TMP_ROOT/e18.ready" "$TMP_ROOT/e18.release"
python3 "$E_UTIL/lockhelper.py" ex "$ANCHOR18" "$TMP_ROOT/e18.ready" "$TMP_ROOT/e18.release" &
helper=$!
if wait_for "$TMP_ROOT/e18.ready"; then
  lib_report 'E26 update in progress' "$H18" WARNING 'Agent Library update in progress' 'Agent Library installed: update in progress' busy
else
  fail 'E26 doctor during an update: the helper never acquired the lock'
fi
: > "$TMP_ROOT/e18.release"; wait "$helper"
write_doc_lib_manifest
o=$(run_lib_doctor "$H1")
contains 'E29 doctor, not pinned: library.install is NOT_APPLICABLE' "$o" "$(row NOT_APPLICABLE library.install)"
check 'E29 doctor --json, not pinned: no pin' 'None not_pinned' "$(run_lib_doctor "$H1" --json | jget '"%s %s" % (o["agent_library"]["pin"], o["agent_library"]["install"]["state"])')"
contains 'E29 version, not pinned: says so' "$(run_lib_version "$H1")" 'Agent Library pin: none'
write_doc_lib_manifest "$LIB_A" "$LIB_TA"
check 'E29 version --json: the pin is the manifest'"'"'s repo, commit and tree' "file://$LIB_ORIGIN $LIB_A $LIB_TA" \
  "$(run_lib_version "$H1" --json | jget '"%s %s %s" % (o["agent_library"]["pin"]["repo"], o["agent_library"]["pin"]["commit"], o["agent_library"]["pin"]["tree"])')"
contains 'E29 version: names the pin' "$(run_lib_version "$H1")" "Agent Library pin: $LIB_A (tree $LIB_TA) from file://$LIB_ORIGIN"

# Runtime: what fm would hand the Captain, the explicit root always winning.
o=$(LIB_BUN=1 run_lib_doctor "$H1")
contains 'E29 doctor runtime, default root available: PASS' "$o" "$(row PASS library.runtime "fm discovers the Agent Library at $D1/agent-library")"
check 'E29 doctor --json runtime, default root available' "default $D1/agent-library True" \
  "$(LIB_BUN=1 run_lib_doctor "$H1" --json | jget '"%s %s %s" % (o["agent_library"]["runtime"]["mode"], o["agent_library"]["runtime"]["root"], o["agent_library"]["runtime"]["available"])')"
contains 'E29 version runtime, default root available' "$(LIB_BUN=1 run_lib_version "$H1")" "Agent Library runtime: default root $D1/agent-library (available)"
o=$(run_lib_doctor "$H1")
contains 'E29 doctor runtime, Library unavailable (no bun): WARNING with the normal fallback' "$o" "$(row WARNING library.runtime 'Agent Library unavailable to fm (bun is not on PATH); tasks use the normal FirstMate fallback')"
contains 'E29 version runtime, Library unavailable' "$(run_lib_version "$H1")" 'Agent Library runtime: default root '"$D1"'/agent-library (unavailable: bun is not on PATH)'
o=$(LIB_BUN=1 AGENT_LIBRARY_ROOT="$TMP_ROOT/e16-explicit" run_lib_doctor "$H1")
contains 'E29 doctor runtime, explicit-root mode: the explicit root wins' "$o" "$(row PASS library.runtime "explicit-root mode: AGENT_LIBRARY_ROOT=$TMP_ROOT/e16-explicit is what fm hands the Captain")"
contains 'E29 doctor, explicit-root mode: the installed Library is still reported' "$o" "$(row PASS library.install)"
check 'E29 version --json runtime, explicit-root mode' "explicit $TMP_ROOT/e16-explicit True" \
  "$(LIB_BUN=1 AGENT_LIBRARY_ROOT="$TMP_ROOT/e16-explicit" run_lib_version "$H1" --json | jget '"%s %s %s" % (o["agent_library"]["runtime"]["mode"], o["agent_library"]["runtime"]["root"], o["agent_library"]["runtime"]["available"])')"
o=$(LIB_BUN=1 AGENT_LIBRARY_ROOT="$TMP_ROOT/no-library-here" run_lib_doctor "$H1")
contains 'E29 doctor runtime, explicit invalid root: unavailable, never replaced by the valid default' "$o" "$(row WARNING library.runtime "explicit-root mode: AGENT_LIBRARY_ROOT=$TMP_ROOT/no-library-here is unavailable (no library/bin/agent-library.ts under $TMP_ROOT/no-library-here)")"
o=$(LIB_BUN=1 AGENT_LIBRARY_ROOT='' run_lib_doctor "$H1")
contains 'E29 doctor runtime, explicit empty root: unavailable, never replaced by the valid default' "$o" "$(row WARNING library.runtime 'explicit-root mode: AGENT_LIBRARY_ROOT= is unavailable (AGENT_LIBRARY_ROOT is exported empty)')"
contains 'E29 version runtime, explicit empty root' "$(LIB_BUN=1 AGENT_LIBRARY_ROOT='' run_lib_version "$H1")" 'Agent Library runtime: explicit AGENT_LIBRARY_ROOT= (unavailable: AGENT_LIBRARY_ROOT is exported empty)'

printf '\nSTACK MANIFEST TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
