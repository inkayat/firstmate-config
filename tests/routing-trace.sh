#!/usr/bin/env bash
# routing-trace.sh - offline acceptance, plus an externally usable `check`
# CLI, for the temporary routing/agent trace the Captain prints during the
# debugging period (firstmate/primary-policy.md section 0).
#
# Usage:
#   tests/routing-trace.sh                     run the offline fixture suite
#   tests/routing-trace.sh check <trace-file> <harness> <model> <effort> [--brief <delivered-brief>]
#       check ONE worker's captured trace against the actual spawn axes
#       (e.g. state/<id>.meta). The trace's Skills line is DERIVED: it must
#       equal the Routing role's frontmatter autoloadSkills
#       (bin/fm-role-handoff --skills <role>), in order, or `none` for a
#       skill-less role. There is no caller-supplied skill list: the Captain
#       selects a role, never a skill. Prints PASS/FAIL; exit 0 only when
#       nothing FAILs. --brief compares Agent with Assigned role in the
#       delivered Firstmate spec and the brief's `Role skill:` paths with the
#       derived skills; a brief that still carries a Captain skill selection
#       header fails.
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
HANDOFF="$CONFIG_ROOT/bin/fm-role-handoff"

trace_check() { # <trace-file> <harness> <model> <effort> [--brief <delivered-brief>]
  FM_CONFIG_ROOT="$CONFIG_ROOT" python3 - "$CREW_DISPATCH" "$CONFIG_ROOT/roles" "$HANDOFF" "$@" <<'PY'
import json, os, re, subprocess, sys

args = sys.argv[1:]
brief_path = None
if len(args) >= 2 and args[-2] == "--brief":
    brief_path = args[-1]
    args = args[:-2]
if len(args) != 7 or any(a == "--brief" for a in args):
    print("FAIL - expected a trace file and spawn axes, then optional --brief <delivered-brief>")
    sys.exit(2)
dispatch, roles_dir, handoff, trace_path, harness, model, effort = args
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

def skill_id(path):
    path = path.strip()
    if path.endswith("/SKILL.md"):
        return os.path.basename(os.path.dirname(path))
    return path

def derived_skills(role):
    # The one parser is bin/fm-role-handoff; never re-parse frontmatter here.
    p = subprocess.run([handoff, "--skills", role], capture_output=True, text=True)
    return p.stdout.split() if p.returncode == 0 else None

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
role_ok = re.fullmatch(r"[a-z0-9-]+", role) is not None and os.path.isfile(os.path.join(roles_dir, role, "ROLE.md"))
if category in FIXED_ROLES:
    result(role == FIXED_ROLES[category], "role %s matches category %s (requires %s)" % (role, category, FIXED_ROLES[category]))
else:
    result(role not in FIXED_ROLES.values() and role_ok,
           "role %s is senior-fullstack or a specialist role file, valid for category %s" % (role, category))

# Skills are derived from the role, never selected: compare, do not accept.
body = skills_lines[0][len("Skills:"):].strip()
entries = [] if body == "none" else [s.strip() for s in body.split(",")]
name_pattern = r"[A-Za-z0-9][A-Za-z0-9_-]*"
result(body == "none" or (all(re.fullmatch(name_pattern, s) and s != "none" for s in entries)
                         and len(entries) == len(set(entries))),
       "Skills contains comma-separated names only, or none")
result(not any(l.startswith("No skill:") for l in lines), "no verbose No skill companion line")
derived = derived_skills(role) if role_ok else None
if derived is None:
    result(False, "Skills derivable from role %s (no such role file)" % role)
else:
    result(entries == derived, "Skills equals role %s's autoloadSkills %s (trace says %s)" % (role, derived or "none", entries or "none"))

# Compare only observable names, never infer hidden assignment identity.
agents = [l for l in lines if l.startswith("Agent:")]
result(len(agents) == 1, "exactly one Agent line per assignment")
a = re.fullmatch(r"Agent: ([a-z0-9-]+)", agents[0]) if len(agents) == 1 else None
result(a is not None, "Agent contains names only")
if a:
    result(a[1] == role, "Agent role agrees with Routing role")
if brief_path is None:
    inspect("assignment names and brief skill paths not compared: no delivered brief supplied")
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
    paths = [brief[i + 1].strip() for i, l in enumerate(brief) if l.rstrip() == "Role skill:" and i + 1 < len(brief)]
    if derived is not None:
        result([skill_id(p) for p in paths] == derived,
               "brief Role skill paths are exactly the role's autoloadSkills (brief has %s)" % ([skill_id(p) for p in paths] or "none"))
    result(not any(l.startswith(("Selected shared worker skill", "Required project skill")) for l in brief),
           "brief carries no Captain skill selection header")
inspect("names only: hidden paths, worker/native identity, stage and native adoption are not checked")

sys.exit(1 if failed else 0)
PY
}
if [ "${1:-}" = check ]; then
  shift
  [ "$#" -ge 4 ] || { printf 'usage: %s check <trace-file> <harness> <model> <effort> [--brief <delivered-brief>]\n' "$0" >&2; exit 2; }
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
  chmod -R u+w "$TMP" "/tmp/fm-$SEAM_ID+"* 2>/dev/null
  rm -rf "/tmp/fm-$SEAM_ID" "/tmp/fm-$SEAM_ID+"* "$TMP"
}
trap cleanup EXIT
t() { printf '%s\n' "$2" > "$TMP/$1"; printf '%s' "$TMP/$1"; }

