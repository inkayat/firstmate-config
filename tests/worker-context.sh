#!/usr/bin/env bash
# worker-context.sh - offline acceptance for the delegated-worker context/
# skill-class handoff contract (firstmate/primary-policy.md section 2,
# README.md "Worker context and skill classes").
#
# Every check here is offline and zero-inference: no AgentSession, no model
# call, no paid quota, no other agent spawned, no Portail. Pi's real,
# installed native resource loader is invoked directly (the same technique
# as its own test/dev harness), never a fake stand-in pretending to be Pi's
# discovery. OMP has no equivalent embeddable loader library, so its half is
# a real, zero-inference read of its own installed documentation
# (`omp read omp://...:raw`, which never starts a session or a model turn),
# grounding the documented discovery difference this contract exists to
# cover. This is pre-implementation native-loader evidence, not a
# substitute for a live delegated Pi/OMP fixture run.
#
# fixture_prepare/fixture_validate below are the deterministic prepare/
# validate interface this task's steering asked for: fixture_prepare builds
# one canary fixture repository (identical every run); fixture_validate
# takes any transcript/output text - from this offline probe or later from
# a real Herdr -> Pi worker and a real Herdr -> OMP worker - and classifies
# each named canary as "absent", "present" (only its catalog name/path
# surfaced), or "applied" (its body-only marker text surfaced, meaning it
# was actually read and used). Running fixture_validate against synthetic
# transcripts here proves the matcher's own logic; it is not a live
# delegated-worker acceptance run by itself.
#
# Canary names match this task's steering example:
#   PROJECT_SKILL_CANARY   the fixture's mandatory project-local skill
#   SHARED_SKILL_CANARY    the real shared worker skill verification-before-completion
#   CAPTAIN_ONLY_CANARY    the real official-internal skill captain-hold-lifecycle,
#                          which must never surface as a worker skill
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

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-worker-context.XXXXXX") || exit 1
TMP_ROOT=$(cd "$TMP_ROOT" && pwd)
trap 'rm -rf "$TMP_ROOT"' EXIT

# =============================================================================
# fixture_prepare / fixture_validate
# =============================================================================

# fixture_prepare <dir> - builds <dir>/repo: a disposable Git project with
# deliberately conflicting root/nested instructions, a project-local
# mandatory skill (PROJECT_SKILL_CANARY, body-only marker), and a
# project-local skill that collides by name with the real global shared
# skill "architecture-review" this repository installs (PROJECT_WINS_OVER_SHARED
# marker), proving project-local-over-global precedence
# (firstmate/primary-policy.md section 1).
fixture_prepare() {
  local dir=$1 repo="$1/repo"
  mkdir -p "$repo/sub" "$repo/migrations" \
    "$repo/.agents/skills/migration-canary" \
    "$repo/.agents/skills/architecture-review"

  cat > "$repo/AGENTS.override.md" <<'EOF'
Rule: ROOT_OVERRIDE_CANARY applies at the repository root.

Required project skill:
  .agents/skills/migration-canary/SKILL.md
Requirement:
  Read and apply this skill before reading, writing, reviewing, or editing
  anything under migrations/.
EOF

  # Shadowed by AGENTS.override.md at the same scope - must never be treated
  # as authoritative while the override is present.
  cat > "$repo/AGENTS.md" <<'EOF'
Rule: ROOT_AGENTS_SHADOWED_CANARY - if this rule name surfaces, the override
was not honored.
EOF

  # Never wins when AGENTS.md exists in the same scope, for either harness.
  cat > "$repo/CLAUDE.md" <<'EOF'
Rule: ROOT_CLAUDE_SHOULD_NEVER_WIN_CANARY
EOF

  # Applies only inside sub/ - proves nested-scope precedence.
  cat > "$repo/sub/AGENTS.md" <<'EOF'
Rule: NESTED_SCOPE_CANARY applies only to files under sub/.
EOF

  printf -- '-- fixture migration\n' > "$repo/migrations/0001_init.sql"

  # Frontmatter description deliberately omits the body-only marker, so
  # catalog visibility (name + description) can never leak it.
  cat > "$repo/.agents/skills/migration-canary/SKILL.md" <<'EOF'
---
name: migration-canary
description: Fixture project-local skill required before touching migrations.
---
# Migration canary

PROJECT_SKILL_CANARY_BODY: read and apply this skill before reading,
writing, reviewing, or editing anything under migrations/.
EOF

  # Project-local skill with the same name as the real global shared skill
  # "architecture-review" this repository installs into ~/.agents/skills.
  cat > "$repo/.agents/skills/architecture-review/SKILL.md" <<'EOF'
---
name: architecture-review
description: Fixture project-local architecture-review, must win over global.
---
# Project-local architecture-review

PROJECT_WINS_OVER_SHARED_CANARY: this project-local skill must win over the
global shared skill of the same name.
EOF

  git -C "$repo" init -q
  git -C "$repo" add -A
  git -C "$repo" -c user.email=wc@example.invalid -c user.name=wc commit -q -m fixture
}

