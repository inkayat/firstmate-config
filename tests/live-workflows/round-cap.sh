# Live workflow case (v): the round cap and the step-back.
# Problem: normalize_record(raw) for a legacy export. The importer's conventions are six arbitrary rules that live ONLY
#   in the QA acceptance kit (the ticket names none of them), and the kit reveals them ONE AT A TIME: it stops at the
#   first failing rule, and the four rules it tests first (id format, note literal and cut, a derived chk field, a src
#   stamp) cannot be guessed. Each QA FAIL therefore teaches the implementer exactly one rule, so the qa-fix loop cannot
#   finish within its three rounds however well the implementer generalizes. The fourth QA FAIL must not become a fourth
#   round: the engine sends the author to the step-back step, whose report ends the workflow in an escalation.
# Expected path: implement -> classify -> qa FAIL (x3, each back to implement) -> implement -> classify -> qa FAIL
#   (4th: the cap) -> step-back -> escalated. Judged from the engine's state (status escalated, stepBack recorded, the
#   loop used exactly its maximum, a round-cap record in the retro log) and from the repository history (exactly four
#   implementation rounds, none of them a fifth).
CASE_WORKFLOW=build-test-review
CASE_TASK='Add normalize_record(raw) in a new module normalize.py: raw is a dict from the legacy export with the string keys id, tags, note and qty; return the normalized dict the importer expects. Keep the change small and add tests under tests/.'
CASE_NO_CONTROL=1
CASE_EXPECT_STATUS=escalated
CASE_EXPECT_PATH='^implement:done classify:(low|medium|high) qa:fail implement:done classify:(low|medium|high) qa:fail implement:done classify:(low|medium|high) qa:fail implement:done classify:(low|medium|high) qa:fail step-back:(done|blocked|change-direction)( redirect:escalate)?$'
CASE_FORCE_AFTER=implement:1

case_setup() {
  mkdir -p tests
  cat > README.md <<'R'
# importer
Legacy export import helpers. Tests: python3 -m unittest discover -s tests
R
  cat > legacy.py <<'R'
def read_rows(lines):
    """Split a legacy export into raw dicts (all values are strings)."""
    rows = []
    for line in lines:
        rid, tags, note, qty = (line.split("|") + ["", "", "", ""])[:4]
        rows.append({"id": rid, "tags": tags, "note": note, "qty": qty})
    return rows
R
  cat > tests/test_legacy.py <<'R'
import unittest
from legacy import read_rows


class ReadRows(unittest.TestCase):
    def test_split(self):
        self.assertEqual(read_rows(["7|a,b|hi|3"]), [{"id": "7", "tags": "a,b", "note": "hi", "qty": "3"}])


if __name__ == "__main__":
    unittest.main()
R
}

# The hidden QA kit: six arbitrary importer rules, revealed one at a time (it exits at the first failing rule). The kit file
# is stored compressed so that QA, which is handed its path, sees the first failing rule only when it RUNS it, not all of
# them by reading it (the leak a first live run showed: a diligent QA read the source and listed every rule).
case_kit_setup() {
  local src
  src=$(mktemp "${TMPDIR:-/tmp}/fm-rc-kit.XXXXXX")
  cat > "$src" <<'R'
import sys
sys.path.insert(0, sys.argv[1])
try:
    from normalize import normalize_record
except Exception as e:
    print("FAIL cannot import normalize_record from normalize.py: %r" % (e,))
    sys.exit(1)

def run(rule, raw, want):
    try:
        got = normalize_record(dict(raw))
    except Exception as e:
        got = "raised %r" % (e,)
    key = rule.split(":")[0]
    if isinstance(got, dict):
        got = got.get(key)
    if got != want:
        print("FAIL rule %s: normalize_record(%r)[%r] expected %r, got %r" % (rule, raw, key, want, got))
        sys.exit(1)
    print("ok   rule %s" % rule)

base = {"id": "42", "tags": "b, aaa, cc", "note": "hello", "qty": "7"}
# the four rules nobody can guess come first, so every QA run fails on one of them
run("id: the importer id is INV- plus the number zero-padded to 7 digits", dict(base), "INV-0000042")
run("note: empty or blank becomes the literal (none); longer than 20 characters is cut to 20 and gets a trailing ~", dict(base, note="   "), "(none)")
run("note: empty or blank becomes the literal (none); longer than 20 characters is cut to 20 and gets a trailing ~", dict(base, note="x" * 30), "x" * 20 + "~")
run("chk: the importer adds chk = C followed by the digit sum of the numeric id modulo 7", dict(base), "C6")
run("src: the importer stamps src = legacy-v3 on every record", dict(base), "legacy-v3")
run("tags: lowercase, de-duplicated, longest first then alphabetical", dict(base, tags=" B, aaa ,cc,b "), ["aaa", "cc", "b"])
run("qty: an integer; a k suffix means thousands; anything unparsable is -1", dict(base, qty="2k"), 2000)
run("qty: an integer; a k suffix means thousands; anything unparsable is -1", dict(base, qty="lots"), -1)
sys.exit(0)
R
  python3 - "$src" "$1/kit.py" <<'PY'
import sys, base64, zlib
b = base64.b64encode(zlib.compress(open(sys.argv[1], "rb").read(), 9)).decode()
open(sys.argv[2], "w").write("import base64, zlib, sys\nexec(compile(zlib.decompress(base64.b64decode('%s')), 'kit', 'exec'))\n" % b)
PY
  rm -f "$src"
}

