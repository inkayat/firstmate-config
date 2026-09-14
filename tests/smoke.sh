#!/usr/bin/env bash
# smoke.sh - acceptance for this configuration.
#
# Two halves. The static half always runs and needs nothing live: launcher
# resolution from a non-repository directory, from a disposable Git
# repository, and from the checkout itself, plus installer idempotency. The
# live half runs only when a captain currently holds the session lock, and
# answers every question with upstream's own predicate rather than a private
# reimplementation - a fork-local copy of "is the watcher fresh" would drift
# from the definition the watcher itself uses.
#
# Usage:
#   tests/smoke.sh          static checks, plus live checks if a captain is up
#   tests/smoke.sh --live   require a live captain; fail if there is none
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${FM_CONFIG_ENV:-$HOME/.config/firstmate-config/env}"
# shellcheck source=/dev/null
[ ! -f "$ENV_FILE" ] || . "$ENV_FILE"
FIRSTMATE_ROOT="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"
FM_HOME="${FM_HOME:-$HOME/.firstmate}"
STATE="$FM_HOME/state"
GRACE="${FM_GUARD_GRACE:-300}"
FM="$CONFIG_ROOT/bin/fm"

REQUIRE_LIVE=0
[ "${1:-}" != --live ] || REQUIRE_LIVE=1

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { # <description> <expected> <actual>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-smoke.XXXXXX") || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT

# --- static: launcher resolution -------------------------------------------
plain="$TMP_ROOT/plain-directory"
repo="$TMP_ROOT/disposable-repo"
mkdir -p "$plain" "$repo"
# Normalise: TMPDIR often ends in a slash, and the launcher reports $PWD.
plain=$(cd "$plain" && pwd)
repo=$(cd "$repo" && pwd)
( cd "$repo" && git init -q && printf 'smoke\n' > README.md && git add -A \
  && git -c user.email=smoke@example.invalid -c user.name=smoke commit -qm init ) || exit 1

for origin in "$plain" "$repo" "$FIRSTMATE_ROOT"; do
  out=$(cd "$origin" && "$FM" --print-command 2>&1) || { fail "fm --print-command failed in $origin: $out"; continue; }
  label=$(basename "$origin")
  check "[$label] launcher resolves the official checkout" "$FIRSTMATE_ROOT" "$(field "$out" FIRSTMATE_ROOT)"
  check "[$label] launcher resolves the machine-local home" "$FM_HOME" "$(field "$out" FM_HOME)"
  check "[$label] launcher selects the herdr backend" herdr "$(field "$out" FM_BACKEND)"
  check "[$label] Pi runs in the checkout so AGENTS.md loads" "$FIRSTMATE_ROOT" "$(field "$out" PI_CWD)"
  check "[$label] the invoking directory is carried through" "$origin" "$(field "$out" FM_FORK_ORIGIN_CWD)"
  case "$(field "$out" COMMAND)" in
    *fm-primary-turnend-guard.ts*fm-primary-pi-watch.ts*)
      pass "[$label] both Pi primary extensions are named explicitly" ;;
    pi) pass "[$label] extensions come from Pi's own discovery (checkout is trusted)" ;;
    *) fail "[$label] neither explicit -e nor trusted discovery: $(field "$out" COMMAND)" ;;
  esac
done

# The shell that ran fm must still be where it started.
before=$PWD
( cd "$plain" && "$FM" --check >/dev/null 2>&1 )
check 'the calling shell keeps its working directory' "$before" "$PWD"

# A project the launcher was pointed at must be untouched by any of this.
check 'the disposable repository is unmodified' '' "$(cd "$repo" && git status --porcelain)"

# --- static: installed state ------------------------------------------------
if [ -L "$FM_HOME/config/crew-dispatch.json" ]; then
  pass 'crew-dispatch.json is linked into the home'
else
  fail 'crew-dispatch.json is not linked into the home'
fi
if [ "$(tr -d '[:space:]' < "$FM_HOME/config/backend" 2>/dev/null)" = herdr ]; then
  pass 'config/backend selects herdr'
else
  fail 'config/backend does not select herdr'
fi
if [ -f "$FM_HOME/data/captain.md" ]; then
  pass 'the captain file exists in the home'
else
  fail 'the captain file is missing from the home'
fi
if [ -z "$(cd "$FIRSTMATE_ROOT" && git status --porcelain)" ]; then
  pass 'the official checkout has no modifications'
else
  fail 'the official checkout has been modified'
fi

