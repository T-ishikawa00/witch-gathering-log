# 魔女の採集帳｜装備収集・長期やり込み・収益化 R1

今回の差分と検証原本。完成した全ゲームではない。まず READABLE_REPORT.html または DESIGN_AND_VALIDATION.md。

重要:原R6-Bが対応する基本13型だけの比較では、4戦況とも直接攻撃が最速。進化固有機能と研究課題は設計したが未実装。多様性を検証できたという報告ではない。

source/は前回ZIP内の55ファイルを同一バイトで保存。history/には前回の品質昇格・導入・経済R1 ZIPを同梱。過去全ZIPを再統合した完全保管庫ではない。新しいゲーム用画像・音・フォント・ゲーム実行ファイルはなし。QA画像はレポート表示確認用。

今回のコードはPythonとNumPy（requirements-research.txtに今回の版）。実行前に内容を確認する。標準ライブラリ以外の自動インストールはしない。Mac・GitHubへ直接保存した事実はない。

```sh
python3 -B tools/verify_bundle.py
# 再計算は新規出力先のみ（納品データを上書きしない）
python3 -B tools/run_lab.py --output ./reruns/lab01 --count 64
python3 -B tools/collection.py --output ./reruns/collection01 --samples 3000
python3 -B tools/run_starter.py --output ./reruns/starter01
```

通常のゲーム用資産・保存は変更しない。稿末のCodex範囲は草案であり、実装やGit操作の許可ではない。
