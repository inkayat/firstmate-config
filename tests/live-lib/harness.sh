# shellcheck shell=bash
# Worker harnesses for tests/crossfamily-live.sh. Sourced, never run. A ROUTE is "<harness>:<model>":
#   omp:<provider>/<model>   omp -p (any family omp reaches under the operator's login), e.g. omp:openai-codex/gpt-6.2-sol
#   claude:<model>           the Claude Code CLI, claude -p --output-format stream-json, e.g. claude:claude-sonnet-5-5
#   codex:<model>            the Codex CLI, codex exec --json, e.g. codex:gpt-6.1-sol
# A ROUTES table is "role=route,role=route,*=route": the exact role name wins, "*" is the default.
#
# Every harness leaves the same files in a step directory, parsed ONLY from the harness's own machine-readable output:
#   calls.tsv (tool<TAB>one-line args), subcalls.tsv, final.txt (the worker's final report), cost.txt (USD, 0 where the CLI
#   reports none), models.txt (one "<harness><TAB><model actually seen>" line per distinct model found in the log).
# The model is read from the log, never from what was requested: omp session jsonl assistant messages carry provider and model;
# claude stream-json carries the model on its init event, on every assistant message and in the result's modelUsage; the codex
# exec event stream carries none, so the model is read from the codex rollout file (turn_context.model) of that thread.

# route_for <routes> <role>: the route of a role (exact match first, then "*"); empty when none
route_for() {
  printf '%s' "$1" | awk -v r="$2" 'BEGIN { RS = "," } { gsub(/\n/, ""); k = $0; sub(/=.*/, "", k); v = $0; sub(/^[^=]*=/, "", v); if (k == r) exact = v; else if (k == "*") def = v }
    END { if (exact != "") print exact; else if (def != "") print def }'
}

# run_worker <route> <cwd> <prompt-file> <session-dir> <stdout> <stderr>; returns the worker's exit status. Globals: THINKING, WORKER_TIMEOUT,
# SYSTEM_PROMPT, OMP_BIN, CLAUDE_BIN, CODEX_BIN, COST_ARGS, COST_ARGS_CLAUDE, SCR_HOME, EXTRA_WORKER_ENV (self-test only). The environment is
# scrubbed (env -i); HOME stays the operator's wherever a login lives there, so their existing login is used in place and nothing is copied.
run_worker() {
  local route=$1 cwd=$2 prompt=$3 sess=$4 out=$5 err=$6 h m rc tid f chome
  h=${route%%:*}; m=${route#*:}
  mkdir -p "$sess"
  case $h in
    omp)
      ( cd "$cwd" && env -i HOME="$HOME" PATH="$PATH" TERM=dumb LANG=C.UTF-8 OMP_SKIP_SETUP=1 PYTHONDONTWRITEBYTECODE=1 ${EXTRA_WORKER_ENV:-} \
          timeout "$WORKER_TIMEOUT" "$OMP_BIN" -p --model "$m" --thinking "$THINKING" --no-extensions --no-skills --no-rules --no-context-files \
          --no-lsp --no-pty --no-title --tools read,grep,glob,bash,edit,write --system-prompt "$SYSTEM_PROMPT" \
          --session-dir "$sess" ${COST_ARGS[@]+"${COST_ARGS[@]}"} --auto-approve --cwd "$cwd" "@$prompt" > "$out" 2> "$err" )
      rc=$? ;;
    claude)
      # --safe-mode: no CLAUDE.md, skills, hooks, plugins or MCP servers of the operator's; the login (keychain) still works, which needs the
      # real HOME and USER. bypassPermissions is the claude equivalent of omp --auto-approve: the isolation is the scratch directories, not a sandbox.
      ( cd "$cwd" && env -i HOME="$HOME" USER="${USER:-$(id -un)}" LOGNAME="${LOGNAME:-${USER:-$(id -un)}}" PATH="$PATH" TERM=dumb LANG=C.UTF-8 PYTHONDONTWRITEBYTECODE=1 ${EXTRA_WORKER_ENV:-} \
          timeout "$WORKER_TIMEOUT" "$CLAUDE_BIN" -p --model "$m" --effort "$THINKING" --safe-mode --no-session-persistence \
          --permission-mode bypassPermissions --tools Read,Grep,Glob,Bash,Edit,Write --system-prompt "$SYSTEM_PROMPT" \
          --output-format stream-json --verbose ${COST_ARGS_CLAUDE[@]+"${COST_ARGS_CLAUDE[@]}"} < "$prompt" > "$out" 2> "$err" )
      rc=$?
      cp "$out" "$sess/claude.jsonl" 2>/dev/null ;;
    codex)
      # HOME is a scratch directory (nothing of the operator's home is read); CODEX_HOME stays the operator's, which is where the login lives.
      # No sandbox, as with the other two harnesses: the default workspace-write sandbox forbids writing .git, so the implementer could not commit.
      chome=${CODEX_HOME:-$HOME/.codex}
      ( cd "$cwd" && env -i HOME="${SCR_HOME:-$HOME}" CODEX_HOME="$chome" USER="${USER:-$(id -un)}" LOGNAME="${LOGNAME:-${USER:-$(id -un)}}" PATH="$PATH" TERM=dumb LANG=C.UTF-8 PYTHONDONTWRITEBYTECODE=1 ${EXTRA_WORKER_ENV:-} \
          timeout "$WORKER_TIMEOUT" "$CODEX_BIN" exec --json --skip-git-repo-check --ignore-user-config --ignore-rules -m "$m" \
          -c "model_reasoning_effort=\"$THINKING\"" -s danger-full-access -C "$cwd" - < "$prompt" > "$out" 2> "$err" )
      rc=$?
      cp "$out" "$sess/codex.jsonl" 2>/dev/null
      tid=$(sed -n 's/.*"type":"thread.started".*"thread_id":"\([^"]*\)".*/\1/p' "$out" | head -1)
      if [ -n "$tid" ] && [ -d "$chome/sessions" ]; then
        f=$(find "$chome/sessions" -name "*$tid*.jsonl" 2>/dev/null | head -1)
        [ -z "$f" ] || cp "$f" "$sess/rollout.jsonl"
      fi ;;
    *) printf 'unknown harness %s\n' "$h" > "$err"; rc=97 ;;
  esac
  return "$rc"
}

