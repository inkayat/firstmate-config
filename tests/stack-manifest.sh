#!/usr/bin/env bash
# stack-manifest.sh - fixture-based acceptance for firstmate/stack-manifest.tsv,
# firstmate/fm-stack-manifest.sh (the one parsing/comparison owner), and the
# compatibility surfaces install.sh, bin/fm-doctor, and bin/fm-version build
# on top of it.
#
# Four sections:
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
for _tool in bash git uname sed awk grep wc date find stat readlink basename dirname tr head cat mkdir env python3 ln cp mv rm chmod mktemp; do
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
printf '# role\n' > "$DOC_CFG/roles/senior-fullstack/ROLE.md"
printf '# role\n' > "$DOC_CFG/roles/architecture/ROLE.md"
printf '# role\n' > "$DOC_CFG/roles/tenth-man/ROLE.md"

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
  models) printf '{"models":[{"provider":"any","id":"claude-sonnet-5"},{"provider":"any","id":"claude-opus-5"},{"provider":"any","id":"gpt-6-astra"}]}\n'; exit 0 ;;
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
: > "$INST_CFG/bin/fm"; chmod +x "$INST_CFG/bin/fm"

INST_FAKE_BIN="$TMP_ROOT/inst-fake-bin"
mkdir -p "$INST_FAKE_BIN"
: > "$INST_FAKE_BIN/pi"; chmod +x "$INST_FAKE_BIN/pi"
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
verify_out=$(FIRSTMATE_ROOT="$TMP_ROOT/no-such-real-checkout" FM_HOME="$TMP_ROOT/d1-fm-home" \
  FM_CONFIG_ENV="$TMP_ROOT/d1-no-env" FM_SKILLS_ROOT="$TMP_ROOT/d1-skills" \
  "$CONFIG_ROOT/install.sh" --verify 2>&1)
contains 'D1 install.sh --verify names the tracked manifest'"'"'s FirstMate origin' "$verify_out" "$SM_FIRSTMATE_REPO"
contains 'D1 install.sh --verify names the tracked manifest'"'"'s validated commit' "$verify_out" "$SM_FIRSTMATE_COMMIT"

# --- D2: `fm version --json` surfaces the same tracked manifest identity ---
version_json=$(FM_CONFIG_ENV="$TMP_ROOT/d2-no-env" "$CONFIG_ROOT/bin/fm-version" --json)
contains 'D2 fm version: JSON schema_version is 2 (stack_manifest field added)' "$version_json" '"schema_version":2'
contains 'D2 fm version: carries the tracked manifest'"'"'s validated commit' "$version_json" "\"firstmate_validated_commit\":\"$SM_FIRSTMATE_COMMIT\""
version_human=$(FM_CONFIG_ENV="$TMP_ROOT/d2-no-env" "$CONFIG_ROOT/bin/fm-version")
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

printf '\nSTACK MANIFEST TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
