#!/usr/bin/env bash
# team-policy.sh - extensions/fm-team-policy.ts against synthetic OMP hook
# events: tool_call, before_subagent_spawn and session_start handlers called
# directly with hand-written `event` and `ctx` objects.
#
# Bindings are written by the real bin/fm-team (a disposable copy of this
# checkout's bin/, roles/, skills/ with fixture profiles) into a fixture
# FM_HOME; the worktree is a plain fixture directory with symlinks. No OMP
# process, model, network, or live root is involved, so this proves the
# extension's decisions for the event and ctx shapes OMP documents, not that a
# real OMP session delivers exactly those shapes (see the report's native
# evidence section). Requires bun; SKIPs without it.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v bun >/dev/null 2>&1; then
  printf 'SKIP - bun is not on PATH; the extension fixtures need a TypeScript runtime\n'
  exit 0
fi

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$3', got '$2')"; fi; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-team-policy.XXXXXX") || exit 1
TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)
trap 'rm -rf "$TMP_ROOT"' EXIT

CFG="$TMP_ROOT/cfg"
mkdir -p "$CFG/bin" "$CFG/teams"
cp "$CONFIG_ROOT/bin/fm-team" "$CFG/bin/fm-team"
cp -R "$CONFIG_ROOT/roles" "$CONFIG_ROOT/skills" "$CFG/"
# Test-only role fixtures (this disposable copy only, never installed): no
# shipped member role declares spawns, so a helper right needs a member whose
# role does - here fm-fixture-host, spawnable by the test-only fm-fixture-lead.
mkdir -p "$CFG/roles/fixture-lead" "$CFG/roles/fixture-host"
printf -- '---\nname: fm-fixture-lead\ndescription: "Test-only fixture lead; never installed."\nspawns:\n  - fm-fixture-host\n  - fm-frontend-master\n---\nTest-only fixture.\n' > "$CFG/roles/fixture-lead/ROLE.md"
printf -- '---\nname: fm-fixture-host\ndescription: "Test-only fixture member that declares a helper; never installed."\nspawns:\n  - scout\n---\nTest-only fixture.\n' > "$CFG/roles/fixture-host/ROLE.md"
export FM_HOME="$TMP_ROOT/fm-home"
# bind reports whether the extension is linked; point it at an empty fixture
# root so the operator's default ~/.omp/agent/extensions is never consulted.
export FM_OMP_EXTENSIONS_ROOT="$TMP_ROOT/omp-extensions"
mkdir -p "$FM_HOME/data" "$FM_HOME/state" "$FM_OMP_EXTENSIONS_ROOT"

cat > "$CFG/teams/web-feature.json" <<'JSON'
{
  "schema": "fm-team-profile.v1",
  "name": "web-feature",
  "lead": "fm-team-lead",
  "members": [
    {"agent": "fm-product-owner", "mode": "read-only"},
    {"agent": "fm-django-pro", "mode": "mutating", "paths": {"write": ["apps/api/**"]}, "talk_to": ["fm-frontend-master"]},
    {"agent": "fm-frontend-master", "mode": "mutating", "paths": {"write": ["apps/web/**"]}, "talk_to": ["fm-django-pro"]},
    {"agent": "fm-qa", "mode": "read-only"}
  ],
  "workflow": {
    "phases": [
      {"name": "planning", "members": ["fm-product-owner"]},
      {"name": "implement", "members": ["fm-django-pro", "fm-frontend-master"]},
      {"name": "verify", "members": ["fm-qa"]}
    ],
    "max_rework_rounds": 2
  },
  "ops": {"commit": "request", "push": "none", "merge": "none"}
}
JSON
cat > "$CFG/teams/docs-only.json" <<'JSON'
{
  "schema": "fm-team-profile.v1",
  "name": "docs-only",
  "lead": "fm-team-lead",
  "members": [
    {"agent": "fm-frontend-master", "mode": "mutating", "paths": {"write": ["docs/**"]}},
    {"agent": "fm-code-reviewer", "mode": "read-only"}
  ],
  "workflow": {"phases": [{"name": "write", "members": ["fm-frontend-master"]}, {"name": "review", "members": ["fm-code-reviewer"]}], "max_rework_rounds": 1},
  "ops": {"commit": "none", "push": "none", "merge": "none"}
}
JSON
cat > "$CFG/teams/wide-open.json" <<'JSON'
{
  "schema": "fm-team-profile.v1",
  "name": "wide-open",
  "lead": "fm-team-lead",
  "members": [{"agent": "fm-django-pro", "mode": "mutating", "paths": {"write": ["**"]}}],
  "workflow": {"phases": [{"name": "all", "members": ["fm-django-pro"]}], "max_rework_rounds": 0},
  "ops": {"commit": "none", "push": "none", "merge": "none"}
}
JSON
cat > "$CFG/teams/helper-host.json" <<'JSON'
{
  "schema": "fm-team-profile.v1",
  "name": "helper-host",
  "lead": "fm-fixture-lead",
  "members": [
    {"agent": "fm-fixture-host", "mode": "mutating", "paths": {"write": ["apps/api/**"]}, "spawn": ["scout"]},
    {"agent": "fm-frontend-master", "mode": "mutating", "paths": {"write": ["apps/web/**"]}}
  ],
  "workflow": {"phases": [{"name": "implement", "members": ["fm-fixture-host", "fm-frontend-master"]}], "max_rework_rounds": 0},
  "ops": {"commit": "none", "push": "none", "merge": "none"}
}
JSON
# https_read fixtures: one member per grant state (true, false, absent), and the
# helper host again with its grant set, so a helper's right is judged against
# its own parent member's.
cat > "$CFG/teams/https-mix.json" <<'JSON'
{
  "schema": "fm-team-profile.v1",
  "name": "https-mix",
  "lead": "fm-team-lead",
  "members": [
    {"agent": "fm-product-owner", "mode": "read-only", "https_read": true},
    {"agent": "fm-qa", "mode": "read-only", "https_read": false},
    {"agent": "fm-django-pro", "mode": "mutating", "paths": {"write": ["apps/api/**"]}}
  ],
  "workflow": {"phases": [{"name": "all", "members": ["fm-product-owner", "fm-qa", "fm-django-pro"]}], "max_rework_rounds": 0},
  "ops": {"commit": "none", "push": "none", "merge": "none"}
}
JSON
python3 - "$CFG/teams/helper-host.json" "$CFG/teams/helper-open.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
p["name"] = "helper-open"
p["members"][0]["https_read"] = True
json.dump(p, open(sys.argv[2], "w"))
PY

