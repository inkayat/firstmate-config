#!/usr/bin/env bash
# doctor.sh - fixture-based acceptance for `fm doctor` / `fm-doctor --json`.
#
# Every scenario fakes only the external processes (pi, claude, herdr, omp)
# and the machine-local state (FIRSTMATE_ROOT, FM_HOME, HOME, PATH); no real
# Portail repository, no paid inference or quota, and no machine-specific
# absolute path. Most scenarios run the real, committed bin/fm-doctor against
# the real, committed roles/skills/crew-dispatch.json in this repository -
# that IS the healthy baseline. Two scenarios (missing role/skill, invalid
# crew-dispatch) need a deliberately broken configuration and use a disposable
# copy of bin/fm-doctor under a fake CONFIG_ROOT so the real repository is
# never touched.
#
# fm-doctor has no dependency-free JSON parser: crew-dispatch.json is parsed
# only via jq or python3, and reports UNKNOWN, never a false PASS, when
# neither is on PATH. The hermetic PATH used by run_doctor therefore includes
# python3 by default (when present on this host - it ships with Xcode CLT on
# macOS and virtually every Linux distribution, matching bin/fm-doctor's own
# assumption) but deliberately omits jq, so most scenarios exercise the
# python3 tier; scenario 11 adds a real jq to the PATH (only when one is
# actually installed on the machine running these tests) to prove the jq
# tier too, and scenario 13 removes every parser to prove the UNKNOWN path.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$CONFIG_ROOT/bin/fm-doctor"

# Real, tracked manifest values - never duplicated as separate literals here.
# The healthy fixture's fake pi/omp/herdr report exactly these tested
# versions, so its new stack-compatibility checks (harnesses.pi_version,
# harnesses.omp_version, runtime.herdr_version) genuinely PASS rather than
# WARNING on an arbitrary "9.9.9-fake". firstmate.commit_compat cannot be
# made to PASS this way (the healthy fixture's FIRSTMATE_ROOT is not a real
# clone of the tracked validated commit, and constructing one would require
# either network access or fabricating a Git object with a chosen hash,
# which is not possible) - it honestly reports UNKNOWN there instead, which
# is scenario 1's own explicit assertion below. A fully-PASS exact-baseline
# scenario, including firstmate.commit_compat, lives in
# tests/stack-manifest.sh, which builds a self-contained synthetic manifest
# and a real local Git repo whose HEAD is genuinely that manifest's baseline.
# shellcheck source=firstmate/fm-stack-manifest.sh
. "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh"
stack_manifest_load "$CONFIG_ROOT/firstmate/stack-manifest.tsv" || {
  printf 'doctor.sh: cannot load the tracked stack manifest: %s\n' "$SM_LOAD_ERROR" >&2
  exit 1
}

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi; }
contains() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in '$2')" ;; esac; }
not_contains() { case $2 in *"$3"*) fail "$1 (unexpectedly found '$3' in '$2')" ;; *) pass "$1" ;; esac; }

# Real JSON parsing of fm-doctor's own --json output, on whatever real parser
# this test runner actually has (independent of run_doctor's hermetic child
# PATH): jq, then python3. Neither present -> returns 2 (skip), never a brace
# balance count standing in for a successful parse.
json_parse_ok() { # <json>
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -e . >/dev/null 2>&1
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1
  else
    return 2
  fi
}

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-doctor-test.XXXXXX") || exit 1
TMP_ROOT=$(cd "$TMP_ROOT" && pwd)
trap 'rm -rf "$TMP_ROOT"' EXIT

# =============================================================================
# Shared fixtures
# =============================================================================

FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/pi" <<'SH'
#!/usr/bin/env bash
available=",${FM_TEST_AVAILABLE-openai-codex/gpt-6-sol,pi-claude-code-provider/sonnet,openai-codex/gpt-6-astra},"
model_base() { printf '%s' "${1#*/}"; }
provider_of() { printf '%s' "${1%%/*}"; }
is_available() { case "$available" in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
if [ "${1:-}" = --version ]; then
  printf '%s\n' "${FM_TEST_PI_VERSION:-9.9.9-fake}"
  exit 0
fi
if [ "${1:-}" = list ]; then
  if [ "${FM_TEST_SONNET_INSTALLED:-yes}" = yes ]; then
    printf 'User packages:\n  npm:pi-claude-code-provider\n    /tmp/pi-claude-code-provider\n'
  else
    printf 'No packages installed.\n'
  fi
  exit 0
fi
if [ "${1:-}" = --list-models ]; then
  model=${2:-}
  if is_available "$model"; then
    printf 'provider      model        context  max-out  thinking  images\n'
    printf '%s  %s  1K  1K  yes  no\n' "$(provider_of "$model")" "$(model_base "$model")"
  else
    printf 'No models matching "%s"\n' "$model"
  fi
  exit 0
fi
if [ "${1:-}" = auth ] && [ "${2:-}" = check ]; then
  model=
  while [ "$#" -gt 0 ]; do
    [ "$1" != --model ] || { model=$2; shift; }
    shift || true
  done
  if ! is_available "$model"; then
    printf '{"status":"not_ready","provider":"%s","reason":"credentials_not_configured"}\n' "$(provider_of "$model")"
  elif [ "$model" = pi-claude-code-provider/sonnet ]; then
    printf '{"status":"invalid","provider":"pi-claude-code-provider/sonnet","reason":"invalid_state"}\n'
  else
    printf '{"status":"ready","provider":"%s","authType":"test"}\n' "$(provider_of "$model")"
  fi
  exit 0
fi
printf 'fake pi should not be executed with args: %s\n' "$*" >&2
exit 64
SH
chmod +x "$FAKE_BIN/pi"

cat > "$FAKE_BIN/claude" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = auth ] && [ "${2:-}" = status ] || exit 64
case ${FM_TEST_SONNET_AUTH:-ready} in
  ready)
    printf '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"max"}\n'
    ;;
  unavailable)
    printf '{"loggedIn":false,"authMethod":"none","apiProvider":"firstParty"}\n'
    exit 1
    ;;
  *) exit 64 ;;
esac
SH
chmod +x "$FAKE_BIN/claude"

