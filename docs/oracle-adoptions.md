# Oracle → gpt-pro-review adoptions

Oracle（`../oracle`）は ChatGPT/Gemini ブラウザ automation の成熟実装。gpt-pro-review Path A は **同じ問題空間**（Pro 長時間生成・DOM 変動・recover）を bash/python nodriver で扱うため、挙動パターンだけを選択的に取り込む。

同期: `bash scripts/sync-oracle-reference.sh` → `vendor/oracle/SYNCED_COMMIT`

## 採用済み（Phase 10, 2026-07-05）

| Oracle 由来 | gpt-pro-review 実装 | 目的 |
|---|---|---|
| `thinkingStatus.ts` — liveness log + stale hint | `IS_GENERATING_JS` + stderr `generating... Ns elapsed (status)` | timeout 時に「止まった/進んでいる」を区別 |
| `assistantResponse.ts` — stop button + thinking labels | `BROWSER_STATE_JS` / `BROWSER_STATE_SUMMARY` | 機械可読状態で recover 判断 |
| `assistantResponse.ts` — send confirmation (turn count) | `click_send` + `SEND_CONFIRM_JS` | 誤クリック送信の防止 |
| `assistantResponse.ts` — Answer now placeholder | `is_answer_now_placeholder()` | Pro thinking プレースホルダを最終回答と誤認しない |
| `promptComposer.ts` — composer-scoped send button | `CLICK_SEND_JS` scope to composer/form | サイドバー誤クリック防止 |
| `attachments.ts` — filename evidence | `wait_attachment_evidence()` | 添付未確認の loud warning |
| `docs/agents.md` — Cursor command/skill | `.cursor/commands/gpt-pro-review.md`, `.cursor/skills/`, `AGENTS.md` | Cursor から同ワークフロー |
| conversation inner scroll (live lesson) | `SCROLL_CONVERSATION_BOTTOM_JS` + assistant-scoped copy | `window.scrollTo` だけではコピーに届かない。overflow を `scrollTop=scrollHeight`。探索を親まで広げると user 添付 download を連打するので禁止 |

## 意図的に採用しない

| Oracle 機能 | 理由 |
|---|---|
| CDP / chrome-launcher 全体系 | gpt-pro-review は nodriver + 専用 profile に固定 |
| Session reattach / tab lease | スコープ外。recover は会話 URL 手動 + `--extract-only` |
| API engine / multi-model | 非目標（SKILL.md） |
| MCP `oracle.consult` | 別プロダクト。gpt-pro-review は bounded save_report のみ |

## 次に見る候補（未実装）

- Oracle `domDebug.ts` — timeout 時 DOM/screenshot artifact（要 `~/.pro-review` 配下パス設計）
- Oracle `recoverConversation.ts` — conversation URL メタデータからの自動 re-open
- Sidecar progress % — `BROWSER_STATE.progressPercent` 拡張

判断に迷ったら live の `browser_state:` をユーザーと共有して方針を決める（無理に自動化しない）。
