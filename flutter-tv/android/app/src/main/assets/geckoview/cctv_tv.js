/*
 * cctv_tv.js —— CCTV 电视版 GeckoView 内容脚本
 * ---------------------------------------------------------------------------
 * 只做三件事：
 *   1. 把官网播放页舞台化：视频铺满屏幕，隐藏网页导航和播放器自带控件；
 *   2. 自动播放，并把 <video> 状态通过 WebExtension native messaging 上报给 Flutter；
 *   3. 接收 Flutter 发来的 play / pause / mute / seekLive 命令。
 *
 * 不解析、不代理、不保存任何视频内容。
 */
(function () {
  'use strict';

  if (window.top !== window.self) return;
  if (window.__CCTV_TV__ && window.__CCTV_TV__.installed) return;

  var STAGE_CLASS = 'cctv-tv-stage';
  var STYLE_ID = 'cctv-tv-style';
  var startedAt = Date.now();
  var AUTO_PLAY_MS = 15000;
  var NO_VIDEO_MS = 20000;

  var video = null;
  var boundVideo = null;
  var readySent = false;
  var autoplayBlockedSent = false;
  var noVideoSent = false;
  var userPaused = false;
  var tickTimer = null;
  var polling = false;

  function sendNative(message) {
    try {
      if (typeof browser === 'undefined' || !browser.runtime ||
          typeof browser.runtime.sendNativeMessage !== 'function') {
        return Promise.resolve(null);
      }
      return browser.runtime.sendNativeMessage('browser', message);
    } catch (e) {
      return Promise.resolve(null);
    }
  }

  /* -------------------------------- 舞台 CSS ------------------------------- */
  function cssText() {
    return [
      'html.' + STAGE_CLASS + ', html.' + STAGE_CLASS + ' body {',
      '  background:#000 !important; overflow:hidden !important;',
      '  margin:0 !important; padding:0 !important; width:100% !important;',
      '}',
      'html.' + STAGE_CLASS + ' body > * { visibility:hidden !important; }',
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
      'html.' + STAGE_CLASS + ' video.cctv-tv-video {',
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
      video.classList.add('cctv-tv-video');
    }
    if (video) {
      video.style.setProperty('object-fit', 'contain', 'important');
      video.style.setProperty('object-position', 'center center', 'important');
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
      if (player) {
        var raw = String(player.textContent || player.innerText || '').trim();
        if (raw && raw.length <= 120) text = raw;
      }
    }
    return text.replace(/\s+/g, ' ').slice(0, 160);
  }

  function describeError(v) {
    if (!v || !v.error) return siteMessage();
    var map = { 1: '播放被中止', 2: '网络错误', 3: '视频解码失败', 4: '视频格式不支持' };
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
    }
    try {
      var promise = v.play();
      if (promise && typeof promise.catch === 'function') {
        promise.catch(function (err) {
          var name = err && err.name ? err.name : '';
          if (name === 'NotAllowedError') {
            if (!autoplayBlockedSent) {
              autoplayBlockedSent = true;
              sendNative({ type: 'autoplayBlocked', data: { name: name } });
            }
          } else if (name !== 'AbortError') {
            sendNative({
              type: 'error',
              data: { message: String(err && err.message || err).slice(0, 200) }
            });
          }
        });
      }
    } catch (e) {
      sendNative({ type: 'error', data: { message: String(e && e.message || e).slice(0, 200) } });
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
    var v = findVideo();
    if (v) {
      try { v.muted = !!muted; } catch (e) { /* ignore */ }
    }
    reportState();
  }

  /* ------------------------------- 状态上报 -------------------------------- */
  function state() {
    var v = findVideo();
    if (v && v !== boundVideo) bindVideo(v);
    var hasPicture = !!v && v.readyState >= 2;
    return {
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
      stage: document.documentElement.classList.contains(STAGE_CLASS)
    };
  }

  function reportState() {
    var s = state();
    if (s.readyState >= 2 && !readySent) {
      readySent = true;
      sendNative({ type: 'ready', data: s });
    }
    return s;
  }

  function execCommand(command) {
    switch (String(command)) {
      case 'play':
        play(true);
        break;
      case 'pause':
        pause();
        break;
      case 'toggle':
        if (video && !video.paused) pause(); else play(true);
        break;
      case 'mute':
        setMuted(true);
        break;
      case 'unmute':
        setMuted(false);
        break;
      case 'seekLive':
        var live = document.getElementById('return_to_live_player');
        if (live && typeof live.click === 'function') {
          try { live.click(); } catch (e) { /* ignore */ }
        }
        break;
      case 'stage':
        applyStage();
        break;
      default:
        break;
    }
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
      'ended', 'volumechange'
    ];
    for (var i = 0; i < events.length; i++) {
      try { v.addEventListener(events[i], onVideoEvent, false); } catch (e) { /* ignore */ }
    }
    sendNative({ type: 'videoDetected', data: { id: v.id || '' } });
    reportState();
  }

  function onVideoEvent(event) {
    if (!video) return;
    if (event && event.type === 'playing') {
      autoplayBlockedSent = false;
    } else if (event && event.type === 'error') {
      sendNative({ type: 'error', data: { message: describeError(video) } });
    }
    reportState();
  }

  /* -------------------------------- 主循环 --------------------------------- */
  function tick() {
    tickTimer = null;
    var v = findVideo();
    if (v) {
      bindVideo(v);
      applyStage();
      if (v.paused && !userPaused && !autoplayBlockedSent &&
          Date.now() - startedAt < AUTO_PLAY_MS) {
        play(false);
      }
    } else if (!noVideoSent && Date.now() - startedAt > NO_VIDEO_MS) {
      noVideoSent = true;
      sendNative({ type: 'noVideo', data: { siteMessage: siteMessage() } });
    }

    if (!polling) {
      polling = true;
      var s = reportState();
      sendNative({ type: 'state', data: s }).then(function (response) {
        polling = false;
        if (typeof response === 'string') {
          try { response = JSON.parse(response); } catch (e) { response = null; }
        }
        var commands = response && response.commands ? response.commands : [];
        for (var i = 0; i < commands.length; i++) {
          execCommand(commands[i]);
        }
      }).catch(function () {
        polling = false;
      });
    }

    tickTimer = setTimeout(tick, 450);
  }

  function start() {
    if (tickTimer) return;
    applyStage();
    var v = findVideo();
    if (v) {
      bindVideo(v);
      play(false);
    }
    reportState();
    tickTimer = setTimeout(tick, 450);
  }

  window.__CCTV_TV__ = {
    installed: true,
    version: '1.0.0',
    play: function () { return play(true); },
    pause: pause,
    setMuted: setMuted,
    state: state,
    stop: function () {
      if (tickTimer) {
        clearTimeout(tickTimer);
        tickTimer = null;
      }
    }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
