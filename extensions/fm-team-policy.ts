// fm-team-policy - firstmate-config's OMP extension that applies a bound team
// profile (bin/fm-team) to the sessions of that one team task.
//
// Scope. It acts only in an OMP process whose FM_TASK_ID (set by the official
// fm-spawn) has a binding in $FM_HOME/data/team-bindings/, or whose brief
// names a `Team profile:`; every other session - the Captain, ordinary
// workers, manual sessions - is a no-op. FM_HOME falls back to the parent of
// the official FM_TASK_INBOX's state/ directory, then ~/.firstmate.
//
// Resolution. The binding and snapshot are read once per task per process and
// the result is kept for the life of the process, so a profile rewritten
// mid-run cannot widen it; a relaunch reads them again (run `fm-team check` as
// the relaunch check). A known team task whose profile is missing, corrupt,
// tampered (sha256 mismatch) or mismatched refuses every tool but read-only
// ones and yield, every message, and every spawn.
//
// Identity, per call from ctx.agent: the main session is the lead; a top-level
// subagent whose agent name is a profile member is that member; a subagent of
// a member session is that member's helper (read-only, may message only that
// member, may not spawn, reads https only if that member may); anything
// else - including a missing identity or an unregistered parent - is
// refused like a broken profile. Sessions register their agent id on their
// first hook call; recipient ids are resolved only through that registry.
//
// Enforced at OMP's own hooks:
// - before_subagent_spawn: the lead spawns only profile members, a member
//   only its profile `spawn` helpers, a helper nothing;
// - tool_call write/edit/apply_patch/notebook/ast_edit (and xd://ast_edit):
//   every target, normalized and symlink-resolved (dangling links followed),
//   must stay inside the worktree and match the writer's globs - a member its
//   own, the lead the union; read-only members and helpers write nothing;
//   local:// is the lead's only, other schemes and archive/sqlite `:` targets
//   are refused, and lsp rename/rename_file/request/applied code actions are
//   refused because they edit arbitrary files;
// - write agent://<id>: never agent://all; a member may message the lead and
//   its talk_to members, the lead any registered session of its task;
// - tool_call read/grep/glob/find/ast_grep `path` and lsp `file` (also via
//   xd://lsp) of a member or helper: host paths must resolve inside the
//   worktree, or under one ~/.agents/skills/<entry> or ~/.agents/references
//   (judged against that entry's own realpath); of internal URLs only
//   local, artifact, agent, rule and omp are read - skill:// and history://
//   reach past these checks and are refused with every other scheme and
//   plain http; https only with the member's `https_read: true`. The whole
//   target and every `;`, comma or whitespace part, colon prefix and glob
//   base is judged. The lead reads as before;
// - eval is refused in a team, and an unlisted tool is refused.
// Best effort only: bash commands matching git commit/cherry-pick/revert/am/
// rebase/merge/push, gh pr merge/create, gh release/repo create, and gh api
// mutations are refused. A pattern cannot see through eval'd strings, scripts,
// aliases or indirection, and bash may still write any file, read anything,
// and use any credential the user account holds. A permitted https read is
// an egress channel for whatever its reader can see. The Captain's `fm-team
// audit` is the delivery-time check for the final tree, and FirstMate alone
// commits, pushes and merges.
import { createHash } from "node:crypto";
import { lstatSync, readFileSync, readlinkSync, realpathSync, type Stats } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";

// The omp extension API surface this file uses, declared locally (omp ships
// no separately installable type package). Events and ctx arrive unvalidated.
type Handler = (event: unknown, ctx: unknown) => unknown;
type ExtensionAPI = { on: (event: string, handler: Handler) => void };
type Fields = Record<string, unknown>;
type AgentInfo = { kind: "main" | "sub"; id: string | undefined; name: string; parentId: string | undefined };
type Registered = AgentInfo & { id: string };
type Member = { mode: string; write: RegExp[]; talkTo: Set<string>; spawn: Set<string>; https: boolean };
type Team = { task: string; profile: string; members: Map<string, Member>; scope: RegExp[]; commit: string };
type Resolution =
  | { kind: "none" }
  | { kind: "team"; team: Team }
  | { kind: "refused"; code: string; detail: string };
