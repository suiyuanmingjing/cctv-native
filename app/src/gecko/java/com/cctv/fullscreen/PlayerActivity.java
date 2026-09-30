package com.cctv.fullscreen;

import android.content.Context;
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
import android.view.WindowManager;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.view.GravityCompat;
import androidx.drawerlayout.widget.DrawerLayout;

import com.google.android.material.navigation.NavigationView;

import org.mozilla.geckoview.GeckoResult;
import org.mozilla.geckoview.GeckoRuntime;
import org.mozilla.geckoview.GeckoRuntimeSettings;
import org.mozilla.geckoview.GeckoSession;
import org.mozilla.geckoview.GeckoView;

import java.util.Collections;
import java.util.List;

/**
 * 播放页（内置 GeckoView 内核）。
 *
 * <p>GeckoView 没有"执行 JS"的公开接口，页面注入只能走 <b>WebExtension 内容脚本</b>：
 * assets/geckoview/manifest.json 把共用的 auto_fullscreen.js 作为 content script
 * 在 document_start 注入所有框架。</p>
 *
 * <p>全屏由 Gecko 的 {@code ContentDelegate.onFullScreen(session, true)} 回调告知；
 * 触发全屏靠往 GeckoView 里合成触摸，让页面拿到用户激活。</p>
 */
public final class PlayerActivity extends AppCompatActivity {

    public static final String EXTRA_CHANNEL_ID = "channel_id";

    private static final String TAG = "CCTVHigh";
    private static final String EXT_LOCATION = "resource://android/assets/geckoview/";
    private static final String EXT_ID = "cctv-fullscreen@local";

    private static final String DESKTOP_USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                    + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

    private static final int SWIPE_THRESHOLD_DP = 80;
    private static final int SWIPE_OPEN_DP = 60;
    private static final int FADE_MS = 260;

    private static final long HARD_MIN_DELAY_MS = 3000L;
    private static final long FALLBACK_DELAY_MS = 5000L;
    private static final long TAP_INTERVAL_MS = 1500L;
    private static final int MAX_TAPS = 12;

    private static GeckoRuntime sRuntime;

    private final Handler ui = new Handler(Looper.getMainLooper());

    private DrawerLayout drawerLayout;
    private NavigationView navigationView;
    private GeckoView geckoView;
    private GeckoSession session;
    private View overlay;

    private List<Channel> channels = Collections.emptyList();
    private int index;

    private boolean inFullScreen;
    private int taps;

    private float touchDownX;
    private float touchDownY;
    private boolean horizontalHandled;

    /** 反复合成触摸，直到 Gecko 报告进入全屏。 */
    private final Runnable tapLoop = new Runnable() {
        @Override
        public void run() {
            if (isFinishing() || inFullScreen) {
                return;
            }
            if (taps >= MAX_TAPS) {
                Log.w(TAG, "多次尝试仍未进全屏，撤掉遮蔽层");
                hideOverlay();
                return;
            }
            taps++;
            synthesizeCenterTap();
            ui.postDelayed(this, TAP_INTERVAL_MS);
        }
    };

    private final Runnable onOverlayGiveUp = this::hideOverlay;

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

        drawerLayout = findViewById(R.id.drawer_layout);
        navigationView = findViewById(R.id.nav_view);
        geckoView = findViewById(R.id.geckoview);
        overlay = findViewById(R.id.loading_overlay);

        buildChannelMenu();
        navigationView.setNavigationItemSelectedListener(
                new NavigationView.OnNavigationItemSelectedListener() {
                    @Override
                    public boolean onNavigationItemSelected(@NonNull MenuItem item) {
                        selectChannel(item.getItemId());
                        return true;
                    }
                });

