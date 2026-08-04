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
assert_contains "$OUT" "BROWSER_STATE_SUMMARY:" "T3 browser state summary"
assert_contains "$OUT" "generating" "T3 browser state shows generating"

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
import builtins
import importlib.machinery
import os
import sys
mod = importlib.machinery.SourceFileLoader("pro_review_browser_drive_reexec", sys.argv[1]).load_module()
calls = []
real_import = builtins.__import__

def fake_import(name, globals=None, locals=None, fromlist=(), level=0):
    if name == "nodriver":
        raise ImportError("forced for test")
    return real_import(name, globals, locals, fromlist, level)

builtins.__import__ = fake_import
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
assert mod.is_answer_now_placeholder("Pro thinking Answer now")
assert not mod.is_answer_now_placeholder("final review text")
assert mod.summarize_browser_state({"generating": True, "assistantTurns": 1, "status": "thinking"}) == "generating; thinking; assistant=1"
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

python3 - "$DRV" <<'PY'
import importlib.machinery
import sys
mod = importlib.machinery.SourceFileLoader("pro_review_browser_drive_scroll", sys.argv[1]).load_module()
scroll = mod.SCROLL_CONVERSATION_BOTTOM_JS
copy = mod.COPY_LAST_REPLY_JS
src = open(sys.argv[1], encoding="utf-8").read()
# 内側スクロールコンテナを最下部へ（window.scrollTo だけでは不足）
assert "scrollTop" in scroll and "scrollHeight" in scroll
assert "overflowY" in scroll
assert "chat-thread" in scroll
# コピー探索は sibling アクションバーまで広げるが、親/user 添付は触らない
assert "nextElementSibling" in copy
assert "scrollIntoView" in copy
assert "copy-turn-action-button" in copy  # Oracle 正本セレクタ
assert "download" in copy  # downloadish 除外
assert 'data-message-author-role="user"' in copy
assert "dispatchClickSequence" in copy
assert "clipboard.writeText" in copy or "clipboard.writeText =" in copy
assert "intercepted" in copy
assert "親へ広げると" in src or "parentElement まで広げると" in src
assert "scopes.push(article.parentElement)" not in copy
# extract_via_copy がスクロール→待機→コピーの順
assert "SCROLL_CONVERSATION_BOTTOM_JS" in src
assert "scroll bottom:" in src
assert "download flood" in src
assert "count_download_matches" in src
assert "intercepted" in src
assert "pbpaste fallback" in src
# サイドバーの「レビュー依頼停止」のような会話名を生成停止ボタンと誤認しない。
assert "/stop generating|停止|" not in src
assert "stop-button|stop-generation|stop-response" in src
assert "ストリーミングを停止|停止)$" in src
extract = src[src.index("async def extract_via_copy") : src.index("async def extract_via_dom")]
assert extract.index("SCROLL_CONVERSATION_BOTTOM_JS") < extract.index("COPY_LAST_REPLY_JS")
assert "await page.sleep(0.4)" in extract
assert 'clicked.get("markdown")' in extract or "clicked.get('markdown')" in extract
# 回帰: parent 探索で download 連打した事故を再発させない
copy_block = src[src.index("COPY_LAST_REPLY_JS") : src.index("IS_GENERATING_JS")]
assert "scopes.push(article.parentElement)" not in copy_block
# download guard unit
assert mod.count_download_matches("") == 0
assert mod.download_guard_stem("/tmp/foo/bar-packet.md") == "bar-packet"
PY
assert_exit_ok "$?" "T14 conversation bottom scroll before copy"

python3 - "$DRV" <<'PY'
import importlib.machinery
import inspect
import sys

mod = importlib.machinery.SourceFileLoader(
    "pro_review_browser_drive_connector_ui", sys.argv[1]
).load_module()
label = "pro-review Tunnel connector"
assert mod.connector_search_prefix(label) == "pro-review T"
assert mod.connector_mention_query(label) == "pro-review"
assert mod.connector_search_prefix("  ") == ""

pill_js = mod.connector_pill_verify_js(label)
search_js = mod.connector_search_click_js(label)
assert "data-inline-selection-pill-cursor-target" in pill_js
assert "dispatchClickSequence" in search_js
assert "connector search result not found" in search_js

sig = inspect.signature(mod.select_connector_mode)
assert list(sig.parameters) == ["page", "label", "timeout"]

