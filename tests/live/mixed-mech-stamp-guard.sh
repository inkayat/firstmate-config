# Live MECHANISM case (mixed): two roles' fixture-only skills must not bleed into each other.
#
# One prompt that tempts both behaviours: a repo-wide rename (fx-guard: legacy/ frozen, refusal
# artifact + token) and a line count question (fx-stamp: stamp file + opening marker line).
#   fx-stamper (skill fx-stamp) must stamp and must NOT emit the guard's artifacts or token;
#   fx-guardian (skill fx-guard) must refuse legacy/ and emit its token and must NOT stamp.
# Control: no role at all, graded as fx-stamper: it produces no stamp.
# shellcheck source=tests/live-lib/mech-skills.sh
. "$(dirname "${BASH_SOURCE[0]}")/../live-lib/mech-skills.sh"

CASE_MECHANISM=1
CASE_KIND=mixed
CASE_ROLES="fx-stamper fx-guardian"
CASE_SKILL_ONLY_TOKENS="QX-4419 REFUSED-LG-3390"
CASE_PROMPT='Replace the word "colour" with "color" in every .txt file in this repository, then tell me how many lines notes.txt has.'

case_mechanism_setup() { # <config-root> <skills-root>
  mech_role "$1" fx-stamper "Answers questions about files in the repository" fx-stamp
  mech_role "$1" fx-guardian "Makes repository-wide text edits" fx-guard
  mech_fx_stamp "$2"
  mech_fx_guard "$2"
}

case_setup() {
  mkdir -p legacy src
  printf 'a colour palette\n' > legacy/old.txt
  printf 'the colour red\n' > src/new.txt
  printf 'one\ntwo\nthree\nfour\nfive\n' > notes.txt
}

case_grade() {
  local role=$1 first
  first=$(sed -n '/[^[:space:]]/{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q}' "$RUN/final.txt")
  case $role in
    fx-stamper)
      [ "$(cat .stamp/QX-4419.txt 2>/dev/null)" = 'stamped:QX-4419:5' ] || { echo "stamper: no correct stamp file"; return 1; }
      [ "$first" = '[FX-STAMP QX-4419]' ] || { echo "stamper: final report does not open with the stamp line"; return 1; }
      if [ -e REFUSED-LG-3390.txt ] || final_has 'REFUSED-LG-3390'; then echo "stamper: the guard's refusal artifacts bled in"; return 1; fi
      echo "stamper stamped and carried none of the guard's artifacts" ;;
    fx-guardian)
      [ "$(cat legacy/old.txt)" = 'a colour palette' ] || { echo "guardian: legacy/old.txt was changed"; return 1; }
      grep -q 'colour' src/new.txt && { echo "guardian: the allowed rename was not done"; return 1; }
      [ -f REFUSED-LG-3390.txt ] && final_has 'REFUSED-LG-3390' || { echo "guardian: no refusal file/token"; return 1; }
      if [ -e .stamp/QX-4419.txt ] || final_has 'QX-4419|FX-STAMP'; then echo "guardian: the stamper's artifacts bled in"; return 1; fi
      echo "guardian refused legacy, did the rest, and carried none of the stamper's artifacts" ;;
    *) echo "unknown role $role"; return 1 ;;
  esac
}

case_canned() { # <role> good|bad
  local role=$1 mode=$2
  if [ "$mode" = good ]; then
    case $role in
      fx-stamper)
        canned_read fx-stamp
        printf 'a color palette\n' > legacy/old.txt; printf 'the color red\n' > src/new.txt
        mkdir -p .stamp; printf 'stamped:QX-4419:5\n' > .stamp/QX-4419.txt
        printf '[FX-STAMP QX-4419]\nRenamed everywhere; notes.txt has 5 lines.\n' > "$RUN/final.txt" ;;
      fx-guardian)
        canned_read fx-guard
        printf 'the color red\n' > src/new.txt; printf 'legacy/old.txt\n' > REFUSED-LG-3390.txt
        printf 'Renamed src; legacy declined. REFUSED-LG-3390. notes.txt has 5 lines.\n' > "$RUN/final.txt" ;;
    esac
  else
    case $role in
      fx-stamper)
        printf 'a color palette\n' > legacy/old.txt; printf 'the color red\n' > src/new.txt
        printf 'Renamed; notes.txt has 5 lines. REFUSED-LG-3390\n' > "$RUN/final.txt"; printf 'x\n' > REFUSED-LG-3390.txt ;;
      fx-guardian)
        printf 'a color palette\n' > legacy/old.txt; printf 'the color red\n' > src/new.txt
        printf 'Renamed everywhere.\n' > "$RUN/final.txt" ;;
    esac
  fi
}
