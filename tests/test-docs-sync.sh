#!/usr/bin/env bash
# 6.14/6.15: docs reflect current UX, not retired flows.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "[test-docs-sync] start"

assert_file_exists "$ROOT/README.md" "T1 README exists"
assert_file_exists "$ROOT/docs/usage.md" "T1 usage exists"
assert_file_exists "$ROOT/docs/manual-checklist.md" "T1 manual checklist exists"

SKILL=$(cat "$ROOT/SKILL.md")
USAGE=$(cat "$ROOT/docs/usage.md")
SETUP=$(cat "$ROOT/SETUP-layer2.md")

assert_contains "$SKILL" "pro-review-run --pro" "T2 SKILL Path A command"
assert_contains "$SKILL" "pro-review-run --thinking" "T2 SKILL Path B command"
assert_contains "$SKILL" "save_report" "T2 SKILL save_report"
assert_contains "$SKILL" "reports/<project>/<run_id>" "T2 SKILL bundle"
assert_not_contains "$SKILL" "claude-in-chrome" "T2 retired claude-in-chrome removed"
assert_not_contains "$SKILL" "API route は採用" "T2 no API route recommendation"

assert_contains "$USAGE" "FALLBACK:" "T3 usage fallback"
assert_contains "$USAGE" "STOP_REASON" "T3 usage stop reason"
assert_contains "$SETUP" "pro-review-tunnel-check" "T3 setup tunnel check"
assert_contains "$SETUP" "save_report" "T3 setup save_report"

echo "[test-docs-sync] PASS"
