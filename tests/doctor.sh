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
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$CONFIG_ROOT/bin/fm-doctor"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi; }
contains() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in '$2')" ;; esac; }
not_contains() { case $2 in *"$3"*) fail "$1 (unexpectedly found '$3' in '$2')" ;; *) pass "$1" ;; esac; }

# Zero-dependency JSON brace/bracket balance check (no jq requirement, mirrors
# bin/fm-doctor's own crew-dispatch validator).
json_balanced() {
  printf '%s' "$1" | awk '
    BEGIN { d = 0 }
    { for (i = 1; i <= length($0); i++) { c = substr($0, i, 1); if (c == "{" || c == "[") d++; if (c == "}" || c == "]") d-- } }
    END { exit (d == 0) ? 0 : 1 }
  '
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
available=",${FM_TEST_AVAILABLE-openai-codex/gpt-5.6-sol,pi-claude-code-provider/sonnet,openai-codex/gpt-6-astra},"
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
  printf '{"client":{"version":"9.9.9-fake","protocol":19},"server":{"running":%s,"version":"9.9.9-fake","protocol":19,"compatible":%s}}\n' \
    "${FM_TEST_HERDR_RUNNING:-true}" "${FM_TEST_HERDR_COMPATIBLE:-true}"
  exit 0
fi
exit 0
SH
chmod +x "$FAKE_BIN/herdr"

cat > "$FAKE_BIN/omp" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" != --version ] || printf 'omp/9.9.9-fake\n'
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
HEALTHY_AVAILABLE="openai-codex/gpt-5.6-sol,pi-claude-code-provider/sonnet,openai-codex/gpt-6-astra,openai-codex/gpt-5.3-codex-spark,openai-codex/gpt-5.5,anthropic/claude-sonnet-5,anthropic/claude-opus-5"

# A fully hermetic system PATH: symlink only the exact utilities fm-doctor
# needs, never a whole real bin directory. On macOS, /usr/bin itself ships a
# real `fm` (Apple's Foundation Models CLI, a genuine real-world PATH
# collision), so the ambient PATH and even a whole system directory are both
# unsafe defaults for a deterministic fixture.
SYS_BIN="$TMP_ROOT/sysbin"
mkdir -p "$SYS_BIN"
for _tool in bash git uname sed awk grep wc date find stat readlink basename dirname tr head cat mkdir env; do
  _p=$(command -v "$_tool" 2>/dev/null) || continue
  ln -s "$_p" "$SYS_BIN/$_tool"
done
SYS_PATH=$SYS_BIN

run_doctor() { # [extra args to fm-doctor]
  ( cd "${RUN_CWD:-$TMP_ROOT}" && \
    PATH="${RUN_PATH:-$LAUNCHER_OK:$FAKE_BIN:$SYS_PATH}" \
    HOME="${RUN_HOME:-$FAKE_HOME}" \
    FIRSTMATE_ROOT="${RUN_FIRSTMATE_ROOT:-$FAKE_FIRSTMATE}" \
    FM_HOME="${RUN_FM_HOME:-$FAKE_FM_HOME}" \
    FM_CONFIG_ENV="$TMP_ROOT/no-such-env-file" \
    FM_SKILLS_ROOT="${RUN_SKILLS_ROOT:-${RUN_HOME:-$FAKE_HOME}/.agents/skills}" \
    FM_TEST_AVAILABLE="${FM_TEST_AVAILABLE-$HEALTHY_AVAILABLE}" \
    FM_TEST_SONNET_INSTALLED="${FM_TEST_SONNET_INSTALLED:-yes}" \
    FM_TEST_SONNET_AUTH="${FM_TEST_SONNET_AUTH:-ready}" \
    FM_TEST_HERDR_RUNNING="${FM_TEST_HERDR_RUNNING:-true}" \
    FM_TEST_HERDR_COMPATIBLE="${FM_TEST_HERDR_COMPATIBLE:-true}" \
    "${RUN_DOC:-$DOC}" "$@" )
}

# =============================================================================
# 1. Healthy: PASS overall, exit 0
# =============================================================================
out=$(run_doctor); code=$?
check 'healthy: exit code is 0' 0 "$code"
contains 'healthy: overall status is PASS' "$out" 'DOCTOR PASS exit=0'
contains 'healthy: launcher resolves ours first' "$out" "PASS          launcher.resolution"
contains 'healthy: captain selects the preferred candidate' "$out" 'selected preferred candidate openai-codex/gpt-5.6-sol'
contains 'healthy: herdr server reported running' "$out" 'PASS          runtime.herdr_server'
contains 'healthy: roles all readable' "$out" 'PASS          roles.tenth-man'
contains 'healthy: skills fully installed' "$out" 'PASS          skills.global_installation'
contains 'healthy: Fable/Qwen reported DEFERRED, not FAIL' "$out" 'DEFERRED      routing.fable_qwen_deferred'
not_contains 'healthy: Fable/Qwen deferred check is never FAIL' "$out" 'FAIL          routing.fable_qwen_deferred'

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
out=$(run_doctor); code=$?
unset FM_TEST_AVAILABLE
check 'Sol down: exit code is 0' 0 "$code"
contains 'Sol down: Sonnet is selected' "$out" 'selected pi-claude-code-provider/sonnet'
contains 'Sol down: Sonnet reports available despite broker invalid_state' "$out" 'PASS          captain.model.pi-claude-code-provider/sonnet'
contains 'Sol down: fallback reason names Sol' "$out" 'openai-codex/gpt-5.6-sol'

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
BROKEN_FM_HOME="$TMP_ROOT/fm-home-broken-dispatch"
mkdir -p "$BROKEN_FM_HOME/state" "$BROKEN_FM_HOME/data" "$BROKEN_FM_HOME/config" "$BROKEN_FM_HOME/projects"
printf '{"rules": [ { "when": "x", "use": [ { "harness": "pi", "model": "a/b", "effort": "yolo" } ] }' > "$BROKEN_FM_HOME/config/crew-dispatch.json"
RUN_FM_HOME=$BROKEN_FM_HOME
out=$(run_doctor); code=$?
unset RUN_FM_HOME
if [ "$code" -eq 0 ]; then fail "invalid crew-dispatch: expected nonzero exit, got 0"; else pass 'invalid crew-dispatch: exit code is nonzero'; fi
contains 'invalid crew-dispatch: routing check reports FAIL' "$out" 'FAIL          routing.crew_dispatch_valid'
contains 'invalid crew-dispatch: other mandatory checks stay healthy' "$out" 'PASS          captain.selection'

# =============================================================================
# 7. Missing role/skill statuses -> reported FAIL, but non-mandatory: exit 0
# =============================================================================
FAKE_CFG="$TMP_ROOT/fake-config-root"
mkdir -p "$FAKE_CFG/bin" "$FAKE_CFG/firstmate" "$FAKE_CFG/roles/senior-fullstack" "$FAKE_CFG/roles/architecture" "$FAKE_CFG/skills/architecture-review"
cp "$CONFIG_ROOT/bin/fm-doctor" "$FAKE_CFG/bin/fm-doctor"
ln -s "$CONFIG_ROOT/bin/fm" "$FAKE_CFG/bin/fm"
chmod +x "$FAKE_CFG/bin/fm-doctor"
cp "$CONFIG_ROOT/firstmate/fm-captain-lib.sh" "$FAKE_CFG/firstmate/fm-captain-lib.sh"
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
- project-b [local-only] - fixture project B (added 2026-01-01)
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

RUN_FM_HOME=$MP_FM_HOME RUN_CWD=$proj_a
json_a=$(run_doctor --json)
unset RUN_FM_HOME RUN_CWD
contains 'multi-project JSON: current.name is project-a' "$json_a" '"name":"project-a"'
contains 'multi-project JSON: agents_md_present is true for project-a' "$json_a" '"agents_md_present":true'
not_contains 'multi-project JSON: never carries file contents' "$json_a" 'AGENTS-A-SECRET-MARKER'

# =============================================================================
# 9. Valid, documented JSON schema
# =============================================================================
json=$(run_doctor --json)
if json_balanced "$json"; then pass 'JSON: braces/brackets are balanced'; else fail 'JSON: unbalanced braces/brackets'; fi
for key in schema_version status exit_code timestamp system firstmate launcher captain runtime harnesses routing roles skills projects checks; do
  contains "JSON: top-level key '$key' present" "$json" "\"$key\":"
done
contains 'JSON: status is PASS for the healthy fixture' "$json" '"status":"PASS"'
contains 'JSON: exit_code is 0 for the healthy fixture' "$json" '"exit_code":0'
contains 'JSON: a check row carries id/status/summary' "$json" '"id":"launcher.resolution","status":"PASS"'

printf '\nDOCTOR TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
