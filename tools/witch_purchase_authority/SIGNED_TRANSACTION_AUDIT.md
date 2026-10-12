# 署名付き取引のローカル監査

`signed_transaction_audit.py` は、Apple公式ライブラリ3.1.2でES256署名と証明書チェーンを検証する、独立したオフライン監査モジュールです。ゲームや購入台帳への接続はありません。既存の `PurchaseAuthority.ingest_apple_jws()` は引き続き拒否します。

対象はSandbox形式だけです。公式ライブラリが署名検証を省略するXcode/LocalTestingと、本番環境を設定時に拒否します。信頼するルートは監査者が設定し、取引の `x5c` に含まれるルートを自動的に信頼しません。公式の厳格なX.509検証を無効にしていません。

署名検証後に、元のJSON型でbundle、環境、商品・数量・種別、UUID形式のアカウント対応、所有種別、取消情報、購入日時と署名日時を検査します。重複JSONキー、過大データ、署名アルゴリズム変更、不明な重要ヘッダーも拒否します。結果には取引ハッシュと設定したルートのハッシュを残し、元のJWSやアカウントトークンは含めません。

**検証結果は付与の許可ではありません。** オンラインの失効確認を行わず、どの結果も `grant_authorized=false`、`revocation_checked=false` です。アカウントトークンの一致は本人認証の代替になりません。信頼ルートの正当性も別途必要です。

テストではメモリ内に非AppleのCA・中間・署名鍵を作り、本物の暗号署名を検証しています。実際のApple Sandbox取引やApple発行チェーンの成功例ではありません。鍵はファイルへ保存せず、ネットワーク呼び出しはテスト中に禁止しています。21件の暗号監査と既存21件、計42件が通過しました。独立監査の指摘を受け、結果の安全フラグをコンストラクターや `dataclasses.replace` から変更できない形にしました。

再実行は、このフォルダを作業ディレクトリにして専用環境で行います。

```sh
.venv_signed_audit_r001/bin/python -m unittest discover -s tests -v
```

依存関係は `signed_audit_requirements.lock` に固定しています。専用環境のない既存stdlib試験では暗号監査モジュールだけが明示的にSKIPされます。暗号監査を実施済みと記録するには、専用環境で21件・SKIPなしが必要です。

初回のヘッダー試験は、PyJWTが `b64=true` を削除したため意図した入力になっていませんでした。元の失敗と修正を保存しています。別の試行は作業ディレクトリ誤りでimportに失敗しました。記録は `docs/production/current/purchases/signed_transaction_audit_r001/` にあります。

本番には、Appleの信頼ルート管理と失効確認、実Sandbox署名取引、認証済みアカウントとの対応、通知と返金の照合、課金台帳・乱数・永続履歴への接続、運用・セキュリティ検証が残ります。

参照: [Apple公式ライブラリv3.1.2](https://github.com/apple/app-store-server-library-python/tree/v3.1.2)、[3.1.2で修正された失効確認の問題](https://github.com/apple/app-store-server-library-python/security/advisories/GHSA-8f6j-263m-g72x)、[Apple PKI](https://www.apple.com/certificateauthority/)。