OPUS=anthropic/claude-opus-5-5
SONNET=anthropic/claude-sonnet-5-5
SOL=openai-codex/gpt-6.2-sol

# skills_line <role> - the Skills line the policy derives for that role.
skills_line() {
  local s
  s=$("$HANDOFF" --skills "$1" | paste -sd, - | sed 's/,/, /g')
  printf 'Skills: %s' "${s:-none}"
}
# block <file> <"CATEGORY [#n]"> <role> <harness> <model> <effort> <why> - a trace
# block whose Skills line is derived from the role.
block() {
  t "$1" "Routing: $2 | role $3 | $4 | $5 | $6 | why: $7
Agent: $3
$(skills_line "$3")"
}
SF_SKILLS=$("$HANDOFF" --skills senior-fullstack | paste -sd, -)

# --- 1. Routing summary reflects the actual spawn axes ----------------------
IMPL=$(block impl.txt 'IMPLEMENT #2' senior-fullstack omp "$OPUS" high 'multi-file behavior change')
expect 'substantive IMPLEMENT trace matches its spawn axes' pass "$IMPL" omp "$OPUS" high
expect 'trace naming Opus while the worker actually ran Sonnet is rejected' fail "$IMPL" omp "$SONNET" high
expect 'trace effort differing from the actual spawn effort is rejected' fail "$IMPL" omp "$OPUS" xhigh
expect 'trace harness differing from the actual spawn harness is rejected' fail "$IMPL" pi "$OPUS" high

BOUNDED=$(block bounded.txt 'IMPLEMENT #1' senior-fullstack omp "$SONNET" high 'one-function fix')
expect 'bounded IMPLEMENT on Sonnet 5.5 high is an allowed route' pass "$BOUNDED" omp "$SONNET" high

HAIKU_IMPL=$(block haiku-impl.txt 'IMPLEMENT #1' senior-fullstack omp anthropic/claude-haiku-4-5 low cheap)
expect 'a model/effort outside the named category rules is rejected' fail "$HAIKU_IMPL" omp anthropic/claude-haiku-4-5 low
OVERRIDE=$(block override.txt 'IMPLEMENT #1' senior-fullstack omp anthropic/claude-haiku-4-5 low 'captain override - captain asked for Haiku')
expect 'an explicit captain override outside the rules is accepted when the why names it' pass "$OVERRIDE" omp anthropic/claude-haiku-4-5 low

DEFAULT=$(block default.txt DEFAULT senior-fullstack omp "$OPUS" high 'no specific category fits')
expect 'DEFAULT trace on Opus 5.5 high matches the debug-period catch-all' pass "$DEFAULT" omp "$OPUS" high

TENTH=$(block tenth.txt 'TENTH-MAN #1' tenth-man pi "$SOL" high 'challenge Claude-authored completion claim')
expect 'TENTH-MAN against Claude output on Pi GPT-6.2 Sol high is accepted' pass "$TENTH" pi "$SOL" high
ARCH_WRONG_ROLE=$(block arch-role.txt 'ARCHITECTURE #1' senior-fullstack omp "$OPUS" high 'module boundary')
expect 'ARCHITECTURE trace must name role architecture' fail "$ARCH_WRONG_ROLE" omp "$OPUS" high
ARCH=$(block arch.txt 'ARCHITECTURE #1' architecture omp "$OPUS" high 'module boundary')
expect 'ARCHITECTURE with role architecture and its derived skills is accepted' pass "$ARCH" omp "$OPUS" high

