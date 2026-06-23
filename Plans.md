# gpt-pro-review Plans.md

作成日: 2026-06-22

このドキュメントは user-scope Skill `~/.claude/skills/gpt-pro-review/` の改修計画。
正本（spec contract）は `SKILL.md`。本ファイルは task ledger（precedence: SKILL.md > Plans.md）。

## Context

OpenAI 公式仕様の制約が判明したため、Skill を **2 パス構成** に再設計する。

**確定した制約**:
- ChatGPT Pro 通常チャット: custom MCP は実質呼べない（公式: "Custom connectors are currently only usable when in deep research mode for Pro users"）
- Agent モード: custom MCP 不可（公式: "Agent mode will not use custom apps"）
- Deep Research: search/fetch で可だが応答時間長く非実用（ユーザー却下）
- Thinking-High: custom MCP（read-only）利用可（実検証済み）
- Pro/Plus アカウント全モード: write 系 MCP ツールは silently disabled

**新仕様**:
- Path A (Pro): ブラウザ経由でプロンプト埋め込み送信。MCP 不使用。`[[DONE-<ts>]]` マーカー＋DOM 抽出で返信回収。GitHub コネクタ ON は **オプション** で公式コネクタ経由（仕様可否は実機要検証）
- Path B (Thinking-High / 非 Pro): 既存ローカル MCP search/fetch を維持。返信は DOM 抽出で `save-reply` 経由ローカル保存に統一

## team_validation_mode

`subagent` — Skeptic / Architecture+Security / QA+TDD の 3 fork 並列レビュー実施済み。

## Spec delta

正本 `SKILL.md` を 2 パス構成で書き直す。precedence: SKILL.md > Plans.md。

主要変更:
1. 冒頭に 2 パス構成図と「いつどっち使うか」の判断表
2. Path A セクション: ブラウザ送信フロー（claude-in-chrome 運転手順、GitHub オプション、DOM 抽出、マーカー縛り）
3. Path B セクション: ローカル MCP search/fetch + Thinking-High
4. 共通セクション: 露出ライフサイクル、reports 永続化、save-reply 経由統一
5. 退役: 「ChatGPT が inbox に直接書く」前提の文言を全削除（Pro/Plus 環境で永遠に動かないため）
6. `PRO_REVIEW_MODE=readonly` 退役（search-fetch だけで Thinking も動く）。`PRO_REVIEW_FULL=1` は Business/Ent 向けに残す

## unknown_data

- **GitHub 公式コネクタが Pro 通常チャットで呼べるか** (`absent` ではなく `unknown`): "custom MCP は不可" の制約が「公式コネクタにも適用されるか」は実機検証必要
- **ChatGPT UI のトークン無音切り捨て閾値**: 公式未公表。経験則で 80k bytes 程度に max-bytes を絞る
- **claude-in-chrome の read_page が "Agent モード OFF" を DOM で取れるか**: 実機要確認（取れなければ手動チェックを SKILL.md に記載）

## 3 fork レビュー要約

| 視点 | 重大な指摘 | 対応 |
|---|---|---|
| Skeptic | マーカー縛りは「最終 1 行完全一致」必須（誤検知防止） | save-reply / watch 側で**正規化チェック**を入れる |
| Skeptic | Path A/B 名前空間共有で state 衝突 | Path A を **state-less（引数明示渡し）** にする |
| Skeptic | since 秒精度衝突 | **ms epoch** に変更（since=`$(($(gdate +%s%N 2>/dev/null \|\| python3 -c 'import time;print(int(time.time()*1000))')/1000000))` または短い uuid） |
| Skeptic | embed token 上限の無音切り捨て | max-bytes default を **80_000** に下げる＋プロンプトに truncated 旗を入れる |
| Skeptic | ブラウザ消失時の fallback 欠如 | watch のタイムアウト＋tab URL 検証＋ブラウザ消失を明示エラー化 |
| Arch+Sec | browser-embed は **build-review-packet に `--for-browser`/`--github-branch`/`--since` 追加** で十分（DRY） | 新規スクリプト作らず既存拡張 |
| Arch+Sec | embed プロンプト build 直前の **secret scan 必須** | Path A の唯一の防御線 |
| Arch+Sec | Path A は **state-less（引数明示渡し）** が安全 | active-project 流用しない |
| Arch+Sec | `PRO_REVIEW_MODE=readonly` 退役 | search-fetch だけで Thinking も動く |
| QA | テスト構成は `tests/_assert.sh` + 7 ファイル | Wave 1 (save-reply) → Wave 2 (embed/search-fetch 並列) → Wave 3 (integration 並列) |

