#!/usr/bin/env bash
# routing-taxonomy.sh - acceptance for the eleven-category worker dispatch
# taxonomy in firstmate/crew-dispatch.json: structural shape, the pinned
# active-primary route per category rule, quota-array purity (a `use`
# array holds only genuinely interchangeable candidates - never a
# semantic escalation or a documented override), the collision-
# disambiguation prose required for every named adjacent-category pair,
# representative example intents (including boundary/ambiguity fixtures),
# and a repository-wide proof that no reference to the retired fast-tier
# codex lane remains.
#
# There is no runtime intent classifier anywhere in this configuration:
# category selection is made by the captain (an LLM) reading
# crew-dispatch.json's own "when"/"why" text, per README.md "Routing in
# v0.1" and primary-policy.md section 3. This script therefore cannot
# execute a fixture intent against a classifier and check its output; it
# proves the taxonomy is structurally correct, that the pinned routes match
# what firstmate/primary-policy.md and README.md document, and that the
# specific disambiguating sentence for every named collision is genuinely
# present in the tracked source - the same fixture-report style already
# used by tests/worker-context.sh, not a new policy-enforcement mechanism.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CREW_DISPATCH="$CONFIG_ROOT/firstmate/crew-dispatch.json"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}
contains() {
  case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3')" ;; esac
}

# =============================================================================
# Parse tier: jq if present, else python3. Mirrors bin/fm-doctor's own
# crew_dispatch_validate tiering (never a third, invented parser).
# =============================================================================
PARSE_METHOD=none
if command -v jq >/dev/null 2>&1; then
  PARSE_METHOD=jq
elif command -v python3 >/dev/null 2>&1; then
  PARSE_METHOD=python3
fi

if [ "$PARSE_METHOD" = none ]; then
  pass 'routing taxonomy: skipped entirely (no jq or python3 on this machine to parse crew-dispatch.json)'
  printf '\nROUTING TAXONOMY TESTS PASS\n'
  exit 0
fi

# category_field <category> <field> - "when", "why", or "use" (use prints
# tab-separated harness/model/effort, one per line, in document order).
# A category may span more than one `rules` entry (a genuine semantic
# escalation, never a quota-array peer of the base rule) - both tiers
# aggregate across every matching rule, in document order, never just the
# first, so a split category's second rule is never silently dropped.
category_field() {
  local cat=$1 field=$2
  if [ "$PARSE_METHOD" = jq ]; then
    case $field in
      use) jq -r --arg c "$cat" '.rules[] | select(.category==$c) | .use[] | "\(.harness)\t\(.model)\t\(.effort)"' "$CREW_DISPATCH" ;;
      *) jq -r --arg c "$cat" --arg f "$field" '.rules[] | select(.category==$c) | .[$f]' "$CREW_DISPATCH" ;;
    esac
  else
    python3 - "$CREW_DISPATCH" "$cat" "$field" <<'PY'
import json, sys
path, cat, field = sys.argv[1], sys.argv[2], sys.argv[3]
doc = json.load(open(path))
matches = [r for r in doc["rules"] if r.get("category") == cat]
for rule in matches:
    if field == "use":
        for u in rule["use"]:
            print("%s\t%s\t%s" % (u["harness"], u["model"], u["effort"]))
    else:
        print(rule[field])
PY
  fi
}

# category_rule_count <category> - how many `rules` entries share this
# category value (1 for an ordinary category, 2 for a split one).
category_rule_count() {
  local cat=$1
  if [ "$PARSE_METHOD" = jq ]; then
    jq -r --arg c "$cat" '[.rules[] | select(.category==$c)] | length' "$CREW_DISPATCH"
  else
    python3 - "$CREW_DISPATCH" "$cat" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
print(len([r for r in doc["rules"] if r.get("category") == sys.argv[2]]))
PY
  fi
}

# category_rule_use_length <category> <rule-occurrence 1-based> - how many
# `use` entries that specific rule's array carries. Used to enforce that
# multi-candidate arrays contain only the deliberately paired peers documented
# by this routing policy.
category_rule_use_length() {
  local cat=$1 occ=$2
  if [ "$PARSE_METHOD" = jq ]; then
    jq -r --arg c "$cat" --argjson i "$((occ - 1))" '[.rules[] | select(.category==$c)][$i].use | length' "$CREW_DISPATCH"
  else
    python3 - "$CREW_DISPATCH" "$cat" "$occ" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
matches = [r for r in doc["rules"] if r.get("category") == sys.argv[2]]
print(len(matches[int(sys.argv[3]) - 1]["use"]))
PY
  fi
}

