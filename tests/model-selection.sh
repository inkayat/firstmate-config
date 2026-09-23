#!/usr/bin/env bash
# model-selection.sh - FirstMate Captain startup model selection acceptance.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FM="$CONFIG_ROOT/bin/fm"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }
check() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}
contains() {
  case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in '$2')" ;; esac
}

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-model-selection.XXXXXX") || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT

fake_bin="$TMP_ROOT/bin"
fake_firstmate="$TMP_ROOT/firstmate"
fake_home="$TMP_ROOT/home"
fake_pi_home="$TMP_ROOT/pi-home"
mkdir -p "$fake_bin" "$fake_firstmate/.pi/extensions" "$fake_home" "$fake_pi_home"
printf 'test\n' > "$fake_firstmate/AGENTS.md"
printf 'test\n' > "$fake_firstmate/.pi/extensions/fm-primary-pi-watch.ts"
printf 'test\n' > "$fake_firstmate/.pi/extensions/fm-primary-turnend-guard.ts"

cat > "$fake_bin/herdr" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fake_bin/herdr"

cat > "$fake_bin/pi" <<'SH'
#!/usr/bin/env bash
available=",${FM_TEST_AVAILABLE-openai-codex/gpt-6-sol,pi-claude-code-provider/sonnet,openai-codex/gpt-6-astra},"
model_base() { printf '%s' "${1#*/}"; }
provider_of() { printf '%s' "${1%%/*}"; }
is_available() { case "$available" in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
thinking_for() {
  case $1 in
    openai-codex/gpt-6-sol) printf '%s' "${FM_TEST_SOL_THINKING:-yes}" ;;
    pi-claude-code-provider/sonnet) printf '%s' "${FM_TEST_SONNET_THINKING:-yes}" ;;
    openai-codex/gpt-6-astra) printf '%s' "${FM_TEST_ASTRA_THINKING:-yes}" ;;
    *) printf 'yes' ;;
  esac
}
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
    printf '%s  %s  1K  1K  %s  no\n' "$(provider_of "$model")" "$(model_base "$model")" "$(thinking_for "$model")"
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
printf 'fake pi should not be executed in model-selection tests\n' >&2
exit 64
SH
chmod +x "$fake_bin/pi"

cat > "$fake_bin/claude" <<'SH'
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
  unknown)
    printf 'temporary status failure\n' >&2
    exit 1
    ;;
  *) exit 64 ;;
esac
SH
chmod +x "$fake_bin/claude"

run_fm() {
  PATH="$fake_bin:$PATH" \
  HOME="$TMP_ROOT/home-dir" \
  PI_CODING_AGENT_DIR="$fake_pi_home" \
  FIRSTMATE_ROOT="$fake_firstmate" \
  FM_HOME="$fake_home" \
  FM_PI_EXTENSIONS=explicit \
  FM_TEST_AVAILABLE="${FM_TEST_AVAILABLE-openai-codex/gpt-6-sol,pi-claude-code-provider/sonnet,openai-codex/gpt-6-astra}" \
  FM_TEST_SOL_THINKING="${FM_TEST_SOL_THINKING:-yes}" \
  FM_TEST_SONNET_THINKING="${FM_TEST_SONNET_THINKING:-yes}" \
  FM_TEST_ASTRA_THINKING="${FM_TEST_ASTRA_THINKING:-yes}" \
  FM_TEST_SONNET_INSTALLED="${FM_TEST_SONNET_INSTALLED:-yes}" \
  FM_TEST_SONNET_AUTH="${FM_TEST_SONNET_AUTH:-ready}" \
  "$FM" --harness pi --print-command
}

out=$(run_fm 2>&1) || { fail "healthy startup command failed: $out"; printf '\nMODEL SELECTION FAIL\n'; exit 1; }
check 'healthy startup selects GPT-6 Sol' 'openai-codex/gpt-6-sol' "$(field "$out" SELECTED_MODEL)"
check 'healthy startup keeps medium effort' 'medium' "$(field "$out" SELECTED_EFFORT)"
check 'preferred model is observable' 'openai-codex/gpt-6-sol' "$(field "$out" PREFERRED_MODEL)"
check 'preferred effort is observable' 'medium' "$(field "$out" PREFERRED_EFFORT)"
check 'Pi command carries the selected model' 'openai-codex/gpt-6-sol' "$(printf '%s\n' "$(field "$out" COMMAND)" | awk '{for (i=1;i<=NF;i++) if ($i=="--model") print $(i+1)}')"
check 'Pi command carries selected effort' 'medium' "$(printf '%s\n' "$(field "$out" COMMAND)" | awk '{for (i=1;i<=NF;i++) if ($i=="--thinking") print $(i+1)}')"

