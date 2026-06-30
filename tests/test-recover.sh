#!/usr/bin/env bash
# Path A recover(8.1) + browser-drive --fixture-reply の e2e。
# 隔離 HOME で実環境を汚さない。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

SK="$(repo_scripts_dir)"
REC="$SK/pro-review-recover"
DRV="$SK/pro-review-browser-drive"
[ -x "$REC" ] || _fail "pro-review-recover not executable: $REC"
[ -x "$DRV" ] || _fail "pro-review-browser-drive not executable: $DRV"

echo "[test-recover] start"

TMP_HOME=$(mktemp -d -t prr-recover-home-XXXXXX)
trap 'cleanup_paths "$TMP_HOME"' EXIT
mkdir -p "$TMP_HOME/.pro-review"
chmod 700 "$TMP_HOME/.pro-review"

RID="1700000000123-rec001"
OKREPLY="$TMP_HOME/ok.txt"
BADREPLY="$TMP_HOME/bad.txt"
printf 'レビュー結論: 問題なし\ncalc.py:1 注意 (低)\n[[DONE-%s]]\n' "$RID" > "$OKREPLY"
printf 'まだ途中の回答\n' > "$BADREPLY"

# ---- T1: browser-drive --fixture-reply (コピー取得のモック) 正常/異常 ----
OUT=$(HOME="$TMP_HOME" "$DRV" --fixture-reply "$OKREPLY" --run-id "$RID")
assert_exit_ok "$?" "T1 drive fixture-reply ok exit"
assert_contains "$OUT" "[[DONE-$RID]]" "T1 drive prints validated reply"
set +e
HOME="$TMP_HOME" "$DRV" --fixture-reply "$BADREPLY" --run-id "$RID" >/dev/null 2>&1
RC=$?
set -e
assert_eq "2" "$RC" "T1 drive fixture-reply missing marker exit 2"

# ---- T2: recover 正常 → save-reply + report_bundle ----
PROJ="recover-ok"
OUT=$(HOME="$TMP_HOME" "$REC" "$PROJ" "$RID" --fixture-reply "$OKREPLY")
assert_exit_ok "$?" "T2 recover exit ok"
assert_contains "$OUT" "saved:" "T2 recover saved"
assert_contains "$OUT" "report_bundle:" "T2 recover bundle"
assert_contains "$OUT" "[recovered]" "T2 recover done line"
BUNDLE=$(printf '%s\n' "$OUT" | awk '/^report_bundle:/{print $2; exit}')
assert_file_exists "$BUNDLE/reply.md" "T2 bundle reply"
assert_contains "$(cat "$BUNDLE/reply.md")" "[[DONE-$RID]]" "T2 bundle reply marker"
assert_file_exists "$TMP_HOME/.pro-review/inbox/$PROJ/REPLY-$RID.md" "T2 inbox REPLY written"

# ---- T3: 抽出失敗(marker無し) → STOP_REASON=recover_extract_failed + exit 3 ----
set +e
OUT3=$(HOME="$TMP_HOME" "$REC" "recover-bad" "$RID" --fixture-reply "$BADREPLY" 2>&1)
RC3=$?
set -e
assert_eq "3" "$RC3" "T3 recover extract fail exit 3"
assert_contains "$OUT3" "STOP_REASON=recover_extract_failed" "T3 recover stop reason"

# ---- T4: 不正な project / run_id は exit 2 ----
set +e
HOME="$TMP_HOME" "$REC" "bad/proj" "$RID" --fixture-reply "$OKREPLY" >/dev/null 2>&1
RC4=$?
HOME="$TMP_HOME" "$REC" "okproj" "bad/id" --fixture-reply "$OKREPLY" >/dev/null 2>&1
RC5=$?
set -e
assert_eq "2" "$RC4" "T4 invalid project exit 2"
assert_eq "2" "$RC5" "T4 invalid run_id exit 2"

echo "[test-recover] PASS"
