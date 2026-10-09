# 不足資料と回収状況

更新日: 2026-10-09

今回指定された10ファイルと、Dotsの森R01納品ZIP 12本はすべて回収・保存できた。指定資料の不足は0件。最初の調査では不在だった研究R1・指定名の画像・Dots納品は、Downloadsへの置き直し後に確認した。具体的な対応とハッシュは [REQUESTED_FILES.json](inventory/REQUESTED_FILES.json) と [ZIP_VERIFICATION.json](inventory/ZIP_VERIFICATION.json) に記録した。

## 納品に含まれない参照ファイル

以下6ファイルは納品文書に名称があるが、プロジェクト・Downloads・回収ZIP内には存在しない。QA専用シーンとrenderスクリプトは `IMPORT_SETTINGS_AND_LIMITS.md:21` で同梱対象外と明記されている。転送中の欠損や今回のコピー失敗ではない。全QAを再現する場合には別途必要となる。

|ファイル名|用途|名称の根拠|
|---|---|---|
|`witch_R01_four_layer_QA.blend`|QA背景4層の再現シーン|`R01_PACKAGE/qa/blender/INDEPENDENT_VISUAL_QA.md:9`|
|`render_layer_qa.py`|QA背景4層の再現スクリプト|`R01_PACKAGE/qa/blender/INDEPENDENT_VISUAL_QA.md:9`|
|`render_R01_set_qa.py`|8原画のQA再現スクリプト|`R01_PACKAGE/qa/blender/R01_EIGHT_ASSET_REVIEW.md:10`|
|`R01_eight_assets_QA.blend`|8原画のQAシーン|`R01_PACKAGE/qa/blender/R01_EIGHT_ASSET_REVIEW.md:10`|
|`ancient_tree_arena_QA.blend`|古樹の静止QAシーン|`R01_PACKAGE/qa/blender/R01_EIGHT_ASSET_REVIEW.md:10`|
|`E_R01_01_cutout_feasibility.blend`|旧前面脚版のリグシーン|`R01_PACKAGE/source/boar_rig/REVIEW.md:21`|

背面脚版の `source/boar_rig/E_R01_01_cutout_behind_body.blend`、`build_rig.py`、2枚の原テクスチャとレビュー動画は保存済み。旧前面脚版の名称を背面脚版へ勝手に置換していない。

## 未制作・未納品の範囲

採取素材 `M_R01_G1` しなり霊枝、`M_R01_G2` 露灯草、`M_R01_G3` 琥珀樹脂、`M_R01_G4` 月白苔の独立アイコンは今回のR01納品に含まれない。収録済みの6アイコンは通常敵4体・ボス2体のドロップ素材であり、これら4採取素材とは別物。

4人の実装用キャラと全行動アニメーション、R01敵6体の完成モーション、猪の独立した頭・牙と接地、物理iPhoneの実素材検証証拠も未完了／未納品。原資料が出力ファイル名を定めていないため、ファイル名はUNKNOWNとして台帳に記録し、架空の名前で不足数を水増ししない。

R02–R05、家、全UIの完成美術は今回の納品範囲外。設計資料の保存完了と、制作完了を区別する。

## 欠落と誤認しない資料

Dots ZIPで重複収録しない「原資料4点」は、承認キャラPNG、世界R1、森R2、R3制作指示を指す。いずれも今回 `docs/design/` に保存済み。`SOURCE_MAP.json` のクラウド作業パスは出所であり、Mac上の同一パスを要求するものではない。

Downloads版と同梱版の検証PDFはバイト列が異なるため両方を保存した。相違は [OPEN_ISSUES](OPEN_ISSUES.md) CF13に記録し、正本を選んでいない。
