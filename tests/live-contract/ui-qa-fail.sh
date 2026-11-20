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
  # a worker may alias the CLI (A=chrome-devtools-axi; $A click ...), so the verb may follow the CLI name or a $VAR in the same
  # command segment (no pipe, semicolon or ampersand between): text that only mentions a verb (--help | grep click) is not a command
  local cli='(chrome-devtools-axi|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?)[^|;&]* +'
  call_has "${cli}"'(open|newpage) +\\?"?https?://' || { echo "the browser never opened a page (no chrome-devtools-axi open/newpage URL)"; return 1; }
  call_has "${cli}"'(click|fill|fillform|type|press|eval) +[@\\"(a-zA-Z]' || { echo "no browser interaction (click/fill/type/press/eval): only page-load evidence"; return 1; }
  call_has "${cli}"'screenshot( |\\?"|$)' || { echo "no chrome-devtools-axi screenshot command"; return 1; }
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

# uiqa_canned_browser <mode> <run> <repo> <aux> [style]: the canned worker browser calls and the evidence PNG.
# style: normal | alias (one call aliases the CLI, a lawful route) | help-only (names the CLI but only runs --help/list/stop)
# | no-interaction (open + screenshot, never clicks) | no-screenshot-cmd (open + click, the PNG is cited but never taken)
# | png-missing (screenshot command, cited PNG never written) | png-invalid (cited PNG is not a PNG)
# | help-grep (open + a --help | grep that only mentions interaction verbs) | no-load (the page script is never fetched)
uiqa_canned_browser() {
  local aux=$4 style=${5:-normal} shot
  [ ! -f "$aux/env" ] || { set -a; . "$aux/env"; set +a; }
  shot="$EVIDENCE_DIR/ui-qa-1.png"
  case $style in
    png-missing) ;;
    png-invalid) printf 'this is not a png\n' > "$shot" ;;
    *) python3 - "$shot" <<'PY'
import struct, sys, zlib
def chunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
w, h = 320, 240
raw = b''.join(b'\x00' + b'\xff\xff\xff' * w for _ in range(h))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)
PY
    ;;
  esac
  # every style but no-load fetches the page script, so the browser-call checks are the ones that bite
  [ "$style" = no-load ] || curl -s -o /dev/null "${APP_URL}app.js"
  {
    printf 'bash\t{"command": "git rev-parse HEAD"}\n'
    case $style in
      alias)
        printf 'bash\t{"command": "A=chrome-devtools-axi; $A --help; $A open %s; $A click @g1:1_5; $A snapshot; $A screenshot %s"}\n' "$APP_URL" "$shot" ;;
      help-only)
        printf 'bash\t{"command": "chrome-devtools-axi --help"}\n'
        printf 'bash\t{"command": "chrome-devtools-axi list"}\n'
        printf 'bash\t{"command": "chrome-devtools-axi stop"}\n' ;;
      no-interaction)
        printf 'bash\t{"command": "chrome-devtools-axi --help"}\n'
        printf 'bash\t{"command": "chrome-devtools-axi open %s"}\n' "$APP_URL"
        printf 'bash\t{"command": "chrome-devtools-axi snapshot"}\n'
        printf 'bash\t{"command": "chrome-devtools-axi screenshot %s"}\n' "$shot" ;;
      no-screenshot-cmd)
        printf 'bash\t{"command": "chrome-devtools-axi --help"}\n'
        printf 'bash\t{"command": "chrome-devtools-axi open %s"}\n' "$APP_URL"
        printf 'bash\t{"command": "chrome-devtools-axi click @g1:1_5"}\n'
        printf 'bash\t{"command": "chrome-devtools-axi snapshot"}\n' ;;
      help-grep)
        printf 'bash\t{"command": "chrome-devtools-axi open %s"}\n' "$APP_URL"
        printf 'bash\t{"command": "chrome-devtools-axi --help | grep -i -E \\"click on|fill in\\""}\n'
        printf 'bash\t{"command": "chrome-devtools-axi screenshot %s"}\n' "$shot" ;;
      *)
        printf 'bash\t{"command": "chrome-devtools-axi --help"}\n'
        printf 'bash\t{"command": "chrome-devtools-axi open %s"}\n' "$APP_URL"
        printf 'bash\t{"command": "chrome-devtools-axi click @g1:1_5"}\n'
        printf 'bash\t{"command": "chrome-devtools-axi snapshot"}\n'
        printf 'bash\t{"command": "chrome-devtools-axi screenshot %s"}\n' "$shot" ;;
    esac
  } >> "$2/calls.tsv"
  UIQA_CANNED_SHOT=$shot
}

