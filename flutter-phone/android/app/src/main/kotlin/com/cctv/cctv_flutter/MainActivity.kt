package com.cctv.cctv_flutter

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.provider.Settings
import android.view.WindowManager
import androidx.webkit.WebViewCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var hasAudioFocus = false

    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                hasAudioFocus = false
                channel?.invokeMethod("audioFocus", "loss")
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                hasAudioFocus = true
                channel?.invokeMethod("audioFocus", "gain")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getWebViewVersion" -> result.success(webViewVersion())
                    "getAppVersion" -> result.success(appVersion())
                    "getVolume" -> result.success(getMediaVolume())
                    "setVolume" -> {
                        setMediaVolume((call.arguments as? Number)?.toDouble() ?: 0.5)
                        result.success(null)
                    }
                    "getBrightness" -> result.success(getWindowBrightness())
                    "setBrightness" -> {
                        setWindowBrightness((call.arguments as? Number)?.toDouble() ?: 0.5)
                        result.success(null)
                    }
                    "resetBrightness" -> {
                        resetWindowBrightness()
                        result.success(null)
                    }
                    "setKeepScreenOn" -> {
                        setKeepScreenOn(call.arguments as? Boolean ?: true)
                        result.success(null)
                    }
                    "openUrl" -> result.success(openUrl(call.arguments as? String))
                    "openWebViewStore" -> result.success(openWebViewStore())
                    "requestAudioFocus" -> {
                        requestAudioFocus()
                        result.success(null)
                    }
                    "abandonAudioFocus" -> {
                        abandonAudioFocus()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun audioManager(): AudioManager? =
        getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    private fun getMediaVolume(): Double {
        val am = audioManager() ?: return 0.5
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return 0.5
        return am.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
    }

    private fun setMediaVolume(value: Double) {
        val am = audioManager() ?: return
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return
        val target = (value.coerceIn(0.0, 1.0) * max).roundToInt().coerceIn(0, max)
        am.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
    }

    private fun getWindowBrightness(): Double {
        val current = window.attributes.screenBrightness
        if (current >= 0f) return current.toDouble().coerceIn(0.01, 1.0)
        val system = try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS)
        } catch (_: Exception) {
            128
        }
        return (system / 255.0).coerceIn(0.01, 1.0)
    }

    private fun setWindowBrightness(value: Double) {
        val params = window.attributes
        params.screenBrightness = value.coerceIn(0.01, 1.0).toFloat()
        window.attributes = params
    }

    private fun resetWindowBrightness() {
        val params = window.attributes
        params.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
        window.attributes = params
    }

    private fun setKeepScreenOn(enabled: Boolean) {
        runOnUiThread {
            if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    private fun openUrl(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openWebViewStore(): Boolean {
        val packages = listOf("com.google.android.webview", "com.android.chrome")
        for (pkg in packages) {
            if (openUrl("market://details?id=$pkg")) return true
        }
        return openUrl("https://play.google.com/store/apps/details?id=com.google.android.webview")
    }

    private fun webViewVersion(): String {
        return try {
            WebViewCompat.getCurrentWebViewPackage(this)?.versionName ?: ""
        } catch (_: Throwable) {
            ""
        }
    }

    private fun appVersion(): String {
        return try {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0).versionName ?: "1.0.0"
        } catch (_: Exception) {
            "1.0.0"
        }
    }

    private fun requestAudioFocus() {
        if (hasAudioFocus) return
        val am = audioManager() ?: return
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
            .build()
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attributes)
            .setOnAudioFocusChangeListener(audioFocusListener)
            .build()
        audioFocusRequest = request
        hasAudioFocus = am.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonAudioFocus() {
        val am = audioManager()
        audioFocusRequest?.let { request ->
            am?.abandonAudioFocusRequest(request)
        }
        audioFocusRequest = null
        hasAudioFocus = false
    }

    override fun onDestroy() {
        abandonAudioFocus()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "com.cctv.live/system"
    }
}