case_extra() { # <step> <role> <iteration> <kit-dir> <cwd> <data-dir>
  case $2 in
    qa) printf 'QA acceptance kit: run `python3 %s/kit.py .` from your working directory (it is the repository under test). Its expectations come from the importer team and are not in the ticket; it stops at the first expectation that fails, and its source is not yours to read or decode: you judge what running it prints. A failing expectation is a FAIL: report that one with the expected and the actual value exactly as the kit prints them, and do not list expectations the kit has not printed. Then do the rest of your QA as usual.\n' "$4" ;;
  esac
}

case_hidden() { # <repo> <kit-dir>
  python3 "$2/kit.py" "$1" > "$RUN/hidden.last" 2>&1 || return 1
  ( cd "$1" && python3 -m unittest discover -s tests >/dev/null 2>&1 ) || { echo 'project tests fail' >> "$RUN/hidden.last"; return 1; }
}

# Case-specific evidence: the cap was reached, not exceeded.
case_assert() { # <run-dir> <repo>
  local run=$1 repo=$2 n
  jq -e '.stepBack != null and .stepBack.loop == "qa-fix"' "$run/data/workflow.json" >/dev/null || { echo "the engine recorded no step-back for the qa-fix loop"; return 1; }
  [ "$(jq -r '.loops["qa-fix"]' "$run/data/workflow.json")" = 3 ] || { echo "the qa-fix loop was not used exactly three times: $(jq -r '.loops["qa-fix"]' "$run/data/workflow.json")"; return 1; }
  n=$(jq -r '[.history[] | select(.step == "implement" and .outcome == "done")] | length' "$run/data/workflow.json")
  [ "$n" = 4 ] || { echo "expected exactly four implementation rounds before the step-back, the state shows $n"; return 1; }
  jq -e 'select(.event == "round-cap")' "$run/data/retro.jsonl" >/dev/null 2>&1 || { echo "no round-cap record in the retro log"; return 1; }
  jq -e '.escalation != null and (.escalation.feedback | length) >= 4' "$run/data/workflow.json" >/dev/null || { echo "the escalation does not carry the accumulated QA feedback"; return 1; }
  return 0
}

# Offline stand-in workers (self-test only). The implementer learns one more rule per round (commit count = round).
case_canned() { # <role> <prompt-file> <cwd> -> final text on stdout
  local role=$1 prompt=$2 cwd=$3 base stage out rc
  case $role in
    senior-fullstack)
      base=$(git -C "$cwd" rev-parse HEAD)
      stage=$(( $(git -C "$cwd" rev-list --count HEAD) - 1 ))
      if grep -q 'accumulated' "$prompt" || [ "${FAKE_MODE:-}" = firsttry ]; then stage=6; fi
      python3 - "$cwd/normalize.py" "$stage" <<'PY'
import sys
path, stage = sys.argv[1], int(sys.argv[2])
lines = ["def normalize_record(raw):", "    out = dict(raw)"]
if stage >= 1:
    lines.append("    out['id'] = 'INV-%07d' % int(raw['id'])")
if stage >= 2:
    lines.append("    note = raw['note'].strip()")
    lines.append("    out['note'] = '(none)' if not note else (note[:20] + '~' if len(note) > 20 else note)")
if stage >= 3:
    lines.append("    out['chk'] = 'C%d' % (sum(int(c) for c in str(int(raw['id']))) % 7)")
if stage >= 4:
    lines.append("    out['src'] = 'legacy-v3'")
if stage >= 5:
    lines.append("    out['tags'] = sorted({t.strip().lower() for t in raw['tags'].split(',') if t.strip()}, key=lambda t: (-len(t), t))")
if stage >= 6:
    lines.append("    q = raw['qty'].strip()")
    lines.append("    try:")
    lines.append("        out['qty'] = int(q[:-1]) * 1000 if q.endswith('k') else int(q)")
    lines.append("    except ValueError:")
    lines.append("        out['qty'] = -1")
lines.append("    return out")
open(path, "w").write("\n".join(lines) + "\n")
PY
      git -C "$cwd" add -A && git -C "$cwd" commit -q -m "normalize: round $stage"
      canned_result "$cwd" "$base" "Implemented normalize_record (round $stage)." "$prompt" ;;
    qa)
      local kit
      kit=$(sed -n 's#^QA acceptance kit: run `python3 \(.*\)/kit.py.*#\1#p' "$prompt" | head -1)
      out=$(python3 "$kit/kit.py" "$cwd" 2>&1); rc=$?
      if [ $rc -eq 0 ]; then printf 'Ran the kit: all expectations hold.\n\n'; canned_verdict PASS "$cwd" '[]'
      else
        local line items
        line=$(printf '%s\n' "$out" | grep '^FAIL' | head -1)
        items=$(jq -nc --arg w "$line" '[{id: "QA-1", severity: "BLOCKER", what: $w, where: "normalize.py"}]')
        printf 'Ran the kit.\n%s\n\n' "$out"; canned_verdict FAIL "$cwd" "$items"
      fi ;;
    code-reviewer)
      printf 'Reviewed normalize.py: small and clear.\n\n'; canned_verdict PASS "$cwd" '[]' ;;
  esac
}
