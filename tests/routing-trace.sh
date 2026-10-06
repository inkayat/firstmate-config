#!/usr/bin/env bash
# routing-trace.sh - offline acceptance, plus an externally usable `check`
# CLI, for the temporary routing/skill trace the Captain prints during the
# debugging period (firstmate/primary-policy.md section 0).
#
# Usage:
#   tests/routing-trace.sh                     run the offline fixture suite
#   tests/routing-trace.sh check <trace-file> <harness> <model> <effort> <skills|none> [<worker-session> [<review-session>]]
#       check ONE worker's captured trace block against the actual spawn
#       axes (the harness/model/effort really passed to fm-spawn, e.g. from
#       state/<id>.meta or the worker's own process line) and the skills
#       actually selected in its brief (comma-separated; absolute
#       .../<name>/SKILL.md paths normalize to <name>, worktree-relative
#       project-local paths stay as written; an absolute or ~/ required-
#       companion path names that exact file). With an omp worker's
#       retained OMP session record
#       (~/.omp/agent/sessions/<worktree>/<id>.jsonl), also check the
#       block's "Skill evidence:" lines against it; a `review` excerpt
#       additionally needs another session's record. Prints PASS/FAIL per
#       check, INSPECT for located context the checker does not assess, and
#       a SUMMARY per skill; exit 0 only when nothing FAILs.
#
# What this proves and what it cannot: `check` compares text the Captain
# printed with facts supplied by the caller. The Routing line starts with
# `CATEGORY` or `CATEGORY #n` only: `#n` names the matched rule within a
# multi-rule category, the axes must be that rule's route (or a named
# captain override), and any free-text sub-lane label is rejected because
# nothing can verify it. For skill evidence it computes READ of each listed
# file from the record's successful `read` results against that exact
# file's current bytes (complete before the first edit/write/ast_edit call,
# late, partial, none, or unreadable when the listed path is no readable
# file; bash/eval calls before the completing read are counted, not
# assessed) and fails a read, excerpt, review, or `usage verified` claim
# whose necessary links the records lack. Excerpts are located, never
# judged: `result` only in bash/eval/background-bash output, each ordered by
# its call (a background job by its launch), `review` only in a different
# session's record. Located links never make usage verified: semantic
# application stays UNPROVEN by this checker and a `usage verified`
# declaration stands only on an independent task-relevant assessment. It
# cannot observe the Captain printing the trace, classify a task into a
# category or rule, prove understanding, why the worker acted, reviewer
# independence, that the record is the assigned worker's, or a record's
# authenticity; a non-omp harness's record supports only UNPROVEN fields.
# It is a diagnostic for the debugging period, never a completion gate,
# dispatch hook, or monitor.
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CREW_DISPATCH="$CONFIG_ROOT/firstmate/crew-dispatch.json"

