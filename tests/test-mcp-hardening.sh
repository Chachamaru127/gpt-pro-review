#!/usr/bin/env bash
# 6.11a: MCP hardening。path leak / hidden / save_report 境界を fixture で固定する。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

MCP="$(repo_scripts_dir)/pro-review-mcp-search-fetch"
[ -x "$MCP" ] || _fail "pro-review-mcp-search-fetch not executable: $MCP"

echo "[test-mcp-hardening] start"

ACTIVE="$HOME/.pro-review/active-project"
ACTIVE_BAK=""
if [ -s "$ACTIVE" ]; then ACTIVE_BAK=$(cat "$ACTIVE"); fi
PROJECT="mcp-hard-$$"
WS="$HOME/.pro-review/workspace/$PROJECT"
INBOX="$HOME/.pro-review/inbox/$PROJECT"
mkdir -p "$WS/.secret" "$INBOX"
echo "visible content" > "$WS/visible.txt"
echo "hidden content" > "$WS/.secret/hidden.txt"
ln -s /etc/passwd "$WS/link.txt"
printf '%s\n' "$PROJECT" > "$ACTIVE"

restore() {
  if [ -n "$ACTIVE_BAK" ]; then printf '%s\n' "$ACTIVE_BAK" > "$ACTIVE"; else : > "$ACTIVE"; fi
  cleanup_paths "$WS" "$INBOX"
}
trap restore EXIT

RESULT=$(PRO_REVIEW_SAVE_REPORT_MAX_BYTES=64 python3 <<EOF
import json, os, subprocess
p = subprocess.Popen(["$MCP"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1, env={**os.environ, "PRO_REVIEW_SAVE_REPORT_MAX_BYTES": "64"})
def send(m):
    p.stdin.write(json.dumps(m, ensure_ascii=False) + "\n")
    p.stdin.flush()
def recv():
    return json.loads(p.stdout.readline())
send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"0"}}})
recv()
send({"jsonrpc":"2.0","method":"notifications/initialized"})

send({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search","arguments":{"query":""}}})
r2 = recv()["result"]["structuredContent"]["results"]

send({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fetch","arguments":{"id":".secret/hidden.txt"}}})
r3 = recv()["result"].get("isError")

send({"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"fetch","arguments":{"id":"link.txt"}}})
r4 = recv()["result"].get("isError")

send({"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"fetch","arguments":{"id":"/etc/passwd"}}})
r5 = recv()["result"].get("isError")

body_good = "ok\\n[[DONE-1700000000123-aabbcc]]"
send({"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"save_report","arguments":{"project":"$PROJECT","run_id":"1700000000123-aabbcc","body":body_good}}})
r6 = recv()["result"]["structuredContent"]

send({"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"save_report","arguments":{"project":"other-project","run_id":"1700000000123-bbbbbb","body":"ok\\n[[DONE-1700000000123-bbbbbb]]"}}})
r7 = recv()["result"].get("isError")

send({"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"save_report","arguments":{"project":"$PROJECT","run_id":"../bad","body":"ok\\n[[DONE-../bad]]"}}})
r8 = recv()["result"].get("isError")

send({"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"save_report","arguments":{"project":"$PROJECT","run_id":"1700000000123-cccccc","body":"marker mismatch\\n[[DONE-1700000000123-dddddd]]"}}})
r9 = recv()["result"].get("isError")

body_big = ("x" * 80) + "\\n[[DONE-1700000000123-eeeeee]]"
send({"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"save_report","arguments":{"project":"$PROJECT","run_id":"1700000000123-eeeeee","body":body_big}}})
r10 = recv()["result"].get("isError")

p.stdin.close()
p.terminate()
print(json.dumps({
  "search": r2, "hidden_fetch": r3, "symlink_fetch": r4, "absolute_fetch": r5,
  "save_good": r6, "wrong_project": r7, "bad_run_id": r8,
  "marker_mismatch": r9, "oversize": r10,
}, ensure_ascii=False))
EOF
)

SEARCH_JSON=$(printf '%s' "$RESULT" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['search'], ensure_ascii=False))")
assert_contains "$SEARCH_JSON" "visible.txt" "T1 visible file listed"
assert_not_contains "$SEARCH_JSON" ".secret" "T1 hidden dir not listed"
assert_not_contains "$SEARCH_JSON" "link.txt" "T1 symlink not listed"
assert_not_contains "$SEARCH_JSON" "$HOME" "T1 no HOME path leak"
assert_not_contains "$SEARCH_JSON" "file://" "T1 no file URL leak"

for key in hidden_fetch symlink_fetch absolute_fetch wrong_project bad_run_id marker_mismatch oversize; do
  VAL=$(printf '%s' "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['$key'])")
  assert_eq "True" "$VAL" "T2 $key rejected"
done

SAVED=$(printf '%s' "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['save_good']['saved'])")
assert_eq "True" "$SAVED" "T3 valid save_report succeeds"
REPLY="$INBOX/REPLY-1700000000123-aabbcc.md"
assert_file_exists "$REPLY" "T3 reply exists"
MODE=$(stat -f '%Lp' "$REPLY")
assert_eq "600" "$MODE" "T3 reply mode 600"

# 既存 dest が symlink の場合は save_report が拒否する。
SYMRID="1700000000123-ffffff"
ln -s "$REPLY" "$INBOX/REPLY-$SYMRID.md"
SYM_RESULT=$(python3 <<EOF
import json, os, subprocess
p = subprocess.Popen(["$MCP"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
def send(m):
    p.stdin.write(json.dumps(m, ensure_ascii=False) + "\n")
    p.stdin.flush()
def recv():
    return json.loads(p.stdout.readline())
send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"0"}}})
recv()
send({"jsonrpc":"2.0","method":"notifications/initialized"})
send({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"save_report","arguments":{"project":"$PROJECT","run_id":"$SYMRID","body":"ok\\n[[DONE-$SYMRID]]"}}})
print(json.dumps(recv(), ensure_ascii=False))
p.stdin.close()
p.terminate()
EOF
)
SYM_ERR=$(printf '%s' "$SYM_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'].get('isError'))")
assert_eq "True" "$SYM_ERR" "T4 save_report refuses symlink dest"

echo "[test-mcp-hardening] PASS"
