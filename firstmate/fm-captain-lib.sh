# shellcheck shell=bash
# fm-captain-lib.sh - shared Captain harness and model availability owner.
#
# Sourced by bin/fm, bin/fm-doctor, and bin/fm-version. Harness selection never
# changes worker routing. Availability probes are non-billable; only a known
# UNAVAILABLE candidate is skipped. Callers set FIRSTMATE_ROOT before init.
#
# model_availability <model> <effort> prints "STATE<TAB>reason" where STATE is
# AVAILABLE, UNAVAILABLE, or UNKNOWN. AVAILABLE and UNKNOWN remain eligible
# candidates; only an authoritative UNAVAILABLE is skipped. For
# pi-claude-code-provider, Pi's own `auth check` does not load extension
# providers and reports invalid_state even when the provider is perfectly
# usable, so this deliberately bypasses the broker and uses the provider's own
# zero-inference `claude auth status` preflight instead - the corrected
# semantics documented in README.md "Captain startup model". Do not add a
# second detector or a paid probe for this provider.

captain_harness_init() { # [omp|pi]; defaults only here
  CAPTAIN_HARNESS=${1:-omp}
  case $CAPTAIN_HARNESS in
    omp)
      CAPTAIN_BIN=${FM_OMP_BIN:-omp}
      CAPTAIN_WATCH_EXT="$FIRSTMATE_ROOT/.omp/extensions/fm-primary-omp-watch.ts"
      CAPTAIN_TURNEND_EXT="$FIRSTMATE_ROOT/.omp/extensions/fm-primary-turnend-guard.ts"
      ;;
    pi)
      CAPTAIN_BIN=${FM_PI_BIN:-pi}
      CAPTAIN_WATCH_EXT="$FIRSTMATE_ROOT/.pi/extensions/fm-primary-pi-watch.ts"
      CAPTAIN_TURNEND_EXT="$FIRSTMATE_ROOT/.pi/extensions/fm-primary-turnend-guard.ts"
      ;;
    *) printf 'fm: unsupported Captain harness %s (expected omp or pi)\n' "$CAPTAIN_HARNESS" >&2; return 1 ;;
  esac
}

captain_model_availability() {
  case $CAPTAIN_HARNESS in
    omp) omp_model_availability "$@" ;;
    pi) model_availability "$@" ;;
  esac
}

# Native OMP's listing uses getAvailable(): resolvable credentials or keyless
# auth, not a live auth/quota guarantee. Never use Pi's broker for OMP.
# Disable factories for this read-only probe: FirstMate extension factories
# write load markers even in `omp models`. Actual launches use discovery.
# An optional effort checks the exact supported list rather than OMP's clamp.
omp_model_availability() { # <model> [effort]
  local model=$1 effort=${2:-} out result
  command -v "${FM_OMP_BIN:-omp}" >/dev/null 2>&1 \
    || { printf 'UNAVAILABLE\tomp executable not on PATH'; return; }
  out=$(cd "$FIRSTMATE_ROOT" && "${FM_OMP_BIN:-omp}" models --json --no-extensions 2>/dev/null) \
    || { printf 'UNKNOWN\tomp native catalog unavailable'; return; }
  if command -v jq >/dev/null 2>&1; then
    result=$(printf '%s' "$out" | jq -er --arg m "$model" --arg e "$effort" '
      if (.models | type) != "array" or
        (all(.models[]; (.provider | type) == "string" and (.id | type) == "string") | not)
      then error("invalid catalog") else
        [.models[] | select((.provider + "/" + .id) == $m)] as $matches |
        if ($matches | length) == 0 then "missing"
        elif ($matches | length) != 1 then error("ambiguous catalog")
        elif $e == "" then "available"
        elif $matches[0].thinking == null then
          if $e == "off" and $matches[0].reasoning == false then "available" else "effort" end
        elif ($matches[0].thinking | type) != "array" then error("invalid efforts")
        elif ($matches[0].thinking | index($e)) != null then "available"
        else "effort" end
      end' 2>/dev/null) || result=unknown
  elif command -v python3 >/dev/null 2>&1; then
    result=$(printf '%s' "$out" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert isinstance(doc["models"], list)
matches = [m for m in doc["models"] if m["provider"] + "/" + m["id"] == sys.argv[1]]
assert len(matches) <= 1
effort = sys.argv[2]
if not matches:
    print("missing")
elif not effort:
    print("available")
else:
    m = matches[0]
    thinking = m.get("thinking")
    assert thinking is None or isinstance(thinking, list)
    print("available" if (effort in thinking if thinking is not None else effort == "off" and m.get("reasoning") is False) else "effort")
' "$model" "$effort" 2>/dev/null) || result=unknown
  else
    result=unknown
  fi
  case $result in
    available) printf 'AVAILABLE\tresolvable native OMP auth; live validity and quota unprobed' ;;
    missing) printf 'UNAVAILABLE\tmodel not in native OMP available catalog (unsupported or credentials unavailable)' ;;
    effort) printf 'UNAVAILABLE\tunsupported configured effort %s' "$effort" ;;
    *) printf 'UNKNOWN\tomp native catalog could not be parsed' ;;
  esac
}

