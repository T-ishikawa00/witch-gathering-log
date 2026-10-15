# 魔女の採集帳｜装備ガチャの再調査 R3

まず `READABLE_REVIEW.html` を読んでください。これはレビュー資料であり、ホーム画面の新デザインでも、Codexへの実装許可でもありません。

前回の希少以上限定案を保存したまま、他の放置ゲームの公式資料と、価格/回数/低品質の価値を比較しました。コモン入り中頻度を次の試遊候補に置きます。確率・価格・無料供給・分解量は未承認です。

## 内容
- `RESEARCH_REVIEW_R3.md` / `READABLE_REVIEW.html`: 調査、評価、提案、残件。
- `data/SOURCES.json`: 公式資料、版、取得方法、主張できない範囲。
- `data/CANDIDATES_R3.json`: A旧R2、B回数のみ対照、C試遊候補。
- `results/ANALYSIS_R3.json` / `COST_COMPARISON.csv`: 条件・分布・費用・低レア分解の感度。
- `tools/compare_gacha.py` / `test_compare.py`: 標準ライブラリだけで再現可能な比較。
- `source/COMMERCE_R2_ORIGINAL.zip`: 直前Commerce R2を原本のまま保全。未取得の旧戦闘R1〜R6を全部収録したという意味ではありません。

## 再実行
コードを確認してから、展開したフォルダ内で実行します。Python 3.10以降の構文を使用し、今回の検査環境は別JSONに記録しています。

```sh
python3 -B tools/test_compare.py
python3 -B tools/compare_gacha.py --output ./rerun_results/check_01
```

結果のあるフォルダを再実行先にすると上書きせず停止します。定数・確率分布は再現できますが、競合の現行排出率や本作の面白さを検証するものではありません。

30の新テストと旧74テスト、抽選待ち回数6万系列の照合を実施。実課金・実機・戦闘・制作/経済全体は未検証。

作成2026-10-10。Mac、GitHub、Codexへ保存/更新/送信していません。外部への連絡・購入・公開なし。確認した公開資料のURLはSOURCESへ保持。
