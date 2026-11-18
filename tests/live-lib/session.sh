# shellcheck shell=bash
# Shared by tests/roles-live.sh and tests/workflows-live.sh. Sourced, never run.

# parse_session <session-dir> <run-dir>: writes calls.tsv (tool<TAB>one-line args),
# final.txt (last assistant text) and cost.txt (USD, summed over the session).
parse_session() {
  python3 - "$1" "$2" <<'PY'
import glob, json, os, sys
sess, out = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(os.path.join(sess, "**", "*.jsonl"), recursive=True))
calls, final, cost = [], "", 0.0
for f in files:
    for line in open(f, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("type") == "model_usage":
            cost += float(((d.get("usage") or {}).get("cost") or {}).get("total") or 0)
        m = d.get("message") or {}
        if m.get("role") != "assistant":
            continue
        cost += float(((m.get("usage") or {}).get("cost") or {}).get("total") or 0)
        content = m.get("content")
        texts = []
        if isinstance(content, str):
            texts.append(content)
        else:
            for c in content or []:
                if c.get("type") == "toolCall":
                    args = json.dumps(c.get("arguments"), ensure_ascii=False)
                    calls.append((c.get("name", "?"), args.replace("\t", " ").replace("\n", " ")))
                elif c.get("type") == "text":
                    texts.append(c.get("text", ""))
        if texts:
            final = "\n".join(texts)
open(os.path.join(out, "calls.tsv"), "w", encoding="utf-8").write("".join("%s\t%s\n" % c for c in calls))
open(os.path.join(out, "final.txt"), "w", encoding="utf-8").write(final)
open(os.path.join(out, "cost.txt"), "w").write("%.6f\n" % cost)
PY
}

