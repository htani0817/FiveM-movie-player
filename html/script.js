// DOM要素 - URL入力画面
const inputContainer = document.getElementById('input-container');
const urlInput = document.getElementById('url-input');
const pasteBtn = document.getElementById('paste-btn');
const playBtn = document.getElementById('play-btn');
const inputCloseBtn = document.getElementById('input-close-btn');
const errorMessage = document.getElementById('error-message');
const receiveToggle = document.getElementById('receive-toggle');

// DOM要素 - 画面共有
const shareBtn = document.getElementById('share-btn');
const playerListContainer = document.getElementById('player-list-container');
const playerList = document.getElementById('player-list');
const playerCount = document.getElementById('player-count');
const playerRange = document.getElementById('player-range');
const shareConfirmBtn = document.getElementById('share-confirm-btn');
const selectAllBtn = document.getElementById('select-all-btn');
const refreshBtn = document.getElementById('refresh-btn');

// DOM要素 - プレイヤー画面
const playerContainer = document.getElementById('player-container');
const playerCloseBtn = document.getElementById('player-close-btn');
const backBtn = document.getElementById('back-btn');
const volumeBtn = document.getElementById('volume-btn');
const volumeSlider = document.getElementById('volume-slider');
const volumeFill = document.getElementById('volume-fill');
const volumeValue = document.getElementById('volume-value');
const volumeIcon = document.getElementById('volume-icon');
const platformBadge = document.getElementById('platform-badge');
const platformName = document.getElementById('platform-name');

// DOM要素 - 共有の承諾確認・トースト
const shareRequest = document.getElementById('share-request');
const shareRequestText = document.getElementById('share-request-text');
const shareRequestHint = document.getElementById('share-request-hint');
const shareRequestRemaining = document.getElementById('share-request-remaining');
const shareRequestBar = document.getElementById('share-request-bar');
const shareRequestAccept = document.getElementById('share-request-accept');
const shareRequestDecline = document.getElementById('share-request-decline');
const toastContainer = document.getElementById('toast-container');

// リソース名は直書きせず、NUI が持っている名前を使う
const RESOURCE_NAME = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'tani-watch';

const POST_TIMEOUT_MS = 15000;       // 再生開始は DUI の準備待ちを含むので長めに取る
const PLAYER_LIST_REFRESH_MS = 2000; // 付近プレイヤー一覧の自動更新間隔
const MAX_TOASTS = 4;

const SELECT_ICON = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="20 6 9 17 4 12"></polyline></svg>';

const ICON_ATTRS = 'width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"';

const TOAST_ICONS = {
    info: `<svg ${ICON_ATTRS}><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="16" x2="12" y2="12"></line><line x1="12" y1="8" x2="12.01" y2="8"></line></svg>`,
    success: `<svg ${ICON_ATTRS}><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path><polyline points="22 4 12 14.01 9 11.01"></polyline></svg>`,
    error: `<svg ${ICON_ATTRS}><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="8" x2="12" y2="12"></line><line x1="12" y1="16" x2="12.01" y2="16"></line></svg>`
};

const CLOSE_ICON = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>';

let currentVolume = 50;
let isMuted = false;
let previousVolume = 50;
let selectedPlayers = new Set();
let nearbyPlayers = [];
let nearbyListSignature = '';
let nearbyRequestInFlight = false;
let playerListTimer = null;
let isPlayerListOpen = false;
let maxTargets = 10;
let nearbyDistance = 50; // 付近プレイヤーの検出距離（m）。距離バーの基準に使う
let shareRequestTick = null;
let screen = 'none'; // 'none' | 'input' | 'player'
let isBusy = false;
let volumeSendTimer = null;

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
async function postAction(name) {
    try {
        await post(name, {}, 5000);
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
            showPlayerScreen(data.platform);
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
    }
});

// ESC で閉じる（NUI にフォーカスがあるとゲーム側はキーを受け取れないため、ここで処理する）
document.addEventListener('keydown', function(e) {
    if (e.key !== 'Escape' || e.repeat || screen === 'none') {
        return;
    }
    e.preventDefault();
    postAction('close');
});

// ================== 画面の切り替え ==================

// URL入力画面を表示
function showInputScreen(options) {
    const opts = options || {};
    screen = 'input';
    inputContainer.classList.remove('hidden');
    playerContainer.classList.add('hidden');

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
    playerRange.textContent = `${formatMeters(nearbyDistance)} 以内`;

    hidePlayerList();
    urlInput.focus();
}

// プレイヤー画面を表示
function showPlayerScreen(platform) {
    screen = 'player';
    updatePlatformBadge(platform === 'twitch' ? 'twitch' : 'youtube');
    hidePlayerList();
    inputContainer.classList.add('hidden');
    playerContainer.classList.remove('hidden');
}

