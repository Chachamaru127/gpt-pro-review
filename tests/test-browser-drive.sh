#!/usr/bin/env bash
# 6.7: pro-review-browser-drive fixture-first extraction/fallback contract.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_assert.sh
source "$SCRIPT_DIR/_assert.sh"

DRV="$(repo_scripts_dir)/pro-review-browser-drive"
[ -x "$DRV" ] || _fail "pro-review-browser-drive not executable: $DRV"

echo "[test-browser-drive] start"

TMP=$(mktemp -d -t prr-browser-drive-XXXXXX)
trap 'cleanup_paths "$TMP"' EXIT
RID="1700000000123-aabbcc"

SUCCESS="$TMP/success.html"
cat > "$SUCCESS" <<EOF
<main>
  <div data-message-author-role="user">review this</div>
  <div data-message-author-role="assistant">
    <p>結論: バグなし</p>
    <p>[[DONE-$RID]]</p>
  </div>
</main>
EOF
OUT=$("$DRV" --fixture-html "$SUCCESS" --run-id "$RID")
assert_exit_ok "$?" "T1 success exit"
assert_contains "$OUT" "結論: バグなし" "T1 body extracted"
assert_contains "$OUT" "[[DONE-$RID]]" "T1 marker extracted"

MID="$TMP/mid.html"
cat > "$MID" <<EOF
<div data-message-author-role="assistant">
  <p>[[DONE-$RID]]</p>
  <p>これはまだ途中</p>
</div>
EOF
set +e
"$DRV" --fixture-html "$MID" --run-id "$RID" >/tmp/prr-drive-mid-$$.out 2>/tmp/prr-drive-mid-$$.err
RC=$?
set -e
assert_exit_nonzero "$RC" "T2 middle marker rejected"
assert_contains "$(cat /tmp/prr-drive-mid-$$.err)" "final line" "T2 final line error"
rm -f /tmp/prr-drive-mid-$$.out /tmp/prr-drive-mid-$$.err

STOP="$TMP/stop.html"
cat > "$STOP" <<EOF
<button aria-label="Stop generating">Stop</button>
<div data-message-author-role="assistant"><p>partial</p></div>
EOF
set +e
OUT=$("$DRV" --fixture-html "$STOP" --run-id "$RID" 2>/dev/null)
RC=$?
set -e
assert_eq "3" "$RC" "T3 stop visible fallback"
assert_contains "$OUT" "FALLBACK:response still generating" "T3 fallback reason"

LOGIN="$TMP/login.html"
cat > "$LOGIN" <<EOF
<button data-testid="login-button">Log in</button>
EOF
set +e
OUT=$("$DRV" --fixture-html "$LOGIN" --run-id "$RID" 2>/dev/null)
RC=$?
set -e
assert_eq "3" "$RC" "T4 login fallback"
assert_contains "$OUT" "FALLBACK:login required" "T4 fallback reason"

EMPTY="$TMP/empty.html"
printf '<main></main>\n' > "$EMPTY"
set +e
OUT=$("$DRV" --fixture-html "$EMPTY" --run-id "$RID" --timeout 0.1 2>/dev/null)
RC=$?
set -e
assert_eq "3" "$RC" "T5 missing reply fallback"
assert_contains "$OUT" "FALLBACK:assistant reply not found" "T5 fallback reason"

ATTR_LOGIN="$TMP/attr-login.html"
cat > "$ATTR_LOGIN" <<'EOF'
<main data-auth-state="login-ok">
  <div id="prompt-textarea" contenteditable="true"></div>
  <script>const text = "log in copy exists in bundle";</script>
</main>
EOF
set +e
OUT=$( "$DRV" --fixture-html "$ATTR_LOGIN" --run-id "$RID" --timeout 0.1 2>/dev/null)
RC=$?
set -e
assert_eq "3" "$RC" "T5b non-login attr fallback"
assert_contains "$OUT" "FALLBACK:assistant reply not found" "T5b attr login is not login gate"

TMP_HOME=$(mktemp -d -t prr-browser-drive-home-XXXXXX)
REQ="$TMP/request.md"
printf 'review this\n' > "$REQ"
set +e
OUT=$(HOME="$TMP_HOME" "$DRV" --request-file "$REQ" --run-id "$RID" --timeout 0.1 2>/dev/null)
RC=$?
set -e
assert_eq "3" "$RC" "T6 live without login marker fallback"
assert_contains "$OUT" "FALLBACK:login required" "T6 login marker gate"

python3 - "$DRV" <<'PY'
import importlib.machinery
import sys
mod = importlib.machinery.SourceFileLoader("pro_review_browser_drive", sys.argv[1]).load_module()
assert mod.classify_live_error(Exception("user data directory is already in use")) == "browser profile already open"
assert mod.classify_live_error(Exception("other failure")) == "live browser error"
PY
assert_exit_ok "$?" "T7 profile lock classified"

python3 - "$DRV" <<'PY'
import importlib.machinery
import os
import sys
mod = importlib.machinery.SourceFileLoader("pro_review_browser_drive_reexec", sys.argv[1]).load_module()
calls = []
mod.live_paths = lambda: {"venv_python": "/tmp/prr-venv/bin/python"}
mod.os.path.exists = lambda path: True
mod.sys.executable = "/usr/local/bin/python3"
mod.sys.argv = ["pro-review-browser-drive", "--request-file", "x", "--run-id", "r"]
def fake_execv(path, argv):
    calls.append((path, argv, os.environ.get("PRO_REVIEW_BROWSER_REEXEC")))
    raise SystemExit(42)
