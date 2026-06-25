#!/usr/bin/env bash
# pro-review-start のプロンプトテンプレ regression テスト。
# 期待: search/fetch/save_report 指示 + [[DONE-${run_id}]] 末尾マーカー + 機械可読行。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

CMD="$(local_start_cmd)"
trap 'rm -rf "$(dirname "$CMD")"' EXIT
[ -x "$CMD" ] || _fail "pro-review-start not executable: $CMD"

echo "[test-start-template] start"

REPO=$(mkrepo)
PROJECT="startreg-$$"
OUT=$("$CMD" "$REPO" "$PROJECT" --mode review --question "find bugs")
RC=$?
assert_exit_ok "$RC" "T1 exit 0"

SINCE=$(printf '%s\n' "$OUT" | awk '/^since:/{print $2; exit}')
RUN_ID=$(printf '%s\n' "$OUT" | awk '/^run_id:/{print $2; exit}')
REQ=$(printf '%s\n'   "$OUT" | awk '/^request_file:/{print $2; exit}')
PNAME=$(printf '%s\n' "$OUT" | awk '/^project_name:/{print $2; exit}')
MODE=$(printf '%s\n'  "$OUT" | awk '/^mode:/{print $2; exit}')

assert_eq "$PROJECT" "$PNAME" "T1 project_name"
assert_eq "review"   "$MODE"  "T1 mode review"
case "$SINCE" in ''|*[!0-9]*) _fail "T1 since must be integer: $SINCE";; esac
_ok "T1 since=$SINCE"
echo "$RUN_ID" | grep -qE '^[0-9]+-[0-9a-f]{6}$' || _fail "T1 run_id format: $RUN_ID"
_ok "T1 run_id=$RUN_ID"
assert_file_exists "$REQ" "T1 request_file"
assert_contains "$REQ" "$RUN_ID" "T1 request_file contains run_id"

CONTENT=$(cat "$REQ")
assert_contains "$CONTENT" "search("  "T1 search() 指示"
assert_contains "$CONTENT" "fetch("   "T1 fetch() 指示"
assert_contains "$CONTENT" "save_report" "T1 save_report 指示"
assert_contains "$CONTENT" "Developer Mode" "T1 Developer Mode 前提"
assert_contains "$CONTENT" "Tunnel connector" "T1 Tunnel connector 前提"
assert_contains "$CONTENT" "STOP_REASON=connector_unavailable" "T1 connector unavailable stop"
assert_contains "$CONTENT" "レビューせず" "T1 connector missing blocks fake review"
assert_contains "$CONTENT" "project: $PROJECT" "T1 project 指示"
assert_contains "$CONTENT" "run_id: $RUN_ID" "T1 run_id 指示"
assert_contains "$CONTENT" "find bugs" "T1 question 反映"
assert_contains "$CONTENT" "[[DONE-$RUN_ID]]" "T1 DONE marker uses run_id"
assert_not_contains "$CONTENT" "[[DONE-$SINCE]]" "T1 DONE not seconds-only"
assert_contains "$OUT" "ChatGPT(non-5.5Pro + Tunnel connector)" "T1 output header"

# 各モードのテンプレ
for M in research implement; do
  PROJ2="startreg-$$-$M"
  OUT2=$("$CMD" "$REPO" "$PROJ2" --mode "$M" --question "Q")
  REQ2=$(printf '%s\n' "$OUT2" | awk '/^request_file:/{print $2; exit}')
  SINCE2=$(printf '%s\n' "$OUT2" | awk '/^since:/{print $2; exit}')
  RUN2=$(printf '%s\n' "$OUT2" | awk '/^run_id:/{print $2; exit}')
  CONT2=$(cat "$REQ2")
  assert_contains "$CONT2" "[[DONE-$RUN2]]" "T2 $M mode DONE marker"
  case "$M" in
    research) assert_contains "$CONT2" "調査" "T2 $M task キーワード";;
    implement) assert_contains "$CONT2" "diff" "T2 $M unified diff 指示";;
  esac
  cleanup_paths "$HOME/.pro-review/inbox/$PROJ2" "$HOME/.pro-review/workspace/$PROJ2"
done

# 不正 mode 拒否
set +e
"$CMD" "$REPO" "startreg-bad-$$" --mode bogus >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T3 不正 mode 拒否"

# active-project の後始末
: > "$HOME/.pro-review/active-project"
cleanup_paths "$REPO" "$HOME/.pro-review/inbox/$PROJECT" "$HOME/.pro-review/workspace/$PROJECT"

echo "[test-start-template] PASS"
