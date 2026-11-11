-- movie-player サーバースクリプト
-- 共有・上映（同期再生）・参加の申請・空間スクリーンの検証と中継
-- クライアントから届く値は全て信用せず、送信者・URL・相手・数値・頻度をサーバ側で検証する

local lastShareAt = {}   -- [送信者のサーバーID] = 最後に共有した時刻（GetGameTimer）
local pendingOffers = {} -- [受信者のサーバーID] = { from = 送信者, sessionId = 上映ID, expires = 有効期限 }

-- 上映（同じ動画をいっしょに観ている集まり）。ホストの再生位置に参加者を合わせる
local sessions = {}      -- [上映ID] = { id, host, hostName, media, members = { [サーバーID] = true }, count, state }
local playerSession = {} -- [サーバーID] = 上映ID
local nextSessionId = 0

-- 参加の申請
local joinRequests = {}       -- [申請者のサーバーID] = { sessionId, host, expires }
local lastJoinRequestAt = {}  -- [申請者のサーバーID] = 時刻
local lastListAt = {}         -- [サーバーID] = 上映一覧を最後に返した時刻
local lastHostStateAt = {}    -- [ホストのサーバーID] = 再生位置の報告を最後に受けた時刻

-- 空間スクリーン（再起動で消える）
local screens = {}            -- [スクリーンID] = { id, owner, ownerSrc, ownerName, x, y, z, heading, width, media, state }
local nextScreenId = 0
local lastScreenActionAt = {} -- [サーバーID] = 時刻

-- 受信者が返せる応答の種類
local RESPONSE_STATUSES = {
    accepted = true,
    declined = true,
    timeout = true,
    invalid = true,
}

local MAX_POSITION = 60 * 60 * 24 -- 再生位置として受け付ける上限（秒）

-- ================== 共通 ==================

local function now()
    return GetGameTimer()
end

-- 通知を送る（kind: 'error' | 'info' | 'success'）
local function notify(target, kind, message)
    TriggerClientEvent('movie-player:notify', target, kind, message)
end

local function playerName(src)
    return MoviePlayer.SanitizeName(GetPlayerName(tostring(src)))
end

local function isOnline(src)
    return GetPlayerName(tostring(src)) ~= nil
end

