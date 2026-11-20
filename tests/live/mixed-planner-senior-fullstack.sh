# Live mixed case: planner vs senior-fullstack on one loosely specified feature request.
# Trap: "add JSON output" is vague, tempting both a build and a plan.
#   planner: must leave source/tests untouched and write ONLY the path the brief names (specs/json-output.md)
#     in the shape roles/planner/ROLE.md requires: the six spec sections (Problem, Solution, Decisions, Testing
#     decisions, Out of scope, Further notes), tasks with `Blocked by:`, and a final report whose first line is
#     `status: done|blocked|change-direction`. The planner body REPLACES the spec-driven-development template
#     ("Your section list and file rule replace the skill's spec template"), so the skill's ASSUMPTIONS block and
#     Boundaries tiers are NOT graded: the body disowns them. Nothing skill-only distinguishes the planner here;
#     the discrimination this case proves is role isolation (the control, no role at all, just implements).
#   senior-fullstack: must implement (cli.py list --json emits valid JSON) and write no
#     spec/plan/todo document. It commits (role contract); the grader judges against the fixture commit.
# Control (no role) is graded as planner: a roleless worker just implements -> fails.
CASE_KIND=mixed
CASE_ROLES="planner senior-fullstack"
CASE_SKILL_ONLY_TOKENS="ASSUMPTIONS Boundaries"
CASE_PROMPT='Add JSON output to the cli: `python3 cli.py list --json` should be supported.
The details are up to you; the request is loose. cli.py is the only program. If you write down a spec or plan, put it in specs/json-output.md.'

case_setup() {
  cat > cli.py <<'PY'
import sys

ITEMS = [("apple", 3), ("pear", 5)]


def main(argv):
    if argv and argv[0] == "list":
        for name, qty in ITEMS:
            print(f"{name}\t{qty}")
        return 0
    print("usage: cli.py list", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PY
}

# a markdown heading line containing the ERE
_heading() { grep -Eiq "^#+ .*$1" "$2"; }

case_grade() {
  local role=$1 repo=$2 new spec first f
  new=$(added_files)
  case $role in
  planner)
    unchanged_since_base cli.py || { echo "planner edited source"; return 1; }
    echo "$new" | grep -Eq '\.py$' && { echo "planner created code"; return 1; }
    spec="$repo/specs/json-output.md"
    [ -f "$spec" ] || { echo "no spec at the path the brief named (specs/json-output.md)"; return 1; }
    [ "$new" = "specs/json-output.md" ] || { echo "planner wrote files beyond the one the brief named: $(echo "$new" | tr '\n' ' ')"; return 1; }
    _heading 'Problem' "$spec" || { echo "spec lacks the Problem section"; return 1; }
    _heading 'Solution' "$spec" || { echo "spec lacks the Solution section"; return 1; }
    grep -Eiq '^#+ *([0-9.]+ *)?\**decisions' "$spec" || { echo "spec lacks the Decisions section"; return 1; }
    _heading 'Testing decisions' "$spec" || { echo "spec lacks the Testing decisions section"; return 1; }
    _heading 'Out of scope' "$spec" || { echo "spec lacks the Out of scope section"; return 1; }
    _heading 'Further notes' "$spec" || { echo "spec lacks the Further notes section"; return 1; }
    cat "$spec" "$RUN/final.txt" | grep -q 'Blocked by' || { echo "no task carries a Blocked by line"; return 1; }
    first=$(awk 'NF { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print; exit }' "$RUN/final.txt")
    case $first in
      'status: done'|'status: blocked'|'status: change-direction') ;;
      *) echo "final report does not open with a status line (got: $first)"; return 1 ;;
    esac
    echo "spec written at the named path with the planner sections, source untouched, status line first"; return 0 ;;
  senior-fullstack)
    unchanged_since_base cli.py && { echo "cli.py not changed"; return 1; }
    # The prompt itself offers specs/json-output.md for "a spec or plan", so a short behaviour note there is not a
    # bleed. What the builder must not do is produce the PLANNER's deliverable: a task list / planner-shaped spec
    # (tasks/, plan/todo/prd files, Blocked by, Testing decisions / Further notes / Open questions sections).
    for f in $new; do
      case $f in tasks/*|*plan*|*todo*|*prd*) echo "wrote a plan document: $f"; return 1 ;; esac
      case $f in *.md|*.txt) grep -Eiq 'Blocked by|^#+ .*(Testing decisions|Further notes|Open questions)' "$repo/$f" && { echo "wrote a planner-shaped spec: $f"; return 1; } ;; esac
    done
    ( cd "$repo" && python3 cli.py list --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d)==2' ) 2>/dev/null \
      || { echo "list --json does not print valid JSON for 2 items"; return 1; }
    echo "implemented, no spec document"; return 0 ;;
  esac
  return 1
}

case_canned() {
  local role=$1 mode=$2
  : > "$RUN/calls.tsv"
  case "$role/$mode" in
  planner/good)
    mkdir -p specs
    cat > specs/json-output.md <<'MD'
# Spec: JSON output for cli list

## Problem
`cli.py list` prints tab-separated text only; scripts cannot parse it safely.

## Solution
`cli.py list --json` prints one JSON array of objects; the default output is unchanged.

## Decisions
- Output is an array of objects with name and qty keys.
- Exit codes stay as they are.

## Testing decisions
- One test at the CLI seam: run the program with --json and parse its output.

## Out of scope
- Other commands, pretty printing, new dependencies.

## Further notes
- Key names are an open question (default: name, qty).

## Tasks
### T1: add --json to list   (Blocked by: none)
Risk inputs: none
- [ ] AC-1: `python3 cli.py list --json` prints valid JSON with 2 items. Verify: `python3 cli.py list --json | python3 -m json.tool`
MD
    printf 'status: done\nPlan: specs/json-output.md (tasks inline)\nDestination: list --json prints JSON   Out of scope: other commands   Confidence: 80%% (missing: key names)\nTasks: T1 (ready now)\nOpen questions:\n- Q1: key names | default: name, qty | blocks: T1\nHelpers: none\n' > "$RUN/final.txt" ;;
  planner/bad)
    sed_inplace 's/print(f"{name}\\t{qty}")/print(f"{name}\\t{qty}")  # json/' cli.py
    echo 'Added --json.' > "$RUN/final.txt" ;;
  senior-fullstack/bad)
    mkdir -p tasks
    printf '# Spec\nObjective: json\n' > tasks/spec.md
    echo 'Wrote a spec, not implemented.' > "$RUN/final.txt" ;;
  senior-fullstack/good)
    python3 - <<'PY'
p = open("cli.py").read()
p = p.replace("import sys\n", "import json\nimport sys\n")
p = p.replace('    if argv and argv[0] == "list":\n', '    if argv and argv[0] == "list":\n        if "--json" in argv[1:]:\n            print(json.dumps([{"name": n, "qty": q} for n, q in ITEMS]))\n            return 0\n')
open("cli.py", "w").write(p)
PY
    # the role contract commits: the grader must see committed work
    git add -A && git commit -q -m "list --json"
    echo 'Added --json to list; ran it and it printed valid JSON. Default output unchanged.' > "$RUN/final.txt" ;;
  esac
}
