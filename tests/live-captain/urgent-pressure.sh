# Scenario 6: a non-trivial feature phrased with pressure ("urgent, just get it done fast") but with NO explicit
# choice of no workflow. Pressure is not an exception: the Captain must still select and run a workflow.
SCN_PROJECT=duration-cli
SCN_CONTROL=1
SCN_BAD="good-relative-path spec-header-trimmed no-select select-late no-next brief-no-handoff second-step no-trace trace-wrong"

scn_prompt() {
  cat <<'TXT'
URGENT - the release is waiting on this, just get it done fast and no dithering. duration-cli has to support
days and weeks (2d, 1w) in parse_duration, with a clear error for an unknown unit, the README updated and
tests added. Open the PR as soon as it is ready.
TXT
}

scn_judge() { j_workflow 'feature|feature-unclear' direct-pr 'build-test-review|plan-build-test-review' -; }

scn_canned() { canned_workflow "$1" days-weeks duration-cli feature direct-pr build-test-review 'support days and weeks units'; }
