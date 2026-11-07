-- movie-player 共通処理（client / server の両方から読み込まれる）
-- URLの検証は必ずここを通す。受け取った文字列をそのまま信用せず、
-- 許可したホストと形式に一致したものだけを「正規化したURL」に作り直して使う。
MoviePlayer = {}

-- 許可するホスト（完全一致。部分一致は使わない）
local YOUTUBE_HOSTS = {
    ['youtube.com'] = true,
    ['www.youtube.com'] = true,
    ['m.youtube.com'] = true,
    ['music.youtube.com'] = true,
}

local TWITCH_HOSTS = {
    ['twitch.tv'] = true,
    ['www.twitch.tv'] = true,
    ['m.twitch.tv'] = true,
}

-- チャンネル名として扱わない Twitch の予約パス
local TWITCH_RESERVED = {
    videos = true, directory = true, p = true, settings = true, downloads = true,
    jobs = true, turbo = true, wallet = true, subscriptions = true, inventory = true,
    drops = true, friends = true, following = true, search = true, store = true,
}

local MSG_UNSUPPORTED = 'YouTubeまたはTwitchのURLを入力してください'
local MSG_BAD_FORMAT = 'URLの形式が正しくありません（動画・配信・クリップのURLを指定してください）'

-- デバッグ時だけログを出す
function MoviePlayer.Log(...)
    if Config.Debug then
        print('[movie-player]', ...)
    end
end

-- 表示名を安全な長さ・文字に整える
function MoviePlayer.SanitizeName(name)
    name = tostring(name or '')
    name = name:gsub('%c', '')
    -- UTF-8 の途中で切らないように、33文字目の位置までで切り詰める
    local ok, position = pcall(utf8.offset, name, 33)
    if ok and position then
        name = name:sub(1, position - 1)
    end
    if name == '' then
        name = '不明'
    end
    return name
end

-- URLを「ホスト」「パス」「クエリ」に分解する。許可できない形なら nil
local function splitUrl(url)
    -- スキームが無ければ https とみなす
    if not url:match('^%a[%w+.-]*://') then
        url = 'https://' .. url
    end

    local scheme, rest = url:match('^(%a[%w+.-]*)://(.*)$')
    if not scheme then
        return nil
    end
    scheme = scheme:lower()
    if scheme ~= 'http' and scheme ~= 'https' then
        return nil
    end

    -- ユーザー情報（user@host）、ポート、空白を含むホストは拒否
    local authority, tail = rest:match('^([^/?#]*)(.*)$')
    if authority == '' or authority:find('[@:%s]') then
        return nil
    end

    local pathPart, queryPart = tail:match('^([^?#]*)%??([^#]*)')
    return authority:lower(), pathPart or '', queryPart or ''
end

local function splitPath(pathPart)
    local segments = {}
    for segment in pathPart:gmatch('[^/]+') do
        segments[#segments + 1] = segment
    end
    return segments
end

local function getQueryParam(query, key)
    for name, value in query:gmatch('([^&=]+)=?([^&]*)') do
        if name == key then
            return value
        end
    end
    return nil
end

local function parseYouTube(host, segments, query)
    local id
    if host == 'youtu.be' then
        id = segments[1]
    elseif segments[1] == 'watch' then
        id = getQueryParam(query, 'v')
    elseif segments[1] == 'shorts' or segments[1] == 'embed' or segments[1] == 'live' then
        id = segments[2]
    end

    if id and #id == 11 and id:match('^[%w_-]+$') then
        return {
            platform = 'youtube',
            kind = 'video',
            id = id,
            url = 'https://www.youtube.com/watch?v=' .. id,
        }
    end
    return nil
end

local function parseTwitch(host, segments)
    if host == 'clips.twitch.tv' then
        local slug = segments[1]
        if slug and #slug <= 100 and slug:match('^[%w_-]+$') then
            return { platform = 'twitch', kind = 'clip', id = slug, url = 'https://clips.twitch.tv/' .. slug }
        end
        return nil
    end

    local first, second, third = segments[1], segments[2], segments[3]

    if first == 'videos' then
        if second and #second <= 20 and second:match('^%d+$') then
            return { platform = 'twitch', kind = 'video', id = second, url = 'https://www.twitch.tv/videos/' .. second }
        end
    elseif first and second == 'clip' then
        if third and #third <= 100 and third:match('^[%w_-]+$') then
            return { platform = 'twitch', kind = 'clip', id = third, url = 'https://clips.twitch.tv/' .. third }
        end
    elseif first and #segments == 1 then
        local channel = first:lower()
        if #channel <= 25 and channel:match('^[%w_]+$') and not TWITCH_RESERVED[channel] then
            return { platform = 'twitch', kind = 'channel', id = channel, url = 'https://www.twitch.tv/' .. channel }
        end
    end
    return nil
end

-- URL文字列を検証して、正規化したメディア情報を返す
-- 成功: { platform = 'youtube'|'twitch', kind = 'video'|'channel'|'clip', id = '...', url = '正規化したURL' }
-- 失敗: nil, 'エラーメッセージ'
function MoviePlayer.ParseMedia(url)
    if type(url) ~= 'string' then
        return nil, 'URLが不正です'
    end

    url = url:match('^%s*(.-)%s*$')
    if url == '' then
        return nil, 'URLを入力してください'
    end
    if #url > (Config.MaxUrlLength or 300) then
        return nil, 'URLが長すぎます'
    end
    if url:find('%c') then
        return nil, 'URLに使用できない文字が含まれています'
    end

    local host, pathPart, query = splitUrl(url)
    if not host then
        return nil, MSG_UNSUPPORTED
    end

    local segments = splitPath(pathPart)

    if host == 'youtu.be' or YOUTUBE_HOSTS[host] then
        local media = parseYouTube(host, segments, query)
        if media then
            return media
        end
        return nil, MSG_BAD_FORMAT
    end

    if host == 'clips.twitch.tv' or TWITCH_HOSTS[host] then
        local media = parseTwitch(host, segments)
        if media then
            return media
        end
        return nil, MSG_BAD_FORMAT
    end

    return nil, MSG_UNSUPPORTED
end
