#!/usr/bin/env bash
# routing-trace.sh - offline acceptance, plus an externally usable `check`
# CLI, for the temporary routing/skill trace the Captain prints during the
# debugging period (firstmate/primary-policy.md section 0).
#
# Usage:
#   tests/routing-trace.sh                     run the offline fixture suite
#   tests/routing-trace.sh check <trace-file> <harness> <model> <effort> <skills|none> [--brief <delivered-brief>]
#       check ONE worker's captured trace against the actual spawn axes
#       (e.g. state/<id>.meta) and selected skills (comma-separated).
#       Selected SKILL.md paths normalize to their parent directory name;
#       required companion paths normalize to their filename without .md.
#       The trace itself contains names only. Prints PASS/FAIL; exit 0 only
#       when nothing FAILs. --brief compares Agent with Assigned role in the
#       delivered Firstmate spec.
#       Hidden paths, worker/native identity and stage are not compared.
#
# This compares captured text with facts supplied by the caller. Routing
# starts with CATEGORY or CATEGORY #n, with #n required for multi-rule
# categories; axes must match that rule's route or a named captain override.
# It cannot observe the Captain printing, choose the correct category/rule,
# prove native adoption, instruction/skill application, or task completion.
# It is a diagnostic, never a completion gate, dispatch hook, or monitor.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CREW_DISPATCH="$CONFIG_ROOT/firstmate/crew-dispatch.json"

