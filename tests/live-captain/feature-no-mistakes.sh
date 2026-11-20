# Scenario 2: a non-trivial feature on a project whose delivery mode is no-mistakes. select must resolve to
# delegated-build (never build-test-review, which would put a manual reviewer on top of no-mistakes), and
# the first worker's brief carries the implementer role only: no reviewer or QA worker is launched.
SCN_PROJECT=notes-cli
SCN_CONTROL=1
SCN_BAD="good-relative-path spec-header-trimmed no-select select-late no-next brief-no-handoff second-step no-trace trace-wrong wrong-delivery"

scn_prompt() {
  cat <<'TXT'
Please add a --json option to notes-cli's list command: it prints the notes as a JSON array of objects with
id and text instead of the plain list, and the README and the tests cover it. Ship it through our usual
pipeline for that project.
TXT
}

scn_judge() { j_workflow 'feature|feature-unclear|bugfix|refactor|ui' no-mistakes 'delegated-build' -; }

scn_canned() { canned_workflow "$1" notes-json-flag notes-cli feature no-mistakes delegated-build 'add a json option to the list command'; }