trace_check() { # <trace-file> <harness> <model> <effort> <skills|none> [<worker-session> [<review-session>]]
  python3 - "$CREW_DISPATCH" "$CONFIG_ROOT/roles" "$@" <<'PY'
import hashlib, json, os, re, sys

dispatch, roles_dir, trace_path, harness, model, effort, skills_arg = sys.argv[1:8]
transcript_path = sys.argv[8] if len(sys.argv) > 8 else None
review_path = sys.argv[9] if len(sys.argv) > 9 else None
# primary-policy.md sections 3-4: two roles are fixed to their categories;
# every other category takes senior-fullstack or any specialist role file.
FIXED_ROLES = {"ARCHITECTURE": "architecture", "TENTH-MAN": "tenth-man"}
# Worker behavior in a retained OMP session record: these tools' calls and
# results, plus a bash background job's delivered output. Brief text,
# assistant prose/thinking, read output, and every other tool are not
# behavior. Eligibility only: what the behavior means is the Captain's call.
BEHAVIOR_TOOLS = {"bash", "eval", "edit", "write", "ast_edit"}
# The first of these calls starts substantive work; a READ must be complete
# before it.
MUTATING_TOOLS = {"edit", "write", "ast_edit"}
READ_STATES = ("complete", "late", "partial", "none")
failed = False

def result(ok, label):
    global failed
    failed |= not ok
    print(("PASS - " if ok else "FAIL - ") + label)

def inspect(label):
    # Located context for an independent assessment: neither a PASS nor a FAIL.
    print("INSPECT - " + label)

def skill_id(token):
    # Absolute (shared/core) skill paths normalize to the skill's name;
    # worktree-relative project-local paths stay distinct from a global
    # skill of the same name.
    token = token.strip().strip("`")  # a Markdown-formatted name is the same skill
    if os.path.isabs(token) and token.endswith("/SKILL.md"):
        return os.path.basename(os.path.dirname(token))
    return token

def skill_source(token, cwd):
    # The exact selected file: an absolute or ~/ path as given, a
    # worktree-relative project-local path under the worker's own worktree
    # (its session cwd), a bare shared skill name under ~/.agents/skills.
    token = os.path.expanduser(token.strip().strip("`"))
    if os.path.isabs(token):
        return token
    if "/" in token:
        return os.path.join(cwd, token)
    return os.path.join(os.path.expanduser("~"), ".agents", "skills", token, "SKILL.md")

def citations(text):
    # Backticked excerpts -> (excerpts, ambiguous). Supported quoting: an
    # excerpt opens with one backtick; inside it, a backtick followed by
    # text opens a nested quote and the next backtick followed by the end,
    # whitespace, or punctuation closes the innermost open quote; a closing
    # double backtick ends a nested quote and the excerpt together, as in the
    # live `Exit code: `1``. So `Exit code: `1`, final` is cited whole, never
    # as a prefix that a different exit code would also match. Anything
    # else (a ``/``` opener, an unclosed quote) is reported ambiguous rather
    # than guessed.
    found, i, n = [], 0, len(text)
    def run_at(k):
        r = 0
        while k + r < n and text[k + r] == "`":
            r += 1
        return r
    def boundary(k):
        return k >= n or text[k].isspace() or text[k] in ".,;:!?)]'\""
    while True:
        start = text.find("`", i)
        if start < 0:
            return found, False
        if run_at(start) != 1:
            return found, True
        j, depth = start + 1, 0
        while True:
            k = text.find("`", j)
            if k < 0:
                return found, True
            r = run_at(k)
            after = k + r
            if r == 1 and not boundary(after):
                depth += 1
            elif r == 1 and depth:
                depth -= 1
            elif r == 1:
                found.append(text[start + 1:k])
                break
            elif r == 2 and depth == 1 and boundary(after):
                found.append(text[start + 1:k + 1])
                break
            else:
                return found, True
            j = after
        i = after

def load_record(path):
    # A retained OMP session record (JSONL under one session header), or
    # None for any other text: prose shaped like a receipt is not one.
    recs = []
    try:
        with open(path, encoding="utf-8") as f:
            for l in f:
                if l.strip():
                    recs.append(json.loads(l))
    except (OSError, ValueError, UnicodeDecodeError):
        return None
    heads = [r for r in recs if isinstance(r, dict) and r.get("type") == "session"]
    if len(heads) != 1 or not isinstance(heads[0].get("cwd"), str):
        return None
    # behavior: (index, timestamp, where, text, order). `order` is the index
    # the behavior started at: a call's own message, a synchronous result's
    # call (never its delivery), and a background job's launching bash call
    # (located by the launch result's details.async.jobId) - None when that
    # launch is not in the record, so its order is unassessed.
    calls, launches, reads, behavior, mutation, brief = {}, {}, [], [], None, None
    for i, r in enumerate(recs):
        if not isinstance(r, dict):
            continue
        ts = r.get("timestamp", "?")
        if r.get("type") == "custom_message" and r.get("customType") == "async-result":
            jobs = (r.get("details") or {}).get("jobs") or []
            if jobs and all(j.get("type") == "bash" for j in jobs) and isinstance(r.get("content"), str):
                started = [launches.get(j.get("jobId")) for j in jobs]
                behavior.append((i, ts, "background bash result", r["content"], None if None in started else max(started)))
            continue
        m = r.get("message") if r.get("type") == "message" else None
        if not isinstance(m, dict):
            continue
        if m.get("role") == "user" and brief is None:
            brief = " ".join("".join(x.get("text", "") for x in m.get("content") or [] if isinstance(x, dict)).split())[:120]
        elif m.get("role") == "assistant":
            for c in m.get("content") or []:
                if not isinstance(c, dict) or c.get("type") != "toolCall":
                    continue
                calls[c.get("id")] = (c, i)
                args = c.get("arguments") if isinstance(c.get("arguments"), dict) else {}
                if c.get("name") in MUTATING_TOOLS and mutation is None:
                    mutation = (i, ts, c.get("name"))
                if c.get("name") in BEHAVIOR_TOOLS:
                    # The "i" intent argument is the worker describing itself.
                    behavior.append((i, ts, "%s call" % c["name"], "\n".join(str(v) for k, v in sorted(args.items()) if k != "i"), i))
        elif m.get("role") == "toolResult":
            call, at = calls.get(m.get("toolCallId"), (None, None))
            if not call or call.get("name") != m.get("toolName"):
                continue
            text = "".join(x.get("text", "") for x in m.get("content") or [] if isinstance(x, dict))
            job = ((m.get("details") or {}).get("async") or {}).get("jobId")
            if m.get("toolName") == "bash" and job:
                launches[job] = at
            if m.get("toolName") == "read":
                if not m.get("isError"):
                    reads.append((i, ts, m.get("toolCallId"), (call.get("arguments") or {}).get("path"), text))
            elif m.get("toolName") in BEHAVIOR_TOOLS:
                behavior.append((i, ts, "%s result" % m["toolName"], text, at))
    return {"path": os.path.realpath(path), "id": heads[0].get("id"), "cwd": heads[0]["cwd"], "started": heads[0].get("timestamp", "?"),
            "brief": brief, "reads": reads, "behavior": behavior, "mutation": mutation}

READ_HEADER = re.compile(r"\[(?:Skill file: (?P<file>.+)|.+#(?P<tag>[0-9A-Za-z]{4}))\]")
SELECTOR = re.compile(r"(?P<path>.*?)(?::-?\d[\d,+-]*)*")

def shown_lines(arg, text, cwd, target, lines):
    # What one successful read result displayed of the selected file:
    # (matching line numbers, mismatching line numbers, tag), or None when
    # it is not a receipt for that exact file. Only the observed OMP shapes
    # count: a `[path#TAG]` header over numbered "N:text" lines (elided and
    # truncated lines are not shown), or a skill:// `[Skill file: path]`
    # header over the whole unnumbered body.
    head, _, body = text.partition("\n")
    h = READ_HEADER.fullmatch(head)
    if not h or not isinstance(arg, str):
        return None
    if arg.startswith("skill://"):
        path = h.group("file")
    else:
        path = os.path.expanduser(SELECTOR.fullmatch(arg).group("path"))
        path = path if os.path.isabs(path) else os.path.join(cwd, path)
    if not path or os.path.realpath(path) != target:
        return None
    if h.group("file"):
        same = body.rstrip("\n") == "\n".join(lines).rstrip("\n")
        return (set(range(1, len(lines) + 1)), set(), "-") if same else (set(), {0}, "-")
    ok, bad = set(), set()
    for l in body.split("\n"):
        n = re.match(r"(\d+):(.*)$", l)
        if n:
            k = int(n.group(1))
            (ok if 1 <= k <= len(lines) and lines[k - 1] == n.group(2) else bad).add(k)
    return ok, bad, h.group("tag")

def read_status(rec, src):
    # READ from the record: complete (every line of the selected file's
    # current bytes shown before the first file-mutating call), late (only
    # after it), partial (some lines, or shown lines that differ from the
    # file), none, or unreadable (the listed path is no readable file, so no
    # receipt can be compared and only UNPROVEN is honest).
    target = os.path.realpath(src)
    try:
        data = open(target, "rb").read()
    except OSError:
        return {"status": "unreadable", "done": None, "target": target, "sha": "unreadable", "covered": 0, "total": 0, "bad": [], "receipts": []}
    lines = data.decode("utf-8", "replace").split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    full = set(range(1, len(lines) + 1))
    covered, bad, receipts, done = set(), set(), [], None
    for i, ts, cid, arg, text in rec["reads"]:
        got = shown_lines(arg, text, rec["cwd"], target, lines)
        if got is None:
            continue
        ok, b, tag = got
        covered |= ok
        bad |= b
        receipts.append("%s %s read %s #%s (%d matching line(s))" % (ts, cid, arg, tag, len(ok)))
        if done is None and not bad and covered >= full:
            done = (i, ts)
    cut = rec["mutation"][0] if rec["mutation"] else None
    if not receipts:
        status = "none"
    elif bad or done is None:
        status = "partial"
    elif cut is not None and done[0] > cut:
        status = "late"
    else:
        status = "complete"
    return {"status": status, "done": done if status == "complete" else None, "target": target,
            "sha": hashlib.sha256(data).hexdigest(), "covered": len(covered & full), "total": len(full),
            "bad": sorted(bad), "receipts": receipts}

def excerpts(name, field, value):
    # [] for UNPROVEN, the one or two cited excerpts, or None after a FAIL.
    if value == "UNPROVEN":
        return []
    cited, ambiguous = citations(value)
    if ambiguous:
        result(False, "%s: ambiguous backtick quoting in %s %r - quote each excerpt as `excerpt`, separated by words or a space" % (name, field, value))
        return None
    if not 1 <= len(cited) <= 2:
        result(False, "%s: %s cites one or two `excerpts` or says UNPROVEN (got %d)" % (name, field, len(cited)))
        return None
    return cited

OUTPUTS = ("bash result", "eval result", "background bash result")

def locate(name, field, rec, c, after, outputs=False):
    # The worker-behavior event holding excerpt c (preferring one whose
    # order follows index `after`) as (order, timestamp, where, context), or
    # None after a FAIL. With `outputs`, only executed output counts: bash,
    # eval, and background-bash results. Edit/write results echo text the
    # worker wrote and are never an observed outcome.
    hits = [h for h in rec["behavior"] if c in h[3] and (not outputs or h[2] in OUTPUTS)]
    if not hits:
        result(False, "%s: %s `%s` occurs in %s of %s (brief text, assistant prose, read output, edit/write echoes and other tools are not %s)" % (
            name, field, c, "a bash, eval, or background-bash result" if outputs else "a tool call or tool result", rec["path"],
            "executed output" if outputs else "behavior"))
        return None
    i, ts, where, text, order = next((h for h in hits if after is not None and h[4] is not None and h[4] > after), hits[0])
    at = text.find(c)
    return order, ts, where, " ".join(text[max(0, at - 80):at + len(c) + 80].split())

lines = open(trace_path, encoding="utf-8").read().splitlines()
routing = [l for l in lines if l.startswith("Routing:")]
skills_lines = [l for l in lines if l.startswith("Skills:")]
if len(routing) != 1 or len(skills_lines) != 1:
    result(False, "block has exactly one Routing: line and one Skills: line (got %d and %d)" % (len(routing), len(skills_lines)))
    sys.exit(1)

fields = [f.strip() for f in routing[0][len("Routing:"):].split("|")]
if len(fields) != 6 or not fields[1].startswith("role ") or not fields[5].startswith("why:"):
    result(False, "Routing line has 'CATEGORY [#n] | role R | harness | model | effort | why: ...' shape")
    sys.exit(1)
head = re.fullmatch(r"(\S+)(?: #(\d+))?", fields[0])
if not head:
    result(False, "Routing starts with 'CATEGORY' or 'CATEGORY #n' only - a free sub-lane label is not verifiable (got %r)" % fields[0])
    sys.exit(1)
category = head.group(1)
rule_no = int(head.group(2)) if head.group(2) else None
role = fields[1][len("role "):].strip()
t_harness, t_model, t_effort, why = fields[2], fields[3], fields[4], fields[5]

result((t_harness, t_model, t_effort) == (harness, model, effort),
       "Routing shows the actual spawn axes %s/%s/%s (trace says %s/%s/%s)" % (harness, model, effort, t_harness, t_model, t_effort))

doc = json.load(open(dispatch))
cat_rules = [r for r in doc["rules"] if r["category"] == category]
result(category == "DEFAULT" or bool(cat_rules), "category %s exists in crew-dispatch.json" % category)
# The sub-lane is identified only by its rule number within the category.
if category == "DEFAULT":
    where, candidates = "the DEFAULT route", doc["default"]
elif rule_no is None and len(cat_rules) > 1:
    result(False, "%s has %d rules, so the trace must name the matched rule as #n" % (category, len(cat_rules)))
    where, candidates = None, []
elif rule_no is not None and not 1 <= rule_no <= len(cat_rules):
    result(False, "%s has no rule #%d (it has %d)" % (category, rule_no, len(cat_rules)))
    where, candidates = None, []
else:
    n = rule_no or 1
    where, candidates = "%s rule #%d's route" % (category, n), cat_rules[n - 1]["use"] if cat_rules else []
if where:
    tuple_ = (t_harness, t_model, t_effort)
    if any((c["harness"], c["model"], c["effort"]) == tuple_ for c in candidates):
        result(True, "%s/%s/%s is %s" % (tuple_ + (where,)))
    elif "captain override" in why.lower():
        result(True, "%s/%s/%s is not %s: accepted as a named captain override" % (tuple_ + (where,)))
    else:
        result(False, "%s/%s/%s is %s (configured: %s)" % (tuple_ + (where, ", ".join(
            "%s/%s/%s" % (c["harness"], c["model"], c["effort"]) for c in candidates))))
if category in FIXED_ROLES:
    result(role == FIXED_ROLES[category], "role %s matches category %s (requires %s)" % (role, category, FIXED_ROLES[category]))
else:
    result(role not in FIXED_ROLES.values() and re.fullmatch(r"[a-z0-9-]+", role) is not None
           and os.path.isfile(os.path.join(roles_dir, role, "ROLE.md")),
           "role %s is senior-fullstack or a specialist role file, valid for category %s" % (role, category))

body = skills_lines[0][len("Skills:"):].strip()
# A reason follows a spaced ASCII hyphen, en dash, or em dash (a real
# Captain printed the em dash); a dash without surrounding spaces belongs
# to the skill id and is left alone.
traced = set() if body == "none" else {skill_id(re.split(" [-\u2013\u2014] ", e, maxsplit=1)[0]) for e in body.split(";") if e.strip()}
selected = set() if skills_arg == "none" else {skill_id(s) for s in skills_arg.split(",") if s.strip()}
result(traced == selected, "Skills names exactly the selected skills %s (trace says %s)" % (sorted(selected) or "none", sorted(traced) or "none"))

if transcript_path is not None:
    starts = [i for i, l in enumerate(lines) if l.startswith("Skill evidence:")]
    if len(starts) != 1:
        result(False, "exactly one Skill evidence: block follows the worker's completion (got %d)" % len(starts))
        sys.exit(1)
    start = starts[0]
    # With no selected skills the header may stand alone or say
    # "none selected" inline, as a live Captain printed it; nothing else.
    inline = lines[start][len("Skill evidence:"):].strip().rstrip(".").lower()
    if inline not in ("", "none", "none selected"):
        result(False, "Skill evidence: header carries nothing inline but 'none selected' (got %r)" % inline)
    entries = []
    for l in lines[start + 1:]:
        m = re.match(r"^- (\S+): (.+)$", l)
        if not m:
            break
        entries.append((skill_id(m.group(1)), m.group(2).strip()))
    if inline in ("none", "none selected") and entries:
        result(False, "Skill evidence: says none selected but lists %d skill line(s)" % len(entries))
    names = [name for name, _ in entries]
    result(len(names) == len(set(names)), "Skill evidence has one line per skill (got %s)" % names)
    result(set(names) == selected,
           "Skill evidence covers exactly the selected skills %s (got %s)" % (sorted(selected) or "none", sorted(set(names)) or "none"))

    # Only an OMP worker's retained record is read; any other harness's
    # record (Pi shares the session header) supports only UNPROVEN.
    rec = load_record(transcript_path) if harness == "omp" else None
    if rec is None:
        inspect("%s is not a retained OMP session record of an omp worker (harness %s): no read receipt, behavior, or result is observable in it; only UNPROVEN fields can pass" % (transcript_path, harness))
    else:
        # Identity for matching the assigned worker: header cwd = its worktree,
        # start after its spawn, first user message = its delivered brief.
        inspect("worker record %s (session %s, started %s, cwd %s, first user message: %r); first edit/write/ast_edit call: %s" % (
            rec["path"], rec["id"], rec["started"], rec["cwd"], rec["brief"], "%s %s" % rec["mutation"][1:] if rec["mutation"] else "none"))
    review_rec = load_record(review_path) if review_path else None
    sources = {} if skills_arg == "none" else {skill_id(s): s for s in skills_arg.split(",") if s.strip()}
    EVIDENCE = re.compile(r"read (\S+) \| applied (.+?) \| result (.+?) \| review (.+?) \| usage (\S+)")
    for name, text in entries:
        m = EVIDENCE.fullmatch(text)
        if not m:
            result(False, "%s: evidence line is 'read <complete|late|partial|none|UNPROVEN> | applied <`excerpt`|UNPROVEN> | result <`excerpt`|UNPROVEN> | review <`excerpt`|UNPROVEN> | usage <verified|UNPROVEN>' (got %r)" % (name, text))
            continue
        if name not in sources:
            continue  # an unselected skill already failed the coverage check
        claim, applied, outcome, review, usage = m.groups()

        # READ: only the record's own successful read results count.
        rs = read_status(rec, skill_source(sources[name], rec["cwd"])) if rec else None
        if claim not in READ_STATES + ("UNPROVEN",):
            result(False, "%s: read is one of %s or UNPROVEN (got %r)" % (name, "/".join(READ_STATES), claim))
        elif rs is None:
            result(claim == "UNPROVEN", "%s: read %s needs a retained OMP session record; without one only UNPROVEN is honest" % (name, claim))
        else:
            detail = "this file only: %d/%d lines of %s (sha256 %s)%s; receipts: %s" % (
                rs["covered"], rs["total"], rs["target"], rs["sha"][:16],
                ", shown lines differing from the file: %s" % rs["bad"] if rs["bad"] else "",
                "; ".join(rs["receipts"]) or "none")
            if claim == "UNPROVEN":
                inspect("%s: read UNPROVEN as reported; the record shows %s: %s" % (name, rs["status"], detail))
            else:
                result(claim == rs["status"], "%s: read %s matches the record (%s): %s" % (name, claim, rs["status"], detail))
        done = rs["done"][0] if rs and rs["done"] else None
        # The edit/write boundary does not see bash/eval writes or the jobs
        # they launch; disclose every such call before the completing read.
        early = sum(1 for h in rec["behavior"] if done is not None and h[0] < done and h[2] in ("bash call", "eval call")) if rec else 0
        if early:
            inspect("%s: %d bash/eval call(s) precede the completing read; writes they made and jobs they launched are not assessed - pre-work order is proven only against edit/write/ast_edit calls" % (name, early))

        # APPLIED and RESULT: located worker behavior, never a semantic PASS.
        # Behavior before a complete pre-work read stays visible with its
        # attribution UNPROVEN.
        after_read, located = {}, {}
        for field, value in (("applied", applied), ("result", outcome)):
            cited = excerpts(name, field, value)
            after_read[field], located[field] = False, 0
            if not cited:
                continue
            if rec is None:
                result(False, "%s: %s excerpts need a retained OMP session record" % (name, field))
                continue
            for c in cited:
                got = locate(name, field, rec, c, done, outputs=field == "result")
                if got is None:
                    continue
                order, ts, where, context = got
                attributed = done is not None and order is not None and order > done
                after_read[field] |= attributed
                located[field] += 1
                inspect("%s: %s `%s` located in %s at %s, %s - location only, semantic application UNPROVEN by this checker: ...%s..." % (
                    name, field, c, where, ts,
                    "after the complete pre-work read" if attributed else "launch order unassessed (job launch not in the record)" if order is None
                    else "attribution UNPROVEN (read %s)" % ("complete, but this precedes it" if done is not None else rs["status"] if rs else "UNPROVEN"),
                    context))

        # REVIEW: a different session record is necessary, never sufficient:
        # reviewer independence and the verdict are not assessed here.
        cited = excerpts(name, "review", review)
        reviewed = 0
        if cited:
            if review_rec is None:
                result(False, "%s: review needs the reviewer's own retained OMP session record as the review-session argument" % name)
            elif rec is not None and (review_rec["id"] == rec["id"] or review_rec["path"] == rec["path"]):
                result(False, "%s: the review record is the worker's own session, not an independent review" % name)
            else:
                for c in cited:
                    got = locate(name, "review", review_rec, c, None)
                    if got:
                        reviewed += 1
                        inspect("%s: review `%s` located in a different session record %s (session %s), %s at %s - reviewer independence and verdict are not assessed by this checker: ...%s..." % (
                            name, c, review_rec["path"], review_rec["id"], got[2], got[1], got[3]))

        # USAGE: necessary links only - a complete pre-work READ, then applied
        # behavior and executed output after it. Located links never make
        # usage verified: semantic application stays UNPROVEN by this checker,
        # and `usage verified` stands only on an independent task-relevant
        # assessment. Review is reported separately.
        missing = [why for ok, why in (
            (done is not None, "a complete pre-work read (record: %s)" % (rs["status"] if rs else "unsupported")),
            (after_read["applied"], "applied behavior located after that read"),
            (after_read["result"], "executed output located after that read")) if not ok]
        if usage not in ("verified", "UNPROVEN"):
            result(False, "%s: usage is verified or UNPROVEN (got %r)" % (name, usage))
        elif usage == "verified" and missing:
            result(False, "%s: usage verified lacks %s" % (name, "; ".join(missing)))
        elif usage == "verified":
            inspect("%s: usage verified is a declaration: its necessary links are located, but semantic application is UNPROVEN by this checker and stands only on an independent task-relevant assessment" % name)
        # What the records support, whatever the line claimed.
        def shown(field):
            if not located[field]:
                return "UNPROVEN"
            return "located" if after_read[field] else "located, attribution UNPROVEN"
        print("SUMMARY - %s: SELECTED yes | READ %s | APPLIED %s | RESULT %s | REVIEW %s | USAGE %s" % (
            name, "%s (this file only)" % rs["status"] if rs else "UNPROVEN (unsupported record)", shown("applied"), shown("result"),
            "located in a different session record" if reviewed else "UNPROVEN",
            "UNPROVEN" if missing else "links located, semantics UNPROVEN by checker"))

sys.exit(1 if failed else 0)
PY
}
if [ "${1:-}" = check ]; then
  shift
  [ "$#" -ge 5 ] || { printf 'usage: %s check <trace-file> <harness> <model> <effort> <skills|none> [<worker-session> [<review-session>]]\n' "$0" >&2; exit 2; }
  trace_check "$@"
  exit $?
