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
README=$(cat "$ROOT/README.md")
USAGE=$(cat "$ROOT/docs/usage.md")
SETUP=$(cat "$ROOT/SETUP-layer2.md")
SPEC=$(cat "$ROOT/docs/spec/00-project-spec.md")

assert_contains "$README" "## ひとことで" "T1 README one-line overview"
assert_contains "$README" "## 導入" "T1 README setup"
assert_contains "$README" "## Path A 使い方" "T1 README Path A usage"
assert_contains "$README" "## Path B 使い方" "T1 README Path B usage"
assert_contains "$README" "Secure MCP Tunnel" "T1 README tunnel concept"
assert_contains "$README" 'nodriver が `pro-review Tunnel connector`' "T1 README Path B nodriver connector"
assert_contains "$README" "Deep research" "T1 README deep research plus menu"
assert_contains "$README" "pro-review-recover" "T1 README recover command"

assert_contains "$SKILL" "pro-review-run --pro" "T2 SKILL Path A command"
assert_contains "$SKILL" "pro-review-run --thinking" "T2 SKILL Path B command"
assert_contains "$SKILL" "--web-search auto|on|off" "T2 SKILL web search policy"
assert_contains "$SKILL" "--deep-research auto|on|off" "T2 SKILL deep research policy"
assert_contains "$SKILL" "/Deepresearch" "T2 SKILL deep research UI selection"
assert_contains "$SKILL" "save_report" "T2 SKILL save_report"
assert_contains "$SKILL" "nodriver が固定ラベル" "T2 SKILL Path B fixed connector selection"
assert_contains "$SKILL" "reports/<project>/<run_id>" "T2 SKILL bundle"
assert_not_contains "$SKILL" "claude-in-chrome" "T2 retired claude-in-chrome removed"
assert_not_contains "$SKILL" "API route は採用" "T2 no API route recommendation"
assert_contains "$SKILL" "pro-review-recover" "T2 SKILL recover command"
assert_contains "$SKILL" "pbpaste" "T2 SKILL copy-button retrieval"

assert_contains "$USAGE" "--web-search" "T3 usage web search option"
assert_contains "$USAGE" "--deep-research" "T3 usage deep research option"
assert_contains "$USAGE" "Nodriver" "T3 usage nodriver deep research selection"
assert_contains "$USAGE" "Path B も nodriver" "T3 usage Path B nodriver connector"
assert_contains "$USAGE" "FALLBACK:" "T3 usage fallback"
assert_contains "$USAGE" "STOP_REASON" "T3 usage stop reason"
assert_contains "$USAGE" "pro-review-recover" "T3 usage recover command"
assert_contains "$SPEC" "pro-review-recover" "T3 spec recover contract"
assert_contains "$SETUP" "pro-review-tunnel-check" "T3 setup tunnel check"
assert_contains "$SETUP" "connector-label" "T3 setup connector label override"
assert_contains "$SETUP" "save_report" "T3 setup save_report"
assert_contains "$SPEC" "Web Search / Deep Research" "T3 spec tool policy"
assert_contains "$SPEC" "/Deepresearch" "T3 spec deep research UI selection"
assert_contains "$SPEC" "Path B も nodriver-first" "T3 spec Path B nodriver-first"

echo "[test-docs-sync] PASS"
