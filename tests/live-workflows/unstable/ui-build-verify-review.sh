# Live workflow case (xi): ui-build-verify-review - the real-browser gate catches what the browser-free checks cannot.
# Needs chrome-devtools-axi (and node for the kit): SKIPPED, never PASSED, when one is absent.
# Problem: the newsletter signup page (app/index.html + app/app.js, served by the driver for the whole case) has its markup in place:
#   the form carries type="email" + required and no novalidate. The ticket asks for the behaviour in app.js: inline validation messages
#   ("Email is required", "Enter a valid email address") in the alert region, no result on an invalid submit, and the result line on a
#   valid one, plus a global validateSignup(email). The natural implementation writes a submit handler - which a REAL browser never
#   runs for an empty or malformed email, because the native constraint validation stops the submit first. QA's kit (node, browser-free)
#   exercises validateSignup and passes; only driving the page shows that nothing renders.
# Forced loop: implement -> classify -> qa PASS -> ui-verify FAIL (real browser, screenshot evidence) -> implement (fixes from that
#   feedback) -> classify -> qa PASS -> ui-verify PASS -> review PASS -> ship PASS -> deliver.
# Outside judge (deterministic, browser-free): the hidden check = the node kit (validateSignup) + a static scan of index.html (the form
#   must not be blocked by native validation: novalidate, or no required/type=email on the email input) + app.js still loaded; it FAILS
#   after the first implementation while the kit alone passes. case_assert: the path has ui-verify:fail then ui-verify:pass; the ui-verify
#   failure names the missing inline message; the screenshot its report names exists in the evidence dir and is a real PNG (magic bytes,
#   IHDR >= 100x100, IDAT, IEND); in a live run the ui-verify transcripts show chrome-devtools-axi opening the page, interacting and taking
#   a screenshot, and the server log shows the page script was fetched. Control: the fix round without the feedback must not fix it.
CASE_WORKFLOW=ui-build-verify-review
CASE_NEEDS='chrome-devtools-axi python3 curl node'
CASE_TASK='The newsletter signup page (app/index.html, app/app.js) has its markup but no behaviour yet. Implement it in app.js. Acceptance: (1) submitting the form with an empty email shows the inline message "Email is required" in the alert region under the field and no subscription result; (2) submitting an email without an @ shows "Enter a valid email address" and no result; (3) submitting dana@example.test with the Pro plan shows the result "Subscribed dana@example.test to the Pro plan" and no error message. app.js must also define a global function validateSignup(email) returning the message for an invalid email and an empty string for a valid one. Keep the change small.'
CASE_CONTROL_STEP=implement
CASE_CONTROL_RUN=2
CASE_CONTROL_STRIP=feedback
CASE_EXPECT_PATH='^implement:done classify:(low|medium|high) qa:pass ui-verify:fail( .*)? ui-verify:pass( .*)? ship:pass deliver:done$'
CASE_FORCE_AFTER=implement:1
CASE_FORCE_KIT_PASS=1
CASE_NEGATIVE='firsttry => the loop was not forced
blindui => FAIL - the final repository does not satisfy the hidden acceptance check'

ui_html() { # <form attributes>
  cat <<EOF
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
<form id="signup"$1>
  <label for="email">Email</label>
  <input id="email" name="email" type="email" required aria-describedby="email-error" autocomplete="off">
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
EOF
}

case_setup() {
  mkdir -p app
  cat > README.md <<'R'
# signup-page
A static page: app/index.html + app/app.js, served as plain files from app/ on the dev URL given in the task.
There is no build step and there are no unit tests; the form is verified in a browser.
R
  ui_html '' > app/index.html
  printf '// signup behaviour goes here\n' > app/app.js
}

# the services: a no-store static server over the live repository's app/ directory (it always serves the current head), a unique
# browser session name, and an evidence directory
case_serve() { # <repo> <aux>
  local repo=$1 aux=$2 port i
  port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()') || return 1
  mkdir -p "$aux/evidence"
  cat > "$aux/server.py" <<'R'
import functools, http.server, sys
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), functools.partial(H, directory=sys.argv[2])).serve_forever()
R
  python3 "$aux/server.py" "$port" "$repo/app" > "$aux/server.log" 2>&1 < /dev/null &
  echo $! >> "$aux/pids"
  i=0
  until curl -s -o /dev/null "http://127.0.0.1:$port/"; do
    i=$((i + 1)); [ "$i" -lt 50 ] || { echo "http server did not start" >&2; return 1; }
    sleep 0.2
  done
  echo "APP_URL=http://127.0.0.1:$port/"
  echo "EVIDENCE_DIR=$aux/evidence"
  echo "CHROME_DEVTOOLS_AXI_SESSION=wl-$(basename "$aux" | tr -c 'A-Za-z0-9\n' '-')"
}

