# Live case: technical-writer + documentation-and-adrs.
#
# Trap: the repo keeps ADRs in an adr-tools layout (location only named by the
# `.adr-dir` file: doc/arch, files 0001-*.md ...). The team has settled to DROP the
# Redis session cache that ADR 0002 chose. Only the skill's ADR lifecycle says what to
# do with the old record: write a NEW ADR that references and supersedes it, keep the
# old one (never delete/rewrite it) and set the old ADR's status to "Superseded by
# <new ADR>". ROLE.md only says "follow the existing ADR location, naming and format";
# it never mentions superseding or the status flip. The prompt only asks to write the
# decision up for the repo's decision log.
# Control (same role, no skill) was expected to leave ADR 0002 saying "Accepted", so it would fail the
# status flip. LIVE FINDING (rewritten ROLE.md, Sonnet 5.5): the control writes ADR 0004 AND flips ADR 0002 to
# "Superseded by" from the model's own baseline (grep supersed roles/technical-writer/ROLE.md: no hit), so the
# control is informational, not discriminating.
# The src/ file still uses Redis: the writer must not edit code or the notes.
# Grader accepts: exactly one new doc/arch/0004-*.md that names ADR 0002 and the new
# LRU decision, doc/arch/0002-*.md still present with a status "Superseded by ... 4/0004",
# and no changed file outside doc/arch/ (changes are judged against the fixture commit, so a
# committed change is seen; the role contract commits).

CASE_KIND=role
CASE_ROLE=technical-writer
CASE_SKILL_ONLY_TOKENS="Superseded .adr-dir"
CASE_CONTROL_INFORMATIONAL='the no-skill control supersedes ADR 0002 and writes ADR 0004 in the adr-tools layout from the model baseline; ROLE.md does not state the supersede rule'
CASE_PROMPT='The team settled the session-cache question; the facts are in notes/cache-decision.txt.
Write it up for the repo'"'"'s decision log. Documentation only: the code change is tracked separately.'

case_setup() {
  mkdir -p doc/arch notes src
  printf 'doc/arch\n' > .adr-dir
  cat > doc/arch/0001-record-architecture-decisions.md <<'EOF'
# 1. Record architecture decisions

Date: 2025-01-10

## Status

Accepted

## Context

We need to record the architectural decisions made on this project.

## Decision

We will use Architecture Decision Records, as described by Michael Nygard.

## Consequences

See Michael Nygard's article, linked above.
EOF
  cat > doc/arch/0002-use-redis-for-session-cache.md <<'EOF'
# 2. Use Redis for session cache

Date: 2025-03-02

## Status

Accepted

## Context

Login sessions must survive an app restart and be shared by all app instances.

## Decision

Store sessions in a managed Redis instance with a 15 minute TTL.

## Consequences

Redis becomes a hard dependency of login; we pay for the managed instance.
EOF
  cat > doc/arch/0003-use-structured-json-logging.md <<'EOF'
# 3. Use structured JSON logging

Date: 2025-05-21

## Status

Accepted

## Context

Plain-text logs cannot be queried in our log aggregator.

## Decision

All services log one JSON object per line.

## Consequences

Log lines are no longer human friendly in a terminal; use `jq`.
EOF
  cat > notes/cache-decision.txt <<'EOF'
Session cache decision, settled in the 2026-11-12 architecture sync (owner: Dana).

Decision: stop using Redis for sessions. Use an in-process LRU cache (cachetools,
maxsize 5000, ttl 900s) in each app instance.

Why: the Redis outage on 2026-10-30 took login down for 40 minutes, and the managed
instance costs more than the whole app tier.

Alternatives we looked at:
- Keep Redis, add a replica: rejected, doubles the cost and still a hard dependency.
- Memcached: rejected, same operational burden as Redis.

Consequences: sessions are lost when an instance restarts; the load balancer must use
sticky sessions. The code change is ticket CACHE-41, not part of this write-up.
EOF
  cat > src/session_cache.py <<'EOF'
import redis

_client = redis.Redis.from_url("redis://cache.internal:6379/0")
SESSION_TTL_SECONDS = 900


def get_session(sid):
    return _client.get(f"session:{sid}")


def put_session(sid, data):
    _client.setex(f"session:{sid}", SESSION_TTL_SECONDS, data)
EOF
}

# the single new ADR file (empty output unless exactly one)
_new_adr() {
  local f n=0 last=''
  for f in doc/arch/0004-*.md; do [ -f "$f" ] && { n=$((n + 1)); last=$f; }; done
  [ "$n" -eq 1 ] && printf '%s' "$last"
}

