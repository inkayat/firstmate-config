# Live workflow case (xi): ui-build-verify-review - the real-browser gate catches what the browser-free checks cannot.
# Needs chrome-devtools-axi (and node for the kit): SKIPPED, never PASSED, when one is absent (live and offline self-test alike: the
# judge drives a real headless browser).
# Problem: the newsletter signup page (app/index.html + app/app.js) has its markup in place; the ticket asks for the behaviour in app.js:
#   inline validation messages, a global validateSignup(email), and, for a valid email, a POST to the subscription service whose
#   message the page shows. The service is documented in docs/api.md as taking JSON. The dev server that runs with the page (the
#   environment, outside the repository: no worker can read it) really takes only application/x-www-form-urlencoded and answers
#   415 + {"error": "Unsupported Media Type: ..."} to JSON: the documentation is stale. Nothing in the repository shows that, so the
#   natural implementation follows the documentation, passes every browser-free check (QA's kit exercises validateSignup in node with a
#   stubbed page) and fails for real: a valid submit shows the 415 text where the result line should be. Only driving the page in a
#   browser against the running service shows it. (Native constraint validation was tried first: every live implementer set
#   form.noValidate on its own, so the first implementation was never vulnerable.)
# Forced loop: implement -> classify -> qa PASS -> ui-verify FAIL (real browser, screenshot evidence, the shown 415 text) -> implement
#   (fixes from that feedback: the form-encoded body) -> classify -> qa PASS -> ui-verify PASS -> review PASS -> ship PASS -> deliver.
# Outside judge (deterministic code, a real headless browser, never a model): the hidden check = the node kit (validateSignup) + six
#   flows driven in a real browser against a private copy of the dev server serving the repository under test (empty, blank, no-@,
#   no-dot, valid with Pro, valid with Free: the alert region and the result line, text and visibility) + the server log must show an
#   accepted POST /api/subscribe for each valid flow (a page that composes the message without the service fails). It FAILS after the first
#   implementation while the kit alone passes. case_assert: the path has ui-verify:fail then ui-verify:pass; the ui-verify failure names
#   the service problem; the screenshot its report names exists in the evidence dir and is a real PNG (magic bytes, IHDR >= 100x100, IDAT,
#   IEND); the dev server log shows a 415 and then a 200 for POST /api/subscribe (the real browsers of ui-verify); in a live run the
#   ui-verify transcripts show chrome-devtools-axi opening the page, interacting and taking a screenshot. Control: the fix round without
#   the feedback must not fix it.
# Workers other than ui-verify get no APP_URL / EVIDENCE_DIR (they know no running service) and a browser rule: one worker killed other
#   people's Chrome (pkill) in an earlier run.
CASE_WORKFLOW=ui-build-verify-review
CASE_NEEDS='chrome-devtools-axi python3 curl node'
CASE_SELFTEST_NEEDS='chrome-devtools-axi python3 curl node'
CASE_TASK='The newsletter signup page (app/index.html, app/app.js) has its markup but no behaviour yet. Implement it in app.js. app.js must define a global function validateSignup(email) that returns the message to show for an invalid email and an empty string for a valid one: an empty or whitespace-only email gives "Email is required"; otherwise the email is valid when it has the shape local@domain.tld (no spaces, exactly one @, at least one dot in the domain part) and gives "Enter a valid email address" when it does not. Acceptance: (1) submitting the form with an empty email shows "Email is required" in the alert region under the field and no subscription result; (2) submitting an invalid email shows "Enter a valid email address" in the alert region and no result; (3) submitting a valid email with a plan POSTs the signup to the subscription service (documented in docs/api.md) and shows the message the service returns in the result line, with nothing in the alert region; when the service answers with an error status, the error text it returns is shown in the alert region instead and the result line stays empty. Keep the change small.'
CASE_CONTROL_STEP=implement
CASE_CONTROL_RUN=2
CASE_CONTROL_STRIP=feedback
CASE_EXPECT_PATH='^implement:done classify:(low|medium|high) qa:pass ui-verify:fail( .*)? ui-verify:pass( .*)? ship:pass deliver:done$'
CASE_FORCE_AFTER=implement:1
CASE_FORCE_KIT_PASS=1
CASE_NEGATIVE='firsttry => the loop was not forced
blindui => FAIL - the final repository does not satisfy the hidden acceptance check: .*(flow|POST)
skipapi => FAIL - the final repository does not satisfy the hidden acceptance check: .*accepted POST'

