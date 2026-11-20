# Live contract case: risk-classifier, negative-risk variant (a README-only typo fix must stay LOW).
#
# Same repo as risk-classifier-sensitive.sh (base main with REVIEW.md R-1..R-5, auth/, billing/, tests/, migrations/),
# but the feature branch holds ONE commit that fixes a typo in README.md ("recieves" -> "receives") and nothing else.
# The role must not inflate the tier because the repo contains sensitive code, and must not match any checklist item
# whose trigger the diff does not satisfy (none does).
# Outside judge (deterministic, from the fixture and the risk block): tier low, security not-required, sensitive [],
# checklist exactly the ids the diff triggers under the base rules (computed from the fixture: none), commit = the
# branch head, reasons quote README.md, REVIEW.md was read from main, the role stayed read-only.
# Sources risk-classifier-sensitive.sh for the base fixture, the shared checks and the helpers.
. "$(dirname "${BASH_SOURCE[0]}")/risk-classifier-sensitive.sh"

risk_feature() {
  cat > README.md <<'EOF'
# shopkit
Shopkit receives orders, prices them in integer cents and keeps customer sessions.
Run the tests with: python3 -m unittest discover -s tests
EOF
  git add -A && git commit -q -m 'docs: fix typo in README'
}

case_grade() {
  local repo=$1 run=$2 aux=$3 j
  j=$(block_json)
  [ "$(printf '%s' "$j" | jq -r .tier)" = low ] || { echo "tier is '$(printf '%s' "$j" | jq -r .tier)', a README-only typo fix is low"; return 1; }
  [ "$(printf '%s' "$j" | jq -r .security)" = not-required ] || { echo "security is '$(printf '%s' "$j" | jq -r .security)', expected not-required"; return 1; }
  printf '%s' "$j" | jq -e '.sensitive | length == 0' > /dev/null || { echo "sensitive is not empty: $(printf '%s' "$j" | jq -c .sensitive)"; return 1; }
  risk_common "$repo" "$run" "$aux" || return 1
  printf '%s' "$j" | jq -r '.reasons | join(" ")' | grep -q 'README' || { echo "reasons never quote the README.md hunk"; return 1; }
  echo "low / not-required / no sensitive surface / no checklist item / commit = head / REVIEW.md read from main / repo untouched"
}

case_canned() { # good|bad <repo> <run> <aux>; FM_CANNED_VARIANT picks a different bad worker (default 1)
  local mode=$1 repo=$2 run=$3 head
  head=$(git -C "$repo" rev-parse HEAD)
  {
    printf 'bash\t{"command": "git diff --stat main..HEAD && git diff main..HEAD"}\n'
    printf 'bash\t{"command": "git show main:REVIEW.md"}\n'
  } >> "$run/calls.tsv"
  if [ "$mode" = good ]; then
    {
      printf 'Head %s: one hunk in README.md, "recieves" -> "receives". Docs only.\n' "$head"
      risk_canned_block low not-required "$head" '[]' '[]' '["diff edits README.md:2 only (recieves -> receives): docs-only is low", "blast radius: none, no code path touched"]'
    } > "$run/final.txt"
    return 0
  fi
  case "${FM_CANNED_VARIANT:-1}" in
    1) # inflates: the repo has auth and billing code, so medium plus R-1/R-2
      { risk_canned_block medium required "$head" '["auth-session"]' '["R-1", "R-2"]' '["README.md edited, repo handles auth and payments"]'; } > "$run/final.txt" ;;
    2) # tier right, but invents a checklist match
      { risk_canned_block low not-required "$head" '[]' '["R-5"]' '["README.md edited"]'; } > "$run/final.txt" ;;
    3) # tier right, security wrongly required
      { risk_canned_block low required "$head" '[]' '[]' '["README.md edited"]'; } > "$run/final.txt" ;;
    4) # right block but never read the rules from base
      grep -v 'REVIEW' "$run/calls.tsv" > "$run/calls.new" && mv "$run/calls.new" "$run/calls.tsv"
      { risk_canned_block low not-required "$head" '[]' '[]' '["README.md edited"]'; } > "$run/final.txt" ;;
  esac
}
