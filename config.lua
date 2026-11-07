-- movie-player 設定ファイル（client / server の両方から読み込まれる）
Config = {}

-- デバッグログ（true にすると client / server で詳細ログを出す）
Config.Debug = false

-- ================== 共有・視聴 ==================

-- 付近プレイヤーとして扱う距離（メートル）。共有先の一覧と、参加を申請できる上映の範囲に使う
Config.NearbyDistance = 50.0

-- 1回の共有で選べる最大人数
Config.MaxShareTargets = 10

-- 同じ送信者が続けて共有できる間隔の下限（ミリ秒）
Config.ShareCooldownMs = 5000

-- サーバ側でも距離を検証する（OneSync 必須。サーバから座標を取れない環境では自動でスキップ）
Config.ServerDistanceCheck = true

-- サーバ側の距離検証に足す余裕（メートル。クライアント側の算出とのずれを吸収する）
Config.ServerDistanceMargin = 15.0

-- 共有を受け取る側に承諾確認を出す（false にすると届いた動画を即再生する）
Config.RequireAcceptance = true

-- 承諾確認の待ち時間（ミリ秒。超えたら辞退扱い）
Config.ShareRequestTimeoutMs = 15000

-- 視聴画面でも、キーボードの入力をゲームへ渡す（ボイスチャットの発話キーやチャットを使えるようにする）
Config.AllowGameInputWhileWatching = true

-- 視聴画面で、歩く・走る・運転するなどの移動を許可する（false なら視聴中はその場から動けない）
-- Config.AllowGameInputWhileWatching = true のときだけ意味がある（false なら入力は全部画面が受け取る）
Config.AllowMovementWhileWatching = false

-- 移動を止めている間も使えるようにしておくコントロール（245: チャット / 249: ボイスチャットの発話）
Config.ControlsAllowedWhileWatching = { 245, 249 }

-- 承諾・辞退のキー（初期値。FiveM のキー設定から各自で変更できる）
-- 共有の承諾確認と、参加の申請（許可・拒否）の両方に使う
Config.AcceptKey = 'Y'
Config.DeclineKey = 'N'

-- ================== 動画の枠（視聴画面） ==================
-- 通知や共有の確認を、動画の上に重ねずに動画の外側へ出すため、動画は中央より少し下に、
-- 画面の6割強の大きさで描く（YouTube の埋め込み要件: プレイヤーの上に表示物を重ねない）
-- 動画の幅（画面の幅に対する割合）。枠の大きさ 100% のときの値
Config.VideoWidth = 0.62

-- 動画の高さの上限（画面の高さに対する割合）。枠の大きさ 100% のときの値
Config.VideoMaxHeight = 0.62

-- 動画の中心の縦位置（0 = 上端、1 = 下端）
Config.VideoCenterY = 0.55

-- 枠の大きさの範囲と刻み（1.0 = 上の大きさ）。上限は画面に収まる大きさで頭打ちになる
Config.FrameScaleMin = 0.5
Config.FrameScaleMax = 1.5
Config.FrameScaleStep = 0.1

-- ================== 再生位置の同期 ==================

-- 再生位置を確かめる間隔（ミリ秒）
Config.SyncIntervalMs = 3000

-- これ以上ずれたら、ホストの再生位置に合わせ直す（秒）
Config.SyncToleranceSec = 2.0

-- ================== 参加の申請 ==================

-- 近くで上映している人に、参加を申請できるようにする
Config.JoinRequestEnabled = true

-- 申請の待ち時間（ミリ秒。超えたら拒否扱い）
Config.JoinRequestTimeoutMs = 15000

-- 同じ人が続けて申請できる間隔の下限（ミリ秒）
Config.JoinRequestCooldownMs = 8000

-- 1つの上映に参加できる最大人数（ホストを含む）
Config.MaxSessionMembers = 30

-- ================== 空間スクリーン ==================

Config.Screens = {
    -- 空間スクリーンを使う
    Enabled = true,

    -- 1人が置けるスクリーンの数（管理者は無制限）
    MaxPerPlayer = 2,

    -- 管理者として扱う ACE 権限（どのスクリーンでも変更・撤去できる、数の上限なし）
    -- 例: server.cfg か permissions.cfg に  add_ace group.admin movieplayer.admin allow
    AdminAce = 'movieplayer.admin',

    -- 置ける距離（自分からスクリーンの中心まで、メートル）
    PlaceDistance = 10.0,

    -- スクリーンの幅（メートル）。高さは 16:9 で決まる
    MinWidth = 1.0,
    MaxWidth = 12.0,
    DefaultWidth = 3.0,

    -- 配置中にマウスホイール 1 回で変わる幅（メートル）
    WidthStep = 0.25,

    -- スクリーンを描く距離（メートル）
    RenderDistance = 60.0,

    -- 同時に再生するスクリーンの数（近い順。1つにつき DUI を1つ使う）
    MaxActive = 2,

    -- 音が聞こえる距離（メートル）。FullVolumeDistance までは設定の音量、そこから AudioDistance で 0 になる
    AudioDistance = 25.0,
    FullVolumeDistance = 5.0,

    -- 心の目（ALT）で操作できる距離（メートル）
    InteractDistance = 8.0,

    -- 置いた人が退出したら、そのスクリーンを撤去する（false なら再起動まで残る）
    RemoveOnOwnerDrop = false,

    -- 置く・動かす・動画の変更の間隔の下限（ミリ秒）
    ActionCooldownMs = 1500,
}

-- ================== URL ==================

-- 受け付けるURLの最大長
Config.MaxUrlLength = 300

-- ================== DUI ==================

-- DUI の解像度
Config.DuiWidth = 1280
Config.DuiHeight = 720

-- DUI の準備を待つ上限（ミリ秒）
Config.DuiReadyTimeoutMs = 8000
