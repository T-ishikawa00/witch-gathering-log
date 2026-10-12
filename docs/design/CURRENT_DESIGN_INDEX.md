# 現在の設計資料 — 統合目次 R1

受領・監査日: 2026-10-10 JST。保存revision: `imports/chatgpt_20261010_r1`。
この目次は原本の保存・分類・照合の結果であり、ゲーム実装・課金・制作開始の許可ではない。

## 最初に確認する状態

[今回のユーザー依頼原文](imports/chatgpt_20261010_r1/authority/USER_REQUEST_ORIGINAL.txt)を最優先する。Human明示承認 → 分野別の既存正本 → 設計候補・検証記録 → 旧案・参考資料の順で読む。新しい日付や試験PASSだけで正式判断を上書きしない。

|管理資料|用途|
|---|---|
|[DECISION_STATUS](DECISION_STATUS.md)|承認済みの方向、検証候補、未確定、撤回・比較案|
|[DESIGN_CONFLICTS](DESIGN_CONFLICTS.md)|両方の原文・場所・推奨解決方向。自動解決しない|
|[MISSING_ORIGINALS](MISSING_ORIGINALS.md)|回収済み・部分欠落・未回収の区別|
|[IMPLEMENTATION_READINESS](IMPLEMENTATION_READINESS.md)|分野別の参照可能性と正式実装前の判断|
|[SOURCE_MANIFEST](SOURCE_MANIFEST.json)|703保存ファイルの出所・保存先・SHA-256・revision・重複|
|[保存・監査報告](imports/chatgpt_20261010_r1/INTEGRATION_REPORT.md)|今回実施した検証、保護、作業境界|
|[GitHub同期候補](imports/chatgpt_20261010_r1/GITHUB_SYNC_CANDIDATES.md)|候補パス・サイズ・ignore状態。今回同期しない|

## 既存正本・制作状況

|分野|入口|扱い|
|---|---|---|
|既存企画・権限|[DESIGN_BIBLE](DESIGN_BIBLE.md)、[DECISION_LOG](DECISION_LOG.md)|4人・5地域等の骨格。カタログ全行の個別承認とは別|
|世界・安定ID|[世界R1カタログ](sources/world_r1/Witch_World_Design_R1_20261008/data/world_catalog.json)|5地域、20地点、30敵、50素材、29装備・29レシピ。数値nullを維持|
|森詳細|[森R2](sources/forest_r2/Witch_Forest_G2_R2_20261009/00_READ_FIRST.md)、[森レビューR3](sources/forest_review_r3/Witch_Forest_G2_R3_20261009/01_READ_FIRST.md)|木橋/石橋等の既存競合を保持|
|全地域美術|[美術R4](sources/all_regions_r4/Witch_AllRegions_ArtSpec_R4_20261009/00_START_HERE.md)|159制作単位。衣装・家具・新装備を追加計上しない|
|キャラクター外見|[最上位正本PNG](visual/witch_characters_R1.png)|UI A画像で容姿や正式名を変更しない|
|最新G2報告・台帳|[制作報告](../../assets/g2/production/codex_unified_20261008T221040Z_fa70940c/FINAL_REPORT_R001.md)、[159台帳](../../assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/FINAL_159_LEDGER_R001.json)、[独立QA R003](../../assets/g2/production/codex_unified_20261008T221040Z_fa70940c/qa/FINAL_LEDGER_INDEPENDENT_REVIEW_R003.json)|静的候補99単位/357 PNG、完成キット・Human採用・ゲーム統合・物理iPhone合格は各0という原報告。今回再実行しない|
|既存未決・保存台帳|[OPEN_ISSUES](OPEN_ISSUES.md)、[ASSET_MANIFEST](ASSET_MANIFEST.md)、[MISSING_FILES](MISSING_FILES.md)|既存原文を変更しない|
|旧G1|[旧報告](archive/g1/reports/G1_REPORT.md)|1人用の技術検証。正式4人モデルの完成証明にしない|

## 戦闘・成長・経済の系譜

