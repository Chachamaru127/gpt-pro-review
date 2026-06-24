#!/usr/bin/env bash
# 6.4: repo-local .pro-review-denylist の final packet scan テスト。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

BUILD="$SCRIPT_DIR/../scripts/build-review-packet"
[ -x "$BUILD" ] || _fail "build-review-packet not executable at $BUILD"

# テスト専用の禁止トークン（skill 本体に含まれてはいけない）
FORBIDDEN_A="FORBIDDEN_DENYLIST_CODENAME_XYZ456"
FORBIDDEN_B="FORBIDDEN_DENYLIST_CUSTOMER_ABC789"
# fixture denylist / packet 内容専用（skill 本体には出さない）
DENY_TOKEN_BODY="DENYLIST_TEST_TOKEN_BODY_42"
DENY_TOKEN_QUESTION="DENYLIST_TEST_TOKEN_QUESTION_99"
DENY_TOKEN_COMMENT="DENYLIST_TEST_TOKEN_COMMENT_77"
DENY_TOKEN_LEAK_TRACKED="DENYLIST_LEAK_TRACKED_SECRET_88"
DENY_TOKEN_LEAK_UNTRACKED="DENYLIST_LEAK_UNTRACKED_SECRET_99"
DENY_TOKEN_HEAD_BYPASS="DENYLIST_HEAD_BYPASS_SECRET_01"
DENY_TOKEN_BASE_BYPASS="DENYLIST_BASE_BYPASS_SECRET_02"
DENY_TOKEN_RENAME="DENYLIST_RENAME_LEAK_SECRET_03"

echo "[test-denylist] start"

OUT="/tmp/prr-denylist-$$.md"
ERR="/tmp/prr-denylist-err-$$.txt"

write_denylist() {
  local repo="$1"
  shift
  printf '%s\n' "$@" > "$repo/.pro-review-denylist"
}

# ---- T1: denylist hit in embedded file body → exit 1, no packet ----
REPO=$(mkrepo)
write_denylist "$REPO" "$DENY_TOKEN_BODY"
(cd "$REPO" && printf '%s\n' "marker=$DENY_TOKEN_BODY" > leak.txt)
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>"$ERR"
RC=$?
set -e
assert_exit_nonzero "$RC" "T1 embedded body denylist hit blocks"
grep -q "repo denylist blocked" "$ERR" || _fail "T1 stderr identifies repo denylist block"
grep -q "line 1" "$ERR" || _fail "T1 stderr mentions pattern line number"
assert_file_not_exists "$OUT" "T1 no packet written on denylist hit"
cleanup_paths "$REPO"
rm -f "$OUT" "$ERR"

# ---- T2: denylist hit via --question → exit 1, no packet ----
REPO=$(mkrepo)
write_denylist "$REPO" "$DENY_TOKEN_QUESTION"
set +e
"$BUILD" --repo "$REPO" --question "Please review $DENY_TOKEN_QUESTION carefully" \
  --out "$OUT" --no-clip 2>"$ERR"
RC=$?
set -e
assert_exit_nonzero "$RC" "T2 question denylist hit blocks"
grep -q "repo denylist blocked" "$ERR" || _fail "T2 stderr identifies repo denylist block"
assert_file_not_exists "$OUT" "T2 no packet written on question denylist hit"
cleanup_paths "$REPO"
rm -f "$OUT" "$ERR"

# ---- T3: no denylist → clean packet succeeds ----
REPO=$(mkrepo)
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/dev/null
RC=$?
set -e
assert_exit_ok "$RC" "T3 no denylist clean repo exit 0"
assert_file_exists "$OUT" "T3 packet written without denylist"
cleanup_paths "$REPO" "$OUT"

# ---- T4: invalid regex → exit 1, no packet ----
REPO=$(mkrepo)
write_denylist "$REPO" "[unclosed"
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>"$ERR"
RC=$?
set -e
assert_exit_nonzero "$RC" "T4 invalid regex blocks"
grep -q ".pro-review-denylist" "$ERR" || _fail "T4 stderr mentions denylist file"
grep -q "line 1" "$ERR" || _fail "T4 stderr mentions line number"
assert_file_not_exists "$OUT" "T4 no packet written on invalid regex"
cleanup_paths "$REPO"
rm -f "$OUT" "$ERR"

# ---- T5: comments and blank lines ignored → exit 0 ----
REPO=$(mkrepo)
write_denylist "$REPO" \
  "# comment line with $DENY_TOKEN_COMMENT" \
  "" \
  "   # indented comment"
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/dev/null
RC=$?
set -e
assert_exit_ok "$RC" "T5 comments/blank lines ignored exit 0"
assert_file_exists "$OUT" "T5 packet written when denylist has only comments/blank lines"
cleanup_paths "$REPO" "$OUT"

# ---- T7: tracked/modified denylist with sensitive literal in comment must not leak ----
REPO=$(mkrepo)
(
  cd "$REPO"
  printf '%s\n' "# initial" > .pro-review-denylist
  git add .pro-review-denylist && git commit -qm "track denylist"
  printf '%s\n' "# $DENY_TOKEN_LEAK_TRACKED" "   " > .pro-review-denylist
)
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/dev/null
RC=$?
set -e
assert_exit_ok "$RC" "T7 tracked modified comment-only denylist exit 0"
assert_file_exists "$OUT" "T7 packet written"
CONTENT=$(cat "$OUT")
assert_not_contains "$CONTENT" "$DENY_TOKEN_LEAK_TRACKED" "T7 sensitive literal not in packet"
assert_contains "$CONTENT" ".pro-review-denylist" "T7 denylist listed in omission manifest"
assert_contains "$CONTENT" "denylist source omitted from packet" "T7 omission reason present"
cleanup_paths "$REPO" "$OUT"

