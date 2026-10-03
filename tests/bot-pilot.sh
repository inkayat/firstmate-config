#!/usr/bin/env bash
# bot-pilot.sh - the P8 bot pilot, simulated end to end in a disposable lab.
#
# What is real: bin/fm-bot from a disposable copy of this checkout, the
# official watcher check registration and its trust-verified snapshot run
# (exactly how fm-watch.sh executes a custom check), the official backlog
# (fm-tasks-axi.sh) in a disposable FM_HOME made by bin/fm-lab-home.sh, the
# `fm bot file` dispatch seam, and real `omp` workers running in panes of an
# isolated, non-default Herdr lab session that only bin/fm-herdr-lab.sh
# provisions, drives, and tears down.
#
# What is simulated, and therefore NOT proven here:
#   - days: the clock is pinned with --now, sweeping every 5 minutes across
#     each local day; no real day elapses and no real fm-watch.sh loop runs;
#   - Firstmate itself: this script plays its part for each wake (run
#     `fm bot file`, compose a brief from the printed plan, mark the task done
#     or held); no Captain session and no fm-spawn/treehouse/supervision is
#     involved, and each worker runs in a disposable clone instead of a
#     dispatched worktree;
#   - authorization: the local-commit bot's authorization field is an
#     explicit FIXTURE-ONLY placeholder, never captain words, and no
#     per-commit captain approval is ever given, so the approve-then-commit
#     step is never exercised; it proves nothing about a real permission.
#   The refactorist role is the real roles/refactorist/ROLE.md of this
#   checkout, copied unchanged into the disposable config copy.
#
# Plan P8 acceptance this checks:
#   (a) a refactorist local-proposal bot, 08:00-08:59 Europe/Stockholm, over
#       seven mornings (crossing the 2026-10-25 DST change): exactly one due
#       line, one filing, and one dated report per morning; silence at every
#       other sweep, including after the day's task is done and pruned inside
#       the window; no branch, file, or commit change anywhere;
#   (b) a local-commit bot over two due runs: each run changes files only on
#       its dated bot branch within the limits, leaves them uncommitted, ends
#       with needs-decision [key=commit-approval], and is held for the
#       captain; no commit or push exists anywhere afterwards.
#
# Herdr isolation follows the task's --herdr-lab contract: one named
# fm-lab-* session, every Herdr call through the helper, one EXIT trap that
# tears down the session (and the lab home's private tmux dir, unused here),
# and the helper's default-session tripwire must hold.
#
# Opt-in: real, billable model calls and tens of minutes. Without
# FM_LIVE_BOT_PILOT=1 it reports SKIPPED; a missing prerequisite reports
# BLOCKED; never PASS. FM_BOT_PILOT_MODEL overrides the worker model;
# FM_BOT_PILOT_KEEP=1 keeps the evidence directory after a pass.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FMROOT="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"
MODEL="${FM_BOT_PILOT_MODEL:-anthropic/claude-sonnet-5-5}"
HERDR_LAB_HELPER="$FMROOT/bin/fm-herdr-lab.sh"
LAB_HOME_HELPER="$FMROOT/bin/fm-lab-home.sh"
LIVE_HOME="$HOME/.firstmate"

if [ "${FM_LIVE_BOT_PILOT:-}" != 1 ]; then
  printf 'SKIP - bot-pilot.sh: set FM_LIVE_BOT_PILOT=1 to run real omp workers in a Herdr lab (never reported as PASS)\n'
  exit 0
fi
for tool in omp herdr python3 tasks-axi git; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'bot-pilot.sh: BLOCKED (%s not on PATH)\n' "$tool"; exit 2; }
done
for s in fm-herdr-lab.sh fm-lab-home.sh fm-tasks-axi.sh fm-check-register.sh fm-check-lib.sh fm-pr-lib.sh fm-project-mode.sh; do
  [ -f "$FMROOT/bin/$s" ] || { printf 'bot-pilot.sh: BLOCKED (no %s under %s)\n' "$s" "$FMROOT"; exit 2; }
done
OMP_BIN=$(command -v omp)

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$3', got '$2')"; fi; }