BASE_SHA=0123456789abcdef0123456789abcdef01234567
BIND_LOG="$TMP_ROOT/bind.log"
for t in t-team t-freeze t-tampered t-missing t-badbind t-unknown; do
  "$CFG/bin/fm-team" bind "$t" --profile web-feature --base "$BASE_SHA" >/dev/null 2>>"$BIND_LOG" || fail "fixture bind $t"
done
"$CFG/bin/fm-team" bind t-docs --profile docs-only --base "$BASE_SHA" >/dev/null 2>>"$BIND_LOG" || fail 'fixture bind t-docs'
"$CFG/bin/fm-team" bind t-helper --profile helper-host --base "$BASE_SHA" >/dev/null 2>>"$BIND_LOG" || fail 'fixture bind t-helper'
"$CFG/bin/fm-team" bind t-https --profile https-mix --base "$BASE_SHA" >/dev/null 2>>"$BIND_LOG" || fail 'fixture bind t-https'
"$CFG/bin/fm-team" bind t-helper-open --profile helper-open --base "$BASE_SHA" >/dev/null 2>>"$BIND_LOG" || fail 'fixture bind t-helper-open'
# Every bind reports the extension root it consulted when the extension is not
# linked there; the fixture root is empty, so each bind names its root.
case $(cat "$BIND_LOG") in
  *"/.omp/agent/extensions/"*) fail "fixture binds consulted the default OMP extension root: $(head -1 "$BIND_LOG")" ;;
  *"$FM_OMP_EXTENSIONS_ROOT/fm-team-policy.ts"*) pass 'fixture binds consult only the fixture extension root' ;;
  *) fail "fixture binds named no extension root: $(head -1 "$BIND_LOG")" ;;
esac
BIND="$FM_HOME/data/team-bindings"
printf ' ' >> "$BIND/t-tampered.profile.json"
rm "$BIND/t-missing.profile.json"
printf 'not json' > "$BIND/t-badbind.json"
mkdir -p "$FM_HOME/data/t-marker"
printf '# brief\nTeam profile: web-feature\n' > "$FM_HOME/data/t-marker/brief.md"
cp "$CFG/teams/wide-open.json" "$TMP_ROOT/wide-open.json"
WIDE_SHA=$(shasum -a 256 < "$TMP_ROOT/wide-open.json" | cut -d' ' -f1)
# A snapshot whose grant is not a boolean, consistent with its binding (bind
# itself would refuse it), so only the extension's own parse can catch it.
python3 - "$CFG/teams/helper-host.json" "$BIND/t-badhttps.profile.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
p["members"][0]["https_read"] = "yes"
open(sys.argv[2], "w").write(json.dumps(p))
PY
printf '{"schema": "fm-team-binding.v1", "task": "t-badhttps", "profile": "helper-host", "profile_sha256": "%s", "base": "%s"}\n' \
  "$(shasum -a 256 < "$BIND/t-badhttps.profile.json" | cut -d' ' -f1)" "$BASE_SHA" > "$BIND/t-badhttps.json"

# Worktree fixture: two owned trees, an unowned one, and three kinds of link.
W="$TMP_ROOT/worktree"
OUTSIDE="$TMP_ROOT/outside"
mkdir -p "$W/apps/api" "$W/apps/web" "$W/other" "$OUTSIDE"
printf 'a\n' > "$W/apps/api/a.py"; printf 'b\n' > "$W/apps/web/b.js"
ln -s "$OUTSIDE" "$W/apps/api/link-out"
ln -s ../web "$W/apps/api/link-web"
ln -s "$OUTSIDE/nowhere.txt" "$W/apps/api/dangle"
# Shared skill and reference roots under a fixture HOME, linked the way
# install.sh links them: entry links into a skill tree (one entry holding links
# that leave it), a sibling entry, the references link, and a host secret.
FHOME="$TMP_ROOT/home"
SKILLS_SRC="$TMP_ROOT/skills-src"
mkdir -p "$FHOME/.agents/skills" "$FHOME/.ssh" "$SKILLS_SRC/e" "$SKILLS_SRC/other" "$SKILLS_SRC/refs" "$W/.agents/skills/p"
printf 'skill\n' > "$SKILLS_SRC/e/SKILL.md"; printf 'other\n' > "$SKILLS_SRC/other/x.md"; printf 'ref\n' > "$SKILLS_SRC/refs/x.md"
printf 'secret\n' > "$OUTSIDE/cred.txt"; printf 'key\n' > "$FHOME/.ssh/x"
ln -s "$OUTSIDE/cred.txt" "$SKILLS_SRC/e/leak"
ln -s ../other/x.md "$SKILLS_SRC/e/sib"
ln -s "$OUTSIDE/nowhere.txt" "$SKILLS_SRC/e/dangle"
ln -s "$SKILLS_SRC/e" "$FHOME/.agents/skills/e"
ln -s "$SKILLS_SRC/other" "$FHOME/.agents/skills/other"
ln -s "$SKILLS_SRC/refs" "$FHOME/.agents/references"
ln -s "$OUTSIDE/cred.txt" "$W/.agents/skills/p/leak"   # a repository-shipped link

