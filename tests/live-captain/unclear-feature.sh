# Scenario 8: an ambiguous and oversized request. select must classify it feature-unclear and resolve
# plan-build-test-review; the first worker is the planner (the plan step), and nothing later is launched.
SCN_PROJECT=taskbook
SCN_CONTROL=1
SCN_BAD="good-relative-path spec-header-trimmed no-select select-late no-next brief-no-handoff second-step no-trace trace-wrong wrong-delivery"

scn_prompt() {
  cat <<'TXT'
I want taskbook to work across all my devices, even offline, and to be shareable with my team. Make it
happen - I have not decided how syncing, accounts or sharing should work, so work out what makes sense and
build it.
TXT
}

scn_judge() { j_workflow 'feature-unclear' direct-pr 'plan-build-test-review' 'planner'; }

scn_canned() { canned_workflow "$1" taskbook-sync taskbook feature-unclear direct-pr plan-build-test-review 'sync taskbook across devices'; }