mod.os.execv = fake_execv
try:
    mod.ensure_live_python()
except SystemExit as exc:
    assert exc.code == 42
assert calls and calls[0][0] == "/tmp/prr-venv/bin/python"
assert calls[0][2] == "1"
PY
assert_exit_ok "$?" "T8 nodriver venv reexec uses venv path"

python3 - "$DRV" <<'PY'
import importlib.machinery
import sys
mod = importlib.machinery.SourceFileLoader("pro_review_browser_drive_policy", sys.argv[1]).load_module()
normal = """# Review

## レビュー観点
bug と security を見て

## ChatGPT ツール利用方針

- deep_research: `auto`
"""
current = """# Review

## レビュー観点
最新CVEと公式ドキュメントを横断して確認して

## ChatGPT ツール利用方針

- deep_research: `auto`
"""
explicit = "- deep_research: `on`\n"
assert mod.parse_deep_research_policy(explicit) == "on"
assert mod.decide_deep_research_selection("on", normal)[0] is True
assert mod.decide_deep_research_selection("off", current)[0] is False
assert mod.decide_deep_research_selection("auto", normal)[0] is False
assert mod.decide_deep_research_selection("auto", current)[0] is True
assert mod.js_object({"ok": True}) == {"ok": True}
assert mod.js_object('{"ok": true, "label": "Deep Research"}')["ok"] is True
class Obj:
    pass
remote = Obj()
remote.deep_serialized_value = Obj()
remote.deep_serialized_value.value = [["ok", {"type": "boolean", "value": True}], ["label", {"type": "string", "value": "Deep Research"}]]
assert mod.js_object(remote) == {"ok": True, "label": "Deep Research"}
# validate_reply tolerance: DOM抽出の末尾ゆらぎ(空行/コードフェンス/バッククォート/末尾空白)を
# 許容しつつ、マーカーが最終内容行であることの完了検知は維持する。
_rid = "1700000000123-aabbcc"
_M = f"[[DONE-{_rid}]]"
assert mod.validate_reply(f"x\n{_M}", _rid)
assert mod.validate_reply(f"x\n{_M}\n\n", _rid)
assert mod.validate_reply(f"x\n```\n{_M}\n```", _rid)
assert mod.validate_reply(f"x\n`{_M}`", _rid)
assert mod.validate_reply(f"x\n{_M}   ", _rid)
for _bad in (f"{_M}\nstill going", "no marker here", f"{_M}\nx\n{_M}"):
    try:
        mod.validate_reply(_bad, _rid)
    except ValueError:
        continue
    raise AssertionError("validate_reply should reject: " + repr(_bad))
src = open(sys.argv[1], encoding="utf-8").read()
assert "deepreseach" in src
assert "composer-plus-btn" in src
PY
assert_exit_ok "$?" "T9 deep research policy decision"

OUT=$("$DRV" --fixture-html "$SUCCESS" --run-id "$RID" --deep-research on)
assert_exit_ok "$?" "T10 fixture accepts deep research flag"
assert_contains "$OUT" "[[DONE-$RID]]" "T10 fixture still extracts marker"

CONN="$TMP/connector.html"
cat > "$CONN" <<'EOF'
<main>
  <button id="composer-plus-btn" aria-label="Tools">+</button>
  <div role="menuitemcheckbox" aria-checked="true" aria-label="pro-review Tunnel connector">pro-review Tunnel connector</div>
  <div id="prompt-textarea" contenteditable="true"></div>
  <button data-testid="send-button" aria-label="Send message">Send</button>
</main>
EOF
OUT=$("$DRV" --fixture-html "$CONN" --mode connector --send-only --request-file "$REQ" --run-id "$RID" --connector-label "pro-review Tunnel connector")
assert_exit_ok "$?" "T11 connector fixture send"
assert_contains "$OUT" "sent: connector" "T11 connector sent line"
assert_contains "$OUT" "connector_label: pro-review Tunnel connector" "T11 connector label line"

NO_CONN="$TMP/no-connector.html"
cat > "$NO_CONN" <<'EOF'
<main>
  <button id="composer-plus-btn" aria-label="Tools">+</button>
  <div id="prompt-textarea" contenteditable="true"></div>
</main>
EOF
set +e
OUT=$("$DRV" --fixture-html "$NO_CONN" --mode connector --send-only --request-file "$REQ" --run-id "$RID" --connector-label "pro-review Tunnel connector" 2>/dev/null)
RC=$?
set -e
assert_eq "3" "$RC" "T12 connector missing stops"
assert_contains "$OUT" "STOP_REASON=connector_unavailable" "T12 connector stop reason"

python3 - "$DRV" <<'PY'
import importlib.machinery
import sys
mod = importlib.machinery.SourceFileLoader("pro_review_browser_drive_connector", sys.argv[1]).load_module()
src = open(sys.argv[1], encoding="utf-8").read()
assert mod.DEFAULT_CONNECTOR_LABEL == "pro-review Tunnel connector"
assert "select_connector_mode" in src
assert "STOP_REASON=connector_unavailable" in src
assert "--send-only" in src
PY
assert_exit_ok "$?" "T13 connector mode source contract"

echo "[test-browser-drive] PASS"
