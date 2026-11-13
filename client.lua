-- ta-movie-player クライアントスクリプト
-- DUI で動画を描画し、NUI（html/index.html）で操作画面を出す
-- 視聴画面（画面の上に枠を出して観る）と、空間スクリーン（街の中に置いたスクリーンで観る）の2通り

-- ================== 状態 ==================

local isOpen = false         -- NUI（入力画面 / 視聴画面）を開いているか
local isPlaying = false      -- 視聴画面で動画を再生中か
local keepsGameInput = false -- カーソルを出したままゲームへ入力を渡している（視聴画面）か
local playSeq = 0            -- 再生要求の通し番号（待機中に閉じられた要求を捨てるために使う）
local currentVolume = 50
local currentMedia = nil     -- 視聴画面で再生中のメディア

-- 視聴画面の枠
local KVP_FRAME_SCALE = 'ta-movie-player:frameScale'
local frameScale = tonumber(GetResourceKvpString(KVP_FRAME_SCALE)) or 1.0
local videoRect = nil        -- 動画を描く位置（NUI が枠の大きさから計算して送ってくる。画面に対する割合）

-- 上映（同期再生）
local session = nil          -- { sessionId, isHost, hostId, hostName, memberCount, platform }
local pendingSessionSync = nil -- 再生の準備が終わる前に届いた再生状態
local lastHostReport = nil   -- ホストとして最後に送った再生位置 { time, paused, at }

-- カーソルを出したままゲームへ入力を渡している間、毎フレーム無効にするコントロール
-- （無効にしないと、カメラが動いたり、ボタンのクリックが射撃・殴打として届いたりする）
-- 1・2: 視点 / 24・25・257: 攻撃・照準 / 68〜70・91・92・106・114: 乗り物の照準・攻撃
-- 142: 近接攻撃(マウス) / 239・240: カーソルの X・Y
-- 歩く・運転するなどのキーボード操作は残す（Config.AllowMovementWhileWatching = false なら移動も止める）
local CONTROLS_BLOCKED_WHILE_KEEPING_INPUT = {
    1, 2, 24, 25, 257, 68, 69, 70, 91, 92, 106, 114, 142, 239, 240,
}

-- DUI（main = 視聴画面、s1・s2… = 空間スクリーン）
local duis = {}              -- [枠の名前] = { object, texture, pageReady }
local runtimeTxd = nil
local TXD_NAME = 'ta_movie_player_dict'

-- 共有の受信
local KVP_RECEIVE = 'ta-movie-player:receiveShare'
local receiveEnabled = GetResourceKvpString(KVP_RECEIVE) ~= '0' -- 未設定なら受け取る
local blockedSenders = {}    -- [送信者のサーバーID] = true（再接続するまで有効）
local lastSender = nil       -- 最後に共有してきた人 { id, name }

-- 承諾確認（共有が届いた / 参加の申請が届いた）。先頭が表示中、残りは順番待ち
local prompts = {}
local promptSeq = 0

-- 空間スクリーン
local screens = {}           -- [スクリーンID] = スクリーン（位置・向き・動画・再生状態）
local isAdmin = false
local screenSlots = {}       -- [枠の名前] = スクリーンID
local screenVolume = {}      -- [スクリーンID] = 自分だけの音量（0〜100）
local screenPanelId = nil    -- 操作パネルを開いているスクリーン
local placing = nil          -- 配置中の状態

-- 描画（DRAW_TEXTURED_POLY は古い名前 DrawSpritePoly でも呼べる）
local drawTexturedPoly = DrawTexturedPoly or DrawSpritePoly or function(...)
    Citizen.InvokeNative(0x29280002282F1928, ...)
end

-- ================== 共通 ==================

-- NUI にトーストを出す（kind: 'info' | 'success' | 'error'）
local function toast(kind, message)
    SendNUIMessage({ action = 'toast', kind = kind, message = message })
end

local function clampVolume(value, fallback)
    value = tonumber(value)
    if not value or value ~= value then
        return fallback
    end
    return math.floor(math.max(0, math.min(100, value)))
end

