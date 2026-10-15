# Codex参照用 — 今回の実行指示ではありません

今回はレアリティと商品体系のレビュー候補。既存共有原本497549eを変更したものではありません。

最初にDESIGN_REPORT.md、docs/DECISION_REGISTER.md、data/RARITY_CANDIDATES.json、data/PRODUCT_CATALOG.jsonを読む。

H1倍率・各価格・追加商品・30日便は未承認。元のg.DATAのrarity_primary_multiplier=falseはそのまま保全し、本番へ無断で変えない。比較コードのmock.patchは独立数式プローブの便宜であり、ゲームエンジンへの実装手法ではない。

価格点は未登録。IAP商品生成、権利台帳の本番変更、Google/Apple設定変更、購入、公開は含まない。新しい衣装や家具を既存159制作単位へ加えない。

本パッケージを受け取っただけでは、import領域への保存、既存管理文書更新、Git add/commit/pushの許可になりません。Humanが別途明示した作業範囲でのみ取り込んでください。

再実行はpython3 -B tools/test_model.py、python3 -B tools/run_analysis.py --output <新規フォルダ>。過去結果は上書きしない。原本SHA一覧はdata/SOURCE_MANIFEST.json。
