--- as-evidencestash / オフライン検証テスト
---
--- FXServer を起動せずに server/main.lua の検証ロジックを実行します。
--- README の「FXServer で確認すべきテスト項目」のうち、
--- C (権限) / D (距離) / E (入力値) / F (クールダウン) と
--- A (起動時の登録) の一部を机上で確認します。
---
--- 実行:  cd <リソースのルート> && lua5.4 tests/run.lua
---
--- 【重要】
--- このテストは FiveM ネイティブ・ox_lib・qb-core・oxmysql を
--- スタブに差し替えて動かしています。ここが全て通っても
--- ライブ FXServer 上での動作を保証するものではありません。
--- 実サーバーでの確認は別途必要です (README 参照)。

package.path = './?.lua;' .. package.path

local stubs = require('tests.stubs')
stubs.install()

-- 実際のリソースコードを読み込む (テスト用の複製ではなく本物)
dofile('config/shared.lua')
dofile('config/server.lua')
dofile('server/main.lua')

local S = stubs.state
local CB = SharedConfig.event('server', 'requestOpen')

-----------------------------------------------------------------------------
-- 簡易テストフレームワーク
-----------------------------------------------------------------------------

local passed, failed = 0, 0

local function group(name)
    stubs.realPrint(('\n--- %s ---'):format(name))
end

local function check(name, ok, detail)
    if ok then
        passed = passed + 1
        stubs.realPrint(('  [PASS] %s'):format(name))
    else
        failed = failed + 1
        stubs.realPrint(('  [FAIL] %s%s'):format(name, detail and ('\n         → ' .. tostring(detail)) or ''))
    end
end

local function eq(name, actual, expected)
    check(name, actual == expected,
        ('期待値: %s / 実際: %s'):format(tostring(expected), tostring(actual)))
end

-----------------------------------------------------------------------------
-- A. 起動時の stash 登録
-----------------------------------------------------------------------------

group('A. 起動時の stash 登録')

stubs.fire('onServerResourceStart', 'as-evidencestash')

local reg = S.registeredStashes['evidence_stash_mission_row']

check('A-1 stash ID "evidence_stash_mission_row" が登録された', reg ~= nil)

if reg then
    eq('A-2 スロット数が ServerConfig の 100', reg.slots, 100)
    eq('A-3 最大重量が ServerConfig の 500000', reg.maxWeight, 500000)
    eq('A-4 owner=false (全体共有)', reg.owner, false)
    eq('A-5 groups に police=2 が渡されている', reg.groups and reg.groups.police, 2)
    check('A-6 coords が渡されている (ox_inventory 側の距離チェック用)', reg.coords ~= nil)
    eq('A-7 label が SharedConfig の値', reg.label, SharedConfig.stashes.mission_row.label)
end

-----------------------------------------------------------------------------
-- B. 正常系
-----------------------------------------------------------------------------

group('B. 正常系')

stubs.addPlayer(1, { job = 'police', grade = 2 })
stubs.resetRecords()

local res = stubs.callback(CB, 1, 'mission_row')

eq('B-1 success = true', res.success, true)
eq('B-2 stashId はサーバーが決定した値', res.stashId, 'evidence_stash_mission_row')
eq('B-3 label が返る', res.label, SharedConfig.stashes.mission_row.label)
eq('B-4 監査ログに open が記録された', stubs.lastLog() and stubs.lastLog().action, 'open')
eq('B-5 ログに citizenid が入っている', stubs.lastLog() and stubs.lastLog().citizenid, 'CID1')

-- 閉じたときのログ
stubs.resetRecords()
stubs.fire('ox_inventory:closedInventory', 1, 'evidence_stash_mission_row')
eq('B-6 閉じると close が記録される', stubs.lastLog() and stubs.lastLog().action, 'close')

