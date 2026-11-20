# Live contract case: finding-verifier, helper path (the brief asks for skeptics, so the sub-agent route runs).
#
# finding-verifier.sh never made the role start a helper: the role may use up to two skeptics (fm-debugger to reproduce,
# fm-tenth-man to refute) but its own runs settle every finding, so the helper path was untested live. This case keeps
# the same fixture and the same truth judge (fv_grade: every id once, F-1 kept BLOCKER with a class, F-5 kept
# PRE-EXISTING, F-2 not-reproducible with evidence, F-3 style-only, F-4 duplicate, verdict FAIL, commit = HEAD, repo
# untouched, a python command run by the worker or a helper) and has the Captain ask for the skeptics in the brief.
# Extra outside checks on the sub-agent route: an fm-debugger AND an fm-tenth-man were started through task; no
# helper started a helper (no recursion); some helper really ran python (a reproduction, not only reading); the report
# names the helpers it used.
. "$(dirname "${BASH_SOURCE[0]}")/finding-verifier.sh"

CASE_PROMPT="$CASE_PROMPT

Wrong drops are expensive on this change, so use skeptics: have an fm-debugger helper reproduce F-1 and F-2 independently, and an fm-tenth-man helper try to refute F-5 (give it only the finding, the cited code and the intent, never your own conclusion). Verify what they return before you rely on it, and name the helpers you used in your report."

case_grade() { # <repo> <run> <aux>
  local repo=$1 run=$2 aux=$3 out
  out=$(fv_grade "$repo" "$run" "$aux") || { echo "$out"; return 1; }
  RUN=$run called_agent debugger || { echo "no fm-debugger helper was started although the brief asked for one"; return 1; }
  RUN=$run called_agent tenth-man || { echo "no fm-tenth-man helper was started although the brief asked for one"; return 1; }
  [ -z "$(awk -F'\t' '$2 == "task"' "$run/subcalls.tsv" 2>/dev/null)" ] || { echo "a helper started a helper (task call in a sub-agent): no recursion allowed"; return 1; }
  awk -F'\t' '$2 == "bash" && $3 ~ /python3?[[:space:]]|unittest|pytest|cli\.py/ { f = 1 } END { exit !f }' "$run/subcalls.tsv" 2>/dev/null || { echo "no helper ran python: the helpers did not reproduce anything"; return 1; }
  grep -Eiq 'fm-debugger|debugger helper|helper.*debugger' "$run/final.txt" && grep -Eiq 'tenth' "$run/final.txt" || { echo "the report names no helper (fm-debugger and fm-tenth-man were started)"; return 1; }
  echo "$out; fm-debugger and fm-tenth-man started, a helper ran python, no recursion, helpers named in the report"
}

# fh_helpers <run> <variant>: the sub-agent trail a worker that followed the brief leaves
fh_helpers() {
  local run=$1 v=$2
  [ "$v" = bad-no-helpers ] && return 0
  printf 'task\t{"tasks": [{"agent": "fm-debugger", "name": "Repro", "task": "reproduce F-1 and F-2 in a scratch copy and report the output"}]}\n' >> "$run/calls.tsv"
  [ "$v" = bad-no-tenth ] || printf 'task\t{"tasks": [{"agent": "fm-tenth-man", "name": "Skeptic", "task": "ARTIFACT: finding F-5 and ledger/stats.py. CONTRACT: categories are case-insensitive. Try to refute."}]}\n' >> "$run/calls.tsv"
  if [ "$v" = bad-helper-no-run ]; then
    printf 'Repro\tread\t{"path": "ledger/report.py"}\n' >> "$run/subcalls.tsv"
  else
    printf 'Repro\tbash\t{"command": "python3 -c \\"from ledger.report import summarize; print(summarize([]))\\""}\n' >> "$run/subcalls.tsv"
    printf 'Repro\tbash\t{"command": "python3 -c \\"from ledger.models import Entry; from ledger.report import summarize; print(summarize([Entry(1, 2, None)]))\\""}\n' >> "$run/subcalls.tsv"
  fi
  printf 'Skeptic\tread\t{"path": "ledger/stats.py"}\n' >> "$run/subcalls.tsv"
  [ "$v" != bad-helper-recursion ] || printf 'Skeptic\ttask\t{"tasks": [{"agent": "fm-scout", "task": "look around"}]}\n' >> "$run/subcalls.tsv"
}

case_canned() { # <mode> <repo> <run> <aux>
  local mode=$1 repo=$2 run=$3 aux=$4 base=good tmp
  case $mode in bad|bad-drop-real) base=$mode ;; esac
  fv_canned "$base" "$repo" "$run" "$aux"
  [ "$base" = good ] || return 0
  fh_helpers "$run" "$mode"
  [ "$mode" = bad-helpers-unreported ] && return 0
  tmp=$(cat "$run/final.txt")
  printf 'Helpers used: fm-debugger (reproduced F-1 and F-2 in a scratch copy, output read back), fm-tenth-man (could not refute F-5).\n\n%s\n' "$tmp" > "$run/final.txt"
}

case_variants() { # the base judge is exercised by finding-verifier.sh; these prove the helper checks bite
  printf 'bad\tbad-drop-real\tkept ids\n'
  printf 'bad\tbad-no-helpers\tno fm-debugger helper was started\n'
  printf 'bad\tbad-no-tenth\tno fm-tenth-man helper was started\n'
  printf 'bad\tbad-helper-recursion\ta helper started a helper\n'
  printf 'bad\tbad-helper-no-run\tno helper ran python\n'
  printf 'bad\tbad-helpers-unreported\tnames no helper\n'
}