# Specialist roles (primary-policy.md section 4) ride any non-fixed category
# as role files; architecture/tenth-man stay fixed to their own categories.
SEC=$(block sec-role.txt 'REVIEW #2' security-engineer omp "$OPUS" high 'authz audit of one service')
expect 'a specialist role file on a non-fixed category is accepted' pass "$SEC" omp "$OPUS" high
UNKNOWN_ROLE=$(t unknown-role.txt "Routing: REVIEW #2 | role pentester | omp | $OPUS | high | why: authz audit
Agent: pentester
Skills: none")
expect_rejects 'a role with no role file is rejected' 'FAIL - role pentester' "$UNKNOWN_ROLE" omp "$OPUS" high
ARCH_SPECIALIST=$(block arch-specialist.txt 'ARCHITECTURE #1' refactorist omp "$OPUS" high 'module boundary')
expect_rejects 'a specialist role cannot replace the fixed ARCHITECTURE role' 'FAIL - role refactorist' "$ARCH_SPECIALIST" omp "$OPUS" high
FIXED_ELSEWHERE=$(block fixed-elsewhere.txt 'IMPLEMENT #1' tenth-man omp "$SONNET" high 'one-function fix')
expect_rejects 'a fixed role is rejected outside its own category' 'FAIL - role tenth-man' "$FIXED_ELSEWHERE" omp "$SONNET" high
MISSING=$(t missing.txt "Skills: none")
expect 'a block without a Routing line is rejected' fail "$MISSING" omp "$OPUS" high

# Sub-lane identity: a multi-rule category's trace names the matched rule
# (#n, 1-based within the category), and the axes must be that rule's own
# route - never merely some route of the category, and no unverifiable
# free-text sub-lane label may follow it.
REVIEW_NO_RULE=$(block rev-norule.txt REVIEW senior-fullstack omp "$SONNET" high 'release-critical security diff')
expect 'a multi-rule category trace without its matched rule #n is rejected' fail "$REVIEW_NO_RULE" omp "$SONNET" high
REVIEW_CRIT_SONNET=$(block rev-crit-sonnet.txt 'REVIEW #3' senior-fullstack omp "$SONNET" high 'release-critical security diff')
expect 'critical REVIEW (#3) displayed on Sonnet 5.5 high contradicts its Opus 5.5 xhigh route and is rejected' fail "$REVIEW_CRIT_SONNET" omp "$SONNET" high
REVIEW_CRIT_OPUS=$(block rev-crit-opus.txt 'REVIEW #3' senior-fullstack omp "$OPUS" xhigh 'release-critical security diff')
expect 'critical REVIEW (#3) on Opus 5.5 xhigh is accepted' pass "$REVIEW_CRIT_OPUS" omp "$OPUS" xhigh
REVIEW_BOUNDED=$(block rev-bounded.txt 'REVIEW #1' senior-fullstack omp "$SONNET" high 'one-file diff')
expect 'bounded REVIEW (#1) on Sonnet 5.5 high is accepted' pass "$REVIEW_BOUNDED" omp "$SONNET" high
REVIEW_CRIT_OVERRIDE=$(block rev-crit-override.txt 'REVIEW #3' senior-fullstack omp "$SONNET" high 'captain override - captain chose Sonnet for this critical review')
expect_shows 'a named captain override of critical REVIEW is accepted and reported as an override' 'captain override' \
  "$REVIEW_CRIT_OVERRIDE" omp "$SONNET" high
REVIEW_BAD_RULE=$(block rev-badrule.txt 'REVIEW #9' senior-fullstack omp "$OPUS" xhigh x)
expect 'a rule number the category does not have is rejected' fail "$REVIEW_BAD_RULE" omp "$OPUS" xhigh
FALSE_CRIT_LABEL=$(block rev-false-crit.txt 'REVIEW #1 critical' senior-fullstack omp "$SONNET" high 'release-critical security diff')
expect 'a free sub-lane label after #n (REVIEW #1 critical on Sonnet high) is rejected' fail "$FALSE_CRIT_LABEL" omp "$SONNET" high
FALSE_BOUNDED_LABEL=$(block rev-false-bounded.txt 'REVIEW #3 bounded' senior-fullstack omp "$OPUS" xhigh 'release-critical security diff')
expect 'a free sub-lane label after #n (REVIEW #3 bounded on Opus xhigh) is rejected' fail "$FALSE_BOUNDED_LABEL" omp "$OPUS" xhigh

# --- 2. Skills are derived from the role, for EVERY role ----------------------
HAS_SKILLS=''
for role in $("$HANDOFF" --roles); do
  case $role in architecture) cat_n='ARCHITECTURE #1' ;; tenth-man) cat_n='TENTH-MAN #1' ;; *) cat_n='IMPLEMENT #2' ;; esac
  case $role in tenth-man) h=pi m=$SOL ;; *) h=omp m=$OPUS ;; esac
  good=$(block "d-$role.txt" "$cat_n" "$role" "$h" "$m" high 'derived-skills fixture')
  expect "role $role: a trace whose Skills line is its autoloadSkills passes" pass "$good" "$h" "$m" high
  derived=$("$HANDOFF" --skills "$role")
  if [ -z "$derived" ]; then
    expect_rejects "role $role (skill-less): naming any skill is rejected" 'Skills equals role' \
      "$(t "x-$role.txt" "$(sed 's/^Skills: none/Skills: ponytail/' "$good")")" "$h" "$m" high
    expect_rejects "role $role (skill-less): Skills must be none" 'Skills equals role' \
      "$(t "xx-$role.txt" "$(sed 's/^Skills: none/Skills: verification-before-completion/' "$good")")" "$h" "$m" high
    continue
  fi
  HAS_SKILLS="$HAS_SKILLS $role"
  expect_rejects "role $role: a Captain-chosen extra skill is rejected" 'Skills equals role' \
    "$(t "e-$role.txt" "$(cat "$good"), tenth-man")" "$h" "$m" high
  expect_rejects "role $role: a dropped skill is rejected" 'Skills equals role' \
    "$(t "r-$role.txt" "$(sed 's/^Skills: [A-Za-z0-9_-]*, /Skills: /; t; s/^Skills: .*/Skills: none/' "$good")")" "$h" "$m" high
  expect_rejects "role $role: Skills none for a role that autoloads skills is rejected" 'Skills equals role' \
    "$(t "n-$role.txt" "$(sed 's/^Skills: .*/Skills: none/' "$good")")" "$h" "$m" high
