# Live workflow case (vi): refactor (refactorist -> classify -> qa -> review -> ship -> deliver).
# Problem: documents.py render_documents() repeats the same net-total computation (a sum over the lines plus the
#   optional discount) in each of its three kind branches and is 29 lines long. The ticket asks for a behaviour-preserving
#   restructure: the computation exists once and no function is longer than 20 lines. Behaviour must stay byte-identical,
#   error cases included, and the existing tests are not to be touched.
# Outside judge (deterministic, all code): the hidden DIFFERENTIAL kit (the pre-refactor implementation is the oracle over
#   ~600 generated inputs, outputs AND raised exceptions compared exactly) + the project tests + the existing test file unchanged
#   since the fixture + a STRUCTURAL scan of the AST (at most one sum() over the lines, at most one discount branch, no function
#   longer than 20 lines). case_assert also proves the judge discriminates: the same check run on the untouched fixture FAILS it.
# No forced loop and no control: the kit and the scan are the judge. Offline negatives: a behaviour change, a refactor that
#   restructures nothing, and an edited test each fail the case.
CASE_WORKFLOW=refactor
CASE_TASK='Refactor render_documents in documents.py (behaviour-preserving, no feature change): its three kind branches repeat the same net-total computation (the sum over the lines and the optional discount). Make that computation exist exactly once, and leave no function in documents.py longer than 20 lines. The output must stay byte-identical for every input, error cases included (same exception type and message). Do not modify the existing tests.'
CASE_NO_CONTROL=1
CASE_EXPECT_PATH='^refactor:done( .*)? qa:pass( .*)? review:pass( security:pass)? ship:pass deliver:done$'
CASE_FORCE_AFTER=''
CASE_NEGATIVE='behavior => the workflow ended complete
nostruct => does not satisfy the hidden acceptance check: .*(STRUCTURE|sum)
edittests => does not satisfy the hidden acceptance check: .*tests'

refactor_source() { # the pre-refactor documents.py (the fixture, and the differential oracle in the kit)
  cat <<'R'
"""Render business documents (invoices, quotes, credit notes) as text lines."""


def render_documents(docs):
    """One line per document plus a count line. Unknown kinds raise ValueError."""
    out = []
    count = 0
    for d in docs:
        kind = d["kind"]
        if kind == "invoice":
            net = sum(l["qty"] * l["price"] for l in d["lines"])
            if d.get("discount"):
                net = net - net * d["discount"] // 100
            tax = net * 19 // 100
            out.append("INV %s net=%d tax=%d total=%d" % (d["id"], net, tax, net + tax))
        elif kind == "quote":
            net = sum(l["qty"] * l["price"] for l in d["lines"])
            if d.get("discount"):
                net = net - net * d["discount"] // 100
            tax = net * 7 // 100
            out.append("QUO %s net=%d tax=%d total=%d valid=%s" % (d["id"], net, tax, net + tax, d.get("valid", "30d")))
        elif kind == "credit":
            net = sum(l["qty"] * l["price"] for l in d["lines"])
            if d.get("discount"):
                net = net - net * d["discount"] // 100
            out.append("CRD %s net=-%d total=-%d" % (d["id"], net, net))
        else:
            raise ValueError("unknown kind: %s" % kind)
        count += 1
    out.append("%d documents" % count)
    return "\n".join(out)
R
}

case_setup() {
  mkdir -p tests
  cat > README.md <<'R'
# documents
Text rendering of business documents. Tests: python3 -m unittest discover -s tests
R
  refactor_source > documents.py
  cat > tests/test_documents.py <<'R'
import unittest
import documents


class Render(unittest.TestCase):
    def test_invoice(self):
        doc = {"id": "A1", "kind": "invoice", "lines": [{"qty": 2, "price": 500}]}
        self.assertEqual(documents.render_documents([doc]), "INV A1 net=1000 tax=190 total=1190\n1 documents")

    def test_quote_with_discount(self):
        doc = {"id": "Q7", "kind": "quote", "discount": 10, "lines": [{"qty": 1, "price": 1000}]}
        self.assertEqual(documents.render_documents([doc]), "QUO Q7 net=900 tax=63 total=963 valid=30d\n1 documents")

    def test_credit(self):
        doc = {"id": "C2", "kind": "credit", "lines": [{"qty": 3, "price": 100}]}
        self.assertEqual(documents.render_documents([doc]), "CRD C2 net=-300 total=-300\n1 documents")

    def test_unknown_kind(self):
        with self.assertRaises(ValueError):
            documents.render_documents([{"id": "X", "kind": "refund", "lines": []}])


if __name__ == "__main__":
    unittest.main()
R
}