|分野revision|仕様の入口|入力・コード・結果|現状態|
|---|---|---|---|
|BATTLE_R1|[原本文](imports/chatgpt_20261010_r1/expanded/Witch_G2C_Design_Consolidated_R1_R5_20261009/Witch_G2C_Balance_Refinement_R5_20261009/history/Witch_G2C_AutoBattle_Design_R1_20261009.md)|R5統合原ZIPにMarkdownとして同梱。単体ZIP名は不明|作戦設定部分は後続Human方針により撤回。本文は保全|
|GROWTH_R2|[成長・装備・スキル](imports/chatgpt_20261010_r1/expanded/Witch_G2C_Growth_Equipment_Skills_R2_20261009/Witch_G2C_Growth_Equipment_Skills_R2_20261009/GROWTH_EQUIPMENT_SKILLS_R2.md)|[設計JSON](imports/chatgpt_20261010_r1/expanded/Witch_G2C_Growth_Equipment_Skills_R2_20261009/Witch_G2C_Growth_Equipment_Skills_R2_20261009/data/growth_gear_skills_R2.json)、[参照モデル](imports/chatgpt_20261010_r1/expanded/Witch_G2C_Growth_Equipment_Skills_R2_20261009/Witch_G2C_Growth_Equipment_Skills_R2_20261009/validation/reference_model.py)、[原検証結果](imports/chatgpt_20261010_r1/expanded/Witch_G2C_Growth_Equipment_Skills_R2_20261009/Witch_G2C_Growth_Equipment_Skills_R2_20261009/validation/VALIDATION_RESULTS.json)|数値・猫装具4型・6枠の詳細は候補|
|ECONOMY_R3|[放置・素材経済](imports/chatgpt_20261010_r1/expanded/Witch_G2C_Idle_Economy_R3_20261009/Witch_G2C_Idle_Economy_R3_20261009/DESIGN_R3.md)|[設計JSON](imports/chatgpt_20261010_r1/expanded/Witch_G2C_Idle_Economy_R3_20261009/Witch_G2C_Idle_Economy_R3_20261009/data/economy_R3.json)、[コード・原結果](imports/chatgpt_20261010_r1/expanded/Witch_G2C_Idle_Economy_R3_20261009/Witch_G2C_Idle_Economy_R3_20261009/validation)、[経済Workbook](imports/chatgpt_20261010_r1/expanded/Witch_G2C_Idle_Economy_R3_20261009/Witch_G2C_Idle_Economy_R3_20261009/Witch_Idle_Economy_R3.xlsx)|有料ガチャ前の経済検証。ガチャ後の成立証明ではない|
|BATTLE_INTEGRATION_R4|[森攻略接続](imports/chatgpt_20261010_r1/expanded/Witch_G2C_R01_EndToEnd_R4_20261009/Witch_G2C_R01_EndToEnd_R4_20261009/REPORT_R4.md)|[参照コード](imports/chatgpt_20261010_r1/expanded/Witch_G2C_R01_EndToEnd_R4_20261009/Witch_G2C_R01_EndToEnd_R4_20261009/tools)、[原検証結果](imports/chatgpt_20261010_r1/expanded/Witch_G2C_R01_EndToEnd_R4_20261009/Witch_G2C_R01_EndToEnd_R4_20261009/results)|2人/4人、素材・制作・装備配分・解放・報酬冪等性の限定検証|
|BALANCE_R5|[戦闘バランス改善](imports/chatgpt_20261010_r1/expanded/Witch_G2C_Design_Consolidated_R1_R5_20261009/Witch_G2C_Balance_Refinement_R5_20261009/REPORT_R5.md)|[R4→R5差分](imports/chatgpt_20261010_r1/expanded/Witch_G2C_Design_Consolidated_R1_R5_20261009/Witch_G2C_Balance_Refinement_R5_20261009/docs/R4_TO_R5_BATTLE.patch)、[コード](imports/chatgpt_20261010_r1/expanded/Witch_G2C_Design_Consolidated_R1_R5_20261009/Witch_G2C_Balance_Refinement_R5_20261009/tools)、[原結果](imports/chatgpt_20261010_r1/expanded/Witch_G2C_Design_Consolidated_R1_R5_20261009/Witch_G2C_Balance_Refinement_R5_20261009/results)|固定小数点・古樹係数・時刻改訂は未正式承認|
|SUPPORT_AI_R6|[支援AI比較](imports/chatgpt_20261010_r1/received/system/Witch_G2C_Support_AI_R6_20261010/REPORT_R6.md)|[決定台帳](imports/chatgpt_20261010_r1/received/system/Witch_G2C_Support_AI_R6_20261010/docs/DECISIONS_R1_R6.json)、[R6-B入口](imports/chatgpt_20261010_r1/received/system/Witch_G2C_Support_AI_R6_20261010/tools/selected_final.py)、[原結果](imports/chatgpt_20261010_r1/received/system/Witch_G2C_Support_AI_R6_20261010/results/VALIDATION_SUMMARY_R6.json)|R6-Bが最新検証候補。一般の強化逆転6/2,000が残存|

