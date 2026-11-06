# 再現・起動・試験

対象：W008のbyte一致ソースsnapshot。確認環境：Xcode 27.2（27B52）、Swift 6.4.2、iOS Simulator 27.2、Apple Silicon Mac。過去2026-10-18のXcode 26.6／SDK 26.5成功記録とは別の試験。

## Gitのみで実施できるCore試験

```sh
python3 tools/repository/core_tests.py --output "$HOME/witch-validation/core-001"
```

出力先は新規で、checkout外・symlinkを含まない実ディレクトリにする。scratch、ModuleCache、TMPDIRとR129／R169／R170／R179／R181／R342試験出力を分離する。R179 fixtureはSHA固定。R159・R179は生成された試験データ、R227はengine QA候補fixtureで、実ユーザーのセーブではない。長期経済・購入host fixture等のopt-in試験は必要入力なしに有効化せず、skipを記録する。

裸の`swift test`だけでは専用出力やfixture指定が不足し、保存試験が失敗する。ゲームコードを緩めて通さず、このwrapperを使う。既存Humanのセーブをfixtureに指定しない。

## iOSアプリに必要な別資材

資材ID：`W008_PREPARED_RESOURCES_20261016T044106`。1,923ファイル、365,929,993 bytes。[manifest](../../native/ResourceManifests/W008_RESOURCE_SHA256.json)とすべてのパス・SHA-256が一致する既存所有者の`PreparedResources`フォルダを使う。画像・アニメーション・音・catalog・privacy・コンパイル済Assets.carを含む。フォントファイルは検出していない。

取得元は所有者の元開発worktreeに保持した固定資材。公開download先は設けていない。所有者が共有権限を確認して提供する必要があり、GitHub cloneだけでは取得できない。破損・欠損時に別の候補素材を自動選択しない。全量の再生成・外部媒体backupは未検証。取得後の配置先を`WITCH_RESOURCE_ROOT`とし、原本を出力先にしない。

```sh
export WITCH_RESOURCE_ROOT="/absolute/path/to/PreparedResources"
python3 tools/repository/copy_resources.py \
  --source "$WITCH_RESOURCE_ROOT" \
  --manifest native/ResourceManifests/W008_RESOURCE_SHA256.json
python3 tools/repository/reproduce.py \
  --resources "$WITCH_RESOURCE_ROOT" \
  --output "$HOME/witch-validation/simulator-001"
```

資材検証後に、専用DerivedDataへRelease／`build-for-testing`を行う。外部Swift packageやPillowはこの凍結pack経路では不要。全ファイルの一致を確認し、コピー後もhashを検査する。ゲームコードの再生成や元フォルダへの書戻しは行わない。

固定コンパイル条件は`STANDARD_PLAY_R169 FIRST_CRAFT_AID_R179 EQUIPMENT_LOADOUTS_R342 NATURAL_GEAR_R350 NATURAL_GEAR_REFINEMENT_R352 GEAR_DISMANTLE_REFUND_R353`。元製品候補の条件を維持している。通常プレイにQA引数を付けない。

## XcodeとSimulator

Xcodeで開く場合は`native/WitchReproduction.xcodeproj`、scheme `WitchGathering`、Releaseを使う。build setting `WITCH_RESOURCE_ROOT`を所有者のpackに設定する。今回の再現用Bundle IDは`local.witch.repository.reproduction`。Teamは空、署名なし。元の`WitchGathering.xcodeproj`や`WitchProductCandidate_R1.xcodeproj`は変更・置換していない。

既存のHuman用Simulatorを選ばず、新規専用Simulatorで試験する。UIスモークwrapperは新しいiPhone17eだけを作成し、試験ごとに独立したUUIDのQAセーブを使う。作成した端末は終了後shutdownし、削除しない。

```sh
python3 tools/repository/simulator_smoke.py \
  --build-root "$HOME/witch-validation/simulator-001" \
  --output "$HOME/witch-validation/ui-001" \
  --runtime com.apple.CoreSimulator.SimRuntime.iOS-27-2
```

runtime名は`xcrun simctl list runtimes`で確認し、インストール済みのものを指定する。新たなruntime取得や既存端末初期化は行わない。7件の対象はwrapperに固定している。保存故障UIのhost-prepared fixture試験や全48画面網羅はこのスモークに含まない。

## iPhoneOS compileと実機

```sh
python3 tools/repository/reproduce.py \
  --resources "$WITCH_RESOURCE_ROOT" \
  --output "$HOME/witch-validation/iphoneos-001" \
  --sdk iphoneos
```

これは署名なしcompileだけ。実機へのインストール、起動、性能・熱・長時間動作、Apple認証、Sandbox購入、本番IAPの確認ではない。元のDeveloper Team・署名・実機接続設定は所有者が維持する。今回の再現用projectを既存実機projectへ機械的に反映しない。

## 検証水準

CoreはGit取得物で試験できる。アプリはGit＋所有者の固定資材パックでの隔離再現。[実測結果](VALIDATION.md)で成功・失敗・skip・未実施を区別する。旧G1のNode/browser試験はiOSの再現根拠にしない。新しい依存導入・署名・実セーブ復元はこの手順に含めない。

## 旧UI試験の扱い

`LargeTextRemainingCompanionsR265Tests`、`LargeTextCompanionReachabilityR233Tests`、`LargeTextContextDiagnosticR247Tests`は旧Bundle ID `local.witch.autonomous.r1`を固定参照する歴史的試験。W008の原ソースとして保持しているが、今回の再現用appへそのまま適用できない。全UI test一括実行や既存SimulatorでのXcode Testは行わず、対象7件を明示した専用wrapperを使う。host故障fixture等の未準備試験も含むため、全UI試験合格とはしていない。将来の移植は別の検証変更として扱う。
