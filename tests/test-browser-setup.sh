#!/usr/bin/env bash
# 6.6: browser setup creates dedicated profile/venv and gives manual next steps.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

SETUP="$(repo_scripts_dir)/pro-review-browser-setup"
[ -x "$SETUP" ] || _fail "pro-review-browser-setup not executable: $SETUP"

echo "[test-browser-setup] start"

TMP_HOME=$(mktemp -d -t prr-browser-setup-home-XXXXXX)
trap 'cleanup_paths "$TMP_HOME"' EXIT

set +e
OUT=$(HOME="$TMP_HOME" "$SETUP" 2>&1)
RC=$?
set -e
case "$RC" in 0|3) _ok "T1 setup exits ready-or-manual ($RC)";; *) _fail "T1 unexpected exit $RC";; esac
PROFILE="$TMP_HOME/.pro-review/browser/profile"
VENV="$TMP_HOME/.pro-review/browser/venv"
[ -d "$PROFILE" ] || _fail "T1 profile missing"
[ -x "$VENV/bin/python" ] || _fail "T1 venv python missing"
assert_eq "700" "$(stat -f '%Lp' "$TMP_HOME/.pro-review")" "T1 base mode"
assert_eq "700" "$(stat -f '%Lp' "$PROFILE")" "T1 profile mode"
assert_contains "$OUT" "profile:" "T1 profile output"
assert_contains "$OUT" "venv:" "T1 venv output"

set +e
OUT2=$(HOME="$TMP_HOME" "$SETUP" --assume-logged-in 2>&1)
RC2=$?
set -e
case "$RC2" in 0|3) _ok "T2 idempotent setup exits ready-or-manual ($RC2)";; *) _fail "T2 unexpected exit $RC2";; esac
assert_file_exists "$PROFILE/.chatgpt-login-ok" "T2 login marker"
assert_contains "$OUT2" "OK login" "T2 login marker recognized"

rm -f "$PROFILE/.chatgpt-login-ok"
set +e
OUT3=$(HOME="$TMP_HOME" PRO_REVIEW_OPEN_LOGIN_DRY_RUN=1 "$SETUP" --open-login 2>&1)
RC3=$?
set -e
assert_eq "3" "$RC3" "T3 open-login exits manual without marker"
assert_contains "$OUT3" "open_login:" "T3 open-login command emitted"
assert_contains "$OUT3" "--mark-logged-in" "T3 mark command documented"

set +e
OUT4=$(HOME="$TMP_HOME" "$SETUP" --mark-logged-in 2>&1)
RC4=$?
set -e
case "$RC4" in 0|3) _ok "T4 mark-logged-in exits ready-or-manual ($RC4)";; *) _fail "T4 unexpected exit $RC4";; esac
assert_file_exists "$PROFILE/.chatgpt-login-ok" "T4 marker via user alias"
assert_contains "$OUT4" "OK login" "T4 marker recognized"
assert_contains "$OUT4" "close the dedicated Chrome window" "T4 close-browser warning"

assert_contains "$(cat "$SETUP")" 'nodriver==${NODRIVER_PIN}' "T5 nodriver version pin"

echo "[test-browser-setup] PASS"
