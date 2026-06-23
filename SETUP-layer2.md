# Layer 2 セットアップ（Path B: Thinking-High でフォルダ直読みさせる）

ChatGPT Thinking-High に、リポジトリのスナップショットを **OpenAI 公式 Secure MCP Tunnel + search/fetch 専用 MCP** 経由で読ませる構成。Path B 専用。**Path A（Pro ブラウザ埋め込み）は MCP 不要なので、このセットアップは不要**。

## なぜ search/fetch だけか

OpenAI 公式仕様で、Pro/Plus 環境では:
- カスタム MCP の **write 系ツールは silently disabled**（`write_file` / `edit_file` 等）
- **GPT-5.5 Pro は Deep Research surface** で search/fetch しか呼ばない
- **Thinking-High は read-only ツールなら呼べる**

ので、両モデルで動く最小公倍数として **search / fetch の 2 ツールだけを公開する MCP** を立てている（`pro-review-mcp-search-fetch`）。Business/Enterprise/Edu なら `PRO_REVIEW_FULL=1` で filesystem MCP の write 込みに切り替えられる。

## 構成図

```
ChatGPT Thinking-High (開発者モード, Connector=Tunnel)
        │  outbound HTTPS
   OpenAI Secure MCP Tunnel
        │
   tunnel-client (ローカル)
        │
   pro-review-mcp (= pro-review-mcp-search-fetch を起動)
        ├─ search(query): workspace 内ファイルを検索
        └─ fetch(id): workspace 内ファイルを取得（read-only）
   公開: ~/.pro-review/workspace/<active-project>/   (read-only スナップショット)
```

ライブのリポジトリは晒さない。`pro-review-snapshot` が `.git` と秘密情報を除いたコピーだけを workspace に置く。

## ユーザー手順（一度だけ）

1. **tunnel-client を入手**
   - https://platform.openai.com/settings/organization/tunnels からバイナリをDL
   - `~/.pro-review/bin/tunnel-client` に置いて `chmod +x`
2. **認証情報を発行して 0600 で保存**
   - 同ページで `tunnel_id` を作成
   - Runtime API keys で key を作成（権限: Tunnels = Read + Use）
   - `~/.pro-review/env.sh` に保存（**`source` ではなく KEY=VALUE 形式で parse される**）：
     ```bash
     CONTROL_PLANE_TUNNEL_ID=tunnel_xxx
     CONTROL_PLANE_API_KEY=sk-proj-xxx
     ```
     必ず `chmod 600 ~/.pro-review/env.sh`
3. **ChatGPT 側で登録**
   - ChatGPT Web 版で **開発者モード** ON（設定 → アプリ → 詳細設定 → Developer Mode）
   - コネクタを追加 → **Tunnel モード** → 同じ `tunnel_id` を登録
   - Authentication は **No / Mixed** どちらでも可（最小権限なので無認証で OK）

## 起動と利用

```bash
# 1. レビュー対象をスナップショット
pro-review-snapshot /path/to/repo my-project

# 2. トンネル起動（run_in_background 推奨）
pro-review-tunnel
```

ChatGPT 側で **Thinking-High** モデルに切替、pro-review コネクタを有効化。`search("") → fetch(id)` で workspace を読ませる依頼文（`pro-review-start` が生成する）を貼って送信。

## 返信の回収方法

ChatGPT は **inbox に write_file できない**（Pro/Plus で silently disabled）。なので：

1. ChatGPT 本文として返ってくる
2. claude-in-chrome の `read_page` / `get_page_text` で `data-message-author-role="assistant"` の最新メッセージを抽出
3. 末尾に `[[DONE-<since>]]` マーカーが付くよう依頼文で指示済み（最終 1 行完全一致で判定）
4. 抽出本文を `pro-review-save-reply <project> <since>` でローカル inbox にアトミック保存
5. `pro-review-watch` が拾って auto-resume

## Business / Enterprise / Edu

`PRO_REVIEW_FULL=1 pro-review-tunnel` で filesystem MCP の write 込み版に切替可能。この場合 ChatGPT が直接 `inbox/REPLY-<since>.md` を書き、save-reply を介さずに watcher が拾う旧フローになる（Pro/Plus アカウントでは write 不可なので使えない）。

## 退役

- 旧 `PRO_REVIEW_MODE=readonly`（filesystem MCP の read-only proxy）: search/fetch だけで Thinking 系も動くので不要。実装は `scripts/_archive/pro-review-mcp-readonly` に保管