all_categories() {
  if [ "$PARSE_METHOD" = jq ]; then
    jq -r '.rules[].category' "$CREW_DISPATCH"
  else
    python3 - "$CREW_DISPATCH" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
for r in doc["rules"]:
    print(r.get("category", ""))
PY
  fi
}

default_tuple() {
  if [ "$PARSE_METHOD" = jq ]; then
    jq -r '.default[0] | "\(.harness)\t\(.model)\t\(.effort)"' "$CREW_DISPATCH"
  else
    python3 - "$CREW_DISPATCH" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
d = doc["default"][0]
print("%s\t%s\t%s" % (d["harness"], d["model"], d["effort"]))
PY
  fi
}

# =============================================================================
# 1. Structural shape: exactly the ten named category values (fourteen
#    `rules` entries total - EXPLORE, RESEARCH, IMPLEMENT-LARGE, and DEEP
#    each span two more-specific rules sharing one category value; every
#    other category is a single rule), plus the untagged `default`
#    catch-all for DEFAULT. No stray category names.
# =============================================================================
EXPECTED_CATEGORIES='ARCHITECTURE
DEEP
EXPLORE
IMPLEMENT
IMPLEMENT-LARGE
QUICK
RESEARCH
REVIEW
TENTH-MAN
UI/BROWSER'

actual_categories=$(all_categories | sort -u)
check 'exactly the ten named categories are present, no more, no fewer' "$EXPECTED_CATEGORIES" "$actual_categories"

total_rules=$(all_categories | wc -l | tr -d ' ')
check 'fourteen total rules entries (ten categories, four of them split)' 14 "$total_rules"

for pair in QUICK:1 EXPLORE:2 RESEARCH:2 REVIEW:1 ARCHITECTURE:1 TENTH-MAN:1 IMPLEMENT:1 IMPLEMENT-LARGE:2 DEEP:2 UI/BROWSER:1; do
  cat=${pair%%:*}
  expected=${pair##*:}
  actual=$(category_rule_count "$cat")
  check "$cat: has exactly $expected rules entry(ies)" "$expected" "$actual"
done

# =============================================================================
# 2. Pinned active route per category rule (regression protection):
#    harness/model/effort exactly as documented in primary-policy.md and
#    README.md. Multi-candidate arrays are limited to the deliberate peer sets
#    for QUICK, ARCHITECTURE, and DEEP; semantic escalations and documented
#    overrides remain separate.
# =============================================================================
check_rule_use() { # <category> <rule-occurrence, for the message only> <aggregated-line-number> <harness> <model> <effort>
  # <aggregated-line-number> indexes category_field's own output, which is
  # every `use` entry from every rule sharing this category, concatenated
  # in document order - not an index local to one rule.
  local cat=$1 occ=$2 line_no=$3 h=$4 m=$5 e=$6 line
  line=$(category_field "$cat" use | sed -n "${line_no}p")
  check "$cat rule #$occ: use entry is $h/$m/$e" "$h	$m	$e" "$line"
}
check_array_length() { # <category> <rule-occurrence> <expected-length>
  local cat=$1 occ=$2 expected=$3 actual
  actual=$(category_rule_use_length "$cat" "$occ")
  check "$cat rule #$occ: use array has exactly $expected candidate(s)" "$expected" "$actual"
}
no_opus_in_array() { # <category> - checks every use array across all of
  # this category's rules at once (category_field aggregates them), since
  # the function cannot discriminate by rule occurrence.
  local cat=$1 models
  models=$(category_field "$cat" use | cut -f2)
  case $models in
    *opus*) fail "$cat: an opus model wrongly appears in a use array" ;;
    *) pass "$cat: no opus model appears in any use array" ;;
  esac
}

# QUICK: one rule, two genuinely interchangeable candidates.
check_array_length QUICK 1 2
check_rule_use QUICK 1 1 omp anthropic/claude-haiku-4-5 low
check_rule_use QUICK 1 2 omp openai-codex/gpt-5.6-luna low

