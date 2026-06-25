#!/usr/bin/env bash
# 6.7r: REPLY-<run_id>.md の厳密採用。偽 marker / 別 run / symlink を拒否する。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

REPO_SCRIPTS="$(repo_scripts_dir)"
VAL="$REPO_SCRIPTS/pro-review-validate-reply"
WA="$REPO_SCRIPTS/pro-review-watch"
FI="$REPO_SCRIPTS/pro-review-finish"

for f in "$VAL" "$WA" "$FI"; do
  [ -x "$f" ] || _fail "executable missing: $f"
done

echo "[test-reply-matching] start"

P="reply-match-$$"
INBOX="$HOME/.pro-review/inbox/$P"
REPORTS="$HOME/.pro-review/reports/$P"
mkdir -p "$INBOX"
trap 'cleanup_paths "$INBOX" "$REPORTS"' EXIT

RID="1700000000123-a1b2c3"
GOOD="$INBOX/REPLY-$RID.md"
printf 'review body\n[[DONE-%s]]\n' "$RID" > "$GOOD"

OUT=$("$VAL" "$INBOX" --run-id "$RID" "$GOOD")
assert_exit_ok "$?" "T1 valid reply accepted"
assert_contains "$OUT" "valid:" "T1 valid output"

W_OUT=$("$WA" "$INBOX" --run-id "$RID" --since 0 --timeout 5 --interval 1 --stable 0.1 2>/dev/null)
assert_exit_ok "$?" "T2 watch accepts validated reply"
assert_contains "$W_OUT" "REPLY-$RID.md" "T2 watch returns expected reply"

F_OUT=$("$FI" "$P" "$GOOD" 2>&1)
assert_exit_ok "$?" "T3 finish accepts validated reply"
assert_contains "$F_OUT" "report_saved:" "T3 report saved"
COUNT=$(ls "$REPORTS"/*REPLY-$RID.md 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" -ge 1 ] || _fail "T3 report file missing"
_ok "T3 report file persisted"

# 別 run_id の filename は期待 run_id と一致しないので拒否。
OTHER="$INBOX/REPLY-1700000000123-deadbe.md"
printf 'review body\n[[DONE-1700000000123-deadbe]]\n' > "$OTHER"
set +e
"$VAL" "$INBOX" --run-id "$RID" "$OTHER" >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T4 wrong run_id filename rejected"

# marker が本文中だけにある場合は拒否。
BODY_ONLY="$INBOX/REPLY-1700000000123-b0b0b0.md"
printf 'quoted marker [[DONE-1700000000123-b0b0b0]]\nactual final line\n' > "$BODY_ONLY"
set +e
"$VAL" "$INBOX" "$BODY_ONLY" >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T5 body-only marker rejected"

# marker が中間行にも出る場合は拒否。
MID="$INBOX/REPLY-1700000000123-c0c0c0.md"
printf 'first\n[[DONE-1700000000123-c0c0c0]]\nsecond\n[[DONE-1700000000123-c0c0c0]]\n' > "$MID"
set +e
"$VAL" "$INBOX" "$MID" >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T6 middle marker rejected"

# symlink は拒否。
SYM="$INBOX/REPLY-1700000000123-d0d0d0.md"
ln -s "$GOOD" "$SYM"
set +e
"$VAL" "$INBOX" "$SYM" >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T7 symlink reply rejected"
rm -f "$SYM"

# inbox 外の同名ファイルは拒否。
OUTSIDE_DIR=$(mktemp -d -t prr-reply-outside-XXXXXX)
OUTSIDE="$OUTSIDE_DIR/REPLY-1700000000123-e0e0e0.md"
printf 'outside\n[[DONE-1700000000123-e0e0e0]]\n' > "$OUTSIDE"
set +e
"$VAL" "$INBOX" "$OUTSIDE" >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T8 outside reply rejected"
cleanup_paths "$OUTSIDE_DIR"

# watch は exact run_id の invalid reply を採用しない。
BAD_RID="1700000000123-f0f0f0"
BAD="$INBOX/REPLY-$BAD_RID.md"
printf 'marker not final [[DONE-%s]]\nnope\n' "$BAD_RID" > "$BAD"
set +e
"$WA" "$INBOX" --run-id "$BAD_RID" --since 0 --timeout 1 --interval 0.2 --stable 0.1 >/tmp/prr-watch-bad-$$.out 2>/dev/null
RC=$?
set -e
assert_exit_nonzero "$RC" "T9 watch rejects invalid exact reply"
assert_contains "$(cat /tmp/prr-watch-bad-$$.out)" "TIMEOUT" "T9 watch times out"
rm -f /tmp/prr-watch-bad-$$.out

# finish 省略時は newest invalid ではなく newest valid REPLY を採用する。
VALID2_RID="1700000000123-abcdef"
VALID2="$INBOX/REPLY-$VALID2_RID.md"
printf 'second valid\n[[DONE-%s]]\n' "$VALID2_RID" > "$VALID2"
sleep 1
INVALID_NEW="$INBOX/REPLY-1700000000123-cccccc.md"
printf 'newer invalid [[DONE-1700000000123-cccccc]]\nnot final\n' > "$INVALID_NEW"
F2_OUT=$("$FI" "$P" 2>&1)
assert_exit_ok "$?" "T10 finish skips invalid newest"
assert_contains "$F2_OUT" "REPLY-$VALID2_RID.md" "T10 finish uses newest valid"

echo "[test-reply-matching] PASS"
