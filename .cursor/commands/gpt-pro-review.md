ChatGPT に独立レビューを依頼する `gpt-pro-review` スキルを使います。

まずリポジトリ直下の `SKILL.md`（または `.cursor/skills/gpt-pro-review/SKILL.md`）を読み、以下の手順で進めてください:

1. ユーザーの依頼から Path A (`pro-review-run --pro`) か Path B (`pro-review-run --thinking`) を選ぶ
2. 送信前に secret scan / final packet scan の gate を尊重し、`ALLOW_SECRETS=1` で安易に通さない
3. レビュー依頼には合格ラインを明記する
4. 返信を `pro-review-save-reply` / `pro-review-finish` で report bundle に保存し、最後に露出を閉じる

## Cursor 実行時の注意

- **GUI Chrome が必要**: Path A/B の live 実行は nodriver が専用 Chrome に接続する。Cursor のサンドボックス/バックグラウンド実行では `Failed to connect to browser` になり得る。**フォアグラウンドターミナル**で実行するか、ユーザーに手動実行を依頼する。
- **timeout ≠ 失敗**: Pro 生成は分単位。`exit 3` + `STILL_GENERATING` + `browser_state:` は「まだ生成中 or 取得待ち」の可能性が高い。`BROWSER_STATE_SUMMARY` を読んで判断し、完了後は `pro-review-recover <project> <run_id>`。
- **不明点はユーザーへ**: ログイン/MFA/CAPTCHA、connector 初回認可、live 添付/コピーの成否は代行しない。判断できない時は無理に続けずユーザーに聞く。

## 最短コマンド

```bash
scripts/pro-review-doctor
scripts/pro-review-run --pro --repo "$(pwd)" --project my-review --question "bug と security を見て"
# timeout 後:
scripts/pro-review-recover my-review <run_id>
```
