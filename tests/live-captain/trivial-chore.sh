# Scenario 4: a one-line mechanical change that is fully specified. select must classify it trivial and print the
# trivial-chore exception: the chore role, one worker, no workflow state file, no fm-workflow next call.
SCN_PROJECT=duration-cli
SCN_BAD="no-select select-late start-workflow wrong-role second-worker no-handoff"

scn_prompt() {
  cat <<'TXT'
In duration-cli, duration.py has the line __version__ = "0.3.1". Change it to "0.3.2". That string is the
only thing to touch - no other file, no changelog, no tag. Open a PR.
TXT
}

scn_judge() { j_exception 'trivial' '^none: trivial-chore' 1 1 'chore'; }

scn_canned() { canned_exception "$1" bump-version duration-cli trivial -- chore 0 'bump the version string'; }
