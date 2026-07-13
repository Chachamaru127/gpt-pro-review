#!/usr/bin/env bash
# 6.13: pro-review-doctor basic classification and secret hygiene.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

DOC="$(repo_scripts_dir)/pro-review-doctor"
[ -x "$DOC" ] || _fail "pro-review-doctor not executable: $DOC"

echo "[test-doctor] start"

TMP_HOME=$(mktemp -d -t prr-doctor-home-XXXXXX)
trap 'cleanup_paths "$TMP_HOME"' EXIT
mkdir -p "$TMP_HOME/.pro-review"
chmod 700 "$TMP_HOME/.pro-review"
cat > "$TMP_HOME/.pro-review/env.sh" <<'EOF'
CONTROL_PLANE_TUNNEL_ID=tunnel_test
CONTROL_PLANE_API_KEY=sk-proj-secretsecretsecretsecret
EOF
chmod 600 "$TMP_HOME/.pro-review/env.sh"

set +e
OUT=$(HOME="$TMP_HOME" "$DOC" 2>&1)
RC=$?
set -e
# Missing tunnel-client/nodriver may make this non-zero or zero depending local setup;
# classification output and secret hygiene are the contract here.
case "$RC" in 0|1) _ok "T1 doctor exit classified ($RC)";; *) _fail "T1 unexpected doctor exit $RC";; esac
assert_contains "$OUT" "base_mode" "T1 base checked"
assert_contains "$OUT" "script:pro-review-mcp" "T1 scripts checked"
assert_contains "$OUT" "env_file" "T1 env file checked"
assert_contains "$OUT" "api_key" "T1 api key presence checked"
assert_not_contains "$OUT" "sk-proj-secretsecretsecretsecret" "T1 secret value not printed"
assert_contains "$OUT" "nodriver_version" "T1 nodriver version checked"
assert_contains "$OUT" "not installed" "T1 nodriver version fallback"

mkdir -p "$TMP_HOME/.pro-review/browser/venv/bin"
cat > "$TMP_HOME/.pro-review/browser/venv/bin/python" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "-c" ] && exit 0
cat >/dev/null
exit 0
EOF
chmod +x "$TMP_HOME/.pro-review/browser/venv/bin/python"
OUT=$(HOME="$TMP_HOME" "$DOC" 2>&1)
assert_exit_ok "$?" "T2 doctor accepts browser venv nodriver"
assert_contains "$OUT" "OK"$'\t'"nodriver"$'\t'"venv module importable" "T2 venv nodriver checked"

echo "[test-doctor] PASS"
