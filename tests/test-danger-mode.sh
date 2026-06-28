#!/usr/bin/env bash
# デンジャラスモード（外部公開前 secret scan の恒久バイパス）の e2e。
# 既定 OFF（scan 有効）/ env・恒久マーカーで bypass / トグル CLI の round-trip /
# Path A(python packet) と Path B(bash snapshot) 双方で一貫することを検証する。
# 隔離 HOME を使い、実環境の ~/.pro-review/danger-mode に影響されないようにする。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

SK="$(repo_scripts_dir)"
SNAP="$SK/pro-review-snapshot"
TOGGLE="$SK/pro-review-danger-mode"
PACKET="$SK/build-review-packet"
[ -x "$SNAP" ] || _fail "pro-review-snapshot not executable: $SNAP"
[ -x "$TOGGLE" ] || _fail "pro-review-danger-mode not executable: $TOGGLE"
[ -x "$PACKET" ] || _fail "build-review-packet not executable: $PACKET"

echo "[test-danger-mode] start"

TMP_HOME=$(mktemp -d -t prr-danger-home-XXXXXX)
trap 'cleanup_paths "$TMP_HOME"' EXIT
mkdir -p "$TMP_HOME/.pro-review"
chmod 700 "$TMP_HOME/.pro-review"

# 疑似秘密(sk- + 40英数)を含む repo。snapshot/packet 双方の高signalパターンにヒットする。
LEAK='token = "sk-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"'
REPO=$(mkrepo)
(cd "$REPO" && printf '%s\n' "$LEAK" > leak.txt)

# ---- T1: 既定 OFF（マーカー無し・env無し）→ snapshot は公開中止 ----
set +e
OUT1=$(HOME="$TMP_HOME" "$SNAP" "$REPO" danger-default 2>&1)
RC1=$?
set -e
assert_eq "1" "$RC1" "T1 default off blocks snapshot"
assert_contains "$OUT1" "公開を中止" "T1 block message"
assert_file_not_exists "$TMP_HOME/.pro-review/danger-mode" "T1 no marker by default"

# ---- T2: PRO_REVIEW_DANGER_MODE=1 (per-call) → bypass + [danger] 警告 ----
set +e
OUT2=$(HOME="$TMP_HOME" PRO_REVIEW_DANGER_MODE=1 "$SNAP" "$REPO" danger-env 2>&1)
RC2=$?
set -e
assert_exit_ok "$RC2" "T2 env bypass exit 0"
assert_contains "$OUT2" "[danger] secret scan bypassed" "T2 danger warning emitted"
assert_contains "$OUT2" "snapshot(read-only):" "T2 snapshot completed"

# ---- T3: トグル --on → マーカー作成 → status ON → snapshot bypass ----
OUT_ON=$(HOME="$TMP_HOME" "$TOGGLE" --on 2>&1)
assert_contains "$OUT_ON" "danger_mode: ON" "T3 toggle on reports ON"
assert_file_exists "$TMP_HOME/.pro-review/danger-mode" "T3 marker created"
ST_ON=$(HOME="$TMP_HOME" "$TOGGLE" --status 2>&1)
assert_contains "$ST_ON" "danger_mode: ON" "T3 status reports ON"
set +e
OUT3=$(HOME="$TMP_HOME" "$SNAP" "$REPO" danger-marker 2>&1)
RC3=$?
set -e
assert_exit_ok "$RC3" "T3 marker bypass exit 0"
assert_contains "$OUT3" "[danger] secret scan bypassed" "T3 marker bypass warning"

# ---- T4: トグル --off → マーカー削除 → snapshot は再び公開中止 ----
OUT_OFF=$(HOME="$TMP_HOME" "$TOGGLE" --off 2>&1)
assert_contains "$OUT_OFF" "danger_mode: OFF" "T4 toggle off reports OFF"
assert_file_not_exists "$TMP_HOME/.pro-review/danger-mode" "T4 marker removed"
set +e
OUT4=$(HOME="$TMP_HOME" "$SNAP" "$REPO" danger-off 2>&1)
RC4=$?
set -e
assert_eq "1" "$RC4" "T4 off blocks snapshot again"

# ---- T5: Path A (python packet) も同じトグルで一貫 ----
REPO5=$(mkrepo)
(cd "$REPO5" && printf 'contact=alice.real@gmail.com\n' > leak.txt)
OUT5="$TMP_HOME/packet5.md"
# 既定 OFF → 中止
set +e
HOME="$TMP_HOME" "$PACKET" --repo "$REPO5" --out "$OUT5" --no-clip >/dev/null 2>"$TMP_HOME/err5a.txt"
RC5A=$?
set -e
assert_exit_nonzero "$RC5A" "T5 packet default off blocks"
# マーカー ON → bypass + [danger]
HOME="$TMP_HOME" "$TOGGLE" --on >/dev/null 2>&1
set +e
HOME="$TMP_HOME" "$PACKET" --repo "$REPO5" --out "$OUT5" --no-clip >/dev/null 2>"$TMP_HOME/err5b.txt"
RC5B=$?
set -e
assert_exit_ok "$RC5B" "T5 packet marker bypass exit 0"
assert_contains "$(cat "$TMP_HOME/err5b.txt")" "[danger]" "T5 packet danger warning"
assert_file_exists "$OUT5" "T5 packet written under bypass"
HOME="$TMP_HOME" "$TOGGLE" --off >/dev/null 2>&1

# ---- T6: 不正な引数は usage で exit 2 ----
set +e
HOME="$TMP_HOME" "$TOGGLE" --bogus >/dev/null 2>&1
RC6=$?
set -e
assert_eq "2" "$RC6" "T6 bad arg exit 2"

# ---- T7: PRO_REVIEW_FORCE_SCAN=1 は marker(ON) より優先して scan を強制する ----
HOME="$TMP_HOME" "$TOGGLE" --on >/dev/null 2>&1
set +e
OUT7=$(HOME="$TMP_HOME" PRO_REVIEW_FORCE_SCAN=1 "$SNAP" "$REPO" danger-force 2>&1)
RC7=$?
set -e
assert_eq "1" "$RC7" "T7 force-scan overrides danger marker (blocks)"
assert_contains "$OUT7" "公開を中止" "T7 force-scan block message"
HOME="$TMP_HOME" "$TOGGLE" --off >/dev/null 2>&1

cleanup_paths "$REPO" "$REPO5" \
  "$TMP_HOME/.pro-review/workspace/danger-default" "$TMP_HOME/.pro-review/workspace/danger-env" \
  "$TMP_HOME/.pro-review/workspace/danger-marker" "$TMP_HOME/.pro-review/workspace/danger-off"

echo "[test-danger-mode] PASS"