# The differential kit: the old implementation is the oracle.
case_kit_setup() {
  refactor_source > "$1/old_documents.py"
  cat > "$1/kit.py" <<'R'
import importlib.util
import os
import random
import sys

sys.dont_write_bytecode = True
repo = sys.argv[1]
sys.path.insert(0, repo)
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("old_documents", os.path.join(here, "old_documents.py"))
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)
try:
    import documents as new
except Exception as e:
    print("FAIL cannot import documents.py: %r" % (e,))
    sys.exit(1)


def run(fn, docs):
    try:
        return ("ok", fn(docs))
    except Exception as e:  # the error type and message are behaviour too
        return ("err", type(e).__name__, str(e))


def gen(rng):
    docs = []
    for _ in range(rng.randint(0, 4)):
        d = {"id": "D%d" % rng.randint(1, 999), "kind": rng.choice(["invoice", "quote", "credit", "invoice", "quote", "credit", "refund"]),
             "lines": [{"qty": rng.randint(0, 5), "price": rng.randint(0, 999)} for _ in range(rng.randint(0, 3))]}
        if rng.random() < 0.4:
            d["discount"] = rng.choice([0, 5, 10, 33, 100])
        if rng.random() < 0.3:
            d["valid"] = rng.choice(["14d", "60d"])
        r = rng.random()
        if r < 0.04:
            del d["lines"]
        elif r < 0.08:
            del d["id"]
        docs.append(d)
    return docs


rng = random.Random(20260101)
cases = [[]] + [gen(rng) for _ in range(600)]
bad = 0
for docs in cases:
    a, b = run(old.render_documents, docs), run(new.render_documents, docs)
    if a != b:
        bad += 1
        if bad <= 3:
            print("FAIL differs on %r: old %r, new %r" % (docs, a, b))
if bad:
    print("FAIL %d of %d generated inputs differ from the pre-refactor behaviour" % (bad, len(cases)))
    sys.exit(1)
print("ok   %d generated inputs byte-identical to the pre-refactor implementation (errors included)" % len(cases))
R
}

case_extra() { # <step> <role> <iteration> <kit-dir> <cwd> <data-dir>
  case $2 in
    qa) printf 'QA acceptance kit: run `python3 %s/kit.py .` from your working directory (it is the repository under test). It is a DIFFERENTIAL check: the pre-refactor implementation is the oracle over generated inputs, outputs and raised exceptions compared exactly; any difference is a behaviour change and a BLOCKER. Then do the rest of your QA as usual (the existing tests unchanged, the restructure the ticket asks for actually present).\n' "$4" ;;
  esac
}

# the structural scan: prints one STRUCTURE line per violation
refactor_structure() { # <repo>
  python3 - "$1/documents.py" <<'R'
import ast, sys
try:
    tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
except Exception as e:
    print("STRUCTURE documents.py does not parse: %r" % (e,))
    sys.exit(0)
fns = [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]
if not any(f.name == "render_documents" for f in fns):
    print("STRUCTURE render_documents is gone")
sums = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == "sum"]
if len(sums) > 1:
    print("STRUCTURE the net-total sum() computation still appears %d times (must be once)" % len(sums))
disc = [n for n in ast.walk(tree) if isinstance(n, ast.If) and "discount" in ast.dump(n.test)]
if len(disc) > 1:
    print("STRUCTURE the discount branch still appears %d times (must be once)" % len(disc))
for f in fns:
    n = f.end_lineno - f.lineno + 1
    if n > 20:
        print("STRUCTURE function %s is %d lines long (max 20)" % (f.name, n))
R
}

case_kit_only() { python3 "$2/kit.py" "$1" >/dev/null 2>&1; } # <repo> <kit-dir>

case_hidden() { # <repo> <kit-dir>
  local s
  python3 "$2/kit.py" "$1" > "$RUN/hidden.last" 2>&1 || return 1
  ( cd "$1" && python3 -m unittest discover -s tests >/dev/null 2>&1 ) || { echo 'project tests fail' >> "$RUN/hidden.last"; return 1; }
  git -C "$1" diff --quiet "$BASE0" -- tests/test_documents.py 2>/dev/null || { echo 'tests were edited: tests/test_documents.py differs from the fixture' >> "$RUN/hidden.last"; return 1; }
  s=$(refactor_structure "$1")
  [ -z "$s" ] || { printf '%s\n' "$s" >> "$RUN/hidden.last"; return 1; }
}