        configureGecko();
        showOverlay();
        // 等内容脚本扩展装好再加载页面，保证第一页就注入到
        ensureExtensionThen(this::loadCurrent);
    }

    /* ------------------------------ GeckoView ------------------------------ */

    private GeckoRuntime runtime() {
        if (sRuntime == null) {
            GeckoRuntimeSettings settings = new GeckoRuntimeSettings.Builder()
                    .javaScriptEnabled(true)
                    .build();
            sRuntime = GeckoRuntime.create(getApplicationContext(), settings);
        }
        return sRuntime;
    }

    private void ensureExtensionThen(Runnable action) {
        runtime().getWebExtensionController()
                .ensureBuiltIn(EXT_LOCATION, EXT_ID)
                .accept(ext -> {
                    Log.i(TAG, "内容脚本扩展就绪: " + (ext == null ? "?" : ext.id));
                    runOnUiThread(action);
                });
    }

    private void configureGecko() {
        session = new GeckoSession();
        session.getSettings().setUserAgentOverride(DESKTOP_USER_AGENT);
        session.open(runtime());
        geckoView.setSession(session);
        geckoView.setOnTouchListener(new SwipeListener());

        // 允许自动播放
        session.setPermissionDelegate(new GeckoSession.PermissionDelegate() {
            @Override
            public GeckoResult<Integer> onContentPermissionRequest(
                    @NonNull GeckoSession s,
                    @NonNull GeckoSession.PermissionDelegate.ContentPermission perm) {
                final int p = perm.permission;
                if (p == GeckoSession.PermissionDelegate.PERMISSION_AUTOPLAY_AUDIBLE
                        || p == GeckoSession.PermissionDelegate.PERMISSION_AUTOPLAY_INAUDIBLE) {
                    return GeckoResult.fromValue(
                            GeckoSession.PermissionDelegate.ContentPermission.VALUE_ALLOW);
                }
                return GeckoResult.fromValue(
                        GeckoSession.PermissionDelegate.ContentPermission.VALUE_DENY);
            }
        });

        session.setProgressDelegate(new GeckoSession.ProgressDelegate() {
            @Override
            public void onPageStart(@NonNull GeckoSession s, @NonNull String url) {
                Log.i(TAG, "页面开始加载: " + url);
            }

            @Override
            public void onPageStop(@NonNull GeckoSession s, boolean success) {
                Log.i(TAG, "页面加载结束 success=" + success);
            }
        });

        session.setContentDelegate(new GeckoSession.ContentDelegate() {
            @Override
            public void onFullScreen(@NonNull GeckoSession s, boolean fullScreen) {
                Log.i(TAG, "全屏状态变化: " + fullScreen);
                if (fullScreen) {
                    inFullScreen = true;
                    ui.removeCallbacks(tapLoop);
                    ui.removeCallbacks(onOverlayGiveUp);
                    runOnUiThread(PlayerActivity.this::hideOverlay);
                } else {
                    inFullScreen = false;
                }
            }
        });
    }

    /* ------------------------------ 加载 ------------------------------ */

    private void loadCurrent() {
        if (channels.isEmpty()) {
            return;
        }
        AppPreferences.saveLastChannelId(this, current().id);
        beginLoad();
        session.loadUri(current().webUrl);
    }

    private void beginLoad() {
        inFullScreen = false;
        taps = 0;
        ui.removeCallbacks(tapLoop);
        ui.removeCallbacks(onOverlayGiveUp);
        // 最少等 3 秒（取不到网络状态 5 秒）再开始尝试全屏
        ui.postDelayed(tapLoop, networkDelayMs());
    }

    /** 往 GeckoView 正中合成一次按下+抬起。 */
    private void synthesizeCenterTap() {
        final int w = geckoView.getWidth();
        final int h = geckoView.getHeight();
        if (w <= 0 || h <= 0) {
            return;
        }
        final long now = SystemClock.uptimeMillis();
        final float x = w / 2f;
        final float y = h / 2f;
        final MotionEvent down =
                MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, x, y, 0);
        final MotionEvent up =
                MotionEvent.obtain(now, now + 60, MotionEvent.ACTION_UP, x, y, 0);
        try {
            geckoView.dispatchTouchEvent(down);
            geckoView.dispatchTouchEvent(up);
            Log.i(TAG, "第 " + taps + " 次合成触摸");
        } catch (Throwable t) {
            Log.w(TAG, "合成触摸失败", t);
        } finally {
            down.recycle();
            up.recycle();
        }
    }

    @SuppressWarnings("deprecation")
    private long networkDelayMs() {
        try {
            final ConnectivityManager cm = (ConnectivityManager)
                    getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm == null) {
                return FALLBACK_DELAY_MS;
            }
            final NetworkInfo info = cm.getActiveNetworkInfo();
            if (info == null || !info.isConnected()) {
                Log.i(TAG, "取不到网络状态，等待 " + FALLBACK_DELAY_MS + "ms");
                return FALLBACK_DELAY_MS;
            }
            Log.i(TAG, "网络正常，最少等待 " + HARD_MIN_DELAY_MS + "ms 后开始尝试全屏");
            return HARD_MIN_DELAY_MS;
        } catch (Throwable t) {
            return FALLBACK_DELAY_MS;
        }
    }

    /* ------------------------------ 遮蔽层 ------------------------------ */

    private void showOverlay() {
        ui.removeCallbacks(onOverlayGiveUp);
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
        overlay.animate().alpha(0f).setDuration(FADE_MS)
                .withEndAction(() -> overlay.setVisibility(View.GONE)).start();
    }

    /* ------------------------------ 频道 ------------------------------ */

    private void buildChannelMenu() {
        final Menu menu = navigationView.getMenu();
        menu.clear();
        menu.setGroupCheckable(Menu.NONE, true, true);
        for (int i = 0; i < channels.size(); i++) {
            final Channel c = channels.get(i);
            final MenuItem item = menu.add(Menu.NONE, i, i, c.label + "    " + c.title);
            item.setCheckable(true);
            item.setChecked(i == index);
        }
        navigationView.setCheckedItem(index);
    }

    private Channel current() {
        return channels.get(index);
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
        final boolean changed = position != index;
        index = position;
        navigationView.setCheckedItem(position);
        closeDrawer();
        if (changed) {
            switchChannelTo(position);
        }
    }

    private void switchChannelTo(int position) {
        index = position;
        navigationView.setCheckedItem(index);
        showOverlay();
        loadCurrent();
    }

    private void switchChannel(int delta) {
        final int count = channels.size();
        if (count == 0) {
            return;
        }
        switchChannelTo(((index + delta) % count + count) % count);
    }

    /* ------------------------------ 手势 ------------------------------ */

    private final class SwipeListener implements View.OnTouchListener {
        private float downY;
        private boolean consumed;

        @Override
        public boolean onTouch(View v, MotionEvent event) {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downY = event.getY();
                    consumed = false;
                    return false;
                case MotionEvent.ACTION_MOVE:
                    if (consumed) {
                        return true;
                    }
                    final float dy = event.getY() - downY;
                    final int threshold = (int) (SWIPE_THRESHOLD_DP
                            * getResources().getDisplayMetrics().density);
                    if (Math.abs(dy) > threshold) {
                        consumed = true;
                        switchChannel(dy < 0 ? 1 : -1);
                        return true;
                    }
                    return false;
                default:
                    return consumed;
            }
        }
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent ev) {
        if (drawerLayout != null && drawerLayout.isDrawerVisible(GravityCompat.START)) {
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
                    final float dx = ev.getX() - touchDownX;
                    final float dy = ev.getY() - touchDownY;
                    final int threshold = (int) (SWIPE_OPEN_DP
                            * getResources().getDisplayMetrics().density);
                    if (dx > threshold && dx > Math.abs(dy) * 1.5f) {
                        horizontalHandled = true;
                        final MotionEvent cancel = MotionEvent.obtain(ev);
                        cancel.setAction(MotionEvent.ACTION_CANCEL);
                        super.dispatchTouchEvent(cancel);
                        cancel.recycle();
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

    /* ------------------------------ 按键 ------------------------------ */

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (event.getAction() != KeyEvent.ACTION_DOWN) {
            return super.dispatchKeyEvent(event);
        }
        final int keyCode = event.getKeyCode();
        if (drawerLayout.isDrawerVisible(GravityCompat.START)) {
            if (keyCode == KeyEvent.KEYCODE_BACK
                    || keyCode == KeyEvent.KEYCODE_DPAD_LEFT
                    || keyCode == KeyEvent.KEYCODE_MENU) {
                closeDrawer();
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
                taps = 0;
                ui.removeCallbacks(tapLoop);
                tapLoop.run();
                return true;
            case KeyEvent.KEYCODE_BACK:
                finish();
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
        super.onBackPressed();
    }

    /* ------------------------------ 生命周期 ------------------------------ */

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            SystemUi.hideBars(this);
        }
    }

    @Override
    protected void onDestroy() {
        ui.removeCallbacks(tapLoop);
        ui.removeCallbacks(onOverlayGiveUp);
        if (session != null) {
            session.close();
            session = null;
        }
        super.onDestroy();
    }
}
