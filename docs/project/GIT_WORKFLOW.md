# 開発を安全に再開する

1. remoteのPrivate状態とmainを確認し、新しいcloneまたは別worktreeで`codex/`ブランチを作る。元の未コミット設定を上書きしない。
2. README、STATUS、VALIDATION、REPRODUCTION、ASSET_REGISTERを読む。基点SHAと使用資材のmanifestを作業記録へ残す。
3. 新しいSwiftは許可したsource/testディレクトリへ置く。`git status --short`と`git check-ignore --no-index -v -- <path>`で保存漏れを確認する。`tools/repository/check_repository.py`も実行する。
4. `.gitignore`の歴史的allowlistは維持し、現行source入口だけ開放した。生成物・個人設定・実セーブ・認証・署名材を入れない。素材は採否・出所・権利・容量を個別に確認する。
5. stageは正確なファイル一覧／NUL pathspecを使う。`git add .`、`git add -A`、`git commit -a`、`git add -f .`は使わない。staged path、mode、size、SHA、秘密情報、意図しないActionsを検査する。
6. Core／必要なUIスモークを専用出力と新規セーブで実行する。既存Human用Simulatorや実機を使わない。
7. 通常push後、remote SHA・tree・ファイル・リンク・資材依存を再取得して確認する。履歴改変・force pushは行わない。READMEの版と検証範囲を更新する。

新規の原画・音源・大容量assetを自動でGitに入れない。必要な資材は台帳へ追加し、所有者の保管実体とhashを確認する。ignoreはbackupではなく、Gitのclean状態も全資産の保存完了を意味しない。

## 大容量・LFS

今回の追加は選別したソース・文書・軽量画面で、固定runtime pack約366MBや原画の全量は追加しない。LFSは導入しておらず、既存履歴を移行していない。GitHubは通常Gitの50MiB超に警告、100MiB超を拒否するため、将来の大容量資材は権利確認後に保存方式を決める。[GitHub公式の大容量ファイル説明](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github)を2026-11-07に確認した。

LFSはpointerと本体が分かれ、保存・downloadが利用枠／転送量に影響する。[LFS公式説明](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-git-large-file-storage)と[課金説明](https://docs.github.com/en/billing/concepts/product-billing/git-lfs)を参照。今回アカウントのLFS利用枠・請求設定は照会していないため、新しい費用や別ストレージは作らない。将来採用する場合も新規commitから適用し、既存履歴を書き換えない。

CI、ブランチ保護、Pages、Release、権限・collaborator設定は変更していない。端末操作、Apple認証・署名、本番課金、公開・発売、権利の採否は別の本人判断。