case_setup() {
  mkdir -p app docs
  cat > README.md <<'R'
# signup-page
A static page: app/index.html + app/app.js, served from app/ on the dev URL, next to the subscription service it talks to (same origin, docs/api.md).
There is no build step and there are no unit tests; the form is verified in a browser.
R
  cat > docs/api.md <<'R'
# Subscription service

`POST /api/subscribe` (same origin as the page)

Request: `Content-Type: application/json`, body `{"email": "<address>", "plan": "free" | "pro"}`.

Responses (always JSON):
- `200` `{"message": "<text to show the user>"}`
- any `4xx` `{"error": "<text to show the user>"}`
R
  cat > app/index.html <<'R'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Newsletter signup</title>
<link rel="icon" href="data:,">
</head>
<body>
<main>
<h1>Newsletter signup</h1>
<form id="signup">
  <label for="email">Email</label>
  <input id="email" name="email" type="text" inputmode="email" aria-describedby="email-error" autocomplete="off">
  <p id="email-error" role="alert"></p>
  <label for="plan">Plan</label>
  <select id="plan" name="plan">
    <option value="free">Free</option>
    <option value="pro">Pro</option>
  </select>
  <button type="submit" id="submit">Subscribe</button>
</form>
<div id="result" role="status"></div>
</main>
<script src="app.js"></script>
</body>
</html>
R
  printf '// signup behaviour goes here\n' > app/app.js
}

# the dev server: static files from the repository's app/ (no-store) and the subscription service, which takes ONLY form-encoded bodies
ui_server_write() { # <path>
  cat > "$1" <<'R'
import functools, http.server, json, sys, urllib.parse
PLANS = {"free": "Free", "pro": "Pro"}
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
    def _json(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)
    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode("utf-8", "replace")
        if self.path.split("?")[0] != "/api/subscribe":
            return self._json(404, {"error": "not found"})
        ctype = (self.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        if ctype != "application/x-www-form-urlencoded":
            return self._json(415, {"error": "Unsupported Media Type: /api/subscribe only accepts application/x-www-form-urlencoded (email=...&plan=...), got %s" % (ctype or "no content type")})
        f = urllib.parse.parse_qs(raw)
        email = (f.get("email") or [""])[0].strip()
        plan = (f.get("plan") or [""])[0]
        if not email or plan not in PLANS:
            return self._json(400, {"error": "email and plan (free or pro) are required"})
        return self._json(200, {"message": "Subscribed %s to the %s plan" % (email, PLANS[plan])})
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), functools.partial(H, directory=sys.argv[2])).serve_forever()
R
}

# the services: the dev server over the live repository's app/ directory (it always serves the current head), a unique browser session
# name, and an evidence directory. The server source is deleted once the process runs: nothing on disk for a worker to read.
case_serve() { # <repo> <aux>
  local repo=$1 aux=$2 port i
  port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()') || return 1
  mkdir -p "$aux/evidence"
  ui_server_write "$aux/server.py"
  python3 "$aux/server.py" "$port" "$repo/app" > "$aux/server.log" 2>&1 < /dev/null &
  echo $! >> "$aux/pids"
  i=0
  until curl -s -o /dev/null "http://127.0.0.1:$port/"; do
    i=$((i + 1)); [ "$i" -lt 50 ] || { echo "http server did not start" >&2; return 1; }
    sleep 0.2
  done
  rm -f "$aux/server.py"
  echo "APP_URL=http://127.0.0.1:$port/"
  echo "EVIDENCE_DIR=$aux/evidence"
  echo "CHROME_DEVTOOLS_AXI_SESSION=wl-$(basename "$aux" | tr -c 'A-Za-z0-9\n' '-')"
}