cat > "$FAKE_BIN/herdr" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = status ] && [ "${2:-}" = --json ]; then
  case "${FM_TEST_HERDR_MODE:-normal}" in
    unreachable)
      # A herdr CLI that cannot even reach its own server: no stdout,
      # nonzero exit (e.g. connection refused), the "unusable output" case.
      exit 1
      ;;
    weird)
      # Well-formed JSON that nonetheless carries no recognizable
      # "running" field at all - a schema doctor cannot interpret.
      printf '{"ok":true}\n'
      exit 0
      ;;
  esac
  printf '{"client":{"version":"%s","protocol":19},"server":{"running":%s,"version":"%s","protocol":19,"compatible":%s}}\n' \
    "${FM_TEST_HERDR_VERSION:-9.9.9-fake}" "${FM_TEST_HERDR_RUNNING:-true}" "${FM_TEST_HERDR_VERSION:-9.9.9-fake}" "${FM_TEST_HERDR_COMPATIBLE:-true}"
  exit 0
fi
exit 0
SH
chmod +x "$FAKE_BIN/herdr"

# omp's own model catalog, independent of pi's: `models <provider> --json`,
# filtered by FM_TEST_OMP_AVAILABLE (falls back to FM_TEST_AVAILABLE so most
# scenarios need not set it separately). Lets scenario 13 prove routing checks
# an omp lane's model through omp, never through pi's fake.
cat > "$FAKE_BIN/omp" <<'SH'
#!/usr/bin/env bash
available=",${FM_TEST_OMP_AVAILABLE-${FM_TEST_AVAILABLE-openai-codex/gpt-6-sol,pi-claude-code-provider/sonnet,openai-codex/gpt-6-astra}},"
if [ "${1:-}" = --version ]; then
  printf 'omp/%s\n' "${FM_TEST_OMP_VERSION:-9.9.9-fake}"
  exit 0
fi
if [ "${1:-}" = models ]; then
  json='{"models":['
  first=1
  IFS=',' read -ra entries <<< "${available#,}"
  for entry in "${entries[@]}"; do
    [ -n "$entry" ] || continue
    p=${entry%%/*}
    id=${entry#*/}
    [ "$first" -eq 1 ] || json="$json,"
    json="$json{\"provider\":\"$p\",\"id\":\"$id\",\"reasoning\":true,\"thinking\":[\"medium\",\"high\",\"xhigh\"]}"
    first=0
  done
  json="$json]}"
  printf '%s\n' "$json"
  exit 0
fi
exit 0
SH
chmod +x "$FAKE_BIN/omp"

# A fake official FirstMate checkout: just enough for the mandatory
# preflight-equivalent facts (AGENTS.md, both harnesses' primary extensions)
# plus a faithful-for-an-idle-home fm-supervision-lib.sh, so doctor's runtime
# section reports what a real idle installation would - never the real
# upstream scripts, and never modified by anything here.
FAKE_FIRSTMATE="$TMP_ROOT/firstmate"
mkdir -p "$FAKE_FIRSTMATE/.pi/extensions" "$FAKE_FIRSTMATE/.omp/extensions" "$FAKE_FIRSTMATE/bin"
printf 'fixture\n' > "$FAKE_FIRSTMATE/AGENTS.md"
printf 'fixture\n' > "$FAKE_FIRSTMATE/.pi/extensions/fm-primary-pi-watch.ts"
printf 'fixture\n' > "$FAKE_FIRSTMATE/.pi/extensions/fm-primary-turnend-guard.ts"
printf 'fixture\n' > "$FAKE_FIRSTMATE/.omp/extensions/fm-primary-omp-watch.ts"
printf 'fixture\n' > "$FAKE_FIRSTMATE/.omp/extensions/fm-primary-turnend-guard.ts"
# An official-internal skill this fixture checkout ships (Captain/FirstMate-
# only, per firstmate/primary-policy.md section 2). Scenario 19 proves the
# shared skill root never resolves into it.
mkdir -p "$FAKE_FIRSTMATE/.agents/skills/fixture-internal-only"
printf 'fixture official-internal-only skill\n' > "$FAKE_FIRSTMATE/.agents/skills/fixture-internal-only/SKILL.md"
cat > "$FAKE_FIRSTMATE/bin/fm-supervision-lib.sh" <<'SH'
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

# Fixture native fm-project-mode.sh: mirrors the upstream mechanical-consumer
# interface (bin/fm-project-mode.sh <project-name>, no flags) so a regression
# that passes --raw or anything beyond the bare project name fails the
# moment this fixture runs. Records every argument it received (one name per
# line, in $FAKE_FIRSTMATE/bin/fm-project-mode.log) and returns a distinct,
# deterministic posture per known project name, so a caller that mixes up
# which project it asked about is also caught.
cat > "$FAKE_FIRSTMATE/bin/fm-project-mode.sh" <<'SH'
#!/usr/bin/env bash
set -eu
[ "$#" -eq 1 ] || { echo "fixture fm-project-mode.sh: expected exactly one argument (project name), got $#: $*" >&2; exit 2; }
name=$1
case $name in
  --*) echo "fixture fm-project-mode.sh: received a flag-like argument '$name'; the native interface takes the project name only" >&2; exit 2 ;;
esac
printf '%s\n' "$name" >> "$(dirname "$0")/fm-project-mode.log"
case $name in
  project-a) printf '%s\n' 'local-only off' ;;
  project-b) printf '%s\n' 'direct-PR on' ;;
  *) printf '%s\n' 'no-mistakes off' ;;
esac
SH
chmod +x "$FAKE_FIRSTMATE/bin/fm-project-mode.sh"

# A fake $HOME with every skill this repository configures actually seeded,
# so the healthy scenario's SKILLS section genuinely passes.
seed_skills_root() { # <skills-root> <config-root>
  local root=$1 cfg=$2 d n
  mkdir -p "$root"
  for d in "$cfg"/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
    n=$(basename "$d")
    mkdir -p "$root/$n"
    printf '# fixture skill\n' > "$root/$n/SKILL.md"
  done
  if [ -f "$cfg/skills/external.lock" ]; then
    while IFS="$(printf '\t')" read -r id _repo _sha _path name; do
      case ${id:-} in ''|\#*) continue ;; esac
      [ -n "${name:-}" ] || continue
      mkdir -p "$root/$name"
      printf '# fixture skill\n' > "$root/$name/SKILL.md"
    done < "$cfg/skills/external.lock"
  fi
}

