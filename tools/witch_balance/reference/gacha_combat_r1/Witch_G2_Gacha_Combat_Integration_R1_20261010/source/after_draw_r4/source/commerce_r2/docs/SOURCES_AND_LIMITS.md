# 一次資料と検証境界

確認日2026-10-10。本文内の提案値はこれらの資料から引用した数値ではなく新規設計案。

## 既存のユーザー資料

- 前回 `Witch_G2_Expansion_Compatibility_R1_20261010.zip`：19論点、46模擬テスト。原本を同梱。
- `DECISION_NOTE.md`：装備ガチャ・衣装/家具への本人の希望と未承認提案。原本同梱。
- UI方向比較R2画像：左側A方向のみ本人採用。文字、通貨、右側Bや画像内の未確定造形は仕様根拠にしない。
- GitHub commit `841db876247d4e65cc898a3cc2e6713c07fcb90f` のWorldR1 `data/gear.csv` をライブ接続で読んだ。29型のメタデータは本パッケージへ手で整理した抜粋で、元CSVそのものの原本コピーではない。
- 同commitの `docs/qa/g2_refinement_20261010_r002/G2_REFINEMENT_REPORT_R003.md` §1：24キーポーズと中間動作不足。見た目を完成品や着せ替え対応と読み替えない。

## Apple

1. App Review Guidelines 3.1.1
   https://developer.apple.com/jp/app-store/review/guidelines/
   有料ランダム仮想アイテムの購入前確率表示、購入クレジット/ゲーム通貨の非失効など。新商品が審査済みという意味ではない。
2. StoreKit transaction.finish()
   https://developer.apple.com/documentation/storekit/transaction/finish()
   購入コンテンツ/サービスを渡した後に取引を完了する。今回の模擬付与はStoreKitの代替ではない。
3. Unlock in-game content with StoreKit and Background Assets (WWDC26)
   https://developer.apple.com/videos/play/wwdc2026/378/
   消耗型とcurrentEntitlementsで見る恒久権利を区別し、コンテンツのローカル利用可能性も扱う。
4. Set a price for an In-App Purchase
   https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/
   実価格はApp Store Connectで設定。今回の円価格を現行利用可能な価格点や承認価格と主張しない。

## 日本の制度

5. 消費者庁 カード合わせQ&A
   https://www.caa.go.jp/policies/policy/representation/fair_labeling/faq/card
   有料取得する特定異種アイテムの組合せと追加利益の論点。通常の装備制作・状態連携を一律に違法とはしていない。実際の入手経路・課金条件を専門家と確認する。
6. 関東財務局 前払式支払手段関係（2026-06-25更新ページ）
   https://lfb.mof.go.jp/kantou/kinyuu/pagekthp00400036.html
   自家型/第三者型、残高/手続き等。券と呼べば資金決済の確認不要になるわけではない。複数通貨を分けて残高義務を回避する案は採らない。

## 明確な未検証

実サーバー/署名/同時実行、StoreKit Sandbox、App審査、実画像/実機、アニメーション、サーバー費用、売上/需要、R6本体と恒常効果の全回帰、課金込みのゲーム進行、消費済み券の返金訂正。

本文中の「確率計算」は浮動小数の有限状態計算で、総確率誤差を検査した。5万系列は検証用擬似乱数であり、実課金や5万人の観測ではない。74テストは契約・算術の模擬検査で、全ての発売条件を満たすものではない。
