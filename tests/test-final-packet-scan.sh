#!/usr/bin/env bash
# build-review-packet の all-mode final packet scan + connector/github-branch guard のテスト。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

BUILD="$SCRIPT_DIR/../scripts/build-review-packet"
[ -x "$BUILD" ] || _fail "build-review-packet not executable at $BUILD"

echo "[test-final-packet-scan] start"

OUT="/tmp/prr-final-scan-$$.md"

# ---- T1: diff 内 secret のみ（ファイル本文は clean）→ embed で exit 1 ----
REPO=$(mkrepo)
(
  cd "$REPO"
  echo "aws_key=AKIA1234567890ABCDEF" > config.txt
  git add config.txt && git commit -qm "add config with secret"
  echo "# clean" > config.txt
  git add config.txt && git commit -qm "remove secret from file"
)
set +e
"$BUILD" --repo "$REPO" --base HEAD~1 --out "$OUT" --no-clip 2>/tmp/prr-final-scan-err-$$.txt
RC=$?
set -e
assert_exit_nonzero "$RC" "T1 diff-only secret blocks (exit 1)"
grep -q "AKIA" /tmp/prr-final-scan-err-$$.txt || _fail "T1 stderr mentions pattern"
assert_file_not_exists "$OUT" "T1 no packet written on secret hit"
cleanup_paths "$REPO"
rm -f "$OUT" /tmp/prr-final-scan-err-$$.txt

# ---- T2: clean repo → exit 0 ----
REPO=$(mkrepo)
OUT="/tmp/prr-final-scan-clean-$$.md"
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/dev/null
RC=$?
set -e
assert_exit_ok "$RC" "T2 clean repo exit 0"
assert_file_exists "$OUT" "T2 packet written"
cleanup_paths "$REPO" "$OUT"

# ---- T3: connector mode、flag 無し → exit 2 ----
REPO=$(mkrepo)
set +e
"$BUILD" --repo "$REPO" --mode connector --out "$OUT" --no-clip 2>/tmp/prr-final-scan-err-$$.txt
RC=$?
set -e
assert_eq "2" "$RC" "T3 connector guard exit 2"
grep -q "PRO_REVIEW_ALLOW_UNSCANNED_MODES" /tmp/prr-final-scan-err-$$.txt \
  || _fail "T3 guard reason on stderr"
assert_file_not_exists "$OUT" "T3 no packet on guard"
cleanup_paths "$REPO"
rm -f "$OUT" /tmp/prr-final-scan-err-$$.txt

# ---- T4: connector + flag + final packet secret → exit 1 ----
REPO=$(mkrepo)
(cd "$REPO" && echo "token=AKIA1234567890ABCDEF" >> calc.py)
set +e
PRO_REVIEW_ALLOW_UNSCANNED_MODES=1 "$BUILD" --repo "$REPO" --mode connector --out "$OUT" --no-clip \
  2>/tmp/prr-final-scan-err-$$.txt
RC=$?
set -e
assert_exit_nonzero "$RC" "T4 connector+flag secret in packet exit 1"
assert_file_not_exists "$OUT" "T4 no packet on secret hit"
cleanup_paths "$REPO"
rm -f "$OUT" /tmp/prr-final-scan-err-$$.txt

# ---- T5: github-branch mode、flag 無し → exit 2 ----
REPO=$(mkrepo)
set +e
"$BUILD" --repo "$REPO" --github-branch main --out "$OUT" --no-clip 2>/tmp/prr-final-scan-err-$$.txt
RC=$?
set -e
assert_eq "2" "$RC" "T5 github-branch guard exit 2"
grep -q "PRO_REVIEW_ALLOW_UNSCANNED_MODES" /tmp/prr-final-scan-err-$$.txt \
  || _fail "T5 guard reason on stderr"
assert_file_not_exists "$OUT" "T5 no packet on guard"
cleanup_paths "$REPO"
rm -f "$OUT" /tmp/prr-final-scan-err-$$.txt

# ---- T6: github-branch + --for-browser でも flag 無し → exit 2（bypass 不可） ----
REPO=$(mkrepo)
set +e
"$BUILD" --repo "$REPO" --github-branch main --for-browser --since 123 --out "$OUT" --no-clip \
  2>/tmp/prr-final-scan-err-$$.txt
RC=$?
set -e
assert_eq "2" "$RC" "T6 github-branch+for-browser guard exit 2"
grep -q "PRO_REVIEW_ALLOW_UNSCANNED_MODES" /tmp/prr-final-scan-err-$$.txt \
  || _fail "T6 guard reason on stderr"
assert_file_not_exists "$OUT" "T6 no packet on guard (--for-browser must not bypass)"
cleanup_paths "$REPO"
rm -f "$OUT" /tmp/prr-final-scan-err-$$.txt

# ---- T7: git diff uses -M -C --find-copies-harder for rename/copy detection ----
grep -qE 'git.*diff.*-M.*-C.*--find-copies-harder' "$BUILD" \
  || _fail "build-review-packet must pass -M -C --find-copies-harder to git diff"
_ok "git diff uses -M -C --find-copies-harder"

# ---- T8: .env->config.txt move (rename undetected) with high-entropy secret -> exit 1 ----
# Simulates delete .env + add config.txt without git mv link; final scan catches embedded config.txt.
REPO=$(mkrepo)
(
  cd "$REPO"
  echo 'api_key=abcdefghijklmnopqrstuvwxyz0123456789ABCD' > .env
  git add .env && git commit -qm "track env"
  git rm --cached .env 2>/dev/null || true
  rm -f .env
  echo 'api_key=abcdefghijklmnopqrstuvwxyz0123456789ABCD' > config.txt
)
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/tmp/prr-final-scan-err-$$.txt
RC=$?
set -e
assert_exit_nonzero "$RC" "T8 .env->config.txt secret leak blocks (exit 1)"
grep -q "config.txt" /tmp/prr-final-scan-err-$$.txt || _fail "T8 stderr mentions config.txt"
assert_file_not_exists "$OUT" "T8 no packet written on secret hit"
cleanup_paths "$REPO"
rm -f "$OUT" /tmp/prr-final-scan-err-$$.txt

echo "[test-final-packet-scan] PASS"