cat > "$TMP_ROOT/driver.ts" <<'TS'
import policy, { globMatch } from "@EXT@";

const W = process.env.FIXTURE_WORKTREE!;
const BIND = process.env.FIXTURE_BINDINGS!;
let failed = 0;

type Agent = { kind: string; id?: string; name?: string; parentId?: string };
function session(agent: Agent | undefined, cwd: string = W) {
  const handlers: Record<string, Array<(e: unknown, c: unknown) => unknown>> = {};
  policy({ on: (ev: string, h: (e: unknown, c: unknown) => unknown) => { (handlers[ev] ??= []).push(h); } });
  const ctx = { cwd, agent };
  const fire = async (ev: string, e: unknown): Promise<unknown> => {
    let r: unknown;
    for (const h of handlers[ev] ?? []) { r = await h(e, ctx); if (verdict(r) !== "allow") return r; }
    return r;
  };
  return {
    start: () => fire("session_start", { type: "session_start" }),
    tool: (toolName: string, input: unknown) => fire("tool_call", { type: "tool_call", toolCallId: "call-1", toolName, input }),
    spawn: (agentName: string | undefined) => fire("before_subagent_spawn", { agent: agentName, invocationKind: "task", patterns: [] }),
  };
}
function verdict(r: unknown): string {
  if (r === null || typeof r !== "object" || !("block" in r) || r.block !== true) return "allow";
  const reason = "reason" in r ? String(r.reason) : "";
  const m = /refused \(([a-z0-9-]+)\)/.exec(reason);
  return m ? m[1] : `block-without-code: ${reason}`;
}
async function expect(label: string, p: Promise<unknown>, want: string) {
  const got = verdict(await p);
  if (got === want) console.log(`ok   - ${label}`);
  else { console.log(`FAIL - ${label} (expected ${want}, got ${got})`); failed = 1; }
}
function task(id: string | undefined) {
  if (id === undefined) delete process.env.FM_TASK_ID; else process.env.FM_TASK_ID = id;
}

// --- glob semantics: the same literal table team.sh runs through bin/fm-team
for (const [glob, path, want] of JSON.parse(process.env.GLOB_TABLE!) as [string, string, boolean][]) {
  const got = globMatch(glob, path);
  if (got === want) console.log(`ok   - glob ${glob} ~ ${path} = ${want}`);
  else { console.log(`FAIL - glob ${glob} ~ ${path} (expected ${want}, got ${got})`); failed = 1; }
}

// --- A. non-team sessions are a no-op ---------------------------------------------------
task(undefined);
const captain = session({ kind: "main", id: "Main", name: "main" });
await expect("A no FM_TASK_ID: a write outside any scope is allowed", captain.tool("write", { path: "/etc/elsewhere", content: "x" }), "allow");
await expect("A no FM_TASK_ID: git push is allowed", captain.tool("bash", { command: "git push origin main" }), "allow");
await expect("A no FM_TASK_ID: any spawn is allowed", captain.spawn("fm-refactorist"), "allow");
task("t-plain");
const plain = session({ kind: "main", id: "Main", name: "main" });
await expect("A worker without binding or team brief: write anywhere allowed", plain.tool("write", { path: "other/z.txt", content: "x" }), "allow");
await expect("A worker without binding or team brief: eval allowed", plain.tool("eval", { code: "1" }), "allow");

