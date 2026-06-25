---
name: gpt-pro-review
description: Send a code review / research / implementation-draft request to ChatGPT when this agent needs an independent second opinion. Path A uses GPT-5.5 Pro via browser/nodriver with local DOM extraction. Path B uses non-5.5Pro ChatGPT with Secure MCP Tunnel, search/fetch, and bounded save_report. Both paths save REPLY-<run_id>.md, validate the final marker, persist a report bundle, and summarize findings for Claude/Codex to judge. Do NOT use for reviews this agent should do itself.
---

# gpt-pro-review

ChatGPT Web の別モデルに、レビュー / 調査 / 実装ドラフトを依頼するための skill。

目的は「自動でコードを直す」ことではない。
目的は「独立した第二意見を取り、Claude/Codex 側で判断する」こと。

## 2 パス

| Path | 使う場面 | 読ませ方 | 保存方法 |
|---|---|---|---|
| Path A: 5.5Pro | Pro 品質が必要なレビュー | prompt に diff / packet を埋める | DOM 抽出 → `pro-review-save-reply` |
| Path B: 非 5.5Pro | workspace を MCP で読ませる | `search` / `fetch` | ChatGPT が `save_report` |

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
pro-review-tunnel
pro-review-tunnel-check my-review
```

Path B では、`pro-review-run --thinking` が ChatGPT に貼る依頼文を作る。
送信前に ChatGPT 側で Developer Mode と pro-review Tunnel connector をそのチャットで有効化する。
ChatGPT は `search("")`、`fetch(id)`、`save_report(project, run_id, body)` を使う。
`search` / `fetch` / `save_report` が見えない場合はレビューせず、`STOP_REASON=connector_unavailable` を返す。

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
- `PRO_REVIEW_FULL=1` は Risk Gate。確認 env なしでは起動しない。
- `~/.pro-review` は 700、reply/report/log は 600。
- log は `CONTROL_PLANE_API_KEY`、`sk-...`、cookie らしき値を redaction する。

## 診断

```bash
pro-review-doctor
pro-review-tunnel-check <project>
```

`doctor` は `OK / FIX / MANUAL` で表示する。
秘密値そのものは表示しない。

## テスト

```bash
bash tests/run-all.sh
```

fixture では Path A / Path B / MCP hardening / report bundle / summary / doctor を検証する。
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
