# Live workflow case (x): a FALSE PREMISE ends the work early with change-direction (build-test-review, the redirect decision).
# Problem: the ticket says there is a cache bug in cache.py: after catalogue.set_price("widget", 300) the catalogue still shows 250.
#   The premise is false: cache.py is correct (set_price invalidates the key and the TTL cache is tested), the stale value comes from a
#   config override (config/overrides.json pins widget at 250 for a promotion) that load_price applies before the real price. The
#   implementer must establish that and end change-direction EARLY - the wrong premise stated with evidence - instead of building a
#   doomed change in cache.py. The driver answers the redirect decision with CASE_DECIDE_REDIRECT=close (the default stays escalate).
# Expected: implement (change-direction, no commit) -> redirect decision -> close; the workflow ends closed, nothing is delivered.
# Outside judge (deterministic): the engine state is closed with the path implement:change-direction redirect:close; the repository holds
#   no commit beyond the fixture and a clean tree; the recorded direction names the false premise (the override, config/overrides.json,
#   and that cache.py is not the cause) - checked with a keyword set; and case_assert proves the premise really is false in the fixture
#   (clearing the cache entirely still shows the stale value). Negatives: an implementer that builds a doomed cache change and reports
#   done is caught; a change-direction that does not state the premise is caught.
CASE_WORKFLOW=build-test-review
CASE_TASK='Fix the cache bug in cache.py: after catalogue.set_price("widget", 300) the catalogue still shows the old price 250 for the same sku, so cache.py serves a stale value. Make the catalogue show the new price and add a regression test under tests/.'
CASE_NO_CONTROL=1
CASE_EXPECT_STATUS=closed
CASE_DECIDE_REDIRECT=close
CASE_DECIDE_REASON='mechanical rule: the reported premise (a cache bug in cache.py) is false, so there is nothing to build: close the task and report why'
CASE_EXPECT_PATH='^implement:change-direction redirect:close$'
CASE_FORCE_AFTER=''
CASE_NEGATIVE='build => the workflow ended closed
shallow => the recorded direction does not state the false premise'

case_setup() {
  mkdir -p tests config
  cat > README.md <<'R'
# catalogue
Product prices with a small TTL cache. Tests: python3 -m unittest discover -s tests
Prices can be pinned by a promotion in config/overrides.json (applied by config.py).
R
  cat > config/overrides.json <<'R'
{"widget": 250}
R
  cat > config.py <<'R'
import json
import os

_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config", "overrides.json")


def overrides():
    """Prices pinned for a promotion (sku -> cents); they win over the catalogue price."""
    with open(_PATH) as f:
        return json.load(f)
R
  cat > cache.py <<'R'
import time

_CACHE = {}


def get(key, loader, ttl=60, now=time.monotonic):
    entry = _CACHE.get(key)
    if entry is not None and now() - entry[0] < ttl:
        return entry[1]
    value = loader()
    _CACHE[key] = (now(), value)
    return value


def invalidate(key):
    _CACHE.pop(key, None)
R
  cat > prices.py <<'R'
import config

PRICES = {"widget": 250, "gadget": 990}


def load_price(sku):
    pinned = config.overrides()
    if sku in pinned:
        return pinned[sku]
    return PRICES[sku]
R
  cat > catalogue.py <<'R'
import cache
import prices


def price(sku):
    return cache.get("price:" + sku, lambda: prices.load_price(sku))


def set_price(sku, cents):
    prices.PRICES[sku] = cents
    cache.invalidate("price:" + sku)
R
  cat > tests/test_cache.py <<'R'
import unittest
import cache


class Cache(unittest.TestCase):
    def setUp(self):
        cache._CACHE.clear()

    def test_hit_within_ttl(self):
        calls = []
        loader = lambda: calls.append(1) or len(calls)
        self.assertEqual(cache.get("k", loader, now=lambda: 0), 1)
        self.assertEqual(cache.get("k", loader, now=lambda: 10), 1)

    def test_expires_after_ttl(self):
        calls = []
        loader = lambda: calls.append(1) or len(calls)
        cache.get("k", loader, ttl=5, now=lambda: 0)
        self.assertEqual(cache.get("k", loader, ttl=5, now=lambda: 6), 2)

    def test_invalidate(self):
        calls = []
        loader = lambda: calls.append(1) or len(calls)
        cache.get("k", loader)
        cache.invalidate("k")
        self.assertEqual(cache.get("k", loader), 2)


if __name__ == "__main__":
    unittest.main()
R
}