---

## Phase 1: 検証・調査（unknown を absent と断定しない）

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 1.1 | [lane:fast][tdd:skip:investigation] GitHub 公式コネクタが Pro 通常チャットで呼べるか実機確認。WebSearch で最新事例＋できれば自分の ChatGPT で 1 回試す | 公式コネクタ可否を `unknown_data` から `confirmed` か `denied` に確定（または `unknown のまま実装は --github-branch を opt-in 必要時のみ` とする） | - | cc:TODO |
| 1.2 | [lane:fast][tdd:skip:docs-only] Skeptic の 5 指摘＋Arch の 5 決定を SKILL.md 設計セクションに反映する草案を作る（実装はしない） | SKILL.md 改訂案 outline が `docs/skill-md-draft.md` 等に作成済（Plans.md の Phase 2 で本実装へ） | - | cc:TODO |

## Phase 2: 実装計画確定（Spec delta）

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 2.1 | [lane:gate][tdd:skip:docs-only] SKILL.md 全面書き直しの最終 outline 確定（Phase 1 の確認結果を反映） | outline が以下を含む: 2 パス図 / Path A 手順 / Path B 手順 / 共通 lifecycle / 退役項目 / スクリプト一覧 / Skeptic 5 件への対処明文 | 1.1, 1.2 | cc:TODO |

## Phase 3: 実装（TDD・Red→Green）

### Wave 1（直列必須・両 Path の土台）

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 3.1 | [lane:gate][tdd:required] `tests/_assert.sh` 作成（assert_eq / assert_contains / assert_file_exists / mkrepo / cleanup ヘルパー） | `bash tests/_assert.sh` 単体実行で構文エラー無し。ヘルパー関数は他 test から source 可能 | 2.1 | cc:完了 |
| 3.2 | [lane:gate][tdd:required] `tests/test-save-reply.sh` (Red): 正常書込 / アトミック / project 名 path injection 拒否 / since 数値検証 / inbox 配下強制 / symlink 拒否 | テスト書き上げ完了 → 実装無しで実行すると **全 case が FAIL** すること | 3.1 | cc:完了 |
| 3.3 | [lane:gate][tdd:required] `scripts/pro-review-save-reply` (Green): stdin/--text 排他 / tmp→rename / 検証 / inbox 配下強制 / symlink 出力先拒否 | `bash tests/test-save-reply.sh` 全 case PASS。サイズ上限と UTF-8 強制は **付けない**（Arch 判断） | 3.2 | cc:完了 |

