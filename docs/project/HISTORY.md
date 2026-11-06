# 開発履歴とrefの対応

確認日：2026-11-07 JST。mtime・版番号だけで正本を選ばず、ソース入力のSHA-256とbuild記録を照合した。

|対象|full SHA／識別|位置づけ|
|---|---|---|
|旧main|`497549e9339431b5680eaa398fef16ff1b81f117`|G1・企画資料。iOS最新実装を含まなかった|
|R046|`1547dde77605a3e16195f892d9add20b66d5c63a`|選別した監査用snapshot|
|R088|`b312d0b559692c561783c762dfa3c2fa1ffdfc05`|後続の選別監査snapshot。開発履歴全体ではない|
|UI48 R020実装|`0318559cf8e584b56b08a201571213731f6c7879`|UI48画面統合|
|UI48 R020 checkpoint|`92f8f657ec331af51090de29684dc7d9d2b492cc`|固定buildと引継ぎ|
|本人採用の記録|`c804e61a4070cea730d28089bd36a57e9a7e36bb`|UI48採用と製品候補の方針|
|W008アプリソース|`26ab9d74e7580db00c6a08252d441908d82b7f1f`|最終作業入力261件を今回の現行入力と照合|
|W008引継ぎHEAD|`d09b7f37071c17a6cc428cc888f12eae44dc3701`|QA・文書checkpoint。W008より新しいゲームコードという意味ではない|
|W009|W008と同じ固定入力のiPhoneOS未署名build|実機インストール・本番販売の証拠ではない|
|2026-10-18容量整理|所有者のローカル保全記録|Git・ソース・原画・UI48・Humanセーブを保持し、旧出力の重複等を整理した記録|
|2026-11-07整備|`codex/git-maintenance-20261107-r1`|旧mainを親とする選別保存。元の110commitの開発履歴はローカルに保持|

[旧mainのREADME](https://github.com/T-ishikawa00/witch-gathering-log/blob/497549e9339431b5680eaa398fef16ff1b81f117/README.md)、[R046](https://github.com/T-ishikawa00/witch-gathering-log/tree/1547dde77605a3e16195f892d9add20b66d5c63a)、[R088](https://github.com/T-ishikawa00/witch-gathering-log/tree/b312d0b559692c561783c762dfa3c2fa1ffdfc05)は保存済みの過去版。UI48/W008の元110commit履歴は今回丸ごとpushしておらず、ローカルSHAをGitHubリンクとして扱わない。今回のsource receiptは[ソース台帳](evidence/SOURCE_SNAPSHOT.json)、[W008最終作業入力](../../native/ResourceManifests/W008_WORKING_SOURCE_SHA256.json)を参照。

## 2026-10-18整理後の所在

今回もR020とW008/W009の固定フォルダ、元worktree、原画・資材、保全ディレクトリの実在を確認した。旧出力は、過去の削除記録と現在の存在を分離する。

|分類|根拠・対応|
|---|---|
|現存|元repository、開発worktree、`qa_source_20261015T232901`、`qa_source_20261016T044106`、preservation配下|
|保全先あり|Human simulator-data、未コミットpatch・ファイル、旧app固有objectの保存先が現存|
|削除記録あり|旧apps、DerivedData、snapshot/QA重複の当時の削除記録。今回の削除は0件|
|復元経路の記録あり|`app-restoration-map.jsonl.gz`、`snapshot-plan.jsonl.gz`等。今回は全旧成果の復元を再実行していない|
|未確認|全旧成果の現時点の完全復元、外部媒体backup、現在の署名済み実機buildとの対応|

元worktree・保全先の絶対パスはローカル最終報告に記録する。GitHub文書には個人用の保存パス・端末ID・実セーブを転載しない。

旧PROJECT_CURRENTと設計直下の48参照を検査し、22参照はローカル専用inventory・原納品先のためmainで未解決。歴史資料を削除・修辞的に修復せず、[未収録参照台帳](evidence/HISTORICAL_LINK_LIMITS.json)へ残した。現在のREADME・新規資料の相対リンクは別に全件検査する。