FAKE_HOME="$TMP_ROOT/home"
seed_skills_root "$FAKE_HOME/.agents/skills" "$CONFIG_ROOT"

FAKE_FM_HOME="$TMP_ROOT/fm-home"
mkdir -p "$FAKE_FM_HOME/state" "$FAKE_FM_HOME/data" "$FAKE_FM_HOME/config" "$FAKE_FM_HOME/projects"

LAUNCHER_OK="$TMP_ROOT/launcher-ok"
mkdir -p "$LAUNCHER_OK"
ln -s "$CONFIG_ROOT/bin/fm" "$LAUNCHER_OK/fm"

LAUNCHER_OTHER="$TMP_ROOT/launcher-other"
mkdir -p "$LAUNCHER_OTHER"
cat > "$LAUNCHER_OTHER/fm" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$LAUNCHER_OTHER/fm"

# Every model this repository's crew-dispatch.json and captain-startup-models
# reference, so the fully-healthy scenario has nothing left UNAVAILABLE.
HEALTHY_AVAILABLE="openai-codex/gpt-6-sol,pi-claude-code-provider/sonnet,openai-codex/gpt-6-astra,anthropic/claude-sonnet-5,anthropic/claude-opus-5-5,anthropic/claude-haiku-4-5,openai-codex/gpt-6-luna"

# A fully hermetic system PATH: symlink only the exact utilities fm-doctor
# needs, never a whole real bin directory. On macOS, /usr/bin itself ships a
# real `fm` (Apple's Foundation Models CLI, a genuine real-world PATH
# collision), so the ambient PATH and even a whole system directory are both
# unsafe defaults for a deterministic fixture.
#
# SYS_BIN_CORE carries no JSON parser at all (scenario 13's UNKNOWN
# regression uses it directly). SYS_BIN adds python3, when this host
# actually has one, since fm-doctor requires jq or python3 for real
# crew-dispatch parsing and most scenarios below need a working parse tier;
# jq is deliberately excluded from both, so it stays scenario 11's own
# opt-in proof of the jq tier.
SYS_BIN_CORE="$TMP_ROOT/sysbin-core"
mkdir -p "$SYS_BIN_CORE"
for _tool in bash git uname sed awk grep wc date find stat readlink basename dirname tr head cat mkdir env; do
  _p=$(command -v "$_tool" 2>/dev/null) || continue
  ln -s "$_p" "$SYS_BIN_CORE/$_tool"
done

SYS_BIN="$TMP_ROOT/sysbin"
mkdir -p "$SYS_BIN"
for _tool in bash git uname sed awk grep wc date find stat readlink basename dirname tr head cat mkdir env python3; do
  _p=$(command -v "$_tool" 2>/dev/null) || continue
  ln -s "$_p" "$SYS_BIN/$_tool"
done
SYS_PATH=$SYS_BIN
SYS_PATH_NO_PARSER=$SYS_BIN_CORE

run_doctor() { # [extra args to fm-doctor]
  ( cd "${RUN_CWD:-$TMP_ROOT}" && \
    PATH="${RUN_PATH:-$LAUNCHER_OK:$FAKE_BIN:$SYS_PATH}" \
    HOME="${RUN_HOME:-$FAKE_HOME}" \
    FIRSTMATE_ROOT="${RUN_FIRSTMATE_ROOT:-$FAKE_FIRSTMATE}" \
    FM_HOME="${RUN_FM_HOME:-$FAKE_FM_HOME}" \
    FM_CONFIG_ENV="$TMP_ROOT/no-such-env-file" \
    FM_VAULT_LOCK="${RUN_VAULT_LOCK:-$TMP_ROOT/no-such-vault-lock}" \
    FM_SKILLS_ROOT="${RUN_SKILLS_ROOT:-${RUN_HOME:-$FAKE_HOME}/.agents/skills}" \
    FM_TEST_AVAILABLE="${FM_TEST_AVAILABLE-$HEALTHY_AVAILABLE}" \
    FM_TEST_OMP_AVAILABLE="${FM_TEST_OMP_AVAILABLE-${FM_TEST_AVAILABLE-$HEALTHY_AVAILABLE}}" \
    FM_TEST_SONNET_INSTALLED="${FM_TEST_SONNET_INSTALLED:-yes}" \
    FM_TEST_SONNET_AUTH="${FM_TEST_SONNET_AUTH:-ready}" \
    FM_TEST_HERDR_RUNNING="${FM_TEST_HERDR_RUNNING:-true}" \
    FM_TEST_HERDR_COMPATIBLE="${FM_TEST_HERDR_COMPATIBLE:-true}" \
    FM_TEST_HERDR_MODE="${FM_TEST_HERDR_MODE:-normal}" \
    FM_TEST_PI_VERSION="${FM_TEST_PI_VERSION:-$SM_PI_TESTED}" \
    FM_TEST_OMP_VERSION="${FM_TEST_OMP_VERSION:-$SM_OMP_TESTED}" \
    FM_TEST_HERDR_VERSION="${FM_TEST_HERDR_VERSION:-$SM_HERDR_TESTED}" \
    "${RUN_DOC:-$DOC}" "$@" )
}

