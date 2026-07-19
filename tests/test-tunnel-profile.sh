#!/usr/bin/env bash
# tunnel auth profile: env.sh パース、doctor 表示、dry-run 解決。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

DOC="$(repo_scripts_dir)/pro-review-doctor"
TUN="$(repo_scripts_dir)/pro-review-tunnel"
[ -x "$DOC" ] || _fail "pro-review-doctor not executable: $DOC"
[ -x "$TUN" ] || _fail "pro-review-tunnel not executable: $TUN"

echo "[test-tunnel-profile] start"

TMP_HOME=$(mktemp -d -t prr-tunnel-profile-home-XXXXXX)
trap 'cleanup_paths "$TMP_HOME"' EXIT
mkdir -p "$TMP_HOME/.pro-review"
chmod 700 "$TMP_HOME/.pro-review"

cat > "$TMP_HOME/.pro-review/env.sh" <<'EOF'
PRO_REVIEW_TUNNEL_PROFILE=A
CONTROL_PLANE_TUNNEL_ID_A=tunnel_profile_a_1234567890
CONTROL_PLANE_API_KEY_A=sk-proj-dummydummydummy
CONTROL_PLANE_ORG_ID_A=org-profiletest01
EOF
chmod 600 "$TMP_HOME/.pro-review/env.sh"

OUT=$(HOME="$TMP_HOME" "$DOC" 2>&1)
assert_contains "$OUT" "OK"$'\t'"api_key"$'\t'"configured (profile 形式)" "T1a doctor api_key profile ok"
assert_contains "$OUT" "OK"$'\t'"tunnel_id"$'\t'"configured (profile 形式)" "T1b doctor tunnel_id profile ok"
assert_contains "$OUT" "OK"$'\t'"tunnel_profile"$'\t'"A" "T1c doctor tunnel_profile shown"
assert_not_contains "$OUT" "sk-proj-dummydummydummy" "T1d doctor does not print api key"

set +e
DRY_OUT=$(HOME="$TMP_HOME" PRO_REVIEW_TUNNEL_DRY_RUN=1 "$TUN" 2>&1)
DRY_RC=$?
set -e
assert_exit_ok "$DRY_RC" "T2 dry-run exit 0"
assert_contains "$DRY_OUT" "[tunnel] profile=A tunnel_id=tunnel_profi… org_header=yes" "T2a dry-run profile A"
assert_not_contains "$DRY_OUT" "sk-proj-dummydummydummy" "T2b dry-run does not print api key"
assert_not_contains "$DRY_OUT" "org-profiletest01" "T2c dry-run does not print org id value"

cat > "$TMP_HOME/.pro-review/env.sh" <<'EOF'
CONTROL_PLANE_TUNNEL_ID=tunnel_legacy_only
CONTROL_PLANE_API_KEY=sk-proj-legacylegacylegacy
EOF
chmod 600 "$TMP_HOME/.pro-review/env.sh"

OUT=$(HOME="$TMP_HOME" "$DOC" 2>&1)
assert_contains "$OUT" "OK"$'\t'"api_key"$'\t'"configured" "T3a doctor unsuffixed api_key ok"
assert_contains "$OUT" "OK"$'\t'"tunnel_id"$'\t'"configured" "T3b doctor unsuffixed tunnel_id ok"
assert_not_contains "$OUT" "OK"$'\t'"tunnel_profile"$'\t' "T3c doctor no tunnel_profile without profile line"

set +e
DRY_OUT=$(HOME="$TMP_HOME" PRO_REVIEW_TUNNEL_DRY_RUN=1 "$TUN" 2>&1)
DRY_RC=$?
set -e
assert_exit_ok "$DRY_RC" "T3d dry-run legacy exit 0"
assert_contains "$DRY_OUT" "[tunnel] profile=default tunnel_id=tunnel_legac… org_header=no" "T3e dry-run default profile"
assert_not_contains "$DRY_OUT" "sk-proj-legacylegacylegacy" "T3f dry-run legacy key not printed"

cat > "$TMP_HOME/.pro-review/env.sh" <<'EOF'
PRO_REVIEW_TUNNEL_PROFILE=B
CONTROL_PLANE_TUNNEL_ID_A=tunnel_wrong_profile
CONTROL_PLANE_API_KEY_A=sk-proj-wrongwrongwrongwrong
CONTROL_PLANE_TUNNEL_ID_B=tunnel_profile_b_abcdefghij
CONTROL_PLANE_API_KEY_B=sk-proj-profilebprofileb
EOF
chmod 600 "$TMP_HOME/.pro-review/env.sh"

set +e
DRY_OUT=$(HOME="$TMP_HOME" PRO_REVIEW_TUNNEL_DRY_RUN=1 "$TUN" 2>&1)
set -e
assert_contains "$DRY_OUT" "[tunnel] profile=B tunnel_id=tunnel_profi… org_header=no" "T4 selects profile B not A"
assert_not_contains "$DRY_OUT" "sk-proj-wrongwrongwrongwrong" "T4a wrong profile key not printed"
assert_not_contains "$DRY_OUT" "sk-proj-profilebprofileb" "T4b selected profile key not printed"

set +e
DRY_OUT=$(HOME="$TMP_HOME" PRO_REVIEW_TUNNEL_PROFILE=A PRO_REVIEW_TUNNEL_DRY_RUN=1 "$TUN" 2>&1)
set -e
assert_contains "$DRY_OUT" "[tunnel] profile=A tunnel_id=tunnel_wrong… org_header=no" "T5 env PRO_REVIEW_TUNNEL_PROFILE overrides file B"

echo "[test-tunnel-profile] PASS"
