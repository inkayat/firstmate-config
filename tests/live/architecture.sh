# Live case: architecture (skill api-and-interface-design).
#
# Trap: the task is "make retries of POST /charges safe". The fixture's queue
# config re-delivers dead-lettered charge jobs for 7 days. api-and-interface-design
# section "Honouring an Idempotency Key" is the only place that says: retention
# must come from the LONGEST retry chain (not disk cost; a 24h TTL behind a 7-day
# DLQ is a duplicate waiting to happen), and that the same key with a different
# body must fail loudly (422 / request hash). An unskilled model reaches for a
# Redis key with a 24h TTL (the obvious default; the README even mentions Redis).
#
# Accepts: read-only (repo unchanged) AND final answer sets key retention at or
# above the DLQ window (7+ days / a week / outliving the DLQ) AND guards a
# reused key with a different payload (422 / payload hash / different body).
# The control normally picks 24h and never mentions the payload guard.
CASE_KIND=role
CASE_ROLE=architecture
CASE_SKILL_ONLY_TOKENS="TOCTOU requestHash"
CASE_PROMPT='POST /charges is retried by clients and by our worker queue, and some customers got charged twice.
Decide how to make retries safe: what the dedupe key is, where its state lives, and how long it is kept.
The code is in this repo.'

case_setup() {
  cat > README.md <<'R'
# payments-api
POST /charges creates a card charge. Clients retry on timeouts. Failed jobs go
through the worker queue (see queue.yaml). Ops runs a small Redis for rate limits.
Postgres is the system of record. Team: 3 engineers.
R
  cat > queue.yaml <<'R'
queue: charge-jobs
max_attempts: 5
backoff: exponential
dead_letter:
  queue: charge-jobs-dlq
  redeliver_after_days: 7   # on-call replays the DLQ once a week
R
  cat > charge.py <<'R'
def handle_charge(req, db, provider):
    order = db.get_order(req["order_id"])
    result = provider.charge(order["amount"], order["card"])
    db.insert_charge(order["id"], result["id"])
    return {"status": 201, "body": result}
R
}

case_grade() {
  local role=$1
  [ -z "$(changed_files)" ] || { echo "architecture role edited files: $(changed_files | tr '\n' ' ')"; return 1; }
  final_has '(7|seven)[- ]day|168 ?h|(8|9|10|14|30|thirty) days|(one|a) week|(outlive|outlast|exceed|longer than)[^.]{0,60}(dlq|dead[- ]letter|retry|redeliver)' \
    || { echo "key retention not tied to the 7-day DLQ retry chain"; return 1; }
  final_has '422|different (payload|body|request)|payload (hash|mismatch)|request ?hash|body hash' \
    || { echo "no guard for the same key reused with a different payload"; return 1; }
  echo "read-only, retention tied to the longest retry chain, payload guard present"
}

case_canned() {
  local role=$1 mode=$2 sd=/fixture-home/.agents/skills
  if [ "$mode" = good ]; then
    {
      printf 'read\t{"path":"%s/api-and-interface-design/SKILL.md"}\n' "$sd"
      printf 'read\t{"path":"queue.yaml"}\n'
    } > "$RUN/calls.tsv"
    cat > "$RUN/final.txt" <<'T'
Decision: client-supplied Idempotency-Key, stored in Postgres with a unique constraint (claimed atomically: insert in_progress first, then call the provider, so there is no TOCTOU race). Redis is rejected: it cannot give the durable single-claim guarantee.
Retention: keys must outlive the longest retry chain. queue.yaml redelivers the DLQ after 7 days, so keep keys at least 8 days, not 24h.
Same key with a different requestHash/body returns 422. In-flight duplicate returns 409. Record the intent before calling the provider because a timeout is an unknown outcome.
First step: add the idempotency table. Not decided: provider-side keys.
T
  else
    : > "$RUN/calls.tsv"
    cat > "$RUN/final.txt" <<'T'
Use a client Idempotency-Key header, stored in Redis with SETNX and a 24 hour TTL. On a repeat key return the cached response. Cheap, fast, and the ops team already runs Redis.
First step: add the header check in handle_charge.
T
  fi
}
