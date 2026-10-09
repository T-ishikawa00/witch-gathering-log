ZIP収録範囲: Swiftソース3点、README、ビルド検証ログ、結果JSON/テキストのみ。
画像、バイナリ、build中間物、SDK、config/build.sh/Info.plistは未収録です。
以下の再現コマンドは元の隔離作業場所用であり、このZIP単独の実行手順ではありません。

G2 素材表示の隔離サンプル

これは表示検証用であり、製品エンジン、端末仕様、原点、縮尺を採用決定するものではありません。
既存ゲームを参照・変更せず、このディレクトリだけで作成しました。

ソース:
Shared/G2Scene.swift: Mac / iOS 共通の SpriteKit シーン
macOS/App.swift: Mac ウィンドウ表示と SpriteKit テクスチャ PNG キャプチャ
iOS/App.swift: UIKit + SKView 最小アプリ
Config/validation.json: 仮の 390 x 844 points、背景 aspectFill、全画像幅130 points
Config/provisional-110pt.json, provisional-150pt.json: 全画像幅比較の設定
build.sh: 導入済み Xcode の swiftc で iPhoneOS / iPhoneSimulator / macOS SDK を使用

ビルド:
zsh build.sh all
zsh build.sh ios
zsh build.sh mac

iOS は arm64 + deployment target 17.0 のコンパイル/リンクのみです。
SDKは導入済み26.5。-no_adhoc_codesign を指定し、署名アカウント/設定は使いません。
これは Xcode プロジェクト、実機向け配布パッケージ、インストールや起動の検証ではありません。
deployment target 17.0はサンプルのコンパイル設定であり、そのOS実行互換性も未検証です。

素材取得成功後に、原入力を変更せず内容が同一のコピーを assets/background.png、assets/monster.png、assets/foreground.png に配置します。
background は clean_plate_v02、foreground は foreground_v02、monster は sprite_prototype_v2 が今回の対象です。
旧 master_v01 は最終表示検証の対象外です。
表示順は background(z=0) → monster(z=10) → foreground(z=20) です。
背景プレート＋独立前景の2層試験で、5層完成背景やリアルタイム3D照明対応とは扱いません。
現時点の assets は空です。未取得素材は画面とログに PLACEHOLDER / not validated と明記します。
入力の取得失敗は上位ディレクトリの library-*-transfer-errors.txt と library-current-input-transfer-log.json に記録しています。

Mac 実行例 (sample ディレクトリから):
./build/macos/G2AssetValidation --config Config/provisional-110pt.json --assets assets --output build/mac-110pt.png
./build/macos/G2AssetValidation --config Config/provisional-150pt.json --assets assets --output build/mac-150pt.png
キャプチャは SKView.texture(from:crop:) の描画結果です。Simulator/iPhoneのスクリーンショットではありません。
現時点では上記Mac実行は未実施で、Macの画像デコード・描画を検証済みと扱いません。

座標・仮設定:
SpriteKit座標は左下原点、pointsです。
画像座標の足元候補 (830,900)、元画像1536 x 1024という提供情報から、
仮anchorPointを (830/1536, 1-900/1024) = (0.54036458,0.12109375) に設定しました。
元画像ピクセル・足元を独立確認した結果ではありません。
widthPointsは透明余白を含む全画像幅です。alpha64 bbox幅1034 pxという提供情報を使うと、
全画像幅110/150 ptに対応する主輪郭幅は約74.05/100.98 ptです。
主輪郭そのものを110/150 ptにしたい場合、全画像幅は約163.40/222.82 ptです。
魔女との相対縮尺は未確定です。

occupancyRects は未制作の4人を示す中立の検証オーバーレイです。
36 x 90 points と位置は任意の仮設定で、背景の乾いた床や人物寸法を確認した結果ではありません。
debugOverlay=falseにすると、仮原点十字、画像枠、占有矩形は表示しません。
scene自体はaspectFitでウィンドウに表示し、背景単体のaspectFill/aspectFitは別設定です。
foreground.offset は画面pointsでの相対移動、scaleMultiplier は背景と同じ描画比率からの倍率です。
初期値は(0,0)、1.0で、元PNGを加工しません。実画像による妥当性は未確認です。
playArea は「画面」canvasの上端原点で正規化した範囲です。
x=[.18,.82]、上からのy=[.50,.80]をSpriteKit座標へ変換すると、
390 x 844 pointsでは x=70.2〜319.8、下端原点y=168.8〜422.0 pointsです。
この領域は検証オーバーレイで、実画像の床分離・前景遮蔽を確認した結果ではありません。

witch_characters_R1.png の正本参照は取得失敗で実ピクセル未確認です。
crop領域は推測せず、帽子・赤スカーフ・猪の牙・ドット密度の比較は未検証です。
body_plate_v1 と foreleg_layer_v1 は必要時のみ取得する依頼のため、この段階では取得保留です。

未検証:
実画像の見た目、透明縁、真のalpha合成、alpha clip比較、Mac素材描画、Simulator起動、iPhone実機。
前景の実際のキャラ遮蔽も未検証です。暗い下端やalpha値のみで合否を判定しません。
呼吸/位置移動/前脚のメッシュ変形も未実装・未検証です。現サンプルはanimation=noneのみ。
単一画像による呼吸や移動を正式な前脚掻き、別脚原画、フルリグ、足アニメ完成とは扱いません。

4つの検証範囲:
Mac 描画: 未実施 (素材取得で停止)
iOS ビルド: iPhoneOS / iPhoneSimulator SDK の署名なしコンパイル・リンク成功
Simulator 実行: 未実施 (既報のCoreSimulator接続・権限エラー)
iPhone 実機: 未実施
