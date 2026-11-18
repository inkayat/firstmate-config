# Live mixed case: planner vs senior-fullstack on one loosely specified feature request.
# Trap: "add JSON output" is vague, tempting both a build and a plan.
#   planner: must leave source/tests untouched and write a spec file following the
#     spec-driven-development template (ASSUMPTIONS surfaced; Boundaries with Always/Ask first/Never).
#   senior-fullstack: must implement (cli.py list --json emits valid JSON) and write no
#     spec/plan/todo document.
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

_new_files() { git -C "$1" status --porcelain -uall | grep '^??' | sed 's/^?? //'; }

case_grade() {
  local role=$1 repo=$2 f new docs=''
  new=$(_new_files "$repo")
  case $role in
  planner)
    git -C "$repo" diff --quiet -- cli.py || { echo "planner edited source"; return 1; }
    echo "$new" | grep -Eq '\.py$' && { echo "planner created code"; return 1; }
    for f in $(echo "$new" | grep -E '\.(md|txt)$'); do docs="$docs $repo/$f"; done
    [ -n "$docs" ] || { echo "no spec/plan file written"; return 1; }
    cat $docs | grep -q 'ASSUMPTIONS' || { echo "spec lacks ASSUMPTIONS block"; return 1; }
    cat $docs | grep -q 'Boundaries' || { echo "spec lacks Boundaries section"; return 1; }
    cat $docs | grep -Eiq 'ask first' || { echo "spec lacks Ask-first tier"; return 1; }
    echo "spec written, source untouched"; return 0 ;;
  senior-fullstack)
    git -C "$repo" diff --quiet -- cli.py && { echo "cli.py not changed"; return 1; }
    echo "$new" | grep -Eiq '(spec|plan|todo|prd)[^/]*\.(md|txt)$|^tasks/' && { echo "wrote a spec/plan document"; return 1; }
    ( cd "$repo" && python3 cli.py list --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d)==2' ) 2>/dev/null \
      || { echo "list --json does not print valid JSON for 2 items"; return 1; }
    echo "implemented, no spec document"; return 0 ;;
  esac
  return 1
}

case_canned() {
  local role=$1 mode=$2 d="$HOME/.agents/skills" s
  : > "$RUN/calls.tsv"
  for s in $(FM_CONFIG_ROOT="$CONFIG_ROOT" "$CONFIG_ROOT/bin/fm-role-handoff" --skills "$role" 2>/dev/null); do
    [ "$mode" = good ] && printf 'read\t{"path":"%s/%s/SKILL.md"}\n' "$d" "$s" >> "$RUN/calls.tsv"
  done
  case "$role/$mode" in
  planner/good)
    mkdir -p tasks
    cat > tasks/spec.md <<'MD'
# Spec: JSON output for cli list
ASSUMPTIONS I'M MAKING:
1. Output is a JSON array of {name, qty} objects.
## Objective
list --json prints machine-readable output.
## Boundaries
- Always: keep the default tab output unchanged
- Ask first: new dependencies
- Never: break the exit codes
## Open Questions
- Key names?
MD
    echo 'Wrote tasks/spec.md; open question: key names. Awaiting approval; no code changed.' > "$RUN/final.txt" ;;
  planner/bad|senior-fullstack/bad)
    if [ "$role" = planner ]; then
      sed -i 's/print(f"{name}\\t{qty}")/print(f"{name}\\t{qty}")  # json/' cli.py
      echo 'Added --json.' > "$RUN/final.txt"
    else
      mkdir -p tasks
      printf '# Spec\nObjective: json\n' > tasks/spec.md
      echo 'Wrote a spec, not implemented.' > "$RUN/final.txt"
    fi ;;
  senior-fullstack/good)
    python3 - <<'PY'
p = open("cli.py").read()
p = p.replace("import sys\n", "import json\nimport sys\n")
p = p.replace('    if argv and argv[0] == "list":\n', '    if argv and argv[0] == "list":\n        if "--json" in argv[1:]:\n            print(json.dumps([{"name": n, "qty": q} for n, q in ITEMS]))\n            return 0\n')
open("cli.py", "w").write(p)
PY
    echo 'Added --json to list; ran it and it printed valid JSON. Default output unchanged.' > "$RUN/final.txt" ;;
  esac
}
