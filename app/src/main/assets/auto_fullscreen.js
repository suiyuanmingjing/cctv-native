/*
 * auto_fullscreen.js —— CCTV 直播"打开即全屏"注入脚本
 * ---------------------------------------------------------------------------
 * 设计约束（务必保持不变）：
 *   - 不隐藏官网任何元素、不重排布局、不自定义控制栏；
 *   - 只做三件事：等待 <video> → 尽力开始播放 → 请求全屏；
 *   - 失败时上报 native，由 native 显示"点击全屏"回退按钮。
 *
 * 共用方：Flutter(flutter_inappwebview) 与 Tauri(WebView2)。
 * 两份副本必须完全一致，运行 `node tools/verify.mjs` 校验。
 */
(function () {
  'use strict';

  if (window.__CCTV_FS__ && window.__CCTV_FS__.installed) {
    return;
  }

  var CONFIG = window.__CCTV_FS_CONFIG__ || {};
  var DEADLINE_MS = CONFIG.deadlineMs || 60000;
  var INTERVAL_MS = CONFIG.intervalMs || 500;
  var SELECTOR = CONFIG.selector || 'video';
  var ALLOW_AUTOPLAY = CONFIG.allowAutoplay !== false;

  var startedAt = Date.now();
  var timer = null;
  var observer = null;
  var boundVideo = null;
  var failedReported = false;
  var enteredReported = false;
  var lastError = '';

  /* ----------------------------- 与 native 通信 ---------------------------- */
  function bridge(event, data) {
    var msg = {
      source: 'cctv-fullscreen',
      event: event,
      data: data || {},
      ts: Date.now()
    };
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('CCTVNative', msg);
        return;
      }
    } catch (e) { /* ignore */ }
    try {
      if (window.__TAURI__ && window.__TAURI__.event && window.__TAURI__.event.emit) {
        window.__TAURI__.event.emit('cctv-fullscreen', msg);
        return;
      }
    } catch (e) { /* ignore */ }
    try {
      if (window.CCTVNative && window.CCTVNative.postMessage) {
        window.CCTVNative.postMessage(JSON.stringify(msg));
      }
    } catch (e) { /* ignore */ }
  }

  /* --------------------------- 深度查找 <video> --------------------------- */
  // 官网播放器可能位于 shadow DOM 或同源 iframe 内；跨域 iframe 无法访问，
  // 因此对跨域子框架由 native 侧对该 frame 单独注入本脚本。
  function queryDeep(root, depth) {
    if (!root || depth > 4) return null;
    var hit = null;
    try { hit = root.querySelector(SELECTOR); } catch (e) { hit = null; }
    if (hit) return hit;

    var all;
    try { all = root.querySelectorAll('*'); } catch (e) { return null; }
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (el.tagName === 'IFRAME') {
        var doc = null;
        try { doc = el.contentDocument; } catch (e) { doc = null; }
        if (doc) {
          var inFrame = queryDeep(doc, depth + 1);
          if (inFrame) return inFrame;
        }
      } else if (el.shadowRoot) {
        var inShadow = queryDeep(el.shadowRoot, depth + 1);
        if (inShadow) return inShadow;
      }
    }
    return null;
  }

  function findVideo() {
    return queryDeep(document, 0);
  }

  /* ------------------------------- 全屏逻辑 ------------------------------- */
  function isFullscreen() {
    return !!(
      document.fullscreenElement ||
      document.webkitFullscreenElement ||
      document.mozFullScreenElement ||
      document.msFullscreenElement
    );
  }

  function requestFullscreen(video) {
    var el = (CONFIG.fullscreenTarget === 'container' && video.parentElement)
      ? video.parentElement
      : video;

    try {
      if (el.requestFullscreen) {
        var p = el.requestFullscreen();
        if (p && typeof p.then === 'function') {
          p.then(function () { reportEntered(); })
           .catch(function (err) {
             lastError = String(err && err.message || err);
             bridge('fullscreen-failed', { reason: lastError });
           });
        }
        // 注意：这里只是"发出了请求"，**不代表成功**。
        bridge('fullscreen-requested', {});
        return true;
      }
      if (el.webkitRequestFullscreen) {
        el.webkitRequestFullscreen(); bridge('fullscreen-requested', {}); return true;
      }
      if (el.mozRequestFullScreen) {
        el.mozRequestFullScreen(); bridge('fullscreen-requested', {}); return true;
      }
      if (el.msRequestFullscreen) {
        el.msRequestFullscreen(); bridge('fullscreen-requested', {}); return true;
      }
      // 老式 WebView / iOS：直接让 video 元素自身进入全屏
      if (video.webkitEnterFullscreen) {
        video.webkitEnterFullscreen(); bridge('fullscreen-requested', {}); return true;
      }
    } catch (e) {
      lastError = String(e && e.message || e);
    }
    return false;
  }

  function startPlayback(video) {
    if (!ALLOW_AUTOPLAY) return;
    try {
      if (video.paused) {
        var p = video.play();
        if (p && typeof p.catch === 'function') { p.catch(function () {}); }
      }
    } catch (e) { /* 需要用户手势时忽略，等待 KICK */ }

    // 部分页面把 <video> 放在启动遮罩之下，点一下官方播放按钮即可开始。
    var starters = [
      '.xgplayer-start',
      '.prism-player .prism-play-btn',
      '.prism-player .prism-big-play-btn',
      '.video-play-btn',
      '.play-btn'
    ];
    for (var i = 0; i < starters.length; i++) {
      var btn = null;
      try { btn = document.querySelector(starters[i]); } catch (e) { btn = null; }
      if (btn && typeof btn.click === 'function') {
        try { btn.click(); } catch (e) { /* ignore */ }
        break;
      }
    }
  }

  /* ------------------------------ 主循环 ---------------------------------- */
  function attempt(force) {
    var video = findVideo();
    if (!video) return false;

    if (video !== boundVideo) { bindVideo(video); }
    startPlayback(video);

    if (isFullscreen()) {
      reportEntered();
      return true;
    }

    return requestFullscreen(video);
  }

  /** 只有**真的**处于全屏状态才上报，native 依据它撤遮蔽层。 */
  function reportEntered() {
    if (enteredReported) return;
    enteredReported = true;
    bridge('fullscreen-entered', {});
  }

  function reportFailure(reason) {
    if (failedReported) return;
    failedReported = true;
    bridge('fullscreen-failed', { reason: reason || lastError || 'unknown' });
  }

  function tick() {
    if (isFullscreen()) { stopTimer(); return; }
    if (Date.now() - startedAt > DEADLINE_MS) {
      stopTimer();
      reportFailure('timeout');
      return;
    }
    attempt(false);
  }

  function startTimer() {
    if (timer) return;
    timer = setInterval(tick, INTERVAL_MS);
  }

  function stopTimer() {
    if (timer) { clearInterval(timer); timer = null; }
  }

  // 直播真正"能播"了才上报：native 依据它决定何时切全屏，
  // 避免页面刚 load 完就请求全屏导致失败。
  function reportReady(video) {
    if (video.__cctvReadyReported) return;
    if (video.readyState < 2) return;
    video.__cctvReadyReported = true;
    bridge('video-ready', { readyState: video.readyState, currentSrc: String(video.currentSrc || '').slice(0, 200) });
  }

  function bindVideo(video) {
    boundVideo = video;
    var fire = function () { attempt(false); reportReady(video); };
    ['loadedmetadata', 'loadeddata', 'canplay', 'canplaythrough', 'playing',
     'webkitbeginfullscreen', 'enterpictureinpicture']
      .forEach(function (evt) {
        try { video.addEventListener(evt, fire); } catch (e) { /* ignore */ }
      });
    reportReady(video);
    try {
      video.addEventListener('fullscreenchange', function () {
        if (isFullscreen()) { reportEntered(); }
        else { enteredReported = false; bridge('fullscreen-exited', {}); }
      });
    } catch (e) { /* ignore */ }
    bridge('video-detected', {});
  }

  function watchDom() {
    if (observer || typeof MutationObserver === 'undefined') return;
    observer = new MutationObserver(function () {
      if (isFullscreen()) return;
      if (findVideo()) { attempt(false); }
    });
    try {
      observer.observe(document.documentElement || document, { childList: true, subtree: true });
    } catch (e) { /* ignore */ }
  }

  /* --------------------- 对外接口（native 可主动调用） -------------------- */
  window.__CCTV_FS__ = {
    installed: true,
    version: '1.0.0',
    // 在收到遥控器/触摸事件时调用，以满足浏览器的用户手势要求。
    kick: function () {
      startedAt = Date.now();
      failedReported = false;
      enteredReported = false;
      var video = findVideo();
      if (video) { startPlayback(video); }
      var ok = attempt(true);
      if (!ok && video) { reportFailure('gesture-request-rejected'); }
      startTimer();
      return ok;
    },
    probe: function () { return !!findVideo(); },
    stop: function () { stopTimer(); if (observer) { observer.disconnect(); observer = null; } }
  };

  /* ------------------- 真实用户手势：补一次全屏请求 ------------------- */
  // 浏览器要求 requestFullscreen 处于"用户激活"上下文，纯自动调用可能被拒绝。
  // 这里在捕获阶段监听任意手势；脚本被注入到所有框架，iframe 内的点击同样生效。
  if (!window.__CCTV_FS_GESTURE__) {
    window.__CCTV_FS_GESTURE__ = true;
    var onGesture = function (evt) {
      if (isFullscreen()) return;
      // 关键：把这次手势吞掉，不让它继续传到官网播放器。
      // 否则一次点击会被播放器同时当成"播放/暂停"，出现
      // "全屏之后又暂停"的怪现象。
      try { evt.stopPropagation(); } catch (e) { /* ignore */ }
      try { evt.preventDefault(); } catch (e) { /* ignore */ }
      window.__CCTV_FS__.kick();
    };
    ['pointerdown', 'touchstart', 'click'].forEach(function (evt) {
      try {
        window.addEventListener(evt, onGesture, { capture: true, passive: false });
      } catch (e) {
        window.addEventListener(evt, onGesture, true);
      }
    });
  }

  /* --------------------------------- 启动 --------------------------------- */
  function boot() {
    bridge('script-ready', { version: '1.0.0', top: window.top === window.self });
    watchDom();
    // 首次尝试不依赖用户手势；若被拒绝，native 会在按键时调用 kick()。
    attempt(false);
    startTimer();
    document.addEventListener('fullscreenchange', function () {
      if (isFullscreen()) { reportEntered(); }
      else { enteredReported = false; bridge('fullscreen-exited', {}); }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
