# shellcheck shell=bash
# fm-captain-lib.sh - the one authoritative Captain model availability path.
#
# Shared by bin/fm (captain startup model selection) and bin/fm-doctor
# (read-only availability reporting), so the two never carry forked
# eligibility semantics. Every probe here is read-only and non-billable: no
# function in this file ever starts a paid model turn merely to check
# availability.
#
# Callers set PI_BIN before sourcing/calling (bin/fm and bin/fm-doctor both
# default it to "${FM_PI_BIN:-pi}"). PI_CLAUDE_CODE_PROVIDER_PATH is optional
# and defaults to "claude" internally.
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
