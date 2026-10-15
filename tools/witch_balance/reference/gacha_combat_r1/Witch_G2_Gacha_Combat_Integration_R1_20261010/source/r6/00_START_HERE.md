# 魔女の採集帳 G2-C — 支援AI再検証 R6 / R1〜R6保全パッケージ

検証日: 2026-10-10 JST。今回の実行範囲は、このチャットの作業領域にある参照モデルのみ。
Macの idle-loot-rpg、GitHub、Codexの美術制作は変更していない。

## 最初に読む

1. `READABLE_REPORT.html` または `REPORT_R6.md` — 結果と限界。
2. `results/VALIDATION_SUMMARY_R6.json` — R6-A/R6-B全条件、未解決、原本保全。
3. `docs/DECISIONS_R1_R6.json` — ユーザー確定、試験候補、未解決を分離。
4. `data/EXPERIMENT_LOCK_R6B.json` — 最終候補の固定時点・未使用seedの試験計画。
5. `handoff/DEFERRED_CODEX_IMPORT.md` — 後日の保存・再現用。自動的な実行許可ではない。

## 読み違えないこと

- 採用候補はR6-B。入口は `tools/selected_final.py` の `FinalBattleR6`。
- R6-Aは比較・副作用検出用に保持。`tools/selected_model.py` はR6-Aであり最終候補ではない。
- `support_ai.py` の比較用パラメータをプレイヤー向け設定として実装しない。
- 既知2条件は解消したが、一般の強化逆転はOPEN。未使用seedの主比較2,000組で6組残存。
- 4人の全機能、全5地域、覚醒・進化武器、実機、実DB、課金、長期継続は未検証。
- 最初の森で得られない装備や素材を与えて勝率を作っていない。数値と経済はR5入力のまま。

## 実行

Python 3.10以上・標準ライブラリだけで数値モデル／テストを実行できる。
HTMLを再生成する工程だけ `markdown-it-py` を使用。既製HTMLを閲覧するだけなら不要。

```sh
python tools/test_final_r6b.py
python tools/test_r6.py
python tools/reproduce_smoke.py --output /tmp/witch-r6-recheck
python tools/run_validation_b.py --job holdout_protect6 --output /tmp/witch-r6-full-recheck
```

再実行先は新しいフォルダを使用。配布済み`results/`や`vendor/`は書き換えない。
`run_validation_b.py` は入力・コード・計画の指紋を照合して同じチェックポイントを再利用する。
同じ結果フォルダを指定しただけでは再計算したことにならないため、独立再現は新しい出力先を使う。

## 過去の全設計

`history/Witch_G2C_Design_Consolidated_R1_R5_20261009.zip` は前回の統合原ZIPと同じバイト列。
その中に戦闘R1、成長R2、経済R3、攻略接続R4、調整R5と検証コード・結果が含まれる。
`vendor/r5/` はその展開コピーで、132原ファイルのハッシュ一致を検査済み。
世界R1・美術R4の別大型アセットは再複製していない。Mac側に統合済みの正本を優先して参照する。
