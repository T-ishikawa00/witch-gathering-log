# 読み込み条件と検証境界

本番エンジンのインポート設定は未決定です。以下は実行済みのBlender試験値であり、本番推奨値やiPhone実機合格ではありません。

## PNG共通
元解像度・RGBAをそのまま保持。透過は元のstraight alpha、しきい値処理なし。色はsRGB画像入力、テクスチャフィルタClosest、Transparent/Emissionミックス。半透明画素は削除しない。フルキャンバス登録で原点を揃えます。アトラス余白、圧縮、mipmap、production pivot、pixel gridは未確定です。

## BG_R01_FIELD
941×1671。選定描画順はfar_v01 → back_trees_v01 → playfield_v02 → actors等（未収録）→ foreground_v02。4層manifestを参照。clean_plate_v02は静的確認用で、4層の下に重ねません。表示試験390×694、farのみ1.01倍overscan。床固定、元画像pixel単位でfar±2x/±1y、back±4x/±2y、front±8x/±4y。中立＋四隅の5位置を確認。連続動作・それ以上の移動は未検証。

## BG_R01_BOSS
941×1672。backforest → terrain_stone → actors等（未収録）→ foreground。masterは比較用、同時に下へ重ねない。独立描き起こしのためmasterを厳密再構成しません。静的合成確認はqa参照。安全な視差幅、境界overscan、4人＋ボス＋HUDは未承認です。

## 役者表示
QAの通常敵bbox幅は猪120、蜘蛛72、葉刃105、甲虫78ポイント。古樹305ポイント。いずれも390×694確認用。設定画の4人に対する最終縮尺・密度の合格を意味しません。qaの描画条件JSONを併用してください。

## 猪の可動試作
Blender 4.3.2、CPU Cycles、4 samples、768×576、24fps、120frames（5秒）。source/boar_rigで blender -b -t 4 --python build_rig.py -- --behind を実行すると背面脚版を再現します。元テクスチャは1536×1024、100pixel/unit、肩pivotは左上原点(900,540)。前脚-7〜+5度、本体X直線移動。テクスチャは.blend内包、別PNGも同梱。継ぎ目と上脚の隠れは既知制限。頭・牙の独立可動、接地維持、全状態は未実装。旧REVIEW.mdは当時の技術観察記録です。

## QA記録の参照範囲
qa/blenderには確認PNG・条件JSON・報告Markdownを収録しています。報告中に登場するQA用render_*.pyとQA専用.blendは元作業の記録で、同梱対象外です。全QA画像の一括再現をこのZIP単独で保証していません。可搬な編集・再現データとして同梱した.blend/.pyはsource/boar_rigのみです。

## 実機
qa/native_sampleは既存ネイティブ検証サンプルとログのコピー。記載された時点の状態に限定されます。Macへの今回の素材保存、実機画面表示、性能PASSを証明しません。
