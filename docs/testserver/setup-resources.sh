#!/usr/bin/env bash
#
# as-evidencestash のテストに必要なリソースを、既存の QBCore サーバーに配置します。
#
#   使い方: ./setup-resources.sh /path/to/server-data
#
# ox_lib / oxmysql / ox_inventory の「ビルド済みリリース zip」を GitHub から取得し、
# as-evidencestash を clone して resources 配下に配置します。
#
# ox_lib / ox_inventory / oxmysql はリポジトリを直接 ZIP ダウンロードすると
# UI がビルドされておらず動きません。このスクリプトは必ず Releases の
# ビルド済み zip を取得します。
#
# qb-core 本体はインストールしません。txAdmin の QBCore レシピなどで
# 土台を作った後に実行してください。
#
# 注意: このスクリプトは Claude が作成しましたが、実際の FXServer 環境では
#       未実行です。実行前に内容を確認してください。

set -euo pipefail

OX_RESOURCES=(ox_lib oxmysql ox_inventory)
EVIDENCE_REPO="https://github.com/FumiTEST07/FIVEM-inventory.git"

step() { printf '\033[36m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m    OK: %s\033[0m\n' "$1"; }
warn() { printf '\033[33m    !!  %s\033[0m\n' "$1"; }
die()  { printf '\033[31mエラー: %s\033[0m\n' "$1" >&2; exit 1; }

# 事前チェック --------------------------------------------------------------

[ $# -ge 1 ] || die "server-data のパスを指定してください: $0 /path/to/server-data"

SERVER_DATA="$1"

[ -d "$SERVER_DATA" ] || die "server-data が見つかりません: $SERVER_DATA"
[ -f "$SERVER_DATA/server.cfg" ] || warn "server.cfg が見つかりません（処理は続行します）"
[ -d "$SERVER_DATA/resources" ] || die "resources フォルダが見つかりません: $SERVER_DATA/resources"

for cmd in git curl unzip; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd が見つかりません。インストールしてください。"
done

# jq があれば使い、無ければ grep で代替します
if command -v jq >/dev/null 2>&1; then
    HAS_JQ=1
else
    HAS_JQ=0
    warn "jq が見つかりません。簡易パースで代替します。"
fi

OX_DIR="$SERVER_DATA/resources/[ox]"
LOCAL_DIR="$SERVER_DATA/resources/[local]"

mkdir -p "$OX_DIR" "$LOCAL_DIR"

# ox 系リソースの取得 -------------------------------------------------------

for name in "${OX_RESOURCES[@]}"; do
    step "$name の最新リリースを取得"

    target="$OX_DIR/$name"

    if [ -e "$target" ]; then
        warn "$target は既に存在します。スキップします（更新したい場合は手動で削除してください）"
        continue
    fi

    api="https://api.github.com/repos/overextended/$name/releases/latest"
    json="$(curl -fsSL -H 'User-Agent: as-evidencestash-setup' "$api")" \
        || die "$name のリリース情報を取得できませんでした"

    if [ "$HAS_JQ" -eq 1 ]; then
        url="$(printf '%s' "$json" | jq -r '[.assets[] | select(.name | endswith(".zip"))][0].browser_download_url // empty')"
        tag="$(printf '%s' "$json" | jq -r '.tag_name // "?"')"
    else
        url="$(printf '%s' "$json" | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
        tag='?'
    fi

    if [ -z "$url" ]; then
        warn "$name のリリースに zip が見つかりませんでした。手動で導入してください: https://github.com/overextended/$name/releases"
        continue
    fi

    echo "    $tag / $(basename "$url")"

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    curl -fsSL -o "$tmp/res.zip" "$url" || die "$name のダウンロードに失敗しました"
    unzip -q "$tmp/res.zip" -d "$tmp/extracted"

    # zip の中身は「リソース名のフォルダ 1 つ」か、直下にファイルが並ぶかの
    # どちらかです。fxmanifest.lua の位置から実体を判定します。
    manifest="$(find "$tmp/extracted" -name fxmanifest.lua -type f \
        | awk '{ print length($0), $0 }' | sort -n | head -1 | cut -d' ' -f2-)"

    if [ -z "$manifest" ]; then
        warn "$name: zip 内に fxmanifest.lua が見つかりません。手動で導入してください。"
        rm -rf "$tmp"; trap - EXIT
        continue
    fi

    cp -r "$(dirname "$manifest")" "$target"
    ok "$name → $target"

    rm -rf "$tmp"; trap - EXIT
done

# as-evidencestash の取得 ---------------------------------------------------

step "as-evidencestash を取得"

EVIDENCE_TARGET="$LOCAL_DIR/as-evidencestash"

if [ -d "$EVIDENCE_TARGET/.git" ]; then
    warn "$EVIDENCE_TARGET は既に存在します。git pull で更新します。"
    git -C "$EVIDENCE_TARGET" pull
elif [ -e "$EVIDENCE_TARGET" ]; then
    die "$EVIDENCE_TARGET が git リポジトリではない状態で存在します。中身を確認してください。"
else
    # フォルダ名は必ず as-evidencestash にする必要があります
    git clone "$EVIDENCE_REPO" "$EVIDENCE_TARGET"
    ok "as-evidencestash → $EVIDENCE_TARGET"
fi

# 結果表示 -----------------------------------------------------------------

echo
step "完了。次にやること"
cat <<MSG
  1. server.cfg に docs/testserver/server.cfg.snippet の内容を追記
     ($EVIDENCE_TARGET/docs/testserver/server.cfg.snippet)

  2. basic-gamemode / fivem-map-skater が有効なら削除（qb-core と競合します）

  3. サーバーを起動し、コンソールに次の 2 行が出るか確認
       [as-evidencestash] 監査ログテーブル \`as_evidencestash_logs\` を準備しました。
       [as-evidencestash] 倉庫 "mission_row" (evidence_stash_mission_row) を登録しました。

  4. ゲーム内で /setjob <自分のID> police 2 を実行

  5. 倉庫を置きたい場所で /evidencestashcoords mission_row を実行し、
     出力を config/shared.lua に反映して restart as-evidencestash
MSG
