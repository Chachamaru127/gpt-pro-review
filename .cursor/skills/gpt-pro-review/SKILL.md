---
name: gpt-pro-review
description: Send a code review / research / implementation-draft request to ChatGPT when this agent needs an independent second opinion. Path A uses GPT-5.5 Pro via browser/nodriver. Path B uses non-5.5Pro ChatGPT via MCP Tunnel. Use from Cursor with foreground shell + dedicated Chrome. Do NOT use for reviews this agent should do itself.
---

# gpt-pro-review (Cursor)

正本: リポジトリ直下の [`SKILL.md`](../../SKILL.md)。矛盾時はそちらを優先。

## Cursor で使うとき

1. `scripts/pro-review-doctor` で OK/FIX/MANUAL を確認
2. Path A: `scripts/pro-review-run --pro --repo <repo> --project <name> --question "..."`
3. Path B: `scripts/pro-review-run --thinking ...`（connector 要セットアップ）
4. `exit 3` 時は stdout の `browser_state:` / `BROWSER_STATE_SUMMARY` を読む
5. 生成完了後: `scripts/pro-review-recover <project> <run_id>`

## timeout 判断

- `browser_state: generating; ...` → 待つ or ユーザーに「完了したら recover」と依頼
- `browser_state: copy-ready; ...` → recover を試す
- `FALLBACK:login required` → `pro-review-browser-setup --open-login` フロー（ユーザーがログイン）

## 安全

- secret scan 失敗は止める（`ALLOW_SECRETS=1` は誤検知時のみ）
- live repo を直接公開しない（packet/snapshot 経由のみ）
