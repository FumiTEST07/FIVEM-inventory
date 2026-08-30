# as-evidencestash / 押収品倉庫

qb-core + ox_inventory 環境向けの、警察専用の共有押収品倉庫リソースです。

指定座標の 2m 以内で TextUI が表示され、`E` キーを押すとサーバー側で権限・距離・
入力値・クールダウンを検証したうえで、全体共有の stash を開きます。

- **リソース名**: `as-evidencestash`
- **表示名**: 押収品倉庫
- **種類**: ジョブ (police)
- **必要ランク**: grade 2 以上

---

## 目次

1. [依存関係](#依存関係)
2. [ファイル構成](#ファイル構成)
3. [導入手順](#導入手順)
4. [設定説明](#設定説明)
5. [動作フロー](#動作フロー)
6. [イベント一覧](#イベント一覧)
7. [セキュリティ設計](#セキュリティ設計)
8. [データ保存について](#データ保存について)
9. [静的検証手順](#静的検証手順)
10. [FXServer で確認すべきテスト項目](#fxserver-で確認すべきテスト項目)
11. [AI が提案した値・未確定事項](#ai-が提案した値未確定事項)
12. [トラブルシューティング](#トラブルシューティング)

---

## 依存関係

| リソース | 用途 |
|---|---|
| [qb-core](https://github.com/qbcore-framework/qb-core) | プレイヤー情報・ジョブ・ランクの取得 |
| [ox_lib](https://github.com/overextended/ox_lib) | TextUI、通知、コールバック |
| [oxmysql](https://github.com/overextended/oxmysql) | 監査ログの保存 |
| [ox_inventory](https://github.com/overextended/ox_inventory) | 共有 stash の登録と永続化 |

これら 4 つが **`as-evidencestash` より先に起動している必要があります**。

---

## ファイル構成

```
as-evidencestash/
├── fxmanifest.lua          依存宣言と読み込み順
├── config/
│   ├── shared.lua          SharedConfig : 倉庫定義・イベント名・日本語文言
│   ├── client.lua          ClientConfig : TextUI・ブリップ・ループ間隔
│   └── server.lua          ServerConfig : 容量・クールダウン・検証・ログ設定
├── client/
│   └── main.lua            距離監視・TextUI・キー入力・許可要求
├── server/
│   ├── main.lua            stash 登録・全検証・管理コマンド
│   └── storage.lua         監査ログの作成・記録・保持期間管理
├── sql/
│   └── install.sql         監査ログテーブルの DDL (任意)
├── .luacheckrc             静的検証用の設定
└── README.md               このファイル
```

### 設定ファイルを 3 つに分けている理由

| ファイル | 読み込まれる場所 | 置いてよい値 |
|---|---|---|
| `config/shared.lua` | クライアント + サーバー | 両側で同じ値を見る必要があるもの (座標・ラベル・文言) |
| `config/client.lua` | クライアントのみ | 見た目と入力に関するものだけ |
| `config/server.lua` | **サーバーのみ** | 容量・クールダウン・検証の厳しさなど、**正となる値** |

`config/server.lua` は `server_scripts` にしか含めていないため、クライアントからは
読み取れません。容量やクールダウンをクライアントが知る必要はないので、
この分割自体がセキュリティ対策になっています。

---

## 導入手順

### 1. 配置

`resources` 配下の任意のフォルダに `as-evidencestash` として配置します。

```
resources/[local]/as-evidencestash/
```

> フォルダ名は必ず `as-evidencestash` にしてください。
> `fxmanifest.lua` の `name` およびイベント名の接頭辞と一致させる前提です。

### 2. server.cfg に追記

**依存リソースより後に** `ensure` を書いてください。

```cfg
ensure oxmysql
ensure ox_lib
ensure qb-core
ensure ox_inventory
ensure as-evidencestash
```

### 3. データベース

`config/server.lua` の `logging.autoCreateTable` が `true`（既定）であれば、
起動時にテーブルが自動作成されるため **手動作業は不要**です。

自動作成を使わない運用にする場合は、先に `autoCreateTable = false` にしてから
`sql/install.sql` をデータベースに流してください。

### 4. 座標の設定

**この作業は必須です。** 既定値は仮の値です。

1. ゲーム内で倉庫を置きたい場所に立つ
2. 座標を取得する（例: ox_lib の `/coords`、または管理ツール）
3. `config/shared.lua` の `SharedConfig.stashes.mission_row.coords` を書き換える

```lua
SharedConfig.stashes = {
    ['mission_row'] = {
        label = '押収品倉庫 (ミッションロウ警察署)',
        coords = vec3(473.75, -996.5, 30.69), -- ← ここを実測値に置き換える
        job = 'police',
        minGrade = 2,
        distance = 2.0,
        showBlip = true
    },
}
```

### 5. 管理者権限（任意）

アクセス履歴を確認するコマンドを使う場合、`server.cfg` に ACE を追加します。

```cfg
add_ace group.admin as-evidencestash.logs allow
```

---

## 設定説明

### `config/shared.lua`

| 項目 | 既定値 | 説明 |
|---|---|---|
| `eventPrefix` | `'as-evidencestash'` | イベント名の接頭辞 |
| `stashPrefix` | `'evidence_stash_'` | stash ID の接頭辞。**稼働後は変更しないこと** |
| `defaultJob` | `'police'` | 既定の利用可能ジョブ |
| `defaultMinGrade` | `2` | 既定の最低ランク |
| `defaultDistance` | `2.0` | 既定の操作距離 (m) |
| `stashes` | 1 件 | 倉庫の定義（複数設置可） |
| `locale` | 日本語 | 表示文言 |

#### 倉庫を追加する

`SharedConfig.stashes` にキーを追加するだけで増やせます。コード修正は不要です。

```lua
['sandy_shores'] = {
    label = '押収品倉庫 (サンディショアーズ保安官事務所)',
    coords = vec3(1853.14, 3689.56, 34.27),
    job = 'police',
    minGrade = 2,
    distance = 2.0,
    showBlip = true
},
```

> **キーの制約**: 半角英数字とアンダースコアのみ、64 文字以内。
> キーは stash ID の一部になるため、**稼働後に変更すると中身が見えなくなります**。
> 条件を満たさないキーは起動時に警告を出して読み込まれません。

### `config/client.lua`

| 項目 | 既定値 | 説明 |
|---|---|---|
| `openControl` | `38` (E) | 倉庫を開くキー |
| `textUI.position` | `'left-center'` | TextUI の表示位置 |
| `textUI.icon` | `'box-archive'` | アイコン (Font Awesome) |
| `notify.position` | `'top-right'` | 通知の表示位置 |
| `notify.duration` | `5000` | 通知の表示時間 (ms) |
| `loop.idleInterval` | `1000` | 倉庫から離れているときのループ間隔 (ms) |
| `loop.nearInterval` | `250` | 倉庫の近くにいるときのループ間隔 (ms) |
| `loop.checkRadius` | `25.0` | 「近く」と判定する半径 (m) |
| `blip.enabled` | `true` | ブリップを表示するか |
| `hideTextUIWithoutJob` | `true` | 権限のないプレイヤーに TextUI を出さない（見た目のみ） |

### `config/server.lua`

| 項目 | 既定値 | 説明 |
|---|---|---|
| `slots` | `100` | stash のスロット数 |
| `maxWeight` | `500000` | stash の最大重量（ox_inventory の単位: グラム） |
| `distanceTolerance` | `3.0` | 距離検証の許容誤差 (m) |
| `requireOnDuty` | `false` | 勤務中のみ利用可にするか |
| `cooldownSeconds` | `0` | 開く操作のクールダウン (秒)。`0` で無効 |
| `logging.enabled` | `true` | 監査ログを記録するか |
| `logging.tableName` | `'as_evidencestash_logs'` | ログテーブル名 |
| `logging.autoCreateTable` | `true` | 起動時にテーブルを自動作成するか |
| `logging.logDenied` | `true` | 拒否されたアクセスも記録するか |
| `logging.logClose` | `true` | 倉庫を閉じたタイミングも記録するか |
| `logging.retentionDays` | `90` | ログの保持日数。`0` で無期限 |
| `debug` | `false` | 検証の経過をコンソールに出力するか |

#### `distanceTolerance` について

サーバーが持つプレイヤー座標はネットワーク同期の遅延で数メートルずれます。
そのため、サーバー側の距離判定は `操作距離 + distanceTolerance` の範囲で行います。

- 小さすぎる → 正常な操作が「離れすぎています」で弾かれる
- 大きすぎる → 遠隔からの操作を許してしまう

既定の `3.0` は妥当な出発点ですが、サーバーの環境に応じて調整してください。

---

## 動作フロー

```
[クライアント]                          [サーバー]
      │
      │ 1秒ごとに最寄りの倉庫との距離を計算
      │
      ├─ 2m 以内かつジョブ条件を満たす
      │   → TextUI「[E] 押収品倉庫を開く」を表示
      │      （※この判定は見た目のためだけのもの）
      │
      │ E キー入力
      │
      ├──── 倉庫のキー（例: "mission_row"）だけを送信 ────▶
      │                                          1. 入力値検証（型・文字種・登録有無）
      │                                          2. stash が登録済みか
      │                                          3. プレイヤーが存在するか
      │                                          4. 権限検証（police / grade 2 以上）
      │                                          5. 距離検証（2.0m + 許容 3.0m）
      │                                          6. クールダウン検証
      │                                          7. 監査ログに記録
      │                                             stash ID をサーバーが決定
      │◀──── { success, stashId, label } ────────┤
      │
      ├─ success = true  → ox_inventory を開く + 成功通知
      └─ success = false → サーバーが返した日本語メッセージで通知
```

クライアントが送るのは**倉庫のキー文字列 1 つだけ**です。
stash ID・スロット数・重量・必要ランクはすべてサーバーが決定します。

---

## イベント一覧

イベント名はすべて `as-evidencestash:side:actionName` 形式です。

| 種別 | 名前 | 方向 | 内容 |
|---|---|---|---|
| ox_lib コールバック | `as-evidencestash:server:requestOpen` | client → server | 引数: 倉庫キー(string)。戻り値: `{ success, stashId, label, message }` |
| ネットイベント | `as-evidencestash:client:notify` | server → client | 引数: メッセージ(string), 種別(string) |

### コマンド

| コマンド | 権限 | 説明 |
|---|---|---|
| `/evidencestashlogs [倉庫キー] [件数]` | ACE `as-evidencestash.logs` またはコンソール | 直近のアクセス履歴をサーバーコンソールに出力 |

例:

```
evidencestashlogs                 # 全倉庫の直近 20 件
evidencestashlogs mission_row 50  # ミッションロウの直近 50 件
```

---

## セキュリティ設計

| 要件 | 実装箇所 | 内容 |
|---|---|---|
| サーバー側の権限検証 | `server/main.lua` `validateJob` | qb-core の `PlayerData.job` をサーバーが直接参照。クライアントの申告は一切使わない |
| 距離検証 | `server/main.lua` `validateDistance` | `GetEntityCoords(GetPlayerPed(src))` をサーバー側で取得して判定 |
| 入力値検証 | `config/shared.lua` `SharedConfig.getStash` | 型・長さ・文字種（`[^%w_]` を拒否）・登録有無を確認 |
| クールダウン検証 | `server/main.lua` `validateCooldown` | サーバー側の `os.time()` で管理。設定 `0` で無効 |
| 重要な値をサーバーに置く | `config/server.lua` | スロット数・重量・許容距離・クールダウンは `server_scripts` のみに読み込む |
| クライアント値を信用しない | `server/main.lua` | 受け取るのは倉庫キーのみ。stash ID はサーバーが `SharedConfig.stashId()` で生成 |
| イベント命名規則 | 全体 | `SharedConfig.event(side, action)` で一元生成 |
| 多層防御 | `server/main.lua` `registerStashes` | 独自検証に加え、`RegisterStash` に `groups` と `coords` を渡し ox_inventory 側でも権限・距離を再検証させる |
| SQL インジェクション対策 | `server/storage.lua` | 値はすべてプレースホルダ (`?`)。テーブル名は埋め込み前に `safeTableName()` で文字種を検証 |

### クライアント側判定の位置づけ

`client/main.lua` にもジョブ判定 (`looksEligible`) がありますが、これは
**権限のないプレイヤーに TextUI を出さないための見た目の制御だけ**です。
クライアントを改造してこの判定を無効化しても、サーバー側の検証で必ず弾かれます。

---

## データ保存について

このリソースの永続化は **2 系統に分かれています**。混同しないでください。

### 1. 押収品アイテムそのもの → ox_inventory が保存

`exports.ox_inventory:RegisterStash()` で登録した共有 stash の中身は、
**ox_inventory が自身のテーブルに自動で永続化します**。

このリソースは stash の中身を独自テーブルに保存しません。
独自保存を追加すると二重管理となり、中身の不整合やアイテム複製の原因になります。

### 2. アクセス履歴 → `as_evidencestash_logs` テーブル

「誰が・いつ・どの倉庫にアクセスしたか」を `server/storage.lua` が記録します。

| カラム | 内容 |
|---|---|
| `stash_id` | ox_inventory 上の stash ID |
| `stash_key` | `SharedConfig.stashes` のキー |
| `citizenid` | qb-core の citizenid |
| `player_name` | 接続時のプレイヤー名 |
| `identifier` | license 識別子 |
| `action` | `open` / `close` / `denied` |
| `detail` | 拒否理由（`no_job`、`no_grade`、`too_far:12.3m` など） |
| `created_at` | 記録日時 |

- ログの書き込みは非同期で、失敗しても倉庫の利用は妨げません
- `retentionDays` を過ぎたログはリソース起動時に削除されます

> **注意**: 監査ログは「アクセスの記録」であって「アイテムの出し入れの記録」では
> ありません。どのアイテムがいつ動いたかを追跡したい場合は、ox_inventory 側の
> ログ機能を併用してください。

---

## 静的検証手順

FXServer を起動せずに確認できる範囲の検証手順です。

### 1. 構文チェック（必須）

Lua 5.4 の `luac` で全ファイルの構文を確認します。

```bash
for f in fxmanifest.lua config/*.lua client/*.lua server/*.lua; do
    luac5.4 -p "$f" && echo "OK   $f" || echo "FAIL $f"
done
```

全ファイルが `OK` になることを確認してください。

<details>
<summary>Lua がインストールされていない場合</summary>

```bash
# Debian / Ubuntu
sudo apt-get install -y lua5.4

# macOS
brew install lua
```
</details>

### 2. Lint（推奨）

```bash
# インストール
luarocks install luacheck

# 実行（.luacheckrc が自動で読み込まれます）
luacheck .
```

`.luacheckrc` に FiveM / ox_lib / qb-core / oxmysql のグローバルを登録済みなので、
`accessing undefined variable` は出ない想定です。

### 3. 設定値の整合性チェック

FXServer なしで `config/shared.lua` のヘルパーだけを動かして確認できます。

```bash
cat > /tmp/check.lua <<'LUA'
function vec3(x, y, z) return { x = x, y = y, z = z } end
dofile('config/shared.lua')

assert(SharedConfig.event('server', 'requestOpen') == 'as-evidencestash:server:requestOpen')
assert(SharedConfig.stashId('mission_row') == 'evidence_stash_mission_row')

-- 入力値検証: 不正な値がすべて弾かれること
assert(SharedConfig.getStash('mission_row'))
assert(SharedConfig.getStash('nope') == nil)
assert(SharedConfig.getStash(123) == nil)
assert(SharedConfig.getStash('a; DROP TABLE') == nil)
assert(SharedConfig.getStash(string.rep('a', 65)) == nil)

print('config/shared.lua OK')
LUA

lua5.4 /tmp/check.lua
```

### 4. 目視チェックリスト

- [ ] `fxmanifest.lua` の `dependencies` に 4 リソースが揃っている
- [ ] `config/server.lua` が `client_scripts` に**含まれていない**
- [ ] `SharedConfig.stashes` の各 `coords` が実サーバーの実測値になっている
- [ ] `SharedConfig.stashes` のキーが半角英数字とアンダースコアのみ
- [ ] `server.cfg` の `ensure` 順が依存 → 本リソースになっている

---

## FXServer で確認すべきテスト項目

> 以下は**実サーバーでの確認が必要な項目**です。
> 本リソースは構文チェックと設定ロジックの検証のみ実施しており、
> **ライブ FXServer 上での動作は未検証です。**

### A. 起動

| # | 手順 | 期待結果 |
|---|---|---|
| A-1 | `ensure as-evidencestash` | コンソールにエラーが出ない |
| A-2 | `config/server.lua` で `debug = true` にして再起動 | `倉庫 "mission_row" (evidence_stash_mission_row) を登録しました。` が出る |
| A-3 | データベースを確認 | `as_evidencestash_logs` テーブルが作成されている |
| A-4 | `SharedConfig.stashes` に不正なキー（例: `['bad key!']`）を入れて起動 | 警告が出て、その倉庫だけ読み込まれない |

### B. 正常系

| # | 手順 | 期待結果 |
|---|---|---|
| B-1 | police / grade 2 で設定座標から 2m 以内に立つ | TextUI「[E] 押収品倉庫を開く」が表示される |
| B-2 | `E` を押す | ox_inventory の stash が開き、成功通知が出る |
| B-3 | スロット数と重量を確認 | 100 スロット / 500000 の容量になっている |
| B-4 | アイテムを預け入れて閉じる → 再度開く | アイテムが残っている |
| B-5 | サーバーを再起動して再度開く | アイテムが残っている（ox_inventory による永続化） |
| B-6 | 別の police プレイヤーで開く | 同じ中身が見える（全体共有） |
| B-7 | ログテーブルを確認 | `action = 'open'` / `'close'` の行が記録されている |

### C. 権限（拒否系）

| # | 手順 | 期待結果 |
|---|---|---|
| C-1 | 無職 / 他ジョブで座標に立つ | TextUI が表示されない |
| C-2 | police grade 0〜1 で座標に立つ | TextUI が表示されない |
| C-3 | police grade 1 でクライアントから直接コールバックを呼ぶ | 「権限が不足しています。(必要ランク: 2 以上)」で拒否され、`action = 'denied'` / `detail = 'no_grade'` が記録される |
| C-4 | 無職でクライアントから直接コールバックを呼ぶ | 「警察官のみ利用できます。」で拒否される |
| C-5 | `requireOnDuty = true` にしてオフデューティで開く | 「勤務中でないため利用できません。」で拒否される |

### D. 距離

| # | 手順 | 期待結果 |
|---|---|---|
| D-1 | 座標から 3m 離れる | TextUI が消える |
| D-2 | 座標から 50m 離れた位置でコールバックを直接呼ぶ | 「倉庫から離れすぎています。」で拒否され、`detail = 'too_far:50.0m'` が記録される |
| D-3 | 2m 境界付近を出入りする | TextUI の表示・非表示が正しく切り替わる |

### E. 入力値

| # | 手順 | 期待結果 |
|---|---|---|
| E-1 | 存在しないキー（`"fake_stash"`）でコールバックを呼ぶ | 「この押収品倉庫は存在しません。」で拒否される |
| E-2 | 数値・テーブル・`nil` を渡す | 同上。サーバーにエラーが出ない |
| E-3 | SQL を含む文字列（`"a'; DROP TABLE x;--"`）を渡す | 拒否され、DB に影響がない |
| E-4 | 極端に長い文字列（1000 文字）を渡す | 拒否される |

### F. クールダウン

| # | 手順 | 期待結果 |
|---|---|---|
| F-1 | `cooldownSeconds = 0`（既定）で連続して開く | 制限なく開ける |
| F-2 | `cooldownSeconds = 5` にして連続で開く | 「まだ利用できません。あと N 秒お待ちください。」が出る |
| F-3 | 5 秒待って再度開く | 正常に開ける |

### G. 複数拠点・再起動

| # | 手順 | 期待結果 |
|---|---|---|
| G-1 | `stashes` に 2 件目を追加して再起動 | 両方の倉庫が独立して開き、中身が混ざらない |
| G-2 | `restart ox_inventory` を実行後に倉庫を開く | 再登録され、正常に開ける |
| G-3 | 倉庫を開いたまま切断 → 再接続 | エラーが出ず、正常に開ける |
| G-4 | `restart as-evidencestash` を実行 | TextUI が消え、ブリップが消え、再登録される |

### H. UI・ログ

| # | 手順 | 期待結果 |
|---|---|---|
| H-1 | マップを開く | 押収品倉庫のブリップが表示される |
| H-2 | `blip.enabled = false` にして再起動 | ブリップが表示されない |
| H-3 | 管理者で `/evidencestashlogs` | 履歴がサーバーコンソールに出力される |
| H-4 | 一般プレイヤーで `/evidencestashlogs` | 「権限がありません。」と通知される |
| H-5 | `logging.enabled = false` にする | ログが記録されず、倉庫は正常に開ける |

---

## AI が提案した値・未確定事項

依頼時点で未確定だった項目について、こちらで既定値を設定しています。
**いずれも本番投入前に確認・調整してください。**

| 項目 | 設定値 | 根拠 | 対応 |
|---|---|---|---|
| **設置座標** | `vec3(473.75, -996.5, 30.69)` | **[AI提案]** 実座標が未確定のため、ミッションロウ警察署の証拠品室付近を仮置き | **必ず実測値に差し替えてください** |
| **クールダウン** | `0`（無効） | 要件では「未設定」でしたが、セキュリティ要件に「クールダウン検証」があり矛盾していました。設定可能な形で実装し、既定は無効にしています | 連打対策が必要なら 2〜5 秒を推奨 |
| **距離許容誤差** | `3.0` m | **[AI提案]** サーバー座標の同期遅延を吸収するための値。要件に指定がありませんでした | 環境に応じて調整 |
| **勤務状態チェック** | `false`（問わない） | **[AI提案]** 要件に指定がなかったため、既存運用を壊さない側に倒しています | 勤務管理を厳格にしているなら `true` |
| **ログ保持日数** | `90` 日 | **[AI提案]** 要件に指定がありませんでした | 運用ポリシーに合わせて調整 |
| **ブリップ** | 有効 (sprite 478) | **[AI提案]** 要件に指定がありませんでした | 不要なら `blip.enabled = false` |

### 要件との差分

依頼内容の「DB保存: 必要 / `server/storage.lua`」について、当初の想定どおりに
独自テーブルへアイテムを保存すると **ox_inventory の永続化と二重管理になり、
アイテム複製や中身の不整合を招きます**。

そのため、確認のうえ以下の構成にしています。

- アイテム本体 → ox_inventory の標準永続化に任せる
- `server/storage.lua` → **アクセス監査ログ**を担当（「DB保存: 必要」を満たす）

---

## トラブルシューティング

| 症状 | 確認すること |
|---|---|
| TextUI が出ない | ジョブが `police` か / grade が 2 以上か / 座標が正しいか / `hideTextUIWithoutJob` の影響 |
| 「押収品倉庫がまだ準備できていません」 | `ensure` の順序。ox_inventory より後に起動しているか。`debug = true` で登録ログを確認 |
| 「倉庫から離れすぎています」が近くでも出る | `distanceTolerance` を少し大きくする（同期遅延の影響） |
| 中身が消えた | `stashPrefix` または `stashes` のキーを変更していないか（stash ID が変わると別の倉庫になります） |
| ログが記録されない | `logging.enabled` / oxmysql の接続 / テーブルが作成されているか |
| `restart ox_inventory` 後に開けない | 通常は自動で再登録されます。直らない場合は `restart as-evidencestash` |

---

## ライセンス・注意

- 本リソースは **ライブ FXServer 上での動作確認を行っていません。**
  実施済みの検証は Lua 5.4 での構文チェックと `config/shared.lua` の
  ヘルパー関数（イベント名生成・stash ID 生成・入力値検証）の単体確認のみです。
- 本番環境に導入する前に、上記「FXServer で確認すべきテスト項目」を
  テストサーバーで一通り実施してください。