trace_check() { # <trace-file> <harness> <model> <effort> <skills|none> [--brief <delivered-brief>]
  python3 - "$CREW_DISPATCH" "$CONFIG_ROOT/roles" "$@" <<'PY'
import json, os, re, sys

args = sys.argv[1:]
brief_path = None
if len(args) >= 2 and args[-2] == "--brief":
    brief_path = args[-1]
    args = args[:-2]
if len(args) != 7 or any(a == "--brief" for a in args):
    print("FAIL - expected spawn axes and skills, then optional --brief <delivered-brief>")
    sys.exit(2)
dispatch, roles_dir, trace_path, harness, model, effort, skills_arg = args
# primary-policy.md sections 3-4: two roles are fixed to their categories;
# every other category takes senior-fullstack or any specialist role file.
FIXED_ROLES = {"ARCHITECTURE": "architecture", "TENTH-MAN": "tenth-man"}
failed = False

def result(ok, label):
    global failed
    failed |= not ok
    print(("PASS - " if ok else "FAIL - ") + label)

def inspect(label):
    # Located context for an independent assessment: neither a PASS nor a FAIL.
    print("INSPECT - " + label)

def skill_id(token):
    # One display naming rule for shared/project skills and companions.
    token = token.strip().strip("`")
    if token.endswith("/SKILL.md"):
        return os.path.basename(os.path.dirname(token))
    return os.path.splitext(os.path.basename(token))[0] if token.endswith(".md") else token

lines = open(trace_path, encoding="utf-8").read().splitlines()
routing = [l for l in lines if l.startswith("Routing:")]
skills_lines = [l for l in lines if l.startswith("Skills:")]
if len(routing) != 1 or len(skills_lines) != 1:
    result(False, "block has exactly one Routing: line and one Skills: line (got %d and %d)" % (len(routing), len(skills_lines)))
    sys.exit(1)

fields = [f.strip() for f in routing[0][len("Routing:"):].split("|")]
if len(fields) != 6 or not fields[1].startswith("role ") or not fields[5].startswith("why:"):
    result(False, "Routing line has 'CATEGORY [#n] | role R | harness | model | effort | why: ...' shape")
    sys.exit(1)
head = re.fullmatch(r"(\S+)(?: #(\d+))?", fields[0])
if not head:
    result(False, "Routing starts with 'CATEGORY' or 'CATEGORY #n' only - a free sub-lane label is not verifiable (got %r)" % fields[0])
    sys.exit(1)
category = head.group(1)
rule_no = int(head.group(2)) if head.group(2) else None
role = fields[1][len("role "):].strip()
t_harness, t_model, t_effort, why = fields[2], fields[3], fields[4], fields[5]

result((t_harness, t_model, t_effort) == (harness, model, effort),
       "Routing shows the actual spawn axes %s/%s/%s (trace says %s/%s/%s)" % (harness, model, effort, t_harness, t_model, t_effort))

doc = json.load(open(dispatch))
cat_rules = [r for r in doc["rules"] if r["category"] == category]
result(category == "DEFAULT" or bool(cat_rules), "category %s exists in crew-dispatch.json" % category)
# The sub-lane is identified only by its rule number within the category.
if category == "DEFAULT":
    where, candidates = "the DEFAULT route", doc["default"]
elif rule_no is None and len(cat_rules) > 1:
    result(False, "%s has %d rules, so the trace must name the matched rule as #n" % (category, len(cat_rules)))
    where, candidates = None, []
elif rule_no is not None and not 1 <= rule_no <= len(cat_rules):
    result(False, "%s has no rule #%d (it has %d)" % (category, rule_no, len(cat_rules)))
    where, candidates = None, []
else:
    n = rule_no or 1
    where, candidates = "%s rule #%d's route" % (category, n), cat_rules[n - 1]["use"] if cat_rules else []
if where:
    tuple_ = (t_harness, t_model, t_effort)
    if any((c["harness"], c["model"], c["effort"]) == tuple_ for c in candidates):
        result(True, "%s/%s/%s is %s" % (tuple_ + (where,)))
    elif "captain override" in why.lower():
        result(True, "%s/%s/%s is not %s: accepted as a named captain override" % (tuple_ + (where,)))
    else:
        result(False, "%s/%s/%s is %s (configured: %s)" % (tuple_ + (where, ", ".join(
            "%s/%s/%s" % (c["harness"], c["model"], c["effort"]) for c in candidates))))
if category in FIXED_ROLES:
    result(role == FIXED_ROLES[category], "role %s matches category %s (requires %s)" % (role, category, FIXED_ROLES[category]))
else:
    result(role not in FIXED_ROLES.values() and re.fullmatch(r"[a-z0-9-]+", role) is not None
           and os.path.isfile(os.path.join(roles_dir, role, "ROLE.md")),
           "role %s is senior-fullstack or a specialist role file, valid for category %s" % (role, category))

body = skills_lines[0][len("Skills:"):].strip()
entries = [] if body == "none" else [s.strip() for s in body.split(",")]
name_pattern = r"[A-Za-z0-9][A-Za-z0-9_-]*"
result(body == "none" or (all(re.fullmatch(name_pattern, s) and s != "none" for s in entries)
                         and len(entries) == len(set(entries))),
       "Skills contains comma-separated names only, or none")
result(not any(l.startswith("No skill:") for l in lines), "no verbose No skill companion line")
traced = set(entries)
selected = set() if skills_arg == "none" else {skill_id(s) for s in skills_arg.split(",") if s.strip()}
result(traced == selected, "Skills names exactly the selected skills %s (trace says %s)" % (sorted(selected) or "none", sorted(traced) or "none"))

# Compare only observable names, never infer hidden assignment identity.
agents = [l for l in lines if l.startswith("Agent:")]
result(len(agents) == 1, "exactly one Agent line per assignment")
a = re.fullmatch(r"Agent: ([a-z0-9-]+)", agents[0]) if len(agents) == 1 else None
result(a is not None, "Agent contains names only")
if a:
    result(a[1] == role, "Agent role agrees with Routing role")
if brief_path is None:
    inspect("assignment names not compared: no delivered brief supplied")
else:
    try:
        brief = open(brief_path, encoding="utf-8").read().splitlines()
    except (OSError, UnicodeError) as e:
        result(False, "cannot read delivered brief: %s" % e)
        brief = []
    for key, match in (("Assigned role", a),):
        values = [l[len(key) + 1:].strip() for l in brief if l.startswith(key + ":")]
        ok = len(values) == 1 and bool(values[0])
        result(ok, "exactly one brief field %s (name agreement unknown if missing/conflicting)" % key)
        if ok and match:
            result(match[1] == values[0], "%s name agrees with brief" % key)
inspect("names only: hidden paths, worker/native identity, stage and native adoption are not checked")

sys.exit(1 if failed else 0)
PY
}
if [ "${1:-}" = check ]; then
  shift
  [ "$#" -ge 5 ] || { printf 'usage: %s check <trace-file> <harness> <model> <effort> <skills|none> [--brief <delivered-brief>]\n' "$0" >&2; exit 2; }
  trace_check "$@"
  exit $?