# only the browser verification knows the running service and may write evidence; every other worker gets just its private browser session
case_worker_env() { # <role>
  case $1 in
    ui-qa) printf '%s\n' "$SVC_ENV_LINES" ;;
    *) printf '%s\n' "$SVC_ENV_LINES" | grep '^CHROME_DEVTOOLS_AXI_SESSION=' ;;
  esac
}

case_stop() { # <aux>
  local sid
  command -v chrome-devtools-axi >/dev/null 2>&1 || return 0
  sid=$(sed -n 's/^CHROME_DEVTOOLS_AXI_SESSION=//p' "$1/env" 2>/dev/null | head -1)
  [ -z "$sid" ] || CHROME_DEVTOOLS_AXI_SESSION=$sid chrome-devtools-axi stop >/dev/null 2>&1
  return 0
}

# QA's kit: validateSignup as the ticket specifies it, in node with a stubbed page (no browser, no service)
case_kit_setup() {
  cat > "$1/kit.js" <<'R'
const vm = require('vm'), fs = require('fs'), path = require('path');
const repo = process.argv[2];
let src;
try { src = fs.readFileSync(path.join(repo, 'app', 'app.js'), 'utf8'); } catch (e) { console.log('FAIL cannot read app/app.js'); process.exit(1); }
function stub() {
  const f = function () {};
  return new Proxy(f, { get: (t, p) => (p === Symbol.toPrimitive ? () => '' : p === 'then' ? undefined : stub()), apply: () => stub(), construct: () => stub(), set: () => true });
}
const ctx = { document: stub(), console: console, localStorage: stub(), setTimeout: () => 0, fetch: () => new Promise(() => {}) };
ctx.window = ctx;
vm.createContext(ctx);
try { vm.runInContext(src, ctx); } catch (e) { console.log('FAIL app.js throws when it is loaded: ' + e); process.exit(1); }
if (typeof ctx.validateSignup !== 'function') { console.log('FAIL app.js does not define a global function validateSignup(email)'); process.exit(1); }
const cases = [['', 'Email is required'], ['   ', 'Email is required'], ['dana', 'Enter a valid email address'], ['dana@example', 'Enter a valid email address'], ['dana@example.test', '']];
let bad = 0;
for (const [input, want] of cases) {
  let got;
  try { got = ctx.validateSignup(input); } catch (e) { got = 'threw ' + e; }
  if (got !== want) { bad++; console.log('FAIL validateSignup(' + JSON.stringify(input) + ') = ' + JSON.stringify(got) + ', expected ' + JSON.stringify(want)); }
  else console.log('ok   validateSignup(' + JSON.stringify(input) + ')');
}
process.exit(bad ? 1 : 0);
R
}

case_kit_only() { node "$2/kit.js" "$1" >/dev/null 2>&1; } # <repo> <kit-dir>

