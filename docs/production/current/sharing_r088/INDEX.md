# 『魔女の採集帳』R088 総合監査目次

**発売完成は未達。これはソースと証拠の監査用スナップショットです。**

- 実装基準：R087 `28d3d0b92c840f215a945f47e574fcb30ef2253b`。
- 最新ローカル記録：R088 `a63990d29ee3e1b9114c512c5abe9e30904c45fe`。R088は監査記録のみで、240入力の実装はR087と同じです。
- 監査ブランチ：`codex/audit-03to05-20261015-r088`。このブランチの共有コミットはR088開発コミットとは別です。共有マニフェストで元の版と各ファイルを照合できます。
- 親：以前の共有R046 `1547dde77605a3e16195f892d9add20b66d5c63a`。既存main・開発履歴は変更せず、重いローカル履歴を共有コミットの祖先に含めていません。
- ソースは固定チェックポイントから取得。補足の未追跡ローカル証拠は別の由来として明記し、R088に含まれていたとは扱いません。既存の未コミットPBX/PROJECT_CURRENT変更はMacに別途保全し、検証済みソースへ混入させていません。
- **HumanとChatGPTの総合レビュー待ち。共有後の新しい大規模仕様変更・実装・アセット制作は一時停止。** 過去のNEXT_ACTIONSや自律継続の記述より、この待機状態を優先します。

## 読む順番と一次証拠

- [最新報告 R088](../FINAL_LOCAL_REPORT_R088.md)
- [完成条件台帳：実装・検証・品質・正式承認を分離](../qa_drafts/final_acceptance_r360/COMPLETION_REGISTER_R014.json)
- [3分野固定版監査の統合判定](../qa_drafts/final_fixed_audit_r466/root/FINAL_VERDICT_R001.json)
- [ゲーム・保存監査](../qa_drafts/final_fixed_audit_r466/gameplay/REVIEW_R001.md)
- [UI・美術監査](../qa_drafts/final_fixed_audit_r466/ui_art/REVIEW_R001.md)
- [課金監査](../qa_drafts/final_fixed_audit_r466/commerce/REVIEW_R001.md)
- [SwiftUI・SpriteKit実装](../../../../native/WitchApp)
- [ゲームCore・安定ID・保存・設定・試験](../../../../native/WitchGameCore)
- [課金権威モデルと試験](../../../../tools/witch_purchase_authority/README.md)
- [設計正本と判断履歴](../../../design)
- [30/90日16条件の経済試験](../qa_drafts/economy_release_matrix_r374/candidate_r002/runner_r002/runs/R374_MATRIX_001/RUN.json)
- [経済試験の独立評価](../qa_drafts/economy_release_matrix_r374/independent_qualitative_review_r001/REVIEW_R001.md)
- [複数ビルドの受入範囲](../qa_drafts/build_diversity_acceptance_r428)
- [通常画面での全5地域進行](../qa_drafts/normal_progression_continuation_r443/independent_review_r001/REVIEW_R001.md)
- [15課題の通常装備勝利と制約](../qa_drafts/native_challenge_completion_r449/independent_review_r001/REVIEW_R001.md)
- [新規無ガチャ3seedのうち追加2seed](../qa_drafts/zero_summon_seed_robustness_r452/ROOT_SCOPED_RESULT_R001.json)
- [159制作単位の個別台帳](../qa_drafts/asset_readiness_r308/ASSET_READINESS_R001.json)
- [159単位・敵30単位の最新整理](../qa_drafts/completion_priority_r457/FINAL_LOCAL_REMAINDERS_R001.json)
- [未観測recoverの分類](../qa_drafts/completion_priority_r457/RECOVERY_ELIGIBILITY_R002.json)
- [衣装・家具の実操作と保存](../qa_drafts/wardrobe_furniture_runtime_r433/ROOT_CLOSEOUT_R001.json)
- [読書衣装の後続修正検証](../qa_drafts/native_reading_mantle_r446)
- [R465 両SDKビルド](../qa_drafts/native_completion_r465/ROOT_BUILD_RESULT_R001.json)
- [保護ファイル数の訂正：15,400](../qa_drafts/native_completion_r465/PROTECTION_COUNT_ERRATUM_R002.json)
- [R465 実画面・保存・冷起動](../qa_drafts/native_completion_r465/ROOT_RUNTIME_RESULT_R001.json)
- [R462 失敗したIME解除](../qa_drafts/native_completion_r462/ROOT_RUNTIME_RESULT_R001.json)
- [StoreKitクラッシュ・権限エラーの区別](../qa_drafts/final_fixed_audit_r460/root/STOREKIT_INCIDENT_READBACK_R001.json)
- [R461 契約と初回失敗・修正後結果](../qa_drafts/authority_contract_r461)
- [R463 隔離永続ストアと7プロセス試験](../qa_drafts/authority_persistence_r463)
- [代表実画面と撮影版](GALLERY.md)
- [Macに保全した一次証拠のパス・ハッシュ](LOCAL_ONLY_EVIDENCE_R001.json)
- [再現可能な範囲と不足物](REPRODUCTION.md)
- [総合レビュー待ち・再開手順](REVIEW_HOLD_R001.json)
- [共有ファイルの版・SHA-256・Git blob](SHARED_PAYLOAD_MANIFEST_R001.json)

