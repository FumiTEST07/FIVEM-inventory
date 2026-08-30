--- as-evidencestash / 押収品倉庫
--- サーバー側。権限・距離・入力値・クールダウンのすべての判定を行います。
--- クライアントから受け取るのは「どの倉庫か」を示すキー文字列のみで、
--- stash ID・スロット数・重量・必要ランクはサーバーの設定からのみ決定します。

local QBCore = exports['qb-core']:GetCoreObject()

--- 登録済み stash。key -> stashId
local registered = {}

--- クールダウン管理。source -> os.time()
local cooldowns = {}

--- 現在開いている倉庫。source -> stashKey (閉じたときのログに使用)
local openedBy = {}

---@param message string
local function debugPrint(message)
    if not ServerConfig.debug then return end

    print('[as-evidencestash] ' .. message)
end

-----------------------------------------------------------------------------
-- stash の登録
-----------------------------------------------------------------------------

--- ox_inventory に共有 stash を登録する。
--- owner = false で全プレイヤー共有、groups でジョブとランクを渡すため、
--- ox_inventory 側でも独立して権限チェックが行われます (多層防御)。
local function registerStashes()
    registered = {}

    for key, stash in pairs(SharedConfig.stashes) do
        if not SharedConfig.getStash(key) then
            print(('[as-evidencestash] 倉庫キー "%s" が不正なため読み込みません。半角英数字とアンダースコアのみ、64文字以内で指定してください。')
                :format(tostring(key)))
        else
            local job, minGrade = SharedConfig.resolve(stash)
            local stashId = SharedConfig.stashId(key)

            local ok, err = pcall(function()
                exports.ox_inventory:RegisterStash(
                    stashId,
                    stash.label or key,
                    ServerConfig.slots,
                    ServerConfig.maxWeight,
                    false,                  -- owner: false = 全体共有
                    { [job] = minGrade },   -- groups: ox_inventory 側の権限チェック
                    stash.coords            -- coords: ox_inventory 側の距離チェック
                )
            end)

            if ok then
                registered[key] = stashId
                debugPrint(('倉庫 "%s" (%s) を登録しました。'):format(key, stashId))
            else
                print(('[as-evidencestash] 倉庫 "%s" の登録に失敗しました: %s')
                    :format(key, tostring(err)))
            end
        end
    end
end

-----------------------------------------------------------------------------
-- 検証
-----------------------------------------------------------------------------

--- ジョブとランクを検証する。
---@param player table qb-core Player
---@param stash table
---@return boolean allowed
---@return string|nil message 拒否理由 (日本語)
---@return string|nil reason ログ用の理由コード
local function validateJob(player, stash)
    local job, minGrade = SharedConfig.resolve(stash)
    local playerJob = player.PlayerData.job

    if not playerJob or playerJob.name ~= job then
        return false, SharedConfig.text('err_no_job'), 'no_job'
    end

    if ServerConfig.requireOnDuty and not playerJob.onduty then
        return false, SharedConfig.text('err_off_duty'), 'off_duty'
    end

    local grade = playerJob.grade and playerJob.grade.level or 0

    if grade < minGrade then
        return false, SharedConfig.text('err_no_grade', minGrade), 'no_grade'
    end

    return true
end

--- 倉庫との距離を検証する。
---@param src number
---@param stash table
---@return boolean allowed
---@return string|nil message
---@return string|nil reason
local function validateDistance(src, stash)
    local ped = GetPlayerPed(src)

    if ped == 0 then
        return false, SharedConfig.text('err_generic'), 'no_ped'
    end

    local _, _, interactDistance = SharedConfig.resolve(stash)
    local distance = #(GetEntityCoords(ped) - stash.coords)
    local allowedDistance = interactDistance + ServerConfig.distanceTolerance

    if distance > allowedDistance then
        return false, SharedConfig.text('err_too_far'),
            ('too_far:%.1fm'):format(distance)
    end

    return true
end

--- クールダウンを検証する。設定が 0 の場合は常に通過します。
---@param src number
---@return boolean allowed
---@return string|nil message
---@return string|nil reason
local function validateCooldown(src)
    local seconds = ServerConfig.cooldownSeconds

    if type(seconds) ~= 'number' or seconds <= 0 then
        return true
    end

    local last = cooldowns[src]
    local now = os.time()

    if last and (now - last) < seconds then
        local remaining = seconds - (now - last)
        return false, SharedConfig.text('err_cooldown', remaining), 'cooldown'
    end

    return true
end

-----------------------------------------------------------------------------
-- ログ
-----------------------------------------------------------------------------