local function finiteNumber(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function myServerId()
    return GetPlayerServerId(PlayerId())
end

-- NUI コールバックの登録。例外が出ても必ず応答を返す
local function registerCallback(name, handler)
    RegisterNUICallback(name, function(data, cb)
        local ok, result = pcall(handler, type(data) == 'table' and data or {})
        if not ok then
            print(('[ta-movie-player] callback %s error: %s'):format(name, tostring(result)))
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

local function textureName(slot)
    return 'ta_movie_player_' .. slot
end

local function createDui(slot)
    if duis[slot] then
        return true
    end

    -- リソース名を直書きせず、実行中のリソース名から作る。どの枠かはクエリで渡す
    local url = ('https://cfx-nui-%s/html/player.html?slot=%s'):format(GetCurrentResourceName(), slot)
    local object = CreateDui(url, Config.DuiWidth, Config.DuiHeight)
    if not object then
        return false
    end

    -- テクスチャ辞書は1回だけ作る（同名の再作成を避ける）
    if not runtimeTxd then
        runtimeTxd = CreateRuntimeTxd(TXD_NAME)
    end
    CreateRuntimeTextureFromDuiHandle(runtimeTxd, textureName(slot), GetDuiHandle(object))

    duis[slot] = { object = object, pageReady = false }
    MoviePlayer.Log('DUI created: ' .. slot)
    return true
end

-- DUI のブラウザが作られ、ページが準備完了を通知するまで待つ。間に合わなければ false
-- （IsDuiAvailable は「ブラウザが作られたか」だけを返し、ページの読み込み完了は示さない）
local function waitForDui(slot)
    local dui = duis[slot]
    if not dui then
        return false
    end

    local deadline = GetGameTimer() + Config.DuiReadyTimeoutMs
    while duis[slot] and not IsDuiAvailable(dui.object) do
        if GetGameTimer() > deadline then
            return false
        end
        Wait(0)
    end
    if not duis[slot] then
        return false
    end

    -- ページ側の準備完了通知（duiReady）を待つ。通知が届かない環境でも一定時間で進む
    local graceDeadline = GetGameTimer() + 1500
    while not dui.pageReady and GetGameTimer() < graceDeadline do
        Wait(0)
    end
    dui.pageReady = true
    return true
end

local function sendDui(slot, action, data)
    local dui = duis[slot]
    if not dui then
        return
    end

    local message = { action = action }
    if data then
        for key, value in pairs(data) do
            message[key] = value
        end
    end
    SendDuiMessage(dui.object, json.encode(message))
end

local function playOnDui(slot, media, volume)
    sendDui(slot, 'syncConfig', { tolerance = Config.SyncToleranceSec, intervalMs = Config.SyncIntervalMs })
    sendDui(slot, 'volume', { volume = volume })
    sendDui(slot, 'play', { media = { platform = media.platform, kind = media.kind, id = media.id } })
end

-- ================== 視聴画面: 状態遷移 ==================

-- 入力画面: キーボードもマウスも NUI が使う
-- 視聴画面: 設定により、キーボードはゲームへ渡す（ボイスチャットの発話キーなど）
local function applyFocus(screenName)
    keepsGameInput = screenName == 'player' and Config.AllowGameInputWhileWatching == true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(keepsGameInput)
end

local function sendSessionInfo()
    SendNUIMessage({
        action = 'sessionInfo',
        inSession = session ~= nil,
        isHost = session ~= nil and session.isHost == true,
        hostName = session and session.hostName or nil,
        memberCount = session and session.memberCount or 1,
        canControl = session == nil or session.isHost == true,
    })
end

-- 今の上映から抜ける（サーバーに伝え、同期をやめる）
local function leaveCurrentSession()
    if session then
        TriggerServerEvent('ta-movie-player:leaveSession')
    end
    session = nil
    pendingSessionSync = nil
    lastHostReport = nil
end

local function stopMainVideo()
    sendDui('main', 'stop')
    isPlaying = false
    currentMedia = nil
end

-- 動画を再生して視聴画面へ進む。成功で true、失敗で false とエラーメッセージ
local function startPlayback(media)
    playSeq = playSeq + 1
    local seq = playSeq

    if not createDui('main') then
        return false, '動画プレイヤーを作成できませんでした'
    end
    if not waitForDui('main') then
        return false, '動画プレイヤーの準備が間に合いませんでした。もう一度お試しください'
    end
    if seq ~= playSeq then
        return false, '再生が中断されました'
    end

    playOnDui('main', media, currentVolume)

    isOpen = true
    isPlaying = true
    currentMedia = media
    applyFocus('player')
    SendNUIMessage({
        action = 'showPlayer',
        platform = media.platform,
        kind = media.kind,
        frame = {
            scale = frameScale,
            min = Config.FrameScaleMin,
            max = Config.FrameScaleMax,
            step = Config.FrameScaleStep,
            videoWidth = Config.VideoWidth,
            videoMaxHeight = Config.VideoMaxHeight,
            videoCenterY = Config.VideoCenterY,
        },
    })
    sendSessionInfo()

    -- 再生の準備中に届いた再生状態があれば合わせる
    if pendingSessionSync then
        sendDui('main', 'sync', pendingSessionSync)
        pendingSessionSync = nil
    end
    return true
end

local function openUrlInput()
    if isOpen or placing then
        return
    end

    isOpen = true
    createDui('main') -- 先に作っておいて、再生開始までの待ち時間を短くする
    applyFocus('input')
    SendNUIMessage({
        action = 'openInput',
        receiveEnabled = receiveEnabled,
        maxTargets = Config.MaxShareTargets,
        nearbyDistance = Config.NearbyDistance,
        joinEnabled = Config.JoinRequestEnabled,
        screensEnabled = Config.Screens.Enabled,
    })
end

local function closePlayer()
    playSeq = playSeq + 1
    if not (isOpen or isPlaying) then
        return
    end

    isOpen = false
    keepsGameInput = false
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    leaveCurrentSession()
    stopMainVideo()
end

local function backToInput()
    playSeq = playSeq + 1
    leaveCurrentSession()
    stopMainVideo()
    isOpen = true
    applyFocus('input')
    SendNUIMessage({ action = 'showInput' })
end

-- ================== コマンド ==================

RegisterCommand('watch', function()
    if screenPanelId then
        return
    end
    openUrlInput()
end, false)

-- ================== NUI コールバック: 視聴画面 ==================

registerCallback('close', function()
    closePlayer()
end)

registerCallback('playVideo', function(data)
    local media, reason = MoviePlayer.ParseMedia(data.url)
    if not media then
        return { success = false, message = reason }
    end

    leaveCurrentSession()
    local ok, err = startPlayback(media)
    if not ok then
        return { success = false, message = err }
    end

    -- ひとりで観るときも上映として登録し、近くの人が参加を申請できるようにする
    TriggerServerEvent('ta-movie-player:startSession', media.url)
    return { success = true, platform = media.platform }
end)

registerCallback('volumeChange', function(data)
    currentVolume = clampVolume(data.volume, currentVolume)
    sendDui('main', 'volume', { volume = currentVolume })
end)

registerCallback('backToInput', function()
    backToInput()
end)

-- 枠の大きさ（10% 刻み）。次に開いたときも同じ大きさにする
registerCallback('setFrameScale', function(data)
    local scale = finiteNumber(data.scale)
    if not scale then
        return
    end
    local step = Config.FrameScaleStep
    scale = math.floor(scale / step + 0.5) * step
    frameScale = math.max(Config.FrameScaleMin, math.min(Config.FrameScaleMax, scale))
    SetResourceKvp(KVP_FRAME_SCALE, tostring(frameScale))
end)

-- 枠の中の、動画を描く位置（左上と幅・高さを画面に対する割合で受け取る）
registerCallback('frameLayout', function(data)
    local x, y, w, h = finiteNumber(data.x), finiteNumber(data.y), finiteNumber(data.w), finiteNumber(data.h)
    if not (x and y and w and h) or w <= 0 or h <= 0 or w > 1 or h > 1 then
        return
    end
    videoRect = { cx = x + w / 2, cy = y + h / 2, w = w, h = h }
end)

-- 一時停止・再開・シーク（ひとりで観ているときと、上映のホストだけ）
registerCallback('playerControl', function(data)
    if not isPlaying then
        return
    end
    if session and not session.isHost then
        toast('info', '再生位置はホストが操作します')
        return
    end

    if data.action == 'pause' then
        sendDui('main', 'pause')
    elseif data.action == 'resume' then
        sendDui('main', 'resume')
    elseif data.action == 'seek' then
        local position = finiteNumber(data.position)
        if position then
            sendDui('main', 'seek', { position = math.max(0, position) })
        end
    end
end)

-- ================== DUI からの通知 ==================

local function slotOf(data)
    local slot = data.slot
    if type(slot) == 'string' and duis[slot] then
        return slot
    end
    return nil
end

-- プレイヤー画面の準備完了通知（DUI → Lua）
registerCallback('duiReady', function(data)
    local slot = slotOf(data)
    if slot then
        duis[slot].pageReady = true
    end
end)

-- プレイヤー画面のエラー通知（DUI → Lua）。視聴画面のものだけトーストでも知らせる
registerCallback('duiStatus', function(data)
    if type(data.message) ~= 'string' or #data.message > 120 then
        return
    end
    local slot = slotOf(data)
    if slot == 'main' then
        toast('error', data.message)
    elseif slot and screenPanelId and screenSlots[slot] == screenPanelId then
        SendNUIMessage({ action = 'screenStatus', id = screenPanelId, message = data.message })
    end
end)

local function progressPayload(data)
    return {
        active = data.active == true,
        ready = data.ready == true,
        time = finiteNumber(data.time),
        duration = finiteNumber(data.duration),
        paused = data.paused == true,
        live = data.live == true,
        seekable = data.seekable == true,
        controllable = data.controllable == true,
    }
end

-- ホストとして、再生位置をサーバーへ知らせる（定期・一時停止の切り替え・シークしたとき）
local function reportHostState(progress)
    if not session or not session.isHost or not progress.time or progress.live then
        return
    end

    local t = GetGameTimer()
    local last = lastHostReport
    local due = last == nil
        or progress.paused ~= last.paused
        or (t - last.at) >= Config.SyncIntervalMs

    if not due and not progress.paused then
        -- 予想した位置から大きく外れた（シークした）ときもすぐ知らせる
        local expected = last.time + (t - last.at) / 1000
        due = math.abs(progress.time - expected) > 1.5
    end
    if not due then
        return
    end

    lastHostReport = { time = progress.time, paused = progress.paused, at = t }
    TriggerServerEvent('ta-movie-player:hostState', not progress.paused, progress.time)
end

-- 再生位置の通知（DUI → Lua、1秒ごと）
registerCallback('duiProgress', function(data)
    local slot = slotOf(data)
    if not slot then
        return
    end
    local progress = progressPayload(data)

    if slot == 'main' then
        if isPlaying then
            SendNUIMessage({ action = 'progress', progress = progress })
            reportHostState(progress)
        end
    elseif screenPanelId and screenSlots[slot] == screenPanelId then
        SendNUIMessage({ action = 'screenProgress', id = screenPanelId, progress = progress })
    end
end)

-- ================== 上映（同期再生） ==================

RegisterNetEvent('ta-movie-player:sessionInfo', function(info)
    if type(info) ~= 'table' or not tonumber(info.sessionId) then
        return
    end
    session = {
        sessionId = tonumber(info.sessionId),
        isHost = info.isHost == true,
        hostId = tonumber(info.hostId),
        hostName = type(info.hostName) == 'string' and MoviePlayer.SanitizeName(info.hostName) or '不明',
        memberCount = tonumber(info.memberCount) or 1,
        platform = info.platform,
    }
    if session.isHost then
        lastHostReport = nil
    end
    sendSessionInfo()
end)

-- ホストの再生状態（参加者だけに届く）
RegisterNetEvent('ta-movie-player:sessionSync', function(payload)
    if type(payload) ~= 'table' or type(payload.playing) ~= 'boolean' then
        return
    end
    local position = finiteNumber(payload.position)
    if not position then
        return
    end
    if session and tonumber(payload.sessionId) ~= session.sessionId then
        return
    end

    local sync = { playing = payload.playing, position = position }
    if isPlaying then
        sendDui('main', 'sync', sync)
    else
        pendingSessionSync = sync
    end
end)

RegisterNetEvent('ta-movie-player:sessionEnded', function(sessionId)
    if not session or tonumber(sessionId) ~= session.sessionId then
        return
    end
    session = nil
    pendingSessionSync = nil
    sendDui('main', 'unsync')
    sendSessionInfo()
    if isPlaying then
        toast('info', 'ホストが上映を終えました。このまま再生を続けます（同期はしません）')
    end
end)

-- ================== 承諾確認（共有・参加の申請） ==================

local function respondShare(status)
    TriggerServerEvent('ta-movie-player:shareResponse', status)
end

local showNextPrompt -- 下で定義

-- 共有された動画を再生し、結果を送信者へ返す
local function beginSharedPlayback(share)
    CreateThread(function()
        leaveCurrentSession()
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

local function promptMessage(prompt, remaining)
    local message = {
        action = 'shareRequest',
        kind = prompt.kind,
        from = prompt.from,
        platform = prompt.platform,
        timeoutMs = remaining,
        acceptKey = Config.AcceptKey,
        declineKey = Config.DeclineKey,
    }
    return message
end

-- 先頭の確認を閉じて、答えを返す
local function resolvePrompt(accepted, status)
    local prompt = table.remove(prompts, 1)
    if not prompt then
        return
    end
    SendNUIMessage({ action = 'shareRequestEnd' })

    if prompt.kind == 'share' then
        if accepted then
            beginSharedPlayback(prompt)
        else
            respondShare(status or 'declined')
        end
    elseif prompt.kind == 'join' then
        TriggerServerEvent('ta-movie-player:joinResponse', prompt.requesterId, accepted == true)
    end

    showNextPrompt()
end

-- 待っている確認のうち、期限内の先頭を表示する
showNextPrompt = function()
    while prompts[1] do
        local prompt = prompts[1]
        local remaining = prompt.expiresAt - GetGameTimer()
        if remaining > 500 then
            if not prompt.shown then
                prompt.shown = true
                SendNUIMessage(promptMessage(prompt, remaining))
                local id = prompt.id
                SetTimeout(remaining, function()
                    if prompts[1] and prompts[1].id == id then
                        resolvePrompt(false, 'timeout')
                    end
                end)
            end
            return
        end

        -- 順番待ちの間に期限が過ぎた
        table.remove(prompts, 1)
        if prompt.kind == 'share' then
            respondShare('timeout')
        end
    end
    SendNUIMessage({ action = 'shareRequestEnd' })
end

local function queuePrompt(prompt)
    promptSeq = promptSeq + 1
    prompt.id = promptSeq
    prompts[#prompts + 1] = prompt
    showNextPrompt()
end

-- 条件に合う確認を取り除く（表示中のものなら次を出す）
local function removePrompts(predicate, status)
    local removedCurrent = false
    for index = #prompts, 1, -1 do
        local prompt = prompts[index]
        if predicate(prompt) then
            table.remove(prompts, index)
            if index == 1 then
                removedCurrent = true
            end
            if status and prompt.kind == 'share' then
                respondShare(status)
            end
        end
    end
    if removedCurrent then
        SendNUIMessage({ action = 'shareRequestEnd' })
        showNextPrompt()
    end
end

local function setReceiveEnabled(enabled)
    receiveEnabled = enabled == true
    SetResourceKvp(KVP_RECEIVE, receiveEnabled and '1' or '0')
    if not receiveEnabled then
        removePrompts(function(prompt) return prompt.kind == 'share' end, 'declined')
    end
end

-- サーバー経由で届いた共有。承諾確認なしに再生や画面の奪取はしない
RegisterNetEvent('ta-movie-player:receiveShare', function(url, fromName, fromId)
    fromName = type(fromName) == 'string' and MoviePlayer.SanitizeName(fromName) or '不明'
    fromId = tonumber(fromId)

    -- 受け取る側でも検証し、正規化したURLだけを使う
    local media = MoviePlayer.ParseMedia(url)
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

    -- サーバーが覚える共有は1人につき最新の1件だけなので、前の共有の確認は（返事をせずに）取り下げる
    removePrompts(function(prompt) return prompt.kind == 'share' end)
    queuePrompt({
        kind = 'share',
        media = media,
        from = fromName,
        fromId = fromId,
        platform = media.platform,
        expiresAt = GetGameTimer() + Config.ShareRequestTimeoutMs,
    })
end)

-- 参加の申請が届いた（ホストだけ）
RegisterNetEvent('ta-movie-player:joinRequest', function(requesterId, name, timeoutMs)
    requesterId = tonumber(requesterId)
    if not requesterId or not session or not session.isHost then
        if requesterId then
            TriggerServerEvent('ta-movie-player:joinResponse', requesterId, false)
        end
        return
    end

    removePrompts(function(prompt) return prompt.kind == 'join' and prompt.requesterId == requesterId end)
    queuePrompt({
        kind = 'join',
        requesterId = requesterId,
        from = type(name) == 'string' and MoviePlayer.SanitizeName(name) or '不明',
        platform = currentMedia and currentMedia.platform or 'youtube',
        expiresAt = GetGameTimer() + math.min(tonumber(timeoutMs) or Config.JoinRequestTimeoutMs, Config.JoinRequestTimeoutMs),
    })
end)

-- 申請が取り消された（時間切れ・申請者の退出など）
RegisterNetEvent('ta-movie-player:joinRequestEnd', function(requesterId)
    requesterId = tonumber(requesterId)
    removePrompts(function(prompt) return prompt.kind == 'join' and prompt.requesterId == requesterId end)
end)

-- 参加が許可された（申請した側）
RegisterNetEvent('ta-movie-player:joinApproved', function(url, hostName)
    local media = MoviePlayer.ParseMedia(url)
    if not media then
        return
    end
    hostName = type(hostName) == 'string' and MoviePlayer.SanitizeName(hostName) or '不明'

    CreateThread(function()
        local ok, err = startPlayback(media)
        if ok then
            toast('success', ('%sさんの上映に参加しました'):format(hostName))
            TriggerServerEvent('ta-movie-player:requestSync')
        else
            toast('error', err or '動画を再生できませんでした')
            leaveCurrentSession()
        end
    end)
end)

registerCallback('acceptShare', function()
    resolvePrompt(true)
end)

registerCallback('declineShare', function()
    resolvePrompt(false, 'declined')
end)

registerCallback('setReceiveShare', function(data)
    setReceiveEnabled(data.enabled)
end)

-- キー操作（NUI にフォーカスが無いとき用。変更は FiveM のキー設定から）
RegisterCommand('ta-movie-player-accept', function()
    resolvePrompt(true)
end, false)

RegisterCommand('ta-movie-player-decline', function()
    resolvePrompt(false, 'declined')
end, false)

RegisterKeyMapping('ta-movie-player-accept', '動画の共有・参加の申請を受ける', 'keyboard', Config.AcceptKey)
RegisterKeyMapping('ta-movie-player-decline', '動画の共有・参加の申請を断る', 'keyboard', Config.DeclineKey)

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

    local blockedId = lastSender.id
    blockedSenders[blockedId] = true
    removePrompts(function(prompt) return prompt.kind == 'share' and prompt.fromId == blockedId end, 'declined')
    toast('success', ('%sさんからの共有をブロックしました（再接続するまで有効）'):format(lastSender.name))
end, false)

-- ================== 共有（送信） ==================

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
                        name = MoviePlayer.SanitizeName(GetPlayerName(playerId)),
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
    local media, reason = MoviePlayer.ParseMedia(data.url)
    if not media then
        return { success = false, message = reason }
    end

    local targets = sanitizeTargets(data.targetPlayers)
    if #targets == 0 then
        return { success = false, message = '共有先が選択されていません' }
    end

    -- 共有した本人も同じ動画を再生する（上映のホストになる）
    leaveCurrentSession()
    local ok, err = startPlayback(media)
    if not ok then
        return { success = false, message = err }
    end

    TriggerServerEvent('ta-movie-player:shareVideo', media.url, targets)
    return { success = true, platform = media.platform }
end)

-- サーバーからの送信結果
RegisterNetEvent('ta-movie-player:shareResult', function(sent, skipped)
    sent = tonumber(sent) or 0
    skipped = tonumber(skipped) or 0

    local message = ('%d人に共有リクエストを送りました'):format(sent)
    if skipped > 0 then
        message = message .. ('（%d人は離れた・退出のため除外）'):format(skipped)
    end
    toast('success', message)
end)

-- サーバーからの通知（検証エラーなど）
RegisterNetEvent('ta-movie-player:notify', function(kind, message)
    if type(message) ~= 'string' then
        return
    end
    if kind ~= 'error' and kind ~= 'success' then
        kind = 'info'
    end
    toast(kind, message)
end)

-- 受信者の応答
RegisterNetEvent('ta-movie-player:shareReply', function(name, status)
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

-- ================== 参加の申請（申請する側） ==================

-- 近くの上映の一覧を問い合わせる（結果は sessionList で届く）
registerCallback('listSessions', function()
    if Config.JoinRequestEnabled then
        TriggerServerEvent('ta-movie-player:listSessions')
    end
end)

RegisterNetEvent('ta-movie-player:sessionList', function(list)
    if type(list) ~= 'table' then
        return
    end

    local myCoords = GetEntityCoords(PlayerPedId())
    local result = {}
    for _, item in ipairs(list) do
        local hostId = tonumber(item.hostId)
        local player = hostId and GetPlayerFromServerId(hostId) or -1
        -- ホストが近くに見えている（同じ範囲にいる）ときだけ出す（OneSync が無い環境の距離検証も兼ねる）
        if player ~= -1 then
            local ped = GetPlayerPed(player)
            local distance = ped ~= 0 and #(myCoords - GetEntityCoords(ped)) or math.huge
            if distance <= Config.NearbyDistance then
                result[#result + 1] = {
                    sessionId = tonumber(item.sessionId),
                    hostName = MoviePlayer.SanitizeName(item.hostName),
                    platform = item.platform == 'twitch' and 'twitch' or 'youtube',
                    memberCount = tonumber(item.memberCount) or 1,
                    full = item.full == true,
                    pending = item.pending == true,
                    distance = distance,
                }
            end
        end
    end
    table.sort(result, function(a, b) return a.distance < b.distance end)
    SendNUIMessage({ action = 'sessionList', sessions = result })
end)

registerCallback('requestJoin', function(data)
    local sessionId = tonumber(data.sessionId)
    if not sessionId or not Config.JoinRequestEnabled then
        return { success = false }
    end
    TriggerServerEvent('ta-movie-player:requestJoin', sessionId)
    return { success = true }
end)

-- ================== 空間スクリーン: 形 ==================

local UP = vector3(0.0, 0.0, 1.0)

local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function normalize(v)
    local length = #v
    if length < 0.0001 then
        return nil
    end
    return v / length
end

local function screenHeight(width)
    return width * 9 / 16
end

-- 向き（GTA の heading。0 = 北）から、スクリーンが向いている方向
local function headingToForward(heading)
    local rad = math.rad(heading)
    return vector3(-math.sin(rad), math.cos(rad), 0.0)
end

local function forwardToHeading(forward)
    return math.deg(math.atan(-forward.x, forward.y)) % 360
end

-- 中心・向き・幅から、四隅と向きのベクトルを求める（見る人から見た左上・右上・左下・右下）
local function buildGeometry(center, heading, width)
    local forward = headingToForward(heading)
    local right = vector3(-forward.y, forward.x, 0.0)
    local halfW = width / 2
    local halfH = screenHeight(width) / 2
    return {
        center = center,
        forward = forward,
        right = right,
        halfW = halfW,
        halfH = halfH,
        tl = center - right * halfW + UP * halfH,
        tr = center + right * halfW + UP * halfH,
        bl = center - right * halfW - UP * halfH,
        br = center + right * halfW - UP * halfH,
    }
end

local function canManage(screen)
    return isAdmin or (screen.ownerSrc ~= nil and screen.ownerSrc == myServerId())
end

local function myScreenCount()
    local count = 0
    local me = myServerId()
    for _, screen in pairs(screens) do
        if screen.ownerSrc == me then
            count = count + 1
        end
    end
    return count
end

-- ================== 空間スクリーン: 描画 ==================

local function drawQuad(geo, r, g, b, a)
    -- 表から見える向き（(b-a)×(c-a) が見る人の方を向く）で2枚の三角形を描く
    DrawPoly(geo.tl.x, geo.tl.y, geo.tl.z, geo.bl.x, geo.bl.y, geo.bl.z, geo.tr.x, geo.tr.y, geo.tr.z, r, g, b, a)
    DrawPoly(geo.tr.x, geo.tr.y, geo.tr.z, geo.bl.x, geo.bl.y, geo.bl.z, geo.br.x, geo.br.y, geo.br.z, r, g, b, a)
end

local function drawQuadBack(geo, r, g, b, a)
    DrawPoly(geo.tl.x, geo.tl.y, geo.tl.z, geo.tr.x, geo.tr.y, geo.tr.z, geo.bl.x, geo.bl.y, geo.bl.z, r, g, b, a)
    DrawPoly(geo.tr.x, geo.tr.y, geo.tr.z, geo.br.x, geo.br.y, geo.br.z, geo.bl.x, geo.bl.y, geo.bl.z, r, g, b, a)
end

local function drawTexturedQuad(geo, slot)
    local tex = textureName(slot)
    drawTexturedPoly(geo.tl.x, geo.tl.y, geo.tl.z, geo.bl.x, geo.bl.y, geo.bl.z, geo.tr.x, geo.tr.y, geo.tr.z,
        255, 255, 255, 255, TXD_NAME, tex, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, 0.0, 1.0)
    drawTexturedPoly(geo.tr.x, geo.tr.y, geo.tr.z, geo.bl.x, geo.bl.y, geo.bl.z, geo.br.x, geo.br.y, geo.br.z,
        255, 255, 255, 255, TXD_NAME, tex, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0)
end

local function drawOutline(geo, r, g, b, a)
    DrawLine(geo.tl.x, geo.tl.y, geo.tl.z, geo.tr.x, geo.tr.y, geo.tr.z, r, g, b, a)
    DrawLine(geo.tr.x, geo.tr.y, geo.tr.z, geo.br.x, geo.br.y, geo.br.z, r, g, b, a)
    DrawLine(geo.br.x, geo.br.y, geo.br.z, geo.bl.x, geo.bl.y, geo.bl.z, r, g, b, a)
    DrawLine(geo.bl.x, geo.bl.y, geo.bl.z, geo.tl.x, geo.tl.y, geo.tl.z, r, g, b, a)
end

-- 縁（ベゼル）。画面より少し大きく、少し後ろに置く。裏から見ても黒い板に見えるよう両面に描く
local function bezelGeometry(geo)
    local margin = 0.04
    local back = geo.forward * -0.012
    local center = geo.center + back
    local halfW, halfH = geo.halfW + margin, geo.halfH + margin
    return {
        tl = center - geo.right * halfW + UP * halfH,
        tr = center + geo.right * halfW + UP * halfH,
        bl = center - geo.right * halfW - UP * halfH,
        br = center + geo.right * halfW - UP * halfH,
    }
end

local function slotOfScreen(id)
    for slot, screenId in pairs(screenSlots) do
        if screenId == id then
            return slot
        end
    end
    return nil
end

CreateThread(function()
    while true do
        local camCoords = GetFinalRenderedCamCoord()
        local anyNear = false

        for id, screen in pairs(screens) do
            if #(camCoords - screen.geo.center) <= Config.Screens.RenderDistance then
                anyNear = true
                local bezel = screen.bezel
                drawQuad(bezel, 8, 8, 9, 255)
                drawQuadBack(bezel, 8, 8, 9, 255)

                local slot = slotOfScreen(id)
                if slot and duis[slot] then
                    drawTexturedQuad(screen.geo, slot)
                else
                    drawQuad(screen.geo, 18, 18, 20, 255)
                end
            end
        end

        Wait(anyNear and 0 or 500)
    end
end)

-- ================== 空間スクリーン: 再生する枠の割り当て ==================

local SCREEN_SLOT_NAMES = {}
for index = 1, math.max(0, Config.Screens.MaxActive) do
    SCREEN_SLOT_NAMES[index] = 's' .. index
end

local slotLoading = {} -- [枠の名前] = true（DUI の準備中）
local slotVolume = {}  -- [枠の名前] = 最後に送った音量

-- スクリーンの再生状態を、送る時点の位置に直して返す
local function screenSyncNow(screen)
    if not screen.sync then
        return nil
    end
    local position = screen.sync.position
    if screen.sync.playing then
        position = position + (GetGameTimer() - screen.syncAt) / 1000
    end
    return { playing = screen.sync.playing, position = position }
end

local function releaseSlot(slot)
    screenSlots[slot] = nil
    slotVolume[slot] = nil
    sendDui(slot, 'stop')
end

local function assignSlot(slot, screen)
    screenSlots[slot] = screen.id
    slotVolume[slot] = 0
    slotLoading[slot] = true

    CreateThread(function()
        local ok = createDui(slot) and waitForDui(slot)
        slotLoading[slot] = nil
        local current = screens[screen.id]
        if not ok or screenSlots[slot] ~= screen.id or not current or not current.media then
            if screenSlots[slot] == screen.id then
                screenSlots[slot] = nil
            end
            return
        end

        playOnDui(slot, current.media, 0)
        local sync = screenSyncNow(current)
        if sync then
            sendDui(slot, 'sync', sync)
        end
    end)
end

-- 距離に応じた音量（近いほど大きい）
local function distanceFactor(distance)
    local full, far = Config.Screens.FullVolumeDistance, Config.Screens.AudioDistance
    if distance <= full then
        return 1.0
    end
    if distance >= far then
        return 0.0
    end
    return 1.0 - (distance - full) / (far - full)
end

CreateThread(function()
    while true do
        Wait(500)

        if Config.Screens.Enabled and next(screens) then
            local pedCoords = GetEntityCoords(PlayerPedId())

            -- 動画があって近いスクリーンから、使える枠の数だけ選ぶ
            local candidates = {}
            for id, screen in pairs(screens) do
                if screen.media then
                    local distance = #(pedCoords - screen.geo.center)
                    if distance <= Config.Screens.RenderDistance then
                        candidates[#candidates + 1] = { id = id, distance = distance }
                    end
                end
            end
            table.sort(candidates, function(a, b) return a.distance < b.distance end)

            local wanted = {}
            for index = 1, math.min(#candidates, #SCREEN_SLOT_NAMES) do
                wanted[candidates[index].id] = candidates[index].distance
            end

            -- 遠くなったスクリーンの枠を空ける
            for _, slot in ipairs(SCREEN_SLOT_NAMES) do
                local id = screenSlots[slot]
                if id and (not wanted[id] or not screens[id] or not screens[id].media) and not slotLoading[slot] then
                    releaseSlot(slot)
                end
            end

            -- 新しく近づいたスクリーンに枠を割り当てる
            for id in pairs(wanted) do
                if not slotOfScreen(id) then
                    for _, slot in ipairs(SCREEN_SLOT_NAMES) do
                        if not screenSlots[slot] and not slotLoading[slot] then
                            assignSlot(slot, screens[id])
                            break
                        end
                    end
                end
            end

            -- 距離で音量を変える（自分だけの音量 × 距離）
            for _, slot in ipairs(SCREEN_SLOT_NAMES) do
                local id = screenSlots[slot]
                if id and wanted[id] and not slotLoading[slot] then
                    local base = screenVolume[id] or 50
                    local volume = math.floor(base * distanceFactor(wanted[id]) + 0.5)
                    if slotVolume[slot] == nil or math.abs(slotVolume[slot] - volume) >= 2 or (volume == 0) ~= (slotVolume[slot] == 0) then
                        slotVolume[slot] = volume
                        sendDui(slot, 'volume', { volume = volume })
                    end
                end
            end
        else
            for _, slot in ipairs(SCREEN_SLOT_NAMES) do
                if screenSlots[slot] then
                    releaseSlot(slot)
                end
            end
        end
    end
end)

-- ================== 空間スクリーン: サーバーとの同期 ==================

local function readScreen(data)
    if type(data) ~= 'table' then
        return nil
    end
    local id = tonumber(data.id)
    local x, y, z = finiteNumber(data.x), finiteNumber(data.y), finiteNumber(data.z)
    local heading, width = finiteNumber(data.heading), finiteNumber(data.width)
    if not (id and x and y and z and heading and width) then
        return nil
    end

    local media = nil
    if type(data.media) == 'table' then
        media = MoviePlayer.ParseMedia(data.media.url) -- 受け取る側でも検証する
    end

    local screen = {
        id = id,
        ownerSrc = tonumber(data.ownerSrc),
        ownerName = type(data.ownerName) == 'string' and MoviePlayer.SanitizeName(data.ownerName) or '不明',
        heading = heading,
        width = width,
        media = media,
        sync = nil,
        syncAt = GetGameTimer(),
    }
    if media and type(data.sync) == 'table' and type(data.sync.playing) == 'boolean' and finiteNumber(data.sync.position) then
        screen.sync = { playing = data.sync.playing, position = finiteNumber(data.sync.position) }
    end
    screen.geo = buildGeometry(vector3(x, y, z), heading, width)
    screen.bezel = bezelGeometry(screen.geo)
    return screen
end

local function screenPanelData(screen)
    return {
        id = screen.id,
        ownerName = screen.ownerName,
        width = screen.width,
        height = screenHeight(screen.width),
        platform = screen.media and screen.media.platform or nil,
        kind = screen.media and screen.media.kind or nil,
        hasMedia = screen.media ~= nil,
        canManage = canManage(screen),
        isMine = screen.ownerSrc ~= nil and screen.ownerSrc == myServerId(),
        volume = screenVolume[screen.id] or 50,
        playing = screen.sync and screen.sync.playing or false,
    }
end

local function upsertScreen(data)
    local screen = readScreen(data)
    if not screen then
        return
    end

    local previous = screens[screen.id]
    screens[screen.id] = screen

    local slot = slotOfScreen(screen.id)
    if slot and not slotLoading[slot] then
        local mediaChanged = (previous and previous.media and previous.media.url) ~= (screen.media and screen.media.url)
        if not screen.media then
            releaseSlot(slot)
        elseif mediaChanged then
            playOnDui(slot, screen.media, slotVolume[slot] or 0)
            local sync = screenSyncNow(screen)
            if sync then
                sendDui(slot, 'sync', sync)
            end
        end
    end

    if screenPanelId == screen.id then
        SendNUIMessage({ action = 'screenPanelUpdate', screen = screenPanelData(screen) })
    end
end

RegisterNetEvent('ta-movie-player:screensInit', function(list, admin)
    isAdmin = admin == true
    screens = {}
    if type(list) == 'table' then
        for _, data in ipairs(list) do
            upsertScreen(data)
        end
    end
end)

RegisterNetEvent('ta-movie-player:screenUpsert', function(data)
    upsertScreen(data)
end)

local function closeScreenPanel()
    if not screenPanelId then
        return
    end
    screenPanelId = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'screenPanelClose' })
end

RegisterNetEvent('ta-movie-player:screenRemove', function(id)
    id = tonumber(id)
    if not id or not screens[id] then
        return
    end
    local slot = slotOfScreen(id)
    if slot then
        releaseSlot(slot)
    end
    screens[id] = nil
    if screenPanelId == id then
        closeScreenPanel()
    end
end)

RegisterNetEvent('ta-movie-player:screenSync', function(payload)
    if type(payload) ~= 'table' or type(payload.playing) ~= 'boolean' then
        return
    end
    local screen = screens[tonumber(payload.screenId) or -1]
    local position = finiteNumber(payload.position)
    if not screen or not position or not screen.media then
        return
    end

    screen.sync = { playing = payload.playing, position = position }
    screen.syncAt = GetGameTimer()

    local slot = slotOfScreen(screen.id)
    if slot and not slotLoading[slot] then
        sendDui(slot, 'sync', screen.sync)
    end
    if screenPanelId == screen.id then
        SendNUIMessage({ action = 'screenPanelUpdate', screen = screenPanelData(screen) })
    end
end)

-- ================== 空間スクリーン: 狙っているスクリーン ==================

local function cameraRay()
    local camCoords = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)
    local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
    local direction = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    return camCoords, direction
end

-- カメラから何かに当たるまでの距離（当たらなければ nil）
local function raycast(from, to)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 1 + 16, PlayerPedId(), 7)
    local _, hit, endCoords, surfaceNormal = GetShapeTestResult(handle)
    if hit == 1 or hit == true then
        return endCoords, surfaceNormal
    end
    return nil
end

local aimCache = { frame = -1, id = nil }

-- 心の目（ALT）で狙っているスクリーン。カメラの視線とスクリーンの面の交点で判定する
-- （スクリーンには当たり判定が無いので、ox_target の当たり判定とは別に自前で計算する）
local function aimedScreenId()
    local frame = GetFrameCount()
    if aimCache.frame == frame then
        return aimCache.id
    end
    aimCache.frame = frame
    aimCache.id = nil

    local pedCoords = GetEntityCoords(PlayerPedId())
    local camCoords, direction = cameraRay()
    local bestId, bestT = nil, math.huge

    for id, screen in pairs(screens) do
        local geo = screen.geo
        if #(pedCoords - geo.center) <= Config.Screens.InteractDistance + geo.halfW then
            local denom = dot(direction, geo.forward)
            if denom < -0.0001 then -- 表から見ているときだけ
                local t = dot(geo.center - camCoords, geo.forward) / denom
                if t > 0 and t < bestT and t <= Config.Screens.InteractDistance + 6.0 then
                    local offset = (camCoords + direction * t) - geo.center
                    if math.abs(dot(offset, geo.right)) <= geo.halfW and math.abs(dot(offset, UP)) <= geo.halfH then
                        bestId, bestT = id, t
                    end
                end
            end
        end
    end

    -- 手前に壁などがあって見えていないスクリーンは除く
    if bestId then
        local hitCoords = raycast(camCoords, camCoords + direction * bestT)
        if hitCoords and #(hitCoords - camCoords) < bestT - 0.15 then
            bestId = nil
        end
    end

    aimCache.id = bestId
    return bestId
end

-- ================== 空間スクリーン: 操作パネル ==================

local function openScreenPanel(id)
    local screen = screens[id]
    if not screen or isOpen or placing then
        return
    end
    screenPanelId = id
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'screenPanel', screen = screenPanelData(screen) })
end