fi

command -v python3 >/dev/null 2>&1 || { printf 'SKIP - routing trace: python3 is required\n\nROUTING TRACE TESTS SKIPPED\n'; exit 0; }

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
expect() { # <label> <pass|fail> <trace-check args...>
  local label=$1 want=$2 out rc
  shift 2
  out=$(trace_check "$@" 2>&1); rc=$?
  if { [ "$want" = pass ] && [ "$rc" -eq 0 ]; } || { [ "$want" = fail ] && [ "$rc" -eq 1 ]; }; then
    pass "$label"
  else
    fail "$label (expected $want, exit $rc): $(printf '%s' "$out" | grep FAIL | head -3 | tr '\n' ' ')"
  fi
}
expect_shows() { # <label> <needle> <trace-check args...> - passes, and prints <needle> for a human
  local label=$1 needle=$2 out rc
  shift 2
  out=$(trace_check "$@" 2>&1); rc=$?
  case $out in
    *"$needle"*) [ "$rc" -eq 0 ] && pass "$label" || fail "$label (exit $rc)" ;;
    *) fail "$label (output never shows '$needle')" ;;
  esac
}
expect_rejects() { # <label> <FAIL needle> <trace-check args...> - fails, and for the stated reason
  local label=$1 needle=$2 out rc
  shift 2
  out=$(trace_check "$@" 2>&1); rc=$?
  case $out in
    *"$needle"*) [ "$rc" -eq 1 ] && pass "$label" || fail "$label (exit $rc)" ;;
    *) fail "$label (no '$needle' in: $(printf '%s' "$out" | grep FAIL | tr '\n' ' '))" ;;
  esac
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-routing-trace.XXXXXX") || exit 1
TMP=$(cd "$TMP" && pwd)
SEAM_TMUX=''
SEAM_ID=fm-trace-seam-$$
cleanup() {
  if [ -n "$SEAM_TMUX" ]; then
    TMUX_TMPDIR="$SEAM_TMUX" tmux kill-server >/dev/null 2>&1 || true
    sleep 0.3
    rm -rf "$SEAM_TMUX"
  fi
  # fm-spawn also creates its launch dir at /tmp/fm-<id>+<home-token>.
  rm -rf "/tmp/fm-$SEAM_ID" "/tmp/fm-$SEAM_ID+"* "$TMP"
}
trap cleanup EXIT
t() { printf '%s\n' "$2" > "$TMP/$1"; printf '%s' "$TMP/$1"; }

OPUS=anthropic/claude-opus-5-5
SONNET=anthropic/claude-sonnet-5-5
SOL=openai-codex/gpt-6.1-sol
TDD=test-driven-development
VBC=verification-before-completion

