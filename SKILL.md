---
name: gpt-pro-review
description: Send a code review / research / implementation-draft request to ChatGPT (GPT-5.5 Pro or Thinking-High) when this agent cannot produce the second-opinion itself. Two paths: (A) Pro = browser-paste via claude-in-chrome with optional GitHub connector, DOM-extract the reply; (B) Thinking-High / non-Pro = local MCP search/fetch over an OpenAI Secure MCP Tunnel. Both paths converge: save the reply to inbox locally, watcher auto-resumes Claude, finish persists to reports. Use when the user says "ask GPT/ChatGPT/Pro to review", "外部モデルにレビュー/リサーチさせて", "Proに調べさせて/実装させて", or wants an independent second opinion from GPT-5.5 Pro / GPT-5.5 Thinking. Do NOT use for reviews this agent should do itself.
---

# gpt-pro-review

別の強力なモデル（典型的には ChatGPT の **GPT-5.5 Pro** または **Thinking-High**）に **レビュー / リサーチ / 実装ドラフト** を依頼するための導線。GPT-5.5 Pro は ChatGPT サブスク枠の Web 専用で、このエージェントから API では呼べない。そこで **コードを向こうに見せる + 答えをファイルで受け取る** 形で実現する。

## 2 パス構成（OpenAI 公式制約を受け入れた設計）

```
┌─────────────────────────────────┬─────────────────────────────────────┐
│ Path A: Pro (ブラウザ埋め込み)  │ Path B: Thinking-High / 非 Pro      │
├─────────────────────────────────┼─────────────────────────────────────┤
│ 入力: プロンプトに埋め込み      │ 入力: Secure MCP Tunnel + search/   │
│   (or GitHub コネクタ経由)      │       fetch でフォルダ直読み        │
│ ブラウザ: claude-in-chrome 必須 │ ブラウザ: claude-in-chrome (送信のみ)│
│ 返信: DOM 抽出 → ローカル保存   │ 返信: DOM 抽出 → ローカル保存       │
│ 完了検知: 完了マーカー [[DONE-N]]│ 完了検知: 完了マーカー [[DONE-N]]   │
└─────────────────────────────────┴─────────────────────────────────────┘
共通: watcher が inbox を監視 → auto-resume → reports/<project>/ に永続化
```

## なぜ 2 パスか（OpenAI 公式制約）

| モデル surface | カスタム MCP 呼び出し | 通常の MCP write |
|---|---|---|
| **GPT-5.5 Pro 通常チャット** | **呼べない**（"Custom connectors are currently only usable when in deep research mode for Pro users"）| - |
| **GPT-5.5 Pro Agent モード** | **呼べない**（"Agent mode will not use custom apps"）| - |
| GPT-5.5 Pro Deep Research | search/fetch のみ（時間かかる、本 Skill では既定で使わない）| 不可 |
| **Thinking / Thinking-High** | 任意の read-only ツール OK | silently disabled (Pro/Plus) |

つまり Pro 経由でレビューさせたい場合、MCP は使えない → **プロンプトに埋め込んで送る** しかない（Path A）。
Thinking-High なら MCP の read 系が呼べる → **search/fetch で workspace を読ませる**（Path B）。
両 path とも、返信は ChatGPT 側から書けない（write disabled）→ **DOM 抽出してローカル保存** に統一。

## Path A: Pro ブラウザ埋め込み

### いつ使うか
- 速さ・品質ともに Pro が要る code review
- 重要な独立第二意見
- GitHub 上のブランチ全体を読ませたい（オプション）

### 手順（エージェントが実行）