### Wave 2（並列可・Wave 1 完了後）

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 3.4 | [lane:gate][tdd:required] `tests/test-browser-embed.sh` (Red): `--for-browser` で `[[DONE-${since}]]` 注入 / `--github-branch` 系で「コード非埋め込み＋GH 指示」/ 未指定系で diff 埋込 / max-bytes default 80_000 / truncated 旗 / secret scan が `.env` 等で exit 1 | 全 case Red 状態（既存 build-review-packet には `--for-browser`/`--github-branch`/`--since` が無いので落ちる） | 3.3 | cc:完了 |
| 3.5 | [lane:gate][tdd:required] `scripts/build-review-packet` 拡張 + `pro-review-browser-embed` orchestrator (Green): `--for-browser`（マーカー注入 + truncated 旗）/ `--github-branch BRANCH`（コード非埋込 + GH 指示文）/ `--since N` / 既存 build 直前 secret scan / max-bytes default を 80_000 に変更 | `bash tests/test-browser-embed.sh` 全 case PASS。既存 embed/connector モードは regression 無し | 3.4 | cc:完了 |
| 3.6 | [lane:gate][tdd:required] `tests/test-search-fetch.sh` (Red/regression): tools/list で search/fetch のみ exposed・write 系除外 / search("") list-all / search 部分一致 / fetch / path traversal 拒否 | 既存 `pro-review-mcp-search-fetch` で全 case PASS（Wave 2 で実装変更しない場合 Red ではなく regression 確認） | 3.3 | cc:完了 |
| 3.7 | [lane:gate][tdd:required] `tests/test-start-template.sh` (Red/regression): pro-review-start が search/fetch 指示プロンプト＋`[[DONE-${since}]]` 末尾を生成 | 全 case PASS。Skeptic 1 対策で start 側も ms epoch since に変更（必要なら） | 3.3 | cc:完了 |
| 3.8 | [lane:fast][tdd:skip:removal-only] `PRO_REVIEW_MODE=readonly` 退役: `pro-review-mcp` の elif 分岐削除 / `pro-review-mcp-readonly` を `scripts/_archive/` に移動 / SKILL.md outline から該当行削除 | `PRO_REVIEW_MODE=readonly pro-review-mcp` を打っても新フローのみ。`scripts/pro-review-mcp-readonly` が `_archive/` 配下 | 3.3 | cc:完了 |

### Wave 3（並列可・Wave 1+2 完了後）

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 3.9 | [lane:gate][tdd:required] `tests/test-integration-path-a.sh`: browser-embed → 偽 reply を save-reply で投入 → watch 検知 → finish が reports 永続化＋クリーンアップ | 全 case PASS。fixture: `mkrepo` で git 初期化済 repo + `[[DONE-${since}]]` 末尾の偽返信 | 3.5, 3.3 | cc:完了 |
| 3.10 | [lane:gate][tdd:required] `tests/test-integration-path-b.sh`: pro-review-start → 偽 reply を save-reply 経由 → watch 検知 → finish | 全 case PASS。Path A と同じ fixture パターン | 3.7, 3.3 | cc:完了 |
| 3.11 | [lane:fast][tdd:required] `tests/run-all.sh`: 全テスト直列実行＋集計＋失敗時 exit 1 | `bash tests/run-all.sh` が緑なら exit 0、赤なら exit 1。テスト件数と pass/fail 数を最後に表示 | 3.9, 3.10 | cc:完了 |

## Phase 4: ドキュメント＆メモリ反映

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 4.1 | [lane:gate][tdd:skip:docs-only] `SKILL.md` 全面書き直し: 2 パス図 / Path A 詳細手順（claude-in-chrome 運転＋GitHub オプション＋DOM 抽出＋マーカー縛り）/ Path B 詳細手順 / スクリプト一覧更新 / Skeptic 5 件への対処明文 / 退役項目明記 | SKILL.md が新仕様で読み切れる。frontmatter 更新（description 改訂） | 3.11 | cc:完了 |
| 4.2 | [lane:fast][tdd:skip:docs-only] `SETUP-layer2.md` 更新（Pro/Plus は MCP 経由で書けない明記、search/fetch 互換 MCP に切替済の説明） | SETUP-layer2.md が新仕様と矛盾しない | 3.11 | cc:完了 |
| 4.3 | [lane:fast][tdd:skip:docs-only] メモリ更新: `reference_gpt_pro_review.md` に 2 パス構成・公式制約・Skeptic 指摘経緯を追記 | メモリ最新化。MEMORY.md index の description も同期 | 3.11 | cc:完了 |

