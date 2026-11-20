#!/usr/bin/env bash
# roles.sh - offline automation for role-only delegation: the Captain chooses a
# role, and the role's frontmatter `autoloadSkills` is the only skill source
# (firstmate/primary-policy.md sections 2, 4, 5). No model, network or real home.
#
#   1. every role's frontmatter parses and its autoloadSkills pass the lint
#      (path resolves, no duplicate, at most three, no orphaned repo-authored skill,
#      operator skills not autoloaded, policy section 4 lists every role)
#   2. the lint really fails on each defect (negative fixtures)
#   3. bin/fm-role-handoff yields the ROLE.md and exactly the role's skills;
#      skill-less roles yield none
#   4. the Captain-side documents contain no skill-selection instruction
#   5. install.sh --verify knows every role, including the new ones
# shellcheck source=tests/fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixture.sh"

POLICY="$FIX_SRC/firstmate/primary-policy.md"
HANDOFF="$FIX_SRC/bin/fm-role-handoff"
MAX_SKILLS=3
ROLES_ROOT="$FIX_SRC/roles"
# shellcheck source=firstmate/fm-roles-lib.sh
. "$FIX_SRC/firstmate/fm-roles-lib.sh"

# local_skills <config-root> - repo-authored skills (skills/<name>/SKILL.md).
local_skills() {
  local d
  for d in "$1"/skills/*/; do [ -f "$d/SKILL.md" ] && basename "$d"; done
}

# managed_skills <config-root> - repo-authored skills plus external.lock names.
managed_skills() {
  local_skills "$1"
  awk -F'\t' '/^[^#]/ && NF >= 5 {print $5}' "$1/skills/external.lock" 2>/dev/null
}

# lint_roles <config-root> <policy> - one "LINT: ..." line per defect.
lint_roles() {
  local root=$1 policy=$2 ROLES_ROOT="$1/roles" role skills s managed operator used='' n
  managed=$(managed_skills "$root" | sort -u)
  operator=$(sed -n 's/^Operator skills[^:]*:[[:space:]]*//p' "$policy" | grep -o '`[^`]*`' | tr -d '`')
  for role in $(role_names); do
    if ! skills=$(role_autoload_skills "$role" 2>&1); then printf 'LINT: role %s: %s\n' "$role" "$skills"; continue; fi
    [ "$(role_frontmatter_name "$role")" = "fm-$role" ] || printf 'LINT: role %s: frontmatter name is not fm-%s\n' "$role" "$role"
    role_frontmatter "$ROLES_ROOT/$role/ROLE.md" | grep -q '^description:[[:space:]]*[^[:space:]]' || printf 'LINT: role %s: no description\n' "$role"
    n=0
    for s in $skills; do
      n=$((n + 1))
      printf '%s\n' "$managed" | grep -qx -- "$s" || printf 'LINT: role %s: autoloaded skill %s is not a managed skill (missing path)\n' "$role" "$s"
      [ "$(printf '%s\n' "$skills" | grep -cx -- "$s")" -le 1 ] || printf 'LINT: role %s: duplicate autoloaded skill %s\n' "$role" "$s"
      printf '%s\n' "$operator" | grep -qx -- "$s" && printf 'LINT: role %s: autoloads operator skill %s\n' "$role" "$s"
      used="$used $s"
    done
    [ "$n" -le "$MAX_SKILLS" ] || printf 'LINT: role %s: %d autoloaded skills (max %d)\n' "$role" "$n" "$MAX_SKILLS"
    grep -q -- "^- \`$role\` -" "$policy" || printf 'LINT: role %s: not listed in policy section 4\n' "$role"
  done
  for s in $(local_skills "$root" | sort -u); do
    case " $used " in *" $s "*) continue ;; esac
    printf '%s\n' "$operator" | grep -qx -- "$s" || printf 'LINT: managed skill %s is autoloaded by no role and not an operator skill in the policy\n' "$s"
  done
  for s in $operator; do
    printf '%s\n' "$managed" | grep -qx -- "$s" || printf 'LINT: operator skill %s is not a managed skill\n' "$s"
  done
  sed -n 's/^- `\([a-z0-9-]*\)` -.*/\1/p' "$policy" | while read -r role; do
    [ -f "$root/roles/$role/ROLE.md" ] || printf 'LINT: policy lists role %s, which has no ROLE.md\n' "$role"
  done
}