# parse_worker <route> <session-dir> <step-dir>: calls.tsv subcalls.tsv final.txt cost.txt models.txt in <step-dir>
parse_worker() {
  local h=${1%%:*}
  case $h in
    omp)
      parse_session "$2" "$3"
      python3 - "$2" "$3" <<'PY'
import glob, json, os, sys
sess, out = sys.argv[1], sys.argv[2]
seen = []
for f in sorted(glob.glob(os.path.join(sess, "**", "*.jsonl"), recursive=True)):
    for line in open(f, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        m = d.get("message") or {}
        if m.get("role") != "assistant":
            continue
        if not (m.get("provider") and m.get("model")):
            continue
        sel = "%s/%s" % (m["provider"], m["model"])
        if sel not in seen:
            seen.append(sel)
open(os.path.join(out, "models.txt"), "w").write("".join("omp\t%s\n" % s for s in seen))
PY
      ;;
    claude)
      python3 - "$2" "$3" <<'PY'
import json, os, sys
sess, out = sys.argv[1], sys.argv[2]
calls, texts, models, cost, final = [], [], [], 0.0, None
p = os.path.join(sess, "claude.jsonl")
for line in open(p, encoding="utf-8", errors="replace") if os.path.exists(p) else []:
    try:
        d = json.loads(line)
    except ValueError:
        continue
    t = d.get("type")
    def add(m):
        if m and m != "<synthetic>" and m not in models:
            models.append(m)
    if t == "system" and d.get("subtype") == "init":
        add(d.get("model"))
    elif t == "assistant":
        msg = d.get("message") or {}
        add(msg.get("model"))
        c = msg.get("content")
        if isinstance(c, str):
            texts.append(c)
        for b in c if isinstance(c, list) else []:
            if b.get("type") == "tool_use":
                calls.append((b.get("name", "?"), json.dumps(b.get("input"), ensure_ascii=False).replace("\t", " ").replace("\n", " ")))
            elif b.get("type") == "text":
                texts.append(b.get("text", ""))
    elif t == "result":
        cost += float(d.get("total_cost_usd") or 0)
        for k in (d.get("modelUsage") or {}):
            add(k)
        if d.get("result") and not d.get("is_error"):
            final = d["result"]
if final is None:
    final = texts[-1] if texts else ""
open(os.path.join(out, "calls.tsv"), "w", encoding="utf-8").write("".join("%s\t%s\n" % c for c in calls))
open(os.path.join(out, "subcalls.tsv"), "w").write("")
open(os.path.join(out, "final.txt"), "w", encoding="utf-8").write(final)
open(os.path.join(out, "cost.txt"), "w").write("%.6f\n" % cost)
open(os.path.join(out, "models.txt"), "w").write("".join("claude\t%s\n" % m for m in models))
PY
      ;;
    codex)
      python3 - "$2" "$3" <<'PY'
import json, os, sys
sess, out = sys.argv[1], sys.argv[2]
calls, texts, models = [], [], []
p = os.path.join(sess, "codex.jsonl")
for line in open(p, encoding="utf-8", errors="replace") if os.path.exists(p) else []:
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("type") != "item.completed":
        continue
    it = d.get("item") or {}
    t = it.get("type")
    if t == "agent_message":
        texts.append(it.get("text", ""))
    elif t == "command_execution":
        calls.append(("bash", json.dumps({"command": it.get("command", "")}, ensure_ascii=False).replace("\t", " ").replace("\n", " ")))
    elif t == "file_change":
        calls.append(("edit", json.dumps({"changes": it.get("changes")}, ensure_ascii=False).replace("\t", " ").replace("\n", " ")))
    elif t in ("mcp_tool_call", "web_search"):
        calls.append((t, json.dumps(it, ensure_ascii=False).replace("\t", " ").replace("\n", " ")))
p = os.path.join(sess, "rollout.jsonl")
for line in open(p, encoding="utf-8", errors="replace") if os.path.exists(p) else []:
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("type") == "turn_context":
        m = (d.get("payload") or {}).get("model")
        if m and m not in models:
            models.append(m)
open(os.path.join(out, "calls.tsv"), "w", encoding="utf-8").write("".join("%s\t%s\n" % c for c in calls))
open(os.path.join(out, "subcalls.tsv"), "w").write("")
open(os.path.join(out, "final.txt"), "w", encoding="utf-8").write(texts[-1] if texts else "")
open(os.path.join(out, "cost.txt"), "w").write("0.000000\n")
open(os.path.join(out, "models.txt"), "w").write("".join("codex\t%s\n" % m for m in models))
PY
      ;;
  esac
}

# route_expected <route> -> "<harness><TAB><model as the log spells it>" (the line models.txt must consist of, and only of)
route_expected() { printf '%s\t%s' "${1%%:*}" "${1#*:}"; }
