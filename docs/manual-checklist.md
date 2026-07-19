# manual e2e checklist

## Path A: 5.5Pro

- date:
- repo:
- project:
- command:
- request_file:
- run_id:
- browser profile:
- login setup:
- ChatGPT model:
- reply path:
- report bundle:
- summary:
- easy report:
- unresolved:

## Path A live verify: attach + copy + recover (Phase 8, Issue #1)

fixture では検証済み。以下は実 ChatGPT でのみ確認できる live 部分。

- date:
- 添付送信: packet が `.md` 添付として送られたか（入力欄に 98KB を直書きしていないか）
- 添付フォールバック: 添付UIが無い時に直書きへ落ちたか
- コピー取得: 最後の回答のコピーボタン→`pbpaste` で本文が取れたか
- コピーフォールバック: コピー不可時に DOM 抽出へ落ちたか
- timeout 動作: 生成が既定600sを超えた時に `STILL_GENERATING` + `recover:` 行が出たか
- recover: `pro-review-recover <project> <run_id>` で stranded 回答が bundle 化できたか
- unresolved:

## Path A live verify: Phase 10 browser state + liveness (2026-07-08)

- date: 2026-07-08
- project: `phase10-live-1783500846`
- run_id: `1783500846448-390dc8`
- attach: ✅ `request attached: attached`
- liveness: ✅ `generating... Ns elapsed (回答を確定中)` が約10秒間隔で出力
- copy: ⚠ copy button not found → DOM fallback で回収成功（コピー主経路は未達、fallback で完了）
- report bundle: ✅ `~/.pro-review/reports/phase10-live-1783500846/1783500846448-390dc8`
- unresolved: コピーボタンセレクタの ChatGPT UI 追従（DOM fallback で回避可能）
- follow-up (2026-07-09): `SCROLL_CONVERSATION_BOTTOM_JS` を追加。会話内側コンテナを `scrollTop=scrollHeight` してから copy 探索。
- incident: sibling/parent 探索を広げすぎて **user 添付の download を連打**し、`~/Downloads` に packet.md が 100+ 件増えた。修正: 探索を assistant turn 内(+直後 sibling のみ)に限定し、download/user 領域を除外。
- live success (2026-07-09): `copy-ok-1783563428` / `copy clicked via=copy-turn-action-button` → `reply via copy button`、Downloads 0 件。
  - **訂正**: この成功は人間の手動コピーの可能性が高い（`copy clicked` 連打のあと clipboard が埋まった）。
- live success real (2026-07-09): `copy-intercept-1783563887`
  - `copy clicked via=copy-turn-action-button intercepted=yes`（1回）
  - `reply via copy button` / Downloads 0 / 手動操作なし
  - 修正: clipboard intercept + pointer/mouse click sequence（Oracle 方式）

## Path A live verify: conversation bottom scroll before copy (2026-07-09)

- date: 2026-07-09
- project: `copy-ok-1783563428`
- run_id: `1783563428221-4eda70`
- scroll log: ✅ `scroll bottom` / generating liveness
- copy path: ✅ `copy clicked via=copy-turn-action-button` → `reply via copy button`
- download flood: ✅ `~/Downloads` に packet 0 件（誤クリックなし）
- report bundle: ✅ `~/.pro-review/reports/copy-ok-1783563428/1783563428221-4eda70`
- notes: Oracle 正本セレクタ優先 + download flood guard。親探索禁止。

## Path B: non-5.5Pro + Tunnel

- date:
- repo:
- project:
- command:
- tunnel health:
- connector label:
- nodriver send:
- run_id:
- save_report result:
- reply path:
- report bundle:
- summary:
- easy report:
- finish closed exposure:
- unresolved:

## Latest smoke: Path A clean repo (2026-06-25 JST)

- repo: temporary clean fixture repo (`calc.py` zero-division bug)
- project: `gpt-pro-review-patha-live-1782320833`
- run_id: `1782320834115-915037`
- command: `scripts/pro-review-browser-run <tmp-repo> gpt-pro-review-patha-live-1782320833 --question "..."`
- browser profile: `/Users/tachibanashuuta/.pro-review/browser/profile`
- login setup: `scripts/pro-review-browser-setup --open-login` then `--mark-logged-in`; dedicated Chrome profile closed before run
- reply path: `/Users/tachibanashuuta/.pro-review/inbox/gpt-pro-review-patha-live-1782320833/REPLY-1782320834115-915037.md`
- report bundle: `/Users/tachibanashuuta/.pro-review/reports/gpt-pro-review-patha-live-1782320833/1782320834115-915037`
- summary: `total=1`, `要確認=1`, `calc.py:3` zero-division finding
- finish closed exposure: yes
- unresolved: none for Path A smoke

