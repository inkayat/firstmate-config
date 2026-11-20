# shellcheck shell=bash
# The isolated lab shared by tests/roles-e2e.sh and tests/workflows-e2e.sh. Sourced, never run.
#
# Both suites drive the REAL official bin/fm-brief.sh and bin/fm-spawn.sh, which create tmux windows
# and treehouse worktrees. This file is what makes them safe on a machine with a live fleet, even when
# they are started from inside a fleet tmux pane or treehouse worktree:
#   - a PRIVATE tmux server (TMUX_TMPDIR in a fresh dir). A tmux client prefers the socket named by an
#     inherited $TMUX over TMUX_TMPDIR, so the official scripts would otherwise open windows in the
#     fleet's own session and our teardown's `kill-server` would kill the fleet's server. The scripts
#     FirstMate runs get an `env -i` environment: no TMUX, TMUX_PANE, FM_*, TREEHOUSE_DIR, HERDR_*,
#     CMUX_* ... from the caller, only the allow-list in lab_up. The caller's git redirection variables
#     (GIT_DIR ...) and FM_WORKFLOWS_ROOT are unset for this process too.
#   - a throwaway HOME, FM_HOME, TMPDIR and project. The project's treehouse.toml has `root = "./"`, so
#     treehouse keeps its pool and state inside the project, inside the lab: nothing under the real
#     ~/.treehouse. The one thing FirstMate hard-codes outside the lab is /tmp/fm-<task-id>[+hash]; the
#     task ids carry this run's unique suffix and lab_down removes exactly those.
#   - recording shims for tmux and treehouse ahead of the real ones on PATH, and deny-and-record shims
#     for the fleet tools (gh, gh-axi, no-mistakes, herdr, orca, zellij, cmux, paseo, tern) when
#     installed. lab_guard reads their log at the end: every tmux call ran on the lab server with the
#     lab HOME and cwd, every treehouse call with the lab HOME and cwd, no fleet tool was reached, and
#     the shims really were on the path (a guard that saw no call proves nothing, so that fails).
#   - lab_down is idempotent, runs on EXIT/HUP/INT/TERM and again explicitly from lab_finish, because a
#     harness that runs scripts in-process (the omp bash tool) does not fire an EXIT trap.
#
# Provided: pass fail check has lacks field (assertions; $failed), lab_prereq, lab_up, lab_run,
# lab_guard, lab_finish, and after lab_up: TMP (lab root, canonical), RUN (unique suffix), SEAM_TMUX,
# home (FM_HOME), proj (project name dir), LAB_TMO (timeout prefix or empty).

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$3', got '$2')"; fi; }
has() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3')" ;; esac; }
lacks() { case $2 in *"$3"*) fail "$1 (unexpected '$3')" ;; *) pass "$1" ;; esac; }
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }
# bash 5.2+ would treat & in a ${var/pat/repl} replacement as the matched text; the specs are pasted verbatim
shopt -u patsub_replacement 2>/dev/null || true

# lab_prereq <name> <BANNER>: SKIP (never PASS) without the real tools.
lab_prereq() {
  if ! command -v tmux >/dev/null 2>&1 || ! command -v treehouse >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 \
     || [ ! -x "$FM_ROOT/bin/fm-spawn.sh" ] || [ ! -x "$FM_ROOT/bin/fm-brief.sh" ]; then
    printf 'SKIP - %s e2e: needs tmux, treehouse, jq, and %s/bin/fm-{brief,spawn}.sh (never reported as PASS)\n\n%s E2E SKIPPED\n' "$1" "$FM_ROOT" "$2"
    exit 0
  fi
}

# lab_up <tag>: build the lab for one suite (tag: wf | roles).
lab_up() {
  local tag=$1 n real t
  LAB_TAG=$tag
  LAB_PATH=$PATH
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX FM_WORKFLOWS_ROOT
  LAB_REAL_TMUX=$(command -v tmux)
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-$tag-e2e.XXXXXX") || exit 1
  TMP=$(cd "$TMP" && pwd -P)
  trap lab_down EXIT
  trap 'lab_down; exit 130' HUP INT TERM
  # a short path: a unix socket path is limited to about 100 bytes
  SEAM_TMUX=$(mktemp -d "/tmp/fm-$tag-tmux.XXXXXX") || exit 1
  SEAM_TMUX=$(cd "$SEAM_TMUX" && pwd -P)
  RUN=$(printf '%s' "${TMP##*.}" | tr 'A-Z' 'a-z')
  home="$TMP/fm-home"
  proj="$home/projects/e2e-proj"
  mkdir -p "$home/state" "$home/config" "$home/data" "$TMP/home" "$TMP/tmp" "$TMP/bin" "$TMP/shim" "$proj"
  : > "$TMP/iso.log"
  printf 'manual\n' > "$home/config/backlog-backend"
  printf '# E2E project\n' > "$proj/AGENTS.md"
  printf 'max_trees = 24\nroot = "./"\n' > "$proj/treehouse.toml"
  git -C "$proj" init -q
  git -C "$proj" add -A
  git -C "$proj" -c user.email=t@example.invalid -c user.name=t commit -q -m init
  printf 'lab: %s (private tmux server in %s, FM_HOME %s)\n' "$TMP" "$SEAM_TMUX" "$home"

  # the fake worker: records the argv it was launched with (the worker's FIRST input), nothing else
  cat > "$TMP/bin/omp" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = --help ] && { printf 'usage: omp [options] [prompt]\n'; exit 0; }
