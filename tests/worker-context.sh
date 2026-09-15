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
# Canary names match this task's steering example:
#   PROJECT_SKILL_CANARY   the fixture's mandatory project-local skill
#   SHARED_SKILL_CANARY    the real shared worker skill verification-before-completion
#   CAPTAIN_ONLY_CANARY    the real official-internal skill captain-hold-lifecycle,
#                          which must never surface as a worker skill
# `validate` also proves: the expected isolated worktree, root override
# authority, absence of the two markers it must shadow, nested-scope
# instruction application, the project-skill body-only marker applied before
# migrations are touched, the shared-skill body-only marker applied, and
# project-local-over-conflicting-shared-skill authority. `handoff` never
# prints a body-only marker, so a worker that only echoes the handoff can
# never pass `validate` - only an actual read of the named files can.
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
# paths each paired with a read-and-apply requirement, and the governed
# task. <repo-dir> is used only to validate the fixture exists; its
# absolute path is NEVER printed. The worker's actual isolated task
# worktree does not exist yet when this handoff is generated (fm-spawn
# creates it later, at a different path than any source/primary checkout),
# so every path below is bare and worktree-relative, with an explicit
# instruction to verify `pwd -P` against `git rev-parse --show-toplevel`
# before resolving them - never read the source/primary checkout instead
# of the worker's own worktree. Also never prints a body-only marker
# (C_PROJECT_SKILL_BODY, C_SHARED_SKILL_BODY) or any other canary constant:
# a worker that only echoes this text back can never pass
# fixture_validate_live, since only an actual read of the named files
# surfaces those markers.
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

Pre-work requirement:
  Read every path named above, resolved from your current worktree root,
  before substantive work. Report any missing, unreadable, or conflicting
  path instead of silently falling back to a different scope or a global
  default. Re-check applicable instructions before editing outside this
  subtree if scope expands.

Task:
  1. Add a NOT NULL constraint to migrations/0001_init.sql.
  2. Add a short note to sub/notes.md explaining the change.
  3. Report what you read and applied, then declare the task complete.
EOF
}

# fixture_validate <transcript-file> - classifies each headline canary from
# raw transcript/output text as absent, present (catalog only), or applied
# (body-only marker present, i.e. actually read and used). Offline
# illustrative classifier for the three headline canaries; see
# fixture_validate_live for the full required-proof gate.
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

# _wc_str_index <haystack> <needle> -> byte offset of the first match, or
# -1. Used to prove ordering (a marker occurring before another) from a
# linear transcript, without a real dependency-free JSON/log parser.
_wc_str_index() {
  local h=$1 n=$2 pre
  case $h in
    *"$n"*) pre=${h%%"$n"*}; printf '%s' "${#pre}" ;;
    *) printf -- '-1' ;;
  esac
}

# fixture_validate_live <worker-report-file> [expected-worktree] - the
# strict, full required-proof gate for a real delegated-worker transcript
# or report. Prints one "PASS <LABEL>", "FAIL <LABEL>", or
# "SKIP <LABEL> (reason)" line per required proof; returns 0 only when
# every required proof passes.
fixture_validate_live() {
  local report=$1 expected=${2:-} t all_ok=0 mig_idx body_idx
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

  # PROJECT_SKILL_APPLIED requires the body marker, and - when the migration
  # file is mentioned at all - requires it to occur no later than that
  # mention, proving the skill was read before migrations were touched.
  body_idx=$(_wc_str_index "$t" "$C_PROJECT_SKILL_BODY")
  mig_idx=$(_wc_str_index "$t" "$C_MIGRATION_FILE")
  if [ "$body_idx" -ge 0 ] && { [ "$mig_idx" -lt 0 ] || [ "$body_idx" -le "$mig_idx" ]; }; then
    _req PROJECT_SKILL_APPLIED 0
  else
    _req PROJECT_SKILL_APPLIED 1
  fi

  case $t in *"$C_SHARED_SKILL_BODY"*) _req SHARED_SKILL_APPLIED 0 ;; *) _req SHARED_SKILL_APPLIED 1 ;; esac

  case $t in
    *"$C_PROJECT_WINS"*)
      case $t in *"$C_GLOBAL_LEAK"*) _req PROJECT_OVER_SHARED_AUTHORITY 1 ;; *) _req PROJECT_OVER_SHARED_AUTHORITY 0 ;; esac
      ;;
    *) _req PROJECT_OVER_SHARED_AUTHORITY 1 ;;
  esac

  case $t in *"$C_CAPTAIN_ONLY"*) _req CAPTAIN_ONLY_ABSENT 1 ;; *) _req CAPTAIN_ONLY_ABSENT 0 ;; esac

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
  validate)
    report=${2:?"usage: $0 validate <worker-report> [expected-worktree]"}
    fixture_validate_live "$report" "${3:-}"
    exit $?
    ;;
  '') ;; # fall through to the offline suite below
  *)
    printf 'usage: %s [prepare <directory>|handoff <repo-dir>|validate <worker-report> [expected-worktree]]\n' "$0" >&2
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
EOF
val_out=$(bash "$SELF" validate "$GOOD_REPORT" "$CLI_DIR/repo" 2>&1); val_rc=$?
check 'CLI validate: a fully compliant report exits 0' 0 "$val_rc"
not_contains 'CLI validate: a fully compliant report has no FAIL line' "$val_out" 'FAIL'

ORDER_BAD_REPORT="$TMP_ROOT/cli-order-bad-report.txt"
cat > "$ORDER_BAD_REPORT" <<EOF
Ran in $CLI_DIR/repo.
$C_ROOT_OVERRIDE observed and followed.
$C_NESTED_SCOPE observed under sub/.
Touched $C_MIGRATION_FILE first, only reading the skill afterward:
$C_PROJECT_SKILL_BODY.
$C_SHARED_SKILL_BODY confirmed before declaring completion.
$C_PROJECT_WINS applied for architecture-review.
EOF
val_order_out=$(bash "$SELF" validate "$ORDER_BAD_REPORT" "$CLI_DIR/repo" 2>&1); val_order_rc=$?
if [ "$val_order_rc" -eq 0 ]; then fail 'CLI validate: touching migrations before reading the skill unexpectedly exits 0'; else pass 'CLI validate: touching migrations before reading the skill exits nonzero'; fi
contains 'CLI validate: out-of-order migration access reports the ordering failure' "$val_order_out" 'FAIL PROJECT_SKILL_APPLIED'

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

no_expected_out=$(bash "$SELF" validate "$GOOD_REPORT" 2>&1)
contains 'CLI validate: an omitted expected-worktree is reported SKIP, never a false FAIL' "$no_expected_out" 'SKIP EXPECTED_WORKTREE'

usage_out=$(bash "$SELF" bogus-subcommand 2>&1); usage_rc=$?
if [ "$usage_rc" -eq 0 ]; then fail 'CLI: an unknown subcommand unexpectedly exits 0'; else pass 'CLI: an unknown subcommand exits nonzero'; fi

printf '\nWORKER CONTEXT TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