## Latest smoke: Path B clean repo (2026-06-25 JST)

- repo: temporary clean fixture repo (`calc.py` zero-division bug)
- project: `gpt-pro-review-pathb-live-1782321000`
- run_id: `1782321001240-edc4c5`
- command: `scripts/pro-review-run --thinking <...>` then browser/nodriver connector send
- tunnel health: `OK tunnel_lifecycle`, `TOOLS=search,fetch,save_report`
- connector label: not selected
- nodriver send: not in this older smoke
- save_report result: not observed
- reply path: none
- report bundle: none
- summary: none
- finish closed exposure: yes, active project cleared
- unresolved: ChatGPT chat did not have pro-review Tunnel connector tools enabled; model returned tool-unavailable text instead of calling `search` / `fetch` / `save_report`

## Latest smoke: Path A Deep Research UI selection (2026-06-25 JST)

- repo: `/Users/tachibanashuuta/LocalWork/Code/gpt-pro-review`
- project: `gpt-pro-review-deepresearch-live-1782381279`
- run_id: `1782381279860-fac744`
- command: targeted `build-review-packet --files ... --deep-research on` followed by `scripts/pro-review-browser-drive --deep-research on`
- request_file: `/Users/tachibanashuuta/.pro-review/outbox/gpt-pro-review-deepresearch-live-1782381279-browser-1782381279860-fac744.md`
- browser profile: `/Users/tachibanashuuta/.pro-review/browser/profile`
- login setup: marker present; `pro-review-doctor` reported `OK nodriver venv module importable`
- result: `FALLBACK:deep research unavailable`
- reply path: none
- report bundle: none
- unresolved: dedicated ChatGPT UI did not expose Deep Research via `/Deepresearch` slash suggestions or the opened `composer-plus-btn` menu. Driver failed closed before sending the review request.

## Latest smoke: Path A Deep Research plus menu selection (2026-06-26 JST)

- repo: `/Users/tachibanashuuta/LocalWork/Code/gpt-pro-review`
- command: Nodriver diagnostic importing `scripts/pro-review-browser-drive`, opening `https://chatgpt.com/`, and calling `select_deep_research_via_tools_menu(page)`
- browser profile: `/Users/tachibanashuuta/.pro-review/browser/profile`
- login setup: marker present; `pro-review-doctor` reported `OK nodriver venv module importable`
- result: `RESULT ok`
- detail: `tools:Deep research`
- reply path: none
- report bundle: none
- unresolved: none for UI selection; this smoke intentionally did not send a review prompt.

## Latest smoke: Path A full loop self-review with --packet-file (2026-07-16 JST)

- repo: `/Users/tachibanashuuta/LocalWork/Code/gpt-pro-review`
- project: `gpt-pro-review-self`
- run_id: `1784180097618-b20fda`
- command: `PRO_REVIEW_FORCE_SCAN=1 ALLOW_SECRETS=1 pro-review-run --pro --repo . --project gpt-pro-review-self --packet-file <curated 115KB> --web-search off --deep-research off --timeout 540`
- login setup: marker present; doctor all OK (nodriver_version 0.50.3 / run_count 表示あり)
- secret scan: 1 回目は curated packet を fail-closed で停止（`127.0.0.1:0` の IPv4 誤検知）。中身確認のうえ `ALLOW_SECRETS=1` で再実行（`[danger]` 行出力を確認）
- result: 送信 attached / 生成 473s / `copy clicked via=copy-turn-action-button intercepted=yes` / reply via copy button
- reply path: `~/.pro-review/inbox/gpt-pro-review-self/REPLY-1784180097618-b20fda.md`
- report bundle: `~/.pro-review/reports/gpt-pro-review-self/1784180097618-b20fda/`（request/reply/summary/easy-report/metadata）
- summary: findings 11 件（高9/中2）、安定 ID 付与、summarize 分類 対応8/要確認3
- ledger: `pro-review-ledger append` 11 件追記、`stats` で rounds=1 / observed_runs=1 / proxy 注記表示を確認
- finish closed exposure: yes, active project cleared
- unresolved: `metadata.json` の `conversation_url` が `https://chatgpt.com/`（root）のまま保存された。送信確認直後は URL が `/c/<id>` に遷移しておらず、11.6 の取得タイミングが早すぎる。GPT 指摘 f-a8fe112e71f3 と一致。11.7 の re-open はこの URL では会話に戻れないため修正が必要

