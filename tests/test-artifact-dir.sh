#!/usr/bin/env bash
# 11.5: --artifact-dir diagnostic artifacts on fallback.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

DRV="$(repo_scripts_dir)/pro-review-browser-drive"
[ -x "$DRV" ] || _fail "pro-review-browser-drive not executable: $DRV"

echo "[test-artifact-dir] start"

TMP=$(mktemp -d -t prr-artifact-dir-XXXXXX)
trap 'cleanup_paths "$TMP"' EXIT
RID="1700000000999-artifact"
ART_DIR="$TMP/reports/test-project/$RID"

STOP="$TMP/stop.html"
cat > "$STOP" <<EOF
<button aria-label="Stop generating">Stop</button>
<div data-message-author-role="assistant"><p>partial</p></div>
EOF

set +e
OUT=$("$DRV" --fixture-html "$STOP" --run-id "$RID" --artifact-dir "$ART_DIR" 2>/dev/null)
RC=$?
set -e
assert_eq "3" "$RC" "T1 fallback exit"
assert_contains "$OUT" "FALLBACK:response still generating" "T1 fallback reason"
assert_contains "$OUT" "ARTIFACTS:$ART_DIR" "T1 artifacts line"
assert_file_exists "$ART_DIR/dom-excerpt.html" "T1 dom excerpt saved"
assert_contains "$(cat "$ART_DIR/dom-excerpt.html")" "Stop generating" "T1 dom excerpt content"

DIR_PERM=$(python3 - <<PY
import os, stat
mode = os.stat("$ART_DIR").st_mode
print(oct(stat.S_IMODE(mode))[-3:])
PY
)
assert_eq "700" "$DIR_PERM" "T1 artifact dir mode"

FILE_PERM=$(python3 - <<PY
import os, stat
mode = os.stat("$ART_DIR/dom-excerpt.html").st_mode
print(oct(stat.S_IMODE(mode))[-3:])
PY
)
assert_eq "600" "$FILE_PERM" "T1 dom excerpt mode"

NO_ART_DIR="$TMP/no-artifacts"
mkdir -p "$NO_ART_DIR"
set +e
OUT2=$("$DRV" --fixture-html "$STOP" --run-id "$RID" 2>/dev/null)
RC=$?
set -e
assert_eq "3" "$RC" "T2 fallback without artifact-dir"
assert_file_not_exists "$NO_ART_DIR/dom-excerpt.html" "T2 no dom excerpt without flag"
assert_not_contains "$OUT2" "ARTIFACTS:" "T2 no artifacts line without flag"

echo "[test-artifact-dir] PASS"
