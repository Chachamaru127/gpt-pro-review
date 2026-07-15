# gpt-pro-review

## ひとことで

ChatGPT Web にコードレビューを頼み、回答をローカルに安全保存する道具です。

## たとえると

これは「外部の専門家に書類を見てもらう受付係」です。

1. あなたの作業フォルダから、見せてよい材料だけを集めます。
2. ChatGPT にレビュー依頼を送ります。
3. ChatGPT の回答を受け取ります。
4. 回答を決まった場所に保存します。
5. Claude / Codex 側で、対応するかを判断します。

コードを勝手に直す道具ではありません。
レビュー結果を受け取る道具です。

## まず何ができるか

| できること | 何のため |
|---|---|
| ChatGPT Pro にレビュー依頼を送る | もう一人の強いレビュアーに見てもらうため |
| ローカルフォルダを ChatGPT に読ませる | 大きな repo を必要な分だけ読ませるため |
| レビュー回答を保存する | あとで見返せる証跡にするため |
| `DONE` マーカーで完了確認する | 別の回答や途中回答を誤って拾わないため |
| Web Search / Deep Research 方針を指定する | 最新情報が必要な時だけ外部調査させるため |
| 前回の指摘が直ったかを再レビューする | 「直したつもり」を ID 付きで追跡するため |
| 指摘を台帳に記録・集計する | 採用率や再出現を数字で見るため |
| 2 つのレビュー結果を突き合わせる | 両方が指摘した箇所から直すため |

## 使う場面

- 変更差分を、ChatGPT Pro に見てもらいたい。
- Claude / Codex だけで結論を出したくない。
- レビュー結果を `reports/` に残したい。
- ChatGPT にローカル workspace を読ませたい。
- ただし、汎用の書き込みや shell 実行は渡したくない。

## 使わない場面

- ChatGPT にコードを自動修正させたい時。
- ChatGPT に自由なファイル書き込みを許したい時。
- OpenAI API だけで完結させたい時。
- 機密値そのものを ChatGPT に読ませたい時。

API（= プログラムから OpenAI を直接呼ぶ方式）は使いません。
この repo は ChatGPT Web を使います。

## 全体像

```
あなた / Claude / Codex
        |
        | 依頼を作る
        v
gpt-pro-review
        |
        +-- Path A: ChatGPT Web をブラウザ操作
        |          diff / ファイル本文を貼る
        |
        +-- Path B: Secure MCP Tunnel
                   search / fetch / save_report だけ渡す
```

MCP（= ChatGPT からローカルの道具を呼ぶ接続方式）は Path B だけで使います。

Path A は MCP 不要です。

## 2 つの道

| Path | 使う時 | 仕組み | 保存方法 |
|---|---|---|---|
| Path A | Pro 品質がほしい時 | Nodriver（= Chrome を自動操作する Python ライブラリ）で ChatGPT Web を動かす | 画面から回答を取得して保存 |
| Path B | ChatGPT に workspace を読ませたい時 | Nodriver で ChatGPT Web を操作し、Secure MCP Tunnel で `search` / `fetch` / `save_report` を渡す | ChatGPT が `save_report` で保存 |

迷ったら Path A です。

Path A はセットアップが軽いです。
Path B はコネクタ設定が必要です。

## 保存される場所

すべて `~/.pro-review` に入ります。

```text
~/.pro-review/
  browser/                  # ChatGPT 専用 Chrome profile
  workspace/<project>/       # Path B 用の一時 snapshot
  inbox/<project>/           # 返信の受け取り口
  reports/<project>/<run_id>/
    request.md
    reply.md
    summary.json
    summary.md
    easy-report.md
    metadata.json
```

`reports/<project>/<run_id>/` が最終成果物です。

## 重要な安全ルール

| ルール | 理由 |
|---|---|
| live repo を直接公開しない | 余計なファイルを見せないため |
| `.git` は送らない | 履歴に秘密がある可能性があるため |
| secret scan を通す | API key や token の誤送信を防ぐため |
| Path B の tool は 3 つだけ | ChatGPT に強すぎる権限を渡さないため |
| `save_report` は保存先固定 | 任意パスへの書き込みを防ぐため |
| 回答の最終行に `[[DONE-...]]` が必要 | 途中回答を拾わないため |

Path B で渡す tool は次の 3 つだけです。

| Tool | 意味 |
|---|---|
| `search(query)` | workspace 内のファイルを探す |
| `fetch(id)` | 指定ファイルを読む |
| `save_report(project, run_id, body)` | 最終レビューだけを保存する |

## 導入

### 1. repo を取る

```bash
git clone https://github.com/Chachamaru127/gpt-pro-review.git
cd gpt-pro-review
```

private repo なので、GitHub 認証が必要です。

### 2. skill として登録する