1. **範囲を決める**：repo / project 名 / 観点（`--question`）。GitHub コネクタ経由で読ませる場合は `--github-branch BRANCH` を渡す（コードは埋め込まない）。
2. **依頼パケットを生成（state-less）**：
   ```bash
   pro-review-browser-embed <repo> <project> --question "<観点>"
   # GitHub 経由なら:
   pro-review-browser-embed <repo> <project> --github-branch <branch> --question "<観点>"
   ```
   出力の機械可読行から `project_name / since / inbox / request_file / clip` を取得。
   - **secret scan** が `.env` 等の秘密情報パターンを検出すると **exit 1 で停止**（誤検知時は `ALLOW_SECRETS=1 pro-review-browser-embed ...`）
   - max-bytes default 80_000 でトークン無音切り捨て対策。超過分は「⚠ 同梱省略」として明示
   - 末尾に **`[[DONE-<since>]]` 完了マーカー**を必ず注入
3. **ブラウザ送信（claude-in-chrome）**：
   - `tabs_context_mcp` で既存ログイン済 ChatGPT タブを探す（無ければ作る、**無料アカウントを新規に開かない**）
   - **エージェントモード OFF** の通常チャットになっているか確認（read_page でモード判定 or 手動チェック）
   - モデル = **GPT-5.5 Pro** を確認
   - GitHub コネクタを使う場合は ChatGPT 側で公式 GitHub コネクタを **ON にしてブランチ指定**（ユーザー操作）
   - `request_file` の内容（=クリップボード）を貼り、送信
4. **完了待ちと DOM 抽出**：
   - 生成中は 30〜60s 間隔で `read_page` / `get_page_text` で `data-message-author-role="assistant"` の最新メッセージを取得
   - **最終 1 行の完全一致**で `[[DONE-<since>]]` を検出（Skeptic 指摘の誤検知防止）
   - 検出したら assistant 本文を抽出し、
     ```bash
     <抽出本文> | pro-review-save-reply <project> <since>
     ```
     でローカル inbox にアトミック保存
5. **auto-resume**：並行して run_in_background で立てた watcher が
   ```bash
   pro-review-watch <inbox> --since <since>
   ```
   保存を検知し終了 → harness がエージェントを自動再呼び出し
6. **永続化＋クリーンアップ**：再開後、
   ```bash
   pro-review-finish <project> <reply-path>
   ```
   で `reports/<project>/<時刻>-<name>.md` に永続化。Path A は state-less なので `active-project` の解除不要（Path B daemon と干渉しない）

### Skeptic 5 件への対処

| 指摘 | 対処 |
|---|---|
| マーカー誤検知/未出力 | 最終 1 行完全一致で判定。引用や説明文中の `[[DONE-N]]` は無視 |
| Path A/B state 衝突 | Path A は state-less（引数明示渡し、active-project 使わない） |
| GitHub コネクタ Pro 通常で使えるか未検証 | **opt-in（`--github-branch` 指定時のみ）**。実機検証はユーザー操作 |
| トークン無音切り捨て | max-bytes default 80k + 「⚠ 同梱省略」旗 |
| ブラウザ消失の脆さ | watch のタイムアウト + tab URL 検証 + 「ブラウザ消失」を明示エラー化 |

## Path B: Thinking-High / 非 Pro

### いつ使うか
- 普段使い（Pro より少し落ちる程度の品質、レビュー用途なら十分）
- フォルダ全体を ChatGPT に直読みさせたい（pro-review-mcp 経由）

### 手順（既存フロー、SKILL の核として残す）

1. **snapshot + 依頼パケット**：
   ```bash
   pro-review-start <repo> <project> --mode review --question "<観点>"
   ```
   `pro-review-snapshot` で `.git`・秘密情報を除いた read-only スナップショットを `~/.pro-review/workspace/<project>/` に作る。依頼文は `search()` / `fetch()` 指示。
2. **デーモン起動**：
   ```bash
   pro-review-tunnel   # run_in_background
   ```
   `pro-review-mcp` 経由で **search/fetch 専用 MCP**（`pro-review-mcp-search-fetch`）が起動。`active-project` で公開対象を絞る。
3. **ChatGPT 側**：Thinking-High に切替、Developer Mode + pro-review コネクタ有効化、依頼文を貼り送信。
4. **完了待ち + DOM 抽出 + 保存**：Path A と共通（save-reply / watch / finish）
5. **クリーンアップ**：finish でデーモン停止＋`active-project` 解除