## R046からの主な変化

| 領域 | 現在の到達点 | まだ証明できないこと |
|---|---|---|
| 保存 | 世代保存・破損/将来形式の扱い・復旧・取引重複防止、通常UIと冷起動の照合を追加 | 実機電源断・全OS条件 |
| 通常進行 | 全5地域30通常戦・15課題を通常画面で検証。別途、無ガチャ新規Core3seedの仮想30日到達を記録 | 人の自然なペース・全ビルド最適性。UI系譜の過去5回の無料QAガチャは消していない |
| 装備・経済 | 自然入手、制作、進化、強化/錬成、分解、装備セット、30/90日16条件、複数ビルドの検証を追加 | 正式価格・販売数・実購入価値・継続率。購入相当の入力は実課金ではない |
| UI・美術 | 家と主要画面、衣装/家具/装備外観、状態別動作を統合。読書衣装とIME検索解除を修正 | 159単位はすべてPARTIAL_OR_NOT_ACCEPTED。17敵recover未観測は17不具合ではなく、全30品質合格でもない |
| 課金 | Xcodeローカル購入/キャンセル/取得失敗/復元/重複、mock→装備受取、署名形式の隔離検証、Swift契約と永続保存を追加 | 本番サービス・実ネットワーク・通常アプリの正式課金配線は未実装。実Apple Sandboxも未実施 |
| iOS | 最新R465の同じ240入力/1922資源から両SDKRelease成功、実画面と保存一致 | iPhoneOSは無署名コンパイル。実機・配布・正式品質合格ではない |

最新3分野監査は確認範囲内で再現P0/P1を報告していません。これは未発見の不具合がない保証ではありません。旧StoreKit `Code3/notEntitled` の根本原因は未確定で、空商品配列のnil強制アンラップとは因果関係を立証していません。IMEのR462失敗、R448の初回5assertion失敗とwrapper未完了、R461のfixture/コンパイル失敗、R463の初回assertion失敗、R465の事前検査失敗を保全しています。原記録のPENDING/INCOMPLETEを後からPASSへ書き換えていません。最新判定・訂正と対にして読んでください。

試験件数は範囲別です。R461のSwift37件はR463の45件に含まれ、加算した独立要件数ではありません。R463は別途7プロセスの再起動/競合試験があります。R449はその実行で15課題に勝利し、初回クリア数は7→15の+8です。仮想時計のCore試験を人間の通し試験と読み替えないでください。

## Humanの操作・決定と、開発側に残る作業

Humanが必要なのは、Apple Account/Developer・App Store Connectの認証と設定、実機導入/操作への協力、正式仕様・美術・販売商品/価格の採用、新規サービス契約や公開の判断です。共有権限は今回のPrivate監査ブランチのみです。

**本番サービスと通常アプリ課金接続の実装、追加の美術品質審査は開発側の未完了作業でもあります。Human承認待ちだけに置き換えていません。** 総合レビューで今後の優先順位を決めてから再開します。実課金・本番公開・有料契約・第三者連絡は未実施です。

共有はコード/軽量証拠を中心とし、アプリ・原画・動画・DerivedData・Simulator内部全体は含めていません。完全なiOS再ビルド/見た目の再審査にはMac保管資源が必要です。旧R046由来のファイルも親から残っており、共有manifest外の全ファイルを最新版証拠とは扱わないでください。
