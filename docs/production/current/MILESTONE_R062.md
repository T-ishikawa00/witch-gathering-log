# R062 — 容量復旧の実内容監査と保存方式

R061を保全し、R184の読み取り専用追加監査、Human承認前の段階整理計画、独立レビュー、50GB再開ガードを保存する。原本・編集元・ソース・全save・Git・固有QA・Codex会話を保持。新規削除、外部Push、実課金、大容量build/生成なし。

追加cache90葉中B88=13.69GB/C2=0.18GB。非R163旧Intermediates119根9.65GBは条件付き。実内容照合307束549,596files、総101.28GB、同一内容98.46GBを確認し別担当が算術/6sample再hash一致。APFS実回収は未測定。22根構造不明・10未測定bundleを明示。Dead134.30GB/972項目は保留、28device available/削除対象0。

現在空き約12.1GBで50GB未達。共有保管方式は未実装で、署名/metadata/絶対path/全save復元の限定試作と独立照合、Human承認、実空き測定が必要。境界の純粋Python test1件/10条件のみPASS。R183ゲーム12test・nativeは未実行。旧runnerのguard hashは今回変更でfailclosedとなる。

失敗/訂正も保持：cacheROOT誤り、candidate索引R001のR163混入、contentR001空集合、contentR003重複読取りの停止、196/195のpath階層差、初期metadata枠9秒超過。採用版を00_READMEに明示。③〜⑤は未完、品質/範囲を縮小しない。