registerCallback('screenPanelClose', function()
    closeScreenPanel()
end)

local function panelScreen(data)
    local id = tonumber(data.id)
    if not id or id ~= screenPanelId then
        return nil
    end
    return screens[id]
end

registerCallback('screenControl', function(data)
    local screen = panelScreen(data)
    if not screen or not canManage(screen) then
        return
    end
    if data.action ~= 'pause' and data.action ~= 'play' and data.action ~= 'seek' then
        return
    end
    TriggerServerEvent('ta-movie-player:screenControl', screen.id, data.action, finiteNumber(data.position))
end)

-- 自分だけの音量（ほかの人には影響しない）
registerCallback('screenVolume', function(data)
    local screen = panelScreen(data)
    if not screen then
        return
    end
    screenVolume[screen.id] = clampVolume(data.volume, screenVolume[screen.id] or 50)
    -- すぐに反映させる（距離の係数は次の更新で掛け直す）
    local slot = slotOfScreen(screen.id)
    if slot then
        slotVolume[slot] = nil
    end
end)

registerCallback('screenSetMedia', function(data)
    local screen = panelScreen(data)
    if not screen or not canManage(screen) then
        return { success = false, message = 'このスクリーンの動画を変える権限がありません' }
    end
    local url = type(data.url) == 'string' and data.url or ''
    if url ~= '' then
        local media, reason = MoviePlayer.ParseMedia(url)
        if not media then
            return { success = false, message = reason }
        end
        url = media.url
    end
    TriggerServerEvent('ta-movie-player:setScreenMedia', screen.id, url)
    return { success = true }
end)