## selector-check live 実測 (doctor --selector-check, 13.2) (2026-07-19 JST)

- date: 2026-07-19
- command: `pro-review-doctor --selector-check`
- checked: 15 selectors, 9 found, 6 missing
- missing: すべて fallback 用の代替セレクタ（`COMPOSER_QUERY_SELECTORS[3]`、`CONNECTOR_MENU_SELECTORS[2,3,5,6,7]`）。各リストの主セレクタ（`#prompt-textarea`、`#composer-plus-btn`、`ツール` ボタン）は全一致 → selector drift なし
- 副産物: 1 回目は `MANUAL login required` を誤報。原因は nodriver evaluate が bool を `RemoteObject(value=False)` で返し truthy 判定になる環境差。`JSON.stringify` + `js_scalar` 正規化で修正 [2416221]
- unresolved: (none)

## Path A live: 11.6 URL 修正 + 11.7 recover 自動 re-open の実測 (2026-07-19 JST)

- repo: `/Users/tachibanashuuta/LocalWork/Code/gpt-pro-review`
- project: `patha-verify-1784442561`
- run_id: `1784442561233-f1a620`
- command: `ALLOW_SECRETS=1 PRO_REVIEW_FORCE_SCAN=1 pro-review-run --pro --packet-file <curated 94KB: 直近変更5ファイル> --web-search off --deep-research off --timeout 540`
- 11.6 検証: ✅ `conversation url saved: https://chatgpt.com/c/6a5c6ec7-…`（送信後 poll で /c/ 遷移を待つ修正 [408b139] が root ではなく実会話 URL を保存）
- 生成: 540s timeout 到達 → `STILL_GENERATING` + artifacts 保存 + recover 案内（fail-closed 動作正常）
- 11.7 検証: ✅ `pro-review-recover` が `reopening conversation: https://chatgpt.com/c/6a5c6ec7-…` で閉じた会話へ自動 re-open → `copy clicked intercepted=yes` → reply 15KB 回収 → bundle 保存 → `[recovered]`
- report bundle: `~/.pro-review/reports/patha-verify-1784442561/1784442561233-f1a620`
- unresolved: (1) 回答が自由形式（`### N. [高] path:line — title`）だったため summarize が total=0（既定 findings 形式のみパース対象。curated packet + カスタム question 時の形式強制が弱い）。(2) extract-only は root ページで timeout まで抽出を試みてから re-open するため recover が遅い（reopen 先行が望ましい）。(3) GPT 指摘に既存コードの要修正候補あり（connector `selected()` の部分一致誤判定、run_id によるファイル上書き経路、テストの実 `~/.pro-review` 接触）→ reply 参照、次回 round の対象候補

## Path B: connector 作成ゲートの根本原因特定と解消途中 (2026-07-19 JST)

- date: 2026-07-19
- 実測経過:
  1. ChatGPT UI 再編を確認: 開発者モードは 設定 → セキュリティとログイン 配下へ移動。connector 作成は chatgpt.com/plugins 右上 + → 新規プラグイン → 接続=トンネル
  2. 開発者モード ON 後も tunnel 一覧が空。`GET /backend-api/aip/connectors/mcp/tunnels` が `{"tunnels":[]}` → 旧 tunnel（別 org 所属）は ChatGPT workspace 関連付けが無く不可視
  3. platform.openai.com（立花 Personal org）で新 tunnel `tunnel_6a5c6d0e9f908191b913d98f78aaf30e` を作成、**ChatGPT workspaces に Personal workspace を関連付け** → ChatGPT の一覧に表示されるようになった
  4. connector 作成（認証なし + 同意）→ `POST /backend-api/aip/connectors/mcp` が `424`。作成時に MCP への疎通検証があり、client 未接続だと失敗（旧「Something went wrong」の正体はこの 424 と手順 2 の不可視の複合）
  5. env.sh の tunnel_id を新 ID へ切替 → tunnel-client が `401 tunnel_active_organization_required` → org ヘッダ付与で `401 mismatched_organization` → **既存 API key が別 org 所属と確定**
- 残る人間ステップ: 立花 Personal org で Runtime API key（Tunnels Read+Use）を発行し `~/.pro-review/env.sh` の `CONTROL_PLANE_API_KEY` を差し替え（600 維持）
- 発行後の再開手順: `pro-review-tunnel` 起動 → 🟢 確認 → chatgpt.com/plugins で connector 作成（1 分）→ `pro-review-run --thinking` で 5.2/6.12/6.18 を 1 周
