# Mac保存検証追補 — R01

保存確認日時（UTC）: 2026-10-08T18:20:56.597040+00:00

ローカルDownloadsに置き直された元ZIPを読み取り、同じ処理でコピーとSHA-256照合を行い、安定したコピーから統合展開しました。Library HTTP403が復旧したとは扱いません。

- 統一地域: /Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/regions/region01_forest
- 保存済みZIP: 12点 / 78584084 bytes
- 展開実体: /Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/regions/region01_forest/deliveries/20261008T182055Z_a2250721/R01_PACKAGE
- 元106ファイル＋説明TXT1点 = 107ファイル / 80236802 bytes
- ZIP CRC・パストラバーサル・symlink・名前衝突検査: 合格
- FILE_LIST.csv: 103件のサイズ・SHA-256一致
- SHA256SUMS.txt: 103件一致。監査メタ3件と追加TXTは元一覧の対象外で、別途全107件の読戻しハッシュを記録
- PNG: 46点すべてImageIOデコードとCoreGraphicsメモリ描画に成功
- 背景2系統、通常敵4体、ボス2体、アイコン6点、猪編集用rig・動画・QA・報告を実在確認

元ZIP・元資料・既存G1・既存設計・セーブ・先行生成成果は移動、削除、上書きしていません。原PNGの画素、原ファイル名、原PDF/READMEの内容は保持しています。原文の「Mac PNG未保存」「HTTP403」は作成時点の記録です。現在の保存証拠はSAVE_MANIFEST.json、PNG_READABILITY.json、SOURCE_NAME_TO_STABLE_ID.jsonです。

原名はstable asset_idへmappingで関連付けています。背景はBG_R01_FIELD/BOSSのkitへ帰属し、独立layer IDを新造していません。

これは保存・読戻し・画像デコードの検証です。SpriteKit合成品質、脚アニメーション完成、Simulator実行、iPhone実機性能は未検証です。画像や編集用rigの存在をゲーム組み込み・完成アニメーションの合格に拡張しません。R4設計58ファイルの原本は別のdesign保存先に保持しています。
