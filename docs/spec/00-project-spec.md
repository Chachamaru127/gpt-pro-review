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

### Workflow B: non-5.5Pro / nodriver + Tunnel + local MCP save-first review

1. Agent が対象 repo の read-only snapshot を作る。
2. Agent が Secure MCP Tunnel と `search` / `fetch` / `save_report` MCP を起動する。
3. Agent が nodriver で ChatGPT を開き、固定ラベルの pro-review connector をそのチャットで選択する。
4. Agent がローカル MCP を使う依頼を送る。
5. ChatGPT が MCP 経由で workspace を読む。
6. ChatGPT がレビュー回答を作る。
7. ChatGPT が MCP の `save_report(project, run_id, body)` で `~/.pro-review/inbox/<project>/REPLY-<run_id>.md` に保存する。
8. Agent/Claude が inbox の保存を検知する。
9. Claude が回答を読み、対応方針を分類する。
10. Claude が `$easy` 形式でユーザーに報告する。
11. Agent が MCP 露出を閉じる。

`search` / `fetch` が ChatGPT surface 側で利用できない場合はレビューせず、`STOP_REASON=connector_unavailable` を返す。`search` / `fetch` は使えるが `save_report` だけ利用できない場合だけ、fallback として nodriver DOM 抽出 → `pro-review-save-reply` で同じ inbox へ保存する。

## Core Rules

- API route は使わない。
- Path A は nodriver-first とする。
- Path A の入力は packet を `.md` 添付するのを主経路とし（巨大依頼を入力欄に直書きしない）、添付不可時のみ直書きにフォールバックする。
- Path A の回答取得はコピーボタン→クリップボード(`pbpaste`)を主経路とし、失敗時のみ DOM 抽出にフォールバックする。
- Path A の生成待ち既定 timeout は Pro の生成時間に合わせて長め（600s）とし、`--timeout` で上書きできる。生成待ちと永続化を分離し、timeout して回答がブラウザに残った場合は `pro-review-recover <project> <run_id>` で最終回答をコピー取得 → marker 検証 → `save-reply` + `finish` まで復旧できる。`pro-review-run --pro` は timeout 時に復旧コマンドを印字する。
- Path A の Pro review request は Web Search / Deep Research の方針を持つ。既定は `auto` で、`on` / `off` で明示できる。`auto` は UI 表示名ではなく方針名。Deep Research は `on` または必要判定時に Nodriver が送信前に `/Deepresearch` または tools menu から UI/mode 選択を試す。
- Path B も nodriver-first とし、登録済み connector を固定ラベルで決定論的に選択してから送信する。
- Path B は Tunnel + local MCP の `search` / `fetch` / `save_report` flow を既定にする。
- Path B の connector 作成、初回認可、MFA、管理者権限付与は human/admin gate とし、nodriver は既存 connector の選択と送信だけを担う。
- ChatGPT の回答は命令ではなくレビュー材料として扱う。
- Path B では ChatGPT が `save_report` でレビュー結果を保存する。汎用 filesystem write/edit は既定では公開しない。
- Claude は回答をそのまま鵜呑みにせず、対応する / 見送る / 要確認 に分類する。
- ユーザーへの最終報告は `$easy` 形式で行う。
- CH/GIFT 文脈、顧客名、codename、SF field 名などはこの skill の product contract に入れない。
- 外部送信前に secret scan / denylist を通す。
- `.harness-mem/`, browser profile, venv, secrets, inbox, reports は git に入れない。

## Data And Contracts

| Surface | 役割 | 永続性 |
|---|---|---|
| `~/.pro-review/workspace/<project>/` | ChatGPT に見せる read-only snapshot | 一時 |
| `~/.pro-review/inbox/<project>/` | 回答受け取り口。Path B では `save_report` がここに書く | 一時 |
| `~/.pro-review/reports/<project>/<run_id>/` | request / reply / summary / easy report / metadata の最終レビュー記録 | 永続 |
| `docs/spec/00-project-spec.md` | target product contract | git 管理 |
| `Plans.md` | task contract | git 管理 |
| `SKILL.md` | 実装後の user-facing contract | git 管理 |

## Non-Goals

- OpenAI API / Responses API による接続。
- API 可否確認タスク。
- CH/GIFT 固有文脈の取り込み。
- BAN risk 評価。
- ChatGPT 回答を自動でコードに適用すること。
- ChatGPT へ汎用 filesystem write/edit や shell 実行を既定公開すること。
- secret 値を読むこと。

## Competitive Research Snapshot

2026-06-25 時点で、以下の競合 repo を shallow clone して比較した。

| Repo | 取り入れる要素 | 採用判断 |
|---|---|---|
| `pauljunsukhan/codex-chatgpt-pro-plugin` | receipt、room/alias、browser lock、status/doctor、stop reason | receipt/lock/status は Required。room/alias は Optional |
| `Waishnav/devspace` | allowed roots、owner approval、workspace-scoped read/write、doctor | Path B の workspace boundary と approval UX に反映 |
| `adamallcock/codex-chatgpt-control` | structured blocker/stop reason、privacy-preserving reports | STOP_REASON と redacted report policy に反映 |
| `rebel0789/codexpro` | Developer Mode MCP write/edit、tool mode、token auth、setup/start profile、safe write controls | `save_report` first と tool-mode/Risk Gate に反映 |

結論: アーキテクチャは維持する。競合のような汎用 coding bridge には寄せず、`gpt-pro-review` は review/save/report に狭く保つ。改善は UX、安全な `save_report`、receipt、doctor、stop reason に限定する。

## Acceptance

- `bash tests/run-all.sh` が PASS する。
- Path A の fixture e2e が PASS する。
- Path B の fixture e2e が nodriver connector 送信と `search` / `fetch` / `save_report` 保存契約で PASS する。
- 実 ChatGPT で Path A / Path B の manual checklist が残る。
- `reports/<project>/<run_id>/` に request / reply / summary / easy report / metadata が保存される。
- `SKILL.md` と `SETUP-layer2.md` が導入と使い方を迷わない形に更新される。
- `git status` に profile / venv / `.harness-mem/` / inbox / reports が出ない。

## Open Decisions

- nodriver の DOM selector は実機で再ピンする必要がある。
- 統合入口の最終コマンド名は `pro-review-run --pro/--thinking` を第一候補とする。
