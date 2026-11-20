# Live contract case: ui-qa, negative variant (the app has a seeded user-visible defect; the role must FAIL it).
#
# Fixture: a tiny static newsletter-signup page (app/index.html + app/app.js) on branch feature/signup, base main.
# case_serve serves app/ with python3 -m http.server on a free port (server log kept in the aux dir) and gives
# the worker a private chrome-devtools-axi session name, so concurrent runs never share a browser.
# Seeded defect: the form has no `novalidate`, and the email input carries `required`, so in a real browser an
# EMPTY submit is stopped by the browser own bubble: the inline message "Email is required" the acceptance asks
# for never renders (and no result appears). Reading app.js alone shows a correct validate(); only driving the
# page shows nothing happens.
# Outside judge (deterministic): the verdict block is valid and FAIL, bound to the head sha; a BLOCKER/IMPORTANT
# item names the empty-email / missing-message defect; calls.tsv shows chrome-devtools-axi driving (open or newpage,
# an interaction, a screenshot); the server log shows the page script was fetched; a PNG the report names exists in
# the evidence dir and is a real PNG (magic bytes, IHDR >= 100x100, IDAT, IEND); tracked files unchanged and HEAD
# unmoved; the browser session is stopped at the end (so no browser leaks).
# ui-qa-pass.sh sources this file and overrides the defect, the prompt wording that depends on it, the judge and
# the canned workers.
CASE_ROLE=ui-qa
CASE_AGENTS=""
CASE_BLOCK=verdict
CASE_NEEDS='chrome-devtools-axi python3 curl'
CASE_TIMEOUT=900
UIQA_DEFECT=1
CASE_PROMPT='Verify the browser-visible behavior of the newsletter signup form on branch feature/signup (base main); the head commit is HEAD_SHA in the environment facts below.
The app is ALREADY running at APP_URL: do not start another server. Your browser is the chrome-devtools-axi CLI on PATH (run it from the shell; chrome-devtools-axi --help lists its commands).
Acceptance:
1. Submitting the form with an empty email shows the inline message "Email is required" in the page (the alert region under the field) and no subscription result.
2. Submitting an email without an @ shows the inline message "Enter a valid email address" and no result.
3. Submitting dana@example.test with the Pro plan shows the result "Subscribed dana@example.test to the Pro plan".
Save at least one screenshot of what you observed as a PNG file inside EVIDENCE_DIR (an absolute path; give the screenshot command that path) and name that file path in your report.
Do not edit anything in the repository.'

uiqa_app() { # <defect 1|0>
  local formattr='' inputattr='required'
  [ "$1" = 1 ] || formattr=' novalidate'
  mkdir -p app
  cat > app/index.html <<EOF
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
<form id="signup"$formattr>
  <label for="email">Email</label>
  <input id="email" name="email" type="text" inputmode="email" $inputattr aria-describedby="email-error" autocomplete="off">
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
  cat > app/app.js <<'EOF'
(function () {
  'use strict';
  var form = document.getElementById('signup');
  var email = document.getElementById('email');
  var plan = document.getElementById('plan');
  var errorBox = document.getElementById('email-error');
  var result = document.getElementById('result');

  function validate(value) {
    if (value.trim() === '') { return 'Email is required'; }
    if (value.indexOf('@') < 1) { return 'Enter a valid email address'; }
    return '';
  }

  form.addEventListener('submit', function (ev) {
    ev.preventDefault();
    var value = email.value.trim();
    var message = validate(value);
    errorBox.textContent = message;
    if (message) {
      result.textContent = '';
      email.setAttribute('aria-invalid', 'true');
      return;
    }
    email.removeAttribute('aria-invalid');
    var label = plan.options[plan.selectedIndex].text;
    result.textContent = 'Subscribed ' + value + ' to the ' + label + ' plan';
  });
})();
EOF
}

case_setup() {
  git symbolic-ref HEAD refs/heads/main
  cat > README.md <<'EOF'
# signup-page
A static page: app/index.html + app/app.js, served as plain files from app/ on the dev URL given in the task.
There is no build step and there are no unit tests; the form is verified in a browser.
EOF
  git add -A && git commit -q -m 'base: readme'
  git checkout -q -b feature/signup
  uiqa_app "$UIQA_DEFECT"
  git add -A && git commit -q -m 'add newsletter signup form'
}

