# ローカルテストサーバー構築手順

`as-evidencestash` を動作確認するための、ローカル FXServer の構築手順です。

> **このフォルダの内容について**
>
> ここにあるスクリプトと手順は Claude が作成しましたが、
> **実際の FXServer / Windows 環境では実行していません。**
> ロジック単体（zip の展開先判定など）は検証済みですが、
> 通しで動かした実績はありません。想定と違う挙動をしたら教えてください。

---

## 前提: なぜ既存の軽量サーバーではダメか

`as-evidencestash` は `qb-core` の `PlayerData.job` を参照して権限を判定します。
そのため **qb-core が動いている環境が必須**です。

`cfx-server-data` 標準の `basic-gamemode` + `fivem-map-skater` の構成では、
そもそもキャラクターという概念がないため、police の grade 2 を持った状態を作れません。
さらにこの 2 つは独自のスポーン処理を持っており、**qb-core と競合します**。

qb-core は単体では成立せず、キャラクター作成・スポーンなどの周辺リソースが要ります。
これを手で揃えるのは大変なので、**txAdmin の QBCore レシピを使ってください。**

---

## ステップ 1: 必要なもの

| 項目 | 入手先 | 備考 |
|---|---|---|
| FXServer artifacts | [Windows](https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/) / [Linux](https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/) | recommended 版 |
| ライセンスキー | [keymaster.fivem.net](https://keymaster.fivem.net/) | **必須・無料** |
| MySQL / MariaDB | XAMPP、MariaDB など | |
| GTA V + FiveM クライアント | | 接続して確認するのに必要 |
| Git | [git-scm.com](https://git-scm.com/) | |

> ⚠️ **ライセンスキーは秘密情報です。** 設定ファイルを誰かに見せるときは
> `sv_licenseKey "***"` のように必ず伏せてください。DB のパスワードや
> 自分の license 識別子も同様です。

---

## ステップ 2: txAdmin で QBCore の土台を作る

1. FXServer を **引数なし**で起動する（txAdmin が立ち上がります）

   ```
   FXServer.exe
   ```

2. 表示された URL（既定は `http://localhost:40120`）をブラウザで開く
3. 画面の指示に従ってアカウントを作成
4. **Deployer → Recipe** で **QBCore (qbcore-framework)** を選択
5. データベースの接続情報を入力

これで qb-core 一式、oxmysql、SQL のインポートまで自動で完了します。
この時点で一度サーバーに接続でき、キャラクターが作れることを確認してください。

> ここが終わるまで次に進まないでください。
> 土台が動いていない状態で `as-evidencestash` を足しても切り分けができません。

---

## ステップ 3: リソースを配置する

このリポジトリの `docs/testserver/` にあるスクリプトを使うと、
`ox_lib` / `oxmysql` / `ox_inventory` の**ビルド済みリリース**と
`as-evidencestash` をまとめて配置できます。

### Windows

```powershell
# まず内容を確認（-WhatIf で実際には変更しません）
.\setup-resources.ps1 -ServerData "C:\FXServer\server-data" -WhatIf

# 問題なければ実行
.\setup-resources.ps1 -ServerData "C:\FXServer\server-data"
```

### Linux

```bash
./setup-resources.sh /path/to/server-data
```

### 手動でやる場合

⚠️ **重要**: `ox_lib` / `ox_inventory` / `oxmysql` を GitHub の
「Code → Download ZIP」で落とすと**動きません**。UI のビルド成果物が
リポジトリに含まれていないためです。必ず **Releases のビルド済み zip** を使ってください。

| リソース | 入手先 |
|---|---|
| ox_lib | https://github.com/overextended/ox_lib/releases |
| oxmysql | https://github.com/overextended/oxmysql/releases |
| ox_inventory | https://github.com/overextended/ox_inventory/releases |

配置先:

```
server-data/resources/
├── [ox]/
│   ├── ox_lib
│   ├── oxmysql
│   └── ox_inventory
└── [local]/
    └── as-evidencestash     ← フォルダ名は必ずこれ
```

`as-evidencestash` の取得:

```bash
git clone https://github.com/FumiTEST07/FIVEM-inventory.git as-evidencestash
```

> フォルダ名を `FIVEM-inventory` のままにすると動きません。
> 必ず `as-evidencestash` にリネームしてください。

---

## ステップ 4: server.cfg を編集する

`server.cfg.snippet` の内容を `server.cfg` に追記してください。

**削除するもの**（qb-core と競合します）:

```cfg
ensure basic-gamemode      ← 削除
ensure fivem-map-skater    ← 削除
```

**ensure の順序**（これを守らないと stash の登録に失敗します）:

```cfg
ensure oxmysql
ensure ox_lib
ensure qb-core
ensure ox_inventory
ensure as-evidencestash
```

`as-evidencestash` は起動時に `ox_inventory` へ stash を登録するため、
必ず `ox_inventory` より後に起動する必要があります。

---

## ステップ 5: 起動して確認する

デバッグ出力を有効にしておくと確認が楽です。

`config/server.lua`:
```lua
ServerConfig.debug = true
```

サーバーを起動し、コンソールに次の 2 行が出れば成功です。

```
[as-evidencestash] 監査ログテーブル `as_evidencestash_logs` を準備しました。
[as-evidencestash] 倉庫 "mission_row" (evidence_stash_mission_row) を登録しました。
```

### 失敗した場合

```
[as-evidencestash] 倉庫 "mission_row" の登録に失敗しました: ...
```

`pcall` で囲んであるのでサーバーは落ちません。エラーメッセージ全文と
`ox_inventory/fxmanifest.lua` の `version` 行を控えてください。

> なお、`ox_inventory v2.47.9` のソースとは引数の順序・型を照合済みです
> （リポジトリ README の「依存リソースのソースとの照合」を参照）。
> 大きく異なるバージョンでなければ通る想定です。

---

## ステップ 6: テスト用の権限を付与する

サーバーコンソールから自分に admin 権限を付与します。

```
addpermission 1 god
```

`1` は自分のサーバー ID（`status` コマンドで確認できます）。

続いてゲーム内で police の grade 2 を設定します。

```
/setjob 1 police 2
```

> qb-core の police は grade 0=Recruit / 1=Officer / **2=Sergeant** /
> 3=Lieutenant / 4=Chief です。本リソースは grade 2 以上で利用できます。
> 拒否のテストをするときは grade 1 に落としてください。

`server.cfg` の `add_principal identifier.license:...` も設定しておくと、
`/evidencestashlogs` と `/evidencestashcoords` が使えるようになります。
license 識別子は一度接続するとサーバーコンソールに表示されます。

---

## ステップ 7: 座標を設定する

`config/shared.lua` の初期座標は **AI が仮置きした値**です。必ず差し替えてください。

1. 倉庫を置きたい場所に立つ
2. `/evidencestashcoords mission_row` を実行
3. サーバーコンソールに出力されたブロックを `config/shared.lua` の
   `SharedConfig.stashes` の該当箇所と差し替える
4. `restart as-evidencestash`

---

## ステップ 8: 動作テスト

リポジトリ README の「FXServer で確認すべきテスト項目」に沿って確認してください。
✅ が付いている項目はオフラインテストで機械的に確認済みなので、
**✅ が付いていない項目を優先**してください。

特に重要なもの:

| 項目 | 内容 |
|---|---|
| B-4 / B-5 | アイテムを預けて再起動 → 残っているか（**永続化**） |
| B-6 | 別プレイヤーで同じ中身が見えるか（**全体共有**） |
| A-3 / B-7 | DB にテーブルとログができているか |
| H-9 | 設定した座標で実際に開けるか |

---

## トラブルシューティング

| 症状 | 確認すること |
|---|---|
| stash の登録に失敗する | ensure の順序。ox_inventory のバージョン |
| TextUI が出ない | police grade 2 以上か。座標が正しいか |
| 「離れすぎています」が近くでも出る | `distanceTolerance` を大きくする（同期遅延） |
| コマンドが「権限がありません」 | `add_ace` と `add_principal` の設定 |
| ログが記録されない | oxmysql の接続。`logging.enabled` |
| キャラクターが作れない | txAdmin のレシピ適用が完了しているか |
