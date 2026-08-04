#!/usr/bin/env bash
# stable run_id (6.5b): collision avoidance, save-reply validation, Path A/B integration.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

REPO_SCRIPTS="$(repo_scripts_dir)"
BE="$(local_browser_embed_cmd)"
ST="$(local_start_cmd)"
SR="$REPO_SCRIPTS/pro-review-save-reply"
WA="$REPO_SCRIPTS/pro-review-watch"
FI="$REPO_SCRIPTS/pro-review-finish"
GEN="$REPO_SCRIPTS/pro-review-gen-run-id"
BUILD="$REPO_SCRIPTS/build-review-packet"

for f in "$BE" "$ST" "$SR" "$WA" "$FI" "$GEN" "$BUILD"; do
  [ -x "$f" ] || _fail "executable missing: $f"
done

echo "[test-run-id] start"

# ---- T1: gen-run-id format ----
RID1=$("$GEN")
RID2=$("$GEN")
echo "$RID1" | grep -qE '^[0-9]+-[0-9a-f]{6}$' || _fail "T1 run_id format: $RID1"
[ "$RID1" != "$RID2" ] || _fail "T1 consecutive gen-run-id must differ: $RID1"
_ok "T1 gen-run-id format ok ($RID1)"

# ---- T2: browser-embed same-second collision ----
REPO=$(mkrepo)
PROJECT="rid-be-$$"
# Force same epoch second for since: line (run_id still unique via ms+hex)
FAKE_SINCE=1700000099
patched="$(mktemp -d -t prr-be2-XXXXXX)"
sed \
  -e 's|SINCE="$(date +%s)"|SINCE="1700000099"|' \
  "$REPO_SCRIPTS/pro-review-browser-embed" > "$patched/embed-fixed-since"
chmod +x "$patched/embed-fixed-since"
OUT1=$("$patched/embed-fixed-since" "$REPO" "$PROJECT" --question "q1" --no-clip)
OUT2=$("$patched/embed-fixed-since" "$REPO" "$PROJECT" --question "q2" --no-clip)
S1=$(awk '/^since:/{print $2; exit}' <<<"$OUT1")
S2=$(awk '/^since:/{print $2; exit}' <<<"$OUT2")
R1=$(awk '/^run_id:/{print $2; exit}' <<<"$OUT1")
R2=$(awk '/^run_id:/{print $2; exit}' <<<"$OUT2")
REQ1=$(awk '/^request_file:/{print $2; exit}' <<<"$OUT1")
REQ2=$(awk '/^request_file:/{print $2; exit}' <<<"$OUT2")
assert_eq "$FAKE_SINCE" "$S1" "T2 since1 fixed second"
assert_eq "$FAKE_SINCE" "$S2" "T2 since2 fixed second"
[ "$R1" != "$R2" ] || _fail "T2 run_id collision: $R1"
[ "$REQ1" != "$REQ2" ] || _fail "T2 request_file collision"
assert_contains "$(cat "$REQ1")" "[[DONE-$R1]]" "T2 DONE marker uses run_id1"
assert_contains "$(cat "$REQ2")" "[[DONE-$R2]]" "T2 DONE marker uses run_id2"
assert_not_contains "$(cat "$REQ1")" "[[DONE-$S1]]" "T2 DONE not seconds-only when run_id set"
_ok "T2 browser-embed no collision (run_id=$R1 vs $R2)"
rm -rf "$patched"
cleanup_paths "$REPO" "$HOME/.pro-review/inbox/$PROJECT" "$REQ1" "$REQ2"

# ---- T3: pro-review-start same-second collision ----
REPO=$(mkrepo)
PROJECT="rid-st-$$"
patched2="$(mktemp -d -t prr-st2-XXXXXX)"
sed \
  -e 's|SINCE=$(date +%s)|SINCE=1700000099|' \
  "$REPO_SCRIPTS/pro-review-start" > "$patched2/start-fixed-since"
