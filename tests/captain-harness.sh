#!/usr/bin/env bash
# Captain boundary regression: wrong harness/catalog/cwd must not change fleet state.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-captain-harness.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd)
mkdir -p "$TMP/bin" "$TMP/official/.omp/extensions" "$TMP/official/.pi/extensions" "$TMP/home" "$TMP/origin"
printf 'fixture\n' > "$TMP/official/AGENTS.md"
for ext in .omp/extensions/fm-primary-omp-watch.ts .omp/extensions/fm-primary-turnend-guard.ts .pi/extensions/fm-primary-pi-watch.ts .pi/extensions/fm-primary-turnend-guard.ts; do
  touch "$TMP/official/$ext"
done
cat > "$TMP/bin/omp" <<'SH'
#!/usr/bin/env bash
case ${1:-} in
  --version) echo 'omp 18.1.21'; exit ;;
  models)
    [ "$PWD" = "$FIRSTMATE_ROOT" ] || exit 65
    case " $* " in *' --no-extensions '*) ;; *) exit 66 ;; esac
    case ${CATALOG:-normal} in
      broken) echo 'not JSON'; exit ;;
      invalid_schema) echo '{"models":[{}]}'; exit ;;
      failed) exit 1 ;;
      empty) echo '{"models":[]}'; exit ;;
      duplicate) printf '{"models":[{"provider":"openai-codex","id":"gpt-6.1-sol","reasoning":true,"thinking":["medium"]},{"provider":"openai-codex","id":"gpt-6-astra","reasoning":true,"thinking":["xhigh"]},{"provider":"openai-codex","id":"gpt-6-astra","reasoning":true,"thinking":["high"]}]}\n'; exit ;;
    esac
    printf '{"models":['
    [ "${GROK:-absent}" != available ] || printf '{"provider":"xai","id":"grok-4.7","selector":"xai/grok-4.7","reasoning":true,"thinking":["%s","xhigh"]},' "${GROK_EFFORT:-high}"
    if [ "${CATALOG:-normal}" != astra ] && [ "${CATALOG:-normal}" != sonnet ]; then
      printf '{"provider":"openai-codex","id":"gpt-6.1-sol","selector":"openai-codex/gpt-6.1-sol","reasoning":true,"thinking":["%s"]},' "${SOL_EFFORT:-medium}"
    fi
    if [ "${CATALOG:-normal}" = sonnet ] || [ "${CATALOG:-normal}" = full ]; then
      printf '{"provider":"anthropic","id":"claude-sonnet-5-5","selector":"anthropic/claude-sonnet-5-5","reasoning":true,"thinking":["%s","xhigh"]},' "${SONNET_EFFORT:-high}"
    fi
    printf '{"provider":"openai-codex","id":"gpt-6-astra","selector":"openai-codex/gpt-6-astra","reasoning":true,"thinking":["xhigh"]}]}\n'
    exit ;;
