/*
 * cctv_native.js —— CCTV 直播 Flutter 手机版注入脚本
 * ---------------------------------------------------------------------------
 * 只做播放器该做的事：
 *   1. 把官网播放页"舞台化"：视频铺满窗口，隐藏网页其它元素和自带控件；
 *   2. 找到 <video>，尽力自动播放，并向 Flutter 上报实时状态；
 *   3. 在网页里识别点击 / 双击 / 上下滑 / 左滑手势，交给 Flutter 处理。
 *
 * 不解析、不代理、不保存任何视频内容。
 */
(function () {
  'use strict';

  var VERSION = '2.0.0';
  var BRIDGE = 'CctvEvents';
  var STAGE_CLASS = 'cctv-native-stage';
  var STYLE_ID = 'cctv-native-style';
  var CONFIG = window.__CCTV_CONFIG__ || {};
  var AUTO_PLAY_MS = CONFIG.autoPlayMs || 15000;
  var NO_VIDEO_MS = CONFIG.noVideoMs || 20000;

  if (window.__CCTV_NATIVE__ && window.__CCTV_NATIVE__.installed) {
    window.__CCTV_NATIVE__.refresh();
    return;
  }

  var video = null;
  var boundVideo = null;
  var readySent = false;
  var autoplayBlockedSent = false;
  var noVideoSent = false;
  var userPaused = false;
  var desiredMuted = false;
  var lastAutoPlayAt = 0;
  var startedAt = Date.now();
  var ticker = null;
  var fitMode = 'contain';

  var tapTimer = null;
  var lastTapAt = 0;
  var touch = null;

  /* ----------------------------- 与 Flutter 通信 ---------------------------- */
  function send(type, data) {
    try {
      var payload = JSON.stringify({ type: type, data: data || {} });
      var bridge = window[BRIDGE];
      if (bridge && typeof bridge.postMessage === 'function') {
        bridge.postMessage(payload);
      }
    } catch (e) { /* ignore */ }
  }

  /* -------------------------------- 舞台 CSS ------------------------------- */
  function cssText() {
    return [
      'html.' + STAGE_CLASS + ', html.' + STAGE_CLASS + ' body {',
      '  background:#000 !important; overflow:hidden !important;',
      '  margin:0 !important; padding:0 !important; width:100% !important;',
      '  height:100% !important; position:fixed !important; inset:0 !important;',
      '  touch-action:none !important; overscroll-behavior:none !important;',
      '}',
      'html.' + STAGE_CLASS + ' body > * { visibility:hidden !important; }',
      'html.' + STAGE_CLASS + ' #cctv-native-video-stage,',
      'html.' + STAGE_CLASS + ' #cctv-native-video-stage * { visibility:visible !important; }',
      'html.' + STAGE_CLASS + ' #cctv-native-video-stage {',
      '  position:fixed !important; inset:0 !important; width:100vw !important; height:100vh !important;',
      '  background:#000 !important; overflow:hidden !important; z-index:2147483646 !important;',
      '  touch-action:none !important;',
      '}',
      'html.' + STAGE_CLASS + ' #player,',
      'html.' + STAGE_CLASS + ' #player * { visibility:visible !important; }',
      'html.' + STAGE_CLASS + ' #player {',
      '  position:fixed !important; left:0 !important; top:0 !important;',
      '  width:100vw !important; height:100vh !important;',
      '  max-width:none !important; max-height:none !important;',
      '  margin:0 !important; padding:0 !important;',
      '  z-index:2147483647 !important; background:#000 !important;',
      '}',
      'html.' + STAGE_CLASS + ' #player > *:not(video) { display:none !important; }',
      'html.' + STAGE_CLASS + ' #player video {',
      '  display:block !important; width:100% !important; height:100% !important;',
      '  object-fit:contain !important; background:#000 !important;',
      '}',
      'html.' + STAGE_CLASS + ' video.cctv-native-video {',
      '  position:fixed !important; left:0 !important; top:0 !important;',
      '  width:100vw !important; height:100vh !important;',
      '  z-index:2147483647 !important; object-fit:contain !important;',
      '  background:#000 !important; visibility:visible !important;',
      '}',
      'html.' + STAGE_CLASS + ' video::-webkit-media-controls { display:none !important; }',
      'html.' + STAGE_CLASS + ' ::-webkit-scrollbar { display:none !important; }',
      'html.' + STAGE_CLASS + ' * {',
      '  -webkit-tap-highlight-color:transparent !important;',
      '  -webkit-user-select:none !important; user-select:none !important;',
      '  -webkit-touch-callout:none !important;',
      '}'
    ].join('\n');
  }

  function ensureVideoStage() {
    var v = video;
    if (!v) return;
    var stage = document.getElementById('cctv-native-video-stage');
    if (!stage) {
      stage = document.createElement('div');
      stage.id = 'cctv-native-video-stage';
      (document.body || document.documentElement).appendChild(stage);
    }
    if (v.parentElement !== stage) {
      try { stage.appendChild(v); } catch (e) { /* ignore */ }
    }
  }
  function applyFit() {
    var v = video;
    if (!v) return;
    ensureVideoStage();
    var vw = v.videoWidth || 0;
    var vh = v.videoHeight || 0;
    var ww = window.innerWidth || document.documentElement.clientWidth || 0;
    var wh = window.innerHeight || document.documentElement.clientHeight || 0;
    if (vw <= 0 || vh <= 0 || ww <= 0 || wh <= 0) return;

    // 不用 object-fit 赌网页 CSS：直接按视频原始比例算出像素尺寸并居中。
    var scale = fitMode === 'cover'
      ? Math.max(ww / vw, wh / vh)
      : Math.min(ww / vw, wh / vh);
    var width = Math.round(vw * scale);
    var height = Math.round(vh * scale);

    v.style.setProperty('position', 'fixed', 'important');
    v.style.setProperty('left', Math.round((ww - width) / 2) + 'px', 'important');
    v.style.setProperty('top', Math.round((wh - height) / 2) + 'px', 'important');
    v.style.setProperty('width', width + 'px', 'important');
    v.style.setProperty('height', height + 'px', 'important');
    v.style.setProperty('max-width', 'none', 'important');
    v.style.setProperty('max-height', 'none', 'important');
    v.style.setProperty('object-fit', 'fill', 'important');
    v.style.setProperty('object-position', 'center center', 'important');
    v.style.setProperty('transform', 'none', 'important');
    v.style.setProperty('margin', '0', 'important');
    v.style.setProperty('background', '#000', 'important');
    v.style.setProperty('z-index', '2147483647', 'important');
  }
  function applyStage() {
    var html = document.documentElement;
    if (!html) return;

    var style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement('style');
      style.id = STYLE_ID;
      style.type = 'text/css';
      (document.head || html).appendChild(style);
    }
    var css = cssText();
    if (style.textContent !== css) style.textContent = css;

    if (!html.classList.contains(STAGE_CLASS)) {
      html.classList.add(STAGE_CLASS);
    }

    var player = document.getElementById('player');
    if (player) {
      player.style.setProperty('width', '100vw', 'important');
      player.style.setProperty('height', '100vh', 'important');
      player.style.setProperty('position', 'fixed', 'important');
      player.style.setProperty('left', '0', 'important');
      player.style.setProperty('top', '0', 'important');
      player.style.setProperty('z-index', '2147483647', 'important');
      player.style.setProperty('background', '#000', 'important');
    } else if (video) {
      video.classList.add('cctv-native-video');
    }

    if (video) {
      applyFit();
    }
  }

  /* ------------------------------ 查找视频元素 ----------------------------- */
  function deepFind(root, depth) {
    if (!root || depth > 4) return null;
    var all = null;
    try { all = root.querySelectorAll('*'); } catch (e) { return null; }
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (el.tagName === 'IFRAME') {
        var doc = null;
        try { doc = el.contentDocument; } catch (e) { doc = null; }
        if (doc) {
          var inFrame = deepFind(doc, depth + 1);
          if (inFrame) return inFrame;
        }
      } else if (el.shadowRoot) {
        var inShadow = deepFind(el.shadowRoot, depth + 1);
        if (inShadow) return inShadow;
      }
    }
    return null;
  }

  function findVideo() {
    if (video && video.isConnected) return video;
    var v = null;
    try { v = document.querySelector('video'); } catch (e) { v = null; }
    if (v) return v;
    return deepFind(document, 0);
  }

  function siteMessage() {
    var el = document.getElementById('error_msg_player');
    if (!el) {
      try { el = document.querySelector('.error_msg'); } catch (e) { el = null; }
    }
    var text = el ? String(el.textContent || el.innerText || '').trim() : '';
    if (!text) {
      var player = document.getElementById('player');
      if (player && player.innerText) {
        var raw = String(player.textContent || player.innerText || '').trim();
        if (raw && raw.length <= 120) text = raw;
      }
    }
    return text.replace(/\s+/g, ' ').slice(0, 160);
  }

  function describeError(v) {
    if (!v || !v.error) return siteMessage();
    var map = {
      1: '播放被中止',
      2: '网络错误',
      3: '视频解码失败',
      4: '视频格式不支持'
    };
    var message = map[v.error.code] || '播放器错误';
    if (v.error.message) message += '：' + v.error.message;
    return message;
  }

  /* ------------------------------- 播放控制 -------------------------------- */
  function play(force) {
    var v = findVideo();
    if (!v) return false;
    bindVideo(v);
    if (force) {
      autoplayBlockedSent = false;
      userPaused = false;
    } else if (v.paused) {
      // 浏览器只允许静音自动播放；这里只静音到 play() 成功，随后立即恢复声音。
      try { v.muted = true; } catch (e) { /* ignore */ }
    }
    try {
      var promise = v.play();
      if (promise && typeof promise.then === 'function') {
        promise.then(function () {
          if (!desiredMuted) {
            // 自动播放只借用一瞬间静音，播放成功后立刻恢复声音和音量。
            try { v.muted = false; } catch (e) { /* ignore */ }
            try { v.volume = 1; } catch (e) { /* ignore */ }
          }
        });
      }
      if (promise && typeof promise.catch === 'function') {
        promise.catch(function (err) {
          var name = err && err.name ? err.name : '';
          if (name === 'NotAllowedError') {
            if (!autoplayBlockedSent) {
              autoplayBlockedSent = true;
              send('autoplayBlocked', { name: name });
            }
          } else if (name !== 'AbortError') {
            send('videoError', {
              message: String(err && err.message || err).slice(0, 200)
            });
          }
        });
      }
    } catch (e) {
      send('videoError', { message: String(e && e.message || e).slice(0, 200) });
    }
    return true;
  }

  function pause() {
    userPaused = true;
    var v = findVideo();
    if (v) {
      try { v.pause(); } catch (e) { /* ignore */ }
    }
    reportState();
  }

  function setMuted(muted) {
    desiredMuted = !!muted;
    var v = findVideo();
    if (v) {
      try { v.muted = !!muted; } catch (e) { /* ignore */ }
      if (!desiredMuted) {
        try { v.volume = 1; } catch (e) { /* ignore */ }
      }
    }
    reportState();
  }

  /* ------------------------------- 状态上报 -------------------------------- */
  function state() {
    var v = findVideo();
    if (v && v !== boundVideo) bindVideo(v);
    var hasPicture = !!v && v.readyState >= 2;
    var s = {
      found: !!v,
      paused: v ? !!v.paused : true,
      muted: v ? !!v.muted : false,
      readyState: v ? v.readyState : 0,
      networkState: v ? v.networkState : 0,
      buffering: !!v && !v.paused && v.readyState < 3,
      currentTime: v && isFinite(v.currentTime) ? v.currentTime : 0,
      width: v ? v.videoWidth : 0,
      height: v ? v.videoHeight : 0,
      error: v && v.error ? describeError(v) : '',
      siteMessage: hasPicture ? '' : siteMessage(),
      stage: document.documentElement.classList.contains(STAGE_CLASS),
      src: v && v.currentSrc ? String(v.currentSrc).slice(0, 180) : ''
    };
    return s;
  }

  function reportState() {
    var s = state();
    if (s.readyState >= 2 && !readySent) {
      readySent = true;
      send('ready', s);
    }
    send('state', s);
    return s;
  }

  /* ------------------------------- 事件绑定 -------------------------------- */
  function bindVideo(v) {
    if (!v || v === boundVideo) return;
    boundVideo = v;
    video = v;
    readySent = false;

    try { v.volume = 1; } catch (e) { /* ignore */ }

    var events = [
      'loadedmetadata', 'loadeddata', 'canplay', 'canplaythrough',
      'playing', 'play', 'pause', 'waiting', 'stalled', 'error',
      'ended', 'volumechange', 'enterpictureinpicture'
    ];
    for (var i = 0; i < events.length; i++) {
      try { v.addEventListener(events[i], onVideoEvent, false); } catch (e) { /* ignore */ }
    }

    send('videoDetected', { id: v.id || '' });
    ensureVideoStage();
    applyFit();
    reportState();
  }

  function onVideoEvent(event) {
    if (!video) return;
    applyFit();
    var type = event && event.type;
    if (type === 'playing') {
      autoplayBlockedSent = false;
      if (!desiredMuted) {
        try { video.muted = false; } catch (e) { /* ignore */ }
      }
      send('playing', {});
    } else if (type === 'pause') {
      send('paused', {});
    } else if (type === 'error') {
      send('videoError', { message: describeError(video) });
    } else if (type === 'ended') {
      send('ended', {});
    }
    reportState();
  }

  /* -------------------------------- 主循环 --------------------------------- */
  function tick() {
    var v = findVideo();
    if (v) {
      bindVideo(v);
      applyStage();
      if (!desiredMuted) {
        // 网页播放器可能把 muted 或 volume 改成 0，这里强制恢复声音。
        try { v.muted = false; } catch (e) { /* ignore */ }
        try { if (v.volume < 0.99) v.volume = 1; } catch (e) { /* ignore */ }
        try { v.defaultMuted = false; } catch (e) { /* ignore */ }
      }

      // 只要不是用户主动暂停，就持续尝试自动播放；直播页自己暂停后也会被拉回来。
      if (v.paused && !userPaused && Date.now() - lastAutoPlayAt > 1200) {
        lastAutoPlayAt = Date.now();
        play(false);
      }
    } else if (!noVideoSent && Date.now() - startedAt > NO_VIDEO_MS) {
      noVideoSent = true;
      send('noVideo', { siteMessage: siteMessage() });
    }
    reportState();
  }

  /* ------------------------------ 触摸手势 -------------------------------- */
  function hasSingleTouch(event) {
    return event && event.touches && event.touches.length === 1;
  }

  function onTouchStart(event) {
    if (!hasSingleTouch(event)) return;
    var t = event.touches[0];
    touch = {
      x: t.clientX,
      y: t.clientY,
      side: t.clientX < window.innerWidth / 2 ? 'left' : 'right',
      mode: null,
      moved: false,
      lastNorm: 0,
      opened: false
    };
    try { event.stopPropagation(); } catch (e) { /* ignore */ }
    try { event.preventDefault(); } catch (e) { /* ignore */ }
  }

  function onTouchMove(event) {
    if (!touch || !hasSingleTouch(event)) return;
    try { event.preventDefault(); } catch (e) { /* ignore */ }
    var t = event.touches[0];
    var dx = t.clientX - touch.x;
    var dy = t.clientY - touch.y;

    if (!touch.mode) {
      if (Math.abs(dx) < 10 && Math.abs(dy) < 10) return;
      touch.moved = true;
      touch.mode = Math.abs(dx) > Math.abs(dy) * 1.25 ? 'horizontal' : 'vertical';
      if (touch.mode === 'vertical') {
        send('gesture', { phase: 'start', side: touch.side, dy: 0 });
      }
    }

    if (touch.mode === 'vertical') {
      var norm = (touch.y - t.clientY) / Math.max(window.innerHeight, 1);
      if (Math.abs(norm - touch.lastNorm) > 0.002) {
        touch.lastNorm = norm;
        send('gesture', { phase: 'move', side: touch.side, dy: norm });
      }
      try { event.preventDefault(); } catch (e) { /* ignore */ }
      try { event.stopPropagation(); } catch (e) { /* ignore */ }
    } else if (touch.mode === 'horizontal') {
      if (!touch.opened && dx / Math.max(window.innerWidth, 1) > 0.18) {
        touch.opened = true;
        send('openChannels', {});
      }
      try { event.preventDefault(); } catch (e) { /* ignore */ }
      try { event.stopPropagation(); } catch (e) { /* ignore */ }
    }
  }

  function onTouchEnd(event) {
    if (!touch) return;
    var current = touch;
    touch = null;

    if (current.mode === 'vertical') {
      send('gesture', {
        phase: 'end',
        side: current.side,
        dy: current.lastNorm
      });
      try { event.preventDefault(); } catch (e) { /* ignore */ }
      return;
    }
    if (current.mode === 'horizontal') return;

    if (!current.moved) {
      var now = Date.now();
      if (now - lastTapAt < 320) {
        if (tapTimer) {
          clearTimeout(tapTimer);
          tapTimer = null;
        }
        lastTapAt = 0;
        send('doubleTap', {});
      } else {
        lastTapAt = now;
        tapTimer = setTimeout(function () {
          tapTimer = null;
          if (lastTapAt) {
            lastTapAt = 0;
            send('tap', {});
            // 单击时如果处于暂停，顺便恢复播放；240ms 仍在用户激活窗口内。
            var current = findVideo();
            if (current && current.paused) play(true);
          }
        }, 240);
      }

      try { event.preventDefault(); } catch (e) { /* ignore */ }
      try { event.stopPropagation(); } catch (e) { /* ignore */ }
    }
  }

  function onTouchCancel() {
    if (touch && touch.mode === 'vertical') {
      send('gesture', {
        phase: 'end',
        side: touch.side,
        dy: touch.lastNorm
      });
    }
    touch = null;
  }

  function installGestures() {
    if (window.__CCTV_GESTURES__) return;
    window.__CCTV_GESTURES__ = true;
    var options = { capture: true, passive: false };
    document.addEventListener('contextmenu', function (event) {
      try { event.preventDefault(); } catch (e) { /* ignore */ }
      try { event.stopPropagation(); } catch (e) { /* ignore */ }
    }, options);
    document.addEventListener('touchstart', onTouchStart, options);
    document.addEventListener('touchmove', onTouchMove, options);
    document.addEventListener('touchend', onTouchEnd, options);
    document.addEventListener('touchcancel', onTouchCancel, options);
  }

  /* ------------------------------ 对外 API -------------------------------- */
  window.__CCTV_NATIVE__ = {
    installed: true,
    version: VERSION,
    play: function () { return play(true); },
    autoplay: function () { return play(false); },
    pause: pause,
    toggle: function () {
      var v = findVideo();
      if (!v) return false;
      if (v.paused) return play(true);
      pause();
      return true;
    },
    setMuted: setMuted,
    kick: function () { applyStage(); return play(true); },
    stage: function () { applyStage(); },
    setFit: function (mode) {
      fitMode = mode === 'cover' ? 'cover' : 'contain';
      applyFit();
      reportState();
    },
    refresh: function () {
      startedAt = Date.now();
      noVideoSent = false;
      applyStage();
      var v = findVideo();
      if (v) {
        bindVideo(v);
        play(true);
      }
      reportState();
    },
    state: state,
    probe: function () { return !!findVideo(); },
    stop: function () {
      if (ticker) {
        clearInterval(ticker);
        ticker = null;
      }
    }
  };

  /* --------------------------------- 启动 --------------------------------- */
  function boot() {
    installGestures();
    window.addEventListener('resize', applyStage);
    applyStage();
    var v = findVideo();
    if (v) {
      bindVideo(v);
      play(false);
    }
    reportState();
    send('scriptReady', { version: VERSION, top: window.top === window.self });

    if (!ticker) {
      ticker = setInterval(tick, 500);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