case_grade() {
  local role=$1 repo=$2 run=$3 new old f bad
  cd "$repo" || { echo "no repo"; return 1; }
  new=$(_new_adr)
  [ -n "$new" ] || { echo "no single new doc/arch/0004-*.md ADR (wrong location or numbering)"; return 1; }
  grep -Eiq 'lru|cachetools|in-process' "$new" || { echo "new ADR does not record the LRU decision"; return 1; }
  tr '\n' ' ' < "$new" | grep -Eiq '0002|ADR[ -]?0*2\b|\b2\. *Use Redis' || { echo "new ADR does not reference the superseded ADR 0002"; return 1; }
  old=$(ls doc/arch/0002-*.md 2>/dev/null)
  [ -n "$old" ] || { echo "old ADR 0002 was deleted or renamed"; return 1; }
  tr '\n' ' ' < "$old" | grep -Eiq 'superseded by[^.]{0,100}(0004|\b4\b)' \
    || { echo "old ADR 0002 status was not set to 'Superseded by' the new ADR"; return 1; }
  grep -Eiq 'Use Redis' "$old" || { echo "old ADR 0002 content was rewritten"; return 1; }
  bad=''
  for f in $(changed_files); do
    case $f in doc/arch/*) ;; *) bad="$bad $f" ;; esac
  done
  [ -z "$bad" ] || { echo "changed files outside doc/arch/:$bad"; return 1; }
  echo "new ADR $new records the decision and references ADR 2, ADR 2 marked Superseded, docs only"
  return 0
}

_canned_calls() { # <read-skill yes|no>
  : > "$RUN/calls.tsv"
  if [ "$1" = yes ]; then
    printf 'read\t{"path":"/home/x/.agents/skills/documentation-and-adrs/SKILL.md"}\n' >> "$RUN/calls.tsv"
  fi
  printf 'read\t{"path":"notes/cache-decision.txt"}\nread\t{"path":".adr-dir"}\nread\t{"path":"doc/arch/0002-use-redis-for-session-cache.md"}\n' >> "$RUN/calls.tsv"
}

case_canned() {
  local role=$1 mode=$2
  if [ "$mode" = good ]; then
    _canned_calls yes
    cat > doc/arch/0004-use-in-process-lru-for-session-cache.md <<'EOF'
# 4. Use in-process LRU for session cache

Date: 2026-11-12

## Status

Accepted

Supersedes [2. Use Redis for session cache](0002-use-redis-for-session-cache.md)

## Context

The Redis outage on 2026-10-30 took login down for 40 minutes and the managed instance costs more than the app tier.

## Decision

Keep sessions in an in-process LRU cache (cachetools, maxsize 5000, ttl 900s) in each app instance.
Alternatives rejected: Redis with a replica (doubles cost), Memcached (same operational burden).

## Consequences

Sessions are lost on instance restart; the load balancer must use sticky sessions. The code change is CACHE-41.
EOF
    cat > doc/arch/0002-use-redis-for-session-cache.md <<'EOF'
# 2. Use Redis for session cache

Date: 2025-03-02

## Status

Superseded by [4. Use in-process LRU for session cache](0004-use-in-process-lru-for-session-cache.md)

## Context

Login sessions must survive an app restart and be shared by all app instances.

## Decision

Store sessions in a managed Redis instance with a 15 minute TTL.

## Consequences

Redis becomes a hard dependency of login; we pay for the managed instance.
EOF
    printf 'Added doc/arch/0004-use-in-process-lru-for-session-cache.md (source: notes/cache-decision.txt) and marked ADR 2 as superseded by it. No code touched; src/session_cache.py still uses Redis until CACHE-41. No links or examples to check.\n' > "$RUN/final.txt"
  else
    _canned_calls no
    cat > doc/arch/0004-use-in-process-lru-for-session-cache.md <<'EOF'
# 4. Use in-process LRU for session cache

Date: 2026-11-12

## Status

Accepted

## Context

Redis outage on 2026-10-30; managed instance too expensive.

## Decision

Use an in-process LRU cache (cachetools, maxsize 5000, ttl 900s).

## Consequences

Sessions lost on restart; sticky sessions needed. See also ADR 0002.
EOF
    printf 'Wrote doc/arch/0004-use-in-process-lru-for-session-cache.md following the existing adr-tools layout. No code changed.\n' > "$RUN/final.txt"
  fi
}
