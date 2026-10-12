# StoreKit 調査の現在地

2026-10-11 00:52 JST 記録再照合。Xcode購入QAは2026-10-10のローカル模擬取引、最終R002追記は13:45。クラッシュ修正済み。本番課金は未完成。macOSセキュリティ設定・SIP・Apple Accountの実認証は変更・実行していない。

## nil クラッシュ（実装不備）

4件のDiagnosticReports（11:54:54、11:56:30、11:58:10、12:00:23）を直接確認した。共通エラーは `EXC_BREAKPOINT (SIGTRAP)`、termination `Trace/BPT trap: 5`、Swiftランタイム `Unexpectedly found nil while unwrapping an Optional value`。発生箇所は `ProbeApp.swift:36 / ProbeView.buy(_:)`。

当該ビルドの式 `try await Product.products(for: [id]).first!` において、商品配列が空で `.first` がnilになった。商品取得の失敗状態を購入ボタン側が強制アンラップしたことが直接原因。4件とも実行バイナリUUID `9F9ABBA4-E0D1-3A35-B60D-F034612C80AC`（11:54:11ビルド）であり、修正後ソースではなく同じ旧インストールバイナリの再起動も確認した。

商品取得を配列としてawaitし、`guard let`で空配列を購入不可として返すよう修正。新しい検証用bundle IDで旧runner混入を分離し、`products=0`で購入ボタンを押しても生存しunavailable表示になるUI回帰テストが6.053秒でPASS。これはクラッシュ回避の証拠であり、購入成功の証拠とは別。

## 商品取得とテスト設定（直接Run経路）

XcodeのRun executableがNone、StoreKit Configurationの参照先が存在しないworkspace下のファイル、使用中のbuild configurationが旧bundle IDという問題を確認。実在する `Products.storekit` と実行アプリ、有効な設定を選び直した。通常のXcode Runでは商品2件を取得し、購入シートにEnvironment: Xcodeが表示された。

この設定不備は直接Runの空配列に対する証拠がある。設定が不完全でも購入処理がクラッシュしてよいわけではなく、nil対策は独立して維持する。

## 以前の権限エラー（別経路・原因未確定）

hostless/hosted macOS XCTest、およびhostless iOS XCTestの `SKTestSession` 制御で次を確認した。

```text
[SKTestSession] Error saving configuration file: Error Domain=SKInternalErrorDomain Code=3 "(null)"
[SKTestSession] Error setting value to 1 for identifier 2 for com.apple.dt.xctest.tool: Error Domain=SKInternalErrorDomain Code=3 "(null)"
[SKTestSession] Error setting storefront to JPN for com.apple.dt.xctest.tool: Error Domain=SKInternalErrorDomain Code=3 "(null)"
[SKTestSession] Error deleting all transactions: Error Domain=SKInternalErrorDomain Code=3 "(null)"
Failed to purchase local.witch.test.ticket in off-device buy mode: リクエストを完了できません。
failed: caught error: "notEntitled"
```

2026-10-10に専用iOS Simulator上で、`TEST_HOST`/`BUNDLE_LOADER`を備えたアプリホスト付きiOS XCTestを実行した。ホストアプリの識別子 `local.witch.storekit.hostedqa` がログに現れたが、取引生成前に同じ `SKInternalErrorDomain Code=3` と `StoreKit.StoreKitError.notEntitled` で失敗した。さらに、公式初期化形に合わせて設定ファイルをホストアプリbundleのResourcesへ含め、`SKTestSession(configurationFileNamed:)`で1件追試したが同じ結果だった。したがって、原因をhostless runnerの `com.apple.dt.xctest.tool` identityや、設定ファイルがテストbundle内だった点だけには限定できない。原因自体はUNKNOWNで、OSセキュリティ設定変更やApple Account認証が必要とは示されていない。詳細、コマンド、ソース/configハッシュ、結果バンドルは [app-hosted試験記録](../../../../native/StoreKitLocalQA/HostedIOS/RESULT.md)。

発生箇所はテストの `makeSession()` の設定操作、その後の `buyProduct`（非消費型テスト19行、消費型31行）。取引ID生成前の失敗。host付きmacOS、iOS Simulator、設定ファイル参照修正を試したが、SKTestSession経路のCode 3は未解決。runnerがローカルStoreKit制御環境に接続していない可能性は仮説である。nilクラッシュとの因果関係は確認していない。セキュリティ設定変更やApple認証を必要条件とする証拠もない。

## 検証の区別

| 項目 | ローカルProbe / Bridge | ゲーム本体 |
|---|---|---|
| 空商品・取得エラー | 空商品UI回帰PASS、例外はmock PASS | 空商品・Xcode Network Error (-1009) とも実UI PASS |
| 購入成功 | Xcode非消費型/消費型を確認 | Xcode取引6/7を分離QAセーブに保存 |
| キャンセル | Xcodeシートからcancel確認 | Xcode実シートからcancel PASS |
| 保留 | Ask to Buy pending/declined確認 | pending未付与→Approveで1回付与、Decline未付与 PASS |
| 復元 | Xcode模擬認証、消費型除外 | 非消費型復元、消費型再付与なしを確認 |
| 重複 | 同じ取引の重複で1記録 | sinkの同時重複・再読込回帰PASS。実コールバック再送の断定はしない |
| 返金 | updates経由で権利除去 | 取引6返金で権利・机表示を除去 |
| 保存失敗 | Code640注入で未保存・未finish確認 | 実シート成功ID8→Code640、保存不変・未finish PASS |
| 再起動・未完了再配信 | XcodeRun時にcontainer/取引履歴変化。再配信はUNKNOWN | 同一バイナリ/コンテナ＋QA引数でID8を未完了再配信から回復。2回目再起動でbyte不変 PASS |

本体のQA取引は通常の無料券・模擬課金・家具所有から分離している。Sandbox/本番取引をこのbridgeで受け付けず、正式な有料ガチャへ接続していない。

詳細な試行、フルログ、xcresult、修正ソースは [履歴](../../../../native/StoreKitLocalQA/RESULT.md)、本体証拠は [STOREKIT_MAINAPP_XCODE_RESULT_R001.md](STOREKIT_MAINAPP_XCODE_RESULT_R001.md)。本番商品、サーバーの信頼境界、Apple Developer/Sandbox、実機、販売仕様・法務確認は別途必要。現時点でHumanにOS権限変更やSIP無効化を依頼する理由はない。

追加試験と前後hash: [R002](STOREKIT_MAINAPP_XCODE_RESULT_R002.md)。保留承認後の表示更新もID12で再検証PASS。QA家具所有・家への描画・同一再起動保存不変を追加確認。


## 2026-10-11 03:12 JST 追加: Simulator runtimeの既知不具合候補

AppleのiOS26.6リリースノートに、SKTestSessionのSimulatorテスト環境接続不良を修正した旨（174738526 / FB22500243）がある。現MacはXcode26.6だがruntimeはiOS26.5のみ。iOS26.6のarm64/universal取得を公式CLIで試し、両方「利用不可」exit70。比較環境未入手のため同一原因とは断定しない。nilクラッシュとの因果は依然未証明、macOS側失敗の原因もこの情報だけでは確定しない。認証・OS設定/SIP・既存Simulatorの変更なし。詳細/公式リンク/環境JSON/全文ログは[プラットフォーム調査R003](storekit_platform_research_r003/PLATFORM_CAUSE_RESEARCH_R003.md)。