live_snapshot() {
  local p
  for p in "$LIVE_HOME/data/bots" "$LIVE_HOME/state/bots.check.sh" "$LIVE_HOME/state/bots.check-trust" \
           "$HOME/.agents/commands/bots.md" "$HOME/.agents/skills/bot-builder"; do
    if [ -e "$p" ] || [ -L "$p" ]; then ls -ldT "$p" 2>/dev/null || ls -ld --full-time "$p"; else printf '%s absent\n' "$p"; fi
  done
}
LIVE_BEFORE=$(live_snapshot)

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-bot-pilot.XXXXXX") || exit 1
TMP_ROOT=$(cd "$TMP_ROOT" && pwd)
HERDR_LAB_SESSION=$("$HERDR_LAB_HELPER" name "${FM_TASK_ID:-bot-pilot}") || exit 1
H=
LAB_PROVISIONED=0
# The single EXIT cleanup the lab contract requires: Herdr teardown through
# the helper (it re-checks refuse-default and verifies the default-session
# tripwire), the lab home's private tmux dir (no tmux server runs here), then
# the evidence directory unless it is kept.
# shellcheck disable=SC2329  # invoked by the EXIT trap
cleanup() {
  local rc=$?
  if [ "$LAB_PROVISIONED" = 1 ]; then
    "$HERDR_LAB_HELPER" teardown "$HERDR_LAB_SESSION" || { printf 'FAIL - herdr lab teardown or tripwire\n' >&2; rc=1; }
  fi
  [ -z "$H" ] || "$LAB_HOME_HELPER" teardown "$H" >/dev/null 2>&1 || true
  if [ "$rc" -ne 0 ] || [ "$failed" -ne 0 ] || [ "${FM_BOT_PILOT_KEEP:-}" = 1 ]; then
    printf 'evidence kept: %s\n' "$TMP_ROOT"
  else
    rm -rf "$TMP_ROOT"
  fi
  exit "$rc"
}
trap cleanup EXIT

# --- disposable config copy (fm-bot validates roles against its own checkout)
CFG="$TMP_ROOT/config"
mkdir -p "$CFG/bin"
cp "$CONFIG_ROOT/bin/fm-bot" "$CFG/bin/fm-bot"
cp -R "$CONFIG_ROOT/firstmate" "$CONFIG_ROOT/roles" "$CFG/"
BOT="$CFG/bin/fm-bot"

# --- lab home and sandbox project -------------------------------------------
H=$("$LAB_HOME_HELPER" create "$TMP_ROOT/home") || { printf 'bot-pilot.sh: BLOCKED (fm-lab-home.sh create failed)\n'; exit 2; }
printf -- '- sandbox [local-only] - disposable bot pilot project (added 2026-10-20)\n' > "$H/data/projects.md"
ORIGIN="$TMP_ROOT/sandbox-origin"
mkdir -p "$ORIGIN/src/shop" "$ORIGIN/tests"
cat > "$ORIGIN/src/shop/__init__.py" <<'EOF'
EOF
cat > "$ORIGIN/src/shop/pricing.py" <<'EOF'
TAX_RATE = 0.25


def price_with_tax(price):
    total = price + price * 0.25
    return float("%.2f" % total)


def discounted_price_with_tax(price, discount):
    reduced = price - price * discount
    total = reduced + reduced * 0.25
    return float("%.2f" % total)


def bundle_price_with_tax(prices):
    subtotal = 0
    for p in prices:
        subtotal = subtotal + p
    total = subtotal + subtotal * 0.25
    return float("%.2f" % total)
EOF
cat > "$ORIGIN/tests/test_pricing.py" <<'EOF'
import unittest

from shop.pricing import bundle_price_with_tax, discounted_price_with_tax, price_with_tax


class PricingTest(unittest.TestCase):
    def test_price_with_tax(self):
        self.assertEqual(price_with_tax(100), 125.0)

    def test_discounted(self):
        self.assertEqual(discounted_price_with_tax(100, 0.1), 112.5)

    def test_bundle(self):
        self.assertEqual(bundle_price_with_tax([10, 20]), 37.5)


if __name__ == "__main__":
    unittest.main()
