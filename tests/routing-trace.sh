#!/usr/bin/env bash
# routing-trace.sh - offline acceptance, plus an externally usable `check`
# CLI, for the temporary routing/skill trace the Captain prints during the
# debugging period (firstmate/primary-policy.md section 8).
#
# Usage:
#   tests/routing-trace.sh                     run the offline fixture suite
#   tests/routing-trace.sh check <trace-file> <harness> <model> <effort> <skills|none> [<worker-transcript>]
#       check ONE worker's captured trace block against the actual spawn
#       axes (the harness/model/effort really passed to fm-spawn, e.g. from
#       state/<id>.meta or the worker's own process line) and the skills
#       actually selected in its brief (comma-separated; absolute
#       .../<name>/SKILL.md paths normalize to <name>, worktree-relative
#       project-local paths stay as written). With a worker transcript,
#       also check the block's "Skill evidence:" lines against it. Prints
#       one PASS/FAIL line per check; exit 0 only when all pass.
#
# What this proves and what it cannot: `check` compares text the Captain
# printed with facts supplied by the caller. The Routing line starts with
# `CATEGORY` or `CATEGORY #n` only: `#n` names the matched rule within a
# multi-rule category, the axes must be that rule's route (or a named
# captain override), and any free-text sub-lane label is rejected because
# nothing can verify it. `check` cannot observe the Captain printing the
# trace, cannot classify a task into a category or rule, and cannot prove a
# skill was applied: an evidence citation PASS means only that the text
# occurs somewhere in the transcript - a quote or a denial matches too - so
# each PASS prints the surrounding transcript text for the Captain to read
# before reporting it. It also rejects duplicate per-skill lines and claims
# for unselected skills. It is a diagnostic for the debugging period, never
# a completion gate, dispatch hook, or monitor.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CREW_DISPATCH="$CONFIG_ROOT/firstmate/crew-dispatch.json"

trace_check() { # <trace-file> <harness> <model> <effort> <skills|none> [<transcript>]
  python3 - "$CREW_DISPATCH" "$@" <<'PY'
import json, os, re, sys

dispatch, trace_path, harness, model, effort, skills_arg = sys.argv[1:7]
transcript_path = sys.argv[7] if len(sys.argv) > 7 else None
NO_EVIDENCE = "selected, but no strong application evidence observed"
ROLES = {"ARCHITECTURE": "architecture", "TENTH-MAN": "tenth-man"}
failed = False

def result(ok, label):
    global failed
    failed |= not ok
    print(("PASS - " if ok else "FAIL - ") + label)

def skill_id(token):
    # Absolute (shared/core) skill paths normalize to the skill's name;
    # worktree-relative project-local paths stay distinct from a global
    # skill of the same name.
    token = token.strip()
    if os.path.isabs(token) and token.endswith("/SKILL.md"):
        return os.path.basename(os.path.dirname(token))
    return token

lines = open(trace_path).read().splitlines()
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
result(role == ROLES.get(category, "senior-fullstack"), "role %s matches category %s" % (role, category))

body = skills_lines[0][len("Skills:"):].strip()
traced = set() if body == "none" else {skill_id(e.split(" - ")[0]) for e in body.split(";") if e.strip()}
selected = set() if skills_arg == "none" else {skill_id(s) for s in skills_arg.split(",") if s.strip()}
result(traced == selected, "Skills names exactly the selected skills %s (trace says %s)" % (sorted(selected) or "none", sorted(traced) or "none"))

if transcript_path is not None:
    transcript = open(transcript_path).read()
    try:
        start = lines.index("Skill evidence:")
    except ValueError:
        result(False, "a Skill evidence: block follows the worker's completion")
        sys.exit(1)
    entries = []
    for l in lines[start + 1:]:
        m = re.match(r"^- (\S+): (.+)$", l)
        if not m:
            break
        entries.append((skill_id(m.group(1)), m.group(2).strip()))
    names = [name for name, _ in entries]
    result(len(names) == len(set(names)), "Skill evidence has one line per skill (got %s)" % names)
    result(set(names) == selected,
           "Skill evidence covers exactly the selected skills %s (got %s)" % (sorted(selected) or "none", sorted(set(names)) or "none"))
    for name, text in entries:
        if text == NO_EVIDENCE:
            result(True, "%s: honestly reported without application evidence" % name)
            continue
        cited = re.findall(r"`([^`]+)`", text)
        result(1 <= len(cited) <= 2, "%s: cites one or two observations (got %d)" % (name, len(cited)))
        for c in cited:
            at = transcript.find(c)
            if at < 0:
                result(False, "%s: cited `%s` occurs in the worker transcript" % (name, c))
                continue
            # Lexical match only: a quote or a denial matches too, so show
            # the surrounding transcript text for the Captain to read.
            context = " ".join(transcript[max(0, at - 80):at + len(c) + 80].split())
            result(True, "%s: cited `%s` occurs in the worker transcript (lexical match only - inspect context: ...%s...)" % (name, c, context))

sys.exit(1 if failed else 0)
PY
}
if [ "${1:-}" = check ]; then
  shift
  [ "$#" -ge 5 ] || { printf 'usage: %s check <trace-file> <harness> <model> <effort> <skills|none> [<worker-transcript>]\n' "$0" >&2; exit 2; }
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
SONNET=anthropic/claude-sonnet-5
SOL=openai-codex/gpt-6-sol
TDD=test-driven-development
VBC=verification-before-completion

