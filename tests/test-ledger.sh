#!/usr/bin/env bash
# 12.3: findings ledger append-only + cross-round stats.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

LEDGER="$(repo_scripts_dir)/pro-review-ledger"
[ -x "$LEDGER" ] || _fail "pro-review-ledger not executable: $LEDGER"

echo "[test-ledger] start"

TMP_HOME=$(mktemp -d -t prr-ledger-home-XXXXXX)
TMP=$(mktemp -d -t prr-ledger-XXXXXX)
trap 'cleanup_paths "$TMP_HOME" "$TMP"' EXIT

PROJECT="ledger-$$"
RID1="1700000000100-run01"
RID2="1700000000200-run02"
SUM1="$TMP/summary1.json"
SUM2="$TMP/summary2.json"
LEDGER_FILE="$TMP_HOME/.pro-review/ledger/$PROJECT.jsonl"

cat > "$SUM1" <<'EOF'
{
  "reply_path": "/tmp/reply1.md",
  "total": 2,
  "counts": {"対応": 1, "見送り": 1},
  "findings": [
    {
      "id": "f-111111111111",
      "severity": "高",
      "file": "a.py",
      "line": 1,
      "title": "issue a",
      "recommendation": "fix a",
      "decision": "対応"
    },
    {
      "id": "f-222222222222",
      "severity": "低",
      "file": "b.py",
      "line": 2,
      "title": "issue b",
      "recommendation": "",
      "decision": "見送り"
    }
  ]
}
EOF

cat > "$SUM2" <<'EOF'
{
  "reply_path": "/tmp/reply2.md",
  "total": 2,
  "counts": {"対応": 1, "要確認": 1},
  "findings": [
    {
      "id": "f-111111111111",
      "severity": "高",
      "file": "a.py",
      "line": 1,
      "title": "issue a",
      "recommendation": "fix a",
      "decision": "対応"
    },
    {
      "id": "f-333333333333",
      "severity": "中",
      "file": "c.py",
      "line": 3,
      "title": "issue c",
      "recommendation": "check",
      "decision": "要確認"
    }
  ]
}
EOF

OUT1=$(HOME="$TMP_HOME" "$LEDGER" append "$PROJECT" "$SUM1" --run-id "$RID1")
assert_exit_ok "$?" "T1 append run1 exit"
assert_contains "$OUT1" "appended: 2 findings" "T1 append run1 count"
assert_file_exists "$LEDGER_FILE" "T1 ledger file exists"

FIRST_SNAPSHOT=$(cat "$LEDGER_FILE")
LINE_COUNT1=$(wc -l < "$LEDGER_FILE" | tr -d ' ')
assert_eq "2" "$LINE_COUNT1" "T1 ledger line count"

python3 - "$LEDGER_FILE" "$RID1" <<'PY'
import json, sys

path, run_id = sys.argv[1], sys.argv[2]
rows = [json.loads(line) for line in open(path, encoding="utf-8") if line.strip()]
if len(rows) != 2:
    raise SystemExit(f"expected 2 rows, got {len(rows)}")
for row in rows:
    for key in ("project", "run_id", "recorded_at", "finding_id", "severity", "decision"):
        if key not in row:
            raise SystemExit(f"missing key {key!r} in row")
    if row["run_id"] != run_id:
        raise SystemExit(f"run_id mismatch: {row['run_id']!r}")
print("ok T1 jsonl schema")
PY
assert_exit_ok "$?" "T1 jsonl schema"

OUT2=$(HOME="$TMP_HOME" "$LEDGER" append "$PROJECT" "$SUM2" --run-id "$RID2")
assert_exit_ok "$?" "T2 append run2 exit"
assert_contains "$OUT2" "appended: 2 findings" "T2 append run2 count"

LINE_COUNT2=$(wc -l < "$LEDGER_FILE" | tr -d ' ')
assert_eq "4" "$LINE_COUNT2" "T2 ledger line count after second append"
assert_eq "$FIRST_SNAPSHOT" "$(head -n 2 "$LEDGER_FILE")" "T2 first append rows unchanged"

LEDGER_MODE=$(stat -f '%Lp' "$LEDGER_FILE")
LEDGER_DIR_MODE=$(stat -f '%Lp' "$TMP_HOME/.pro-review/ledger")
assert_eq "600" "$LEDGER_MODE" "T2 ledger file mode 600"
assert_eq "700" "$LEDGER_DIR_MODE" "T2 ledger dir mode 700"

STATS=$(HOME="$TMP_HOME" "$LEDGER" stats "$PROJECT")
assert_exit_ok "$?" "T3 stats exit"
assert_contains "$STATS" "total_findings: 4" "T3 total findings"
assert_contains "$STATS" "rounds: 2" "T3 rounds"
assert_contains "$STATS" "recurring_ids: 1" "T3 recurring id count"
assert_contains "$STATS" "対応: 2 (50.0%)" "T3 対応 rate"
assert_contains "$STATS" "見送り: 1 (25.0%)" "T3 見送り rate"
assert_contains "$STATS" "要確認: 1 (25.0%)" "T3 要確認 rate"
assert_contains "$STATS" "proxy 指標" "T3 proxy note present"
assert_contains "$STATS" "客観的な正誤率ではありません" "T3 proxy disclaimer present"

echo "[test-ledger] PASS"