chmod +x "$patched2/start-fixed-since"
OUT1=$("$patched2/start-fixed-since" "$REPO" "$PROJECT" --mode review --question "a")
OUT2=$("$patched2/start-fixed-since" "$REPO" "$PROJECT-b" --mode review --question "b")
S1=$(awk '/^since:/{print $2; exit}' <<<"$OUT1")
R1=$(awk '/^run_id:/{print $2; exit}' <<<"$OUT1")
R2=$(awk '/^run_id:/{print $2; exit}' <<<"$OUT2")
REQ1=$(awk '/^request_file:/{print $2; exit}' <<<"$OUT1")
REQ2=$(awk '/^request_file:/{print $2; exit}' <<<"$OUT2")
assert_eq "1700000099" "$S1" "T3 since fixed second"
[ "$R1" != "$R2" ] || _fail "T3 run_id collision"
[ "$REQ1" != "$REQ2" ] || _fail "T3 request_file collision"
assert_contains "$(cat "$REQ1")" "[[DONE-$R1]]" "T3 start DONE uses run_id"
assert_not_contains "$(cat "$REQ1")" "[[DONE-$S1]]" "T3 start DONE not seconds-only"
_ok "T3 start no collision"
rm -rf "$patched2"
: > "$HOME/.pro-review/active-project" 2>/dev/null || true
cleanup_paths "$REPO" "$HOME/.pro-review/inbox/$PROJECT" "$HOME/.pro-review/inbox/$PROJECT-b" \
  "$HOME/.pro-review/workspace/$PROJECT" "$HOME/.pro-review/workspace/$PROJECT-b" \
  "$REQ1" "$REQ2"

# ---- T4: save-reply accepts hyphenated run_id, rejects unsafe ----
P="rid-sr-$$"
GOOD="1700000000123-deadbe"
mkdir -p "$HOME/.pro-review/inbox/$P"
OUT=$("$SR" "$P" "$GOOD" --text "ok [[DONE-$GOOD]]" < /dev/null)  # CI は stdin が空 FIFO のため明示 close
assert_exit_ok "$?" "T4 hyphenated run_id"
assert_file_exists "$HOME/.pro-review/inbox/$P/REPLY-$GOOD.md" "T4 reply file"
cleanup_paths "$HOME/.pro-review/inbox/$P"

# legacy numeric still works
P2="rid-sr2-$$"
NUM=1700000042
mkdir -p "$HOME/.pro-review/inbox/$P2"
"$SR" "$P2" "$NUM" --text "legacy [[DONE-$NUM]]" >/dev/null < /dev/null
assert_file_exists "$HOME/.pro-review/inbox/$P2/REPLY-$NUM.md" "T4 legacy numeric"
cleanup_paths "$HOME/.pro-review/inbox/$P2"

for bad in "../x" "" "has space" "a/b" ".." ".foo" "-foo"; do
  set +e
  "$SR" "rid-bad-$$" "$bad" --text "x" >/dev/null 2>&1 < /dev/null
  RC=$?
  set -e
  assert_exit_nonzero "$RC" "T4 reject run_id '$bad'"
done

# ---- T4b: build-review-packet --run-id rejects same unsafe ids as save-reply ----
REPO=$(mkrepo)
OUT_BR="/tmp/prr-runid-br-$$.md"
for bad in ".foo" "-foo"; do
  set +e
  "$BUILD" --repo "$REPO" --for-browser --run-id "$bad" --out "$OUT_BR" --no-clip >/dev/null 2>&1
  RC=$?
  set -e
  assert_exit_nonzero "$RC" "T4b build-review-packet reject run_id '$bad'"
done
rm -f "$OUT_BR"
cleanup_paths "$REPO"