# The browser judge. ui_judge_run repo <repository>: a private dev server over <repository>/app and a private browser session, six flows,
# then the server log must show an accepted POST for each valid flow. ui_judge_run url <base-url> [<screenshot>]: the same flows against a
# server that is already running (the worker's own session from the environment; used by the offline stand-in for ui-verify).
# Prints one FAIL line per problem; a browser that cannot open the page is a FAIL, never a pass. Nothing of it stays on disk.
ui_judge_run() { # <mode> <target> [<screenshot>]
  local d rc
  d=$(mktemp -d "${TMPDIR:-/tmp}/wl-judge.XXXXXX") || return 1
  ui_server_write "$d/server.py"
  cat > "$d/judge.py" <<'R'
import json, os, socket, subprocess, sys, tempfile, time, urllib.request
mode, target = sys.argv[1], sys.argv[2]
shot = sys.argv[3] if len(sys.argv) > 3 else ""
server_py = sys.argv[4]
env = dict(os.environ)
bad = []
proc = None
log = None
def axi(*a, timeout=60):
    return subprocess.run(["chrome-devtools-axi"] + list(a), env=env, capture_output=True, text=True, timeout=timeout)
try:
    if mode == "repo":
        env["CHROME_DEVTOOLS_AXI_SESSION"] = "wl-judge-%d-%d" % (os.getpid(), int(time.time()))
        s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
        log = os.path.join(os.path.dirname(server_py), "server.log")
        proc = subprocess.Popen([sys.executable, server_py, str(port), os.path.join(target, "app")], stdout=open(log, "w"), stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        base = "http://127.0.0.1:%d/" % port
        for _ in range(50):
            try:
                urllib.request.urlopen(base, timeout=2).read(); break
            except Exception:
                time.sleep(0.2)
    else:
        base = target
    JS = """(async () => {
  const q = (s) => document.querySelector(s);
  const set = (el, v) => { el.value = v; el.dispatchEvent(new Event('input', {bubbles: true})); el.dispatchEvent(new Event('change', {bubbles: true})); };
  set(q('#email'), %s);
  q('#plan').value = %s;
  q('#submit').click();
  const want = %s;
  for (let i = 0; i < 30; i++) {
    await new Promise(r => setTimeout(r, 100));
    const el = q(want ? '#result' : '#email-error');
    if (el && el.textContent.trim()) break;
  }
  await new Promise(r => setTimeout(r, 200));
  const vis = (el) => { if (!el || !(el.textContent || '').trim()) return false; const st = getComputedStyle(el); return el.getClientRects().length > 0 && st.display !== 'none' && st.visibility !== 'hidden'; };
  const t = (s) => (q(s) ? q(s).textContent.trim() : null);
  return JSON.stringify({alert: t('#email-error'), alertVisible: vis(q('#email-error')), result: t('#result'), resultVisible: vis(q('#result'))});
})()"""
    flows = [
        ("", "free", "Email is required", ""),
        ("   ", "free", "Email is required", ""),
        ("dana", "free", "Enter a valid email address", ""),
        ("dana@example", "pro", "Enter a valid email address", ""),
        ("dana@example.test", "pro", "", "Subscribed dana@example.test to the Pro plan"),
        ("lee@example.test", "free", "", "Subscribed lee@example.test to the Free plan"),
    ]
    infra = False
    for n, (email, plan, want_alert, want_result) in enumerate(flows, 1):
        opened = False
        for _ in range(3):
            try:
                r = axi("open", base)
                if r.returncode == 0 and "page:" in r.stdout:
                    opened = True; break
            except subprocess.TimeoutExpired:
                pass
            time.sleep(1)
        if not opened:
            bad.append("FAIL flow %d: the browser could not open the page (judge infrastructure, not a verdict on the change)" % n); infra = True; break
        try:
            r = axi("eval", JS % (json.dumps(email), json.dumps(plan), "true" if want_result else "false"))
        except subprocess.TimeoutExpired:
            bad.append("FAIL flow %d (email %r): the page did not answer" % (n, email)); continue
        line = [l for l in r.stdout.splitlines() if l.startswith("result: ")]
        got = None
        if line:
            v = line[0][len("result: "):]
            for _ in range(3):
                try: v = json.loads(v)
                except Exception: break
                if isinstance(v, dict): break
            got = v if isinstance(v, dict) else None
        if got is None:
            bad.append("FAIL flow %d (email %r, plan %s): the page was reloaded or the script failed: %s" % (n, email, plan, (r.stdout + r.stderr).strip().replace("\n", " ")[:160])); continue
        ga, gr = got.get("alert") or "", got.get("result") or ""
        if ga != want_alert or gr != want_result:
            bad.append("FAIL flow %d (email %r, plan %s): expected alert %r and result %r, the page shows alert %r and result %r" % (n, email, plan, want_alert, want_result, ga, gr))
        elif (want_alert and not got.get("alertVisible")) or (want_result and not got.get("resultVisible")):
            bad.append("FAIL flow %d (email %r, plan %s): the expected text is in the page but not visible" % (n, email, plan))
    if shot and not infra:
        axi("screenshot", shot)
    if mode == "repo" and not infra:
        time.sleep(0.3)
        text = open(log, encoding="utf-8", errors="replace").read() if log else ""
        ok = text.count('"POST /api/subscribe HTTP/1.1" 200')
        if ok < 2:
            bad.append("FAIL the page made %d accepted POST /api/subscribe request(s); each valid submit must be accepted by the service (2 needed)" % ok)
finally:
    if mode == "repo":
        try: axi("stop", timeout=30)
        except Exception: pass
    if proc is not None:
        proc.terminate()
print("\n".join(bad))
sys.exit(1 if bad else 0)
R
  python3 "$d/judge.py" "$1" "$2" "${3:-}" "$d/server.py"; rc=$?
  rm -rf "$d"
  return $rc
}

case_hidden() { # <repo> <kit-dir>
  node "$2/kit.js" "$1" > "$RUN/hidden.last" 2>&1 || return 1
  ui_judge_run repo "$1" >> "$RUN/hidden.last" 2>&1 || return 1
}

case_extra() { # <step> <role> <iteration> <kit-dir> <cwd> <data-dir>
  case $2 in
    qa) printf 'QA acceptance kit: run `node %s/kit.js .` from your working directory (it is the repository under test); it checks validateSignup in app.js without a browser. A failing expectation is a FAIL. Then do the rest of your QA as usual; a browser check follows in the next step.\n' "$4" ;;
    ui-qa) printf 'Environment facts for the browser verification: the app is ALREADY running at APP_URL=%s together with the subscription service it talks to, and serves the repository head under test: do not start another server (this overrides the general no-network note: that one localhost URL is allowed). Your browser is the chrome-devtools-axi CLI on PATH (run it from bash; chrome-devtools-axi --help lists its commands); CHROME_DEVTOOLS_AXI_SESSION=%s is already set in your environment, keep it for every call. Exercise every acceptance flow of the ticket end to end, the valid-email one included, and report what the page SHOWS in each. Save at least one screenshot of what you observed as a PNG file inside EVIDENCE_DIR=%s (an absolute path: give the screenshot command that path) and name that file path in your report. Do not edit anything in the repository.\n' "$(svc_get APP_URL)" "$(svc_get CHROME_DEVTOOLS_AXI_SESSION)" "$(svc_get EVIDENCE_DIR)" ;;
  esac
  printf 'Browser rule for this task: the only browser you may use is the chrome-devtools-axi CLI, with the CHROME_DEVTOOLS_AXI_SESSION already in your environment; never start Chrome or any other browser yourself and never kill, pkill or restart any browser process (other people'"'"'s browsers run on this machine); stop your own session with chrome-devtools-axi stop when you are done with it.\n'
}

