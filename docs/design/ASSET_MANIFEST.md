# ファイル・アセット台帳

更新日: 2026-10-09

指定10ファイル、Downloads内の関連75ファイル、既存資料、回収したDots納品を保存・照合した。研究R1とDotsの12ZIPは過去のSHA-256記録とも一致する。既存ファイルを移動・削除せず、重複はバイト単位で記録した。

## 全件台帳

|台帳|内容|
|---|---|
|[FILE_MANIFEST.json](inventory/FILE_MANIFEST.json)|全ローカルファイルのファイル名、絶対保存先、相対保存先、サイズ、SHA-256、分類、出所|
|[EXTERNAL_SOURCE_MAP.json](inventory/EXTERNAL_SOURCE_MAP.json)|Downloadsの75原ファイル名と、ハッシュで一致する保存先。「(1)」や別名も個別に記録|
|[REQUESTED_FILES.json](inventory/REQUESTED_FILES.json)|今回指定10ファイルの原名・保存先・SHA-256|
|[COPY_READBACK.json](inventory/COPY_READBACK.json)|コピーした全ファイルとZIP各メンバーの出所・元hash・保存hash・読み戻し|
|[DUPLICATES.json](inventory/DUPLICATES.json)|同じSHA-256を持つ既存ファイル、保存コピー、外部原本|
|[ZIP_VERIFICATION.json](inventory/ZIP_VERIFICATION.json)|ZIP実読CRC、内部マニフェスト、Dots過去受領記録との照合|
|[MISSING_FILES.json](inventory/MISSING_FILES.json)|実名がある同梱対象外6ファイルと、名称未定の未納品範囲|
|[INTEGRATION_VERIFICATION.json](inventory/INTEGRATION_VERIFICATION.json)|既存保護、実読、画像・文書形式、リンクの検査結果|
|[SHA256SUMS.txt](inventory/SHA256SUMS.txt)|全保存ファイルと管理文書の最終ハッシュ。パスはプロジェクトルートからの相対パス|

FILE_MANIFESTは自分自身・最終検証JSON・チェックサムファイルを除外して循環を避ける。それらのうちFILE_MANIFESTと検証JSONはSHA256SUMSで検査する。SHA256SUMS自身は自己参照のため除外する。設計原本、コピー、管理文書5点はいずれもハッシュ対象。OSの.DS_Storeと並行更新中のnative_render原フォルダは観測時点のhashをFILE_MANIFESTに記録し、固定チェックサムから除外する。native_renderの保存文書コピーは固定チェックサムに含める。

## 最上位ビジュアル

`visual/witch_characters_R1.png`（3,114,648 bytes）のSHA-256:

`c20e010feec532d3fba9bc33a2a9e4bc54fae67aa4b5ffc7554e6ab884537601`

指定「(1)」PNGと通常名PNG、4つの設計パッケージ内の承認画像が一致する。補助設定画は `visual/supporting/`、地域ボード等は `visual/reference_only/`。承認済みの範囲を拡張していない。

## 原ZIPの保存先とSHA-256

