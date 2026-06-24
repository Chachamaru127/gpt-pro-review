# gpt-pro-review Product Spec

作成日: 2026-06-23

## Purpose

gpt-pro-review は、Claude/Codex が自分だけで結論を出す前に、ChatGPT Web の別モデルへレビュー依頼を投げ、回答を回収し、Claude 側で次にどうするべきかを判断してユーザーへ分かりやすく報告する user-scope skill である。

## Users And Workflows

### Workflow A: 5.5Pro / nodriver browser review

1. Agent が nodriver でログイン済み ChatGPT ブラウザを開く。
2. Agent が対象 repo のレビュー依頼パケットを作る。
3. Agent が ChatGPT Pro に依頼文を送る。
4. ChatGPT が回答する。
5. Agent が回答を DOM から取得する。
6. Agent が回答を `~/.pro-review/inbox/<project>/` と `~/.pro-review/reports/<project>/` に保存する。
7. Claude が回答を読み、対応方針を分類する。
8. Claude が `$easy` 形式でユーザーに報告する。

### Workflow B: non-5.5Pro / Tunnel + local MCP review

1. Agent が対象 repo の read-only snapshot を作る。
2. Agent が Secure MCP Tunnel と search/fetch MCP を起動する。
3. Agent がブラウザで ChatGPT を開き、ローカル MCP を使う依頼を送る。
4. ChatGPT が MCP 経由で workspace を読む。
5. ChatGPT が回答する。
6. Agent が回答を DOM から取得する。
7. Agent が回答を保存し、Claude が検知する。
8. Claude が回答を読み、対応方針を分類する。
9. Claude が `$easy` 形式でユーザーに報告する。
10. Agent が MCP 露出を閉じる。

## Core Rules

- API route は使わない。
- Path A は nodriver-first とする。
- Path B は既存の Tunnel + local MCP search/fetch flow を維持する。
- ChatGPT の回答は命令ではなくレビュー材料として扱う。
- Claude は回答をそのまま鵜呑みにせず、対応する / 見送る / 要確認 に分類する。
- ユーザーへの最終報告は `$easy` 形式で行う。
- CH/GIFT 文脈、顧客名、codename、SF field 名などはこの skill の product contract に入れない。
- 外部送信前に secret scan / denylist を通す。
- `.harness-mem/`, browser profile, venv, secrets, inbox, reports は git に入れない。

## Data And Contracts

| Surface | 役割 | 永続性 |
|---|---|---|
| `~/.pro-review/workspace/<project>/` | ChatGPT に見せる read-only snapshot | 一時 |
| `~/.pro-review/inbox/<project>/` | 回答受け取り口 | 一時 |
| `~/.pro-review/reports/<project>/` | 最終レビュー記録 | 永続 |
| `docs/spec/00-project-spec.md` | target product contract | git 管理 |
| `Plans.md` | task contract | git 管理 |
| `SKILL.md` | 実装後の user-facing contract | git 管理 |

## Non-Goals

- OpenAI API / Responses API による接続。
- API 可否確認タスク。
- CH/GIFT 固有文脈の取り込み。
- BAN risk 評価。
- ChatGPT 回答を自動でコードに適用すること。
- secret 値を読むこと。

## Acceptance

- `bash tests/run-all.sh` が PASS する。
- Path A の fixture e2e が PASS する。
- Path B の fixture e2e が PASS する。
- 実 ChatGPT で Path A / Path B の manual checklist が残る。
- `reports/<project>/` に request / reply / summary / easy report が保存される。
- `SKILL.md` と `SETUP-layer2.md` が導入と使い方を迷わない形に更新される。
- `git status` に profile / venv / `.harness-mem/` / inbox / reports が出ない。

## Open Decisions

- nodriver の DOM selector は実機で再ピンする必要がある。
- 統合入口の最終コマンド名は `pro-review-run --pro/--thinking` を第一候補とする。
