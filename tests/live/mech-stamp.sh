# Live MECHANISM case: autoload -> read -> apply of a fixture-only skill (fx-stamp).
#
# Role fx-stamper autoloads fx-stamp, which demands an arbitrary artifact (.stamp/QX-4419.txt holding
# the computed line count) and an exact first line in the final report. A decoy skill (fx-decoy) is
# installed in the same skills root but listed by no role: it must stay unread and unapplied. Nothing in
# the prompt, the role or the fixture mentions any of this, so only reading the autoloaded skill gets it.
# Control: same role, skill stripped from the handoff -> no stamp, no marker line.
# shellcheck source=tests/live-lib/mech-skills.sh
. "$(dirname "${BASH_SOURCE[0]}")/../live-lib/mech-skills.sh"

CASE_MECHANISM=1
CASE_KIND=role
CASE_ROLE=fx-stamper
CASE_SKILL_ONLY_TOKENS="QX-4419"
CASE_PROMPT='How many lines does data.txt have? Answer in one sentence.'

case_mechanism_setup() { # <config-root> <skills-root>
  mech_role "$1" fx-stamper "Answers questions about files in the repository" fx-stamp
  mech_fx_stamp "$2"
  mech_fx_decoy "$2"
}

case_setup() { printf 'alpha\nbeta\ngamma\ndelta\nepsilon\nzeta\neta\n' > data.txt; }

case_grade() {
  local first
  [ -f .stamp/QX-4419.txt ] || { echo "no .stamp/QX-4419.txt: the skill was not applied"; return 1; }
  [ "$(cat .stamp/QX-4419.txt)" = 'stamped:QX-4419:7' ] || { echo "stamp content wrong: $(cat .stamp/QX-4419.txt)"; return 1; }
  first=$(awk 'NF { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print; exit }' "$RUN/final.txt")
  [ "$first" = '[FX-STAMP QX-4419]' ] || { echo "final report does not open with the stamp line (got: $first)"; return 1; }
  if [ -e .stamp/ZZ-9120.txt ] || final_has 'ZZ-9120|FX-DECOY' || call_has 'fx-decoy'; then
    echo "the unlisted decoy skill leaked in: only autoloaded skills may be used"; return 1
  fi
  echo "stamp file with the computed count, exact opening line, decoy untouched"
}

case_canned() { # <role> good|bad
  if [ "$2" = good ]; then
    canned_read fx-stamp
    printf 'bash\t{"command": "wc -l data.txt"}\n' >> "$RUN/calls.tsv"
    mkdir -p .stamp; printf 'stamped:QX-4419:7\n' > .stamp/QX-4419.txt
    printf '[FX-STAMP QX-4419]\ndata.txt has 7 lines.\n' > "$RUN/final.txt"
  else
    printf 'bash\t{"command": "wc -l data.txt"}\n' >> "$RUN/calls.tsv"
    printf 'data.txt has 7 lines.\n' > "$RUN/final.txt"
  fi
}