Claude / Codex / agents から見える場所に symlink（= 参照用の近道）を作ります。

```bash
mkdir -p "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills"

ln -sfn "$PWD" "$HOME/.claude/skills/gpt-pro-review"
ln -sfn "$PWD" "$HOME/.codex/skills/gpt-pro-review"
ln -sfn "$PWD" "$HOME/.agents/skills/gpt-pro-review"
```

これで `$gpt-pro-review` として見つかります。

### 3. コマンドを PATH に置く

PATH（= shell がコマンドを探す場所）に `~/.local/bin` を入れます。

```bash
mkdir -p "$HOME/.local/bin"

for f in scripts/pro-review-*; do
  ln -sf "$PWD/$f" "$HOME/.local/bin/$(basename "$f")"
done

ln -sf "$PWD/scripts/build-review-packet" "$HOME/.local/bin/build-review-packet"
ln -sf "$PWD/scripts/build-review-packet" "$HOME/.local/bin/gpt-pro-review-packet"
```

`~/.local/bin` が PATH に無い場合だけ、次を追加します。

```bash
printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zshrc"
source "$HOME/.zshrc"
```

確認します。

```bash
command -v pro-review-run
command -v pro-review-doctor
```

### 4. 診断する

```bash
pro-review-doctor
```

`OK` が多ければ進めます。

`FIX` や `MANUAL` が出たら、その行を直します。

## Path A 導入

Path A は ChatGPT Web をブラウザで動かします。

最初に専用 Chrome profile を作ります。

```bash
pro-review-browser-setup --install
pro-review-browser-setup --open-login
```

開いた Chrome で ChatGPT にログインします。

未ログインのまま `pro-review-run --pro` を実行した時も、
tool が `FALLBACK:login required` と判断して同じログイン画面を自動で開きます。

ログイン後に marker（= ログイン済み印）を付けます。

```bash
pro-review-browser-setup --mark-logged-in
```

その Chrome ウィンドウを閉じます。

閉じる理由:

- Nodriver が同じ profile を使うため。
- 人間が開いたままだと profile lock になります。
- profile lock は「同じ鍵を二人で同時に使う」状態です。

## Path A 使い方

一番よく使う形です。

```bash
pro-review-run --pro \
  --repo /path/to/repo \
  --project my-review \
  --question "bug と security を見て"
```

`--repo` は見てほしい repo です。

`--project` は保存用の名前です。

`--question` はレビュー観点です。

### Web Search / Deep Research

Path A では外部調査の方針を指定できます。

```bash
pro-review-run --pro \
  --repo /path/to/repo \
  --project my-review \
  --web-search auto \
  --deep-research auto \
  --question "最新仕様も踏まえて review"
```

| Option | 値 | 意味 |
|---|---|---|
| `--web-search` | `auto` | 必要なら ChatGPT が Search を使う |
| `--web-search` | `on` | Search 使用を明示する |
| `--web-search` | `off` | Search を使わせない |
| `--deep-research` | `auto` | 必要なら Deep Research を選ぶ |
| `--deep-research` | `on` | Deep Research を必ず選ぼうとする |
| `--deep-research` | `off` | Deep Research を使わせない |

`auto` は ChatGPT UI の Auto ボタンではありません。

`auto` はこの tool の方針名です。

Deep Research は、Nodriver が送信前に選びます。

試す順番:

1. `/Deepresearch`
2. `/Deep Research`
3. 左側の `+` ボタン
4. tools menu の `Deep research`
5. typo 表記の `Deep reseach`

選べない場合は、通常レビューに落としません。

`FALLBACK:deep research unavailable` で止めます。

理由は単純です。

Deep Research していないのに、したふりをしないためです。

### 入力と取得のしくみ

依頼は packet を `.md` ファイルとして添付します。

入力欄に大きな依頼文を直書きしません。

添付できない時だけ、入力欄への直書きに切り替えます。

回答はコピーボタンから取り込みます。

うまくいかない時だけ、画面の読み取りに切り替えます。

### 答えが保存されなかった時（復旧）

Pro は答えるのに数分かかります。

待ち時間の既定は 600 秒です（`--timeout` で変えられます）。

待ち切れずに終わっても、答えはブラウザに残ります。

その時はこれで救えます。

```bash
pro-review-recover <project> <run_id>
```

`pro-review-recover` は、開いている会話の最後の答えを取り込みます。

`[[DONE-<run_id>]]` を確認して、保存とレポート化まで進めます。

`pro-review-run --pro` が時間切れで終わった時は、画面に `recover:` の行で実行コマンドが出ます。

会話タブを閉じてしまっても大丈夫です。

送信成功時に会話の URL を控えてあります（`chatgpt.com` の URL だけを受け付けます）。

