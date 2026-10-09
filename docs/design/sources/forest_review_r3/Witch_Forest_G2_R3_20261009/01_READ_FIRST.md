# 木漏れ日の森 — 個別素材レビュー R3

**重要:** このパッケージの背景2点・魔物6点は、既存のAI生成コンセプトボードから個別に切り出した**方向性確認用の参照画像**です。新規制作の完成原画、ゲーム用透過スプライト、アニメーション、背景レイヤーを意味しません。

## 正本の優先順位
1. 承認済みの4キャラクター設定画 `reference/APPROVED_CHARACTERS_R1.png`（外見を変更しない）
2. 前回の地域・魔物・素材・装備設計 R1/R2（名称・素材・出現時期・因果関係）
3. 今回の切り出し画像 R3（絵柄・色・雰囲気の暫定参考）

## 画像一覧

|ID|対象|個別画像|取得素材|状態|
|---|---|---|---|---|
| `BG_R01_FIELD` | こもれびの採集路 | [images/background_refs/BG_R01_FIELD_SCENE_REF.png](images/background_refs/BG_R01_FIELD_SCENE_REF.png) | — | **参考のみ** |
| `BG_R01_BOSS` | 苔冠の古樹前 | [images/background_refs/BG_R01_BOSS_SCENE_REF.png](images/background_refs/BG_R01_BOSS_SCENE_REF.png) | — | **参考のみ** |
| `E_R01_01` | 苔角いのしし | [images/creature_refs/E_R01_01_MOSS_TUSK_BOAR.png](images/creature_refs/E_R01_01_MOSS_TUSK_BOAR.png) | 苔角片 | **参考のみ** |
| `E_R01_02` | 糸灯ぐも | [images/creature_refs/E_R01_02_LANTERN_SPIDER.png](images/creature_refs/E_R01_02_LANTERN_SPIDER.png) | 灯糸 | **参考のみ** |
| `E_R01_03` | 葉刃むし | [images/creature_refs/E_R01_03_LEAF_BLADE_INSECT.png](images/creature_refs/E_R01_03_LEAF_BLADE_INSECT.png) | 葉刃殻 | **参考のみ** |
| `E_R01_04` | 樹脂ころがし | [images/creature_refs/E_R01_04_AMBER_ROLLER.png](images/creature_refs/E_R01_04_AMBER_ROLLER.png) | 琥珀の甲片 | **参考のみ** |
| `B_R01_A` | 根絡みの大猪 | [images/creature_refs/B_R01_A_ROOTED_BOAR.png](images/creature_refs/B_R01_A_ROOTED_BOAR.png) | 根絡みの牙 | **参考のみ** |
| `B_R01_B` | 苔冠の古樹 | [images/creature_refs/B_R01_B_ANCIENT_CROWN_TREE.png](images/creature_refs/B_R01_B_ANCIENT_CROWN_TREE.png) | 苔冠の生木核 | **参考のみ** |

## この段階で合意可能なこと
- 森の暖かい琥珀光・深い緑・苔・曲がった木・真鍮色の遺物の方向性
- 4体の通常敵と2体のボスの分類とドロップする素材名
- 物語上の扱い：採集・自然との力比べ、ボスは死亡しない

## まだ承認してはならないこと
- 2背景を「本番用完成背景」と見なすこと（個別原画・レイヤーがない）
- 古樹の青い巨大結晶を正式設定として追加すること
- ボスの位置・当たり判定・4人と敵を重ねたiPhone縦画面の表示
- 通常敵の透過スプライト・攻撃予告・アニメーションが完成したという扱い

## 本番制作に入るための受入条件

1. 背景はキャラクター・ボス・HUD・文字が描かれていない独立した原画である。
2. 背景は遠景、背景、中景、床、手前草など分離して再配置できる。
3. `BG_R01_BOSS` に苔冠の古樹の身体を描き込まず、戦闘キャラクターレイヤーに独立させる。
4. 4人と敵の姿・影・HP・攻撃予告がiPhone縦画面で識別できる。
5. 魔物6体はそれぞれ斜め前向きの輪郭・攻撃予告・攻撃・被弾・後隙・ドロップ部位の一貫性を持つ。
6. 1種類ずつ透過・原寸・正しいピクセルグリッドの書き出しを検証する。
7. 通常敵・ボスのドロップ素材は別の独立アイコンで再現する。
8. 原画・レイヤー・ライセンス・制作経緯を記録し、正本のレシピIDと整合させる。

## G1との関係
G1は固定18装備・3ボスの技術試作であり、R01新アセットを既存G1の保存データや戦闘数値へ直接上書きしない。先にG2 Vertical Sliceで新しいゲーム用描画方式とセーブ移行を検証する。
