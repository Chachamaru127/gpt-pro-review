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
REPORT_BUNDLE=$(printf '%s\n' "$OUT" | awk '/^report_bundle:/{print $2; exit}')
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
RUN_ID2=$(printf '%s\n' "$OUT2" | awk '/^run_id:/{print $2; exit}')
assert_file_exists "$HOME/.pro-review/reports/$PROJECT2/$RUN_ID2/dom-excerpt.html" "T2 connector failure artifact"
ACTIVE=$(cat "$HOME/.pro-review/active-project" 2>/dev/null || true)
assert_eq "" "$ACTIVE" "T2 active-project cleared"

cleanup_paths "$REPO" \
  "$HOME/.pro-review/inbox/$PROJECT" "$HOME/.pro-review/reports/$PROJECT" "$HOME/.pro-review/workspace/$PROJECT" \
  "$HOME/.pro-review/inbox/$PROJECT2" "$HOME/.pro-review/reports/$PROJECT2" "$HOME/.pro-review/workspace/$PROJECT2"

echo "[test-connector-run] PASS"
