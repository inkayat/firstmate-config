#!/usr/bin/env bash
# worker-context.sh - offline acceptance, plus an externally usable
# prepare/validate/handoff CLI, for the delegated-worker context/skill-class
# handoff contract (firstmate/primary-policy.md section 2, README.md
# "Worker context and skill classes").
#
# Usage:
#   tests/worker-context.sh                          run the offline suite (default)
#   tests/worker-context.sh prepare <directory>       build a persistent fixture
#                                                      Git repo at <directory>/repo,
#                                                      print its path, exit 0.
#                                                      Never deleted by this
#                                                      script; the caller owns
#                                                      cleanup.
#   tests/worker-context.sh handoff <repo-dir>        print the compact, no-body
#                                                      Firstmate-spec-shaped
#                                                      handoff text for the
#                                                      fixture repo at
#                                                      <repo-dir> (paths,
#                                                      precedence conclusions,
#                                                      and required actions
#                                                      only - hand this to a
#                                                      real delegated worker).
#   tests/worker-context.sh validate <worker-report> [<expected-worktree>]
#                                                      classify a real worker
#                                                      transcript/report
#                                                      against every required
#                                                      canary proof; print one
#                                                      PASS/FAIL/SKIP line per
#                                                      proof; exit 0 only when
#                                                      every required proof
#                                                      passes.
#
# `prepare` + `handoff` + `validate` are the deterministic interface for a
# live acceptance run: prepare the fixture, hand `handoff`'s output to a real
# delegated Pi worker and, separately, a real delegated OMP worker with the
# fixture repo as their task worktree, capture each worker's own report, and
# feed it to `validate <report> <repo-dir>`.
#
# The default (no-argument) offline suite below is zero-inference: no
# AgentSession, no model call, no paid quota, no other agent spawned, no
# Portail. Pi's real, installed native resource loader is invoked directly
# (the same technique as its own test/dev harness), never a fake stand-in
# pretending to be Pi's discovery. OMP has no equivalent embeddable loader
# library, so its half is a real, zero-inference read of its own installed
# documentation (`omp read omp://...:raw`, which never starts a session or a
# model turn), grounding the documented discovery difference this contract
# exists to cover. This is pre-implementation native-loader evidence, not a
# substitute for the live delegated Pi/OMP fixture run `validate` supports.
#
# Canary names below label this file's own offline illustration
# (`fixture_validate`, section 1); they are never text a live worker
# should search for. The real forbidden skill name is the literal string
# `captain-hold-lifecycle` - never the label `CAPTAIN_ONLY_CANARY` itself,
# which is only this file's shorthand:
#   PROJECT_SKILL_CANARY   the fixture's mandatory project-local skill
#   SHARED_SKILL_CANARY    the real shared worker skill verification-before-completion
#   CAPTAIN_ONLY_CANARY    the real official-internal skill captain-hold-lifecycle,
#                          which must never surface as a worker skill
# For a live run, `fixture_validate_live` (CLI `validate`) never accepts
# mere omission of that literal name as proof - a report that simply never
# mentions the check would pass it for free. It requires POSITIVE evidence
# instead: `fixture_handoff` (CLI `handoff`) asks the worker to introspect
# its own harness-native skill catalog (never a filesystem scan of the
# official checkout) and report a resolved path for the required project
# skill, a resolved path for the selected shared skill, its catalog's
# source roots/count, and an explicit zero count of catalog entries under
# the official FirstMate distro root. `validate` checks the report for
# worktree identity, root/nested authority, project/shared skill markers,
# skill origins, and bounded-helper context. These are fixture-report
# checks, not independent observations of tool access or task completion.
# Report order cannot establish when instructions were read or applied.
# `handoff` omits body-only markers and the source fixture's absolute path
# so echoing the handoff alone does not satisfy these checks.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${FM_CONFIG_ENV:-$HOME/.config/firstmate-config/env}"
# shellcheck source=/dev/null
[ ! -f "$ENV_FILE" ] || . "$ENV_FILE"
FIRSTMATE_ROOT="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi; }
contains() { case $2 in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in '$2')" ;; esac; }
not_contains() { case $2 in *"$3"*) fail "$1 (unexpectedly found '$3' in '$2')" ;; *) pass "$1" ;; esac; }

# =============================================================================
# Canary constants - the single source for every marker string, reused by
# fixture_prepare (writes them), fixture_validate/fixture_validate_live
# (match them), and fixture_handoff (must never print a *_BODY constant).
# =============================================================================
C_ROOT_OVERRIDE='ROOT_OVERRIDE_CANARY'
C_ROOT_AGENTS_SHADOWED='ROOT_AGENTS_SHADOWED_CANARY'
C_ROOT_CLAUDE_NEVER_WIN='ROOT_CLAUDE_SHOULD_NEVER_WIN_CANARY'
C_NESTED_SCOPE='NESTED_SCOPE_CANARY'
C_PROJECT_SKILL_NAME='migration-canary'
C_PROJECT_SKILL_BODY='PROJECT_SKILL_CANARY_BODY'
C_SHARED_SKILL_NAME='verification-before-completion'
C_SHARED_SKILL_BODY='NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE'
C_PROJECT_WINS='PROJECT_WINS_OVER_SHARED_CANARY'
C_GLOBAL_LEAK='GLOBAL_ARCHITECTURE_REVIEW_CANARY'
C_CAPTAIN_ONLY='captain-hold-lifecycle'
C_MIGRATION_FILE='migrations/0001_init.sql'

# =============================================================================
# fixture_prepare / fixture_handoff / fixture_validate / fixture_validate_live
# =============================================================================

# fixture_prepare <dir> - builds <dir>/repo: a disposable Git project with
# deliberately conflicting root/nested instructions, a project-local
# mandatory skill (PROJECT_SKILL_CANARY, body-only marker), and a
# project-local skill that collides by name with the real global shared
# skill "architecture-review" this repository installs (PROJECT_WINS_OVER_SHARED
# marker), proving project-local-over-global precedence
# (firstmate/primary-policy.md section 1). Never deleted by this function;
# the caller owns the directory's lifetime.
fixture_prepare() {
  local dir=$1 repo="$1/repo"
  mkdir -p "$repo/sub" "$repo/migrations" \
    "$repo/.agents/skills/migration-canary" \
    "$repo/.agents/skills/architecture-review"

  cat > "$repo/AGENTS.override.md" <<EOF
Rule: $C_ROOT_OVERRIDE applies at the repository root.

Required project skill:
  .agents/skills/migration-canary/SKILL.md
Requirement:
  Read and apply this skill before reading, writing, reviewing, or editing
  anything under migrations/.
EOF

  # Shadowed by AGENTS.override.md at the same scope - must never be treated
  # as authoritative while the override is present.
  cat > "$repo/AGENTS.md" <<EOF
Rule: $C_ROOT_AGENTS_SHADOWED - if this rule name surfaces, the override was
not honored.
EOF

  # Never wins when AGENTS.md exists in the same scope, for either harness.
  cat > "$repo/CLAUDE.md" <<EOF
Rule: $C_ROOT_CLAUDE_NEVER_WIN
EOF

  # Applies only inside sub/ - proves nested-scope precedence.
  cat > "$repo/sub/AGENTS.md" <<EOF
Rule: $C_NESTED_SCOPE applies only to files under sub/.
EOF

  printf -- '-- fixture migration\n' > "$repo/$C_MIGRATION_FILE"

  # Frontmatter description deliberately omits the body-only marker, so
  # catalog visibility (name + description) can never leak it.
  cat > "$repo/.agents/skills/migration-canary/SKILL.md" <<EOF
---
name: migration-canary
description: Fixture project-local skill required before touching migrations.
---
# Migration canary

$C_PROJECT_SKILL_BODY: read and apply this skill before reading, writing,
reviewing, or editing anything under migrations/.
EOF

  # Project-local skill with the same name as the real global shared skill
  # "architecture-review" this repository installs into ~/.agents/skills.
  cat > "$repo/.agents/skills/architecture-review/SKILL.md" <<EOF
---
name: architecture-review
description: Fixture project-local architecture-review, must win over global.
---
# Project-local architecture-review

$C_PROJECT_WINS: this project-local skill must win over the global shared
skill of the same name.
EOF

  git -C "$repo" init -q
  git -C "$repo" add -A
  git -C "$repo" -c user.email=wc@example.invalid -c user.name=wc commit -q -m fixture
}

