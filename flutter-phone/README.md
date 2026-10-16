# CCTV 直播 · Flutter 手机版

把 [suiyuanmingjing/cctv-native](https://github.com/suiyuanmingjing/cctv-native) 的 Android 原生
WebView 封装改写为 Flutter 手机版：继续用央视网官方直播页播放，但控制层完全由 Flutter 实现，
并针对手机触摸操作补齐了常见播放器功能。

- **只依赖系统 Chrome 内核**：使用 Android System WebView / Chrome，不内置 GeckoView。
- **竖屏观看 + 频道列表**：上方 16:9 直播，下方 18 个频道；固定竖屏，不随手机旋转；全屏只由按钮手动进入。
- **自动播放 / 点击隐藏**：打开频道自动播放，只有用户主动暂停才停；控件显示时点画面空白处立即隐藏。
- **画面锁定**：直播画面放在独立固定舞台层，滑动只调音量/亮度，不会拖动或缩放画面；全屏支持“适应 / 铺满”切换。
- **最低 Android 9（API 28）**，`compileSdk / targetSdk 36`。
- **18 个 CCTV 频道**，频道数据与原项目保持一致。
- **不解析、不代理、不保存**任何视频内容，只打开央视网公开直播页。

## 功能

| 分类 | 功能 |
| --- | --- |
| 频道 | 18 个 CCTV 频道网格、上次观看高亮、记住上次频道 |
| 播放 | 播放 / 暂停、双击播放暂停、点击显示 / 隐藏控制栏 |
| 声音 | 静音 / 取消静音、系统媒体音量滑杆、上下滑屏幕右侧调音量 |
| 画面 | 上下滑屏幕左侧调亮度、亮度滑杆、全屏 / 退出全屏、自动横屏全屏 |
| 频道切换 | 右侧频道抽屉、上一个 / 下一个频道、左滑打开频道列表 |
| 状态 | 加载进度、缓冲动画、直播中 / 已暂停、已观看时长、分辨率标记 |
| 异常 | 网络错误 / 节目不可用提示、重试、切换频道、在浏览器中打开 |
| 体验 | 保持屏幕常亮、音频焦点（来电 / 其他应用播放时自动暂停）、沉浸式全屏 |
| 内核 | 启动时读取系统 WebView 版本，低于 88 时提示更新 |

## 与 Android 原版的区别

| 项目 | 原版 | 本 Flutter 版 |
| --- | --- | --- |
| UI | Android View / Material | Flutter Material 3，手机优先布局 |
| 播放内核 | WebView 或 GeckoView 两个变体 | 只保留系统 Chrome / WebView |
| 全屏 | 网页 `requestFullscreen` + `onShowCustomView` | Flutter 横屏 + 沉浸式系统栏 + 注入 CSS 舞台化 |
| 控制栏 | 网页自带 | Flutter 原生控制层 |
| 手势 | 上下滑切台、左滑开列表 | 左滑开列表、左侧上下滑亮度、右侧上下滑音量、双击播放暂停 |
| 最低系统 | Android 5.0 | Android 9（API 28） |

> 说明：本版不再调用网页的 HTML5 全屏。注入脚本会把 `#player` 固定到整个窗口、隐藏网页
> 其它元素，再由 Flutter 负责横屏和系统栏，因此控制层始终可用，也不会出现"全屏后网页控件
> 盖住原生按钮"的问题。

## 环境要求

| 项目 | 要求 |
| --- | --- |
| Flutter | 3.47.x（Dart 3.13） |
| JDK | 17 或更高（本机使用 JDK 21） |
| Android SDK | Platform 36、Build-Tools 36.0.0 |
| 设备 | Android 9+，系统 Chrome / Android System WebView 主版本建议 ≥ 88 |

## 构建

```bash
cd cctv_flutter

# 国内网络建议设置 pub 镜像
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

产物：

```text
build/app/outputs/flutter-apk/app-release.apk
```

安装：

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

> `dist/` 下的 APK 已经用 `../signing/suiyuanmingjing.jks`（别名 `suiyuanmingjing`）重新签名。
> 直接运行 `flutter build apk` 生成的是 debug 签名；重新构建后请用下面的命令重签：
>
> ```bash
> zipalign -f -p 4 app-release.apk app-release-aligned.apk
> apksigner sign \
>   --ks ../signing/suiyuanmingjing.jks \
>   --ks-key-alias suiyuanmingjing \
>   --ks-pass pass:Suiyuanmingjing@2026 \
>   --key-pass pass:Suiyuanmingjing@2026 \
>   --out app-release-signed.apk app-release-aligned.apk
> ```
>
> 之前安装过 debug 签名版本的手机，需要先卸载旧版再安装。


### 构建镜像说明

- `android/gradle/wrapper/gradle-wrapper.properties` 已指向腾讯云 Gradle 镜像，国内下载更稳；如在海外可改回
  `https://services.gradle.org/distributions/gradle-9.3.1-all.zip`。
- `android/settings.gradle.kts` / `android/build.gradle.kts` 已优先使用阿里云 Maven 镜像，官方仓库兜底。
- `android/gradle.properties` 中设置了 `kotlin.incremental=false`。原因是本机 pub cache 在 C: 盘、项目在 E: 盘，
  Kotlin 增量缓存跨盘符会报 `different roots`；关闭增量编译可以稳定构建（只影响编译速度）。
- `flutter build apk --release` 生成的是**通用 APK**，包含 `arm64-v8a`、`armeabi-v7a` 两个 ABI，约 39.7 MB。
  如果只需要主流 64 位手机，可以执行：

  ```bash
  flutter build apk --release --split-per-abi
  # 产物：build/app/outputs/flutter-apk/app-arm64-v8a-release.apk（约 26 MB）
  ```

## 产物

| 文件 | 适用设备 | 大小 |
| --- | --- | --- |
| `dist/cctv-live-1.0.0-universal.apk` | 所有 Android 9+（含 arm64 / armv7） | 39.7 MB |
| `dist/cctv-live-1.0.0-arm64-v8a.apk` | 主流 64 位手机，推荐 | 26.0 MB |
| `dist/cctv-live-1.0.0-armeabi-v7a.apk` | 32 位老设备 | 23.5 MB |
| [`../cctv_tv_flutter/dist/cctv-tv-1.0.0-flutter-gecko-universal.apk`](../cctv_tv_flutter/dist/cctv-tv-1.0.0-flutter-gecko-universal.apk) | **电视 / TV 盒子（Flutter UI + GeckoView，无 WebView）** | 147.6 MB |

安装示例：

```bash
adb install -r dist/cctv-live-1.0.0-arm64-v8a.apk
```

## 电视版（GeckoView，不使用 WebView）

电视端 Flutter 产物在 [`../cctv_tv_flutter`](../cctv_tv_flutter)：

- 包名 `com.cctv.tv`，版本 `1.0.0`
- **Flutter 电视 UI + 内置 GeckoView 平台视图**，不使用系统 WebView
- 支持 Android 7+、遥控器 D-pad、频道网格、播放页上下换台、左键频道列表
- 签名 `CN=suiyuanmingjing`
- APK：[`cctv-tv-1.0.0-flutter-gecko-universal.apk`](../cctv_tv_flutter/dist/cctv-tv-1.0.0-flutter-gecko-universal.apk)（147.6 MB）

原项目的原生 GeckoView TV 版仍保留在 [`../cctv_tv`](../cctv_tv) 作为备用。详细说明见
[`../cctv_tv_flutter/README.md`](../cctv_tv_flutter/README.md)。
## 项目结构

```text
cctv_flutter/
├── assets/
│   ├── channel-list.json          # 18 个频道（与原项目相同）
│   └── js/cctv_native.js          # 注入官网的舞台化 / 播放 / 手势脚本
├── lib/
│   ├── main.dart                  # 入口、edge-to-edge
│   ├── app.dart                   # MaterialApp、中文本地化
│   ├── core/
│   │   ├── app_colors.dart        # 暖褐主页 + CCTV 红
│   │   ├── theme.dart             # 深色播放器主题
│   │   ├── formatters.dart        # 时长 / 版本号
│   │   ├── native_system.dart     # 音量、亮度、常亮、内核、音频焦点
│   │   └── preferences.dart       # 上次频道 / 自动全屏 / 常亮
│   ├── models/
│   │   ├── channel.dart           # 频道模型与 JSON 解析
│   │   └── video_state.dart       # 注入脚本上报的 <video> 状态
│   ├── data/channel_repository.dart
│   ├── screens/
│   │   ├── home_screen.dart       # 频道网格
│   │   └── player_screen.dart     # 播放页与控制层
│   └── widgets/
│       ├── channel_card.dart
│       ├── channel_panel.dart
│       └── settings_sheet.dart
├── android/
│   └── app/src/main/kotlin/com/cctv/cctv_flutter/MainActivity.kt
└── test/channel_test.dart
```

## 播放器操作

| 操作 | 效果 |
| --- | --- |
| 点击画面 | 显示 / 隐藏控制栏 |
| 双击画面 | 播放 / 暂停 |
| 屏幕左侧上下滑 | 调亮度 |
| 屏幕右侧上下滑 | 调音量 |
| 从左向右滑 | 打开频道列表 |
| 底部滑杆 | 音量 / 亮度 |
| 底部按钮 | 上一个 / 下一个频道、频道列表、重试、全屏 |
| 系统返回 | 优先关闭频道列表 / 退出全屏，再返回主页 |

## 频道列表

频道放在 `assets/channel-list.json`，字段与原项目一致：

| 字段 | 作用 |
| --- | --- |
| `id` | 内部编号，不要重复 |
| `number` | 排序 |
| `label` | 卡片上行小字，如 `CCTV-5+` |
| `title` | 卡片下行大字，如 `体育赛事` |
| `webKey` | 官网地址里的 slug |
| `webUrl` | 官网直播页地址 |

注意 CCTV-9 和 CCTV-14 的 slug 与 id 不同：

| 频道 | 官网地址 |
| --- | --- |
| CCTV-9 纪录 | `https://tv.cctv.com/live/cctvjilu/` |
| CCTV-14 少儿 | `https://tv.cctv.com/live/cctvchild/` |

修改 `channel-list.json` 后重新 `flutter build apk` 即可，无需改 Dart 代码。

## 实现要点

1. **PC 页面 + 桌面 UA**：央视网手机页会跳回 PC 页，因此继续使用原项目的桌面 Chrome UA。
2. **舞台化 CSS**：注入脚本把 `#player` 设为 `position: fixed; inset: 0`，隐藏网页其它节点和
   播放器自带控件，`<video>` 使用 `object-fit: contain` 完整显示画面。
3. **状态上报**：脚本每 500ms 通过 `CctvEvents` JavaScriptChannel 上报播放 / 缓冲 / 错误 /
   分辨率 / 已观看时长；Flutter 据此驱动控制层。
4. **网页内手势**：在 `touchstart/move/end` 的捕获阶段处理点击、双击、上下滑、左滑，并阻止
   官网播放器收到同一次触摸，避免"点一下既显示控制栏又暂停"。
5. **原生能力**：Kotlin 侧通过 MethodChannel 提供系统媒体音量、窗口亮度、屏幕常亮、
   外部浏览器、音频焦点；WebView 版本用 `WebViewCompat.getCurrentWebViewPackage()` 读取。


## 验证

本次交付已完成：

- `flutter analyze --no-pub`：No issues found
- `flutter test --no-pub`：9 个测试全部通过（频道解析、特殊 slug、地址校验、时长 / 版本格式化、
  VideoState 解析、主页手机尺寸渲染）
- 在 Chromium（Edge）中加载真实的 `https://tv.cctv.com/live/cctv13/` 并注入 `cctv_native.js`，验证：
  - `<video>` 找到并进入 `readyState=4` 播放
  - 舞台 CSS 让画面铺满 390×844 / 844×390 视口，网页导航和播放器自带控件被隐藏
  - `pause()` / `play()` / `setMuted()` / 状态上报正常
  - 单击、双击、上下滑手势能通过 `CctvEvents` 上报
- APK 静态检查：`minSdkVersion=28`、`targetSdkVersion=36`、包名 `com.cctv.live`、INTERNET 权限、
  两个资源文件（`channel-list.json`、`cctv_native.js`）均已打包。
- 手机与电视 APK 均已用 `suiyuanmingjing` 密钥签名（`apksigner verify` 显示
  `CN=suiyuanmingjing`）。
- 电视端 `assembleGeckoRelease` 构建成功；APK 含 `LEANBACK_LAUNCHER`、GeckoView 的
  `libxul.so` 等内核库，包名 `com.cctv.fullscreen.gecko`，minSdk 21。

> 构建机没有可用的硬件加速 Android 模拟器（未安装 Hypervisor 驱动），因此没有做模拟器真机截图；
> 建议在 Android 9+ 真机上安装 `dist/cctv-live-1.0.0-universal.apk` 做最终播放验证。

## 已知限制

- 播放依赖央视网页面结构和 DRM/Widevine 支持；如果官网改版、频道下线或节目时段不可用，
  页面会显示对应提示，App 提供"在浏览器打开"作为兜底。
- 系统 WebView 过旧（< 88）可能无法播放或无法执行注入脚本，需要在应用商店更新
  「Android System WebView」或「Chrome」。
- 本项目只适配 Android；没有 iOS / 桌面端。
- 直播没有可拖动的进度条；底部红色横条表示"直播中"，并显示本次已观看时长。

## 免责声明

本应用只打开央视网（tv.cctv.com）的公开直播页面，不解析、不代理、不保存任何视频内容。
频道地址取自央视网公开导航。请遵守央视网的使用条款，仅用于个人学习与观看。

## 致谢

- 原项目：[suiyuanmingjing/cctv-native](https://github.com/suiyuanmingjing/cctv-native)
- 播放页面与频道数据来自央视网。