// --- B. a sound team ---------------------------------------------------------------------
task("t-team");
const lead = session({ kind: "main", id: "Main", name: "main" });
await lead.start();
await expect("B lead writes in a member's scope", lead.tool("write", { path: "apps/api/x.py", content: "x" }), "allow");
await expect("B lead writes in the other member's scope", lead.tool("write", { path: `${W}/apps/web/y.js`, content: "x" }), "allow");
await expect("B lead writes the team plan in local://", lead.tool("write", { path: "local://team-plan.md", content: "x" }), "allow");
await expect("B lead outside the team scope", lead.tool("write", { path: "other/z.txt", content: "x" }), "path-outside-scope");
await expect("B lead traversal out of the worktree", lead.tool("write", { path: "../escape.txt", content: "x" }), "path-outside-worktree");
await expect("B lead absolute path outside", lead.tool("write", { path: "/etc/hosts", content: "x" }), "path-outside-worktree");
await expect("B lead home-relative path", lead.tool("write", { path: "~/notes.txt", content: "x" }), "path-outside-worktree");
await expect("B normalization: in-scope prefix escaping via ..", lead.tool("write", { path: "apps/api/../../other/z.txt", content: "x" }), "path-outside-scope");
await expect("B normalization: . and .. that stay in scope", lead.tool("write", { path: "apps/api/./sub/../ok.py", content: "x" }), "allow");
await expect("B lead spawns a profile member", lead.spawn("fm-django-pro"), "allow");
await expect("B lead spawns a role outside the profile", lead.spawn("fm-refactorist"), "spawn-not-allowed");
await expect("B lead spawns a lead-spawns role the profile omits", lead.spawn("fm-architecture"), "spawn-not-allowed");
await expect("B lead spawns a bundled agent", lead.spawn("scout"), "spawn-not-allowed");
await expect("B spawn event without an agent name", lead.spawn(undefined), "spawn-not-allowed");
await expect("B lead: eval is refused in a team", lead.tool("eval", { code: "open('x','w')" }), "eval-not-allowed");
await expect("B lead: an unlisted tool is refused", lead.tool("github", { op: "pr_merge" }), "tool-not-allowed");
await expect("B lead: read stays allowed", lead.tool("read", { path: "other/z.txt" }), "allow");
await expect("B lead: archive/sqlite colon targets are refused", lead.tool("write", { path: "apps/api/x.zip:inner", content: "x" }), "colon-target-not-allowed");
await expect("B lead: other schemes are refused", lead.tool("write", { path: "cfg://tools/approval", content: "x" }), "scheme-not-allowed");

const api = session({ kind: "sub", id: "Api", name: "fm-django-pro", parentId: "Main" });
await api.start();
const web = session({ kind: "sub", id: "Web", name: "fm-frontend-master", parentId: "Main" });
await web.start();
const qa = session({ kind: "sub", id: "Qa", name: "fm-qa", parentId: "Main" });
await qa.start();
await expect("B member writes its own scope", api.tool("write", { path: "apps/api/a.py", content: "x" }), "allow");
await expect("B member writes the other member's scope", api.tool("write", { path: "apps/web/b.js", content: "x" }), "path-outside-scope");
await expect("B member may not write local://", api.tool("write", { path: "local://team-plan.md", content: "x" }), "local-write-not-allowed");
await expect("B hashline edit into another scope", api.tool("edit", { input: "[apps/web/b.js#ABCD]\nPUT 1.=1:\n+x\n" }), "path-outside-scope");
await expect("B hashline edit in scope", api.tool("edit", { input: "[apps/api/a.py#ABCD]\nPUT 1.=1:\n+x\n" }), "allow");
await expect("B hashline MV destination outside scope", api.tool("edit", { input: "[apps/api/a.py#ABCD]\nMV apps/web/a.py\n" }), "path-outside-scope");
await expect("B edit with OMP's derived path field", api.tool("edit", { input: "...", path: "apps/web/b.js" }), "path-outside-scope");
await expect("B replace-mode edit in scope", api.tool("edit", { path: "apps/api/a.py", old_string: "a", new_string: "b" }), "allow");
await expect("B apply_patch into another scope", api.tool("apply_patch", { input: "*** Begin Patch\n*** Update File: apps/web/b.js\n@@\n-b\n+c\n*** End Patch" }), "path-outside-scope");
await expect("B edit with no recognizable target", api.tool("edit", { input: "PUT 1.=1:\n+x\n" }), "unparsed-edit-target");
await expect("B symlink out of the worktree", api.tool("write", { path: "apps/api/link-out/f.txt", content: "x" }), "path-outside-worktree");
await expect("B in-scope symlink into another member's tree", api.tool("write", { path: "apps/api/link-web/x.js", content: "x" }), "path-outside-scope");
await expect("B dangling symlink pointing outside", api.tool("write", { path: "apps/api/dangle", content: "x" }), "path-outside-worktree");
await expect("B ast_edit in scope", api.tool("ast_edit", { ops: [{ pat: "a", out: "b" }], paths: ["apps/api/a.py"] }), "allow");
await expect("B ast_edit glob reaching another scope", api.tool("ast_edit", { ops: [{ pat: "a", out: "b" }], paths: ["apps/**"] }), "path-outside-scope");
await expect("B ast_edit with brace syntax", api.tool("ast_edit", { ops: [{ pat: "a", out: "b" }], paths: ["apps/api/{../web}/x.js"] }), "unsafe-target");
await expect("B ast_edit through the xd device", api.tool("write", { path: "xd://ast_edit", content: JSON.stringify({ ops: [], paths: ["apps/web/b.js"] }) }), "path-outside-scope");
await expect("B lsp navigation through the xd device", api.tool("write", { path: "xd://lsp", content: JSON.stringify({ action: "definition", file: "apps/web/b.js" }) }), "allow");
await expect("B lsp rename through the xd device", api.tool("write", { path: "xd://lsp", content: JSON.stringify({ action: "rename", file: "apps/api/a.py", new_name: "z" }) }), "lsp-refactor-not-allowed");
await expect("B member messages its listed peer", api.tool("write", { path: "agent://Web", content: "contract changed" }), "allow");
await expect("B member messages an unlisted member", api.tool("write", { path: "agent://Qa", content: "hi" }), "recipient-not-allowed");
await expect("B member messages an unknown id", api.tool("write", { path: "agent://Ghost", content: "hi" }), "unknown-recipient");
await expect("B member broadcasts", api.tool("write", { path: "agent://all", content: "hi" }), "broadcast-not-allowed");
await expect("B member messages the lead", api.tool("write", { path: "agent://Main", content: "gap" }), "allow");
await expect("B lead messages a member", lead.tool("write", { path: "agent://Qa", content: "fix" }), "allow");
await expect("B lead broadcasts", lead.tool("write", { path: "agent://all", content: "hi" }), "broadcast-not-allowed");
await expect("B member with no profile helper right spawns", api.spawn("scout"), "spawn-not-allowed");
await expect("B member without helper rights spawns", qa.spawn("scout"), "spawn-not-allowed");
await expect("B read-only member writes", qa.tool("write", { path: "apps/api/a.py", content: "x" }), "read-only-member");
await expect("B read-only member runs tests", qa.tool("bash", { command: "python -m pytest -q" }), "allow");
await expect("B git status is allowed", qa.tool("bash", { command: "git status --short" }), "allow");
await expect("B git commit (commit: request)", qa.tool("bash", { command: "git add -A && git commit -m wip" }), "op-commit");
await expect("B git commit behind -C and -c options", lead.tool("bash", { command: "git -C . -c core.hooksPath=/dev/null commit -qm x" }), "op-commit");
await expect("B git push", lead.tool("bash", { command: "git push origin HEAD" }), "op-push");
await expect("B git merge", lead.tool("bash", { command: "git merge feature" }), "op-merge");
await expect("B gh pr merge", lead.tool("bash", { command: "gh pr merge 13 --squash" }), "op-merge");
await expect("B gh pr create", lead.tool("bash", { command: "gh pr create --fill" }), "op-push");
await expect("B gh api mutation", lead.tool("bash", { command: "gh api -X PUT repos/o/r/pulls/1/merge" }), "op-push");
await expect("B gh api read", lead.tool("bash", { command: "gh api repos/o/r/pulls/1" }), "allow");

