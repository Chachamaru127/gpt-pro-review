#!/usr/bin/env bash
# 6.11b: PRO_REVIEW_FULL=1 は明示 Risk Gate なしでは許可しない。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

MCP_ENTRY="$(repo_scripts_dir)/pro-review-mcp"
[ -x "$MCP_ENTRY" ] || _fail "pro-review-mcp not executable: $MCP_ENTRY"

echo "[test-full-gate] start"

ACTIVE="$HOME/.pro-review/active-project"
ACTIVE_BAK=""
if [ -s "$ACTIVE" ]; then ACTIVE_BAK=$(cat "$ACTIVE"); fi
PROJECT="full-gate-$$"
mkdir -p "$HOME/.pro-review/workspace/$PROJECT" "$HOME/.pro-review/inbox/$PROJECT"
printf '%s\n' "$PROJECT" > "$ACTIVE"

restore() {
  if [ -n "$ACTIVE_BAK" ]; then printf '%s\n' "$ACTIVE_BAK" > "$ACTIVE"; else : > "$ACTIVE"; fi
  cleanup_paths "$HOME/.pro-review/workspace/$PROJECT" "$HOME/.pro-review/inbox/$PROJECT"
}
trap restore EXIT

# default entrypoint exposes only bounded tools.
RESULT=$(python3 <<EOF
import json, subprocess
p = subprocess.Popen(["$MCP_ENTRY"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
def send(m):
    p.stdin.write(json.dumps(m) + "\n")
    p.stdin.flush()
def recv():
    return json.loads(p.stdout.readline())
send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"0"}}})
recv()
send({"jsonrpc":"2.0","method":"notifications/initialized"})
send({"jsonrpc":"2.0","id":2,"method":"tools/list"})
tools = recv()["result"]["tools"]
p.stdin.close()
p.terminate()
print(",".join(t["name"] for t in tools))
EOF
)
assert_eq "search,fetch,save_report" "$RESULT" "T1 default bounded tool list"
assert_not_contains "$RESULT" "write_file" "T1 no generic write"
assert_not_contains "$RESULT" "edit_file" "T1 no generic edit"
assert_not_contains "$RESULT" "bash" "T1 no bash"

set +e
ERR=$(PRO_REVIEW_FULL=1 "$MCP_ENTRY" 2>&1 >/tmp/prr-full-gate-$$.out)
RC=$?
set -e
assert_exit_nonzero "$RC" "T2 PRO_REVIEW_FULL without confirm rejected"
assert_contains "$ERR" "Risk Gate" "T2 rejection explains Risk Gate"

set +e
DRY=$(PRO_REVIEW_FULL=1 PRO_REVIEW_FULL_CONFIRM=I_UNDERSTAND_PRO_REVIEW_FULL PRO_REVIEW_FULL_DRY_RUN=1 "$MCP_ENTRY" 2>&1)
RC=$?
set -e
assert_exit_ok "$RC" "T3 PRO_REVIEW_FULL with confirm dry-run allowed"
assert_contains "$DRY" "would_exec:" "T3 dry-run command shown"
assert_contains "$DRY" "$PROJECT" "T3 scoped project paths"

rm -f /tmp/prr-full-gate-$$.out
echo "[test-full-gate] PASS"
