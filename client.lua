-- tani-watch クライアントスクリプト
-- DUI で動画を描画し、NUI（html/index.html）で操作画面を出す

-- ================== 状態 ==================

local isOpen = false        -- NUI（入力画面 / 視聴画面）を開いているか
local isPlaying = false     -- 動画を再生中か
local keepsGameInput = false -- カーソルを出したままゲームへ入力を渡している（視聴画面）か
local playSeq = 0           -- 再生要求の通し番号（待機中に閉じられた要求を捨てるために使う）
local currentVolume = 50

-- カーソルを出したままゲームへ入力を渡している間、毎フレーム無効にするコントロール
-- （無効にしないと、カメラが動いたり、ボタンのクリックが射撃・殴打として届いたりする）
-- 1・2: 視点 / 24・25・257: 攻撃・照準 / 68〜70・91・92・106・114: 乗り物の照準・攻撃
-- 142: 近接攻撃(マウス) / 239・240: カーソルの X・Y
-- 歩く・運転するなどのキーボード操作は残す（R・Q の近接攻撃キー 140・141・263・264 も対象外）
local CONTROLS_BLOCKED_WHILE_KEEPING_INPUT = {
    1, 2, 24, 25, 257, 68, 69, 70, 91, 92, 106, 114, 142, 239, 240,
}

-- DUI
local duiObject = nil
local duiPageReady = false  -- player.html が準備完了を通知した（または待ち時間を過ぎた）か
local runtimeTxd = nil
local TXD_NAME = 'tani_watch_dict'
local TEXTURE_NAME = 'tani_watch_txd'

-- 共有の受信
local KVP_RECEIVE = 'tani-watch:receiveShare'
local receiveEnabled = GetResourceKvpString(KVP_RECEIVE) ~= '0' -- 未設定なら受け取る
local blockedSenders = {}   -- [送信者のサーバーID] = true（再接続するまで有効）
local pendingShare = nil    -- 承諾待ちの共有 { media, from, fromId, seq }
local lastSender = nil      -- 最後に共有してきた人 { id, name }
local shareRequestSeq = 0

-- ================== 共通 ==================

-- NUI にトーストを出す（kind: 'info' | 'success' | 'error'）
local function toast(kind, message)
    SendNUIMessage({ action = 'toast', kind = kind, message = message })
end

local function clampVolume(value)
    value = tonumber(value)
    if not value then
        return currentVolume
    end
    return math.floor(math.max(0, math.min(100, value)))
end

-- NUI コールバックの登録。例外が出ても必ず応答を返す
local function registerCallback(name, handler)
    RegisterNUICallback(name, function(data, cb)
        local ok, result = pcall(handler, type(data) == 'table' and data or {})
        if not ok then
            print(('[tani-watch] callback %s error: %s'):format(name, tostring(result)))
            cb({ success = false, message = '内部エラーが発生しました' })
            return
        end
        if result == nil then
            result = 'ok'
        end
        cb(result)
    end)
end

-- ================== DUI ==================

local function createDui()
    if duiObject then
        return true
    end

    -- リソース名を直書きせず、実行中のリソース名から作る
    local url = ('https://cfx-nui-%s/html/player.html'):format(GetCurrentResourceName())
    local object = CreateDui(url, Config.DuiWidth, Config.DuiHeight)
    if not object then
        return false
    end

    duiObject = object
    duiPageReady = false

    -- テクスチャ辞書は1回だけ作る（同名の再作成を避ける）
    if not runtimeTxd then
        runtimeTxd = CreateRuntimeTxd(TXD_NAME)
    end
    CreateRuntimeTextureFromDuiHandle(runtimeTxd, TEXTURE_NAME, GetDuiHandle(duiObject))

    TaniWatch.Log('DUI Player created')
    return true
end

-- DUI のブラウザが作られ、ページが準備完了を通知するまで待つ。間に合わなければ false
-- （IsDuiAvailable は「ブラウザが作られたか」だけを返し、ページの読み込み完了は示さない）
local function waitForDui()
    local deadline = GetGameTimer() + Config.DuiReadyTimeoutMs

    -- ブラウザの生成を待つ
    while duiObject and not IsDuiAvailable(duiObject) do
        if GetGameTimer() > deadline then
            return false
        end
        Wait(0)
    end
    if not duiObject then
        return false
    end

    -- ページ側の準備完了通知（duiReady）を待つ。通知が届かない環境でも一定時間で進む
    local graceDeadline = GetGameTimer() + 1500
    while not duiPageReady and GetGameTimer() < graceDeadline do
        Wait(0)
    end
    duiPageReady = true

    return duiObject ~= nil