-- 数値として正しい（NaN・無限大でない）値だけを返す
local function finiteNumber(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- プレイヤーの座標。OneSync が無効などで取れなければ nil
local function getPlayerCoords(src)
    -- GetPlayerPed はプレイヤーの source を「文字列」で受け取る（公式ドキュメントの仕様）
    local ped = GetPlayerPed(tostring(src))
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return nil
    end
    return GetEntityCoords(ped)
end

-- 2人のプレイヤーが距離内にいるかを返す
-- OneSync が無効などでサーバから座標を取れない場合は検証できないので通す
local function isWithinRange(sourceA, sourceB)
    if not Config.ServerDistanceCheck then
        return true
    end

    local a, b = getPlayerCoords(sourceA), getPlayerCoords(sourceB)
    if not a or not b then
        return true
    end
    return #(a - b) <= (Config.NearbyDistance + Config.ServerDistanceMargin)
end

-- プレイヤーが座標の近くにいるかを返す（座標を取れない環境では通す）
local function isNearPoint(src, point, distance)
    if not Config.ServerDistanceCheck then
        return true
    end

    local coords = getPlayerCoords(src)
    if not coords then
        return true
    end
    return #(coords - point) <= distance + Config.ServerDistanceMargin
end

-- 再生状態 { playing, position, at } の「いま」の再生位置
local function currentPosition(state)
    if state.playing then
        return state.position + (now() - state.at) / 1000
    end
    return state.position
end

-- クライアントへ送る再生状態（送る時点の位置に直して送る）
local function syncPayload(state)
    return { playing = state.playing, position = currentPosition(state) }
end

-- 共有・上映・スクリーンの再生に使うメディア情報（クライアントでも検証し直す）
local function publicMedia(media)
    return { url = media.url, platform = media.platform, kind = media.kind, id = media.id }
end

-- ================== 上映（同期再生） ==================

local function sessionInfo(session, member)
    return {
        sessionId = session.id,
        isHost = member == session.host,
        hostId = session.host,
        hostName = session.hostName,
        memberCount = session.count,
        platform = session.media.platform,
    }
end

-- 参加者全員に、人数などの情報を送り直す
local function broadcastSessionInfo(session)
    for member in pairs(session.members) do
        TriggerClientEvent('movie-player:sessionInfo', member, sessionInfo(session, member))
    end
end

-- ホスト以外の参加者に再生状態を送る
local function broadcastSessionSync(session)
    local payload = syncPayload(session.state)
    payload.sessionId = session.id
    for member in pairs(session.members) do
        if member ~= session.host then
            TriggerClientEvent('movie-player:sessionSync', member, payload)
        end
    end
end

-- 申請中の参加を取り消す（上映が終わった・申請者が退出したなど）
local function cancelJoinRequest(requester, reason)
    local request = joinRequests[requester]
    if not request then
        return
    end
    joinRequests[requester] = nil

    if isOnline(request.host) then
        TriggerClientEvent('movie-player:joinRequestEnd', request.host, requester)
    end
    if reason and isOnline(requester) then
        notify(requester, 'info', reason)
    end
end

local function endSession(session, reason)
    sessions[session.id] = nil
    for member in pairs(session.members) do
        if playerSession[member] == session.id then
            playerSession[member] = nil
        end
        if member ~= session.host and isOnline(member) then
            TriggerClientEvent('movie-player:sessionEnded', member, session.id, reason)
        end
    end
    for requester, request in pairs(joinRequests) do
        if request.sessionId == session.id then
            cancelJoinRequest(requester, 'ホストが上映を終えたため、参加の申請を取り消しました')
        end
    end
    MoviePlayer.Log(('session %d ended'):format(session.id))
end

-- 今の上映から抜ける。ホストが抜けたら上映を終える
local function leaveSession(src)
    local id = playerSession[src]
    if not id then
        return
    end
    playerSession[src] = nil

    local session = sessions[id]
    if not session then
        return
    end

    if session.host == src then
        endSession(session, 'host_left')
        return
    end

    if session.members[src] then
        session.members[src] = nil
        session.count = session.count - 1
        broadcastSessionInfo(session)
    end
end

local function addMember(session, src)
    if session.members[src] then
        return true
    end
    if session.count >= Config.MaxSessionMembers then
        return false
    end

    leaveSession(src)
    session.members[src] = true
    session.count = session.count + 1
    playerSession[src] = session.id
    broadcastSessionInfo(session)

    local payload = syncPayload(session.state)
    payload.sessionId = session.id
    TriggerClientEvent('movie-player:sessionSync', src, payload)
    return true
end

-- ホストとして新しい上映を始める（前の上映からは抜ける）
local function startSession(src, media)
    leaveSession(src)

    nextSessionId = nextSessionId + 1
    local session = {
        id = nextSessionId,
        host = src,
        hostName = playerName(src),
        media = media,
        members = { [src] = true },
        count = 1,
        state = { playing = true, position = 0, at = now() },
    }
    sessions[session.id] = session
    playerSession[src] = session.id
    TriggerClientEvent('movie-player:sessionInfo', src, sessionInfo(session, src))
    MoviePlayer.Log(('session %d started by %d (%s)'):format(session.id, src, media.platform))
    return session
end

-- ひとりで再生を始めたとき（共有なし）も上映として扱い、近くの人が参加を申請できるようにする
RegisterNetEvent('movie-player:startSession', function(url)
    local src = tonumber(source)
    if not src then
        return
    end

    local media = MoviePlayer.ParseMedia(url)
    if not media then
        return
    end
    startSession(src, media)
end)

RegisterNetEvent('movie-player:leaveSession', function()
    local src = tonumber(source)
    if src then
        leaveSession(src)
    end
end)

-- ホストの再生位置の報告（定期と、一時停止・シークしたとき）
RegisterNetEvent('movie-player:hostState', function(playing, position)
    local src = tonumber(source)
    if not src then
        return
    end

    local session = sessions[playerSession[src] or -1]
    if not session or session.host ~= src then
        return
    end

    position = finiteNumber(position)
    if type(playing) ~= 'boolean' or not position then
        return
    end

    -- 報告の頻度を抑える（操作の直後に続けて届くことがあるので、ごく短い間隔だけ弾く）
    local t = now()
    if lastHostStateAt[src] and (t - lastHostStateAt[src]) < 250 then
        return
    end
    lastHostStateAt[src] = t

    session.state = { playing = playing, position = clamp(position, 0, MAX_POSITION), at = t }
    broadcastSessionSync(session)
end)

-- 参加者が再生を始めたときに、今の再生状態を問い合わせる
RegisterNetEvent('movie-player:requestSync', function()
    local src = tonumber(source)
    if not src then
        return
    end

    local session = sessions[playerSession[src] or -1]
    if not session or session.host == src then
        return
    end

    local payload = syncPayload(session.state)
    payload.sessionId = session.id
    TriggerClientEvent('movie-player:sessionSync', src, payload)
end)

-- ================== 共有（ホストから近くの人へ） ==================

-- 引数は url と targetPlayers のみ。送信者の名前と ID は source から取得する
RegisterNetEvent('movie-player:shareVideo', function(url, targetPlayers)
    local src = tonumber(source)
    if not src then
        return
    end

    -- URL（正規化したものだけを中継する）
    local media, reason = MoviePlayer.ParseMedia(url)
    if not media then
        notify(src, 'error', reason)
        return
    end

    -- 共有した本人はすでに再生を始めているので、検証で弾いても上映は作っておく
    local session = startSession(src, media)

    if type(targetPlayers) ~= 'table' then
        notify(src, 'error', '共有先が不正です')
        return
    end

    -- 連続送信の制限
    local t = now()
    local last = lastShareAt[src]
    if last and (t - last) < Config.ShareCooldownMs then
        notify(src, 'error', '共有の間隔が短すぎます。少し待ってからもう一度お試しください')
        return
    end

    -- 共有先の検証（型・人数上限・在線・重複・距離）
    local targets = {}
    local seen = {}
    local skipped = 0

    for index, raw in ipairs(targetPlayers) do
        if index > Config.MaxShareTargets then
            notify(src, 'error', ('一度に共有できるのは%d人までです'):format(Config.MaxShareTargets))
            return
        end

        local id = tonumber(raw)
        if id and id > 0 and id == math.floor(id) and id ~= src and not seen[id] then
            seen[id] = true
            if isOnline(id) and isWithinRange(src, id) then
                targets[#targets + 1] = id
            else
                skipped = skipped + 1
            end
        end
    end

    if #targets == 0 then
        notify(src, 'error', '共有できるプレイヤーがいません（離れた、または退出した可能性があります）')
        return
    end

    lastShareAt[src] = t
    MoviePlayer.Log(('player %d shares %s to %d players'):format(src, media.platform, #targets))

    for _, targetId in ipairs(targets) do
        pendingOffers[targetId] = {
            from = src,
            sessionId = session.id,
            expires = t + Config.ShareRequestTimeoutMs + 5000,
        }
        TriggerClientEvent('movie-player:receiveShare', targetId, media.url, session.hostName, src)
    end

    TriggerClientEvent('movie-player:shareResult', src, #targets, skipped)
end)

-- 受信者の応答（視聴する / 辞退 / 時間切れ）を送信者へ伝える
-- 直前にこの受信者へ共有した送信者がいる場合だけ有効。視聴するなら上映に加える
RegisterNetEvent('movie-player:shareResponse', function(status)
    local src = tonumber(source)
    if not src then
        return
    end
    if type(status) ~= 'string' or not RESPONSE_STATUSES[status] then
        return
    end

    local offer = pendingOffers[src]
    if not offer then
        return
    end
    pendingOffers[src] = nil

    if now() > offer.expires or not isOnline(offer.from) then
        return
    end

    if status == 'accepted' then
        local session = sessions[offer.sessionId]
        if session and session.host == offer.from and not addMember(session, src) then
            notify(src, 'info', '上映の人数が上限に達しているため、同期せずに再生します')
        end
    end

    TriggerClientEvent('movie-player:shareReply', offer.from, playerName(src), status)
end)

-- ================== 参加の申請（近くの人からホストへ） ==================

-- 近くで上映している上映の一覧（自分が参加していないもの）
RegisterNetEvent('movie-player:listSessions', function()
    local src = tonumber(source)
    if not src or not Config.JoinRequestEnabled then
        return
    end

    local t = now()
    if lastListAt[src] and (t - lastListAt[src]) < 1000 then
        return
    end
    lastListAt[src] = t

    local list = {}
    local mine = playerSession[src]
    for id, session in pairs(sessions) do
        if id ~= mine and session.host ~= src and isWithinRange(src, session.host) then
            list[#list + 1] = {
                sessionId = id,
                hostId = session.host,
                hostName = session.hostName,
                platform = session.media.platform,
                memberCount = session.count,
                full = session.count >= Config.MaxSessionMembers,
                pending = joinRequests[src] ~= nil and joinRequests[src].sessionId == id,
            }
        end
    end
    TriggerClientEvent('movie-player:sessionList', src, list)
end)

RegisterNetEvent('movie-player:requestJoin', function(sessionId)
    local src = tonumber(source)
    if not src or not Config.JoinRequestEnabled then
        return
    end

    sessionId = tonumber(sessionId)
    local session = sessionId and sessions[sessionId]
    if not session then
        notify(src, 'error', 'この上映は終わりました')
        return
    end
    if session.host == src or session.members[src] then
        return
    end
    if session.count >= Config.MaxSessionMembers then
        notify(src, 'error', 'この上映は人数が上限に達しています')
        return
    end
    if not isWithinRange(src, session.host) then
        notify(src, 'error', 'ホストから離れているため、申請できません')
        return
    end

    local t = now()
    if lastJoinRequestAt[src] and (t - lastJoinRequestAt[src]) < Config.JoinRequestCooldownMs then
        notify(src, 'error', '申請の間隔が短すぎます。少し待ってからもう一度お試しください')
        return
    end
    lastJoinRequestAt[src] = t

    -- 申請は同時に1件だけ（前の申請は取り消す）
    cancelJoinRequest(src)

    local expires = t + Config.JoinRequestTimeoutMs
    joinRequests[src] = { sessionId = session.id, host = session.host, expires = expires }
    TriggerClientEvent('movie-player:joinRequest', session.host, src, playerName(src), Config.JoinRequestTimeoutMs)
    notify(src, 'info', ('%sさんに参加を申請しました'):format(session.hostName))

    SetTimeout(Config.JoinRequestTimeoutMs + 1000, function()
        local request = joinRequests[src]
        if request and request.expires == expires then
            cancelJoinRequest(src, ('%sさんから応答がありませんでした'):format(session.hostName))
        end
    end)
end)

-- ホストの答え（許可 / 拒否）
RegisterNetEvent('movie-player:joinResponse', function(requester, approved)
    local src = tonumber(source)
    requester = tonumber(requester)
    if not src or not requester or type(approved) ~= 'boolean' then
        return
    end

    local request = joinRequests[requester]
    if not request or request.host ~= src then
        return
    end
    joinRequests[requester] = nil

    local session = sessions[request.sessionId]
    if not session or session.host ~= src or not isOnline(requester) then
        return
    end

    local hostName = session.hostName
    if not approved then
        notify(requester, 'info', ('%sさんは参加の申請を断りました'):format(hostName))
        return
    end

    if not addMember(session, requester) then
        notify(requester, 'error', 'この上映は人数が上限に達しています')
        notify(src, 'info', '人数が上限に達しているため、参加できませんでした')
        return
    end

    TriggerClientEvent('movie-player:joinApproved', requester, session.media.url, hostName)
    notify(src, 'success', ('%sさんが参加しました'):format(playerName(requester)))
end)

-- ================== 空間スクリーン ==================

local function licenseOf(src)
    local license = GetPlayerIdentifierByType(tostring(src), 'license')
    return license or ('src:' .. tostring(src))
end

-- IsPlayerAceAllowed は許可のとき true ではなく 1 を返す（2026-11-11 に実機で確認）。どちらでも通す
-- Lua では 0 も真になるので、真偽をそのまま使わずに true か 1 かで見る
local function isAdmin(src)
    local allowed = IsPlayerAceAllowed(tostring(src), Config.Screens.AdminAce)
    return allowed == true or allowed == 1
end

local function canManageScreen(src, screen)
    return isAdmin(src) or screen.owner == licenseOf(src)
end

-- クライアントへ送るスクリーンの情報（持ち主の license は送らない）
local function publicScreen(screen)
    return {
        id = screen.id,
        ownerSrc = screen.ownerSrc,
        ownerName = screen.ownerName,
        x = screen.x,
        y = screen.y,
        z = screen.z,
        heading = screen.heading,
        width = screen.width,
        media = screen.media and publicMedia(screen.media) or nil,
        sync = screen.media and syncPayload(screen.state) or nil,
    }
end

local function broadcastScreen(screen)
    TriggerClientEvent('movie-player:screenUpsert', -1, publicScreen(screen))
end

-- 置く・動かす・動画の変更の頻度を抑える
local function screenActionAllowed(src)
    local t = now()
    if lastScreenActionAt[src] and (t - lastScreenActionAt[src]) < Config.Screens.ActionCooldownMs then
        notify(src, 'error', '操作の間隔が短すぎます。少し待ってからもう一度お試しください')
        return false
    end
    lastScreenActionAt[src] = t
    return true
end

-- 位置・向き・幅を検証して返す。不正なら nil とエラーメッセージ
local function readPlacement(src, data)
    if type(data) ~= 'table' then
        return nil, '配置の情報が不正です'
    end

    local x, y, z = finiteNumber(data.x), finiteNumber(data.y), finiteNumber(data.z)
    local heading, width = finiteNumber(data.heading), finiteNumber(data.width)
    if not (x and y and z and heading and width) then
        return nil, '配置の情報が不正です'
    end
    if math.abs(x) > 20000 or math.abs(y) > 20000 or z < -500 or z > 3000 then
        return nil, '置けない場所です'
    end

    local point = vector3(x, y, z)
    if not isNearPoint(src, point, Config.Screens.PlaceDistance) then
        return nil, '離れすぎているため置けません'
    end

    return {
        x = x,
        y = y,
        z = z,
        heading = heading % 360,
        width = clamp(width, Config.Screens.MinWidth, Config.Screens.MaxWidth),
    }
end

local function countScreensOf(owner)
    local count = 0
    for _, screen in pairs(screens) do
        if screen.owner == owner then
            count = count + 1
        end
    end
    return count
end

local function setScreenMedia(screen, media)
    screen.media = media
    screen.state = { playing = true, position = 0, at = now() }
end

-- 置く（url を付けると、置いたスクリーンでそのまま再生する）
RegisterNetEvent('movie-player:placeScreen', function(data, url)
    local src = tonumber(source)
    if not src or not Config.Screens.Enabled then
        return
    end

    local placement, reason = readPlacement(src, data)
    if not placement then
        notify(src, 'error', reason)
        return
    end

    local media
    if url ~= nil and url ~= '' then
        local err
        media, err = MoviePlayer.ParseMedia(url)
        if not media then
            notify(src, 'error', err)
            return
        end
    end

    local owner = licenseOf(src)
    if not isAdmin(src) and countScreensOf(owner) >= Config.Screens.MaxPerPlayer then
        notify(src, 'error', ('置けるスクリーンは%d枚までです。撤去してから置いてください'):format(Config.Screens.MaxPerPlayer))
        return
    end
    if not screenActionAllowed(src) then
        return
    end

    nextScreenId = nextScreenId + 1
    local screen = {
        id = nextScreenId,
        owner = owner,
        ownerSrc = src,
        ownerName = playerName(src),
    }
    for key, value in pairs(placement) do
        screen[key] = value
    end
    if media then
        setScreenMedia(screen, media)
    end

    screens[screen.id] = screen
    broadcastScreen(screen)
    notify(src, 'success', 'スクリーンを置きました。心の目（ALT）で操作できます')
    MoviePlayer.Log(('screen %d placed by %d'):format(screen.id, src))
end)

-- 位置・大きさを変える
RegisterNetEvent('movie-player:moveScreen', function(id, data)
    local src = tonumber(source)
    local screen = screens[tonumber(id) or -1]
    if not src or not screen then
        return
    end
    if not canManageScreen(src, screen) then
        notify(src, 'error', 'このスクリーンを動かす権限がありません')
        return
    end

    local placement, reason = readPlacement(src, data)
    if not placement then
        notify(src, 'error', reason)
        return
    end
    if not screenActionAllowed(src) then
        return
    end

    for key, value in pairs(placement) do
        screen[key] = value
    end
    broadcastScreen(screen)
    notify(src, 'success', 'スクリーンを動かしました')
end)

RegisterNetEvent('movie-player:removeScreen', function(id)
    local src = tonumber(source)
    local screen = screens[tonumber(id) or -1]
    if not src or not screen then
        return
    end
    if not canManageScreen(src, screen) then
        notify(src, 'error', 'このスクリーンを撤去する権限がありません')
        return
    end

    screens[screen.id] = nil
    TriggerClientEvent('movie-player:screenRemove', -1, screen.id)
    notify(src, 'success', 'スクリーンを撤去しました')
end)

-- 動画を変える（空の URL なら止める）
RegisterNetEvent('movie-player:setScreenMedia', function(id, url)
    local src = tonumber(source)
    local screen = screens[tonumber(id) or -1]
    if not src or not screen then
        return
    end
    if not canManageScreen(src, screen) then
        notify(src, 'error', 'このスクリーンの動画を変える権限がありません')
        return
    end

    local media
    if url ~= nil and url ~= '' then
        local err
        media, err = MoviePlayer.ParseMedia(url)
        if not media then
            notify(src, 'error', err)
            return
        end
    end
    if not screenActionAllowed(src) then
        return
    end

    if media then
        setScreenMedia(screen, media)
    else
        screen.media = nil
        screen.state = nil
    end
    broadcastScreen(screen)
end)

-- 再生・一時停止・シーク（置いた人と管理者だけ。音量は各自がクライアントで変える）
RegisterNetEvent('movie-player:screenControl', function(id, action, position)
    local src = tonumber(source)
    local screen = screens[tonumber(id) or -1]
    if not src or not screen or not screen.media then
        return
    end
    if not canManageScreen(src, screen) then
        notify(src, 'error', 'このスクリーンを操作する権限がありません')
        return
    end

    local current = currentPosition(screen.state)
    position = finiteNumber(position)

    if action == 'pause' then
        screen.state = { playing = false, position = position or current, at = now() }
    elseif action == 'play' then
        screen.state = { playing = true, position = position or current, at = now() }
    elseif action == 'seek' and position then
        screen.state = { playing = screen.state.playing, position = clamp(position, 0, MAX_POSITION), at = now() }
    else
        return
    end

    local payload = syncPayload(screen.state)
    payload.screenId = screen.id
    TriggerClientEvent('movie-player:screenSync', -1, payload)
end)

-- 参加したときに、置かれているスクリーンを全部送る
RegisterNetEvent('movie-player:requestScreens', function()
    local src = tonumber(source)
    if not src then
        return
    end

    local list = {}
    for _, screen in pairs(screens) do
        list[#list + 1] = publicScreen(screen)
    end
    TriggerClientEvent('movie-player:screensInit', src, list, isAdmin(src))
end)

-- 再接続した持ち主を、スクリーンの持ち主として表示し直す
AddEventHandler('playerJoining', function()
    local src = tonumber(source)
    if not src then
        return
    end

    local owner = licenseOf(src)
    for _, screen in pairs(screens) do
        if screen.owner == owner then
            screen.ownerSrc = src
            screen.ownerName = playerName(src)
            broadcastScreen(screen)
        end
    end
end)

-- ================== 退出 ==================

-- 退出したプレイヤーの状態を片付ける（サーバーIDは再利用されるため）
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then
        return
    end

    -- 上映を終える前に、このホストへの申請を「退出したため」として取り消す
    for requester, request in pairs(joinRequests) do
        if request.host == src then
            cancelJoinRequest(requester, 'ホストが退出したため、参加の申請を取り消しました')
        end
    end
    cancelJoinRequest(src)
    leaveSession(src)

    lastShareAt[src] = nil
    lastJoinRequestAt[src] = nil
    lastListAt[src] = nil
    lastHostStateAt[src] = nil
    lastScreenActionAt[src] = nil
    pendingOffers[src] = nil
    for targetId, offer in pairs(pendingOffers) do
        if offer.from == src then
            pendingOffers[targetId] = nil
        end
    end

    for id, screen in pairs(screens) do
        if screen.ownerSrc == src then
            screen.ownerSrc = nil
            if Config.Screens.RemoveOnOwnerDrop then
                screens[id] = nil
                TriggerClientEvent('movie-player:screenRemove', -1, id)
            else
                broadcastScreen(screen)
            end
        end
    end
end)

-- リソース開始時のログ
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        print('[movie-player] Resource started')
    end
end)
