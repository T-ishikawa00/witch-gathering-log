# 除外と重複再利用

外側ZIP2件を含む保存原本703ファイルを全件分類した。下表は保存先の件数であり、同一内容の複数コピーを含む。INCLUDED_ORIGINALは共有した同一内容への対応、REUSE_REMOTEは既存GitHubへの対応である。新規原本の実際のコピー数は台帳を参照する。

|分類|保存先件数|合計bytes|
|---|---:|---:|
|EXCLUDED_ARCHIVE|15|36,451,303|
|EXCLUDED_BINARY_DUPLICATE|1|39,448|
|EXCLUDED_IMAGE|9|1,268,829|
|EXCLUDED_INTERMEDIATE_OR_DUPLICATE|401|46,526,811|
|INCLUDED_ORIGINAL|267|9,802,397|
|REUSE_REMOTE|10|1,176,478|

重複ZIP15件、フルパッケージ、巨大な制作画像・検証スクリーンショット、旧UIの2.9MB HTML、撤回美術一覧、Workbook、詳細トレース・セル結果・開発チェックポイント、PID・環境・ブラウザ記録、HTML生成ランナーは同期対象から除く。全てローカル保全のままであり、削除していない。
世界カタログを含む既存の世界観・装備・地域設計は[既存GitHub台帳](EXISTING_REMOTE_REFERENCE.json)で照合し再利用する。衣装・家具・恒常効果の設計データは、世界29型や地域159単位とは別資料として収録した。

ローカル絶対パスを大量に含む旧SOURCE_MANIFEST、依頼原文、全保存台帳、保護baseline、検索記録は共有対象から除き、今回の相対パス台帳に置き換えた。PROJECT_CURRENT.mdの既存変更も今回の追加対象に含めない。
必要な例外は、UI A/Bの原画像1件とガチャ後R4の小さな操作検証HTML1件。Pythonは数式と契約を読むための原本ソースであり、実行用バイナリや再現環境は含めない。
