#!/usr/bin/env bash
# 6.3b: Path A (embed) の secret-ish filename 除外テスト。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

BUILD="$SCRIPT_DIR/../scripts/build-review-packet"
[ -x "$BUILD" ] || _fail "build-review-packet not executable at $BUILD"

echo "[test-pathA-filename-exclude] start"

REPO=$(mkrepo)
(
  cd "$REPO"
  echo 'SECRET=super_secret_value' > .env
  cat > id_rsa <<'EOF'
-----BEGIN RSA PRIVATE KEY-----
FAKE
EOF
  echo '{"client_secret":"leaked"}' > credentials.json
)

OUT="/tmp/prr-pathA-excl-$$.md"
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/dev/null
RC=$?
set -e
assert_exit_ok "$RC" "exclude-only repo exit 0 (bodies omitted, not scanned)"
assert_file_exists "$OUT" "packet written"

CONTENT=$(cat "$OUT")

assert_not_contains "$CONTENT" "super_secret_value" ".env body not embedded"
assert_not_contains "$CONTENT" "BEGIN RSA PRIVATE KEY" "id_rsa body not embedded"
assert_not_contains "$CONTENT" "client_secret" "credentials.json body not embedded"

assert_contains "$CONTENT" ".env" ".env listed in omitted"
assert_contains "$CONTENT" "id_<REDACTED>" "id_rsa listed in omitted (redacted)"
assert_contains "$CONTENT" "credentials.json" "credentials.json listed in omitted"
assert_contains "$CONTENT" "同梱省略" "omitted section present"
cleanup_paths "$REPO" "$OUT"

# ---- P1: diff-path leak — tracked .env secret must not appear via diff ----
REPO=$(mkrepo)
(
  cd "$REPO"
  echo 'SECRET=super_secret_value' > .env
  git add .env && git commit -qm "track env"
  echo 'SECRET=super_secret_value_changed' > .env
)
OUT="/tmp/prr-pathA-diff-excl-$$.md"
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/dev/null
RC=$?
set -e
assert_exit_ok "$RC" "tracked .env diff leak exit 0 (diff hunk stripped)"
assert_file_exists "$OUT" "diff-excl packet written"
CONTENT=$(cat "$OUT")
assert_not_contains "$CONTENT" "super_secret_value" ".env secret not in packet via diff"
assert_not_contains "$CONTENT" "super_secret_value_changed" ".env changed secret not in packet via diff"
assert_contains "$CONTENT" ".env" ".env listed in omitted (diff exclusion)"
cleanup_paths "$REPO" "$OUT"

# ---- FIX1: normal app paths under profile/cookies segments ARE embedded ----
REPO=$(mkrepo)
(
  cd "$REPO"
  mkdir -p src/profile app/cookies
  echo 'export default function Profile() { return <div>profile page</div>; }' > src/profile/page.tsx
  echo 'export async function GET() { return Response.json({ ok: true }); }' > app/cookies/route.ts
  git add src/profile/page.tsx app/cookies/route.ts
  git commit -qm "add profile and cookies routes"
  echo 'export default function Profile() { return <div>updated profile</div>; }' > src/profile/page.tsx
  echo 'export async function GET() { return Response.json({ ok: true, v: 2 }); }' > app/cookies/route.ts
)
OUT="/tmp/prr-pathA-profile-cookies-$$.md"
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/dev/null
RC=$?
set -e
assert_exit_ok "$RC" "profile/cookies app paths exit 0"
assert_file_exists "$OUT" "profile/cookies packet written"
CONTENT=$(cat "$OUT")
assert_contains "$CONTENT" "updated profile" "src/profile/page.tsx body embedded"
assert_contains "$CONTENT" "v: 2" "app/cookies/route.ts body embedded"
assert_contains "$CONTENT" "src/profile/page.tsx" "src/profile/page.tsx in packet"
assert_contains "$CONTENT" "app/cookies/route.ts" "app/cookies/route.ts in packet"
assert_not_contains "$CONTENT" "同梱省略" "profile/cookies paths not falsely omitted"
cleanup_paths "$REPO" "$OUT"

# ---- P2a: credentials/ dir is NOT auto-excluded; only credentials.json basename is ----
REPO=$(mkrepo)
(
  cd "$REPO"
  mkdir -p credentials
  echo 'session=abc123' > credentials/session.txt
)
OUT="/tmp/prr-pathA-nested-cred-$$.md"
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/dev/null
RC=$?
set -e
assert_exit_ok "$RC" "credentials/session.txt exit 0 (dir not excluded)"
assert_file_exists "$OUT" "nested-cred packet written"
CONTENT=$(cat "$OUT")
assert_contains "$CONTENT" "session=abc123" "credentials/session.txt body embedded"
assert_contains "$CONTENT" "credentials/session.txt" "credentials/session.txt in packet body"
cleanup_paths "$REPO" "$OUT"