## Phase 5: 手動実走（ブラウザ）

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 5.1 | [lane:fast][tdd:skip:manual-e2e] Path A 手動実走: 実際の Chrome で ChatGPT Pro 開く → browser-embed のプロンプトを貼って送信 → 完了待ち → DOM 抽出して save-reply → watch auto-resume → finish | reports/<project>/ にレビュー結果が永続化。1 周動作の手動 checklist が記録される | 4.1 | cc:TODO |
| 5.2 | [lane:fast][tdd:skip:manual-e2e] Path B 手動実走: Thinking-High で pro-review-mcp 経由の search/fetch を呼ばせて、本文を DOM 抽出 → save-reply → finish | reports に永続化。1 周動作の手動 checklist が記録される | 4.1 | cc:TODO |

## /breezing 並列分割

```
直列必須:    Phase 1 → Phase 2 → Wave 1 (3.1→3.2→3.3) → Phase 4 → Phase 5
並列可:      Wave 2 内 (3.4↔3.6↔3.8 同時。3.5 は 3.4 の後。3.7 は 3.6 の後)
             Wave 3 内 (3.9 ↔ 3.10 同時。3.11 はその後)
             Phase 4 内 (4.1 ↔ 4.2 ↔ 4.3 同時)
             Phase 5 内 (5.1 ↔ 5.2 同時)
```

## Risk Gate

- Path A は repo の embed プロンプトに secret 含み得る → **build 直前 secret scan が落ちないと送信できない設計** にする（task 3.5 の DoD）
- `PRO_REVIEW_MODE=readonly` の退役は破壊的変更だが、利用実績は本セッションのテストのみで影響範囲なし → `_archive/` 移動で revert 容易
- GitHub コネクタの Pro 通常チャット利用は **task 1.1 で確定するまで実装に含めない**（unknown を absent と書かない原則）

## 起動案内

新しいセッションの起動コマンド: `claude`
起動後の最初の入力: `/breezing all`
向いている場面: Wave 1 → Wave 2（並列）→ Wave 3（並列）→ Phase 4 → Phase 5 で並列消化が効くため

---

# Phase 6: nodriver ブラウザ経路移行（2026-06-23 追加）

## Context（方向転換の経緯）

当初 patchright（undetected Playwright）への置換を計画したが、3 視点（Security / Architecture / Skeptic）の独立検証で前提が崩れた:

- **Skeptic**: `gpt-5.5-pro` は 2026-04-24 から **OpenAI API（Responses）で直接呼べる**。Path A がブラウザ自動化している理由（Pro は Web 専用）は陳腐化。SKILL.md の該当前提は今や偽。
- **Security**: patchright は「プログラム抽出（グレー）」→「保護措置の能動的回避（ToU 正面抵触）」へリスクを一段悪化。安定化なら stealth でなく retry で足りる。課金 Pro の BAN リスク。
- 検知耐性の実測（2026 ベンチ 31 ターゲット）で **nodriver が首位**（CDP 直駆動・Playwright 痕跡なし）。patchright/Camoufox は Playwright fork で protocol 層に痕跡。ChatGPT の Cloudflare は protocol fingerprinting が主力 → nodriver が適。

**ユーザー判断（2026-06-23）**: ブラウザ経路を nodriver で作る。secret scan 強化を先頭に。skill 本体は `~/LocalWork/Code/gpt-pro-review/`（git 管理）へ移し user スコープへ symlink（完了済）。

## Spec skip reason

Context Harness repo の `spec.md` には影響なし（本件は独立 user-scope skill の改修で製品 contract 外）。product contract は本 skill の `SKILL.md`。Phase 6 では SKILL.md に delta（Path A の運転方式を claude-in-chrome → nodriver へ、API で Pro 取得可の NOTE 追記）を入れる（task 6.7）。

## unknown_data（absent と断定しない）

