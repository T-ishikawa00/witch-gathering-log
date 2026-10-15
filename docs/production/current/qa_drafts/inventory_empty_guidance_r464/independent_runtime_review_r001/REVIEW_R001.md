# R462 実画面・保存状態の独立確認

対象 run: `799b47c3-09fb-4461-a16b-2f754a5278be`（R462、`CAPTURE_CLOSED_FILTER_GUIDANCE_COLD_SAVES_EXACT`）。本記録は保存結果と画面表示を別々に判定する。

## 実画面で確認したこと

`empty_search/screen.png`（SHA-256 `e0eab325423a38fa5378732851cffca31c335a3bd7d8b1fa43aac69b12f1ac99`）では所持43件・表示0件で、該当なし案内と「検索と品質の条件を解除」ボタンが見える。検索欄には `zR464 の ztch っっ Z` が残っている。

`filters_cleared/screen.png`（SHA-256 `c3a00aa8687eb31d264a73e92b43a5aa1ce9b59996cf0b4d7c711afdf29017d3`）では所持43件・表示43件に戻り、品質は「すべて」に戻っている。一方、検索欄には空検索画面と同じ文字列が残ったまま。したがって解除操作は一覧の絞り込み状態には効くが、表示中の日本語IME入力文字列は消せていない。これは画面上の実不整合であり、保存破損を示す証拠ではない。

`cold/screen.png`（SHA-256 `833a02bd383adaf508f3ef6d46316f8c7a93fbf9e9e0675f9b0da72dbd9726ff`）は再起動後のホーム画面で、在庫画面を再表示していない。この画像からIME文字列が再起動後に消えた、または残ったとは判定しない。

## 保存状態

RUN（SHA-256 `70f6aad69924dee2b1bab2d5e9f469ba35671b6b6e25328767b81ceec701e71a`）の5 checkpoint は全て revision 138、`protectedUnchanged: true`。`save.json` は全段階で SHA-256 `3725e9c13d0e514804d5941d23b7847e12d7c13eb04aac0b3e676b190ae3a3c1`、`save.json.previous` は `27e965d92ab0d943541a075a599055d37ffd8e4bff501862b00f127846ca3a44` で一致し、cold checkpoint も `coldSaveBytesExact: true`。検索・品質解除とIME表示不整合は、今回の計測範囲ではセーブrevisionやセーブ本文の変更を伴っていない。

起動時に派生 identity receipt は `d45f65919d166c4d2ecc7047bdecbdd67d5200a04d9dbb709dee3acc4a28c0fd`、cold 起動後は `6cef1fb0e9b980f593a03deb19893e0e04f9f110b4624071c49c8470966c7dc5`。これはRUNが別ファイルとして記録する起動由来の観測値であり、上記save/previousの同一性と混同しない。

## 判定と範囲

- 保存保全: このrunの保存対象に限り一致を確認。
- 画面操作: 空検索案内、条件解除後の43件表示を確認。
- UI不具合: 条件解除後もIME入力文字列が欄に残ることを確認。Root予定のFocusStateと入力世代の修正はこの表示状態を解消できるかを別途確認する必要がある。
- 未確認: 修正後の画面、解除後に日本語IMEの未確定文字列/marked textが消える挙動、cold reopen後の在庫画面。

画面SHAは保存済みPNGから確認。再実行・Simulator操作・既存証拠変更は行っていない。