成長R2のJSON内: `actors/growth`=レベル・基礎能力、`skills/ai_policy/timing_contract`=固有技能・連携、`equipment_rules/gear_templates/rarities/affixes`=6枠・適格条件・猫装具・品質・副効果・強化・研成・進化、`research/awakenings/caps/combat`=研究・覚醒・上限・計算、本文と参照モデル=装備個体ID・投資履歴・保存保護。元数値は修正せず、R5の新計算と別に参照する。

経済R3のJSON内: `expedition/rates/sources`=放置遠征・48時間候補上限・地域供給・確定ボス素材、`loot/regional_gear_theme_pools`=自然装備・品質抽選、`costs/onboarding/endgame`=制作/進化費用・初回報酬・長期課題。コードの資源準備シミュレーションは実ボス突破日数・面白さ・収益を証明しない。

R6の読取入口は `selected_final.py/FinalBattleR6`。`selected_model.py` はR6-Aの比較履歴。支援条件は内部AI候補であり、プレイヤーの編集機能ではない。結果値は原記録、今回の再実行ではない。詳細は [システム内容監査](imports/chatgpt_20261010_r1/reports/SYSTEM_AUDIT.md)。

## 装備ガチャ・衣装・家具・UIの系譜

|分野revision|仕様の入口|入力・コード・結果|現状態|
|---|---|---|---|
|EXPANSION_R1|[既存との整合](imports/chatgpt_20261010_r1/expanded/Expansion_Compatibility_R1_ORIGINAL/Witch_G2_Expansion_Compatibility_R1_20261010/docs/INTEGRATION_REVIEW_R1.md)|[分析・決定・課題](imports/chatgpt_20261010_r1/expanded/Expansion_Compatibility_R1_ORIGINAL/Witch_G2_Expansion_Compatibility_R1_20261010/data)、[検証](imports/chatgpt_20261010_r1/expanded/Expansion_Compatibility_R1_ORIGINAL/Witch_G2_Expansion_Compatibility_R1_20261010/validation)|構想・比較案を保全|
|COMMERCE_R2|[装備ガチャ・衣装・家具・共鳴](imports/chatgpt_20261010_r1/expanded/COMMERCE_R2_ORIGINAL/Witch_G2_Commerce_Production_Design_R2_20261010/docs/DESIGN_R2.md)|[商品/効果候補](imports/chatgpt_20261010_r1/expanded/COMMERCE_R2_ORIGINAL/Witch_G2_Commerce_Production_Design_R2_20261010/data/PRODUCT_AND_LIVING_CANDIDATE.json)、[制作規格案](imports/chatgpt_20261010_r1/expanded/COMMERCE_R2_ORIGINAL/Witch_G2_Commerce_Production_Design_R2_20261010/data/PRODUCTION_CONTRACT.json)、[コード](imports/chatgpt_20261010_r1/expanded/COMMERCE_R2_ORIGINAL/Witch_G2_Commerce_Production_Design_R2_20261010/tools)、[検証](imports/chatgpt_20261010_r1/expanded/COMMERCE_R2_ORIGINAL/Witch_G2_Commerce_Production_Design_R2_20261010/results)|直接販売・外見反映・試着・無料家具・配置/動作連携を設計対象として保存。価格・数量・実装規格・恒常効果は未確定|
|GACHA_RESEARCH_R3|[A/B/C比較](imports/chatgpt_20261010_r1/expanded/RESEARCH_R3_ORIGINAL/Witch_G2_Gacha_Research_R3_20261010/RESEARCH_REVIEW_R3.md)|[比較入力](imports/chatgpt_20261010_r1/expanded/RESEARCH_R3_ORIGINAL/Witch_G2_Gacha_Research_R3_20261010/data/CANDIDATES_R3.json)、[原結果](imports/chatgpt_20261010_r1/expanded/RESEARCH_R3_ORIGINAL/Witch_G2_Gacha_Research_R3_20261010/results/VALIDATION_SUMMARY.json)|Cを試遊第一候補、希少以上Aを比較として残す|
|AFTER_DRAW_R4|[ガチャ後の保護・分解・粉・強化](imports/chatgpt_20261010_r1/expanded/Witch_G2_Gacha_AfterDraw_Validation_R4_20261010/Witch_G2_Gacha_AfterDraw_Validation_R4_20261010/REPORT_R4.md)|[制約](imports/chatgpt_20261010_r1/expanded/Witch_G2_Gacha_AfterDraw_Validation_R4_20261010/Witch_G2_Gacha_AfterDraw_Validation_R4_20261010/docs/DECISION_AND_LIMITS.md)、[原結果](imports/chatgpt_20261010_r1/expanded/Witch_G2_Gacha_AfterDraw_Validation_R4_20261010/Witch_G2_Gacha_AfterDraw_Validation_R4_20261010/results/VALIDATION_SUMMARY_R4.json)、[コード](imports/chatgpt_20261010_r1/expanded/Witch_G2_Gacha_AfterDraw_Validation_R4_20261010/Witch_G2_Gacha_AfterDraw_Validation_R4_20261010/tools)|模擬在庫の条件付き検証。実戦闘・実DB・購入価値・整理時間は未検証|
|UI_VISUAL_R2_A|[A/B原画像](imports/chatgpt_20261010_r1/received/handoff/Witch_Codex_Design_Handoff_20261010_R1/supplements/ui_reference/UI_DIRECTION_R2_AB_ORIGINAL.png)|左A「暮らしが見える家」を直接目視確認|採用は美術方向のみ。紺/金・温かい家・人物背景を主役にする。全画面配置・通貨・個別容姿は未確定|
|UI_OPERATION_R1|[旧18画面操作HTML](imports/chatgpt_20261010_r1/received/handoff/Witch_Codex_Design_Handoff_20261010_R1/supplements/history/WITCH_UI_PROTOTYPE_R1.html)、[旧美術PNG](imports/chatgpt_20261010_r1/received/handoff/Witch_Codex_Design_Handoff_20261010_R1/supplements/history/UI_R1_REJECTED_VISUAL_OVERVIEW.png)|過去資料として保存。完全な旧UI ZIPは未回収|管理画面風美術は撤回。最終UIの正本として使わない|

