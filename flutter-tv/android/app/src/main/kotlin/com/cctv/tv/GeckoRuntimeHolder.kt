package com.cctv.tv

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoRuntimeSettings
import org.mozilla.geckoview.WebExtension

/** 进程内共享的 GeckoRuntime 和内置 WebExtension。 */
object GeckoRuntimeHolder {
    private const val TAG = "CctvTvGecko"
    private const val EXTENSION_LOCATION = "resource://android/assets/geckoview/"
    private const val EXTENSION_ID = "cctv-tv@local"

    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var sRuntime: GeckoRuntime? = null

    @Volatile
    private var sExtension: WebExtension? = null

    fun runtime(context: Context): GeckoRuntime {
        var current = sRuntime
        if (current == null) {
            synchronized(this) {
                current = sRuntime
                if (current == null) {
                    val settings = GeckoRuntimeSettings.Builder()
                        .javaScriptEnabled(true)
                        .consoleOutput(true)
                        .build()
                    current = GeckoRuntime.create(context.applicationContext, settings)
                    sRuntime = current
                }
            }
        }
        return current!!
    }

    fun ensureExtension(
        context: Context,
        onReady: (WebExtension) -> Unit,
        onError: (Throwable) -> Unit,
    ) {
        val existing = sExtension
        if (existing != null) {
            onReady(existing)
            return
        }
        runtime(context).webExtensionController
            .ensureBuiltIn(EXTENSION_LOCATION, EXTENSION_ID)
            .accept({ extension ->
                if (extension != null) {
                    val ext = extension
                    sExtension = ext
                    main.post { onReady(ext) }
                }
            }, { error ->
                Log.e(TAG, "ensureBuiltIn failed", error)
                main.post { onError(error ?: RuntimeException("unknown")) }
            })
    }
}
