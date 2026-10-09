# 計算用参照ソースの読取対応

ソースは原本と同一バイト、権限0644で収録した。数式・条件・過去検証を読むための文書である。元のvendor/source配置、実行環境、ランナー全体は移植していない。importやファイルopenの相対位置は元配置を指すため、ここからそのまま実行しない。今回、import・テスト・シミュレーションを実行していない。

|元の依存先・役割|共有先|
|---|---|
|R6-B入口→支援AI B→支援AI A|[selected_final](sources/support_ai_r6/tools/selected_final.py)、[support_ai_b](sources/support_ai_r6/tools/support_ai_b.py)、[support_ai](sources/support_ai_r6/tools/support_ai.py)|
|R6のvendor/r5/toolsとfixtures/bootstrap|[battle_r5](sources/balance_r5/tools/battle_r5.py)、[precision_rules](sources/balance_r5/tools/precision_rules.py)、[compare_candidates](sources/balance_r5/tools/compare_candidates.py)、[fixtures](sources/support_ai_r6/tools/fixtures_r6.py)、[bootstrap](sources/support_ai_r6/tools/bootstrap.py)|
|R5のvendor/r01_r4/tools|[battle_model](sources/battle_r4/tools/battle_model.py)、[progression_bridge](sources/battle_r4/tools/progression_bridge.py)|
|R4のsource/growth_r2/validation|[成長計算](sources/growth_r2/validation/reference_model.py)、[成長JSON](sources/growth_r2/data/growth_gear_skills_R2.json)|
|成長R2のreference/world_catalog_R1_UNCHANGED.json|[既存GitHub世界カタログ](../../sources/world_r1/Witch_World_Design_R1_20261008/data/world_catalog.json)。同一SHA-256のため重複収録しない|
|R4のsource/economy_r3/toolsとdata|[経済計算](sources/economy_r3/tools/economy_model.py)、[経済JSON](sources/economy_r3/data/economy_R3.json)、[R4局所候補](sources/battle_r4/data/LOCAL_CANDIDATES.json)|
|AfterDraw R4のsource/research_r3/tools|[compare_gacha](sources/gacha_research_r3/tools/compare_gacha.py)、[比較入力](sources/gacha_research_r3/data/CANDIDATES_R3.json)|
|AfterDraw R4のsource/commerce_r2/data|[副効果・装備メタデータ](sources/commerce_r2/data/GEAR_METADATA_AND_NEW_AFFIX_PROPOSAL.json)|
|R6-B契約テスト|[test_final_r6b](sources/support_ai_r6/tools/test_final_r6b.py)|

data/SOURCE_LOCK、SOURCE_COVERAGE、SOURCE_HASHES、PRIOR_DESIGN_ARCHIVE_INDEXは当時の原本参照記録であり、共有フォルダの実行依存一覧ではない。そこに記載されたZIP、制作画像、レビュー中間結果等の除外は[除外方針](EXCLUSION_SUMMARY.md)で説明する。