esac
printf 'EXEC_HARNESS=omp\nEXEC_CWD=%s\nEXEC_HOME=%s\nEXEC_BACKEND=%s\nEXEC_ORIGIN=%s\n' "$PWD" "$FM_HOME" "$FM_BACKEND" "$FM_FORK_ORIGIN_CWD"
printf 'EXEC_FOREIGN=%s%s%s\n' "${CLAUDECODE-}" "${PI_CODING_AGENT-}" "${FM_PI_HARNESS-}"
printf 'EXEC_OMP_MARKER=%s\nEXEC_TIMEOUT=%s\n' "${FM_OMP_HARNESS-}" "${FM_TIMEOUT_MECHANISM_OVERRIDE-}"
printf 'EXEC_VAULT=%s\n' "${FM_SKILL_VAULT_ROOT-}"
printf 'EXEC_ARGS=%s\n' "$*"
SH
cat > "$TMP/bin/pi" <<'SH'
#!/usr/bin/env bash
case ${1:-} in
  --version) echo 'pi 0.85.1' ;;
  --list-models)
    [ "${PI_LIST:-ok}" = ok ] || exit 1
    printf 'openai-codex gpt-6.1-sol 1K 1K yes no\nopenai-codex gpt-6-astra 1K 1K yes no\n'
    [ "${PI_GROK:-absent}" != listed ] || printf 'xai grok-4.7 500K 500K %s yes\n' "${PI_GROK_THINKING:-yes}"
    # Pi lists only models whose provider is usable: the Claude Code
    # provider's unversioned alias once installed, Anthropic's exact id once
    # credentials are configured.
    [ "${PI_CLAUDE:-absent}" != installed ] || printf 'pi-claude-code-provider sonnet 1K 1K yes no\n'
    [ "${PI_ANTHROPIC:-absent}" != configured ] || printf 'anthropic claude-sonnet-5-5 1M 128K %s yes\n' "${PI_SONNET_THINKING:-yes}"
    ;;
  auth)
    case ${PI_AUTH:-ready} in
      ready) printf '{"status":"ready"}\n' ;;
      *) printf '{"status":"error","reason":"auth service unreachable"}\n' ;;
    esac ;;
  list)
    if [ "${PI_CLAUDE:-absent}" = installed ]; then printf 'User packages:\n  npm:pi-claude-code-provider\n'; else echo 'No packages installed.'; fi ;;
  *)
    printf 'EXEC_HARNESS=pi\n'
    printf 'EXEC_OMP_MARKER=%s\nEXEC_TIMEOUT=%s\n' "${FM_OMP_HARNESS-}" "${FM_TIMEOUT_MECHANISM_OVERRIDE-}"
    printf 'EXEC_VAULT=%s\n' "${FM_SKILL_VAULT_ROOT-}"
    printf 'EXEC_ARGS=%s\n' "$*"
    ;;
esac
SH
cat > "$TMP/bin/claude" <<'SH'
#!/usr/bin/env bash
[ "$*" = 'auth status' ] || exit 64
printf '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"max"}\n'
SH
cat > "$TMP/bin/herdr" <<'SH'
#!/usr/bin/env bash
case ${1:-} in
  --version) echo 'herdr 0.8.0' ;;
  status) echo '{"server":{"running":true,"compatible":true}}' ;;
