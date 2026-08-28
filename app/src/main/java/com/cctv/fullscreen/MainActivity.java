package com.cctv.fullscreen;

import android.content.Intent;
import android.content.res.Configuration;
import android.os.Bundle;
import android.view.WindowManager;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.GridLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

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
}
