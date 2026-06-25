# gpt-pro-review usage

## ひとことで

ChatGPT にレビューを頼み、結果を安全に保存して、Claude/Codex が判断するための道具。

## 初回

```bash
pro-review-doctor
pro-review-browser-setup --install
```

Path A を live で使う前に専用 profile へログインする。

```bash
pro-review-browser-setup --open-login
# ChatGPT にログイン後
pro-review-browser-setup --mark-logged-in
```

ログイン後は、その専用 Chrome ウィンドウを閉じてから Path A を実行する。
同じ profile を開いたままだと nodriver が profile lock で起動できない。

Path B を使うなら、`SETUP-layer2.md` の tunnel-client 設定も行う。

## Path A: 5.5Pro

```bash
pro-review-run --pro \
  --repo /path/to/repo \
  --project my-review \
  --question "bug と security を見て"
```

Path A では ChatGPT Web の Search / Deep Research 方針を request に入れられる。
どちらも既定は `auto`。
`auto` は UI の Auto 表示ではなく、この skill の方針名。
Web Search は ChatGPT 側の自動判断に任せる。
Deep Research は `on`、または `auto` でレビュー観点から複数ソース調査が必要と判定した時に、Nodriver が送信前に `/Deepresearch` または tools menu から UI/mode 選択を試す。

```bash
pro-review-run --pro \
  --repo /path/to/repo \
  --project my-review \
  --web-search on \
  --deep-research off \
  --question "最新仕様の確認は web も使って review"
```

| Option | 値 | 意味 |
|---|---|---|
| `--web-search` | `auto` / `on` / `off` | Search を ChatGPT 判断 / 明示使用 / 禁止にする |
| `--deep-research` | `auto` / `on` / `off` | Deep Research を ChatGPT 判断 / 明示使用 / 禁止にする |

Deep Research は複数ソースを横断して調査・統合する重い作業向け。
通常の repo-local なコードレビューだけなら `auto` のままでよい。

失敗時に `FALLBACK:<reason>` が出たら、表示された `manual_save:` の形で手貼り保存できる。

## Path B: 非 5.5Pro + MCP

```bash
pro-review-run --thinking \
  --repo /path/to/repo \
  --project my-review \
  --question "bug と security を見て"

pro-review-tunnel
pro-review-tunnel-check my-review
```

ChatGPT 側では、送信前に Developer Mode と pro-review Tunnel connector をこのチャットで有効化してから依頼文を貼る。
ChatGPT は `search` / `fetch` で読み、`save_report` で保存する。
`search` / `fetch` / `save_report` が見えない場合はレビューせず、`STOP_REASON=connector_unavailable` が出る。

## 結果

```text
~/.pro-review/reports/<project>/<run_id>/
```

この中に `reply.md`、`summary.json`、`summary.md`、`easy-report.md`、`metadata.json` が入る。

## 復旧

```bash
pro-review-doctor
pro-review-tunnel-check <project>
```

`STOP_REASON` が出たら、隣の `NEXT_ACTION` を実行する。

## cleanup

一時データだけ消す。

```bash
rm -rf ~/.pro-review/workspace/<project> ~/.pro-review/inbox/<project>
```

永続レポートも消す。

```bash
rm -rf ~/.pro-review/reports/<project>
```