src = open(sys.argv[1], encoding="utf-8").read()
fn_start = src.index("async def select_connector_mode")
fn_end = src.index("async def select_deep_research_via_slash", fn_start)
fn_body = src[fn_start:fn_end]
assert "select_connector_via_menu_search" in fn_body
assert "select_connector_via_mention" in fn_body
assert "verify_connector_pill" in fn_body
assert "click_connector_candidate" in fn_body
assert fn_body.index("select_connector_via_mention") < fn_body.index(
    "select_connector_via_menu_search"
)
assert fn_body.index("select_connector_via_menu_search") < fn_body.index(
    "click_connector_candidate"
)
assert "connector attempt" in fn_body
assert "attempts[-4:]" not in fn_body
search_start = src.index("async def select_connector_via_menu_search")
search_end = src.index("async def is_connector_selected", search_start)
search_body = src[search_start:search_end]
assert "send_keys_to_active_page" in search_body
assert "focus_connector_menu_search" in search_body
assert 'if not focused.get("ok"):' in search_body
assert 'selected_label = clicked.get("label") or label' in search_body
assert "verify_connector_pill(page, selected_label)" in search_body
assert "editor.click()" not in search_body
assert "editor.send_keys(prefix)" not in search_body
menu_start = src.index("async def click_connector_menu_candidate")
menu_end = src.index("async def select_connector_mode", menu_start)
menu_body = src[menu_start:menu_end]
assert "dispatchClickSequence" in menu_body
assert "await page.select_all" in menu_body
assert "nodriver:work-plugin:" in menu_body
assert "await page.select" in menu_body
assert "await element.click_mouse()" in menu_body
assert "el.click()" not in menu_body
assert "async def select_chat_surface" in src
assert "Chat surface:" in src
connector_mode_start = src.index('if args.mode == "connector"')
connector_mode_end = src.index('else:', connector_mode_start)
connector_mode_body = src[connector_mode_start:connector_mode_end]
assert connector_mode_body.index("await select_chat_surface(page)") < connector_mode_body.index(
    "await select_connector_mode("
)
assert connector_mode_body.index("await clear_prompt(page)") < connector_mode_body.index(
    "await select_connector_mode("
)
assert "menu_rounds < 3" in fn_body
assert "fill_prompt_preserve_pill" in src
assert "SEND_KEYS_MAX_CHARS" in src
connector_failure = src[
    src.index('if not selected:', src.index('if args.mode == "connector"'))
    : src.index('connector selected:', src.index('if args.mode == "connector"'))
]
assert "await save_diagnostic_artifacts_async()" in connector_failure
PY
assert_exit_ok "$?" "T15 connector search path source contract"