fi

command -v python3 >/dev/null 2>&1 || { printf 'SKIP - routing trace: python3 is required\n\nROUTING TRACE TESTS SKIPPED\n'; exit 0; }

failed=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; failed=1; }
expect() { # <label> <pass|fail> <trace-check args...>
  local label=$1 want=$2 out rc
  shift 2
  out=$(trace_check "$@" 2>&1); rc=$?
  if { [ "$want" = pass ] && [ "$rc" -eq 0 ]; } || { [ "$want" = fail ] && [ "$rc" -eq 1 ]; }; then
    pass "$label"
  else
    fail "$label (expected $want, exit $rc): $(printf '%s' "$out" | grep FAIL | head -3 | tr '\n' ' ')"
  fi
}
expect_shows() { # <label> <needle> <trace-check args...> - passes, and prints <needle> for a human
  local label=$1 needle=$2 out rc
  shift 2
  out=$(trace_check "$@" 2>&1); rc=$?
  case $out in
    *"$needle"*) [ "$rc" -eq 0 ] && pass "$label" || fail "$label (exit $rc)" ;;
    *) fail "$label (output never shows '$needle')" ;;
  esac
}
expect_rejects() { # <label> <FAIL needle> <trace-check args...> - fails, and for the stated reason
  local label=$1 needle=$2 out rc
  shift 2
  out=$(trace_check "$@" 2>&1); rc=$?
  case $out in
    *"$needle"*) [ "$rc" -eq 1 ] && pass "$label" || fail "$label (exit $rc)" ;;
    *) fail "$label (no '$needle' in: $(printf '%s' "$out" | grep FAIL | tr '\n' ' '))" ;;
  esac
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-routing-trace.XXXXXX") || exit 1
TMP=$(cd "$TMP" && pwd)
SEAM_TMUX=''
SEAM_ID=fm-trace-seam-$$
cleanup() {
  if [ -n "$SEAM_TMUX" ]; then
    TMUX_TMPDIR="$SEAM_TMUX" tmux kill-server >/dev/null 2>&1 || true
    sleep 0.3
    rm -rf "$SEAM_TMUX"
  fi
  # fm-spawn also creates its launch dir at /tmp/fm-<id>+<home-token>.
  rm -rf "/tmp/fm-$SEAM_ID" "/tmp/fm-$SEAM_ID+"* "$TMP"
}
trap cleanup EXIT
t() { printf '%s\n' "$2" > "$TMP/$1"; printf '%s' "$TMP/$1"; }

OPUS=anthropic/claude-opus-5-5
SONNET=anthropic/claude-sonnet-5-5
SOL=openai-codex/gpt-6.1-sol
TDD=test-driven-development
VBC=verification-before-completion