### Business / Enterprise / Edu の場合

`PRO_REVIEW_FULL=1 pro-review-tunnel` で filesystem MCP を素のまま公開 → ChatGPT が直接 inbox に write_file する旧フロー（Pro/Plus では silently disabled なので動かない）。

## 共通: 露出ライフサイクル

- 公開されるのは **active-project の workspace（読）** のみ。ライブ repo は晒さない。
- snapshot は `.git`・秘密情報を除外し、**secret scan** 通過 + **OS read-only**（`chmod a-w`）。
- Path A: state-less。Path B: snapshot 開始 → finish で解除。
- 複数プロジェクトは `workspace/<project>` `inbox/<project>` `reports/<project>` で分離（同名・別パスは取り違え防止で拒否）。
- Path A の embed プロンプト build 直前で **secret scan**（path A 唯一の防御線）

## スクリプト一覧

| script | 役割 | 使い所 |
|---|---|---|
| `pro-review-browser-embed` | Path A orchestrator（state-less） | Pro ブラウザ送信 |
| `build-review-packet` | embed/connector/github-branch パケット生成 | browser-embed 内で呼ばれる、単独でも可 |
| `pro-review-start` | Path B orchestrator（snapshot + 依頼文） | Thinking-High 経由 |
| `pro-review-run` | コピペ版の一括ライフサイクル | Path B フォールバック |
| `pro-review-snapshot` | クリーンなスナップショット生成 | start が内部で呼ぶ |
| `pro-review-tunnel` | tunnel-client を pro-review プロファイルで起動 | Path B デーモン。`PRO_REVIEW_FULL=1` でフルアクセスに切替 |
| `pro-review-mcp` | MCP エントリ。既定で search/fetch 専用 MCP | tunnel-client が呼ぶ |
| `pro-review-mcp-search-fetch` | Deep Research 互換 MCP（read-only） | tunnel-client が起動する本体 |
| `pro-review-save-reply` | DOM 抽出本文を inbox にアトミック保存 | **両 path 共通の返信入口** |
| `pro-review-watch` | inbox 監視 → 返信検知で終了 | run_in_background で auto-resume |
| `pro-review-finish` | reports/ 永続化＋デーモン停止＋クリーンアップ | 締め |

## テスト

```bash
bash ~/.claude/skills/gpt-pro-review/tests/run-all.sh
```

全 6 ファイル / 47 アサーション。Path A / Path B 両方を fixture 偽返信で統合テストまで通す。手動 e2e（実 ChatGPT 操作）は Phase 5（SKILL 外）で確認する。

## セットアップ（ユーザーが一度だけ行う）

Path B（MCP）を使う場合のみ：`SETUP-layer2.md` 参照。tunnel-client 入手 / tunnel_id・runtime key 発行（`~/.pro-review/env.sh`, 0600）/ ChatGPT 開発者モード ON + Tunnel コネクタ登録。

Path A は MCP 不要。claude-in-chrome 拡張が ChatGPT タブに接続できれば即動く。

## ガードレール

- これはエージェント自身がやるべきレビューの代替ではなく、**独立した第二意見**を得る導線
- ブラウザ自動化は **自分の Pro アカウント・有人・低頻度・人間ペース** で使う。規約はグレー。非常用に手貼りへ退避できる状態を保つ
- `implement` モードは **適用前に差分提示の承認** を必ず挟む。勝手に本番を壊さない
- secret scan が落ちたら embed プロンプト build を必ず失敗させる。`ALLOW_SECRETS=1` は誤検知時の明示上書きのみ
- 汎用ツール。特定の案件・ブランド・顧客に依存しない

## 退役

- `PRO_REVIEW_MODE=readonly`（filesystem MCP read-only proxy）: search/fetch で Thinking も動くため不要。`scripts/_archive/pro-review-mcp-readonly` に保管
- 「ChatGPT が inbox に直接書く」前提の文言: Pro/Plus では write 系が silently disabled で動かないため全削除。代わりに **save-reply 経由のローカル保存** に統一