# ---- P1 rename/copy: .env -> config.txt must not leak removed .env lines via diff ----
REPO=$(mkrepo)
(
  cd "$REPO"
  echo 'SECRET=super_secret_value' > .env
  git add .env && git commit -qm "track env"
  git mv .env config.txt
)
OUT="/tmp/prr-pathA-rename-excl-$$.md"
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/dev/null
RC=$?
set -e
assert_exit_ok "$RC" "rename .env->config.txt exit 0 (diff hunk stripped via a/ path)"
assert_file_exists "$OUT" "rename-excl packet written"
CONTENT=$(cat "$OUT")
assert_not_contains "$CONTENT" "super_secret_value" ".env secret not in packet via rename diff"
assert_contains "$CONTENT" ".env" ".env listed in omitted (rename/copy diff exclusion)"
cleanup_paths "$REPO" "$OUT"

# ---- P2 nested-key omission: .ssh/id_rsa and certs/server.pem must not self-flag final scan ----
REPO=$(mkrepo)
(
  cd "$REPO"
  mkdir -p .ssh certs
  cat > .ssh/id_rsa <<'EOF'
-----BEGIN RSA PRIVATE KEY-----
FAKE
EOF
  echo "FAKE PEM BODY" > certs/server.pem
)
OUT="/tmp/prr-pathA-nested-key-$$.md"
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/dev/null
RC=$?
set -e
assert_exit_ok "$RC" "nested .ssh/id_rsa + certs/server.pem exit 0 (omission manifest not self-flagged)"
assert_file_exists "$OUT" "nested-key packet written"
CONTENT=$(cat "$OUT")
assert_not_contains "$CONTENT" "BEGIN RSA PRIVATE KEY" "id_rsa body not embedded"
assert_not_contains "$CONTENT" "FAKE PEM BODY" "server.pem body not embedded"
assert_contains "$CONTENT" "id_<REDACTED>" "id_rsa listed in omitted (redacted)"
assert_contains "$CONTENT" ".<REDACTED>" "server.pem listed in omitted (redacted)"
assert_contains "$CONTENT" "同梱省略" "omitted section present for nested keys"
cleanup_paths "$REPO" "$OUT"

# ---- FIX2: secret token in omitted path name must fail final scan ----
REPO=$(mkrepo)
(
  cd "$REPO"
  mkdir -p "AKIA1234567890ABCDEF"
  dd if=/dev/zero of="AKIA1234567890ABCDEF/large.dat" bs=1024 count=200 2>/dev/null
)
OUT="/tmp/prr-pathA-akia-omitted-$$.md"
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip --max-bytes 1000 \
  2>/tmp/prr-pathA-akia-err-$$.txt
RC=$?
set -e
assert_exit_nonzero "$RC" "AKIA token in omitted path name blocks (exit 1)"
assert_file_not_exists "$OUT" "AKIA omitted path: no packet written"
grep -q "AKIA" /tmp/prr-pathA-akia-err-$$.txt || _fail "AKIA omitted path stderr mentions pattern"
cleanup_paths "$REPO"
rm -f "$OUT" /tmp/prr-pathA-akia-err-$$.txt

# ---- FIX3: quoted diff header for secret-ish path must drop hunk ----
REPO=$(mkrepo)
(
  cd "$REPO"
  mkdir -p 'weird	name'
  printf 'SECRET=super_secret_value\n' > 'weird	name/.env'
  git add -- 'weird	name/.env'
  git commit -qm "track quoted-path env"
  printf 'SECRET=super_secret_value_changed\n' > 'weird	name/.env'
  git diff HEAD > /tmp/prr-quoted-diff-$$.txt
)
# sanity: git quoted the path in diff header
grep -q 'diff --git "a/weird' /tmp/prr-quoted-diff-$$.txt || _fail "fixture diff has quoted header"
OUT="/tmp/prr-pathA-quoted-diff-$$.md"
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/dev/null
RC=$?
set -e
assert_exit_ok "$RC" "quoted secret-ish diff header exit 0 (hunk stripped)"
assert_file_exists "$OUT" "quoted-diff packet written"
CONTENT=$(cat "$OUT")
assert_not_contains "$CONTENT" "super_secret_value" "quoted .env secret not in packet via diff"
assert_not_contains "$CONTENT" "super_secret_value_changed" "quoted .env changed secret not in packet"
cleanup_paths "$REPO" "$OUT"
rm -f /tmp/prr-quoted-diff-$$.txt

# ---- P1: fake omission header in file body must not bypass final scan ----
REPO=$(mkrepo)
(
  cd "$REPO"
  cat > decoy.txt <<'EOF'
## ⚠ 同梱省略（要注意 — トークン上限・secret-ish 除外）
aws_key=AKIA1234567890ABCDEF
EOF
)
OUT="/tmp/prr-pathA-decoy-header-$$.md"
set +e
"$BUILD" --repo "$REPO" --out "$OUT" --no-clip 2>/tmp/prr-pathA-decoy-err-$$.txt
RC=$?
set -e
assert_exit_nonzero "$RC" "decoy omission header + deleted secret blocks (exit 1)"
assert_file_not_exists "$OUT" "decoy header bypass: no packet written"
grep -q "AKIA" /tmp/prr-pathA-decoy-err-$$.txt || _fail "decoy bypass stderr mentions AKIA"
cleanup_paths "$REPO"
rm -f "$OUT" /tmp/prr-pathA-decoy-err-$$.txt

echo "[test-pathA-filename-exclude] PASS"