registerCallback('screenRemove', function(data)
    local screen = panelScreen(data)
    if not screen or not canManage(screen) then
        return
    end
    TriggerServerEvent('ta-movie-player:removeScreen', screen.id)
    closeScreenPanel()
end)

local startPlacement -- 下で定義

registerCallback('screenMove', function(data)
    local screen = panelScreen(data)
    if not screen or not canManage(screen) then
        return
    end
    closeScreenPanel()
    startPlacement({ mode = 'move', screenId = screen.id, width = screen.width })
end)

-- 心の目（ALT）が無い環境・使わない人のためのコマンド。近くで狙っているか、いちばん近いスクリーンを開く
RegisterCommand('watchscreenmenu', function()
    if not Config.Screens.Enabled then
        return
    end
    local id = aimedScreenId()
    if not id then
        local pedCoords = GetEntityCoords(PlayerPedId())
        local best = Config.Screens.InteractDistance
        for screenId, screen in pairs(screens) do
            local distance = #(pedCoords - screen.geo.center)
            if distance <= best then
                id, best = screenId, distance
            end
        end
    end
    if id then
        openScreenPanel(id)
    else
        toast('info', '近くにスクリーンがありません')
    end
end, false)

-- ================== 空間スクリーン: 配置 ==================

-- 配置中に止めるコントロール（攻撃・武器の切り替え・カバー・拾う・メニュー・矢印キー・決定・戻る・G）
local PLACEMENT_BLOCKED = {
    14, 15, 16, 17, 24, 25, 37, 38, 44, 45, 47, 58, 140, 141, 142, 172, 173, 174, 175,
    177, 191, 194, 199, 200, 201, 202, 241, 242, 257, 261, 262,
}

