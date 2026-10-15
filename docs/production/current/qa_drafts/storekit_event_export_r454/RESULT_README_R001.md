# R454 ローカル購入・装備受取の検証結果

実際のXcodeローカル購入1件を、専用の模擬ホスト台帳へ渡し、装備1個・天井値・操作記録をSwiftの世代セーブへ一度だけ保存できた。これは本番課金の完成判定ではない。

- 検証アプリ: `local.witch.autonomous.r1.storekit.r454`、R004 Debug、Simulator iOS 26.5。
- 最終実行ファイル: `d4629570f955590affebb909f95f66744eb3dae9a6170eecc23ddccbee824539`。
- 購入はXcodeのテスト環境のみ。実課金・Apple Accountへの実認証・実機導入・外部送信は0件。
- 既存R445通常版の保存revision137は変更していない。

## 修正した問題

R003では購入済み取引2を再照会すると `transactionNotFound(2)` が返り、装備受取へ進めなかった。購入自体は成功し、QA券1枚と取引記録はrevision2へ保存済みだった。ホストへの要求は0件。検証用保存処理が完了した消耗型取引をfinishした後、`Transaction.all` の既定動作ではその取引を取得できないことが原因だった。

R004では専用QAアプリのInfo.plistに `SKIncludeConsumableInAppPurchaseHistory=true` を設定した。受取画面をiOS 18以降・この設定あり・DEBUG Simulator・専用引数・専用セーブに限定した。同じ取引2から復旧でき、追加購入はしていない。[Appleの設定仕様](https://developer.apple.com/documentation/bundleresources/information-property-list/skincludeconsumableinapppurchasehistory)

また、初回の商品0件は生成したXcodeプロジェクトのbundle設定が既定IDのままだったため、実際の検証アプリとStoreKit構成の適用先が一致しなかった。専用生成プロジェクトのIDを修正し、同じ実行ファイルで商品2件の取得を確認した。R004生成工程へも反映した。元のプロジェクトは変更していない。

これらを、過去の `ProbeApp.swift:36` のOptional強制アンラップ、`SKInternalErrorDomain Code 3`、Xcode自身の構成パスassertionとは別の問題として扱う。因果関係を示す証拠はない。

## 実際に確認したこと

| 操作 | 結果 |
|---|---|
| 存在しない商品・購入キャンセル | エラーまたはキャンセルを表示し、保存内容は不変 |
| Xcode購入成功 | 取引2を1件保存。revision1→2、検証券0→1 |
| 修正版で取引2を再照会・装備受取 | 装備4→5、天井値を1回更新、revision2→3 |
| 同じ取引の再送 | ホストの装備結果は同一。アプリの保存はバイト単位で不変 |
| ホストの模擬返金後に再送 | 拒否。ホスト負債1、アプリ保存は不変 |
| Xcodeの購入復元 | 消耗型商品を再付与しない。保存は不変 |
| 終了・再起動 | 商品2件を表示。revision3と保存SHAが一致 |

最終保存SHA: `63936957bb1ac8c592ee485b17591d294856652c04c06afc2d1766bc70a38034`。実行時間1,014.91秒/上限1,200秒、PNG6枚/上限6枚、証拠約2.26MB/上限30MB。元の失敗記録は削除していない。

## 証拠と限界

正確な値は `runtime_r001/RUNTIME_RESULT_R001.json`、実装・テスト集計は `ROOT_SCOPED_RESULT_R002.json`、独立監査は `runtime_independent_review_r001/REVIEW_R001.md`。ソース・生成物はR004の `postbuild_readback_r001/debug_BUILD_PASS.json` で照合した。

Swiftは25合格・0失敗・0スキップ、Pythonホスト処理は6合格。R453の保存中断・CAS競合・取引不一致の試験を含む。非消耗型商品の復元はR377の証拠を継承し、今回の新規確認とは数えない。

ホスト側は模擬台帳であり、Apple署名検証や本番サーバーではない。ホストで券1枚を消費しても、独立したアプリ内QA券表示は1のまま。返金はホストの模擬処理で、既に渡した装備は回収していない。有料通貨の本番会計、配布後返金の運用、サーバーと端末間の原子的な決済を完成済みとは扱わない。通常ReleaseではこのQA経路を無効にする。
