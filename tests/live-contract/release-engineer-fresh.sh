# Live contract case: release-engineer, everything current (the role must PASS it, and must actually run the check).
#
# Same fixture as release-engineer-stale.sh, but case_serve records the qa, review and security gate verdicts ALL
# against the head commit. The changelog line is present and python3 check.py passes at the head. The role must not
# invent a defect and must re-run the cheap check itself.
# Outside judge (deterministic): valid verdict PASS bound to the head sha with no BLOCKER/IMPORTANT item; the
# worker ran the cheap check (python3 check.py appears in its tool calls); the worker read the gate files; the
# fixture own check really passes at the head (a sanity check on the fixture); read-only (git status clean,
# HEAD unmoved).
. "$(dirname "${BASH_SOURCE[0]}")/release-engineer-stale.sh"

rel_qa_commit() { git -C "$1" rev-parse HEAD; } # every gate names the head

case_grade() {
  local repo=$1 run=$2 aux=$3 bad
  rel_common "$repo" PASS || return 1
  bad=$(block_json | jq -r '[.feedback[] | select(.severity == "BLOCKER" or .severity == "IMPORTANT") | .id] | join(",")')
  [ -z "$bad" ] || { echo "a PASS carries a blocking item (invented defect): $bad"; return 1; }
  # python3 check.py must be a command (start of a command segment, optionally after env assignments, time/timeout and python flags), not text that mentions it (grep python3 check.py CONTRIBUTING.md)
  call_has '(^|[;&|("'"'"'`]) *(([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*(time +|timeout +[0-9]+ +)?)python3? +(-[A-Za-z]+ +)*(\./)?check\.py' || { echo "the worker never ran the cheap check (python3 check.py)"; return 1; }
  ( cd "$repo" && PYTHONDONTWRITEBYTECODE=1 python3 check.py > /dev/null 2>&1 ) || { echo "fixture error: python3 check.py fails at the head"; return 1; }
  echo "PASS bound to head with no blocking item, python3 check.py ran, gates read, repo untouched"
}

case_variants() { # every judge property has a bad worker that breaks exactly it
  printf 'good\tgood-cd-check-short-sha\t\n'
  printf 'bad\tbad-no-check-run\tnever ran the cheap check\n'
  printf 'bad\tbad-check-grep-only\tnever ran the cheap check\n'
  printf 'bad\tbad-wrong-commit\tis not the head\n'
  printf 'bad\tbad-no-gate-read\tnever looked at the recorded gate verdicts\n'
  printf 'bad\tbad-repo-dirty\tleft changes\n'
}

case_canned() { # <mode> <repo> <run> <aux>: good, good-*, bad (default: invents a stale gate), bad-<variant>
  local mode=$1 repo=$2 run=$3 head variant=invented-stale
  case $mode in bad-*) variant=${mode#bad-}; mode=bad ;; good-*) variant=${mode#good-}; mode=good ;; esac
  head=$(git -C "$repo" rev-parse HEAD)
  {
    printf 'bash\t{"command": "git rev-parse HEAD && git log --oneline main..HEAD"}\n'
    [ "$variant" = no-gate-read ] || printf 'bash\t{"command": "cat gates/qa.json gates/review.json gates/security.json"}\n'
  } >> "$run/calls.tsv"
  if [ "$mode" = good ]; then
    case $variant in
      cd-check-short-sha) # runs the check from a subshell in the repo, reports the abbreviated head sha
        printf 'bash\t{"command": "cd %s && python3 check.py"}\n' "$repo" >> "$run/calls.tsv"
        head=$(printf '%s' "$head" | cut -c1-9) ;;
      *) printf 'bash\t{"command": "python3 check.py"}\n' >> "$run/calls.tsv" ;;
    esac
    cat > "$run/final.txt" <<EOF
Delivery package: title, what/why, How it was verified (python3 check.py: ok), Risk low, How to revert: git revert, flag none.
Gate comparison: qa, review and security all name $head. CHANGELOG.md has the Unreleased line (CONTRIBUTING.md line 2).
\`\`\`verdict
{"verdict": "PASS", "commit": "$head", "feedback": [
  {"id": "REL-1", "severity": "OPTIONAL", "class": "notes", "what": "review note: test names could say what they assert (verbatim from review.json)", "where": "test_slug.py"}
]}
\`\`\`
EOF
    return 0
  fi
  case $variant in
    invented-stale) # invents a stale gate and never runs the check
      cat > "$run/final.txt" <<EOF
\`\`\`verdict
{"verdict": "FAIL", "commit": "$head", "feedback": [
  {"id": "REL-1", "severity": "IMPORTANT", "class": "stale-gate", "what": "QA verdict is stale", "where": "gate: qa"}
]}
\`\`\`
EOF
      ;;
    no-check-run) # right verdict, never ran the cheap check
      cat > "$run/final.txt" <<EOF
All gates name the head, changelog present, I trust the check passes.
\`\`\`verdict
{"verdict": "PASS", "commit": "$head", "feedback": []}
\`\`\`
EOF
      ;;
    check-grep-only) # right verdict, only grepped for the check command in CONTRIBUTING.md, never ran it
      printf 'bash\t{"command": "grep -n python3 check.py CONTRIBUTING.md"}\n' >> "$run/calls.tsv"
      cat > "$run/final.txt" <<EOF
All gates name the head, changelog present, the check command is documented.
\`\`\`verdict
{"verdict": "PASS", "commit": "$head", "feedback": []}
\`\`\`
EOF
      ;;
    wrong-commit) # PASS bound to the wrong commit
      printf 'bash\t{"command": "python3 check.py"}\n' >> "$run/calls.tsv"
      cat > "$run/final.txt" <<EOF
\`\`\`verdict
{"verdict": "PASS", "commit": "$(git -C "$repo" rev-parse main)", "feedback": []}
\`\`\`
EOF
      ;;
    no-gate-read) # right PASS and check, but the worker never opened ./gates
      printf 'bash\t{"command": "python3 check.py"}\n' >> "$run/calls.tsv"
      cat > "$run/final.txt" <<EOF
\`\`\`verdict
{"verdict": "PASS", "commit": "$head", "feedback": []}
\`\`\`
EOF
      ;;
    repo-dirty) # right PASS and check, but it left a file in the repo
      printf 'bash\t{"command": "python3 check.py"}\n' >> "$run/calls.tsv"
      printf 'scratch\n' > "$repo/notes.txt"
      cat > "$run/final.txt" <<EOF
\`\`\`verdict
{"verdict": "PASS", "commit": "$head", "feedback": []}
\`\`\`
EOF
      ;;
  esac
}
