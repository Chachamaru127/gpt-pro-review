# Layer 2 セットアップ（Path B: Thinking-High でフォルダ直読みさせる）

非 5.5Pro の ChatGPT に、リポジトリのスナップショットを **OpenAI 公式 Secure MCP Tunnel + search/fetch/save_report 専用 MCP** 経由で読ませ、レビュー結果を ChatGPT 自身に保存させる構成。Path B 専用。**Path A（5.5Pro ブラウザ埋め込み）は MCP 不要なので、このセットアップは不要**。

## なぜ search/fetch/save_report か

ユーザー確認により、Pro/Plus でも Developer Mode / MCP surface で write-capable tool は普通に使える前提に更新した。

ただし、本 Skill は coding bridge ではなくレビュー依頼ツールなので、汎用 `write_file` / `edit_file` / `bash` は既定公開しない。

既定で公開するのは次の 3 つだけ。

- `search(query)`: workspace のファイルを探す
- `fetch(id)`: 必要なファイルを読む
- `save_report(project, run_id, body)`: レビュー結果だけを inbox に保存する

`save_report` は保存先を自由に選ばせない。`~/.pro-review/inbox/<project>/REPLY-<run_id>.md` だけに atomic write する。

## 構成図

```
ChatGPT Thinking-High (nodriver操作, 開発者モード, Connector=Tunnel)
        │  outbound HTTPS
   OpenAI Secure MCP Tunnel
        │
   tunnel-client (ローカル)
        │
   pro-review-mcp (= pro-review-mcp-search-fetch を起動)
        ├─ search(query): workspace 内ファイルを検索
        ├─ fetch(id): workspace 内ファイルを取得（read-only）
        └─ save_report(project, run_id, body): inbox にレビュー結果だけ保存
   公開: ~/.pro-review/workspace/<active-project>/   (read-only スナップショット)
         ~/.pro-review/inbox/<active-project>/       (save_report のみ write)
```

ライブのリポジトリは晒さない。`pro-review-snapshot` が `.git` と秘密情報を除いたコピーだけを workspace に置く。

## ユーザー手順（一度だけ）

1. **tunnel-client を入手**
   - https://platform.openai.com/settings/organization/tunnels からバイナリをDL
   - `~/.pro-review/bin/tunnel-client` に置いて `chmod +x`
2. **tunnel を作成（workspace 関連付けが必須）**
   - 同ページの Create tunnel で作成。このとき **ChatGPT workspaces に、使う ChatGPT アカウントの workspace を必ず追加**する（2026-07 実測: 関連付けが無い tunnel は ChatGPT 側のトンネル一覧に一切表示されない）
   - Organizations は API key を発行する org と一致させる。key の org と tunnel の org が違うと tunnel-client が `401 mismatched_organization` になる
3. **認証情報を発行して 0600 で保存**
   - Runtime API keys で key を作成（権限: Tunnels = Read + Use。**tunnel と同じ org で発行**）
   - `~/.pro-review/env.sh` に保存（**`source` ではなく KEY=VALUE 形式で parse される**）：
     ```bash
     CONTROL_PLANE_TUNNEL_ID=tunnel_xxx
     CONTROL_PLANE_API_KEY=sk-proj-xxx
     ```
     必ず `chmod 600 ~/.pro-review/env.sh`
4. **ChatGPT 側で登録（2026-07 UI）**
   - **開発者モード** ON: 設定 → **セキュリティとログイン** → 開発者モード（旧: アプリ → 詳細設定）
   - **先に `pro-review-tunnel` を起動して接続状態にしておく**（ChatGPT はプラグイン作成時に MCP へ疎通検証する。未接続だと `424` で「Something went wrong」になる）
   - chatgpt.com/plugins → 右上 **+** → 新規プラグイン → 接続で **トンネル** → 一覧から tunnel を選択
   - 認証は **認証なし / 両方** どちらでも可（最小権限なので無認証で OK）
   - 名前は既定で `pro-review Tunnel connector` にする。違う名前にする場合は実行時に `--connector-label` を指定する。

