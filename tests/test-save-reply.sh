#!/usr/bin/env bash
# pro-review-save-reply のテスト。
# 正常系: stdin / --text / アトミック / 出力パス
# 異常系: project 名 path injection / since 数値以外 / inbox 配下強制 / symlink 拒否

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

CMD="$(repo_scripts_dir)/pro-review-save-reply"
[ -x "$CMD" ] || _fail "pro-review-save-reply not executable at $CMD"

# テスト隔離: 各 case で project 名を変える
TS_BASE=1700000000

echo "[test-save-reply] start"

# ---- T1: 正常系 (stdin) ----
P="prr-t1-$$"
SINCE=$((TS_BASE + 1))
INBOX_DIR="$HOME/.pro-review/inbox/$P"
mkdir -p "$INBOX_DIR"
OUT=$(printf 'review body\n[[DONE-%s]]\n' "$SINCE" | "$CMD" "$P" "$SINCE")
RC=$?
assert_exit_ok "$RC" "T1 exit 0"
assert_contains "$OUT" "saved:" "T1 saved: line"
EXPECT="$INBOX_DIR/REPLY-$SINCE.md"
assert_file_exists "$EXPECT" "T1 reply file"
assert_contains "$(cat "$EXPECT")" "[[DONE-$SINCE]]" "T1 file contains marker"
# tmp ファイルが残っていないこと
TMP_COUNT=$(find "$INBOX_DIR" -maxdepth 1 -name '.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "0" "$TMP_COUNT" "T1 no leftover tmp file"
cleanup_paths "$INBOX_DIR"

# ---- T2: 正常系 (--text) ----
P="prr-t2-$$"
SINCE=$((TS_BASE + 2))
INBOX_DIR="$HOME/.pro-review/inbox/$P"
mkdir -p "$INBOX_DIR"
OUT=$("$CMD" "$P" "$SINCE" --text "hello [[DONE-$SINCE]]" < /dev/null)  # CI は stdin が空 FIFO のため明示 close
assert_exit_ok "$?" "T2 exit 0"
assert_file_exists "$INBOX_DIR/REPLY-$SINCE.md" "T2 reply file"
cleanup_paths "$INBOX_DIR"

# ---- T3: stdin と --text の併用は拒否 ----
P="prr-t3-$$"
SINCE=$((TS_BASE + 3))
mkdir -p "$HOME/.pro-review/inbox/$P"
set +e
echo "stdin" | "$CMD" "$P" "$SINCE" --text "text" >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T3 stdin+--text 排他"
cleanup_paths "$HOME/.pro-review/inbox/$P"

# ---- T4: project 名 path injection 拒否 ----
set +e
echo "x" | "$CMD" "../etc" 1700000004 >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T4 project '../etc' 拒否"

set +e
echo "x" | "$CMD" "../../foo" 1700000004 >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T4 project '../../foo' 拒否"

set +e
echo "x" | "$CMD" "" 1700000004 >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T4 project '' 拒否"

# ---- T5: run_id 不正値 拒否 ----
set +e
echo "x" | "$CMD" "prr-t5-$$" "-1" >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T5 run_id '-1' 拒否"

set +e
echo "x" | "$CMD" "prr-t5-$$" "" >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T5 run_id '' 拒否"

set +e
echo "x" | "$CMD" "prr-t5-$$" "../x" >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T5 run_id '../x' 拒否"

set +e
echo "x" | "$CMD" "prr-t5-$$" "has space" >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T5 run_id 'has space' 拒否"

set +e
echo "x" | "$CMD" "prr-t5-$$" "a/b" >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T5 run_id 'a/b' 拒否"

# path-safe 非数値 id（新 run_id 形式の簡易例）は受理
P5="prr-t5b-$$"
mkdir -p "$HOME/.pro-review/inbox/$P5"
"$CMD" "$P5" "legacy-alpha" --text "ok" >/dev/null < /dev/null
assert_file_exists "$HOME/.pro-review/inbox/$P5/REPLY-legacy-alpha.md" "T5 path-safe non-numeric run_id"
cleanup_paths "$HOME/.pro-review/inbox/$P5"

# ---- T6: 出力先が既に symlink の場合は拒否 ----
P="prr-t6-$$"
SINCE=$((TS_BASE + 6))
INBOX_DIR="$HOME/.pro-review/inbox/$P"
mkdir -p "$INBOX_DIR"
ln -s /tmp/nonexistent "$INBOX_DIR/REPLY-$SINCE.md"
set +e
echo "x" | "$CMD" "$P" "$SINCE" >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T6 出力先 symlink 拒否"
rm -f "$INBOX_DIR/REPLY-$SINCE.md"
cleanup_paths "$INBOX_DIR"

# ---- T7: アトミック性 — 大きめの content でも tmp 残骸無し ----
P="prr-t7-$$"
SINCE=$((TS_BASE + 7))
INBOX_DIR="$HOME/.pro-review/inbox/$P"
mkdir -p "$INBOX_DIR"
python3 -c "import sys; sys.stdout.write('A' * 100_000 + '\n[[DONE-%d]]\n' % $SINCE)" | "$CMD" "$P" "$SINCE" >/dev/null
assert_file_exists "$INBOX_DIR/REPLY-$SINCE.md" "T7 100KB reply written"
SIZE=$(wc -c < "$INBOX_DIR/REPLY-$SINCE.md")
[ "$SIZE" -gt 99000 ] || _fail "T7 reply size suspicious: $SIZE"
_ok "T7 size $SIZE bytes"
TMP_COUNT=$(find "$INBOX_DIR" -maxdepth 1 -name '.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "0" "$TMP_COUNT" "T7 no tmp leftover after large write"
cleanup_paths "$INBOX_DIR"

echo "[test-save-reply] PASS"
