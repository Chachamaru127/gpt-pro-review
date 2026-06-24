# HANDOFF — gpt-pro-review（nodriver 移行）

宛先: `~/LocalWork/Code/gpt-pro-review` を **CWD にして**再開する新セッション
作成: 2026-06-23

> この CWD で起動すれば、前回の根因（CWD が Context Harness worktree のまま＝CH の CLAUDE.md が常時 ON で固有語が漏れた）が**構造的に消える**。この skill は自前の project 文脈で動く。

## このプロジェクトは何か

- **汎用**のブラウザ越し外部レビュー skill。どの repo の diff でも GPT に貼って second-opinion を得る
- **project 非依存**。GIFT / Context Harness とは**無関係**。固有語（顧客名 / codename / SF field 名 等）を skill 本体に入れない（CLAUDE.md 黄金律）
- user スコープへ symlink 済: `~/.claude/skills/gpt-pro-review` → このフォルダ

## 決定事項（why 付き）

- **ブラウザ経路は nodriver**（patchright / Camoufox でなく）。理由: ChatGPT の Cloudflare は automation-protocol fingerprinting が主力 → CDP 直駆動の nodriver が実測首位（2026 ベンチ）。patchright / Camoufox は Playwright fork で protocol 痕跡が残る。headless 不要（ログイン済み headed 運用）なので Camoufox の headless 優位は無関係
- **API route は採用しない**。ユーザー判断により、接続はあくまで nodriver + ChatGPT Web 前提。API 可否確認や API pivot は Phase 6 から除外。
- **secret scan は汎用のまま強化**（6.1）。固有語は対象 repo の `.pro-review-denylist` で供給（6.1b）。skill 本体に literal を書かない（grep 0 件が DoD）

## 現状（このセッションで完了済）

- 移設（`~/.claude/skills` → ここ）・symlink 復元・`git init`・`.gitignore`（profile/venv/secrets/reports 除外）
- `Plans.md` に **Phase 6**（nodriver-first 完成計画）記載。API route は明示除外、`docs/spec/00-project-spec.md` で target contract 固定済
- `.harness-mem/` は `.gitignore` 追加済
- baseline commit 済（このファイルを含む）

## 次の一手

- `/harness-work 6.3`（secret scan 汎用強化）→ nodriver Path A / Tunnel Path B の UX 完成
- API ではなく、ブラウザで依頼・回答取得・Claude 側判断・`$easy` 報告までを完成させる

## 失敗の教訓（再発防止）

1. skill 本体に他 project の固有語を焼かない（前回 6.1 で CH の codename/SF field を混入 → 修正済）
2. subagent に project ルールを渡したら、**出力採用前に「この助言はこの contract に属すか」を1回問う**（harness-plan の「渡された情報をそのまま Plans に落とさない」を飛ばさない）
3. pivot 時は CWD かタスク文脈を物理的に切替える（← 今回この HANDOFF + 新 CWD がその実践）

## 引き込まない別ワークストリーム

- **GIFT 課題自動処理**（Context Harness repo の Issue → 3 PR #150/#152/#153）は**別件で保留中**（Slack 承認待ち）。この skill とは無関係。混ぜない
