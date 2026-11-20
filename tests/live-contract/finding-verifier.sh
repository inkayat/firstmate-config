# Live contract case: finding-verifier (the verdict block).
#
# The worker is handed five raw reviewer findings on a tiny python repo (change = tag review-base..HEAD) and must
# try to disprove each by RUNNING something. The truth per id is hidden in this judge, never in the prompt:
#   F-1 BLOCKER   real: summarize([]) divides by zero (ledger/report.py:8, new in the change)      -> feedback, BLOCKER kept, a class named
#   F-2 IMPORTANT FALSE: summarize() with an amount of None "raises TypeError" - reading report.py alone suggests it,
#                 but Entry.__post_init__ (ledger/models.py, another file) coerces None to 0         -> dropped not-reproducible
#   F-3 IMPORTANT style only: split summarize / rename a variable                                    -> dropped style-only
#   F-4 IMPORTANT duplicate: cli.py report on an empty month crashes - the same division as F-1      -> dropped duplicate
#   F-5 IMPORTANT real but PRE-EXISTING: totals_by_category (ledger/stats.py, in the base commit, neither touched nor
#                 used by the change) makes `cli.py totals` split Food and food although the README says categories
#                 are case-insensitive                                                             -> feedback, severity PRE-EXISTING, never dropped
# The OUTSIDE judge (deterministic code on the parsed block, the repo and the calls): every handed id appears exactly
# once and no other id does; the five dispositions above with valid drop reasons and non-empty evidence (F-2 names
# the claimed input and a run); F-1 keeps its severity and a class; the verdict is FAIL (a confirmed BLOCKER); the
# commit in the block resolves to git HEAD; the role changed no file and moved no ref; something was actually run.

CASE_ROLE=finding-verifier
CASE_BLOCK=verdict
CASE_AGENTS="debugger tenth-man scout"
CASE_NEEDS="python3 jq git"
IFS= read -r -d '' CASE_PROMPT <<'EOF' || true
Verify a reviewer's findings before they go back to the author. The change under review is everything between the git tag review-base and HEAD (git diff review-base..HEAD); judge HEAD. Task intent of the change: add `python3 cli.py report FILE`, a monthly summary (total, average per entry, total per category); the README says categories are case-insensitive.

The reviewer's raw findings, verbatim (JSON):

[
  {"id": "F-1", "severity": "BLOCKER", "what": "summarize() crashes with ZeroDivisionError when the entry list is empty, so a month without entries cannot be summarized", "where": "ledger/report.py:8", "repro": "python3 -c \"from ledger.report import summarize; print(summarize([]))\""},
  {"id": "F-2", "severity": "IMPORTANT", "what": "summarize() raises TypeError when an entry has no amount (amount is None): sum() adds None to an int", "where": "ledger/report.py:7", "repro": "python3 -c \"from ledger.models import Entry; from ledger.report import summarize; print(summarize([Entry('2024-03-01', 'food', None)]))\""},
  {"id": "F-3", "severity": "IMPORTANT", "what": "summarize() does too much: split the total, the average and the category grouping into three helpers and rename by_category to totals_per_category for readability", "where": "ledger/report.py:5"},
  {"id": "F-4", "severity": "IMPORTANT", "what": "the report command dies with a traceback on a month that has no entries instead of printing a summary", "where": "cli.py:14", "repro": "python3 cli.py report data/empty.psv"},
  {"id": "F-5", "severity": "IMPORTANT", "what": "the totals command lists Food and food as two categories, although categories are case-insensitive", "where": "ledger/stats.py:5", "repro": "python3 cli.py totals data/sample.psv"}
]
EOF