-- 空中モードの切り替えキー（47 = INPUT_DETONATE、キーボードの G）
local PLACEMENT_AIR_TOGGLE = 47

local function placementHint(state)
    SendNUIMessage({
        action = 'placeHint',
        show = true,
        mode = placing and placing.mode or 'new',
        width = state.width,
        height = screenHeight(state.width),
        valid = state.valid,
        reason = state.reason,
        surface = state.surface,
    })
end

local function stopPlacement()
    if not placing then
        return
    end
    placing = nil
    SendNUIMessage({ action = 'placeHint', show = false })
end

-- カメラが狙っている場所から、置く位置と向きを決める
local function previewPlacement(state)
    local camCoords, direction = cameraRay()
    local maxDistance = Config.Screens.PlaceDistance + 4.0
    local hitCoords, normal = raycast(camCoords, camCoords + direction * maxDistance)
    local halfH = screenHeight(state.width) / 2

    local center, forward, surface
    if state.air then
        -- 空中: カメラの視線の先、state.airDistance の位置に、自分の方を向けて浮かべる。Q / E で回せる
        -- 手前に壁などがあるときは、その手前で止める（壁の向こうに埋もれないように）
        surface = 'air'
        local distance = state.airDistance
        if hitCoords then
            distance = math.min(distance, math.max(0.5, #(hitCoords - camCoords) - 0.15))
        end
        local toCamera = normalize(vector3(-direction.x, -direction.y, 0.0)) or vector3(0.0, 1.0, 0.0)
        forward = headingToForward(forwardToHeading(toCamera) + state.rotation)
        center = camCoords + direction * distance + UP * state.lift

        -- 下の端が床にめり込むときは、床の上まで持ち上げる
        local groundCoords = raycast(center, center - UP * (halfH + 0.05))
        if groundCoords then
            center = vector3(center.x, center.y, groundCoords.z + halfH + 0.05)
        end
    elseif hitCoords and normal then
        if math.abs(normal.z) < 0.6 then
            -- 壁: 壁に沿って、壁から少し浮かせて貼る
            surface = 'wall'
            forward = normalize(vector3(normal.x, normal.y, 0.0)) or vector3(0.0, 1.0, 0.0)
            center = hitCoords + forward * 0.03 + UP * state.lift
        else
            -- 床・天井: 自分の方を向けて立てる（吊るす）。Q / E で回せる
            surface = normal.z > 0 and 'floor' or 'ceiling'
            local toCamera = normalize(vector3(camCoords.x - hitCoords.x, camCoords.y - hitCoords.y, 0.0)) or vector3(0.0, 1.0, 0.0)
            forward = headingToForward(forwardToHeading(toCamera) + state.rotation)
            if surface == 'floor' then
                center = hitCoords + UP * (halfH + 0.05 + state.lift)
            else
                center = hitCoords - UP * (halfH + 0.05 - state.lift)
            end
        end
    else
        surface = 'none'
        local toCamera = normalize(vector3(-direction.x, -direction.y, 0.0)) or vector3(0.0, 1.0, 0.0)
        forward = toCamera
        center = camCoords + direction * Config.Screens.PlaceDistance
    end

    local heading = forwardToHeading(forward)
    local geo = buildGeometry(center, heading, state.width)

    -- 置けるかどうか
    local valid, reason = true, nil
    local pedCoords = GetEntityCoords(PlayerPedId())
    if surface == 'none' then
        valid, reason = false, '壁か床を狙ってください（G で空中に置けます）'
    elseif #(pedCoords - center) > Config.Screens.PlaceDistance then
        valid, reason = false, ('遠すぎます（%dm 以内に置けます）'):format(math.floor(Config.Screens.PlaceDistance))
    else
        for id, other in pairs(screens) do
            if id ~= state.screenId then
                local gap = #(other.geo.center - center)
                if gap < (state.width + other.width) * 0.5 * 0.75 then
                    valid, reason = false, 'ほかのスクリーンと重なっています'
                    break
                end
            end
        end
    end

    return geo, heading, valid, reason, surface
end

startPlacement = function(options)
    if placing or not Config.Screens.Enabled then
        return
    end
    if options.mode == 'new' and not isAdmin and myScreenCount() >= Config.Screens.MaxPerPlayer then
        toast('error', ('置けるスクリーンは%d枚までです。撤去してから置いてください'):format(Config.Screens.MaxPerPlayer))
        return
    end

    placing = {
        mode = options.mode,
        screenId = options.screenId,
        url = options.url,
        width = math.max(Config.Screens.MinWidth, math.min(Config.Screens.MaxWidth, options.width or Config.Screens.DefaultWidth)),
        rotation = 0.0,
        lift = 0.0,
        -- 空中モード（G で切り替え）。壁・床・天井に合わせず、視線の先に浮かべる
        air = false,
        airDistance = Config.Screens.AirDistance,
    }

    CreateThread(function()
        local lastHintAt, lastHintKey = 0, nil
        local lastTime = GetGameTimer()

        while placing do
            Wait(0)
            local state = placing
            local t = GetGameTimer()
            local dt = math.min(0.1, (t - lastTime) / 1000)
            lastTime = t

            for _, control in ipairs(PLACEMENT_BLOCKED) do
                DisableControlAction(0, control, true)
            end

            -- マウスホイールで大きさ、Q / E で回転、↑ / ↓ で高さ
            if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 241) then
                state.width = math.min(Config.Screens.MaxWidth, state.width + Config.Screens.WidthStep)
            elseif IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 242) then
                state.width = math.max(Config.Screens.MinWidth, state.width - Config.Screens.WidthStep)
            end
            if IsDisabledControlPressed(0, 44) then
                state.rotation = state.rotation - 90 * dt
            elseif IsDisabledControlPressed(0, 38) then
                state.rotation = state.rotation + 90 * dt
            end
            if IsDisabledControlPressed(0, 172) then
                state.lift = math.min(4.0, state.lift + 1.0 * dt)
            elseif IsDisabledControlPressed(0, 173) then
                state.lift = math.max(-2.0, state.lift - 1.0 * dt)
            end

            -- G で空中モードの切り替え。高さと向きは、切り替えるたびに戻す（前のモードの調整を持ち越さない）
            if IsDisabledControlJustPressed(0, PLACEMENT_AIR_TOGGLE) then
                state.air = not state.air
                state.lift = 0.0
                state.rotation = 0.0
                PlaySoundFrontend(-1, 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            end

            -- 空中モードでは ← / → で距離（→ で遠く、← で近く）
            if state.air then
                if IsDisabledControlPressed(0, 175) then
                    state.airDistance = math.min(Config.Screens.AirMaxDistance, state.airDistance + 2.0 * dt)
                elseif IsDisabledControlPressed(0, 174) then
                    state.airDistance = math.max(Config.Screens.AirMinDistance, state.airDistance - 2.0 * dt)
                end
            end

            local geo, heading, valid, reason, surface = previewPlacement(state)

            -- ハイライト（置ける = 緑、置けない = 赤）。裏からも見えるよう両面に描く
            local r, g, b = 76, 195, 138
            if not valid then
                r, g, b = 229, 72, 77
            end
            drawQuad(geo, r, g, b, 70)
            drawQuadBack(geo, r, g, b, 70)
            drawOutline(geo, r, g, b, 255)
            local arrowTip = geo.center + geo.forward * 0.4
            DrawLine(geo.center.x, geo.center.y, geo.center.z, arrowTip.x, arrowTip.y, arrowTip.z, r, g, b, 255)

            -- 案内の表示は変わったときだけ送る
            local key = ('%.2f|%s|%s|%s'):format(state.width, tostring(valid), reason or '', surface)
            if key ~= lastHintKey and (t - lastHintAt) > 80 then
                lastHintKey, lastHintAt = key, t
                placementHint({ width = state.width, valid = valid, reason = reason, surface = surface })
            end

            -- 決定（左クリック / Enter）・やめる（右クリック / Backspace / ESC）
            if IsDisabledControlJustPressed(0, 24) or IsDisabledControlJustPressed(0, 191) then
                if valid then
                    local data = { x = geo.center.x, y = geo.center.y, z = geo.center.z, heading = heading, width = state.width }
                    if state.mode == 'move' then
                        TriggerServerEvent('ta-movie-player:moveScreen', state.screenId, data)
                    else
                        TriggerServerEvent('ta-movie-player:placeScreen', data, state.url or '')
                    end
                    stopPlacement()
                else
                    PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                end
            elseif IsDisabledControlJustPressed(0, 25) or IsDisabledControlJustPressed(0, 177)
                or IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 202) then
                stopPlacement()
                toast('info', 'スクリーンの配置をやめました')
            end
        end
    end)
