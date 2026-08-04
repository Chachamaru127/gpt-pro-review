#!/usr/bin/env bash
# Path B nodriver connector orchestrator fixture e2e.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

RUN="$(repo_scripts_dir)/pro-review-connector-run"
[ -x "$RUN" ] || _fail "pro-review-connector-run not executable: $RUN"

echo "[test-connector-run] start"

TMP=$(mktemp -d -t prr-connector-run-XXXXXX)
trap 'cleanup_paths "$TMP"' EXIT
REPO=$(mkrepo)
PROJECT="connector-run-$$"
FIXTURE="$TMP/connector.html"
cat > "$FIXTURE" <<'EOF'
<main>
  <button id="composer-plus-btn" aria-label="Tools">+</button>
  <div role="menuitemcheckbox" aria-checked="true" aria-label="pro-review Tunnel connector">pro-review Tunnel connector</div>
  <div id="prompt-textarea" contenteditable="true"></div>
  <button data-testid="send-button" aria-label="Send message">Send</button>
</main>
EOF

OUT=$("$RUN" "$REPO" "$PROJECT" --question "find bugs" --fixture-html "$FIXTURE" --timeout 5 --drive-timeout 1)
assert_exit_ok "$?" "T1 connector-run fixture exit"
assert_contains "$OUT" "tunnel_fixture: skipped" "T1 fixture skips live tunnel"
assert_contains "$OUT" "sent: connector" "T1 browser connector send"
assert_contains "$OUT" "REPLY:" "T1 watch reply"
assert_contains "$OUT" "report_bundle:" "T1 report bundle"
REPORT_BUNDLE=$(awk '/^report_bundle:/{print $2; exit}' <<<"$OUT")
assert_file_exists "$REPORT_BUNDLE/reply.md" "T1 bundle reply"
assert_file_exists "$REPORT_BUNDLE/request.md" "T1 bundle request"
assert_contains "$(cat "$REPORT_BUNDLE/request.md")" "save_report" "T1 request asks save_report"

NO_CONN="$TMP/no-connector.html"
cat > "$NO_CONN" <<'EOF'
<main>
  <button id="composer-plus-btn" aria-label="Tools">+</button>
  <div id="prompt-textarea" contenteditable="true"></div>
</main>
EOF
PROJECT2="connector-run-missing-$$"
set +e
OUT2=$("$RUN" "$REPO" "$PROJECT2" --question "find bugs" --fixture-html "$NO_CONN" --timeout 1 --drive-timeout 1 2>/dev/null)
RC=$?
set -e
assert_eq "3" "$RC" "T2 connector missing exit 3"
assert_contains "$OUT2" "STOP_REASON=connector_unavailable" "T2 connector unavailable stop"
RUN_ID2=$(awk '/^run_id:/{print $2; exit}' <<<"$OUT2")
assert_file_exists "$HOME/.pro-review/reports/$PROJECT2/$RUN_ID2/dom-excerpt.html" "T2 connector failure artifact"
ACTIVE=$(cat "$HOME/.pro-review/active-project" 2>/dev/null || true)
assert_eq "" "$ACTIVE" "T2 active-project cleared"

cleanup_paths "$REPO" \
  "$HOME/.pro-review/inbox/$PROJECT" "$HOME/.pro-review/reports/$PROJECT" "$HOME/.pro-review/workspace/$PROJECT" \
  "$HOME/.pro-review/inbox/$PROJECT2" "$HOME/.pro-review/reports/$PROJECT2" "$HOME/.pro-review/workspace/$PROJECT2"

# T3 (14.2): Path B singleton lock。ほぼ同時に2プロセス起動すると、後発は
# 既存 run を殺さず STOP_REASON=another_run_active で拒否される(実プロセス2本)。
TMP_HOME3=$(mktemp -d -t prr-connector-run-lock-XXXXXX)
REPO3=$(mkrepo)
PROJECT3="connector-run-lock-$$"
(
  set +e
  HOME="$TMP_HOME3" "$RUN" "$REPO3" "$PROJECT3" --question "find bugs" --fixture-html "$FIXTURE" --timeout 5 --drive-timeout 1 \
    > "$TMP/lock-run1.out" 2> "$TMP/lock-run1.err"
  echo "$?" > "$TMP/lock-run1.rc"
) &
PID1=$!
set +e
OUT3=$(HOME="$TMP_HOME3" "$RUN" "$REPO3" "$PROJECT3" --question "find bugs" --fixture-html "$FIXTURE" --timeout 5 --drive-timeout 1 2>&1)
RC3=$?
set -e
wait "$PID1"
RC1=$(cat "$TMP/lock-run1.rc")