-- grade 3 (最低ランク超え) も通ること
stubs.addPlayer(2, { job = 'police', grade = 3 })
eq('B-7 grade 3 (最低ランク超え) も許可される',
    stubs.callback(CB, 2, 'mission_row').success, true)

-----------------------------------------------------------------------------
-- C. 権限 (拒否系)
-----------------------------------------------------------------------------

group('C. 権限')

-- C-3: police grade 1 がクライアントから直接コールバックを呼ぶ
stubs.addPlayer(10, { job = 'police', grade = 1 })
stubs.resetRecords()
res = stubs.callback(CB, 10, 'mission_row')

eq('C-3a grade 1 は拒否される', res.success, false)
eq('C-3b 日本語メッセージが返る', res.message, SharedConfig.text('err_no_grade', 2))
check('C-3c stashId を返さない', res.stashId == nil)
eq('C-3d ログに denied が記録される', stubs.lastLog() and stubs.lastLog().action, 'denied')
eq('C-3e 拒否理由が no_grade', stubs.lastLog() and stubs.lastLog().detail, 'no_grade')

-- C-4: 無職
stubs.addPlayer(11, { job = 'unemployed', grade = 5 })
stubs.resetRecords()
res = stubs.callback(CB, 11, 'mission_row')

eq('C-4a 他ジョブは grade が高くても拒否される', res.success, false)
eq('C-4b メッセージが「警察官のみ」', res.message, SharedConfig.text('err_no_job'))
eq('C-4c 拒否理由が no_job', stubs.lastLog() and stubs.lastLog().detail, 'no_job')

-- C-5: requireOnDuty
ServerConfig.requireOnDuty = true
stubs.addPlayer(12, { job = 'police', grade = 2, onduty = false })
stubs.resetRecords()
res = stubs.callback(CB, 12, 'mission_row')

eq('C-5a requireOnDuty=true でオフデューティは拒否される', res.success, false)
eq('C-5b メッセージが「勤務中でない」', res.message, SharedConfig.text('err_off_duty'))
eq('C-5c 拒否理由が off_duty', stubs.lastLog() and stubs.lastLog().detail, 'off_duty')

ServerConfig.requireOnDuty = false
eq('C-5d requireOnDuty=false に戻すとオフデューティでも許可される',
    stubs.callback(CB, 12, 'mission_row').success, true)

-- 存在しないプレイヤー
res = stubs.callback(CB, 999, 'mission_row')
eq('C-6 未登録の source は拒否される', res.success, false)

-----------------------------------------------------------------------------
-- D. 距離
-----------------------------------------------------------------------------

group('D. 距離')

local base = SharedConfig.stashes.mission_row.coords

-- D-2: 50m 離れた位置から直接コールバックを呼ぶ
stubs.addPlayer(20, { job = 'police', grade = 2, coords = stubs.vec3(base.x + 50, base.y, base.z) })
stubs.resetRecords()
res = stubs.callback(CB, 20, 'mission_row')

eq('D-2a 50m 離れていると拒否される', res.success, false)
eq('D-2b メッセージが「離れすぎ」', res.message, SharedConfig.text('err_too_far'))
check('D-2c 拒否理由に距離が入る',
    (stubs.lastLog() and stubs.lastLog().detail or ''):match('^too_far:') ~= nil,
    stubs.lastLog() and stubs.lastLog().detail)

-- 境界: 操作距離 2.0m + 許容 3.0m = 5.0m
stubs.addPlayer(21, { job = 'police', grade = 2, coords = stubs.vec3(base.x + 4.0, base.y, base.z) })
eq('D-4 許容範囲内 (4.0m < 2.0+3.0) は許可される',
    stubs.callback(CB, 21, 'mission_row').success, true)

stubs.addPlayer(22, { job = 'police', grade = 2, coords = stubs.vec3(base.x + 6.0, base.y, base.z) })
eq('D-5 許容範囲外 (6.0m > 2.0+3.0) は拒否される',
    stubs.callback(CB, 22, 'mission_row').success, false)

