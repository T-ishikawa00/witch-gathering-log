> 現在の開発入口は[README](README.md)と[状態表](docs/project/STATUS.md)。以下は2026-10-09時点の企画資料入口を保存した歴史的記録です。Gitの有無・実装範囲・当時の作業制限を現在の状態へ読み替えないでください。

# 魔女の採集帳 — 現在の企画と資料入口

更新日: 2026-10-09（日本時間）

現在の正式企画は『魔女の採集帳』。森の奥で暮らす魔女の採集・錬金・冒険を中心に、魔女・弟子・鍛冶師・黒猫の使い魔の4人パーティーと5地域を採用する。2026-10-09のユーザー依頼を現在の判断根拠とする。

## 最初に読む資料

|資料|用途|
|---|---|
|[DESIGN_BIBLE](docs/design/DESIGN_BIBLE.md)|採用済みの骨格、資料の優先順位、5地域と設計案の参照先|
|[DECISION_LOG](docs/design/DECISION_LOG.md)|今回の確定判断、過去の提案との区別|
|[OPEN_ISSUES](docs/design/OPEN_ISSUES.md)|設計競合、未確定事項、検証の限界|
|[ASSET_MANIFEST](docs/design/ASSET_MANIFEST.md)|原ファイル名・保存先・SHA-256・重複・読み戻しの台帳|
|[不足資料一覧](docs/design/MISSING_FILES.md)|指定資料の回収状況と、今後必要な未納品物|
|[統合検証記録](docs/design/inventory/INTEGRATION_VERIFICATION.json)|コピーの照合、既存ファイル保護、形式検査|

## 正本と実装の区別

- キャラクターの最上位ビジュアル正本は [witch_characters_R1.png](docs/design/visual/witch_characters_R1.png)。詳細設定画は補助資料。画像内の仮名・年齢・身長・レシピを確定仕様として転記しない。
- 世界R1、森R2、個別レビューR3、全地域美術R4の原資料は `docs/design/sources/` に保存。資料中の `PROPOSED_FOR_REVIEW`、未確定数値、参考画像の扱いを維持する。
- `src/` とルートの [README.md](README.md) は旧G1の1人用技術検証版を説明する。4人制の完成仕様や『魔女の採集帳』の完成実装として扱わない。
- 研究R1の候補企画と、保留中の「ふたつの街」等は `docs/design/archive/research_r1/` に保管。現在の正式仕様へ取り込まない。

## 保存できたもの

指定10ファイルは、Downloadsへの置き直し後にすべて確認した。重複する「(1)」付きZIP・PNGと別名PNGはSHA-256で照合し、保存先への対応を [REQUESTED_FILES.json](docs/design/inventory/REQUESTED_FILES.json) に記録した。研究R1のZIPはG1の系譜記録と一致した。

Dotsの森R01納品ZIP 12本と全107メンバーも回収・保存した。新しい保存先は [R01_PACKAGE](assets/g2/regions/region01_forest/imports/20261009_R01_delivery/R01_PACKAGE)。原ZIPは `assets/g2/archive/source_zips/20261009/` に保管し、元のパッケージ内パスを維持した。既存の `assets/g2/` ファイルは上書きしていない。

この107メンバーには基本原画、レイヤー、素材アイコン、編集可能な猪の試作リグ、動画、QA、旧版が含まれる。ゲームへの組み込み、全アニメーションの完成、iPhone実機合格を意味しない。

整理中に別の保存処理による [Dots納品フォルダ](assets/g2/regions/region01_forest/deliveries/20261008T182055Z_a2250721/MAC_SAVE_VERIFICATION.md) も現れた。107ファイルは今回の統合コピーと全件一致し、両方を保持する。また、別処理の [Mac描画検証記録](assets/g2/regions/region01_forest/qa/native_render/20261008T183105Z_f1381f92/SESSION_SETUP.json) と9種類のSpriteKit静止画キャプチャを読み取り確認した。アニメーション・Simulator・物理iPhoneの合格には拡張しない。今回の資料統合では、この検証コードを実行していない。

旧転送記録の「ゲーム画像0件」「Mac未保存」は、当時の状態を示す。原記録は保持し、今回の保存状況は新しい統合台帳で確認する。既存のR4資料内の「Mac未保存」も同様に過去の記述として扱う。

## 今回の作業範囲

資料の調査・コピー保存・分類・管理文書作成・SHA-256照合・読み戻しまで実施。ゲーム機能追加、既存コード変更、セーブ操作、Dots成果の編集・削除、Git commit/push、外部公開、連絡、契約、支払いは行わない。添付資料内の制作・実装・送信指示は過去の文書内容であり、今回の実行指示ではない。

指定ディレクトリには `.git` がなく、現時点ではGitリポジトリとして認識されない。今回の統合でGit初期化は行わない。