WINNERS=0
[ "$RC1" = "0" ] && WINNERS=$((WINNERS + 1))
[ "$RC3" = "0" ] && WINNERS=$((WINNERS + 1))
assert_eq "1" "$WINNERS" "T3 exactly one parallel run succeeds (rc1=$RC1 rc3=$RC3)"

REJECTS=0
if [ "$RC1" = "3" ] && grep -q "STOP_REASON=another_run_active" "$TMP/lock-run1.out" "$TMP/lock-run1.err" 2>/dev/null; then
  REJECTS=$((REJECTS + 1))
fi
if [ "$RC3" = "3" ] && grep -q "STOP_REASON=another_run_active" <<<"$OUT3"; then
  REJECTS=$((REJECTS + 1))
fi
assert_eq "1" "$REJECTS" "T3 exactly one parallel run rejected with another_run_active"
cleanup_paths "$TMP_HOME3" "$REPO3"

# T4 (14.2): lock ディレクトリはあるが記録された PID が死んでいれば stale として奪取する。
TMP_HOME4=$(mktemp -d -t prr-connector-run-stale-XXXXXX)
REPO4=$(mkrepo)
PROJECT4="connector-run-stale-$$"
mkdir -p "$TMP_HOME4/.pro-review"
LOCK_DIR4="$TMP_HOME4/.pro-review/.run-lock"
mkdir -p "$LOCK_DIR4"
( : ) &
DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null || true
printf '%s\n' "$DEAD_PID" > "$LOCK_DIR4/pid"

OUT4=$(HOME="$TMP_HOME4" "$RUN" "$REPO4" "$PROJECT4" --question "find bugs" --fixture-html "$FIXTURE" --timeout 5 --drive-timeout 1)
assert_exit_ok "$?" "T4 stale lock (dead pid) is stolen, run succeeds"
assert_contains "$OUT4" "report_bundle:" "T4 stale lock takeover completes run"
[ ! -d "$LOCK_DIR4" ] || _fail "T4 lock dir should be released after run completes"
cleanup_paths "$TMP_HOME4" "$REPO4"

# ---- T5 (14.3): watch timeout 時に inbox の旧 valid reply を再採用しない ----
TMP_HOME5=$(mktemp -d -t prr-home5-XXXXXX)
REPO5=$(mkrepo)
PROJECT5="connector-run-t5-$$"
OUT5A=$(HOME="$TMP_HOME5" "$RUN" "$REPO5" "$PROJECT5" --question "find bugs" --fixture-html "$FIXTURE" --timeout 5 --drive-timeout 1)
assert_exit_ok "$?" "T5 first round succeeds"
OLD_RUN5="1000000000000-aaaaaa"
printf 'old body\n[[DONE-%s]]' "$OLD_RUN5" > "$TMP_HOME5/.pro-review/inbox/$PROJECT5/REPLY-$OLD_RUN5.md"
REPORTS5="$TMP_HOME5/.pro-review/reports/$PROJECT5"
BEFORE5=$(find "$REPORTS5" -type f 2>/dev/null | wc -l | tr -d ' ')
set +e
OUT5B=$(HOME="$TMP_HOME5" PRO_REVIEW_FIXTURE_SKIP_REPLY=1 "$RUN" "$REPO5" "$PROJECT5" --question "find bugs" --fixture-html "$FIXTURE" --timeout 1 --drive-timeout 1 2>&1)
RC5=$?
set -e
assert_eq "3" "$RC5" "T5 timeout round exits 3"
assert_contains "$OUT5B" "STOP_REASON=save_report_timeout" "T5 stop reason on timeout"
AFTER5=$(find "$REPORTS5" -type f 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$BEFORE5" "$AFTER5" "T5 stale reply not re-adopted (no new report files)"
ACTIVE5=$(cat "$TMP_HOME5/.pro-review/active-project" 2>/dev/null || true)
assert_eq "" "$ACTIVE5" "T5 active-project cleared on timeout"
cleanup_paths "$TMP_HOME5" "$REPO5"

echo "[test-connector-run] PASS"