if [ "${1:-}" = models ]; then
  printf '{"models":[{"provider":"anthropic","id":"claude-opus-5-5","selector":"anthropic/claude-opus-5-5"},{"provider":"anthropic","id":"claude-sonnet-5-5","selector":"anthropic/claude-sonnet-5-5"}]}\n'
  exit 0
fi
printf '%s\n' "$@" > worker-argv.tmp
mv worker-argv.tmp worker-argv.txt
SH
  chmod +x "$TMP/bin/omp"

  # the recording shim: name|HOME|TMUX|TMUX_TMPDIR|PWD|first-argument per call, then the real tool, or a refusal
  cat > "$TMP/shim/tmux" <<'SH'
#!/bin/bash
d=$(cd "$(dirname "$0")" && pwd -P)
n=$(basename "$0")
printf '%s|%s|%s|%s|%s|%s\n' "$n" "$HOME" "${TMUX-}" "${TMUX_TMPDIR-}" "$PWD" "${1-}" >> "$d/../iso.log"
if [ -f "$d/.deny-$n" ]; then echo "e2e lab: $n must not be called here" >&2; exit 99; fi
exec "$(cat "$d/.real-$n")" "$@"
SH
  chmod +x "$TMP/shim/tmux"
  for n in tmux treehouse gh gh-axi no-mistakes herdr orca zellij cmux paseo tern; do
    real=$(command -v "$n" 2>/dev/null) || continue
    [ -n "$real" ] || continue
    [ "$n" = tmux ] || cp "$TMP/shim/tmux" "$TMP/shim/$n"
    printf '%s' "$real" > "$TMP/shim/.real-$n"
    case $n in tmux|treehouse) ;; *) : > "$TMP/shim/.deny-$n" ;; esac
  done

  # exactly what the official scripts get: nothing from the caller's environment but this allow-list
  LAB_ENV=(PATH="$TMP/shim:$TMP/bin:$LAB_PATH" HOME="$TMP/home" TMPDIR="$TMP/tmp"
    USER="${USER:-$(id -un)}" LOGNAME="${LOGNAME:-$(id -un)}" SHELL="${SHELL:-/bin/bash}" TERM="${TERM:-dumb}"
    TMUX_TMPDIR="$SEAM_TMUX" FM_HOME="$home" FM_BACKEND=tmux FM_CONFIG_ROOT="$CONFIG_ROOT" FM_SKILLS_ROOT="$TMP/home/.agents/skills")
  [ -z "${LANG:-}" ] || LAB_ENV+=(LANG="$LANG")
  [ -z "${LC_ALL:-}" ] || LAB_ENV+=(LC_ALL="$LC_ALL")
  t=$(command -v timeout || command -v gtimeout || true)
  LAB_TMO=()
  [ -z "$t" ] || LAB_TMO=("$t" 90)
  export FM_CONFIG_ROOT="$CONFIG_ROOT" FM_SKILLS_ROOT="$TMP/home/.agents/skills"
}

# lab_run <command> [args]...: run a FirstMate script in the lab environment, from the lab's FM home.
lab_run() { ( cd "$home" && env -i "${LAB_ENV[@]}" "$@" ); }