- `gpt-5.5-pro` がユーザー org tier で API 200 を返すか（task 6.2 の curl で確定）
- ChatGPT の agent-mode トグル / stop ボタンの実 `data-testid`（DOM 不安定 → config ブロック化して再ピン可能に。task 6.4）
- nodriver の AGPL-3.0 が将来の skill 公開配布時に課す義務（自分用途なら無害。配布時 unknown）
- 低頻度・ログイン済み運用で Cloudflare challenge 発生頻度（task 6.8 実走で観測）

## Stage 1: 検証・調査（先頭・最優先）

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 6.1 | [lane:gate][tdd:required] **secret scan 強化（最優先・方向非依存・汎用のまま）**: `build-review-packet` の secret scan を (a) **diff 本文にも適用**（現状 embed 全文のみ）(b) **汎用の秘密の形**を追加=`.pem`/秘密鍵パス・IP アドレス正規表現・email・追加 token 形（既存5種に加え汎用 high-entropy）・日本の PII 正規表現（郵便番号/電話番号）。**特定プロジェクトの literal（顧客名/codename/SF field 名等）は skill 本体に一切書かない** | 偽装 fixture（汎用 IP/.pem/PII を仕込んだ diff+全文）で **exit 1**、クリーン fixture で exit 0。既存 5 パターン回帰維持。skill コードに固有語 literal が grep で 0 件 | - | cc:TODO |
| 6.1b | [lane:gate][tdd:required] **repo 別 denylist 機構（固有語はここで供給）**: レビュー対象 repo の root に `.pro-review-denylist`（1行1語/正規表現、任意）を置けば build-review-packet が読み込み、その語を追加検査。skill 本体は機構だけ持ち、語は持たない。Context Harness で使う時はあの repo 側に codename/SF field を置く | denylist file 有り fixture で固有語ヒット→exit 1、file 無し fixture で従来通り動作。skill 本体に固有語 0 件（6.1 と同条件） | 6.1 | cc:TODO |
| 6.2 | [lane:fast][tdd:skip:verify-only] **(Recommended pre-flight)** API tier 確認: `gpt-5.5-pro` を Responses API に curl 1 発（ユーザー実行・外部送信ゲート）。**200 が返れば 6.3 以降のブラウザ実装は退役候補**＝API 化 pivot を再提案 | curl 結果が記録され、API 可否が確定。可なら方向再判断、不可なら 6.3 へ進む判断が残る | - | cc:TODO |

## Stage 2: 実装計画確定（環境）

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 6.3 | [lane:gate][tdd:skip:setup] `scripts/pro-review-browser-setup`: skill 内 `scripts/.venv` に nodriver を pip install、初回手動ログイン（headed）で ChatGPT セッションを専用 profile（`~/.pro-review/chrome-profile`）へ保存。Google Chrome 検出（無ければ警告）。**profile dir は chmod 700**、`pro-review-snapshot` 除外リストに profile を追加 | `pro-review-browser-setup` 実行で venv 作成・nodriver 導入・profile に cookie 保存。再実行 idempotent。profile が 700 かつ snapshot に含まれない | 6.1 | cc:TODO |

## Stage 3: 実装（TDD）

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 6.4 | [lane:gate][tdd:required] `scripts/pro-review-browser-drive`（nodriver, async Python）: packet を ChatGPT に投入 → `[[DONE-<since>]]` を **2 シグナル**（末尾行マーカー完全一致 AND stop ボタン消失）で完了判定 → assistant 本文を stdout → save-reply にパイプ。selector は先頭 config ブロック化。`exit 3 + FALLBACK:<理由>` で login / Cloudflare / agent-mode-on / timeout を退避 | 静的 fixture（6.6）で本文抽出・マーカー判定が正。stdout は本文のみ。退避時 exit 3。`browser-embed` の `since`/`request_file` を消費 | 6.3 | cc:TODO |
| 6.5 | [lane:gate][tdd:required] フォールバック配線: drive `exit 3` → **claude-in-chrome 旧経路（A1）** → **手貼り（A2: `save-reply --text`）**。nodriver 未導入でも skill は A1 で動く（hard 依存にしない） | drive 失敗を fixture で再現し A1→A2 へ縮退。nodriver 無し環境で skill 全体が緑 | 6.4 | cc:TODO |

