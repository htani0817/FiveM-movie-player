// ================== DOM要素 ==================
const $ = (id) => document.getElementById(id);

// URL入力画面
const inputContainer = $('input-container');
const urlInput = $('url-input');
const pasteBtn = $('paste-btn');
const playBtn = $('play-btn');
const inputCloseBtn = $('input-close-btn');
const errorMessage = $('error-message');
const receiveToggle = $('receive-toggle');
const placeBtn = $('place-btn');

// 近くの人に共有
const shareBtn = $('share-btn');
const playerListContainer = $('player-list-container');
const playerList = $('player-list');
const playerCount = $('player-count');
const playerRange = $('player-range');
const shareConfirmBtn = $('share-confirm-btn');
const selectAllBtn = $('select-all-btn');
const refreshBtn = $('refresh-btn');

// 近くで上映中
const sessionListContainer = $('session-list-container');
const sessionList = $('session-list');
const sessionCount = $('session-count');

// 視聴画面（枠）
const playerContainer = $('player-container');
const frame = $('frame');
const frameHeader = $('frame-header');
const frameVideo = $('frame-video');
const frameFooter = $('frame-footer');
const playerCloseBtn = $('player-close-btn');
const backBtn = $('back-btn');
const platformBadge = $('platform-badge');
const platformName = $('platform-name');
const playState = $('play-state');
const sessionMeta = $('session-meta');
const sizeDownBtn = $('size-down-btn');
const sizeUpBtn = $('size-up-btn');
const sizeValue = $('size-value');

// 空間スクリーンの操作パネル
const screenPanel = $('screen-panel');
const screenOwner = $('screen-owner');
const screenNowText = $('screen-now-text');
const screenNow = $('screen-now');
const screenNote = $('screen-note');
const screenManage = $('screen-manage');
const screenUrlInput = $('screen-url-input');
const screenError = $('screen-error');
const screenPlayBtn = $('screen-play-btn');
const screenStopBtn = $('screen-stop-btn');
const screenMoveBtn = $('screen-move-btn');
const screenRemoveBtn = $('screen-remove-btn');
const screenSize = $('screen-size');

// 配置中の案内
const placeHint = $('place-hint');
const placeDot = $('place-dot');
const placeStatus = $('place-status');
const placeSize = $('place-size');
const placeKeys = $('place-keys');

// 承諾確認・トースト
const shareRequest = $('share-request');
const shareRequestTitle = $('share-request-title');
const shareRequestText = $('share-request-text');
const shareRequestHint = $('share-request-hint');
const shareRequestRemaining = $('share-request-remaining');
const shareRequestBar = $('share-request-bar');
const shareRequestAccept = $('share-request-accept');
const shareRequestDecline = $('share-request-decline');
const toastContainer = $('toast-container');

// リソース名は直書きせず、NUI が持っている名前を使う
const RESOURCE_NAME = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'movie-player';

const POST_TIMEOUT_MS = 15000;       // 再生開始は DUI の準備待ちを含むので長めに取る
const PLAYER_LIST_REFRESH_MS = 2000; // 付近プレイヤー一覧の自動更新間隔
const SESSION_LIST_REFRESH_MS = 3000; // 近くの上映一覧の自動更新間隔
const JOIN_PENDING_MS = 16000;       // 申請したあと「申請中」と出しておく時間
const MAX_TOASTS = 4;

// 枠の配置（px）
const EDGE = 16;          // 画面の端との余白
const TOAST_MIN = 150;    // 通知の最小の幅（この幅を右の余白に確保できる大きさまでしか枠を広げない）
const TOAST_MAX = 220;
const TOAST_GAP = 16;     // 枠と通知の間
const COMPACT_WIDTH = 600; // これより狭い枠では、シークバーを1段目に分ける

const SELECT_ICON = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="20 6 9 17 4 12"></polyline></svg>';

const ICON_ATTRS = 'width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"';

const TOAST_ICONS = {
    info: `<svg ${ICON_ATTRS}><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="16" x2="12" y2="12"></line><line x1="12" y1="8" x2="12.01" y2="8"></line></svg>`,
    success: `<svg ${ICON_ATTRS}><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path><polyline points="22 4 12 14.01 9 11.01"></polyline></svg>`,
    error: `<svg ${ICON_ATTRS}><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="8" x2="12" y2="12"></line><line x1="12" y1="16" x2="12.01" y2="16"></line></svg>`
};

const CLOSE_ICON = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>';

const PAUSE_ICON = '<rect x="6" y="5" width="4" height="14" rx="1"></rect><rect x="14" y="5" width="4" height="14" rx="1"></rect>';
const PLAY_ICON = '<path d="M7 4.5v15a1 1 0 0 0 1.52.85l12-7.5a1 1 0 0 0 0-1.7l-12-7.5A1 1 0 0 0 7 4.5z"></path>';

const VOLUME_ICONS = {
    muted: '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon><line x1="23" y1="9" x2="17" y2="15"></line><line x1="17" y1="9" x2="23" y2="15"></line>',
    low: '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon><path d="M15.54 8.46a5 5 0 0 1 0 7.07"></path>',
    high: '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon><path d="M15.54 8.46a5 5 0 0 1 0 7.07"></path><path d="M19.07 4.93a10 10 0 0 1 0 14.14"></path>'
};

// ================== 状態 ==================

let view = 'none'; // 'none' | 'input' | 'player' | 'panel'
let isBusy = false;

let selectedPlayers = new Set();
let nearbyPlayers = [];
let nearbyListSignature = '';
let nearbyRequestInFlight = false;
let playerListTimer = null;
let isPlayerListOpen = false;
let maxTargets = 10;
let nearbyDistance = 50; // 付近プレイヤーの検出距離（m）。距離バーの基準に使う

let joinEnabled = true;
let sessionListTimer = null;
let nearbySessions = [];
const pendingJoins = new Map(); // [上映ID] = 申請した時刻

let shareRequestTick = null;