ui_png_ok() { # <file>: a real PNG (magic, IHDR >= 100x100, IDAT, IEND)
  python3 - "$1" <<'R'
import struct, sys
b = open(sys.argv[1], 'rb').read()
ok = len(b) >= 100 and b[:8] == b'\x89PNG\r\n\x1a\n' and b[12:16] == b'IHDR' and b'IDAT' in b and b.endswith(b'IEND\xaeB`\x82')
if ok:
    w, h = struct.unpack('>II', b[16:24])
    ok = w >= 100 and h >= 100
sys.exit(0 if ok else 1)
R
}

# What the transcript of a ui-verify worker must show: the browser opened on a URL, driven (click, fill, fillform, type, press or eval) and
# photographed. The tool is the chrome-devtools-axi CLI called by name or through a shell variable that was set to it (X=chrome-devtools-axi,
# then $X eval '...'): the command word must come right after the tool, so a --help listing that merely mentions click is not driving it.
# Prints what is missing (open, interaction, screenshot), nothing when all three are shown.
ui_browser_evidence() { # <calls.tsv>
  python3 - "$1" <<'R'
import json, re, sys
cmds = []
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    tool, _, arg = line.rstrip("\n").partition("\t")
    if tool != "bash":
        continue
    try:
        cmds.append(json.loads(arg).get("command", ""))
    except Exception:
        cmds.append(arg)
aliases = set()
for c in cmds:
    aliases.update(re.findall(r"(?:^|[\s;&|(])([A-Za-z_][A-Za-z0-9_]*)=[\"']?chrome-devtools-axi[\"']?(?=[\s;&|)]|$)", c))
tok = r"(?:chrome-devtools-axi" + "".join(r"|\$\{?%s\}?" % re.escape(a) for a in sorted(aliases)) + r")"
want = {
    "open": tok + r"\s+(?:open|newpage)\s+[\"']?https?://",
    "interaction": tok + r"\s+(?:click|fill|fillform|type|press|eval)\s+\S",
    "screenshot": tok + r"\s+screenshot\s+\S",
}
print(" ".join(k for k, rx in want.items() if not any(re.search(rx, c) for c in cmds)))
R
}

