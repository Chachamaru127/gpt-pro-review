#!/usr/bin/env bash
# 6.8/6.8b: Path A orchestrator fixture e2e and fallback.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

RUN="$(repo_scripts_dir)/pro-review-browser-run"
[ -x "$RUN" ] || _fail "pro-review-browser-run not executable: $RUN"

echo "[test-browser-run] start"

TMP=$(mktemp -d -t prr-browser-run-XXXXXX)
trap 'cleanup_paths "$TMP"' EXIT
REPO=$(mkrepo)
(cd "$REPO" && echo "BUG" >> calc.py)
PROJECT="browser-run-$$"
EMPTY="$TMP/empty.html"
FIXTURE="$TMP/success.html"
printf '<main></main>\n' > "$EMPTY"
set +e
FB_OUT=$("$RUN" "$REPO" "$PROJECT" --question "find bugs" --fixture-html "$EMPTY" --timeout 0.1 2>/dev/null)
FB_RC=$?
set -e
assert_eq "3" "$FB_RC" "T1 missing fixture fallback"
assert_contains "$FB_OUT" "FALLBACK" "T1 fallback emitted"
assert_contains "$FB_OUT" "manual_save:" "T1 manual fallback command"

cat > "$FIXTURE" <<EOF
<div data-message-author-role="assistant">
  <p>結論: Path A fixture OK</p>
  <p>[[DONE-__RUN_ID__]]</p>
</div>
EOF

OUT=$("$RUN" "$REPO" "$PROJECT" --question "find bugs" --fixture-html "$FIXTURE" --web-search on --deep-research off)
assert_exit_ok "$?" "T2 browser-run success"
assert_contains "$OUT" "saved:" "T2 save-reply ran"
assert_contains "$OUT" "REPLY:" "T2 watch ran"
assert_contains "$OUT" "report_saved:" "T2 finish ran"
REPORT=$(printf '%s\n' "$OUT" | awk '/^report_saved:/{print $2; exit}')
assert_file_exists "$REPORT" "T2 report exists"
REQ=$(printf '%s\n' "$OUT" | awk '/^request_file:/{print $2; exit}')
assert_contains "$(cat "$REQ")" 'web_search: `on`' "T2 request web search on"
assert_contains "$(cat "$REQ")" 'deep_research: `off`' "T2 request deep research off"

RUN_ID=$(printf '%s\n' "$OUT" | awk '/^run_id:/{print $2; exit}')
assert_contains "$(cat "$REPORT")" "[[DONE-$RUN_ID]]" "T2 report marker"

cleanup_paths "$REPO" "$HOME/.pro-review/inbox/$PROJECT" "$HOME/.pro-review/reports/$PROJECT" "$HOME/.pro-review/workspace/$PROJECT"

echo "[test-browser-run] PASS"