esac
SH
chmod +x "$TMP/bin/omp" "$TMP/bin/pi" "$TMP/bin/herdr" "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH" HOME="$TMP/home" FM_CONFIG_ENV="$TMP/absent"
export FIRSTMATE_ROOT="$TMP/official" FM_HOME="$TMP/fleet" FM_BACKEND=herdr
export FM_PI_BIN="$TMP/bin/pi" FM_OMP_BIN="$TMP/bin/omp" FM_PI_EXTENSIONS=explicit
failed=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s (expected %s, got %s)\n' "$1" "$2" "$3"; failed=1; fi; }
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }
run() { (cd "$TMP/origin" && "$ROOT/bin/fm" "$@"); }
OMP_DEFAULT="$FM_OMP_BIN --model openai-codex/gpt-6.1-sol --thinking medium"
OMP_CLAUDE="$FM_OMP_BIN --model anthropic/claude-sonnet-5-5 --thinking high"
OMP_GROK="$FM_OMP_BIN --model xai/grok-4.7 --thinking high"
PI_EXTS="-e $FIRSTMATE_ROOT/.pi/extensions/fm-primary-turnend-guard.ts -e $FIRSTMATE_ROOT/.pi/extensions/fm-primary-pi-watch.ts"
PI_DEFAULT="$FM_PI_BIN --model openai-codex/gpt-6.1-sol --thinking medium $PI_EXTS"
PI_SONNET55="$FM_PI_BIN --model anthropic/claude-sonnet-5-5 --thinking high $PI_EXTS"
PI_GROK_CMD="$FM_PI_BIN --model xai/grok-4.7 --thinking high $PI_EXTS"
out=$(PI_GROK=listed run --print-command 2>&1)
check 'default Captain harness is Pi' pi "$(field "$out" CAPTAIN_HARNESS)"
check 'default Pi Captain prefers Grok 4.7 at high when Pi reports it' "$PI_GROK_CMD" "$(field "$out" COMMAND)"
check 'Grok default needs no fallback reason' '' "$(field "$out" FALLBACK_REASON)"
check 'default Captain cwd is official, not origin' "$FIRSTMATE_ROOT" "$(field "$out" CAPTAIN_CWD)"
out=$(run --print-command 2>&1)
check 'default Pi without Grok falls back to Sol with trust-free extensions' "$PI_DEFAULT" "$(field "$out" COMMAND)"
check 'default without Grok names it as the skipped first preference' xai/grok-4.7 "$(field "$out" FALLBACK_REASON | cut -d' ' -f1)"
out=$(PI_GROK=listed PI_GROK_THINKING=no run --print-command 2>&1)
check 'Pi Grok without thinking support is skipped' openai-codex/gpt-6.1-sol "$(field "$out" SELECTED_MODEL)"
out=$(PI_GROK=listed run --harness pi --print-command 2>&1)
check 'explicit Pi selects the same Grok command' "$PI_GROK_CMD" "$(field "$out" COMMAND)"
out=$(run --harness omp --print-command 2>&1)
check 'explicit OMP uses native command' "$OMP_DEFAULT" "$(field "$out" COMMAND)"
check 'explicit OMP without Grok names it as the skipped first preference' xai/grok-4.7 "$(field "$out" FALLBACK_REASON | cut -d' ' -f1)"
out=$(GROK=available run --harness omp --print-command 2>&1)
check 'explicit OMP prefers Grok 4.7 at high when OMP reports it' "$OMP_GROK" "$(field "$out" COMMAND)"
check 'OMP Grok selection needs no fallback reason' '' "$(field "$out" FALLBACK_REASON)"
out=$(GROK=available GROK_EFFORT=medium run --harness omp --print-command 2>&1)
check 'Grok without exact high effort is skipped, never downgraded' "$OMP_DEFAULT" "$(field "$out" COMMAND)"
out=$(CATALOG=astra run --harness omp --print-command 2>&1)
check 'OMP skips absent Sol and the Pi-only Sonnet candidate without inventing replacement' openai-codex/gpt-6-astra "$(field "$out" SELECTED_MODEL)"
check 'Astra effort is not downgraded' xhigh "$(field "$out" SELECTED_EFFORT)"
out=$(CATALOG=sonnet run --harness omp --print-command 2>&1)
check 'OMP falls back to its own native Claude Sonnet candidate, never the Pi-only provider id' anthropic/claude-sonnet-5-5 "$(field "$out" SELECTED_MODEL)"
check 'OMP native Sonnet fallback keeps high effort' high "$(field "$out" SELECTED_EFFORT)"
out=$(SOL_EFFORT=low run --harness omp --print-command 2>&1)
check 'unsupported exact effort skips candidate' openai-codex/gpt-6-astra "$(field "$out" SELECTED_MODEL)"
for kind in broken failed invalid_schema; do
  out=$(CATALOG=$kind run --harness omp --check 2>&1)
  check "$kind catalog is UNKNOWN rather than false unavailability" UNKNOWN "$(field "$out" SELECTED_AVAILABILITY)"
