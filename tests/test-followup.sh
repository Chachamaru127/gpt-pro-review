#!/usr/bin/env bash
# 12.4: --followup multi-round re-review packet + metadata + verdict extraction.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

export PRO_REVIEW_FORCE_SCAN=1

RUN="$(repo_scripts_dir)/pro-review-run"
SUM="$(repo_scripts_dir)/pro-review-summarize"
FI="$(repo_scripts_dir)/pro-review-finish"
SR="$(repo_scripts_dir)/pro-review-save-reply"
for f in "$RUN" "$SUM" "$FI" "$SR"; do
  [ -x "$f" ] || _fail "executable missing: $f"
done

echo "[test-followup] start"

TMP=$(mktemp -d -t prr-followup-XXXXXX)
trap 'cleanup_paths "$TMP" "$REPO"' EXIT

REPO=$(mkrepo)
PROJECT="followup-$$"
PREV_RUN_ID="1700000000123-prevrun"
PREV_BUNDLE="$HOME/.pro-review/reports/$PROJECT/$PREV_RUN_ID"
PREV_REPLY="$TMP/prev-reply.md"
mkdir -p "$PREV_BUNDLE"

cat > "$PREV_REPLY" <<'EOF'
[高] app.py:12 — 認証なしで管理操作が実行できる
推奨修正: require_admin() を通す
[低] README.md:3 — 文言が少し古い
推奨修正: 後で更新
[[DONE-1700000000123-prevrun]]
EOF
"$SUM" "$PREV_REPLY" --json-out "$PREV_BUNDLE/summary.json" >/dev/null
assert_file_exists "$PREV_BUNDLE/summary.json" "T0 prev summary.json"

python3 - "$PREV_BUNDLE/summary.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
if len(data.get("findings", [])) != 2:
    raise SystemExit(f"expected 2 findings, got {len(data.get('findings', []))}")
for f in data["findings"]:
    if not f.get("id", "").startswith("f-"):
        raise SystemExit(f"missing stable id: {f!r}")
print("ok T0 stable ids present")
PY
assert_exit_ok "$?" "T0 summary has stable ids"

IDS=$("$SUM" "$PREV_REPLY" | python3 -c "import json,sys; print(' '.join(f['id'] for f in json.load(sys.stdin)['findings']))")
ID_HIGH=$(printf '%s' "$IDS" | awk '{print $1}')
ID_LOW=$(printf '%s' "$IDS" | awk '{print $2}')

(cd "$REPO" && printf '\n# followup fix\n' >> calc.py)

FIXTURE="$TMP/followup.html"
cat > "$FIXTURE" <<'EOF'
<div data-message-author-role="assistant">
  <p>followup verdicts</p>
  <p>[[DONE-__RUN_ID__]]</p>
</div>
EOF

OUT=$("$RUN" --pro --repo "$REPO" --project "$PROJECT" --followup "$PREV_RUN_ID" --fixture-html "$FIXTURE")
assert_exit_ok "$?" "T1 followup run exit 0"
assert_contains "$OUT" "report_bundle:" "T1 report bundle saved"

REQ=$(printf '%s\n' "$OUT" | awk '/^request_file:/{print $2; exit}')
[ -n "$REQ" ] || _fail "T1 request_file missing"
CONTENT=$(cat "$REQ")
assert_contains "$CONTENT" "Follow-up review" "T1 followup header"
assert_contains "$CONTENT" "resolved" "T1 verdict instruction"
assert_contains "$CONTENT" "still-open" "T1 still-open instruction"
assert_contains "$CONTENT" "| id | severity | file:line | title | decision |" "T1 findings table header"
assert_contains "$CONTENT" "$ID_HIGH" "T1 prev finding id in table"
assert_contains "$CONTENT" "app.py:12" "T1 prev finding location in table"
assert_contains "$CONTENT" "認証なしで管理操作が実行できる" "T1 prev finding title in table"
assert_contains "$CONTENT" '```diff' "T1 diff block"
assert_contains "$CONTENT" "followup fix" "T1 repo diff included"
assert_contains "$CONTENT" "[[DONE-" "T1 DONE marker injected"

BUNDLE=$(printf '%s\n' "$OUT" | awk '/^report_bundle:/{print $2; exit}')
assert_file_exists "$BUNDLE/metadata.json" "T1 bundle metadata"
META=$(cat "$BUNDLE/metadata.json")
assert_contains "$META" "\"previous_run_id\": \"$PREV_RUN_ID\"" "T1 metadata previous_run_id"

