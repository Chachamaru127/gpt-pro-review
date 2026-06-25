#!/usr/bin/env bash
# 6.9: reply を 対応/見送り/要確認 に分類する。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

SUM="$(repo_scripts_dir)/pro-review-summarize"
[ -x "$SUM" ] || _fail "pro-review-summarize not executable: $SUM"

echo "[test-summarize] start"

TMP=$(mktemp -d -t prr-summarize-XXXXXX)
trap 'cleanup_paths "$TMP"' EXIT
REPLY="$TMP/reply.md"
JSON_OUT="$TMP/summary.json"
MD_OUT="$TMP/summary.md"
cat > "$REPLY" <<'EOF'
[高] app.py:12 — 認証なしで管理操作が実行できる
推奨修正: require_admin() を通す
[低] README.md:3 — 文言が少し古い
推奨修正: 後で更新
[中] billing.py:88 — 境界条件は要確認
推奨修正: 実データで確認する
[[DONE-1700000000123-aabbcc]]
EOF

OUT=$("$SUM" "$REPLY" --json-out "$JSON_OUT" --markdown-out "$MD_OUT")
assert_exit_ok "$?" "T1 summarize exit"
assert_file_exists "$JSON_OUT" "T1 json output"
assert_file_exists "$MD_OUT" "T1 markdown output"

TOTAL=$(printf '%s' "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['total'])")
assert_eq "3" "$TOTAL" "T1 total findings"
ACT=$(printf '%s' "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['counts'].get('対応'))")
ASK=$(printf '%s' "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['counts'].get('要確認'))")
SKIP=$(printf '%s' "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['counts'].get('見送り'))")
assert_eq "1" "$ACT" "T1 対応 count"
assert_eq "1" "$ASK" "T1 要確認 count"
assert_eq "1" "$SKIP" "T1 見送り count"
assert_contains "$(cat "$MD_OUT")" "app.py:12" "T1 markdown file line"
assert_contains "$(cat "$JSON_OUT")" "require_admin" "T1 recommendation captured"

file_mode() {
  python3 - "$1" <<'PY'
import os, stat, sys
print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])
PY
}
MODE_JSON=$(file_mode "$JSON_OUT")
MODE_MD=$(file_mode "$MD_OUT")
assert_eq "600" "$MODE_JSON" "T1 json mode 600"
assert_eq "600" "$MODE_MD" "T1 markdown mode 600"

LIVE_REPLY="$TMP/live-reply.md"
cat > "$LIVE_REPLY" <<'EOF'
全体評価:
要修正
指摘一覧:
[中]
calc.py:3
—
b == 0
で依然として
ZeroDivisionError
が発生し、期待値 None と矛盾します —
b == 0 を明示的に処理してください。
追加確認:
None を返す契約が本当に正しいか確認が必要です。
[[DONE-1782320834115-915037]]
EOF
LIVE_OUT=$("$SUM" "$LIVE_REPLY")
LIVE_TOTAL=$(printf '%s' "$LIVE_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['total'])")
assert_eq "1" "$LIVE_TOTAL" "T2 live multiline total"
assert_contains "$LIVE_OUT" "calc.py" "T2 live file captured"
assert_contains "$LIVE_OUT" "ZeroDivisionError" "T2 live multiline title captured"

JP_INLINE_REPLY="$TMP/jp-inline-reply.md"
cat > "$JP_INLINE_REPLY" <<'EOF'
結論: 要修正です。

* 重大度: 中 — divide(a, b) はゼロ除算時に None を返す期待仕様にもかかわらず、return a / b のままなので b == 0 で ZeroDivisionError が発生します。該当箇所: calc.py:2-3

推奨修正:
```python
def divide(a, b):
    if b == 0:
        return None
    return a / b
```