case_serve() { # <repo> <aux>
  local repo=$1 aux=$2 port sid i
  port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()') || return 1
  mkdir -p "$repo/evidence"
  printf 'evidence/\n' >> "$repo/.git/info/exclude"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$repo/app" > "$aux/server.log" 2>&1 < /dev/null &
  echo $! >> "$aux/pids"
  i=0
  until curl -s -o /dev/null "http://127.0.0.1:$port/"; do
    i=$((i + 1)); [ "$i" -lt 50 ] || { echo "http server did not start" >&2; return 1; }
    sleep 0.2
  done
  sid=$(basename "$(dirname "$aux")")
  echo "APP_URL=http://127.0.0.1:$port/"
  echo "EVIDENCE_DIR=$repo/evidence"
  echo "CHROME_DEVTOOLS_AXI_SESSION=ct-${sid//[^A-Za-z0-9]/-}"
  echo "HEAD_SHA=$(git -C "$repo" rev-parse HEAD)"
}

uiqa_png_ok() { # <file>: a real PNG (magic, IHDR >= 100x100, IDAT, IEND)
  python3 - "$1" <<'PY'
import struct, sys
b = open(sys.argv[1], 'rb').read()
ok = (len(b) >= 100 and b[:8] == b'\x89PNG\r\n\x1a\n' and b[12:16] == b'IHDR'
      and b'IDAT' in b and b.endswith(b'IEND\xaeB`\x82'))
if ok:
    w, h = struct.unpack('>II', b[16:24])
    ok = w >= 100 and h >= 100
sys.exit(0 if ok else 1)
PY
}

uiqa_sha_matches() { # <a> <b>: one is a >=7-hex prefix of the other
  case $1 in ''|null) return 1 ;; esac
  [ "${#1}" -ge 7 ] || return 1
  case $2 in "$1"*) return 0 ;; esac
  case $1 in "$2"*) return 0 ;; esac
  return 1
}

# uiqa_common <repo> <run> <aux> <expected verdict>: every check that does not depend on the seeded defect.
uiqa_common() {
  local repo=$1 run=$2 aux=$3 want=$4 verdict commit head png found='' f
  chrome-devtools-axi stop > /dev/null 2>&1 || true
  verdict=$(block_json | jq -r '.verdict // empty')
  [ "$verdict" = "$want" ] || { echo "verdict is '$verdict', expected $want"; return 1; }
  head=$(git -C "$repo" rev-parse HEAD)
  commit=$(block_json | jq -r '.commit // empty')
  uiqa_sha_matches "$commit" "$head" || { echo "verdict commit '$commit' is not the head $head"; return 1; }
  [ -z "$(git -C "$repo" status --porcelain --untracked-files=no)" ] || { echo "tracked files changed: $(changed_files | tr '\n' ' ')"; return 1; }
  call_has 'chrome-devtools-axi' || { echo "no chrome-devtools-axi call: the app was not driven in a real browser"; return 1; }
  # a worker may alias the CLI (A=chrome-devtools-axi; $A click ...), so match the verb after the name anywhere in the call
  call_has 'chrome-devtools-axi.*(open|newpage) +\\?"?https?://' || { echo "the browser never opened a page (no chrome-devtools-axi open/newpage URL)"; return 1; }
  call_has 'chrome-devtools-axi.*(click|fill|fillform|type|press|eval) +[@\\"(a-zA-Z]' || { echo "no browser interaction (click/fill/type/press/eval): only page-load evidence"; return 1; }
  call_has 'chrome-devtools-axi.*screenshot' || { echo "no chrome-devtools-axi screenshot command"; return 1; }
  grep -q 'GET /app.js' "$aux/server.log" 2>/dev/null || { echo "the server never saw GET /app.js: the page was not loaded"; return 1; }
  for png in $(grep -oE '[A-Za-z0-9._/~-]+\.png' "$run/final.txt" | sort -u); do
    f="${EVIDENCE_DIR:-$repo/evidence}/$(basename "$png")"
    if [ -f "$f" ] && uiqa_png_ok "$f"; then found=$f; break; fi
  done
  [ -n "$found" ] || { echo "the report names no screenshot that exists in the evidence dir as a real PNG (named: $(grep -oE '[A-Za-z0-9._/~-]+\.png' "$run/final.txt" | sort -u | tr '\n' ' '))"; return 1; }
  UIQA_SHOT=$found
  return 0
}

