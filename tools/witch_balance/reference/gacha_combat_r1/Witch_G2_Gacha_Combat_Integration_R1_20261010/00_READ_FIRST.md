# 魔女の採集帳 — ガチャと成長・戦闘の接続検証 R1

2026-10-10。**新しい統合検証のR1**であり、旧戦闘R1やガチャ構想R1の置換ではありません。

入口は `READABLE_REPORT.html` または `REPORT.md`。

## 要点

成長R2・経済R3・支援AI R6-Bの元コードをそのまま使い、ガチャCを原装備個体へ変換して戦闘させました。
29型と猫4型、副効果AF_BARRIER/AF_WARDの対応を、原本変更ではなく検証用bridgeへ分離しています。
9ファイルはGitHubの固定commitとバイト対応を確認し、原本369ファイルは保全しました。

C案は実際の能力値と初回森の戦闘へ効果を持ちました。一方で、空き部位を埋める効果が大きく、初回ガチャ解放タイミングの判断が必要です。
潜在副効果を含めると、同じ見た目の低レアが将来も完全な重複とは限りません。分解の安全性と将来の最適性を分けています。

## 収録

- `data/SOURCE_AND_MAPPING_AUDIT.json`：固定commit、原本対応、29＋4型・副効果の整理。
- `data/EXPERIMENT_PLAN.json`：実行前に固定した比較条件。
- `results/VALIDATION_SUMMARY.json`：結果と境界。
- `results/main/EXPERIMENT_RESULTS.json`：主比較7,680戦の集計。
- `results/main/BATTLE_ROWS.csv`：各参照戦闘の結果。
- `results/main/SCENARIOS_AND_DRAWS.jsonl.gz`：初期所持品、開封、保護、分解、装備、強化のスナップショット。
- `results/POST_ANALYSIS.json`：品質別の実装備数、強化前後、時間差、潜在枠差。
- `results/POSTHOC_ALL_COMMON_DIAGNOSTIC.json`：同じC50型を全て普通にした事後診断192戦。販売候補ではない。
- `source/`：提供された2つのZIPからの参照原本コピー。
- `tools/`：新しい接続・検証コード。旧コードは変更しない。

## 再確認

Python標準ライブラリで計算します。内容を確認してから実行してください。

```sh
python3 -B tools/verify_package.py
python3 -B -m unittest discover -s tools -p 'test_bridge.py' -v
# 数分程度の再計算。新しい空の出力先を指定し、納品resultsを上書きしない
python3 -B tools/run_experiments.py --output ./reruns/main_01
```

主比較の壁時計時間はこの環境で約198秒。Macの所要時間の保証ではありません。

## 対象外

正式な装備ID移行・猫装備採用、ゲーム本体/iOS統合、課金、実保存DB、30/90日の攻略予測、全地域の進化武器/覚醒、UIの最終デザイン、購入意欲/実ユーザーテスト。

R6の既知の強化逆転6/2,000は未解決のまま。本試験内の逆転0を一般的な修正証明にしないでください。

Mac・GitHubへ保存・pushした事実はありません。Codexへ渡しただけで実装/Git操作を許可しません。