// 枠
let frameConfig = { scale: 1, min: 0.5, max: 1.5, step: 0.1, videoWidth: 0.62, videoMaxHeight: 0.62, videoCenterY: 0.55 };
let effectiveScale = 1;
let maxAllowedScale = 1.5;
let lastLayoutKey = '';

// 上映
let sessionState = { inSession: false, isHost: false, hostName: null, memberCount: 1, canControl: true };
let mediaKind = 'video';
let lastMainProgress = null; // 最後に届いた再生位置（ホスト・参加者が切り替わったときに描き直す）

// 空間スクリーンの操作パネル
let panelScreen = null;
let removeArmedUntil = 0;

// ================== Lua との通信 ==================

// NUI コールバックを呼ぶ。タイムアウトや通信エラーは例外で返す
async function post(name, body, timeoutMs) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs || POST_TIMEOUT_MS);

    try {
        const response = await fetch(`https://${RESOURCE_NAME}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {}),
            signal: controller.signal
        });
        if (!response.ok) {
            throw new Error(`${name}: HTTP ${response.status}`);
        }

        const text = await response.text();
        try {
            return JSON.parse(text);
        } catch (e) {
            return text;
        }
    } finally {
        clearTimeout(timer);
    }
}

// 結果を待たない通知（失敗してもコンソールに残すだけ）
function postQuiet(name, body) {
    post(name, body, 5000).catch(err => console.warn(`${name} failed:`, err));
}

// 閉じる・戻るのように、失敗したら利用者に知らせるべき操作
async function postAction(name, body) {
    try {
        await post(name, body || {}, 5000);
    } catch (err) {
        console.warn(`${name} failed:`, err);
        showToast('error', '操作に失敗しました。もう一度お試しください');
    }
}

// FiveMからのメッセージを受信
window.addEventListener('message', function(event) {
    const data = event.data;
    if (!data || typeof data !== 'object') {
        return;
    }

    switch (data.action) {
        case 'openInput':
            showInputScreen(data);
            break;
        case 'showInput':
            showInputScreen({ reset: false });
            break;
        case 'showPlayer':
            showPlayerScreen(data);
            break;
        case 'close':
            closeAll();
            break;
        case 'toast':
            showToast(data.kind, data.message);
            break;
        case 'shareRequest':
            showShareRequest(data);
            break;
        case 'shareRequestEnd':
            hideShareRequest();
            break;
        case 'progress':
            lastMainProgress = data.progress;
            renderProgress(mainTransport, data.progress, sessionState.canControl);
            break;
        case 'sessionInfo':
            updateSessionInfo(data);
            break;
        case 'sessionList':
            updateSessionList(data.sessions);
            break;
        case 'screenPanel':
            openScreenPanel(data.screen);
            break;
        case 'screenPanelUpdate':
            updateScreenPanel(data.screen);
            break;
        case 'screenPanelClose':
            closeScreenPanel();
            break;
        case 'screenProgress':
            if (panelScreen && data.id === panelScreen.id) {
                renderProgress(panelTransport, data.progress, panelScreen.canManage);
            }
            break;
        case 'screenStatus':
            if (panelScreen && data.id === panelScreen.id && typeof data.message === 'string') {
                screenNote.textContent = data.message;
            }
            break;
        case 'placeHint':
            updatePlaceHint(data);
            break;
    }
});

// ESC で閉じる（NUI にフォーカスがあるとゲーム側はキーを受け取れないため、ここで処理する）
document.addEventListener('keydown', function(e) {
    if (e.key !== 'Escape' || e.repeat || view === 'none') {
        return;
    }
    e.preventDefault();
    if (view === 'panel') {
        postQuiet('screenPanelClose');
        closeScreenPanel();
    } else {
        postAction('close');
    }
});

// ================== 共通の部品 ==================

// 50 → "50m"、12.5 → "12.5m"（整数なら小数を付けない）
function formatMeters(value) {
    return (Number.isInteger(value) ? String(value) : value.toFixed(1)) + 'm';
}

// 秒 → "1:23"・"1:02:03"
function formatTime(seconds) {
    if (!Number.isFinite(seconds) || seconds < 0) {
        return '--:--';
    }
    const total = Math.floor(seconds);
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    const pad = (n) => String(n).padStart(2, '0');
    return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

function platformLabel(platform) {
    return platform === 'twitch' ? 'Twitch' : 'YouTube';
}

function setFill(fill, fraction) {
    const value = Number.isFinite(fraction) ? Math.max(0, Math.min(1, fraction)) : 0;
    fill.style.transform = `scaleX(${value.toFixed(4)})`;
}

// キーの案内（キー名は textContent で入れる）
function keyHint(key, label) {
    const kbd = document.createElement('kbd');
    kbd.textContent = typeof key === 'string' && key !== '' ? key : '?';
    const text = document.createElement('span');
    text.textContent = label;
    return [kbd, text];
}

// 音量の操作（ミュートボタン・スライダー・数値）。視聴画面とスクリーンのパネルで使う
function createVolumeControl(ids, onChange) {
    const btn = $(ids.btn), slider = $(ids.slider), fill = $(ids.fill), value = $(ids.value), icon = $(ids.icon);
    const control = { volume: 50, muted: false, previous: 50, timer: null };

    function render() {
        setFill(fill, control.volume / 100);
        value.textContent = control.volume + '%';
        slider.value = control.volume;
        const kind = control.volume === 0 ? 'muted' : control.volume < 50 ? 'low' : 'high';
        icon.innerHTML = VOLUME_ICONS[kind];
        btn.classList.toggle('muted', control.volume === 0);
    }

    // ドラッグ中に大量に送らないよう、短い間隔でまとめて最新の値だけ送る
    function schedule() {
        if (control.timer !== null) {
            return;
        }
        control.timer = setTimeout(function() {
            control.timer = null;
            onChange(control.volume);
        }, 80);
    }

    slider.addEventListener('input', function() {
        control.volume = parseInt(this.value, 10) || 0;
        // スライダーで音を上げたらミュート解除。次のボタン操作は「ミュート」になる
        control.muted = control.volume === 0;
        if (control.volume > 0) {
            control.previous = control.volume;
        }
        render();
        schedule();
    });

    btn.addEventListener('click', function() {
        if (control.muted || control.volume === 0) {
            control.muted = false;
            control.volume = control.previous || 50;
        } else {
            control.muted = true;
            control.previous = control.volume || control.previous;
            control.volume = 0;
        }
        render();
        schedule();
    });

    control.set = function(volume) {
        control.volume = Math.max(0, Math.min(100, Math.round(volume)));
        control.muted = control.volume === 0;
        if (control.volume > 0) {
            control.previous = control.volume;
        }
        render();
    };
    render();
    return control;
}

// 再生位置の表示と操作（一時停止ボタン・時刻・シークバー）。視聴画面とスクリーンのパネルで使う
function createTransport(ids, handlers) {
    const ui = {
        playBtn: $(ids.playBtn),
        playIcon: $(ids.playIcon),
        current: $(ids.current),
        duration: $(ids.duration),
        slider: $(ids.slider),
        fill: $(ids.fill),
        live: $(ids.live),
        seeking: false,
        paused: false,
        lastDuration: 0
    };

    ui.slider.addEventListener('input', function() {
        ui.seeking = true;
        const value = Number(this.value);
        ui.current.textContent = formatTime(value);
        setFill(ui.fill, ui.lastDuration > 0 ? value / ui.lastDuration : 0);
    });

    ui.slider.addEventListener('change', function() {
        ui.seeking = false;
        handlers.seek(Number(this.value));
    });

    ui.playBtn.addEventListener('click', function() {
        handlers.toggle(ui.paused);
    });

    return ui;
}

function renderProgress(ui, progress, canControl) {
    if (!progress || typeof progress !== 'object') {
        return;
    }

    const live = progress.live === true;
    const seekable = progress.seekable === true && Number.isFinite(progress.duration);
    const controllable = progress.controllable === true && canControl;

    ui.paused = progress.paused === true;
    ui.playIcon.innerHTML = ui.paused ? PLAY_ICON : PAUSE_ICON;
    const playLabel = ui.paused ? '再生' : '一時停止';
    ui.playBtn.setAttribute('aria-label', playLabel);
    ui.playBtn.title = canControl ? playLabel : '再生位置はホスト（スクリーンは置いた人）が操作します';
    ui.playBtn.disabled = !controllable;

    ui.live.classList.toggle('hidden', !live);
    ui.current.classList.toggle('hidden', live);
    ui.duration.classList.toggle('hidden', live);
    ui.slider.parentElement.classList.toggle('hidden', live);

    if (!live) {
        const duration = seekable ? progress.duration : 0;
        ui.lastDuration = duration;
        ui.slider.max = String(Math.floor(duration));
        ui.slider.disabled = !(seekable && canControl);
        ui.slider.parentElement.classList.toggle('disabled', !(seekable && canControl));
        ui.duration.textContent = seekable ? formatTime(duration) : '--:--';
        if (!ui.seeking) {
            const time = Number.isFinite(progress.time) ? progress.time : 0;
            ui.current.textContent = seekable || Number.isFinite(progress.time) ? formatTime(time) : '--:--';
            ui.slider.value = String(Math.floor(time));
            setFill(ui.fill, duration > 0 ? time / duration : 0);
        }
    }

    if (ui === mainTransport) {
        playState.textContent = live ? 'ライブ' : (ui.paused ? '一時停止中' : '再生中');
        platformBadge.classList.toggle('paused', ui.paused);
    }
}

const mainVolume = createVolumeControl(
    { btn: 'volume-btn', slider: 'volume-slider', fill: 'volume-fill', value: 'volume-value', icon: 'volume-icon' },
    (volume) => postQuiet('volumeChange', { volume: volume })
);

const mainTransport = createTransport(
    { playBtn: 'playpause-btn', playIcon: 'playpause-icon', current: 'time-current', duration: 'time-duration', slider: 'seek-slider', fill: 'seek-fill', live: 'live-label' },
    {
        seek: (position) => postQuiet('playerControl', { action: 'seek', position: position }),
        toggle: (paused) => postQuiet('playerControl', { action: paused ? 'resume' : 'pause' })
    }
);

const panelVolume = createVolumeControl(
    { btn: 'screen-volume-btn', slider: 'screen-volume-slider', fill: 'screen-volume-fill', value: 'screen-volume-value', icon: 'screen-volume-icon' },
    (volume) => {
        if (panelScreen) {
            panelScreen.volume = volume;
            postQuiet('screenVolume', { id: panelScreen.id, volume: volume });
        }
    }
);

const panelTransport = createTransport(
    { playBtn: 'screen-playpause-btn', playIcon: 'screen-playpause-icon', current: 'screen-time-current', duration: 'screen-time-duration', slider: 'screen-seek-slider', fill: 'screen-seek-fill', live: 'screen-live-label' },
    {
        seek: (position) => panelScreen && postQuiet('screenControl', { id: panelScreen.id, action: 'seek', position: position }),
        toggle: (paused) => panelScreen && postQuiet('screenControl', { id: panelScreen.id, action: paused ? 'play' : 'pause' })
    }
);

// ================== 画面の切り替え ==================

// URL入力画面を表示
function showInputScreen(options) {
    const opts = options || {};
    view = 'input';
    inputContainer.classList.remove('hidden');
    playerContainer.classList.add('hidden');
    resetToastLane();

    if (opts.reset !== false) {
        urlInput.value = '';
        hideError();
    }
    if (typeof opts.receiveEnabled === 'boolean') {
        receiveToggle.checked = opts.receiveEnabled;
    }
    if (Number.isInteger(opts.maxTargets) && opts.maxTargets > 0) {
        maxTargets = opts.maxTargets;
    }
    if (Number.isFinite(opts.nearbyDistance) && opts.nearbyDistance > 0) {
        nearbyDistance = opts.nearbyDistance;
    }
    if (typeof opts.joinEnabled === 'boolean') {
        joinEnabled = opts.joinEnabled;
    }
    if (typeof opts.screensEnabled === 'boolean') {
        placeBtn.classList.toggle('hidden', !opts.screensEnabled);
    }
    playerRange.textContent = `${formatMeters(nearbyDistance)} 以内`;

    hidePlayerList();
    startSessionPolling();
    urlInput.focus();
}

// 視聴画面を表示
function showPlayerScreen(data) {
    view = 'player';
    stopSessionPolling();
    mediaKind = typeof data.kind === 'string' ? data.kind : 'video';
    updatePlatformBadge(data.platform === 'twitch' ? 'twitch' : 'youtube');

    const cfg = data.frame || {};
    for (const key of ['scale', 'min', 'max', 'step', 'videoWidth', 'videoMaxHeight', 'videoCenterY']) {
        if (Number.isFinite(cfg[key]) && cfg[key] > 0) {
            frameConfig[key] = cfg[key];
        }
    }

    // 再生位置が届くまでの表示
    lastMainProgress = null;
    renderProgress(mainTransport, { live: mediaKind === 'channel', paused: false, seekable: false, controllable: false }, sessionState.canControl);

    hidePlayerList();
    inputContainer.classList.add('hidden');
    playerContainer.classList.remove('hidden');
    lastLayoutKey = '';
    layoutFrame();
}

// 全て閉じる
function closeAll() {
    if (view !== 'panel') {
        view = 'none';
    }
    inputContainer.classList.add('hidden');
    playerContainer.classList.add('hidden');
    urlInput.value = '';
    hideError();
    hidePlayerList();
    stopSessionPolling();
    setBusy(false);
    resetToastLane();
}

// プラットフォームバッジを更新
function updatePlatformBadge(platform) {
    platformBadge.classList.toggle('twitch', platform === 'twitch');
    platformName.textContent = platformLabel(platform);
}

// ================== 枠（大きさ・配置） ==================

function roundScale(value) {
    const step = frameConfig.step;
    return Math.round(Math.round(value / step) * step * 100) / 100;
}

// 大きさ 100% のときの動画の幅（px）
function baseVideoWidth() {
    const W = window.innerWidth, H = window.innerHeight;
    return Math.min(frameConfig.videoWidth * W, frameConfig.videoMaxHeight * H * 16 / 9);
}

// 画面に収まる最大の大きさ（刻みに切り捨て）。右の余白に通知の最小幅を残す
function fitScale(base, headerH, footerH) {
    const W = window.innerWidth, H = window.innerHeight;
    const maxW = Math.min(
        W - 2 * (EDGE + TOAST_MIN + TOAST_GAP) - 2,
        (H - 2 * EDGE - headerH - footerH - 2) * 16 / 9
    );
    const step = frameConfig.step;
    return Math.floor((maxW / base) / step + 1e-6) * step;
}

function layoutFrame() {
    if (view !== 'player') {
        return;
    }

    const W = window.innerWidth, H = window.innerHeight;
    const base = baseVideoWidth();
    let scale = Math.max(frameConfig.min, Math.min(frameConfig.max, roundScale(frameConfig.scale)));
    let headerH = 0, footerH = 0;

    // 枠の幅で下の段の折り返しが変わり、高さも変わるので、2回まで測り直す
    for (let pass = 0; pass < 2; pass++) {
        const videoW = Math.round(base * scale);
        frame.style.width = (videoW + 2) + 'px';
        frame.classList.toggle('compact', videoW < COMPACT_WIDTH);
        headerH = frameHeader.offsetHeight;
        footerH = frameFooter.offsetHeight;
        maxAllowedScale = Math.max(frameConfig.min, Math.min(frameConfig.max, fitScale(base, headerH, footerH)));
        if (scale <= maxAllowedScale + 1e-6) {
            break;
        }
        scale = roundScale(maxAllowedScale);
    }
    effectiveScale = scale;

    const videoW = Math.round(base * scale);
    const videoH = Math.round(videoW * 9 / 16);
    frameVideo.style.height = videoH + 'px';

    // 動画の中心が Config.VideoCenterY に来るように置き、画面からはみ出す分だけずらす
    const frameW = videoW + 2;
    const frameH = headerH + videoH + footerH + 2;
    let top = Math.round(H * frameConfig.videoCenterY - (1 + headerH + videoH / 2));
    top = Math.max(EDGE, Math.min(H - EDGE - frameH, top));
    const left = Math.round((W - frameW) / 2);
    frame.style.left = left + 'px';
    frame.style.top = top + 'px';

    // 通知は枠の右の余白に収める
    const lane = W - (left + frameW) - TOAST_GAP - EDGE;
    toastContainer.style.width = Math.max(TOAST_MIN, Math.min(TOAST_MAX, lane)) + 'px';

    sizeValue.textContent = Math.round(scale * 100) + '%';
    sizeDownBtn.disabled = scale - frameConfig.step < frameConfig.min - 1e-6;
    sizeUpBtn.disabled = scale + frameConfig.step > maxAllowedScale + 1e-6;
    sizeUpBtn.title = sizeUpBtn.disabled ? 'これ以上は画面に収まりません' : '大きくする (10%)';

    // 動画を描く位置を Lua に送る（変わったときだけ）
    const rect = frameVideo.getBoundingClientRect();
    const layout = { x: rect.left / W, y: rect.top / H, w: rect.width / W, h: rect.height / H };
    const key = [layout.x, layout.y, layout.w, layout.h].map(v => v.toFixed(4)).join(',');
    if (key !== lastLayoutKey) {
        lastLayoutKey = key;
        postQuiet('frameLayout', layout);
    }
}

function changeFrameScale(direction) {
    const next = roundScale(effectiveScale + direction * frameConfig.step);
    if (next < frameConfig.min - 1e-6 || next > maxAllowedScale + 1e-6) {
        return;
    }
    frameConfig.scale = next;
    layoutFrame();
    postQuiet('setFrameScale', { scale: next });
}

sizeDownBtn.addEventListener('click', () => changeFrameScale(-1));
sizeUpBtn.addEventListener('click', () => changeFrameScale(1));
window.addEventListener('resize', () => layoutFrame());

// 通知の幅を、入力画面などの既定に戻す
function resetToastLane() {
    toastContainer.style.width = '';
}

// ================== 上映の表示 ==================

function updateSessionInfo(data) {
    sessionState = {
        inSession: data.inSession === true,
        isHost: data.isHost === true,
        hostName: typeof data.hostName === 'string' ? data.hostName : null,
        memberCount: Number.isInteger(data.memberCount) ? data.memberCount : 1,
        canControl: data.canControl !== false
    };

    let text = '';
    if (sessionState.inSession && !sessionState.isHost) {
        text = `${sessionState.hostName || '不明'}さんの上映 · ${sessionState.memberCount}人`;
    } else if (sessionState.inSession && sessionState.memberCount > 1) {
        text = `ホスト · ${sessionState.memberCount}人で視聴中`;
    }
    sessionMeta.textContent = text;
    sessionMeta.classList.toggle('hidden', text === '');
    frame.classList.toggle('follower', !sessionState.canControl);
    if (lastMainProgress) {
        renderProgress(mainTransport, lastMainProgress, sessionState.canControl);
    }
}

// ================== エラー・処理中の表示 ==================

function showError(message) {
    errorMessage.textContent = message;
    errorMessage.classList.remove('hidden');
}

function hideError() {
    errorMessage.classList.add('hidden');
}

// 再生・共有の要求中は二重に押せないようにする
function setBusy(busy) {
    isBusy = busy;
    playBtn.disabled = busy;
    playBtn.classList.toggle('loading', busy);
    playBtn.querySelector('span').textContent = busy ? '読み込み中…' : '再生';
    playBtn.setAttribute('aria-busy', String(busy));
    placeBtn.disabled = busy;
    updateShareButton();
}

// ================== 再生 ==================

// URLの検証は Lua 側（サーバーと同じ規則）で行う。ここでは空かどうかだけ見る
async function validateAndPlay() {
    if (isBusy) {
        return;
    }

    const url = urlInput.value.trim();
    if (!url) {
        showError('URLを入力してください');
        urlInput.focus();
        return;
    }

    hideError();
    setBusy(true);

    try {
        const result = await post('playVideo', { url: url });
        if (!result || result.success !== true) {
            showError((result && result.message) || '再生できませんでした');
        }
        // 成功したときは Lua から showPlayer が届いて画面が切り替わる
    } catch (err) {
        console.warn('playVideo failed:', err);
        showError('再生を開始できませんでした。時間をおいてもう一度お試しください');
    } finally {
        setBusy(false);
    }
}

// 空間にスクリーンを置く（URL は空でもよい）
placeBtn.addEventListener('click', async function() {
    if (isBusy) {
        return;
    }
    hideError();
    try {
        const result = await post('startPlacement', { url: urlInput.value.trim() }, 5000);
        if (!result || result.success !== true) {
            showError((result && result.message) || 'スクリーンを置けませんでした');
        }
        // 成功したときは Lua が入力画面を閉じて、配置の案内に切り替わる
    } catch (err) {
        console.warn('startPlacement failed:', err);
        showError('操作に失敗しました。もう一度お試しください');
    }
});

// ================== 近くの人に共有 ==================

shareBtn.addEventListener('click', function() {
    if (isPlayerListOpen) {
        hidePlayerList();
    } else {
        showPlayerList();
    }
});

function showPlayerList() {
    isPlayerListOpen = true;
    playerListContainer.classList.remove('hidden');
    shareBtn.classList.add('active');
    shareBtn.setAttribute('aria-expanded', 'true');

    requestNearbyPlayers();
    clearInterval(playerListTimer);
    playerListTimer = setInterval(requestNearbyPlayers, PLAYER_LIST_REFRESH_MS);
}

function hidePlayerList() {
    isPlayerListOpen = false;
    playerListContainer.classList.add('hidden');
    shareBtn.classList.remove('active');
    shareBtn.setAttribute('aria-expanded', 'false');
    clearInterval(playerListTimer);
    playerListTimer = null;
    selectedPlayers.clear();
    nearbyListSignature = '';
    updateShareButton();
}

// 付近プレイヤーを要求
async function requestNearbyPlayers() {
    if (nearbyRequestInFlight) {
        return;
    }
    nearbyRequestInFlight = true;

    try {
        const result = await post('getNearbyPlayers', {}, 5000);
        if (isPlayerListOpen) {
            updateNearbyPlayersList(result && result.players);
        }
    } catch (err) {
        console.warn('getNearbyPlayers failed:', err);
    } finally {
        nearbyRequestInFlight = false;
    }
}

function isValidPlayer(player) {
    return player
        && Number.isInteger(player.id)
        && typeof player.name === 'string'
        && Number.isFinite(player.distance);
}

function updateNearbyPlayersList(players) {
    nearbyPlayers = Array.isArray(players) ? players.filter(isValidPlayer) : [];
    playerCount.textContent = nearbyPlayers.length + '人';

    // 範囲外に出た・退出した人は選択から外す（人数表示とずらさない）
    const currentIds = new Set(nearbyPlayers.map(player => player.id));
    selectedPlayers.forEach(id => {
        if (!currentIds.has(id)) {
            selectedPlayers.delete(id);
        }
    });

    // 内容が変わったときだけ描き直す（フォーカスやホバーを保つため）
    const signature = nearbyPlayers.map(player => `${player.id}:${Math.round(player.distance)}`).join(',');
    if (signature !== nearbyListSignature) {
        const focusedId = document.activeElement && document.activeElement.dataset
            ? document.activeElement.dataset.id
            : null;
        nearbyListSignature = signature;
        renderPlayerList();
        if (focusedId) {
            const item = playerList.querySelector(`.player-item[data-id="${CSS.escape(focusedId)}"]`);
            if (item) {
                item.focus();
            }
        }
    }

    updateShareButton();
}

// 距離の数字と、検出範囲の中でどれだけ近いかのバー（近いほど長い）
function distanceElement(value) {
    const distance = document.createElement('div');
    distance.className = 'player-distance';
    const distanceValue = document.createElement('div');
    distanceValue.className = 'player-distance-value num';
    distanceValue.textContent = value.toFixed(1) + 'm';
    const track = document.createElement('div');
    track.className = 'player-distance-track';
    const fill = document.createElement('div');
    fill.className = 'player-distance-fill';
    const closeness = Math.max(0.04, Math.min(1, 1 - value / nearbyDistance));
    fill.style.transform = `scaleX(${closeness.toFixed(3)})`;
    track.appendChild(fill);
    distance.append(distanceValue, track);
    return distance;
}

// プレイヤー一覧を DOM API で組み立てる（名前は textContent で入れるので HTML として解釈されない）
function renderPlayerList() {
    playerList.replaceChildren();

    if (nearbyPlayers.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'no-players';
        empty.textContent = `${formatMeters(nearbyDistance)} 以内にプレイヤーがいません`;
        playerList.appendChild(empty);
        return;
    }

    nearbyPlayers.forEach(player => {
        const selected = selectedPlayers.has(player.id);

        const item = document.createElement('div');
        item.className = 'player-item' + (selected ? ' selected' : '');
        item.dataset.id = String(player.id);
        item.tabIndex = 0;
        item.setAttribute('role', 'checkbox');
        item.setAttribute('aria-checked', String(selected));

        const checkbox = document.createElement('div');
        checkbox.className = 'player-checkbox';
        checkbox.innerHTML = SELECT_ICON;

        const info = document.createElement('div');
        info.className = 'player-info';
        const name = document.createElement('div');
        name.className = 'player-name';
        name.textContent = player.name;
        const id = document.createElement('div');
        id.className = 'player-id num';
        id.textContent = 'ID ' + player.id;
        info.append(name, id);

        item.append(checkbox, info, distanceElement(player.distance));

        item.addEventListener('click', () => togglePlayerSelection(player.id, item));
        item.addEventListener('keydown', e => {
            if (e.key === ' ' || e.key === 'Enter') {
                e.preventDefault();
                togglePlayerSelection(player.id, item);
            }
        });

        playerList.appendChild(item);
    });
}

function togglePlayerSelection(playerId, item) {
    if (selectedPlayers.has(playerId)) {
        selectedPlayers.delete(playerId);
    } else {
        if (selectedPlayers.size >= maxTargets) {
            showError(`一度に共有できるのは${maxTargets}人までです`);
            return;
        }
        selectedPlayers.add(playerId);
    }

    const selected = selectedPlayers.has(playerId);
    item.classList.toggle('selected', selected);
    item.setAttribute('aria-checked', String(selected));
    updateShareButton();
}

// 全員を選ぶ。全員が選ばれているときは全解除
selectAllBtn.addEventListener('click', function() {
    // 上限より人数が多いときは、近い順に上限人数までを「全員」として扱う
    const candidates = nearbyPlayers.slice(0, maxTargets);
    const allSelected = candidates.length > 0 && candidates.every(player => selectedPlayers.has(player.id));

    selectedPlayers.clear();
    if (!allSelected) {
        candidates.forEach(player => selectedPlayers.add(player.id));
        if (nearbyPlayers.length > maxTargets) {
            showError(`近い順に${maxTargets}人まで選択しました`);
        }
    }

    renderPlayerList();
    updateShareButton();
});

refreshBtn.addEventListener('click', requestNearbyPlayers);

function updateShareButton() {
    const count = selectedPlayers.size;
    shareConfirmBtn.disabled = count === 0 || isBusy;
    shareConfirmBtn.querySelector('span').textContent = count === 0
        ? '共有する相手を選択'
        : `${count}人に共有`;
    selectAllBtn.disabled = nearbyPlayers.length === 0;
}

shareConfirmBtn.addEventListener('click', async function() {
    if (isBusy) {
        return;
    }

    const url = urlInput.value.trim();
    if (!url) {
        showError('URLを入力してください');
        urlInput.focus();
        return;
    }
    if (selectedPlayers.size === 0) {
        showError('共有するプレイヤーを選択してください');
        return;
    }

    hideError();
    setBusy(true);

    try {
        const result = await post('shareVideo', {
            url: url,
            targetPlayers: Array.from(selectedPlayers)
        });
        if (!result || result.success !== true) {
            showError((result && result.message) || '共有できませんでした');
        }
        // 成功したときは Lua から showPlayer が届いて画面が切り替わり、結果はトーストで届く
    } catch (err) {
        console.warn('shareVideo failed:', err);
        showError('共有を開始できませんでした。時間をおいてもう一度お試しください');
    } finally {
        setBusy(false);
    }
});

// ================== 近くで上映中（参加の申請） ==================

function startSessionPolling() {
    stopSessionPolling();
    if (!joinEnabled) {
        sessionListContainer.classList.add('hidden');
        return;
    }
    postQuiet('listSessions');
    sessionListTimer = setInterval(() => postQuiet('listSessions'), SESSION_LIST_REFRESH_MS);
}

function stopSessionPolling() {
    clearInterval(sessionListTimer);
    sessionListTimer = null;
}

function isValidSession(item) {
    return item
        && Number.isInteger(item.sessionId)
        && typeof item.hostName === 'string'
        && Number.isFinite(item.distance);
}

function updateSessionList(list) {
    if (view !== 'input') {
        return;
    }
    nearbySessions = Array.isArray(list) ? list.filter(isValidSession) : [];

    // 一覧から消えた上映の「申請中」は忘れる
    const now = Date.now();
    pendingJoins.forEach((at, id) => {
        if (now - at > JOIN_PENDING_MS || !nearbySessions.some(item => item.sessionId === id)) {
            pendingJoins.delete(id);
        }
    });

    sessionListContainer.classList.toggle('hidden', nearbySessions.length === 0);
    sessionCount.textContent = nearbySessions.length + '件';
    renderSessionList();
}

function renderSessionList() {
    sessionList.replaceChildren();

    nearbySessions.forEach(item => {
        const row = document.createElement('div');
        row.className = 'player-item session-item';
        row.setAttribute('role', 'listitem');

        const tally = document.createElement('span');
        tally.className = 'tally';
        tally.setAttribute('aria-hidden', 'true');

        const info = document.createElement('div');
        info.className = 'player-info';
        const name = document.createElement('div');
        name.className = 'player-name';
        name.textContent = `${item.hostName}さん`;
        const meta = document.createElement('div');
        meta.className = 'player-id';
        meta.textContent = `${platformLabel(item.platform)} · ${item.memberCount}人で視聴中 · ${item.distance.toFixed(0)}m`;
        info.append(name, meta);

        const pending = item.pending || pendingJoins.has(item.sessionId);
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'list-action-btn join-btn';
        btn.textContent = item.full ? '満員' : (pending ? '申請中' : '参加を申請');
        btn.disabled = item.full || pending;
        btn.addEventListener('click', async () => {
            btn.disabled = true;
            btn.textContent = '申請中';
            pendingJoins.set(item.sessionId, Date.now());
            try {
                await post('requestJoin', { sessionId: item.sessionId }, 5000);
            } catch (err) {
                console.warn('requestJoin failed:', err);
                pendingJoins.delete(item.sessionId);
                renderSessionList();
                showToast('error', '申請できませんでした。もう一度お試しください');
            }
        });

        row.append(tally, info, btn);
        sessionList.appendChild(row);
    });
}

// ================== 承諾確認（共有・参加の申請） ==================

const PROMPT_TEXTS = {
    share: {
        title: '動画の共有が届きました',
        text: (from, platform) => `${from} さんが ${platform} の動画を共有しました`,
        accept: '視聴する',
        decline: '辞退',
        acceptHint: 'で視聴',
        declineHint: 'で辞退（初期設定のキー）'
    },
    join: {
        title: '参加の申請が届きました',
        text: (from) => `${from} さんが、いっしょに観たいと申請しています`,
        accept: '許可',
        decline: '拒否',
        acceptHint: 'で許可',
        declineHint: 'で拒否（初期設定のキー）'
    }
};

function showShareRequest(data) {
    const texts = PROMPT_TEXTS[data.kind] || PROMPT_TEXTS.share;
    const from = typeof data.from === 'string' ? data.from : '不明';
    const timeoutMs = Number.isFinite(data.timeoutMs) && data.timeoutMs > 0 ? data.timeoutMs : 15000;

    shareRequestTitle.textContent = texts.title;
    shareRequestText.textContent = texts.text(from, platformLabel(data.platform));
    shareRequestAccept.textContent = texts.accept;
    shareRequestDecline.textContent = texts.decline;

    // キーの案内はキーキャップで出す
    shareRequestHint.replaceChildren(
        ...keyHint(data.acceptKey || 'Y', texts.acceptHint),
        ...keyHint(data.declineKey || 'N', texts.declineHint)
    );

    // 残り時間のバーを最初から動かし直す
    shareRequestBar.style.animation = 'none';
    void shareRequestBar.offsetWidth;
    shareRequestBar.style.animation = `shareRequestTimer ${timeoutMs}ms linear forwards`;

    // 残り秒数（バーと同じ時間で数える）
    const deadline = Date.now() + timeoutMs;
    const updateRemaining = () => {
        const seconds = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
        shareRequestRemaining.textContent = String(seconds);
    };
    clearInterval(shareRequestTick);
    updateRemaining();
    shareRequestTick = setInterval(updateRemaining, 250);

    shareRequest.classList.remove('hidden');
}

function hideShareRequest() {
    shareRequest.classList.add('hidden');
    clearInterval(shareRequestTick);
    shareRequestTick = null;
}

shareRequestAccept.addEventListener('click', function() {
    hideShareRequest();
    postQuiet('acceptShare');
});

shareRequestDecline.addEventListener('click', function() {
    hideShareRequest();
    postQuiet('declineShare');
});

// ================== 空間スクリーンの操作パネル ==================

function openScreenPanel(screen) {
    if (!screen || !Number.isInteger(screen.id)) {
        return;
    }
    view = 'panel';
    panelScreen = null;
    screenUrlInput.value = '';
    screenError.classList.add('hidden');
    removeArmedUntil = 0;
    resetRemoveButton();
    updateScreenPanel(screen);
    renderProgress(panelTransport, { paused: !screen.playing, seekable: false, controllable: false, live: screen.kind === 'channel' }, screen.canManage);
    screenPanel.classList.remove('hidden');
    // 置いた人は URL の入力欄から。ほかの人はパネル自体にフォーカスを置く（閉じるボタンに枠を出さない）
    (screen.canManage ? screenUrlInput : $('screen-panel-dialog')).focus();
}

function updateScreenPanel(screen) {
    if (!screen || !Number.isInteger(screen.id)) {
        return;
    }
    if (panelScreen && panelScreen.id !== screen.id) {
        return;
    }
    const first = panelScreen === null;
    panelScreen = screen;

    screenOwner.textContent = screen.isMine ? 'あなたが設置' : `${screen.ownerName}さんが設置`;
    screenSize.textContent = `幅 ${screen.width.toFixed(1)}m × 高さ ${screen.height.toFixed(1)}m`;

    if (screen.hasMedia) {
        screenNowText.textContent = `${platformLabel(screen.platform)} ${screen.playing ? '再生中' : '一時停止中'}`;
    } else {
        screenNowText.textContent = '動画が設定されていません';
    }
    screenNow.classList.toggle('idle', !screen.hasMedia);
    $('screen-transport-block').classList.toggle('hidden', !screen.hasMedia);
    screenNote.textContent = screen.canManage
        ? '一時停止・再生位置の変更は、近くで観ている全員に反映されます'
        : '一時停止・再生位置は、置いた人と管理者が操作します';

    screenManage.classList.toggle('hidden', !screen.canManage);
    screenStopBtn.disabled = !screen.hasMedia;
    if (first) {
        panelVolume.set(Number.isFinite(screen.volume) ? screen.volume : 50);
    }
}

function closeScreenPanel() {
    screenPanel.classList.add('hidden');
    panelScreen = null;
    if (view === 'panel') {
        view = 'none';
    }
}

$('screen-close-btn').addEventListener('click', function() {
    postQuiet('screenPanelClose');
    closeScreenPanel();
});

async function setScreenMedia(url) {
    if (!panelScreen) {
        return;
    }
    screenError.classList.add('hidden');
    try {
        const result = await post('screenSetMedia', { id: panelScreen.id, url: url }, 5000);
        if (!result || result.success !== true) {
            screenError.textContent = (result && result.message) || '動画を変えられませんでした';
            screenError.classList.remove('hidden');
        } else if (url) {
            screenUrlInput.value = '';
        }
    } catch (err) {
        console.warn('screenSetMedia failed:', err);
        screenError.textContent = '操作に失敗しました。もう一度お試しください';
        screenError.classList.remove('hidden');
    }
}

screenPlayBtn.addEventListener('click', function() {
    const url = screenUrlInput.value.trim();
    if (!url) {
        screenError.textContent = 'URLを入力してください';
        screenError.classList.remove('hidden');
        screenUrlInput.focus();
        return;
    }
    setScreenMedia(url);
});

screenUrlInput.addEventListener('keydown', function(e) {
    if (e.key === 'Enter' && !e.isComposing && e.keyCode !== 229) {
        screenPlayBtn.click();
    }
});

screenUrlInput.addEventListener('input', () => screenError.classList.add('hidden'));

screenStopBtn.addEventListener('click', () => setScreenMedia(''));

screenMoveBtn.addEventListener('click', function() {
    if (panelScreen) {
        postQuiet('screenMove', { id: panelScreen.id });
        closeScreenPanel();
    }
});

// 撤去は取り消せないので、2回押して確かめる
function resetRemoveButton() {
    screenRemoveBtn.textContent = '撤去する';
    screenRemoveBtn.classList.remove('armed');
}

screenRemoveBtn.addEventListener('click', function() {
    if (!panelScreen) {
        return;
    }
    if (Date.now() > removeArmedUntil) {
        removeArmedUntil = Date.now() + 3000;
        screenRemoveBtn.textContent = 'もう一度押すと撤去します';
        screenRemoveBtn.classList.add('armed');
        setTimeout(() => {
            if (Date.now() > removeArmedUntil) {
                resetRemoveButton();
            }
        }, 3100);
        return;
    }
    postQuiet('screenRemove', { id: panelScreen.id });
    closeScreenPanel();
});

$('screen-paste-btn').addEventListener('click', async function() {
    try {
        const text = await navigator.clipboard.readText();
        screenUrlInput.value = text.trim();
        screenError.classList.add('hidden');
    } catch (err) {
        screenError.textContent = 'クリップボードを読み取れませんでした。入力欄をクリックして Ctrl+V で貼り付けてください';
        screenError.classList.remove('hidden');
    }
    screenUrlInput.focus();
});

// ================== 配置中の案内 ==================

function updatePlaceHint(data) {
    if (!data.show) {
        placeHint.classList.add('hidden');
        return;
    }

    const valid = data.valid === true;
    placeHint.classList.remove('hidden');
    placeHint.classList.toggle('invalid', !valid);
    placeDot.classList.toggle('invalid', !valid);
    placeStatus.textContent = valid
        ? (data.mode === 'move' ? 'ここに動かせます' : 'ここに置けます')
        : (typeof data.reason === 'string' ? data.reason : 'ここには置けません');
    if (Number.isFinite(data.width) && Number.isFinite(data.height)) {
        placeSize.textContent = `${data.width.toFixed(2)}m × ${data.height.toFixed(2)}m`;
    }

    const keys = [
        ...keyHint('ホイール', '大きさ'),
        ...keyHint('↑ ↓', '高さ')
    ];
    if (data.surface === 'floor' || data.surface === 'ceiling') {
        keys.push(...keyHint('Q E', '向き'));
    }
    keys.push(...keyHint('左クリック', data.mode === 'move' ? '動かす' : '置く'));
    keys.push(...keyHint('右クリック', 'やめる'));
    placeKeys.replaceChildren(...keys);
}

// ================== トースト通知 ==================

function showToast(kind, message) {
    if (typeof message !== 'string' || message === '') {
        return;
    }

    const type = kind === 'success' || kind === 'error' ? kind : 'info';

    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.setAttribute('role', type === 'error' ? 'alert' : 'status');

    const icon = document.createElement('div');
    icon.className = 'toast-icon';
    icon.innerHTML = TOAST_ICONS[type];

    const text = document.createElement('div');
    text.className = 'toast-text';
    text.textContent = message;

    const closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.className = 'toast-close';
    closeBtn.setAttribute('aria-label', '通知を閉じる');
    closeBtn.innerHTML = CLOSE_ICON;
    closeBtn.addEventListener('click', () => toast.remove());

    toast.append(icon, text, closeBtn);
    toastContainer.appendChild(toast);

    while (toastContainer.children.length > MAX_TOASTS) {
        toastContainer.firstElementChild.remove();
    }

    setTimeout(() => toast.remove(), type === 'error' ? 7000 : 5000);
}

// ================== 基本機能 ==================

pasteBtn.addEventListener('click', async function() {
    try {
        const text = await navigator.clipboard.readText();
        urlInput.value = text.trim();
        hideError();
    } catch (err) {
        // CEF ではクリップボードの読み取りが拒否されやすい。手動の貼り付けに誘導する
        showError('クリップボードを読み取れませんでした。入力欄をクリックして Ctrl+V で貼り付けてください');
    }
    urlInput.focus();
});

playBtn.addEventListener('click', validateAndPlay);

urlInput.addEventListener('keydown', function(e) {
    // 日本語入力の変換確定の Enter では再生しない
    if (e.key === 'Enter' && !e.isComposing && e.keyCode !== 229) {
        validateAndPlay();
    }
});

urlInput.addEventListener('input', hideError);

receiveToggle.addEventListener('change', function() {
    postQuiet('setReceiveShare', { enabled: receiveToggle.checked });
});

inputCloseBtn.addEventListener('click', function() {
    postAction('close');
});

playerCloseBtn.addEventListener('click', function() {
    postAction('close');
});

backBtn.addEventListener('click', function() {
    postAction('backToInput');
});

// 初期化
updateShareButton();