# =============================================================================
# 1. Healthy: exit 0. Overall status is UNKNOWN, not PASS - the one honest
#    gap in an otherwise fully-green fixture is firstmate.commit_compat: this
#    fixture's FIRSTMATE_ROOT is not a real clone of the tracked validated
#    commit (see the manifest-sourcing comment near the top of this file),
#    so fm-doctor correctly reports UNKNOWN rather than guessing PASS or
#    FAIL. Every other new stack-compatibility check genuinely PASSes here,
#    because the fake pi/omp/herdr report exactly the tracked manifest's
#    tested versions (see run_doctor's FM_TEST_*_VERSION defaults). This
#    scenario runs with the default FM_VAULT_LOCK pointed at a nonexistent
#    path (see run_doctor), so vault.pin/vault.no_global_leak are honestly
#    NOT_APPLICABLE here; the vault's own install/doctor states are covered
#    by tests/vault.sh.
# =============================================================================
out=$(run_doctor); code=$?
check 'healthy: exit code is 0' 0 "$code"
contains 'healthy: overall status is UNKNOWN (only commit_compat is unproven offline)' "$out" 'DOCTOR UNKNOWN exit=0'
contains 'healthy: launcher resolves ours first' "$out" "PASS          launcher.resolution"
contains 'healthy: captain selects the preferred candidate' "$out" 'selected preferred candidate openai-codex/gpt-6-sol'
contains 'healthy: herdr server reported running' "$out" 'PASS          runtime.herdr_server'
contains 'healthy: FM_HOME is explicitly reported' "$out" "FM_HOME=$FAKE_FM_HOME"
contains 'healthy: an explicit heartbeat check is reported' "$out" 'runtime.heartbeat'
contains 'healthy: roles all readable' "$out" 'PASS          roles.tenth-man'
contains 'healthy: skills fully installed' "$out" 'PASS          skills.global_installation'
contains 'healthy: no official-internal skill leakage' "$out" 'PASS          skills.no_official_internal_leak'
contains 'healthy: Opus 5.5 is an active available routing model' "$out" 'PASS          routing.model.omp.anthropic/claude-opus-5-5'
contains 'healthy: Qwen/Ollama remain deferred' "$out" 'DEFERRED      routing.qwen_ollama_deferred'
contains 'healthy: stack manifest loaded' "$out" 'PASS          stack.manifest'
contains 'healthy: Pi version matches the tested baseline' "$out" "PASS          harnesses.pi_version"
contains 'healthy: omp version matches the tested baseline' "$out" "PASS          harnesses.omp_version"
contains 'healthy: herdr version matches the tested baseline' "$out" "PASS          runtime.herdr_version"
contains 'healthy: FirstMate commit compat is honestly UNKNOWN, never a guessed PASS or FAIL' "$out" 'UNKNOWN       firstmate.commit_compat'
not_contains 'healthy: FirstMate commit compat never falsely reports PASS' "$out" 'PASS          firstmate.commit_compat'
not_contains 'healthy: FirstMate commit compat never falsely reports FAIL' "$out" 'FAIL          firstmate.commit_compat'

# =============================================================================
# 2. A later, non-shadowing competing `fm` -> WARNING, exit 0
# =============================================================================
RUN_PATH="$LAUNCHER_OK:$LAUNCHER_OTHER:$FAKE_BIN:$SYS_PATH"
out=$(run_doctor); code=$?
unset RUN_PATH
check 'later competing fm: exit code is 0' 0 "$code"
contains 'later competing fm: launcher check is WARNING' "$out" 'WARNING       launcher.resolution'
contains 'later competing fm: names the competitor' "$out" "$LAUNCHER_OTHER/fm"

# =============================================================================
# 3. A shadowing `fm` earlier on PATH -> FAIL, nonzero exit
# =============================================================================
RUN_PATH="$LAUNCHER_OTHER:$LAUNCHER_OK:$FAKE_BIN:$SYS_PATH"
out=$(run_doctor); code=$?
unset RUN_PATH
if [ "$code" -eq 0 ]; then fail "shadowing fm: expected nonzero exit, got 0"; else pass 'shadowing fm: exit code is nonzero'; fi
contains 'shadowing fm: launcher check is FAIL' "$out" 'FAIL          launcher.resolution'
contains 'shadowing fm: names the shadowing entry' "$out" "$LAUNCHER_OTHER/fm"
contains 'shadowing fm: overall exit is reported nonzero' "$out" 'exit=1'

# =============================================================================
# 4. Sol unavailable, Sonnet usable under corrected provider semantics
# =============================================================================
FM_TEST_AVAILABLE='pi-claude-code-provider/sonnet,openai-codex/gpt-6-astra'
out=$(run_doctor --harness pi); code=$?
unset FM_TEST_AVAILABLE
check 'Sol down: exit code is 0' 0 "$code"
contains 'Sol down: Sonnet is selected' "$out" 'selected pi-claude-code-provider/sonnet'
contains 'Sol down: Sonnet reports available despite broker invalid_state' "$out" 'PASS          captain.model.pi-claude-code-provider/sonnet'
contains 'Sol down: fallback reason names Sol' "$out" 'openai-codex/gpt-6-sol'

# =============================================================================
# 5. Every Captain candidate unavailable -> FAIL, nonzero exit
# =============================================================================
FM_TEST_AVAILABLE=''
out=$(run_doctor); code=$?
unset FM_TEST_AVAILABLE
if [ "$code" -eq 0 ]; then fail "all candidates unavailable: expected nonzero exit, got 0"; else pass 'all candidates unavailable: exit code is nonzero'; fi
contains 'all candidates unavailable: selection reports FAIL' "$out" 'FAIL          captain.selection'
contains 'all candidates unavailable: no usable Captain is explained' "$out" 'no configured Captain startup model is available'

# =============================================================================
# 6. Invalid crew-dispatch.json -> FAIL, nonzero exit (mandatory, isolated)
# =============================================================================
# Requires a real parser (python3 here; jq is scenario 11's own opt-in): with
# neither available, fm-doctor correctly reports UNKNOWN rather than FAIL, so
# this scenario's mandatory-nonzero-exit proof needs the parser present.
SYS_PY=$(command -v python3 2>/dev/null || printf '')
if [ -n "$SYS_PY" ]; then
  BROKEN_FM_HOME="$TMP_ROOT/fm-home-broken-dispatch"
  mkdir -p "$BROKEN_FM_HOME/state" "$BROKEN_FM_HOME/data" "$BROKEN_FM_HOME/config" "$BROKEN_FM_HOME/projects"
  printf '{"rules": [ { "when": "x", "use": [ { "harness": "pi", "model": "a/b", "effort": "yolo" } ] }' > "$BROKEN_FM_HOME/config/crew-dispatch.json"
  RUN_FM_HOME=$BROKEN_FM_HOME
  out=$(run_doctor); code=$?
  unset RUN_FM_HOME
  if [ "$code" -eq 0 ]; then fail "invalid crew-dispatch: expected nonzero exit, got 0"; else pass 'invalid crew-dispatch: exit code is nonzero'; fi
  contains 'invalid crew-dispatch: routing check reports FAIL' "$out" 'FAIL          routing.crew_dispatch_valid'
  contains 'invalid crew-dispatch: parsed via python3' "$out" 'parsed via python3'
  contains 'invalid crew-dispatch: other mandatory checks stay healthy' "$out" 'PASS          captain.selection'
else
  pass 'invalid crew-dispatch: skipped (no jq or python3 on the test runner)'