EOF
printf '# sandbox\n\nTests: PYTHONPATH=src python3 -m unittest discover -s tests\n' > "$ORIGIN/README.md"
git -C "$ORIGIN" init -q -b main
git -C "$ORIGIN" -c user.email=pilot@example.invalid -c user.name=pilot add -A
git -C "$ORIGIN" -c user.email=pilot@example.invalid -c user.name=pilot commit -q -m 'sandbox baseline'
ORIGIN_REFS=$(git -C "$ORIGIN" for-each-ref --format='%(refname) %(objectname)')

run_bot() { HOME="$TMP_ROOT/decoy" FM_HOME="$H" FIRSTMATE_ROOT="$FMROOT" "$BOT" "$@"; }
axi() { HOME="$TMP_ROOT/decoy" FM_HOME="$H" "$FMROOT/bin/fm-tasks-axi.sh" "$@"; }
herdr_lab() { "$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" "$@"; }
mkdir -p "$TMP_ROOT/decoy" "$TMP_ROOT/runs"

run_bot create refactor-am --role refactorist --project sandbox --route 'EXPLORE #2' \
  --at 08:00 --until 08:59 --scope 'src/shop only: propose one or two small behavior-preserving refactors' \
  --wall-clock-min 8 --max-candidates 2 --now 2026-10-20T10:00Z >/dev/null \
  || { printf 'bot-pilot.sh: BLOCKED (cannot create refactor-am)\n'; exit 2; }
run_bot create refactor-commit --role refactorist --project sandbox --route 'IMPLEMENT #1' \
  --at 09:00 --until 09:30 --scope 'src/shop only: apply one small behavior-preserving refactor' \
  --wall-clock-min 8 --level local-commit --max-files 2 --max-lines 40 --exclude tests/ \
  --authorization 'FIXTURE-ONLY placeholder: no captain authorization exists for this pilot bot' \
  --authorization-scope 'disposable pilot sandbox only' --authorized-on 2026-10-01 --expires 2026-12-31 \
  --now 2026-10-20T10:00Z >/dev/null \
  || { printf 'bot-pilot.sh: BLOCKED (cannot create refactor-commit)\n'; exit 2; }
run_bot pause refactor-commit >/dev/null
run_bot check-install >/dev/null || { printf 'bot-pilot.sh: BLOCKED (check-install failed)\n'; exit 2; }

# Official trust-verified snapshot run, as fm-watch.sh runs a custom check.
set +u
# shellcheck source=/dev/null
. "$FMROOT/bin/fm-pr-lib.sh"
# shellcheck source=/dev/null
. "$FMROOT/bin/fm-check-lib.sh"
set -u
sweep() {  # <utc-instant>
  fm_custom_check_snapshot_prepare "$H/state" bots || { echo 'snapshot refused'; return; }
  env -i PATH="$PATH" HOME="$TMP_ROOT/decoy" bash "$FM_CUSTOM_CHECK_SNAPSHOT" --now "$1" 2>/dev/null
  fm_custom_check_snapshot_cleanup
}

"$HERDR_LAB_HELPER" provision "$HERDR_LAB_SESSION" >/dev/null || { printf 'bot-pilot.sh: BLOCKED (herdr lab provision failed)\n'; exit 2; }
LAB_PROVISIONED=1

