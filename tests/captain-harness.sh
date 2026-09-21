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
    esac
    printf '{"models":['
    if [ "${CATALOG:-normal}" != astra ] && [ "${CATALOG:-normal}" != sonnet ]; then
      printf '{"provider":"openai-codex","id":"gpt-5.6-sol","selector":"openai-codex/gpt-5.6-sol","reasoning":true,"thinking":["%s"]},' "${SOL_EFFORT:-high}"
    fi
    if [ "${CATALOG:-normal}" = sonnet ]; then
      printf '{"provider":"anthropic","id":"claude-sonnet-5","selector":"anthropic/claude-sonnet-5","reasoning":true,"thinking":["high","xhigh"]},'
    fi
    printf '{"provider":"openai-codex","id":"gpt-6-astra","selector":"openai-codex/gpt-6-astra","reasoning":true,"thinking":["xhigh"]}]}\n'
    exit ;;
esac
printf 'EXEC_HARNESS=omp\nEXEC_CWD=%s\nEXEC_HOME=%s\nEXEC_BACKEND=%s\nEXEC_ORIGIN=%s\n' "$PWD" "$FM_HOME" "$FM_BACKEND" "$FM_FORK_ORIGIN_CWD"
printf 'EXEC_FOREIGN=%s%s%s\n' "${CLAUDECODE-}" "${PI_CODING_AGENT-}" "${FM_PI_HARNESS-}"
printf 'EXEC_OMP_MARKER=%s\nEXEC_TIMEOUT=%s\n' "${FM_OMP_HARNESS-}" "${FM_TIMEOUT_MECHANISM_OVERRIDE-}"
printf 'EXEC_ARGS=%s\n' "$*"
SH
cat > "$TMP/bin/pi" <<'SH'
#!/usr/bin/env bash
case ${1:-} in
  --version) echo 'pi 0.85.1' ;;
  --list-models) printf 'openai-codex gpt-5.6-sol 1K 1K yes no\n' ;;
  auth) printf '{"status":"ready"}\n' ;;
  list) echo 'No packages installed.' ;;
  *)
    printf 'EXEC_HARNESS=pi\n'
    printf 'EXEC_OMP_MARKER=%s\nEXEC_TIMEOUT=%s\n' "${FM_OMP_HARNESS-}" "${FM_TIMEOUT_MECHANISM_OVERRIDE-}"
    ;;
esac
SH
cat > "$TMP/bin/herdr" <<'SH'
#!/usr/bin/env bash
case ${1:-} in
  --version) echo 'herdr 0.8.0' ;;
  status) echo '{"server":{"running":true,"compatible":true}}' ;;
esac
SH
chmod +x "$TMP/bin/omp" "$TMP/bin/pi" "$TMP/bin/herdr"
export PATH="$TMP/bin:$PATH" HOME="$TMP/home" FM_CONFIG_ENV="$TMP/absent"
export FIRSTMATE_ROOT="$TMP/official" FM_HOME="$TMP/fleet" FM_BACKEND=herdr
export FM_PI_BIN="$TMP/bin/pi" FM_OMP_BIN="$TMP/bin/omp" FM_PI_EXTENSIONS=explicit
failed=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s (expected %s, got %s)\n' "$1" "$2" "$3"; failed=1; fi; }
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }
run() { (cd "$TMP/origin" && "$ROOT/bin/fm" "$@"); }
out=$(run --print-command 2>&1)
check 'default invokes OMP without explicit extensions or overlay' "$FM_OMP_BIN --model openai-codex/gpt-5.6-sol --thinking high" "$(field "$out" COMMAND)"
check 'default Captain cwd is official, not origin' "$FIRSTMATE_ROOT" "$(field "$out" CAPTAIN_CWD)"
out=$(run --harness omp --print-command 2>&1)
check 'explicit OMP uses native command' "$FM_OMP_BIN --model openai-codex/gpt-5.6-sol --thinking high" "$(field "$out" COMMAND)"
out=$(run --harness pi --print-command 2>&1)
check 'explicit Pi preserves trust-free extensions' "$FM_PI_BIN --model openai-codex/gpt-5.6-sol --thinking high -e $FIRSTMATE_ROOT/.pi/extensions/fm-primary-turnend-guard.ts -e $FIRSTMATE_ROOT/.pi/extensions/fm-primary-pi-watch.ts" "$(field "$out" COMMAND)"
out=$(CATALOG=astra run --print-command 2>&1)
check 'OMP skips absent Sol and the Pi-only Sonnet candidate without inventing replacement' openai-codex/gpt-6-astra "$(field "$out" SELECTED_MODEL)"
check 'Astra effort is not downgraded' xhigh "$(field "$out" SELECTED_EFFORT)"
out=$(CATALOG=sonnet run --print-command 2>&1)
check 'OMP falls back to its own native Claude Sonnet candidate, never the Pi-only provider id' anthropic/claude-sonnet-5 "$(field "$out" SELECTED_MODEL)"
check 'OMP native Sonnet fallback keeps high effort' high "$(field "$out" SELECTED_EFFORT)"
out=$(SOL_EFFORT=low run --print-command 2>&1)
check 'unsupported exact effort skips candidate' openai-codex/gpt-6-astra "$(field "$out" SELECTED_MODEL)"
for kind in broken failed invalid_schema; do
  out=$(CATALOG=$kind run --check 2>&1)
  check "$kind catalog is UNKNOWN rather than false unavailability" UNKNOWN "$(field "$out" SELECTED_AVAILABILITY)"
done
if CATALOG=empty run --check >/dev/null 2>&1; then check 'empty native catalog refuses launch' failure success; else check 'empty native catalog refuses launch' failure failure; fi
if run --harness invalid --check >/dev/null 2>&1; then check 'unknown harness refuses launch' failure success; else check 'unknown harness refuses launch' failure failure; fi
out=$(CLAUDECODE=1 PI_CODING_AGENT=1 FM_PI_HARNESS=pi FM_OMP_HARNESS=foreign FM_TIMEOUT_MECHANISM_OVERRIDE=external run 2>&1)
check 'real launch crosses directly into OMP' omp "$(field "$out" EXEC_HARNESS)"
check 'real launch runs at official cwd' "$FIRSTMATE_ROOT" "$(field "$out" EXEC_CWD)"
check 'real launch preserves operational home' "$FM_HOME" "$(field "$out" EXEC_HOME)"
check 'real launch preserves Herdr' herdr "$(field "$out" EXEC_BACKEND)"
check 'real launch preserves origin hint' "$TMP/origin" "$(field "$out" EXEC_ORIGIN)"
check 'foreign Captain identity is scrubbed' '' "$(field "$out" EXEC_FOREIGN)"
check 'OMP establishes its own identity after scrubbing' omp "$(field "$out" EXEC_OMP_MARKER)"
check 'OMP selects stock timeout topology within ancestry bound' bash "$(field "$out" EXEC_TIMEOUT)"
out=$(FM_OMP_HARNESS=omp FM_TIMEOUT_MECHANISM_OVERRIDE= run --harness pi 2>&1)
check 'Pi fallback does not inherit OMP identity' '' "$(field "$out" EXEC_OMP_MARKER)"
check 'Pi fallback does not force OMP timeout topology' '' "$(field "$out" EXEC_TIMEOUT)"
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
  [ "$harness" != pi ] || expected=openai-codex/gpt-5.6-sol
  check "doctor uses the same $harness candidate detector as launch" "$expected" "$actual"
done
printf '\nCAPTAIN HARNESS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