## Stage 4: レビュー（テスト）

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 6.6 | [lane:gate][tdd:required] `tests/test-browser-drive-extract.sh`: **静的 fixture HTML** に対し DOM 抽出＋マーカー判定を検証（本文＋末尾マーカー→exit0 / マーカーが中間行→exit3 偽陽性なし / stop ボタン有→待機 / login ボタン有→FALLBACK）。`run-all.sh` に追加。nodriver 未導入時は **skip-with-pass** | 全 case PASS。実 ChatGPT 不要（fixture のみ）。`run-all.sh` が nodriver 無し機でも緑 | 6.4 | cc:TODO |
| 6.7 | [lane:gate][tdd:skip:docs-only] `SKILL.md` 配線更新: Path A の claude-in-chrome ステップを `browser-drive` 呼び出しへ差し替え、Fallback A1/A2 明記、setup 手順追記、frontmatter description 改訂、**NOTE: gpt-5.5-pro は API で取得可（将来 API 化候補）** を追記 | SKILL.md が nodriver 経路で読み切れる。旧 claude-in-chrome は Fallback として残置記載 | 6.5, 6.6 | cc:TODO |

## Stage 5: closeout（手動実走・コミット）

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 6.8 | [lane:fast][tdd:skip:manual-e2e] 手動 e2e（`PRO_REVIEW_E2E=1`・非CI）: 実 ChatGPT Pro で 1 周（setup→drive→save-reply→watch→finish）→ reports 永続化。低頻度・ログイン済み・本人アカウント前提を runbook 化（BAN リスク緩和） | reports/<project>/ にレビュー結果。1 周の手動 checklist と Cloudflare challenge 観測を記録 | 6.7 | cc:TODO |
| 6.9 | [lane:fast][tdd:skip:setup] git baseline commit: 専用フォルダ + `.gitignore`（profile/venv/secrets 除外）で初期コミット | `git log` に baseline commit。profile/venv/secrets が tracked に含まれない | 6.7 | cc:TODO |

## Phase 6 Risk Gate

- **外部送信**: repo diff を ChatGPT（API でも browser でも）へ送る。6.1 の secret scan 強化が落ちないと送信不可の設計を維持。この機密 repo の diff 外部送信は **ユーザー明示承認ゲート**（汎用ツールとしては可でも本体適用は別判断）
- **ToU / BAN**: nodriver でもブラウザ自動化は ToU グレー。低頻度・本人アカウント・ログイン済みに限定。stealth が無いと動かない場面は「回避でなく手貼り退避の合図」として扱う
- **認証情報**: ChatGPT cookie を平文 profile に保持 → chmod 700 + snapshot/Git 除外（6.3, .gitignore で対応済）
- **API pivot**: 6.2 が 200 なら本 Phase のブラウザ実装（6.3-6.8）は退役候補。実装着手前に 6.2 を回すのが TCO 最小

## Phase 6 /breezing 並列分割

```
先頭単独:   6.1（secret scan 強化、他に依存されるゲート）
独立:        6.2（API 確認、pre-flight。6.1 と並列可）
直列:        6.1 → 6.3 → 6.4 → 6.5
並列可:      6.6（fixture テスト、6.4 後）↔ 6.7（docs、6.5+6.6 後）
closeout:    6.8 → 6.9（6.7 後）
```

## Phase 6 起動案内

新しいセッションの起動コマンド: `claude`
起動後の最初の入力: `/harness-work 6.1`（secret scan 強化を先頭で確定）→ 続けて `6.2` の curl 確認
向いている場面: 6.1 は他タスクのゲートなので単独先行。6.2 の API 結果次第でブラウザ実装をやめられるため、6.3 以降の着手前に 6.1・6.2 を回すのが最小コスト