done
if CATALOG=empty run --harness omp --check >/dev/null 2>&1; then check 'empty native catalog refuses launch' failure success; else check 'empty native catalog refuses launch' failure failure; fi
if run --harness invalid --check >/dev/null 2>&1; then check 'unknown harness refuses launch' failure success; else check 'unknown harness refuses launch' failure failure; fi
out=$(CLAUDECODE=1 PI_CODING_AGENT=1 FM_PI_HARNESS=pi FM_OMP_HARNESS=foreign FM_TIMEOUT_MECHANISM_OVERRIDE=external run --harness omp 2>&1)
check 'explicit OMP launch crosses directly into OMP' omp "$(field "$out" EXEC_HARNESS)"
check 'real launch runs at official cwd' "$FIRSTMATE_ROOT" "$(field "$out" EXEC_CWD)"
check 'real launch preserves operational home' "$FM_HOME" "$(field "$out" EXEC_HOME)"
check 'real launch preserves Herdr' herdr "$(field "$out" EXEC_BACKEND)"
check 'real launch preserves origin hint' "$TMP/origin" "$(field "$out" EXEC_ORIGIN)"
check 'foreign Captain identity is scrubbed' '' "$(field "$out" EXEC_FOREIGN)"
check 'OMP establishes its own identity after scrubbing' omp "$(field "$out" EXEC_OMP_MARKER)"
check 'OMP selects stock timeout topology within ancestry bound' bash "$(field "$out" EXEC_TIMEOUT)"
out=$(PI_GROK=listed FM_OMP_HARNESS=omp FM_TIMEOUT_MECHANISM_OVERRIDE= run 2>&1)
check 'default launch crosses directly into Pi' pi "$(field "$out" EXEC_HARNESS)"
check 'default Pi launch receives Grok 4.7 at high' "--model xai/grok-4.7 --thinking high $PI_EXTS" "$(field "$out" EXEC_ARGS)"
check 'default Pi does not inherit OMP identity' '' "$(field "$out" EXEC_OMP_MARKER)"
check 'default Pi does not force OMP timeout topology' '' "$(field "$out" EXEC_TIMEOUT)"

# A previously exported FM_SKILL_VAULT_ROOT (the removed specialist-vault
# handoff surface) simulates a stale value inherited from the calling
# shell, not one written by any env file (FM_CONFIG_ENV points at an
# absent path throughout this fixture) - sourcing that absent file cannot
# clear it, so only bin/fm's own launch-boundary scrub can.
export FM_SKILL_VAULT_ROOT="$TMP/inherited-stale-vault-root"
out=$(run --harness omp 2>&1)
check 'inherited stale FM_SKILL_VAULT_ROOT never reaches the OMP Captain process' '' "$(field "$out" EXEC_VAULT)"
out=$(run 2>&1)
check 'inherited stale FM_SKILL_VAULT_ROOT never reaches the Pi Captain process' '' "$(field "$out" EXEC_VAULT)"
unset FM_SKILL_VAULT_ROOT
for harness in omp pi; do
  out=$(run --harness "$harness" doctor --json 2>/dev/null)
  actual=$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["captain"]["harness"])' 2>/dev/null)
  check "doctor reports selected $harness Captain" "$harness" "$actual"
  out=$(run --harness "$harness" version --json 2>/dev/null)
  actual=$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["captain_harness"])' 2>/dev/null)
  check "version reports selected $harness Captain" "$harness" "$actual"
  out=$(CATALOG=astra run --harness "$harness" doctor --json 2>/dev/null)
  actual=$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["captain"]["selected_model"])' 2>/dev/null)
  expected=openai-codex/gpt-6-astra
  [ "$harness" != pi ] || expected=openai-codex/gpt-6.1-sol
  check "doctor uses the same $harness candidate detector as launch" "$expected" "$actual"
done
out=$(PI_GROK=listed run doctor --json 2>/dev/null)
actual=$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin)["captain"]; print(d["harness"], d["selected_model"])' 2>/dev/null)
check 'doctor reports the same default Pi Captain and Grok selection as launch' 'pi xai/grok-4.7' "$actual"
out=$(run version --json 2>/dev/null)
actual=$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["captain_harness"])' 2>/dev/null)
check 'version reports the same default Pi Captain as launch' pi "$actual"

# --model codex|claude|grok: one-launch Captain model presets, verified as a full
# model+effort pair through the selected harness's own availability owner.
# Anything short of AVAILABLE, and any other value, warns and restores the
# same harness's exact default command (model AND effort).
has() { case $2 in *"$3"*) check "$1" yes yes ;; *) check "$1" "output containing '$3'" "$2" ;; esac; }
lacks() { case $2 in *"$3"*) check "$1" "no '$3'" "$2" ;; *) check "$1" yes yes ;; esac; }