fi

# =============================================================================
# 7. Missing role/skill statuses -> reported FAIL, but non-mandatory: exit 0
# =============================================================================
FAKE_CFG="$TMP_ROOT/fake-config-root"
mkdir -p "$FAKE_CFG/bin" "$FAKE_CFG/firstmate" "$FAKE_CFG/roles/senior-fullstack" "$FAKE_CFG/roles/architecture" "$FAKE_CFG/skills/architecture-review"
cp "$CONFIG_ROOT/bin/fm-doctor" "$FAKE_CFG/bin/fm-doctor"
ln -s "$CONFIG_ROOT/bin/fm" "$FAKE_CFG/bin/fm"
chmod +x "$FAKE_CFG/bin/fm-doctor"
cp "$CONFIG_ROOT/firstmate/fm-captain-lib.sh" "$FAKE_CFG/firstmate/fm-captain-lib.sh"
cp "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh" "$FAKE_CFG/firstmate/fm-stack-manifest.sh"
cp "$CONFIG_ROOT/firstmate/fm-vault-lib.sh" "$FAKE_CFG/firstmate/fm-vault-lib.sh"
cp "$CONFIG_ROOT/firstmate/stack-manifest.tsv" "$FAKE_CFG/firstmate/stack-manifest.tsv"
cp "$CONFIG_ROOT/firstmate/captain-startup-models.tsv" "$FAKE_CFG/firstmate/captain-startup-models.tsv"
cp "$CONFIG_ROOT/firstmate/crew-dispatch.json" "$FAKE_CFG/firstmate/crew-dispatch.json"
printf '# role\n' > "$FAKE_CFG/roles/senior-fullstack/ROLE.md"
printf '# role\n' > "$FAKE_CFG/roles/architecture/ROLE.md"
# roles/tenth-man/ROLE.md deliberately absent.
printf '# skill\n' > "$FAKE_CFG/skills/architecture-review/SKILL.md"
printf '%s\t%s\t%s\t%s\t%s\n' tenth-man:x some/repo deadbeef skills/tenth-man tenth-man > "$FAKE_CFG/skills/external.lock"
FAKE_HOME7="$TMP_ROOT/home-missing-skill"
mkdir -p "$FAKE_HOME7/.agents/skills/architecture-review"
printf '# fixture skill\n' > "$FAKE_HOME7/.agents/skills/architecture-review/SKILL.md"
# tenth-man skill deliberately never installed under $FAKE_HOME7.
RUN_DOC="$FAKE_CFG/bin/fm-doctor" RUN_HOME="$FAKE_HOME7"
out=$(run_doctor); code=$?
unset RUN_DOC RUN_HOME
check 'missing role/skill: exit code stays 0 (non-mandatory)' 0 "$code"
contains 'missing role: tenth-man reported FAIL' "$out" 'FAIL          roles.tenth-man'
contains 'missing skill: global installation reported FAIL' "$out" 'FAIL          skills.global_installation'
contains 'missing skill: names the missing skill' "$out" 'tenth-man'

# =============================================================================
# 8. Multi-project reporting: registry, confident current project, no leakage
# =============================================================================
MP_FM_HOME="$TMP_ROOT/fm-home-multiproject"
mkdir -p "$MP_FM_HOME/state" "$MP_FM_HOME/data" "$MP_FM_HOME/config"
proj_a="$MP_FM_HOME/projects/project-a"
proj_b="$MP_FM_HOME/projects/project-b"
mkdir -p "$proj_a" "$proj_b"
( cd "$proj_a" && git init -q && printf 'AGENTS-A-SECRET-MARKER\n' > AGENTS.md && printf 'CLAUDE-A\n' > CLAUDE.md \
  && git add -A && git -c user.email=t@example.invalid -c user.name=t commit -qm init )
( cd "$proj_b" && git init -q && printf 'AGENTS-B-SECRET-MARKER\n' > AGENTS.md \
  && git add -A && git -c user.email=t@example.invalid -c user.name=t commit -qm init )
cat > "$MP_FM_HOME/data/projects.md" <<'MD'
- project-a [local-only] - fixture project A (added 2026-01-01)
- project-b [direct-PR +yolo] - fixture project B (added 2026-01-01)
MD

RUN_FM_HOME=$MP_FM_HOME RUN_CWD=$proj_a
out_a=$(run_doctor); code_a=$?
RUN_FM_HOME=$MP_FM_HOME RUN_CWD=$proj_b
out_b=$(run_doctor); code_b=$?
RUN_FM_HOME=$MP_FM_HOME RUN_CWD=$TMP_ROOT
out_none=$(run_doctor); code_none=$?
unset RUN_FM_HOME RUN_CWD
check 'multi-project: unregistered cwd run exits 0' 0 "$code_none"

check 'multi-project: project A run exits 0' 0 "$code_a"
check 'multi-project: project B run exits 0' 0 "$code_b"
contains 'multi-project: registry lists both projects' "$out_a" 'project-a,project-b'
contains 'multi-project: from A, current project is A' "$out_a" 'confident current project: project-a'
not_contains 'multi-project: from A, current project is not B' "$out_a" 'confident current project: project-b'
contains 'multi-project: from B, current project is B' "$out_b" 'confident current project: project-b'
contains 'multi-project: from an unregistered cwd, no project is guessed' "$out_none" 'no confident current project'
not_contains 'multi-project: unregistered cwd does not default to A' "$out_none" 'confident current project: project-a'
not_contains "multi-project: A's own AGENTS.md content never leaks" "$out_a" 'AGENTS-A-SECRET-MARKER'
not_contains "multi-project: B's AGENTS.md content never leaks into A's run" "$out_a" 'AGENTS-B-SECRET-MARKER'
not_contains "multi-project: B's own AGENTS.md content never leaks" "$out_b" 'AGENTS-B-SECRET-MARKER'
not_contains "multi-project: A's AGENTS.md content never leaks into B's run" "$out_b" 'AGENTS-A-SECRET-MARKER'

# An unrelated checkout that merely shares a registered project's directory
# name, but is not that project's own clone under $FM_HOME/projects, must
# never be identified as the confident current project - the basename-match
# misidentification bin/fm-doctor's project resolution used to have.
IMPOSTOR_DIR="$TMP_ROOT/elsewhere/project-a"
mkdir -p "$IMPOSTOR_DIR"
( cd "$IMPOSTOR_DIR" && git init -q && printf 'not the real project A\n' > README.md \
  && git add -A && git -c user.email=t@example.invalid -c user.name=t commit -qm init )
