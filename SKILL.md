---
name: gpt-pro-review
description: Send a code review / research / implementation-draft request to ChatGPT when this agent needs an independent second opinion. Path A uses GPT-5.5 Pro via browser/nodriver with local DOM extraction. Path B uses non-5.5Pro ChatGPT via browser/nodriver plus Secure MCP Tunnel, search/fetch, and bounded save_report. Both paths save REPLY-<run_id>.md, validate the final marker, persist a report bundle, and summarize findings for Claude/Codex to judge. Do NOT use for reviews this agent should do itself.
---

# gpt-pro-review

ChatGPT Web の別モデルに、レビュー / 調査 / 実装ドラフトを依頼するための skill。

目的は「自動でコードを直す」ことではない。
目的は「独立した第二意見を取り、Claude/Codex 側で判断する」こと。

## 2 パス

| Path | 使う場面 | 読ませ方 | 保存方法 |
|---|---|---|---|
| Path A: 5.5Pro | Pro 品質が必要なレビュー | packet を `.md` 添付（主）/ prompt 直書き（fb） | コピーボタン→`pbpaste`（主）/ DOM 抽出（fb）→ `pro-review-save-reply` |
| Path B: 非 5.5Pro | nodriver で ChatGPT を開き、workspace を MCP で読ませる | `search` / `fetch` | ChatGPT が `save_report` |

共通の最後:

1. `REPLY-<run_id>.md` を inbox に保存する。
2. `pro-review-validate-reply` で最終行 `[[DONE-<run_id>]]` を検証する。
3. `pro-review-finish` で `reports/<project>/<run_id>/` に bundle 保存する。
4. `pro-review-summarize` で `対応 / 見送り / 要確認` に分類する。

## 最短コマンド

Path A:

```bash
pro-review-browser-setup --install
pro-review-browser-setup --open-login
# ChatGPT にログイン後
pro-review-browser-setup --mark-logged-in
# 専用 Chrome ウィンドウを閉じてから実行
pro-review-run --pro --repo /path/to/repo --project my-review --question "bug と security を見て"
```

`pro-review-run --pro` が `FALLBACK:login required` と判断した場合は、
`pro-review-browser-setup --open-login` を自動実行して専用 Chrome の ChatGPT ログイン画面を開く。
ユーザーが行うのはブラウザ上のログイン、Chrome を閉じること、`pro-review-browser-setup --mark-logged-in` の実行だけ。
資格情報入力・MFA・CAPTCHA の代行はしない。

Path A の入力は packet を `.md` として添付するのが主経路（98KB を入力欄に直書きしない）。添付不可なら直書きにフォールバックする。
回答取得はコピーボタン→`pbpaste` が主経路で、失敗時のみ DOM 抽出にフォールバックする。

Pro の生成は分単位のため、Path A の生成待ち既定 timeout は 600 秒（`--timeout` で上書き可）。
待ち切れず終了しても回答はブラウザに残るので、生成完了後に復旧できる。

```bash
# 答えis出ているのに自動保存されなかった時（timeout 後など）に救う
pro-review-recover <project> <run_id>
```

`pro-review-recover` は専用ブラウザの該当会話から最終回答をコピー取得し、`[[DONE-<run_id>]]` を検証して `save-reply` + `finish` まで通す。
`pro-review-run --pro` が timeout して exit 3 した時は、貼り付け用に `recover: pro-review-recover <project> <run_id>` を出力する。

Path A の ChatGPT ツール利用方針は既定で `auto`。
`auto` は UI 上の Auto ボタン名ではなく、この skill の方針名。
Web Search は ChatGPT 側の自動判断に任せる。
Deep Research は `on`、または `auto` でレビュー観点から複数ソース調査が必要と判定した時に、Nodriver が送信前に `/Deepresearch` または tools menu から UI/mode 選択を試す。
明示したい時だけ次を付ける。

```bash
pro-review-run --pro --repo /path/to/repo --project my-review \
  --web-search on \
  --deep-research off \
  --question "最新ライブラリ仕様も踏まえて review"
```

- `--web-search auto|on|off`
- `--deep-research auto|on|off`

