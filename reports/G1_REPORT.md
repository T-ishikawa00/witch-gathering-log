# G1完了報告 — Idle Loot RPG

2026-10-08 / G1-0.1.0 / `G1_IMPLEMENTATION_AND_TECHNICAL_VALIDATION_COMPLETE`

Macのローカルブラウザで、初回開始→ボス挑戦→比較→装備変更→再戦→放置報酬→再読込まで動作しました。人による面白さの判定は `USER_TEST_NOT_RUN` です。G2・G3には着手していません。

## 起動と操作

現在のローカルURLは [http://127.0.0.1:4173](http://127.0.0.1:4173) です。停止後の再起動はプロジェクトフォルダで `npm start`。Node.js 20以上、依存インストール不要です。

まず「探索」で崩門の番人へ挑戦してください。初期会心6点は一度だけ付与。初回勝利で毒・防御の試用12点を解放します。「装備」で各枠を選び、構成全体の差を比較して適用できます。「帰還」の8時間送りは開発用です。3ボスのクリア状況と次の目標を保存・表示します。

操作の詳細は [README](../README.md)、人間の確認項目は [HUMAN_REVIEW](HUMAN_REVIEW.md) に記載しました。

## 実装した範囲

- 整数・seedに基づく戦闘、会心・毒・ガード・反撃、1倍/2倍/省略、一時停止・中断、結果内訳と前戦比較。
- 18固定装備、6枠の自由編集、3つの保存構成、名称変更、確認付き上書き、ロックと一括選別。
- 3地域、15分工程、端数・24時間上限、地域変更前の精算、重複素材化、72枠と保留の受取・素材化、素材120の指定制作。
- IndexedDB原子的保存、世代競合の再読込、現在＋前2世代、チェックサムと読戻し、失敗時再試行、破損世代の復旧警告、非対応schemaで停止。
- 帰還・装備・探索・戦闘/結果の操作画面、時計異常の確認付き再設定、別セーブのバランス検証、ローカル観察記録。

コア計算、内容データ、保存アダプター、画面を分離しています。最終iOS方式と2D/3D方式は固定していません。

## 自動試験の実結果

|試験|結果|証拠|
|---|---|---|
|Python参照モデル|30 / 30成功|[reference-tests.txt](reference-tests.txt)|
|現行JavaScriptコア・進行・合成境界|39 / 39成功|[core-tests.tap](core-tests.tap)|
|元ゴールデン戦闘|28 / 28完全一致|[combat.test.js](../tests/combat.test.js)|
|729構成×3ボス×32seedの直接照合|69,984 / 69,984完全一致|[combat-parity.json](combat-parity.json)|
|実Chromeの保存・復旧・競合・故障注入|27 / 27成功|[storage-tests.json](storage-tests.json)|
|R3の6シナリオとUIの追加確認|51 / 51成功|[browser-tests.json](browser-tests.json)|
|復旧警告保持・保留受取・戦闘中断の追加確認|7 / 7成功|[recovery-ui-tests.json](recovery-ui-tests.json)|

ゲームからの外部HTTP要求、JavaScript例外、コンソールエラーは観測試験で0件。受取・保存失敗試験は故障注入で、実際の容量不足やOS電源断の再現ではありません。異常状態の試験には明示したfixtureを用いました。人間が遊んだ証拠には使用しません。

## 装備変更の実例

群刃の衛兵、seed1001で、毒6点は攻撃88・防御65・ガード5%、25.600秒で敗北。靴と指輪を防御へ替えると攻撃80・防御140・ガード23%、38.000秒で勝利しHP245が残りました。ボス別の勝敗フラグではなく同じ計算の結果です。

## 画面の証拠

- [帰還・デスクトップ](browser-evidence/desktop-01-return.png)
- [装備・デスクトップ](browser-evidence/desktop-02-equipment.png)
- [探索・デスクトップ](browser-evidence/desktop-03-expedition.png)
- [結果・デスクトップ](browser-evidence/desktop-04-result.png)
- [戦闘中のHP・実イベント](browser-evidence/battle-desktop.png)
- [375×667の帰還](browser-evidence/mobile-375-return.png)、[390×844の帰還](browser-evidence/mobile-390-return.png)
- [375幅の200%文字](browser-evidence/mobile-375-equipment-200pct.png)、[390幅の200%文字](browser-evidence/mobile-390-equipment-200pct.png)
- [復旧警告](browser-evidence/recovery-warning.png)、[時計異常](browser-evidence/clock-anomaly.png)

375×667と390×844で横はみ出しなし。比較の適用・取消とフォーカス復帰、Reduce Motion、文字拡大、ボタン44 CSSpx以上を確認しました。CSSpxでの検証でありiPhone実機の結果ではありません。

## 既知の制約と未完成機能

重大な未解決の戦闘・報酬重複・保護欠陥は、今回の試験範囲では確認していません。

- 最新セーブ世代が破損すると前の有効世代へ戻ります。その世代だけにあった装備変更・戦闘結果・デバッグ時間送りは失われる場合があります。復旧警告を表示します。全世代破損や非対応schemaでは上書き初期化しません。
- 別ブラウザ・端末・ポートのセーブ共有、セーブ移行、JSON再取込、クラウド復旧は未実装です。古いセーブの複製や時計改変を完全には防止しません。
- 実時間8/24/48時間の実機離席、iPhone Safari、ネイティブ復帰・電池・発熱、実transaction中のOS/プロセス強制終了、実ハードウェア容量不足は未実施です。
- 観察ログは端末内に保存し、保存できなかった操作の記録は当該セッションのメモリにも保持します。保存失敗直後に再起動すると、そのメモリ記録は失われる場合があります。
- 素材は仮表現です。本番アート・音、ランダム装備、覚醒、広告・課金、長期進行、公開版は今回の範囲外です。面白さ・長期継続・集客・売上は未検証です。

## G2前の確認

本人の初見試用で、目標が分かるか、敗北後に自発的に比較・変更・再戦するか、帰還が新しい判断につながるかを確認してください。次段階ではランダム戦利品の検証価値、iPhone技術、代表アート、長期保存、予算・正式発売範囲を人間が判断します。観察用チェックシートは [HUMAN_REVIEW](HUMAN_REVIEW.md) です。

## ソースと安全確認

ソース識別：`27e9779b4f184271075a03eec41ab70f1895e5567980b7456375c0fb4c8407fe`

正本content SHA-256：`297e97b4e619e8ea0e9b49f1a9b94544c81fee38f35b2cb2441694af5c543dd1`

参照31項目のハッシュを再照合し、変更なし。現行sourceとブラウザ報告のハッシュも一致しています。全ファイルの識別情報は [source-manifest.json](source-manifest.json)、集約状態は [G1_FINAL_STATUS.json](G1_FINAL_STATUS.json) にあります。

初期フォルダは空、Gitリポジトリなし、開始時空き527GiB。作業成果物は約6MiB。観測した作業区間は約23.8分で、将来の工数保証ではありません。開発用依存の新規導入0、commit/push0、外部デプロイ0、外部連絡・契約・支払い0です。元資料はreferenceに保全しました。G1終了時点で停止します。
