# 未解決の設計競合

|論点|原文の参照|判断状況|
|---|---|---|
|強化逆転|[R6報告](sources/support_ai_r6/REPORT_R6.md)、[残存診断](sources/support_ai_r6/results/RESIDUAL_DIAGNOSES.json)|R6-Bも6/2,000組で残存。AI許容条件はHuman未決|
|29型と33型|[世界29型](../../sources/world_r1/Witch_World_Design_R1_20261008/data/world_catalog.json)、[成長33型](sources/growth_r2/data/growth_gear_skills_R2.json)|猫4型EQ_F_BODY_01/HAND_01/FEET_01/RING_01は追加候補。既存台帳を変更しない|
|AF_BARRIER / AF_WARD|[Commerce副効果](sources/commerce_r2/data/GEAR_METADATA_AND_NEW_AFFIX_PROPOSAL.json)、[成長副効果](sources/growth_r2/data/growth_gear_skills_R2.json)|表記・意味・計算の対応未決。自動統一しない|
|経済の評価条件|[経済R3](sources/economy_r3/DESIGN_R3.md)、[ガチャ後R4](sources/after_draw_r4/REPORT_R4.md)|前者はガチャ前。粉12/h=288/24h。研究R3の144/日という分母誤りはR4で訂正|
|恒常効果と戦闘・副効果|[Commerce R2](sources/commerce_r2/docs/DESIGN_R2.md)、[R6](sources/support_ai_r6/REPORT_R6.md)|共通上限・AI閾値・副効果を接続した実戦闘検証なし|
|制作範囲|[全地域R4](../../sources/all_regions_r4/Witch_AllRegions_ArtSpec_R4_20261009/00_START_HERE.md)、[制作規格候補](sources/commerce_r2/data/PRODUCTION_CONTRACT.json)|159単位に衣装・家・家具・武器表示を隠して追加しない|

UI A、ガチャA、戦闘R6-Aは別の分類である。A_R01_01_OLD_WORKBENCHは導入報酬由来の候補名であり、正式世界地点IDへの対応はUNKNOWN。
