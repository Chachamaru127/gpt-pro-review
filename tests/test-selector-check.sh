#!/usr/bin/env bash
# 13.2: pro-review-doctor --selector-check opt-in selector probe.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

DOC="$(repo_scripts_dir)/pro-review-doctor"
HELPER="$(repo_scripts_dir)/pro-review-doctor-selector-check"
DRV="$(repo_scripts_dir)/pro-review-browser-drive"
[ -x "$DOC" ] || _fail "pro-review-doctor not executable: $DOC"
[ -f "$HELPER" ] || _fail "pro-review-doctor-selector-check missing: $HELPER"
[ -x "$DRV" ] || _fail "pro-review-browser-drive not executable: $DRV"

echo "[test-selector-check] start"

TMP_HOME=$(mktemp -d -t prr-doctor-home-XXXXXX)
trap 'cleanup_paths "$TMP_HOME"' EXIT
mkdir -p "$TMP_HOME/.pro-review"
chmod 700 "$TMP_HOME/.pro-review"
cat > "$TMP_HOME/.pro-review/env.sh" <<'EOF'
CONTROL_PLANE_TUNNEL_ID=tunnel_test
CONTROL_PLANE_API_KEY=sk-proj-secretsecretsecretsecret
EOF
chmod 600 "$TMP_HOME/.pro-review/env.sh"

OUT=$(HOME="$TMP_HOME" "$DOC" 2>&1)
assert_exit_ok "$?" "T1 doctor without flag exits 0"
assert_not_contains "$OUT" "selector" "T1 default doctor has no selector lines"

set +e
OUT=$(HOME="$TMP_HOME" "$DOC" --selector-check 2>&1)
RC=$?
set -e
assert_exit_ok "$RC" "T2 selector-check manual path exits 0"
assert_contains "$OUT" "MANUAL"$'\t'"selector_check" "T2 manual selector_check emitted"
assert_contains "$OUT" "## selector-check (doctor --selector-check)" "T2 manual-checklist block emitted"

python3 - "$DRV" "$HELPER" <<'PY'
import importlib.machinery
import sys

mod = importlib.machinery.SourceFileLoader(
    "pro_review_browser_drive_enum", sys.argv[1]
).load_module()
helper = importlib.machinery.SourceFileLoader(
    "pro_review_doctor_selector_check_enum", sys.argv[2]
).load_module()
entries = helper.collect_selector_entries(mod)
assert entries, "expected non-empty selector list"
assert any(name.startswith("COMPOSER_QUERY_SELECTORS[") for name, _ in entries)
assert any(name == "BUTTON_ROLE_SELECTOR" for name, _ in entries)
PY
assert_exit_ok "$?" "T3 selector enumeration non-empty"

JS_OUT=$(python3 - "$HELPER" <<'PY'
import importlib.machinery
import sys

helper = importlib.machinery.SourceFileLoader(
    "pro_review_doctor_selector_check_js_out", sys.argv[1]
).load_module()
sample = [
    ("COMPOSER_QUERY_SELECTORS[0]", "#prompt-textarea"),
    ("BUTTON_ROLE_SELECTOR", 'button,[role="button"]'),
]
print(helper.build_selector_check_js(sample))
PY
)
assert_exit_ok "$?" "T4 build_selector_check_js renders"
if command -v node >/dev/null 2>&1; then
  printf '%s\n' "$JS_OUT" | node --check
  assert_exit_ok "$?" "T4 selector check JS passes node --check"
else
  _fail "T4 node required for JS syntax validation"
fi

echo "[test-selector-check] PASS"