# --- 1. the real repository passes the lint --------------------------------------
real=$(lint_roles "$FIX_SRC" "$POLICY")
check 'role lint: every role and skill reference in this repository is clean' "$real" ''
check 'role frontmatter: all roles found' "$(role_names | wc -l | tr -d ' ')" "$(ls -d "$FIX_SRC"/roles/*/ | wc -l | tr -d ' ')"

# --- 2. the lint fails on each defect ---------------------------------------------
LINT_FIX="$T/lint-fixture"
fresh_fixture() {
  rm -rf "$LINT_FIX"; mkdir -p "$LINT_FIX/skills/local-skill" "$LINT_FIX/roles/alpha" "$LINT_FIX/firstmate"
  printf -- '---\nname: local-skill\ndescription: x\n---\n' > "$LINT_FIX/skills/local-skill/SKILL.md"
  printf '# lock\nfx:ext\trepo\tsha\tskills/ext-skill\text-skill\n' > "$LINT_FIX/skills/external.lock"
  printf -- '---\nname: fm-alpha\ndescription: "a"\nautoloadSkills:\n  - local-skill\n  - ext-skill\n---\n# alpha\n' > "$LINT_FIX/roles/alpha/ROLE.md"
  printf -- '- `alpha` - fixture\n\nOperator skills (Captain/operator only): `none-here`.\n' > "$LINT_FIX/firstmate/policy.md"
  sed -i 's/`none-here`/`local-op`/' "$LINT_FIX/firstmate/policy.md"
  mkdir -p "$LINT_FIX/skills/local-op"; printf -- '---\nname: local-op\n---\n' > "$LINT_FIX/skills/local-op/SKILL.md"
}
lint_fix() { lint_roles "$LINT_FIX" "$LINT_FIX/firstmate/policy.md"; }
fresh_fixture
check 'lint fixture: a clean fixture passes' "$(lint_fix)" ''
fresh_fixture; sed -i 's/  - ext-skill/  - ghost-skill/' "$LINT_FIX/roles/alpha/ROLE.md"
has 'lint fails on an autoloaded skill whose path does not exist' "$(lint_fix)" 'ghost-skill is not a managed skill'
fresh_fixture; sed -i 's/  - ext-skill/  - local-skill/' "$LINT_FIX/roles/alpha/ROLE.md"
has 'lint fails on a duplicate autoloaded skill' "$(lint_fix)" 'duplicate autoloaded skill local-skill'
fresh_fixture; mkdir -p "$LINT_FIX/skills/orphan"; printf -- '---\nname: orphan\n---\n' > "$LINT_FIX/skills/orphan/SKILL.md"
has 'lint fails on a managed skill no role autoloads and the policy does not list' "$(lint_fix)" 'orphan is autoloaded by no role'
fresh_fixture; printf 'fx:spare\trepo\tsha\tskills/spare\tspare-skill\n' >> "$LINT_FIX/skills/external.lock"
check 'lint allows an external pin that no role autoloads' "$(lint_fix)" ''
fresh_fixture; sed -i 's/  - ext-skill/  - ext-skill\n  - local-op\n  - x1/' "$LINT_FIX/roles/alpha/ROLE.md"
has 'lint fails when a role carries an operator skill' "$(lint_fix)" 'autoloads operator skill local-op'
fresh_fixture; sed -i 's/  - ext-skill/  - ext-skill\n  - a\n  - b/' "$LINT_FIX/roles/alpha/ROLE.md"
has 'lint fails above the three-skill budget' "$(lint_fix)" '4 autoloaded skills (max 3)'
fresh_fixture; printf -- 'name: fm-alpha\n' > "$LINT_FIX/roles/alpha/ROLE.md"
has 'lint fails on a role without a closed frontmatter block' "$(lint_fix)" 'frontmatter is missing or not closed'
fresh_fixture; sed -i 's/^autoloadSkills:/autoloadSkills: local-skill/; /^  - /d' "$LINT_FIX/roles/alpha/ROLE.md"
has 'lint fails on a non-list autoloadSkills' "$(lint_fix)" 'not a plain block list'
fresh_fixture; mkdir -p "$LINT_FIX/roles/beta"; cp "$LINT_FIX/roles/alpha/ROLE.md" "$LINT_FIX/roles/beta/ROLE.md"
has 'lint fails on a role the policy does not list and whose name mismatches' "$(lint_fix)" 'role beta: not listed in policy section 4'
fresh_fixture; printf -- '- `alpha` - f\n- `ghost` - f\nOperator skills (x): `local-op`.\n' > "$LINT_FIX/firstmate/policy.md"
has 'lint fails on a policy role with no ROLE.md' "$(lint_fix)" 'policy lists role ghost'
fresh_fixture; sed -i 's/autoloadSkills:/autoloadSkills: []/; /^  - /d' "$LINT_FIX/roles/alpha/ROLE.md"
check 'a role with autoloadSkills: [] is valid and skill-less' "$(lint_roles "$LINT_FIX" "$LINT_FIX/firstmate/policy.md" | grep -v 'autoloaded by no role' || true)" ''

