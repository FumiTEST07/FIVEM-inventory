--- as-evidencestash / 押収品倉庫
--- クライアント側の責務は次の 3 つだけです。
---   1. 倉庫の近くにいるかを監視して TextUI を出す
---   2. E キーの入力を受け取る
---   3. サーバーに「開いてよいか」を尋ね、許可されたら ox_inventory を開く
--- 権限・距離・クールダウンの判定結果はサーバーが返すものだけを信用します。
--- ここでのジョブ判定は TextUI を出すかどうかの見た目の制御にすぎません。

local QBCore = exports['qb-core']:GetCoreObject()

local playerJob = nil          --- @type table|nil qb-core の PlayerData.job
local textUIVisible = false
local requestInFlight = false  --- 多重送信の防止
local blips = {}

-----------------------------------------------------------------------------
-- 通知
-----------------------------------------------------------------------------

---@param message string
---@param notifyType string 'success' | 'error' | 'inform'
---@param title string|nil
local function notify(message, notifyType, title)
    lib.notify({
        id = 'as_evidencestash',
        title = title or SharedConfig.text('notify_error_title'),
        description = message,
        type = notifyType or 'inform',
        position = ClientConfig.notify.position,
        duration = ClientConfig.notify.duration
    })
end

-----------------------------------------------------------------------------
-- TextUI
-----------------------------------------------------------------------------

local function showTextUI()
    if textUIVisible then return end
    textUIVisible = true

    lib.showTextUI(SharedConfig.text('text_ui_open'), {
        position = ClientConfig.textUI.position,
        icon = ClientConfig.textUI.icon,
        iconColor = ClientConfig.textUI.iconColor
    })
end

local function hideTextUI()
    if not textUIVisible then return end
    textUIVisible = false

    lib.hideTextUI()
end

-----------------------------------------------------------------------------
-- ジョブ状態 (TextUI の事前フィルタ用)
-----------------------------------------------------------------------------

--- 見た目の制御にのみ使う簡易判定。サーバーの判定を置き換えるものではありません。
---@param stash table
---@return boolean
local function looksEligible(stash)
    if not ClientConfig.hideTextUIWithoutJob then return true end
    if not playerJob then return false end

    local job, minGrade = SharedConfig.resolve(stash)
    if playerJob.name ~= job then return false end

    local grade = playerJob.grade and playerJob.grade.level or 0
    return grade >= minGrade
end

local function refreshJob()
    local data = QBCore.Functions.GetPlayerData()
    playerJob = data and data.job or nil
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    refreshJob()
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    playerJob = job
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    playerJob = nil
    hideTextUI()
end)

-----------------------------------------------------------------------------
-- ブリップ
-----------------------------------------------------------------------------

local function createBlips()
    if not ClientConfig.blip.enabled then return end

    for _, stash in pairs(SharedConfig.stashes) do
        if stash.showBlip then
            local blip = AddBlipForCoord(stash.coords.x, stash.coords.y, stash.coords.z)

            SetBlipSprite(blip, ClientConfig.blip.sprite)
            SetBlipColour(blip, ClientConfig.blip.color)
            SetBlipScale(blip, ClientConfig.blip.scale + 0.0)
            SetBlipDisplay(blip, ClientConfig.blip.display)
            SetBlipAsShortRange(blip, ClientConfig.blip.shortRange)

            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(ClientConfig.blip.label)
            EndTextCommandSetBlipName(blip)

            blips[#blips + 1] = blip
        end
    end
end

local function removeBlips()
    for i = 1, #blips do
        if DoesBlipExist(blips[i]) then
            RemoveBlip(blips[i])
        end
    end
    blips = {}
end

-----------------------------------------------------------------------------
-- 倉庫を開く
-----------------------------------------------------------------------------

--- サーバーに許可を求め、許可された場合のみ ox_inventory を開きます。
--- 送信するのは倉庫のキーだけで、stash ID・容量・権限は一切送りません。
---@param stashKey string
local function requestOpen(stashKey)
    if requestInFlight then return end
    requestInFlight = true

    local response = lib.callback.await(
        SharedConfig.event('server', 'requestOpen'), false, stashKey
    )

    requestInFlight = false

    if type(response) ~= 'table' then
        notify(SharedConfig.text('err_generic'), 'error')
        return
    end

    if not response.success then
        notify(response.message or SharedConfig.text('err_generic'), 'error')
        return
    end

    -- stash ID はサーバーが決定した値を使います。
    hideTextUI()
    exports.ox_inventory:openInventory('stash', response.stashId)

    notify(
        SharedConfig.text('notify_opened', response.label or ''),
        'success',
        SharedConfig.text('notify_opened_title')
    )
end

-----------------------------------------------------------------------------
-- 距離監視ループ
-----------------------------------------------------------------------------

--- 最も近い倉庫を返す。
---@param coords vector3
---@return string|nil key
---@return table|nil stash
---@return number distance
local function findNearest(coords)
    local nearestKey, nearestStash
    local nearestDist = math.huge

    for key, stash in pairs(SharedConfig.stashes) do
        local dist = #(coords - stash.coords)

        if dist < nearestDist then
            nearestDist = dist
            nearestKey = key
            nearestStash = stash
        end
    end

    return nearestKey, nearestStash, nearestDist
end

CreateThread(function()
    refreshJob()
    createBlips()

    while true do
        local wait = ClientConfig.loop.idleInterval
        local coords = GetEntityCoords(cache.ped)
        local key, stash, dist = findNearest(coords)

        if stash and dist <= ClientConfig.loop.checkRadius then
            wait = ClientConfig.loop.nearInterval

            local _, _, interactDistance = SharedConfig.resolve(stash)

            if dist <= interactDistance and looksEligible(stash) then
                -- 操作距離内では入力を取りこぼさないよう毎フレーム処理します。
                wait = 0
                showTextUI()

                if IsControlJustReleased(0, ClientConfig.openControl) then
                    requestOpen(key)
                end
            else
                hideTextUI()
            end
        else
            hideTextUI()
        end

        Wait(wait)
    end
end)

-----------------------------------------------------------------------------
-- サーバーからの通知
-----------------------------------------------------------------------------

RegisterNetEvent(SharedConfig.event('client', 'notify'), function(message, notifyType)
    if type(message) ~= 'string' then return end

    notify(message, notifyType)
end)

-----------------------------------------------------------------------------
-- 後始末
-----------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    hideTextUI()
    removeBlips()
end)
