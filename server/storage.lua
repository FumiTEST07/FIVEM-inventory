--- as-evidencestash / 押収品倉庫
--- 監査ログ (アクセス履歴) の永続化。
---
--- 重要: 押収品アイテムそのものは ox_inventory が自身のテーブルに保存します。
--- ここで独自にアイテムを保存すると二重管理となり、
--- 中身の不整合やアイテム複製の原因になります。絶対に行わないでください。
--- このファイルが扱うのは「誰が・いつ・どの倉庫にアクセスしたか」だけです。

Storage = {}

local tableReady = false

--- 設定されたテーブル名を検証して返す。
--- テーブル名はプレースホルダにできないため、SQL に直接埋め込む前に
--- 英数字とアンダースコアのみであることを確認します。
---@return string|nil
local function safeTableName()
    local name = ServerConfig.logging.tableName

    if type(name) ~= 'string' or #name == 0 or #name > 64 or name:find('[^%w_]') then
        print(('[as-evidencestash] 不正なテーブル名です: %s'):format(tostring(name)))
        return nil
    end

    return name
end

-----------------------------------------------------------------------------
-- テーブル準備
-----------------------------------------------------------------------------

--- テーブルを作成し、保持期間を過ぎたログを削除する。
--- リソース起動時に一度だけ呼ばれます。
function Storage.init()
    if not ServerConfig.logging.enabled then return end

    local tbl = safeTableName()
    if not tbl then return end

    if not ServerConfig.logging.autoCreateTable then
        tableReady = true
        Storage.purge()
        return
    end

    local query = ([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `stash_id` VARCHAR(64) NOT NULL,
            `stash_key` VARCHAR(64) NOT NULL,
            `citizenid` VARCHAR(64) DEFAULT NULL,
            `player_name` VARCHAR(128) DEFAULT NULL,
            `identifier` VARCHAR(64) DEFAULT NULL,
            `action` VARCHAR(32) NOT NULL,
            `detail` VARCHAR(255) DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_stash_created` (`stash_id`, `created_at`),
            KEY `idx_citizenid` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]]):format(tbl)

    MySQL.query(query, {}, function(result)
        if result == nil then
            print('[as-evidencestash] 監査ログテーブルの作成に失敗しました。DB 設定を確認してください。')
            return
        end

        tableReady = true

        if ServerConfig.debug then
            print(('[as-evidencestash] 監査ログテーブル `%s` を準備しました。'):format(tbl))
        end

        Storage.purge()
    end)
end

-----------------------------------------------------------------------------
-- 記録
-----------------------------------------------------------------------------

--- アクセス履歴を 1 件記録する。
--- 非同期で実行するため、呼び出し側の処理をブロックしません。
--- ログの失敗が倉庫の利用を妨げないよう、エラーは出力のみ行います。
---@param entry table { stashId, stashKey, citizenid, playerName, identifier, action, detail }
function Storage.log(entry)
    if not ServerConfig.logging.enabled or not tableReady then return end

    local tbl = safeTableName()
    if not tbl then return end

    local query = ([[
        INSERT INTO `%s`
            (`stash_id`, `stash_key`, `citizenid`, `player_name`, `identifier`, `action`, `detail`)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]]):format(tbl)

    MySQL.insert(query, {
        entry.stashId,
        entry.stashKey,
        entry.citizenid,
        entry.playerName,
        entry.identifier,
        entry.action,
        entry.detail
    })
end

-----------------------------------------------------------------------------
-- 保持期間
-----------------------------------------------------------------------------

--- 保持期間を過ぎたログを削除する。
function Storage.purge()
    local days = ServerConfig.logging.retentionDays

    if type(days) ~= 'number' or days <= 0 then return end

    local tbl = safeTableName()
    if not tbl then return end

    local query = ([[
        DELETE FROM `%s` WHERE `created_at` < DATE_SUB(NOW(), INTERVAL ? DAY)
    ]]):format(tbl)

    MySQL.update(query, { math.floor(days) }, function(affected)
        if ServerConfig.debug and affected and affected > 0 then
            print(('[as-evidencestash] 古い監査ログを %d 件削除しました。'):format(affected))
        end
    end)
end

-----------------------------------------------------------------------------
-- 参照
-----------------------------------------------------------------------------

--- 直近のアクセス履歴を取得する (管理コマンド用)。
---@param stashKey string|nil 省略時は全倉庫
---@param limit number
---@return table
function Storage.fetchRecent(stashKey, limit)
    if not ServerConfig.logging.enabled or not tableReady then return {} end

    local tbl = safeTableName()
    if not tbl then return {} end

    limit = math.min(math.max(math.floor(tonumber(limit) or 20), 1), 200)

    if stashKey then
        local query = ([[
            SELECT `created_at`, `player_name`, `citizenid`, `action`, `detail`
            FROM `%s` WHERE `stash_key` = ?
            ORDER BY `id` DESC LIMIT %d
        ]]):format(tbl, limit)

        return MySQL.query.await(query, { stashKey }) or {}
    end

    local query = ([[
        SELECT `created_at`, `player_name`, `citizenid`, `stash_key`, `action`, `detail`
        FROM `%s`
        ORDER BY `id` DESC LIMIT %d
    ]]):format(tbl, limit)

    return MySQL.query.await(query, {}) or {}
end