# the judge's own variants (run by the offline self-test): evidence that shows a driven browser is accepted in every spelling workers used
# (plain, through a variable set in the same call, through a variable set in an earlier call), evidence that does not is rejected
case_judge_selftest() { # prints one line per wrong verdict; nothing when the judge is right
  local d got
  d=$(mktemp -d "${TMPDIR:-/tmp}/wl-uievid.XXXXXX") || return 1
  L() { printf '%s\t%s\n' "$1" "$2"; }
  check() { # <name> <expected missing> <calls.tsv>
    got=$(ui_browser_evidence "$3")
    [ "$got" = "$2" ] || echo "ui evidence variant '$1': expected missing '$2', the judge said '$got'"
  }
  { L bash '{"command": "chrome-devtools-axi open http://127.0.0.1:5/ | head"}'; L bash '{"command": "chrome-devtools-axi fill @g1:1_5 \"a@b.com\"; chrome-devtools-axi click @g1:1_9"}'; L bash '{"command": "chrome-devtools-axi screenshot /e/a.png"}'; } > "$d/plain.tsv"
  { L bash '{"command": "C=chrome-devtools-axi\n$C open http://127.0.0.1:5/ >/dev/null\n$C eval '"'"'(()=>{return 1})()'"'"'\n$C screenshot /e/a.png"}'; } > "$d/alias-same-call.tsv"
  { L bash '{"command": "C=chrome-devtools-axi"}'; L bash '{"command": "${C} open \"http://127.0.0.1:5/\""}'; L bash '{"command": "$C press Enter"}'; L bash '{"command": "$C screenshot /e/a.png"}'; } > "$d/alias-earlier-call.tsv"
  { L bash '{"command": "chrome-devtools-axi --help | head -40"}'; L bash '{"command": "chrome-devtools-axi screenshot /e/a.png"}'; } > "$d/help-only.tsv"
  { L bash '{"command": "chrome-devtools-axi open http://127.0.0.1:5/"}'; L bash '{"command": "chrome-devtools-axi screenshot /e/a.png"}'; } > "$d/no-interaction.tsv"
  { L bash '{"command": "chrome-devtools-axi --help | grep -n click"}'; L bash '{"command": "chrome-devtools-axi open http://127.0.0.1:5/"}'; L bash '{"command": "chrome-devtools-axi screenshot /e/a.png"}'; } > "$d/click-only-in-help.tsv"
  { L bash '{"command": "grep -n eval app/app.js; curl -s http://127.0.0.1:5/ | head"}'; L read '{"path": "app/app.js"}'; } > "$d/no-browser.tsv"
  { L bash '{"command": "X=chrome-devtools-axi; $X open http://127.0.0.1:5/; $X click @a"}'; } > "$d/no-screenshot.tsv"
  check plain '' "$d/plain.tsv"
  check alias-same-call '' "$d/alias-same-call.tsv"
  check alias-earlier-call '' "$d/alias-earlier-call.tsv"
  check help-only 'open interaction' "$d/help-only.tsv"
  check no-interaction 'interaction' "$d/no-interaction.tsv"
  check click-only-in-help 'interaction' "$d/click-only-in-help.tsv"
  check no-browser 'open interaction screenshot' "$d/no-browser.tsv"
  check no-screenshot 'screenshot' "$d/no-screenshot.tsv"
  rm -rf "$d"
}