## 起動と利用

```bash
# Path B を実行する（snapshot -> tunnel -> nodriver connector送信 -> watch -> finish）
pro-review-run --thinking --repo /path/to/repo --project my-project --question "bug と security を見て"
```

`pro-review-run --thinking` は `pro-review-tunnel` と `pro-review-tunnel-check` を内部で実行する。
その後 nodriver で ChatGPT を開き、`pro-review Tunnel connector` をこのチャットで選択してから依頼文を送る。

ChatGPT 側で非 5.5Pro の MCP 利用可能モデルに切替できること、登録済み pro-review コネクタがあることは前提。
connector 作成、初回認可、MFA、管理者権限付与は人間/管理者作業のまま。
connector 名が違う場合は次のように指定する。

```bash
pro-review-run --thinking --repo /path/to/repo --project my-project \
  --connector-label "Your Connector Name" \
  --question "bug と security を見て"
```

この有効化は「登録済み connector がある」だけでは足りない。送信するチャットで Developer Mode と pro-review Tunnel connector が選択されている必要がある。nodriver が固定ラベルを見つけられない場合は送信せず `STOP_REASON=connector_unavailable` と `NEXT_ACTION=ChatGPT側でpro-review Tunnel connectorを有効化` を返す。ChatGPT 側で `search` / `fetch` / `save_report` が tool として見えない場合も、ChatGPT はレビューを推測せず同じ stop reason を返す。

## 返信の回収方法

既定は ChatGPT が MCP の `save_report` で保存する。

1. ChatGPT が search/fetch で workspace を読む
2. ChatGPT がレビュー本文を作る
3. ChatGPT が本文の最終行に `[[DONE-<run_id>]]` を付ける
4. ChatGPT が `save_report(project, run_id, body)` を呼ぶ
5. `save_report` が `~/.pro-review/inbox/<project>/REPLY-<run_id>.md` に atomic write する
6. `pro-review-watch --run-id <run_id>` が拾って auto-resume

`search` / `fetch` が使えない surface ではレビューしない。`search` / `fetch` は使えるが `save_report` だけ使えない surface だけ、fallback として nodriver DOM 抽出 → `pro-review-save-reply <project> <run_id>` を使う。

## 状態確認

`pro-review-tunnel-check <project>` は次を確認する。

- `active-project` が対象 project か
- `health.url` があるか
- MCP tool list に `save_report` があるか
- doctor fail が出ていないか

失敗時は `STOP_REASON=<reason>` と `NEXT_ACTION=<next>` を出す。

## 汎用 write/edit が必要な場合

通常は不要。`PRO_REVIEW_FULL=1` は汎用 filesystem write/edit を開く Risk Gate として残すが、既定では使わない。Path B の通常保存は `save_report` のみ。

## 保存・cleanup

`~/.pro-review` は 700、inbox/reports 配下の reply/report は 600 で作成する。`daemon.log` は `CONTROL_PLANE_API_KEY`、`sk-...`、cookie らしき値を redaction して保存する。

最終レポートは次に保存される。

```text
~/.pro-review/reports/<project>/<run_id>/
  request.md
  reply.md
  summary.json
  summary.md
  easy-report.md
  metadata.json
```

不要になった一時データは次で削除できる。

```bash
rm -rf ~/.pro-review/workspace/<project> ~/.pro-review/inbox/<project>
```

永続レポートも消す場合だけ、明示的に次を実行する。

```bash
rm -rf ~/.pro-review/reports/<project>
```

## 退役

- 旧 `PRO_REVIEW_MODE=readonly`（filesystem MCP の read-only proxy）: search/fetch だけで Thinking 系も動くので不要。実装は `scripts/_archive/pro-review-mcp-readonly` に保管