# ---- T5: Path A integration uses run_id for reply, since for watch ----
REPO=$(mkrepo)
(cd "$REPO" && echo "X" >> calc.py)
PROJECT="rid-iA-$$"
OUT=$("$BE" "$REPO" "$PROJECT" --question "q" --no-clip)
SINCE=$(awk '/^since:/{print $2; exit}' <<<"$OUT")
RUN_ID=$(awk '/^run_id:/{print $2; exit}' <<<"$OUT")
INBOX=$(awk '/^inbox:/{print $2; exit}' <<<"$OUT")
FAKE=$(printf 'review\n[[DONE-%s]]' "$RUN_ID")
printf '%s' "$FAKE" | "$SR" "$PROJECT" "$RUN_ID" >/dev/null
REPLY="$INBOX/REPLY-$RUN_ID.md"
assert_file_exists "$REPLY" "T5 Path A reply by run_id"
W_OUT=$("$WA" "$INBOX" --run-id "$RUN_ID" --since "$((SINCE - 1))" --timeout 5 --interval 1 2>/dev/null)
assert_exit_ok "$?" "T5 watch with run_id + numeric since"
assert_contains "$W_OUT" "REPLY:" "T5 watch hit"
F_OUT=$("$FI" "$PROJECT" "$REPLY" 2>&1)
assert_exit_ok "$?" "T5 finish"
assert_contains "$F_OUT" "REPLY-$RUN_ID" "T5 report keeps run_id filename"
cleanup_paths "$REPO" "$INBOX" "$HOME/.pro-review/reports/$PROJECT"

# ---- T6: Path B integration uses run_id for reply, since for watch ----
REPO=$(mkrepo)
PROJECT="rid-iB-$$"
OUT=$("$ST" "$REPO" "$PROJECT" --mode review --question "q")
SINCE=$(awk '/^since:/{print $2; exit}' <<<"$OUT")
RUN_ID=$(awk '/^run_id:/{print $2; exit}' <<<"$OUT")
INBOX=$(awk '/^inbox:/{print $2; exit}' <<<"$OUT")
printf 'ok\n[[DONE-%s]]' "$RUN_ID" | "$SR" "$PROJECT" "$RUN_ID" >/dev/null
REPLY="$INBOX/REPLY-$RUN_ID.md"
assert_file_exists "$REPLY" "T6 Path B reply by run_id"
W_OUT=$("$WA" "$INBOX" --run-id "$RUN_ID" --since "$((SINCE - 1))" --timeout 5 --interval 1 2>/dev/null)
assert_exit_ok "$?" "T6 watch with run_id + numeric since"
"$FI" "$PROJECT" "$REPLY" >/dev/null
REPORTS="$HOME/.pro-review/reports/$PROJECT"
COUNT=$(ls "$REPORTS"/*REPLY* 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" -ge 1 ] || _fail "T6 reports missing"
_ok "T6 Path B reports ($COUNT)"
: > "$HOME/.pro-review/active-project" 2>/dev/null || true
cleanup_paths "$REPO" "$INBOX" "$REPORTS" "$HOME/.pro-review/workspace/$PROJECT"

# ---- T7: watch --run-id picks correct reply when sibling is newer ----
P="rid-wt-$$"
INBOX="$HOME/.pro-review/inbox/$P"
mkdir -p "$INBOX"
RA="1700000000123-aaa111"
RB="1700000000123-bbb222"
SINCE=1700000099
"$SR" "$P" "$RA" --text "$(printf 'reply A\n[[DONE-%s]]' "$RA")" >/dev/null < /dev/null
"$SR" "$P" "$RB" --text "$(printf 'reply B\n[[DONE-%s]]' "$RB")" >/dev/null < /dev/null
touch "$INBOX/REPLY-$RB.md"
[ "$(stat -f '%m' "$INBOX/REPLY-$RB.md")" -ge "$(stat -f '%m' "$INBOX/REPLY-$RA.md")" ] \
  || _fail "T7 setup: REPLY-B must be newer than REPLY-A"
W_OUT=$("$WA" "$INBOX" --run-id "$RA" --since "$((SINCE - 1))" --timeout 5 --interval 1 2>/dev/null)
assert_exit_ok "$?" "T7 watch with run_id A"
assert_contains "$W_OUT" "REPLY-$RA.md" "T7 returns REPLY-A"
assert_not_contains "$W_OUT" "REPLY-$RB.md" "T7 does not return newer REPLY-B"
_ok "T7 watch --run-id disambiguates concurrent replies"
cleanup_paths "$INBOX"

echo "[test-run-id] PASS"