done
[ -n "$HAS_SKILLS" ] && pass 'derived-skills loop covered roles that carry skills' || fail 'derived-skills loop found no role with skills'
DEFAULT_WRONG=$(t default-wrong.txt "Routing: DEFAULT | role senior-fullstack | omp | $OPUS | high | why: no specific category fits
Agent: senior-fullstack
Skills: none")
expect_rejects 'senior-fullstack with Skills: none contradicts its autoloadSkills' 'Skills equals role senior-fullstack' "$DEFAULT_WRONG" omp "$OPUS" high
REORDER=$(t reorder.txt "$(sed 's/^Skills: .*/Skills: verification-before-completion, ponytail, test-driven-development/' "$IMPL")")
expect_rejects 'the derived Skills list keeps the role file order' 'Skills equals role' "$REORDER" omp "$OPUS" high
for invalid in 'test-driven-development - reason' 'test-driven-development – reason' 'test-driven-development — reason' \
  'test-driven-development; ponytail' '.agents/skills/test-driven-development/SKILL.md' "$HOME/.agents/skills/test-driven-development/SKILL.md" \
  'test-driven-development, ' 'test-driven-development, test-driven-development' 'none, ponytail' ''; do
  expect_rejects 'expanded or malformed skill display is rejected' 'Skills contains comma-separated names only' \
    "$(t invalid-skills.txt "$(sed "s@^Skills:.*@Skills: $invalid@" "$BOUNDED")")" omp "$SONNET" high
done
expect_rejects 'Skills none stands alone without a verbose reason line' 'no verbose No skill companion line' \
  "$(t none-reason.txt "$(cat "$(block scout-none.txt 'EXPLORE #1' scout omp anthropic/claude-haiku-4-5 low x)")
No skill: verbose explanation")" omp anthropic/claude-haiku-4-5 low

# --- 3. Assignment name agreement, never hidden identity/adoption proof ------
# Catch a trace contradicting the delivered role name, Routing, or the role's skills.
ASSIGN_BRIEF="$TMP/assignment-brief.md"
{ printf '## Firstmate spec\n'; "$HANDOFF" senior-fullstack; } > "$ASSIGN_BRIEF"
ASSIGNED=$(block assigned.txt 'IMPLEMENT #2' senior-fullstack omp "$OPUS" high 'coherent CLI and guide change')
expect 'the real handoff block agrees with the trace on role and skills' pass \
  "$ASSIGNED" omp "$OPUS" high --brief "$ASSIGN_BRIEF"
expect_rejects 'an Agent role differing from the delivered brief is rejected' 'Assigned role name agrees with brief' \
  "$(t assign-wrong-role.txt "$(sed 's/Agent: senior-fullstack/Agent: django-pro/' "$ASSIGNED")")" \
  omp "$OPUS" high --brief "$ASSIGN_BRIEF"
expect_rejects 'a missing Agent line is rejected' 'exactly one Agent' \
  "$(t assign-missing.txt "$(sed '/^Agent:/d' "$ASSIGNED")")" omp "$OPUS" high
cp "$ASSIGN_BRIEF" "$TMP/contradictory-brief.md"
printf 'Assigned role: django-pro\n' >> "$TMP/contradictory-brief.md"
expect_rejects 'contradictory brief names fail rather than last-value-wins' 'exactly one brief field Assigned role' \
  "$ASSIGNED" omp "$OPUS" high --brief "$TMP/contradictory-brief.md"
expect_rejects 'an Agent role cannot contradict Routing even without a brief' 'Agent role agrees with Routing role' \
  "$(t assign-role-conflict.txt "$(sed 's/Routing: IMPLEMENT #2 | role senior-fullstack/Routing: IMPLEMENT #2 | role django-pro/' "$ASSIGNED")")" \
  omp "$OPUS" high
expect_rejects 'two Agent lines cannot hide conflicting assignments' 'exactly one Agent' \
  "$(t assign-duplicate.txt "$(cat "$ASSIGNED")
Agent: django-pro")" omp "$OPUS" high --brief "$ASSIGN_BRIEF"
for extra in ' | path /fixture/ROLE.md' ' | native UNPROVEN' ' | worker fixture' ' | why: role fit'; do
  expect_rejects 'Agent rejects expanded metadata instead of silently accepting it' 'Agent contains names only' \
    "$(t assign-expanded.txt "$(sed "s@^Agent:.*@Agent: senior-fullstack$extra@" "$ASSIGNED")")" \
    omp "$OPUS" high --brief "$ASSIGN_BRIEF"
done
# The brief's skill paths must be the role's skills: a missing, extra or
# Captain-selected entry is a brief that does not match the role.
awk '/^Role skill:/ { getline nxt; if (nxt ~ /\/ponytail\/SKILL\.md$/) { skip = 2; next } else { print; print nxt; next } } skip > 0 { skip--; next } { print }' \
  "$ASSIGN_BRIEF" > "$TMP/brief-dropped.md"
expect_rejects 'a brief missing one of the role skills is rejected' 'brief Role skill paths are exactly' \
  "$ASSIGNED" omp "$OPUS" high --brief "$TMP/brief-dropped.md"
{ cat "$ASSIGN_BRIEF"; printf 'Role skill:\n  %s/.agents/skills/tenth-man/SKILL.md\nRequirement:\n  Read.\n' "$HOME"; } > "$TMP/brief-extra.md"
expect_rejects 'a brief with an extra skill the role does not carry is rejected' 'brief Role skill paths are exactly' \
  "$ASSIGNED" omp "$OPUS" high --brief "$TMP/brief-extra.md"
{ cat "$ASSIGN_BRIEF"; printf 'Selected shared worker skill:\n  tenth-man\nRequirement:\n  Apply.\n'; } > "$TMP/brief-selected.md"
expect_rejects 'a brief carrying a Captain skill selection header is rejected' 'no Captain skill selection header' \
  "$ASSIGNED" omp "$OPUS" high --brief "$TMP/brief-selected.md"
SCOUT_BLOCK=$(block scout-block.txt 'EXPLORE #1' scout omp anthropic/claude-haiku-4-5 low 'recon')
{ printf '## Firstmate spec\n'; "$HANDOFF" scout; } > "$TMP/scout-brief.md"
expect 'a skill-less role brief carries no Role skill and agrees with Skills: none' pass \
  "$SCOUT_BLOCK" omp anthropic/claude-haiku-4-5 low --brief "$TMP/scout-brief.md"

# Obsolete invocation shapes must be usage errors, never silently accepted: the
# old trailing skills argument and the old session arguments.
out=$(trace_check "$ASSIGNED" omp "$OPUS" high "$SF_SKILLS" --brief "$ASSIGN_BRIEF" 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then pass 'the retired caller-supplied skills argument is rejected as CLI misuse'; else fail "caller-supplied skills argument reached reporting (exit $rc, want 2): $out"; fi
for obsolete in worker-session review-session; do
  session_args=("$TMP/unused-worker.jsonl")
  [ "$obsolete" != review-session ] || session_args+=("$TMP/unused-review.jsonl")
  out=$(trace_check "$ASSIGNED" omp "$OPUS" high "${session_args[@]}" --brief "$ASSIGN_BRIEF" 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "obsolete $obsolete argument is rejected as CLI misuse"
  else
    fail "obsolete $obsolete argument reached reporting (exit $rc, want 2): $out"
  fi
done

# --- 4. Real dispatch/brief/spawn seam --------------------------------------
# The real, unmodified official bin/fm-spawn.sh launches one task on an
# isolated tmux server (never the shared session) into a real treehouse
# worktree of a disposable project. Only the omp executable is faked: it
# records the argv it was really launched with. This script plays the
# Captain: it takes the substantive-IMPLEMENT route from crew-dispatch.json
# (the category choice itself is still the Captain's judgment and is NOT
# proven here), writes the brief with bin/fm-role-handoff, prints the derived
# trace, spawns with those axes, and then checks the trace against what
# fm-spawn recorded and what the worker was really launched with.
# tests/roles-e2e.sh runs every role through the same seam.
FIRSTMATE_ROOT_REAL="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }

if ! command -v tmux >/dev/null 2>&1 || ! command -v treehouse >/dev/null 2>&1 || [ ! -x "$FIRSTMATE_ROOT_REAL/bin/fm-spawn.sh" ]; then
  printf 'SKIP - real spawn seam: needs tmux, treehouse, and %s/bin/fm-spawn.sh (never reported as PASS)\n' "$FIRSTMATE_ROOT_REAL"
else
  seam_home="$TMP/fm-home"
  seam_proj="$seam_home/projects/seam-proj"
  mkdir -p "$seam_home/state" "$seam_home/config" "$seam_home/data/$SEAM_ID" "$TMP/home" "$TMP/bin" "$seam_proj"
  printf 'manual\n' > "$seam_home/config/backlog-backend"
  printf '# Seam project\n' > "$seam_proj/AGENTS.md"
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
printf '%s\n' "$@" > worker-argv.tmp
mv worker-argv.tmp worker-argv.txt
SH
  chmod +x "$TMP/bin/omp"

  BRIEF="$seam_home/data/$SEAM_ID/brief.md"
  {
    printf "# Task\n\n## Captain's intent\nFixture substantive implementation for the routing-trace seam.\n\n## Firstmate spec\n"
    "$HANDOFF" senior-fullstack
  } > "$BRIEF"
  route=$(python3 -c 'import json,sys; r=[r for r in json.load(open(sys.argv[1]))["rules"] if r["category"]=="IMPLEMENT"][1]["use"][0]; print(r["harness"], r["model"], r["effort"])' "$CREW_DISPATCH")
  set -- $route
  r_harness=$1 r_model=$2 r_effort=$3
  CAPTAIN_TRACE=$(block seam-trace.txt 'IMPLEMENT #2' senior-fullstack "$r_harness" "$r_model" "$r_effort" 'fixture multi-component change')

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
    while [ ! -f "$wt/worker-argv.txt" ] && [ "$waited" -lt 100 ]; do sleep 0.1; waited=$((waited + 1)); done
    argv=$(cat "$wt/worker-argv.txt" 2>/dev/null)
    launched_model=$(printf '%s\n' "$argv" | sed -n '/^--model$/{n;p;}')
    launched_effort=$(printf '%s\n' "$argv" | sed -n '/^--thinking$/{n;p;}')
    delivered="$TMP/delivered-brief.txt"
    printf '%s\n' "$argv" > "$delivered"

    expect 'seam: trace matches the axes fm-spawn recorded' pass \
      "$CAPTAIN_TRACE" "$(field "$meta" harness)" "$(field "$meta" model)" "$(field "$meta" effort)"
    expect 'seam: trace and role skills match the brief the worker was really launched with' pass \
      "$CAPTAIN_TRACE" omp "$launched_model" "$launched_effort" --brief "$delivered"
    expect 'seam: a trace printing xhigh for a task really launched at high is rejected' fail \
      "$(t seam-wrong.txt "$(sed 's/| high |/| xhigh |/' "$CAPTAIN_TRACE")")" omp "$launched_model" "$launched_effort"
  fi
fi

printf '\nROUTING TRACE TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