// --- helpers inherit from the member that spawned them -----------------------------------
task("t-helper");
const hlead = session({ kind: "main", id: "Main", name: "main" });
await hlead.start();
const hapi = session({ kind: "sub", id: "Api", name: "fm-fixture-host", parentId: "Main" });
await hapi.start();
const hweb = session({ kind: "sub", id: "Web", name: "fm-frontend-master", parentId: "Main" });
await hweb.start();
const helper = session({ kind: "sub", id: "Api.Scout", name: "scout", parentId: "Api" });
await helper.start();
await expect("H member spawns its profile helper", hapi.spawn("scout"), "allow");
await expect("H member spawns a helper outside its profile", hapi.spawn("task"), "spawn-not-allowed");
await expect("H helper of a mutating member is read-only", helper.tool("write", { path: "apps/api/a.py", content: "x" }), "read-only-member");
await expect("H helper may message the member that spawned it", helper.tool("write", { path: "agent://Api", content: "found it" }), "allow");
await expect("H helper may not message its parent's peers", helper.tool("write", { path: "agent://Web", content: "hi" }), "recipient-not-allowed");
await expect("H helper may not spawn", helper.spawn("scout"), "spawn-not-allowed");
await expect("H helper may read", helper.tool("grep", { pattern: "x" }), "allow");
await expect("H helper still runs bash under the op checks", helper.tool("bash", { command: "git push" }), "op-push");
const orphan = session({ kind: "sub", id: "Stray", name: "scout", parentId: "Nope" });
await expect("H helper whose parent is unknown cannot write", orphan.tool("write", { path: "apps/api/a.py", content: "x" }), "team-identity-unresolved");
await expect("H helper whose parent is unknown cannot run bash", orphan.tool("bash", { command: "ls" }), "team-identity-unresolved");
await expect("H helper whose parent is unknown may read", orphan.tool("read", { path: "apps/api/a.py" }), "allow");
const noagent = session(undefined);
await expect("H a session without agent identity cannot write", noagent.tool("write", { path: "apps/api/a.py", content: "x" }), "team-identity-unresolved");

task("t-unknown");
const ulead = session({ kind: "main", id: "Main", name: "main" });
await ulead.start();
const stranger = session({ kind: "sub", id: "Ref", name: "fm-refactorist", parentId: "Main" });
await expect("H a non-member spawned past the policy cannot write", stranger.tool("write", { path: "apps/api/a.py", content: "x" }), "team-identity-unresolved");

// --- C. a known team task whose required profile cannot be used ---------------------------
for (const [id, code] of [["t-marker", "team-binding-missing"], ["t-tampered", "team-profile-tampered"],
                          ["t-missing", "team-profile-missing"], ["t-badbind", "team-binding-corrupt"]]) {
  task(id);
  const s = session({ kind: "main", id: "Main", name: "main" });
  await expect(`C ${code}: write refused`, s.tool("write", { path: "apps/api/a.py", content: "x" }), code);
  await expect(`C ${code}: bash refused`, s.tool("bash", { command: "ls" }), code);
  await expect(`C ${code}: message refused`, s.tool("write", { path: "agent://Api", content: "x" }), code);
  await expect(`C ${code}: spawn refused`, s.spawn("fm-django-pro"), code);
  await expect(`C ${code}: read allowed`, s.tool("read", { path: "apps/api/a.py" }), "allow");
  await expect(`C ${code}: an outside read is unchanged`, s.tool("read", { path: "/etc/hosts" }), "allow");
  await expect(`C ${code}: yield allowed`, s.tool("yield", { result: "blocked" }), "allow");
}

