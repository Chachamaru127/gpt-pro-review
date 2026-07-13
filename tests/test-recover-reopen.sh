#!/usr/bin/env bash
# 11.7: extract-only auto re-open via staged conversation URL (host validation at use).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

DRV="$(repo_scripts_dir)/pro-review-browser-drive"
[ -x "$DRV" ] || _fail "pro-review-browser-drive not executable: $DRV"

echo "[test-recover-reopen] start"

TMP_HOME=$(mktemp -d -t prr-recover-reopen-home-XXXXXX)
OUTBOX="$TMP_HOME/.pro-review/outbox"
mkdir -p "$OUTBOX"
chmod 700 "$TMP_HOME/.pro-review" "$OUTBOX"
trap 'cleanup_paths "$TMP_HOME"' EXIT

RID="1700000000123-reopen01"
GOOD_URL="https://chatgpt.com/c/reopen-fixture"

HOME="$TMP_HOME" python3 - "$DRV" "$RID" "$GOOD_URL" <<'PY'
import importlib.machinery
import io
import sys

mod = importlib.machinery.SourceFileLoader("prr_reopen", sys.argv[1]).load_module()
run_id = sys.argv[2]
good_url = sys.argv[3]
conv_file = mod.conversation_url_outbox_path(run_id)

with open(conv_file, "w", encoding="utf-8") as f:
    f.write("https://evil.example.com/c/x\n")

assert mod.load_persisted_conversation_url(run_id) is None
assert mod.resolve_reopen_conversation_url(run_id) is None

stderr = io.StringIO()
real_stderr = sys.stderr
sys.stderr = stderr
try:
    assert mod.resolve_reopen_conversation_url(run_id) is None
finally:
    sys.stderr = real_stderr
err = stderr.getvalue()
assert "rejected for reopen" in err
assert "evil.example.com" in err

with open(conv_file, "w", encoding="utf-8") as f:
    f.write(good_url + "\n")
assert mod.resolve_reopen_conversation_url(run_id) == good_url
assert mod.load_persisted_conversation_url(run_id) == good_url
PY
assert_exit_ok "$?" "T1 resolve_reopen rejects evil host and accepts chatgpt.com"

python3 - "$DRV" <<'PY'
import importlib.machinery
import re
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
start = src.index("if args.extract_only:")
end = src.index("selector, editor = await wait_for_chat_input", start)
block = src[start:end]
assert block.count("reopening conversation:") == 1
assert block.count("await extract_live_reply(") == 2
assert not re.search(r"\bwhile\b.*extract_live_reply", block, re.S)
assert not re.search(r"\bfor\b.*extract_live_reply", block, re.S)
assert "resolve_reopen_conversation_url" in block
assert block.count("validate_conversation_url(reopen_url)") == 1
PY
assert_exit_ok "$?" "T2 extract-only re-open retries extract once (no loop)"

echo "[test-recover-reopen] PASS"