-- ped が存在しない場合
S.pedCoords[23] = nil
stubs.addPlayer(23, { job = 'police', grade = 2 })
S.pedCoords[23] = nil
res = stubs.callback(CB, 23, 'mission_row')
eq('D-6 ped が取得できない場合は拒否される', res.success, false)

-----------------------------------------------------------------------------
-- E. 入力値
-----------------------------------------------------------------------------

group('E. 入力値')

stubs.addPlayer(30, { job = 'police', grade = 2 })

local badInputs = {
    { 'E-1 存在しないキー',            'fake_stash' },
    { 'E-2a 数値',                     123 },
    { 'E-2b テーブル',                 { evil = true } },
    { 'E-2c nil',                      nil },
    { 'E-2d 真偽値',                   true },
    { 'E-3a SQL 文字列',               "a'; DROP TABLE x;--" },
    { 'E-3b パストラバーサル',         '../../etc/passwd' },
    { 'E-3c ハイフン入り',             'mission-row' },
    { 'E-3d 空白入り',                 'mission row' },
    { 'E-4a 空文字',                   '' },
    { 'E-4b 65 文字',                  string.rep('a', 65) },
    { 'E-4c 1000 文字',                string.rep('a', 1000) },
    { 'E-5 stash ID を直接指定',       'evidence_stash_mission_row' },
}

for i = 1, #badInputs do
    local label, value = badInputs[i][1], badInputs[i][2]
    local ok, r = pcall(stubs.callback, CB, 30, value)

    check(label .. ' が拒否される (エラーにならない)',
        ok and type(r) == 'table' and r.success == false,
        ok and ('success=' .. tostring(type(r) == 'table' and r.success)) or ('エラー: ' .. tostring(r)))
end

-- 正しいキーは引き続き通ること (過剰な拒否がないことの確認)
eq('E-6 正しいキーは引き続き許可される',
    stubs.callback(CB, 30, 'mission_row').success, true)

-----------------------------------------------------------------------------
-- F. クールダウン
-----------------------------------------------------------------------------

group('F. クールダウン')

-- F-1: 既定 (0 = 無効) では連続で開ける
ServerConfig.cooldownSeconds = 0
stubs.addPlayer(40, { job = 'police', grade = 2 })

local allOk = true
for _ = 1, 5 do
    if not stubs.callback(CB, 40, 'mission_row').success then allOk = false end
end
check('F-1 cooldownSeconds=0 なら連続 5 回開ける', allOk)

-- F-2: 5 秒に設定すると 2 回目が拒否される
ServerConfig.cooldownSeconds = 5
stubs.addPlayer(41, { job = 'police', grade = 2 })

eq('F-2a 1 回目は許可される', stubs.callback(CB, 41, 'mission_row').success, true)

res = stubs.callback(CB, 41, 'mission_row')
eq('F-2b 直後の 2 回目は拒否される', res.success, false)
eq('F-2c メッセージが残り秒数を含む', res.message, SharedConfig.text('err_cooldown', 5))
check('F-2d クールダウン拒否はログに残さない (連打でログが溢れないこと)',
    stubs.lastLog() == nil or stubs.lastLog().action ~= 'denied' or stubs.lastLog().detail ~= 'cooldown')

-- F-3: 時間を進めると再度開ける
S.now = S.now + 5
eq('F-3 5 秒経過後は再度開ける', stubs.callback(CB, 41, 'mission_row').success, true)

-- 別プレイヤーは影響を受けない
stubs.addPlayer(42, { job = 'police', grade = 2 })
eq('F-4 クールダウンはプレイヤーごとに独立している',
    stubs.callback(CB, 42, 'mission_row').success, true)

ServerConfig.cooldownSeconds = 0

-----------------------------------------------------------------------------
-- G. 後始末
-----------------------------------------------------------------------------

group('G. 後始末')

