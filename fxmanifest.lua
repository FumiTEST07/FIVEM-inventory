fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'as-evidencestash'
description '押収品倉庫 / Evidence Stash for qb-core + ox_inventory'
author 'as'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/shared.lua'
}

client_scripts {
    'config/client.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config/server.lua',
    'server/storage.lua',
    'server/main.lua'
}

dependencies {
    'qb-core',
    'ox_lib',
    'oxmysql',
    'ox_inventory'
}