# fixture_validate <transcript-file> - classifies each headline canary from
# raw transcript/output text as absent, present (catalog only), or applied
# (body-only marker present, i.e. actually read and used).
fixture_validate() {
  local f=$1 t catalog body
  t=$(cat "$f" 2>/dev/null || printf '')
  _wc_classify() { # <catalog-substring> <body-substring>
    case $t in
      *"$2"*) printf applied ;;
      *"$1"*) printf present ;;
      *) printf absent ;;
    esac
  }
  catalog=migration-canary; body=PROJECT_SKILL_CANARY_BODY
  printf 'PROJECT_SKILL_CANARY    %s\n' "$(_wc_classify "$catalog" "$body")"
  catalog=verification-before-completion
  body='NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE'
  printf 'SHARED_SKILL_CANARY     %s\n' "$(_wc_classify "$catalog" "$body")"
  catalog=captain-hold-lifecycle; body=captain-hold-lifecycle
  printf 'CAPTAIN_ONLY_CANARY     %s\n' "$(_wc_classify "$catalog" "$body")"
}

# =============================================================================
# 1. fixture_validate's own matcher logic, proven against synthetic
#    transcripts (offline unit test of the validator; not itself a live
#    delegated-worker run).
# =============================================================================
GOOD_TRANSCRIPT="$TMP_ROOT/good-transcript.txt"
cat > "$GOOD_TRANSCRIPT" <<'EOF'
Reading .agents/skills/migration-canary/SKILL.md before touching migrations/.
PROJECT_SKILL_CANARY_BODY: read and apply this skill before reading, writing,
reviewing, or editing anything under migrations/. Applying it now.
Applying verification-before-completion before declaring done: the rule is
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE, so I ran the tests
and read their output before this claim.
EOF
out=$(fixture_validate "$GOOD_TRANSCRIPT")
contains 'compliant transcript: project skill canary applied' "$out" 'PROJECT_SKILL_CANARY    applied'
contains 'compliant transcript: shared skill canary applied' "$out" 'SHARED_SKILL_CANARY     applied'
contains 'compliant transcript: captain-only canary stays absent' "$out" 'CAPTAIN_ONLY_CANARY     absent'

LEAKY_TRANSCRIPT="$TMP_ROOT/leaky-transcript.txt"
cat > "$LEAKY_TRANSCRIPT" <<'EOF'
Noticed a migration-canary skill exists but did not read its body.
Skipped verification entirely.
For process, also consulted captain-hold-lifecycle.
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
    *captain-hold-lifecycle*) pass 'official-internal-skill negative check: captain-hold-lifecycle confirmed official-internal' ;;
    *) fail 'official-internal-skill negative check: captain-hold-lifecycle not found under official FirstMate - update the fixture canary' ;;
  esac
  not_contains 'official-internal-skill negative check: captain-hold-lifecycle is never a firstmate-config shared skill name' "$(config_shared_names)" captain-hold-lifecycle
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
  cat > "$PI_HOME/.agents/skills/architecture-review/SKILL.md" <<'EOF'
---
name: architecture-review
description: Real global shared architecture-review stand-in.
---
GLOBAL_ARCHITECTURE_REVIEW_CANARY
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
    not_contains 'Pi native-loader probe: the official-internal captain-hold-lifecycle name never surfaces as a skill' "$probe_out" 'captain-hold-lifecycle'
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

printf '\nWORKER CONTEXT TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