RUN_FM_HOME=$MP_FM_HOME RUN_CWD=$IMPOSTOR_DIR
out_impostor=$(run_doctor); code_impostor=$?
unset RUN_FM_HOME RUN_CWD
check 'impostor checkout: exit code stays 0' 0 "$code_impostor"
contains 'impostor checkout: no confident current project, despite the matching directory name' "$out_impostor" 'no confident current project'
not_contains 'impostor checkout: never misidentified as the registered project-a' "$out_impostor" 'confident current project: project-a'

RUN_FM_HOME=$MP_FM_HOME RUN_CWD=$proj_a
json_a=$(run_doctor --json)
unset RUN_FM_HOME RUN_CWD
contains 'multi-project JSON: current.name is project-a' "$json_a" '"name":"project-a"'
contains 'multi-project JSON: agents_md_present is true for project-a' "$json_a" '"agents_md_present":true'
not_contains 'multi-project JSON: never carries file contents' "$json_a" 'AGENTS-A-SECRET-MARKER'

# The native fm-project-mode.sh interface takes the bare project name only
# (no --raw or any other flag); the shared fixture script above records
# every argument it actually received and returns a distinct posture per
# project, so a caller that passes the wrong argument or mixes up which
# project it asked about is caught here.
PROJECT_MODE_LOG="$FAKE_FIRSTMATE/bin/fm-project-mode.log"
project_mode_log=$(cat "$PROJECT_MODE_LOG" 2>/dev/null || printf '')
not_contains 'native project-mode fixture: never invoked with --raw or any flag' "$project_mode_log" '--raw'
contains 'native project-mode fixture: invoked with the bare project-a name' "$project_mode_log" 'project-a'
contains 'native project-mode fixture: invoked with the bare project-b name' "$project_mode_log" 'project-b'
contains 'multi-project JSON: records project-a exact posture from the native script' "$json_a" '"name":"project-a","mode":"local-only","yolo":"off"'
contains 'multi-project JSON: records project-b exact, distinct posture from the native script' "$json_a" '"name":"project-b","mode":"direct-PR","yolo":"on"'

# =============================================================================
# 9. Valid, documented JSON schema
# =============================================================================
json=$(run_doctor --json)
json_parse_ok "$json"; jpo_rc=$?
case $jpo_rc in
  0) pass 'JSON: parses with a real JSON parser' ;;
  2) pass 'JSON: parse check skipped (no jq or python3 on the test runner itself)' ;;
  *) fail 'JSON: failed to parse' ;;
esac
for key in schema_version status exit_code timestamp system firstmate launcher captain runtime harnesses routing roles skills projects checks; do
  contains "JSON: top-level key '$key' present" "$json" "\"$key\":"
done
contains 'JSON: top-level status is UNKNOWN for the healthy fixture (commit_compat is the one honest gap)' "$json" '"schema_version":1,"status":"UNKNOWN",'
contains 'JSON: exit_code is 0 for the healthy fixture' "$json" '"exit_code":0'
contains 'JSON: a check row carries id/status/summary' "$json" '"id":"launcher.resolution","status":"PASS"'
contains 'JSON: system carries fm_home' "$json" "\"fm_home\":\"$FAKE_FM_HOME\""
contains 'JSON: launcher exposes the executable currently resolved from PATH' "$json" "\"resolved\":\"$LAUNCHER_OK/fm\""
contains 'JSON: an empty PATH competitor array serializes as []' "$json" '"competing_before":[],"competing_after":[]'
not_contains 'JSON: an empty PATH competitor array never serializes as [""]' "$json" '"competing_after":[""]'
contains 'JSON: runtime carries an explicit heartbeat object' "$json" '"heartbeat":{'

# =============================================================================
# 10. Herdr protocol incompatibility -> mandatory FAIL, nonzero exit
# =============================================================================
FM_TEST_HERDR_COMPATIBLE=false
out=$(run_doctor); code=$?
json_incompatible=$(FM_TEST_HERDR_COMPATIBLE=false run_doctor --json)
unset FM_TEST_HERDR_COMPATIBLE
if [ "$code" -eq 0 ]; then fail "herdr incompatible: expected nonzero exit, got 0"; else pass 'herdr incompatible: exit code is nonzero'; fi
contains 'herdr incompatible: server check reports FAIL' "$out" 'FAIL          runtime.herdr_server'
contains 'herdr incompatible: overall exit is reported nonzero' "$out" 'exit=1'
contains 'herdr incompatible: other mandatory checks stay healthy' "$out" 'PASS          captain.selection'
contains 'herdr incompatible JSON: runtime.herdr.compatible is false' "$json_incompatible" '"compatible":false'

# =============================================================================
# 11. crew-dispatch parsed via the jq tier, when jq is actually installed
# =============================================================================
SYS_JQ=$(command -v jq 2>/dev/null || printf '')
if [ -n "$SYS_JQ" ]; then
  JQ_BIN="$TMP_ROOT/jqbin"
  mkdir -p "$JQ_BIN"
  ln -s "$SYS_JQ" "$JQ_BIN/jq"
  RUN_PATH="$LAUNCHER_OK:$FAKE_BIN:$JQ_BIN:$SYS_PATH"
  out=$(run_doctor); code=$?
  unset RUN_PATH
  check 'jq tier: exit code is 0' 0 "$code"
  contains 'jq tier: crew-dispatch reports it was parsed via jq' "$out" 'parsed via jq'
  contains 'jq tier: the real crew-dispatch.json has 30 lanes' "$out" '30 lane(s)'
else
  pass 'jq tier: skipped (no jq installed on the test runner)'
fi