end

-- 入力画面の「空間にスクリーンを置く」（URL を入れていれば、置いたスクリーンでそのまま再生する）
registerCallback('startPlacement', function(data)
    if not Config.Screens.Enabled then
        return { success = false, message = '空間スクリーンは使えません' }
    end

    local url = ''
    if type(data.url) == 'string' and data.url:match('%S') then
        local media, reason = MoviePlayer.ParseMedia(data.url)
        if not media then
            return { success = false, message = reason }
        end
        url = media.url
    end
    if not isAdmin and myScreenCount() >= Config.Screens.MaxPerPlayer then
        return { success = false, message = ('置けるスクリーンは%d枚までです。撤去してから置いてください'):format(Config.Screens.MaxPerPlayer) }
    end

    closePlayer()
    startPlacement({ mode = 'new', url = url })
    return { success = true }
end)

RegisterCommand('watchscreen', function()
    if isOpen or screenPanelId then
        return
    end
    startPlacement({ mode = 'new' })
end, false)

-- 心の目（ALT）のメニュー。スクリーンには当たり判定が無いので、全体のオプションに足して
-- 「視線がスクリーンに当たっているか」を canInteract で毎回判定する
local function registerTargetOptions()
    if not Config.Screens.Enabled or GetResourceState('ox_target') ~= 'started' then
        return
    end

    -- 参加時は自分と ox_target の両方の起動イベントから呼ばれることがあるので、
    -- 先に同じ名前のオプションを外してから足す（二重登録の警告を出さない）
    exports.ox_target:removeGlobalOption({ 'ta-movie-player:screen-panel', 'ta-movie-player:screen-move' })

    local lastAimed = nil
    exports.ox_target:addGlobalOption({
        {
            name = 'ta-movie-player:screen-panel',
            icon = 'fa-solid fa-tv',
            label = 'スクリーンを操作する',
            canInteract = function()
                lastAimed = aimedScreenId()
                return lastAimed ~= nil
            end,
            onSelect = function()
                if lastAimed then
                    openScreenPanel(lastAimed)
                end
            end,
        },
        {
            name = 'ta-movie-player:screen-move',
            icon = 'fa-solid fa-up-down-left-right',
            label = 'スクリーンの位置・大きさを変える',
            canInteract = function()
                local id = aimedScreenId()
                return id ~= nil and screens[id] ~= nil and canManage(screens[id])
            end,
            onSelect = function()
                local id = aimedScreenId() or lastAimed
                local screen = id and screens[id]
                if screen and canManage(screen) then
                    startPlacement({ mode = 'move', screenId = id, width = screen.width })
                end
            end,
        },
    })