preset() { # label expected-command fm-args...
  local label=$1 expected=$2 out
  shift 2
  out=$(run "$@" --print-command 2>&1)
  check "$label" "$expected" "$(field "$out" COMMAND)"
  lacks "$label is accepted without a warning" "$out" 'fm: warning'
}
CATALOG=full preset 'claude on OMP selects Sonnet 5.5 at high' "$OMP_CLAUDE" --harness omp --model claude
CATALOG=full preset '--model claude --harness omp selects the same command' "$OMP_CLAUDE" --model claude --harness omp
CATALOG=full preset 'codex on OMP selects Sol 6.1 at medium' "$OMP_DEFAULT" --model codex --harness omp
PI_ANTHROPIC=configured preset 'claude on the default Pi Captain selects exact Sonnet 5.5 at high' "$PI_SONNET55" --model claude
PI_ANTHROPIC=configured preset '--model claude --harness pi selects the same command' "$PI_SONNET55" --model claude --harness pi
PI_ANTHROPIC=configured preset '--harness pi --model claude selects the same command' "$PI_SONNET55" --harness pi --model claude
preset 'codex on the default Pi Captain selects Sol 6.1 at medium' "$PI_DEFAULT" --model codex
preset '--model codex --harness pi selects the same command' "$PI_DEFAULT" --model codex --harness pi
GROK=available preset 'grok on OMP selects Grok 4.7 at high' "$OMP_GROK" --model grok --harness omp
GROK=available preset '--harness omp --model grok selects the same command' "$OMP_GROK" --harness omp --model grok
PI_GROK=listed preset 'grok on the default Pi Captain selects Grok 4.7 at high' "$PI_GROK_CMD" --model grok
PI_GROK=listed preset '--model grok --harness pi selects the same command' "$PI_GROK_CMD" --model grok --harness pi
GROK=available preset 'codex overrides the OMP Grok preference for one launch' "$OMP_DEFAULT" --harness omp --model codex
GROK=available CATALOG=full preset 'claude overrides the OMP Grok preference for one launch' "$OMP_CLAUDE" --harness omp --model claude
PI_GROK=listed preset 'codex overrides the default Pi Grok for one launch' "$PI_DEFAULT" --model codex
PI_GROK=listed PI_ANTHROPIC=configured preset 'claude overrides the default Pi Grok for one launch' "$PI_SONNET55" --model claude

fallback() { # label expected-command fm-args...
  local label=$1 expected=$2 out
  shift 2
  out=$(run "$@" --print-command 2>&1)
  check "$label restores the exact default command" "$expected" "$(field "$out" COMMAND)"
  has "$label warns plainly" "$out" 'fm: warning: requested model'
}
fallback 'claude absent from the OMP catalog' "$OMP_DEFAULT" --harness omp --model claude
CATALOG=full SONNET_EFFORT=medium fallback 'claude without high effort on OMP' "$OMP_DEFAULT" --harness omp --model claude
CATALOG=full SOL_EFFORT=low fallback 'codex without medium effort keeps the default chain precedence' "$FM_OMP_BIN --model anthropic/claude-sonnet-5-5 --thinking high" --harness omp --model codex
fallback 'claude without Pi Anthropic credentials on the default Pi Captain' "$PI_DEFAULT" --model claude
fallback 'claude without Pi Anthropic credentials' "$PI_DEFAULT" --harness pi --model claude
PI_CLAUDE=installed fallback 'claude never treats the unversioned Pi sonnet alias as Sonnet 5.5' "$PI_DEFAULT" --harness pi --model claude
PI_ANTHROPIC=configured PI_SONNET_THINKING=no fallback 'claude without Pi thinking support' "$PI_DEFAULT" --harness pi --model claude
fallback 'grok absent from the OMP catalog' "$OMP_DEFAULT" --harness omp --model grok
GROK=available GROK_EFFORT=medium fallback 'grok without high effort on OMP' "$OMP_DEFAULT" --harness omp --model grok
fallback 'grok absent from the default Pi Captain' "$PI_DEFAULT" --model grok
fallback 'unknown preset' "$PI_DEFAULT" --model gpt-6-astra
fallback 'raw model id on OMP' "$OMP_DEFAULT" --harness omp --model openai-codex/gpt-6-astra
fallback 'raw model id on Pi' "$PI_DEFAULT" --harness pi --model openai-codex/gpt-6-astra
CATALOG=full fallback 'preset names are exact' "$OMP_DEFAULT" --harness omp --model Claude
fallback 'shell metacharacters' "$PI_DEFAULT" --model "\$(touch $TMP/pwned);\`touch $TMP/pwned\`"
check 'shell metacharacters in --model are never evaluated' absent "$([ -e "$TMP/pwned" ] && echo present || echo absent)"
out=$(CATALOG=failed run --harness omp --model claude --print-command 2>&1)
check 'unreachable OMP catalog restores the default chain head, still eligible as UNKNOWN' "$OMP_GROK" "$(field "$out" COMMAND)"
has 'unreachable OMP catalog is reported as unverified' "$out" 'could not be verified'
out=$(PI_AUTH=unknown run --harness pi --model codex --print-command 2>&1)
check 'unverifiable Pi auth restores the default command' "$PI_DEFAULT" "$(field "$out" COMMAND)"
has 'unverifiable Pi auth is reported as unverified' "$out" 'could not be verified'

