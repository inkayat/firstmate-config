# Scenario 5: the human explicitly says no workflow for this task. The Captain must record the stated choice with
# fm-workflow select <kind> --none '<choice>' (the captain-none exception) and create no workflow state.
SCN_PROJECT=duration-cli
SCN_BAD="no-select select-late start-workflow no-handoff ignored-choice second-worker"

scn_prompt() {
  cat <<'TXT'
Add a --verbose flag to duration-cli's cli.py that prints the parsed parts (for example 1h30m -> 1h + 30m)
before the total. Skip the workflow for this one - I do not want the QA and review steps, just a single worker
that builds it and opens the PR.
TXT
}

j_none_reason() { # the select call carries --none with a non-empty stated choice
  local r
  r=$(evq '[.[] | select(.tool == "fm-workflow" and .args[0] == "select" and .rc == 0)] | (last // empty) | .args as $a | ([range(0; ($a | length))] | map(select($a[.] == "--none")) | (first // -1)) as $i | if $i < 0 then "" else ($a[$i + 1] // "") end')
  [ -n "$r" ] && ok "select recorded the stated choice: $(printf '%s' "$r" | cut -c1-90)" || bad "the select call carries no --none '<stated choice>'"
}

scn_judge() {
  j_exception 'feature|feature-unclear|bugfix|refactor|ui' '^none: captain-none' 1 1 - || return 1
  j_none_reason
}

scn_canned() {
  case $1 in
    ignored-choice) canned_workflow good verbose-flag duration-cli feature direct-pr build-test-review 'add a verbose flag' ;;
    *) canned_exception "$1" verbose-flag duration-cli feature --none 'captain said no workflow for this task' -- senior-fullstack 0 'add a verbose flag' ;;
  esac
}
