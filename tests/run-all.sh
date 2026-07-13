#!/usr/bin/env bash
# 全テスト直列実行＋集計。
# 失敗があれば exit 1。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$HOME"  # 安全な cwd

TESTS=(
  "test-syntax-check.sh"
  "test-save-reply.sh"
  "test-browser-embed.sh"
  "test-browser-setup.sh"
  "test-browser-drive.sh"
  "test-browser-run.sh"
  "test-connector-run.sh"
  "test-search-fetch.sh"
  "test-mcp-hardening.sh"
  "test-full-gate.sh"
  "test-persistence-redaction.sh"
  "test-summarize.sh"
  "test-summarize-stable-id.sh"
  "test-ledger.sh"
  "test-report-bundle.sh"
  "test-conversation-url.sh"
  "test-doctor.sh"
  "test-tunnel-check.sh"
  "test-run-entry.sh"
  "test-docs-sync.sh"
  "test-start-template.sh"
  "test-run-id.sh"
  "test-reply-matching.sh"
  "test-integration-path-a.sh"
  "test-integration-path-b.sh"
  "test-final-packet-scan.sh"
  "test-secret-scan-extended.sh"
  "test-pathA-filename-exclude.sh"
  "test-prompt-injection.sh"
  "test-denylist.sh"
  "test-danger-mode.sh"
  "test-recover.sh"
  "test-omission-warn.sh"
  "test-packet-file.sh"
  "test-followup.sh"
)

pass=0; fail=0
failed=()
for t in "${TESTS[@]}"; do
  echo
  echo "================================================================"
  echo "RUN: $t"
  echo "================================================================"
  if bash "$SCRIPT_DIR/$t"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed+=("$t")
  fi
done

echo
echo "================================================================"
echo "SUMMARY: pass=$pass fail=$fail / ${#TESTS[@]}"
if [ "$fail" -gt 0 ]; then
  echo "Failed:"
  for f in "${failed[@]}"; do echo "  - $f"; done
  echo "================================================================"
  exit 1
fi
echo "All tests passed."
echo "================================================================"
