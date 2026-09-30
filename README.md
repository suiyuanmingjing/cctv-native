# CCTV 直播 · Android 原生版

打开即全屏播放 CCTV 官网直播的 Android 客户端。用系统 WebView 加载官网页面并注入脚本
自动全屏，**不做任何网页重绘**（不隐藏元素、不重排布局、不注入 UI）。

## 功能

- 主页频道网格，Material Design；横屏 4 列、竖屏 2 列，标题随列表滚动
- 选台 → 纯黑遮蔽层「正在加载」→ 加载完成后自动全屏
- 播放中**上下滑动切台**，**左→右滑动打开频道列表**
- 侧边栏选台；返回键一次回主页
- 电视遥控器支持；**没有悬浮按钮**，不遮挡画面
- 频道记忆（记住上次观看）

## 环境要求

| 项 | 版本 |
| --- | --- |
| JDK | 17+ |
| Android SDK | compileSdk 34、build-tools 34.0.0+ |
| Gradle | 8.9（仓库自带 wrapper） |
| minSdk / targetSdk | 21（Android 5.0）/ 34 |

## 构建

```bash
# 1) 指向本机 Android SDK
echo "sdk.dir=$ANDROID_HOME" > local.properties

# 2) 构建
./gradlew assembleDebug      # 装上即可测试
./gradlew assembleRelease    # 默认不签名，需自行签名后再分发
```

> 本仓库**不包含任何签名配置**，release 产物默认未签名。

## 项目结构

```
app/src/main/
├── AndroidManifest.xml
├── java/com/cctv/fullscreen/
│   ├── MainActivity.java        # 主页：频道网格，横竖屏自适应
│   ├── PlayerActivity.java      # 播放页：遮蔽层、全屏、手势、侧边栏
│   ├── ChannelAdapter.java      # 频道卡片适配器
│   ├── Channel.java             # 频道模型
│   ├── ChannelRepository.java   # 读取频道表
│   ├── AppPreferences.java      # 频道记忆
│   └── SystemUi.java            # 隐藏状态栏/导航栏
├── assets/
│   ├── auto_fullscreen.js       # 自动全屏注入脚本
│   └── channel-list.json        # 18 个频道
└── res/
    ├── layout/                  # activity_main / activity_player / item_channel
    ├── values/                  # colors / strings / themes
    ├── drawable*/               # 图标与背景
    └── mipmap-*/                # 各密度启动图标
```

## 频道数据

[`app/src/main/assets/channel-list.json`](app/src/main/assets/channel-list.json)，18 个频道：

| 字段 | 说明 |
| --- | --- |
| `id` | 稳定标识（也用于频道记忆） |
| `number` | 排序序号 |
| `label` | 卡片**上行小字**，如 `CCTV-5+` |
| `title` | 卡片**下行大字**，如 `体育赛事` |
| `name` | `label + title` |
| `webKey` | **官网真实 URL slug** |
| `webUrl` | `https://tv.cctv.com/live/{webKey}/` |

### ⚠️ webKey 不等于 id

| 频道 | 地址 |
| --- | --- |
| CCTV-9 纪录 | `https://tv.cctv.com/live/cctvjilu/` |
| CCTV-14 少儿 | `https://tv.cctv.com/live/cctvchild/` |

其余频道与 id 同名。**少儿频道没有 `cctv14` 这个地址**（实测 404），纪录频道
官网导航用的也是 `cctvjilu`。改频道表时务必用 `webKey`，不要用 id 拼 URL。

## 交互

| 操作 | 行为 |
| --- | --- |
| 主页点击 / 确认键 | 进入播放页 |
| 播放中上滑 / 下滑（或上下键） | 切台 |
| 播放中左→右滑（或左键 / 菜单键） | 打开频道列表 |
| 返回（列表开着） | 关列表，不退出播放 |
| 点列表外空白 | 关列表 |
| 返回 | 回主页 |

