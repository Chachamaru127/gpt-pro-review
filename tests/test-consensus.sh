#!/usr/bin/env bash
# 13.1: compare two summary JSON files into agreed / only_a / only_b.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

CONSENSUS="$(repo_scripts_dir)/pro-review-consensus"
[ -x "$CONSENSUS" ] || _fail "pro-review-consensus not executable: $CONSENSUS"

echo "[test-consensus] start"

TMP=$(mktemp -d -t prr-consensus-XXXXXX)
trap 'cleanup_paths "$TMP"' EXIT

SUM_A="$TMP/summary_a.json"
SUM_B="$TMP/summary_b.json"
OUT="$TMP/consensus.json"

cat > "$SUM_A" <<'EOF'
{
  "total": 3,
  "counts": {"対応": 2, "見送り": 1},
  "findings": [
    {
      "id": "f-aaaaaaaaaaaa",
      "severity": "高",
      "file": "./app.py",
      "line": 12,
      "title": "Auth bypass",
      "recommendation": "require_admin()",
      "decision": "対応"
    },
    {
      "id": "f-bbbbbbbbbbbb",
      "severity": "低",
      "file": "README.md",
      "line": 3,
      "title": "Stale wording",
      "recommendation": "",
      "decision": "見送り"
    },
    {
      "id": "f-cccccccccccc",
      "severity": "中",
      "file": "billing.py",
      "line": 88,
      "title": "Only in A",
      "recommendation": "check",
      "decision": "対応"
    }
  ]
}
EOF

cat > "$SUM_B" <<'EOF'
{
  "total": 3,
  "counts": {"対応": 1, "要確認": 1, "見送り": 1},
  "findings": [
    {
      "id": "f-dddddddddddd",
      "severity": "中",
      "file": "App.py",
      "line": 12,
      "title": "Different title but same location",
      "recommendation": "require_admin()",
      "decision": "対応"
    },
    {
      "id": "f-eeeeeeeeeeee",
      "severity": "低",
      "file": "README.md",
      "line": 3,
      "title": "Stale wording",
      "recommendation": "",
      "decision": "見送り"
    },
    {
      "id": "f-ffffffffffff",
      "severity": "高",
      "file": "db.py",
      "line": 40,
      "title": "Only in B",
      "recommendation": "add index",
      "decision": "要確認"
    }
  ]
}
EOF

RESULT=$("$CONSENSUS" "$SUM_A" "$SUM_B")
assert_exit_ok "$?" "T1 consensus exit"

python3 - "$RESULT" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["totals"]["agreed"] == 2, data
assert data["totals"]["only_a"] == 1, data
assert data["totals"]["only_b"] == 1, data
app = next(item for item in data["agreed"] if item["line"] == 12)
assert app["file"].lower().lstrip("./") == "app.py"
assert app["severity_a"] == "高"
assert app["severity_b"] == "中"
assert app["id_a"] == "f-aaaaaaaaaaaa"
assert app["id_b"] == "f-dddddddddddd"
assert data["only_a"][0]["title"] == "Only in A"
assert data["only_b"][0]["title"] == "Only in B"
PY
assert_exit_ok "$?" "T1 agree/dispute classification"

"$CONSENSUS" "$SUM_A" "$SUM_B" --out "$OUT" >/dev/null
assert_exit_ok "$?" "T2 --out exit"
assert_file_exists "$OUT" "T2 --out file"

file_mode() {
  python3 - "$1" <<'PY'
import os, stat, sys
print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])
PY
}
MODE=$(file_mode "$OUT")
assert_eq "600" "$MODE" "T2 --out mode 600"

MISSING="$TMP/missing.json"
set +e
"$CONSENSUS" "$MISSING" "$SUM_B" >/dev/null 2>&1
CODE=$?
set -e
assert_eq "2" "$CODE" "T3 missing input exit 2"

BAD="$TMP/bad.json"
echo 'not json' > "$BAD"
set +e
"$CONSENSUS" "$BAD" "$SUM_B" >/dev/null 2>&1
CODE=$?
set -e
assert_eq "2" "$CODE" "T4 invalid JSON exit 2"

MULTI_A="$TMP/multi_a.json"
MULTI_B="$TMP/multi_b.json"
cat > "$MULTI_A" <<'EOF'
{
  "total": 2,
  "counts": {"対応": 2},
  "findings": [
    {
      "id": "f-111111111111",
      "severity": "高",
      "file": "svc.py",
      "line": 10,
      "title": "Missing auth",
      "recommendation": "",
      "decision": "対応"
    },
    {
      "id": "f-222222222222",
      "severity": "中",
      "file": "svc.py",
      "line": 10,
      "title": "Race condition",
      "recommendation": "",
      "decision": "対応"
    }
  ]
}
EOF

cat > "$MULTI_B" <<'EOF'
{
  "total": 2,
  "counts": {"対応": 2},
  "findings": [
    {
      "id": "f-333333333333",
      "severity": "高",
      "file": "svc.py",
      "line": 10,
      "title": "Missing   Auth",
      "recommendation": "",
      "decision": "対応"
    },
    {
      "id": "f-444444444444",
      "severity": "低",
      "file": "svc.py",
      "line": 10,
      "title": "Race condition",
      "recommendation": "",
      "decision": "対応"
    }
  ]
}
EOF

MULTI_OUT=$("$CONSENSUS" "$MULTI_A" "$MULTI_B")
python3 - "$MULTI_OUT" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["totals"] == {"agreed": 2, "only_a": 0, "only_b": 0}, data
titles = sorted(item["title"] for item in data["agreed"])
assert titles == ["Missing auth", "Race condition"], titles
PY
assert_exit_ok "$?" "T5 multiple findings at same file:line match by title"

echo "[test-consensus] done"
