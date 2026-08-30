-- as-evidencestash / 押収品倉庫
-- 静的検証 (luacheck) 用の設定。
-- 実行方法は README.md の「静的検証手順」を参照してください。

std = 'lua54'
max_line_length = 140

-- 未使用の self / 引数は FiveM のイベントハンドラで頻出するため許容します。
self = false
unused_args = false

-- FiveM / ox_lib / qb-core / oxmysql が実行時に提供するグローバル (読み取りのみ)
read_globals = {
    -- FiveM natives / API
    'AddBlipForCoord', 'AddEventHandler', 'AddTextComponentSubstringPlayerName',
    'BeginTextCommandSetBlipName', 'CreateThread', 'DoesBlipExist',
    'EndTextCommandSetBlipName', 'GetCurrentResourceName', 'GetEntityCoords',
    'GetPlayerIdentifierByType', 'GetPlayerName', 'GetPlayerPed',
    'IsControlJustReleased', 'IsPlayerAceAllowed', 'RegisterCommand',
    'RegisterNetEvent', 'RemoveBlip', 'SetBlipAsShortRange', 'SetBlipColour',
    'SetBlipDisplay', 'SetBlipScale', 'SetBlipSprite',
    'TriggerClientEvent', 'Wait', 'exports', 'source', 'vec3', 'vector3',

    -- fxmanifest
    'fx_version', 'game', 'lua54', 'name', 'description', 'author', 'version',
    'shared_scripts', 'client_scripts', 'server_scripts', 'dependencies',

    -- ライブラリ
    'lib', 'cache', 'MySQL',
}

-- このリソースが定義するグローバル
globals = {
    'SharedConfig', 'ClientConfig', 'ServerConfig', 'Storage',
}
