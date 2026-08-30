---@diagnostic disable: lowercase-global
--- as-evidencestash / 押収品倉庫
--- SharedConfig : クライアントとサーバーの両方が参照する定義。
--- ここに置いてよいのは「両側で同じ値を見る必要があるもの」だけです。
--- 報酬・数量・権限判定の最終決定は必ず server 側で行います (config/server.lua)。

SharedConfig = {}

-----------------------------------------------------------------------------
-- リソース識別
-----------------------------------------------------------------------------

--- イベント名の接頭辞。イベントは "as-evidencestash:side:actionName" 形式に統一します。
SharedConfig.eventPrefix = 'as-evidencestash'

--- ox_inventory に登録する stash ID の接頭辞。
--- 実際の stash ID は "evidence_stash_" .. (stashes のキー) になります。
--- 一度稼働させた後に変更すると、旧 ID に入っていたアイテムへ
--- アクセスできなくなるので変更しないでください。
SharedConfig.stashPrefix = 'evidence_stash_'

-----------------------------------------------------------------------------
-- 既定の権限・距離
-- 個々の倉庫 (SharedConfig.stashes) 側で上書きできます。
-----------------------------------------------------------------------------

--- 利用可能ジョブ。
SharedConfig.defaultJob = 'police'

--- 最低ランク (qb-core の job.grade.level と比較。この値以上で許可)。
SharedConfig.defaultMinGrade = 2

--- 操作距離 (m)。TextUI の表示と、サーバー側の距離検証の基準になります。
SharedConfig.defaultDistance = 2.0

-----------------------------------------------------------------------------
-- 倉庫の設置場所
-----------------------------------------------------------------------------
--- キー (mission_row など) は stash ID の一部になります。
--- 半角英数字とアンダースコアのみ、64文字以内にしてください。
--- 稼働後にキーを変更すると別の stash として扱われ、中身が見えなくなります。
---
--- 各項目:
---   label    : ox_inventory 上に表示される倉庫名
---   coords    : 設置座標 (vec3)
---   job       : 利用可能ジョブ (省略時 defaultJob)
---   minGrade  : 最低ランク (省略時 defaultMinGrade)
---   distance  : 操作距離 (省略時 defaultDistance)
---   showBlip  : マップにブリップを出すか (見た目は config/client.lua)
SharedConfig.stashes = {
    ['mission_row'] = {
        label = '押収品倉庫 (ミッションロウ警察署)',
        -- [AI提案] 実座標が未確定のため、ミッションロウ警察署の証拠品室付近を
        -- 仮の既定値として設定しています。必ず実サーバーで座標を取得し直して
        -- 差し替えてください。(/coords 等で取得した値に置き換える)
        coords = vec3(473.75, -996.5, 30.69),
        job = 'police',
        minGrade = 2,
        distance = 2.0,
        showBlip = true
    },

    -- 拠点を増やす場合はこの形式で追記してください。
    -- ['sandy_shores'] = {
    --     label = '押収品倉庫 (サンディショアーズ保安官事務所)',
    --     coords = vec3(1853.14, 3689.56, 34.27), -- [AI提案] 要調整
    --     job = 'police',
    --     minGrade = 2,
    --     distance = 2.0,
    --     showBlip = true
    -- },
}

-----------------------------------------------------------------------------
-- 表示文言 (日本語)
-----------------------------------------------------------------------------

SharedConfig.locale = {
    -- TextUI
    text_ui_open        = '[E] 押収品倉庫を開く',

    -- 成功
    notify_opened_title = '押収品倉庫',
    notify_opened       = '%s を開きました。',

    -- 失敗
    notify_error_title  = '押収品倉庫',
    err_no_job          = '警察官のみ利用できます。',
    err_no_grade        = '権限が不足しています。(必要ランク: %d 以上)',
    err_off_duty        = '勤務中でないため利用できません。',
    err_too_far         = '倉庫から離れすぎています。',
    err_unknown_stash   = 'この押収品倉庫は存在しません。',
    err_cooldown        = 'まだ利用できません。あと %d 秒お待ちください。',
    err_not_registered  = '押収品倉庫がまだ準備できていません。管理者に連絡してください。',
    err_generic         = '押収品倉庫を開けませんでした。'
}

-----------------------------------------------------------------------------
-- ヘルパー
-----------------------------------------------------------------------------

--- イベント名を組み立てる。
---@param side string 'client' | 'server'
---@param action string
---@return string
function SharedConfig.event(side, action)
    return ('%s:%s:%s'):format(SharedConfig.eventPrefix, side, action)
end

--- 文言を取得する (存在しないキーはキー名をそのまま返す)。
---@param key string
---@param ... any string.format に渡す引数
---@return string
function SharedConfig.text(key, ...)
    local line = SharedConfig.locale[key]
    if not line then return key end
    if select('#', ...) == 0 then return line end

    local ok, formatted = pcall(string.format, line, ...)
    return ok and formatted or line
end

--- 倉庫定義を取得する。入力値検証を兼ねる。
--- 不正な型・未登録キーの場合は nil を返します。
---@param key any クライアントから届く値なので型は信用しない
---@return table|nil stash
---@return string|nil stashKey
function SharedConfig.getStash(key)
    if type(key) ~= 'string' then return nil end
    if #key == 0 or #key > 64 then return nil end
    if key:find('[^%w_]') then return nil end

    local stash = SharedConfig.stashes[key]
    if type(stash) ~= 'table' then return nil end

    return stash, key
end

--- stash 定義から ox_inventory の stash ID を作る。
---@param key string
---@return string
function SharedConfig.stashId(key)
    return SharedConfig.stashPrefix .. key
end

--- 倉庫ごとの実効設定 (既定値を反映したもの) を返す。
---@param stash table
---@return string job
---@return number minGrade
---@return number distance
function SharedConfig.resolve(stash)
    return stash.job or SharedConfig.defaultJob,
        stash.minGrade or SharedConfig.defaultMinGrade,
        stash.distance or SharedConfig.defaultDistance
end
