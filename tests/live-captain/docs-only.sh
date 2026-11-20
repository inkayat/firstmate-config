# Scenario 7: a README-only prose change. select must classify it docs and print the out-of-scope result: the
# forcing rule covers code-changing tasks, so no workflow state file and no fm-workflow next call.
SCN_PROJECT=duration-cli
SCN_BAD="no-select select-late start-workflow no-handoff wrong-kind second-worker"

scn_prompt() {
  cat <<'TXT'
The Usage section of duration-cli's README explains the unit table badly. Rewrite that prose so it reads
clearly and add two worked examples. README only: no code, no tests, no behavior change. Open a PR.
TXT
}

scn_judge() { j_exception 'docs' '^none: out-of-scope' 1 1 -; }

scn_canned() {
  case $1 in
    wrong-kind) canned_workflow good readme-usage duration-cli feature direct-pr build-test-review 'rewrite the readme usage section' ;;
    *) canned_exception "$1" readme-usage duration-cli docs -- technical-writer 0 'rewrite the readme usage section' ;;
  esac
}