|原ファイル名|保存先（プロジェクトルート基準）|SHA-256|
|---|---|---|
|`Idle_Loot_RPG_Research_R1_20261008.zip`|`docs/design/archive/source_zips/Idle_Loot_RPG_Research_R1_20261008.zip`|`4c4562e28e442e7f8e3fe4fbbf13b99bf708f2d69b6a5637f9232f2e80b49bee`|
|`Idle_Loot_RPG_G1_R3_Ready_for_Codex_20261008.zip`|`docs/design/archive/source_zips/Idle_Loot_RPG_G1_R3_Ready_for_Codex_20261008.zip`|`a5c26e98a7e09abed9c13b84d7de5188aad82c979dd3f655ea232ac7073449c6`|
|`Witch_World_Design_R1_20261008.zip`|`docs/design/archive/source_zips/Witch_World_Design_R1_20261008.zip`|`ffeadcb5bc17244ea7487e204fa5b91a4ffc5a4e2930f1d9110a6ca37b64f294`|
|`Witch_Forest_G2_R2_20261009.zip`|`docs/design/archive/source_zips/Witch_Forest_G2_R2_20261009.zip`|`086ac9a5829341c282eeb8c0c48158dd126a05dab6f172768e9296f7e30669f4`|
|`Witch_Forest_Individual_Visual_Review_R3_20261009.zip`|`docs/design/archive/source_zips/Witch_Forest_Individual_Visual_Review_R3_20261009.zip`|`be723f57f76139dad63fb2b8aabbb4eb2389708f38505592427d72c70056707f`|
|`Witch_AllRegions_ArtSpec_R4_20261009.zip`|`docs/design/archive/source_zips/Witch_AllRegions_ArtSpec_R4_20261009.zip`|`567c081fa18d10a7a3918060253460eb3f916765662a5433812df5142bf93f21`|
|`Witch_G2_R01_02_Boss_Background.zip`|`assets/g2/archive/source_zips/20261009/Witch_G2_R01_02_Boss_Background.zip`|`97b58c8749d2278b4489bfefdf1b243b96d0c16e4fe1519e5930ae87f1785b17`|
|`Witch_G2_R01_Small_01_Field_Background.zip`|`assets/g2/archive/source_zips/20261009/Witch_G2_R01_Small_01_Field_Background.zip`|`d97584502971e3cad150979756fc7ef974ee4b6bb30807691bb0ff85589b4358`|
|`Witch_G2_R01_Small_02_Field_Background.zip`|`assets/g2/archive/source_zips/20261009/Witch_G2_R01_Small_02_Field_Background.zip`|`fac2982a6046a8d00873960bd1e7400d77a20003fa59b4783f8ba2088d6790ce`|
|`Witch_G2_R01_Small_03_Actors_Items.zip`|`assets/g2/archive/source_zips/20261009/Witch_G2_R01_Small_03_Actors_Items.zip`|`ebecfcde3938bde5ad52ba139427ca480f8ce603f0f81bf94d6f30b440d95d80`|
|`Witch_G2_R01_Small_04_Actors_Items.zip`|`assets/g2/archive/source_zips/20261009/Witch_G2_R01_Small_04_Actors_Items.zip`|`dfd5178f6fa54404336a95f42ea2cdf6d556a1640f9952707bdba91e46d8a3b9`|
|`Witch_G2_R01_Small_05_Actors_Items.zip`|`assets/g2/archive/source_zips/20261009/Witch_G2_R01_Small_05_Actors_Items.zip`|`d2aaf81fafc721b8bae97db4b8308cc4c969a6d3424699219280032c86b87da9`|
|`Witch_G2_R01_Small_06_Rig_QA_Docs.zip`|`assets/g2/archive/source_zips/20261009/Witch_G2_R01_Small_06_Rig_QA_Docs.zip`|`8a6234d69bb8471a08f31a2b64be6c84b51f53e2a4f77702cbc7c5e98a14dfee`|
|`Witch_G2_R01_Small_07_Rig_QA_Docs.zip`|`assets/g2/archive/source_zips/20261009/Witch_G2_R01_Small_07_Rig_QA_Docs.zip`|`d9dd42a516160000dcd55be679605b85d0b2fcad3dfb33f8f05478162d1219e4`|
|`Witch_G2_R01_Small_08_Rig_QA_Docs.zip`|`assets/g2/archive/source_zips/20261009/Witch_G2_R01_Small_08_Rig_QA_Docs.zip`|`14c8c52617cc98fd7111a0ad19191af43cb597a1732b73f55745ce695706eba5`|
|`Witch_G2_R01_Small_09_Archive.zip`|`assets/g2/archive/source_zips/20261009/Witch_G2_R01_Small_09_Archive.zip`|`0b2ac94401ffd22ddcde26f6e7263c2a18245d5a6bf6dd7b3bf437882a9e6c2a`|
|`Witch_G2_R01_Small_10_Archive.zip`|`assets/g2/archive/source_zips/20261009/Witch_G2_R01_Small_10_Archive.zip`|`36297268c6ed31b2a646ee550a2760bf56001af4f6b01a0cb23edf6873ff6386`|
|`Witch_G2_R01_Small_11_Archive.zip`|`assets/g2/archive/source_zips/20261009/Witch_G2_R01_Small_11_Archive.zip`|`b0d0e3518956b15618f57f85da917b7bcce66b2c6553c7308f78a47d0c1f48af`|

同じSHA-256の「(1)」付きZIPは上表の保存先に対応付けた。原名はEXTERNAL_SOURCE_MAPに保持し、Downloads側の原本を削除していない。

## Dots納品と旧版の保全

`assets/g2/regions/region01_forest/imports/20261009_R01_delivery/R01_PACKAGE/` に107メンバーを元のパス構造で保存した。ZIP間の完全パス・大文字小文字／Unicode正規化後の衝突は0件。異なるフォルダにある同名READMEやApp.swiftを統合・上書きしない。

Dots内部SHA256SUMSの103項目も照合した。107メンバーには元のメタデータと分割ZIPのREADMEが含まれるため、103をゲーム画像数として数えない。旧版は元の `archive/not_selected/` と原ZIPの両方で保管する。

## PDFの版差

|版|保存先|SHA-256|
|---|---|---|
|Downloads版|`docs/design/archive/dots_reports/downloads_version/witch_g2_r01_validation.pdf`|`6487a461520bcbce16bad26611035ac7d6987e12a7c53a1c63f90fd36fe29fd8`|
|納品ZIP内版|`docs/design/archive/dots_reports/package_snapshot/docs/witch_g2_r01_validation.pdf`|`41ba8f7992f10753768fc8db17af3d0da99bacb05af184aa563ccbd3f0e57688`|

## 整理中に追加された保存・検証ファイル

別処理で追加されたDotsの `deliveries/20261008T182055Z_a2250721/R01_PACKAGE` は、今回の `imports/20261009_R01_delivery/R01_PACKAGE` と107メンバーすべてが一致する。原ZIP12本も各保存先で一致する。どちらも移動・削除せず、重複として登録した。

[CONCURRENT_G2_SNAPSHOT.json](inventory/CONCURRENT_G2_SNAPSHOT.json) は整理開始後に観測した追加ファイルと、その時点のSHA-256を記録する。保存レシートやMac検証記録の文書は `archive/dots_reports/concurrent_save_and_QA_snapshot/` にもコピーした。これは本統合作業が新しいゲームコードを作成・実行したという記録ではない。

[OBSERVED_NATIVE_RENDER.json](inventory/OBSERVED_NATIVE_RENDER.json) でMac SpriteKit静止画9件の結果レシートと画像ハッシュを照合した。Mac静止画の存在と、完全アニメーション・Simulator・実機合格は別である。

既存のG1ソース、reference、reports、G2の旧ファイルは統合前171ファイルのベースラインで保護した。ブラウザのセーブ領域は起動・書き込み・移行を行っていない。今回は資料と保存ファイルの検証であり、本統合がゲーム実行や実機品質の再検証を行ったものではない。