ServerConfig.cooldownSeconds = 5
stubs.addPlayer(50, { job = 'police', grade = 2 })
stubs.callback(CB, 50, 'mission_row')

eq('G-1 クールダウン中は拒否される', stubs.callback(CB, 50, 'mission_row').success, false)

-- 切断でクールダウンが解放される
_G.source = 50
stubs.fire('playerDropped')
_G.source = nil

eq('G-2 切断後に再接続すると即座に開ける (状態が解放される)',
    stubs.callback(CB, 50, 'mission_row').success, true)

ServerConfig.cooldownSeconds = 0

-- 不正なキーの倉庫は登録されない
SharedConfig.stashes['bad key!'] = {
    label = 'bad', coords = stubs.vec3(0, 0, 0), job = 'police', minGrade = 2
}
stubs.fire('onServerResourceStart', 'as-evidencestash')

check('G-3 不正なキーの倉庫は登録されない',
    S.registeredStashes['evidence_stash_bad key!'] == nil)
check('G-4 不正なキーは警告が出力される',
    (function()
        for i = 1, #S.prints do
            if S.prints[i]:find('bad key!', 1, true) then return true end
        end
        return false
    end)())

SharedConfig.stashes['bad key!'] = nil

-- ox_inventory 再起動で再登録される
S.registeredStashes = {}
stubs.fire('onServerResourceStart', 'ox_inventory')
check('G-5 ox_inventory 再起動時に stash が再登録される',
    S.registeredStashes['evidence_stash_mission_row'] ~= nil)

-----------------------------------------------------------------------------
-- H. 管理コマンド
-----------------------------------------------------------------------------

group('H. 管理コマンド')

stubs.addPlayer(60, { job = 'police', grade = 2, coords = stubs.vec3(1.25, 2.5, 3.75) })

local function runCommand(name, src, args)
    S.commands[name](src, args or {})
end

-- 権限なし
S.aceAllowed[60] = false
stubs.resetRecords()
runCommand('evidencestashcoords', 60)

eq('H-4a ACE 権限がないと座標コマンドを拒否する',
    S.notifications[1] and S.notifications[1].message, '権限がありません。')

-- 権限あり
S.aceAllowed[60] = true
stubs.resetRecords()
runCommand('evidencestashcoords', 60)

local snippet = table.concat(S.prints, '\n')

check('H-6a 現在地が設定用コードとして出力される',
    snippet:find('vec3(1.25, 2.50, 3.75)', 1, true) ~= nil, snippet)
check('H-6b キー省略時は new_stash になる',
    snippet:find("['new_stash']", 1, true) ~= nil, snippet)

-- キー指定
stubs.resetRecords()
runCommand('evidencestashcoords', 60, { 'sandy_shores' })
check('H-6c 引数でキーを指定できる',
    table.concat(S.prints, '\n'):find("['sandy_shores']", 1, true) ~= nil)

-- 不正なキー
stubs.resetRecords()
runCommand('evidencestashcoords', 60, { 'bad key!' })
check('H-6d 不正なキーは拒否され、コードを出力しない',
    #S.prints == 0 and S.notifications[1] ~= nil)

-- ログコマンドの権限
S.aceAllowed[61] = false
stubs.addPlayer(61, { job = 'police', grade = 2 })
stubs.resetRecords()
runCommand('evidencestashlogs', 61)

eq('H-4b ACE 権限がないとログコマンドを拒否する',
    S.notifications[1] and S.notifications[1].message, '権限がありません。')

-----------------------------------------------------------------------------
-- 結果
-----------------------------------------------------------------------------

stubs.realPrint(('\n=========================================='))
stubs.realPrint(('  成功: %d / 失敗: %d'):format(passed, failed))
stubs.realPrint(('=========================================='))
stubs.realPrint('※ これはスタブ環境での検証です。')
stubs.realPrint('※ ライブ FXServer での動作確認は別途必要です。')

os.exit(failed == 0 and 0 or 1)