case_stop() { # <aux>
  local sid
  [ -z "${SELFTEST_MODE:-}" ] && command -v chrome-devtools-axi >/dev/null 2>&1 || return 0
  sid=$(sed -n 's/^CHROME_DEVTOOLS_AXI_SESSION=//p' "$1/env" 2>/dev/null | head -1)
  [ -z "$sid" ] || CHROME_DEVTOOLS_AXI_SESSION=$sid chrome-devtools-axi stop >/dev/null 2>&1
  return 0
}

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
const ctx = { document: stub(), console: console, localStorage: stub(), setTimeout: () => 0 };
ctx.window = ctx;
vm.createContext(ctx);
try { vm.runInContext(src, ctx); } catch (e) { console.log('FAIL app.js throws when it is loaded: ' + e); process.exit(1); }
if (typeof ctx.validateSignup !== 'function') { console.log('FAIL app.js does not define a global function validateSignup(email)'); process.exit(1); }
const cases = [['', 'Email is required'], ['   ', 'Email is required'], ['dana', 'Enter a valid email address'], ['@x.test', 'Enter a valid email address'], ['dana@example.test', '']];
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

# the static scan: native constraint validation must not be able to stop the submit before the page script runs
ui_static() { # <repo>: prints a NATIVE line when the form can be blocked natively
  python3 - "$1/app/index.html" <<'R'
import sys
from html.parser import HTMLParser
class P(HTMLParser):
    form = None; email = None; script = False
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "form" and a.get("id") == "signup": self.form = a
        if tag == "input" and a.get("id") == "email": self.email = a
        if tag == "script" and (a.get("src") or "").endswith("app.js"): self.script = True
try:
    p = P(); p.feed(open(sys.argv[1], encoding="utf-8").read())
except Exception as e:
    print("NATIVE index.html unreadable: %r" % (e,)); sys.exit(0)
if p.form is None or p.email is None: print("NATIVE the signup form or the email input is gone")
elif "novalidate" not in p.form and ("required" in p.email or (p.email.get("type") or "").lower() == "email"):
    print("NATIVE the form has no novalidate and the email input is required/type=email: the browser stops an empty or malformed submit before the page script runs, so no inline message can render")
if not p.script: print("NATIVE index.html no longer loads app.js")
R
}

case_hidden() { # <repo> <kit-dir>
  local s
  node "$2/kit.js" "$1" > "$RUN/hidden.last" 2>&1 || return 1
  s=$(ui_static "$1")
  [ -z "$s" ] || { printf '%s\n' "$s" >> "$RUN/hidden.last"; return 1; }
}

case_extra() { # <step> <role> <iteration> <kit-dir> <cwd> <data-dir>
  case $2 in
    qa) printf 'QA acceptance kit: run `node %s/kit.js .` from your working directory (it is the repository under test); it checks validateSignup in app.js without a browser. A failing expectation is a FAIL. Then do the rest of your QA as usual; a browser check follows in the next step.\n' "$4" ;;
    ui-qa) printf 'Environment facts for the browser verification: the app is ALREADY running at APP_URL=%s and serves the repository head under test: do not start another server (this overrides the general no-network note: that one localhost URL is allowed). Your browser is the chrome-devtools-axi CLI on PATH (run it from bash; chrome-devtools-axi --help lists its commands); CHROME_DEVTOOLS_AXI_SESSION=%s is already set in your environment, keep it for every call. Save at least one screenshot of what you observed as a PNG file inside EVIDENCE_DIR=%s (an absolute path: give the screenshot command that path) and name that file path in your report. Do not edit anything in the repository.\n' "$(svc_get APP_URL)" "$(svc_get CHROME_DEVTOOLS_AXI_SESSION)" "$(svc_get EVIDENCE_DIR)" ;;
  esac
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

