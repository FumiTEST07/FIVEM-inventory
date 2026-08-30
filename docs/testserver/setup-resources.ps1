<#
.SYNOPSIS
    as-evidencestash のテストに必要なリソースを、既存の QBCore サーバーに配置します。

.DESCRIPTION
    ox_lib / oxmysql / ox_inventory の「ビルド済みリリース zip」を GitHub から取得し、
    as-evidencestash を clone して、指定した server-data の resources 配下に配置します。

    ox_lib / ox_inventory / oxmysql はリポジトリを直接 ZIP ダウンロードすると
    UI がビルドされておらず動きません。このスクリプトは必ず Releases の
    ビルド済み zip を取得します。

    qb-core 本体はインストールしません。txAdmin の QBCore レシピなどで
    土台を作った後に実行してください。

.PARAMETER ServerData
    server.cfg がある server-data フォルダのパス。

.EXAMPLE
    .\setup-resources.ps1 -ServerData "C:\FXServer\server-data"

.NOTES
    このスクリプトは Claude が作成しましたが、実際の Windows 環境では未実行です。
    実行前に -WhatIf で内容を確認することを推奨します。
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerData
)

$ErrorActionPreference = 'Stop'

# 取得するリソース
$OxResources = @('ox_lib', 'oxmysql', 'ox_inventory')
$EvidenceRepo = 'https://github.com/FumiTEST07/FIVEM-inventory.git'

# ---------------------------------------------------------------------------

function Write-Step { param($Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param($Message) Write-Host "    OK: $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "    !!  $Message" -ForegroundColor Yellow }

# 事前チェック -------------------------------------------------------------

if (-not (Test-Path $ServerData)) {
    throw "server-data が見つかりません: $ServerData"
}

$cfgPath = Join-Path $ServerData 'server.cfg'
if (-not (Test-Path $cfgPath)) {
    Write-Warn "server.cfg が見つかりません: $cfgPath"
    Write-Warn "パスが正しいか確認してください（処理は続行します）"
}

$resourcesRoot = Join-Path $ServerData 'resources'
if (-not (Test-Path $resourcesRoot)) {
    throw "resources フォルダが見つかりません: $resourcesRoot"
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git が見つかりません。https://git-scm.com/ からインストールしてください。"
}

$oxDir = Join-Path $resourcesRoot '[ox]'
$localDir = Join-Path $resourcesRoot '[local]'

foreach ($dir in @($oxDir, $localDir)) {
    if (-not (Test-Path $dir)) {
        if ($PSCmdlet.ShouldProcess($dir, 'フォルダ作成')) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Ok "作成: $dir"
        }
    }
}

# ox 系リソースの取得 -------------------------------------------------------

foreach ($name in $OxResources) {
    Write-Step "$name の最新リリースを取得"

    $target = Join-Path $oxDir $name

    if (Test-Path $target) {
        Write-Warn "$target は既に存在します。スキップします（更新したい場合は手動で削除してください）"
        continue
    }

    # 最新リリースの zip アセットを探す。
    # これらのリポジトリはリリースごとに zip を 1 つだけ公開しています。
    $api = "https://api.github.com/repos/overextended/$name/releases/latest"
    $release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'as-evidencestash-setup' }

    $asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1

    if (-not $asset) {
        Write-Warn "$name のリリースに zip が見つかりませんでした。手動で導入してください: https://github.com/overextended/$name/releases"
        continue
    }

    Write-Host "    $($release.tag_name) / $($asset.name)"

    if (-not $PSCmdlet.ShouldProcess($target, "ダウンロードして展開")) { continue }

    $tmpZip = Join-Path $env:TEMP "$name-$([guid]::NewGuid()).zip"
    $tmpDir = Join-Path $env:TEMP "$name-$([guid]::NewGuid())"

    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpZip
        Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

        # zip の中身は「リソース名のフォルダ 1 つ」か、直下にファイルが並ぶかの
        # どちらかです。fxmanifest.lua の位置から実体を判定します。
        $manifest = Get-ChildItem -Path $tmpDir -Filter 'fxmanifest.lua' -Recurse -File |
                    Sort-Object { $_.FullName.Length } | Select-Object -First 1

        if (-not $manifest) {
            Write-Warn "$name: zip 内に fxmanifest.lua が見つかりません。手動で導入してください。"
            continue
        }

        Copy-Item -Path $manifest.Directory.FullName -Destination $target -Recurse -Force
        Write-Ok "$name → $target"
    }
    finally {
        Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# as-evidencestash の取得 ---------------------------------------------------

Write-Step "as-evidencestash を取得"

$evidenceTarget = Join-Path $localDir 'as-evidencestash'

if (Test-Path $evidenceTarget) {
    Write-Warn "$evidenceTarget は既に存在します。git pull で更新します。"
    if ($PSCmdlet.ShouldProcess($evidenceTarget, 'git pull')) {
        git -C $evidenceTarget pull
    }
}
else {
    if ($PSCmdlet.ShouldProcess($evidenceTarget, 'git clone')) {
        # フォルダ名は必ず as-evidencestash にする必要があります
        git clone $EvidenceRepo $evidenceTarget
        Write-Ok "as-evidencestash → $evidenceTarget"
    }
}

# 結果表示 -----------------------------------------------------------------

Write-Host ""
Write-Step "完了。次にやること"
Write-Host @"
  1. server.cfg に docs/testserver/server.cfg.snippet の内容を追記
     ($evidenceTarget\docs\testserver\server.cfg.snippet)

  2. basic-gamemode / fivem-map-skater が有効なら削除（qb-core と競合します）

  3. サーバーを起動し、コンソールに次の 2 行が出るか確認
       [as-evidencestash] 監査ログテーブル ``as_evidencestash_logs`` を準備しました。
       [as-evidencestash] 倉庫 "mission_row" (evidence_stash_mission_row) を登録しました。

  4. ゲーム内で /setjob <自分のID> police 2 を実行

  5. 倉庫を置きたい場所で /evidencestashcoords mission_row を実行し、
     出力を config/shared.lua に反映して restart as-evidencestash
"@ -ForegroundColor Gray