type Who =
  | { role: "lead" }
  | { role: "member"; member: Member; name: string }
  | { role: "helper"; parentId: string; https: boolean }
  | { role: "unknown"; why: string };
type Verdict = { block: true; reason: string } | undefined;

const TASK_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/;
const NAME_RE = /^[a-z0-9][a-z0-9-]{0,39}$/;
const AGENT_RE = /^fm-[a-z0-9][a-z0-9-]*$/;
const SHA256_RE = /^[0-9a-f]{64}$/;
const BASE_RE = /^[0-9a-f]{7,40}$/;
// bin/fm-team's BRIEF_MARKER_RE: the marker in whatever Markdown wraps it.
const MARKER_RE = /^[ \t]*(?:[-*+][ \t]+)?[*_]{0,2}team profile[*_]{0,2}:[*_]{0,2}[ \t]+`?([^\s`*]+)/im;
const GLOB_SEGMENT_RE = /^[A-Za-z0-9._@+*?-]+$/;
const SAFE_TARGET_RE = /^[A-Za-z0-9._/@+*?~ -]+$/;
// Tools every resolved team identity keeps; tools handled below are judged on
// their input, and any other tool is refused.
const SAFE_TOOLS: Record<string, true> = {
  yield: true, todo: true, wait: true, web_search: true, ask: true, checkpoint: true, rewind: true, recall: true, resolve: true, reject: true,
};
// Schemes a member or helper may read: virtual docs and rules, and task-local
// files OMP itself contains (local:// by realpath; artifact:// and agent://
// by id or listed name). https is judged separately, by the https_read grant.
const READ_SCHEMES: Record<string, true> = { local: true, artifact: true, agent: true, rule: true, omp: true };
// OMP 18.5.0's own scheme detection (internal-urls/parse.ts extractUriScheme):
// `x://...`, or an opaque `xy:rest` whose name has no dot and whose rest is no
// line/raw/conflicts selector. EMBEDDED_URL_RE is its single-slash-alias scan.
const URL_RE = /^([a-z][a-z0-9+.-]*):\/\//i;
const OPAQUE_RE = /^([a-z][a-z0-9+.-]*):(.+)$/is;
const SEL = String.raw`(?:raw|conflicts|-?\d+(?:[-+]\d+)?(?:,\d+(?:[-+]\d+)?)*)`;
const SELECTOR_RE = new RegExp(`^${SEL}(?::${SEL})*$`, "i");
const EMBEDDED_URL_RE = /[\\/]([a-z][a-z0-9+.-]*):\/\/(?=[^/]|$)/gi;
// The only tools a refused or unidentified team session keeps.
const REFUSED_TOOLS: Record<string, true> = { read: true, grep: true, glob: true, find: true, ast_grep: true, yield: true };
const MUTATING_LSP: Record<string, true> = { rename: true, rename_file: true, request: true };
// Best-effort command patterns; see the header for what they cannot see.
const OP_PATTERNS: Array<[string, RegExp]> = [
  ["op-push", /\bgit\b[^\n;&|]*?\spush\b/],
  ["op-merge", /\bgit\b[^\n;&|]*?\smerge\b/],
  ["op-commit", /\bgit\b[^\n;&|]*?\s(?:commit|cherry-pick|revert|am|rebase)\b/],
  ["op-merge", /\bgh\b[^\n;&|]*?\spr\s+merge\b/],
  ["op-push", /\bgh\b[^\n;&|]*?\s(?:pr\s+create|release\s+create|repo\s+(?:create|delete|edit))\b/],
  ["op-push", /\bgh\b[^\n;&|]*?\sapi\b[^\n;&|]*?(?:-X|--method)[\s=]*(?:POST|PUT|PATCH|DELETE)\b/i],
];

// Module state is shared by a parent session and the subagents OMP rebinds
// this factory to, which is what a team needs; it is keyed by task id, so two
// tasks in one process never see each other's resolution or identities.
const resolutions = new Map<string, Resolution>();
const identities = new Map<string, Map<string, Registered>>();
const NONE: Resolution = { kind: "none" };