// 全て閉じる
function closeAll() {
    screen = 'none';
    inputContainer.classList.add('hidden');
    playerContainer.classList.add('hidden');
    urlInput.value = '';
    hideError();
    hidePlayerList();
    setBusy(false);
}

// プラットフォームバッジを更新
function updatePlatformBadge(platform) {
    platformBadge.className = 'platform-badge ' + platform;
    platformName.textContent = platform === 'twitch' ? 'Twitch' : 'YouTube';
}

// 50 → "50m"、12.5 → "12.5m"（整数なら小数を付けない）
function formatMeters(value) {
    return (Number.isInteger(value) ? String(value) : value.toFixed(1)) + 'm';
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

// ================== 画面共有機能 ==================

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

        // 距離の数字と、検出範囲の中でどれだけ近いかのバー（近いほど長い）
        const distance = document.createElement('div');
        distance.className = 'player-distance';
        const distanceValue = document.createElement('div');
        distanceValue.className = 'player-distance-value num';
        distanceValue.textContent = player.distance.toFixed(1) + 'm';
        const track = document.createElement('div');
        track.className = 'player-distance-track';
        const fill = document.createElement('div');
        fill.className = 'player-distance-fill';
        const closeness = Math.max(0.04, Math.min(1, 1 - player.distance / nearbyDistance));
        fill.style.transform = `scaleX(${closeness.toFixed(3)})`;
        track.appendChild(fill);
        distance.append(distanceValue, track);

        item.append(checkbox, info, distance);

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

// ================== 共有された動画の承諾確認 ==================

function showShareRequest(data) {
    const from = typeof data.from === 'string' ? data.from : '不明';
    const platform = data.platform === 'twitch' ? 'Twitch' : 'YouTube';
    const timeoutMs = Number.isFinite(data.timeoutMs) && data.timeoutMs > 0 ? data.timeoutMs : 15000;

    shareRequestText.textContent = `${from} さんが ${platform} の動画を共有しました`;

    // キーの案内はキーキャップで出す（キー名は textContent で入れる）
    const keyHint = (key, label) => {
        const kbd = document.createElement('kbd');
        kbd.textContent = typeof key === 'string' && key !== '' ? key : '?';
        const text = document.createElement('span');
        text.textContent = label;
        return [kbd, text];
    };
    shareRequestHint.replaceChildren(
        ...keyHint(data.acceptKey || 'Y', 'で視聴'),
        ...keyHint(data.declineKey || 'N', 'で辞退（初期設定のキー）')
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

// 音量スライダー
volumeSlider.addEventListener('input', function() {
    currentVolume = parseInt(this.value, 10);
    if (currentVolume > 0) {
        // スライダーで音を上げたらミュート解除。次のボタン操作は「ミュート」になる
        isMuted = false;
        previousVolume = currentVolume;
    } else {
        isMuted = true;
    }
    updateVolumeUI();
    scheduleVolumeSend();
});

// ミュートボタン
volumeBtn.addEventListener('click', function() {
    if (isMuted) {
        isMuted = false;
        currentVolume = previousVolume || 50;
    } else {
        isMuted = true;
        previousVolume = currentVolume || previousVolume;
        currentVolume = 0;
    }

    volumeSlider.value = currentVolume;
    updateVolumeUI();
    scheduleVolumeSend();
});

function updateVolumeUI() {
    volumeFill.style.transform = `scaleX(${currentVolume / 100})`;
    volumeValue.textContent = currentVolume + '%';

    if (currentVolume === 0) {
        volumeIcon.innerHTML = `
            <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon>
            <line x1="23" y1="9" x2="17" y2="15"></line>
            <line x1="17" y1="9" x2="23" y2="15"></line>
        `;
        volumeBtn.classList.add('muted');
    } else if (currentVolume < 50) {
        volumeIcon.innerHTML = `
            <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon>
            <path d="M15.54 8.46a5 5 0 0 1 0 7.07"></path>
        `;
        volumeBtn.classList.remove('muted');
    } else {
        volumeIcon.innerHTML = `
            <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon>
            <path d="M15.54 8.46a5 5 0 0 1 0 7.07"></path>
            <path d="M19.07 4.93a10 10 0 0 1 0 14.14"></path>
        `;
        volumeBtn.classList.remove('muted');
    }
}

// ドラッグ中に大量に送らないよう、短い間隔でまとめて最新の値だけ送る
function scheduleVolumeSend() {
    if (volumeSendTimer !== null) {
        return;
    }
    volumeSendTimer = setTimeout(function() {
        volumeSendTimer = null;
        postQuiet('volumeChange', { volume: currentVolume });
    }, 80);
}

// 初期化
updateVolumeUI();
updateShareButton();
