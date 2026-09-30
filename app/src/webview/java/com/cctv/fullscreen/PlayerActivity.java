package com.cctv.fullscreen;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.KeyEvent;
import android.view.Menu;
import android.view.MenuItem;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.view.GravityCompat;
import androidx.drawerlayout.widget.DrawerLayout;
import androidx.webkit.WebViewCompat;

import com.google.android.material.navigation.NavigationView;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.Collections;
import java.util.List;

/**
 * 播放页：全屏 WebView + 暗色遮蔽层 + 上下滑动切台。
 *
 * <p>手势：竖直滑动切台；从左向右滑动打开频道列表；返回键或点空白区关闭列表。</p>
 *
 * <p>全屏时机：不再"页面 load 完就点全屏"，而是等注入脚本上报
 * {@code video-ready}（分片已能解码）。等待时长由当前网络类型决定，
 * 拿不到网络信息时固定等 5 秒；另有 15 秒硬上限兜底。</p>
 */
public final class PlayerActivity extends AppCompatActivity {

    public static final String EXTRA_CHANNEL_ID = "channel_id";

    private static final String TAG = "CCTVHigh";
    private static final String SCRIPT_ASSET = "auto_fullscreen.js";

    private static final String DESKTOP_USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                    + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

    /** 竖直滑动切台阈值。 */
    private static final int SWIPE_THRESHOLD_DP = 80;
    /** 从左向右滑动打开频道列表的阈值。 */
    private static final int SWIPE_OPEN_DP = 60;
    private static final int FADE_MS = 260;
    /** 硬下限：无论网络状态如何，自动全屏都不会早于这个时间。 */
    private static final long HARD_MIN_DELAY_MS = 3000L;
    /** 能拿到网络状态时的等待。 */
    private static final long MIN_DELAY_MS = 3000L;
    /** 取不到网络状态时的等待。 */
    private static final long FALLBACK_DELAY_MS = 5000L;
    /** 等不到 video-ready 的硬上限。 */
    private static final long READY_HARD_CAP_MS = 6000L;
    /** 尝试全屏后仍不成功的话，最多再遮多久。 */
    private static final long OVERLAY_GIVE_UP_MS = 5000L;

    private final Handler ui = new Handler(Looper.getMainLooper());

    private DrawerLayout drawerLayout;
    private NavigationView navigationView;
    private WebView webView;
    private View overlay;
    private TextView overlayStatus;

    private View customView;
    private FrameLayout fullscreenContainer;
    private WebChromeClient.CustomViewCallback customViewCallback;

    private List<Channel> channels = Collections.emptyList();
    private int index;
    private String script = "";
    private boolean documentStartInstalled;

    private long loadStartedAt;
    private boolean delayElapsed;
    private boolean videoReady;
    private boolean hardCapReached;

    private final Runnable onRevealDelay = () -> {
        delayElapsed = true;
        maybeReveal();
    };
    private final Runnable onHardCap = () -> {
        hardCapReached = true;
        Log.w(TAG, "等待 video-ready 超时，仍然尝试全屏");
        attemptFullscreen();
    };
    /** 硬下限到点后正式请求全屏。 */
    private final Runnable onHardFloor = this::attemptFullscreen;
    /** 全屏迟迟不成功时，撤掉遮蔽层让用户至少能看到画面。 */
    private final Runnable onOverlayGiveUp = () -> {
        Log.w(TAG, "全屏未成功，撤掉遮蔽层");
        hideOverlay();
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        SystemUi.hideBars(this);
        setContentView(R.layout.activity_player);

        channels = ChannelRepository.load(this);
        String id = getIntent().getStringExtra(EXTRA_CHANNEL_ID);
        if (id == null) {
            id = AppPreferences.lastChannelId(this);
        }
        index = ChannelRepository.indexOfId(channels, id);
        script = readAsset(SCRIPT_ASSET);

        drawerLayout = findViewById(R.id.drawer_layout);
        navigationView = findViewById(R.id.nav_view);
        webView = findViewById(R.id.webview);
        overlay = findViewById(R.id.loading_overlay);
        overlayStatus = findViewById(R.id.overlay_status);

        buildChannelMenu();
        navigationView.setNavigationItemSelectedListener(
                new NavigationView.OnNavigationItemSelectedListener() {
                    @Override
                    public boolean onNavigationItemSelected(@NonNull MenuItem item) {
                        selectChannel(item.getItemId());
                        return true;
                    }
                });

        configureWebView();
        showOverlay();
        loadCurrent();
    }