# EXPLORE: two separate rules (ordinary, then harder-reasoning escalation).
check_array_length EXPLORE 1 1
check_array_length EXPLORE 2 1
check_rule_use EXPLORE 1 1 omp anthropic/claude-haiku-4-5 low
check_rule_use EXPLORE 2 2 omp anthropic/claude-sonnet-5 medium

# RESEARCH: two separate rules (default OMP, then Pi-tooling-better).
check_array_length RESEARCH 1 1
check_array_length RESEARCH 2 1
check_rule_use RESEARCH 1 1 omp anthropic/claude-sonnet-5 medium
check_rule_use RESEARCH 2 2 pi openai-codex/gpt-5.6-sol medium

# REVIEW: one rule, one candidate.
check_array_length REVIEW 1 1
check_rule_use REVIEW 1 1 omp anthropic/claude-sonnet-5 medium

# ARCHITECTURE: Astra and Fable 5.1 are active xhigh peers.
check_array_length ARCHITECTURE 1 2
check_rule_use ARCHITECTURE 1 1 pi openai-codex/gpt-6-astra xhigh
check_rule_use ARCHITECTURE 1 2 omp anthropic/claude-fable-5-1 xhigh
no_opus_in_array ARCHITECTURE
arch_why=$(category_field ARCHITECTURE why)
contains 'ARCHITECTURE: why-text names Fable 5.1' "$arch_why" 'anthropic/claude-fable-5-1'

# TENTH-MAN: one rule, Astra only, with Opus as a prose-only override.
check_array_length TENTH-MAN 1 1
check_rule_use TENTH-MAN 1 1 pi openai-codex/gpt-6-astra xhigh
no_opus_in_array TENTH-MAN
tenthman_why=$(category_field TENTH-MAN why)
contains 'TENTH-MAN: Opus is documented as an override in why-text' "$(printf '%s' "$tenthman_why" | tr '[:upper:]' '[:lower:]')" 'opus'

# IMPLEMENT: one rule, one candidate.
check_array_length IMPLEMENT 1 1
check_rule_use IMPLEMENT 1 1 omp anthropic/claude-sonnet-5 medium

# IMPLEMENT-LARGE: two separate rules (ordinary broad, then the
# sustained-execution escalation to Opus - a real rule, unlike TENTH-MAN's
# prose-only Opus override).
check_array_length IMPLEMENT-LARGE 1 1
check_array_length IMPLEMENT-LARGE 2 1
check_rule_use IMPLEMENT-LARGE 1 1 omp anthropic/claude-sonnet-5 high
check_rule_use IMPLEMENT-LARGE 2 2 omp anthropic/claude-opus-5 high

# DEEP: diagnosis and implementation each pair Fable 5.1 with Astra at xhigh.
check_array_length DEEP 1 2
check_array_length DEEP 2 2
check_rule_use DEEP 1 1 omp anthropic/claude-fable-5-1 xhigh
check_rule_use DEEP 1 2 pi openai-codex/gpt-6-astra xhigh
check_rule_use DEEP 2 3 omp anthropic/claude-fable-5-1 xhigh
check_rule_use DEEP 2 4 omp openai-codex/gpt-6-astra xhigh
no_opus_in_array DEEP
deep_why=$(category_field DEEP why)
contains 'DEEP: why-text names Fable 5.1' "$deep_why" 'anthropic/claude-fable-5-1'

# UI/BROWSER: one rule, one candidate.
check_array_length UI/BROWSER 1 1
check_rule_use UI/BROWSER 1 1 omp anthropic/claude-sonnet-5 high

default_line=$(default_tuple)
check 'DEFAULT: catch-all route is omp/anthropic/claude-sonnet-5/medium' "omp	anthropic/claude-sonnet-5	medium" "$default_line"

# =============================================================================
# 3. Roles referenced by name stay within the three that exist
#    (senior-fullstack is the unmarked default and is never named in the
#    JSON; architecture and tenth-man are named explicitly in their own
#    category's "when" text, never elsewhere).
# =============================================================================
arch_when=$(category_field ARCHITECTURE when)
contains 'ARCHITECTURE names role architecture' "$arch_when" 'role architecture'
tenthman_when=$(category_field TENTH-MAN when)
contains 'TENTH-MAN names role tenth-man' "$tenthman_when" 'role tenth-man'
for cat in QUICK EXPLORE RESEARCH REVIEW IMPLEMENT IMPLEMENT-LARGE DEEP UI/BROWSER; do
  when=$(category_field "$cat" when)
  case $when in
    *"role architecture"*|*"role tenth-man"*)
      fail "$cat: when-text wrongly names a role reserved for ARCHITECTURE/TENTH-MAN"
      ;;
    *) pass "$cat: when-text does not claim the architecture/tenth-man role" ;;
  esac