衣装は4人の着せ替え、戦闘装備との分離、家/仲間/戦闘への反映、武器外観、購入前試着を含む。家具は配置・差替え、キャラ動作連携、単品/テーマ商品、無料獲得・制作を含む。所有による恒常効果と無料研究との共通上限は比較案。全ての数値・商品量・制作規格を正式化した資料ではない。

詳細は [Commerce/UI内容監査](imports/chatgpt_20261010_r1/reports/COMMERCE_UI_AUDIT.md)。UIのA、ガチャのA、戦闘案のAを混同しない。

## 原本・依存関係・検証

二つの外側ZIP → 戦闘R6内のR1〜R5統合ZIP → R1本文とR2/R3/R4各原ZIP。別系統は引継ぎ → AfterDraw R4原ZIP → Research R3原ZIP → Commerce R2原ZIP → Expansion R1原ZIP。各展開を独立パスに置き、同じZIPのSHA-256一致は再展開せず別出所として記録した。

[ZIP系譜台帳](imports/chatgpt_20261010_r1/verification/ARCHIVE_INVENTORY.json)、[保存実読](imports/chatgpt_20261010_r1/verification/IMPORT_READBACK.json)、[同梱manifest照合](imports/chatgpt_20261010_r1/verification/PACKAGED_MANIFEST_CHECKS.json)、[重複・版差](imports/chatgpt_20261010_r1/verification/DUPLICATE_RELATIONS.json)、[既存ID照合](imports/chatgpt_20261010_r1/verification/ID_RECONCILIATION.json)、[最終検証](imports/chatgpt_20261010_r1/verification/FINAL_VERIFICATION.json)を参照。

703件の原本/展開コピーは全件保存・hash一致。同梱15台帳948項目のうち947件は存在・size/hash一致、1件はR4内部分コピーのUI画像欠落。完全なCommerce R2と引継ぎ側に同一画像があるため原画像は回収済み。原台帳の欠落を埋めたりPASSへ改ざんせず例外として残した。

引継ぎ `context/` は会話要約、`reading/` は原文コピー、`checks/` と各 `results/validation/` は過去の検証記録。今回の実装許可や再検証完了ではない。