end

local function sendDuiAction(action, data)
    if not duiObject then
        return
    end

    local message = { action = action }
    if data then
        for key, value in pairs(data) do
            message[key] = value
        end
    end
    SendDuiMessage(duiObject, json.encode(message))
end

local function stopDuiVideo()
    sendDuiAction('stop')
    isPlaying = false
end

-- ================== 画面の状態遷移 ==================

-- 入力画面: キーボードもマウスも NUI が使う
-- 視聴画面: 設定により、キーボードはゲームへ渡す（歩く・運転するなどができる）
local function applyFocus(screen)
    keepsGameInput = screen == 'player' and Config.AllowGameInputWhileWatching == true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(keepsGameInput)
end

-- 動画を再生して視聴画面へ進む。成功で true、失敗で false とエラーメッセージ
local function startPlayback(media)
    playSeq = playSeq + 1
    local seq = playSeq

    if not createDui() then
        return false, '動画プレイヤーを作成できませんでした'
    end
    if not waitForDui() then
        return false, '動画プレイヤーの準備が間に合いませんでした。もう一度お試しください'
    end
    if seq ~= playSeq then
        return false, '再生が中断されました'
    end

    sendDuiAction('volume', { volume = currentVolume })
    sendDuiAction('play', { media = { platform = media.platform, kind = media.kind, id = media.id } })

    isOpen = true
    isPlaying = true
    applyFocus('player')
    SendNUIMessage({ action = 'showPlayer', platform = media.platform })
    return true
end

local function openUrlInput()
    if isOpen then
        return
    end

    isOpen = true
    createDui() -- 先に作っておいて、再生開始までの待ち時間を短くする
    applyFocus('input')
    SendNUIMessage({
        action = 'openInput',
        receiveEnabled = receiveEnabled,
        maxTargets = Config.MaxShareTargets,
        nearbyDistance = Config.NearbyDistance,
    })
end

local function closePlayer()
    playSeq = playSeq + 1
    if not (isOpen or isPlaying) then
        return
    end

    isOpen = false
    isPlaying = false
    keepsGameInput = false
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    stopDuiVideo()
end

local function backToInput()
    playSeq = playSeq + 1
    stopDuiVideo()
    isOpen = true
    applyFocus('input')
    SendNUIMessage({ action = 'showInput' })
end

-- ================== コマンド ==================

RegisterCommand('watch', function()
    openUrlInput()
end, false)

-- ================== NUI コールバック ==================

registerCallback('close', function()
    closePlayer()
end)

registerCallback('playVideo', function(data)
    local media, reason = TaniWatch.ParseMedia(data.url)
    if not media then
        return { success = false, message = reason }
    end

    local ok, err = startPlayback(media)
    if not ok then
        return { success = false, message = err }
    end
    return { success = true, platform = media.platform }
end)

registerCallback('volumeChange', function(data)
    currentVolume = clampVolume(data.volume)
    sendDuiAction('volume', { volume = currentVolume })
end)

registerCallback('backToInput', function()
    backToInput()
end)

-- プレイヤー画面の準備完了通知（DUI → Lua）
registerCallback('duiReady', function()
    duiPageReady = true
end)

-- プレイヤー画面のエラー通知（DUI → Lua）。画面にも表示されるので、トーストでも知らせる
registerCallback('duiStatus', function(data)
    if type(data.message) == 'string' and #data.message <= 120 then
        toast('error', data.message)
    end
end)

-- ================== 画面共有（送信） ==================

local function getNearbyPlayers()
    local players = {}
    local myPlayerId = PlayerId()
    local myCoords = GetEntityCoords(PlayerPedId())

    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= myPlayerId then
            local ped = GetPlayerPed(playerId)
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local distance = #(myCoords - GetEntityCoords(ped))
                if distance <= Config.NearbyDistance then
                    players[#players + 1] = {
                        id = GetPlayerServerId(playerId),
                        name = TaniWatch.SanitizeName(GetPlayerName(playerId)),
                        distance = distance,
                    }
                end
            end
        end
    end

    table.sort(players, function(a, b)
        return a.distance < b.distance
    end)

    return players
end