case_assert() { # <run-dir> <repo>
  local st=$1/data/workflow.json tmp
  # the judge discriminates: the untouched fixture must FAIL the structural scan (it passes the kit trivially)
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/fm-wf-live-base.XXXXXX")
  git -C "$2" archive "$BASE0" | tar -x -C "$tmp"
  if [ -z "$(refactor_structure "$tmp")" ]; then rm -rf "$tmp"; echo "the structural scan passes the UNTOUCHED fixture, so it does not discriminate"; return 1; fi
  python3 "$KIT/kit.py" "$tmp" >/dev/null 2>&1 || { rm -rf "$tmp"; echo "the differential kit fails the untouched fixture (it must pass the oracle itself)"; return 1; }
  rm -rf "$tmp"
  [ "$(git -C "$2" rev-list --count "$BASE0"..HEAD)" -ge 1 ] || { echo "no commit beyond the fixture: nothing was refactored"; return 1; }
  jq -e '[.history[] | select(.step == "refactor" and .outcome == "done")] | length >= 1 and ((.[0].evidence | length) >= 2)' "$st" >/dev/null \
    || { echo "the refactorist's result block carries fewer than two evidence entries (before and after)"; return 1; }
}

case_canned() { # <role> <prompt-file> <cwd>
  local role=$1 prompt=$2 cwd=$3 base kit
  case $role in
    refactorist)
      base=$(git -C "$cwd" rev-parse HEAD)
      refactor_canned_write "$cwd"
      git -C "$cwd" diff --quiet && git -C "$cwd" diff --cached --quiet || { git -C "$cwd" add -A && git -C "$cwd" commit -q -m "documents: compute the net total once"; }
      # before and after, as the role asks: the unit tests, then the differential over the same inputs
      canned_result "$cwd" "$base" 'Refactored render_documents and committed it.' "$prompt" \
        | jq -Rr 'if startswith("{") then (fromjson | .evidence = [{command: "python3 -m unittest discover -s tests", observed: "OK (before)"}, {command: "python3 -m unittest discover -s tests", observed: "OK (after)"}] | tojson) else . end' ;;
    qa)
      kit=$(sed -n 's#^QA acceptance kit: run `python3 \(.*\)/kit.py.*#\1#p' "$prompt" | head -1)
      if python3 "$kit/kit.py" "$cwd" >/dev/null 2>&1; then printf 'Ran the differential kit: identical.\n\n'; canned_verdict PASS "$cwd" '[]'
      else printf 'Kit failed.\n\n'; canned_verdict FAIL "$cwd" '[{"id":"QA-1","severity":"BLOCKER","what":"the differential kit found a behaviour change","where":"documents.py"}]'; fi ;;
    code-reviewer) printf 'Reviewed the diff: behaviour preserved.\n\n'; canned_verdict PASS "$cwd" '[]' ;;
  esac
}

refactor_canned_write() { # <cwd>: the stand-in refactorist (FAKE_MODE: behavior | nostruct | edittests | good)
  local cwd=$1 tax
  case ${FAKE_MODE:-} in
    nostruct) printf '\n# reviewed\n' >> "$cwd/documents.py"; return 0 ;;
    behavior) tax='net * 19 // 100 + 1' ;;
    *) tax='net * 19 // 100' ;;
  esac
  cat > "$cwd/documents.py" <<R
"""Render business documents (invoices, quotes, credit notes) as text lines."""

KINDS = ("invoice", "quote", "credit")


def _net(d):
    net = sum(l["qty"] * l["price"] for l in d["lines"])
    if d.get("discount"):
        net = net - net * d["discount"] // 100
    return net


def _render(kind, d, net):
    if kind == "invoice":
        tax = $tax
        return "INV %s net=%d tax=%d total=%d" % (d["id"], net, tax, net + tax)
    if kind == "quote":
        tax = net * 7 // 100
        return "QUO %s net=%d tax=%d total=%d valid=%s" % (d["id"], net, tax, net + tax, d.get("valid", "30d"))
    return "CRD %s net=-%d total=-%d" % (d["id"], net, net)


def render_documents(docs):
    """One line per document plus a count line. Unknown kinds raise ValueError."""
    out = []
    for d in docs:
        kind = d["kind"]
        if kind not in KINDS:
            raise ValueError("unknown kind: %s" % kind)
        out.append(_render(kind, d, _net(d)))
    out.append("%d documents" % len(out))
    return "\n".join(out)
R
  [ "${FAKE_MODE:-}" != edittests ] || printf '\n# touched\n' >> "$cwd/tests/test_documents.py"
}