case_assert() { # <run-dir> <repo>
  local st=$1/data/workflow.json d f png found fb
  jq -e '[.history[] | select(.step == "ui-verify") | .outcome] | (index("fail") // 99) < (index("pass") // -1)' "$st" >/dev/null || { echo "ui-verify did not fail and then pass: $(jq -c '[.history[] | select(.step == "ui-verify") | .outcome]' "$st")"; return 1; }
  fb=$(jq -r '[.history[] | select(.step == "ui-verify" and .outcome == "fail") | .feedback[]? | .what + " " + .where + " " + (.class // "")] | join("\n")' "$st")
  printf '%s' "$fb" | grep -qiE 'empty|blank|required|valid|message|inline|alert|submit' || { echo "the ui-verify failure does not name the missing inline message"; return 1; }
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
      grep -qE 'chrome-devtools-axi.*(open|newpage) +\\?"?https?://' "$d/calls.tsv" || { echo "$(basename "$d"): the browser never opened the page (no chrome-devtools-axi open/newpage URL)"; return 1; }
      grep -qE 'chrome-devtools-axi.*(click|fill|fillform|type|press|eval) +[@\\"(a-zA-Z]' "$d/calls.tsv" || { echo "$(basename "$d"): no browser interaction (click/fill/type/press/eval)"; return 1; }
      grep -qE 'chrome-devtools-axi.*screenshot' "$d/calls.tsv" || { echo "$(basename "$d"): no chrome-devtools-axi screenshot command"; return 1; }
    fi
  done
  grep -q 'GET /app.js' "$1/aux/server.log" 2>/dev/null || { echo "the server never saw GET /app.js: the page was not loaded by a browser"; return 1; }
}

ui_write_png() { # <path>
  python3 - "$1" <<'R'
import struct, sys, zlib
def chunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
w, h = 320, 240
raw = b''.join(b'\x00' + b'\xff\xff\xff' * w for _ in range(h))
open(sys.argv[1], 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
R
}

case_canned() { # <role> <prompt-file> <cwd> (FAKE_MODE: firsttry | blindui)
  local role=$1 prompt=$2 cwd=$3 base s shot head
  case $role in
    senior-fullstack)
      base=$(git -C "$cwd" rev-parse HEAD)
      cat > "$cwd/app/app.js" <<'R'
function validateSignup(email) {
  var v = String(email).trim();
  if (v === '') { return 'Email is required'; }
  if (v.indexOf('@') < 1) { return 'Enter a valid email address'; }
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
    result.textContent = message ? '' : 'Subscribed ' + email.value.trim() + ' to the ' + plan.options[plan.selectedIndex].text + ' plan';
  });
})();
R
      if { grep -q '^- feedback:' "$prompt"; } || [ "${FAKE_MODE:-}" = firsttry ]; then ui_html ' novalidate' > "$cwd/app/index.html"; fi
      git -C "$cwd" add -A && git -C "$cwd" commit -q -m "signup: behaviour" || true
      canned_result "$cwd" "$base" 'Implemented the signup behaviour and committed it.' "$prompt" ;;
    qa)
      if node "$(sed -n 's#^QA acceptance kit: run `node \(.*\)/kit.js.*#\1#p' "$prompt" | head -1)/kit.js" "$cwd" >/dev/null 2>&1; then printf 'Ran the kit: validateSignup passes.\n\n'; canned_verdict PASS "$cwd" '[]'
      else printf 'Kit failed.\n\n'; canned_verdict FAIL "$cwd" '[{"id":"QA-1","severity":"BLOCKER","what":"kit failure","where":"app/app.js"}]'; fi ;;
    ui-qa)
      head=$(git -C "$cwd" rev-parse HEAD)
      shot="$EVIDENCE_DIR/ui-$(printf '%s' "$head" | cut -c1-7).png"
      ui_write_png "$shot"
      curl -s -o /dev/null "${APP_URL}app.js"
      s=$(ui_static "$cwd")
      if [ -n "$s" ] && [ "${FAKE_MODE:-}" != blindui ]; then
        printf 'Drove the page: an empty submit rendered nothing (screenshot %s).\n\n' "$shot"
        canned_verdict FAIL "$cwd" "$(jq -nc --arg s "$shot" '[{id: "UIQA-1", severity: "BLOCKER", class: "missing-validation-message", what: ("step 1: submitting an empty email shows no inline message \"Email is required\" (alert region empty, no result); screenshot " + $s), where: "signup form submit", layer: "author"}]')"
      else printf 'Drove the page: all three flows behave (screenshot %s).\n\n' "$shot"; canned_verdict PASS "$cwd" '[]'; fi ;;
    code-reviewer) printf 'Small and correct.\n\n'; canned_verdict PASS "$cwd" '[]' ;;
  esac
}
