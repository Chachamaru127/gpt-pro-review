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
