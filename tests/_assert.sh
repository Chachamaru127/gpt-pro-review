# shellcheck shell=bash
# 共通 assertion ヘルパー。各 test ファイルから `source` して使う。
# 失敗時は即 exit 1 + メッセージ。標準出力は test 本体の進捗用に空けておく。

set -uo pipefail  # -e は呼び出し側で。アサート関数が exit 制御するため

_FAIL_PREFIX="FAIL"
_PASS_PREFIX="ok"

_fail() { echo "$_FAIL_PREFIX: $*" >&2; exit 1; }
_ok()   { echo "  $_PASS_PREFIX  $*"; }

assert_eq() {
  # assert_eq EXPECTED ACTUAL [MSG]
  local exp="$1" act="$2" msg="${3:-eq}"
  [ "$exp" = "$act" ] || _fail "$msg: expected '$exp' got '$act'"
  _ok "$msg"
}

assert_contains() {
  # assert_contains HAYSTACK NEEDLE [MSG]
  local hay="$1" needle="$2" msg="${3:-contains}"
  case "$hay" in
    *"$needle"*) _ok "$msg ($needle)";;
    *) _fail "$msg: '$needle' not in: ${hay:0:200}";;
  esac
}

assert_not_contains() {
  local hay="$1" needle="$2" msg="${3:-not_contains}"
  case "$hay" in
    *"$needle"*) _fail "$msg: '$needle' unexpectedly in: ${hay:0:200}";;
    *) _ok "$msg (no '$needle')";;
  esac
}

assert_file_exists() {
  local p="$1" msg="${2:-file_exists}"
  [ -f "$p" ] || _fail "$msg: file not found: $p"
  _ok "$msg ($p)"
}

assert_file_not_exists() {
  local p="$1" msg="${2:-file_not_exists}"
  [ ! -e "$p" ] || _fail "$msg: file exists when it should not: $p"
  _ok "$msg ($p)"
}

assert_exit_ok() {
  # assert_exit_ok CODE [MSG]
  local code="$1" msg="${2:-exit_ok}"
  [ "$code" = "0" ] || _fail "$msg: expected exit 0, got $code"
  _ok "$msg"
}

assert_exit_nonzero() {
  local code="$1" msg="${2:-exit_nonzero}"
  [ "$code" != "0" ] || _fail "$msg: expected non-zero exit, got 0"
  _ok "$msg (exit=$code)"
}

mkrepo() {
  # mkrepo [INITIAL_FILES...] → echoes path to a tmp git repo
  local d
  d=$(mktemp -d -t prr-test-XXXXXX)
  (
    cd "$d"
    git init -q
    git config user.email "test@local"
    git config user.name  "Test"
    echo "# selftest" > README.md
    printf 'def add(a, b):\n    return a + b\n' > calc.py
    git add . && git commit -qm "init"
  )
  echo "$d"
}

cleanup_paths() {
  # cleanup_paths PATH [PATH...] — rm -rf the given paths if under /var/folders or /tmp or HOME/.pro-review
  for p in "$@"; do
    case "$p" in
      /var/folders/*|/tmp/*|/private/var/folders/*|/private/tmp/*) rm -rf "$p" 2>/dev/null || true;;
      "$HOME/.pro-review/"*) rm -rf "$p" 2>/dev/null || true;;
      *) echo "  skip cleanup (not under safe prefix): $p" >&2;;
    esac
  done
  return 0
}

# isolate_pro_review_workspace [PROJECT] → echoes the project name; cleans inbox/workspace/reports/metadata under it.
# テスト終了時に caller が cleanup_paths を呼ぶこと。
isolate_pro_review_workspace() {
  local proj="${1:-prr-test-$$-$RANDOM}"
  for sub in workspace inbox reports metadata; do
    mkdir -p "$HOME/.pro-review/$sub/$proj"
  done
  echo "$proj"
}

# local_browser_embed_cmd → repo-local build-review-packet を使う browser-embed 実行パス。
# インストール済み skill が main worktree を指していても、テスト中の scripts/ を使う。
local_browser_embed_cmd() {
  local repo_scripts patched dir
  repo_scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"
  patched="$(mktemp -d -t prr-be-XXXXXX)"
  sed "s|SK=\"\$HOME/.claude/skills/gpt-pro-review/scripts\"|SK=\"$repo_scripts\"|" \
    "$repo_scripts/pro-review-browser-embed" > "$patched/pro-review-browser-embed"
  chmod +x "$patched/pro-review-browser-embed"
  echo "$patched/pro-review-browser-embed"
}
