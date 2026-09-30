package com.cctv.fullscreen;

import android.content.Intent;
import android.content.res.Configuration;
import android.net.Uri;
import android.os.Bundle;
import android.view.WindowManager;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.GridLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.material.dialog.MaterialAlertDialogBuilder;

import java.util.List;

/**
 * 主页：频道选择（Material Design）。横屏 4 列、竖屏 2 列。
 */
public final class MainActivity extends AppCompatActivity {

    private List<Channel> channels;
    private RecyclerView grid;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        SystemUi.hideBars(this);
        setContentView(R.layout.activity_main);

        channels = ChannelRepository.load(this);
        grid = findViewById(R.id.channel_grid);
        grid.setLayoutManager(new GridLayoutManager(this, gridColumns()));
        grid.setHasFixedSize(true);
        bind();
        checkWebViewVersion();
    }

    /** 竖屏 2 列，横屏 4 列。 */
    private int gridColumns() {
        boolean landscape = getResources().getConfiguration().orientation
                == Configuration.ORIENTATION_LANDSCAPE;
        return landscape ? 4 : 2;
    }

    private void bind() {
        grid.setAdapter(new ChannelAdapter(
                channels,
                AppPreferences.lastChannelId(this),
                new ChannelAdapter.OnChannelClick() {
                    @Override
                    public void onChannelClick(Channel channel) {
                        openPlayer(channel);
                    }
                }));
    }

    @Override
    public void onConfigurationChanged(@NonNull Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        // 旋转会重建窗口装饰，系统栏可能又冒出来，这里重新隐藏
        SystemUi.hideBars(this);
        if (grid != null && grid.getLayoutManager() instanceof GridLayoutManager) {
            ((GridLayoutManager) grid.getLayoutManager()).setSpanCount(gridColumns());
        }
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            SystemUi.hideBars(this);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        SystemUi.hideBars(this);
        // 返回主页时刷新"上次观看"高亮
        if (grid != null && channels != null) {
            bind();
        }
    }

    private void openPlayer(Channel channel) {
        AppPreferences.saveLastChannelId(this, channel.id);
        Intent intent = new Intent(this, PlayerActivity.class);
        intent.putExtra(PlayerActivity.EXTRA_CHANNEL_ID, channel.id);
        startActivity(intent);
    }

    /**
     * 系统浏览器内核太旧时提示用户更新。
     *
     * <p>应用本身不内置内核，靠系统 WebView；太旧的话网页脚本或全屏会失效。</p>
     */
    private void checkWebViewVersion() {
        // plain 变体不做任何检测
        if (!BuildConfig.WEBVIEW_CHECK) {
            return;
        }
        final WebViewVersion info = WebViewVersion.read(this);
        if (!info.tooOld()) {
            return;
        }
        new MaterialAlertDialogBuilder(this)
                .setTitle(R.string.webview_old_title)
                .setMessage(getString(R.string.webview_old_message,
                        info.versionName, WebViewVersion.MIN_MAJOR))
                .setPositiveButton(R.string.webview_update,
                        (dialog, which) -> openWebViewStore(info.packageName))
                .setNegativeButton(R.string.webview_continue, null)
                .show();
    }

    /** 跳到应用商店的内核更新页；没有商店就退回到网页版。 */
    private void openWebViewStore(String pkg) {
        final String id = (pkg == null || pkg.isEmpty())
                ? WebViewVersion.WEBVIEW_PACKAGE : pkg;
        try {
            startActivity(new Intent(Intent.ACTION_VIEW,
                    Uri.parse("market://details?id=" + id)));
            return;
        } catch (Exception ignored) {
            // 没有应用商店，继续走网页
        }
        try {
            startActivity(new Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://play.google.com/store/apps/details?id=" + id)));
        } catch (Exception ignored) {
            // 什么都没有就算了
        }
    }
}
