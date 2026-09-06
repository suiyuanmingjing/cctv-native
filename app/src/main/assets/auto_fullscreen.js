/*
 * auto_fullscreen.js —— CCTV 直播"打开即全屏"注入脚本（初版）
 *
 * 只做一件事：等 <video> 出现，然后请求全屏。
 */
(function () {
  'use strict';

  if (window.__CCTV_FS__ && window.__CCTV_FS__.installed) {
    return;
  }

  const checkVideo = setInterval(() => {
    const video = document.querySelector('video');
    if (video) {
      clearInterval(checkVideo);
      // 尝试自动全屏
      if (video.requestFullscreen) {
        video.requestFullscreen().catch(() => {});
      } else if (video.webkitEnterFullscreen) {
        video.webkitEnterFullscreen();
      }
    }
  }, 500);
})();
