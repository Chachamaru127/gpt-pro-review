#!/usr/bin/env bash
# 11.6: conversation URL host validation and metadata.json persistence.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

DRV="$(repo_scripts_dir)/pro-review-browser-drive"
SR="$(repo_scripts_dir)/pro-review-save-reply"
FI="$(repo_scripts_dir)/pro-review-finish"
for f in "$DRV" "$SR" "$FI"; do
  [ -x "$f" ] || _fail "executable missing: $f"
done

echo "[test-conversation-url] start"

PROJECT="convurl-$$"
RID="1700000000123-aabbcc"
INBOX="$HOME/.pro-review/inbox/$PROJECT"
REPORTS="$HOME/.pro-review/reports/$PROJECT"
OUTBOX="$HOME/.pro-review/outbox"
CONV_FILE="$OUTBOX/conversation-url-$RID"
GOOD_URL="https://chatgpt.com/c/abc123-def456"
mkdir -p "$OUTBOX"
trap 'cleanup_paths "$INBOX" "$REPORTS" "$CONV_FILE"' EXIT

python3 - "$DRV" <<'PY'
import importlib.machinery
import sys
mod = importlib.machinery.SourceFileLoader("prr_convurl", sys.argv[1]).load_module()
good = "https://chatgpt.com/c/abc123-def456"
assert mod.validate_conversation_url(good) == good
assert mod.validate_conversation_url("https://evil.example.com/c/x") is None
assert mod.validate_conversation_url("https://chat.openai.com/c/x") is None
assert mod.validate_conversation_url("https://www.chatgpt.com/c/x") is None
assert mod.validate_conversation_url("http://chatgpt.com/c/x") is None
assert mod.validate_conversation_url("") is None
assert mod.validate_conversation_url(None) is None
PY
assert_exit_ok "$?" "T1 validate_conversation_url unit"

python3 - "$DRV" <<'PY'
import importlib.machinery
import sys
mod = importlib.machinery.SourceFileLoader("prr_convurl_is", sys.argv[1]).load_module()
assert mod.is_conversation_url("https://chatgpt.com/c/abc123") is True
assert mod.is_conversation_url("https://chatgpt.com/") is False
assert mod.is_conversation_url("https://evil.example.com/c/x") is False
PY
assert_exit_ok "$?" "T1b is_conversation_url unit"

python3 - "$DRV" "$RID" "$GOOD_URL" <<'PY'
import importlib.machinery
import sys
mod = importlib.machinery.SourceFileLoader("prr_convurl_persist", sys.argv[1]).load_module()
run_id = sys.argv[2]
url = sys.argv[3]
saved = mod.persist_conversation_url(run_id, url)
assert saved == url
assert mod.load_persisted_conversation_url(run_id) == url
PY
assert_exit_ok "$?" "T2 persist valid url to outbox"
assert_file_exists "$CONV_FILE" "T2 outbox staging file"

printf '[高] app.py:1 — 問題\n推奨修正: 直す\n[[DONE-%s]]\n' "$RID" | "$SR" "$PROJECT" "$RID" >/dev/null
REPLY="$INBOX/REPLY-$RID.md"
F_OUT=$(PRO_REVIEW_REPORT_MODE=path-a PRO_REVIEW_REPORT_SINCE=1700000000123 "$FI" "$PROJECT" "$REPLY" 2>&1)
assert_exit_ok "$?" "T3 finish with valid conversation url"
BUNDLE=$(printf '%s\n' "$F_OUT" | awk '/^report_bundle:/{print $2; exit}')
[ -n "$BUNDLE" ] || _fail "T3 report_bundle missing"
META=$(cat "$BUNDLE/metadata.json")
assert_contains "$META" '"conversation_url": "https://chatgpt.com/c/abc123-def456"' "T3 metadata records chatgpt.com url"

printf 'https://evil.example.com/c/bad\n' > "$CONV_FILE"
F_OUT2=$(PRO_REVIEW_REPORT_MODE=path-a PRO_REVIEW_REPORT_SINCE=1700000000123 "$FI" "$PROJECT" "$REPLY" 2>&1)
assert_exit_ok "$?" "T4 finish rejects evil host on read"
BUNDLE2=$(printf '%s\n' "$F_OUT2" | awk '/^report_bundle:/{print $2; exit}')
META2=$(cat "$BUNDLE2/metadata.json")
assert_contains "$META2" '"conversation_url": null' "T4 metadata null for evil host"
assert_not_contains "$META2" "evil.example.com" "T4 evil url not in metadata"

printf 'https://chat.openai.com/c/legacy\n' > "$CONV_FILE"
F_OUT3=$(PRO_REVIEW_REPORT_MODE=path-a PRO_REVIEW_REPORT_SINCE=1700000000123 "$FI" "$PROJECT" "$REPLY" 2>&1)
assert_exit_ok "$?" "T5 finish rejects chat.openai.com host"
BUNDLE3=$(printf '%s\n' "$F_OUT3" | awk '/^report_bundle:/{print $2; exit}')
META3=$(cat "$BUNDLE3/metadata.json")
assert_contains "$META3" '"conversation_url": null' "T5 metadata null for chat.openai.com"
assert_not_contains "$META3" "chat.openai.com" "T5 legacy host not in metadata"

rm -f "$CONV_FILE"
F_OUT4=$(PRO_REVIEW_REPORT_MODE=path-a PRO_REVIEW_REPORT_SINCE=1700000000123 "$FI" "$PROJECT" "$REPLY" 2>&1)
assert_exit_ok "$?" "T6 finish without staging file"
BUNDLE4=$(printf '%s\n' "$F_OUT4" | awk '/^report_bundle:/{print $2; exit}')
META4=$(cat "$BUNDLE4/metadata.json")
assert_contains "$META4" '"conversation_url": null' "T6 metadata null when staging missing"

python3 - "$DRV" "$RID" <<'PY'
import importlib.machinery
import sys
mod = importlib.machinery.SourceFileLoader("prr_convurl_reject", sys.argv[1]).load_module()
run_id = sys.argv[2]
assert mod.persist_conversation_url(run_id, "https://evil.example.com/x") is None
assert mod.load_persisted_conversation_url(run_id) is None
PY
assert_exit_ok "$?" "T7 persist rejects invalid host without writing"

python3 - "$DRV" "$RID" "$CONV_FILE" <<'PY'
import importlib.machinery
import os
import sys
mod = importlib.machinery.SourceFileLoader("prr_convurl_root", sys.argv[1]).load_module()
run_id = sys.argv[2]
conv_file = sys.argv[3]
root = "https://chatgpt.com/"
assert mod.is_conversation_url(root) is False
if mod.is_conversation_url(root):
    mod.persist_conversation_url(run_id, root)
assert mod.load_persisted_conversation_url(run_id) is None
assert not os.path.isfile(conv_file)
PY
assert_exit_ok "$?" "T8 root url not persisted when not a conversation link"

echo "[test-conversation-url] PASS"