const refuse = (code: string, detail: string): Verdict => ({ block: true, reason: `fm-team-policy refused (${code}): ${detail}` });
const refused = (code: string, detail: string): Resolution => ({ kind: "refused", code, detail });
const fields = (v: unknown): Fields => (v !== null && typeof v === "object" ? (v as Fields) : {});
const isStrList = (v: unknown): v is string[] => Array.isArray(v) && v.every((x) => typeof x === "string");
const str = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);

function lstatOrNull(p: string): Stats | null {
  try {
    return lstatSync(p);
  } catch {
    return null;
  }
}

// --- globs: the same translation as bin/fm-team's glob_regex -------------------

function globRegExp(glob: string): RegExp {
  let rx = "";
  let needSep = false;
  const parts = glob.split("/");
  parts.forEach((seg, i) => {
    if (seg === "**") {
      const last = i === parts.length - 1;
      rx += last ? (needSep ? "(?:/.*)?" : ".*") : needSep ? "/(?:.*/)?" : "(?:.*/)?";
      needSep = false;
      return;
    }
    if (needSep) rx += "/";
    for (const c of seg) rx += c === "*" ? "[^/]*" : c === "?" ? "[^/]" : c.replace(/[.+^${}()|[\]\\]/, "\\$&");
    needSep = true;
  });
  return new RegExp(`^${rx}$`, "s");
}

export function globMatch(glob: string, path: string): boolean {
  return globRegExp(glob).test(path);
}

function globOk(glob: string): boolean {
  if (!glob || glob.length > 200 || glob.startsWith("/") || glob.includes("\\")) return false;
  return glob.split("/").every((s) => !["", ".", ".."].includes(s) && GLOB_SEGMENT_RE.test(s) && (s === "**" || !s.includes("**")));
}

// --- resolution ------------------------------------------------------------------

function fmHome(): string {
  if (process.env.FM_HOME) return process.env.FM_HOME;
  const inbox = process.env.FM_TASK_INBOX;
  if (inbox && basename(dirname(inbox)) === "state") return dirname(dirname(inbox));
  return join(homedir(), ".firstmate");
}

function parseTeam(task: string, parsed: unknown, name: string): Team | string {
  const p = fields(parsed);
  if (p.schema !== "fm-team-profile.v1" || p.name !== name) return `snapshot is not the bound fm-team-profile.v1 profile ${name}`;
  if (!Array.isArray(p.members) || p.members.length === 0) return "snapshot has no members";
  const members = new Map<string, Member>();
  const scope: RegExp[] = [];
  for (const entry of p.members) {
    const m = fields(entry);
    const write = fields(m.paths).write ?? [];
    const talkTo = m.talk_to ?? [];
    const spawn = m.spawn ?? [];
    const agent = str(m.agent);
    const mode = str(m.mode);
    const https = m.https_read === undefined ? false : m.https_read;
    if (!agent || !AGENT_RE.test(agent) || (mode !== "read-only" && mode !== "mutating") || members.has(agent)
        || !isStrList(write) || !isStrList(talkTo) || !isStrList(spawn) || typeof https !== "boolean"
        || (mode === "read-only" && write.length > 0) || !write.every(globOk)) {
      return `snapshot member ${JSON.stringify(m.agent)} is malformed`;
    }
    const rx = write.map(globRegExp);
    scope.push(...rx);
    members.set(agent, { mode, write: rx, talkTo: new Set(talkTo), spawn: new Set(spawn.map((s) => s.toLowerCase())), https });
  }
  const ops = fields(p.ops);
  const commit = str(ops.commit);
  if ((commit !== "none" && commit !== "request") || ops.push !== "none" || ops.merge !== "none") {
    return "snapshot ops grant more than commit none|request, push none, merge none";
  }
  return { task, profile: name, members, scope, commit };
}