NEW_RUN_ID=$(printf '%s\n' "$OUT" | awk '/^run_id:/{print $2; exit}')
VERDICT_REPLY="$TMP/verdict-reply.md"
cat > "$VERDICT_REPLY" <<EOF
Follow-up verdicts:
- $ID_LOW: resolved — README updated
- $ID_HIGH: still-open — admin guard still missing
- f-000000000001: new — unrelated new finding
[[DONE-$NEW_RUN_ID]]
EOF
VERDICT_OUT=$("$SUM" "$VERDICT_REPLY")
assert_contains "$VERDICT_OUT" '"followup_verdicts"' "T2 followup_verdicts present"
python3 - "$VERDICT_OUT" "$ID_HIGH" "$ID_LOW" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
id_high, id_low = sys.argv[2], sys.argv[3]
verdicts = data.get("followup_verdicts") or {}
if verdicts.get(id_low) != "resolved":
    raise SystemExit(f"expected {id_low}=resolved, got {verdicts.get(id_low)!r}")
if verdicts.get(id_high) != "still-open":
    raise SystemExit(f"expected {id_high}=still-open, got {verdicts.get(id_high)!r}")
if verdicts.get("f-000000000001") != "new":
    raise SystemExit(f"expected new verdict, got {verdicts.get('f-000000000001')!r}")
print("ok T2 verdict ids mapped")
PY
assert_exit_ok "$?" "T2 verdict extraction by id"

REORDER_REPLY="$TMP/reorder-reply.md"
cat > "$REORDER_REPLY" <<EOF
- $ID_HIGH: still-open — still broken
- $ID_LOW: resolved — fixed now
[[DONE-$NEW_RUN_ID]]
EOF
REORDER_OUT=$("$SUM" "$REORDER_REPLY")
python3 - "$REORDER_OUT" "$ID_HIGH" "$ID_LOW" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
id_high, id_low = sys.argv[2], sys.argv[3]
verdicts = data["followup_verdicts"]
if verdicts[id_high] != "still-open" or verdicts[id_low] != "resolved":
    raise SystemExit(f"reorder mapping failed: {verdicts!r}")
print("ok T3 reorder still maps by id")
PY
assert_exit_ok "$?" "T3 reorder verdict mapping"

OUTBOX="$HOME/.pro-review/outbox"
mkdir -p "$OUTBOX"
FINISH_RID="1700000000999-finishfu"
cat > "$OUTBOX/$PROJECT-review-$FINISH_RID.md" <<EOF
followup finish test
[[DONE-$FINISH_RID]]
EOF
printf '[高] app.py:1 — x\n[[DONE-%s]]\n' "$FINISH_RID" | "$SR" "$PROJECT" "$FINISH_RID" >/dev/null
REPLY="$HOME/.pro-review/inbox/$PROJECT/REPLY-$FINISH_RID.md"
F_OUT=$(PRO_REVIEW_REPORT_MODE=path-a PRO_REVIEW_REPORT_SINCE=1700000000999 \
  PRO_REVIEW_PREVIOUS_RUN_ID="$PREV_RUN_ID" "$FI" "$PROJECT" "$REPLY" 2>&1)
assert_exit_ok "$?" "T4 finish exit"
FBUNDLE=$(printf '%s\n' "$F_OUT" | awk '/^report_bundle:/{print $2; exit}')
assert_contains "$(cat "$FBUNDLE/metadata.json")" "\"previous_run_id\": \"$PREV_RUN_ID\"" "T4 finish metadata previous_run_id"

set +e
ERR=$("$RUN" --pro --repo "$REPO" --project "$PROJECT" --followup "missing-run-id" --fixture-html "$FIXTURE" 2>&1 >/dev/null)
RC=$?
set -e
assert_exit_nonzero "$RC" "T5 missing prev summary rejected"
assert_contains "$ERR" "followup summary not found" "T5 missing summary error"

cleanup_paths "$HOME/.pro-review/inbox/$PROJECT" "$HOME/.pro-review/reports/$PROJECT" \
  "$HOME/.pro-review/workspace/$PROJECT" "$OUTBOX/$PROJECT-review-$FINISH_RID.md"

echo "[test-followup] PASS"