# --- 1. Routing summary reflects the actual spawn axes ----------------------
IMPL=$(t impl.txt "Routing: IMPLEMENT #2 | role senior-fullstack | omp | $OPUS | high | why: multi-file behavior change
Agent: senior-fullstack
Skills: $TDD, $VBC")
expect 'substantive IMPLEMENT trace matches its spawn axes' pass "$IMPL" omp "$OPUS" high "$TDD,$VBC"
expect 'trace naming Opus while the worker actually ran Sonnet is rejected' fail "$IMPL" omp "$SONNET" high "$TDD,$VBC"
expect 'trace effort differing from the actual spawn effort is rejected' fail "$IMPL" omp "$OPUS" xhigh "$TDD,$VBC"
expect 'trace harness differing from the actual spawn harness is rejected' fail "$IMPL" pi "$OPUS" high "$TDD,$VBC"

BOUNDED=$(t bounded.txt "Routing: IMPLEMENT #1 | role senior-fullstack | omp | $SONNET | high | why: one-function fix
Agent: senior-fullstack
Skills: $TDD")
expect 'bounded IMPLEMENT on Sonnet 5.5 high is an allowed route' pass "$BOUNDED" omp "$SONNET" high "$TDD"

HAIKU_IMPL=$(t haiku-impl.txt "Routing: IMPLEMENT #1 | role senior-fullstack | omp | anthropic/claude-haiku-4-5 | low | why: cheap
Agent: senior-fullstack
Skills: none")
expect 'a model/effort outside the named category rules is rejected' fail "$HAIKU_IMPL" omp anthropic/claude-haiku-4-5 low none
OVERRIDE=$(t override.txt "Routing: IMPLEMENT #1 | role senior-fullstack | omp | anthropic/claude-haiku-4-5 | low | why: captain override - captain asked for Haiku
Agent: senior-fullstack
Skills: none")
expect 'an explicit captain override outside the rules is accepted when the why names it' pass "$OVERRIDE" omp anthropic/claude-haiku-4-5 low none

DEFAULT=$(t default.txt "Routing: DEFAULT | role senior-fullstack | omp | $OPUS | high | why: no specific category fits
Agent: senior-fullstack
Skills: none")
expect 'DEFAULT trace on Opus 5.5 high matches the debug-period catch-all' pass "$DEFAULT" omp "$OPUS" high none

TENTH=$(t tenth.txt "Routing: TENTH-MAN #1 | role tenth-man | pi | $SOL | xhigh | why: challenge Claude-authored completion claim
Agent: tenth-man
Skills: none")
expect 'TENTH-MAN against Claude output on Pi GPT-6.1 Sol xhigh is accepted' pass "$TENTH" pi "$SOL" xhigh none
ARCH_WRONG_ROLE=$(t arch-role.txt "Routing: ARCHITECTURE #1 | role senior-fullstack | omp | $OPUS | high | why: module boundary
Agent: senior-fullstack
Skills: none")
expect 'ARCHITECTURE trace must name role architecture' fail "$ARCH_WRONG_ROLE" omp "$OPUS" high none

# Specialist roles (primary-policy.md section 4) ride any non-fixed category
# as role files; architecture/tenth-man stay fixed to their own categories.
SEC=$(t sec-role.txt "Routing: REVIEW #2 | role security-engineer | omp | $OPUS | high | why: authz audit of one service
Agent: security-engineer
Skills: security-and-hardening, $VBC")
expect 'a specialist role file on a non-fixed category is accepted' pass "$SEC" omp "$OPUS" high "security-and-hardening,$VBC"
UNKNOWN_ROLE=$(t unknown-role.txt "Routing: REVIEW #2 | role pentester | omp | $OPUS | high | why: authz audit
Agent: pentester
Skills: none")
expect_rejects 'a role with no role file is rejected' 'FAIL - role pentester' "$UNKNOWN_ROLE" omp "$OPUS" high none
ARCH_SPECIALIST=$(t arch-specialist.txt "Routing: ARCHITECTURE #1 | role refactorist | omp | $OPUS | high | why: module boundary
Agent: refactorist
Skills: none")
expect_rejects 'a specialist role cannot replace the fixed ARCHITECTURE role' 'FAIL - role refactorist' "$ARCH_SPECIALIST" omp "$OPUS" high none
FIXED_ELSEWHERE=$(t fixed-elsewhere.txt "Routing: IMPLEMENT #1 | role tenth-man | omp | $SONNET | high | why: one-function fix
Agent: tenth-man
Skills: none")
expect_rejects 'a fixed role is rejected outside its own category' 'FAIL - role tenth-man' "$FIXED_ELSEWHERE" omp "$SONNET" high none
MISSING=$(t missing.txt "Skills: none")
expect 'a block without a Routing line is rejected' fail "$MISSING" omp "$OPUS" high none

# Sub-lane identity: a multi-rule category's trace names the matched rule
# (#n, 1-based within the category, pinned by tests/routing-taxonomy.sh),
# and the axes must be that rule's own route - never merely some route of
# the category, and no unverifiable free-text sub-lane label may follow it
# (review findings: "REVIEW critical" and "REVIEW #1 critical" on Sonnet
# high both passed).
REVIEW_NO_RULE=$(t rev-norule.txt "Routing: REVIEW | role senior-fullstack | omp | $SONNET | high | why: release-critical security diff
Agent: senior-fullstack
Skills: none")
expect 'a multi-rule category trace without its matched rule #n is rejected' fail "$REVIEW_NO_RULE" omp "$SONNET" high none
REVIEW_CRIT_SONNET=$(t rev-crit-sonnet.txt "Routing: REVIEW #3 | role senior-fullstack | omp | $SONNET | high | why: release-critical security diff
Agent: senior-fullstack
Skills: none")
expect 'critical REVIEW (#3) displayed on Sonnet 5.5 high contradicts its Opus 5.5 xhigh route and is rejected' fail "$REVIEW_CRIT_SONNET" omp "$SONNET" high none
REVIEW_CRIT_OPUS=$(t rev-crit-opus.txt "Routing: REVIEW #3 | role senior-fullstack | omp | $OPUS | xhigh | why: release-critical security diff
Agent: senior-fullstack
Skills: none")
expect 'critical REVIEW (#3) on Opus 5.5 xhigh is accepted' pass "$REVIEW_CRIT_OPUS" omp "$OPUS" xhigh none
REVIEW_BOUNDED=$(t rev-bounded.txt "Routing: REVIEW #1 | role senior-fullstack | omp | $SONNET | high | why: one-file diff
Agent: senior-fullstack
Skills: none")
expect 'bounded REVIEW (#1) on Sonnet 5.5 high is accepted' pass "$REVIEW_BOUNDED" omp "$SONNET" high none
REVIEW_CRIT_OVERRIDE=$(t rev-crit-override.txt "Routing: REVIEW #3 | role senior-fullstack | omp | $SONNET | high | why: captain override - captain chose Sonnet for this critical review
Agent: senior-fullstack
Skills: none")
expect_shows 'a named captain override of critical REVIEW is accepted and reported as an override' 'captain override' \
  "$REVIEW_CRIT_OVERRIDE" omp "$SONNET" high none
REVIEW_BAD_RULE=$(t rev-badrule.txt "Routing: REVIEW #9 | role senior-fullstack | omp | $OPUS | xhigh | why: x
Agent: senior-fullstack
Skills: none")
expect 'a rule number the category does not have is rejected' fail "$REVIEW_BAD_RULE" omp "$OPUS" xhigh none
FALSE_CRIT_LABEL=$(t rev-false-crit.txt "Routing: REVIEW #1 critical | role senior-fullstack | omp | $SONNET | high | why: release-critical security diff
Agent: senior-fullstack
Skills: none")
expect 'a free sub-lane label after #n (REVIEW #1 critical on Sonnet high) is rejected' fail "$FALSE_CRIT_LABEL" omp "$SONNET" high none
FALSE_BOUNDED_LABEL=$(t rev-false-bounded.txt "Routing: REVIEW #3 bounded | role senior-fullstack | omp | $OPUS | xhigh | why: release-critical security diff
Agent: senior-fullstack
Skills: none")
expect 'a free sub-lane label after #n (REVIEW #3 bounded on Opus xhigh) is rejected' fail "$FALSE_BOUNDED_LABEL" omp "$OPUS" xhigh none

# --- 2. Skills summary reflects exactly the selected skills -----------------
expect 'Skills naming an unselected, merely installed skill is rejected' fail "$IMPL" omp "$OPUS" high "$TDD"
expect 'Skills omitting a selected skill is rejected' fail "$BOUNDED" omp "$SONNET" high "$TDD,$VBC"
expect 'zero selected skills with "Skills: none" is valid' pass "$DEFAULT" omp "$OPUS" high none
expect 'absolute shared-skill paths from the brief normalize to their names' pass "$IMPL" omp "$OPUS" high "$HOME/.agents/skills/$TDD/SKILL.md,$HOME/.agents/skills/$VBC/SKILL.md"
PROJECT=$(t project.txt "Routing: REVIEW #2 | role senior-fullstack | omp | $OPUS | high | why: cross-component diff
Agent: senior-fullstack
Skills: architecture-review, ponytail-review")
expect 'project-local and shared skills display only selected names' pass "$PROJECT" omp "$OPUS" high '.agents/skills/architecture-review/SKILL.md,ponytail-review'
expect 'same-named local and global sources cannot be distinguished by this display' pass "$PROJECT" omp "$OPUS" high 'architecture-review,ponytail-review'
COMPANION=$(t companion.txt "Routing: IMPLEMENT #1 | role senior-fullstack | omp | $SONNET | high | why: bounded behavior change
Agent: senior-fullstack
Skills: ponytail, $TDD, writing-good-tests")
expect 'a required companion displays a short name, not its full path' pass \
  "$COMPANION" omp "$SONNET" high "ponytail,~/.agents/skills/$TDD/SKILL.md,~/.agents/skills/$TDD/writing-good-tests.md"
for invalid in "$TDD - reason" "$TDD – reason" "$TDD — reason" "$TDD; $VBC" \
  ".agents/skills/$TDD/SKILL.md" "$HOME/.agents/skills/$TDD/SKILL.md" \
  "$TDD, " "$TDD, $TDD" "none, $TDD" ""; do
  expect_rejects 'expanded or malformed skill display is rejected' 'Skills contains comma-separated names only' \
    "$(t invalid-skills.txt "$(sed "s@^Skills:.*@Skills: $invalid@" "$BOUNDED")")" omp "$SONNET" high "$TDD"
done
expect_rejects 'Skills none stands alone without a verbose reason line' 'no verbose No skill companion line' \
  "$(t none-reason.txt "$(cat "$DEFAULT")
No skill: verbose explanation")" omp "$OPUS" high none

# --- 3. Assignment name agreement, never hidden identity/adoption proof ------
# Catch a trace contradicting the delivered role name or Routing.
ASSIGN_BRIEF="$TMP/assignment-brief.md"
# Name-comparison fixture, not a complete worker handoff.
cat > "$ASSIGN_BRIEF" <<'EOF'
## Firstmate spec
Assigned role: senior-fullstack
EOF
ASSIGNED=$(t assigned.txt "Routing: IMPLEMENT #2 | role senior-fullstack | omp | $OPUS | high | why: coherent CLI and guide change
Agent: senior-fullstack
Skills: none")
expect 'compact assignment compares role names without a recipe field' pass \
  "$ASSIGNED" omp "$OPUS" high none --brief "$ASSIGN_BRIEF"
expect_rejects 'an Agent role differing from the delivered brief is rejected' 'Assigned role name agrees with brief' \
  "$(t assign-wrong-role.txt "$(sed 's/Agent: senior-fullstack/Agent: django-pro/' "$ASSIGNED")")" \
  omp "$OPUS" high none --brief "$ASSIGN_BRIEF"
expect_rejects 'a missing Agent line is rejected' 'exactly one Agent' \
  "$(t assign-missing.txt "$(sed '/^Agent:/d' "$ASSIGNED")")" omp "$OPUS" high none
cp "$ASSIGN_BRIEF" "$TMP/contradictory-brief.md"
printf 'Assigned role: django-pro\n' >> "$TMP/contradictory-brief.md"
expect_rejects 'contradictory brief names fail rather than last-value-wins' 'exactly one brief field Assigned role' \
  "$ASSIGNED" omp "$OPUS" high none --brief "$TMP/contradictory-brief.md"
expect_rejects 'an Agent role cannot contradict Routing even without a brief' 'Agent role agrees with Routing role' \
  "$(t assign-role-conflict.txt "$(sed 's/Routing: IMPLEMENT #2 | role senior-fullstack/Routing: IMPLEMENT #2 | role django-pro/' "$ASSIGNED")")" \
  omp "$OPUS" high none
expect_rejects 'two Agent lines cannot hide conflicting assignments' 'exactly one Agent' \
  "$(t assign-duplicate.txt "$(cat "$ASSIGNED")
Agent: django-pro")" omp "$OPUS" high none --brief "$ASSIGN_BRIEF"
for extra in ' | path /fixture/ROLE.md' ' | native UNPROVEN' ' | worker fixture' ' | why: role fit'; do
  expect_rejects 'Agent rejects expanded metadata instead of silently accepting it' 'Agent contains names only' \
    "$(t assign-expanded.txt "$(sed "s@^Agent:.*@Agent: senior-fullstack$extra@" "$ASSIGNED")")" \
    omp "$OPUS" high none --brief "$ASSIGN_BRIEF"
done

# Session arguments no longer belong to this compact assignment diagnostic.
# Catch an old invocation reaching post-work reporting instead of a usage error.
for obsolete in worker-session review-session; do
  session_args=("$TMP/unused-worker.jsonl")
  [ "$obsolete" != review-session ] || session_args+=("$TMP/unused-review.jsonl")
  out=$(trace_check "$ASSIGNED" omp "$OPUS" high none "${session_args[@]}" --brief "$ASSIGN_BRIEF" 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "obsolete $obsolete argument is rejected as CLI misuse"
  else
    fail "obsolete $obsolete argument reached reporting (exit $rc, want 2): $out"
  fi
done

# --- 4. Real dispatch/brief/spawn seam --------------------------------------
# The real, unmodified official bin/fm-spawn.sh launches one task on an
# isolated tmux server (never the shared session) into a real treehouse
# worktree of a disposable project - the same seam tests/multi-project-
# captain.sh uses. Only the omp executable is faked: it records the argv it
# was really launched with and, when the delivered brief names the fixture
# project skill, runs that skill's ./check.sh into a result file. This
# script plays the Captain: it takes the substantive-IMPLEMENT route from
# crew-dispatch.json (the category choice itself is still the Captain's
# judgment and is NOT proven here), reads selected skills from the brief
# it writes, prints the trace, spawns with those axes, and then checks the
# trace against what fm-spawn recorded and what the worker actually
# received and did.
FIRSTMATE_ROOT_REAL="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }

# brief_skills <brief-file> - the skills a primary-policy.md section 2
# brief selects: the indented line after each "Required project skill:" or
# "Selected shared worker skill:" header, comma-joined, or "none".
brief_skills() {
  local s
  s=$(awk '/^(Required project skill|Selected shared worker skill)/ {getline; gsub(/^[ \t]+|[ \t]+$/, ""); printf "%s%s", sep, $0; sep=","}' "$1")
  printf '%s' "${s:-none}"
}

if ! command -v tmux >/dev/null 2>&1 || ! command -v treehouse >/dev/null 2>&1 || [ ! -x "$FIRSTMATE_ROOT_REAL/bin/fm-spawn.sh" ]; then
  printf 'SKIP - real spawn seam: needs tmux, treehouse, and %s/bin/fm-spawn.sh (never reported as PASS)\n' "$FIRSTMATE_ROOT_REAL"
else
  seam_home="$TMP/fm-home"
  seam_proj="$seam_home/projects/seam-proj"
  mkdir -p "$seam_home/state" "$seam_home/config" "$seam_home/data/$SEAM_ID" "$TMP/home" "$TMP/bin" \
    "$seam_proj/.agents/skills/trace-canary"
  printf 'manual\n' > "$seam_home/config/backlog-backend"
  printf '# Seam project\n' > "$seam_proj/AGENTS.md"
  printf -- '---\nname: trace-canary\ndescription: fixture project skill\n---\nRun ./check.sh before claiming done.\n' \
    > "$seam_proj/.agents/skills/trace-canary/SKILL.md"
  printf '#!/bin/sh\necho CHECK OK\n' > "$seam_proj/check.sh"
  chmod +x "$seam_proj/check.sh"
  printf 'max_trees = 4\nroot = "./"\n' > "$seam_proj/treehouse.toml"
  git -C "$seam_proj" init -q
  git -C "$seam_proj" add -A
  git -C "$seam_proj" -c user.email=t@example.invalid -c user.name=t commit -q -m init

  cat > "$TMP/bin/omp" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = --help ] && { printf 'usage: omp [options] [prompt]\n'; exit 0; }
# fm-spawn validates --model against `omp models --json` before launch.
if [ "${1:-}" = models ]; then
  printf '{"models":[{"provider":"anthropic","id":"claude-opus-5-5","selector":"anthropic/claude-opus-5-5"},{"provider":"anthropic","id":"claude-sonnet-5-5","selector":"anthropic/claude-sonnet-5-5"}]}\n'
  exit 0
fi
printf '%s\n' "$@" > worker-argv.txt
# With the canary skill in its brief, run the fixture check in the worktree.
: > worker-result.tmp
case "$*" in
  *.agents/skills/trace-canary/SKILL.md*)
    ./check.sh > worker-result.tmp ;;
esac
mv worker-result.tmp worker-result.txt
SH
  chmod +x "$TMP/bin/omp"

  BRIEF="$seam_home/data/$SEAM_ID/brief.md"
  cat > "$BRIEF" <<'EOF'
# Task

## Captain's intent
Fixture substantive implementation for the routing-trace seam.

## Firstmate spec
Required project skill:
  .agents/skills/trace-canary/SKILL.md
Requirement:
  Read and apply before claiming done.
Selected shared worker skill:
  verification-before-completion
Requirement:
  Apply before declaring the task complete.
EOF
  route=$(python3 -c 'import json,sys; r=[r for r in json.load(open(sys.argv[1]))["rules"] if r["category"]=="IMPLEMENT"][1]["use"][0]; print(r["harness"], r["model"], r["effort"])' "$CREW_DISPATCH")
  set -- $route
  r_harness=$1 r_model=$2 r_effort=$3
  selected=$(brief_skills "$BRIEF")
  CAPTAIN_TRACE=$(t seam-trace.txt "Routing: IMPLEMENT #2 | role senior-fullstack | $r_harness | $r_model | $r_effort | why: fixture multi-component change
Agent: senior-fullstack
Skills: trace-canary, verification-before-completion")

  SEAM_TMUX=$(mktemp -d /tmp/fm-trace-tmux.XXXXXX) || exit 1
  spawn_out=$(TMUX_TMPDIR="$SEAM_TMUX" PATH="$TMP/bin:$PATH" HOME="$TMP/home" FM_HOME="$seam_home" FM_BACKEND=tmux \
    timeout 60 "$FIRSTMATE_ROOT_REAL/bin/fm-spawn.sh" "$SEAM_ID" projects/seam-proj \
    --mode local-only --yolo off --harness "$r_harness" --model "$r_model" --effort "$r_effort" 2>&1)
  if [ $? -ne 0 ]; then
    fail "real fm-spawn of the seam task failed: $spawn_out"
  else
    meta=$(cat "$seam_home/state/$SEAM_ID.meta" 2>/dev/null)
    wt=$(field "$meta" worktree)
    waited=0
    while [ ! -f "$wt/worker-result.txt" ] && [ "$waited" -lt 100 ]; do sleep 0.1; waited=$((waited + 1)); done
    argv=$(cat "$wt/worker-argv.txt" 2>/dev/null)
    launched_model=$(printf '%s\n' "$argv" | sed -n '/^--model$/{n;p;}')
    launched_effort=$(printf '%s\n' "$argv" | sed -n '/^--thinking$/{n;p;}')
    delivered="$TMP/delivered-brief.txt"
    printf '%s\n' "$argv" > "$delivered"

    expect 'seam: trace matches the axes fm-spawn recorded and the skills in the written brief' pass \
      "$CAPTAIN_TRACE" "$(field "$meta" harness)" "$(field "$meta" model)" "$(field "$meta" effort)" "$selected"
    expect 'seam: trace matches the --model/--thinking the worker process was really launched with' pass \
      "$CAPTAIN_TRACE" omp "$launched_model" "$launched_effort" "$(brief_skills "$delivered")"
    expect 'seam: a trace printing xhigh for a task really launched at high is rejected' fail \
      "$(t seam-wrong.txt "$(sed 's/| high |/| xhigh |/' "$CAPTAIN_TRACE")")" omp "$launched_model" "$launched_effort" "$selected"

    if [ "$(cat "$wt/worker-result.txt" 2>/dev/null)" = 'CHECK OK' ]; then
      pass 'seam: the delivered project skill triggers the fixture check'
    else
      fail 'seam: the delivered project skill did not produce CHECK OK'
    fi
  fi
fi

printf '\nROUTING TRACE TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
