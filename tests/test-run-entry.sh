#!/usr/bin/env bash
# 6.16: pro-review-run unified entrypoint.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

RUN="$(repo_scripts_dir)/pro-review-run"
[ -x "$RUN" ] || _fail "pro-review-run not executable: $RUN"

echo "[test-run-entry] start"

TMP=$(mktemp -d -t prr-run-entry-XXXXXX)
trap 'cleanup_paths "$TMP"' EXIT
REPO=$(mkrepo)
(cd "$REPO" && echo "BUG" >> calc.py)

FIXTURE="$TMP/pro.html"
cat > "$FIXTURE" <<'EOF'
<div data-message-author-role="assistant">
  <p>結論: unified pro OK</p>
  <p>[[DONE-__RUN_ID__]]</p>
</div>
EOF
PROJ="entry-pro-$$"
OUT=$("$RUN" --pro --repo "$REPO" --project "$PROJ" --question "find bugs" --fixture-html "$FIXTURE" --web-search off --deep-research on)
assert_exit_ok "$?" "T1 --pro exit"
assert_contains "$OUT" "report_saved:" "T1 --pro report saved"
assert_contains "$OUT" "run_id:" "T1 --pro run id"
REQ=$(awk '/^request_file:/{print $2; exit}' <<<"$OUT")
assert_contains "$(cat "$REQ")" 'web_search: `off`' "T1 --pro web search forwarded"
assert_contains "$(cat "$REQ")" 'deep_research: `on`' "T1 --pro deep research forwarded"

PROJ2="entry-thinking-$$"
CONN_FIXTURE="$TMP/connector.html"
cat > "$CONN_FIXTURE" <<'EOF'
<main>
  <button id="composer-plus-btn" aria-label="Tools">+</button>
  <div role="menuitemcheckbox" aria-checked="true" aria-label="pro-review Tunnel connector">pro-review Tunnel connector</div>
  <div id="prompt-textarea" contenteditable="true"></div>
  <button data-testid="send-button" aria-label="Send message">Send</button>
</main>
EOF
OUT2=$("$RUN" --thinking --repo "$REPO" --project "$PROJ2" --question "find bugs" --fixture-html "$CONN_FIXTURE" --timeout 5 --drive-timeout 1)
assert_exit_ok "$?" "T2 --thinking exit"
assert_contains "$OUT2" "sent: connector" "T2 thinking nodriver connector send"
assert_contains "$OUT2" "REPLY:" "T2 thinking watch reply"
assert_contains "$OUT2" "report_bundle:" "T2 thinking finish bundle"
REQ2=$(awk '/^request_file:/{print $2; exit}' <<<"$OUT2")
assert_contains "$(cat "$REQ2")" "save_report" "T2 thinking request save_report"
assert_contains "$(cat "$REQ2")" "Tunnel connector" "T2 thinking request connector gate"
assert_contains "$(cat "$REQ2")" "STOP_REASON=connector_unavailable" "T2 thinking request connector stop"

set +e
ERR=$("$RUN" --repo "$REPO" 2>&1 >/dev/null)
RC=$?
set -e
assert_exit_nonzero "$RC" "T3 missing mode rejected"
assert_contains "$ERR" "--pro or --thinking" "T3 mode guidance"

set +e
ERR=$("$RUN" --thinking --repo "$REPO" --project "entry-thinking-policy-$$" --web-search on 2>&1 >/dev/null)
RC=$?
set -e
assert_exit_nonzero "$RC" "T4 thinking rejects Path A tool policy"
assert_contains "$ERR" "Path A (--pro) options" "T4 thinking policy guidance"

cleanup_paths "$REPO" "$HOME/.pro-review/inbox/$PROJ" "$HOME/.pro-review/reports/$PROJ" "$HOME/.pro-review/workspace/$PROJ" \
  "$HOME/.pro-review/inbox/$PROJ2" "$HOME/.pro-review/reports/$PROJ2" "$HOME/.pro-review/workspace/$PROJ2" \
  "$HOME/.pro-review/inbox/entry-thinking-policy-$$" "$HOME/.pro-review/workspace/entry-thinking-policy-$$"

echo "[test-run-entry] PASS"