function loadTeam(task: string): Resolution {
  const home = fmHome();
  const dir = join(home, "data", "team-bindings");
  let marker: string | undefined;
  try {
    marker = MARKER_RE.exec(readFileSync(join(home, "data", task, "brief.md"), "utf8"))?.[1];
  } catch {
    marker = undefined;
  }
  const bpath = join(dir, `${task}.json`);
  const bstat = lstatOrNull(bpath);
  if (!bstat) return marker ? refused("team-binding-missing", `the brief names team profile ${marker} but ${bpath} is absent`) : NONE;
  if (!bstat.isFile()) return refused("team-binding-corrupt", `${bpath} is not a regular file`);
  let parsedBinding: unknown;
  try {
    parsedBinding = JSON.parse(readFileSync(bpath, "utf8"));
  } catch (err) {
    return refused("team-binding-corrupt", `${bpath}: ${err}`);
  }
  const b = fields(parsedBinding);
  if (b.schema !== "fm-team-binding.v1") return refused("team-binding-corrupt", `${bpath} is not a fm-team-binding.v1 record`);
  if (b.task !== task) return refused("team-binding-mismatch", `${bpath} records task ${JSON.stringify(b.task)}`);
  const profile = str(b.profile);
  const sha = str(b.profile_sha256);
  const base = str(b.base);
  if (!profile || !NAME_RE.test(profile) || !sha || !SHA256_RE.test(sha) || !base || !BASE_RE.test(base)) {
    return refused("team-binding-corrupt", `${bpath} has a missing or malformed field`);
  }
  if (marker && marker !== profile) return refused("team-binding-mismatch", `the brief names ${marker} but the binding names ${profile}`);
  const spath = join(dir, `${task}.profile.json`);
  const sstat = lstatOrNull(spath);
  if (!sstat) return refused("team-profile-missing", `${spath} is absent`);
  if (!sstat.isFile()) return refused("team-profile-corrupt", `${spath} is not a regular file`);
  const raw = readFileSync(spath);
  if (createHash("sha256").update(raw).digest("hex") !== sha) return refused("team-profile-tampered", `${spath} no longer matches the bound sha256`);
  let parsedProfile: unknown;
  try {
    parsedProfile = JSON.parse(raw.toString("utf8"));
  } catch (err) {
    return refused("team-profile-corrupt", `${spath}: ${err}`);
  }
  const team = parseTeam(task, parsedProfile, profile);
  return typeof team === "string" ? refused("team-profile-corrupt", team) : { kind: "team", team };
}

function current(): Resolution {
  const task = process.env.FM_TASK_ID;
  // bin/fm-team refuses to bind an id outside TASK_RE, so none can be a team.
  if (!task || !TASK_RE.test(task)) return NONE;
  let r = resolutions.get(task);
  if (!r) {
    r = loadTeam(task);
    resolutions.set(task, r);
  }
  return r;
}

// --- identity --------------------------------------------------------------------

function agentOf(ctx: unknown): AgentInfo | undefined {
  const a = fields(fields(ctx).agent);
  if (a.kind !== "main" && a.kind !== "sub") return undefined;
  return { kind: a.kind, id: str(a.id), name: (str(a.name) ?? "").toLowerCase(), parentId: str(a.parentId) };
}

function registry(task: string): Map<string, Registered> {
  let ids = identities.get(task);
  if (!ids) identities.set(task, (ids = new Map()));
  return ids;
}

function register(task: string, a: AgentInfo | undefined): void {
  if (!a?.id) return;
  const ids = registry(task);
  if (!ids.has(a.id)) ids.set(a.id, { ...a, id: a.id });
}

function topLevel(ids: Map<string, Registered>, a: AgentInfo): boolean {
  return a.parentId === undefined || ids.get(a.parentId)?.kind === "main";
}

function identify(team: Team, a: AgentInfo | undefined): Who {
  if (!a) return { role: "unknown", why: "this session carries no agent identity" };
  register(team.task, a);
  if (a.kind === "main") return { role: "lead" };
  const ids = registry(team.task);
  if (a.parentId !== undefined) {
    const parent = ids.get(a.parentId);
    if (!parent) return { role: "unknown", why: `${a.name} (${a.id}) has parent ${a.parentId}, which is no registered session of task ${team.task}` };
    if (parent.kind === "sub") {
      const host = topLevel(ids, parent) ? team.members.get(parent.name) : undefined;
      if (host) return { role: "helper", parentId: parent.id, https: host.https };
      return { role: "unknown", why: `${a.name} (${a.id}) descends from ${parent.name}, which is not a member of ${team.profile}` };
    }
  }
  const member = team.members.get(a.name);
  if (member) return { role: "member", member, name: a.name };
  return { role: "unknown", why: `${a.name} (${a.id}) is not a member of team profile ${team.profile}` };
}