取り込みに失敗すると、控えた URL を自動で開き直して、もう 1 回だけ取得を試します。

それでも失敗した時は、原因調査用に画面の中身（DOM 抜粋）と screenshot を
`reports/<project>/<run_id>/` に自動保存します。

## Path B 導入

Path B は Secure MCP Tunnel を使います。

Secure MCP Tunnel は、ChatGPT とあなたの PC を安全につなぐ通路です。

外からあなたの PC に入る穴は開けません。

あなたの PC から OpenAI 側へ outbound HTTPS（= 外向き通信）でつなぎます。

詳しい初回設定は [SETUP-layer2.md](SETUP-layer2.md) です。

必要なもの:

| 必要なもの | 何に使うか |
|---|---|
| `tunnel-client` | OpenAI Tunnel につなぐ |
| `CONTROL_PLANE_TUNNEL_ID` | どの tunnel か識別する |
| `CONTROL_PLANE_API_KEY` | tunnel を使うための鍵 |
| ChatGPT Developer Mode | ChatGPT から connector を使うため |
| pro-review Tunnel connector | ChatGPT 側の接続口 |

## Path B 使い方

`pro-review-run --thinking` が snapshot 作成、tunnel 起動、tool 確認、nodriver での connector 選択、依頼文送信、watch、finish まで行います。

```bash
pro-review-run --thinking \
  --repo /path/to/repo \
  --project my-review \
  --question "bug と security を見て"
```

ChatGPT 側では、事前に次を登録しておきます。

1. Developer Mode
2. pro-review Tunnel connector
3. 同じ tunnel_id の connector

実行時は nodriver が `pro-review Tunnel connector` という固定ラベルを探して、そのチャットで選択してから送信します。
connector 名が違う場合は `--connector-label "..."` を付けます。
connector 作成、初回認可、MFA、管理者権限付与は人間操作のままです。

ChatGPT は次の順で動きます。

1. `search("")` でファイル一覧を見る。
2. `fetch(id)` で必要なファイルを読む。
3. レビュー本文を書く。
4. 最終行に `[[DONE-<run_id>]]` を付ける。
5. `save_report(...)` で保存する。

## 結果を見る

レビューが終わると、bundle（= ひとまとまりの保存物）ができます。

```text
~/.pro-review/reports/<project>/<run_id>/
```

よく見るファイルはこの 4 つです。

| ファイル | 中身 |
|---|---|
| `request.md` | ChatGPT に送った依頼 |
| `reply.md` | ChatGPT の回答 |
| `summary.md` | 指摘の要約 |
| `easy-report.md` | ユーザー向けの読みやすい報告 |

## 具体例

`calc.py` のゼロ除算を見てもらう例です。

```bash
pro-review-run --pro \
  --repo "$PWD" \
  --project calc-review \
  --question "divide(a, b) のゼロ除算とテスト不足を見て"
```

成功すると、だいたい次のように残ります。

```text
~/.pro-review/reports/calc-review/<run_id>/
  request.md
  reply.md
  summary.md
  easy-report.md
```

## もう一回見てもらう（followup 再レビュー）

前回の指摘が直ったかを、もう一度 ChatGPT に確認してもらえます。

各指摘には ID（`f-` で始まる短い印）が付きます。

ID は指摘の内容から作るので、並び順が変わっても同じ指摘は同じ ID です。

```bash
pro-review-run --pro \
  --repo /path/to/repo \
  --project my-review \
  --followup <前回の run_id>
```

送る内容は 3 点セットです。

1. 前回の指摘一覧（ID 付きの表）
2. その後の修正 diff（= 何をどう変えたか）
3. 「ID ごとに `resolved` / `still-open` / `new` で答えて」という指示

毎回、新しい会話として送ります。

前の会話の続きには書き込みません。

結果の `metadata.json` に `previous_run_id` が入り、round 同士がつながります。

## 指摘を台帳に残す（ledger）

レビューのたびに指摘を記録して、あとから数字で振り返れます。

```bash
pro-review-ledger append <project> <summary.json のパス> --run-id <run_id>
pro-review-ledger stats <project>
```

`stats` が出すもの:

| 項目 | 意味 |
|---|---|
| `total_findings` | 記録した指摘の総数 |
| `rounds` | レビューした回数 |
| `observed_runs` | 保存されている run bundle の数（参考値） |
| `recurring_ids` | 2 回以上出てきた指摘（= 未解決の可能性） |
| decision の割合 | 対応 / 見送り / 要確認 の内訳 |

この数字は「あなたがどれだけ採用したか」の目安です。

指摘の正誤を判定するものではありません（出力にも毎回その注意が付きます）。

## 2 つのレビューを突き合わせる（consensus）

ChatGPT と Codex など、別々のレビュー結果を比べられます。

