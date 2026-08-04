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

TMP_HOME=$(mktemp -d -t prr-browser-run-home-XXXXXX)
mkdir -p "$TMP_HOME/.claude/skills"
ln -s "$(cd "$SCRIPT_DIR/.." && pwd)" "$TMP_HOME/.claude/skills/gpt-pro-review"
LIVE_REPO=$(mkrepo)
(cd "$LIVE_REPO" && echo "LIVE" >> calc.py)
set +e
LOGIN_OUT=$(HOME="$TMP_HOME" PRO_REVIEW_OPEN_LOGIN_DRY_RUN=1 "$RUN" "$LIVE_REPO" "$PROJECT-auto-login" --question "find bugs" --timeout 0.1 2>/tmp/prr-browser-run-login-$$.err)
LOGIN_RC=$?
set -e
assert_eq "3" "$LOGIN_RC" "T1b missing live login marker fallback"
assert_contains "$LOGIN_OUT" "FALLBACK:login required" "T1b login fallback emitted"
assert_contains "$LOGIN_OUT" "login_action: open-login attempted" "T1b login browser open attempted"
assert_contains "$LOGIN_OUT" "login_next:" "T1b login next action emitted"
assert_contains "$LOGIN_OUT" "login_rerun:" "T1b rerun command emitted"
assert_contains "$(cat /tmp/prr-browser-run-login-$$.err)" "MANUAL login" "T1b setup guidance emitted"
rm -f /tmp/prr-browser-run-login-$$.err

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
REPORT=$(awk '/^report_saved:/{print $2; exit}' <<<"$OUT")
assert_file_exists "$REPORT" "T2 report exists"
REQ=$(awk '/^request_file:/{print $2; exit}' <<<"$OUT")
assert_contains "$(cat "$REQ")" 'web_search: `on`' "T2 request web search on"
assert_contains "$(cat "$REQ")" 'deep_research: `off`' "T2 request deep research off"

RUN_ID=$(awk '/^run_id:/{print $2; exit}' <<<"$OUT")
assert_contains "$(cat "$REPORT")" "[[DONE-$RUN_ID]]" "T2 report marker"

# T3: 大きな embed(>64KB) で printf|awk パースが SIGPIPE(141) で落ちない回帰。
# ~72KB の無害テキスト(秘密/PII無し)を untracked で置くと packet 本体が pipe バッファを超える。
BIGREPO=$(mkrepo)
# pipe を使わず生成(yes|head は pipefail+set -e で SIGPIPE になる)。~70KB(>64KB pipe buffer, <80KB budget)。
awk 'BEGIN{for(i=0;i<1200;i++) print "alpha beta gamma delta epsilon zeta eta theta iota kappa"}' > "$BIGREPO/big.txt"
BIGPROJ="browser-run-big-$$"
set +e
BIG_OUT=$("$RUN" "$BIGREPO" "$BIGPROJ" --question "find bugs" --fixture-html "$FIXTURE")
BIG_RC=$?
set -e
assert_exit_ok "$BIG_RC" "T3 large embed parses without SIGPIPE (was exit 141)"
assert_contains "$BIG_OUT" "report_saved:" "T3 large embed completes end-to-end"
BIG_RUN_ID=$(awk '/^run_id:/{print $2; exit}' <<<"$BIG_OUT")
assert_contains "$BIG_OUT" "run_id: $BIG_RUN_ID" "T3 run_id parsed from large embed"
cleanup_paths "$BIGREPO" "$HOME/.pro-review/inbox/$BIGPROJ" "$HOME/.pro-review/reports/$BIGPROJ" "$HOME/.pro-review/workspace/$BIGPROJ"

cleanup_paths "$REPO" "$HOME/.pro-review/inbox/$PROJECT" "$HOME/.pro-review/reports/$PROJECT" "$HOME/.pro-review/workspace/$PROJECT"
cleanup_paths "$TMP_HOME" "$LIVE_REPO"

echo "[test-browser-run] PASS"
