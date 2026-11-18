# Live MECHANISM case: a role with TWO autoloaded skills; both must be read and applied.
#
# fx-order demands before/after logs of ./check.sh (the before-log must exist before the first edit);
# fx-name demands an `nsq_` prefix on added functions. Neither is guessable. Control: both stripped.
# shellcheck source=tests/live-lib/mech-skills.sh
. "$(dirname "${BASH_SOURCE[0]}")/../live-lib/mech-skills.sh"

CASE_MECHANISM=1
CASE_KIND=role
CASE_ROLE=fx-dual
CASE_SKILL_ONLY_TOKENS="check.before.log nsq_"
CASE_PROMPT='Add a function to calc.py that doubles a number, and make sure the checks still pass.'

case_mechanism_setup() { # <config-root> <skills-root>
  mech_role "$1" fx-dual "Small Python changes" fx-order fx-name
  mech_fx_order "$2"
  mech_fx_name "$2"
}

case_setup() {
  printf 'def add(a, b):\n    return a + b\n' > calc.py
  printf '#!/bin/sh\npython3 -c "import calc; assert calc.add(1, 2) == 3" && echo CHECKS-OK\n' > check.sh
  chmod +x check.sh
}

case_grade() {
  local first_log first_edit
  [ -f check.before.log ] && [ -f check.after.log ] || { echo "before/after check logs missing"; return 1; }
  grep -q '^def nsq_' calc.py || { echo "no function with the nsq_ prefix in calc.py"; return 1; }
  first_log=$(awk -F'\t' 'index($2, "check.before.log") { print NR; exit }' "$RUN/calls.tsv")
  first_edit=$(awk -F'\t' '($1 == "edit" || $1 == "write") && index($2, "calc.py") { print NR; exit }' "$RUN/calls.tsv")
  [ -n "$first_log" ] && { [ -z "$first_edit" ] || [ "$first_log" -lt "$first_edit" ]; } || { echo "check.before.log was not produced before the first edit of calc.py"; return 1; }
  echo "both skills applied: ordered logs and the nsq_ prefix"
}

case_canned() { # <role> good|bad
  if [ "$2" = good ]; then
    canned_read fx-order fx-name
    printf 'bash\t{"command": "./check.sh > check.before.log"}\n' >> "$RUN/calls.tsv"
    printf 'edit\t{"path": "calc.py"}\n' >> "$RUN/calls.tsv"
    printf 'def add(a, b):\n    return a + b\n\ndef nsq_double(x):\n    return x * 2\n' > calc.py
    ./check.sh > check.before.log 2>&1; ./check.sh > check.after.log 2>&1
    printf 'Added nsq_double; checks pass.\n' > "$RUN/final.txt"
  else
    printf 'edit\t{"path": "calc.py"}\n' >> "$RUN/calls.tsv"
    printf 'def add(a, b):\n    return a + b\n\ndef double(x):\n    return x * 2\n' > calc.py
    printf 'Added double; checks pass.\n' > "$RUN/final.txt"
  fi
}