```bash
pro-review-consensus summary_a.json summary_b.json --out consensus.json
```

同じ file:line への指摘は `agreed` に入ります。

片方だけの指摘は `only_a` / `only_b` に入ります。

両方が指摘した箇所は、直す優先度が高いと判断できます。

このコマンドは比較だけをします。

他の AI を勝手に呼び出すことはありません。

## 依頼文を自分で用意する（--packet-file）

repo からの自動組み立てを飛ばして、用意した Markdown をそのまま送れます。

```bash
pro-review-run --pro \
  --repo /path/to/repo \
  --project my-review \
  --packet-file my-request.md
```

この場合も secret scan と `DONE` マーカーは必ず適用されます。

安全チェックを飛ばす近道ではありません。

## よくある失敗

### `FALLBACK:login required`

ChatGPT 専用 profile にログインできていません。
`pro-review-run --pro` はこの fallback を見たら、専用 Chrome のログイン画面を自動で開きます。

```bash
# 開いた Chrome で ChatGPT にログインする
# その Chrome を閉じる
pro-review-browser-setup --mark-logged-in
```

### `FALLBACK:browser profile already open`

専用 Chrome が開いたままです。

閉じてから再実行します。

### `FALLBACK:deep research unavailable`

Deep Research を選べませんでした。

ChatGPT UI に `Deep research` が出るか確認します。

左側の `+` ボタン内にある場合は、最新版では拾えるようにしています。

### `STOP_REASON=connector_unavailable`

Path B で connector が有効ではありません。

ChatGPT 側で Developer Mode と pro-review connector を有効にします。
登録済み connector が見つからない場合、nodriver は送信せずここで止まります。

### `STOP_REASON=tunnel_not_running`

tunnel が起動していません。

```bash
pro-review-tunnel
pro-review-tunnel-check <project>
```

### secret scan で止まる

送信前に秘密っぽい文字列を検出しています。

止まるのが正しいです。

対象ファイルを絞るか、秘密を消します。

## コマンド早見表

| コマンド | 何をするか |
|---|---|
| `pro-review-doctor` | 全体診断 |
| `pro-review-browser-setup --install` | Path A のブラウザ環境を用意 |
| `pro-review-browser-setup --open-login` | 専用 Chrome で ChatGPT ログイン |
| `pro-review-run --pro` | Path A 実行 |
| `pro-review-run --thinking` | Path B 実行（tunnel + nodriver connector送信 + 保存待ち） |
| `pro-review-tunnel` | Path B tunnel 起動 |
| `pro-review-tunnel-check <project>` | tunnel と tool を確認 |
| `pro-review-watch` | inbox の返信を待つ |
| `pro-review-finish` | report bundle を作る |
| `pro-review-run --pro --followup <run_id>` | 前回指摘の再レビュー |
| `pro-review-ledger` | 指摘台帳への記録と集計 |
| `pro-review-consensus` | 2 つのレビュー結果の突き合わせ |

## テスト

全部まとめて確認します。

```bash
bash tests/run-all.sh
```

GitHub に push すると、GitHub Actions（= GitHub 上の自動テスト）が
macOS 環境で同じテストと shellcheck（= shell script の静的検査）を実行します。

個別に見たい時は次です。

```bash
bash tests/test-browser-drive.sh
bash tests/test-browser-run.sh
bash tests/test-search-fetch.sh
bash tests/test-docs-sync.sh
```

## cleanup

一時データだけ消します。

```bash
rm -rf ~/.pro-review/workspace/<project>
rm -rf ~/.pro-review/inbox/<project>
```

永続レポートも消す場合だけ、次を実行します。

```bash
rm -rf ~/.pro-review/reports/<project>
```

## もっと詳しく

| 文書 | 役割 |
|---|---|
| [docs/usage.md](docs/usage.md) | 普段の使い方 |
| [SETUP-layer2.md](SETUP-layer2.md) | Path B / Tunnel 設定 |
| [docs/spec/00-project-spec.md](docs/spec/00-project-spec.md) | 仕様 |
| [docs/manual-checklist.md](docs/manual-checklist.md) | 実機 smoke の記録 |
| [docs/oracle-adoptions.md](docs/oracle-adoptions.md) | Oracle から取り込んだ browser パターン |
| [Plans.md](Plans.md) | 実装計画と完了履歴 |

## Cursor から使う

1. この repo を Cursor で開く（`/gpt-pro-review` コマンドが使える）
2. `scripts/pro-review-doctor` → Path A/B を実行
3. `exit 3` 時は `browser_state:` を読み、完了後 `scripts/pro-review-recover <project> <run_id>`

詳細: [`AGENTS.md`](AGENTS.md)、[`.cursor/skills/gpt-pro-review/SKILL.md`](.cursor/skills/gpt-pro-review/SKILL.md)