out=$(FM_TEST_AVAILABLE='pi-claude-code-provider/sonnet,openai-codex/gpt-6-astra' run_fm 2>&1) || { fail "fallback to Sonnet command failed: $out"; out=''; }
check 'unavailable Sol selects usable Claude Sonnet despite broker invalid_state' 'pi-claude-code-provider/sonnet' "$(field "$out" SELECTED_MODEL)"
check 'Claude Sonnet keeps high effort' 'high' "$(field "$out" SELECTED_EFFORT)"
contains 'fallback reason is visible' "$(field "$out" FALLBACK_REASON)" 'openai-codex/gpt-6-sol'

out=$(FM_TEST_AVAILABLE='pi-claude-code-provider/sonnet,openai-codex/gpt-6-astra' FM_TEST_SONNET_AUTH=unavailable run_fm 2>&1) || { fail "authoritative Sonnet auth failure command failed: $out"; out=''; }
check 'authoritative Claude Sonnet auth failure skips to Astra' 'openai-codex/gpt-6-astra' "$(field "$out" SELECTED_MODEL)"
contains 'authoritative Sonnet auth failure remains visible' "$(field "$out" FALLBACK_REASON)" 'pi-claude-code-provider/sonnet'

out=$(FM_TEST_AVAILABLE='pi-claude-code-provider/sonnet,openai-codex/gpt-6-astra' FM_TEST_SONNET_AUTH=unknown run_fm 2>&1) || { fail "unknown Sonnet auth command failed: $out"; out=''; }
check 'unknown non-authoritative Sonnet auth does not reject an installed catalog model' 'pi-claude-code-provider/sonnet' "$(field "$out" SELECTED_MODEL)"
check 'unknown Sonnet selection exposes its availability state' 'UNKNOWN' "$(field "$out" SELECTED_AVAILABILITY)"

out=$(FM_TEST_AVAILABLE='openai-codex/gpt-6-astra' run_fm 2>&1) || { fail "fallback to Astra command failed: $out"; out=''; }
check 'unavailable Sol and Sonnet selects Astra' 'openai-codex/gpt-6-astra' "$(field "$out" SELECTED_MODEL)"
check 'Astra keeps xhigh effort' 'xhigh' "$(field "$out" SELECTED_EFFORT)"
contains 'both unavailable candidates are named' "$(field "$out" FALLBACK_REASON)" 'pi-claude-code-provider/sonnet'

if out=$(FM_TEST_AVAILABLE='' run_fm 2>&1); then
  fail 'all unavailable candidates should fail startup'
else
  pass 'all unavailable candidates fail startup'
  contains 'all-unavailable failure is clear' "$out" 'no configured captain startup model is available'
  contains 'all-unavailable failure names Sol' "$out" 'openai-codex/gpt-6-sol'
  contains 'all-unavailable failure names Sonnet' "$out" 'pi-claude-code-provider/sonnet'
  contains 'all-unavailable failure names Astra' "$out" 'openai-codex/gpt-6-astra'
fi

out=$(FM_TEST_SOL_THINKING=no run_fm 2>&1) || { fail "unsupported effort fallback command failed: $out"; out=''; }
check 'unsupported effort does not downgrade and skips candidate' 'pi-claude-code-provider/sonnet' "$(field "$out" SELECTED_MODEL)"
check 'next candidate effort remains high' 'high' "$(field "$out" SELECTED_EFFORT)"
contains 'unsupported effort reason is visible' "$(field "$out" FALLBACK_REASON)" 'unsupported configured effort medium'

before=$(shasum -a 256 "$CONFIG_ROOT/firstmate/crew-dispatch.json" | awk '{print $1}')
run_fm >/dev/null 2>&1 || true
after=$(shasum -a 256 "$CONFIG_ROOT/firstmate/crew-dispatch.json" | awk '{print $1}')
check 'crew-dispatch remains unchanged' "$before" "$after"

if find "$fake_pi_home" -type f -print | grep -q .; then
  fail 'standalone Pi configuration was touched'
else
  pass 'standalone Pi default remains untouched'
fi

printf '\nMODEL SELECTION %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