## 实现要点（踩坑记录）

代码注释里都标了原因，改之前建议先读这几处。

### 1. 必须伪装桌面 UA

Android UA 会让 tv.cctv.com 下发移动端页面，播放器可能根本不产出 `<video>`。
所以在 `PlayerActivity` 里固定成 Windows Chrome：

```java
settings.setUserAgentString(DESKTOP_USER_AGENT);
```

### 2. 注入脚本必须进"所有框架"

原生 `evaluateJavascript` **只能进主框架**。官网播放器一旦在 iframe 里，脚本就够不着，
表现为"怎么都不进全屏"。正解是 `androidx.webkit`：

```java
WebViewCompat.addDocumentStartJavaScript(webView, script, Collections.singleton("*"));
```

`"*"` 会注入到包括跨域 iframe 在内的所有框架，且在页面脚本之前执行。

### 3. 全屏必须由原生"合成触摸"触发

Chromium 要求 `requestFullscreen()` 处于**用户激活**上下文。从 native 直接
`evaluateJavascript` 调过去不带激活，**必然被拒**。所以由 App 主动往 WebView 的输入
链路里派发一次触摸：

```java
MotionEvent down = MotionEvent.obtain(now, now,      ACTION_DOWN, centerX, centerY, 0);
MotionEvent up   = MotionEvent.obtain(now, now + 60, ACTION_UP,   centerX, centerY, 0);
webView.dispatchTouchEvent(down);
webView.dispatchTouchEvent(up);
```

同时脚本在捕获阶段**吞掉**这次手势（`stopPropagation` + `preventDefault`），否则官网
播放器会把它当成"播放/暂停"，出现"全屏之后又暂停"。

### 4. 遮蔽层的关闭依据是"直播加载完成"，不是"全屏成功"

自动全屏可能失败，若非要等全屏才关遮蔽层，它就会一直挂着。正确时机：

- 等待时间：能取到网络状态 → **最少 3 秒**；取不到 → **5 秒**
- 且注入脚本上报 `video-ready`（`readyState >= 2`，即真的能解码）
- 等不到 `video-ready` 有 6 秒硬上限
- 直播出来后**自动撤遮蔽层**，然后再尝试全屏
- 全屏成功、或尝试后 5 秒仍未成功 → 也撤掉

### 5. 全屏画面必须挂在**内容区**

`onShowCustomView` 给的全屏 view 要加到 `webview_container`（DrawerLayout 的内容区），
**不能加到 `android.R.id.content`** —— 加到后者会让全屏画面盖在 DrawerLayout 之上，
侧边栏和手势就全被压住、完全用不了。

### 6. 返回键判断顺序：列表优先于全屏

`dispatchKeyEvent` 里必须先判"抽屉是否可见"，再判"是否在全屏"。顺序反了的话，
全屏时开着列表按返回会走到 `finish()` 分支，直接回主页。

另外用 `isDrawerVisible` 而不是 `isDrawerOpen` —— 后者在抽屉**动画过程中**返回 false，
会让"刚滑开一半按返回"误退到主页。

### 7. 手势放在 Activity 层

竖直切台、横向开列表都通过 `dispatchTouchEvent` 在 Activity 层拦截，这样 WebView、
原生全屏画面、遮蔽层任何状态下都生效（挂在 WebView 上的话，全屏时 WebView 被隐藏就失效）。

## 已知限制

- **自动全屏依赖合成触摸被认可为用户手势**。多数设备可行，个别 ROM 会判定为非可信
  输入，此时界面会出现"点一下屏幕中间"的补全屏路径。
- 官网改版可能让 `auto_fullscreen.js` 的选择器失效（脚本里的兜底最多重试 60 秒）。
- 仅在侧载场景验证过，未做上架相关适配。

## 声明

本客户端仅加载 CCTV 官网公开的直播页面，**不解析、不代理、不转存**任何流媒体内容。
频道地址来自官网自身导航。
