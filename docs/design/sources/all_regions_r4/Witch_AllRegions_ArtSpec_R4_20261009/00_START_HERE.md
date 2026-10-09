# 魔女の採集帳 — 5地域統合美術制作仕様 R4
2026-10-09 / Chat側の設計成果物

## これは何か
Dotsが第1地域を制作している間に、残る地域も同じ規格で作れるように整えた**全地域の設計パッケージ**。新しい完成画像やスプライトを生成したものではありません。G2ゲーム本体の完成仕様や、全5地域量産の自動許可でもありません。

**読む：`ART_BIBLE_R4.html`**（画像は埋込、外部CDN/通信なし）

## 内容
5地域・20地点・30魔物/ボス・50素材・29装備型、87の材料→装備接続を保持。10背景キット＋10地点差分＋30魔物キット＋50素材アイコン＋20採取小物＋29装備アイコン＋10VFXキット＝159制作単位。

## 必ず守る
- 承認済み4キャラの容姿を維持。画像文字の仮名/年齢や絵に紛れたレシピを仕様へ変換しない。
- 世界R1のID/入手先/レシピ/未決数値をそのまま保管。本書の新規スケール/パレット/分割は提案として分離。
- Dotsの第1地域を止めず、既存の猪の承認見本を保全。P0の数値へ合わせるために即描き直ししない。
- `src/`・G1セーブ・既存資料は変更しない。

## 読む順
1. `docs/01_AUTHORITY_AND_CHANGELOG.md` — 正本/12の差異
2. `docs/02_SHARED_ART_STANDARD.md` — 共通画風・カメラ・仮P0
3. `regions/R01...R05...` — 背景・魔物・素材の個別制作仕様
4. `docs/03_ANIMATION_EXPORT_CONTRACT.md` — 部品/アニメ/alpha/納品
5. `docs/04_MATERIAL_GEAR_AND_SCOPE.md` — 素材・装備・159制作単位
6. `docs/05_QA_AND_BATCH_PLAN.md` / `docs/06_ROADMAP_AND_OPEN_DECISIONS.md`

## データ
`source_snapshot/` は原資料を保全。`data/art_catalog_R4.json` が追加設計の機械可読版。Excelは閲覧・進捗管理用の派生物で、世界の数値正本を書き換えるものではありません。

## Mac保存
このパッケージはChatGPT内で作成。**Macへは未保存**。推奨先は
`/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/design/all_regions_art_r4_20261009/`。
Dotsへ`handoff/DOTS_APPEND_R4.md`とZIPを渡して追記保存し、実パス/hash/readbackを確認してください。第1地域の原画を消して新フォルダへ置換する必要はありません。

## 検証
`python3 tools/validate_art_spec.py`、`python3 -m unittest discover -s tools -p 'test_*.py'`。
結果は`qa/`。構造検査合格≠絵の完成≠iPhone動作合格≠売上の保証です。
