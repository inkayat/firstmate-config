#!/usr/bin/env bash
# broken-firstmate.sh - negative controls for tests/roles-e2e.sh and tests/workflows-e2e.sh.
#
#   bash tests/e2e-lib/broken-firstmate.sh <mode> <dest-dir>    prints <dest-dir>, a FirstMate root to feed in:
#   FIRSTMATE_ROOT=$(bash tests/e2e-lib/broken-firstmate.sh <mode> "$(mktemp -d)") bash tests/workflows-e2e.sh
#
# <dest-dir> mirrors the official checkout; its bin/fm-spawn.sh breaks ONE contract in the brief the Captain
# filled, then runs the official fm-spawn.sh on it: a launch the suite must FAIL on.
#   pass                 breaks nothing: the baseline, the suite must PASS (the mirror is faithful)
#   drop-handoff         the whole role handoff (Assigned role ... skill requirements) is missing from the first input
#   drop-skills          the Role skill entries of the handoff are missing (the Assigned role and ROLE.md stay)
#   wrong-role-path      the Role source names another role's ROLE.md
#   extra-skill          a Selected shared worker skill the role does not autoload is added
#   drop-feedback        the feedback input of a step that has one is missing
#   wrong-feedback       the feedback ids are not the ones the previous step produced
#   leak-review-wording  the reviewer's raw wording reaches the implementer next to the verified list
#   drop-spec-header     the Workflow step header, the first line of the spec, is missing
#   trim-spec            a line of the spec is missing (the spec is not pasted whole)
#   trace-line           the chat-only Workflow: trace line is pasted into the brief
#   leak-home            a tmux call runs with the real HOME
#   leak-socket          a tmux call runs against a socket outside the lab (TMUX names another server)
#   leak-fleet-tool      a fleet tool (the first installed of gh, gh-axi, no-mistakes, herdr) is called
# The three leak-* modes only run read-only commands (tmux ls, --version) and are made to fail by lab_guard.
set -u

mode=${1:-}
dest=${2:-}
real="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"
case $mode in
  pass|drop-handoff|drop-skills|wrong-role-path|extra-skill|drop-feedback|wrong-feedback|leak-review-wording|drop-spec-header|trim-spec|trace-line|leak-home|leak-socket|leak-fleet-tool) ;;
  *) sed -n '2,/^set -u/p' "$0" | sed 's/^# \{0,1\}//' | sed '$d' >&2; exit 2 ;;
esac
[ -n "$dest" ] || { echo 'broken-firstmate: a destination directory is required' >&2; exit 2; }
[ -x "$real/bin/fm-spawn.sh" ] && [ -x "$real/bin/fm-brief.sh" ] || { echo "broken-firstmate: no FirstMate at $real" >&2; exit 1; }
tool=''
for t in gh gh-axi no-mistakes herdr; do
  command -v "$t" >/dev/null 2>&1 && { tool=$t; break; }
done
if [ "$mode" = leak-fleet-tool ] && [ -z "$tool" ]; then
  echo 'broken-firstmate: no fleet tool installed, this control cannot run here' >&2; exit 1
fi

# A mirror of the official checkout: its bin/ is a copy (so the official scripts derive the SAME root, this
# directory, that the suites compare against), everything else a symlink. fm-spawn.sh is the wrapper and the
# official one sits beside it; .git is not mirrored.
mkdir -p "$dest"
[ "$(cd "$dest" && pwd -P)" != "$(cd "$real" && pwd -P)" ] || { echo 'broken-firstmate: the destination is the official checkout itself' >&2; exit 2; }
for e in "$real"/* "$real"/.[!.]*; do
  b=${e##*/}
  case $b in bin|.git) continue ;; esac
  [ -e "$dest/$b" ] || ln -s "$e" "$dest/$b"
done
rm -rf "${dest:?}/bin"
cp -R "$real/bin" "$dest/bin"
mv "$dest/bin/fm-spawn.sh" "$dest/bin/fm-spawn-official.sh"
{
  printf '#!/usr/bin/env bash\nMODE=%q\nREALHOME=%q\nFLEETTOOL=%q\n' "$mode" "$HOME" "$tool"
  cat <<'SH'
set -u
brief="$FM_HOME/data/$1/brief.md"
mut() { "$@" < "$brief" > "$brief.mut" && mv "$brief.mut" "$brief"; }
case $MODE in
  drop-handoff) mut awk '/^Assigned role:/ {skip = 1} /^# Herdr lifecycle/ {skip = 0} !skip' ;;
  drop-skills) mut awk '/^Role skill:$/ {skip = 1} /^# Herdr lifecycle/ {skip = 0} !skip' ;;
  wrong-role-path) mut sed -E 's#/roles/[a-z-]+/ROLE\.md#/roles/chore/ROLE.md#' ;;
  extra-skill) mut awk -v p="$FM_SKILLS_ROOT/extra-skill/SKILL.md" '/^# Herdr lifecycle/ {print "Selected shared worker skill:"; print "  " p; print ""} {print}' ;;
  drop-feedback) mut awk '/^- feedback:/ {skip = 1; next} skip && /^```json$/ {blk = 1; next} skip && blk && /^```$/ {skip = 0; blk = 0; next} !skip' ;;
  wrong-feedback) mut sed 's/"id":"QA-1"/"id":"QA-9"/; s/"id":"REV-1"/"id":"REV-9"/' ;;
  leak-review-wording) ! grep -q '^- feedback:' "$brief" || printf '%s\n' '- raw review: {"id":"REV-1","severity":"IMPORTANT","what":"the retry swallows the error"}' >> "$brief" ;;
  drop-spec-header) mut awk '!d && /^Workflow step: / {d = 1; next} {print}' ;;
  trim-spec) mut awk '!d && /^Output: / {d = 1; next} {print}' ;;
  trace-line) mut awk '{print} !d && /^Workflow step: / {d = 1; print "Workflow: x v1 | step y #1 | loops none | running"}' ;;
  leak-home) env HOME="$REALHOME" tmux ls >/dev/null 2>&1 || true ;;
  leak-socket) env TMUX=/tmp/e2e-no-such-fleet/default,1,0 tmux ls >/dev/null 2>&1 || true ;;
  leak-fleet-tool) "$FLEETTOOL" --version >/dev/null 2>&1 || true ;;
esac
exec "$(dirname "$0")/fm-spawn-official.sh" "$@"
SH
} > "$dest/bin/fm-spawn.sh"
chmod +x "$dest/bin/fm-brief.sh" "$dest/bin/fm-spawn.sh"
printf '%s\n' "$dest"