`auto` は、現在情報・外部仕様・CVE・競合比較などが必要な時だけ使う方針。
`on` は使用を依頼し、使えない surface では status / STOP_REASON を返す方針。
`off` は外部検索を使わず、必要な論点を `要確認` に寄せる方針。

Path B:

```bash
pro-review-run --thinking --repo /path/to/repo --project my-review --question "bug と security を見て"
```

Path B では、`pro-review-run --thinking` が snapshot 作成、Tunnel 起動、connector check、nodriver による ChatGPT UI 送信、watch、finish まで行う。
送信前に ChatGPT 側で Developer Mode と pro-review Tunnel connector が登録済みである必要がある。
実行時は nodriver が固定ラベル `pro-review Tunnel connector` をこのチャットで選択してから依頼文を送る。
connector の作成・初回認可・MFA・権限付与は人間/管理者操作のまま。
ChatGPT は `search("")`、`fetch(id)`、`save_report(project, run_id, body)` を使う。
`search` / `fetch` / `save_report` が見えない場合はレビューせず、`STOP_REASON=connector_unavailable` を返す。
connector 名が違う場合は `--connector-label "..."` を付ける。

## 重要な保存契約

返信は必ず次の名前にする。

```text
~/.pro-review/inbox/<project>/REPLY-<run_id>.md
```

返信の最終行は必ずこれにする。

```text
[[DONE-<run_id>]]
```

`pro-review-validate-reply` は次を拒否する。

- 別 run_id の返信
- symlink
- inbox 外のファイル
- marker が本文中だけにある返信
- marker が複数ある返信

## レポート bundle

`pro-review-finish` は次を作る。

```text
~/.pro-review/reports/<project>/<run_id>/
  request.md        # 見つかった場合
  reply.md
  summary.json
  summary.md
  easy-report.md
  metadata.json
```

古い互換用に timestamp 付き reply も `reports/<project>/` 直下に残す。

## 安全境界

- live repo は直接公開しない。
- Path B は snapshot を `~/.pro-review/workspace/<project>/` に作る。
- MCP の既定 tool は `search` / `fetch` / `save_report` だけ。
- 汎用 `write_file` / `edit_file` / `bash` は既定公開しない。
- 外部公開前に secret scan を実行し、ヒット時は公開中止する。
- secret scan のバイパスは Risk Gate。既定 OFF（scan 有効）。誤検知は `ALLOW_SECRETS=1`（per-call）で上書き。`pro-review-danger-mode --on` でこの環境だけ恒久バイパス（マーカー `~/.pro-review/danger-mode`。git 経由で他環境に伝播しない）。バイパスでヒットした時は実行ログに `[danger]` 行で公開対象を必ず出す。`PRO_REVIEW_FORCE_SCAN=1` は恒久バイパス（marker / `PRO_REVIEW_DANGER_MODE`）を無効化して scan を強制（danger ON 環境でこの実行だけ既定挙動に戻す。同一コールの `ALLOW_SECRETS=1` は優先）。
- `PRO_REVIEW_FULL=1` は Risk Gate。確認 env なしでは起動しない。
- `~/.pro-review` は 700、reply/report/log は 600。
- log は `CONTROL_PLANE_API_KEY`、`sk-...`、cookie らしき値を redaction する。

## 診断

```bash
pro-review-doctor
pro-review-tunnel-check <project>
```

`doctor` は `OK / WARN / FIX / MANUAL` で表示する。
`WARN danger_mode ON` は secret scan がこの環境で bypass 中であることを示す。
秘密値そのものは表示しない。

## テスト

```bash
bash tests/run-all.sh
```

fixture では Path A / Path B nodriver connector / MCP hardening / report bundle / summary / doctor を検証する。
実 ChatGPT の manual e2e は `docs/manual-checklist.md` に記録する。

## 非目標

- OpenAI API route への pivot
- CH/GIFT 固有文脈の混入
- ChatGPT 回答の自動適用
- 汎用 coding bridge 化

## 退役

- `PRO_REVIEW_MODE=readonly`
- 「ChatGPT が inbox に直接書けない」という前提
  - 現在は bounded `save_report` first。
  - DOM 抽出保存は fallback。
