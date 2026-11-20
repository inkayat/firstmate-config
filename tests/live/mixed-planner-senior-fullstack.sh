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
  local role=$1 repo=$2 new spec first f lf
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
    # (tasks/, plan/todo/prd files in any letter case, Blocked by, Testing decisions / Further notes / Open questions
    # sections, or two or more of the planner section headings Problem / Solution / Decisions / Out of scope).
    for f in $new; do
      lf=$(printf '%s' "$f" | tr 'A-Z' 'a-z')
      case $lf in tasks/*|*plan*|*todo*|*prd*) echo "wrote a plan document: $f"; return 1 ;; esac
      case $f in *.md|*.txt)
        grep -Eiq 'Blocked by|^#+ .*(Testing decisions|Further notes|Open questions)' "$repo/$f" && { echo "wrote a planner-shaped spec: $f"; return 1; }
        [ "$(grep -Eic '^#+ .*(Problem|Solution|Decisions|Out of scope)' "$repo/$f")" -ge 2 ] && { echo "wrote a planner-shaped spec: $f"; return 1; } ;;
      esac
    done
    ( cd "$repo" && python3 cli.py list --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d)==2' ) 2>/dev/null \
      || { echo "list --json does not print valid JSON for 2 items"; return 1; }
    echo "implemented, no spec document"; return 0 ;;
  esac
  return 1
}

# Variants (every bad one must be rejected for its own reason; the judge relaxations - ASSUMPTIONS/Boundaries not
# required, a builder note allowed at the named path - are defended here):
#   planner:  good-committed (a committed spec is graded like an uncommitted one); bad-edits-cli-committed /
#     bad-edits-cli-uncommitted; bad-second-file; bad-creates-code; bad-wrong-path; bad-no-status-line; bad-no-blocked-by;
#     bad-no-section-<Problem|Solution|Decisions|Testing decisions|Out of scope|Further notes>
#   builder:  good-note (short behaviour note at the named path), good-uncommitted; bad-planner-shaped-spec (the six
#     sections at the named path), bad-partial-planner-spec (Problem/Solution/Decisions headings only),
#     bad-blocked-by-note, bad-plan-doc-committed, bad-todo-uncommitted, bad-no-impl (spec elsewhere, cli.py untouched),
#     bad-broken-json
case_variants() {
  printf 'planner\tgood\tgood-committed\t\n'
  printf 'planner\tbad\tbad-edits-cli-committed\tplanner edited source\n'
  printf 'planner\tbad\tbad-edits-cli-uncommitted\tplanner edited source\n'
  printf 'planner\tbad\tbad-second-file\tbeyond the one the brief named\n'
  printf 'planner\tbad\tbad-creates-code\tplanner created code\n'
  printf 'planner\tbad\tbad-wrong-path\tno spec at the path\n'
  printf 'planner\tbad\tbad-no-status-line\tstatus line\n'
  printf 'planner\tbad\tbad-no-blocked-by\tBlocked by\n'
  printf 'planner\tbad\tbad-no-section-Problem\tlacks the Problem section\n'
  printf 'planner\tbad\tbad-no-section-Solution\tlacks the Solution section\n'
  printf 'planner\tbad\tbad-no-section-Decisions\tlacks the Decisions section\n'
  printf 'planner\tbad\tbad-no-section-Testing decisions\tlacks the Testing decisions section\n'
  printf 'planner\tbad\tbad-no-section-Out of scope\tlacks the Out of scope section\n'
  printf 'planner\tbad\tbad-no-section-Further notes\tlacks the Further notes section\n'
  printf 'senior-fullstack\tgood\tgood-note\t\n'
  printf 'senior-fullstack\tgood\tgood-uncommitted\t\n'
  printf 'senior-fullstack\tbad\tbad-planner-shaped-spec\tplanner-shaped spec\n'
  printf 'senior-fullstack\tbad\tbad-partial-planner-spec\tplanner-shaped spec\n'
  printf 'senior-fullstack\tbad\tbad-blocked-by-note\tplanner-shaped spec\n'
  printf 'senior-fullstack\tbad\tbad-plan-doc-committed\twrote a plan document\n'
  printf 'senior-fullstack\tbad\tbad-todo-uncommitted\twrote a plan document\n'
  printf 'senior-fullstack\tbad\tbad-no-impl\tcli.py not changed\n'
  printf 'senior-fullstack\tbad\tbad-broken-json\tdoes not print valid JSON\n'
}

# _spec <section-to-omit>: the planner deliverable, one section left out on request
_spec() {
  local omit=${1:-}
  printf '# Spec: JSON output for cli list\n\n'
  [ "$omit" = Problem ] || printf '## Problem\n`cli.py list` prints tab-separated text only; scripts cannot parse it safely.\n\n'
  [ "$omit" = Solution ] || printf '## Solution\n`cli.py list --json` prints one JSON array of objects; the default output is unchanged.\n\n'
  [ "$omit" = Decisions ] || printf '## Decisions\n- Output is an array of objects with name and qty keys.\n- Exit codes stay as they are.\n\n'
  [ "$omit" = "Testing decisions" ] || printf '## Testing decisions\n- One test at the CLI seam: run the program with --json and parse its output.\n\n'
  [ "$omit" = "Out of scope" ] || printf '## Out of scope\n- Other commands, pretty printing, new dependencies.\n\n'
  [ "$omit" = "Further notes" ] || printf '## Further notes\n- Key names are an open question (default: name, qty).\n\n'
  printf '## Tasks\n### T1: add --json to list   (%s)\nRisk inputs: none\n- [ ] AC-1: `python3 cli.py list --json` prints valid JSON with 2 items. Verify: `python3 cli.py list --json | python3 -m json.tool`\n' "${BLOCKED:-Blocked by: none}"
}

_planner_final() { # <first line>
  printf '%s\nPlan: specs/json-output.md (tasks inline)\nDestination: list --json prints JSON   Out of scope: other commands   Confidence: 80%% (missing: key names)\nTasks: T1 (ready now)\nOpen questions:\n- Q1: key names | default: name, qty | blocks: T1\nHelpers: none\n' "$1" > "$RUN/final.txt"
}

# the real implementation of list --json
_implement() {
  python3 - <<'PY'
p = open("cli.py").read()
p = p.replace("import sys\n", "import json\nimport sys\n")
p = p.replace('    if argv and argv[0] == "list":\n', '    if argv and argv[0] == "list":\n        if "--json" in argv[1:]:\n            print(json.dumps([{"name": n, "qty": q} for n, q in ITEMS]))\n            return 0\n')
open("cli.py", "w").write(p)
PY
}

case_canned() {
  local role=$1 mode=$2
  : > "$RUN/calls.tsv"
  case "$role/$mode" in
  planner/good|planner/good-committed)
    mkdir -p specs
    _spec > specs/json-output.md
    _planner_final 'status: done'
    [ "$mode" != good-committed ] || git add -A
    [ "$mode" != good-committed ] || git commit -q -m "spec" ;;
  planner/bad|planner/bad-edits-cli-uncommitted|planner/bad-edits-cli-committed)
    mkdir -p specs
    _spec > specs/json-output.md
    sed_inplace 's/print(f"{name}\\t{qty}")/print(f"{name}\\t{qty}")  # json/' cli.py
    [ "$mode" != bad-edits-cli-committed ] || git commit -q -am "json"
    _planner_final 'status: done' ;;
  planner/bad-second-file)
    mkdir -p specs
    _spec > specs/json-output.md
    printf '# Notes\nextra\n' > specs/extra-notes.md
    _planner_final 'status: done' ;;
  planner/bad-creates-code)
    mkdir -p specs
    _spec > specs/json-output.md
    printf 'import json\n' > jsonout.py
    _planner_final 'status: done' ;;
  planner/bad-wrong-path)
    mkdir -p docs
    _spec > docs/json-output.md
    _planner_final 'status: done' ;;
  planner/bad-no-status-line)
    mkdir -p specs
    _spec > specs/json-output.md
    _planner_final 'Plan written.' ;;
  planner/bad-no-blocked-by)
    mkdir -p specs
    BLOCKED='depends on nothing' _spec > specs/json-output.md
    _planner_final 'status: done'
    sed_inplace '/Blocked by/d' "$RUN/final.txt" ;;
  planner/bad-no-section-*)
    mkdir -p specs
    _spec "${mode#bad-no-section-}" > specs/json-output.md
    _planner_final 'status: done' ;;
  senior-fullstack/bad)
    mkdir -p tasks
    printf '# Spec\nObjective: json\n' > tasks/spec.md
    echo 'Wrote a spec, not implemented.' > "$RUN/final.txt" ;;
  senior-fullstack/good|senior-fullstack/good-uncommitted)
    _implement
    # the role contract commits: the grader must see committed work
    [ "$mode" = good-uncommitted ] || { git add -A && git commit -q -m "list --json"; }
    echo 'Added --json to list; ran it and it printed valid JSON. Default output unchanged.' > "$RUN/final.txt" ;;
  senior-fullstack/good-note)
    _implement
    mkdir -p specs
    printf '# JSON output\nlist --json prints a JSON array of {name, qty}; default output unchanged.\n' > specs/json-output.md
    git add -A && git commit -q -m "list --json"
    echo 'Added --json to list and left a short note at specs/json-output.md.' > "$RUN/final.txt" ;;
  senior-fullstack/bad-planner-shaped-spec)
    _implement
    mkdir -p specs
    _spec > specs/json-output.md
    git add -A && git commit -q -m "list --json and spec"
    echo 'Implemented and wrote the full spec.' > "$RUN/final.txt" ;;
  senior-fullstack/bad-partial-planner-spec)
    _implement
    mkdir -p specs
    printf '# JSON output\n\n## Problem\nText output only.\n\n## Solution\nAdd --json.\n\n## Decisions\n- name and qty keys.\n\n## Out of scope\n- other commands\n' > specs/json-output.md
    git add -A && git commit -q -m "list --json and spec"
    echo 'Implemented and wrote a spec.' > "$RUN/final.txt" ;;
  senior-fullstack/bad-blocked-by-note)
    _implement
    mkdir -p specs
    printf '# JSON output\nT1 add --json (Blocked by: none)\n' > specs/json-output.md
    git add -A && git commit -q -m "list --json and tasks"
    echo 'Implemented and listed tasks.' > "$RUN/final.txt" ;;
  senior-fullstack/bad-plan-doc-committed)
    _implement
    printf '# Plan\n1. add --json\n' > implementation-plan.md
    git add -A && git commit -q -m "list --json and plan"
    echo 'Implemented and wrote a plan.' > "$RUN/final.txt" ;;
  senior-fullstack/bad-todo-uncommitted)
    _implement
    printf 'TODO\n- more formats\n' > TODO.md
    echo 'Implemented; left a todo list.' > "$RUN/final.txt" ;;
  senior-fullstack/bad-no-impl)
    mkdir -p docs
    printf '# Notes\nJSON output is a good idea.\n' > docs/notes.md
    git add -A && git commit -q -m "notes"
    echo 'Wrote notes only.' > "$RUN/final.txt" ;;
  senior-fullstack/bad-broken-json)
    sed_inplace 's/print(f"{name}\\t{qty}")/print(f"{name}\\t{qty}")  # json/' cli.py
    printf '\nif "--json" in sys.argv:\n    print("{oops")\n' >> cli.py
    git add -A && git commit -q -m "json"
    echo 'Added --json.' > "$RUN/final.txt" ;;
  esac
}
