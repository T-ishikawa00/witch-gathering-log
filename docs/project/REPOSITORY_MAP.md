# 正本と保存範囲

この整備では既存の未コミット変更を取り込まず、旧mainを起点に新しいworktree／ブランチを作成した。main更新が成功した後は、新しいcloneのmainを共有用開発入口とする。元開発worktreeの版・未コミット設定と新mainを黙って混ぜない。

|保存対象|元開発側|整備後の共有範囲|
|---|---|---|
|W008のapp/core/UI test/helper|元開発HEAD d09b7f37と固定入力WORKING receipt|全261件を同じ相対位置へ選別保存。追加Core試験・入力をsource receiptに収録|
|元のXcode設定|個人Team・実機用変更を含む。保持|今回追加せず、新規`WitchReproduction.xcodeproj`へ可搬化した構成だけ保存|
|UI48・企画正本|元履歴と資料|コードと既存mainの企画資料を保持。全原納品ZIP・画面証拠を重複登録しない|
|runtime資材|固定W008 pack 1,923件／365,929,993 bytes|パス・SHA-256台帳のみ。所有者の別資材が必要|
|原画・編集元・候補・音源|元の素材群・制作フォルダ|今回追加しない。採否・権利・保存先を素材台帳で明示|
|Humanセーブ・署名秘密|所有者の既存環境・保全先|GitHubへ追加しない|
|大量の過去QA・build/cache|元環境と過去記録|今回追加しない。必要な伏字summaryと新規画面だけ保存|
|旧mainの未コミット文書1件、開発側の未コミット6パス|元worktreeにそのまま保持|整備commitへ混合しない|

## 正本の特定根拠

`WORKING_SOURCE_SHA256.json`とlive入力261件がすべて一致した。旧`SOURCE_SHA256.json`は最終作業入力と13共通項目が異なるため、`W008_LEGACY_SOURCE_SHA256.json`として履歴資料に限定する。最終入力の証拠には`W008_WORKING_SOURCE_SHA256.json`を使う。Core Package・83試験Swift等は最終アプリ261件と別枠で保存する。

元の開発ブランチには110commit・65,217追跡パスがある。大型QA出力、私有パス、未確認資材を含む全履歴を共有しないため、既存mainの履歴を親に必要な最終snapshotを保存した。元のcommitは消去・改変していない。単純にR088や元開発ブランチをmergeしたものではない。

元worktreeは共通Git directoryに依存するlinked worktree。フォルダ単体のコピーを独立したGit backupと呼ばない。新しいremote cloneを使った読戻し検証とローカル原画・セーブの保全は別々に扱う。

パス単位の追加sourceと管理対象外の対応は[保存差分台帳](LOCAL_REMOTE_GAP.csv)を参照。
