#!/usr/bin/env bash
# 6.3a: 拡張 secret/PII パターン + project literal 非混入のテスト。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

BUILD="$SCRIPT_DIR/../scripts/build-review-packet"
[ -x "$BUILD" ] || _fail "build-review-packet not executable at $BUILD"

# テスト専用の禁止トークン（skill 本体に含まれてはいけない）
FORBIDDEN_A="FORBIDDEN_CODENAME_XYZ123"
FORBIDDEN_B="FORBIDDEN_CUSTOMER_ABC"

echo "[test-secret-scan-extended] start"

OUT="/tmp/prr-secret-ext-$$.md"
ERR="/tmp/prr-secret-ext-err-$$.txt"

scan_fixture() {
  # scan_fixture LABEL CONTENT
  local label="$1" content="$2"
  local repo
  repo=$(mkrepo)
  (cd "$repo" && printf '%s\n' "$content" > leak.txt)
  set +e
  "$BUILD" --repo "$repo" --out "$OUT" --no-clip >/dev/null 2>"$ERR"
  local rc=$?
  set -e
  cleanup_paths "$repo"
  rm -f "$OUT" "$ERR"
  echo "$rc"
}

# ---- reserved example emails → exit 0 ----
assert_exit_ok "$(scan_fixture example_com 'contact=user@example.com')" \
  "example.com email allowed"
assert_exit_ok "$(scan_fixture example_org 'contact=user@example.org')" \
  "example.org email allowed"
assert_exit_ok "$(scan_fixture example_tld 'contact=user@foo.example')" \
  ".example TLD email allowed"

# ---- real-looking email → exit 1 ----
assert_exit_nonzero "$(scan_fixture real_email 'contact=alice.real@gmail.com')" \
  "real email in packet blocks"
assert_exit_nonzero "$(scan_fixture real_email_period 'contact=alice.real@gmail.com.')" \
  "real email with trailing period blocks"
assert_exit_ok "$(scan_fixture example_com_period 'contact=user@example.com.')" \
  "example.com with trailing period allowed"
assert_exit_nonzero "$(scan_fixture ipv4 'server=203.0.113.50')" \
  "IPv4 in packet blocks"
assert_exit_nonzero "$(scan_fixture phone 'tel=090-1234-5678')" \
  "JP phone in packet blocks"
assert_exit_nonzero "$(scan_fixture postal 'zip=100-0001')" \
  "JP postal in packet blocks"
assert_exit_nonzero "$(scan_fixture token 'api_key=abcdefghijklmnopqrstuvwxyz0123456789ABCD')" \
  "high-entropy token in packet blocks"
assert_exit_nonzero "$(scan_fixture json_api_key '{"api_key": "abcdefghijklmnopqrstuvwxyz0123456789ABCD"}')" \
  "JSON quoted api_key in packet blocks"
assert_exit_nonzero "$(scan_fixture json_spaced '  "secret" : "abcdefghijklmnopqrstuvwxyz0123456789ABCD"  ')" \
  "JSON spaced quoted secret in packet blocks"
assert_exit_nonzero "$(scan_fixture single_quoted "'token' = 'abcdefghijklmnopqrstuvwxyz0123456789ABCD'")" \
  "single-quoted token assignment in packet blocks"
assert_exit_nonzero "$(scan_fixture hyphen_key 'api-key = \"abcdefghijklmnopqrstuvwxyz0123456789ABCD\"')" \
  "hyphenated api-key quoted value in packet blocks"
assert_exit_ok "$(scan_fixture clean_json '{"name": "demo", "count": 3}')" \
  "clean JSON without secret allowed"
assert_exit_ok "$(scan_fixture clean_json_key '{"api_key": "placeholder"}')" \
  "short api_key placeholder allowed"
assert_exit_nonzero "$(scan_fixture pem 'key_path=/home/user/.ssh/id_rsa.pem')" \
  ".pem path in packet blocks"
assert_exit_nonzero "$(scan_fixture pem_slash 'ssl_path=/etc/ssl/server.pem')" \
  "/etc/ssl/server.pem path in packet blocks"
assert_exit_nonzero "$(scan_fixture rsa_private_key '-----BEGIN RSA PRIVATE KEY-----')" \
  "RSA private key material in packet blocks"
assert_exit_ok "$(scan_fixture private_key_identifier 'const privateKey = config.privateKey;')" \
  "privateKey identifier without key material or path allowed"
assert_exit_ok "$(scan_fixture private_key_hyphen 'const private-key = signer.private-key;')" \
  "private-key identifier without key material or path allowed"

# ---- clean repo → exit 0 ----
REPO=$(mkrepo)
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/dev/null
RC=$?
set -e
assert_exit_ok "$RC" "clean repo exit 0"
assert_file_exists "$OUT" "clean repo packet written"
cleanup_paths "$REPO" "$OUT"

# ---- skill 本体に project 固有 literal が無い ----
for tok in "$FORBIDDEN_A" "$FORBIDDEN_B"; do
  if grep -qF "$tok" "$BUILD"; then
    _fail "build-review-packet must not contain project literal: $tok"
  fi
  _ok "no forbidden literal ($tok)"
done

echo "[test-secret-scan-extended] PASS"
