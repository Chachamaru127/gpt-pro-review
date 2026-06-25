#!/usr/bin/env bash
# Report bundle under reports/<project>/<run_id>/.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

SR="$(repo_scripts_dir)/pro-review-save-reply"
FI="$(repo_scripts_dir)/pro-review-finish"
for f in "$SR" "$FI"; do
  [ -x "$f" ] || _fail "executable missing: $f"
done

echo "[test-report-bundle] start"

PROJECT="bundle-$$"
RID="1700000000123-aabbcc"
INBOX="$HOME/.pro-review/inbox/$PROJECT"
REPORTS="$HOME/.pro-review/reports/$PROJECT"
OUTBOX="$HOME/.pro-review/outbox"
mkdir -p "$OUTBOX"
trap 'cleanup_paths "$INBOX" "$REPORTS" "$OUTBOX/$PROJECT-review-$RID.md"' EXIT

cat > "$OUTBOX/$PROJECT-review-$RID.md" <<EOF
request for $PROJECT
[[DONE-$RID]]
EOF

printf '[高] app.py:1 — 問題\n推奨修正: 直す\n[[DONE-%s]]\n' "$RID" | "$SR" "$PROJECT" "$RID" >/dev/null
REPLY="$INBOX/REPLY-$RID.md"
F_OUT=$(PRO_REVIEW_REPORT_MODE=path-a PRO_REVIEW_REPORT_SINCE=1700000000123 "$FI" "$PROJECT" "$REPLY" 2>&1)
assert_exit_ok "$?" "T1 finish exit"
BUNDLE=$(printf '%s\n' "$F_OUT" | awk '/^report_bundle:/{print $2; exit}')
[ -n "$BUNDLE" ] || _fail "T1 report_bundle missing"
assert_file_exists "$BUNDLE/reply.md" "T1 bundle reply"
assert_file_exists "$BUNDLE/request.md" "T1 bundle request"
assert_file_exists "$BUNDLE/summary.json" "T1 bundle summary json"
assert_file_exists "$BUNDLE/summary.md" "T1 bundle summary md"
assert_file_exists "$BUNDLE/easy-report.md" "T1 bundle easy report"
assert_file_exists "$BUNDLE/metadata.json" "T1 bundle metadata"
META=$(cat "$BUNDLE/metadata.json")
assert_contains "$META" "$RID" "T1 metadata run_id"
assert_contains "$META" '"mode": "path-a"' "T1 metadata mode"
assert_contains "$META" '"since": "1700000000123"' "T1 metadata since"
assert_contains "$META" '"request": "request.md"' "T1 metadata request"
assert_contains "$META" '"reply": "reply.md"' "T1 metadata reply"
assert_contains "$META" '"report": "reply.md"' "T1 metadata report"
for file in reply.md request.md summary.json summary.md easy-report.md metadata.json; do
  assert_eq "600" "$(stat -f '%Lp' "$BUNDLE/$file")" "T1 $file mode 600"
done

echo "[test-report-bundle] PASS"
