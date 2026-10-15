from pathlib import Path
import json,posixpath,datetime,subprocess,hashlib
R=Path(__file__).resolve().parents[4];D=Path(__file__).resolve().parent;Q='docs/production/current/qa_drafts/';S=json.loads((D/'local_only/SELECTION_REVIEWED_R003.json').read_text())
links=[
('最新報告 R088','docs/production/current/FINAL_LOCAL_REPORT_R088.md'),
('完成条件台帳：実装・検証・品質・正式承認を分離',Q+'final_acceptance_r360/COMPLETION_REGISTER_R014.json'),
('3分野固定版監査の統合判定',Q+'final_fixed_audit_r466/root/FINAL_VERDICT_R001.json'),
('ゲーム・保存監査',Q+'final_fixed_audit_r466/gameplay/REVIEW_R001.md'),
('UI・美術監査',Q+'final_fixed_audit_r466/ui_art/REVIEW_R001.md'),
('課金監査',Q+'final_fixed_audit_r466/commerce/REVIEW_R001.md'),
('SwiftUI・SpriteKit実装','native/WitchApp'),('ゲームCore・安定ID・保存・設定・試験','native/WitchGameCore'),('課金権威モデルと試験','tools/witch_purchase_authority/README.md'),('設計正本と判断履歴','docs/design'),
('30/90日16条件の経済試験',Q+'economy_release_matrix_r374/candidate_r002/runner_r002/runs/R374_MATRIX_001/RUN.json'),
('経済試験の独立評価',Q+'economy_release_matrix_r374/independent_qualitative_review_r001/REVIEW_R001.md'),
('複数ビルドの受入範囲',Q+'build_diversity_acceptance_r428'),
('通常画面での全5地域進行',Q+'normal_progression_continuation_r443/independent_review_r001/REVIEW_R001.md'),
('15課題の通常装備勝利と制約',Q+'native_challenge_completion_r449/independent_review_r001/REVIEW_R001.md'),
('新規無ガチャ3seedのうち追加2seed',Q+'zero_summon_seed_robustness_r452/ROOT_SCOPED_RESULT_R001.json'),
('159制作単位の個別台帳',Q+'asset_readiness_r308/ASSET_READINESS_R001.json'),
('159単位・敵30単位の最新整理',Q+'completion_priority_r457/FINAL_LOCAL_REMAINDERS_R001.json'),
('未観測recoverの分類',Q+'completion_priority_r457/RECOVERY_ELIGIBILITY_R002.json'),
('衣装・家具の実操作と保存',Q+'wardrobe_furniture_runtime_r433/ROOT_CLOSEOUT_R001.json'),
('読書衣装の後続修正検証',Q+'native_reading_mantle_r446'),
('R465 両SDKビルド',Q+'native_completion_r465/ROOT_BUILD_RESULT_R001.json'),
('保護ファイル数の訂正：15,400',Q+'native_completion_r465/PROTECTION_COUNT_ERRATUM_R002.json'),
('R465 実画面・保存・冷起動',Q+'native_completion_r465/ROOT_RUNTIME_RESULT_R001.json'),
('R462 失敗したIME解除',Q+'native_completion_r462/ROOT_RUNTIME_RESULT_R001.json'),
('StoreKitクラッシュ・権限エラーの区別',Q+'final_fixed_audit_r460/root/STOREKIT_INCIDENT_READBACK_R001.json'),
('R461 契約と初回失敗・修正後結果',Q+'authority_contract_r461'),
('R463 隔離永続ストアと7プロセス試験',Q+'authority_persistence_r463'),
('代表実画面と撮影版','docs/production/current/sharing_r088/GALLERY.md'),
('Macに保全した一次証拠のパス・ハッシュ','docs/production/current/sharing_r088/LOCAL_ONLY_EVIDENCE_R001.json'),
('再現可能な範囲と不足物','docs/production/current/sharing_r088/REPRODUCTION.md'),
('総合レビュー待ち・再開手順','docs/production/current/sharing_r088/REVIEW_HOLD_R001.json'),
('共有ファイルの版・SHA-256・Git blob','docs/production/current/sharing_r088/SHARED_PAYLOAD_MANIFEST_R001.json')]
intro='''# 『魔女の採集帳』R088 総合監査目次

**発売完成は未達。これはソースと証拠の監査用スナップショットです。**

- 実装基準：R087 `28d3d0b92c840f215a945f47e574fcb30ef2253b`。
- 最新ローカル記録：R088 `a63990d29ee3e1b9114c512c5abe9e30904c45fe`。R088は監査記録のみで、240入力の実装はR087と同じです。
- 監査ブランチ：`codex/audit-03to05-20261015-r088`。このブランチの共有コミットはR088開発コミットとは別です。共有マニフェストで元の版と各ファイルを照合できます。
- 親：以前の共有R046 `1547dde77605a3e16195f892d9add20b66d5c63a`。既存main・開発履歴は変更せず、重いローカル履歴を共有コミットの祖先に含めていません。
- ソースは固定チェックポイントから取得。補足の未追跡ローカル証拠は別の由来として明記し、R088に含まれていたとは扱いません。既存の未コミットPBX/PROJECT_CURRENT変更はMacに別途保全し、検証済みソースへ混入させていません。
- **HumanとChatGPTの総合レビュー待ち。共有後の新しい大規模仕様変更・実装・アセット制作は一時停止。** 過去のNEXT_ACTIONSや自律継続の記述より、この待機状態を優先します。

## 読む順番と一次証拠

'''
ending='''
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
'''
for target in [D/'INDEX.md',D/'AUDIT_README_R001.md']:
 root=target.name=='AUDIT_README_R001.md'
 content=intro+'\n'.join('- ['+label+']('+ (path if root else posixpath.relpath(path,str(D.relative_to(R)))) +')' for label,path in links)+'\n'+ending
 target.write_text(content)
