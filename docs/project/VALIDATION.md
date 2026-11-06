# 今回の検証結果

確認日：2026-11-07 JST。対象はW008の最終作業入力261件とbyte一致するsnapshot、別の再現用project、固定資材pack。アプリのルール・ビジュアルは変更していない。新規commitのhashとremote読戻しは整備完了receiptで追跡する。

|試験|成功|失敗|skip／未実施|判定|
|---|---:|---:|---|---|
|W008ソースSHA照合|261|0|0|全入力一致|
|固定資材の入力・出力hash|1,923|0|0|全ファイル一致、365,929,993 bytes|
|Core最終run|418|0|17 skip|435 total。skipは成功に含めない|
|資材copy安全性テスト|4|0|0|変更・余剰入力、traversal、symlinkを拒否|
|Simulator Release build-for-testing|1|0|0|Xcode27.2／SDK27.2、専用Bundle ID、署名なし|
|iPhoneOS Release build|1|0|実機install・run未実施|署名なしcompileのみ|
|UI最終スモーク|7|0|全48画面網羅・host故障fixtureは未実施|新規専用iPhone17e／iOS27.2、UUIDごとのQAセーブ|
|実機・Apple Sandbox・本番IAP|0|0|未実施|本人／外部環境の段階|

7 UI試験は、5入口・戻る／閉じる、制作目標の非消費とcold再読込、音設定の保存、制作取消・連打・処理表示・cold結果、装備セット参照品の分解保護と再起動、研究の消費と保存、未接続ショップの非購入状態を確認した。合成fixtureを使うため、自然進行・面白さ・製品受入れの証拠にはしない。

## 初回の失敗と対応

- 裸のCore試験：435 total、407成功、20skip、8失敗。専用evidence rootの未指定と、Git保存候補から欠けていたR227 fixtureが原因。原fixtureの出所・hashを確認して追加し、専用wrapperへ設定を集約。コードや期待値を緩めず、最終runは418成功・17skip・0失敗。
- Simulator初回：StoreKit helper 1件の選別漏れでbuild失敗。最終作業manifestとの照合で追加し、261件一致・build成功。
- UI初回：6成功・1失敗。故障UI試験用のhost準備fixture／UI48FaultRunがなく、安全停止した。これは解消済みにせず、当該host故障試験を未実施項目に残す。最終スモーク7件は明示した別の対象集合。
- 独立レビューで再現用のplistに元Bundle IDが残ることを検出。projectとapp／test plistを整合させ、専用IDへ変更後のbuildと7 UI試験を最終結果に採用した。元のTeam・署名・実機projectは変更なし。

## skipの内訳

[skip台帳](evidence/CORE_SKIPS.json)に17件を記録。購入Python交換fixture1、成長感度snapshot1、長期経済sweep2、既得装備／進行比較等5、購入配送fixture7、購入transaction固定fixture1。長期の候補経済・過去seed・host購入fixtureを必要入力なしに有効化しなかった。

## 証拠と限界

[今回のrun summary](evidence/VALIDATION.json)、[ソースreceipt](evidence/SOURCE_SNAPSHOT.json)、[画面出所](SCREENSHOTS.md)を参照。完全ログ・xcresult・個人用の実行パスはローカル最終報告から参照する。共有用に生ログ・実セーブ・端末IDを転載しない。

コンパイラの既存警告は残っている。警告0件・全端末合格とはしていない。2026-10-18やW008/R020の過去試験と今回の件数は合算しない。アプリはGit＋固定資材packによる再現であり、Gitのみの完全なasset再生成ではない。