# =============================================================================
# 12. Routing model discovery is scoped to each lane's own harness
# =============================================================================
# openai-codex/gpt-6-sol is configured on both a pi lane and an omp lane in
# the real crew-dispatch.json (Astra, by contrast, is now confined to
# pi-only exceptional lanes). Make it absent from omp's fake catalog but
# available in pi's, so a doctor that still used the Captain's Pi detector
# for every lane would wrongly report the omp lane available too.
FM_TEST_OMP_AVAILABLE='anthropic/claude-sonnet-5,anthropic/claude-opus-5-5'
out=$(run_doctor); code=$?
unset FM_TEST_OMP_AVAILABLE
check 'harness-scoped routing: exit code stays 0 (non-mandatory)' 0 "$code"
contains 'harness-scoped routing: the pi lane is checked through pi and is available' "$out" 'PASS          routing.model.pi.openai-codex/gpt-6-sol'
contains 'harness-scoped routing: the omp lane for the same model is checked independently through omp and is unavailable' "$out" 'FAIL          routing.model.omp.openai-codex/gpt-6-sol'

# =============================================================================
# 13. No JSON parser available -> crew-dispatch validity UNKNOWN, exit 0
# =============================================================================
# Neither jq nor python3 on PATH: fm-doctor must never fall back to a
# brace-balance or sed scan and call that a parse. It reports UNKNOWN, never
# a false PASS and never a false FAIL, and uncertainty never forces exit 1.
RUN_PATH="$LAUNCHER_OK:$FAKE_BIN:$SYS_PATH_NO_PARSER"
out=$(run_doctor); code=$?
json_noparser=$(run_doctor --json)
unset RUN_PATH
check 'no parser: exit code stays 0 (uncertainty is not failure)' 0 "$code"
contains 'no parser: routing check reports UNKNOWN, never a false PASS' "$out" 'UNKNOWN       routing.crew_dispatch_valid'
not_contains 'no parser: routing check never falsely reports PASS' "$out" 'PASS          routing.crew_dispatch_valid'
not_contains 'no parser: routing check never falsely reports FAIL from a missing tool alone' "$out" 'FAIL          routing.crew_dispatch_valid'
contains 'no parser JSON: parse_method reports none' "$json_noparser" '"parse_method":"none"'
contains 'no parser JSON: crew_dispatch valid is null, never coerced true or false' "$json_noparser" '"valid":null'

# =============================================================================
# 14. Herdr server explicitly reports running:false -> mandatory FAIL
# =============================================================================
FM_TEST_HERDR_RUNNING=false
out=$(run_doctor); code=$?
unset FM_TEST_HERDR_RUNNING
if [ "$code" -eq 0 ]; then fail "herdr not running: expected nonzero exit, got 0"; else pass 'herdr not running: exit code is nonzero'; fi
contains 'herdr not running: server check reports FAIL' "$out" 'FAIL          runtime.herdr_server'
contains 'herdr not running: overall exit is reported nonzero' "$out" 'exit=1'

# =============================================================================
# 15. Herdr status --json fails outright (nonzero exit, no output) -> the
#     CLI could not even reach its own server: definitively unreachable,
#     mandatory FAIL, never merely UNKNOWN.
# =============================================================================
FM_TEST_HERDR_MODE=unreachable
out=$(run_doctor); code=$?
unset FM_TEST_HERDR_MODE
if [ "$code" -eq 0 ]; then fail "herdr unreachable: expected nonzero exit, got 0"; else pass 'herdr unreachable: exit code is nonzero'; fi
contains 'herdr unreachable: server check reports FAIL' "$out" 'FAIL          runtime.herdr_server'
contains 'herdr unreachable: names it unreachable' "$out" 'appears unreachable'

# =============================================================================
# 16. Herdr status --json succeeds but carries no recognizable "running"
#     field -> genuinely indeterminate: UNKNOWN, never FAIL, never PASS,
#     and never forces a nonzero exit.
# =============================================================================
FM_TEST_HERDR_MODE=weird
out=$(run_doctor); code=$?
unset FM_TEST_HERDR_MODE
check 'herdr weird output: exit code stays 0 (uncertainty is not failure)' 0 "$code"
contains 'herdr weird output: server check reports UNKNOWN' "$out" 'UNKNOWN       runtime.herdr_server'
not_contains 'herdr weird output: never falsely reports FAIL' "$out" 'FAIL          runtime.herdr_server'
not_contains 'herdr weird output: never falsely reports PASS' "$out" 'PASS          runtime.herdr_server'

# =============================================================================
# 17. Honest stale/dead task-record reporting: UNKNOWN when there are
#     in-flight records and no safe bulk classifier exists, NOT_APPLICABLE
#     when there is nothing to classify - never a bare PASS that implies
#     staleness was actually checked.
# =============================================================================
contains 'healthy fixture: no in-flight tasks -> staleness is NOT_APPLICABLE' "$(run_doctor)" 'NOT_APPLICABLE runtime.task_staleness'

TASK_FM_HOME="$TMP_ROOT/fm-home-with-task"
mkdir -p "$TASK_FM_HOME/state" "$TASK_FM_HOME/data" "$TASK_FM_HOME/config"
printf 'fixture\n' > "$TASK_FM_HOME/state/AgentX.meta"
RUN_FM_HOME=$TASK_FM_HOME
out_task=$(run_doctor); code_task=$?
unset RUN_FM_HOME
check 'in-flight task: exit code stays 0 (non-mandatory)' 0 "$code_task"
contains 'in-flight task: metadata count reports 1' "$out_task" '1 in-flight task record(s)'
contains 'in-flight task: staleness reports UNKNOWN, never a false PASS' "$out_task" 'UNKNOWN       runtime.task_staleness'
not_contains 'in-flight task: staleness never falsely reports PASS' "$out_task" 'PASS          runtime.task_staleness'

# =============================================================================
# 18. Git probes are read-only: every git invocation fm-doctor makes runs
#     with GIT_OPTIONAL_LOCKS=0, so no probe can write an index refresh or
#     ref lock into a repository it merely inspects (core rule: never
#     modify firstmate-config, official FirstMate, or a project). Proven
#     with a git wrapper that records the value it actually saw and then
#     execs the real git, so every other check still behaves normally.
# =============================================================================
SYS_GIT=$(command -v git 2>/dev/null || printf '')
if [ -n "$SYS_GIT" ]; then
  FAKE_GIT_DIR="$TMP_ROOT/gitwrap"
  mkdir -p "$FAKE_GIT_DIR"
  GIT_LOCKS_LOG="$TMP_ROOT/git-optional-locks.log"
  rm -f "$GIT_LOCKS_LOG"
  cat > "$FAKE_GIT_DIR/git" <<GITWRAP
