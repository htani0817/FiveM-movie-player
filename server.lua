-- movie-player サーバースクリプト
-- 画面共有イベントの検証と中継
-- クライアントから届く値は全て信用せず、送信者・URL・共有先・頻度をサーバ側で検証する

local lastShareAt = {}   -- [送信者のサーバーID] = 最後に共有した時刻（GetGameTimer）
local pendingOffers = {} -- [受信者のサーバーID] = { from = 送信者のサーバーID, expires = 有効期限 }

-- 受信者が返せる応答の種類
local RESPONSE_STATUSES = {
    accepted = true,
    declined = true,
    timeout = true,
    invalid = true,
}

-- 送信者へ通知を送る（kind: 'error' | 'info'）
local function notify(target, kind, message)
    TriggerClientEvent('movie-player:notify', target, kind, message)
end

-- 2人のプレイヤーが距離内にいるかを返す
-- OneSync が無効などでサーバから座標を取れない場合は検証できないので通す
local function isWithinRange(sourceA, sourceB)
    if not Config.ServerDistanceCheck then
        return true
    end

    -- GetPlayerPed はプレイヤーの source を「文字列」で受け取る（公式ドキュメントの仕様）
    local pedA = GetPlayerPed(tostring(sourceA))
    local pedB = GetPlayerPed(tostring(sourceB))
    if not pedA or pedA == 0 or not pedB or pedB == 0 then
        return true
    end
    if not DoesEntityExist(pedA) or not DoesEntityExist(pedB) then
        return true
    end

    local distance = #(GetEntityCoords(pedA) - GetEntityCoords(pedB))
    return distance <= (Config.NearbyDistance + Config.ServerDistanceMargin)
end

-- 画面共有: クライアント → サーバー
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

    if type(targetPlayers) ~= 'table' then
        notify(src, 'error', '共有先が不正です')
        return
    end

    -- 連続送信の制限
    local now = GetGameTimer()
    local last = lastShareAt[src]
    if last and (now - last) < Config.ShareCooldownMs then
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
            if GetPlayerName(tostring(id)) and isWithinRange(src, id) then
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

    lastShareAt[src] = now

    local senderName = MoviePlayer.SanitizeName(GetPlayerName(tostring(src)))
    MoviePlayer.Log(('player %d shares %s to %d players'):format(src, media.platform, #targets))

    for _, targetId in ipairs(targets) do
        pendingOffers[targetId] = {
            from = src,
            expires = now + Config.ShareRequestTimeoutMs + 5000,
        }
        TriggerClientEvent('movie-player:receiveShare', targetId, media.url, senderName, src)
    end

    TriggerClientEvent('movie-player:shareResult', src, #targets, skipped)
end)

-- 受信者の応答（視聴する / 辞退 / 時間切れ）を送信者へ伝える
-- 直前にこの受信者へ共有した送信者がいる場合だけ有効
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

    if GetGameTimer() > offer.expires then
        return
    end

    local senderName = GetPlayerName(tostring(offer.from))
    if not senderName then
        return
    end

    local receiverName = MoviePlayer.SanitizeName(GetPlayerName(tostring(src)))
    TriggerClientEvent('movie-player:shareReply', offer.from, receiverName, status)
end)

-- 退出したプレイヤーの状態を片付ける（サーバーIDは再利用されるため）
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then
        return
    end

    lastShareAt[src] = nil
    pendingOffers[src] = nil
    for targetId, offer in pairs(pendingOffers) do
        if offer.from == src then
            pendingOffers[targetId] = nil
        end
    end
end)

-- リソース開始時のログ
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        print("[movie-player] Resource started")
    end
end)