# A worker's real transcript excerpt: the evidence lines below may only
# cite what appears here verbatim.
TRANSCRIPT=$(t transcript.txt '$ bash tests/routing-trace.sh
FAIL - substantive IMPLEMENT trace matches its spawn axes (expected pass, exit 2)
ROUTING TRACE TESTS FAIL
$ bash tests/routing-taxonomy.sh
ROUTING TAXONOMY TESTS PASS')

# --- 1. Routing summary reflects the actual spawn axes ----------------------
IMPL=$(t impl.txt "Routing: IMPLEMENT #2 | role senior-fullstack | omp | $OPUS | high | why: multi-file behavior change
Skills: $TDD - behavior change needs failing-first tests; $VBC - completion claim needs fresh evidence")
expect 'substantive IMPLEMENT trace matches its spawn axes' pass "$IMPL" omp "$OPUS" high "$TDD,$VBC"
expect 'trace naming Opus while the worker actually ran Sonnet is rejected' fail "$IMPL" omp "$SONNET" high "$TDD,$VBC"
expect 'trace effort differing from the actual spawn effort is rejected' fail "$IMPL" omp "$OPUS" xhigh "$TDD,$VBC"
expect 'trace harness differing from the actual spawn harness is rejected' fail "$IMPL" pi "$OPUS" high "$TDD,$VBC"

BOUNDED=$(t bounded.txt "Routing: IMPLEMENT #1 | role senior-fullstack | omp | $SONNET | high | why: one-function fix
Skills: $TDD - bug fix")
expect 'bounded IMPLEMENT on Sonnet 5 high is an allowed route' pass "$BOUNDED" omp "$SONNET" high "$TDD"

HAIKU_IMPL=$(t haiku-impl.txt "Routing: IMPLEMENT #1 | role senior-fullstack | omp | anthropic/claude-haiku-4-5 | low | why: cheap
Skills: none")
expect 'a model/effort outside the named category rules is rejected' fail "$HAIKU_IMPL" omp anthropic/claude-haiku-4-5 low none
OVERRIDE=$(t override.txt "Routing: IMPLEMENT #1 | role senior-fullstack | omp | anthropic/claude-haiku-4-5 | low | why: captain override - captain asked for Haiku
Skills: none")
expect 'an explicit captain override outside the rules is accepted when the why names it' pass "$OVERRIDE" omp anthropic/claude-haiku-4-5 low none

DEFAULT=$(t default.txt "Routing: DEFAULT | role senior-fullstack | omp | $OPUS | high | why: no specific category fits
Skills: none")
expect 'DEFAULT trace on Opus 5.5 high matches the debug-period catch-all' pass "$DEFAULT" omp "$OPUS" high none

TENTH=$(t tenth.txt "Routing: TENTH-MAN #1 | role tenth-man | pi | $SOL | xhigh | why: challenge Claude-authored completion claim
Skills: none")
expect 'TENTH-MAN against Claude output on Pi GPT-6 Sol xhigh is accepted' pass "$TENTH" pi "$SOL" xhigh none
ARCH_WRONG_ROLE=$(t arch-role.txt "Routing: ARCHITECTURE #1 | role senior-fullstack | omp | $OPUS | high | why: module boundary
Skills: none")
expect 'ARCHITECTURE trace must name role architecture' fail "$ARCH_WRONG_ROLE" omp "$OPUS" high none
MISSING=$(t missing.txt "Skills: none")
expect 'a block without a Routing line is rejected' fail "$MISSING" omp "$OPUS" high none

# Sub-lane identity: a multi-rule category's trace names the matched rule
# (#n, 1-based within the category, pinned by tests/routing-taxonomy.sh),
# and the axes must be that rule's own route - never merely some route of
# the category, and no unverifiable free-text sub-lane label may follow it
# (review findings: "REVIEW critical" and "REVIEW #1 critical" on Sonnet
# high both passed).
REVIEW_NO_RULE=$(t rev-norule.txt "Routing: REVIEW | role senior-fullstack | omp | $SONNET | high | why: release-critical security diff
Skills: none")
expect 'a multi-rule category trace without its matched rule #n is rejected' fail "$REVIEW_NO_RULE" omp "$SONNET" high none
REVIEW_CRIT_SONNET=$(t rev-crit-sonnet.txt "Routing: REVIEW #3 | role senior-fullstack | omp | $SONNET | high | why: release-critical security diff
Skills: none")
expect 'critical REVIEW (#3) displayed on Sonnet 5 high contradicts its Opus 5.5 xhigh route and is rejected' fail "$REVIEW_CRIT_SONNET" omp "$SONNET" high none
REVIEW_CRIT_OPUS=$(t rev-crit-opus.txt "Routing: REVIEW #3 | role senior-fullstack | omp | $OPUS | xhigh | why: release-critical security diff
Skills: none")
expect 'critical REVIEW (#3) on Opus 5.5 xhigh is accepted' pass "$REVIEW_CRIT_OPUS" omp "$OPUS" xhigh none
REVIEW_BOUNDED=$(t rev-bounded.txt "Routing: REVIEW #1 | role senior-fullstack | omp | $SONNET | high | why: one-file diff
Skills: none")
expect 'bounded REVIEW (#1) on Sonnet 5 high is accepted' pass "$REVIEW_BOUNDED" omp "$SONNET" high none
REVIEW_CRIT_OVERRIDE=$(t rev-crit-override.txt "Routing: REVIEW #3 | role senior-fullstack | omp | $SONNET | high | why: captain override - captain chose Sonnet for this critical review
Skills: none")
expect_shows 'a named captain override of critical REVIEW is accepted and reported as an override' 'captain override' \
  "$REVIEW_CRIT_OVERRIDE" omp "$SONNET" high none
REVIEW_BAD_RULE=$(t rev-badrule.txt "Routing: REVIEW #9 | role senior-fullstack | omp | $OPUS | xhigh | why: x
Skills: none")
expect 'a rule number the category does not have is rejected' fail "$REVIEW_BAD_RULE" omp "$OPUS" xhigh none
FALSE_CRIT_LABEL=$(t rev-false-crit.txt "Routing: REVIEW #1 critical | role senior-fullstack | omp | $SONNET | high | why: release-critical security diff
Skills: none")
expect 'a free sub-lane label after #n (REVIEW #1 critical on Sonnet high) is rejected' fail "$FALSE_CRIT_LABEL" omp "$SONNET" high none
FALSE_BOUNDED_LABEL=$(t rev-false-bounded.txt "Routing: REVIEW #3 bounded | role senior-fullstack | omp | $OPUS | xhigh | why: release-critical security diff
Skills: none")
expect 'a free sub-lane label after #n (REVIEW #3 bounded on Opus xhigh) is rejected' fail "$FALSE_BOUNDED_LABEL" omp "$OPUS" xhigh none

# --- 2. Skills summary reflects exactly the selected skills -----------------
expect 'Skills naming an unselected, merely installed skill is rejected' fail "$IMPL" omp "$OPUS" high "$TDD"
expect 'Skills omitting a selected skill is rejected' fail "$BOUNDED" omp "$SONNET" high "$TDD,$VBC"
expect 'zero selected skills with "Skills: none" is valid' pass "$DEFAULT" omp "$OPUS" high none
expect 'absolute shared-skill paths from the brief normalize to their names' pass "$IMPL" omp "$OPUS" high "$HOME/.agents/skills/$TDD/SKILL.md,$HOME/.agents/skills/$VBC/SKILL.md"
PROJECT=$(t project.txt "Routing: REVIEW #2 | role senior-fullstack | omp | $OPUS | high | why: cross-component diff
Skills: .agents/skills/architecture-review/SKILL.md - project-local version wins; ponytail-review - complexity check")
expect 'a project-local skill path and a core skill are reported as selected' pass "$PROJECT" omp "$OPUS" high '.agents/skills/architecture-review/SKILL.md,ponytail-review'
GLOBAL_SWAP=$(t swap.txt "Routing: REVIEW #2 | role senior-fullstack | omp | $OPUS | high | why: cross-component diff
Skills: architecture-review - global default; ponytail-review - complexity check")
expect 'substituting the global skill for the selected project-local one is rejected' fail "$GLOBAL_SWAP" omp "$OPUS" high '.agents/skills/architecture-review/SKILL.md,ponytail-review'

# --- 3. Post-work Skill evidence derives from the worker transcript ---------
EVIDENCE_OK=$(t ev-ok.txt "$(cat "$IMPL")
Skill evidence:
- $TDD: ran \`bash tests/routing-trace.sh\` before implementing and saw \`ROUTING TRACE TESTS FAIL\`
- $VBC: selected, but no strong application evidence observed")
expect 'evidence citing verbatim transcript excerpts is accepted' pass "$EVIDENCE_OK" omp "$OPUS" high "$TDD,$VBC" "$TRANSCRIPT"
EVIDENCE_FALSE=$(t ev-false.txt "$(cat "$IMPL")
Skill evidence:
- $TDD: watched \`npm test\` fail first
- $VBC: selected, but no strong application evidence observed")
expect 'evidence citing something the worker never did is rejected' fail "$EVIDENCE_FALSE" omp "$OPUS" high "$TDD,$VBC" "$TRANSCRIPT"
EVIDENCE_BARE=$(t ev-bare.txt "$(cat "$IMPL")
Skill evidence:
- $TDD: applied test-driven development throughout
- $VBC: selected, but no strong application evidence observed")
expect 'a bare "applied" claim with no cited observation is rejected' fail "$EVIDENCE_BARE" omp "$OPUS" high "$TDD,$VBC" "$TRANSCRIPT"
EVIDENCE_UNSELECTED=$(t ev-unsel.txt "$(cat "$IMPL")
Skill evidence:
- $TDD: saw \`ROUTING TRACE TESTS FAIL\`
- $VBC: selected, but no strong application evidence observed
- systematic-debugging: saw \`ROUTING TAXONOMY TESTS PASS\`")
expect 'evidence for a skill the brief never selected is rejected' fail "$EVIDENCE_UNSELECTED" omp "$OPUS" high "$TDD,$VBC" "$TRANSCRIPT"
EVIDENCE_GAP=$(t ev-gap.txt "$(cat "$IMPL")
Skill evidence:
- $TDD: saw \`ROUTING TRACE TESTS FAIL\`")
expect 'a selected skill with no evidence line at all is rejected' fail "$EVIDENCE_GAP" omp "$OPUS" high "$TDD,$VBC" "$TRANSCRIPT"
EVIDENCE_LONG=$(t ev-long.txt "$(cat "$IMPL")
Skill evidence:
- $TDD: ran \`bash tests/routing-trace.sh\`; saw \`ROUTING TRACE TESTS FAIL\`; then \`ROUTING TAXONOMY TESTS PASS\`
- $VBC: selected, but no strong application evidence observed")
expect 'more than two observations for one skill is rejected' fail "$EVIDENCE_LONG" omp "$OPUS" high "$TDD,$VBC" "$TRANSCRIPT"
expect 'a transcript supplied without any Skill evidence block is rejected' fail "$IMPL" omp "$OPUS" high "$TDD,$VBC" "$TRANSCRIPT"
EVIDENCE_DUP=$(t ev-dup.txt "$(cat "$IMPL")
Skill evidence:
- $TDD: watched \`never-ran-test\` fail
- $TDD: selected, but no strong application evidence observed
- $VBC: selected, but no strong application evidence observed")
expect 'two evidence lines for one skill are rejected (a later line must not mask an earlier false one)' fail \
  "$EVIDENCE_DUP" omp "$OPUS" high "$TDD,$VBC" "$TRANSCRIPT"
# A citation only proves the text occurs somewhere in the transcript; it
# cannot tell a run from a quote or a denial. check therefore prints the
# transcript line holding each citation, so the Captain reads its context.
NEGATED=$(t negated.txt 'Worker report: I did not run any tests. The brief suggested: "run bash tests/red.sh and expect FAIL expected".')
EVIDENCE_NEGATED=$(t ev-negated.txt "$(cat "$IMPL")
Skill evidence:
- $TDD: ran \`bash tests/red.sh\` before implementation; saw \`FAIL expected\`
- $VBC: selected, but no strong application evidence observed")
expect_shows 'a citation found only inside a denial surfaces that transcript line for human inspection' \
  'I did not run any tests' "$EVIDENCE_NEGATED" omp "$OPUS" high "$TDD,$VBC" "$NEGATED"

# --- 4. Real dispatch/brief/spawn seam --------------------------------------
# The real, unmodified official bin/fm-spawn.sh launches one task on an
# isolated tmux server (never the shared session) into a real treehouse
# worktree of a disposable project - the same seam tests/multi-project-
# captain.sh uses. Only the omp executable is faked: it records the argv it
# was really launched with and, when the delivered brief names the fixture
# project skill, runs that skill's ./check.sh into its own transcript. This
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
  printf '{"models":[{"provider":"anthropic","id":"claude-opus-5-5","selector":"anthropic/claude-opus-5-5"},{"provider":"anthropic","id":"claude-sonnet-5","selector":"anthropic/claude-sonnet-5"}]}\n'
  exit 0
fi
printf '%s\n' "$@" > worker-argv.txt
case "$*" in
  *.agents/skills/trace-canary/SKILL.md*) { printf '$ ./check.sh\n'; ./check.sh; } > worker-transcript.tmp ;;
  *) : > worker-transcript.tmp ;;
esac
mv worker-transcript.tmp worker-transcript.txt
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
Skills: .agents/skills/trace-canary/SKILL.md - project check before done; verification-before-completion - completion claim needs fresh evidence")

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
    while [ ! -f "$wt/worker-transcript.txt" ] && [ "$waited" -lt 100 ]; do sleep 0.1; waited=$((waited + 1)); done
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

    SEAM_EVIDENCE=$(t seam-ev.txt "$(cat "$CAPTAIN_TRACE")
Skill evidence:
- .agents/skills/trace-canary/SKILL.md: worker ran \`\$ ./check.sh\` and saw \`CHECK OK\`
- verification-before-completion: selected, but no strong application evidence observed")
    expect 'seam: post-work evidence cites what the launched worker actually did' pass \
      "$SEAM_EVIDENCE" omp "$launched_model" "$launched_effort" "$selected" "$wt/worker-transcript.txt"
    SEAM_FALSE=$(t seam-false.txt "$(cat "$CAPTAIN_TRACE")
Skill evidence:
- .agents/skills/trace-canary/SKILL.md: worker ran \`\$ ./check.sh\` and saw \`CHECK OK\`
- verification-before-completion: worker re-ran \`bash tests/all.sh\` before claiming done")
    expect 'seam: evidence claiming a verification run the worker never made is rejected' fail \
      "$SEAM_FALSE" omp "$launched_model" "$launched_effort" "$selected" "$wt/worker-transcript.txt"
  fi
fi

printf '\nROUTING TRACE TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