# fixture_handoff <repo-dir> - prints the compact, Firstmate-spec-shaped
# handoff for the fixture prepared at <repo-dir>: applicable instruction
# paths and which wins at each scope, required project-local/shared skill
# paths each paired with a read-and-apply requirement, a skill-catalog
# evidence requirement, and the governed task. <repo-dir> is used only to
# validate the fixture exists; its absolute path is NEVER printed. The
# worker's actual isolated task worktree does not exist yet when this
# handoff is generated (fm-spawn creates it later, at a different path
# than any source/primary checkout), so every path below is bare and
# worktree-relative, with an explicit instruction to verify `pwd -P`
# against `git rev-parse --show-toplevel` before resolving them - never
# read the source/primary checkout instead of the worker's own worktree.
# $FIRSTMATE_ROOT (the official, persistent FirstMate checkout - never
# this fixture's own disposable source path) is named only as the
# comparison root for the official-internal-skill count below; the worker
# must derive that count from its own harness-native skill catalog, never
# from scanning that checkout's filesystem. Also never prints a body-only
# marker (C_PROJECT_SKILL_BODY, C_SHARED_SKILL_BODY) or any other canary
# constant, so echoing this text alone does not satisfy the fixture's
# report checks. Corroborating actual reads and catalog introspection
# requires the harness session evidence, not just this report.
fixture_handoff() {
  local repo=$1
  if [ ! -f "$repo/AGENTS.override.md" ]; then
    printf 'fixture_handoff: %s is missing AGENTS.override.md; not a prepared fixture\n' "$repo" >&2
    return 1
  fi
  cat <<EOF
Task worktree: your current isolated task worktree - never the primary or
source checkout this fixture was prepared from, which does not exist from
your side and must never be read instead.

Before reading anything below, verify you are standing at that worktree's
root: run pwd -P and git rev-parse --show-toplevel and confirm they are
equal. Every path below is bare and relative to that root.

Applicable instruction paths, nearest scope first, name given where more
than one file exists at a scope:
  AGENTS.override.md   - wins at the repository root
  AGENTS.md            - shadowed by AGENTS.override.md at this scope; not authoritative
  CLAUDE.md            - not authoritative while AGENTS.md exists at this scope
  sub/AGENTS.md        - wins only for files under sub/

Required project skill:
  .agents/skills/migration-canary/SKILL.md
Requirement:
  Read and apply this skill before reading, writing, reviewing, or editing
  anything under migrations/.

Required project skill (name collision with a global shared skill):
  .agents/skills/architecture-review/SKILL.md
Requirement:
  This project-local skill overrides the global shared skill of the same
  name for this task; apply the project-local version, never a global
  default.

Selected shared worker skill:
  $C_SHARED_SKILL_NAME
Requirement:
  Apply before declaring the task complete.

Skill-catalog evidence requirement:
  Never a filesystem scan: use your harness's own skill catalog or
  resource listing, and report exactly these four lines:
    PROJECT_SKILL_RESOLVED_PATH: <absolute path your harness resolved for
      the required project skill above>
    SHARED_SKILL_RESOLVED_PATH: <absolute path your harness resolved for
      the selected shared worker skill above>
    SKILL_CATALOG_SOURCES: <N> source root(s): <root1>[, <root2>, ...]
      (every skill source your harness's own catalog reports, by root
      path and count - never every individual skill name)
    OFFICIAL_INTERNAL_SKILL_COUNT: <the number of entries in that same
      catalog whose resolved path falls under $FIRSTMATE_ROOT - given
      here only as the comparison root, never to scan its filesystem
      yourself>

Bounded internal delegation evidence requirement (report only if your
harness has a native bounded subagent mechanism; otherwise report
INTERNAL_SUBAGENT_USED: not-applicable with one reason line - never force
a mechanism your harness lacks):
  If you spawn any task-local scout, researcher, reviewer, or helper
  through your harness's own native mechanism, it must stay read-only,
  under this same task/project/worktree, create no separate Firstmate
  task, and never recurse past your harness's own native bound. Report:
    INTERNAL_SUBAGENT_USED: yes | no | not-applicable
    (when yes, also report all of:)
    INTERNAL_SUBAGENT_ID: <its registry/session id>
    INTERNAL_SUBAGENT_HARNESS: <harness name>
    INTERNAL_SUBAGENT_MODEL: <model>
    INTERNAL_SUBAGENT_EFFORT: <effort>
    INTERNAL_SUBAGENT_PURPOSE: <why it was spawned, one line>
    INTERNAL_SUBAGENT_MODE: read-only | mutating
    INTERNAL_SUBAGENT_SAME_WORKTREE: true | false
    INTERNAL_SUBAGENT_SAME_PROJECT: true | false
    INTERNAL_SUBAGENT_FIRSTMATE_TASK_CREATED: none | <task id>
    INTERNAL_SUBAGENT_CONTEXT_INHERITED: <what it inherited from you,
      e.g. same cwd/worktree, shared local:// root - never re-derived>

Pre-work requirement:
  Read every path named above, resolved from your current worktree root,
  before substantive work. Report any missing, unreadable, or conflicting
  path instead of silently falling back to a different scope or a global
  default. Re-check applicable instructions before editing outside this
  subtree if scope expands.

Task:
  1. Add a NOT NULL constraint to migrations/0001_init.sql.
  2. Add a short note to sub/notes.md explaining the change.
  3. Run a verification command for the change and report what it observed.
  4. Report the bounded-internal-delegation evidence above (yes/no/not-
     applicable).
  5. Report what you read and applied, plus the skill-catalog and
     internal-delegation evidence above.
EOF
}

# =============================================================================
# Bounded-internal-delegation canary fixture: real, disposable canary files
# placed INSIDE the caller's own real task worktree (never a synthetic
# standalone repo), because a native bounded subagent (e.g. omp's task
# tool, non-isolated) always inherits the parent SESSION's cwd - there is
# no cwd/workspace parameter to spawn it elsewhere. That structural fact is
# itself part of the "same worktree" proof: the canary must be reachable
# from wherever the real subagent already stands, not planted in a
# separate repo it was never given a way to reach.
# =============================================================================
C_ID_PROJECT_INSTRUCTION='INTERNAL_DELEGATION_PROJECT_INSTRUCTION_CANARY'
C_ID_SKILL_NAME='internal-delegation-canary-skill'
C_ID_SKILL_BODY='INTERNAL_DELEGATION_SKILL_BODY_CANARY'
C_ID_TARGET_FILE='internal-delegation-canary-notes.md'

# fixture_internal_delegation_prepare <dir> - <dir> MUST be a path inside
# the real task worktree the caller is currently standing in (never a
# separate disposable repo - see the header above for why). Writes a
# canary project instruction, a canary project-local skill, and a target
# file; never deleted by this function, the caller owns cleanup (this
# fixture is scratch content and must never be committed).
fixture_internal_delegation_prepare() {
  local dir=$1
  mkdir -p "$dir/.agents/skills/$C_ID_SKILL_NAME"
  cat > "$dir/AGENTS.md" <<EOF
Rule: $C_ID_PROJECT_INSTRUCTION applies to files in this directory.

Required project-local skill:
  .agents/skills/$C_ID_SKILL_NAME/SKILL.md
Requirement:
  Read this skill before reading or discussing $C_ID_TARGET_FILE.
EOF
  cat > "$dir/.agents/skills/$C_ID_SKILL_NAME/SKILL.md" <<EOF
---
name: $C_ID_SKILL_NAME
description: Disposable canary skill for the bounded-internal-delegation acceptance fixture.
---
$C_ID_SKILL_BODY: read and apply this skill before reading or discussing
$C_ID_TARGET_FILE.
EOF
  printf -- '-- disposable internal-delegation canary target, read-only\n' > "$dir/$C_ID_TARGET_FILE"
}

