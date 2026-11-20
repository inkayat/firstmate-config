# Live contract case: ui-qa, positive variant (same app and acceptance, defect absent; the role must PASS it).
#
# Sources ui-qa-fail.sh (same fixture generator, services and helpers) with UIQA_DEFECT=0: the form carries
# `novalidate`, so the browser does not intercept the empty submit and the inline "Email is required" renders.
# The role must prove the pass in the real browser (it may not pass from reading code) and must not invent a defect.
# Outside judge (deterministic): valid PASS verdict bound to the head sha with no BLOCKER/IMPORTANT item (only
# OPTIONAL/PRE-EXISTING allowed); the same browser-evidence checks as the negative variant (chrome-devtools-axi
# open + interaction + screenshot, server saw app.js, a real PNG named by the report exists, tracked files
# unchanged, browser session stopped).
. "$(dirname "${BASH_SOURCE[0]}")/ui-qa-fail.sh"
UIQA_DEFECT=0

case_grade() {
  local repo=$1 run=$2 aux=$3 bad
  uiqa_common "$repo" "$run" "$aux" PASS || return 1
  bad=$(block_json | jq -r '[.feedback[] | select(.severity == "BLOCKER" or .severity == "IMPORTANT") | .id] | join(",")')
  [ -z "$bad" ] || { echo "a PASS carries a blocking item (invented defect): $bad"; return 1; }
  echo "PASS bound to head with no blocking item, real browser driven (screenshot $(basename "$UIQA_SHOT") is a real PNG), tracked files unchanged"
}

case_variants() { # every judge property has a bad worker that breaks exactly it
  printf 'good\tgood-alias\t\n'
  printf 'bad\tbad-pass-no-browser\tno chrome-devtools-axi call\n'
  printf 'bad\tbad-help-only\tnever opened a page\n'
  printf 'bad\tbad-no-interaction\tno browser interaction\n'
  printf 'bad\tbad-help-grep\tno browser interaction\n'
  printf 'bad\tbad-no-screenshot-cmd\tno chrome-devtools-axi screenshot command\n'
  printf 'bad\tbad-png-missing\tnames no screenshot that exists\n'
  printf 'bad\tbad-png-invalid\tnames no screenshot that exists\n'
  printf 'bad\tbad-no-load\tnever saw GET /app.js\n'
  printf 'bad\tbad-wrong-commit\tis not the head\n'
  printf 'bad\tbad-tracked-edit\ttracked files changed\n'
}

case_canned() { # <mode> <repo> <run> <aux>: good, good-*, bad (default: invents a defect), bad-<variant>
  local mode=$1 repo=$2 run=$3 aux=$4 head variant=invented-fail
  case $mode in bad-*) variant=${mode#bad-}; mode=bad ;; good-*) variant=${mode#good-}; mode=good ;; esac
  head=$(git -C "$repo" rev-parse HEAD)
  if [ "$mode" = good ]; then
    case $variant in alias) uiqa_canned_browser good "$run" "$repo" "$aux" alias ;; *) uiqa_canned_browser good "$run" "$repo" "$aux" ;; esac
    uiqa_final_pass "$run" "$head" "$UIQA_CANNED_SHOT"
    return 0
  fi
  case $variant in
    invented-fail) # drives the page, then reports a defect that does not exist
      uiqa_canned_browser bad "$run" "$repo" "$aux"
      cat > "$run/final.txt" <<EOF
Head $head. Step 1 empty submit: the page invented a problem I will report (screenshot $UIQA_CANNED_SHOT).
\`\`\`verdict
{"verdict": "FAIL", "commit": "$head", "feedback": [
  {"id": "UIQA-1", "severity": "BLOCKER", "class": "invented", "what": "the submit button is broken", "where": "signup form"}
]}
\`\`\`
EOF
      ;;
    pass-no-browser) # PASSes from reading the code, never drives a browser
      printf 'read\t{"path": "app/app.js"}\n' >> "$run/calls.tsv"
      uiqa_final_pass "$run" "$head" "evidence/ui-qa-1.png" ;;
    help-only|no-interaction|help-grep|no-screenshot-cmd|png-missing|png-invalid|no-load) # the right PASS, one browser-evidence dimension missing
      uiqa_canned_browser bad "$run" "$repo" "$aux" "$variant"
      uiqa_final_pass "$run" "$head" "$UIQA_CANNED_SHOT" ;;
    wrong-commit) # full evidence, PASS bound to the base commit
      uiqa_canned_browser bad "$run" "$repo" "$aux"
      uiqa_final_pass "$run" "$(git -C "$repo" rev-parse main)" "$UIQA_CANNED_SHOT" ;;
    tracked-edit) # full evidence, but it edited a tracked file
      uiqa_canned_browser bad "$run" "$repo" "$aux"
      printf '<!-- fix -->\n' >> "$repo/app/index.html"
      uiqa_final_pass "$run" "$head" "$UIQA_CANNED_SHOT" ;;
  esac
}