// --- decisions ---------------------------------------------------------------------

function within(root: string, p: string): string | null {
  const rel = relative(root, p);
  if (rel === ".." || rel.startsWith("../") || isAbsolute(rel)) return null;
  return rel;
}

// The real location a write to `p` would land on: the nearest existing
// ancestor's realpath plus the rest, following a dangling link's text too.
function realpathDeep(p: string, hops = 0): string | null {
  if (hops > 40) return null;
  const tail: string[] = [];
  let cur = p;
  for (;;) {
    const st = lstatOrNull(cur);
    if (st) {
      try {
        return join(realpathSync(cur), ...tail);
      } catch {
        if (!st.isSymbolicLink()) return null;
        return realpathDeep(join(resolve(dirname(cur), readlinkSync(cur)), ...tail), hops + 1);
      }
    }
    const parent = dirname(cur);
    if (parent === cur) return join(cur, ...tail);
    tail.unshift(basename(cur));
    cur = parent;
  }
}

type Root = { abs: string; real: string };

function sessionRoot(cwd: unknown): Root | string {
  if (typeof cwd !== "string" || !cwd) return "this session has no working directory to judge paths against";
  const abs = resolve(cwd);
  try {
    return { abs, real: realpathSync(abs) };
  } catch {
    return `the session directory ${cwd} does not resolve`;
  }
}

function expandHome(p: string): string {
  return p === "~" ? homedir() : p.startsWith("~/") ? join(homedir(), p.slice(2)) : p;
}

function decidePath(team: Team, who: Who, cwd: unknown, raw: unknown): Verdict {
  const scope = who.role === "lead" ? team.scope : who.role === "member" && who.member.mode === "mutating" ? who.member.write : null;
  if (!scope) return refuse("read-only-member", `a read-only ${who.role} of team ${team.profile} writes no files`);
  if (typeof raw !== "string" || !raw || raw.includes("\0")) return refuse("unparsed-edit-target", `cannot read a target path from ${JSON.stringify(raw)}`);
  if (raw.includes(":")) return refuse("colon-target-not-allowed", `${raw}: archive and sqlite targets are not judged, so they are refused`);
  const root = sessionRoot(cwd);
  if (typeof root === "string") return refuse("path-outside-worktree", root);
  const lexical = resolve(root.abs, expandHome(raw));
  const relLexical = within(root.abs, lexical) ?? within(root.real, lexical);
  if (relLexical === null) return refuse("path-outside-worktree", `${raw} is outside the task worktree`);
  const real = realpathDeep(lexical);
  const relReal = real === null ? null : within(root.real, real);
  if (relReal === null) return refuse("path-outside-worktree", `${raw} resolves through a link to outside the task worktree`);
  if (!scope.some((g) => g.test(relLexical)) || !scope.some((g) => g.test(relReal))) {
    const as = relReal === relLexical ? relLexical : `${relLexical} (resolves to ${relReal})`;
    return refuse("path-outside-scope", `${as} is outside the write globs ${who.role === "member" ? `of ${who.name}` : `of team ${team.profile}`}`);
  }
  return undefined;
}

function decideEach(team: Team, who: Who, cwd: unknown, targets: string[]): Verdict {
  if (targets.length === 0) return decidePath(team, who, cwd, undefined);
  for (const t of targets) {
    const v = decidePath(team, who, cwd, t);
    if (v) return v;
  }
  return undefined;
}

