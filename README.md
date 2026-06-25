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

非 5.5Pro / MCP 経由:

```bash
pro-review-run --thinking --repo /path/to/repo --project my-review --question "bug と security を見て"
pro-review-tunnel
pro-review-tunnel-check my-review
```

ChatGPT 側では、送信するチャットで Developer Mode と pro-review Tunnel connector を有効化してから依頼文を貼る。

詳細は [docs/usage.md](docs/usage.md) と [SETUP-layer2.md](SETUP-layer2.md)。
