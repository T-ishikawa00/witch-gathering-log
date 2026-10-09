# 外部一次資料 — 確認日2026-10-10

以下は規則/APIの確認先。設計提案の成功や個別商品の適法性を保証する資料ではない。

1. Apple, App Review Guidelines 3.1.1: 購入前のランダムアイテム確率、購入通貨の失効禁止、復元。
   https://developer.apple.com/app-store/review/guidelines/
2. Apple, In-App Purchase types: 消耗型と非消耗型の違い。
   https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-types
3. Apple, Transaction.currentEntitlements: 非消耗型等の権利。消耗型・返金/取消品はcurrentEntitlementsに含まれない。
   https://developer.apple.com/documentation/storekit/transaction/currententitlements?changes=l_1_8
4. Apple, App Store Server Notifications notificationType: REFUND / REFUND_REVERSED等。
   https://developer.apple.com/documentation/AppStoreServerNotifications/notificationType
5. Apple, Get Refund History: 返金履歴と取り逃した通知への補完。
   https://developer.apple.com/documentation/appstoreserverapi/get-refund-history
6. Apple, Set an app age rating: コンテンツとLoot Boxesを含む申告。
   https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/
7. 消費者庁「インターネット上の取引と『カード合わせ』に関するQ&A」Q10/Q16/Q21/Q26/Q27等。
   https://www.caa.go.jp/policies/policy/representation/fair_labeling/faq/card
8. 関東財務局「前払式支払手段(商品券・プリペイドカード等)関係」更新2026-06-25。
   https://lfb.mof.go.jp/kantou/kinyuu/pagekthp00400036.html
9. 北海道財務局 前払式支払手段の説明: 自家型の基準日未使用残高1,000万円超等。
   https://lfb.mof.go.jp/hokkaido/syoutori/pagehkhp015000146.html
10. 金融庁「商品券（プリペイドカード）の払戻しについて」: 利用終了時の手続。
    https://www.fsa.go.jp/policy/prepaid/

## プロジェクトの直接参照

読取commit: 841db876247d4e65cc898a3cc2e6713c07fcb90f

- 制作報告R003
  https://github.com/T-ishikawa00/witch-gathering-log/blob/841db876247d4e65cc898a3cc2e6713c07fcb90f/docs/qa/g2_refinement_20261010_r002/G2_REFINEMENT_REPORT_R003.md
- 世界R1 装備・進行
  https://github.com/T-ishikawa00/witch-gathering-log/blob/841db876247d4e65cc898a3cc2e6713c07fcb90f/docs/design/sources/world_r1/Witch_World_Design_R1_20261008/docs/03_EQUIPMENT_AND_PROGRESSION_R1.md

内容はGitHub connectorで読んだ。全原画やローカルの大容量アセットを取得・再測定したわけではない。