// --- D. a resolution is fixed for the life of the process (relaunch re-reads) -------------
task("t-freeze");
const f1 = session({ kind: "main", id: "Main", name: "main" });
await expect("D before the swap: outside scope refused", f1.tool("write", { path: "other/z.txt", content: "x" }), "path-outside-scope");
const fs = await import("node:fs");
fs.copyFileSync(process.env.WIDE_PROFILE!, `${BIND}/t-freeze.profile.json`);
const b = JSON.parse(fs.readFileSync(`${BIND}/t-freeze.json`, "utf8"));
b.profile = "wide-open"; b.profile_sha256 = process.env.WIDE_SHA;
fs.writeFileSync(`${BIND}/t-freeze.json`, JSON.stringify(b));
const f2 = session({ kind: "main", id: "Main", name: "main" });
await expect("D a consistent mid-process swap to a wider profile does not widen this process", f2.tool("write", { path: "other/z.txt", content: "x" }), "path-outside-scope");

// --- E. two tasks in one process keep separate policies ----------------------------------
task("t-docs");
const dlead = session({ kind: "main", id: "Main", name: "main" });
await expect("E docs-only task: docs in scope", dlead.tool("write", { path: "docs/x.md", content: "x" }), "allow");
await expect("E docs-only task: apps/api is not in this task's scope", dlead.tool("write", { path: "apps/api/a.py", content: "x" }), "path-outside-scope");
await expect("E docs-only task: commit right none still blocks git commit", dlead.tool("bash", { command: "git commit -m x" }), "op-commit");
task("t-team");
const lead2 = session({ kind: "main", id: "Main", name: "main" });
await expect("E back on the web-feature task: apps/api is in scope again", lead2.tool("write", { path: "apps/api/a.py", content: "x" }), "allow");
await expect("E web-feature identities did not leak into docs-only", lead2.tool("write", { path: "docs/x.md", content: "x" }), "path-outside-scope");

