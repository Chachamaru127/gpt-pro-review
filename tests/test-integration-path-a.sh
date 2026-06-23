#!/usr/bin/env bash
# Path A (Pro ブラウザ埋め込み) の統合テスト。
# pro-review-browser-embed → 偽 reply を save-reply で投入 → watch 検知 → finish が reports 永続化。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

BE="$HOME/.claude/skills/gpt-pro-review/scripts/pro-review-browser-embed"
SR="$HOME/.claude/skills/gpt-pro-review/scripts/pro-review-save-reply"
WA="$HOME/.claude/skills/gpt-pro-review/scripts/pro-review-watch"
FI="$HOME/.claude/skills/gpt-pro-review/scripts/pro-review-finish"
for f in "$BE" "$SR" "$WA" "$FI"; do
  [ -x "$f" ] || _fail "executable missing: $f"
done

echo "[test-integration-path-a] start"
cd "$HOME"  # 安全な cwd で開始（テスト中の repo 削除に巻き込まれない）

# Step 1: browser-embed で依頼パケットを用意
REPO=$(mkrepo)
(cd "$REPO" && echo "BUG_HERE" >> calc.py)
PROJECT="iA-$$"
OUT=$("$BE" "$REPO" "$PROJECT" --question "find the bug" --no-clip)
RC=$?
assert_exit_ok "$RC" "S1 browser-embed exit 0"
SINCE=$(printf '%s\n' "$OUT" | awk '/^since:/{print $2; exit}')
INBOX=$(printf '%s\n'   "$OUT" | awk '/^inbox:/{print $2; exit}')
REQ=$(printf '%s\n'     "$OUT" | awk '/^request_file:/{print $2; exit}')
[ -n "$SINCE" ] && [ -n "$INBOX" ] && [ -n "$REQ" ] || _fail "S1 machine-readable missing"
_ok "S1 since=$SINCE inbox=$INBOX"

# Step 2: 偽 reply を save-reply 経由で投入（ChatGPT DOM 抽出を模擬）
FAKE_REPLY=$(printf 'コードレビュー結果:\n[高] calc.py:2 — BUG_HERE は誤って追加されたトークン\n推奨修正: 削除\n[[DONE-%s]]' "$SINCE")
SR_OUT=$(printf '%s' "$FAKE_REPLY" | "$SR" "$PROJECT" "$SINCE")
assert_exit_ok "$?" "S2 save-reply exit 0"
assert_contains "$SR_OUT" "saved:" "S2 saved: line"
REPLY_PATH="$INBOX/REPLY-$SINCE.md"
assert_file_exists "$REPLY_PATH" "S2 reply persisted"
assert_contains "$(cat "$REPLY_PATH")" "[[DONE-$SINCE]]" "S2 reply has marker"

# Step 3: watch で検知（保存済みなので即 hit、timeout 短く）
W_OUT=$("$WA" "$INBOX" --since "$((SINCE - 1))" --timeout 5 --interval 1 2>/dev/null)
W_RC=$?
assert_exit_ok "$W_RC" "S3 watch detected"
assert_contains "$W_OUT" "REPLY:" "S3 watch REPLY line"

# Step 4: finish で reports 永続化＋クリーンアップ
F_OUT=$("$FI" "$PROJECT" "$REPLY_PATH" 2>&1)
F_RC=$?
assert_exit_ok "$F_RC" "S4 finish exit 0"
REPORTS="$HOME/.pro-review/reports/$PROJECT"
COUNT=$(ls "$REPORTS"/*REPLY* 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" -ge 1 ] || _fail "S4 reports not persisted ($COUNT files in $REPORTS)"
_ok "S4 reports persisted ($COUNT file(s) in $REPORTS)"

# クリーンアップ
cleanup_paths "$REPO" "$INBOX" "$REPORTS" "$HOME/.pro-review/workspace/$PROJECT" "$HOME/.pro-review/metadata/$PROJECT.source"
: > "$HOME/.pro-review/active-project" 2>/dev/null || true

echo "[test-integration-path-a] PASS"
