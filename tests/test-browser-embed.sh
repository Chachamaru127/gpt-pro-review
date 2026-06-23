#!/usr/bin/env bash
# pro-review-browser-embed のテスト。
# - `--github-branch` 未指定: build-review-packet 風に diff/changed file を埋め込む
# - `--github-branch BRANCH` 指定: コード非埋め込み + ChatGPT GitHub connector への指示文
# - 末尾に [[DONE-<since>]] マーカー注入
# - max-bytes default 80_000 (Skeptic: 無音切り捨て防止)
# - secret scan ヒット時は exit 1 (ALLOW_SECRETS=1 で上書き可)
# - 機械可読: project_name / since / inbox / request_file / clip

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

CMD="$HOME/.claude/skills/gpt-pro-review/scripts/pro-review-browser-embed"
[ -x "$CMD" ] || _fail "pro-review-browser-embed not executable at $CMD"

echo "[test-browser-embed] start"

# ---- T1: 未指定 = diff & changed file 埋込 + マーカー注入 ----
REPO=$(mkrepo)
(cd "$REPO" && echo "BUGGY_TOKEN" >> calc.py)   # 未コミット変更（subshell で cwd 汚染しない）
PROJECT="brem-t1-$$"
OUT=$("$CMD" "$REPO" "$PROJECT" --question "find bugs" --no-clip)
RC=$?
assert_exit_ok "$RC" "T1 exit 0"

SINCE=$(printf '%s\n' "$OUT" | awk '/^since:/{print $2; exit}')
REQ=$(printf '%s\n'   "$OUT" | awk '/^request_file:/{print $2; exit}')
INBOX_LINE=$(printf '%s\n' "$OUT" | awk '/^inbox:/{print $2; exit}')
PNAME=$(printf '%s\n'   "$OUT" | awk '/^project_name:/{print $2; exit}')

assert_eq "$PROJECT" "$PNAME" "T1 project_name echo"
[ -n "$SINCE" ] || _fail "T1 since empty"
case "$SINCE" in ''|*[!0-9]*) _fail "T1 since must be integer: $SINCE";; esac
_ok "T1 since=$SINCE (integer)"
assert_file_exists "$REQ" "T1 request_file"

CONTENT=$(cat "$REQ")
assert_contains "$CONTENT" "[[DONE-$SINCE]]" "T1 DONE marker injected"
assert_contains "$CONTENT" "BUGGY_TOKEN"      "T1 changed file content embedded"
assert_contains "$CONTENT" "find bugs"        "T1 question included"

cleanup_paths "$REPO" "$INBOX_LINE"

# ---- T2: --github-branch 指定 = コード非埋込 + GH 指示 ----
REPO=$(mkrepo)
PROJECT="brem-t2-$$"
OUT=$("$CMD" "$REPO" "$PROJECT" --github-branch main --question "Q" --no-clip)
assert_exit_ok "$?" "T2 exit 0"
REQ=$(printf '%s\n' "$OUT" | awk '/^request_file:/{print $2; exit}')
CONTENT=$(cat "$REQ")
assert_contains "$CONTENT" "GitHub" "T2 GH 指示文"
assert_contains "$CONTENT" "main"   "T2 branch名"
assert_not_contains "$CONTENT" '```diff' "T2 diff 非埋込"
assert_not_contains "$CONTENT" 'def add' "T2 changed file 非埋込"
SINCE=$(printf '%s\n' "$OUT" | awk '/^since:/{print $2; exit}')
assert_contains "$CONTENT" "[[DONE-$SINCE]]" "T2 DONE marker injected"
cleanup_paths "$REPO" "$HOME/.pro-review/inbox/$PROJECT"

# ---- T3: secret scan ヒット → exit 1 (ALLOW_SECRETS=1 で上書き可) ----
REPO=$(mkrepo)
# 偽のAWS access key を含むファイルを置く（untracked のまま＝build-review-packet が embed 対象に拾う）
(cd "$REPO" && echo "aws_key=AKIA1234567890ABCDEF" > config.txt)
PROJECT="brem-t3-$$"
set +e
"$CMD" "$REPO" "$PROJECT" --question "Q" --no-clip >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T3 secret scan で送信中止"

# ALLOW_SECRETS=1 で上書き
set +e
ALLOW_SECRETS=1 "$CMD" "$REPO" "$PROJECT" --question "Q" --no-clip >/dev/null 2>&1
RC=$?
set -e
assert_exit_ok "$RC" "T3 ALLOW_SECRETS=1 で上書き"
cleanup_paths "$REPO" "$HOME/.pro-review/inbox/$PROJECT"

# ---- T4: max-bytes default = 80_000 (Skeptic 対策) ----
REPO=$(mkrepo)
# 100KB を untracked で（embed 対象に拾わせる）
(cd "$REPO" && python3 -c "import sys; sys.stdout.write('X' * 100000)" > big.txt)
PROJECT="brem-t4-$$"
OUT=$("$CMD" "$REPO" "$PROJECT" --question "Q" --no-clip)
REQ=$(printf '%s\n' "$OUT" | awk '/^request_file:/{print $2; exit}')
CONTENT=$(cat "$REQ")
# truncated 注意書きが入っているか、もしくは big.txt が省略されているか
assert_contains "$CONTENT" "省略" "T4 truncated 旗 or 省略表示"
# サイズが極端に大きくない (max-bytes=80KB なので最終プロンプトは概ね 90KB 以内)
SZ=$(wc -c < "$REQ"); _ok "T4 prompt size=$SZ"
[ "$SZ" -lt 200000 ] || _fail "T4 prompt too large: $SZ (max-bytes 80KB のはず)"
cleanup_paths "$REPO" "$HOME/.pro-review/inbox/$PROJECT"

# ---- T5: project 名 path injection 拒否 ----
REPO=$(mkrepo)
set +e
"$CMD" "$REPO" "../etc" --question "Q" --no-clip >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T5 project '../etc' 拒否"
cleanup_paths "$REPO"

echo "[test-browser-embed] PASS"
