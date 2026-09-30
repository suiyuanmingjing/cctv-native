package com.cctv.fullscreen;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.util.Log;

import androidx.webkit.WebViewCompat;

/**
 * 读取系统浏览器内核（WebView）的版本。
 *
 * <p>本应用<b>不内置浏览器内核</b>，用的是系统自带的 WebView。内核太旧时网页脚本或
 * 全屏可能失效，所以启动时读一下版本，过低就提示用户去应用商店更新。</p>
 */
public final class WebViewVersion {

    private static final String TAG = "CCTVHigh";

    /** 低于这个主版本号就提示更新。 */
    public static final int MIN_MAJOR = 88;

    /** 系统 WebView 的包名。 */
    public static final String WEBVIEW_PACKAGE = "com.google.android.webview";

    public final boolean available;
    public final String packageName;
    public final String versionName;
    public final int major;

    private WebViewVersion(boolean available, String packageName, String versionName, int major) {
        this.available = available;
        this.packageName = packageName;
        this.versionName = versionName;
        this.major = major;
    }

    /** 是否低于建议版本。 */
    public boolean tooOld() {
        return available && major > 0 && major < MIN_MAJOR;
    }

    public static WebViewVersion read(Context context) {
        PackageInfo info = null;
        try {
            info = WebViewCompat.getCurrentWebViewPackage(context);
        } catch (Throwable t) {
            Log.w(TAG, "读取浏览器内核版本失败", t);
        }
        if (info == null) {
            Log.w(TAG, "没找到系统浏览器内核");
            return new WebViewVersion(false, null, null, -1);
        }
        final String version = info.versionName == null ? "" : info.versionName;
        final int major = majorOf(version);
        Log.i(TAG, "系统浏览器内核：" + info.packageName + " " + version
                + "（主版本 " + major + "，建议不低于 " + MIN_MAJOR + "）");
        return new WebViewVersion(true, info.packageName, version, major);
    }

    private static int majorOf(String versionName) {
        int i = 0;
        while (i < versionName.length() && Character.isDigit(versionName.charAt(i))) {
            i++;
        }
        if (i == 0) {
            return -1;
        }
        try {
            return Integer.parseInt(versionName.substring(0, i));
        } catch (NumberFormatException e) {
            return -1;
        }
    }
}