// --- R. member and helper reads stay in the worktree and the shared skill roots ----------
const OUT = process.env.FIXTURE_OUTSIDE!;
const FH = process.env.HOME!;
const R = "read-outside-worktree";
const S = "read-scheme-not-allowed";
task("t-team");
const memberReads: Array<[string, string, Record<string, unknown>, string]> = [
  ["reads a worktree file", "read", { path: "apps/api/a.py" }, "allow"],
  ["reads a worktree line range", "read", { path: "apps/api/a.py:1-5" }, "allow"],
  ["reads a worktree archive member", "read", { path: "apps/x.zip:inner" }, "allow"],
  ["reads the worktree by absolute path", "read", { path: `${W}/apps/web/b.js` }, "allow"],
  ["greps a worktree list", "grep", { pattern: "x", path: "apps; other" }, "allow"],
  ["greps the default scope", "grep", { pattern: "x" }, "allow"],
  ["globs inside the worktree", "glob", { path: "apps/**/*.py" }, "allow"],
  ["finds inside the worktree", "find", { query: "x", grep_keywords: [], path: "apps" }, "allow"],
  ["ast_greps inside the worktree", "ast_grep", { pat: "x", path: "apps/api" }, "allow"],
  ["lsp navigation inside the worktree", "lsp", { action: "definition", file: "apps/web/b.js" }, "allow"],
  ["reads local://", "read", { path: "local://notes.md" }, "allow"],
  ["reads a local:// range", "read", { path: "local://notes.md:1-5" }, "allow"],
  ["reads artifact://", "read", { path: "artifact://3" }, "allow"],
  ["reads agent://", "read", { path: "agent://Api" }, "allow"],
  ["reads rule://", "read", { path: "rule://r" }, "allow"],
  ["reads omp://", "read", { path: "omp://tools/read.md" }, "allow"],
  ["reads a shared skill", "read", { path: "~/.agents/skills/e/SKILL.md" }, "allow"],
  ["reads a shared skill by absolute path", "read", { path: `${FH}/.agents/skills/e/SKILL.md` }, "allow"],
  ["reads a shared reference", "read", { path: "~/.agents/references/x.md" }, "allow"],
  ["reads an outside file", "read", { path: `${OUT}/cred.txt` }, R],
  ["reads ~/.ssh", "read", { path: "~/.ssh/x" }, R],
  ["reads out through ..", "read", { path: "../outside/cred.txt" }, R],
  ["reads through a worktree link to outside", "read", { path: "apps/api/link-out/f.txt" }, R],
  ["reads a dangling worktree link to outside", "read", { path: "apps/api/dangle" }, R],
  ["reads a repository-shipped skill link to outside", "read", { path: ".agents/skills/p/leak" }, R],
  ["reads an outside line range", "read", { path: "/etc/passwd:1-5" }, R],
  ["reads an outside archive member", "read", { path: `${OUT}/x.zip:inner` }, R],
  ["hides an outside path after whitespace", "read", { path: `apps/api/a.py ${OUT}/cred.txt` }, R],
  ["hides an outside path after a comma", "read", { path: `apps/api/a.py,${OUT}/cred.txt` }, R],
  ["escapes with backslash separators", "read", { path: "..\\outside\\cred.txt" }, R],
  ["escapes behind a glob character", "read", { path: "apps/*/../../../outside/cred.txt" }, R],
  ["greps a list reaching outside", "grep", { pattern: "x", path: `apps; ${OUT}` }, R],
  ["globs from an outside root", "glob", { path: `${OUT}/**/*.txt` }, R],
  ["finds outside", "find", { query: "x", grep_keywords: [], path: OUT }, R],
  ["ast_greps outside", "ast_grep", { pat: "x", path: OUT }, R],
  ["lsp navigation on an outside file", "lsp", { action: "definition", file: `${OUT}/cred.txt` }, R],
  ["lsp through the xd device on an outside file", "write", { path: "xd://lsp", content: JSON.stringify({ action: "hover", file: `${OUT}/cred.txt` }) }, R],
  ["leaves the skills root through ..", "read", { path: "~/.agents/skills/../.ssh/x" }, R],
  ["reads a look-alike skills root", "read", { path: "~/.agents/skillsX/a" }, R],
  ["leaves the references root through ..", "read", { path: "~/.agents/references/../x" }, R],
  ["follows a skill link to outside", "read", { path: "~/.agents/skills/e/leak" }, R],
  ["follows a skill link into another entry", "read", { path: "~/.agents/skills/e/sib" }, R],
  ["follows a dangling skill link", "read", { path: "~/.agents/skills/e/dangle" }, R],
  ["greps a skill link to outside in a list", "grep", { pattern: "x", path: "apps; ~/.agents/skills/e/leak" }, R],
  ["reads skill://", "read", { path: "skill://x" }, S],
  ["reads a file inside a skill://", "read", { path: "skill://x/leak" }, S],
  ["lists history://", "read", { path: "history://" }, S],
  ["reads the lead transcript", "read", { path: "history://Main" }, S],
  ["reads history://current/full", "read", { path: "history://current/full" }, S],
  ["reads ssh://", "read", { path: "ssh://h/etc/passwd" }, S],
  ["reads vault://", "read", { path: "vault://n" }, S],
  ["reads cfg://", "read", { path: "cfg://x" }, S],
  ["reads mcp://", "read", { path: "mcp://x" }, S],
  ["reads pr://", "read", { path: "pr://1" }, S],
  ["reads issue://", "read", { path: "issue://1" }, S],
  ["reads proc://", "read", { path: "proc://x" }, S],
  ["reads xd://", "read", { path: "xd://lsp" }, S],
  ["reads file://", "read", { path: "file:///etc/passwd" }, S],
  ["reads an unknown scheme", "read", { path: "foo://x" }, S],
  ["reads an opaque ssh: target", "read", { path: "ssh:h/etc/passwd" }, S],
  ["reads a single-slash skill: alias", "read", { path: "skill:/x" }, S],
  ["reads an upper-case scheme", "read", { path: "SKILL://x" }, S],
  ["reads a scheme embedded after a path", "read", { path: "apps/skill://x" }, S],
  ["greps a skill:// entry in a list", "grep", { pattern: "x", path: "apps; skill://x" }, S],
  ["reads plain http", "read", { path: "http://example.com" }, S],
  ["reads a non-string path", "read", { path: ["apps"] }, "unparsed-read-target"],
  ["calls a tool named browser", "browser", { action: "open" }, "tool-not-allowed"],
];
for (const [label, tool, input, want] of memberReads) await expect(`R member ${label}`, api.tool(tool, input), want);
await expect("R read-only member reads an outside file", qa.tool("read", { path: `${OUT}/cred.txt` }), R);
await expect("R the lead reads an outside file (unchanged)", lead.tool("read", { path: `${OUT}/cred.txt` }), "allow");
await expect("R the lead reads skill:// (unchanged)", lead.tool("read", { path: "skill://x" }), "allow");
await expect("R the lead reads history:// (unchanged)", lead.tool("read", { path: "history://Main" }), "allow");
await expect("R the lead reads plain http (unchanged)", lead.tool("read", { path: "http://example.com" }), "allow");
await expect("R a member still may not write local://", api.tool("write", { path: "local://notes.md", content: "x" }), "local-write-not-allowed");
task("t-plain");
await expect("R a session without a team reads anywhere (unchanged)", plain.tool("read", { path: `${OUT}/cred.txt` }), "allow");
task("t-helper");
await expect("R a helper reads its worktree", helper.tool("read", { path: "apps/api/a.py" }), "allow");
await expect("R a helper reads an outside file", helper.tool("read", { path: `${OUT}/cred.txt` }), R);
await expect("R a helper reads skill://", helper.tool("read", { path: "skill://x" }), S);