end

-- ================== 描画スレッド（視聴画面） ==================

-- DUI を画面に描画（再生中だけ毎フレーム回す）
CreateThread(function()
    while true do
        if isPlaying and duis.main then
            Wait(0)

            -- 位置と大きさは、NUI が枠から計算して送ってくる（動画の上に表示物を重ねないため）
            local rect = videoRect
            if not rect then
                local aspect = GetAspectRatio(false)
                local width = Config.VideoWidth
                local height = width * aspect * 9 / 16
                if height > Config.VideoMaxHeight then
                    height = Config.VideoMaxHeight
                    width = height * 16 / (9 * aspect)
                end
                rect = { cx = 0.5, cy = Config.VideoCenterY, w = width, h = height }
            end

            SetScriptGfxDrawBehindPausemenu(true)
            DrawSprite(TXD_NAME, textureName('main'), rect.cx, rect.cy, rect.w, rect.h, 0.0, 255, 255, 255, 255)
            SetScriptGfxDrawBehindPausemenu(false)
        else
            Wait(100)
        end
    end
end)

-- ================== キー入力処理 ==================

-- ESC で閉じる（キーボードがゲームへ渡っているとき用。NUI にフォーカスがあるときは JS 側で閉じる）
-- 視聴画面でゲームへ入力を渡している間は、視点と攻撃を無効にする。移動を許可しない設定なら移動も止める
CreateThread(function()
    while true do
        if isOpen then
            Wait(0)
            if keepsGameInput and not Config.AllowMovementWhileWatching then
                DisableAllControlActions(0)
                for _, control in ipairs(Config.ControlsAllowedWhileWatching or {}) do
                    EnableControlAction(0, control, true)
                end
            elseif keepsGameInput then
                for _, control in ipairs(CONTROLS_BLOCKED_WHILE_KEEPING_INPUT) do
                    DisableControlAction(0, control, true)
                end
            end
            DisableControlAction(0, 200, true) -- ESC
            if IsDisabledControlJustReleased(0, 200) then
                closePlayer()
            end
        elseif screenPanelId then
            Wait(0)
            DisableControlAction(0, 200, true)
            if IsDisabledControlJustReleased(0, 200) then
                closeScreenPanel()
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
    if Config.Screens.Enabled then
        TriggerEvent('chat:addSuggestion', '/watchscreen', '空間にスクリーンを置く')
        TriggerEvent('chat:addSuggestion', '/watchscreenmenu', '近くのスクリーンを操作する')
    end
end

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        registerSuggestions()
        registerTargetOptions()
        TriggerServerEvent('ta-movie-player:requestScreens')
    elseif resourceName == 'chat' then
        registerSuggestions()
    elseif resourceName == 'ox_target' then
        registerTargetOptions()
    end
end)
