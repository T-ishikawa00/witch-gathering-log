# 既存GitHub参照の制限

今回の新規共有ファイル内の相対リンクは、既存GitHubの固定commitと新規追加対象の和集合で検証する。実同期は未実施である。
既存GitHub文書内には、過去に同期されなかったローカル監査台帳、R01納品README、旧G1補助ファイル等へのリンク切れが19箇所ある。今回の追加で生じたものではなく、既存文書を変更せず記録した。世界・装備・地域・人物の主要原本は既存GitHubに存在する。
下表の文字列は欠落先の識別子であり、クリックできる共有原本ではない。原本ZIP自体の未回収とは[欠落原本](MISSING_ORIGINALS.md)で区別する。

|既存文書|既存GitHubにない参照先|
|---|---|
|`docs/design/ASSET_MANIFEST.md`|`docs/design/inventory/FILE_MANIFEST.json`|
|`docs/design/ASSET_MANIFEST.md`|`docs/design/inventory/EXTERNAL_SOURCE_MAP.json`|
|`docs/design/ASSET_MANIFEST.md`|`docs/design/inventory/REQUESTED_FILES.json`|
|`docs/design/ASSET_MANIFEST.md`|`docs/design/inventory/COPY_READBACK.json`|
|`docs/design/ASSET_MANIFEST.md`|`docs/design/inventory/DUPLICATES.json`|
|`docs/design/ASSET_MANIFEST.md`|`docs/design/inventory/ZIP_VERIFICATION.json`|
|`docs/design/ASSET_MANIFEST.md`|`docs/design/inventory/MISSING_FILES.json`|
|`docs/design/ASSET_MANIFEST.md`|`docs/design/inventory/INTEGRATION_VERIFICATION.json`|
|`docs/design/ASSET_MANIFEST.md`|`docs/design/inventory/SHA256SUMS.txt`|
|`docs/design/ASSET_MANIFEST.md`|`docs/design/inventory/CONCURRENT_G2_SNAPSHOT.json`|
|`docs/design/ASSET_MANIFEST.md`|`docs/design/inventory/OBSERVED_NATIVE_RENDER.json`|
|`docs/design/DESIGN_BIBLE.md`|`assets/g2/regions/region01_forest/imports/20261009_R01_delivery/R01_PACKAGE/README.md`|
|`docs/design/MISSING_FILES.md`|`docs/design/inventory/REQUESTED_FILES.json`|
|`docs/design/MISSING_FILES.md`|`docs/design/inventory/ZIP_VERIFICATION.json`|
|`docs/design/OPEN_ISSUES.md`|`docs/design/inventory/OBSERVED_NATIVE_RENDER.json`|
|`docs/design/OPEN_ISSUES.md`|`docs/design/inventory/CONCURRENT_G2_SNAPSHOT.json`|
|`docs/design/README.md`|`assets/g2/regions/region01_forest/imports/20261009_R01_delivery/R01_PACKAGE`|
|`docs/design/archive/g1/reports/G1_REPORT.md`|`docs/design/archive/g1/README.md`|
|`docs/design/archive/g1/reports/G1_REPORT.md`|`docs/design/archive/g1/tests/combat.test.js`|

全リポジトリのリンク完全性をPASSと表現しない。今回の共有目次・原本への新規リンクと、既存文書の過去リンクを分けて評価する。
既存GitHub資料333件のうち28ファイルには、過去の保存・build・render記録としてローカル絶対パスが123件ある。今回の新規共有資料には持ち込んでいない。既存文書を変更しないという今回の範囲に従い保全したが、ローカルユーザー名・環境情報が残る点は別途整理すべき既存リスクである。既存GitHubはprivateである。
