# 再現範囲と実行条件

この共有作業ではゲーム試験の再実行や新しいビルドは行っていません。既存結果の版・ハッシュ・内容を照合しました。

1. `SHARED_PAYLOAD_MANIFEST_R001.json`のファイルSHA-256を確認する。R088由来とローカル補足を区別する。240入力はR465 `NATIVE_SOURCE_MAP_R001.json`と一致する。
2. `native/WitchGameCore/Package.swift`はSwift6.0、macOS14/iOS17以上。Coreソース・Resources・Testsを共有。基本の`swift test --package-path native/WitchGameCore`はdefault構成で、通常アプリのフラグ付き結果や過去のcandidate試験と同一とは限らない。実行時は新しいscratch/outputを割り当てる。
3. 各QAのcandidate source、INPUT_MANIFEST、run driver、初回失敗と最終RESULT/RUNを合わせる。R374/R448/R452はフラグ・seed・仮想時計・plannerを使う。過去の保存済み複製packageを現在コードで置換すると同じ実験にはならない。省いた複製のパスとSHAはOMITTED_REPRO_COPIESに残す。
4. `tools/witch_purchase_authority/README.md`のローカルunittest手順を利用できる。署名試験は`signed_audit_requirements.lock`依存が必要。未導入時のskipはPASSとしない。synthetic証明書/fixtureのみで、Apple秘密鍵・実購入トークンを含めない。サーバー/Appleへの通信や本番付与はできない。
5. R465の実際の生成project、GameInfo、SOURCE/RESOURCE_SHA256を`build_identity/`に格納した。これは対応関係の一次証拠であり、共有先ディレクトリへ単独で移してそのままビルドするprojectではない。元の凍結パス・PreparedResourcesを参照する。通常`native/WitchGathering.xcodeproj`のPBXは継承されたGit版で、Macの未コミットPBXとは異なり、最新成功ビルドを保証しない。
6. 完全なiOSアプリ再構築にはLOCAL_ONLY_EVIDENCEに列挙した1922資源、元の凍結入力、Xcode26.6(17F113)/SDK26.5相当が必要。監査共有だけで全画面・動作・音を再現できるとは主張しない。build_toolsのsealed manifestは既存出力/保護ハッシュを固定しているため、無編集の再実行や上書きを行わない。
7. 最新実画面はR465run。補助画面R456/R443/R433は別版。R465通し動画は未撮影。R424動画3本の絶対パス/版/SHAをLOCAL_ONLY_EVIDENCEに記録し、原本はMacへ保全。

原画・編集元・セーブ・Git履歴・固有QA証拠を保護する。レビュー中は大規模開発を停止。再開時は新たな指示、Git状態/実行プロセス/容量、R088報告と完成台帳を確認してから未完了項目へ進む。既存307アプリを削除/変更しない。