[[DONE-1782322527856-db0e7a]]
EOF
JP_INLINE_OUT=$("$SUM" "$JP_INLINE_REPLY")
JP_INLINE_TOTAL=$(printf '%s' "$JP_INLINE_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['total'])")
assert_eq "1" "$JP_INLINE_TOTAL" "T3 jp inline severity total"
assert_contains "$JP_INLINE_OUT" "calc.py" "T3 jp inline file captured"
assert_contains "$JP_INLINE_OUT" "ZeroDivisionError" "T3 jp inline title captured"
JP_INLINE_REC=$(printf '%s' "$JP_INLINE_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['findings'][0]['recommendation'])")
assert_contains "$JP_INLINE_REC" "return None" "T3 jp inline multiline recommendation captured"

COMPACT_REPLY="$TMP/compact-reply.md"
cat > "$COMPACT_REPLY" <<'EOF'
[Medium]calc.py:3—compact form still fails
recommendation: handle zero before division
[[DONE-1782374904970-b429de]]
EOF
COMPACT_OUT=$("$SUM" "$COMPACT_REPLY")
COMPACT_TOTAL=$(printf '%s' "$COMPACT_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['total'])")
COMPACT_DECISION=$(printf '%s' "$COMPACT_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['findings'][0]['decision'])")
assert_eq "1" "$COMPACT_TOTAL" "T4 compact finding total"
assert_eq "対応" "$COMPACT_DECISION" "T4 severity normalization decision"

SPLIT_REPLY="$TMP/split-reply.md"
cat > "$SPLIT_REPLY" <<'EOF'
[中]
scripts/pro-review-summarize
:16 — split file and line style
推奨修正: keep parsing this form
[[DONE-1782374904970-b429de]]
EOF
SPLIT_OUT=$("$SUM" "$SPLIT_REPLY")
SPLIT_TOTAL=$(printf '%s' "$SPLIT_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['total'])")
SPLIT_FILE=$(printf '%s' "$SPLIT_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['findings'][0]['file'])")
SPLIT_LINE=$(printf '%s' "$SPLIT_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['findings'][0]['line'])")
SPLIT_TITLE=$(printf '%s' "$SPLIT_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['findings'][0]['title'])")
SPLIT_REC=$(printf '%s' "$SPLIT_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['findings'][0]['recommendation'])")
assert_eq "1" "$SPLIT_TOTAL" "T5 split file-line total"
assert_eq "scripts/pro-review-summarize" "$SPLIT_FILE" "T5 split file captured"
assert_eq "16" "$SPLIT_LINE" "T5 split line captured"
assert_contains "$SPLIT_TITLE" "split file and line style" "T5 split title captured"
assert_contains "$SPLIT_REC" "keep parsing this form" "T5 split recommendation captured"

DONE_IN_FENCE_REPLY="$TMP/done-in-fence-reply.md"
cat > "$DONE_IN_FENCE_REPLY" <<'EOF'
[中] calc.py:3 — code fence contains marker text
推奨修正:
```text
[[DONE-not-the-run-id]]
```
[[DONE-1782374904970-b429de]]
EOF
DONE_IN_FENCE_OUT=$("$SUM" "$DONE_IN_FENCE_REPLY")
DONE_IN_FENCE_REC=$(printf '%s' "$DONE_IN_FENCE_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['findings'][0]['recommendation'])")
assert_contains "$DONE_IN_FENCE_REC" "DONE-not-the-run-id" "T6 DONE marker inside fence retained"

POSITIVE_SPLIT_EXAMPLE_REPLY="$TMP/positive-split-example-reply.md"
cat > "$POSITIVE_SPLIT_EXAMPLE_REPLY" <<'EOF'
OK / 高・中 severity なし
指摘一覧
なし。
見落としやすい点:
T5 は以下の true split 形式になっています。
[中]
→
scripts/pro-review-summarize
→
:16 — split file and line style
compact / JP inline / fenced recommendation も合格ラインを満たしています。
[[DONE-1782375908488-dc1c39]]
EOF
POSITIVE_SPLIT_OUT=$("$SUM" "$POSITIVE_SPLIT_EXAMPLE_REPLY")
POSITIVE_SPLIT_TOTAL=$(printf '%s' "$POSITIVE_SPLIT_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['total'])")
assert_eq "0" "$POSITIVE_SPLIT_TOTAL" "T7 positive split example is not a finding"

echo "[test-summarize] PASS"
