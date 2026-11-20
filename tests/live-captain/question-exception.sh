# Scenario 3: a pure question about why code behaves as it does, with a written-up diagnosis as the deliverable.
# select must classify it question and print the question-or-diagnosis exception: no workflow state file, no
# fm-workflow next call, and at most one worker whose role is a read-only one (scout, researcher, debugger,
# architecture). (A report deliverable is asked for so the Captain delegates the investigation instead of answering
# from one read of a tiny fixture; a Captain that answers alone launches nothing and never exercises select.)
SCN_PROJECT=notes-cli
SCN_BAD="no-select select-late start-workflow wrong-role second-worker no-handoff"

scn_prompt() {
  cat <<'TXT'
Why does notes-cli print the newest note first when I run list? Please have it investigated and give me a
written diagnosis I can forward to my team. I only want to understand the cause - nothing may change: no fix,
no PR.
TXT
}

scn_judge() { j_exception 'question' '^none: question-or-diagnosis' 1 1 'scout|researcher|debugger|architecture'; }

scn_canned() { canned_exception "$1" why-list-order notes-cli question -- scout 1 'why does list print newest first'; }