model_provider() { printf '%s' "${1%%/*}"; }
model_name() { printf '%s' "${1#*/}"; }

json_string_field() { # <json> <field>
  printf '%s' "$1" | tr '\n' ' ' | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

json_bool_field() { # <json> <field>
  printf '%s' "$1" | tr '\n' ' ' | sed -E -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*(true|false).*/\1/p" | head -1
}

json_number_field() { # <json> <field>
  printf '%s' "$1" | tr '\n' ' ' | sed -E -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*(-?[0-9]+).*/\1/p" | head -1
}

broker_auth_availability() { # <model> ; prints STATE<TAB>reason
  local model=$1 out status reason
  out=$("${PI_BIN:-pi}" auth check --model "$model" --json --no-refresh 2>&1) || true
  status=$(json_string_field "$out" status)
  reason=$(json_string_field "$out" reason)
  case $status in
    ready) printf 'AVAILABLE\t' ;;
    not_ready|missing)
      case $reason in
        provider_not_found|credentials_not_configured|credential_not_available|missing_auth)
          printf 'UNAVAILABLE\t%s' "$reason"
          ;;
        *) printf 'UNKNOWN\t%s' "${reason:-authentication status unknown}" ;;
      esac
      ;;
    *) printf 'UNKNOWN\t%s' "${reason:-${status:-authentication status unknown}}" ;;
  esac
}

claude_provider_installed() {
  local out
  out=$("${PI_BIN:-pi}" list 2>/dev/null) || return 1
  printf '%s\n' "$out" | grep -Eq '(^|[/@:])pi-claude-code-provider([[:space:]]|$)'
}

claude_provider_auth_availability() { # prints STATE<TAB>reason
  local claude_bin out logged_in auth_method api_provider subscription
  if ! claude_provider_installed; then
    printf 'UNAVAILABLE\tprovider package not installed'
    return
  fi
  claude_bin=${PI_CLAUDE_CODE_PROVIDER_PATH:-claude}
  if ! command -v "$claude_bin" >/dev/null 2>&1; then
    printf 'UNAVAILABLE\tClaude Code executable unavailable'
    return
  fi
  out=$("$claude_bin" auth status 2>&1) || true
  logged_in=$(json_bool_field "$out" loggedIn)
  auth_method=$(json_string_field "$out" authMethod)
  api_provider=$(json_string_field "$out" apiProvider)
  subscription=$(json_string_field "$out" subscriptionType)
  if [ "$logged_in" = false ]; then
    printf 'UNAVAILABLE\tClaude Code is not logged in'
  elif [ "$logged_in" = true ] && [ "$auth_method" = claude.ai ] && [ "$api_provider" = firstParty ]; then
    case $subscription in
      pro|max|team|enterprise) printf 'AVAILABLE\t' ;;
      '') printf 'UNKNOWN\tClaude Code subscription status unknown' ;;
      *) printf 'UNAVAILABLE\tunsupported Claude subscription type %s' "$subscription" ;;
    esac
  elif [ "$logged_in" = true ] && { [ -n "$auth_method" ] || [ -n "$api_provider" ]; }; then
    printf 'UNAVAILABLE\tClaude Code requires a first-party claude.ai subscription'
  else
    printf 'UNKNOWN\tClaude Code authentication status unknown'
  fi
}

model_availability() { # <model> <effort> ; prints STATE<TAB>reason
  local model=$1 effort=$2 out thinking
  case $effort in
    off|minimal|low|medium|high|xhigh|max) ;;
    *) printf 'UNAVAILABLE\tunsupported configured effort %s' "$effort"; return ;;
  esac
  out=$("${PI_BIN:-pi}" --list-models "$model" 2>/dev/null) || { printf 'UNAVAILABLE\tmodel/provider unavailable'; return; }
  thinking=$(printf '%s\n' "$out" | awk -v p="$(model_provider "$model")" -v m="$(model_name "$model")" '$1 == p && $2 == m {print $5; exit}')
  if [ -z "$thinking" ]; then
    printf 'UNAVAILABLE\tmodel/provider unavailable'
    return
  fi
  if [ "$effort" != off ] && [ "$thinking" != yes ]; then
    printf 'UNAVAILABLE\tunsupported configured effort %s' "$effort"
    return
  fi
  case $(model_provider "$model") in
    pi-claude-code-provider) claude_provider_auth_availability ;;
    *) broker_auth_availability "$model" ;;
  esac
}