#!/usr/bin/env bash
printf '%s\n' "\${GIT_OPTIONAL_LOCKS:-<unset>}" >> "$GIT_LOCKS_LOG"
exec "$SYS_GIT" "\$@"
GITWRAP
  chmod +x "$FAKE_GIT_DIR/git"
  RUN_PATH="$LAUNCHER_OK:$FAKE_BIN:$FAKE_GIT_DIR:$SYS_PATH"
  out=$(run_doctor); code=$?
  unset RUN_PATH
  check 'git read-only: exit code stays 0' 0 "$code"
  git_calls=$(wc -l < "$GIT_LOCKS_LOG" 2>/dev/null | tr -d ' ')
  [ -n "$git_calls" ] || git_calls=0
  if [ "$git_calls" -gt 0 ]; then pass 'git read-only: fm-doctor made at least one git probe'; else fail 'git read-only: no git probe was captured'; fi
  bad=0
  while IFS= read -r val; do [ "$val" = "0" ] || bad=1; done < "$GIT_LOCKS_LOG"
  if [ "$bad" -eq 0 ] && [ "$git_calls" -gt 0 ]; then
    pass 'git read-only: every git probe ran with GIT_OPTIONAL_LOCKS=0'
  else
    fail "git read-only: a git probe ran without GIT_OPTIONAL_LOCKS=0"
  fi
else
  pass 'git read-only: no system git available to wrap (skipped)'
fi

# =============================================================================
# 19. Official FirstMate internal skill leaking into the shared skill root ->
#     reported FAIL, but non-mandatory: exit 0. Proves the shared root a
#     worker actually reads never silently resolves into the official
#     checkout's Captain/FirstMate-only .agents/skills (primary-policy.md
#     section 2, README "Worker context and skill classes").
# =============================================================================
FAKE_HOME19="$TMP_ROOT/home-official-leak"
mkdir -p "$FAKE_HOME19/.agents/skills"
seed_skills_root "$FAKE_HOME19/.agents/skills" "$CONFIG_ROOT"
rm -rf "$FAKE_HOME19/.agents/skills/architecture-review"
ln -s "$FAKE_FIRSTMATE/.agents/skills/fixture-internal-only" "$FAKE_HOME19/.agents/skills/architecture-review"
RUN_HOME="$FAKE_HOME19"
out=$(run_doctor); code=$?
unset RUN_HOME
check 'official leak: exit code stays 0 (non-mandatory)' 0 "$code"
contains 'official leak: reported FAIL' "$out" 'FAIL          skills.no_official_internal_leak'
contains 'official leak: names the leaking skill' "$out" 'architecture-review'
contains 'official leak: names the official FirstMate root' "$out" "$FAKE_FIRSTMATE"

# =============================================================================
# 20. Status contract: human overall status, JSON overall status, and
#     process exit code must never disagree. A harness-specific optional
#     Captain candidate absent from the active harness's own catalog (the
#     Pi-only Sonnet provider is never native to OMP - see README.md
#     "Captain startup model") is expected, tolerated fallback behavior when
#     a usable candidate exists elsewhere in the chain, never a genuine
#     defect: it must not drag the overall verdict to FAIL while the process
#     exits 0. Covers all three contract states this task's regression
#     coverage requires: healthy, warning/optional-unavailable, and genuine
#     failure - proving the human "DOCTOR X exit=Y" line, JSON "status", and
#     the real exit code agree in every case.
# =============================================================================
status_exit_agree() { # <label> <human-out> <json-out> <exit-code>
  local label=$1 human=$2 json=$3 code=$4 human_status json_status
  human_status=$(printf '%s' "$human" | sed -n 's/^DOCTOR \([A-Z_]*\) exit=.*/\1/p')
  json_status=$(printf '%s' "$json" | sed -n 's/.*"schema_version":[0-9]*,"status":"\([A-Z_]*\)".*/\1/p')
  check "$label: human header status matches JSON status" "$json_status" "$human_status"
  if [ "$human_status" = FAIL ]; then
    if [ "$code" -eq 0 ]; then fail "$label: human/JSON status is FAIL but exit code is 0"; else pass "$label: FAIL status paired with nonzero exit"; fi
  else
    check "$label: non-FAIL status pairs with exit code 0" 0 "$code"
  fi
}

# 20a. Healthy: every candidate available, nothing unavailable at all.
out20a=$(run_doctor); code20a=$?
json20a=$(run_doctor --json)
status_exit_agree '20a healthy' "$out20a" "$json20a" "$code20a"

# 20b. Optional-unavailable (the reported bug): active harness is OMP
# (fm-doctor's default), Sol and Astra are available in OMP's native
# catalog, but the Pi-only Sonnet provider is not - exactly the shape
# README.md documents as expected on OMP. Selection still succeeds via Sol.
FM_TEST_OMP_AVAILABLE='openai-codex/gpt-6-sol,openai-codex/gpt-6-astra,anthropic/claude-sonnet-5,anthropic/claude-opus-5-5,anthropic/claude-haiku-4-5,openai-codex/gpt-6-luna'
out20b=$(run_doctor); code20b=$?
json20b=$(FM_TEST_OMP_AVAILABLE='openai-codex/gpt-6-sol,openai-codex/gpt-6-astra,anthropic/claude-sonnet-5,anthropic/claude-opus-5-5,anthropic/claude-haiku-4-5,openai-codex/gpt-6-luna' run_doctor --json)
unset FM_TEST_OMP_AVAILABLE
check '20b optional-unavailable: exit code stays 0' 0 "$code20b"
contains '20b optional-unavailable: Sol is selected as preferred' "$out20b" 'selected preferred candidate openai-codex/gpt-6-sol'
not_contains '20b optional-unavailable: the absent Pi-only candidate is never reported FAIL' "$out20b" 'FAIL          captain.model.pi-claude-code-provider/sonnet'
status_exit_agree '20b optional-unavailable' "$out20b" "$json20b" "$code20b"

# 20c. Genuine failure: no configured Captain candidate is usable at all.
FM_TEST_AVAILABLE=''
out20c=$(run_doctor); code20c=$?
json20c=$(FM_TEST_AVAILABLE='' run_doctor --json)
unset FM_TEST_AVAILABLE
status_exit_agree '20c genuine failure' "$out20c" "$json20c" "$code20c"


printf '\nDOCTOR TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