-- NUI から届いた共有先を、数値・重複なし・人数上限内に整える
local function sanitizeTargets(raw)
    local targets = {}
    local seen = {}
    if type(raw) ~= 'table' then
        return targets
    end

    for _, value in ipairs(raw) do
        local id = tonumber(value)
        if id and id > 0 and id == math.floor(id) and not seen[id] then
            seen[id] = true
            targets[#targets + 1] = math.floor(id)
            if #targets >= Config.MaxShareTargets then
                break
            end
        end
    end
    return targets
end

registerCallback('getNearbyPlayers', function()
    return { players = getNearbyPlayers() }
end)

registerCallback('shareVideo', function(data)
    local media, reason = TaniWatch.ParseMedia(data.url)
    if not media then
        return { success = false, message = reason }
    end

    local targets = sanitizeTargets(data.targetPlayers)
    if #targets == 0 then
        return { success = false, message = '共有先が選択されていません' }
    end

    -- 共有した本人も同じ動画を再生する
    local ok, err = startPlayback(media)
    if not ok then
        return { success = false, message = err }
    end

    TriggerServerEvent('tani-watch:shareVideo', media.url, targets)
    return { success = true, platform = media.platform }
end)

-- サーバーからの送信結果
RegisterNetEvent('tani-watch:shareResult', function(sent, skipped)
    sent = tonumber(sent) or 0
    skipped = tonumber(skipped) or 0

    local message = ('%d人に共有リクエストを送りました'):format(sent)
    if skipped > 0 then
        message = message .. ('（%d人は離れた・退出のため除外）'):format(skipped)
    end
    toast('success', message)
end)

-- サーバーからの通知（検証エラーなど）
RegisterNetEvent('tani-watch:notify', function(kind, message)
    if type(message) ~= 'string' then
        return
    end
    toast(kind == 'error' and 'error' or 'info', message)
end)

-- 受信者の応答
RegisterNetEvent('tani-watch:shareReply', function(name, status)
    if type(name) ~= 'string' or type(status) ~= 'string' then
        return
    end

    if status == 'accepted' then
        toast('success', ('%sさんが視聴を開始しました'):format(name))
    elseif status == 'declined' then
        toast('info', ('%sさんは共有を辞退しました'):format(name))
    elseif status == 'timeout' then
        toast('info', ('%sさんから応答がありませんでした'):format(name))
    elseif status == 'invalid' then
        toast('error', ('%sさんの環境で再生できませんでした'):format(name))
    end
end)

-- ================== 画面共有（受信） ==================

local function respondShare(status)
    TriggerServerEvent('tani-watch:shareResponse', status)
end

-- 共有された動画を再生し、結果を送信者へ返す
local function beginSharedPlayback(share)
    CreateThread(function()
        local ok, err = startPlayback(share.media)
        if ok then
            respondShare('accepted')
            toast('success', ('%sさんが共有した動画を再生します'):format(share.from))
        else
            respondShare('invalid')
            toast('error', err or '共有された動画を再生できませんでした')
        end
    end)
end

local function acceptPendingShare()
    local share = pendingShare
    if not share then
        return
    end

    pendingShare = nil
    SendNUIMessage({ action = 'shareRequestEnd' })
    beginSharedPlayback(share)
end

local function declinePendingShare(status)
    local share = pendingShare
    if not share then
        return
    end

    pendingShare = nil
    SendNUIMessage({ action = 'shareRequestEnd' })
    respondShare(status or 'declined')
end

local function setReceiveEnabled(enabled)
    receiveEnabled = enabled == true
    SetResourceKvp(KVP_RECEIVE, receiveEnabled and '1' or '0')
    if not receiveEnabled then
        declinePendingShare('declined')
    end
end

-- サーバー経由で届いた共有。承諾確認なしに再生や画面の奪取はしない
RegisterNetEvent('tani-watch:receiveShare', function(url, fromName, fromId)
    fromName = type(fromName) == 'string' and TaniWatch.SanitizeName(fromName) or '不明'
    fromId = tonumber(fromId)

    -- 受け取る側でも検証し、正規化したURLだけを使う
    local media = TaniWatch.ParseMedia(url)
    if not media then
        respondShare('invalid')
        return
    end

    if not receiveEnabled or (fromId and blockedSenders[fromId]) then
        respondShare('declined')
        return
    end

    lastSender = { id = fromId, name = fromName }

    if not Config.RequireAcceptance then
        beginSharedPlayback({ media = media, from = fromName, fromId = fromId })
        return
    end

    shareRequestSeq = shareRequestSeq + 1
    local seq = shareRequestSeq
    pendingShare = { media = media, from = fromName, fromId = fromId, seq = seq }

    SendNUIMessage({
        action = 'shareRequest',
        from = fromName,
        platform = media.platform,
        timeoutMs = Config.ShareRequestTimeoutMs,
        acceptKey = Config.AcceptKey,
        declineKey = Config.DeclineKey,
    })

    -- 時間切れは辞退扱い
    SetTimeout(Config.ShareRequestTimeoutMs, function()
        if pendingShare and pendingShare.seq == seq then
            declinePendingShare('timeout')
        end
    end)
end)

registerCallback('acceptShare', function()
    acceptPendingShare()
end)

registerCallback('declineShare', function()
    declinePendingShare('declined')
end)

registerCallback('setReceiveShare', function(data)
    setReceiveEnabled(data.enabled)
end)

-- キー操作（NUI にフォーカスが無いとき用。変更は FiveM のキー設定から）
RegisterCommand('tani-watch-accept', function()
    acceptPendingShare()
end, false)

RegisterCommand('tani-watch-decline', function()
    declinePendingShare('declined')
end, false)

RegisterKeyMapping('tani-watch-accept', '共有された動画を視聴する', 'keyboard', Config.AcceptKey)
RegisterKeyMapping('tani-watch-decline', '共有された動画を辞退する', 'keyboard', Config.DeclineKey)

-- 共有の受信を切り替える
RegisterCommand('watchdnd', function()
    setReceiveEnabled(not receiveEnabled)
    toast('info', receiveEnabled and '共有の受信をオンにしました' or '共有の受信をオフにしました')
end, false)

-- 最後に共有してきた人をブロックする（再接続するまで有効）
RegisterCommand('watchblock', function()
    if not lastSender or not lastSender.id then
        toast('info', 'ブロックできる送信者がいません')
        return
    end

    blockedSenders[lastSender.id] = true
    if pendingShare and pendingShare.fromId == lastSender.id then
        declinePendingShare('declined')
    end
    toast('success', ('%sさんからの共有をブロックしました（再接続するまで有効）'):format(lastSender.name))
end, false)

-- ================== 描画スレッド ==================

-- DUI をスクリーンに描画（再生中だけ毎フレーム回す）
CreateThread(function()
    while true do
        if isPlaying and duiObject then
            Wait(0)

            -- 16:9 の動画を、画面の縦横比に合わせて歪まないように描く。
            -- 上と左右に余白を残し、通知や共有の確認はその余白に出す（動画の上には重ねない）
            local aspect = GetAspectRatio(false)
            local width = Config.VideoWidth
            local height = width * aspect * 9 / 16
            if height > Config.VideoMaxHeight then
                height = Config.VideoMaxHeight
                width = height * 16 / (9 * aspect)
            end

            SetScriptGfxDrawBehindPausemenu(true)
            DrawSprite(TXD_NAME, TEXTURE_NAME, 0.5, Config.VideoCenterY, width, height, 0.0, 255, 255, 255, 255)
            SetScriptGfxDrawBehindPausemenu(false)
        else
            Wait(100)
        end
    end
end)

-- ================== キー入力処理 ==================

-- ESC で閉じる（キーボードがゲームへ渡っているとき用。NUI にフォーカスがあるときは JS 側で閉じる）
-- あわせて、視聴画面でカーソルを出したままゲームへ入力を渡している間は、視点と攻撃を無効にする
CreateThread(function()
    while true do
        if isOpen then
            Wait(0)
            DisableControlAction(0, 200, true) -- ESC
            if IsDisabledControlJustReleased(0, 200) then
                closePlayer()
            elseif keepsGameInput then
                for _, control in ipairs(CONTROLS_BLOCKED_WHILE_KEEPING_INPUT) do
                    DisableControlAction(0, control, true)
                end
            end
        else
            Wait(250)
        end
    end
end)

-- ================== 登録 ==================

-- リソース停止時の DUI の破棄と NUI フォーカスの解除は、FiveM 本体が行うので、ここでは何もしない

-- チャットのコマンド候補（chat がまだ起動していない場合に備え、chat の起動時にも登録する）
local function registerSuggestions()
    TriggerEvent('chat:addSuggestion', '/watch', 'YouTube/Twitchのビデオを視聴・共有')
    TriggerEvent('chat:addSuggestion', '/watchdnd', '動画共有の受信をオン/オフにする')
    TriggerEvent('chat:addSuggestion', '/watchblock', '最後に共有してきた人をブロックする')
end

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() or resourceName == 'chat' then
        registerSuggestions()
    end
end)
