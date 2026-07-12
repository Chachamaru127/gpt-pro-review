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

### Workflow C: multi-round re-review（followup）

1. Agent が前回 run の findings（安定 ID 付き）と、その後の修正 diff から followup packet を作る。
2. Agent が **新規会話** として Path A で送信する（既存会話への reattach はしない）。
3. ChatGPT が finding ID ごとに `resolved` / `still-open` / `new` を判定して回答する。
4. Agent が回答を回収し、findings ledger に追記する。
5. Claude が分類し、`$easy` 形式で報告する。

各 round は独立した run_id を持ち、`metadata.json` の `previous_run_id` で連結する。

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
- followup（Workflow C）は毎 round 新規会話で送る。既存会話への session reattach / tab lease は採用しない。
- findings は安定 ID（内容ベース。並び替え・再要約で変わらない）を持つ。ID は followup 判定と ledger 追記の主キーになる。
- findings ledger の採用率・誤検知率は「Claude/ユーザーの受容の proxy 指標」であり、客観的な正誤ではないことを表示に明記する。
- fallback / timeout 時の診断 artifact（DOM 抜粋・screenshot）は `reports/<project>/<run_id>/` 配下に `chmod 600` で保存する。umask 継承には依存しない。
- `metadata.json` に保存する会話 URL は、保存時・使用時の双方で host が `chatgpt.com` であることを検証する。検証に失敗したら使わず止まる。
- consensus 比較は「2 つの findings JSON を突き合わせて agreed / disputed を出すローカルユーティリティ」までとする。GPR 自身が他の agent（Codex 等）を起動しない。第二レビューの取得は呼び出し元 agent の責務。

## Data And Contracts

| Surface | 役割 | 永続性 |
|---|---|---|
| `~/.pro-review/workspace/<project>/` | ChatGPT に見せる read-only snapshot | 一時 |
| `~/.pro-review/inbox/<project>/` | 回答受け取り口。Path B では `save_report` がここに書く | 一時 |
| `~/.pro-review/reports/<project>/<run_id>/` | request / reply / summary / easy report / metadata / 診断 artifact の最終レビュー記録 | 永続 |
| `~/.pro-review/ledger/<project>.jsonl` | findings ledger（finding ID・round・分類・採用判断の追記ログ、chmod 600） | 永続 |
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
- 無人スケジュール実行（launchd/cron nightly review）。GUI Chrome 必須（headless 非対応）・ログイン失効・消費者不在のため成立しない（2026-07-12 判断）。
- 非 OpenAI 宛の外部送信（Slack / PR コメント等へのレビュー共有）。単一ユーザー設計と衝突し、新しい外部送信面・認証面を増やすため（2026-07-12 判断）。
- 実行回数の強制上限（quota cap / pacing 強制）。BAN risk 評価の Non-Goal と衝突。観測用の実行回数表示までは可。
- GPR 自身によるマルチエージェント起動（Codex 呼び出し等の orchestration）。

## Competitive Research Snapshot

2026-06-25 時点で、以下の競合 repo を shallow clone して比較した。

| Repo | 取り入れる要素 | 採用判断 |
|---|---|---|
| `pauljunsukhan/codex-chatgpt-pro-plugin` | receipt、room/alias、browser lock、status/doctor、stop reason | receipt/lock/status は Required。room/alias は Optional |
| `Waishnav/devspace` | allowed roots、owner approval、workspace-scoped read/write、doctor | Path B の workspace boundary と approval UX に反映 |
| `adamallcock/codex-chatgpt-control` | structured blocker/stop reason、privacy-preserving reports | STOP_REASON と redacted report policy に反映 |
| `rebel0789/codexpro` | Developer Mode MCP write/edit、tool mode、token auth、setup/start profile、safe write controls | `save_report` first と tool-mode/Risk Gate に反映 |

結論: アーキテクチャは維持する。競合のような汎用 coding bridge には寄せず、`gpt-pro-review` は review/save/report に狭く保つ。改善は UX、安全な `save_report`、receipt、doctor、stop reason に限定する。

### Market gap research（2026-07-12 追記）

grok（Web/X）+ Claude WebSearch のクロス調査で、A 系（agent → ChatGPT Web second opinion）市場の未充足を確認した。

- Oracle（steipete、3.2k stars）が旗艦だが、リリースの大半が ChatGPT UI 追従修正に費やされ、multi-round review の契約化・finding 追跡は持たない。
- 全競合（Oracle / Pro Line / codex-chatgpt-control / DevSpace / CodexPro）が製品化していない領域: 契約化された multi-round review、finding 単位の status ledger、採用率・誤検知の追跡。
- GPR は secret scan / snapshot isolation / bounded tools / report bundle で安全側の差別化を既に持つ。

採用判断: 差別化投資は「multi-round review protocol + findings ledger」（Workflow C）に集中する。scheduled 実行・チーム共有・quota 強制は市場ギャップとして実在するが、GPR の単一ユーザー・狭スコープ原則と衝突するため Non-Goals に明記して見送る。

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
- Path B（Plans.md 6.18、ChatGPT 側 app creation gate 未通過）を「解決する」か「明示凍結して Path A 専念」かをユーザーが決める。新フェーズは全て Path A のみで成立する。
- ToS / BAN スタンスの文書化は Non-Goal「BAN risk 評価」と衝突するため、書くならユーザーの明示判断（法務 Risk Gate）が先。
- doctor への selector drift probe（chatgpt.com へ read-only 到達）は doctor の脅威モデルを「純ローカル」から変えるため、opt-in フラグ化を含めてユーザー判断待ち。
