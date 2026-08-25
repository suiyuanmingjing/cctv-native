package com.cctv.fullscreen;

import android.content.Context;
import android.util.Log;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.Collections;
import java.util.List;

/** 从打包的 assets 读取共享频道列表。 */
public final class ChannelRepository {

    private static final String TAG = "ChannelRepository";
    private static final String ASSET = "channel-list.json";

    private static List<Channel> sCache;

    private ChannelRepository() {
    }

    public static synchronized List<Channel> load(Context context) {
        if (sCache != null) {
            return sCache;
        }
        InputStream in = null;
        try {
            in = context.getAssets().open(ASSET);
            BufferedReader reader = new BufferedReader(new InputStreamReader(in, "UTF-8"));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line).append('\n');
            }
            sCache = Channel.parseCatalog(sb.toString());
        } catch (Exception e) {
            Log.e(TAG, "读取 " + ASSET + " 失败", e);
            sCache = Collections.emptyList();
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (IOException ignored) {
                }
            }
        }
        return sCache;
    }

    public static int indexOfId(List<Channel> channels, String id) {
        if (id == null || channels == null) {
            return 0;
        }
        for (int i = 0; i < channels.size(); i++) {
            if (id.equals(channels.get(i).id)) {
                return i;
            }
        }
        return 0;
    }
}