# One worker in its own lab workspace, on a disposable clone with hooks that
# refuse and log any commit or push. Returns when the worker exits.
dispatch() {  # <plan-json-file>
  local plan=$1 id run repo ws pane deadline
  id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$plan")
  run="$TMP_ROOT/runs/$id"
  repo="$run/repo"
  mkdir -p "$run" "$H/data/$id"
  git clone -q "$ORIGIN" "$repo"
  git -C "$repo" config user.email pilot@example.invalid
  git -C "$repo" config user.name pilot
  for hook in pre-commit pre-push; do
    # shellcheck disable=SC2016  # $(date) is meant to run inside the hook, not here
    printf '#!/bin/sh\necho "%s $(date -u +%%FT%%TZ)" >> %q\nexit 1\n' "$hook" "$run/hook-attempts" > "$repo/.git/hooks/$hook"
    chmod +x "$repo/.git/hooks/$hook"
  done
  python3 - "$plan" "$H" "$run/brief.md" <<'PY'
import json, sys
plan, home, out = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
lines = [
    "You are a bot worker in a FirstMate bot pilot. Work autonomously; nobody will answer questions.",
    f"Task id: {plan['id']} (bot {plan['bot']}, level {plan['level']}, route {plan['route']}).",
    f"Role: read {plan['role_file']} and apply it.",
    "Project: the Git checkout in your current directory. Tests: PYTHONPATH=src python3 -m unittest discover -s tests",
    f"Scope: {plan['scope']}",
    f"Limits: at most {plan['wall_clock_min']} minutes."
    + (f" At most {plan['max_candidates']} candidates." if plan.get("max_candidates") else "")
    + (f" At most {plan['max_files']} files and {plan['max_lines']} changed lines." if plan.get("max_files") else "")
    + (f" Never touch: {', '.join(plan['exclude'])}." if plan.get("exclude") else ""),
    f"Access: {plan['access']}. Never use the network.",
]
if plan["level"] == "local-proposal":
    report = f"{home}/{plan['report']}"
    lines += [f"Stop rule: {plan['stop_rule'].replace(plan['report'], report)}",
              f"When the report is written, append exactly one line to {home}/state/{plan['id']}.status:",
              "done: <one-line summary>"]
else:
    lines += [f"First run: git switch -c {plan['branch']}",
              f"Stop rule: {plan['stop_rule']}",
              f"Append the final line to {home}/state/{plan['id']}.status in exactly this form:",
              "needs-decision [key=commit-approval]: <files changed, test result>"]
open(out, "w").write("\n".join(lines) + "\n")
PY
  cat > "$run/run.sh" <<EOF
#!/usr/bin/env bash
cd $(printf '%q' "$repo") || exit 1
$(printf '%q' "$OMP_BIN") -p --no-session --mode json --model $(printf '%q' "$MODEL") --thinking low \\
  --auto-approve --max-time 12m "\$(cat $(printf '%q' "$run/brief.md"))" > $(printf '%q' "$run/omp.jsonl") 2> $(printf '%q' "$run/omp.err")
echo \$? > $(printf '%q' "$run/exit")
EOF
  ws=$(herdr_lab workspace create --cwd "$repo" --label "$id" --no-focus) || { fail "$id: lab workspace create"; return; }
  pane=$(printf '%s' "$ws" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["root_pane"]["pane_id"])')
  herdr_lab pane run "$pane" bash "$run/run.sh" >/dev/null || { fail "$id: lab pane run"; return; }
  deadline=$(( $(date +%s) + 900 ))
  while [ ! -s "$run/exit" ] && [ "$(date +%s)" -lt "$deadline" ]; do sleep 5; done
  [ -s "$run/exit" ] || fail "$id: worker did not finish within 15 minutes"
  herdr_lab workspace close "$(printf '%s' "$ws" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["workspace"]["workspace_id"])')" >/dev/null 2>&1 || true
}

# All 5-minute sweep instants of one Stockholm local day, in UTC.
day_instants() {  # <YYYY-MM-DD>
  python3 - "$1" <<'PY'
import datetime, sys, zoneinfo
tz, utc = zoneinfo.ZoneInfo("Europe/Stockholm"), datetime.timezone.utc
day = datetime.date.fromisoformat(sys.argv[1])
start = datetime.datetime(day.year, day.month, day.day, tzinfo=tz).astimezone(utc)
end = datetime.datetime.combine(day + datetime.timedelta(days=1), datetime.time(), tzinfo=tz).astimezone(utc)
t = start
while t < end:
    print(t.strftime("%Y-%m-%dT%H:%MZ"), t.astimezone(tz).strftime("%H:%M"))
    t += datetime.timedelta(minutes=5)
PY
}

