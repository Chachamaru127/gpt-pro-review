#!/usr/bin/env bash
# 12.2: findings に内容ベースの安定 ID を付与する。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

SUM="$(repo_scripts_dir)/pro-review-summarize"
[ -x "$SUM" ] || _fail "pro-review-summarize not executable: $SUM"

echo "[test-summarize-stable-id] start"

TMP=$(mktemp -d -t prr-stable-id-XXXXXX)
trap 'cleanup_paths "$TMP"' EXIT

REPLY_A="$TMP/reply-order-a.md"
REPLY_B="$TMP/reply-order-b.md"
DUPE_REPLY="$TMP/reply-duplicates.md"

cat > "$REPLY_A" <<'EOF'
[高] app.py:12 — 認証なしで管理操作が実行できる
推奨修正: require_admin() を通す
[低] README.md:3 — 文言が少し古い
推奨修正: 後で更新
[中] billing.py:88 — 境界条件は要確認
推奨修正: 実データで確認する
[[DONE-1700000000123-aabbcc]]
EOF

cat > "$REPLY_B" <<'EOF'
[中] billing.py:88 — 境界条件は要確認
推奨修正: 実データで確認する
[低] README.md:3 — 文言が少し古い
推奨修正: 後で更新
[高] app.py:12 — 認証なしで管理操作が実行できる
推奨修正: require_admin() を通す
[[DONE-1700000000123-aabbcc]]
EOF

cat > "$DUPE_REPLY" <<'EOF'
[高] app.py:12 — duplicate finding
推奨修正: fix once
[高] app.py:12 — duplicate finding
推奨修正: fix once
[[DONE-1700000000123-aabbcc]]
EOF

OUT_A=$("$SUM" "$REPLY_A")
assert_exit_ok "$?" "T1 summarize exit (order A)"

OUT_B=$("$SUM" "$REPLY_B")
assert_exit_ok "$?" "T2 summarize exit (order B)"

python3 - "$OUT_A" "$OUT_B" <<'PY'
import json, re, sys

out_a, out_b = sys.argv[1], sys.argv[2]
id_re = re.compile(r"^f-[0-9a-f]{12}(-\d+)?$")

def check_ids(label, payload):
    data = json.loads(payload)
    findings = data["findings"]
    ids = []
    for i, f in enumerate(findings):
        if "id" not in f:
            raise SystemExit(f"{label}: finding[{i}] missing id field")
        fid = f["id"]
        if not id_re.match(fid):
            raise SystemExit(f"{label}: finding[{i}] id invalid: {fid!r}")
        ids.append(fid)
    return ids

ids_a = check_ids("order A", out_a)
ids_b = check_ids("order B", out_b)

if len(ids_a) != 3 or len(ids_b) != 3:
    raise SystemExit(f"expected 3 findings, got A={len(ids_a)} B={len(ids_b)}")

if set(ids_a) != set(ids_b):
    raise SystemExit(
        f"ID sets differ across order permutations:\n"
        f"  A: {sorted(ids_a)}\n"
        f"  B: {sorted(ids_b)}"
    )
print("ok T1-T2 all findings have stable ids across reorder")
PY
assert_exit_ok "$?" "T1-T2 stable id across reorder"

DUPE_OUT=$("$SUM" "$DUPE_REPLY")
assert_exit_ok "$?" "T3 summarize exit (duplicates)"

python3 - "$DUPE_OUT" <<'PY'
import json, re, sys

data = json.loads(sys.argv[1])
findings = data["findings"]
if len(findings) != 2:
    raise SystemExit(f"expected 2 duplicate findings, got {len(findings)}")

base_re = re.compile(r"^f-[0-9a-f]{12}$")
id0, id1 = findings[0]["id"], findings[1]["id"]

if not base_re.match(id0):
    raise SystemExit(f"first duplicate id invalid: {id0!r}")
if id1 != f"{id0}-2":
    raise SystemExit(f"second duplicate id expected {id0}-2, got {id1!r}")
print("ok T3 duplicate findings get -2 suffix on second occurrence")
PY
assert_exit_ok "$?" "T3 duplicate id suffix"

echo "[test-summarize-stable-id] PASS"
