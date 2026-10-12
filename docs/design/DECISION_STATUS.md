# 設計判断の状態 R1

更新: 2026-10-10 JST。根拠: [今回のユーザー依頼原文](imports/chatgpt_20261010_r1/authority/USER_REQUEST_ORIGINAL.txt)、[既存判断台帳](DECISION_LOG.md)。この整理自体は新しいゲーム仕様の承認ではない。

|状態|内容|効力・限界|
|---|---|---|
|Human承認済みの骨格|『魔女の採集帳』、魔女・弟子・鍛冶師・黒猫の4人、5地域、4人完全自動|手動スキル・作戦プリセット・AI条件編集を再導入しない。加入順・正式名・計算詳細まで確定しない|
|Human承認済みの外見正本|[witch_characters_R1.png](visual/witch_characters_R1.png)|UI Aの人物像で差し替えない。補助画の文字・年齢も未確定|
|Human採用済みのUI美術方向|左A「暮らしが見える家」。紺・アンティークゴールド、幻想的で温かい家|家/探索/仲間/工房/採集帳の5入口。ガチャ等を含む全画面配置は設計中|
|設計対象として確認された方向|装備ガチャ、衣装直接販売、家のカスタマイズ、家具販売/無料制作、恒常効果の検討|商品・数値・販売・制作・実装の一括承認ではない|
|最新の検証候補|R5固定小数点・古樹係数、支援AI R6-B|R6-B主比較は逆転6/2,000残存。Human正式採用・一般単調性の証明は未了|
|試遊第一候補|コモン入りガチャC|比較入力と次回の試遊候補。正式実装決定ではない|
|未確定|成長/経済数値、猫4装具/6枠詳細、ID対応、品質/副効果、本番保存方式|既存正本のnullをoverlayの値で上書きしない|
|未確定|確率・価格・無料回数・保証・粉・商品量・共鳴の上限/効果量|下表は比較値であり確定値ではない|
|撤回済み|旧BATTLE_R1の作戦設定提案、旧UI管理画面風美術|原本と操作HTMLを履歴として保持。復活させない|
|最終推奨外・比較保全|R6-A、希少以上ガチャA、UI B|R6-Aの失敗を保存。ガチャAは現在も比較対象であり全面撤回とはしない|

## 未承認の代表値

|分野|原候補値|位置付け|
|---|---|---|
|ガチャC|普通35/良質40/希少20/特級4/伝説1%、30円換算、無料5回/日|[研究R3](imports/chatgpt_20261010_r1/expanded/RESEARCH_R3_ORIGINAL/Witch_G2_Gacha_Research_R3_20261010/data/CANDIDATES_R3.json)の比較値|
|C保証|特級以上20回、伝説100回、目標50%と次伝説の目標保証|同上。自然ドロップの保証と別管理候補|
|旧ガチャA|希少80/特級17/伝説3%、150円換算、無料1回/日、伝説40回、特級以上10回|比較対象。UI A採用とは無関係|
|粉還元|普通1/良質2/希少4等|[AfterDraw R4](imports/chatgpt_20261010_r1/expanded/Witch_G2_Gacha_AfterDraw_Validation_R4_20261010/Witch_G2_Gacha_AfterDraw_Validation_R4_20261010/REPORT_R4.md)の感度・模擬在庫入力|
|共鳴|100点、衣装20点/家具2点、最大+3ポイント等|[Commerce R2](imports/chatgpt_20261010_r1/expanded/COMMERCE_R2_ORIGINAL/Witch_G2_Commerce_Production_Design_R2_20261010/data/PRODUCT_AND_LIVING_CANDIDATE.json)の案。所有/着用/配置条件・無料研究との上限共有は未確定|
|商品量|追加衣装4、家具10、候補価格|制作見積り案。既存159に含めない|
|旧経済R3|48時間上限、装備2個/時、森12粉/時|有料ガチャ導入前の候補。12粉/時×24時間=288粉/日|
|成長R2|Lv60、研成V、強化+3%、6枠、猫4装具|[原決定台帳](imports/chatgpt_20261010_r1/received/system/Witch_G2C_Support_AI_R6_20261010/docs/DECISIONS_R1_R6.json)は `PROPOSED_PRESERVED`|

詳細な引用・検証条件は [システム監査](imports/chatgpt_20261010_r1/reports/SYSTEM_AUDIT.md) と [Commerce/UI監査](imports/chatgpt_20261010_r1/reports/COMMERCE_UI_AUDIT.md)。保存成功・検証PASS・Human承認・本番統合・実機合格を別々に扱う。