    /* ------------------- 脚本注入：所有框架 + 文档开始 ------------------- */

    private String configPrefix() {
        return "window.__CCTV_FS_CONFIG__ = {deadlineMs: 60000, intervalMs: 500};\n";
    }

    private void installDocumentStartScript() {
        if (script == null || script.isEmpty()) {
            return;
        }
        try {
            WebViewCompat.addDocumentStartJavaScript(
                    webView, configPrefix() + script, Collections.singleton("*"));
            documentStartInstalled = true;
            Log.i(TAG, "document-start 注入已安装（所有框架）");
        } catch (Throwable t) {
            Log.w(TAG, "document-start 注入不可用，退回主框架注入", t);
        }
    }

    private void inject(WebView view) {
        if (documentStartInstalled || script == null || script.isEmpty()) {
            return;
        }
        view.evaluateJavascript(configPrefix() + script, null);
    }

    /* ------------------- 网络探测：决定等多久 ------------------- */

    /** @return 进入全屏前的等待毫秒数；拿不到网络信息时 5000ms。 */
    @SuppressWarnings("deprecation")
    private long networkDelayMs() {
        try {
            ConnectivityManager cm = (ConnectivityManager)
                    getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm == null) {
                Log.i(TAG, "取不到网络状态，等待 " + FALLBACK_DELAY_MS + "ms");
                return Math.max(FALLBACK_DELAY_MS, HARD_MIN_DELAY_MS);
            }
            NetworkInfo info = cm.getActiveNetworkInfo();
            if (info == null || !info.isConnected()) {
                Log.i(TAG, "取不到网络状态/未连接，等待 " + FALLBACK_DELAY_MS + "ms");
                return Math.max(FALLBACK_DELAY_MS, HARD_MIN_DELAY_MS);
            }
            Log.i(TAG, "网络状态正常（type=" + info.getType() + "），等待 "
                    + MIN_DELAY_MS + "ms");
            return Math.max(MIN_DELAY_MS, HARD_MIN_DELAY_MS);
        } catch (Throwable t) {
            Log.w(TAG, "读取网络状态失败，等待 " + FALLBACK_DELAY_MS + "ms", t);
            return Math.max(FALLBACK_DELAY_MS, HARD_MIN_DELAY_MS);
        }
    }

    /** 每次加载/切台时重置等待窗口。 */
    private void beginLoad() {
        loadStartedAt = SystemClock.elapsedRealtime();
        videoReady = false;
        delayElapsed = false;
        hardCapReached = false;
        ui.removeCallbacks(onRevealDelay);
        ui.removeCallbacks(onHardCap);
        ui.removeCallbacks(onOverlayGiveUp);
        long delay = networkDelayMs();
        ui.postDelayed(onRevealDelay, delay);
        ui.postDelayed(onHardCap, delay + READY_HARD_CAP_MS);
    }

    /**
     * 等待时间到了 **且** 直播画面已经出来（或硬超时）：由 App 主动全屏。
     *
     * <p>遮蔽层此时**不**撤：它的职责就是"把全屏这件事做完"。全屏成功、
     * 或者尝试 OVERLAY_GIVE_UP_MS 仍未成功，才把它收掉。</p>
     */
    private void maybeReveal() {
        if (!delayElapsed) {
            return;
        }
        if (!videoReady && !hardCapReached) {
            return;
        }
        attemptFullscreen();
    }

    private void attemptFullscreen() {
        // 硬下限：即使有其他路径（video-ready 提前、硬上限、按键）触发，
        // 也绝不早于 HARD_MIN_DELAY_MS 请求全屏。
        long elapsed = SystemClock.elapsedRealtime() - loadStartedAt;
        if (elapsed < HARD_MIN_DELAY_MS) {
            long remain = HARD_MIN_DELAY_MS - elapsed;
            Log.i(TAG, "距加载仅 " + elapsed + "ms，再等 " + remain + "ms 才请求全屏");
            ui.removeCallbacks(onHardFloor);
            ui.postDelayed(onHardFloor, remain);
            return;
        }
        // 双管齐下：
        //  1) 往 WebView 里合成一次真实触摸 —— 页面拿到"用户激活"，
        //     注入脚本据此调用 requestFullscreen，**不需要用户动手**；
        //  2) 同时直接调一次脚本的 kick() 兜底。
        synthesizeCenterTap();
        kickFullscreen();
        ui.removeCallbacks(onOverlayGiveUp);
        ui.postDelayed(onOverlayGiveUp, OVERLAY_GIVE_UP_MS);
    }

    /**
     * 在 WebView 正中合成一次按下+抬起。
     *
     * <p>Chromium 要求 requestFullscreen 处于"用户激活"上下文，从 native 直接
     * evaluateJavascript 调过去是不带激活的、必被拒。把触摸事件派发进 WebView
     * 的输入链路，页面就把它当作一次真实手势。</p>
     */
    private void synthesizeCenterTap() {
        int w = webView.getWidth();
        int h = webView.getHeight();
        if (w <= 0 || h <= 0) {
            Log.w(TAG, "WebView 尺寸为 0，跳过合成点击");
            return;
        }
        long now = SystemClock.uptimeMillis();
        float x = w / 2f;
        float y = h / 2f;
        MotionEvent down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, x, y, 0);
        MotionEvent up = MotionEvent.obtain(now, now + 60, MotionEvent.ACTION_UP, x, y, 0);
        try {
            webView.dispatchTouchEvent(down);
            webView.dispatchTouchEvent(up);
            Log.i(TAG, "已向 WebView 中心合成一次触摸，用于触发全屏");
        } catch (Throwable t) {
            Log.w(TAG, "合成触摸失败", t);
        } finally {
            down.recycle();
            up.recycle();
        }
    }

    /* ----------------------------- WebView ----------------------------- */

    @SuppressWarnings("SetJavaScriptEnabled")
    private void configureWebView() {
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setUserAgentString(DESKTOP_USER_AGENT);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        settings.setSupportMultipleWindows(false);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);

        webView.setBackgroundColor(0xFF000000);
        webView.addJavascriptInterface(new Bridge(), "CCTVNative");
        webView.setOnTouchListener(new SwipeToSwitchListener());

        installDocumentStartScript();

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                inject(view);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                inject(view);
                // 不再用固定延时揭幕：交给 beginLoad() 的等待窗口 + video-ready。
            }
        });

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onShowCustomView(View view, CustomViewCallback callback) {
                showCustomView(view, callback);
            }

            @Override
            public void onShowCustomView(View view, int requestedOrientation,
                                         CustomViewCallback callback) {
                showCustomView(view, callback);
            }

            @Override
            public void onHideCustomView() {
                hideCustomView();
            }
        });
    }

    /* ------------------------- 暗色遮蔽层（渐入渐出） ------------------------- */

    private void showOverlay() {
        overlay.setVisibility(View.VISIBLE);
        overlay.setAlpha(0f);
        overlay.bringToFront();
        overlay.animate().alpha(1f).setDuration(FADE_MS).start();
    }

    private void hideOverlay() {
        ui.removeCallbacks(onOverlayGiveUp);
        if (overlay.getVisibility() != View.VISIBLE) {
            return;
        }
        overlay.animate().alpha(0f).setDuration(FADE_MS).withEndAction(() -> {
            overlay.setVisibility(View.GONE);
            }).start();
    }

    /* ------------------------- Material 侧边栏 ------------------------- */

    private void buildChannelMenu() {
        Menu menu = navigationView.getMenu();
        menu.clear();
        menu.setGroupCheckable(Menu.NONE, true, true);
        for (int i = 0; i < channels.size(); i++) {
            Channel channel = channels.get(i);
            MenuItem item = menu.add(Menu.NONE, i, i, channel.label + "    " + channel.title);
            item.setCheckable(true);
            item.setChecked(i == index);
        }
        navigationView.setCheckedItem(index);
    }

    private void openDrawer() {
        if (!channels.isEmpty()) {
            drawerLayout.openDrawer(GravityCompat.START);
        }
    }

    private void closeDrawer() {
        if (drawerLayout.isDrawerVisible(GravityCompat.START)) {
            drawerLayout.closeDrawer(GravityCompat.START);
        }
    }

    private void selectChannel(int position) {
        if (position < 0 || position >= channels.size()) {
            closeDrawer();
            return;
        }
        boolean changed = position != index;
        index = position;
        navigationView.setCheckedItem(position);
        closeDrawer();
        if (changed) {
            switchChannelTo(position);
        }
    }

    private Channel current() {
        return channels.get(index);
    }

    private void loadCurrent() {
        if (channels.isEmpty()) {
            return;
        }
        AppPreferences.saveLastChannelId(this, current().id);
        beginLoad();
        webView.loadUrl(current().webUrl);
    }

    private void switchChannelTo(int position) {
        index = position;
        navigationView.setCheckedItem(index);
        // 全屏状态下切台：先退出全屏，再走正常的"遮蔽层 → 加载 → 全屏"
        if (customView != null) {
            hideCustomView();
        }
        showOverlay();
        loadCurrent();
    }

    private void switchChannel(int delta) {
        int count = channels.size();
        if (count == 0) {
            return;
        }
        switchChannelTo(((index + delta) % count + count) % count);
    }

    private void kickFullscreen() {
        webView.evaluateJavascript(
                "window.__CCTV_FS__ && window.__CCTV_FS__.kick();", null);
    }

    /* ------------------------------ 全屏 ------------------------------ */

    private void showCustomView(View view, WebChromeClient.CustomViewCallback callback) {
        if (customView != null) {
            callback.onCustomViewHidden();
            return;
        }
        closeDrawer();
        customView = view;
        customViewCallback = callback;

        fullscreenContainer = new FrameLayout(this);
        fullscreenContainer.setBackgroundColor(Color.BLACK);
        // 全屏期间手势不能失效：切台 / 左→右开列表都交给同一个监听器。
        fullscreenContainer.setOnTouchListener(new SwipeToSwitchListener());
        view.setLayoutParams(new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT));
        fullscreenContainer.addView(view);

        // 关键：放进 webview_container（DrawerLayout 的**内容区**），
        // 而不是 android.R.id.content。放到 content 会让全屏画面盖在
        // DrawerLayout 之上，抽屉和手势就全被压住、完全用不了。
        FrameLayout container = findViewById(R.id.webview_container);
        container.addView(fullscreenContainer, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT));
        webView.setVisibility(View.GONE);
        hideOverlay();
        SystemUi.hideBars(this);
    }

    private void hideCustomView() {
        if (customView == null) {
            return;
        }
        FrameLayout container = findViewById(R.id.webview_container);
        if (fullscreenContainer != null) {
            fullscreenContainer.removeAllViews();
            container.removeView(fullscreenContainer);
            fullscreenContainer = null;
        }
        customView = null;
        webView.setVisibility(View.VISIBLE);
        if (customViewCallback != null) {
            customViewCallback.onCustomViewHidden();
            customViewCallback = null;
        }
        SystemUi.hideBars(this);
    }

    @Override
    public void onConfigurationChanged(android.content.res.Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        SystemUi.hideBars(this);
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            SystemUi.hideBars(this);
        }
    }

    /* ---------------------------- 上下滑动切台 ---------------------------- */

    private final class SwipeToSwitchListener implements View.OnTouchListener {

        private float downX;
        private float downY;
        private boolean consumed;

        @Override
        public boolean onTouch(View v, MotionEvent event) {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downX = event.getX();
                    downY = event.getY();
                    consumed = false;
                    return false;
                case MotionEvent.ACTION_MOVE:
                    if (consumed) {
                        return true;
                    }
                    float dy = event.getY() - downY;
                    float dx = event.getX() - downX;
                    float density = getResources().getDisplayMetrics().density;
                    int vThreshold = (int) (SWIPE_THRESHOLD_DP * density);

                    // 竖直滑动：上滑下一个台、下滑上一个台
                    if (Math.abs(dy) > vThreshold && Math.abs(dy) > Math.abs(dx) * 1.5f) {
                        consumed = true;
                        switchChannel(dy < 0 ? 1 : -1);
                        return true;
                    }
                    return false;
                case MotionEvent.ACTION_UP:
                    if (!consumed) {
                        float total = (float) Math.hypot(
                                event.getX() - downX, event.getY() - downY);
                        if (total < 20f) {
                            kickFullscreen();
                        }
                    }
                    return consumed;
                default:
                    return consumed;
            }
        }
    }

    /* ---------------------- 全局手势：左→右打开频道列表 ---------------------- */

    private float touchDownX;
    private float touchDownY;
    private boolean horizontalHandled;

    /**
     * 在 Activity 层拦截"从左向右滑"，因此**任何界面状态都生效**：
     * WebView、原生全屏画面、遮蔽层，都能触发打开频道列表。
     */
    @Override
    public boolean dispatchTouchEvent(MotionEvent ev) {
        if (drawerLayout != null && drawerLayout.isDrawerVisible(GravityCompat.START)) {
            // 列表已打开：交给 DrawerLayout 自己处理（滑动关闭 / 点空白关闭）
            return super.dispatchTouchEvent(ev);
        }
        switch (ev.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                touchDownX = ev.getX();
                touchDownY = ev.getY();
                horizontalHandled = false;
                break;
            case MotionEvent.ACTION_MOVE:
                if (!horizontalHandled) {
                    float dx = ev.getX() - touchDownX;
                    float dy = ev.getY() - touchDownY;
                    int threshold = (int) (SWIPE_OPEN_DP
                            * getResources().getDisplayMetrics().density);
                    if (dx > threshold && dx > Math.abs(dy) * 1.5f) {
                        horizontalHandled = true;
                        // 给下层视图一个 CANCEL，免得它以为手指还按着
                        MotionEvent cancel = MotionEvent.obtain(ev);
                        cancel.setAction(MotionEvent.ACTION_CANCEL);
                        super.dispatchTouchEvent(cancel);
                        cancel.recycle();
                        Log.i(TAG, "全局手势：左→右，打开频道列表");
                        openDrawer();
                        return true;
                    }
                }
                break;
            default:
                break;
        }
        return super.dispatchTouchEvent(ev);
    }

    /* ---------------------------- 遥控器按键 ---------------------------- */

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (event.getAction() != KeyEvent.ACTION_DOWN) {
            return super.dispatchKeyEvent(event);
        }
        int keyCode = event.getKeyCode();

        // 顺序很重要：列表优先于全屏判断。
        // 否则"全屏 + 列表开着"时会走到下面的 finish 分支，一按返回直接回主页。
        if (drawerLayout.isDrawerVisible(GravityCompat.START)) {
            if (keyCode == KeyEvent.KEYCODE_BACK
                    || keyCode == KeyEvent.KEYCODE_DPAD_LEFT
                    || keyCode == KeyEvent.KEYCODE_MENU) {
                closeDrawer();
                return true;
            }
            return super.dispatchKeyEvent(event);
        }

        if (customView != null) {
            if (keyCode == KeyEvent.KEYCODE_BACK) {
                // 列表没开时，一次返回直接回主页
                hideCustomView();
                finish();
                return true;
            }
            return super.dispatchKeyEvent(event);
        }

        switch (keyCode) {
            case KeyEvent.KEYCODE_DPAD_LEFT:
            case KeyEvent.KEYCODE_MENU:
                openDrawer();
                return true;
            case KeyEvent.KEYCODE_DPAD_UP:
            case KeyEvent.KEYCODE_CHANNEL_UP:
                switchChannel(-1);
                return true;
            case KeyEvent.KEYCODE_DPAD_DOWN:
            case KeyEvent.KEYCODE_CHANNEL_DOWN:
                switchChannel(1);
                return true;
            case KeyEvent.KEYCODE_DPAD_RIGHT:
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
                kickFullscreen();
                return true;
            default:
                return super.dispatchKeyEvent(event);
        }
    }

    @Override
    public void onBackPressed() {
        if (drawerLayout.isDrawerVisible(GravityCompat.START)) {
            closeDrawer();
            return;
        }
        if (customView != null) {
            hideCustomView();
        }
        // 一次返回直接回主页
        super.onBackPressed();
    }

    /* ---------------------------- 生命周期 ---------------------------- */

    @Override
    protected void onResume() {
        super.onResume();
        if (webView != null) {
            webView.onResume();
        }
    }

    @Override
    protected void onPause() {
        if (webView != null) {
            webView.onPause();
        }
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        ui.removeCallbacks(onRevealDelay);
        ui.removeCallbacks(onHardCap);
        if (webView != null) {
            webView.destroy();
        }
        super.onDestroy();
    }

    private String readAsset(String name) {
        BufferedReader reader = null;
        try {
            reader = new BufferedReader(
                    new InputStreamReader(getAssets().open(name), "UTF-8"));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line).append('\n');
            }
            return sb.toString();
        } catch (IOException e) {
            Log.e(TAG, "读取 " + name + " 失败", e);
            return "";
        } finally {
            if (reader != null) {
                try {
                    reader.close();
                } catch (IOException ignored) {
                }
            }
        }
    }

    /** 接收注入脚本上报的事件。 */
    private final class Bridge {

        @JavascriptInterface
        public void postMessage(final String message) {
            runOnUiThread(() -> {
                Log.i(TAG, "bridge: " + message);
                if (message.contains("fullscreen-entered")) {
                    // 只有"真的进全屏了"才撤遮蔽层；
                    // fullscreen-requested 只代表发出了请求，不采纳。
                    hideOverlay();
                } else if (message.contains("video-ready")) {
                    // 直播已加载出来，可以尝试全屏（但仍受最小等待时间约束）。
                    videoReady = true;
                    maybeReveal();
                }
            });
        }
    }
}
