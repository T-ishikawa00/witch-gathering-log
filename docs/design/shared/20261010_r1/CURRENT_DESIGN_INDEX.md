# 現在の設計目次 — GitHub共有用 R1

2026-10-10。Humanの明示判断、分野別の既存正本、設計候補・検証記録、旧案の順で読む。新しい版や試験PASSは正式採用を意味しない。
[判断状態](DECISION_STATUS.md)・[設計競合](DESIGN_CONFLICTS.md)・[欠落原本](MISSING_ORIGINALS.md)・[実装前の未決](IMPLEMENTATION_READINESS.md)・[台帳](SOURCE_MANIFEST.json)を先に確認する。

## 既存GitHub原本

|分野|原本|扱い|
|---|---|---|
|骨格・判断|[DESIGN_BIBLE](../../DESIGN_BIBLE.md)、[DECISION_LOG](../../DECISION_LOG.md)、[OPEN_ISSUES](../../OPEN_ISSUES.md)|4人・5地域の既存設計。今回上書きしない|
|世界・装備・安定ID|[世界R1カタログ](../../sources/world_r1/Witch_World_Design_R1_20261008/data/world_catalog.json)|29装備・29レシピ。各数値nullを維持|
|森|[森R2](../../sources/forest_r2/Witch_Forest_G2_R2_20261009/00_READ_FIRST.md)、[森レビューR3](../../sources/forest_review_r3/Witch_Forest_G2_R3_20261009/01_READ_FIRST.md)|既存競合を維持|
|地域美術|[全地域R4](../../sources/all_regions_r4/Witch_AllRegions_ArtSpec_R4_20261009/00_START_HERE.md)|159制作単位に新衣装・家具を加算しない|
|人物外見|[キャラクター正本](../../visual/witch_characters_R1.png)|UI画像から正式容姿を変更しない|

## 戦闘R1〜R6

|系譜|仕様原本|データ・検証・参照コード|状態|
|---|---|---|---|
|戦闘R1|[原文](sources/battle_r1/Witch_G2C_AutoBattle_Design_R1_20261009.md)|旧作戦設定を含む履歴|作戦・AI編集の旧部分は撤回|
|成長R2|[成長・装備・技能](sources/growth_r2/GROWTH_EQUIPMENT_SKILLS_R2.md)|[データ](sources/growth_r2/data/growth_gear_skills_R2.json)、[原検証](sources/growth_r2/validation/VALIDATION_RESULTS.json)、[計算](sources/growth_r2/validation/reference_model.py)|33型、6枠、数値は候補|
|経済R3|[放置・素材経済](sources/economy_r3/DESIGN_R3.md)|[データ](sources/economy_r3/data/economy_R3.json)、[原検証](sources/economy_r3/validation/VALIDATION_RESULTS.json)、[シミュレーション記録](sources/economy_r3/validation/SIMULATION_RESULTS.json)|ガチャ前の経済|
|戦闘接続R4|[森攻略接続](sources/battle_r4/REPORT_R4.md)|[原検証](sources/battle_r4/results/VALIDATION_SUMMARY.json)、[条件](sources/battle_r4/docs/ASSUMPTIONS_AND_COVERAGE.md)、[計算](sources/battle_r4/tools/battle_model.py)|限定シナリオの記録|
|バランスR5|[報告](sources/balance_r5/REPORT_R5.md)|[原検証](sources/balance_r5/results/VALIDATION_SUMMARY_R5.json)、[差分](sources/balance_r5/docs/R4_TO_R5_BATTLE.patch)、[計算](sources/balance_r5/tools/battle_r5.py)|固定小数点等は候補|
|支援AI R6|[報告](sources/support_ai_r6/REPORT_R6.md)|[決定履歴](sources/support_ai_r6/docs/DECISIONS_R1_R6.json)、[原検証](sources/support_ai_r6/results/VALIDATION_SUMMARY_R6.json)、[R6-B](sources/support_ai_r6/tools/selected_final.py)、[未検証範囲](sources/support_ai_r6/docs/SCOPE_AND_NOT_TESTED.md)|R6-Bは最新候補。強化逆転6/2,000残存|

成長JSONのactors/growth、skills/ai_policy/timing_contract、equipment_rules/gear_templates/rarities/affixes、research/awakenings/caps/combatは、能力・技能・装備・品質・副効果・研究・覚醒・計算の参照先である。元数値を正式値と扱わない。

## ガチャR1〜R4・衣装・家具・恒常効果・UI

|系譜|仕様原本|データ・検証|状態|
|---|---|---|---|
|構想R1|[方向原文](sources/direction_r1/MONETIZATION_APPEARANCE_DIRECTION_R1_ORIGINAL.md)、[整合レビュー](sources/expansion_r1/docs/INTEGRATION_REVIEW_R1.md)|[課題](sources/expansion_r1/data/ISSUE_REGISTER.json)、[制作範囲](sources/expansion_r1/data/PRODUCTION_SCOPE.json)|構想・比較|
|Commerce R2|[装備ガチャ・衣装・家具](sources/commerce_r2/docs/DESIGN_R2.md)|[商品と暮らし・恒常効果](sources/commerce_r2/data/PRODUCT_AND_LIVING_CANDIDATE.json)、[制作規格](sources/commerce_r2/data/PRODUCTION_CONTRACT.json)、[装備副効果](sources/commerce_r2/data/GEAR_METADATA_AND_NEW_AFFIX_PROPOSAL.json)、[原検証](sources/commerce_r2/results/VALIDATION_SUMMARY.json)|価格・数量・共鳴・規格未確定|
|ガチャ比較R3|[A/B/C比較](sources/gacha_research_r3/RESEARCH_REVIEW_R3.md)|[入力](sources/gacha_research_r3/data/CANDIDATES_R3.json)、[原検証](sources/gacha_research_r3/results/VALIDATION_SUMMARY.json)、[比較結果](sources/gacha_research_r3/results/ANALYSIS_R3.json)|Cは試遊第一候補。希少以上Aは比較|
|ガチャ後R4|[保護・分解・粉・強化](sources/after_draw_r4/REPORT_R4.md)|[制約](sources/after_draw_r4/docs/DECISION_AND_LIMITS.md)、[原検証](sources/after_draw_r4/results/VALIDATION_SUMMARY_R4.json)|実DB・戦闘・購入価値は未検証|
|UI A|[A/B原画像](sources/ui_a/UI_DIRECTION_R2_AB_ORIGINAL.png)|左A「暮らしが見える家」|美術方向のみ採用。全画面配置は未確定|

衣装は4人の着せ替え、装備との分離、家・仲間・戦闘への反映、武器外観、試着を含む。家具は配置・差替え、人物動作、単品・テーマ商品、無料獲得・制作を含む。所有恒常効果と無料研究の共通上限は候補である。

[コード依存の読取対応](CODE_REFERENCE.md)と[保存系譜](SOURCE_MANIFEST.json)を参照する。原本文中のsource/vendorや旧ファイル名は元パッケージの識別子であり、この共有パッケージの実行配置ではない。元の15 manifest/948項目にある1件の画像欠落は[欠落原本](MISSING_ORIGINALS.md)に維持した。

既存GitHub文書内の過去のリンク切れは[既存参照の制限](EXISTING_REMOTE_LIMITS.md)を確認する。