if command -v node >/dev/null 2>&1; then
  JS_BUNDLE=$(python3 - "$DRV" <<'PY'
import importlib.machinery
import sys
mod = importlib.machinery.SourceFileLoader(
    "pro_review_browser_drive_connector_js", sys.argv[1]
).load_module()
label = "pro-review Tunnel connector"
print(mod.connector_pill_verify_js(label))
print(mod.connector_search_click_js(label))
PY
  )
  assert_exit_ok "$?" "T16 connector JS render"
  printf '%s\n' "$JS_BUNDLE" | node --check
  assert_exit_ok "$?" "T16 connector JS passes node --check"

  PILL_JS=$(python3 - "$DRV" <<'PY'
import importlib.machinery
import sys
mod = importlib.machinery.SourceFileLoader(
    "pro_review_browser_drive_pill_js", sys.argv[1]
).load_module()
print(mod.connector_pill_verify_js("pro-review Tunnel connector"))
PY
)
  assert_exit_ok "$?" "T17 pill verify JS render"

  # T17: pill 検証 JS は composer 内の pill マーカーと connector ラベル文字列の
  # 両方を要求する。DOM 実行は jsdom 不要の範囲で fixture の構造と JS 条件を照合する。
  PILL_WITH=$(cat <<'EOF'
<div id="prompt-textarea" class="ProseMirror" contenteditable="true">
  <span data-inline-selection-pill-cursor-target aria-hidden="true" contenteditable="false"></span>
  <span contenteditable="false">pro-review Tunnel connector</span>
  review this
</div>
EOF
)
  PILL_WITHOUT=$(cat <<'EOF'
<div id="prompt-textarea" class="ProseMirror" contenteditable="true">review this</div>
EOF
)
  assert_contains "$PILL_WITH" "data-inline-selection-pill-cursor-target" "T17 positive fixture has pill marker"
  assert_contains "$PILL_WITH" "pro-review Tunnel connector" "T17 positive fixture has connector label"
  assert_not_contains "$PILL_WITHOUT" "data-inline-selection-pill-cursor-target" "T17 negative fixture lacks pill marker"
  assert_contains "$PILL_JS" "hasPill && hasLabel" "T17 pill verify requires pill and label"
  PILL_EVAL=$(PILL_HTML="$PILL_WITH" node -e "
const html = process.env.PILL_HTML || '';
const wanted = 'pro-review tunnel connector';
const text = html.replace(/<[^>]+>/g, ' ').replace(/\\s+/g, ' ').trim().toLowerCase();
const hasPill = html.includes('data-inline-selection-pill-cursor-target');
const hasLabel = text.includes(wanted);
if (!(hasPill && hasLabel)) process.exit(2);
" 2>/dev/null) || PILL_EVAL_RC=$?
  assert_exit_ok "${PILL_EVAL_RC:-0}" "T17 positive fixture satisfies pill+label predicate"
  set +e
  PILL_HTML="$PILL_WITHOUT" node -e "
const html = process.env.PILL_HTML || '';
const wanted = 'pro-review tunnel connector';
const text = html.replace(/<[^>]+>/g, ' ').replace(/\\s+/g, ' ').trim().toLowerCase();
const hasPill = html.includes('data-inline-selection-pill-cursor-target');
const hasLabel = text.includes(wanted);
if (hasPill && hasLabel) process.exit(3);
" >/dev/null 2>&1
  NEG_RC=$?
  set -e
  assert_exit_ok "$NEG_RC" "T17 negative fixture fails pill+label predicate"
else
  _fail "T16 node required for connector JS syntax validation"
fi

# T18 (14.1): selected() は完全一致のみ true。"unchecked" が "checked" を部分文字列に
# 含む・"not-selected" が "selected" を部分文字列に含むケースで誤検出しないこと。
# 全成功経路で pill 再検証(verify_connector_pill)を必須化したことも構造で確認する。
python3 - "$DRV" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
# 旧: 部分一致 regex が selected() 側に残っていないこと(2箇所とも)
assert "/true|checked|selected|on/" not in src
# 新: aria-* は === 'true' のみ、data-state は許可値との完全一致のみ
assert src.count("=== 'true'") >= 6  # aria-checked/aria-selected/aria-pressed x 2箇所
assert "['checked', 'selected', 'on', 'active'].includes" in src

fn_start = src.index("async def select_connector_mode")
fn_end = src.index("async def select_deep_research_via_slash", fn_start)
fn_body = src[fn_start:fn_end]
# 全成功経路(pill検出 / already-selected / visible / menu-selected / menu-click)で
# pill 再検証が入っていること。pill検出自体を含め計5箇所以上 verify_connector_pill を参照。
assert fn_body.count("verify_connector_pill") >= 5
assert "already-selected" in fn_body
assert "visible:" in fn_body
PY
assert_exit_ok "$?" "T18 selected() exact match + pill reverify source contract"

if command -v node >/dev/null 2>&1; then
  # selected() の状態判定ロジックを fixture 属性値に対して評価する。
  # el.closest は自身を返すだけで足りる(traversal は別関心事、ここでは状態判定のみ検証)。
  SELECTED_EVAL=$(node -e "
const selected = (attrs) => {
  const el = { getAttribute: (k) => (k in attrs ? attrs[k] : null) };
  const target = el;
  const ariaChecked = target.getAttribute('aria-checked');
  const ariaSelected = target.getAttribute('aria-selected');
  const ariaPressed = target.getAttribute('aria-pressed');
  const dataState = (target.getAttribute('data-state') || '').toLowerCase();
  return ariaChecked === 'true' || ariaSelected === 'true' || ariaPressed === 'true' ||
    ['checked', 'selected', 'on', 'active'].includes(dataState);
};
const cases = [
  [{ 'data-state': 'unchecked' }, false],
  [{ 'data-state': 'not-selected' }, false],
  [{ 'data-state': 'checked' }, true],
  [{ 'data-state': 'selected' }, true],
  [{ 'data-state': 'on' }, true],
  [{ 'data-state': 'active' }, true],
  [{ 'aria-checked': 'true' }, true],
  [{ 'aria-checked': 'false' }, false],
  [{ 'aria-pressed': 'true' }, true],
  [{}, false],
];
for (const [attrs, want] of cases) {
  const got = selected(attrs);
  if (got !== want) {
    console.error('mismatch: ' + JSON.stringify(attrs) + ' got=' + got + ' want=' + want);
    process.exit(1);
  }
}
" 2>&1) || SELECTED_EVAL_RC=$?
  assert_exit_ok "${SELECTED_EVAL_RC:-0}" "T18 selected() predicate: unchecked/not-selected false, checked/selected/on/active true ($SELECTED_EVAL)"
else
  _fail "T18 node required for selected() predicate validation"
fi

# T19 (14.4): --run-id 共通検証。path-safe [A-Za-z0-9._-]+、"."/".." 拒否、
# 先頭 "-"/"." 拒否。CLI 経路(main 冒頭で即 exit 2)と、outbox パス生成
# (conversation_url_outbox_path 経由の read/write 双方)の二層で拒否する。
T19_I=0
for BAD_RID in '../../etc/passwd' 'a/b' '.hidden' '-foo' '.' '..'; do
  T19_I=$((T19_I + 1))
  # マーカーを BAD_RID に合わせた fixture を都度作る。run_id 検証が抜けていると
  # マーカーが一致して抽出成功(exit 0)してしまうため、これで真に検証ゲートを Red 化できる。
  BAD_FIX="$TMP/badrid-$T19_I.html"
  printf '<main><div data-message-author-role="assistant"><p>x</p><p>[[DONE-%s]]</p></div></main>\n' "$BAD_RID" > "$BAD_FIX"
  set +e
  # "-foo" は argparse 自体がオプション風とみなすため --run-id=BAD_RID 形式で値として渡す
  OUT=$("$DRV" --fixture-html "$BAD_FIX" "--run-id=$BAD_RID" 2>&1)
  RC=$?
  set -e
  assert_eq "2" "$RC" "T19 CLI rejects run_id '$BAD_RID'"
  assert_contains "$OUT" "invalid run_id" "T19 CLI rejects run_id '$BAD_RID' with clear reason"
done

TMP_HOME19=$(mktemp -d -t prr-browser-drive-runid-XXXXXX)
HOME="$TMP_HOME19" python3 - "$DRV" <<'PY'
import importlib.machinery
import os
import sys

mod = importlib.machinery.SourceFileLoader("pro_review_browser_drive_runid", sys.argv[1]).load_module()

# write 経路: 不正 run_id は outbox パスを作らない(persist は None を返す)
for bad in ("../../etc/passwd", "a/b", ".hidden", "-foo", ".", ".."):
    assert mod.conversation_url_outbox_path(bad) is None, f"outbox path should reject {bad!r}"
    assert mod.persist_conversation_url(bad, "https://chatgpt.com/c/x") is None, (
        f"persist should reject run_id {bad!r}"
    )

# read 経路: 不正 run_id は既存ファイルの有無に関わらず None
for bad in ("../../etc/passwd", "a/b", ".hidden", "-foo"):
    assert mod.load_persisted_conversation_url(bad) is None, f"load should reject {bad!r}"
    assert mod.resolve_reopen_conversation_url(bad) is None, f"resolve should reject {bad!r}"

# 正常系は引き続き通る
good = "1700000000123-runid19"
assert mod.persist_conversation_url(good, "https://chatgpt.com/c/ok") == "https://chatgpt.com/c/ok"
assert mod.load_persisted_conversation_url(good) == "https://chatgpt.com/c/ok"

# 既存 symlink は read/write 双方拒否(先勝ちで置かれた symlink 経由の誤動作防止)
sym_rid = "1700000000123-symlink19"
outbox = os.path.expanduser("~/.pro-review/outbox")
os.makedirs(outbox, exist_ok=True)
target = os.path.join(outbox, "elsewhere.txt")
with open(target, "w", encoding="utf-8") as f:
    f.write("https://evil.example.com/c/x\n")
sym_path = os.path.join(outbox, f"conversation-url-{sym_rid}")
os.symlink(target, sym_path)
assert mod.conversation_url_outbox_path(sym_rid) is None, "symlink outbox path must be rejected"
assert mod.load_persisted_conversation_url(sym_rid) is None, "symlink read must be rejected"
assert mod.persist_conversation_url(sym_rid, "https://chatgpt.com/c/y") is None, (
    "symlink write must be rejected"
)
PY
assert_exit_ok "$?" "T19 conversation_url_outbox_path read/write reject traversal + symlink"
cleanup_paths "$TMP_HOME19"

echo "[test-browser-drive] PASS"
