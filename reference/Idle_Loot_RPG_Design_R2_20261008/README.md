# 装備ビルド特化・2D放置ハクスラRPG — コア設計 R2
2026-10-08 / R2.0-G1 / iPhone向けの限定試作仕様

**前回の市場調査を、実装可能なコア仕様へ進めた資料。完成ゲーム・市場検証済み商品ではない。**
「ふたつの街」は保留のまま。ジャンル変更や追加の新規事業提案はしない。

## 最初に開くもの
1. `01_DECISION_AND_GAME_DESIGN_R2.md`：今回決めたゲームの内容と、未決定事項。
2. `ux/UX_PREVIEW_R2.html`：4画面の操作設計プレビュー。ブラウザで開く。通信・広告・課金なし。
3. `CODEX_REQUEST_G1_R2.md`：このフォルダを添付してCodexへ渡す限定試作依頼文。

## 資料の正本・優先順位
- 内容ID・数値：`data/content.json`
- 戦闘の実行順・整数化：`validation/core.py` と `spec/02_COMBAT_AND_ITEMS_R2.md`
- 放置・装備保護の意味：`validation/progression.py` と `spec/03_OFFLINE_SAVE_ECONOMY_R2.md`
- 画面の挙動：`spec/04_UX_AND_VISUAL_GATE_R2.md`。HTMLは固定サンプルの情報設計確認用。
- 実装範囲と禁止事項：`CODEX_REQUEST_G1_R2.md`
矛盾を見つけた場合は、勝手に埋めず差分を記録して最小修正する。R1の「未決定」を本資料で試作用に具体化したが、正式製品への承認と混同しない。

## 今回実施したこと
18個の固定性能装備、6枠、3ボスを定義。729構成×3ボス×32乱数＝69,984戦を参照モデルで比較した。主要3構成は別途各300乱数、上位候補は未使用乱数で確認。戦闘・放置・保護のPythonテスト30件を実行。

**この30件はネイティブ保存・課金・広告・実機テストを含まない。** コードが通ったことを「面白い」「売れる」とは扱わない。

## 再実行
Python 3.10以上、標準ライブラリのみ。Windowsでは `python` を `py -3` に替えてよい。

```text
cd validation
python -m unittest -v test_reference
python check_balance.py
python build_report.py
```

`check_balance.py` は比較結果のCSVとJSONを書き直す。ゲームデータや外部アカウントは操作しない。
HTMLは単独ファイルでも開ける。iPhoneの添付プレビューでJavaScriptが動かない場合、PCのブラウザで開く。iPhone Safariそのものの互換性は別途確認が必要。

## 成果物の限界
実機プレイ、長期継続、人による評価、最終アート、音、iOS本体、広告SDK、StoreKit、本番売上、App Storeでの検索露出は未検証。ソース内の数値は企画仮説であり、競合データ・市場平均ではない。
支払い、契約、連絡、投稿、公開、リポジトリ変更は行っていない。実装の自律範囲はG1のローカル試作まで。
