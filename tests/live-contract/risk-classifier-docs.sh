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

case_variants() { # every judge property has a bad worker that breaks exactly it
  printf 'good\tgood-catfile-shortsha\t\n'
  printf 'bad\tbad-inflated-tier\ttier is .medium.\n'
  printf 'bad\tbad-invented-checklist\tmatched checklist is .R-5., the diff triggers .\n'
  printf 'bad\tbad-security-required\tsecurity is .required.\n'
  printf 'bad\tbad-no-base-read\tnever read REVIEW.md from the base branch\n'
  printf 'bad\tbad-head-rules-read\tnever read REVIEW.md from the base branch\n'
  printf 'bad\tbad-wrong-commit\tnot the branch head\n'
  printf 'bad\tbad-repo-dirty\tleft changes\n'
  printf 'bad\tbad-no-readme-reason\tnever quote the README.md hunk\n'
  printf 'bad\tbad-tier-high\ttier is .high.\n'
}

case_canned() { # <mode> <repo> <run> <aux>: good, good-*, bad (default), bad-<variant>
  local mode=$1 repo=$2 run=$3 head variant=inflated-tier
  case $mode in bad-*) variant=${mode#bad-}; mode=bad ;; good-*) variant=${mode#good-}; mode=good ;; esac
  head=$(git -C "$repo" rev-parse HEAD)
  {
    printf 'bash\t{"command": "git diff --stat main..HEAD && git diff main..HEAD"}\n'
    if [ "$variant" = catfile-shortsha ]; then printf 'bash\t{"command": "git cat-file -p main:REVIEW.md"}\n'; else printf 'bash\t{"command": "git show main:REVIEW.md"}\n'; fi
  } >> "$run/calls.tsv"
  if [ "$mode" = good ]; then
    [ "$variant" = catfile-shortsha ] && head=$(printf '%s' "$head" | cut -c1-10)
    {
      printf 'Head %s: one hunk in README.md, "recieves" -> "receives". Docs only.\n' "$head"
      risk_canned_block low not-required "$head" '[]' '[]' '["diff edits README.md:2 only (recieves -> receives): docs-only is low", "blast radius: none, no code path touched"]'
    } > "$run/final.txt"
    return 0
  fi
  case $variant in
    inflated-tier) # inflates: the repo has auth and billing code, so medium plus R-1/R-2
      { risk_canned_block medium required "$head" '["auth-session"]' '["R-1", "R-2"]' '["README.md edited, repo handles auth and payments"]'; } > "$run/final.txt" ;;
    invented-checklist) # tier right, but invents a checklist match
      { risk_canned_block low not-required "$head" '[]' '["R-5"]' '["README.md edited"]'; } > "$run/final.txt" ;;
    security-required) # tier right, security wrongly required
      { risk_canned_block low required "$head" '[]' '[]' '["README.md edited"]'; } > "$run/final.txt" ;;
    no-base-read) # right block but never read the rules from base
      grep -v 'REVIEW' "$run/calls.tsv" > "$run/calls.new" && mv "$run/calls.new" "$run/calls.tsv"
      { risk_canned_block low not-required "$head" '[]' '[]' '["README.md edited"]'; } > "$run/final.txt" ;;
    head-rules-read) # right block, but the rules were read from HEAD, not from main
      grep -v 'REVIEW' "$run/calls.tsv" > "$run/calls.new" && mv "$run/calls.new" "$run/calls.tsv"
      printf 'bash\t{"command": "git show HEAD:REVIEW.md"}\n' >> "$run/calls.tsv"
      { risk_canned_block low not-required "$head" '[]' '[]' '["README.md edited"]'; } > "$run/final.txt" ;;
    wrong-commit) # right block bound to the base commit
      { risk_canned_block low not-required "$(git -C "$repo" rev-parse main)" '[]' '[]' '["README.md edited"]'; } > "$run/final.txt" ;;
    repo-dirty) # right block, left a file in the repo
      printf 'scratch\n' > "$repo/notes.txt"
      { risk_canned_block low not-required "$head" '[]' '[]' '["README.md edited"]'; } > "$run/final.txt" ;;
    no-readme-reason) # right block, reasons never quote the README hunk
      { risk_canned_block low not-required "$head" '[]' '[]' '["only prose changed"]'; } > "$run/final.txt" ;;
    tier-high) # inflates to high
      { risk_canned_block high required "$head" '[]' '[]' '["README.md edited"]'; } > "$run/final.txt" ;;
  esac
}
