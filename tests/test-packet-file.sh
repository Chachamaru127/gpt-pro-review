#!/usr/bin/env bash
# --packet-file: curated Markdown packet の直接投入。
# - curated 本文が REQ になり DONE marker が注入される
# - secret 混入時は scan で停止
# - 未指定時は従来経路（embed）が維持される

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

export PRO_REVIEW_FORCE_SCAN=1

BUILD="$(repo_scripts_dir)/build-review-packet"
EMBED="$(local_browser_embed_cmd)"
RUN="$(repo_scripts_dir)/pro-review-run"
[ -x "$BUILD" ] || _fail "build-review-packet not executable: $BUILD"
[ -x "$EMBED" ] || _fail "pro-review-browser-embed not executable: $EMBED"
[ -x "$RUN" ] || _fail "pro-review-run not executable: $RUN"

echo "[test-packet-file] start"

TMP=$(mktemp -d -t prr-packet-file-XXXXXX)
trap 'cleanup_paths "$TMP" "$REPO"' EXIT

REPO=$(mkrepo)
CURATED="$TMP/curated.md"
cat > "$CURATED" <<'EOF'
# Curated review packet

Please review this hand-picked scope only.

## Scope
- auth middleware
- session store
EOF

# ---- T1: curated packet → REQ + DONE marker ----
OUT=$("$BUILD" --repo "$REPO" --packet-file "$CURATED" --for-browser --run-id "pkt-t1-run" \
  --out "$TMP/out-t1.md" --no-clip 2>/dev/null)
assert_exit_ok "$?" "T1 build exit 0"
CONTENT=$(cat "$TMP/out-t1.md")
assert_contains "$CONTENT" "Curated review packet" "T1 curated body preserved"
assert_contains "$CONTENT" "auth middleware" "T1 curated scope preserved"
assert_contains "$CONTENT" "[[DONE-pkt-t1-run]]" "T1 DONE marker injected"
assert_not_contains "$CONTENT" "# コードレビュー依頼" "T1 no auto-rebuild header"

# ---- T2: browser-embed 貫通 ----
PROJECT="pkt-t2-$$"
OUT=$("$EMBED" "$REPO" "$PROJECT" --packet-file "$CURATED" --no-clip)
assert_exit_ok "$?" "T2 embed exit 0"
REQ=$(awk '/^request_file:/{print $2; exit}' <<<"$OUT")
RUN_ID=$(awk '/^run_id:/{print $2; exit}' <<<"$OUT")
CONTENT=$(cat "$REQ")
assert_contains "$CONTENT" "Curated review packet" "T2 embed uses curated packet"
assert_contains "$CONTENT" "[[DONE-$RUN_ID]]" "T2 embed DONE marker"
assert_not_contains "$CONTENT" 'def add' "T2 embed skips repo file embed"
cleanup_paths "$HOME/.pro-review/inbox/$PROJECT"

# ---- T3: secret in curated packet → exit 1 ----
SECRET_PACKET="$TMP/secret.md"
echo "aws_key=AKIA1234567890ABCDEF" > "$SECRET_PACKET"
set +e
"$BUILD" --repo "$REPO" --packet-file "$SECRET_PACKET" --out "$TMP/out-t3.md" --no-clip >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T3 secret in curated packet blocked"

# ---- T4: missing / empty packet-file ----
set +e
"$BUILD" --repo "$REPO" --packet-file "$TMP/missing.md" --out "$TMP/out-t4.md" --no-clip >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T4 missing packet-file rejected"

echo "" > "$TMP/empty.md"
set +e
"$BUILD" --repo "$REPO" --packet-file "$TMP/empty.md" --out "$TMP/out-t4b.md" --no-clip >/dev/null 2>&1
RC=$?
set -e
assert_exit_nonzero "$RC" "T4b empty packet-file rejected"

# ---- T5: pro-review-run --pro 貫通 ----
FIXTURE="$TMP/pro.html"
cat > "$FIXTURE" <<'EOF'
<div data-message-author-role="assistant">
  <p>curated OK</p>
  <p>[[DONE-__RUN_ID__]]</p>
</div>
EOF
PROJECT="pkt-t5-$$"
OUT=$("$RUN" --pro --repo "$REPO" --project "$PROJECT" --packet-file "$CURATED" --fixture-html "$FIXTURE")
assert_exit_ok "$?" "T5 run --pro exit 0"
REQ=$(awk '/^request_file:/{print $2; exit}' <<<"$OUT")
CONTENT=$(cat "$REQ")
assert_contains "$CONTENT" "Curated review packet" "T5 run --pro uses curated packet"
assert_contains "$CONTENT" "[[DONE-" "T5 run --pro DONE marker"
cleanup_paths "$HOME/.pro-review/inbox/$PROJECT" "$HOME/.pro-review/reports/$PROJECT" "$HOME/.pro-review/workspace/$PROJECT"

# ---- T6: 未指定時は従来 embed 経路 ----
(cd "$REPO" && echo "LEGACY_TOKEN" >> calc.py)
PROJECT="pkt-t6-$$"
OUT=$("$EMBED" "$REPO" "$PROJECT" --question "legacy path" --no-clip)
assert_exit_ok "$?" "T6 legacy embed exit 0"
REQ=$(awk '/^request_file:/{print $2; exit}' <<<"$OUT")
CONTENT=$(cat "$REQ")
assert_contains "$CONTENT" "LEGACY_TOKEN" "T6 legacy path embeds repo changes"
assert_contains "$CONTENT" "# コードレビュー依頼" "T6 legacy path rebuilds packet"
cleanup_paths "$HOME/.pro-review/inbox/$PROJECT"

echo "[test-packet-file] PASS"