# --- 3. the handoff expansion yields exactly the role's skills -----------------------
export FM_CONFIG_ROOT="$FIX_SRC" FM_SKILLS_ROOT="$T/skills-root"
SKILL_LESS=''
for role in $(role_names); do
  want=$(role_autoload_skills "$role") || want=''
  out=$("$HANDOFF" "$role" 2>&1); rc=$?
  check "handoff $role: exits 0" "$rc" 0
  has "handoff $role: names the role" "$out" "Assigned role: $role"
  has "handoff $role: names the absolute ROLE.md with a read-and-apply requirement" "$out" "Role source:
  $FIX_SRC/roles/$role/ROLE.md
Requirement:
  Read and apply this role file in full"
  got=$(printf '%s\n' "$out" | sed -n 's#^  '"$T"'/skills-root/\(.*\)/SKILL\.md$#\1#p')
  check "handoff $role: skill paths are exactly the role's autoloadSkills" "$got" "$want"
  check "handoff $role: --skills prints the same list" "$("$HANDOFF" --skills "$role")" "$want"
  check "handoff $role: nothing but ROLE.md and its skills is a path" \
    "$(printf '%s\n' "$out" | grep -c '^  /')" "$(( $(printf '%s' "$want" | grep -c .) + 1 ))"
  if [ -z "$want" ]; then
    SKILL_LESS="$SKILL_LESS $role"
    has "handoff $role: a skill-less role says so" "$out" 'Role skills:
  none'
    lacks "handoff $role: a skill-less role hands over no SKILL.md" "$out" 'SKILL.md'
  fi