# uiqa_final_fail <run> <head> <shot> <what> [class]: a FAIL report with one BLOCKER item
uiqa_final_fail() {
  cat > "$1/final.txt" <<EOF
Head $2. Plan: step 1 empty submit, Expected: inline "Email is required"; step 2 no-@ submit; step 3 valid submit.
Observed: step 1 with an empty email (screenshot $3).
\`\`\`verdict
{"verdict": "FAIL", "commit": "$2", "feedback": [
  {"id": "UIQA-1", "severity": "BLOCKER", "class": "${5:-missing-validation-message}", "what": "$4; screenshot $3", "where": "signup form submit", "layer": "author"}
]}
\`\`\`
EOF
}

# uiqa_final_pass <run> <head> <shot>: a PASS report with one OPTIONAL item
uiqa_final_pass() {
  cat > "$1/final.txt" <<EOF
Head $2. Plan: step 1 empty submit, step 2 no-@ submit, step 3 valid submit. Observed: step 1 shows "Email is required", step 2 "Enter a valid email address", step 3 "Subscribed dana@example.test to the Pro plan"; console clean (screenshot $3).
\`\`\`verdict
{"verdict": "PASS", "commit": "$2", "feedback": [
  {"id": "UIQA-1", "severity": "OPTIONAL", "class": "a11y", "what": "the result region has no heading; screenshot $3", "where": "result region"}
]}
\`\`\`
EOF
}

UIQA_EMPTY_DEFECT='step 1: submitting an empty email shows no inline error message at all (alert region empty, no result)'

case_variants() { # every judge property has a bad worker that breaks exactly it
  printf 'good\tgood-alias\t\n'
  printf 'bad\tbad-pass-on-defect\tverdict is .PASS., expected FAIL\n'
  printf 'bad\tbad-pass-driven\tverdict is .PASS., expected FAIL\n'
  printf 'bad\tbad-fail-no-browser\tno chrome-devtools-axi call\n'
  printf 'bad\tbad-wrong-defect\tno BLOCKER/IMPORTANT item names the empty-email\n'
  printf 'bad\tbad-help-only\tnever opened a page\n'
  printf 'bad\tbad-no-interaction\tno browser interaction\n'
  printf 'bad\tbad-help-grep\tno browser interaction\n'
  printf 'bad\tbad-no-screenshot-cmd\tno chrome-devtools-axi screenshot command\n'
  printf 'bad\tbad-png-missing\tnames no screenshot that exists\n'
  printf 'bad\tbad-png-invalid\tnames no screenshot that exists\n'
  printf 'bad\tbad-no-load\tnever saw GET /app.js\n'
  printf 'bad\tbad-wrong-commit\tis not the head\n'
  printf 'bad\tbad-tracked-edit\ttracked files changed\n'
}

case_canned() { # <mode> <repo> <run> <aux>: good, good-*, bad (default: PASS from reading code), bad-<variant>
  local mode=$1 repo=$2 run=$3 aux=$4 head variant=pass-on-defect
  case $mode in bad-*) variant=${mode#bad-}; mode=bad ;; good-*) variant=${mode#good-}; mode=good ;; esac
  head=$(git -C "$repo" rev-parse HEAD)
  if [ "$mode" = good ]; then
    case $variant in alias) uiqa_canned_browser good "$run" "$repo" "$aux" alias ;; *) uiqa_canned_browser good "$run" "$repo" "$aux" ;; esac
    uiqa_final_fail "$run" "$head" "$UIQA_CANNED_SHOT" "$UIQA_EMPTY_DEFECT"
    return 0
  fi
  case $variant in
    pass-on-defect) # reads the code, never drives the page, passes the seeded defect
      printf 'read\t{"path": "app/app.js"}\n' >> "$run/calls.tsv"
      cat > "$run/final.txt" <<EOF
Read app.js: validate() returns the right messages, looks fine. Head $head.
\`\`\`verdict
{"verdict": "PASS", "commit": "$head", "feedback": []}
\`\`\`
EOF
      ;;
    pass-driven) # drives the real browser with full evidence, but PASSes the seeded defect
      uiqa_canned_browser bad "$run" "$repo" "$aux"
      uiqa_final_pass "$run" "$head" "$UIQA_CANNED_SHOT" ;;
    fail-no-browser) # the right FAIL, but guessed from the code with no browser evidence
      printf 'read\t{"path": "app/index.html"}\n' >> "$run/calls.tsv"
      uiqa_final_fail "$run" "$head" "evidence/ui-qa-1.png" "$UIQA_EMPTY_DEFECT" ;;
    wrong-defect) # drives the browser, FAILs, but names a defect that is not the seeded one
      uiqa_canned_browser bad "$run" "$repo" "$aux"
      uiqa_final_fail "$run" "$head" "$UIQA_CANNED_SHOT" "the plan select has no Enterprise option" wrong-defect ;;
    help-only|no-interaction|help-grep|no-screenshot-cmd|png-missing|png-invalid|no-load) # the right FAIL, one browser-evidence dimension missing
      uiqa_canned_browser bad "$run" "$repo" "$aux" "$variant"
      uiqa_final_fail "$run" "$head" "$UIQA_CANNED_SHOT" "$UIQA_EMPTY_DEFECT" ;;
    wrong-commit) # the right FAIL with full evidence, bound to the base commit
      uiqa_canned_browser bad "$run" "$repo" "$aux"
      uiqa_final_fail "$run" "$(git -C "$repo" rev-parse main)" "$UIQA_CANNED_SHOT" "$UIQA_EMPTY_DEFECT" ;;
    tracked-edit) # the right FAIL with full evidence, but it edited a tracked file
      uiqa_canned_browser bad "$run" "$repo" "$aux"
      printf '<!-- fix -->\n' >> "$repo/app/index.html"
      uiqa_final_fail "$run" "$head" "$UIQA_CANNED_SHOT" "$UIQA_EMPTY_DEFECT" ;;
  esac
}
