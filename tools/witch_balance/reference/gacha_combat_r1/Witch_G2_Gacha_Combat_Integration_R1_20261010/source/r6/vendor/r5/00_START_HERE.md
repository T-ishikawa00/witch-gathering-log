# 魔女の採集帳 G2-C 統合保全 R1〜R5

最初に `REPORT_R5.md` または `READABLE_REPORT.html` を読む。

これは設計と数値検証の保全用パッケージ。**Mac/GitHubへの取り込みや本番実装を自動許可しない。**

## 読む順

1. `REPORT_R5.md` — 今回の修正と実験、未解決事項。
2. `data/DESIGN_DECISIONS_R1_R5.json` — 決定済み・提案・未決の区別。
3. `data/PRIOR_DESIGN_ARCHIVE_INDEX.json` と `history/` — 過去G2-C四版の原本。
4. `results/HOLDOUT_RESULTS.json` / `HOLDOUT_SUMMARY.csv` — 同じseedでの比較。
5. `results/UPGRADE_REVERSAL_DIAGNOSIS.json` — 未解決2条件。
6. `tools/` — 参照実装。全5地域用の本番ゲームエンジンではない。

## 現在地

完全自動・作戦不要はユーザー決定。成長R2・経済R3は数値候補。R5では端数問題を直し、古樹の圧力配分候補を検証。支援AIの境界による逆転が残るため、数値一式の最終凍結はしない。

古いR1の作戦選択を現行仕様へ戻さない。旧ファイルを全件「承認済み」として取り込まない。現在のアセット制作・G1・セーブ・原画を変更しない。

## コマンド

```sh
python tools/verify_package.py
python tools/test_r5.py
python tools/run_holdout.py --output /任意の新しい空フォルダ --max-new-cells 5
```

後者は同じoutputで繰り返すと、検証済みcellを再利用して37条件まで継続する。別条件を同じフォルダへ混ぜない。結果は参照実験であり、iPhoneの動作保証ではない。

`history/` は元の4資料をそのまま保存したもの。従来の世界R1・美術R4と承認アートは、既存プロジェクトの正本を参照するため、大容量の重複は含めていない。