// --- S. HTTPS reads only where the bound profile grants https_read ------------------------
const N = "https-read-not-granted";
const URL1 = "https://example.com/a";
task("t-https");
const slead = session({ kind: "main", id: "Main", name: "main" });
await slead.start();
const po = session({ kind: "sub", id: "Po", name: "fm-product-owner", parentId: "Main" });
await po.start();
const sqa = session({ kind: "sub", id: "Qa", name: "fm-qa", parentId: "Main" });
await sqa.start();
const sapi = session({ kind: "sub", id: "Api", name: "fm-django-pro", parentId: "Main" });
await sapi.start();
await expect("S https_read true: https read allowed", po.tool("read", { path: URL1 }), "allow");
await expect("S https_read true: www. read allowed", po.tool("read", { path: "www.example.com" }), "allow");
await expect("S https_read true: https grep allowed", po.tool("grep", { pattern: "x", path: URL1 }), "allow");
await expect("S https_read true: plain http still refused", po.tool("read", { path: "http://example.com" }), S);
await expect("S https_read true: an outside host read still refused", po.tool("read", { path: `${OUT}/cred.txt` }), R);
await expect("S https_read true: skill:// still refused", po.tool("read", { path: "skill://x" }), S);
await expect("S https_read false: https refused", sqa.tool("read", { path: URL1 }), N);
await expect("S https_read absent: https refused", sapi.tool("read", { path: URL1 }), N);
await expect("S https_read absent: www. refused", sapi.tool("read", { path: "www.example.com" }), N);
await expect("S https_read absent: collapsed https:/ refused", sapi.tool("read", { path: "https:/example.com" }), N);
await expect("S https_read absent: upper-case HTTPS refused", sapi.tool("read", { path: "HTTPS://example.com" }), N);
await expect("S https_read absent: https hidden in a grep list refused", sapi.tool("grep", { pattern: "x", path: "apps; https://example.com" }), N);
await expect("S https_read absent: ast_grep of a web URL refused", sapi.tool("ast_grep", { pat: "x", path: "https://example.com/a.js" }), N);
await expect("S the lead reads https with no grant (unchanged)", slead.tool("read", { path: URL1 }), "allow");
task("t-helper-open");
const olead = session({ kind: "main", id: "Main", name: "main" });
await olead.start();
const ohost = session({ kind: "sub", id: "Api", name: "fm-fixture-host", parentId: "Main" });
await ohost.start();
const ohelper = session({ kind: "sub", id: "Api.Scout", name: "scout", parentId: "Api" });
await ohelper.start();
await expect("S a granted member reads https", ohost.tool("read", { path: URL1 }), "allow");
await expect("S the helper of a granted member reads https", ohelper.tool("read", { path: URL1 }), "allow");
await expect("S the helper of a granted member stays read-confined", ohelper.tool("read", { path: `${OUT}/cred.txt` }), R);
await expect("S the helper of a granted member stays read-only", ohelper.tool("write", { path: "apps/api/a.py", content: "x" }), "read-only-member");
task("t-helper");
await expect("S another task's same-named helper without the grant: https refused", helper.tool("read", { path: URL1 }), N);
await expect("S another task's same-named member without the grant: https refused", hapi.tool("read", { path: URL1 }), N);
task("t-helper-open");
await expect("S back on the granted task: its helper still reads https", ohelper.tool("read", { path: URL1 }), "allow");
task("t-badhttps");
const bad = session({ kind: "main", id: "Main", name: "main" });
await expect("S a non-boolean https_read snapshot refuses the task", bad.tool("write", { path: "apps/api/a.py", content: "x" }), "team-profile-corrupt");
await expect("S a non-boolean https_read snapshot keeps reads", bad.tool("read", { path: "apps/api/a.py" }), "allow");

process.exit(failed);
TS

# Literal glob table, judged identically by both implementations.
GLOB_TABLE='[["apps/api/**","apps/api/a.py",true],["apps/api/**","apps/api",true],["apps/api/**","apps/api/x/y/z.py",true],
["apps/api/**","apps/apix/a.py",false],["apps/api/**","apps/web/a.py",false],["*.md","README.md",true],["*.md","docs/a.md",false],
["**/*.md","docs/a/b.md",true],["**/*.md","b.md",true],["a/**/b","a/b",true],["a/**/b","a/x/y/b",true],["a/**/b","a/xb",false],
["src/?.ts","src/a.ts",true],["src/?.ts","src/ab.ts",false],["README.md","README.md",true],["README.md","README.mdx",false],
["a.b","axb",false],["**","anything/at/all",true]]'

sed "s#@EXT@#$CONFIG_ROOT/extensions/fm-team-policy.ts#" "$TMP_ROOT/driver.ts" > "$TMP_ROOT/run.ts"
FIXTURE_WORKTREE="$W" FIXTURE_BINDINGS="$BIND" FIXTURE_OUTSIDE="$OUTSIDE" HOME="$FHOME" WIDE_PROFILE="$TMP_ROOT/wide-open.json" WIDE_SHA="$WIDE_SHA" \
  GLOB_TABLE="$GLOB_TABLE" FM_TASK_INBOX='' bun "$TMP_ROOT/run.ts"
check 'extension fixture driver exits 0' "$?" 0

# The same table through bin/fm-team's own matcher (the delivery audit's).
py_out=$(GLOB_TABLE="$GLOB_TABLE" python3 - "$CFG/bin/fm-team" <<'PY'
import importlib.machinery, importlib.util, json, os, sys
loader = importlib.machinery.SourceFileLoader("fm_team", sys.argv[1])
spec = importlib.util.spec_from_loader("fm_team", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
bad = [row for row in json.loads(os.environ["GLOB_TABLE"]) if mod.glob_match(row[0], row[1]) != row[2]]
print("mismatch: %r" % bad if bad else "agree")
PY
)
check 'bin/fm-team glob matcher agrees with the same literal table' "$py_out" agree

exit "$failed"