done

# =============================================================================
# 4. Collision disambiguation: the specific sentence that resolves every
#    named adjacent-category pair is present in the owning category's own
#    when/why text (combined, since a couple of these distinctions live in
#    "why" rather than "when"). Ten pairs, checked in both directions.
# =============================================================================
collision_check() { # <category> <required substring> <pair label>
  local cat=$1 phrase=$2 label=$3 when why combined
  when=$(category_field "$cat" when)
  why=$(category_field "$cat" why)
  combined="$when $why"
  contains "$label: $cat's when/why resolves toward the neighbor" "$combined" "$phrase"
}

collision_check QUICK           'IMPLEMENT instead, not QUICK'    'QUICK/IMPLEMENT'
collision_check IMPLEMENT       'that is QUICK instead'           'QUICK/IMPLEMENT'
collision_check EXPLORE         'that is RESEARCH instead'        'EXPLORE/RESEARCH'
collision_check RESEARCH        'that is EXPLORE instead'         'EXPLORE/RESEARCH'
collision_check RESEARCH        'that is REVIEW instead'          'RESEARCH/REVIEW'
collision_check REVIEW          'that is RESEARCH instead'        'RESEARCH/REVIEW'
collision_check REVIEW          'that is TENTH-MAN instead'       'REVIEW/TENTH-MAN'
collision_check TENTH-MAN       'that is REVIEW instead'          'REVIEW/TENTH-MAN'
collision_check REVIEW          'that is ARCHITECTURE instead'    'REVIEW/ARCHITECTURE'
collision_check ARCHITECTURE    'that is REVIEW instead'          'REVIEW/ARCHITECTURE'
collision_check ARCHITECTURE    'that is DEEP instead'            'ARCHITECTURE/DEEP'
collision_check DEEP            'that is ARCHITECTURE instead'    'ARCHITECTURE/DEEP'
collision_check IMPLEMENT       'that is IMPLEMENT-LARGE instead' 'IMPLEMENT/IMPLEMENT-LARGE'
collision_check IMPLEMENT-LARGE 'that is IMPLEMENT instead'       'IMPLEMENT/IMPLEMENT-LARGE'
collision_check IMPLEMENT-LARGE 'that is DEEP instead'            'IMPLEMENT-LARGE/DEEP'
collision_check DEEP            'that is IMPLEMENT-LARGE instead' 'IMPLEMENT-LARGE/DEEP'
collision_check IMPLEMENT       'that is UI/BROWSER instead'      'IMPLEMENT/UI-BROWSER'
collision_check UI/BROWSER      'that is IMPLEMENT instead'       'IMPLEMENT/UI-BROWSER'
collision_check DEEP            'that is TENTH-MAN instead'       'DEEP/TENTH-MAN'
collision_check TENTH-MAN       'TENTH-MAN versus DEEP'           'DEEP/TENTH-MAN'

# =============================================================================
# 5. Representative example intents, one per category, plus boundary/
#    ambiguity fixtures for every named collision. These are reference
#    fixtures for a human or captain session to sanity-check dispatch
#    against - see the header comment for why no classifier runs them here.
#    The only mechanical assertion is that every category a fixture claims
#    actually exists in the parsed taxonomy, so a renamed/removed category
#    cannot leave a stale fixture silently pointing nowhere.
# =============================================================================
FIXTURES='
QUICK|Rename this local variable across the one file that uses it.
EXPLORE|Find every caller of fm_project_mode_resolve in this repository.
RESEARCH|Summarize how the upstream herdr CLI defines its --json status schema.
REVIEW|Review this diff for correctness and maintainability before it merges.
ARCHITECTURE|Decide how project registration should be modeled going forward.
TENTH-MAN|Challenge the completion claim on the routing-taxonomy branch before merge.
IMPLEMENT|Fix the bug where fm doctor mis-reports staleness for one in-flight task.
IMPLEMENT-LARGE|Rework the doctor JSON schema across every check emitter, direction already agreed.
DEEP|Diagnose an intermittent race in the wake-queue that only reproduces under load.
UI/BROWSER|Fix the login form so a validation error actually displays to the user.
'

