package com.cctv.tv

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var focusRequest: AudioFocusRequest? = null
    private var hasFocus = false

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        hasFocus = change == AudioManager.AUDIOFOCUS_GAIN
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "cctv/tv/geckoview",
            GeckoViewFactory(flutterEngine.dartExecutor.binaryMessenger),
        )

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cctv/tv/system",
        ).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepScreenOn" -> {
                        setKeepScreenOn(call.arguments as? Boolean ?: true)
                        result.success(null)
                    }

                    "requestAudioFocus" -> {
                        requestAudioFocus()
                        result.success(null)
                    }

                    "abandonAudioFocus" -> {
                        abandonAudioFocus()
                        result.success(null)
                    }

                    "finish" -> {
                        finish()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun audioManager(): AudioManager? =
        getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    private fun setKeepScreenOn(enabled: Boolean) {
        runOnUiThread {
            if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    private fun requestAudioFocus() {
        if (hasFocus) return
        val manager = audioManager() ?: return
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
            .build()
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attributes)
            .setOnAudioFocusChangeListener(focusListener)
            .build()
        focusRequest = request
        hasFocus = manager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonAudioFocus() {
        val manager = audioManager()
        focusRequest?.let { request ->
            manager?.abandonAudioFocusRequest(request)
        }
        focusRequest = null
        hasFocus = false
    }

    override fun onDestroy() {
        abandonAudioFocus()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }
}