---@param src number
---@param stashKey string
---@param action string
---@param detail string|nil
local function writeLog(src, stashKey, action, detail)
    if not ServerConfig.logging.enabled then return end

    local player = QBCore.Functions.GetPlayer(src)

    Storage.log({
        stashId = registered[stashKey] or SharedConfig.stashId(stashKey),
        stashKey = stashKey,
        citizenid = player and player.PlayerData.citizenid or nil,
        playerName = GetPlayerName(src) or 'unknown',
        identifier = GetPlayerIdentifierByType(src, 'license') or nil,
        action = action,
        detail = detail
    })
end

-----------------------------------------------------------------------------
-- 開錠リクエスト
-----------------------------------------------------------------------------

--- クライアントから倉庫キーを受け取り、すべての検証を行ってから
--- 開いてよいかどうかを返します。stash ID もここで決定して返すため、
--- クライアントが任意の stash を指定することはできません。
lib.callback.register(SharedConfig.event('server', 'requestOpen'), function(source, stashKey)
    local src = source

    -- 1. 入力値検証: 型・文字種・登録有無をすべて確認する
    local stash, key = SharedConfig.getStash(stashKey)

    if not stash or not key then
        debugPrint(('不正な倉庫キーを受信しました。source=%s value=%s')
            :format(src, tostring(stashKey)))

        return { success = false, message = SharedConfig.text('err_unknown_stash') }
    end

    -- 2. stash が ox_inventory に登録済みかを確認する
    local stashId = registered[key]

    if not stashId then
        return { success = false, message = SharedConfig.text('err_not_registered') }
    end

    -- 3. プレイヤーの存在確認
    local player = QBCore.Functions.GetPlayer(src)

    if not player then
        return { success = false, message = SharedConfig.text('err_generic') }
    end

    -- 4. 権限検証
    local allowed, message, reason = validateJob(player, stash)

    if not allowed then
        if ServerConfig.logging.logDenied then
            writeLog(src, key, 'denied', reason)
        end

        return { success = false, message = message }
    end

    -- 5. 距離検証
    allowed, message, reason = validateDistance(src, stash)

    if not allowed then
        if ServerConfig.logging.logDenied then
            writeLog(src, key, 'denied', reason)
        end

        return { success = false, message = message }
    end

    -- 6. クールダウン検証
    allowed, message, reason = validateCooldown(src)

    if not allowed then
        return { success = false, message = message }
    end

    cooldowns[src] = os.time()
    openedBy[src] = key

    writeLog(src, key, 'open', nil)
    debugPrint(('%s (id:%s) が倉庫 "%s" を開きました。'):format(GetPlayerName(src), src, key))

    return {
        success = true,
        stashId = stashId,
        label = stash.label or key
    }
end)

-----------------------------------------------------------------------------
-- 閉じたときのログ
-----------------------------------------------------------------------------

AddEventHandler('ox_inventory:closedInventory', function(playerId, inventoryId)
    local key = openedBy[playerId]

    if not key then return end
    if registered[key] ~= inventoryId then return end

    openedBy[playerId] = nil

    if ServerConfig.logging.logClose then
        writeLog(playerId, key, 'close', nil)
    end
end)

-----------------------------------------------------------------------------
-- 後始末
-----------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    local src = source

    cooldowns[src] = nil
    openedBy[src] = nil
end)

-----------------------------------------------------------------------------
-- 管理コマンド
-- ACE 権限 "as-evidencestash.logs" を持つ管理者、またはサーバーコンソールから
-- 直近のアクセス履歴を確認できます。
-- server.cfg 例: add_ace group.admin as-evidencestash.logs allow
-----------------------------------------------------------------------------

RegisterCommand('evidencestashlogs', function(source, args)
    local src = source

    if src ~= 0 and not IsPlayerAceAllowed(src, 'as-evidencestash.logs') then
        TriggerClientEvent(SharedConfig.event('client', 'notify'), src,
            '権限がありません。', 'error')
        return
    end

    if not ServerConfig.logging.enabled then
        print('[as-evidencestash] 監査ログは無効になっています。')
        return
    end

    local stashKey = args[1] and SharedConfig.getStash(args[1]) and args[1] or nil
    local rows = Storage.fetchRecent(stashKey, tonumber(args[2]) or 20)

    print(('[as-evidencestash] 直近のアクセス履歴 (%d 件)'):format(#rows))

    for i = 1, #rows do
        local row = rows[i]

        print(('  %s | %s (%s) | %s | %s | %s'):format(
            tostring(row.created_at),
            tostring(row.player_name),
            tostring(row.citizenid),
            tostring(row.stash_key or stashKey),
            tostring(row.action),
            tostring(row.detail or '-')
        ))
    end
end, false)

-----------------------------------------------------------------------------
-- 起動
-----------------------------------------------------------------------------

AddEventHandler('onServerResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        MySQL.ready(function()
            Storage.init()
        end)

        registerStashes()
    elseif resource == 'ox_inventory' then
        -- ox_inventory を再起動すると登録内容が失われるため、再登録します。
        registerStashes()
    end
end)
