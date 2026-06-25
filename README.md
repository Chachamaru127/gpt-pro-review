# gpt-pro-review

ChatGPT Web に外部レビューを依頼し、結果を `~/.pro-review` に保存する user-scope skill。

## Quick Start

```bash
pro-review-doctor
pro-review-browser-setup --install
pro-review-browser-setup --open-login
# ChatGPT にログイン後
pro-review-browser-setup --mark-logged-in
# 専用 Chrome ウィンドウを閉じてから実行
pro-review-run --pro --repo /path/to/repo --project my-review --question "bug と security を見て"
```

Path A では Web Search / Deep Research の使い方を指定できる。
既定は `auto`。これは UI の Auto 表示ではなく方針名。
Web Search は ChatGPT 側の自動判断、Deep Research は Nodriver が必要時に `/Deepresearch` または tools menu から UI/mode 選択を試す。

```bash
pro-review-run --pro --repo /path/to/repo --project my-review \
  --web-search auto \
  --deep-research auto \
  --question "bug と security を見て"
```

非 5.5Pro / MCP 経由:

```bash
pro-review-run --thinking --repo /path/to/repo --project my-review --question "bug と security を見て"
pro-review-tunnel
pro-review-tunnel-check my-review
```

ChatGPT 側では、送信するチャットで Developer Mode と pro-review Tunnel connector を有効化してから依頼文を貼る。

詳細は [docs/usage.md](docs/usage.md) と [SETUP-layer2.md](SETUP-layer2.md)。
