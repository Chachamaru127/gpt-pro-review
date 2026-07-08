# HANDOFF — gpt-pro-review

更新: 2026-07-08
CWD: `/Users/tachibanashuuta/LocalWork/Code/gpt-pro-review`

## 結論

Phase 10（Cursor + Oracle sync + browser state）完了。fixture/docs gate `pass=30 fail=0`。実機 Path A live e2e も 2026-07-08 に通過。Path B は ChatGPT 側 app creation gate が残存。

## 現在の完成ライン

- Path A: `pro-review-run --pro` で `browser-embed -> browser-drive -> save-reply -> watch -> finish` が fixture + live 済み。
- Path B: `pro-review-run --thinking` で tunnel/check → nodriver connector → watch → finish。`save_report` 設計は fixture 済み。
- Phase 10: Cursor コマンド/スキル、`BROWSER_STATE`/`browser_state:`、liveness log、Oracle 採用パターン取り込み済み。
- 返信採用: `REPLY-<run_id>.md` + 最終行 `[[DONE-<run_id>]]` 完全一致のみ。
- report bundle: `reports/<project>/<run_id>/` に request/reply/summary/easy-report/metadata。
- safety: default MCP は `search` / `fetch` / `save_report` のみ。

## 検証済み

- `bash tests/run-all.sh` PASS（pass=30 fail=0、2026-07-08）
- `scripts/pro-review-doctor` OK
- Path A live Phase 10: project `phase10-live-1783500846`, run_id `1783500846448-390dc8`
  - attach ✅ / liveness ✅ / copy→DOM fallback ✅ / report bundle ✅
- Path A live 過去 smoke: `gpt-pro-review-patha-live-1782320833` 成功済み
- Path B: tunnel `TOOLS=search,fetch,save_report` OK。ChatGPT app creation は `Something went wrong` で未通過

## 次にやること

1. **9.2 `--packet-file`**: curated packet 直接投入（Plans.md cc:TODO）
2. **Path B live (6.18)**: ChatGPT Business/workspace 権限で app creation を通す
3. **コピーボタンセレクタ**: ChatGPT UI 変更への追従（現状 DOM fallback で回避可能）
4. **recover 会話 URL**: 自動 re-open 未実装（Oracle `recoverConversation.ts` 候補）

## 未完了 gate

- 6.18: Path B ChatGPT app creation / live e2e
- 9.2: `--packet-file` curated packet

## 最短コマンド

```bash
scripts/pro-review-doctor
scripts/pro-review-run --pro --repo "$(pwd)" --project my-review --question "bug と security を見て"
# timeout 後:
scripts/pro-review-recover my-review <run_id>
```
