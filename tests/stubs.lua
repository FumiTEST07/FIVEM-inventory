--- as-evidencestash / テスト用スタブ
---
--- FXServer を起動せずに server/main.lua の検証ロジックを実行するため、
--- FiveM ネイティブ・ox_lib・qb-core・oxmysql の最小限の代替を提供します。
---
--- これは「本物の実行環境」ではありません。ここで通ることは
--- ライブ FXServer 上での動作を保証しません。
--- あくまで検証ロジック (権限・距離・入力値・クールダウン) を
--- 机上で確認するためのものです。

local M = {}

--- テスト中に発生した副作用の記録
M.state = {
    players = {},          -- src -> qb-core Player 相当
    pedCoords = {},        -- src -> vector3
    registeredStashes = {},-- 呼ばれた RegisterStash の引数
    logs = {},             -- Storage.log に渡された内容
    notifications = {},    -- TriggerClientEvent の内容
    prints = {},           -- print されたメッセージ
    callbacks = {},        -- lib.callback.register されたもの
    eventHandlers = {},    -- AddEventHandler されたもの
    aceAllowed = {},       -- src -> boolean
    now = 1000,            -- os.time() の戻り値 (テストから進められる)
}

local S = M.state

-----------------------------------------------------------------------------
-- vector3
-- FiveM の vector3 は加減算と長さ演算子 (#) をサポートします。
-----------------------------------------------------------------------------

local vecmt = {}
vecmt.__index = vecmt

function vecmt.__sub(a, b)
    return M.vec3(a.x - b.x, a.y - b.y, a.z - b.z)
end

function vecmt.__add(a, b)
    return M.vec3(a.x + b.x, a.y + b.y, a.z + b.z)
end

function vecmt.__len(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

function vecmt.__tostring(v)
    return ('vec3(%.2f, %.2f, %.2f)'):format(v.x, v.y, v.z)
end

function M.vec3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vecmt)
end

-----------------------------------------------------------------------------
-- 環境を組み立てる
-----------------------------------------------------------------------------

function M.install()
    -- グローバルな vec3 / vector3
    _G.vec3 = M.vec3
    _G.vector3 = M.vec3

    -- os.time をテストから制御できるようにする
    local realTime = os.time
    M.realTime = realTime
    os.time = function() return S.now end

    -- FiveM ネイティブ ------------------------------------------------------

    _G.GetCurrentResourceName = function() return 'as-evidencestash' end

    _G.GetPlayerPed = function(src)
        return S.pedCoords[src] and src or 0
    end

    _G.GetEntityCoords = function(ped)
        return S.pedCoords[ped] or M.vec3(0, 0, 0)
    end

    _G.GetPlayerName = function(src)
        local p = S.players[src]
        return p and p.name or ('player_' .. tostring(src))
    end

    _G.GetPlayerIdentifierByType = function(src, kind)
        return ('%s:test%s'):format(kind, tostring(src))
    end

    _G.IsPlayerAceAllowed = function(src)
        return S.aceAllowed[src] == true
    end

    _G.TriggerClientEvent = function(event, src, message, kind)
        S.notifications[#S.notifications + 1] = {
            event = event, src = src, message = message, kind = kind
        }
    end

    _G.RegisterCommand = function(name, handler)
        S.commands = S.commands or {}
        S.commands[name] = handler
    end

    _G.AddEventHandler = function(event, handler)
        S.eventHandlers[event] = S.eventHandlers[event] or {}
        table.insert(S.eventHandlers[event], handler)
    end

    _G.RegisterNetEvent = _G.AddEventHandler
    _G.CreateThread = function(fn) return fn end
    _G.Wait = function() end

    -- print を記録しつつ黙らせる
    M.realPrint = print
    _G.print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do
            parts[#parts + 1] = tostring((select(i, ...)))
        end
        S.prints[#S.prints + 1] = table.concat(parts, ' ')
    end

    -- exports --------------------------------------------------------------

    -- exports.ox_inventory:RegisterStash(...) と
    -- exports['qb-core']:GetCoreObject() の両方の書き方に対応します。
    local resources = {
        ox_inventory = {
            RegisterStash = function(_, id, label, slots, maxWeight, owner, groups, coords)
                S.registeredStashes[id] = {
                    id = id, label = label, slots = slots,
                    maxWeight = maxWeight, owner = owner,
                    groups = groups, coords = coords
                }
            end
        },
        ['qb-core'] = {
            GetCoreObject = function()
                return M.QBCore
            end
        }
    }

    _G.exports = setmetatable({}, {
        __index = function(_, resource)
            return resources[resource] or {}
        end,
        __call = function(_, resource)
            return resources[resource] or {}
        end
    })

    -- qb-core --------------------------------------------------------------

    M.QBCore = {
        Functions = {
            GetPlayer = function(src) return S.players[src] end,
            GetPlayerData = function() return nil end
        }
    }

    -- ox_lib ---------------------------------------------------------------

    _G.lib = {
        callback = {
            register = function(name, fn)
                S.callbacks[name] = fn
            end
        }
    }

    -- oxmysql --------------------------------------------------------------
    -- storage.lua は差し替えるため最低限のみ

    -- MySQL.query は関数としても MySQL.query.await としても呼べる必要があるため、
    -- __call を持つテーブルにしています (oxmysql と同じ形)。
    local mysqlQuery = setmetatable(
        { await = function() return {} end },
        { __call = function(_, _, _, cb) if cb then cb({}) end end }
    )

    _G.MySQL = {
        ready = function(fn) fn() end,
        query = mysqlQuery,
        insert = function() end,
        update = function(_, _, cb) if cb then cb(0) end end,
    }

    -- Storage --------------------------------------------------------------
    -- DB は使わず、記録内容だけを配列に貯めます。

    _G.Storage = {
        init = function() end,
        purge = function() end,
        fetchRecent = function() return {} end,
        log = function(entry)
            S.logs[#S.logs + 1] = entry
        end
    }
end

-----------------------------------------------------------------------------
-- テスト補助
-----------------------------------------------------------------------------

--- プレイヤーを作る
---@param src number
---@param opts table { job, grade, onduty, coords, citizenid, name }
function M.addPlayer(src, opts)
    opts = opts or {}

    S.players[src] = {
        name = opts.name or ('player_' .. src),
        PlayerData = {
            citizenid = opts.citizenid or ('CID' .. src),
            job = {
                name = opts.job or 'police',
                onduty = opts.onduty ~= false,
                grade = { level = opts.grade or 2 }
            }
        }
    }

    S.pedCoords[src] = opts.coords or M.vec3(473.75, -996.5, 30.69)
end

--- 記録をリセットする (プレイヤーは残す)
function M.resetRecords()
    S.logs = {}
    S.notifications = {}
    S.prints = {}
end

--- 登録済みコールバックを呼ぶ
function M.callback(name, src, ...)
    local fn = S.callbacks[name]
    assert(fn, '未登録のコールバック: ' .. name)
    return fn(src, ...)
end

--- 登録済みイベントを発火する
function M.fire(event, ...)
    local handlers = S.eventHandlers[event]
    if not handlers then return end

    for i = 1, #handlers do handlers[i](...) end
end

--- 最後に記録されたログを返す
function M.lastLog()
    return S.logs[#S.logs]
end

return M