# fixture_internal_delegation_handoff <dir> <expected-worktree> - the exact,
# read-only task text for a REAL bounded internal subagent. Never pastes a
# skill/instruction body (only the canary paths); the subagent must
# actually read them for the body markers to appear in its report.
fixture_internal_delegation_handoff() {
  local dir=$1 expected=$2
  cat <<EOF
You are a bounded, read-only, task-local helper spawned by your parent
through its harness's own native mechanism. You share your parent's exact
task/project/worktree - there is no separate workspace or cwd for you.
Do NOT write, edit, or run any mutating command. Do NOT create a
Firstmate task, switch project, or spawn any child agent of your own.

Before anything else, run \`pwd -P\` and \`git rev-parse --show-toplevel\`
yourself and report both raw outputs; they should equal $expected.

Read $dir/AGENTS.md, resolved from your current worktree root, and follow
what it says before reading $dir/$C_ID_TARGET_FILE.

Check your own available tool list for anything task/agent/subagent-
shaped; report whether one is present, and - regardless - do not use it.
Check your harness's own skill catalog (never a filesystem scan) for an
entry named captain-hold-lifecycle and report its count. Separately,
report the first content line of one real, already-installed shared
skill from your global skill root, naming which skill it is.

Report exactly these labels, one per line, then declare you are finished:
  INTERNAL_SUBAGENT_ID: <your own registry/session id>
  INTERNAL_SUBAGENT_HARNESS: <harness name>
  INTERNAL_SUBAGENT_MODEL: <model>
  INTERNAL_SUBAGENT_EFFORT: <effort>
  INTERNAL_SUBAGENT_PURPOSE: <why you were spawned, one line>
  INTERNAL_SUBAGENT_MODE: read-only
  INTERNAL_SUBAGENT_SAME_WORKTREE: true | false
  INTERNAL_SUBAGENT_SAME_PROJECT: true | false
  INTERNAL_SUBAGENT_FIRSTMATE_TASK_CREATED: none | <task id>
  INTERNAL_SUBAGENT_CONTEXT_INHERITED: <what you inherited, one line>
  INTERNAL_SUBAGENT_RECURSION_TOOL_SEEN: yes | no
  INTERNAL_SUBAGENT_RECURSION_TOOL_USED: no
  INTERNAL_SUBAGENT_OFFICIAL_INTERNAL_SKILL_COUNT: <n>
  INTERNAL_SUBAGENT_SHARED_SKILL_EVIDENCE: <skill name>: <its first content line>
EOF
}

# fixture_validate <transcript-file> - classifies each headline canary from
# raw transcript/output text as absent, present (catalog only), or applied
# (body-only marker reported). Offline illustrative classifier for the
# three headline canaries; see fixture_validate_live for the full set of
# report checks. Neither classifier independently observes tool use.
fixture_validate() {
  local f=$1 t
  t=$(cat "$f" 2>/dev/null || printf '')
  _wc_classify() { # <catalog-substring> <body-substring>
    case $t in
      *"$2"*) printf applied ;;
      *"$1"*) printf present ;;
      *) printf absent ;;
    esac
  }
  printf 'PROJECT_SKILL_CANARY    %s\n' "$(_wc_classify "$C_PROJECT_SKILL_NAME" "$C_PROJECT_SKILL_BODY")"
  printf 'SHARED_SKILL_CANARY     %s\n' "$(_wc_classify "$C_SHARED_SKILL_NAME" "$C_SHARED_SKILL_BODY")"
  printf 'CAPTAIN_ONLY_CANARY     %s\n' "$(_wc_classify "$C_CAPTAIN_ONLY" "$C_CAPTAIN_ONLY")"
}

# _wc_field <text> <label> -> the value after "LABEL:" on the last matching
# line, trimmed; empty if the label never appears verbatim.
_wc_field() {
  printf '%s\n' "$1" | sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" | tail -1
}

_wc_starts_with() { case $1 in "$2"*) return 0 ;; *) return 1 ;; esac; }

# fixture_validate_live <worker-report-file> [expected-worktree] - checks
# a delegated-worker transcript/report for the fixture's required evidence.
# Prints PASS/FAIL/SKIP for each report check; returns 0 when those checks
# pass, not when a FirstMate task is authorized to complete. Reported paths,
# canaries and catalog counts need corroboration from the live session.
# Omitting a forbidden skill name alone is not enough: the report must
# include skill origins, catalog sources and the official-internal count.
fixture_validate_live() {
  local report=$1 expected=${2:-} t all_ok=0
  local proj_path shared_path sources count
  if [ ! -r "$report" ]; then
    printf 'FAIL WORKTREE_REPORT_READABLE   worker report not readable: %s\n' "$report"
    return 1
  fi
  t=$(cat "$report")

  _req() { # <label> <ok:0|1>
    if [ "$2" -eq 0 ]; then printf 'PASS %-28s\n' "$1"; else printf 'FAIL %-28s\n' "$1"; all_ok=1; fi
  }

  if [ -n "$expected" ]; then
    case $t in
      *"$expected"*) _req EXPECTED_WORKTREE 0 ;;
      *) _req EXPECTED_WORKTREE 1 ;;
    esac
  else
    printf 'SKIP %-28s (no expected worktree given)\n' EXPECTED_WORKTREE
  fi

  case $t in *"$C_ROOT_OVERRIDE"*) _req ROOT_OVERRIDE_AUTHORITY 0 ;; *) _req ROOT_OVERRIDE_AUTHORITY 1 ;; esac

  case $t in
    *"$C_ROOT_AGENTS_SHADOWED"*|*"$C_ROOT_CLAUDE_NEVER_WIN"*) _req SHADOWED_MARKERS_ABSENT 1 ;;
    *) _req SHADOWED_MARKERS_ABSENT 0 ;;
  esac

  case $t in *"$C_NESTED_SCOPE"*) _req NESTED_SCOPE_APPLIED 0 ;; *) _req NESTED_SCOPE_APPLIED 1 ;; esac

  # Marker presence records reported skill use, not the order of tool access.
  case $t in *"$C_PROJECT_SKILL_BODY"*) _req PROJECT_SKILL_APPLIED 0 ;; *) _req PROJECT_SKILL_APPLIED 1 ;; esac

  case $t in *"$C_SHARED_SKILL_BODY"*) _req SHARED_SKILL_APPLIED 0 ;; *) _req SHARED_SKILL_APPLIED 1 ;; esac

  case $t in
    *"$C_PROJECT_WINS"*)
      case $t in *"$C_GLOBAL_LEAK"*) _req PROJECT_OVER_SHARED_AUTHORITY 1 ;; *) _req PROJECT_OVER_SHARED_AUTHORITY 0 ;; esac
      ;;
    *) _req PROJECT_OVER_SHARED_AUTHORITY 1 ;;
  esac

  # Defense-in-depth only: never sufficient by itself (see below).
  case $t in *"$C_CAPTAIN_ONLY"*) _req CAPTAIN_ONLY_ABSENT 1 ;; *) _req CAPTAIN_ONLY_ABSENT 0 ;; esac

  # Positive origin proof: the required project skill must have resolved
  # under the worker's own worktree, never a global or unrelated path.
  proj_path=$(_wc_field "$t" PROJECT_SKILL_RESOLVED_PATH)
  if [ -z "$expected" ]; then
    printf 'SKIP %-28s (no expected worktree given)\n' PROJECT_SKILL_PATH_UNDER_WORKTREE
  elif [ -n "$proj_path" ] && _wc_starts_with "$proj_path" "$expected"; then
    _req PROJECT_SKILL_PATH_UNDER_WORKTREE 0
  else
    _req PROJECT_SKILL_PATH_UNDER_WORKTREE 1
  fi

  # Positive origin proof: the shared skill must have resolved to the real
  # global shared root's copy, never a project-local stand-in.
  shared_path=$(_wc_field "$t" SHARED_SKILL_RESOLVED_PATH)
  case $shared_path in
    *".agents/skills/$C_SHARED_SKILL_NAME/SKILL.md")
      if [ -n "$expected" ] && _wc_starts_with "$shared_path" "$expected"; then
        _req SHARED_SKILL_PATH_IS_GLOBAL 1
      else
        _req SHARED_SKILL_PATH_IS_GLOBAL 0
      fi
      ;;
    *) _req SHARED_SKILL_PATH_IS_GLOBAL 1 ;;
  esac

  # The worker must have actually introspected its own harness-exposed
  # skill catalog (source roots and a count), not merely stayed silent.
  sources=$(_wc_field "$t" SKILL_CATALOG_SOURCES)
  case $sources in
    [0-9]*) _req SKILL_CATALOG_SOURCES_REPORTED 0 ;;
    *) _req SKILL_CATALOG_SOURCES_REPORTED 1 ;;
  esac

  # The decisive official-internal-skill proof: an explicit reported zero
  # count of catalog entries under the official FirstMate distro root.
  # Missing this line fails - it is never inferred from name-omission.
  count=$(_wc_field "$t" OFFICIAL_INTERNAL_SKILL_COUNT)
  if [ "$count" = 0 ]; then
    _req OFFICIAL_INTERNAL_SKILL_COUNT_ZERO 0
  else
    _req OFFICIAL_INTERNAL_SKILL_COUNT_ZERO 1
  fi

  # Bounded internal delegation (README.md "Bounded internal delegation",
  # firstmate/primary-policy.md section 6). A worker that never reports
  # INTERNAL_SUBAGENT_USED at all fails outright - silence is not
  # "not-applicable". "not-applicable" and "no" both skip the detail
  # checks below (nothing to prove); "yes" requires every scope/context
  # field to be present AND correct: read-only, same worktree, same
  # project, and no separate Firstmate task created.
  local subagent_used mode same_wt same_proj fm_task
  subagent_used=$(_wc_field "$t" INTERNAL_SUBAGENT_USED)
  case $subagent_used in
    yes*|no*|not-applicable*) _req INTERNAL_SUBAGENT_EVIDENCE_REPORTED 0 ;;
    *) _req INTERNAL_SUBAGENT_EVIDENCE_REPORTED 1 ;;
  esac
  case $subagent_used in
    yes*)
      mode=$(_wc_field "$t" INTERNAL_SUBAGENT_MODE)
      same_wt=$(_wc_field "$t" INTERNAL_SUBAGENT_SAME_WORKTREE)
      same_proj=$(_wc_field "$t" INTERNAL_SUBAGENT_SAME_PROJECT)
      fm_task=$(_wc_field "$t" INTERNAL_SUBAGENT_FIRSTMATE_TASK_CREATED)
      case $mode in read-only) _req INTERNAL_SUBAGENT_READ_ONLY 0 ;; *) _req INTERNAL_SUBAGENT_READ_ONLY 1 ;; esac
      case $same_wt in true) _req INTERNAL_SUBAGENT_SAME_WORKTREE 0 ;; *) _req INTERNAL_SUBAGENT_SAME_WORKTREE 1 ;; esac
      case $same_proj in true) _req INTERNAL_SUBAGENT_SAME_PROJECT 0 ;; *) _req INTERNAL_SUBAGENT_SAME_PROJECT 1 ;; esac
      case $fm_task in none) _req INTERNAL_SUBAGENT_NO_FIRSTMATE_TASK 0 ;; *) _req INTERNAL_SUBAGENT_NO_FIRSTMATE_TASK 1 ;; esac
      if [ -n "$(_wc_field "$t" INTERNAL_SUBAGENT_ID)" ] && [ -n "$(_wc_field "$t" INTERNAL_SUBAGENT_HARNESS)" ] \
        && [ -n "$(_wc_field "$t" INTERNAL_SUBAGENT_PURPOSE)" ] && [ -n "$(_wc_field "$t" INTERNAL_SUBAGENT_CONTEXT_INHERITED)" ]; then
        _req INTERNAL_SUBAGENT_IDENTITY_REPORTED 0
      else
        _req INTERNAL_SUBAGENT_IDENTITY_REPORTED 1
      fi

      # Require the fixture's content as well as the helper's labels.
      # This checks the report; actual reads still need session evidence.
      case $t in
        *"$C_ID_PROJECT_INSTRUCTION"*"$C_ID_SKILL_BODY"*|*"$C_ID_SKILL_BODY"*"$C_ID_PROJECT_INSTRUCTION"*)
          _req INTERNAL_SUBAGENT_CANARY_APPLIED 0 ;;
        *) _req INTERNAL_SUBAGENT_CANARY_APPLIED 1 ;;
      esac

      # Bounded recursion: seeing a delegation-shaped tool is fine (the
      # harness's own native depth gate governs that); actually using one
      # is not - this task's acceptance scenario is exactly one bounded
      # level, never a chain.
      case $(_wc_field "$t" INTERNAL_SUBAGENT_RECURSION_TOOL_USED) in
        no) _req INTERNAL_SUBAGENT_RECURSION_BOUNDED 0 ;;
        *) _req INTERNAL_SUBAGENT_RECURSION_BOUNDED 1 ;;
      esac

      # Zero official-internal-skill leakage into the internal subagent's
      # own catalog view - the same positive-count proof pattern as the
      # outer worker's OFFICIAL_INTERNAL_SKILL_COUNT_ZERO check above.
      case $(_wc_field "$t" INTERNAL_SUBAGENT_OFFICIAL_INTERNAL_SKILL_COUNT) in
        0) _req INTERNAL_SUBAGENT_ZERO_OFFICIAL_LEAK 0 ;;
        *) _req INTERNAL_SUBAGENT_ZERO_OFFICIAL_LEAK 1 ;;
      esac
      ;;
    *)
      for label in INTERNAL_SUBAGENT_READ_ONLY INTERNAL_SUBAGENT_SAME_WORKTREE INTERNAL_SUBAGENT_SAME_PROJECT \
        INTERNAL_SUBAGENT_NO_FIRSTMATE_TASK INTERNAL_SUBAGENT_IDENTITY_REPORTED INTERNAL_SUBAGENT_CANARY_APPLIED \
        INTERNAL_SUBAGENT_RECURSION_BOUNDED INTERNAL_SUBAGENT_ZERO_OFFICIAL_LEAK; do
        printf 'SKIP %-28s (%s)\n' "$label" "no internal subagent reported ($subagent_used)"
      done
      ;;
  esac

  return $all_ok
}

# =============================================================================
# CLI dispatch - must run before any offline-suite scratch state (TMP_ROOT,
# its EXIT trap) is created, so prepare/validate/handoff never depend on or
# disturb the default suite's own temporary root.
# =============================================================================
case "${1:-}" in
  prepare)
    dir=${2:?"usage: $0 prepare <directory>"}
    mkdir -p "$dir"
    fixture_prepare "$dir"
    printf '%s\n' "$dir/repo"
    exit 0
    ;;
  handoff)
    repo=${2:?"usage: $0 handoff <repo-dir>"}
    fixture_handoff "$repo"
    exit 0
    ;;
  internal-prepare)
    dir=${2:?"usage: $0 internal-prepare <directory-inside-your-real-task-worktree>"}
    fixture_internal_delegation_prepare "$dir"
    printf '%s\n' "$dir"
    exit 0
    ;;
  internal-handoff)
    dir=${2:?"usage: $0 internal-handoff <directory> <expected-worktree>"}
    expected=${3:?"usage: $0 internal-handoff <directory> <expected-worktree>"}
    fixture_internal_delegation_handoff "$dir" "$expected"
    exit 0
    ;;
  validate)
    report=${2:?"usage: $0 validate <worker-report> [expected-worktree]"}
    fixture_validate_live "$report" "${3:-}"
    exit $?
    ;;
  '') ;; # fall through to the offline suite below
  *)
    printf 'usage: %s [prepare <directory>|handoff <repo-dir>|internal-prepare <directory>|internal-handoff <directory> <expected-worktree>|validate <worker-report> [expected-worktree]]\n' "$0" >&2
    exit 2
    ;;
esac

# =============================================================================
# Offline suite (default, no arguments)
# =============================================================================

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-worker-context.XXXXXX") || exit 1
TMP_ROOT=$(cd "$TMP_ROOT" && pwd)
trap 'rm -rf "$TMP_ROOT"' EXIT

# =============================================================================
# 1. fixture_validate's own matcher logic, proven against synthetic
#    transcripts (offline unit test of the validator; not itself a live
#    delegated-worker run).
# =============================================================================
GOOD_TRANSCRIPT="$TMP_ROOT/good-transcript.txt"
cat > "$GOOD_TRANSCRIPT" <<EOF
Reading .agents/skills/migration-canary/SKILL.md before touching migrations/.
$C_PROJECT_SKILL_BODY: read and apply this skill before reading, writing,
reviewing, or editing anything under migrations/. Applying it now.
Applying $C_SHARED_SKILL_NAME before declaring done: the rule is
$C_SHARED_SKILL_BODY, so I ran the tests and read their output before this
claim.
EOF
out=$(fixture_validate "$GOOD_TRANSCRIPT")
contains 'compliant transcript: project skill canary applied' "$out" 'PROJECT_SKILL_CANARY    applied'
contains 'compliant transcript: shared skill canary applied' "$out" 'SHARED_SKILL_CANARY     applied'
contains 'compliant transcript: captain-only canary stays absent' "$out" 'CAPTAIN_ONLY_CANARY     absent'

LEAKY_TRANSCRIPT="$TMP_ROOT/leaky-transcript.txt"
cat > "$LEAKY_TRANSCRIPT" <<EOF
Noticed a $C_PROJECT_SKILL_NAME skill exists but did not read its body.
Skipped verification entirely.
For process, also consulted $C_CAPTAIN_ONLY.
EOF
out=$(fixture_validate "$LEAKY_TRANSCRIPT")
contains 'non-compliant transcript: project skill canary only present, not applied' "$out" 'PROJECT_SKILL_CANARY    present'
contains 'non-compliant transcript: shared skill canary absent' "$out" 'SHARED_SKILL_CANARY     absent'
not_contains 'non-compliant transcript: captain-only canary is caught, never reported absent' "$out" 'CAPTAIN_ONLY_CANARY     absent'

# =============================================================================
# 2. Official-internal-skill negative check (structural, offline): no name
#    this repository installs as a shared worker skill collides with a real
#    official FirstMate internal skill name.
# =============================================================================
official_names() { # -> one official-internal skill name per line
  [ -d "$FIRSTMATE_ROOT/.agents/skills" ] || return 0
  local d
  for d in "$FIRSTMATE_ROOT"/.agents/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
    basename "$d"
  done
}

config_shared_names() { # -> one firstmate-config shared skill name per line
  local d
  for d in "$CONFIG_ROOT"/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
    basename "$d"
  done
  [ -f "$CONFIG_ROOT/skills/external.lock" ] || return 0
  while IFS="$(printf '\t')" read -r id _repo _sha _path name; do
    case ${id:-} in ''|\#*) continue ;; esac
    [ -n "${name:-}" ] || continue
    printf '%s\n' "$name"
  done < "$CONFIG_ROOT/skills/external.lock"
}

if [ -d "$FIRSTMATE_ROOT/.agents/skills" ]; then
  overlap=$(comm -12 <(official_names | sort -u) <(config_shared_names | sort -u))
  if [ -z "$overlap" ]; then
    pass 'official-internal-skill negative check: no name collision with firstmate-config shared skills'
  else
    fail "official-internal-skill negative check: colliding name(s): $overlap"
  fi
  names=$(official_names)
  case $names in
    *"$C_CAPTAIN_ONLY"*) pass 'official-internal-skill negative check: captain-hold-lifecycle confirmed official-internal' ;;
    *) fail 'official-internal-skill negative check: captain-hold-lifecycle not found under official FirstMate - update the fixture canary' ;;
  esac
  not_contains 'official-internal-skill negative check: captain-hold-lifecycle is never a firstmate-config shared skill name' "$(config_shared_names)" "$C_CAPTAIN_ONLY"
else
  pass 'official-internal-skill negative check: skipped (no official FirstMate checkout at FIRSTMATE_ROOT)'
fi

# =============================================================================
# 3. Real, zero-inference probe of Pi's installed native resource loader
#    against the fixture: root/nested/override precedence, project-trust
#    gating, and project-local-over-global skill dedup. No AgentSession, no
#    model call.
# =============================================================================
resolve_pi_pkg_root() {
  command -v pi >/dev/null 2>&1 || return 1
  command -v node >/dev/null 2>&1 || return 1
  local pi_bin pi_js pkg
  pi_bin=$(command -v pi)
  pi_js=$(node -p 'require("fs").realpathSync(process.argv[1])' "$pi_bin" 2>/dev/null) || return 1
  case $pi_js in
    */dist/bundle/cli.js) pkg=${pi_js%/dist/bundle/cli.js} ;;
    *) return 1 ;;
  esac
  [ -f "$pkg/dist/core/resource-loader.js" ] && [ -f "$pkg/dist/core/settings-manager.js" ] || return 1
  printf '%s' "$pkg"
}

PI_PKG_ROOT=$(resolve_pi_pkg_root || printf '')
if [ -z "$PI_PKG_ROOT" ]; then
  pass 'Pi native-loader probe: skipped (pi/node unavailable or internal module layout changed)'
else
  FIX_DIR="$TMP_ROOT/pi-fixture"
  mkdir -p "$FIX_DIR"
  fixture_prepare "$FIX_DIR"
  PI_REPO="$FIX_DIR/repo"
  PI_HOME="$TMP_ROOT/pi-home"
  PI_AGENT_DIR="$PI_HOME/.pi/agent"
  mkdir -p "$PI_HOME/.agents/skills/architecture-review" "$PI_HOME/.agents/skills/shared-fixture-skill" "$PI_AGENT_DIR"
  cat > "$PI_HOME/.agents/skills/architecture-review/SKILL.md" <<EOF
---
name: architecture-review
description: Real global shared architecture-review stand-in.
---
$C_GLOBAL_LEAK
EOF
  cat > "$PI_HOME/.agents/skills/shared-fixture-skill/SKILL.md" <<'EOF'
---
name: shared-fixture-skill
description: Fixture stand-in for a selected shared worker skill.
---
SHARED_FIXTURE_CANARY
EOF

  PROBE="$TMP_ROOT/pi-probe.mjs"
  cat > "$PROBE" <<EOF
import { DefaultResourceLoader, loadProjectContextFiles } from '$PI_PKG_ROOT/dist/core/resource-loader.js';
import { SettingsManager } from '$PI_PKG_ROOT/dist/core/settings-manager.js';
import path from 'node:path';
const repo = '$PI_REPO';
const agentDir = '$PI_AGENT_DIR';
const out = {};
for (const trusted of [false, true]) {
  const settingsManager = SettingsManager.create(repo, agentDir, { projectTrusted: trusted });
  const loader = new DefaultResourceLoader({ cwd: repo, agentDir, settingsManager, noExtensions: true, noPromptTemplates: true, noThemes: true });
  await loader.reload();
  const skills = loader.getSkills().skills;
  const contexts = loader.getAgentsFiles().agentsFiles.filter(f => f.path.startsWith(repo));
  out[trusted ? 'trusted' : 'untrusted'] = {
    contexts: contexts.map(f => f.path),
    skills: skills.map(s => ({ name: s.name, path: s.filePath })),
  };
}
out.nested = loadProjectContextFiles({ cwd: path.join(repo, 'sub'), agentDir })
  .filter(f => f.path.startsWith(repo)).map(f => f.path);
console.log(JSON.stringify(out));
EOF
  probe_out=$(HOME="$PI_HOME" node "$PROBE" 2>&1)
  probe_rc=$?
  if [ "$probe_rc" -ne 0 ]; then
    fail "Pi native-loader probe: node exited $probe_rc: $probe_out"
  else
    UNTRUSTED_PART=${probe_out%%,\"trusted\"*}
    TRUSTED_PART=${probe_out#*\"trusted\":}
    contains 'Pi native-loader probe: override wins at repo root (untrusted)' "$probe_out" "$PI_REPO/AGENTS.override.md"
    not_contains 'Pi native-loader probe: shadowed root AGENTS.md never surfaces' "$probe_out" "\"$PI_REPO/AGENTS.md\""
    not_contains 'Pi native-loader probe: root CLAUDE.md never surfaces alongside AGENTS' "$probe_out" "$PI_REPO/CLAUDE.md"
    contains 'Pi native-loader probe: nested sub/AGENTS.md applies only in that scope' "$probe_out" "$PI_REPO/sub/AGENTS.md"
    contains 'Pi native-loader probe: untrusted project still sees the shared global skill' "$probe_out" 'shared-fixture-skill'
    not_contains 'Pi native-loader probe: untrusted project never sees the project-local migration skill' "$UNTRUSTED_PART" 'migration-canary'
    contains 'Pi native-loader probe: trusted project sees the required migration skill' "$TRUSTED_PART" 'migration-canary'
    contains 'Pi native-loader probe: trusted project-local architecture-review wins the same-name collision' "$TRUSTED_PART" "\"path\":\"$PI_REPO/.agents/skills/architecture-review/SKILL.md\""
    not_contains 'Pi native-loader probe: the global architecture-review stand-in never wins once project-local exists' "$TRUSTED_PART" "\"path\":\"$PI_HOME/.agents/skills/architecture-review/SKILL.md\""
    not_contains 'Pi native-loader probe: the official-internal captain-hold-lifecycle name never surfaces as a skill' "$probe_out" "$C_CAPTAIN_ONLY"
  fi
fi

# =============================================================================
# 3b. Real, zero-inference filesystem check (no model call, no AgentSession):
#     Pi's installed bundled tool set ships no task/agent/subagent tool, so
#     "a Pi worker does not spawn workers" (README.md "Bounded internal
#     delegation", firstmate/primary-policy.md section 6) is verified rather
#     than assumed. Mirrors README.md's Codex tripwire: if a future Pi
#     release adds one, this check starts failing and the policy text and
#     `not-applicable` fixtures above need updating together.
# =============================================================================
if [ -z "$PI_PKG_ROOT" ]; then
  pass 'Pi native task-tool absence probe: skipped (pi/node unavailable or internal module layout changed)'
elif [ ! -d "$PI_PKG_ROOT/dist/core/tools" ]; then
  pass 'Pi native task-tool absence probe: skipped (bundled tools directory layout changed)'
else
  pi_tool_names=$(find "$PI_PKG_ROOT/dist/core/tools" -maxdepth 1 -name '*.js' ! -name '*.d.ts*' -exec basename {} \; | sort)
  case $pi_tool_names in
    *task*|*agent*|*subagent*|*delegat*)
      fail "Pi native task-tool absence probe: unexpected delegation-shaped tool file found: $pi_tool_names"
      ;;
    *)
      pass 'Pi native task-tool absence probe: bundled tool set has no task/agent/subagent/delegate file'
      ;;
  esac
fi

# =============================================================================
# 4. Real, zero-inference read of OMP's own installed documentation: grounds
#    the documented discovery gap (no AGENTS.override.md support) this
#    contract exists to cover. `omp read` never starts a session or a model
#    turn.
# =============================================================================
if command -v omp >/dev/null 2>&1; then
  OMP_HOME="$TMP_ROOT/omp-home"
  OMP_TMPDIR="$TMP_ROOT/omp-tmp"
  mkdir -p "$OMP_HOME" "$OMP_TMPDIR"
  omp_doc=$(HOME="$OMP_HOME" TMPDIR="$OMP_TMPDIR" OMP_SKIP_SETUP=1 omp read omp://context-files.md:raw 2>/dev/null)
  if [ -z "$omp_doc" ]; then
    pass 'OMP context-files doc probe: skipped (omp read unavailable in this environment)'
  else
    not_contains 'OMP context-files doc: no AGENTS.override.md provider is documented' "$omp_doc" 'AGENTS.override'
    contains 'OMP context-files doc: standalone AGENTS.md is documented' "$omp_doc" 'AGENTS.md'
  fi
else
  pass 'OMP context-files doc probe: skipped (omp not on PATH)'
fi

# =============================================================================
# 5. CLI interface: prepare/handoff/validate, the externally usable
#    prepare/validate interface for Firstmate's own live Herdr -> Pi /
#    Herdr -> OMP fixture runs. Each sub-invocation below runs this same
#    script as a fresh process; the CLI dispatch above guarantees none of
#    them re-enters this offline suite or its $TMP_ROOT.
# =============================================================================
SELF="$CONFIG_ROOT/tests/worker-context.sh"
CLI_DIR="$TMP_ROOT/cli-prepare"
prep_out=$(bash "$SELF" prepare "$CLI_DIR" 2>&1); prep_rc=$?
check 'CLI prepare: exits 0' 0 "$prep_rc"
check 'CLI prepare: prints the fixture repo path' "$CLI_DIR/repo" "$prep_out"
if [ -f "$CLI_DIR/repo/AGENTS.override.md" ]; then pass 'CLI prepare: fixture repo exists and is persistent'; else fail 'CLI prepare: fixture repo missing'; fi

handoff_out=$(bash "$SELF" handoff "$CLI_DIR/repo" 2>&1); handoff_rc=$?
check 'CLI handoff: exits 0' 0 "$handoff_rc"
contains 'CLI handoff: names the required project skill path' "$handoff_out" 'migration-canary/SKILL.md'
contains 'CLI handoff: names the selected shared worker skill' "$handoff_out" "$C_SHARED_SKILL_NAME"
for marker in "$C_ROOT_OVERRIDE" "$C_ROOT_AGENTS_SHADOWED" "$C_ROOT_CLAUDE_NEVER_WIN" "$C_NESTED_SCOPE" \
  "$C_PROJECT_SKILL_BODY" "$C_SHARED_SKILL_BODY" "$C_PROJECT_WINS" "$C_GLOBAL_LEAK" "$C_CAPTAIN_ONLY"; do
  not_contains "CLI handoff: never quotes the canary marker '$marker'" "$handoff_out" "$marker"
done
contains 'CLI handoff: requires PROJECT_SKILL_RESOLVED_PATH evidence' "$handoff_out" 'PROJECT_SKILL_RESOLVED_PATH'
contains 'CLI handoff: requires SHARED_SKILL_RESOLVED_PATH evidence' "$handoff_out" 'SHARED_SKILL_RESOLVED_PATH'
contains 'CLI handoff: requires SKILL_CATALOG_SOURCES evidence' "$handoff_out" 'SKILL_CATALOG_SOURCES'
contains 'CLI handoff: requires OFFICIAL_INTERNAL_SKILL_COUNT evidence' "$handoff_out" 'OFFICIAL_INTERNAL_SKILL_COUNT'
contains 'CLI handoff: instructs using the harness catalog, never a filesystem scan' "$handoff_out" 'Never a filesystem scan'
contains 'CLI handoff: names the official FirstMate root only as a comparison root' "$handoff_out" "$FIRSTMATE_ROOT"

# The source fixture's absolute path must never leak into the handoff: the
# worker's isolated task worktree does not exist yet when the handoff is
# generated, and reading the primary/source checkout instead of that
# worktree is exactly the violation this proves absent. A unique token in
# the source path makes a leak unmistakable, not just plausible.
SOURCE_DIR="$TMP_ROOT/SOURCE-ONLY-$$-do-not-leak"
mkdir -p "$SOURCE_DIR"
fixture_prepare "$SOURCE_DIR"
SOURCE_REPO="$SOURCE_DIR/repo"
source_handoff_out=$(bash "$SELF" handoff "$SOURCE_REPO" 2>&1)
not_contains 'CLI handoff: never prints the source/primary checkout absolute path' "$source_handoff_out" "$SOURCE_REPO"
not_contains 'CLI handoff: never prints the unique source-path token' "$source_handoff_out" 'SOURCE-ONLY'
contains 'CLI handoff: names AGENTS.override.md as a bare worktree-relative path' "$source_handoff_out" 'AGENTS.override.md'
contains 'CLI handoff: names sub/AGENTS.md as a bare worktree-relative path' "$source_handoff_out" 'sub/AGENTS.md'
contains 'CLI handoff: names the migration skill as a bare worktree-relative path' "$source_handoff_out" '.agents/skills/migration-canary/SKILL.md'
contains 'CLI handoff: names the migration file as a bare worktree-relative path' "$source_handoff_out" 'migrations/0001_init.sql'
contains 'CLI handoff: instructs verifying pwd -P against the current worktree' "$source_handoff_out" 'pwd -P'
contains 'CLI handoff: instructs verifying against git rev-parse --show-toplevel' "$source_handoff_out" 'git rev-parse --show-toplevel'

GOOD_REPORT="$TMP_ROOT/cli-good-report.txt"
cat > "$GOOD_REPORT" <<EOF
Ran in $CLI_DIR/repo.
$C_ROOT_OVERRIDE observed and followed.
$C_NESTED_SCOPE observed under sub/.
$C_PROJECT_SKILL_BODY applied before touching $C_MIGRATION_FILE.
$C_SHARED_SKILL_BODY confirmed before declaring completion.
$C_PROJECT_WINS applied for architecture-review.
PROJECT_SKILL_RESOLVED_PATH: $CLI_DIR/repo/.agents/skills/$C_PROJECT_SKILL_NAME/SKILL.md
SHARED_SKILL_RESOLVED_PATH: $HOME/.agents/skills/$C_SHARED_SKILL_NAME/SKILL.md
SKILL_CATALOG_SOURCES: 3 source root(s): $HOME/.pi/agent/skills, $CLI_DIR/repo/.agents/skills, $HOME/.agents/skills
OFFICIAL_INTERNAL_SKILL_COUNT: 0
INTERNAL_SUBAGENT_USED: not-applicable (harness has no native bounded subagent mechanism)
EOF
val_out=$(bash "$SELF" validate "$GOOD_REPORT" "$CLI_DIR/repo" 2>&1); val_rc=$?
check 'CLI validate: complete context evidence needs no verification runner' 0 "$val_rc"
not_contains 'CLI validate: complete context evidence has no FAIL line' "$val_out" 'FAIL'

# A summary is not an ordered tool trace. Mentioning the target before the
# skill marker must not be treated as evidence of an early file access.
SUMMARY_REPORT="$TMP_ROOT/cli-summary-report.txt"
printf 'Changed %s.\n' "$C_MIGRATION_FILE" > "$SUMMARY_REPORT"
cat "$GOOD_REPORT" >> "$SUMMARY_REPORT"
summary_out=$(bash "$SELF" validate "$SUMMARY_REPORT" "$CLI_DIR/repo" 2>&1); summary_rc=$?
check 'CLI validate: report presentation order is not tool execution order' 0 "$summary_rc"

MISSING_SKILL_REPORT="$TMP_ROOT/cli-missing-skill-report.txt"
grep -v -F "$C_PROJECT_SKILL_BODY" "$GOOD_REPORT" > "$MISSING_SKILL_REPORT"
missing_skill_out=$(bash "$SELF" validate "$MISSING_SKILL_REPORT" "$CLI_DIR/repo" 2>&1); missing_skill_rc=$?
if [ "$missing_skill_rc" -eq 0 ]; then fail 'CLI validate: missing project skill evidence unexpectedly exits 0'; else pass 'CLI validate: missing project skill evidence exits nonzero'; fi
contains 'CLI validate: missing project skill evidence fails its specific check' "$missing_skill_out" 'FAIL PROJECT_SKILL_APPLIED'

BAD_REPORT="$TMP_ROOT/cli-bad-report.txt"
cat > "$BAD_REPORT" <<EOF
Ran somewhere else.
$C_ROOT_AGENTS_SHADOWED leaked.
$C_CAPTAIN_ONLY consulted.
EOF
val_bad_out=$(bash "$SELF" validate "$BAD_REPORT" "$CLI_DIR/repo" 2>&1); val_bad_rc=$?
if [ "$val_bad_rc" -eq 0 ]; then fail 'CLI validate: a non-compliant report unexpectedly exits 0'; else pass 'CLI validate: a non-compliant report exits nonzero'; fi
contains 'CLI validate: a non-compliant report reports the shadowed-marker failure' "$val_bad_out" 'FAIL SHADOWED_MARKERS_ABSENT'
contains 'CLI validate: a non-compliant report reports the captain-only leak' "$val_bad_out" 'FAIL CAPTAIN_ONLY_ABSENT'
contains 'CLI validate: a non-compliant report reports the missing expected worktree' "$val_bad_out" 'FAIL EXPECTED_WORKTREE'

# The exact false-confidence failure this task's steering caught: a report
# that omits the forbidden skill name's literal text - the old
# CAPTAIN_ONLY_ABSENT check alone would have PASSed this - but provides no
# positive skill-catalog evidence at all. This must fail overall.
FALSE_CONFIDENCE_REPORT="$TMP_ROOT/cli-false-confidence-report.txt"
cat > "$FALSE_CONFIDENCE_REPORT" <<EOF
Ran in $CLI_DIR/repo. Read and applied everything required. All good.
EOF
val_fc_out=$(bash "$SELF" validate "$FALSE_CONFIDENCE_REPORT" "$CLI_DIR/repo" 2>&1); val_fc_rc=$?
if [ "$val_fc_rc" -eq 0 ]; then fail 'CLI validate: false-confidence report (name omitted, no catalog evidence) unexpectedly exits 0'; else pass 'CLI validate: false-confidence report exits nonzero'; fi
contains 'CLI validate: false-confidence report still reports the name-omission check as PASS (never sufficient alone)' "$val_fc_out" 'PASS CAPTAIN_ONLY_ABSENT'
contains 'CLI validate: false-confidence report fails on missing catalog-source evidence' "$val_fc_out" 'FAIL SKILL_CATALOG_SOURCES_REPORTED'
contains 'CLI validate: false-confidence report fails on missing official-internal-count evidence' "$val_fc_out" 'FAIL OFFICIAL_INTERNAL_SKILL_COUNT_ZERO'

# A worker that reports a nonzero official-internal catalog count must
# fail even though it never mentions the forbidden skill name literally.
LEAK_COUNT_REPORT="$TMP_ROOT/cli-leak-count-report.txt"
cat > "$LEAK_COUNT_REPORT" <<EOF
Ran in $CLI_DIR/repo.
PROJECT_SKILL_RESOLVED_PATH: $CLI_DIR/repo/.agents/skills/$C_PROJECT_SKILL_NAME/SKILL.md
SHARED_SKILL_RESOLVED_PATH: $HOME/.agents/skills/$C_SHARED_SKILL_NAME/SKILL.md
SKILL_CATALOG_SOURCES: 3 source root(s): $HOME/.pi/agent/skills, $CLI_DIR/repo/.agents/skills, $HOME/.agents/skills
OFFICIAL_INTERNAL_SKILL_COUNT: 1
EOF
val_leak_out=$(bash "$SELF" validate "$LEAK_COUNT_REPORT" "$CLI_DIR/repo" 2>&1); val_leak_rc=$?
if [ "$val_leak_rc" -eq 0 ]; then fail 'CLI validate: a nonzero official-internal-skill count unexpectedly exits 0'; else pass 'CLI validate: a nonzero official-internal-skill count exits nonzero'; fi
contains 'CLI validate: a nonzero official-internal-skill count fails the count check' "$val_leak_out" 'FAIL OFFICIAL_INTERNAL_SKILL_COUNT_ZERO'

# The resolved-path origin proofs themselves: a project skill resolved
# outside the worktree, or a "shared" skill resolved inside it, must fail
# even with an otherwise well-formed report.
PATH_ORIGIN_BAD_REPORT="$TMP_ROOT/cli-path-origin-bad-report.txt"
cat > "$PATH_ORIGIN_BAD_REPORT" <<EOF
Ran in $CLI_DIR/repo.
PROJECT_SKILL_RESOLVED_PATH: $HOME/.agents/skills/$C_PROJECT_SKILL_NAME/SKILL.md
SHARED_SKILL_RESOLVED_PATH: $CLI_DIR/repo/.agents/skills/$C_SHARED_SKILL_NAME/SKILL.md
SKILL_CATALOG_SOURCES: 3 source root(s): $HOME/.pi/agent/skills, $CLI_DIR/repo/.agents/skills, $HOME/.agents/skills
OFFICIAL_INTERNAL_SKILL_COUNT: 0
EOF
val_origin_out=$(bash "$SELF" validate "$PATH_ORIGIN_BAD_REPORT" "$CLI_DIR/repo" 2>&1); val_origin_rc=$?
if [ "$val_origin_rc" -eq 0 ]; then fail 'CLI validate: swapped project/shared skill origins unexpectedly exits 0'; else pass 'CLI validate: swapped project/shared skill origins exits nonzero'; fi
contains 'CLI validate: a project skill resolved outside the worktree fails' "$val_origin_out" 'FAIL PROJECT_SKILL_PATH_UNDER_WORKTREE'
contains 'CLI validate: a shared skill resolved inside the worktree fails' "$val_origin_out" 'FAIL SHARED_SKILL_PATH_IS_GLOBAL'

no_expected_out=$(bash "$SELF" validate "$GOOD_REPORT" 2>&1)
contains 'CLI validate: an omitted expected-worktree is reported SKIP, never a false FAIL' "$no_expected_out" 'SKIP EXPECTED_WORKTREE'
contains 'CLI validate: an omitted expected-worktree also SKIPs the project-skill-origin check' "$no_expected_out" 'SKIP PROJECT_SKILL_PATH_UNDER_WORKTREE'

# Bounded internal delegation: a fully compliant read-only, same-task-scope
# helper is accepted; each individual scope/context violation is rejected
# on its own specific check, never merely a generic failure.
VALID_SUBAGENT_REPORT="$TMP_ROOT/cli-valid-subagent-report.txt"
ID_FIXTURE_DIR="$TMP_ROOT/internal-delegation-canary"
fixture_internal_delegation_prepare "$ID_FIXTURE_DIR"
cat "$GOOD_REPORT" > "$VALID_SUBAGENT_REPORT"
cat >> "$VALID_SUBAGENT_REPORT" <<EOF
INTERNAL_SUBAGENT_USED: yes
INTERNAL_SUBAGENT_ID: fixture-scout-1
INTERNAL_SUBAGENT_HARNESS: omp
INTERNAL_SUBAGENT_MODEL: anthropic/claude-sonnet-5
INTERNAL_SUBAGENT_EFFORT: medium
INTERNAL_SUBAGENT_PURPOSE: read-only review of one narrow file before finalizing
INTERNAL_SUBAGENT_MODE: read-only
INTERNAL_SUBAGENT_SAME_WORKTREE: true
INTERNAL_SUBAGENT_SAME_PROJECT: true
INTERNAL_SUBAGENT_FIRSTMATE_TASK_CREATED: none
INTERNAL_SUBAGENT_CONTEXT_INHERITED: same cwd as parent, no isolated workspace
Read $ID_FIXTURE_DIR/AGENTS.md: $C_ID_PROJECT_INSTRUCTION applies here.
Read $ID_FIXTURE_DIR/.agents/skills/$C_ID_SKILL_NAME/SKILL.md before the target file:
$C_ID_SKILL_BODY applied.
INTERNAL_SUBAGENT_RECURSION_TOOL_SEEN: yes
INTERNAL_SUBAGENT_RECURSION_TOOL_USED: no
INTERNAL_SUBAGENT_OFFICIAL_INTERNAL_SKILL_COUNT: 0
INTERNAL_SUBAGENT_SHARED_SKILL_EVIDENCE: ponytail: apply the smallest supported mechanism
EOF
val_subagent_out=$(bash "$SELF" validate "$VALID_SUBAGENT_REPORT" "$CLI_DIR/repo" 2>&1); val_subagent_rc=$?
check 'CLI validate: a compliant bounded internal subagent report exits 0' 0 "$val_subagent_rc"
not_contains 'CLI validate: a compliant bounded internal subagent report has no FAIL line' "$val_subagent_out" 'FAIL'

MUTATING_SUBAGENT_REPORT="$TMP_ROOT/cli-mutating-subagent-report.txt"
sed 's/INTERNAL_SUBAGENT_MODE: read-only/INTERNAL_SUBAGENT_MODE: mutating/' "$VALID_SUBAGENT_REPORT" > "$MUTATING_SUBAGENT_REPORT"
val_mut_out=$(bash "$SELF" validate "$MUTATING_SUBAGENT_REPORT" "$CLI_DIR/repo" 2>&1); val_mut_rc=$?
if [ "$val_mut_rc" -eq 0 ]; then fail 'CLI validate: a mutating internal subagent unexpectedly exits 0'; else pass 'CLI validate: a mutating internal subagent exits nonzero'; fi
contains 'CLI validate: a mutating internal subagent fails the read-only check' "$val_mut_out" 'FAIL INTERNAL_SUBAGENT_READ_ONLY'

CROSS_WORKTREE_SUBAGENT_REPORT="$TMP_ROOT/cli-cross-worktree-subagent-report.txt"
sed 's/INTERNAL_SUBAGENT_SAME_WORKTREE: true/INTERNAL_SUBAGENT_SAME_WORKTREE: false/' "$VALID_SUBAGENT_REPORT" > "$CROSS_WORKTREE_SUBAGENT_REPORT"
val_cross_out=$(bash "$SELF" validate "$CROSS_WORKTREE_SUBAGENT_REPORT" "$CLI_DIR/repo" 2>&1); val_cross_rc=$?
if [ "$val_cross_rc" -eq 0 ]; then fail 'CLI validate: a cross-worktree internal subagent unexpectedly exits 0'; else pass 'CLI validate: a cross-worktree internal subagent exits nonzero'; fi
contains 'CLI validate: a cross-worktree internal subagent fails the same-worktree check' "$val_cross_out" 'FAIL INTERNAL_SUBAGENT_SAME_WORKTREE'

SEPARATE_TASK_SUBAGENT_REPORT="$TMP_ROOT/cli-separate-task-subagent-report.txt"
sed 's/INTERNAL_SUBAGENT_FIRSTMATE_TASK_CREATED: none/INTERNAL_SUBAGENT_FIRSTMATE_TASK_CREATED: task-9999/' "$VALID_SUBAGENT_REPORT" > "$SEPARATE_TASK_SUBAGENT_REPORT"
val_sep_out=$(bash "$SELF" validate "$SEPARATE_TASK_SUBAGENT_REPORT" "$CLI_DIR/repo" 2>&1); val_sep_rc=$?
if [ "$val_sep_rc" -eq 0 ]; then fail 'CLI validate: an internal subagent that created a separate Firstmate task unexpectedly exits 0'; else pass 'CLI validate: an internal subagent that created a separate Firstmate task exits nonzero'; fi
contains 'CLI validate: creating a separate Firstmate task fails the no-task check' "$val_sep_out" 'FAIL INTERNAL_SUBAGENT_NO_FIRSTMATE_TASK'

# The strengthened, real-canary-backed proofs: a "yes" self-report with no
# actual canary evidence, a recursion tool that was used rather than only
# seen, and a nonzero official-internal-skill count each fail on their own
# specific check - self-reported prose is never enough by itself.
NO_CANARY_SUBAGENT_REPORT="$TMP_ROOT/cli-no-canary-subagent-report.txt"
grep -v -F "$C_ID_PROJECT_INSTRUCTION" "$VALID_SUBAGENT_REPORT" > "$NO_CANARY_SUBAGENT_REPORT"
val_nocanary_out=$(bash "$SELF" validate "$NO_CANARY_SUBAGENT_REPORT" "$CLI_DIR/repo" 2>&1); val_nocanary_rc=$?
if [ "$val_nocanary_rc" -eq 0 ]; then fail 'CLI validate: a subagent report with no real canary evidence unexpectedly exits 0'; else pass 'CLI validate: a subagent report with no real canary evidence exits nonzero'; fi
contains 'CLI validate: missing real canary evidence fails the canary-applied check' "$val_nocanary_out" 'FAIL INTERNAL_SUBAGENT_CANARY_APPLIED'

RECURSED_SUBAGENT_REPORT="$TMP_ROOT/cli-recursed-subagent-report.txt"
sed 's/INTERNAL_SUBAGENT_RECURSION_TOOL_USED: no/INTERNAL_SUBAGENT_RECURSION_TOOL_USED: yes/' "$VALID_SUBAGENT_REPORT" > "$RECURSED_SUBAGENT_REPORT"
val_recursed_out=$(bash "$SELF" validate "$RECURSED_SUBAGENT_REPORT" "$CLI_DIR/repo" 2>&1); val_recursed_rc=$?
if [ "$val_recursed_rc" -eq 0 ]; then fail 'CLI validate: a subagent that used its recursion tool unexpectedly exits 0'; else pass 'CLI validate: a subagent that used its recursion tool exits nonzero'; fi
contains 'CLI validate: using the recursion tool fails the bounded-recursion check' "$val_recursed_out" 'FAIL INTERNAL_SUBAGENT_RECURSION_BOUNDED'

LEAKY_SUBAGENT_REPORT="$TMP_ROOT/cli-leaky-subagent-report.txt"
sed 's/INTERNAL_SUBAGENT_OFFICIAL_INTERNAL_SKILL_COUNT: 0/INTERNAL_SUBAGENT_OFFICIAL_INTERNAL_SKILL_COUNT: 1/' "$VALID_SUBAGENT_REPORT" > "$LEAKY_SUBAGENT_REPORT"
val_leaky_out=$(bash "$SELF" validate "$LEAKY_SUBAGENT_REPORT" "$CLI_DIR/repo" 2>&1); val_leaky_rc=$?
if [ "$val_leaky_rc" -eq 0 ]; then fail 'CLI validate: a nonzero official-internal-skill count for the subagent unexpectedly exits 0'; else pass 'CLI validate: a nonzero official-internal-skill count for the subagent exits nonzero'; fi
contains 'CLI validate: a nonzero official-internal-skill count fails the zero-leak check' "$val_leaky_out" 'FAIL INTERNAL_SUBAGENT_ZERO_OFFICIAL_LEAK'

# GOOD_REPORT itself already reports INTERNAL_SUBAGENT_USED: not-applicable
# (Pi's case) and still exits 0 with the detail checks skipped, not failed.
contains 'CLI validate: not-applicable skips the detail checks rather than failing them' "$val_out" 'SKIP INTERNAL_SUBAGENT_READ_ONLY'

usage_out=$(bash "$SELF" bogus-subcommand 2>&1); usage_rc=$?
if [ "$usage_rc" -eq 0 ]; then fail 'CLI: an unknown subcommand unexpectedly exits 0'; else pass 'CLI: an unknown subcommand exits nonzero'; fi

printf '\nWORKER CONTEXT TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