done
check 'skill-less roles are exactly scout, chore, tenth-man and risk-classifier' "$(printf '%s' "$SKILL_LESS" | tr ' ' '\n' | grep . | sort | tr '\n' ' ')" 'chore risk-classifier scout tenth-man '
check 'chore, the neutral role, expands to no skill' "$("$HANDOFF" --skills chore)" ''
out=$("$HANDOFF" no-such-role 2>&1); rc=$?
check 'handoff for an unknown role fails' "$rc" 1
has 'handoff for an unknown role says so' "$out" 'no such role'
out=$("$HANDOFF" 'Bad Role' 2>&1); rc=$?
check 'handoff rejects a malformed role name' "$rc" 1
check 'handoff --roles lists every role' "$("$HANDOFF" --roles | sort | tr '\n' ' ')" "$(ls -d "$FIX_SRC"/roles/*/ | xargs -n1 basename | sort | tr '\n' ' ')"
# the inventory: the skills each role carries (README.md "Context and skills" records why; section 6 checks it)
inventory() { # <role> -> its autoloadSkills, space separated
  case $1 in
    senior-fullstack) echo 'test-driven-development ponytail verification-before-completion' ;;
    test-engineer) echo 'test-driven-development principle-test-behavior-not-implementation' ;;
    refactorist) echo 'code-simplification verification-before-completion karpathy-guidelines' ;;
    perf-engineer) echo 'performance-optimization benchmark-checklist' ;;
    technical-writer) echo 'documentation-and-adrs' ;;
    lead) echo 'planning-and-task-breakdown verification-before-completion' ;;
    planner) echo 'spec-driven-development planning-and-task-breakdown be-ambitious' ;;
    architecture) echo 'api-and-interface-design codebase-design be-ambitious' ;;
    researcher) echo 'source-driven-development be-ambitious' ;;
    debugger) echo 'systematic-debugging' ;;
    qa|ui-qa|release-engineer|finding-verifier) echo 'verification-before-completion' ;;
    code-reviewer) echo 'code-review-and-quality ponytail-review karpathy-guidelines' ;;
    security-engineer) echo 'security-and-hardening verification-before-completion' ;;
    improver) echo 'retro' ;;
    scout|chore|tenth-man|risk-classifier) echo '' ;;
    *) echo 'UNLISTED' ;;
  esac
}
for sel in $(role_names); do
  w=$(inventory "$sel")
  check "role $sel carries the skills the inventory assigned it" "$("$HANDOFF" --skills "$sel" | tr '\n' ' ' | sed 's/ $//')" "$w"
done
# karpathy-guidelines is for the refactoring and reviewing roles; senior-fullstack keeps ponytail.
karpathy_roles=
for role in $("$HANDOFF" --roles | sort); do
  "$HANDOFF" --skills "$role" | grep -qx karpathy-guidelines && karpathy_roles="$karpathy_roles $role"
done
check 'karpathy-guidelines is autoloaded by exactly the refactoring and reviewing roles' "$karpathy_roles" ' code-reviewer refactorist'

# --- 4. the Captain side contains no skill-selection instruction ------------------------
captain_docs="$POLICY $FIX_SRC/README.md $FIX_SRC/firstmate/captain.md $FIX_SRC/firstmate/crew-dispatch.json"
for phrase in 'independently selected' 'Selected shared worker skill' 'Required project skill' \
  'at most two workflow' 'skill budget' 'Select them; do not dump' 'Before choosing shared worker skills' \
  'Skills: <selected' 'selected skills' 'skill selection' 'Default skill'; do
  # shellcheck disable=SC2086
  hits=$(grep -n -F -- "$phrase" $captain_docs 2>/dev/null || true)
  check "captain docs carry no '$phrase' instruction" "$hits" ''
done
check 'crew-dispatch.json never mentions skills (rules choose route, not skills)' "$(grep -ci skill "$FIX_SRC/firstmate/crew-dispatch.json")" 0
has 'policy: the Captain handoff is the role handoff command' "$(cat "$POLICY")" 'bin/fm-role-handoff <role>'
has 'policy: skills belong to roles, not tasks' "$(cat "$POLICY")" 'Skills belong to roles, not to tasks.'
has 'policy: project-local skills are not selected by the Captain' "$(cat "$POLICY")" 'the Captain does not
   select them'
has 'policy: the trace Skills line is derived' "$(cat "$POLICY")" '`Skills` is derived, never chosen'
trace_skills_arg=$(bash "$FIX_SRC/tests/routing-trace.sh" check 2>&1 | head -1)
has 'trace check CLI takes no caller-supplied skill list' "$trace_skills_arg" '<trace-file> <harness> <model> <effort> [--brief'
lacks 'trace check CLI usage no longer offers a skills argument' "$trace_skills_arg" 'skills|none'

# --- 5. install.sh --verify knows every role ------------------------------------------------
make_world
fresh=$("$FMC/install.sh" --verify 2>&1)
for role in $(role_names); do
  has "verify on a fresh machine reports a missing link for fm-$role" "$fresh" "$HOME/.omp/agent/agents/fm-$role.md"