case_assert() { # <run-dir> <repo>
  local st=$1/data/workflow.json d f png found fb first415 first200
  jq -e '[.history[] | select(.step == "ui-verify") | .outcome] | (index("fail") // 99) < (index("pass") // -1)' "$st" >/dev/null || { echo "ui-verify did not fail and then pass: $(jq -c '[.history[] | select(.step == "ui-verify") | .outcome]' "$st")"; return 1; }
  fb=$(jq -r '[.history[] | select(.step == "ui-verify" and .outcome == "fail") | .feedback[]? | .what + " " + .where + " " + (.class // "")] | join("\n")' "$st")
  printf '%s' "$fb" | grep -qiE '415|unsupported|media type|content.type|urlencoded|subscribe|service|api|server|result|error' || { echo "the ui-verify failure does not name the problem with the valid submit (service answer / missing result)"; return 1; }
  jq -e '[.history[] | select(.step == "implement")] | length >= 2 and (.[-1].answers | length) >= 1' "$st" >/dev/null || { echo "the fixing implementer run reported no answer to the ui-verify finding"; return 1; }
  # the screenshot each ui-verify report names must exist in the evidence dir and be a real PNG
  for d in "$1"/steps/[0-9][0-9]-ui-verify; do
    found=''
    for png in $(grep -oE '[A-Za-z0-9._/~-]+\.png' "$d/final.txt" | sort -u); do
      f="$1/aux/evidence/$(basename "$png")"
      if [ -f "$f" ] && ui_png_ok "$f"; then found=$f; break; fi
    done
    [ -n "$found" ] || { echo "$(basename "$d"): the report names no screenshot that exists in the evidence dir as a real PNG (named: $(grep -oE '[A-Za-z0-9._/~-]+\.png' "$d/final.txt" | sort -u | tr '\n' ' '))"; return 1; }
    if [ -z "${SELFTEST_MODE:-}" ]; then
      found=$(ui_browser_evidence "$d/calls.tsv")
      [ -z "$found" ] || { echo "$(basename "$d"): the transcript does not show the browser being driven: missing $found"; return 1; }
    fi
  done
  grep -q 'GET /app.js' "$1/aux/server.log" 2>/dev/null || { echo "the server never saw GET /app.js: the page was not loaded by a browser"; return 1; }
  first415=$(grep -n 'POST /api/subscribe HTTP/1.1" 415' "$1/aux/server.log" 2>/dev/null | head -1 | cut -d: -f1)
  first200=$(grep -n 'POST /api/subscribe HTTP/1.1" 200' "$1/aux/server.log" 2>/dev/null | head -1 | cut -d: -f1)
  [ -n "$first415" ] && [ -n "$first200" ] && [ "$first415" -lt "$first200" ] || { echo "the dev server log does not show a 415 and then a 200 for POST /api/subscribe (415 at line '${first415:-none}', 200 at line '${first200:-none}'): the real browser did not hit the service drift and then the fix"; return 1; }
}

# Offline stand-ins (self-test only; the self-test drives a real headless browser). FAKE_MODE: firsttry (right at once) | blindui
# (the browser verification passes whatever it sees) | skipapi (the page composes the message without calling the service, and the
# browser verification is blind)
ui_app_js() { # <fix: 1 = form-encoded body | 0 = the documented JSON body | local = compose without the service>
  local post
  case $1 in
    1) post="fetch('/api/subscribe', {method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: new URLSearchParams({email: email.value.trim(), plan: plan.value}).toString()})" ;;
    0) post="fetch('/api/subscribe', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({email: email.value.trim(), plan: plan.value})})" ;;
  esac
  cat <<R
