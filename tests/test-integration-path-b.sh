#!/usr/bin/env bash
# Path B (Thinking-High / 非 5.5Pro ローカル MCP) の統合テスト。
# pro-review-start → MCP save_report で投入 → watch 検知 → finish が reports 永続化。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

ST="$(local_start_cmd)"
REPO_SCRIPTS="$(repo_scripts_dir)"
SR="$REPO_SCRIPTS/pro-review-save-reply"
WA="$REPO_SCRIPTS/pro-review-watch"
FI="$REPO_SCRIPTS/pro-review-finish"
MCP="$REPO_SCRIPTS/pro-review-mcp-search-fetch"
for f in "$ST" "$SR" "$WA" "$FI" "$MCP"; do
  [ -x "$f" ] || _fail "executable missing: $f"
done

echo "[test-integration-path-b] start"
cd "$HOME"  # 安全な cwd

# Step 1: pro-review-start で依頼 + workspace snapshot を用意
REPO=$(mkrepo)
PROJECT="iB-$$"
OUT=$("$ST" "$REPO" "$PROJECT" --mode review --question "are there bugs?")
assert_exit_ok "$?" "S1 start exit 0"
SINCE=$(printf '%s\n' "$OUT" | awk '/^since:/{print $2; exit}')
RUN_ID=$(printf '%s\n' "$OUT" | awk '/^run_id:/{print $2; exit}')
INBOX=$(printf '%s\n'   "$OUT" | awk '/^inbox:/{print $2; exit}')
[ -n "$SINCE" ] && [ -n "$RUN_ID" ] && [ -n "$INBOX" ] || _fail "S1 machine-readable missing"
_ok "S1 since=$SINCE run_id=$RUN_ID inbox=$INBOX"

# Step 2: 偽 reply を MCP save_report で投入（ChatGPT が MCP で保存する想定）
FAKE_REPLY=$(printf 'workspace を search で見て fetch で読みました。\n結論: バグなし\n[[DONE-%s]]' "$RUN_ID")
SAVE_OUT=$(python3 <<EOF
import json, subprocess
p = subprocess.Popen(["$MCP"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
def send(m):
    p.stdin.write(json.dumps(m, ensure_ascii=False) + "\n")
    p.stdin.flush()
def recv():
    return json.loads(p.stdout.readline())
send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"0"}}})
recv()
send({"jsonrpc":"2.0","method":"notifications/initialized"})
send({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"save_report","arguments":{"project":"$PROJECT","run_id":"$RUN_ID","body":"""$FAKE_REPLY"""}}})
resp = recv()
p.stdin.close()
p.terminate()
print(json.dumps(resp, ensure_ascii=False))
EOF
)
SAVE_OK=$(printf '%s' "$SAVE_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['structuredContent']['saved'])")
assert_eq "True" "$SAVE_OK" "S2 save_report saved"
REPLY_PATH="$INBOX/REPLY-$RUN_ID.md"
assert_file_exists "$REPLY_PATH" "S2 reply persisted"

# Step 3: watch で検知
W_OUT=$("$WA" "$INBOX" --run-id "$RUN_ID" --since "$((SINCE - 1))" --timeout 5 --interval 1 2>/dev/null)
assert_exit_ok "$?" "S3 watch detected"
assert_contains "$W_OUT" "REPLY:" "S3 REPLY line"

# Step 4: finish で reports 永続化＋クリーンアップ
F_OUT=$("$FI" "$PROJECT" "$REPLY_PATH" 2>&1)
assert_exit_ok "$?" "S4 finish exit 0"
REPORTS="$HOME/.pro-review/reports/$PROJECT"
COUNT=$(ls "$REPORTS"/*REPLY* 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" -ge 1 ] || _fail "S4 reports not persisted"
_ok "S4 reports persisted ($COUNT file(s))"

# active-project が finish で空になっているか確認
ACTIVE=$(cat "$HOME/.pro-review/active-project" 2>/dev/null || true)
assert_eq "" "$ACTIVE" "S4 active-project cleared"

# クリーンアップ
cleanup_paths "$REPO" "$INBOX" "$REPORTS" "$HOME/.pro-review/workspace/$PROJECT" "$HOME/.pro-review/metadata/$PROJECT.source"

echo "[test-integration-path-b] PASS"
