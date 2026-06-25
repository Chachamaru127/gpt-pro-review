#!/usr/bin/env bash
# 6.11c: persistence permission と daemon log redaction。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

REPO_SCRIPTS="$(repo_scripts_dir)"
SR="$REPO_SCRIPTS/pro-review-save-reply"
FI="$REPO_SCRIPTS/pro-review-finish"
RED="$REPO_SCRIPTS/pro-review-redact-log"
for f in "$SR" "$FI" "$RED"; do
  [ -x "$f" ] || _fail "executable missing: $f"
done

echo "[test-persistence-redaction] start"

PROJECT="persist-$$"
RID="1700000000123-aabbcc"
INBOX="$HOME/.pro-review/inbox/$PROJECT"
REPORTS="$HOME/.pro-review/reports/$PROJECT"
trap 'cleanup_paths "$INBOX" "$REPORTS" "$HOME/.pro-review/daemon-test-$$.log"' EXIT

printf 'review\n[[DONE-%s]]\n' "$RID" | "$SR" "$PROJECT" "$RID" >/dev/null
BASE_MODE=$(stat -f '%Lp' "$HOME/.pro-review")
INBOX_MODE=$(stat -f '%Lp' "$INBOX")
REPLY="$INBOX/REPLY-$RID.md"
REPLY_MODE=$(stat -f '%Lp' "$REPLY")
assert_eq "700" "$BASE_MODE" "T1 ~/.pro-review mode 700"
assert_eq "700" "$INBOX_MODE" "T1 inbox mode 700"
assert_eq "600" "$REPLY_MODE" "T1 reply mode 600"

F_OUT=$("$FI" "$PROJECT" "$REPLY" 2>&1)
assert_exit_ok "$?" "T2 finish exit 0"
REPORT=$(printf '%s\n' "$F_OUT" | awk '/^report_saved:/{print $2; exit}')
assert_file_exists "$REPORT" "T2 report exists"
REPORT_MODE=$(stat -f '%Lp' "$REPORT")
assert_eq "600" "$REPORT_MODE" "T2 report mode 600"

RAW='CONTROL_PLANE_API_KEY=sk-proj-1234567890abcdef Cookie: sessionid=secret_cookie sk-live-abcdefghijklmnop'
LOG="$HOME/.pro-review/daemon-test-$$.log"
printf '%s\n' "$RAW" | "$RED" > "$LOG"
chmod 600 "$LOG"
CONTENT=$(cat "$LOG")
assert_not_contains "$CONTENT" "sk-proj-1234567890abcdef" "T3 API key redacted"
assert_not_contains "$CONTENT" "secret_cookie" "T3 cookie redacted"
assert_not_contains "$CONTENT" "sk-live-abcdefghijklmnop" "T3 sk token redacted"
assert_contains "$CONTENT" "<REDACTED>" "T3 redaction marker present"
LOG_MODE=$(stat -f '%Lp' "$LOG")
assert_eq "600" "$LOG_MODE" "T3 daemon log mode 600"

echo "[test-persistence-redaction] PASS"