# Plays Firstmate for one simulated day: every sweep's output is recorded;
# each due line goes through `fm bot file`, then a worker, then the task's
# next backlog state (done + prune for a report, captain hold for a commit).
handle_wake() {  # <day> <local-hm> <utc-instant> <line>
  local day=$1 local_hm=$2 instant=$3 line=$4 id plan_file i
  printf '%s %s %s\n' "$day" "$local_hm" "$line" >> "$TMP_ROOT/wakes.log"
  case $line in 'bot due: '*) ;; *) return ;; esac
  id=${line#bot due: }; id=${id%% *}
  plan_file="$TMP_ROOT/runs/$id.plan.json"
  run_bot file "$id" --json --now "$instant" > "$plan_file" 2>> "$TMP_ROOT/file-errors.log" || return
  printf '%s %s filed %s\n' "$day" "$local_hm" "$id" >> "$TMP_ROOT/filings.log"
  axi start "$id" >/dev/null 2>&1 || true
  dispatch "$plan_file"
  if python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1]))["level"] != "local-proposal")' "$plan_file"; then
    axi "done" "$id" --report "data/$id/report.md" >/dev/null
    for i in 1 2 3 4 5 6 7 8 9 10 11; do axi add "filler-$id-$i" --title filler >/dev/null; axi "done" "filler-$id-$i" >/dev/null; done
  else
    axi hold "$id" --reason 'commit approval pending' --kind captain >/dev/null
  fi
}

simulate_day() {  # <YYYY-MM-DD>
  local day=$1 entry instant local_hm out line
  local -a instants
  mapfile -t instants < <(day_instants "$day")
  for entry in "${instants[@]}"; do
    instant=${entry% *}; local_hm=${entry#* }
    out=$(sweep "$instant")
    [ -n "$out" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] && handle_wake "$day" "$local_hm" "$instant" "$line" < /dev/null
    done <<< "$out"
  done
}

: > "$TMP_ROOT/wakes.log"; : > "$TMP_ROOT/filings.log"
DAYS_A="2026-10-21 2026-10-22 2026-10-23 2026-10-24 2026-10-25 2026-10-26 2026-10-27"
DAYS_B="2026-10-28 2026-10-29"
for d in $DAYS_A; do simulate_day "$d"; done
run_bot pause refactor-am >/dev/null
run_bot resume refactor-commit >/dev/null
for d in $DAYS_B; do simulate_day "$d"; done

# Project changes a worker left, ignoring the bytecode caches a test run
# writes (they are not changes to the project).
project_changes() {  # <repo>
  git -C "$1" status --porcelain --untracked-files=all | grep -v '__pycache__/' || true
}

# The worker read the dispatched role file, and that file is this checkout's
# real refactorist role.
read_real_role() {  # <id>
  python3 - "$TMP_ROOT/runs/$1.plan.json" "$TMP_ROOT/runs/$1/omp.jsonl" "$CONFIG_ROOT/roles/refactorist/ROLE.md" <<'PY'
import json, sys
plan, log, real = sys.argv[1:]
role = json.load(open(plan))["role_file"]
same = open(role, "rb").read() == open(real, "rb").read()
read = any(e.get("type") == "tool_execution_start" and role in json.dumps(e.get("args") or {})
           for e in (json.loads(l) for l in open(log, encoding="utf-8") if l.startswith("{")))
print("yes" if same and read else f"no (same={same} read={read})")
PY
}

# =============================================================================
# (a) seven local-proposal mornings
# =============================================================================
for d in $DAYS_A; do
  id="refactor-am-${d//-/}"
  check "a $d: exactly one wake line all day" "$(grep -c "^$d " "$TMP_ROOT/wakes.log")" 1
  check "a $d: that wake is the 08:00 due line" "$(grep "^$d " "$TMP_ROOT/wakes.log")" \
    "$d 08:00 bot due: $id spec=data/bots/refactor-am.md level=local-proposal"
  check "a $d: filed once at 08:00" "$(grep "^$d " "$TMP_ROOT/filings.log")" "$d 08:00 filed $id"
  if [ -s "$H/data/$id/report.md" ]; then pass "a $d: dated report written"; else fail "a $d: dated report written"; fi
  repo="$TMP_ROOT/runs/$id/repo"
  check "a $d: no branch created" "$(git -C "$repo" for-each-ref --format='%(refname)' refs/heads)" refs/heads/main
  check "a $d: no file changed in the project" "$(project_changes "$repo")" ''
  check "a $d: no commit" "$(git -C "$repo" rev-list --count origin/main..HEAD 2>/dev/null)" 0
  if [ -e "$TMP_ROOT/runs/$id/hook-attempts" ]; then fail "a $d: no commit or push attempted"; else pass "a $d: no commit or push attempted"; fi
  case $(tail -1 "$H/state/$id.status" 2>/dev/null) in done:*) pass "a $d: worker ended done" ;; *) fail "a $d: worker ended done" ;; esac
  check "a $d: worker read the real refactorist role" "$(read_real_role "$id")" yes
