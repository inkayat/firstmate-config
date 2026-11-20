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

case_canned() { # good|bad <repo> <run> <aux>
  local mode=$1 repo=$2 run=$3 aux=$4 head
  head=$(git -C "$repo" rev-parse HEAD)
  uiqa_canned_browser "$mode" "$run" "$repo" "$aux"
  if [ "$mode" = good ]; then
    cat > "$run/final.txt" <<EOF
Head $head. Plan: step 1 empty submit, step 2 no-@ submit, step 3 valid submit. Observed: step 1 shows "Email is required", step 2 "Enter a valid email address", step 3 "Subscribed dana@example.test to the Pro plan"; console clean (screenshot $UIQA_CANNED_SHOT).
\`\`\`verdict
{"verdict": "PASS", "commit": "$head", "feedback": [
  {"id": "UIQA-1", "severity": "OPTIONAL", "class": "a11y", "what": "the result region has no heading; screenshot $UIQA_CANNED_SHOT", "where": "result region"}
]}
\`\`\`
EOF
  else
    cat > "$run/final.txt" <<EOF
Head $head. Step 1 empty submit: the page invented a problem I will report (screenshot $UIQA_CANNED_SHOT).
\`\`\`verdict
{"verdict": "FAIL", "commit": "$head", "feedback": [
  {"id": "UIQA-1", "severity": "BLOCKER", "class": "invented", "what": "the submit button is broken", "where": "signup form"}
]}
\`\`\`
EOF
  fi
}
