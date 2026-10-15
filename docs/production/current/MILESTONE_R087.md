# R087 ローカル統合チェックポイント

R086から、課金候補の型付きクライアント/サービス契約R461、隔離永続ストアR463、持ちものの0件案内と日本語入力解除修正R464/R465を統合。通常ゲームの資源を再制作せず、同一240入力/1922資源で両SDKをビルドし、保存を変更しない実画面回帰を行った。

- R461: Python 10 focused、Swift 37メソッド合格。合成署名の購入/抽選/返金を実オフライン検証器に通した。初回fixture/compile失敗は保全。
- R463: Swift 45メソッド合格（既存37+追加8）、別7プロセスで再起動・同時更新・返金保持・古い成功応答拒否を確認。256件は累積上限で、無制限運用や本番保持設計の証明ではない。
- R462: 両SDKビルド合格、保存/旧成果保護合格、IME表示残りは不合格のまま保全。
- R465: 両SDK274.385秒/1.442GB。検索文字/品質解除、43件復帰、未確定IME解除、再入力、冷起動43件、revision138と本体/previous一致。4PNG・222.780秒。実機・実Apple・本番課金は対象外。
- 保護: 旧15,300製品ファイル、実行時旧8ツリー7,776ファイル、元プロジェクトと継承PBXの内容を保全。追加削除・Pushなし。

[完成条件台帳R014](qa_drafts/final_acceptance_r360/COMPLETION_REGISTER_R014.json)、[ビルド結果](qa_drafts/native_completion_r465/ROOT_BUILD_RESULT_R001.json)、[実画面結果](qa_drafts/native_completion_r465/ROOT_RUNTIME_RESULT_R001.json)、[本番課金の残作業](qa_drafts/native_completion_r465/commerce_remaining_r001/REVIEW_R001.md)。固定SHA独立監査はこのチェックポイントを対象に続ける。