# lab_in <path>: the path is inside the lab (TMP, with or without the /private of a macOS /var or /tmp)
lab_in() {
  case $1 in
    "$TMP"/*|"$TMP"|"${TMP#/private}"/*|"${TMP#/private}") return 0 ;;
  esac
  return 1
}

# _lab_once <list> <item>: the list with the item appended unless it is there (one note per distinct offence)
_lab_once() { case " $1 " in *" $2 "*) printf '%s' "$1" ;; *) printf '%s %s' "$1" "$2" ;; esac; }

# lab_guard [log]: the isolation assertions, from the shims' own record of every tmux and treehouse call.
lab_guard() {
  local log=${1:-$TMP/iso.log} name h tx td cwd first nt=0 nh=0 bad_t='' bad_h='' bad_f='' fleet=0
  while IFS='|' read -r name h tx td cwd first || [ -n "$name" ]; do
    case $name in
      tmux)
        nt=$((nt + 1))
        [ "$h" = "$TMP/home" ] || bad_t=$(_lab_once "$bad_t" "HOME=$h")
        lab_in "$cwd" || bad_t=$(_lab_once "$bad_t" "cwd=$cwd")
        case $first in -S*|-L*|-f*) bad_t=$(_lab_once "$bad_t" "option=$first") ;; esac
        if [ -n "$tx" ]; then
          case $tx in "$SEAM_TMUX"/*) ;; *) bad_t=$(_lab_once "$bad_t" "TMUX=$tx") ;; esac
        else
          [ "$td" = "$SEAM_TMUX" ] || bad_t=$(_lab_once "$bad_t" "TMUX_TMPDIR=$td")
        fi ;;
      treehouse)
        nh=$((nh + 1))
        [ "$h" = "$TMP/home" ] || bad_h=$(_lab_once "$bad_h" "HOME=$h")
        lab_in "$cwd" || bad_h=$(_lab_once "$bad_h" "cwd=$cwd")
        case $tx in ''|"$SEAM_TMUX"/*) ;; *) bad_h=$(_lab_once "$bad_h" "TMUX=$tx") ;; esac ;;
      '') ;;
      *) fleet=$((fleet + 1)); bad_f=$(_lab_once "$bad_f" "$name") ;;
    esac
  done < "$log"
  if [ "$nt" -eq 0 ] || [ "$nh" -eq 0 ]; then
    fail "isolation: the lab recorded $nt tmux and $nh treehouse calls, the recording shims were bypassed"
    return
  fi
  if [ -z "$bad_t" ]; then pass "isolation: all $nt tmux calls ran on the lab server (lab TMUX_TMPDIR or lab socket), lab HOME, lab cwd, no -S/-L/-f"
  else fail "isolation: tmux call outside the lab:$bad_t"; fi
  if [ -z "$bad_h" ]; then pass "isolation: all $nh treehouse calls ran with the lab HOME and lab cwd"
  else fail "isolation: treehouse call outside the lab:$bad_h"; fi
  if [ "$fleet" -eq 0 ]; then pass 'isolation: no fleet tool (gh, gh-axi, no-mistakes, herdr, orca, zellij, cmux, paseo, tern) was reached'
  else fail "isolation: $fleet call(s) reached a fleet tool:$bad_f"; fi
}

# lab_kill_tmux: stop the lab tmux server (never the caller's: no TMUX, the lab's own TMUX_TMPDIR).
lab_kill_tmux() {
  [ -n "${SEAM_TMUX:-}" ] || return 0
  env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$SEAM_TMUX" "$LAB_REAL_TMUX" kill-server >/dev/null 2>&1 || true
  sleep 0.3
}

# lab_down: stop the lab tmux server, remove the lab. Idempotent.
lab_down() {
  local gone=()
  [ -n "${TMP:-}" ] || return 0
  lab_kill_tmux
  gone=("$TMP")
  [ -z "${SEAM_TMUX:-}" ] || gone+=("$SEAM_TMUX")
  # FirstMate hard-codes /tmp/fm-<task-id>[+hash]; this run's ids carry its unique RUN suffix
  [ -z "${RUN:-}" ] || gone+=(/tmp/fm-fm-"$LAB_TAG"-e2e-"$RUN"-*)
  # git objects of the worktrees are read-only
  chmod -R u+w "${gone[@]}" 2>/dev/null
  rm -rf "${gone[@]}"
  TMP=''
}

# lab_finish <NAME>: guard, tear down, prove the lab is gone, print the verdict; the exit status is the result.
lab_finish() {
  local tmp=$TMP seam=$SEAM_TMUX run=$RUN left
  lab_guard
  lab_kill_tmux
  check 'lab: the lab tmux server is stopped' "$(env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$seam" "$LAB_REAL_TMUX" ls 2>&1 | grep -c '^firstmate:')" 0
  lab_down
  left=$(ls -d "$tmp" "$seam" /tmp/fm-fm-"$LAB_TAG"-e2e-"$run"-* 2>/dev/null)
  check 'lab: torn down, no directory of this run is left behind' "$left" ''
  printf '\n%s E2E %s\n' "$1" "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
  [ "$failed" -eq 0 ]
}