missing_skills=
while IFS="$(printf '\t')" read -r id _repo _sha _path name; do
  case ${id:-} in ''|\#*) continue ;; esac
  [ -n "${name:-}" ] || continue
  [ -f "$HOME/.agents/skills/$name/SKILL.md" ] || missing_skills="$missing_skills $id"
done < "$CONFIG_ROOT/skills/external.lock"
for own in "$CONFIG_ROOT"/skills/*/; do
  [ -f "$own/SKILL.md" ] || continue
  name=$(basename "$own")
  [ -f "$HOME/.agents/skills/$name/SKILL.md" ] || missing_skills="$missing_skills $name"
done
check 'every configured global skill is installed' '' "$missing_skills"

drift=$("$CONFIG_ROOT/install.sh" --verify 2>&1 | tail -1)
case $drift in
  *'0 drift item(s), 0 failure(s)') pass 'install.sh reports no drift, so a rerun changes nothing' ;;
  *) fail "install.sh reports drift: $drift" ;;
esac

# --- live: a captain currently holding the lock -----------------------------
lock_line=$("$FIRSTMATE_ROOT/bin/fm-lock.sh" status 2>&1 | tail -1)
case $lock_line in
  *'held by live harness pid'*) live=1 ;;
  *) live=0 ;;
esac

if [ "$live" -eq 0 ]; then
  if [ "$REQUIRE_LIVE" -eq 1 ]; then
    fail "no live captain holds the session lock ($lock_line)"
  else
    printf 'skip - live captain checks: %s\n' "$lock_line"
  fi
else
  pass "fleet lock: $lock_line"
  # shellcheck source=/dev/null
  . "$FIRSTMATE_ROOT/bin/fm-wake-lib.sh"
  # shellcheck source=/dev/null
  . "$FIRSTMATE_ROOT/bin/fm-supervision-lib.sh"

  if fm_pi_extension_owns_supervision "$STATE" "$FIRSTMATE_ROOT"; then
    pass 'both Pi primary extensions are loaded at their on-disk build by the lock holder'
  else
    fail 'fm_pi_extension_owns_supervision is false for this home'
  fi

  fm_supervision_status "$STATE" "$GRACE"
  if [ "${FM_SUP_WATCHER_FRESH:-false}" = true ]; then
    pass "watcher: live with a fresh beacon (grace ${GRACE}s)"
  else
    fail "watcher: no live watcher with a fresh beacon (last beat: ${FM_SUP_BEACON_DESC:-never})"
  fi
  if [ "${FM_SUP_QUEUE_PENDING:-false}" = false ]; then
    pass 'wake queue: nothing unconsumed'
  else
    fail 'wake queue: rows are pending and unconsumed'
  fi

  if [ -f "$STATE/.last-watcher-beat" ]; then
    now=$(date +%s)
    mtime=$(stat -f %m "$STATE/.last-watcher-beat" 2>/dev/null || stat -c %Y "$STATE/.last-watcher-beat" 2>/dev/null || printf 0)
    age=$((now - mtime))
    if [ "$age" -le "$GRACE" ]; then
      pass "heartbeat: beacon ${age}s old"
    else
      fail "heartbeat: beacon ${age}s old, past the ${GRACE}s grace"
    fi
  else
    fail 'heartbeat: no beacon file'
  fi

  # The launcher records what it actually resolved; the pid ties that record
  # to the process holding the lock.
  rec="$STATE/.fm-launch"
  if [ -f "$rec" ]; then
    lock_pid=$(sed -n '1p' "$STATE/.lock")
    check 'the launch record belongs to the lock holder' "$lock_pid" "$(sed -n 's/^pid=//p' "$rec")"
    check 'the live captain was launched with the herdr backend' herdr "$(sed -n 's/^fm_backend=//p' "$rec")"
    check 'the live captain uses the official checkout' "$FIRSTMATE_ROOT" "$(sed -n 's/^firstmate_root=//p' "$rec")"
    origin=$(sed -n 's/^origin_cwd=//p' "$rec")
    if [ -n "$origin" ]; then
      pass "the live captain knows where it was launched from: $origin"
    else
      fail 'the live captain has no recorded origin directory'
    fi
  else
    fail 'no launch record; this captain was not started by fm'
  fi
fi

if command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  hs=$(herdr status --json 2>/dev/null || printf '')
  if [ "$(printf '%s' "$hs" | jq -r '.server.running // false')" = true ]; then
    pass "herdr: server running, client $(printf '%s' "$hs" | jq -r '.client.version // "?"')"
  else
    fail 'herdr: server is not running'
  fi
else
  fail 'herdr or jq is missing'
fi

printf '\nSMOKE %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
