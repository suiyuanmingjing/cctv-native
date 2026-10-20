# CCTV 直播

Flutter 手机版 + Flutter / GeckoView 电视版。应用直接打开央视网公开直播页播放，
不解析、不代理、不保存任何视频内容。

## 直接下载

所有安装包都在 GitHub Releases：

**https://github.com/suiyuanmingjing/cctv-native/releases/latest**

| 端 | 文件 | 适用设备 |
| --- | --- | --- |
| 手机（推荐） | `cctv-live-1.0.0-arm64-v8a.apk` | Android 9+，64 位手机 |
| 手机（通用） | `cctv-live-1.0.0-universal.apk` | Android 9+，含 arm64 / armv7 |
| 手机（32 位） | `cctv-live-1.0.0-armeabi-v7a.apk` | 老款 32 位手机 |
| 电视（推荐） | `cctv-tv-1.0.0-flutter-gecko-universal.apk` | Android 7+，Flutter UI + 内置 GeckoView |
| 电视（老系统兜底） | `cctv-tv-1.0-gecko-suiyuanmingjing.apk` | Android 5+，原生 GeckoView，无 WebView |

APK 体积较大（尤其电视版 147 MB），所以放在 Releases，不放进 git 仓库。

## 手机版怎么用

1. 安装 `cctv-live-1.0.0-arm64-v8a.apk`（或通用包）。
2. 打开后是 18 个频道，点频道卡片开始播放。
3. 竖屏布局：上方是直播画面，下方是频道列表，点列表可直接换台。
4. 播放控制：
   - 播放 / 暂停：画面中央按钮或底部控制条。
   - 音量 / 亮度：拖动滑杆，或在画面上左右两侧上下滑动。
   - 换台：底部上一个 / 下一个，或直接点下方频道。
   - 全屏：点全屏按钮；退出全屏或按返回会回到竖屏。
   - 画面适应 / 铺满：全屏时切换，适应会留黑边，铺满会裁切边缘。
   - 静音：点音量图标；自动播放不会保持静音。
5. 默认锁定竖屏，手机旋转不会自动切换；全屏只由按钮手动进入。
6. 打开频道会自动播放，只有你主动暂停才停。
7. 控件显示时，点画面空白处隐藏控件；再点一下重新显示。
8. 最低 Android 9（API 28）。

安装命令：

```bash
adb install -r cctv-live-1.0.0-arm64-v8a.apk
```

## 电视版怎么用

1. 优先安装 `cctv-tv-1.0.0-flutter-gecko-universal.apk`（Android 7+）。
2. 电视装不上或系统低于 Android 7，用 `cctv-tv-1.0-gecko-suiyuanmingjing.apk`（Android 5+）。
3. 遥控器操作：
   - 方向键：在频道网格中移动焦点。
   - 确定键：播放选中的频道。
   - 播放页上 / 下：切换上一个 / 下一个频道。
   - 播放页左键：打开频道列表。
   - 返回键：关闭列表 / 退出播放 / 回主页。
4. 电视版内置 GeckoView，不依赖电视盒子的系统 WebView。
5. 原 `cctv-native` 原生电视工程仍保留在 `app/`。

电视 APK 可通过 U 盘拷贝到电视安装，或在同局域网用文件管理器安装。

## 从源码构建

手机版：

```bash
cd flutter-phone
flutter pub get
flutter build apk --release --target-platform android-arm64
```

电视版：

```bash
cd flutter-tv
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64
```

原电视工程：

```bash
./gradlew assembleRelease
```

构建需要 Flutter 3.47+、Android SDK 36、JDK 21（原工程用 JDK 17）。

## 目录

```text
flutter-phone/   Flutter 手机版（系统 WebView）
flutter-tv/      Flutter 电视版（内置 GeckoView）
app/             原 cctv-native 原生电视工程
docs/            原工程文档
```

签名密钥不放进仓库；升级安装时请保持同一签名。

## 说明

- 频道和直播地址来自央视网 `tv.cctv.com`。
- 本应用只打开官网公开直播页，不解析、不代理、不保存视频内容。
- 电视盒子型号较多，个别设备的遥控器按键映射可能不同。

## 赞助

这个项目完全免费，也没有广告。如果它对你有点用，欢迎请我喝杯茶：

<img src="docs/afdian.jpg" alt="爱发电赞助码" width="320" />