# --- 1. Routing summary reflects the actual spawn axes ----------------------
IMPL=$(t impl.txt "Routing: IMPLEMENT #2 | role senior-fullstack | omp | $OPUS | high | why: multi-file behavior change
Skills: $TDD - behavior change needs failing-first tests; $VBC - completion claim needs fresh evidence")
expect 'substantive IMPLEMENT trace matches its spawn axes' pass "$IMPL" omp "$OPUS" high "$TDD,$VBC"
expect 'trace naming Opus while the worker actually ran Sonnet is rejected' fail "$IMPL" omp "$SONNET" high "$TDD,$VBC"
expect 'trace effort differing from the actual spawn effort is rejected' fail "$IMPL" omp "$OPUS" xhigh "$TDD,$VBC"
expect 'trace harness differing from the actual spawn harness is rejected' fail "$IMPL" pi "$OPUS" high "$TDD,$VBC"

BOUNDED=$(t bounded.txt "Routing: IMPLEMENT #1 | role senior-fullstack | omp | $SONNET | high | why: one-function fix
Skills: $TDD - bug fix")
expect 'bounded IMPLEMENT on Sonnet 5.5 high is an allowed route' pass "$BOUNDED" omp "$SONNET" high "$TDD"

HAIKU_IMPL=$(t haiku-impl.txt "Routing: IMPLEMENT #1 | role senior-fullstack | omp | anthropic/claude-haiku-4-5 | low | why: cheap
Skills: none")
expect 'a model/effort outside the named category rules is rejected' fail "$HAIKU_IMPL" omp anthropic/claude-haiku-4-5 low none
OVERRIDE=$(t override.txt "Routing: IMPLEMENT #1 | role senior-fullstack | omp | anthropic/claude-haiku-4-5 | low | why: captain override - captain asked for Haiku
Skills: none")
expect 'an explicit captain override outside the rules is accepted when the why names it' pass "$OVERRIDE" omp anthropic/claude-haiku-4-5 low none

DEFAULT=$(t default.txt "Routing: DEFAULT | role senior-fullstack | omp | $OPUS | high | why: no specific category fits
Skills: none")
expect 'DEFAULT trace on Opus 5.5 high matches the debug-period catch-all' pass "$DEFAULT" omp "$OPUS" high none

TENTH=$(t tenth.txt "Routing: TENTH-MAN #1 | role tenth-man | pi | $SOL | xhigh | why: challenge Claude-authored completion claim
Skills: none")
expect 'TENTH-MAN against Claude output on Pi GPT-6.1 Sol xhigh is accepted' pass "$TENTH" pi "$SOL" xhigh none
ARCH_WRONG_ROLE=$(t arch-role.txt "Routing: ARCHITECTURE #1 | role senior-fullstack | omp | $OPUS | high | why: module boundary
Skills: none")
expect 'ARCHITECTURE trace must name role architecture' fail "$ARCH_WRONG_ROLE" omp "$OPUS" high none

# Specialist roles (primary-policy.md section 4) ride any non-fixed category
# as role files; architecture/tenth-man stay fixed to their own categories.
SEC=$(t sec-role.txt "Routing: REVIEW #2 | role security-engineer | omp | $OPUS | high | why: authz audit of one service
Skills: security-and-hardening - role default; $VBC - role default")
expect 'a specialist role file on a non-fixed category is accepted' pass "$SEC" omp "$OPUS" high "security-and-hardening,$VBC"
UNKNOWN_ROLE=$(t unknown-role.txt "Routing: REVIEW #2 | role pentester | omp | $OPUS | high | why: authz audit
Skills: none")
expect_rejects 'a role with no role file is rejected' 'FAIL - role pentester' "$UNKNOWN_ROLE" omp "$OPUS" high none
ARCH_SPECIALIST=$(t arch-specialist.txt "Routing: ARCHITECTURE #1 | role refactorist | omp | $OPUS | high | why: module boundary
Skills: none")
expect_rejects 'a specialist role cannot replace the fixed ARCHITECTURE role' 'FAIL - role refactorist' "$ARCH_SPECIALIST" omp "$OPUS" high none
FIXED_ELSEWHERE=$(t fixed-elsewhere.txt "Routing: IMPLEMENT #1 | role tenth-man | omp | $SONNET | high | why: one-function fix
Skills: none")
expect_rejects 'a fixed role is rejected outside its own category' 'FAIL - role tenth-man' "$FIXED_ELSEWHERE" omp "$SONNET" high none
MISSING=$(t missing.txt "Skills: none")
expect 'a block without a Routing line is rejected' fail "$MISSING" omp "$OPUS" high none

# Sub-lane identity: a multi-rule category's trace names the matched rule
# (#n, 1-based within the category, pinned by tests/routing-taxonomy.sh),
# and the axes must be that rule's own route - never merely some route of
# the category, and no unverifiable free-text sub-lane label may follow it
# (review findings: "REVIEW critical" and "REVIEW #1 critical" on Sonnet
# high both passed).
REVIEW_NO_RULE=$(t rev-norule.txt "Routing: REVIEW | role senior-fullstack | omp | $SONNET | high | why: release-critical security diff
Skills: none")
expect 'a multi-rule category trace without its matched rule #n is rejected' fail "$REVIEW_NO_RULE" omp "$SONNET" high none
REVIEW_CRIT_SONNET=$(t rev-crit-sonnet.txt "Routing: REVIEW #3 | role senior-fullstack | omp | $SONNET | high | why: release-critical security diff
Skills: none")
expect 'critical REVIEW (#3) displayed on Sonnet 5.5 high contradicts its Opus 5.5 xhigh route and is rejected' fail "$REVIEW_CRIT_SONNET" omp "$SONNET" high none
REVIEW_CRIT_OPUS=$(t rev-crit-opus.txt "Routing: REVIEW #3 | role senior-fullstack | omp | $OPUS | xhigh | why: release-critical security diff
Skills: none")
expect 'critical REVIEW (#3) on Opus 5.5 xhigh is accepted' pass "$REVIEW_CRIT_OPUS" omp "$OPUS" xhigh none
REVIEW_BOUNDED=$(t rev-bounded.txt "Routing: REVIEW #1 | role senior-fullstack | omp | $SONNET | high | why: one-file diff
Skills: none")
expect 'bounded REVIEW (#1) on Sonnet 5.5 high is accepted' pass "$REVIEW_BOUNDED" omp "$SONNET" high none
REVIEW_CRIT_OVERRIDE=$(t rev-crit-override.txt "Routing: REVIEW #3 | role senior-fullstack | omp | $SONNET | high | why: captain override - captain chose Sonnet for this critical review
Skills: none")
expect_shows 'a named captain override of critical REVIEW is accepted and reported as an override' 'captain override' \
  "$REVIEW_CRIT_OVERRIDE" omp "$SONNET" high none
REVIEW_BAD_RULE=$(t rev-badrule.txt "Routing: REVIEW #9 | role senior-fullstack | omp | $OPUS | xhigh | why: x
Skills: none")
expect 'a rule number the category does not have is rejected' fail "$REVIEW_BAD_RULE" omp "$OPUS" xhigh none
FALSE_CRIT_LABEL=$(t rev-false-crit.txt "Routing: REVIEW #1 critical | role senior-fullstack | omp | $SONNET | high | why: release-critical security diff
Skills: none")
expect 'a free sub-lane label after #n (REVIEW #1 critical on Sonnet high) is rejected' fail "$FALSE_CRIT_LABEL" omp "$SONNET" high none
FALSE_BOUNDED_LABEL=$(t rev-false-bounded.txt "Routing: REVIEW #3 bounded | role senior-fullstack | omp | $OPUS | xhigh | why: release-critical security diff
Skills: none")
expect 'a free sub-lane label after #n (REVIEW #3 bounded on Opus xhigh) is rejected' fail "$FALSE_BOUNDED_LABEL" omp "$OPUS" xhigh none

# --- 2. Skills summary reflects exactly the selected skills -----------------
expect 'Skills naming an unselected, merely installed skill is rejected' fail "$IMPL" omp "$OPUS" high "$TDD"
expect 'Skills omitting a selected skill is rejected' fail "$BOUNDED" omp "$SONNET" high "$TDD,$VBC"
expect 'zero selected skills with "Skills: none" is valid' pass "$DEFAULT" omp "$OPUS" high none
expect 'absolute shared-skill paths from the brief normalize to their names' pass "$IMPL" omp "$OPUS" high "$HOME/.agents/skills/$TDD/SKILL.md,$HOME/.agents/skills/$VBC/SKILL.md"
PROJECT=$(t project.txt "Routing: REVIEW #2 | role senior-fullstack | omp | $OPUS | high | why: cross-component diff
Skills: .agents/skills/architecture-review/SKILL.md - project-local version wins; ponytail-review - complexity check")
expect 'a project-local skill path and a core skill are reported as selected' pass "$PROJECT" omp "$OPUS" high '.agents/skills/architecture-review/SKILL.md,ponytail-review'
GLOBAL_SWAP=$(t swap.txt "Routing: REVIEW #2 | role senior-fullstack | omp | $OPUS | high | why: cross-component diff
Skills: architecture-review - global default; ponytail-review - complexity check")
expect 'substituting the global skill for the selected project-local one is rejected' fail "$GLOBAL_SWAP" omp "$OPUS" high '.agents/skills/architecture-review/SKILL.md,ponytail-review'
# The reason separator in "Skills: <skill> - <reason>" may be a spaced
# ASCII hyphen or en dash (the em dash a real Captain printed is covered
# just below). Hyphens inside a skill id are never separators, and the
# separator must not change which routes, roles or skills are accepted.
for SEP in ' - ' ' – '; do
  SEP_TRACE=$(t "sep-$RANDOM.txt" "Routing: IMPLEMENT #2 | role senior-fullstack | omp | $OPUS | high | why: multi-file behavior change
Skills: $TDD${SEP}behavior change needs failing-first tests; $VBC${SEP}completion claim needs fresh evidence")
  expect "the '${SEP# }' reason separator is accepted for two hyphenated skill ids" pass "$SEP_TRACE" omp "$OPUS" high "$TDD,$VBC"
  expect "with '${SEP# }' a missing selected skill is still rejected" fail "$SEP_TRACE" omp "$OPUS" high "$TDD,$VBC,ponytail-review"
  expect "with '${SEP# }' an unselected skill is still rejected" fail "$SEP_TRACE" omp "$OPUS" high "$TDD"
  expect "with '${SEP# }' the wrong route is still rejected" fail "$SEP_TRACE" omp "$SONNET" high "$TDD,$VBC"
done
expect 'a single em-dash entry with a project-local path is accepted' pass \
  "$(t sep-project.txt "Routing: REVIEW #2 | role senior-fullstack | omp | $OPUS | high | why: cross-component diff
Skills: .agents/skills/architecture-review/SKILL.md — project-local version wins")" omp "$OPUS" high '.agents/skills/architecture-review/SKILL.md'
expect 'an unspaced dash stays part of the skill id (only spaced dashes separate the reason)' pass \
  "$(t sep-unspaced.txt "Routing: IMPLEMENT #2 | role senior-fullstack | omp | $OPUS | high | why: x
Skills: odd–id — reason")" omp "$OPUS" high 'odd–id'
# The real Captain printed `Skills:` reasons after an em dash (2026-10-05,
# REVIEW #3 trace); the selected name must still parse, and the same shape
# must still reject an unselected skill.
EM_DASH=$(t em-dash.txt "Routing: REVIEW #3 | role code-reviewer | omp | $OPUS | xhigh | why: supervision identity risk
Skills: $VBC — ground the review in executed evidence")
expect 'an em-dash Skills reason, as the real Captain printed it, names the selected skill' pass "$EM_DASH" omp "$OPUS" xhigh "$VBC"
expect 'an em-dash Skills reason still rejects a different selection' fail "$EM_DASH" omp "$OPUS" xhigh "$TDD"
# Skills entries are separated by `;` (primary-policy.md section 0): a
# semicolon inside a reason invents a second skill; commas are words.
expect_rejects 'a semicolon inside a genuine shared skill reason invents a second skill and is rejected' 'Skills names exactly the selected skills' \
  "$(t reason-semicolon.txt "Routing: IMPLEMENT #2 | role senior-fullstack | omp | $OPUS | high | why: x
Skills: $VBC - fresh evidence before done; then report it")" omp "$OPUS" high "$VBC"
expect 'commas inside a shared skill reason are accepted' pass \
  "$(t reason-comma.txt "Routing: IMPLEMENT #2 | role senior-fullstack | omp | $OPUS | high | why: x
Skills: $VBC - fresh evidence before done, then report it")" omp "$OPUS" high "$VBC"

# --- 3. Post-work Skill evidence: SELECTED / READ / APPLIED / VERIFIED ------
# Evidence is checked against the worker's retained OMP session record
# (JSONL). omp-record appends records in that exact retained shape - an
# assistant toolCall, its toolResult (read results carry the `[path#TAG]`
# header and numbered lines; a truncated read ends with the real
# "[Showing lines a-b of N. Use :b+1 to continue]" footer), a bash
# background-job async-result, user brief text, assistant prose - so each
# fixture is a record a real worker could leave, never prose pretending
# to be a receipt.
cat > "$TMP/omp-record.py" <<'PY'
import hashlib, json, os, sys
path, kind, args = sys.argv[1], sys.argv[2], sys.argv[3:]
n = sum(1 for _ in open(path)) if os.path.exists(path) else 0
def ts(k):
    return "2026-10-05T07:%02d:%02d.000Z" % divmod(n + k, 60)
def emit(*recs):
    with open(path, "a") as f:
        for r in recs:
            f.write(json.dumps(r) + "\n")
def message(k, role, **fields):
    return {"type": "message", "id": "m%d" % (n + k), "timestamp": ts(k), "message": dict(role=role, timestamp=ts(k), **fields)}
def tool(name, arguments, text, error=False, details=None):
    cid = "toolu_%d" % n
    emit(message(0, "assistant", content=[{"type": "toolCall", "id": cid, "name": name, "arguments": dict(arguments, i="intent text")}]),
         message(1, "toolResult", toolCallId=cid, toolName=name, content=[{"type": "text", "text": text}], details=details or {}, isError=error))
def read_text(arg, shown, first=None, last=None):
    lines = open(shown).read().split("\n")[:-1]
    first, last = first or 1, last or len(lines)
    body = ["%d:%s" % (k, lines[k - 1]) for k in range(first, last + 1)]
    if last < len(lines):
        body += ["", "[Showing lines %d-%d of %d. Use :%d to continue]" % (first, last, len(lines), last + 1)]
    head = "[%s#%s]" % (arg.split(":")[0].replace(os.path.expanduser("~"), "~"), hashlib.sha256(open(shown, "rb").read()).hexdigest()[:4].upper())
    return "\n".join([head] + body), len(lines)
if kind == "session":
    emit({"type": "session", "version": 3, "id": hashlib.sha256(path.encode()).hexdigest()[:32], "timestamp": ts(0), "cwd": args[0]})
elif kind == "user":
    emit(message(0, "user", content=[{"type": "text", "text": args[0]}]))
elif kind == "say":
    emit(message(0, "assistant", content=[{"type": "text", "text": args[0]}]))
elif kind == "read":  # <path argument> <file shown> [<first> <last>]
    text, total = read_text(*args[:2], *(int(a) for a in args[2:4]))
    tool("read", {"path": args[0]}, text, details={"totalLines": total})
elif kind == "parallel":  # <read path argument> <file shown> <bash command> <bash output> - one message issues both calls
    text, total = read_text(args[0], args[1])
    emit(message(0, "assistant", content=[{"type": "toolCall", "id": "toolu_r%d" % n, "name": "read", "arguments": {"path": args[0], "i": "intent text"}},
                                          {"type": "toolCall", "id": "toolu_b%d" % n, "name": "bash", "arguments": {"command": args[2], "i": "intent text"}}]),
         message(1, "toolResult", toolCallId="toolu_r%d" % n, toolName="read", content=[{"type": "text", "text": text}], details={"totalLines": total}, isError=False),
         message(2, "toolResult", toolCallId="toolu_b%d" % n, toolName="bash", content=[{"type": "text", "text": args[3]}], details={}, isError=False))
elif kind == "read-error":
    tool("read", {"path": args[0]}, "Path '%s' not found" % args[0], error=True)
elif kind == "tool":  # <name> <command or input> <output>
    tool(args[0], {"command" if args[0] == "bash" else "input": args[1]}, args[2])
elif kind == "bg":  # <command> - a bash call backgrounded as job bg_1 (real launch shape)
    tool("bash", {"command": args[0], "async": True},
         "Backgrounded as job bg_1 (killed once it has run 300s in total; `timeout: 0` disables the deadline)",
         details={"async": {"state": "running", "jobId": "bg_1", "type": "bash"}, "timeoutSeconds": 300})
elif kind == "job":  # a background bash job's delivered output
    emit({"type": "custom_message", "customType": "async-result", "id": "c%d" % n, "timestamp": ts(0), "display": True, "attribution": "agent",
          "content": "<system-notice>\nBackground job bg_1 has completed.\n%s\n</system-notice>" % args[0],
          "details": {"meta": {"source": {"type": "report", "value": "background job delivery"}}, "jobs": [{"jobId": "bg_1", "type": "bash", "label": "job"}]}})
PY
rec() { python3 "$TMP/omp-record.py" "$@"; }

# Selected shared skills resolve by name under the shared root
# ~/.agents/skills (primary-policy.md section 2); HOME points at a fixture.
EVHOME="$TMP/evhome"
SK="$EVHOME/.agents/skills"
mkdir -p "$SK/$TDD" "$SK/$VBC" "$TMP/wt/.agents/skills/local-check" "$TMP/elsewhere/$TDD"
printf -- '---\nname: %s\ndescription: fixture\n---\n# TDD\nWrite the failing test first.\nWatch it fail.\nWrite minimal code.\nWatch it pass.\nRefactor.\nRepeat.\nDone.\n' "$TDD" > "$SK/$TDD/SKILL.md"
printf -- '---\nname: %s\ndescription: fixture\n---\nEvidence before claims.\n' "$VBC" > "$SK/$VBC/SKILL.md"
printf -- '---\nname: local-check\ndescription: fixture project skill\n---\nRun ./check.sh before done.\n' > "$TMP/wt/.agents/skills/local-check/SKILL.md"
cp "$SK/$TDD/SKILL.md" "$TMP/elsewhere/$TDD/SKILL.md"
ev() { HOME="$EVHOME" "$@"; }
# ev_block <file> <tdd line> [<vbc line>] - the IMPL trace plus its Skill evidence
ev_block() {
  t "$1" "$(cat "$IMPL")
Skill evidence:
- $TDD: $2
- $VBC: ${3:-read UNPROVEN | applied UNPROVEN | result UNPROVEN | review UNPROVEN | usage UNPROVEN}"
}
BRIEF_TEXT="Selected shared worker skill: $TDD. Requirement: read and apply; run \`bash tests/red.sh\` and expect \`FAIL expected\`."

# W_GOOD: brief, complete pre-work read of the selected TDD skill, RED run,
# the fix, GREEN run, then the worker's own claim.
W_GOOD="$TMP/w-good.jsonl"
rec "$W_GOOD" session "$TMP/wt"
rec "$W_GOOD" user "$BRIEF_TEXT"
rec "$W_GOOD" read "$SK/$TDD/SKILL.md" "$SK/$TDD/SKILL.md"
rec "$W_GOOD" tool bash 'bash tests/red.sh' 'not ok - rejects empty email
FAIL expected'
rec "$W_GOOD" tool edit 'src/form.py: reject empty email' 'Updated src/form.py'
rec "$W_GOOD" tool bash 'bash tests/red.sh' 'ok - rejects empty email
PASS all'
rec "$W_GOOD" say "I applied $TDD throughout and saw PASS all."
VERIFIED_LINE='read complete | applied ran `bash tests/red.sh` and saw `FAIL expected` | result `PASS all` | review UNPROVEN | usage verified'
ev expect 'a complete pre-work read, behavior after it, and executed output locate every link a usage-verified declaration needs' pass \
  "$(ev_block ev-good.txt "$VERIFIED_LINE")" omp "$OPUS" high "$TDD,$VBC" "$W_GOOD"

# READ: missing receipt. The skill is named only in the brief and the
# worker's claim; real behavior stays reportable, attribution UNPROVEN.
W_UNREAD="$TMP/w-unread.jsonl"
rec "$W_UNREAD" session "$TMP/wt"
rec "$W_UNREAD" user "$BRIEF_TEXT"
rec "$W_UNREAD" tool bash 'bash tests/red.sh' 'not ok - rejects empty email
FAIL expected'
rec "$W_UNREAD" tool edit 'src/form.py: reject empty email' 'Updated src/form.py'
rec "$W_UNREAD" tool bash 'bash tests/red.sh' 'ok - rejects empty email
PASS all'
rec "$W_UNREAD" say "I read $TDD/SKILL.md and applied it."
ev expect 'no read receipt: claiming the selected skill was read is rejected' fail \
  "$(ev_block ev-unread-claim.txt "$VERIFIED_LINE")" omp "$OPUS" high "$TDD,$VBC" "$W_UNREAD"
ev expect 'no read receipt: claiming verified usage is rejected even when the behavior and result are real' fail \
  "$(ev_block ev-unread-usage.txt 'read none | applied ran `bash tests/red.sh` and saw `FAIL expected` | result `PASS all` | review UNPROVEN | usage verified')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_UNREAD"
ev expect_shows 'no read receipt: real behavior is still shown, with its attribution UNPROVEN' 'attribution UNPROVEN' \
  "$(ev_block ev-unread-honest.txt 'read none | applied ran `bash tests/red.sh` and saw `FAIL expected` | result `PASS all` | review UNPROVEN | usage UNPROVEN')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_UNREAD"

# READ: partial receipt (a truncated read never continued).
W_PARTIAL="$TMP/w-partial.jsonl"
rec "$W_PARTIAL" session "$TMP/wt"
rec "$W_PARTIAL" read "$SK/$TDD/SKILL.md" "$SK/$TDD/SKILL.md" 1 8
rec "$W_PARTIAL" tool bash 'bash tests/red.sh' 'FAIL expected'
rec "$W_PARTIAL" tool edit 'src/form.py: fix' 'Updated src/form.py'
rec "$W_PARTIAL" tool bash 'bash tests/red.sh' 'PASS all'
ev expect 'a truncated read is not reported as a complete read' fail \
  "$(ev_block ev-partial.txt "$VERIFIED_LINE")" omp "$OPUS" high "$TDD,$VBC" "$W_PARTIAL"
ev expect 'a truncated read honestly reported as partial is accepted without verified usage' pass \
  "$(ev_block ev-partial-honest.txt 'read partial | applied ran `bash tests/red.sh` and saw `FAIL expected` | result `PASS all` | review UNPROVEN | usage UNPROVEN')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_PARTIAL"

# READ: explicitly read ranges aggregate into one complete receipt.
W_RANGES="$TMP/w-ranges.jsonl"
rec "$W_RANGES" session "$TMP/wt"
rec "$W_RANGES" read "$SK/$TDD/SKILL.md" "$SK/$TDD/SKILL.md" 1 8
rec "$W_RANGES" read "$SK/$TDD/SKILL.md:9-12" "$SK/$TDD/SKILL.md" 9 12
rec "$W_RANGES" tool bash 'bash tests/red.sh' 'FAIL expected'
rec "$W_RANGES" tool edit 'src/form.py: fix' 'Updated src/form.py'
rec "$W_RANGES" tool bash 'bash tests/red.sh' 'PASS all'
ev expect 'two pre-work reads that together cover the whole skill are a complete read' pass \
  "$(ev_block ev-ranges.txt "$VERIFIED_LINE")" omp "$OPUS" high "$TDD,$VBC" "$W_RANGES"

# READ ORDER: the continuation arrives only after the first file edit.
W_LATE="$TMP/w-late.jsonl"
rec "$W_LATE" session "$TMP/wt"
rec "$W_LATE" read "$SK/$TDD/SKILL.md" "$SK/$TDD/SKILL.md" 1 8
rec "$W_LATE" tool bash 'bash tests/red.sh' 'FAIL expected'
rec "$W_LATE" tool edit 'src/form.py: fix' 'Updated src/form.py'
rec "$W_LATE" read "$SK/$TDD/SKILL.md:9-12" "$SK/$TDD/SKILL.md" 9 12
rec "$W_LATE" tool bash 'bash tests/red.sh' 'PASS all'
ev expect 'coverage completed only after substantive work started is not a complete pre-work read' fail \
  "$(ev_block ev-late.txt "$VERIFIED_LINE")" omp "$OPUS" high "$TDD,$VBC" "$W_LATE"
ev expect 'a late read cannot back verified usage' fail \
  "$(ev_block ev-late-usage.txt 'read late | applied `bash tests/red.sh` | result `PASS all` | review UNPROVEN | usage verified')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_LATE"
ev expect 'a late read honestly reported as late is accepted' pass \
  "$(ev_block ev-late-honest.txt 'read late | applied `bash tests/red.sh` | result `PASS all` | review UNPROVEN | usage UNPROVEN')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_LATE"

# SOURCE IDENTITY: a same-named SKILL.md elsewhere, a failed read, and a
# selected file whose bytes differ from what was shown are not receipts.
W_ELSEWHERE="$TMP/w-elsewhere.jsonl"
rec "$W_ELSEWHERE" session "$TMP/wt"
rec "$W_ELSEWHERE" read "$TMP/elsewhere/$TDD/SKILL.md" "$TMP/elsewhere/$TDD/SKILL.md"
rec "$W_ELSEWHERE" read-error "$SK/$TDD/SKILL.md"
rec "$W_ELSEWHERE" tool bash 'bash tests/red.sh' 'FAIL expected'
rec "$W_ELSEWHERE" tool edit 'src/form.py: fix' 'Updated src/form.py'
rec "$W_ELSEWHERE" tool bash 'bash tests/red.sh' 'PASS all'
ev expect 'reading a same-named SKILL.md at another path, or a failed read, is no receipt for the selected one' fail \
  "$(ev_block ev-elsewhere.txt "$VERIFIED_LINE")" omp "$OPUS" high "$TDD,$VBC" "$W_ELSEWHERE"
# Same path, bytes changed after the read: the receipt no longer shows the
# selected file's content, so the identical record stops being complete.
H2="$TMP/evhome2"
mkdir -p "$H2/.agents/skills/$TDD" && cp "$SK/$TDD/SKILL.md" "$H2/.agents/skills/$TDD/SKILL.md"
W_CHANGED="$TMP/w-changed.jsonl"
rec "$W_CHANGED" session "$TMP/wt"
rec "$W_CHANGED" read "$H2/.agents/skills/$TDD/SKILL.md" "$H2/.agents/skills/$TDD/SKILL.md"
rec "$W_CHANGED" tool bash 'bash tests/red.sh' 'FAIL expected'
rec "$W_CHANGED" tool edit 'src/form.py: fix' 'Updated src/form.py'
rec "$W_CHANGED" tool bash 'bash tests/red.sh' 'PASS all'
CHANGED_ARGS=("$(ev_block ev-changed.txt "$VERIFIED_LINE")" omp "$OPUS" high "$H2/.agents/skills/$TDD/SKILL.md,$VBC" "$W_CHANGED")
ev expect 'content identity control: the receipt matches the unchanged selected file' pass "${CHANGED_ARGS[@]}"
sed -i.bak 's/Watch it fail\./Skip the failing run./' "$H2/.agents/skills/$TDD/SKILL.md"
ev expect 'a receipt whose shown lines differ from the selected file bytes is not a complete read' fail "${CHANGED_ARGS[@]}"

# A project-local selection resolves against the worker's own worktree (the
# session cwd); the same body read from elsewhere never stands in for it.
LOCAL=.agents/skills/local-check/SKILL.md
W_LOCAL="$TMP/w-local.jsonl"
rec "$W_LOCAL" session "$TMP/wt"
rec "$W_LOCAL" read "$LOCAL" "$TMP/wt/$LOCAL"
rec "$W_LOCAL" tool bash './check.sh' 'CHECK OK'
LOCAL_BLOCK=$(t ev-local.txt "Routing: REVIEW #2 | role senior-fullstack | omp | $OPUS | high | why: cross-component diff
Skills: $LOCAL - project check
Skill evidence:
- $LOCAL: read complete | applied ran \`./check.sh\` | result \`CHECK OK\` | review UNPROVEN | usage verified")
ev expect 'a worktree-relative project-local skill read in the worker worktree is a complete read' pass \
  "$LOCAL_BLOCK" omp "$OPUS" high "$LOCAL" "$W_LOCAL"
W_LOCAL_ELSE="$TMP/w-local-else.jsonl"
rec "$W_LOCAL_ELSE" session "$TMP/elsewhere"
mkdir -p "$TMP/elsewhere/.agents/skills/local-check" && cp "$TMP/wt/$LOCAL" "$TMP/elsewhere/$LOCAL"
rec "$W_LOCAL_ELSE" read "$TMP/wt/$LOCAL" "$TMP/wt/$LOCAL"
rec "$W_LOCAL_ELSE" tool bash './check.sh' 'CHECK OK'
ev expect 'reading the primary/other checkout copy is no receipt for the worker worktree skill' fail \
  "$LOCAL_BLOCK" omp "$OPUS" high "$LOCAL" "$W_LOCAL_ELSE"

# APPLIED / RESULT sources: mention, self-report, quoted brief or plan text
# is not behavior; only the worker's own tool calls and their output are.
W_QUOTED="$TMP/w-quoted.jsonl"
rec "$W_QUOTED" session "$TMP/wt"
rec "$W_QUOTED" user "$BRIEF_TEXT Then expect \`PASS all\`."
rec "$W_QUOTED" read "$SK/$TDD/SKILL.md" "$SK/$TDD/SKILL.md"
printf 'Plan: run bash tests/red.sh, see FAIL expected, then PASS all.\n' > "$TMP/plan.md"
rec "$W_QUOTED" read "$TMP/plan.md" "$TMP/plan.md"
rec "$W_QUOTED" tool edit 'src/form.py: fix' 'Updated src/form.py'
rec "$W_QUOTED" say 'I ran `bash tests/red.sh`, saw FAIL expected, then PASS all.'
ev expect 'applied evidence found only in the brief, a read plan, or the worker prose is rejected' fail \
  "$(ev_block ev-quoted-applied.txt 'read complete | applied ran `bash tests/red.sh` and saw `FAIL expected` | result UNPROVEN | review UNPROVEN | usage UNPROVEN')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_QUOTED"
ev expect 'a result found only in the brief, a read plan, or the worker prose is rejected' fail \
  "$(ev_block ev-quoted-result.txt 'read complete | applied `src/form.py: fix` | result `PASS all` | review UNPROVEN | usage UNPROVEN')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_QUOTED"

# APPLIED ORDER: behavior before the receipt is shown but is not attributable.
W_BEFORE="$TMP/w-before.jsonl"
rec "$W_BEFORE" session "$TMP/wt"
rec "$W_BEFORE" tool bash 'bash tests/red.sh' 'FAIL expected'
rec "$W_BEFORE" read "$SK/$TDD/SKILL.md" "$SK/$TDD/SKILL.md"
rec "$W_BEFORE" tool edit 'src/form.py: fix' 'Updated src/form.py'
rec "$W_BEFORE" bg 'bash tests/all.sh'
rec "$W_BEFORE" job 'ok - rejects empty email
PASS all'
ev expect 'verified usage whose only applied evidence predates the read receipt is rejected' fail \
  "$(ev_block ev-before.txt 'read complete | applied ran `bash tests/red.sh` and saw `FAIL expected` | result `PASS all` | review UNPROVEN | usage verified')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_BEFORE"
ev expect 'post-receipt behavior and a job launched after the read locate every link a usage-verified declaration needs' pass \
  "$(ev_block ev-before-ok.txt 'read complete | applied `src/form.py: fix` | result `PASS all` | review UNPROVEN | usage verified')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_BEFORE"
# A background job runs from its launch, not its delivery: launched before
# the read and delivered after it, its output cannot follow the read.
W_EARLYJOB="$TMP/w-earlyjob.jsonl"
rec "$W_EARLYJOB" session "$TMP/wt"
rec "$W_EARLYJOB" bg 'bash tests/red.sh'
rec "$W_EARLYJOB" read "$SK/$TDD/SKILL.md" "$SK/$TDD/SKILL.md"
rec "$W_EARLYJOB" tool edit 'src/form.py: fix' 'Updated src/form.py'
rec "$W_EARLYJOB" job 'ok - rejects empty email
PASS all'
ev expect 'a background result launched before the read, delivered after it, cannot back verified usage' fail \
  "$(ev_block ev-earlyjob.txt 'read complete | applied `src/form.py: fix` | result `PASS all` | review UNPROVEN | usage verified')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_EARLYJOB"
# The edit/write boundary does not see bash writes: a complete read that
# finishes after bash calls says how many preceded it.
W_BASHFIRST="$TMP/w-bashfirst.jsonl"
rec "$W_BASHFIRST" session "$TMP/wt"
rec "$W_BASHFIRST" read "$SK/$TDD/SKILL.md" "$SK/$TDD/SKILL.md" 1 4
rec "$W_BASHFIRST" tool bash "cat > src/form.py <<'EOF'" '(no output)'
rec "$W_BASHFIRST" tool bash "sed -i '' s/bool/len/ src/form.py" '(no output)'
rec "$W_BASHFIRST" read "$SK/$TDD/SKILL.md:5-12" "$SK/$TDD/SKILL.md" 5 12
ev expect_shows 'bash calls before the completing read are disclosed, not hidden behind "complete"' '2 bash/eval call(s) precede the completing read' \
  "$(ev_block ev-bashfirst.txt 'read complete | applied UNPROVEN | result UNPROVEN | review UNPROVEN | usage UNPROVEN')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_BASHFIRST"

# USAGE: located links are never the checker's verdict. A complete read
# followed only by an echoed plan locates both excerpts; semantics stay
# unproven by the checker (independent review, 2026-10-05, S1).
expect_usage() { # <label> <skill> <want SUMMARY USAGE field> <trace-check args...> - and no PASS on usage
  local label=$1 skill=$2 want=$3 out got
  shift 3
  out=$(trace_check "$@" 2>&1)
  got=$(printf '%s\n' "$out" | sed -n "s/^SUMMARY - $skill: .* | USAGE //p")
  if [ "$got" != "$want" ]; then
    fail "$label (USAGE '$got', want '$want')"
  elif printf '%s\n' "$out" | grep -q "^PASS - $skill: usage"; then
    fail "$label (a PASS line asserts usage)"
  else
    pass "$label"
  fi
}
W_PLAN="$TMP/w-plan.jsonl"
rec "$W_PLAN" session "$TMP/wt"
rec "$W_PLAN" read "$SK/$TDD/SKILL.md" "$SK/$TDD/SKILL.md"
rec "$W_PLAN" tool bash 'cat plan.md' 'Plan: run bash tests/red.sh, watch it fail, fix, then expect PASS all.'
ev expect_usage 'an echoed plan with every link located is never reported as verified usage' "$TDD" 'links located, semantics UNPROVEN by checker' \
  "$(ev_block ev-plan.txt "$VERIFIED_LINE")" omp "$OPUS" high "$TDD,$VBC" "$W_PLAN"

# A synchronous result runs from its call: a command issued in the same
# message as the read was chosen before the skill was shown, even when its
# output is recorded after the read result (real shape, re-review V2-I1).
W_PARALLEL="$TMP/w-parallel.jsonl"
rec "$W_PARALLEL" session "$TMP/wt"
rec "$W_PARALLEL" parallel "$SK/$TDD/SKILL.md" "$SK/$TDD/SKILL.md" 'bash tests/all.sh' 'ok - all
PASS all'
rec "$W_PARALLEL" tool edit 'src/form.py: fix' 'Updated src/form.py'
ev expect 'output of a command issued alongside the read is not ordered after the read' fail \
  "$(ev_block ev-parallel.txt 'read complete | applied `src/form.py: fix` | result `PASS all` | review UNPROVEN | usage verified')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_PARALLEL"

# VERIFIED: an observed result and an independent review stay separate.
ev expect 'verified usage without an observed result is rejected' fail \
  "$(ev_block ev-noresult.txt 'read complete | applied `bash tests/red.sh` | result UNPROVEN | review UNPROVEN | usage verified')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_GOOD"
# A result is output the worker observed, not text it wrote: the expected
# line inside the test it edited is no outcome (real readiness record:
# the GREEN test name first appears in the edit that added the test).
W_WROTE="$TMP/w-wrote.jsonl"
rec "$W_WROTE" session "$TMP/wt"
rec "$W_WROTE" read "$SK/$TDD/SKILL.md" "$SK/$TDD/SKILL.md"
rec "$W_WROTE" tool edit "tests/red.sh: echo 'PASS all'" "[tests/red.sh#ABCD]
4:echo 'PASS all'"
rec "$W_WROTE" tool bash 'bash tests/red.sh' 'FAIL expected'
ev expect 'a result found only in text the worker wrote, never in observed output, is rejected' fail \
  "$(ev_block ev-wrote.txt 'read complete | applied `bash tests/red.sh` | result `PASS all` | review UNPROVEN | usage verified')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_WROTE"
ev expect 'a cited result the worker never observed is rejected' fail \
  "$(ev_block ev-falseresult.txt 'read complete | applied `bash tests/red.sh` | result `ALL 40 TESTS PASS` | review UNPROVEN | usage UNPROVEN')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_GOOD"
REVIEW_LINE='read complete | applied `bash tests/red.sh` | result `PASS all` | review `0 BLOCKER` | usage verified'
ev expect 'a review claim with no reviewer record is rejected' fail \
  "$(ev_block ev-review-none.txt "$REVIEW_LINE")" omp "$OPUS" high "$TDD,$VBC" "$W_GOOD"
# The worker writing its own verdict is still not independent review.
W_SELF="$TMP/w-self.jsonl"
cp "$W_GOOD" "$W_SELF"
rec "$W_SELF" tool write 'report.md: Verdict: 0 BLOCKER' 'Wrote report.md'
ev expect "the worker's own record is not an independent review, even holding the verdict" fail \
  "$(ev_block ev-review-self.txt "$REVIEW_LINE")" omp "$OPUS" high "$TDD,$VBC" "$W_SELF" "$W_SELF"
R_REVIEW="$TMP/r-review.jsonl"
rec "$R_REVIEW" session "$TMP/review-wt"
rec "$R_REVIEW" say '0 BLOCKER'
ev expect "a review verdict found only in the reviewer's prose is rejected" fail \
  "$(ev_block ev-review-prose.txt "$REVIEW_LINE")" omp "$OPUS" high "$TDD,$VBC" "$W_GOOD" "$R_REVIEW"
rec "$R_REVIEW" tool write 'report.md: Verdict: 0 BLOCKER, 1 IMPORTANT' 'Wrote report.md'
ev expect "a review excerpt located in a different session record is accepted (independence not assessed)" pass \
  "$(ev_block ev-review-ok.txt "$REVIEW_LINE")" omp "$OPUS" high "$TDD,$VBC" "$W_GOOD" "$R_REVIEW"

# Unsupported records: arbitrary text, even text shaped like a receipt,
# cannot prove a read; only explicit UNPROVEN fields pass against it.
FAKE_RECEIPT=$(t fake-receipt.txt "[~/.agents/skills/$TDD/SKILL.md#ABCD]
$(awk '{ printf "%d:%s\n", NR, $0 }' "$SK/$TDD/SKILL.md")
$ bash tests/red.sh
FAIL expected
PASS all")
ev expect 'prose shaped like a read receipt is not an OMP record and proves no read' fail \
  "$(ev_block ev-fake.txt "$VERIFIED_LINE")" omp "$OPUS" high "$TDD,$VBC" "$FAKE_RECEIPT"
ALL_UNPROVEN='read UNPROVEN | applied UNPROVEN | result UNPROVEN | review UNPROVEN | usage UNPROVEN'
ev expect 'explicit UNPROVEN fields are accepted against an unsupported record' pass \
  "$(ev_block ev-unsupported.txt "$ALL_UNPROVEN")" omp "$OPUS" high "$TDD,$VBC" "$FAKE_RECEIPT"
# Only an OMP harness record is read: a Pi worker's record, even in the
# same session shape, supports only UNPROVEN (real Pi records share the
# header; their read output is not the observed receipt shape).
PI_BLOCK="Routing: TENTH-MAN #1 | role tenth-man | pi | $SOL | xhigh | why: challenge Claude-authored completion claim
Skills: $VBC - fresh evidence
Skill evidence:"
ev expect 'a non-OMP harness record cannot support a read-none claim' fail \
  "$(t pi-none.txt "$PI_BLOCK
- $VBC: read none | applied UNPROVEN | result UNPROVEN | review UNPROVEN | usage UNPROVEN")" pi "$SOL" xhigh "$VBC" "$W_GOOD"
ev expect 'a non-OMP harness record accepts explicit UNPROVEN fields' pass \
  "$(t pi-unproven.txt "$PI_BLOCK
- $VBC: $ALL_UNPROVEN")" pi "$SOL" xhigh "$VBC" "$W_GOOD"

# A companion the selected skill makes mandatory (TDD -> writing-good-tests.md
# when tests change) is its own exact-path entry; the SKILL.md receipt never
# covers it.
COMP="$SK/$TDD/writing-good-tests.md"
printf '# Writing Good Tests\nName the break.\nExercise the real thing.\n' > "$COMP"
comp_block() { # <file> <companion evidence fields>
  t "$1" "Routing: IMPLEMENT #2 | role senior-fullstack | omp | $OPUS | high | why: multi-file behavior change
Skills: $TDD - behavior change; $COMP - required companion
Skill evidence:
- $TDD: $ALL_UNPROVEN
- $COMP: $2"
}
ev expect 'a required companion never read is not covered by the SKILL.md read' fail \
  "$(comp_block comp-unread.txt 'read complete | applied UNPROVEN | result UNPROVEN | review UNPROVEN | usage UNPROVEN')" \
  omp "$OPUS" high "$TDD,$COMP" "$W_GOOD"
W_COMP="$TMP/w-comp.jsonl"
cp "$W_GOOD" "$W_COMP"
rec "$W_COMP" read "$COMP" "$COMP"
ev expect 'a required companion read after the first edit is reported late for its own entry' pass \
  "$(comp_block comp-read.txt 'read late | applied UNPROVEN | result UNPROVEN | review UNPROVEN | usage UNPROVEN')" \
  omp "$OPUS" high "$TDD,$COMP" "$W_COMP"
# Companion path forms (re-review V2-I2): a `~/` path names the same shared
# file the worker read; a path that resolves to no readable file is
# unreadable, never an honest "read none".
W_COMPFIRST="$TMP/w-compfirst.jsonl"
rec "$W_COMPFIRST" session "$TMP/wt"
rec "$W_COMPFIRST" read "$COMP" "$COMP"
form_block() { # <file> <companion form> <read claim>
  t "$1" "Routing: IMPLEMENT #2 | role senior-fullstack | omp | $OPUS | high | why: multi-file behavior change
Skills: $2 - required companion
Skill evidence:
- $2: read $3 | applied UNPROVEN | result UNPROVEN | review UNPROVEN | usage UNPROVEN"
}
# shellcheck disable=SC2088  # the literal ~/ form is the input under test
TILDE="~/.agents/skills/$TDD/writing-good-tests.md"
ev expect 'a ~/ companion path names the shared file the worker read in full' pass \
  "$(form_block form-tilde.txt "$TILDE" complete)" omp "$OPUS" high "$TILDE" "$W_COMPFIRST"
ev expect 'a companion path resolving to no readable file cannot support a read-none claim' fail \
  "$(form_block form-relative.txt "$TDD/writing-good-tests.md" none)" omp "$OPUS" high "$TDD/writing-good-tests.md" "$W_COMPFIRST"
# OMP-shaped lines sliced out of a record, without its session header
# (worker identity and worktree), are not a retained record either.
grep -v '"type": "session"' "$W_GOOD" > "$TMP/w-headless.jsonl"
ev expect_rejects 'record lines without their session header prove no read' 'needs a retained OMP session record' \
  "$(ev_block ev-headless.txt "$VERIFIED_LINE")" omp "$OPUS" high "$TDD,$VBC" "$TMP/w-headless.jsonl"

# Block structure: one line per selected skill, nothing for unselected ones.
ev expect 'evidence for a skill the brief never selected is rejected' fail \
  "$(t ev-unsel.txt "$(cat "$(ev_block ev-unsel-base.txt "$ALL_UNPROVEN")")
- systematic-debugging: $ALL_UNPROVEN")" omp "$OPUS" high "$TDD,$VBC" "$W_GOOD"
ev expect 'a selected skill with no evidence line at all is rejected' fail \
  "$(t ev-gap.txt "$(cat "$IMPL")
Skill evidence:
- $TDD: $ALL_UNPROVEN")" omp "$OPUS" high "$TDD,$VBC" "$W_GOOD"
ev expect 'two evidence lines for one skill are rejected (a later line must not mask an earlier false one)' fail \
  "$(t ev-dup.txt "$(cat "$(ev_block ev-dup-base.txt "$VERIFIED_LINE")")
- $TDD: $ALL_UNPROVEN")" omp "$OPUS" high "$TDD,$VBC" "$W_UNREAD"
ev expect 'a transcript supplied without any Skill evidence block is rejected' fail "$IMPL" omp "$OPUS" high "$TDD,$VBC" "$W_GOOD"
ev expect 'an evidence line without separate read/applied/result/review/usage fields is rejected' fail \
  "$(ev_block ev-bare.txt 'applied test-driven development throughout')" omp "$OPUS" high "$TDD,$VBC" "$W_GOOD"
ev expect 'more than two applied excerpts for one skill are rejected' fail \
  "$(ev_block ev-long.txt 'read complete | applied `bash tests/red.sh`, `FAIL expected` and `PASS all` | result `PASS all` | review UNPROVEN | usage UNPROVEN')" \
  omp "$OPUS" high "$TDD,$VBC" "$W_GOOD"
LIVE_NONE=$(t live-none.txt "Routing: EXPLORE #1 | role senior-fullstack | omp | openai-codex/gpt-6-luna | low | why: measured viable capacity
Skills: none
Skill evidence: none selected.")
expect '"Skill evidence: none selected." after "Skills: none" is accepted' pass \
  "$LIVE_NONE" omp openai-codex/gpt-6-luna low none "$W_GOOD"
expect 'inline "none selected" while a skill was selected is rejected' fail \
  "$(t live-none-sel.txt "$(sed "s/^Skills: none\$/Skills: $VBC - fresh output/" "$LIVE_NONE")")" \
  omp openai-codex/gpt-6-luna low "$VBC" "$W_GOOD"

# Excerpt quoting: a nested excerpt is located whole, never as a prefix
# that a different exit code would also match; ambiguous quoting fails.
W_EXIT="$TMP/w-exit.jsonl"
rec "$W_EXIT" session "$TMP/wt"
rec "$W_EXIT" read "$SK/$VBC/SKILL.md" "$SK/$VBC/SKILL.md"
rec "$W_EXIT" tool bash 'bash tests/all.sh' 'Exit code: `10`'
VBC_ONLY="Routing: EXPLORE #1 | role senior-fullstack | omp | openai-codex/gpt-6-luna | low | why: bounded
Skills: $VBC - fresh verification
Skill evidence:"
ev expect 'a nested excerpt followed by a comma is not matched by its prefix in a different exit code' fail \
  "$(t nested.txt "$VBC_ONLY
- \`$VBC\`: read complete | applied ran \`bash tests/all.sh\` | result saw \`Exit code: \`1\`, final\` | review UNPROVEN | usage UNPROVEN")" \
  omp openai-codex/gpt-6-luna low "$VBC" "$W_EXIT"
ev expect 'unbalanced backtick quoting is rejected as ambiguous, never guessed' fail \
  "$(t ambiguous.txt "$VBC_ONLY
- \`$VBC\`: read complete | applied \`\`\`bash tests/all.sh\` | result UNPROVEN | review UNPROVEN | usage UNPROVEN")" \
  omp openai-codex/gpt-6-luna low "$VBC" "$W_EXIT"
ev expect 'a backticked skill name with a located nested excerpt is accepted' pass \
  "$(t nested-ok.txt "$VBC_ONLY
- \`$VBC\`: read complete | applied ran \`bash tests/all.sh\` | result saw \`Exit code: \`10\`\` | review UNPROVEN | usage verified")" \
  omp openai-codex/gpt-6-luna low "$VBC" "$W_EXIT"

# --- 4. Real dispatch/brief/spawn seam --------------------------------------
# The real, unmodified official bin/fm-spawn.sh launches one task on an
# isolated tmux server (never the shared session) into a real treehouse
# worktree of a disposable project - the same seam tests/multi-project-
# captain.sh uses. Only the omp executable is faked: it records the argv it
# was really launched with and, when the delivered brief names the fixture
# project skill, runs that skill's ./check.sh into its own transcript. This
# script plays the Captain: it takes the substantive-IMPLEMENT route from
# crew-dispatch.json (the category choice itself is still the Captain's
# judgment and is NOT proven here), reads selected skills from the brief
# it writes, prints the trace, spawns with those axes, and then checks the
# trace against what fm-spawn recorded and what the worker actually
# received and did.
FIRSTMATE_ROOT_REAL="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }

# brief_skills <brief-file> - the skills a primary-policy.md section 2
# brief selects: the indented line after each "Required project skill:" or
# "Selected shared worker skill:" header, comma-joined, or "none".
brief_skills() {
  local s
  s=$(awk '/^(Required project skill|Selected shared worker skill)/ {getline; gsub(/^[ \t]+|[ \t]+$/, ""); printf "%s%s", sep, $0; sep=","}' "$1")
  printf '%s' "${s:-none}"
}

if ! command -v tmux >/dev/null 2>&1 || ! command -v treehouse >/dev/null 2>&1 || [ ! -x "$FIRSTMATE_ROOT_REAL/bin/fm-spawn.sh" ]; then
  printf 'SKIP - real spawn seam: needs tmux, treehouse, and %s/bin/fm-spawn.sh (never reported as PASS)\n' "$FIRSTMATE_ROOT_REAL"
else
  seam_home="$TMP/fm-home"
  seam_proj="$seam_home/projects/seam-proj"
  mkdir -p "$seam_home/state" "$seam_home/config" "$seam_home/data/$SEAM_ID" "$TMP/home" "$TMP/bin" \
    "$seam_proj/.agents/skills/trace-canary"
  printf 'manual\n' > "$seam_home/config/backlog-backend"
  printf '# Seam project\n' > "$seam_proj/AGENTS.md"
  printf -- '---\nname: trace-canary\ndescription: fixture project skill\n---\nRun ./check.sh before claiming done.\n' \
    > "$seam_proj/.agents/skills/trace-canary/SKILL.md"
  printf '#!/bin/sh\necho CHECK OK\n' > "$seam_proj/check.sh"
  chmod +x "$seam_proj/check.sh"
  printf 'max_trees = 4\nroot = "./"\n' > "$seam_proj/treehouse.toml"
  git -C "$seam_proj" init -q
  git -C "$seam_proj" add -A
  git -C "$seam_proj" -c user.email=t@example.invalid -c user.name=t commit -q -m init

  cat > "$TMP/bin/omp" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = --help ] && { printf 'usage: omp [options] [prompt]\n'; exit 0; }
# fm-spawn validates --model against `omp models --json` before launch.
if [ "${1:-}" = models ]; then
  printf '{"models":[{"provider":"anthropic","id":"claude-opus-5-5","selector":"anthropic/claude-opus-5-5"},{"provider":"anthropic","id":"claude-sonnet-5-5","selector":"anthropic/claude-sonnet-5-5"}]}\n'
  exit 0
fi
printf '%s\n' "$@" > worker-argv.txt
# A launched worker leaves its session record in the retained OMP shape:
# with the canary skill in its brief, it reads that skill in its own
# worktree and runs the skill's ./check.sh.
rm -f worker-session.tmp
omp-record worker-session.tmp session "$PWD"
case "$*" in
  *.agents/skills/trace-canary/SKILL.md*)
    omp-record worker-session.tmp read .agents/skills/trace-canary/SKILL.md .agents/skills/trace-canary/SKILL.md
    omp-record worker-session.tmp tool bash ./check.sh "$(./check.sh)" ;;
esac
mv worker-session.tmp worker-session.jsonl
SH
  chmod +x "$TMP/bin/omp"
  printf '#!/bin/sh\nexec python3 %s "$@"\n' "$TMP/omp-record.py" > "$TMP/bin/omp-record"
  chmod +x "$TMP/bin/omp-record"

  BRIEF="$seam_home/data/$SEAM_ID/brief.md"
  cat > "$BRIEF" <<'EOF'
# Task

## Captain's intent
Fixture substantive implementation for the routing-trace seam.

## Firstmate spec
Required project skill:
  .agents/skills/trace-canary/SKILL.md
Requirement:
  Read and apply before claiming done.
Selected shared worker skill:
  verification-before-completion
Requirement:
  Apply before declaring the task complete.
EOF
  route=$(python3 -c 'import json,sys; r=[r for r in json.load(open(sys.argv[1]))["rules"] if r["category"]=="IMPLEMENT"][1]["use"][0]; print(r["harness"], r["model"], r["effort"])' "$CREW_DISPATCH")
  set -- $route
  r_harness=$1 r_model=$2 r_effort=$3
  selected=$(brief_skills "$BRIEF")
  CAPTAIN_TRACE=$(t seam-trace.txt "Routing: IMPLEMENT #2 | role senior-fullstack | $r_harness | $r_model | $r_effort | why: fixture multi-component change
Skills: .agents/skills/trace-canary/SKILL.md - project check before done; verification-before-completion - completion claim needs fresh evidence")

  SEAM_TMUX=$(mktemp -d /tmp/fm-trace-tmux.XXXXXX) || exit 1
  spawn_out=$(TMUX_TMPDIR="$SEAM_TMUX" PATH="$TMP/bin:$PATH" HOME="$TMP/home" FM_HOME="$seam_home" FM_BACKEND=tmux \
    timeout 60 "$FIRSTMATE_ROOT_REAL/bin/fm-spawn.sh" "$SEAM_ID" projects/seam-proj \
    --mode local-only --yolo off --harness "$r_harness" --model "$r_model" --effort "$r_effort" 2>&1)
  if [ $? -ne 0 ]; then
    fail "real fm-spawn of the seam task failed: $spawn_out"
  else
    meta=$(cat "$seam_home/state/$SEAM_ID.meta" 2>/dev/null)
    wt=$(field "$meta" worktree)
    waited=0
    while [ ! -f "$wt/worker-session.jsonl" ] && [ "$waited" -lt 100 ]; do sleep 0.1; waited=$((waited + 1)); done
    argv=$(cat "$wt/worker-argv.txt" 2>/dev/null)
    launched_model=$(printf '%s\n' "$argv" | sed -n '/^--model$/{n;p;}')
    launched_effort=$(printf '%s\n' "$argv" | sed -n '/^--thinking$/{n;p;}')
    delivered="$TMP/delivered-brief.txt"
    printf '%s\n' "$argv" > "$delivered"

    expect 'seam: trace matches the axes fm-spawn recorded and the skills in the written brief' pass \
      "$CAPTAIN_TRACE" "$(field "$meta" harness)" "$(field "$meta" model)" "$(field "$meta" effort)" "$selected"
    expect 'seam: trace matches the --model/--thinking the worker process was really launched with' pass \
      "$CAPTAIN_TRACE" omp "$launched_model" "$launched_effort" "$(brief_skills "$delivered")"
    expect 'seam: a trace printing xhigh for a task really launched at high is rejected' fail \
      "$(t seam-wrong.txt "$(sed 's/| high |/| xhigh |/' "$CAPTAIN_TRACE")")" omp "$launched_model" "$launched_effort" "$selected"

    SEAM_EVIDENCE=$(t seam-ev.txt "$(cat "$CAPTAIN_TRACE")
Skill evidence:
- .agents/skills/trace-canary/SKILL.md: read complete | applied worker ran \`./check.sh\` | result saw \`CHECK OK\` | review UNPROVEN | usage verified
- verification-before-completion: read none | applied UNPROVEN | result UNPROVEN | review UNPROVEN | usage UNPROVEN")
    expect 'seam: post-work evidence matches the launched worker record (receipt, behavior, result)' pass \
      "$SEAM_EVIDENCE" omp "$launched_model" "$launched_effort" "$selected" "$wt/worker-session.jsonl"
    SEAM_FALSE=$(t seam-false.txt "$(cat "$CAPTAIN_TRACE")
Skill evidence:
- .agents/skills/trace-canary/SKILL.md: read complete | applied worker ran \`./check.sh\` | result saw \`CHECK OK\` | review UNPROVEN | usage verified
- verification-before-completion: read complete | applied worker re-ran \`bash tests/all.sh\` | result UNPROVEN | review UNPROVEN | usage UNPROVEN")
    expect 'seam: evidence claiming a read and a verification run the worker never made is rejected' fail \
      "$SEAM_FALSE" omp "$launched_model" "$launched_effort" "$selected" "$wt/worker-session.jsonl"
  fi
fi

printf '\nROUTING TRACE TESTS %s\n' "$([ "$failed" -eq 0 ] && echo PASS || echo FAIL)"
[ "$failed" -eq 0 ]