g=json.loads((D/'GALLERY_MANIFEST_R001.json').read_text());out=['# 実際のSimulator画面\n','最新R465の4枚と、以前の通常操作・失敗証拠8枚。画像は加工していません。CFBundleVersionは1を再使用しているため、内部版・実行ファイルSHA・runで識別します。画面は操作/状態の証拠であり、製品品質合格ではありません。最新R465のガチャ全画面や通し動画はありません。\n']
for x in g['images']:
 p=posixpath.relpath(x['path'],str(D.relative_to(R)));out+=['## '+x['captureRelease']+' / '+x['caption'],'\n![実画面]('+p+')\n','- SHA-256: `'+x['sha256']+'`','- 状態revision: `'+str(x.get('stateRevision','see source checkpoint'))+'`','- 実行ファイルSHA-256: `'+str(x.get('executableSHA256','see R462 root/runtime receipt'))+'`','- [撮影・状態の原記録]('+posixpath.relpath(x.get('sourceRun') or x['sourceCheckpoint'],str(D.relative_to(R)))+')\n']
(D/'GALLERY.md').write_text('\n'.join(out)+'\n')
(D/'REPRODUCTION.md').write_text('''# 再現範囲と実行条件

この共有作業ではゲーム試験の再実行や新しいビルドは行っていません。既存結果の版・ハッシュ・内容を照合しました。

1. `SHARED_PAYLOAD_MANIFEST_R001.json`のファイルSHA-256を確認する。R088由来とローカル補足を区別する。240入力はR465 `NATIVE_SOURCE_MAP_R001.json`と一致する。
2. `native/WitchGameCore/Package.swift`はSwift6.0、macOS14/iOS17以上。Coreソース・Resources・Testsを共有。基本の`swift test --package-path native/WitchGameCore`はdefault構成で、通常アプリのフラグ付き結果や過去のcandidate試験と同一とは限らない。実行時は新しいscratch/outputを割り当てる。
3. 各QAのcandidate source、INPUT_MANIFEST、run driver、初回失敗と最終RESULT/RUNを合わせる。R374/R448/R452はフラグ・seed・仮想時計・plannerを使う。過去の保存済み複製packageを現在コードで置換すると同じ実験にはならない。省いた複製のパスとSHAはOMITTED_REPRO_COPIESに残す。
4. `tools/witch_purchase_authority/README.md`のローカルunittest手順を利用できる。署名試験は`signed_audit_requirements.lock`依存が必要。未導入時のskipはPASSとしない。synthetic証明書/fixtureのみで、Apple秘密鍵・実購入トークンを含めない。サーバー/Appleへの通信や本番付与はできない。
5. R465の実際の生成project、GameInfo、SOURCE/RESOURCE_SHA256を`build_identity/`に格納した。これは対応関係の一次証拠であり、共有先ディレクトリへ単独で移してそのままビルドするprojectではない。元の凍結パス・PreparedResourcesを参照する。通常`native/WitchGathering.xcodeproj`のPBXは継承されたGit版で、Macの未コミットPBXとは異なり、最新成功ビルドを保証しない。
6. 完全なiOSアプリ再構築にはLOCAL_ONLY_EVIDENCEに列挙した1922資源、元の凍結入力、Xcode26.6(17F113)/SDK26.5相当が必要。監査共有だけで全画面・動作・音を再現できるとは主張しない。build_toolsのsealed manifestは既存出力/保護ハッシュを固定しているため、無編集の再実行や上書きを行わない。
7. 最新実画面はR465run。補助画面R456/R443/R433は別版。R465通し動画は未撮影。R424動画3本の絶対パス/版/SHAをLOCAL_ONLY_EVIDENCEに記録し、原本はMacへ保全。

原画・編集元・セーブ・Git履歴・固有QA証拠を保護する。レビュー中は大規模開発を停止。再開時は新たな指示、Git状態/実行プロセス/容量、R088報告と完成台帳を確認してから未完了項目へ進む。既存307アプリを削除/変更しない。
''')
(D/'REVIEW_HOLD_R001.json').write_text(json.dumps({'at':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).isoformat(),'status':'PAUSED_FOR_HUMAN_CHATGPT_COMPREHENSIVE_REVIEW_AFTER_SHARE','userAuthorizedPushOnly':'T-ishikawa00/witch-gathering-log new private audit branch','developmentCheckpoint':S['sourceCheckpoint'],'auditedImplementation':S['auditedImplementation'],'largeDevelopmentPaused':True,'newGameplayCodeChanges':False,'ongoingOwnedBuildOrGameProcessObserved':False,'resumeSteps':['ReceiveHumanreviewandpriorities','VerifyHEAD,dirtyfiles,activeprocesses,storage','ReadFINAL_LOCAL_REPORT_R088andCOMPLETION_REGISTER_R014','Resumeunresolveditemswithoutrecreatingpassedfeatures'],'protectedDirtyFiles':['native/WitchGathering.xcodeproj/project.pbxproj','/Users/PUBLIC_USER/Projects/idle-loot-rpg/PROJECT_CURRENT.md'],'localProtectedSnapshotFolder':str(D/'local_only'),'remaining':['productionpurchaseimplementationandintegration','actualAppleSandboxandphysicaldevice','completeartqualityacceptance','humanformalspec/art/productdecisions'],'releaseComplete':False},ensure_ascii=False,indent=2)+'\n')
print('Wrote audit index/gallery/reproduction/review hold')