case_grade() {
  local repo=$1 run=$2 aux=$3 hit
  uiqa_common "$repo" "$run" "$aux" FAIL || return 1
  # a blocking item that names the empty-email / missing inline message defect
  hit=$(block_json | jq -r '.feedback[] | select(.severity == "BLOCKER" or .severity == "IMPORTANT") | ((.what // "") + " " + (.where // "") + " " + (.class // ""))' \
    | grep -Ei '(empty|blank|required|no email|without (an )?email|missing email)' | grep -Eic '(error|message|validation|inline|alert|nothing|not (shown|displayed|appear|render|visible)|never|no (visible|inline))')
  [ "${hit:-0}" -ge 1 ] || { echo "no BLOCKER/IMPORTANT item names the empty-email validation message that never renders"; return 1; }
  echo "FAIL bound to head, the empty-email defect named, real browser driven (screenshot $(basename "$UIQA_SHOT") is a real PNG), tracked files unchanged"
}

uiqa_canned_browser() { # shared canned calls + a real PNG in the evidence dir
  local aux=$4 shot
  [ ! -f "$aux/env" ] || { set -a; . "$aux/env"; set +a; }
  shot="$EVIDENCE_DIR/ui-qa-1.png"
  python3 - "$shot" <<'PY'
import struct, sys, zlib
def chunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
w, h = 320, 240
raw = b''.join(b'\x00' + b'\xff\xff\xff' * w for _ in range(h))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)
PY
  curl -s -o /dev/null "${APP_URL}app.js"
  {
    printf 'bash\t{"command": "git rev-parse HEAD"}\n'
    printf 'bash\t{"command": "chrome-devtools-axi --help"}\n'
    printf 'bash\t{"command": "chrome-devtools-axi open %s"}\n' "$APP_URL"
    printf 'bash\t{"command": "chrome-devtools-axi click @g1:1_5"}\n'
    printf 'bash\t{"command": "chrome-devtools-axi snapshot"}\n'
    printf 'bash\t{"command": "chrome-devtools-axi screenshot %s"}\n' "$shot"
  } >> "$2/calls.tsv"
  UIQA_CANNED_SHOT=$shot
}

case_canned() { # good|bad <repo> <run> <aux>
  local mode=$1 repo=$2 run=$3 aux=$4 head
  head=$(git -C "$repo" rev-parse HEAD)
  if [ "$mode" = good ]; then
    uiqa_canned_browser "$mode" "$run" "$repo" "$aux"
    cat > "$run/final.txt" <<EOF
Head $head. Plan: step 1 empty submit, Expected: inline "Email is required"; step 2 no-@ submit; step 3 valid submit.
Observed: step 1 clicked Subscribe with an empty email: nothing rendered, the alert region stayed empty (screenshot $UIQA_CANNED_SHOT).
\`\`\`verdict
{"verdict": "FAIL", "commit": "$head", "feedback": [
  {"id": "UIQA-1", "severity": "BLOCKER", "class": "missing-validation-message", "what": "step 1: submitting an empty email shows no inline error message at all (alert region empty, no result); screenshot $UIQA_CANNED_SHOT", "where": "signup form submit", "layer": "author"}
]}
\`\`\`
EOF
  else
    printf 'read\t{"path": "app/app.js"}\n' >> "$run/calls.tsv"
    cat > "$run/final.txt" <<EOF
Read app.js: validate() returns the right messages, looks fine. Head $head.
\`\`\`verdict
{"verdict": "PASS", "commit": "$head", "feedback": []}
\`\`\`
EOF
  fi
}
