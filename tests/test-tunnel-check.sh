#!/usr/bin/env bash
# 6.11: tunnel lifecycle UX checks.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

CHK="$(repo_scripts_dir)/pro-review-tunnel-check"
[ -x "$CHK" ] || _fail "pro-review-tunnel-check not executable: $CHK"

echo "[test-tunnel-check] start"

TMP_HOME=$(mktemp -d -t prr-tunnel-check-home-XXXXXX)
HPID=""
trap 'if [ -n "$HPID" ]; then kill "$HPID" 2>/dev/null || true; wait "$HPID" 2>/dev/null || true; fi; cleanup_paths "$TMP_HOME"' EXIT
PROJECT="tun-$$"
mkdir -p "$TMP_HOME/.pro-review/workspace/$PROJECT" "$TMP_HOME/.pro-review/inbox/$PROJECT"
echo "x" > "$TMP_HOME/.pro-review/workspace/$PROJECT/a.txt"

set +e
OUT=$(HOME="$TMP_HOME" "$CHK" "$PROJECT" 2>&1)
RC=$?
set -e
assert_exit_nonzero "$RC" "T1 no active project rejected"
assert_contains "$OUT" "STOP_REASON=no_active_project" "T1 no active reason"

mkdir -p "$TMP_HOME/.pro-review"
printf 'other\n' > "$TMP_HOME/.pro-review/active-project"
set +e
OUT=$(HOME="$TMP_HOME" "$CHK" "$PROJECT" 2>&1)
RC=$?
set -e
assert_exit_nonzero "$RC" "T2 stale active rejected"
assert_contains "$OUT" "STOP_REASON=stale_active_project" "T2 stale reason"
assert_contains "$OUT" "NEXT_ACTION=" "T2 next action"

printf '%s\n' "$PROJECT" > "$TMP_HOME/.pro-review/active-project"
set +e
OUT=$(HOME="$TMP_HOME" PRO_REVIEW_TUNNEL_DOCTOR_FAIL=1 "$CHK" "$PROJECT" 2>&1)
RC=$?
set -e
assert_exit_nonzero "$RC" "T3 doctor fail rejected"
assert_contains "$OUT" "STOP_REASON=doctor_failed" "T3 doctor reason"

set +e
OUT=$(HOME="$TMP_HOME" "$CHK" "$PROJECT" 2>&1)
RC=$?
set -e
assert_exit_nonzero "$RC" "T4 no health rejected"
assert_contains "$OUT" "STOP_REASON=tunnel_not_running" "T4 health reason"

PORT_FILE="$TMP_HOME/health.port"
READY_FILE="$TMP_HOME/tunnel.ready"
python3 - "$PORT_FILE" "$READY_FILE" <<'PY' &
import http.server, socketserver, sys
from pathlib import Path

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/readyz" and not Path(sys.argv[2]).exists():
            self.send_response(503)
            self.end_headers()
            self.wfile.write(b"not ready")
            return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")
    def log_message(self, *args):
        pass

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    Path(sys.argv[1]).write_text(str(httpd.server_address[1]))
    httpd.serve_forever()
PY
HPID=$!
for _ in 1 2 3 4 5; do
  [ -s "$PORT_FILE" ] && break
  sleep 0.2
done
[ -s "$PORT_FILE" ] || _fail "T5 health fixture did not start"
printf 'http://127.0.0.1:%s\n' "$(cat "$PORT_FILE")" > "$TMP_HOME/.pro-review/health.url"

set +e
OUT=$(HOME="$TMP_HOME" PRO_REVIEW_READY_TIMEOUT=0 "$CHK" "$PROJECT" 2>&1)
RC=$?
set -e
assert_exit_nonzero "$RC" "T5 live but not ready rejected"
assert_contains "$OUT" "STOP_REASON=tunnel_not_ready" "T5 ready reason"

touch "$READY_FILE"
OUT=$(HOME="$TMP_HOME" "$CHK" "$PROJECT")
assert_exit_ok "$?" "T6 lifecycle OK"
assert_contains "$OUT" "OK tunnel_lifecycle" "T6 OK output"
assert_contains "$OUT" "save_report" "T6 save_report available"

OUT=$(HOME="$TMP_HOME" PRO_REVIEW_READONLY=1 "$CHK" "$PROJECT")
assert_exit_ok "$?" "T7 readonly lifecycle OK"
assert_contains "$OUT" "MODE=readonly" "T7 readonly mode"
assert_contains "$OUT" "TOOLS=search,fetch" "T7 readonly tools"
assert_not_contains "$OUT" "save_report" "T7 readonly hides save_report"

echo "[test-tunnel-check] PASS"
