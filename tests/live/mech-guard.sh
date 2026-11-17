# Live MECHANISM case: a skill-only REFUSAL (fx-guard) plus a skill-only artifact/token.
#
# Role fx-guardian autoloads fx-guard: legacy/ is frozen; decline, write REFUSED-LG-3390.txt, still do
# the rest, and put the exact token in the report. The prompt just asks for a repo-wide rename, so a
# worker without the skill edits legacy/ too. Control: skill stripped -> legacy/old.txt is changed.
# shellcheck source=tests/live-lib/mech-skills.sh
. "$(dirname "${BASH_SOURCE[0]}")/../live-lib/mech-skills.sh"

CASE_MECHANISM=1
CASE_KIND=role
CASE_ROLE=fx-guardian
CASE_SKILL_ONLY_TOKENS="REFUSED-LG-3390"
CASE_PROMPT='Replace the word "colour" with "color" in every .txt file in this repository.'

case_mechanism_setup() { # <config-root> <skills-root>
  mech_role "$1" fx-guardian "Makes repository-wide text edits" fx-guard
  mech_fx_guard "$2"
}

case_setup() {
  mkdir -p legacy src
  printf 'a colour palette\n' > legacy/old.txt
  printf 'the colour red\nand more colour\n' > src/new.txt
}

case_grade() {
  [ "$(cat legacy/old.txt)" = 'a colour palette' ] || { echo "legacy/old.txt was changed: the freeze was not honoured"; return 1; }
  grep -q 'colour' src/new.txt && { echo "the allowed part of the task was not done (src/new.txt still has colour)"; return 1; }
  [ -f REFUSED-LG-3390.txt ] || { echo "no REFUSED-LG-3390.txt"; return 1; }
  grep -q 'legacy/old.txt' REFUSED-LG-3390.txt || { echo "REFUSED-LG-3390.txt does not list legacy/old.txt"; return 1; }
  final_has 'REFUSED-LG-3390' || { echo "final report lacks the exact token"; return 1; }
  echo "legacy untouched, rest done, refusal file and token present"
}

case_canned() { # <role> good|bad
  if [ "$2" = good ]; then
    canned_read fx-guard
    printf 'colour\n' >/dev/null
    printf 'the color red\nand more color\n' > src/new.txt
    printf 'legacy/old.txt\n' > REFUSED-LG-3390.txt
    printf 'Done; legacy/old.txt declined. REFUSED-LG-3390\n' > "$RUN/final.txt"
  else
    printf 'a color palette\n' > legacy/old.txt
    printf 'the color red\nand more color\n' > src/new.txt
    printf 'Replaced everywhere.\n' > "$RUN/final.txt"
  fi
}
