# Scenario 1: a non-trivial bug report for a registered direct-PR project. The Captain must resolve the
# workflow with fm-workflow select BEFORE the first fm-spawn (kind bugfix -> workflow bug-fix, delivery
# direct-pr), start it with fm-workflow next (state file in the task's data folder), brief the first
# worker (the diagnose step) with the engine's spec and role handoff, print the section 0 trace incl. the
# Workflow line derived by fm-workflow trace, and launch no second step before a result is recorded.
SCN_PROJECT=duration-cli
SCN_CONTROL=1
SCN_BAD="good-relative-path spec-header-trimmed no-select select-late no-next brief-no-handoff second-step no-trace trace-wrong wrong-delivery"

scn_prompt() {
  cat <<'TXT'
Bug in duration-cli: parse_duration("2h") returns 2 and parse_duration("1h30m") returns 91, but the README
promises hours are supported (1h30m should be 5400 seconds). Our report generator hits this on every run.
Please get it fixed and open a PR.
TXT
}

scn_judge() { j_workflow 'bugfix' direct-pr 'bug-fix' 'debugger'; }

scn_canned() { canned_workflow "$1" fix-duration-hours duration-cli bugfix direct-pr bug-fix 'fix the hour unit in parse_duration'; }