done
check 'a seven reports, no duplicates' "$(find "$H/data" -maxdepth 2 -path '*/refactor-am-*/report.md' | wc -l | tr -d ' ')" 7
check 'a pruned same-day tasks never re-fired' "$(grep -c 'bot due: refactor-am' "$TMP_ROOT/wakes.log")" 7

# =============================================================================
# (b) two local-commit runs stop ready-uncommitted at needs-decision
# =============================================================================
for d in $DAYS_B; do
  id="refactor-commit-${d//-/}"
  check "b $d: exactly one wake line all day" "$(grep -c "^$d " "$TMP_ROOT/wakes.log")" 1
  check "b $d: that wake is the 09:00 due line" "$(grep "^$d " "$TMP_ROOT/wakes.log")" \
    "$d 09:00 bot due: $id spec=data/bots/refactor-commit.md level=local-commit"
  check "b $d: plan is a local-only ship on the dated bot branch" \
    "$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print(p["kind"], p["delivery"], p["branch"])' "$TMP_ROOT/runs/$id.plan.json")" \
    "ship local-only bot/refactor-commit/${d//-/}"
  repo="$TMP_ROOT/runs/$id/repo"
  check "b $d: worker is on the dated bot branch" "$(git -C "$repo" branch --show-current)" "bot/refactor-commit/${d//-/}"
  check "b $d: no commit on the branch" "$(git -C "$repo" rev-list --count origin/main..HEAD 2>/dev/null)" 0
  changed=$(project_changes "$repo" | grep -c . || true)
  if [ "$changed" -ge 1 ] && [ "$changed" -le 2 ]; then pass "b $d: an uncommitted change within the file limit ($changed)"; else fail "b $d: an uncommitted change within the file limit ($changed)"; fi
  lines=$(git -C "$repo" diff --numstat | awk '{s += $1 + $2} END {print s + 0}')
  if [ "$lines" -le 40 ]; then pass "b $d: within the line limit ($lines)"; else fail "b $d: within the line limit ($lines)"; fi
  if project_changes "$repo" | grep -q ' tests/'; then fail "b $d: excluded tests/ untouched"; else pass "b $d: excluded tests/ untouched"; fi
  if ( cd "$repo" && PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=src python3 -m unittest discover -s tests >/dev/null 2>&1 ); then
    pass "b $d: tests pass on the uncommitted change"
  else
    fail "b $d: tests pass on the uncommitted change"
  fi
  case $(tail -1 "$H/state/$id.status" 2>/dev/null) in
    'needs-decision [key=commit-approval]'*) pass "b $d: run ends at needs-decision [key=commit-approval]" ;;
    *) fail "b $d: run ends at needs-decision [key=commit-approval] ($(tail -1 "$H/state/$id.status" 2>/dev/null))" ;;
  esac
  if [ -e "$TMP_ROOT/runs/$id/hook-attempts" ]; then fail "b $d: no commit or push attempted"; else pass "b $d: no commit or push attempted"; fi
  contains_hold=$(axi show "$id" 2>/dev/null)
  case $contains_hold in *'hold_kind: captain'*) pass "b $d: held for the captain, not done" ;; *) fail "b $d: held for the captain, not done" ;; esac
  check "b $d: worker read the real refactorist role" "$(read_real_role "$id")" yes
done

# =============================================================================
# isolation
# =============================================================================
check 'sandbox origin refs unchanged (no branch, commit, or push reached it)' \
  "$(git -C "$ORIGIN" for-each-ref --format='%(refname) %(objectname)')" "$ORIGIN_REFS"
check 'no file-seam refusals' "$(cat "$TMP_ROOT/file-errors.log" 2>/dev/null)" ''
check 'live home and shared roots unchanged' "$(live_snapshot)" "$LIVE_BEFORE"
exit "$failed"
