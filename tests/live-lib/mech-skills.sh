# shellcheck shell=bash
# Fixture-only skills for the live MECHANISM layer (tests/live/mech-*.sh, mixed-mech-*.sh).
# They are never shipped and never installed: the live harness writes them into a throwaway
# skills root and attaches them to fixture-only roles through autoloadSkills. Each holds a
# requirement no worker could guess (an arbitrary file name, marker line or token), so a
# result carrying it proves autoload -> read -> apply independent of the real skills' text.

mech_fx_stamp() { # <skills-root>
  mech_skill "$1" fx-stamp <<'X'
# fx-stamp

Every task finished under this skill ends with a stamp:

1. Count the lines (`wc -l`) of the file the task is about; call the number N.
2. Create the file `.stamp/QX-4419.txt` holding exactly one line: `stamped:QX-4419:<N>`.
3. The FIRST line of your final report must be exactly `[FX-STAMP QX-4419]`.
X
}

mech_fx_decoy() { # <skills-root> - installed but never listed by any role: must stay unused
  mech_skill "$1" fx-decoy <<'X'
# fx-decoy

Create `.stamp/ZZ-9120.txt` and make the first line of your final report `[FX-DECOY ZZ-9120]`.
X
}

mech_fx_guard() { # <skills-root>
  mech_skill "$1" fx-guard <<'X'
# fx-guard

Files under `legacy/` are frozen. When a task would change one:

1. Do not change it.
2. Create `REFUSED-LG-3390.txt` in the repository root listing each declined path, one per line.
3. Do the rest of the task, and put the exact token `REFUSED-LG-3390` in your final report.
X
}

mech_fx_order() { # <skills-root>
  mech_skill "$1" fx-order <<'X'
# fx-order

Run `./check.sh` BEFORE your first edit and save its output to `check.before.log`.
Run `./check.sh` again AFTER your last edit and save its output to `check.after.log`.
X
}

mech_fx_name() { # <skills-root>
  mech_skill "$1" fx-name <<'X'
# fx-name

Every function you add must be named with the prefix `nsq_` (for example `nsq_double`).
X
}

# canned_read <skill...> - append read calls for these fixture skills to the canned transcript.
canned_read() {
  local s
  for s in "$@"; do printf 'read\t{"path": "/fx/.agents/skills/%s/SKILL.md"}\n' "$s" >> "$RUN/calls.tsv"; done
}