// The realpath of the shared root a lexical path sits under: one entry of
// ~/.agents/skills (anchored to that entry, so a link out of it or into a
// sibling entry fails) or ~/.agents/references, the roots install.sh links.
function sharedAnchor(lexical: string): string | null {
  const agents = join(homedir(), ".agents");
  const rel = within(agents, lexical);
  if (rel === null) return null;
  const [top, entry] = rel.split("/");
  const anchor = top === "references" ? join(agents, "references") : top === "skills" && entry ? join(agents, "skills", entry) : null;
  if (anchor === null) return null;
  try {
    return realpathSync(anchor);
  } catch {
    return null;
  }
}

function readable(root: Root, p: string): boolean {
  const lexical = resolve(root.abs, expandHome(p));
  const real = realpathDeep(lexical);
  if (real === null) return false;
  if ((within(root.abs, lexical) ?? within(root.real, lexical)) !== null && within(root.real, real) !== null) return true;
  const anchor = sharedAnchor(lexical);
  return anchor !== null && within(anchor, real) !== null;
}

// Every path OMP may read for one entry: the whole entry and each prefix
// before a `:` (selectors, archive members, views), each also cut before its
// first glob character (the base a glob walks).
function readCandidates(p: string): string[] {
  const out: string[] = [];
  for (let i = p.indexOf(":"); ; i = p.indexOf(":", i + 1)) {
    const s = i < 0 ? p : p.slice(0, i);
    const g = s.search(/[*?[{]/);
    out.push(s);
    if (g >= 0) out.push(s.slice(0, g));
    if (i < 0) return out;
  }
}

function uriScheme(t: string): string | undefined {
  if (/^www\./i.test(t)) return "https";
  const url = URL_RE.exec(t);
  if (url) return url[1].toLowerCase();
  const opaque = OPAQUE_RE.exec(t);
  if (!opaque || opaque[1].length === 1 || opaque[1].includes(".") || SELECTOR_RE.test(opaque[2])) return undefined;
  return opaque[1].toLowerCase();
}

function decideReadEntry(team: Team, who: Who, cwd: unknown, https: boolean, t: string): Verdict {
  const scheme = uriScheme(t);
  if (scheme === "https") return https ? undefined : refuse("https-read-not-granted", `${t}: team ${team.profile} grants this ${who.role} no https_read`);
  if (scheme === "skill") {
    const name = t.replace(/^skill:\/*/i, "");
    const copy = name ? `; read ~/.agents/skills/${name.includes("/") ? name : `${name}/SKILL.md`} for a shared skill, or a project skill by its worktree path` : "";
    return refuse("read-scheme-not-allowed", `skill:// can reach any host file through a link${copy}`);
  }
  if (scheme !== undefined) {
    return READ_SCHEMES[scheme] === true ? undefined : refuse("read-scheme-not-allowed", `${scheme}: targets are not readable by a ${who.role} of team ${team.profile}`);
  }
  for (const m of t.matchAll(EMBEDDED_URL_RE)) {
    const v = decideReadEntry(team, who, cwd, https, t.slice(m.index + 1));
    if (v) return v;
  }
  const root = sessionRoot(cwd);
  if (typeof root === "string") return refuse("read-outside-worktree", root);
  for (const variant of new Set([t, t.replace(/\\/g, "/")])) {
    for (const p of readCandidates(variant)) {
      if (!readable(root, p)) return refuse("read-outside-worktree", `${t} is outside the task worktree and the shared skill roots`);
    }
  }
  return undefined;
}

// A member's or helper's read-family target (read/grep/glob/find/ast_grep
// `path`, lsp `file`). OMP splits `;` lists, and comma or whitespace lists
// once a part exists, so the whole value and every part are judged. The lead
// reads as before.
function decideRead(team: Team, who: Who, cwd: unknown, raw: unknown): Verdict {
  if (who.role === "lead" || raw === undefined) return undefined;
  if (typeof raw !== "string" || raw.includes("\0")) return refuse("unparsed-read-target", `cannot read a target from ${JSON.stringify(raw)}`);
  const https = who.role === "member" ? who.member.https : who.role === "helper" && who.https;
  for (const entry of new Set([raw, ...raw.split(/[;,\s]+/)])) {
    const t = entry.trim();
    if (!t) continue;
    const v = decideReadEntry(team, who, cwd, https, t);
    if (v) return v;
  }
  return undefined;
}

function unquote(s: string): string {
  const t = s.trim();
  return t.length > 1 && (t[0] === '"' || t[0] === "'") && t.endsWith(t[0]) ? t.slice(1, -1) : t;
}

// Targets of every OMP edit mode: OMP's derived path/paths fields, the
// replace/patch `path` and `rename`, hashline [PATH#TAG] headers and MV, and
// apply_patch/sloppy file headers.
function editTargets(input: Fields): string[] {
  const out: string[] = [];
  if (typeof input.path === "string") out.push(input.path);
  if (isStrList(input.paths)) out.push(...input.paths);
  if (Array.isArray(input.edits)) {
    for (const e of input.edits) {
      const rename = fields(e).rename;
      if (typeof rename === "string") out.push(rename);
    }
  }
  if (typeof input.input === "string") {
    for (const line of input.input.split("\n")) {
      const m = /^\[(.+)#[0-9A-Fa-f]{4}\]\s*$/.exec(line) ?? /^MV\s+(.+?)\s*$/.exec(line)
        ?? /^\*\*\* (?:Add|Update|Delete|Edit) File:\s*(.+?)(?:\s+all)?\s*$/.exec(line) ?? /^\*\*\* Move to:\s*(.+?)\s*$/.exec(line);
      if (m) out.push(unquote(m[1]));
    }
  }
  return out;
}

function decideAst(team: Team, who: Who, cwd: unknown, args: unknown): Verdict {
  const paths = fields(args).paths;
  if (!isStrList(paths) || paths.length === 0) return refuse("unparsed-edit-target", "ast_edit names no target paths");
  for (const p of paths) if (!SAFE_TARGET_RE.test(p)) return refuse("unsafe-target", `ast_edit target ${JSON.stringify(p)} uses syntax beyond * ? **`);
  return decideEach(team, who, cwd, paths);
}

function decideLsp(team: Team, who: Who, cwd: unknown, args: unknown): Verdict {
  const a = fields(args);
  const action = String(a.action ?? "");
  if (MUTATING_LSP[action] === true || (action === "code_actions" && a.apply === true)) {
    return refuse("lsp-refactor-not-allowed", `lsp ${action} edits files outside any write-glob check`);
  }
  return decideRead(team, who, cwd, a.file);
}

function decideMessage(team: Team, who: Who, target: string): Verdict {
  if (target === "all") return refuse("broadcast-not-allowed", "agent://all reaches every live peer; message named members only");
  const ids = registry(team.task);
  const r = ids.get(target);
  if (!r) return refuse("unknown-recipient", `agent://${target} is no registered session of task ${team.task}`);
  if (who.role === "lead") return undefined;
  if (who.role === "helper") return target === who.parentId ? undefined : refuse("recipient-not-allowed", `a helper messages only ${who.parentId}`);
  if (who.role !== "member") return refuse("team-identity-unresolved", "unidentified sender");
  if (r.kind === "main" || (topLevel(ids, r) && who.member.talkTo.has(r.name))) return undefined;
  return refuse("recipient-not-allowed", `${who.name} may message the lead and ${[...who.member.talkTo].join(", ") || "no member"}, not ${r.name}`);
}

function decideWrite(team: Team, who: Who, cwd: unknown, path: unknown, content: unknown): Verdict {
  if (typeof path !== "string") return refuse("unparsed-edit-target", "write names no path");
  if (path.startsWith("agent://")) return decideMessage(team, who, path.slice("agent://".length));
  if (path.startsWith("local://")) {
    return who.role === "lead" ? undefined : refuse("local-write-not-allowed", "only the lead writes the team's local:// files");
  }
  if (path.startsWith("xd://")) {
    const device = path.slice("xd://".length).split(/[/?#]/)[0];
    let args: unknown;
    try {
      args = JSON.parse(String(content ?? ""));
    } catch {
      args = undefined;
    }
    if (device === "ast_edit") return decideAst(team, who, cwd, args);
    if (device === "lsp") return decideLsp(team, who, cwd, args);
    if (device === "resolve" || device === "reject") return undefined;
    return refuse("device-not-allowed", `xd://${device} is not available in a team`);
  }
  if (who.role === "lead" && /^proc:\/\/[^/]+\/kill$/.test(path)) return undefined;
  if (/^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(path)) return refuse("scheme-not-allowed", `${path.split("://")[0]}:// writes are not available in a team`);
  return decidePath(team, who, cwd, path);
}

function decideCommand(team: Team, command: unknown): Verdict {
  if (typeof command !== "string") return refuse("unparsed-command", "bash names no command");
  for (const [code, rx] of OP_PATTERNS) {
    if (rx.test(command)) {
      const commitNote = team.commit === "request" ? " Leave the change uncommitted and stop with needs-decision [key=commit-approval]." : "";
      return refuse(code, `team ${team.profile} grants no commit, push or merge; FirstMate performs them (best-effort command pattern).${commitNote}`);
    }
  }
  return undefined;
}

function decideTool(res: Resolution, ctx: unknown, event: unknown): Verdict {
  if (res.kind === "none") return undefined;
  const ev = fields(event);
  const tool = String(ev.toolName ?? "");
  if (res.kind === "refused") {
    return REFUSED_TOOLS[tool] === true ? undefined : refuse(res.code, `${res.detail}. This team task cannot run until Firstmate repairs its binding; stop and report blocked.`);
  }
  const team = res.team;
  const who = identify(team, agentOf(ctx));
  if (who.role === "unknown") return REFUSED_TOOLS[tool] === true ? undefined : refuse("team-identity-unresolved", who.why);
  const input = fields(ev.input);
  const cwd = fields(ctx).cwd;
  switch (tool) {
    case "write":
      return decideWrite(team, who, cwd, input.path, input.content);
    case "edit":
    case "apply_patch":
    case "notebook":
      return decideEach(team, who, cwd, editTargets(input));
    case "ast_edit":
      return decideAst(team, who, cwd, input);
    case "lsp":
      return decideLsp(team, who, cwd, input);
    case "read":
    case "grep":
    case "glob":
    case "find":
    case "ast_grep":
      return decideRead(team, who, cwd, input.path);
    case "bash":
      return decideCommand(team, input.command);
    case "eval":
      return refuse("eval-not-allowed", "eval runs arbitrary code outside every team check");
    case "task":
      return undefined; // judged per child in before_subagent_spawn
    default:
      return SAFE_TOOLS[tool] === true ? undefined : refuse("tool-not-allowed", `${tool} is not available in team ${team.profile}`);
  }
}

function decideSpawn(res: Resolution, ctx: unknown, event: unknown): Verdict {
  if (res.kind === "none") return undefined;
  if (res.kind === "refused") return refuse(res.code, res.detail);
  const who = identify(res.team, agentOf(ctx));
  if (who.role === "unknown") return refuse("team-identity-unresolved", who.why);
  const agent = fields(event).agent;
  const name = (str(agent) ?? str(fields(agent).name) ?? "").toLowerCase();
  if (name && who.role === "lead" && res.team.members.has(name)) return undefined;
  if (name && who.role === "member" && who.member.spawn.has(name)) return undefined;
  return refuse("spawn-not-allowed", `${who.role} of team ${res.team.profile} may not spawn ${name || "an unnamed agent"}`);
}

// A handler error blocks the call in OMP, so contain it: fail closed for a
// task that is (or may be) a team task, stay a no-op for everything else.
function guard(fn: () => Verdict): Verdict {
  try {
    return fn();
  } catch (err) {
    const task = process.env.FM_TASK_ID;
    if (!task || resolutions.get(task)?.kind === "none") return undefined;
    return refuse("team-policy-error", String(err));
  }
}

export default function fmTeamPolicy(pi: ExtensionAPI): void {
  pi.on("session_start", (_event, ctx) => guard(() => {
    const r = current();
    if (r.kind === "team") register(r.team.task, agentOf(ctx));
    return undefined;
  }));
  pi.on("tool_call", (event, ctx) => guard(() => decideTool(current(), ctx, event)));
  pi.on("before_subagent_spawn", (event, ctx) => guard(() => decideSpawn(current(), ctx, event)));
}
