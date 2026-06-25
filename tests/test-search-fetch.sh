#!/usr/bin/env bash
# pro-review-mcp-search-fetch の regression テスト。
# tools/list で search/fetch/save_report のみ + 動作 + path traversal 拒否。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

MCP="$(repo_scripts_dir)/pro-review-mcp-search-fetch"
[ -x "$MCP" ] || _fail "pro-review-mcp-search-fetch not executable: $MCP"

echo "[test-search-fetch] start"

# active-project を一時的に退避（テスト中に汚さない）
ACTIVE_BAK=""
ACTIVE="$HOME/.pro-review/active-project"
if [ -s "$ACTIVE" ]; then ACTIVE_BAK=$(cat "$ACTIVE"); fi
PROJECT="sfreg-$$"
mkdir -p "$HOME/.pro-review/workspace/$PROJECT"
echo "fn add(){}" > "$HOME/.pro-review/workspace/$PROJECT/calc.rs"
echo "console.log('hi')" > "$HOME/.pro-review/workspace/$PROJECT/app.js"
printf '%s\n' "$PROJECT" > "$ACTIVE"

restore() {
  if [ -n "$ACTIVE_BAK" ]; then printf '%s\n' "$ACTIVE_BAK" > "$ACTIVE"; else : > "$ACTIVE"; fi
  cleanup_paths "$HOME/.pro-review/workspace/$PROJECT" "$HOME/.pro-review/inbox/$PROJECT"
}
trap restore EXIT

RESULT=$(python3 <<EOF
import json, subprocess, sys, os
p = subprocess.Popen(["$MCP"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
def send(m): p.stdin.write((json.dumps(m)+"\n").encode()); p.stdin.flush()
def recv(): return json.loads(p.stdout.readline())
send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"0"}}})
init = recv()
send({"jsonrpc":"2.0","method":"notifications/initialized"})

send({"jsonrpc":"2.0","id":2,"method":"tools/list"})
tl = recv()
names = [t.get("name") for t in tl["result"]["tools"]]
ros = {t["name"]: (t.get("annotations") or {}).get("readOnlyHint") for t in tl["result"]["tools"]}

send({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search","arguments":{"query":""}}})
r3 = recv()
search_count = len(r3["result"]["structuredContent"]["results"])

send({"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"search","arguments":{"query":"calc"}}})
r4 = recv()
search_calc = [x["id"] for x in r4["result"]["structuredContent"]["results"]]

send({"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"fetch","arguments":{"id":"calc.rs"}}})
r5 = recv()
fetch_text = r5["result"]["structuredContent"]["text"]

send({"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"fetch","arguments":{"id":"../../etc/passwd"}}})
r6 = recv()
traversal = r6["result"].get("isError")

body = "結論: 問題なし\\n[[DONE-1700000000123-aabbcc]]"
send({"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"save_report","arguments":{"project":"$PROJECT","run_id":"1700000000123-aabbcc","body":body}}})
r7 = recv()
save_report = r7["result"]["structuredContent"]

send({"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"save_report","arguments":{"project":"$PROJECT","run_id":"../bad","body":"x"}}})
r8 = recv()
save_bad = r8["result"].get("isError")

send({"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"write_file","arguments":{}}})
r9 = recv()
unknown = r9.get("error",{}).get("message","")

p.stdin.close(); p.terminate()
print(json.dumps({
    "names": names, "ros": ros,
    "search_count": search_count, "search_calc": search_calc,
    "fetch_text": fetch_text[:50], "traversal": traversal,
    "save_report": save_report, "save_bad": save_bad, "unknown": unknown,
}))
EOF
)

NAMES=$(printf '%s' "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(','.join(d['names']))")
assert_eq "search,fetch,save_report" "$NAMES" "T1 only bounded tools exposed"

RO_SEARCH=$(printf '%s' "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['ros']['search'])")
RO_FETCH=$(printf '%s' "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['ros']['fetch'])")
RO_SAVE=$(printf '%s' "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['ros']['save_report'])")
assert_eq "True" "$RO_SEARCH" "T2 search readOnlyHint:true"
assert_eq "True" "$RO_FETCH"  "T2 fetch readOnlyHint:true"
assert_eq "False" "$RO_SAVE"  "T2 save_report readOnlyHint:false"

COUNT=$(printf '%s' "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['search_count'])")
[ "$COUNT" -ge 2 ] || _fail "T3 search('') expected >= 2 files, got $COUNT"
_ok "T3 search('') count=$COUNT"

CALC_HIT=$(printf '%s' "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('calc.rs' in d['search_calc'])")
assert_eq "True" "$CALC_HIT" "T4 search('calc') hits calc.rs"

TEXT=$(printf '%s' "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['fetch_text'])")
assert_contains "$TEXT" "fn add" "T5 fetch returns content"

TRAV=$(printf '%s' "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['traversal'])")
assert_eq "True" "$TRAV" "T6 path traversal isError:true"

SAVED=$(printf '%s' "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['save_report']['saved'])")
assert_eq "True" "$SAVED" "T7 save_report saved:true"
REPLY="$HOME/.pro-review/inbox/$PROJECT/REPLY-1700000000123-aabbcc.md"
assert_file_exists "$REPLY" "T7 save_report wrote reply"
assert_contains "$(cat "$REPLY")" "[[DONE-1700000000123-aabbcc]]" "T7 save_report marker"

SAVE_BAD=$(printf '%s' "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['save_bad'])")
assert_eq "True" "$SAVE_BAD" "T8 invalid save_report isError:true"

UNK=$(printf '%s' "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['unknown'])")
assert_contains "$UNK" "unknown tool" "T9 unknown tool error"

echo "[test-search-fetch] PASS"
