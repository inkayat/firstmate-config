# Live case: debugger (skill: systematic-debugging).
#
# Trap: `bash report.sh` dies with "REGION: unbound variable". The tree alone says
# "REGION is missing from config/defaults.env". The reason it is missing, and therefore the
# SAFE fix boundary (export it on the deploy host, do NOT re-add a default), exists only in a
# commit message three commits back: "OPS-4417". Two newer commits touch the same file / the
# docs so `git log -1` / `git diff HEAD~1` do not show it. The skill's Phase 1 step 3 "Check
# Recent Changes (git diff, recent commits)" is what finds it; ROLE.md only says "start with the
# reported symptom and retained evidence" and never mentions history.
# Control (same role, skill stripped): reads the files, runs the script, blames the missing
# variable, proposes re-adding REGION=... and never cites OPS-4417.
# Accepts: the failing command was run, no tracked file was changed, the final report cites
# OPS-4417 and REGION, and does not claim the failure is fixed.

CASE_KIND=role
CASE_ROLE=debugger
CASE_SKILL_ONLY_TOKENS="Phase Recent"
CASE_PROMPT='`bash report.sh` exits 1. Find out why it fails and report what you found.'

fx_commit() { git add -A && git -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m "$1"; }

case_setup() {
  mkdir -p config lib
  cat > report.sh <<'EOF'
#!/usr/bin/env bash
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/config/defaults.env"
. "$here/lib/names.sh"
printf 'report for %s (%s)\n' "$(bucket_name)" "$FORMAT"
EOF
  cat > lib/names.sh <<'EOF'
bucket_name() {
  echo "acme-${REGION}-reports"
}
EOF
  printf 'Run `bash report.sh`. Defaults live in config/defaults.env.\n' > README.md
  printf 'OUTPUT_DIR=out\nFORMAT=json\nREGION=eu-west-1\n' > config/defaults.env
  fx_commit 'initial report tool'
  printf 'OUTPUT_DIR=out\nFORMAT=json\n' > config/defaults.env
  fx_commit 'tidy defaults.env: drop REGION, deploy hosts export it now (OPS-4417)'
  printf 'OUTPUT_DIR=out\nFORMAT=csv\n' > config/defaults.env
  fx_commit 'config: default FORMAT is csv'
  printf 'Run `bash report.sh` from the repo root. Defaults live in config/defaults.env.\n' > README.md
  fx_commit 'docs: readme wording'
}

case_grade() {
  if ! git -C "$REPO" diff --quiet HEAD; then echo "tracked files were modified: $(changed_files | tr '\n' ' ')"; return 1; fi
  call_has '(bash|sh) +(-[a-z]+ +)*[^"|;&]*report\.sh|\./report\.sh' || { echo "never ran the failing command"; return 1; }
  final_has 'OPS-4417' || { echo "final report does not cite the commit message (OPS-4417): history was not checked"; return 1; }
  final_has 'REGION' || { echo "final report never names REGION"; return 1; }
  final_lacks '(I|have|has) (now |already )?(fixed|patched|applied the fix|restored)' || { echo "final report claims a fix"; return 1; }
  echo "ran the failing command, cited the removing commit (OPS-4417), repo untouched"
  return 0
}

case_canned() {
  local role=$1 mode=$2
  local sk=/home/u/.agents/skills
  if [ "$mode" = good ]; then
    {
      printf 'read\t{"path": "%s/systematic-debugging/SKILL.md"}\n' "$sk"
      printf 'bash\t{"command": "pwd -P && git rev-parse --show-toplevel"}\n'
      printf 'read\t{"path": "report.sh"}\n'
      printf 'bash\t{"command": "bash report.sh; echo exit=$?"}\n'
      printf 'bash\t{"command": "git log --stat --format=%%h%%x20%%s"}\n'
      printf 'bash\t{"command": "git show HEAD~2 -- config/defaults.env"}\n'
    } > "$RUN/calls.tsv"
    cat > "$RUN/final.txt" <<'EOF'
Symptom: `bash report.sh` exits 1 with `lib/names.sh: line 2: REGION: unbound variable` (reproduced).
Cause: report.sh sources config/defaults.env then lib/names.sh; bucket_name() expands ${REGION} under `set -u`.
Commit "tidy defaults.env: drop REGION, deploy hosts export it now (OPS-4417)" removed REGION=eu-west-1 from
defaults.env, so any host that does not export REGION fails. Rejected: names.sh itself changed (it did not).
Confidence high. Smallest fix boundary: export REGION on the host (per OPS-4417), not re-add the default; then rerun
`bash report.sh`. No files were changed.
EOF
  else
    {
      printf 'bash\t{"command": "pwd -P && git rev-parse --show-toplevel"}\n'
      printf 'read\t{"path": "report.sh"}\n'
      printf 'read\t{"path": "config/defaults.env"}\n'
      printf 'bash\t{"command": "bash report.sh; echo exit=$?"}\n'
    } > "$RUN/calls.tsv"
    cat > "$RUN/final.txt" <<'EOF'
`bash report.sh` fails with `REGION: unbound variable`. lib/names.sh uses ${REGION} but config/defaults.env does not
define REGION. Adding `REGION=eu-west-1` to config/defaults.env would make it pass. No files were changed.
EOF
  fi
}