function validateSignup(email) {
  var v = String(email).trim();
  if (v === '') { return 'Email is required'; }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+\$/.test(v)) { return 'Enter a valid email address'; }
  return '';
}

(function () {
  var form = document.getElementById('signup');
  var email = document.getElementById('email');
  var plan = document.getElementById('plan');
  var errorBox = document.getElementById('email-error');
  var result = document.getElementById('result');
  form.addEventListener('submit', function (ev) {
    ev.preventDefault();
    var message = validateSignup(email.value);
    errorBox.textContent = message;
    result.textContent = '';
    if (message) { return; }
R
  if [ "$1" = local ]; then
    cat <<'R'
    result.textContent = 'Subscribed ' + email.value.trim() + ' to the ' + plan.options[plan.selectedIndex].text + ' plan';
  });
})();
R
  else
    cat <<R
    $post
      .then(function (r) { return r.json().then(function (d) { return {ok: r.ok, d: d}; }); })
      .then(function (x) { if (x.ok) { result.textContent = x.d.message; } else { errorBox.textContent = x.d.error; } })
      .catch(function () { errorBox.textContent = 'The subscription service did not answer'; });
  });
})();
R
  fi
}

case_canned() { # <role> <prompt-file> <cwd> (FAKE_MODE: firsttry | blindui | skipapi)
  local role=$1 prompt=$2 cwd=$3 base shot head out kind
  case $role in
    senior-fullstack)
      base=$(git -C "$cwd" rev-parse HEAD)
      kind=0
      if grep -q '^- feedback:' "$prompt" || [ "${FAKE_MODE:-}" = firsttry ]; then kind=1; fi
      [ "${FAKE_MODE:-}" != skipapi ] || kind=local
      ui_app_js "$kind" > "$cwd/app/app.js"
      git -C "$cwd" add -A && git -C "$cwd" commit -q -m "signup: behaviour" || true
      canned_result "$cwd" "$base" 'Implemented the signup behaviour and committed it.' "$prompt" ;;
    qa)
      if node "$(sed -n 's#^QA acceptance kit: run `node \(.*\)/kit.js.*#\1#p' "$prompt" | head -1)/kit.js" "$cwd" >/dev/null 2>&1; then printf 'Ran the kit: validateSignup passes.\n\n'; canned_verdict PASS "$cwd" '[]'
      else printf 'Kit failed.\n\n'; canned_verdict FAIL "$cwd" '[{"id":"QA-1","severity":"BLOCKER","what":"kit failure","where":"app/app.js"}]'; fi ;;
    ui-qa)
      head=$(git -C "$cwd" rev-parse HEAD)
      shot="$EVIDENCE_DIR/ui-$(printf '%s' "$head" | cut -c1-7).png"
      out=$(ui_judge_run url "$APP_URL" "$shot" 2>&1); kind=$?
      if [ "$kind" -ne 0 ] && [ "${FAKE_MODE:-}" != blindui ] && [ "${FAKE_MODE:-}" != skipapi ]; then
        printf 'Drove the page: a valid submit shows an error instead of the result (screenshot %s).\n\n' "$shot"
        canned_verdict FAIL "$cwd" "$(jq -nc --arg s "$shot" --arg o "$(printf '%s' "$out" | head -5 | tr '\n' ' ')" '[{id: "UIQA-1", severity: "BLOCKER", class: "service-contract-mismatch", what: ("step 3: submitting dana@example.test with the Pro plan shows the service error in the alert region and no result (the service answers 415 Unsupported Media Type: it only accepts application/x-www-form-urlencoded); screenshot " + $s + "; " + $o), where: "app/app.js: POST /api/subscribe", layer: "author"}]')"
      else printf 'Drove the page: all flows behave (screenshot %s).\n\n' "$shot"; canned_verdict PASS "$cwd" '[]'; fi ;;
    code-reviewer) printf 'Small and correct.\n\n'; canned_verdict PASS "$cwd" '[]' ;;
  esac
}