# ---- T8: untracked denylist with comment-only sensitive literal must not leak ----
REPO=$(mkrepo)
write_denylist "$REPO" "# $DENY_TOKEN_LEAK_UNTRACKED"
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/dev/null
RC=$?
set -e
assert_exit_ok "$RC" "T8 untracked comment-only denylist exit 0"
assert_file_exists "$OUT" "T8 packet written"
CONTENT=$(cat "$OUT")
assert_not_contains "$CONTENT" "$DENY_TOKEN_LEAK_UNTRACKED" "T8 sensitive literal not in packet"
assert_contains "$CONTENT" ".pro-review-denylist" "T8 denylist listed in omission manifest"
assert_contains "$CONTENT" "denylist source omitted from packet" "T8 omission reason present"
cleanup_paths "$REPO" "$OUT"

# ---- T9: HEAD denylist bypass — weaken/delete working-tree denylist, token elsewhere → exit 1 ----
REPO=$(mkrepo)
(
  cd "$REPO"
  printf '%s\n' "$DENY_TOKEN_HEAD_BYPASS" > .pro-review-denylist
  git add .pro-review-denylist && git commit -qm "track denylist with protected token"
  printf '%s\n' "# comment only" > .pro-review-denylist
  printf '%s\n' "leak=$DENY_TOKEN_HEAD_BYPASS" > leak.txt
)
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>"$ERR"
RC=$?
set -e
assert_exit_nonzero "$RC" "T9 HEAD denylist bypass blocks"
grep -q "repo denylist blocked" "$ERR" || _fail "T9 stderr identifies repo denylist block"
grep -q "HEAD:.pro-review-denylist" "$ERR" || _fail "T9 stderr cites trusted HEAD denylist source"
assert_file_not_exists "$OUT" "T9 no packet written on HEAD denylist bypass"
cleanup_paths "$REPO"
rm -f "$OUT" "$ERR"

# ---- T10: --base denylist bypass — base has token, candidate weakens denylist + leaks → exit 1 ----
REPO=$(mkrepo)
(
  cd "$REPO"
  printf '%s\n' "# empty" > .pro-review-denylist
  git add .pro-review-denylist && git commit -qm "init empty denylist"
  printf '%s\n' "$DENY_TOKEN_BASE_BYPASS" > .pro-review-denylist
  git add .pro-review-denylist && git commit -qm "add protected token to denylist"
  printf '%s\n' "# weakened" > .pro-review-denylist
  printf '%s\n' "leak=$DENY_TOKEN_BASE_BYPASS" > leak.txt
  git add .pro-review-denylist leak.txt && git commit -qm "weaken denylist and add leak"
)
set +e
"$BUILD" --repo "$REPO" --base HEAD~1 --out "$OUT" --no-clip 2>"$ERR"
RC=$?
set -e
assert_exit_nonzero "$RC" "T10 base denylist bypass blocks"
grep -q "repo denylist blocked" "$ERR" || _fail "T10 stderr identifies repo denylist block"
grep -q "HEAD~1:.pro-review-denylist" "$ERR" || _fail "T10 stderr cites trusted base denylist source"
assert_file_not_exists "$OUT" "T10 no packet written on base denylist bypass"
cleanup_paths "$REPO"
rm -f "$OUT" "$ERR"

# ---- T11: rename/copy denylist must not embed body; succeeds when active patterns do not block ----
REPO=$(mkrepo)
(
  cd "$REPO"
  printf '%s\n' "# comment with $DENY_TOKEN_RENAME" > .pro-review-denylist
  git add .pro-review-denylist && git commit -qm "track denylist"
  git mv .pro-review-denylist denylist-backup.txt
)
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/dev/null
RC=$?
set -e
assert_exit_ok "$RC" "T11 renamed denylist exit 0"
assert_file_exists "$OUT" "T11 packet written after denylist rename"
CONTENT=$(cat "$OUT")
assert_not_contains "$CONTENT" "$DENY_TOKEN_RENAME" "T11 sensitive literal not in packet after rename"
assert_contains "$CONTENT" "denylist-backup.txt" "T11 renamed path listed in omission manifest"
assert_contains "$CONTENT" "denylist source omitted from packet" "T11 rename omission reason present"
cleanup_paths "$REPO" "$OUT"

# ---- T6: skill 本体に project 固有 literal が無い ----
for tok in "$FORBIDDEN_A" "$FORBIDDEN_B" "$DENY_TOKEN_BODY" "$DENY_TOKEN_QUESTION" "$DENY_TOKEN_COMMENT" \
  "$DENY_TOKEN_LEAK_TRACKED" "$DENY_TOKEN_LEAK_UNTRACKED" "$DENY_TOKEN_HEAD_BYPASS" \
  "$DENY_TOKEN_BASE_BYPASS" "$DENY_TOKEN_RENAME"; do
  if grep -qF "$tok" "$BUILD"; then
    _fail "build-review-packet must not contain project/test literal: $tok"
  fi
  _ok "no forbidden literal ($tok)"
done

echo "[test-denylist] PASS"
