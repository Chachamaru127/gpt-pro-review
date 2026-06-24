#!/usr/bin/env bash
# 6.5: repo-local shell/python 構文チェック baseline（formatter なし）。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$HOME"  # 安全な cwd（run-all.sh と同様）

failures=0
checked=0
skipped=0

_rel() {
  local p="$1"
  case "$p" in
    "$REPO_ROOT"/*) echo "${p#$REPO_ROOT/}";;
    *) echo "$p";;
  esac
}

# Repo-local __pycache__ outside ignored/runtime dirs (compile() must not create these).
_pycache_snapshot() {
  find "$REPO_ROOT" \
    \( \
      -path "$REPO_ROOT/.git" -o -path "$REPO_ROOT/.git/*" -o \
      -path "$REPO_ROOT/.venv" -o -path "$REPO_ROOT/.venv/*" -o \
      -path "$REPO_ROOT/venv" -o -path "$REPO_ROOT/venv/*" -o \
      -path "$REPO_ROOT/scripts/.venv" -o -path "$REPO_ROOT/scripts/.venv/*" -o \
      -path "$REPO_ROOT/node_modules" -o -path "$REPO_ROOT/node_modules/*" -o \
      -path "$REPO_ROOT/.harness-mem" -o -path "$REPO_ROOT/.harness-mem/*" -o \
      -path "$REPO_ROOT/.pro-review" -o -path "$REPO_ROOT/.pro-review/*" \
    \) -prune -o \
    -name '__pycache__' -type d -print 2>/dev/null | sort -u
}

_check_bash() {
  local f="$1"
  if bash -n "$f" 2>&1; then
    echo "  ok  bash: $(_rel "$f")"
  else
    echo "FAIL: bash syntax: $(_rel "$f")" >&2
    failures=$((failures + 1))
  fi
  checked=$((checked + 1))
}

_check_python() {
  local f="$1"
  # compile() only — no py_compile / __pycache__ (read-only CI safe).
  if python3 -c "import sys; compile(open(sys.argv[1], encoding='utf-8').read(), sys.argv[1], 'exec')" "$f" 2>&1; then
    echo "  ok  python: $(_rel "$f")"
  else
    echo "FAIL: python syntax: $(_rel "$f")" >&2
    failures=$((failures + 1))
  fi
  checked=$((checked + 1))
}

_classify_and_check() {
  local f="$1"
  local force="${2:-}"

  case "$force" in
    bash) _check_bash "$f"; return;;
    python) _check_python "$f"; return;;
  esac

  case "${f##*.}" in
    sh) _check_bash "$f"; return;;
    py) _check_python "$f"; return;;
  esac

  local first_line=""
  IFS= read -r first_line < "$f" || {
    echo "  skip unreadable: $(_rel "$f")"
    skipped=$((skipped + 1))
    return
  }

  case "$first_line" in
    \#!/usr/bin/env\ python*|\#!/usr/bin/python*|\#!/bin/python*)
      _check_python "$f";;
    \#!/usr/bin/env\ bash|\#!/bin/bash|\#!/usr/bin/env\ sh|\#!/bin/sh)
      _check_bash "$f";;
    *)
      echo "  skip unknown shebang: $(_rel "$f")"
      skipped=$((skipped + 1));;
  esac
}

echo "[test-syntax-check] start"

before_file="$(mktemp)"
after_file="$(mktemp)"
_reg_root="$REPO_ROOT/scripts/.venv/__syntax_check_regression__"
cleanup() {
  rm -rf "$_reg_root" "$before_file" "$after_file"
}
trap cleanup EXIT

_pycache_snapshot > "$before_file"

# Regression: pre-existing ignored/runtime __pycache__ must not fail the guard.
mkdir -p "$_reg_root/__pycache__"
echo '# regression dummy' > "$_reg_root/__pycache__/dummy.pyc"
echo "  ok  regression: tolerated ignored __pycache__ under scripts/.venv"

for f in "$REPO_ROOT"/scripts/*; do
  [ -f "$f" ] || continue
  [ -x "$f" ] || continue
  _classify_and_check "$f"
done

for f in "$REPO_ROOT"/tests/*.sh; do
  [ -f "$f" ] || continue
  _classify_and_check "$f" bash
done

_pycache_snapshot > "$after_file"
new_pycache="$(comm -13 "$before_file" "$after_file")"
if [ -n "$new_pycache" ]; then
  echo "FAIL: repo-local __pycache__ created during syntax check (outside ignored/runtime dirs):" >&2
  echo "$new_pycache" >&2
  failures=$((failures + 1))
fi

echo "[test-syntax-check] checked=$checked skipped=$skipped failures=$failures"
if [ "$failures" -gt 0 ]; then
  echo "FAIL: syntax baseline ($failures file(s))" >&2
  exit 1
fi
echo "PASS: syntax baseline ($checked file(s))"
exit 0