out=$(PI_LIST=failed run --harness pi --model codex 2>&1); rc=$?
check 'a failing Pi default chain still refuses launch after --model fallback' 1 "$rc"
has 'the default-chain blocker stays visible' "$out" 'no configured captain startup model is available'
out=$(FM_OMP_BIN="$TMP/missing-omp" run --harness omp --model claude 2>&1); rc=$?
check 'a missing harness executable is still a blocker with --model' 1 "$rc"
has 'the missing executable stays visible' "$out" 'is not on PATH'

out=$(CATALOG=full run --harness omp --model claude 2>&1)
check 'real OMP launch receives the claude preset model and effort' '--model anthropic/claude-sonnet-5-5 --thinking high' "$(field "$out" EXEC_ARGS)"
out=$(PI_ANTHROPIC=configured run --model claude --harness pi 2>&1)
check 'real Pi launch receives the claude preset model and effort' "--model anthropic/claude-sonnet-5-5 --thinking high $PI_EXTS" "$(field "$out" EXEC_ARGS)"
out=$(GROK=available run --harness omp 2>&1)
check 'real explicit OMP launch receives Grok 4.7 at high' '--model xai/grok-4.7 --thinking high' "$(field "$out" EXEC_ARGS)"
out=$(GROK=available run --harness omp --model codex 2>&1)
check 'real OMP launch with codex overrides the Grok preference' '--model openai-codex/gpt-6.1-sol --thinking medium' "$(field "$out" EXEC_ARGS)"
out=$(PI_GROK=listed run --model codex 2>&1)
check 'real default Pi launch with codex overrides the Grok default' "--model openai-codex/gpt-6.1-sol --thinking medium $PI_EXTS" "$(field "$out" EXEC_ARGS)"
out=$(run --harness omp --model claude 2>&1)
check 'real fallback launch execs OMP once with the default flags' '--model openai-codex/gpt-6.1-sol --thinking medium' "$(field "$out" EXEC_ARGS)"

usage_error() { # label fm-args...
  local label=$1 out rc
  shift
  out=$(run "$@" 2>&1); rc=$?
  check "$label is an argument error" 1 "$rc"
  check "$label never launches" '' "$(field "$out" EXEC_HARNESS)"
}
usage_error 'missing --model value' --model
usage_error 'empty --model value' --model ''
usage_error 'flag in place of --model value' --model --check
usage_error 'missing --model value after --harness' --harness pi --model
usage_error 'repeated --model' --model claude --model codex
usage_error '--model before doctor' --model claude doctor
usage_error '--model before --' --model claude --
usage_error '--model before an unknown flag' --model claude --bogus
check 'no --model run wrote account or user configuration' '' "$(find "$HOME" "$FM_HOME/config" -type f 2>/dev/null)"
printf '\nCAPTAIN HARNESS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
