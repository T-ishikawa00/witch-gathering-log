# セキュリティ・プライバシー検査

確認日：2026-11-07 JST。秘密の値を出さず、パス・種類・件数だけを記録した。

## 共有する範囲

旧mainの4commit履歴を維持し、その上に選別したソース・安全な設定・文書・画面だけを追加する。元開発ブランチの110commit履歴は今回pushしない。したがって元の大型QA、実セーブ、署名情報、個人用設定がhistory経由で新規共有されない構成にした。

今回の変更対象・staged blob・新規commitについて、API token、GitHub token、AWS access key、OpenAI key、Slack token、private key block、認証・署名ファイル、個人絶対パス、メール、実セーブ名を確認した。疑似秘密・試験fixture・画像名の`@2x`を実秘密と区別する。新しいcommitにはGitHubのnoreplyメールを使い、既存commitの作者情報は改変しない。

既にremoteへ存在するmain・R046・R088の到達可能履歴も、ローカルにある同一SHAから3,338 unique blob／255,345,507 bytesを読んで限定検査した。UTF-8 text 3,245件、binary/non-UTF-8 93件。対象の高確度token／private-key正規表現の一致は0件。remote以外の110commit全量や未知形式の秘密を完全検査したという意味ではない。

## 入れないもの

- `.env`、秘密鍵、署名証明書、Provisioning Profile、Apple／GitHub認証情報、Keychain。
- 実ユーザーのセーブ、端末識別子、実購入receipt、個人のQAログ・環境設定。
- 権利の確認が残る原画・音源・編集元や、巨大な生QA出力の一括登録。
- 未承認のGitHub Actions、Pages、Release、外部送信・配布ジョブ。

R159・R179は生成された試験save、R227はengine QA候補fixture。出所・固定hashは[fixture台帳](evidence/FIXTURE_PROVENANCE.json)へ記録し、実セーブと区別した。実セーブを匿名化して共有する処理は行っていない。

## 副作用と限界

新規projectの唯一のbuild scriptは、指定した固定資材を検証して専用build出力へコピーする。外部package取得、Apple認証、元のproject書換え、source生成は行わない。新しいBundle IDと専用Simulatorを使用する。元のTeam・署名設定は変更しない。

main・R046・R088と新規treeで`.github/workflows/`がないことを確認した。設定・権限・default branch・Public化・公開操作・外部連絡は行わない。

検査は正規表現と目視・構成確認による限定的なもの。全binary内部の任意データ、未知形式の秘密、原画全量のOCR、外部credentialの有効性、依存脆弱性の網羅検査は未実施。新規の代表画面は目視確認する。秘密の「不存在」や全資材の権利確定を保証するものではない。実秘密や未検査の共有historyが見つかった場合は当該pushを保留し、既存履歴を書き換えない。
