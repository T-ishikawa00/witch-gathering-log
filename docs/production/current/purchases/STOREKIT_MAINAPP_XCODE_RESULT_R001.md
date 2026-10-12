# メインアプリ StoreKit Xcode Environment 試験 r001

日時: 2026-10-10 12:42–12:44 JST
環境: Xcode 26.6 / iOS Simulator 26.5, `StoreKit Local QA 20261010` (`A8E9E99B-F6DC-4EF0-90D8-CB1C4202D514`)
アプリ: `local.witch.autonomous.r1`, Xcode scheme `WitchStoreKitQA`, Debug、起動引数 `--qa-isolated --qa-save-key=storekit-integration-r001 --xcode-local-storekit-qa --screen=購入検証`
StoreKit設定: `native/StoreKitLocalQA/iOSRunner/AppProbe/Products.storekit`。Xcode Runから products=2 を取得。試験商品は `local.witch.test.furniture` (non-consumable) と `local.witch.test.ticket` (consumable) のローカルQA専用。価格表示は¥100だったが、各システム購入確認画面に `[Environment: Xcode]` と「For testing purposes only. You will not be charged for confirming this purchase.」を確認。実課金・Apple Account入力・外部通信は行っていない。

## メインアプリで確認した動作

- 起動直後は商品2件、検証机未所有、QAレシート0件。
- 検証机をXcode Environmentで購入。StoreKit確認に成功し、transaction ID 6。ゲームのQA画面は `delivered(transactionID: 6)`、机所有、レシート1件を表示。ホームへ戻ると家のシーンに机と机で読書するキャラクターが描画された。
- 検証チケットを購入。transaction ID 7。成功後に `storekit_qa_ticket=1`、レシート2件。これはQA専用通貨であり、ゲーム抽選には使用されない。
- QAパネルを離れて再度開くと所有・通貨・レシート件数が維持された。設定画面は revision 3 を表示し、QAパネルは机所有、チケット1、購入レコード2を表示した。保存JSONの実読取は返金後のrevision 4を下記の通り確認。
- XcodeのManage StoreKit TransactionsからWitchGathering transaction 6をRefund。Xcode取引履歴は `Refunded` / `Revoked`。アプリホームから机と読書表現が消え、再度QAパネルを開くと机未所有、QAチケット1、レコード3。QA保存JSON revision 4に transaction 6 の purchase + revocation、transaction 7 のticket purchaseがあり、`localStoreKitQAOwnedProductIDs=[]`。
- Refund後の復元も実施。StoreKitの確認は「Press OK to simulate authenticating with an Apple Account. [Environment: Xcode]」のみ。OKを押し、実アカウントの認証情報は入力していない。アプリは「ローカル復元完了」を表示し、返金済み机は未所有、consumable ticketは1のまま。消費型が復元対象から除外され、revocation後にownershipが戻らないことを確認。
- 再読込後も机が見えなかった。QA ownershipが有効な間に、通常ホームシーンへ机が出ていることを実画面で確認した。
- Xcode再ビルドをせず `simctl terminate` → `simctl launch` で同じインストール済みアプリを終了・再起動。QA起動引数なしの通常ホームへ戻った。再起動前後のsave JSON SHA-256は同じ `0ed5083003ba442b0c57a974ce2d91ba9b3acff70bebacb64048e149db989a2a`。再起動後もrevision 4、tx6 purchase+revocation、tx7 ticket purchase、ticket1、家具owned set空が維持された。実行バイナリUUID (arm64) `3EA62BC8-9106-3303-B39C-6FA562D76E2E`。

## 監査上の留保

- 机の購入ボタンを購入済み状態でもう一度押したが、取引一覧やQA状態に変化が見えなかった。重複イベントを明示的に再配送するUIはなく、transaction ID 6の重複commit idempotenceをこのUI操作だけで確定しない。sink synthetic regressionは独立した別証拠として扱う。
- 模様替え画面で「植物研究の机を置く」を押すと、このQAセーブでは進行条件未達モーダルとなった。購入QA所有中の机はホーム背景に直接反映されていたため、これはゲーム進行条件付きの配置操作であり、購入権利がホーム描画へ届かない現象とは異なる。通常の無料家具/進行ゲートと有料商品数・配置条件の正式仕様は未承認。
- UIでのcancel、保留、保存失敗時にfinishしないこと、同transaction callback再配送、商品取得error/emptyはこのRunでは未実施。Xcode StoreKit本番/sandbox、サーバー検証、App Store Connect登録、実機は未検証。本試験だけで販売readyとは判断しない。

## ビルド・保存証拠

- Xcode `WitchStoreKitQA` scheme build/run succeeded for the dedicated iOS Simulator. The simulator-installed app that executed the UI cases had UUID arm64 `3EA62BC8-9106-3303-B39C-6FA562D76E2E`, x86_64 `FD4C584E-62AA-3C25-96C4-B5E53430E72B`. A separate CLI-derived build artifact produced during setup had UUID arm64 `DACDB5A3-DC4D-3F20-9A90-FEE57A006D8A`, x86_64 `E3A994D2-8FDE-3D5C-9F75-A44B9A036C9D`; it is not claimed to be the simulator-installed executable.
- `GameStoreKitQA.swift` SHA-256 `5c67a727fd8c390e5c94f8351429fdb64773a99aeed0390e04fe17f450162733`
- `GameStoreKitQASink.swift` SHA-256 `5fe30ef2b12fba102d9d1edee8a0f08e6c92d79a03e75263cdb6ba925ab07255`
- `ReusableBridge.swift` SHA-256 `4c6582273ac9c19e775e89bf6b2cc9d75ac2d3abe99718be6fa66f6de60ea6b7`
- scheme SHA-256 `d197aaaec8ed06fad6181d857ca9ab84d54ad1098d264b1cab5b38f1af7ec967`
- `Products.storekit` SHA-256 `c0861fbcbe3173144018923b1fff7a7262f8990905d642e0dc302116272fbc3f`
- Save file: simulator app container `Library/Application Support/Witch03to05R1/qa-storekit-integration-r001-save.json`. Read-only snapshot was inspected locally; it contains revision 4, one QA ticket, three records (furniture purchase, its revocation, ticket purchase), and no current QA furniture ownership. This is a simulator-only, isolated QA save.

この記録はローカルXcodeテスト証跡であり、販売・本番課金・正式な所有権仕様の承認ではない。