BOUNDARY_FIXTURES='
QUICK~IMPLEMENT~A one-line config edit that also requires deciding a new default value.
EXPLORE~RESEARCH~Find out how our retry logic compares to the upstream library it wraps.
RESEARCH~REVIEW~Read the proposed dependency upgrade PR and judge whether to merge it.
REVIEW~TENTH-MAN~An independent adversarial pass on a plan nobody has challenged yet.
REVIEW~ARCHITECTURE~A proposal review that turns out to hinge on a module boundary decision.
ARCHITECTURE~DEEP~A production incident whose root cause looks like a wrong service boundary.
IMPLEMENT~IMPLEMENT-LARGE~A refactor that started in one file and now touches a dozen call sites.
IMPLEMENT-LARGE~DEEP~A broad migration that keeps failing for a reason nobody has found yet.
IMPLEMENT~UI/BROWSER~A backend fix whose only symptom is a broken form validation message.
DEEP~TENTH-MAN~A stress test of whether a hard bug diagnosis is actually correct.
'

fixture_categories_valid() { # <fixtures-block> <label>
  local block=$1 label=$2 cat ok=1
  while IFS='|' read -r cat _intent; do
    [ -n "$cat" ] || continue
    if printf '%s\n' "$actual_categories" | grep -qFx "$cat"; then :; else
      fail "$label: fixture names unknown category '$cat'"; ok=0
    fi
  done <<EOF
$block
EOF
  [ "$ok" -eq 1 ] && pass "$label: every fixture category name matches a real configured category"
}

boundary_categories_valid() { # <boundary-fixtures-block>
  local winner other ok=1
  while IFS='~' read -r winner other _intent; do
    [ -n "$winner" ] || continue
    for cat in "$winner" "$other"; do
      if printf '%s\n' "$actual_categories" | grep -qFx "$cat"; then :; else
        fail "boundary fixtures: names unknown category '$cat'"; ok=0
      fi
    done
  done <<EOF
$BOUNDARY_FIXTURES
EOF
  [ "$ok" -eq 1 ] && pass 'boundary fixtures: every winner/neighbor category matches a real configured category'
}

fixture_count=$(printf '%s\n' "$FIXTURES" | grep -c '|')
check '11 representative example intents: one per category' 10 "$fixture_count"
fixture_categories_valid "$FIXTURES" 'representative fixtures'

boundary_count=$(printf '%s\n' "$BOUNDARY_FIXTURES" | grep -c '~')
check 'boundary/ambiguity fixtures: one per named collision' 10 "$boundary_count"
boundary_categories_valid "$BOUNDARY_FIXTURES"

# =============================================================================
# 6. Retired fast-tier codex lane (formerly openai-codex/gpt-5.3-codex-spark):
#    zero active references anywhere in the tracked repository except this
#    file's own check below, which must name the literal string to search
#    for it - the same self-reference any "no banned string" check has, so
#    it is excluded from the scan by path rather than required to avoid the
#    word in its own comments. Nothing else in the tracked tree, including
#    README.md and primary-policy.md, keeps even a retirement note that
#    spells out the model ID: it was dropped for good, not reworded into a
#    historical mention.
# =============================================================================
RETIRED_MODEL='openai-codex/gpt-5.3-codex-spark'
SELF_PATH=tests/routing-taxonomy.sh
if command -v git >/dev/null 2>&1 && git -C "$CONFIG_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  retired_hits=$(git -C "$CONFIG_ROOT" ls-files -z -- ":!$SELF_PATH" \
    | xargs -0 grep -il 'spark' 2>/dev/null | wc -l | tr -d ' ')
  check 'zero tracked files (besides this one) mention Spark in any form' 0 "$retired_hits"
else
  pass 'retired-model repository scan: skipped (no git available)'
fi

crew_retired=$(grep -Fic "$RETIRED_MODEL" "$CREW_DISPATCH" 2>/dev/null || true)
check 'crew-dispatch.json itself has zero references to the retired fast-tier codex model' 0 "${crew_retired:-0}"

printf '\nROUTING TAXONOMY TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
