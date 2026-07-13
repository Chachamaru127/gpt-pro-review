#!/usr/bin/env bash
# 11.3: GitHub Actions workflow の必須要素を静的検証する。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$HOME" || exit

CI_YML="$ROOT/.github/workflows/ci.yml"

echo "[test-ci-workflow] start"

if [ ! -f "$CI_YML" ]; then
  echo "FAIL: missing $CI_YML" >&2
  exit 1
fi

content="$(cat "$CI_YML")"

grep -q 'macos-latest' "$CI_YML" || {
  echo "FAIL: ci.yml must use macos-latest runner" >&2
  exit 1
}
echo "  ok  macos-latest runner"

grep -q 'tests/run-all\.sh' "$CI_YML" || {
  echo "FAIL: ci.yml must run tests/run-all.sh" >&2
  exit 1
}
echo "  ok  run-all step"

grep -qi 'shellcheck' "$CI_YML" || {
  echo "FAIL: ci.yml must include shellcheck step" >&2
  exit 1
}
echo "  ok  shellcheck step"

grep -q 'py_compile' "$CI_YML" || {
  echo "FAIL: ci.yml must include py_compile step" >&2
  exit 1
}
echo "  ok  py_compile step"

case "$content" in
  *"pull_request"*) echo "  ok  pull_request trigger";;
  *)
    echo "FAIL: ci.yml must trigger on pull_request" >&2
    exit 1
    ;;
esac

case "$content" in
  *"branches: [main]"*|*"branches: [ main ]"*) echo "  ok  push main trigger";;
  *)
    echo "FAIL: ci.yml must trigger push on main" >&2
    exit 1
    ;;
esac

echo "[test-ci-workflow] PASS"
exit 0
