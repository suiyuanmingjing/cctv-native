# CCTV 直播 · Flutter 电视版（内置 GeckoView，不使用 WebView）

电视端 Flutter 重写：频道网格和播放控制层用 Flutter，视频画面由 **GeckoView 平台视图**承载。
GeckoView 内核随 APK 安装，不依赖电视盒子的系统 WebView。

- 包名：`com.cctv.tv`
- 最低系统：Android 7.0（API 24）
- targetSdk：36
- 架构：`arm64-v8a` + `armeabi-v7a`
- GeckoView：`128.0.20240725162350`
- 签名：`CN=suiyuanmingjing`
- 安装包：[`dist/cctv-tv-1.0.0-flutter-gecko-universal.apk`](dist/cctv-tv-1.0.0-flutter-gecko-universal.apk)（147.6 MB）

## 功能

- 18 个 CCTV 频道，Flutter 电视网格，遥控器焦点高亮
- 播放页：确定键播放/暂停、上下键换台、左键打开频道列表、返回键回主页
- 频道列表：上下选择、确定键切换、左键/返回关闭
- 自动播放、加载/缓冲提示、错误重试、记住上次频道
- 保持屏幕常亮、音频焦点
- 画质/分辨率标记、已观看时长
- 不使用 WebView

## 实测情况

已在 Android 12（API 31）手机上通过 ADB 安装验证：

- 手机版 `com.cctv.live` 安装并播放 CCTV-1 正常
- 电视版 `com.cctv.tv` 安装成功，GeckoView 画面正常显示
- 播放页上下键换台（CCTV-1 → CCTV-2 → CCTV-3）正常
- 左键频道列表、列表内选择切换正常
- 确定键播放/暂停正常
- 两个 APK 均为 `suiyuanmingjing` 签名

> 电视主页的方向键焦点切换在手机模拟 D-pad 上只验证到首项聚焦；播放页上下换台和左键频道列表已验证。
> 部分设备会显示系统默认焦点高亮边框，可在 Android 主题中关闭 `defaultFocusHighlightEnabled`。

## 架构

```text
cctv_tv_flutter/
├── lib/
│   ├── screens/tv_home_screen.dart     # Flutter 频道网格
│   ├── screens/tv_player_screen.dart   # Flutter 播放控制层 + AndroidView
│   ├── widgets/tv_channel_card.dart
│   └── core/                           # 主题、偏好、原生通道
├── android/app/src/main/kotlin/com/cctv/tv/
│   ├── MainActivity.kt
│   ├── GeckoViewFactory.kt
│   ├── GeckoViewPlatformView.kt        # GeckoView 平台视图 + WebExtension 消息
│   └── GeckoRuntimeHolder.kt
└── android/app/src/main/assets/geckoview/
    ├── manifest.json                   # nativeMessaging / nativeMessagingFromContent
    └── cctv_tv.js                      # 舞台化、状态上报、播放/静音命令
```

Flutter 通过 `AndroidView(viewType: 'cctv/tv/geckoview')` 嵌入原生 GeckoView；内容脚本每 450ms
通过 `browser.runtime.sendNativeMessage` 上报 `<video>` 状态，并接收 Flutter 下发的
`play` / `pause` / `mute` / `stage` 命令。

## 构建

```bash
cd cctv_tv_flutter
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

flutter pub get
flutter analyze
flutter test
flutter build apk --release --no-pub --target-platform android-arm,android-arm64
```

重新签名：

```bash
zipalign -f -p 4 app-release.apk app-release-aligned.apk
apksigner sign \
  --ks ../signing/suiyuanmingjing.jks \
  --ks-key-alias suiyuanmingjing \
  --ks-pass pass:Suiyuanmingjing@2026 \
  --key-pass pass:Suiyuanmingjing@2026 \
  --out cctv-tv-1.0.0-flutter-gecko-universal.apk \
  app-release-aligned.apk
```

## 说明

本应用只打开央视网（tv.cctv.com）的公开直播页面，不解析、不代理、不保存任何视频内容。
