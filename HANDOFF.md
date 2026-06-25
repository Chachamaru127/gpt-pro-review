# HANDOFF — gpt-pro-review

作成: 2026-06-25
CWD: `/Users/tachibanashuuta/LocalWork/Code/gpt-pro-review`

## 結論

実装・fixture・docs gate は完了。実環境 smoke では Path A live e2e が通過済み。Path B は local tunnel/MCP tool list まで通過し、ChatGPT 側の custom app / connector 作成で止まっている。残りは ChatGPT 側 app creation gate の解消と final closeout。

## 現在の完成ライン

- Path A: `pro-review-run --pro` で `browser-embed -> browser-drive -> save-reply -> watch -> finish` が fixture e2e 済み。live driver は nodriver + 専用 profile + login marker で動く。
- Path B: `search` / `fetch` / `save_report` の bounded MCP が実装済み。ChatGPT が `save_report(project, run_id, body)` で `REPLY-<run_id>.md` を保存する設計。
- 返信採用: `REPLY-<run_id>.md`、inbox 配下、非 symlink、最終行 `[[DONE-<run_id>]]` 完全一致のみ。
- report bundle: `reports/<project>/<run_id>/` に `request.md` / `reply.md` / `summary.json` / `summary.md` / `easy-report.md` / `metadata.json` を保存。
- safety: default MCP は `search` / `fetch` / `save_report` のみ。汎用 write/edit/bash は `PRO_REVIEW_FULL=1` かつ明示 confirmation が必要。
- docs: `SKILL.md`、`SETUP-layer2.md`、`README.md`、`docs/usage.md`、`docs/manual-checklist.md` を現 UX に同期済み。

## 検証済み

- `bash tests/test-report-bundle.sh` PASS
- `bash tests/test-browser-run.sh` PASS
- `bash tests/run-all.sh` PASS（pass=26 fail=0、Path A live/connector-gate 反映後）
- `scripts/pro-review-doctor` OK（nodriver venv importable、tunnel-client/env configured）
- Path A clean repo live smoke: project `gpt-pro-review-patha-live-1782320833`, run_id `1782320834115-915037`, bundle `/Users/tachibanashuuta/.pro-review/reports/gpt-pro-review-patha-live-1782320833/1782320834115-915037`, summary `total=1` / `要確認=1` / `calc.py:3`
- Path B clean repo tunnel smoke: `OK tunnel_lifecycle`, `TOOLS=search,fetch,save_report`
- Path B live ChatGPT attempt: tunnel/tool list OK, but ChatGPT custom app / connector creation failed with `Something went wrong`; `save_report`付きと read-only (`search,fetch`) の両方で失敗したため、write tool が原因ではない。`finish` cleared exposure.
- Path A login UX: `scripts/pro-review-browser-setup --open-login` / `--mark-logged-in`。Path A 実行前に専用 Chrome を閉じる（profile lock 回避）。
- Path B connector UX: generated prompt now requires Developer Mode + pro-review Tunnel connector in the chat and stops with `STOP_REASON=connector_unavailable` instead of inventing a review when `search` / `fetch` are unavailable.

## 次にやること

1. 実環境 doctor:
   ```bash
   scripts/pro-review-doctor
   scripts/pro-review-browser-setup
   ```
   `pro-review-browser-setup` が login gate を出したら、`scripts/pro-review-browser-setup --open-login` で専用 profile を開き、ChatGPT ログイン後に `scripts/pro-review-browser-setup --mark-logged-in` を実行する。最後にその専用 Chrome ウィンドウを閉じてから Path A を走らせる。

2. Path B app creation / live e2e:
   ```bash
   scripts/pro-review-run --thinking --repo <repo> --project <project> --question "<review question>"
   scripts/pro-review-tunnel-check <project>
   ```
   ChatGPT 側で Business / Enterprise / Edu workspace、admin / owner / authorized developer 権限、Developer Mode を確認する。custom app / connector 作成が通ったら、このチャットで pro-review Tunnel connector を有効化して依頼文を貼る。ChatGPT 側が `save_report` を呼び、`finish` で exposure が閉じるところまで確認する。

3. final closeout:
   - `Plans.md` の 6.18 / 6.19 を完了へ更新
   - `HANDOFF.md` に live e2e の実測結果を追記
   - `git status --short` で未追跡が意図した新規ファイルだけか確認

## 置いた仮定

- API route はスコープ外。
- BAN リスク評価はユーザー指定により対象外。
- 旧 claude-in-chrome fallback は現 UX から外し、nodriver 失敗時は `manual_save` 手順を出す。
- 実 ChatGPT UI の送信 / connector 操作は agent だけでは完了できないため、ユーザーのログイン済み UI が必要。
- `.claude/memory/decisions.md` / `.claude/memory/patterns.md` はこの repo には存在しないため、判断根拠は `Plans.md`、`docs/spec/00-project-spec.md`、harness-mem の project scoped resume pack。

## 未完了 gate

- 6.18: 実 ChatGPT non-5.5Pro + Tunnel app creation / Path B live e2e
- 6.19: live 結果込みの final HANDOFF