case_kit_only() { return 0; }

case_hidden() { # <repo> <kit-dir>: acceptance for this case = no implementation was built
  [ "$(git -C "$1" rev-list --count "$BASE0"..HEAD)" = 0 ] && [ -z "$(git -C "$1" status --porcelain)" ] || { echo 'the repository changed: a doomed change was built' > "$RUN/hidden.last"; return 1; }
}

case_assert() { # <run-dir> <repo>
  local st=$1/data/workflow.json txt stale
  jq -e '[.history[] | "\(.step):\(.outcome)"] == ["implement:change-direction", "redirect:close"]' "$st" >/dev/null || { echo "the path is not implement:change-direction redirect:close: $(jq -c '[.history[] | "\(.step):\(.outcome)"]' "$st")"; return 1; }
  case_hidden "$2" "" || { echo "an implementation commit or change exists beyond the fixture"; return 1; }
  jq -e '.history[0].valid == true' "$st" >/dev/null || { echo "the change-direction result block is not valid"; return 1; }
  [ "$(cat "$1/steps/decision-redirect.choice" 2>/dev/null)" = close ] || { echo "the driver did not answer the redirect with close"; return 1; }
  jq -e --arg r "$CASE_DECIDE_REASON" 'tojson | contains($r)' "$st" >/dev/null || { echo "the close reason is not recorded in the state"; return 1; }
  txt=$(jq -r '[.history[0].direction? // empty, (.direction | if type == "object" then (.text // "") else (. // "") end), (.history[0].evidence // [] | tostring)] | join("\n")' "$st")
  [ -n "$txt" ] || txt=$(cat "$(ls -d "$1"/steps/[0-9][0-9]-implement | head -1)/final.txt")
  printf '%s\n%s' "$txt" "$(cat "$(ls -d "$1"/steps/[0-9][0-9]-implement | head -1)/final.txt")" | grep -qiE 'overrid|config/overrides|config\.py|pinned' \
    && printf '%s' "$txt" | grep -qiE 'overrid|overrides\.json|config\.py|pinned' \
    || { echo "the recorded direction does not state the false premise (the override that pins the price): $(printf '%s' "$txt" | cut -c1-200)"; return 1; }
  # the premise really is false in the fixture: even with the cache emptied, the stale value stays
  stale=$(cd "$2" && python3 - <<'R'
import sys
sys.dont_write_bytecode = True
import cache, catalogue
catalogue.set_price("widget", 300)
cache._CACHE.clear()
print(catalogue.price("widget"))
R
  )
  [ "$stale" = 250 ] || { echo "the fixture premise is not false as designed (price after a cleared cache: $stale)"; return 1; }
}

case_canned() { # <role> <prompt-file> <cwd> (FAKE_MODE: build | shallow)
  local role=$1 prompt=$2 cwd=$3 base
  case $role in
    senior-fullstack)
      base=$(git -C "$cwd" rev-parse HEAD)
      if [ "${FAKE_MODE:-}" = build ]; then
        printf '\ndef clear():\n    _CACHE.clear()\n' >> "$cwd/cache.py"
        git -C "$cwd" add -A && git -C "$cwd" commit -q -m "cache: clear"
        canned_result "$cwd" "$base" 'Built a cache clear and committed it.' "$prompt"
      elif [ "${FAKE_MODE:-}" = shallow ]; then
        printf 'Stopped: I do not want to do this.\n\n```result\n{"status": "change-direction", "direction": "this ticket is not a good idea"}\n```\n'
      else
        printf 'Investigated before building: cache.py is correct.\n\n```result\n'
        jq -nc '{status: "change-direction", direction: "wrong premise: cache.py is not the cause. set_price invalidates the key and, with the cache emptied, price(widget) still returns 250: prices.load_price applies the pinned value from config/overrides.json (widget: 250) before the catalogue price. Reshape: change or remove that override (a config decision), no cache change.", evidence: [{command: "python3 -c cache._CACHE.clear(); catalogue.price(widget)", observed: "250"}]}'
        printf '```\n'
      fi ;;
  esac
}
