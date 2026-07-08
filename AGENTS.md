# Agent notes (Claude Code / Codex / Cursor)

## gpt-pro-review

このリポジトリは **ChatGPT Web への独立レビュー依頼** 用ツール群です。自動修正ではなく第二意見取得が目的です。

- **Path A (Pro)**: `scripts/pro-review-run --pro --repo <repo> --project <name> --question "..."`
- **Path B (Thinking + MCP)**: `scripts/pro-review-run --thinking ...`
- **詳細**: [`SKILL.md`](SKILL.md) / [`docs/usage.md`](docs/usage.md)
- **Cursor**: `/gpt-pro-review` コマンド（[`.cursor/commands/gpt-pro-review.md`](.cursor/commands/gpt-pro-review.md)）

### Live 実行

- 専用 Chrome + nodriver が必要。エージェントのサンドボックス内からはブラウザ接続できないことがある。
- timeout 時は `browser_state:` 行で生成中か copy 可能かを判断。完了後 `scripts/pro-review-recover <project> <run_id>`。

### Oracle 参考

ブラウザ automation の改善は sibling [`oracle`](../oracle) を参照。同期: `scripts/sync-oracle-reference.sh`（[`docs/oracle-adoptions.md`](docs/oracle-adoptions.md)）。
