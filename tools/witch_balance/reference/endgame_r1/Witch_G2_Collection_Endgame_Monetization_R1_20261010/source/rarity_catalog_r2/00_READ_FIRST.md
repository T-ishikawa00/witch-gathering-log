# 今回は「レアリティ×購入目的」の設計候補

入口: READABLE_DESIGN.html / DESIGN_REPORT.md。
数値: data/RARITY_CANDIDATES.json。
商品: data/PRODUCT_CATALOG.json（21個の候補ID、21商品を即販売する決定ではない）。
結果: results/VALIDATION_SUMMARY.json / results/analysis/。
判断: docs/DECISION_REGISTER.md。

過去の全資料を再梱包したものではなく、今回の差分＋再現に必要な原本26ファイル。
Mac/GitHubへの保存・商品登録・課金・実装・commit/pushは一切行っていません。

再実行はPython標準ライブラリのみ。
python3 -B tools/test_model.py
python3 -B tools/run_analysis.py --output ./reruns/recheck_01
出力先は新規または空にしてください。

HTMLはレポートで、ゲームUIのデザイン案ではありません。
