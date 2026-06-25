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
REQ=$(printf '%s\n' "$OUT" | awk '/^request_file:/{print $2; exit}')
assert_contains "$(cat "$REQ")" 'web_search: `off`' "T1 --pro web search forwarded"
assert_contains "$(cat "$REQ")" 'deep_research: `on`' "T1 --pro deep research forwarded"

PROJ2="entry-thinking-$$"
OUT2=$("$RUN" --thinking --repo "$REPO" --project "$PROJ2" --question "find bugs")
assert_exit_ok "$?" "T2 --thinking exit"
assert_contains "$OUT2" "save_report" "T2 thinking prompt save_report"
assert_contains "$OUT2" "Tunnel connector" "T2 thinking prompt connector gate"
assert_contains "$OUT2" "STOP_REASON=connector_unavailable" "T2 thinking prompt connector stop"
assert_contains "$OUT2" "next_tunnel:" "T2 next tunnel"
assert_contains "$OUT2" "next_check:" "T2 next check"
assert_contains "$OUT2" "next_watch:" "T2 next watch"

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
  "$HOME/.pro-review/inbox/$PROJ2" "$HOME/.pro-review/workspace/$PROJ2" \
  "$HOME/.pro-review/inbox/entry-thinking-policy-$$" "$HOME/.pro-review/workspace/entry-thinking-policy-$$"

echo "[test-run-entry] PASS"
