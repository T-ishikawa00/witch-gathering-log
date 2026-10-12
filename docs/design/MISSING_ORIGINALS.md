# 原本の回収状況・不足 R1

監査日: 2026-10-10 JST。検索は指定2ZIP・全内包ZIP、許可されたプロジェクトとDownloadsの関連名に限定。無関係な個人データ・ブラウザ保管領域・メールは探索していない。本文要約から原本を再制作していない。

|ID|実名/内容|現在の状態|
|---|---|---|
|INT-M01/回収済み|`Witch_G2C_Design_Consolidated_R1_R6_20261010.zip`|Downloadsで `(1)` のない名前を確認し保存。R1本文、R2/R3/R4原ZIP、R5統合原ZIP・実行snapshot、R6-A/B文書・コード・結果を受領。引継ぎのM01「未回収」は当時の記録|
|INT-M02/未回収|`Witch_G2_UIUX_R1_20261010.zip`|旧18画面の完全設計・検証原記録・全スクリーンショットを含むZIPがない。`READABLE_UIUX_SPEC_R1.html`も検索手掛かりとして未回収。操作HTMLと3画面比較PNGは保存済み。これは独立した旧UI履歴の残件|
|INT-M03/原梱包の1パス欠落・別原本で回収済み|ガチャR4内 `source/commerce_r2/source/UI_DIRECTION_R2_A_APPROVED_REFERENCE.png`|R4内部分コピーのmanifest/coverageは列挙するがmemberがない。完全Commerce R2と引継ぎ側に同size/hash画像あり。原画像不足ではなく、部分コピーの参照不整合として記録|
|INT-M04/不存在を断定しない|BATTLE_R1単体ZIPの正確名|正確な配布名は不明。R5統合ZIP内に原Markdownがあり、R1本文の欠落ではない。架空名や必須不足を追加しない|
|INT-M05/新規設計未確定|課金込みの全UI配置、衣装/家具の確定商品・効果、ガチャ接続経済|完成ファイルがあると推測しない。過去原本の紛失と、これからHumanが決める仕様を区別|

Expansion R1・Commerce R2・Gacha Research R3・AfterDraw R4は各原ZIP、設計文書、データ、検証コード・原結果を受領。UI A/B画像は直接目視確認し、左Aの美術方向を特定した。旧UI完全ZIPの不足が残るため「すべての過去資料が完全回収」とは報告しない。

R1〜R6回収後、R1〜R5統合ZIPや各R2/R3/R4を別々の不足として重複計上しない。Downloadsの単体Growth R2は内包原ZIPとのSHA-256照合対象とし、同一なら追加回収不要。

既存アセット/QA再現用の未納品・未確認事項は [既存MISSING_FILES](MISSING_FILES.md) を維持。今回の設計受領でアニメーション・実機・編集データの未納品まで解消したことにはしない。詳細な梱包例外は [DESIGN_CONFLICTS](DESIGN_CONFLICTS.md) INT-C11。