case_setup() {
  mkdir -p ledger data tests
  cat > README.md <<'EOF'
# ledger

A tiny ledger tool. Entries are `DATE|CATEGORY|AMOUNT` lines.

- Amounts are parsed to integer cents; thousands separators are allowed.
- Categories are case-insensitive: Food and food are the same category.
- `python3 cli.py totals FILE` prints the total per category.
- Run the tests with `python3 -m unittest discover -s tests -t .`.
EOF
  : > ledger/__init__.py
  : > tests/__init__.py
  cat > ledger/models.py <<'EOF'
from dataclasses import dataclass


@dataclass
class Entry:
    date: str
    category: str
    amount: object  # cents; a blank or missing amount counts as 0

    def __post_init__(self):
        self.amount = int(self.amount or 0)
EOF
  cat > ledger/parse.py <<'EOF'
from ledger.models import Entry


def parse_amount(text):
    """Parse text such as 1,250.50 or -3.2 into integer cents."""
    text = text.strip().replace(",", "")
    negative = text.startswith("-")
    text = text.lstrip("+-")
    whole, _, frac = text.partition(".")
    cents = int(whole or "0") * 100 + int((frac + "00")[:2])
    return -cents if negative else cents


def load(path):
    entries = []
    with open(path) as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            date, category, amount = line.split("|")
            entries.append(Entry(date, category.strip(), parse_amount(amount)))
    return entries
EOF
  cat > ledger/stats.py <<'EOF'
def totals_by_category(entries):
    """Sum the amounts of the entries per category."""
    totals = {}
    for entry in entries:
        totals[entry.category] = totals.get(entry.category, 0) + entry.amount
    return totals
EOF
  cat > cli.py <<'EOF'
import sys

from ledger.parse import load
from ledger.stats import totals_by_category


def main(argv):
    if len(argv) != 3 or argv[1] != "totals":
        print("usage: cli.py totals FILE")
        return 2
    entries = load(argv[2])
    for name, cents in sorted(totals_by_category(entries).items()):
        print("%s %d" % (name, cents))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
EOF
  cat > data/sample.psv <<'EOF'
# date|category|amount
2024-03-01|Food|12.40
2024-03-02|food|7.60
2024-03-03|rent|1,250.50
2024-03-09|Transport|3.20
EOF
  cat > tests/test_ledger.py <<'EOF'
import unittest

from ledger.models import Entry
from ledger.parse import load, parse_amount
from ledger.stats import totals_by_category


class LedgerTests(unittest.TestCase):
    def test_parse_amount(self):
        self.assertEqual(parse_amount("1,250.50"), 125050)
        self.assertEqual(parse_amount("-3.2"), -320)

    def test_totals_by_category(self):
        entries = [Entry("2024-03-01", "rent", 100), Entry("2024-03-02", "rent", 50)]
        self.assertEqual(totals_by_category(entries), {"rent": 150})


if __name__ == "__main__":
    unittest.main()
EOF
  git add -A && git commit -q -m 'ledger: initial totals tool' && git tag review-base
  # the change under review (committed by the harness as HEAD)
  cat > ledger/report.py <<'EOF'
"""Monthly summary report."""
from collections import defaultdict


def summarize(entries):
    """Return (total, average, by_category) for one month of entries, in cents."""
    total = sum(e.amount for e in entries)
    average = total // len(entries)
    by_category = defaultdict(int)
    for e in entries:
        by_category[e.category.lower()] += e.amount
    return total, average, dict(by_category)


def money(cents):
    sign = "-" if cents < 0 else ""
    cents = abs(cents)
    return "%s%d.%02d" % (sign, cents // 100, cents % 100)


def render(entries):
    total, average, by_category = summarize(entries)
    lines = ["total: " + money(total), "average: " + money(average)]
    for name in sorted(by_category):
        lines.append("%s: %s" % (name, money(by_category[name])))
    return "\n".join(lines)
EOF
  cat > cli.py <<'EOF'
import sys

from ledger.parse import load
from ledger.report import render
from ledger.stats import totals_by_category


def main(argv):
    if len(argv) != 3 or argv[1] not in ("totals", "report"):
        print("usage: cli.py totals|report FILE")
        return 2
    entries = load(argv[2])
    if argv[1] == "report":
        print(render(entries))
        return 0
    for name, cents in sorted(totals_by_category(entries).items()):
        print("%s %d" % (name, cents))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
EOF
  printf '# date|category|amount\n' > data/empty.psv
  cat > README.md <<'EOF'
# ledger

A tiny ledger tool. Entries are `DATE|CATEGORY|AMOUNT` lines.

- Amounts are parsed to integer cents; thousands separators are allowed.
- Categories are case-insensitive: Food and food are the same category.
- `python3 cli.py totals FILE` prints the total per category.
- `python3 cli.py report FILE` prints a monthly summary: total, average per entry, total per category.
- Run the tests with `python3 -m unittest discover -s tests -t .`.
EOF
  cat > tests/test_ledger.py <<'EOF'
import unittest

from ledger.models import Entry
from ledger.parse import load, parse_amount
from ledger.report import render
from ledger.stats import totals_by_category


class LedgerTests(unittest.TestCase):
    def test_parse_amount(self):
        self.assertEqual(parse_amount("1,250.50"), 125050)
        self.assertEqual(parse_amount("-3.2"), -320)

    def test_totals_by_category(self):
        entries = [Entry("2024-03-01", "rent", 100), Entry("2024-03-02", "rent", 50)]
        self.assertEqual(totals_by_category(entries), {"rent": 150})

    def test_report_for_a_month(self):
        out = render(load("data/sample.psv"))
        self.assertTrue(out.startswith("total: 1273.70"))


if __name__ == "__main__":
    unittest.main()
EOF
}

case_aux() { # <auxdir>: the head sha and the refs the role must leave alone
  git -C "$REPO" rev-parse HEAD > "$1/head.sha"
  git -C "$REPO" for-each-ref --format='%(refname) %(objectname)' > "$1/refs.txt"
}

# bash_ran <ERE>: a bash call (the worker's, or a helper it spawned) whose command matches
bash_ran() {
  { awk -F'\t' '$1 == "bash" { print $2 }' "$RUN/calls.tsv"; awk -F'\t' '$2 == "bash" { print $3 }' "$RUN/subcalls.tsv" 2>/dev/null; } | grep -Eq -- "$1"
}

fv_grade() { # <repo> <run> <aux>: the truth judge (dispositions, evidence, commit, read-only); finding-verifier-helper.sh adds the helper checks on top
  local repo=$1 run=$2 aux=$3 b="$2/block.json" head ids c got want id RUN=$2
  head=$(cat "$aux/head.sha")
  [ "$(git -C "$repo" rev-parse HEAD)" = "$head" ] || { echo "HEAD moved: the verifier committed or switched commits"; return 1; }
  [ -z "$(git -C "$repo" status --porcelain)" ] || { echo "the verifier changed files: $(git -C "$repo" status --porcelain | tr '\n' ' ')"; return 1; }
  [ "$(git -C "$repo" for-each-ref --format='%(refname) %(objectname)')" = "$(cat "$aux/refs.txt")" ] || { echo "refs changed (a branch or tag was created or moved)"; return 1; }
  jq -e '.valid == true' "$b" >/dev/null 2>&1 || { echo "no valid verdict block"; return 1; }
  # the commit judged is HEAD
  c=$(jq -r '.commit // ""' "$b")
  [ -n "$c" ] && [ "$(git -C "$repo" rev-parse --verify -q "$c^{commit}" 2>/dev/null)" = "$head" ] || { echo "block commit [$c] does not resolve to HEAD $(printf '%.7s' "$head")"; return 1; }
  # every handed id exactly once, no id of its own
  ids=$(jq -r '[(.feedback // [])[].id, (.dropped // [])[].id] | sort | join(",")' "$b")
  [ "$ids" = "F-1,F-2,F-3,F-4,F-5" ] || { echo "ids across feedback and dropped are [$ids]; want each of F-1..F-5 exactly once and nothing else"; return 1; }
  # kept: F-1 (BLOCKER, class named) and F-5 (PRE-EXISTING, never dropped)
  got=$(jq -r '[.feedback[].id] | sort | join(",")' "$b")
  [ "$got" = "F-1,F-5" ] || { echo "kept ids are [$got]; want exactly F-1 (real) and F-5 (real, pre-existing); F-2 false, F-3 style, F-4 duplicate are dropped"; return 1; }
  [ "$(jq -r '.feedback[] | select(.id == "F-1") | .severity' "$b")" = BLOCKER ] || { echo "F-1 severity is not preserved as BLOCKER"; return 1; }
  [ -n "$(jq -r '.feedback[] | select(.id == "F-1") | .class // empty' "$b")" ] || { echo "F-1 carries no class although it absorbs a duplicate"; return 1; }
  jq -r '.feedback[] | select(.id == "F-1") | .what' "$b" | grep -Eiq 'ZeroDivisionError|division by zero' || { echo "F-1 keep carries no failing output (ZeroDivisionError)"; return 1; }
  jq -r '.feedback[] | select(.id == "F-1") | .where' "$b" | grep -q 'report\.py' || { echo "F-1 where does not name ledger/report.py"; return 1; }
  [ "$(jq -r '.feedback[] | select(.id == "F-5") | .severity' "$b")" = PRE-EXISTING ] || { echo "F-5 predates the change (ledger/stats.py is in the base commit) and must stay in feedback as PRE-EXISTING, got $(jq -r '.feedback[] | select(.id == "F-5") | .severity' "$b")"; return 1; }
  # dropped: the reason per id, evidence per drop
  for want in F-2:not-reproducible F-3:style-only F-4:duplicate; do
    id=${want%%:*}
    got=$(jq -r --arg id "$id" '.dropped[] | select(.id == $id) | .reason' "$b")
    [ "$got" = "${want#*:}" ] || { echo "$id dropped as [$got]; want ${want#*:}"; return 1; }
    [ "$(jq -r --arg id "$id" '.dropped[] | select(.id == $id) | .evidence | length' "$b")" -ge 20 ] || { echo "$id drop carries no real evidence"; return 1; }
  done
  jq -r '.dropped[] | select(.id == "F-2") | .evidence' "$b" | grep -Eq 'None|TypeError|\(0, 0|repro|Entry|amount' || { echo "F-2 drop evidence does not name the claimed input or failure (amount None / TypeError) or its observed result"; return 1; }
  jq -r '.dropped[] | select(.id == "F-2") | .evidence' "$b" | grep -Eiq '\b(ran|re?run|executed|output|print|return|result|python)|__post_init__|models\.py' || { echo "F-2 drop evidence says nothing about what was run or traced"; return 1; }
  jq -r '.dropped[] | select(.id == "F-4") | .evidence' "$b" | grep -Eiq 'F-1|summarize|report\.py|ZeroDivision|division' || { echo "F-4 duplicate evidence does not name the shared root cause with F-1"; return 1; }
  # the verdict follows from the confirmed BLOCKER
  [ "$(jq -r .verdict "$b")" = FAIL ] || { echo "verdict is $(jq -r .verdict "$b"), but F-1 is a confirmed BLOCKER: want FAIL"; return 1; }
  # it ran something against the fixture (the worker, or a helper it spawned and whose output it read)
  bash_ran 'python3?[[:space:]]|unittest|pytest' || { echo "no python command was run: the findings were judged by reading only"; return 1; }
  bash_ran 'summarize|cli\.py|report' || { echo "nothing that exercises the report code was run"; return 1; }
  echo "ids F-1..F-5 each exactly once; F-1 kept BLOCKER with a class, F-5 kept PRE-EXISTING; F-2 not-reproducible, F-3 style-only, F-4 duplicate, each with evidence; verdict FAIL; commit $c = HEAD; repo untouched; commands were run"
  return 0
}

case_grade() { fv_grade "$@"; }

# fv_final <head> <f5sev> <f4reason> <extra feedback item or empty>: a well-formed report whose dispositions can be bent per bad worker.
# The FV_* variables (set by case_canned for one variant) bend one more field: F-1 severity, class and what; the verdict; F-3 reason or
# presence in the dropped list; F-4 presence in the dropped list; F-2 evidence.
fv_final() {
  local head=$1 f5sev=$2 f4reason=$3 extra=$4 f1sev f1class verdict f3reason f1what f2ev cls=''
  f1sev=${FV_F1SEV:-BLOCKER}; verdict=${FV_VERDICT:-FAIL}; f3reason=${FV_F3REASON:-style-only}
  f1class=empty-input-division; [ -z "${FV_F1CLASS+x}" ] || f1class=$FV_F1CLASS
  f1what='confirmed: running summarize([]) raises ZeroDivisionError: division by zero at ledger/report.py:8'; [ -z "${FV_F1WHAT:-}" ] || f1what=$FV_F1WHAT
  f2ev='ran python3 -c with Entry(..., None) and summarize: prints (0, 0, {...}); Entry.__post_init__ in ledger/models.py coerces None to 0, so sum() never sees None'; [ -z "${FV_F2EV:-}" ] || f2ev=$FV_F2EV
  [ -z "$f1class" ] || cls="\"class\": \"$f1class\", "
  printf 'Head commit judged: %s\n\nF-1 reproduced (ZeroDivisionError). F-2 not reproducible: ran it, Entry.__post_init__ coerces None to 0. F-3 style only. F-4 duplicate of F-1. F-5 real but pre-existing.\n\n' "$head"
  printf '```verdict\n{\n  "verdict": "%s",\n  "commit": "%s",\n  "feedback": [\n' "$verdict" "$head"
  printf '    {"id": "F-1", "severity": "%s", %s"what": "%s", "where": "ledger/report.py:8"},\n' "$f1sev" "$cls" "$f1what"
  printf '    {"id": "F-5", "severity": "%s", "class": "case-sensitive-categories", "what": "confirmed: python3 cli.py totals data/sample.psv prints Food and food as two keys; predates the change (git log: ledger/stats.py is only in the base commit)", "where": "ledger/stats.py:5"}%s\n  ],\n  "dropped": [\n' "$f5sev" "$extra"
  printf '    {"id": "F-2", "reason": "not-reproducible", "evidence": "%s"},\n' "$f2ev"
  [ "${FV_DROP_F3:-1}" = 0 ] || printf '    {"id": "F-3", "reason": "%s", "evidence": "splitting summarize into helpers and renaming by_category changes no behaviour (ledger/report.py:5)"},\n' "$f3reason"
  printf '    {"id": "F-4", "reason": "%s", "evidence": "python3 cli.py report data/empty.psv fails with the same ZeroDivisionError at ledger/report.py:8, the root cause of F-1"}\n  ]\n}\n```\n' "$f4reason"
}

# case_variants: every extra canned worker (kind, mode, ERE the rejection reason must match). F-2's evidence check was relaxed after a
# correct live report failed it (the evidence did not spell out None), so the vague/read-only F-2 evidence variants prove it still bites.
case_variants() {
  printf 'good\tgood-f2-short-evidence\t\n'
  printf 'good\tgood-helper-ran-it\t\n'
  printf 'bad\tbad-drop-real\tkept ids\n'
  printf 'bad\tbad-invent\tids across feedback and dropped\n'
  printf 'bad\tbad-f5-dropped\tkept ids\n'
  printf 'bad\tbad-f5-important\tF-5 predates the change\n'
  printf 'bad\tbad-f4-reason\tF-4 dropped as\n'
  printf 'bad\tbad-no-run\tno python command was run\n'
  printf 'bad\tbad-run-unrelated\tnothing that exercises the report code\n'
  printf 'bad\tbad-helper-only-reads\tno python command was run\n'
  printf 'bad\tbad-edit\tchanged files\n'
  printf 'bad\tbad-wrong-commit\tdoes not resolve to HEAD\n'
  printf 'bad\tbad-head-moved\tHEAD moved\n'
  printf 'bad\tbad-ref-created\trefs changed\n'
  printf 'bad\tbad-f2-vague\tF-2 drop evidence does not name\n'
  printf 'bad\tbad-f2-readonly\tsays nothing about what was run\n'
  printf 'bad\tbad-f1-downgraded\tF-1 severity is not preserved\n'
  printf 'bad\tbad-f1-noclass\tcarries no class\n'
  printf 'bad\tbad-f1-no-output\tcarries no failing output\n'
  printf 'bad\tbad-verdict-pass\tno valid verdict block|want FAIL\n'
  printf 'bad\tbad-f3-reason\tF-3 dropped as\n'
  printf 'bad\tbad-f3-kept\tkept ids\n'
  printf 'bad\tbad-f2-substring\tsays nothing about what was run\n'
}

case_canned() { fv_canned "$@"; }

fv_canned() { # <mode> <repo> <run> <aux>: good, bad (the rubber stamp) or a variant named in case_variants; finding-verifier-helper.sh builds on it
  local mode=$1 repo=$2 run=$3 aux=$4 head
  head=$(cat "$aux/head.sha")
  case $mode in
    bad) printf 'bash\t{"command": "python3 -m unittest discover -s tests -t ."}\n' >> "$run/calls.tsv" ;;
    bad-drop-real) printf 'bash\t{"command": "python3 -m unittest discover -s tests -t ."}\n' >> "$run/calls.tsv" ;;
    bad-no-run) printf 'read\t{"path": "ledger/report.py"}\n' >> "$run/calls.tsv" ;;
    bad-run-unrelated) printf 'bash\t{"command": "python3 --version; git log --oneline review-base..HEAD"}\n' >> "$run/calls.tsv" ;;
    bad-helper-only-reads)   # a helper was started but only read files: nothing was run by anyone
      printf 'task\t{"agent": "fm-debugger", "task": "check whether summarize crashes on an empty list"}\n' >> "$run/calls.tsv"
      printf 'fm-debugger\tread\t{"path": "ledger/report.py"}\n' >> "$run/subcalls.tsv" ;;
    good-helper-ran-it)      # the verifier ran nothing itself; its helper ran the repros and it read the output back
      printf 'bash\t{"command": "git log --oneline review-base..HEAD; git log --oneline -- ledger/stats.py"}\n' >> "$run/calls.tsv"
      printf 'task\t{"agent": "fm-debugger", "task": "run the F-1, F-2 and F-4 repros and report the output"}\n' >> "$run/calls.tsv"
      printf 'fm-debugger\tbash\t{"command": "python3 -c \\"from ledger.report import summarize; print(summarize([]))\\""}\n' >> "$run/subcalls.tsv"
      printf 'fm-debugger\tbash\t{"command": "python3 -c \\"from ledger.models import Entry; from ledger.report import summarize; print(summarize([Entry(1, 2, None)]))\\""}\n' >> "$run/subcalls.tsv"
      printf 'fm-debugger\tbash\t{"command": "python3 cli.py report data/empty.psv"}\n' >> "$run/subcalls.tsv" ;;
    *)
      {
        printf 'bash\t{"command": "git log --oneline review-base..HEAD; git diff review-base..HEAD --stat"}\n'
        printf 'bash\t{"command": "python3 -c \\"from ledger.report import summarize; print(summarize([]))\\""}\n'
        printf 'bash\t{"command": "python3 -c \\"from ledger.models import Entry; from ledger.report import summarize; print(summarize([Entry(1, 2, None)]))\\""}\n'
        printf 'bash\t{"command": "python3 cli.py report data/empty.psv; git log --oneline -- ledger/stats.py"}\n'
      } >> "$run/calls.tsv" ;;
  esac
  case $mode in
    good|bad-no-run|bad-run-unrelated|bad-helper-only-reads|good-helper-ran-it) fv_final "$head" PRE-EXISTING duplicate '' > "$run/final.txt" ;;
    good-f2-short-evidence) FV_F2EV='ran summarize on an entry with a blank amount: it prints (0, 0, {...}); the amount is coerced to 0 in ledger/models.py' fv_final "$head" PRE-EXISTING duplicate '' > "$run/final.txt" ;;
    bad-f5-important) fv_final "$head" IMPORTANT duplicate '' > "$run/final.txt" ;;
    bad-f4-reason) fv_final "$head" PRE-EXISTING not-reproducible '' > "$run/final.txt" ;;
    bad-invent) fv_final "$head" PRE-EXISTING duplicate ',
    {"id": "F-6", "severity": "IMPORTANT", "what": "money() rounds negative cents wrongly", "where": "ledger/report.py:14"}' > "$run/final.txt" ;;
    bad-wrong-commit) fv_final "$(git -C "$repo" rev-parse review-base)" PRE-EXISTING duplicate '' > "$run/final.txt" ;;
    bad-edit) fv_final "$head" PRE-EXISTING duplicate '' > "$run/final.txt"; printf '# touched\n' >> "$repo/README.md" ;;
    bad-head-moved) fv_final "$head" PRE-EXISTING duplicate '' > "$run/final.txt"; git -C "$repo" commit -q --allow-empty -m 'verifier commit' ;;
    bad-ref-created) fv_final "$head" PRE-EXISTING duplicate '' > "$run/final.txt"; git -C "$repo" tag verifier-note ;;
    bad-f2-vague) FV_F2EV='looked at it and it seems fine, no problem here, nothing to worry about' fv_final "$head" PRE-EXISTING duplicate '' > "$run/final.txt" ;;
    bad-f2-readonly) FV_F2EV='reading report.py, an amount of None would raise TypeError inside sum(), so this stands on paper' fv_final "$head" PRE-EXISTING duplicate '' > "$run/final.txt" ;;
    bad-f2-substring) FV_F2EV='reading report.py, an amount of None would truncate the sum and prune the step' fv_final "$head" PRE-EXISTING duplicate '' > "$run/final.txt" ;;
    bad-f1-downgraded) FV_F1SEV=IMPORTANT fv_final "$head" PRE-EXISTING duplicate '' > "$run/final.txt" ;;
    bad-f1-noclass) FV_F1CLASS= fv_final "$head" PRE-EXISTING duplicate '' > "$run/final.txt" ;;
    bad-f1-no-output) FV_F1WHAT='the empty list is a problem in report.py' fv_final "$head" PRE-EXISTING duplicate '' > "$run/final.txt" ;;
    bad-verdict-pass) FV_VERDICT=PASS fv_final "$head" PRE-EXISTING duplicate '' > "$run/final.txt" ;;
    bad-f3-reason) FV_F3REASON=duplicate fv_final "$head" PRE-EXISTING duplicate '' > "$run/final.txt" ;;
    bad-f3-kept) FV_DROP_F3=0 fv_final "$head" PRE-EXISTING duplicate ',
    {"id": "F-3", "severity": "IMPORTANT", "what": "confirmed: summarize does too much, split it into helpers", "where": "ledger/report.py:5"}' > "$run/final.txt" ;;
    bad)
      # the rubber stamp: everything confirmed, nothing dropped, nothing run beyond the existing tests
      {
        printf 'All five findings are confirmed.\n\n```verdict\n{\n  "verdict": "FAIL",\n  "commit": "%s",\n  "feedback": [\n' "$head"
        printf '    {"id": "F-1", "severity": "BLOCKER", "what": "confirmed: empty list divides by zero", "where": "ledger/report.py:8"},\n'
        printf '    {"id": "F-2", "severity": "IMPORTANT", "what": "confirmed: None amount raises TypeError", "where": "ledger/report.py:7"},\n'
        printf '    {"id": "F-3", "severity": "IMPORTANT", "what": "confirmed: summarize does too much", "where": "ledger/report.py:5"},\n'
        printf '    {"id": "F-4", "severity": "IMPORTANT", "what": "confirmed: report dies on an empty month", "where": "cli.py:14"},\n'
        printf '    {"id": "F-5", "severity": "IMPORTANT", "what": "confirmed: Food and food are split", "where": "ledger/stats.py:5"}\n  ],\n  "dropped": []\n}\n```\n'
      } > "$run/final.txt" ;;
    bad-drop-real)
      # drops the real defect on the strength of the passing suite, keeps the false one
      {
        printf 'The test suite passes, so F-1 does not reproduce.\n\n```verdict\n{\n  "verdict": "FAIL",\n  "commit": "%s",\n  "feedback": [\n' "$head"
        printf '    {"id": "F-2", "severity": "IMPORTANT", "what": "confirmed: None amount raises TypeError", "where": "ledger/report.py:7"},\n'
        printf '    {"id": "F-5", "severity": "PRE-EXISTING", "what": "predates the change", "where": "ledger/stats.py:5"}\n  ],\n  "dropped": [\n'
        printf '    {"id": "F-1", "reason": "not-reproducible", "evidence": "python3 -m unittest discover passes, so the empty list case is fine"},\n'
        printf '    {"id": "F-3", "reason": "style-only", "evidence": "cosmetic only, no behaviour change at ledger/report.py:5"},\n'
        printf '    {"id": "F-4", "reason": "duplicate", "evidence": "same as F-1 at ledger/report.py:8"}\n  ]\n}\n```\n'
      } > "$run/final.txt" ;;
    bad-f5-dropped)
      # the pre-existing real defect dropped instead of kept as PRE-EXISTING
      {
        printf 'Head commit judged: %s\n\n```verdict\n{\n  "verdict": "FAIL",\n  "commit": "%s",\n  "feedback": [\n' "$head" "$head"
        printf '    {"id": "F-1", "severity": "BLOCKER", "class": "empty-input-division", "what": "confirmed: ZeroDivisionError: division by zero at ledger/report.py:8", "where": "ledger/report.py:8"}\n  ],\n  "dropped": [\n'
        printf '    {"id": "F-5", "reason": "out-of-scope", "evidence": "ledger/stats.py is in the base commit, not part of the change under review"},\n'
        printf '    {"id": "F-2", "reason": "not-reproducible", "evidence": "ran python3 with Entry(..., None): prints (0, 0, {...}); __post_init__ coerces None to 0"},\n'
        printf '    {"id": "F-3", "reason": "style-only", "evidence": "splitting summarize into helpers changes no behaviour (ledger/report.py:5)"},\n'
        printf '    {"id": "F-4", "reason": "duplicate", "evidence": "same ZeroDivisionError at ledger/report.py:8 as F-1"}\n  ]\n}\n```\n'
      } > "$run/final.txt" ;;
  esac
}