done
"$FMC/install.sh" > "$T/install.out" 2>&1
for role in $(role_names); do
  check "install links fm-$role to its ROLE.md" "$(readlink "$HOME/.omp/agent/agents/fm-$role.md" | sed 's#^.*/roles/#roles/#')" "roles/$role/ROLE.md"
done
check 'verify reports no drift after install, new roles included' "$("$FMC/install.sh" --verify 2>&1 | tail -1)" 'verify: 0 drift item(s), 0 failure(s)'
rm "$HOME/.omp/agent/agents/fm-planner.md" "$HOME/.omp/agent/agents/fm-chore.md"
drift=$("$FMC/install.sh" --verify 2>&1)
has 'verify reports the unlinked planner role as drift' "$drift" 'fm-planner.md'
has 'verify reports the unlinked chore role as drift' "$drift" 'fm-chore.md'
check 'verify counts exactly the two missing role links' "$(printf '%s\n' "$drift" | tail -1)" 'verify: 2 drift item(s), 0 failure(s)'

# --- 6. every role has the contract structure; its sub-agent section matches the manifest; the README table matches the frontmatter
HEADS='Working shape|Definition of done|Evidence|What to refuse|If you cannot finish|Sub-agents|Final report'
README_TEXT=$(cat "$FIX_SRC/README.md")
for role in $(role_names); do
  got=$(grep '^## ' "$ROLES_ROOT/$role/ROLE.md" | sed 's/^## //' | tr '\n' '|' | sed 's/|$//')
  check "role $role: the contract headings, in order" "$got" "$HEADS"
  want=$(jq -r --arg r "$role" '.roles[$r].spawns | map("fm-" + .) | sort | join(" ")' "$FIX_SRC/roles/manifest.json")
  sect=$(awk '/^## Sub-agents$/ {p = 1; next} /^## / && p {exit} p {print}' "$ROLES_ROOT/$role/ROLE.md")
  have=''
  for tok in $(printf '%s\n' "$sect" | grep -o 'fm-[a-z-]*' | sort -u); do
    role_file "${tok#fm-}" >/dev/null 2>&1 && have="$have $tok"
  done
  check "role $role: its Sub-agents section names exactly the roles the manifest lets it call" "$(printf '%s' "$have" | sed 's/^ //')" "$want"
  if [ -n "$want" ]; then
    has "role $role: a spawning role says helpers cannot start helpers" "$sect" 'cannot start helpers'
    has "role $role: ... and that a helper never publishes or merges" "$sect" 'never publishes'
  fi
  row=$(printf '%s\n' "$README_TEXT" | grep -m1 "^| \`$role\` |" || true)
  readme_skills=$(printf '%s\n' "$row" | awk -F'|' '{print $3}' | tr -d '`' | sed 's/^ *//; s/ *$//; s/, */ /g; s/^none$//')
  check "README role -> skills table row for $role equals its frontmatter autoloadSkills" "$readme_skills" "$("$HANDOFF" --skills "$role" | tr '\n' ' ' | sed 's/ $//')"
  [ -n "$row" ] && ok "README table has a row for $role" || bad "README table has no row for $role"
done
# the adopted external pins: each new pin is a managed skill with a real commit, never a branch
for pin in addy:performance addy:source-driven pstack:benchmark pstack:test-behavior pocock:retro pocock:codebase-design ambition:be-ambitious; do
  line=$(grep -m1 "^$pin	" "$FIX_SRC/skills/external.lock" || true)
  check "external.lock pins $pin by a full commit sha" "$(printf '%s' "$line" | awk -F'\t' '{print $3}' | grep -cE '^[0-9a-f]{40}$')" 1
done
check 'external.lock tracks no branch: every commit field is a 40-hex sha' "$(awk -F'\t' '/^[^#]/ && NF >= 5 {print $3}' "$FIX_SRC/skills/external.lock" | grep -cvE '^[0-9a-f]{40}$')" 0

finish
