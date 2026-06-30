#!/usr/bin/env bash
# Phase 9.1: 予算超過で変更ファイルが省略された時、見落とせない形で warn する。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

# 操作者の danger mode に影響されず scan 既定挙動で検証する
export PRO_REVIEW_FORCE_SCAN=1

BUILD="$SCRIPT_DIR/../scripts/build-review-packet"
[ -x "$BUILD" ] || _fail "build-review-packet not executable: $BUILD"

echo "[test-omission-warn] start"

REPO=$(mkrepo)
# 大きめの変更ファイル(>max-bytes)を untracked で置く
awk 'BEGIN{for(i=0;i<400;i++) print "filler filler filler filler filler line "i}' > "$REPO/big.txt"
OUT="$REPO/packet.md"
ERR="$REPO/err.txt"

# ---- T1: max-bytes 2000 で big.txt が予算超過 → loud warn ----
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip --max-bytes 2000 >/dev/null 2>"$ERR"
RC=$?
set -e
assert_exit_ok "$RC" "T1 packet still written despite omission"
ERRTXT="$(cat "$ERR")"
assert_contains "$ERRTXT" "⚠ OMITTED" "T1 loud omission warning on stderr"
assert_contains "$ERRTXT" "big.txt" "T1 omitted file named"
assert_contains "$ERRTXT" "省略 1" "T1 packet summary shows omitted count"
assert_file_exists "$OUT" "T1 packet file written"

# ---- T2: 十分な予算なら省略0・warn無し ----
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip --max-bytes 200000 >/dev/null 2>"$ERR"
RC=$?
set -e
assert_exit_ok "$RC" "T2 packet written"
ERRTXT="$(cat "$ERR")"
assert_not_contains "$ERRTXT" "⚠ OMITTED" "T2 no omission warning when budget suffices"
assert_contains "$ERRTXT" "省略 0" "T2 summary shows zero omissions"

cleanup_paths "$REPO"

echo "[test-omission-warn] PASS"
