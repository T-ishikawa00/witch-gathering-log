# ゲーム本体・Xcode StoreKit追加検証 R002

2026-10-10 13:31 JST。ローカルXcode環境のみ。実課金・Apple Account認証・セキュリティ/SIP変更なし。本番課金完成ではない。

- 空商品: `local.witch.test.missing` → `WitchGathering.StoreKitLocalQAError.productUnavailable("local.witch.test.missing")`。クラッシュ/付与なし。
- 購入キャンセル: Xcode購入シートの閉じる操作 → `cancelled`。検証券1、記録3のまま。
- 実購入経路の保存失敗: QA注入後、Xcode購入成功ID8 → `Error Domain=NSCocoaErrorDomain Code=640 "空き領域が不足しているので、ファイルを保存できませんでした。"`。保存前後のSHA256同一、検証券1/記録3。Xcode取引一覧に `This transaction has not been finished by calling finish()` を確認。
- 未完了再配信: **同じインストール済みバイナリ/コンテナ**をsimctlで終了・同じQA引数を付けて再起動。購入シートを再表示せずID8が `Transaction.unfinished` から永続化され、検証券2/記録4、revision5。finish警告消失。2回目の同一再起動後、保存ファイルはbyte単位で同一。旧Probeの別コンテナ事象とは区別する。
- 保留と承認: 設定をXcode Runへ適用後、ID10はPending Approval、アプリ`pending`、検証券3/記録5のまま。XcodeでApprove後、検証券4/記録6、ID10のfinish警告消失。UIだけpendingが残る不備を検出し、永続化コールバックで更新表示する修正を追加（修正後再検証は別記）。
- 保留と却下: ID11をPending ApprovalからDecline。アプリは検証券4/記録6のまま。StoreKitのpurchase応答pendingと現在の承認状態は異なる。却下のアプリ側通知まで立証したとは記録しない。
- 商品取得例外: Xcode Simulated StoreKit FailuresのLoad Products=Network Errorを設定し本体Run。起動時および購入ボタンで `StoreKit.StoreKitError.networkError(Foundation.URLError(_nsError: Error Domain=NSURLErrorDomain Code=-1009 "(null)"))`。コンソール下層は`ASDErrorDomain Code=511`、client-environment-type=XcodeTest。クラッシュせず、保存byte同一、付与なし。空配列と例外の両方を実UI経路で検証。
- 試験後 `Products.storekit` のAsk to Buy=false、StoreKit error injection=[]に復旧。

証拠: `mainapp_r002/` の前後JSON、エラー全文receipt、設定、バイナリ/コンテナ同一性記録。

| 保存 | revision | 検証券 | 記録 | SHA256 |
|---|---:|---:|---:|---|
| before / failed | 4 | 1 | 3 | 0ed5083003ba442b0c57a974ce2d91ba9b3acff70bebacb64048e149db989a2a |
| recovered / second restart | 5 | 2 | 4 | 222c44a8e44c8d0a1dd8b2c5edd9b6a4ba246c20b1f1f4d114b1e07a18003f35 |
| pending ID10 | 6 | 3 | 5 | f919a2474aa612512004ef2bc44cf99de467920c7e8f02cb8356b519f107e747 |
| approved ID10 / declined ID11 / network failure | 7 | 4 | 6 | 99762b5ed462c5466daaaeb7d0715fe0a52340849b2fbc65b2ca0d1e7edc4803 |

ID9は設定変更を新しいXcode Runへ反映する前に実行した通常のXcode成功取引。保留の証拠には使用しない。OSの権限変更は必要なかった。SKTestSession Code3/notEntitledは未解決の別経路であり、この結果をもって解決済みとはしない。

## 13:45 JST additional UI regression and active entitlement

Xcode Ask-to-Buy transaction ID12 (non-consumable QA furniture) was pending without entitlement. After Approve, the repaired UI callback displayed persisted-update status with 7 records, owned QA furniture, and 4 QA tickets. The transaction finished warning disappeared. Closing QA sheet showed the desk with Luna using it in the native home. After same-installed-app restart with the same QA arguments, the save was byte-identical. Evidence: approved_furniture_update.json, approved_furniture_save.json, furniture_restart_save.json, approved_furniture_ui.png, approved_furniture_home.png. This is QA-only visual integration: normal production ownedFurnitureIDs and placement actions remain separate, and no production product is enabled. Ask-to-Buy=false and failure injection=[] restored in the configuration file.
