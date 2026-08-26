package com.cctv.fullscreen;

import android.content.Context;
import android.content.SharedPreferences;

/** 频道记忆。 */
public final class AppPreferences {

    private static final String FILE = "cctv_high_prefs";
    private static final String KEY_LAST_CHANNEL = "last_channel_id";

    private AppPreferences() {
    }

    public static String lastChannelId(Context context) {
        return prefs(context).getString(KEY_LAST_CHANNEL, null);
    }

    public static void saveLastChannelId(Context context, String id) {
        prefs(context).edit().putString(KEY_LAST_CHANNEL, id).apply();
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(FILE, Context.MODE_PRIVATE);
    }
}
