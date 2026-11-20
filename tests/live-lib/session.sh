# shellcheck shell=bash
# Shared by tests/roles-live.sh and tests/workflows-live.sh. Sourced, never run.

# parse_session <session-dir> <run-dir>: writes calls.tsv (tool<TAB>one-line args) and final.txt (last assistant
# text) from the TOP-LEVEL session transcript only, subcalls.tsv (agent<TAB>tool<TAB>args) from the transcripts of
# sub-agents the worker spawned (omp writes them under <session>/<parent-id>/<Agent>.jsonl), and cost.txt (USD,
# summed over the worker and every sub-agent).
parse_session() {
  python3 - "$1" "$2" <<'PY'
import glob, json, os, sys
sess, out = sys.argv[1], sys.argv[2]
allf = sorted(glob.glob(os.path.join(sess, "**", "*.jsonl"), recursive=True))
top = sorted(glob.glob(os.path.join(sess, "*.jsonl")))
nested = [f for f in allf if f not in top]
calls, subcalls, top_texts, cost = [], [], [], 0.0
for f in top + nested:
    is_top = f in top
    agent = os.path.splitext(os.path.basename(f))[0]
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
                    args = json.dumps(c.get("arguments"), ensure_ascii=False).replace("\t", " ").replace("\n", " ")
                    if is_top:
                        calls.append((c.get("name", "?"), args))
                    else:
                        subcalls.append((agent, c.get("name", "?"), args))
                elif c.get("type") == "text":
                    texts.append(c.get("text", ""))
        if texts and is_top:
            top_texts.append("\n".join(texts))
# A worker that waits for async helpers can be woken AFTER it wrote its report and answers the notice with a short
# acknowledgement; the report is then the message before it. A trailing text under 40% of the previous one (and under
# 1500 characters) is that acknowledgement, not the report - unless it carries a final block (result, verdict, risk)
# the previous text does not have, in which case it is the report. An acknowledgement that merely repeats a block the
# previous text already carries is still an acknowledgement.
import re
def block_tags(s):
    return set(re.findall(r"```(result|verdict|risk)\b", s))
final = top_texts[-1] if top_texts else ""
if len(top_texts) >= 2 and len(final) < 1500 and len(final) < 0.4 * len(top_texts[-2]):
    if "```" not in final or (block_tags(final) and block_tags(final) <= block_tags(top_texts[-2])):
        final = top_texts[-2]
open(os.path.join(out, "calls.tsv"), "w", encoding="utf-8").write("".join("%s\t%s\n" % c for c in calls))
open(os.path.join(out, "subcalls.tsv"), "w", encoding="utf-8").write("".join("%s\t%s\t%s\n" % c for c in subcalls))
open(os.path.join(out, "final.txt"), "w", encoding="utf-8").write(final)
open(os.path.join(out, "cost.txt"), "w").write("%.6f\n" % cost)
PY
}

