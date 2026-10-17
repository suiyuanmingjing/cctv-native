package com.cctv.tv

import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.json.JSONArray
import org.json.JSONObject
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoView
import org.mozilla.gecko.util.GeckoBundle
import org.mozilla.geckoview.WebExtension
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Flutter 平台视图：内部是一块 TextureView 后端的 GeckoView。
 *
 * Flutter 只负责 UI；网页状态通过 GeckoView WebExtension 的
 * native messaging 传回，控制命令通过轮询响应下发。
 */
class GeckoViewPlatformView(
    private val context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    private val initialUrl: String?,
) : PlatformView {

    private val geckoView = GeckoView(context)
    private val session = GeckoSession()
    private val channel = MethodChannel(messenger, "cctv/tv/gecko_$viewId")
    private val commands = ConcurrentLinkedQueue<String>()
    private val main = Handler(Looper.getMainLooper())
    private var loaded = false

    private val messageDelegate = object : WebExtension.MessageDelegate {
        override fun onMessage(
            nativeApp: String,
            message: Any,
            sender: WebExtension.MessageSender,
        ): GeckoResult<Any> {
            val json: JSONObject? = when (message) {
                is JSONObject -> message
                is GeckoBundle -> try {
                    message.toJSONObject()
                } catch (e: Throwable) {
                    null
                }
                is String -> try {
                    JSONObject(message)
                } catch (e: Throwable) {
                    null
                }
                else -> null
            }
            Log.d("CctvTvGecko", "onMessage class=${message.javaClass.name} json=${json?.toString()?.take(200)}")
            if (json != null) {
                val type = json.optString("type")
                when (type) {
                    "state" -> {
                        val data = json.optJSONObject("data")?.toString() ?: "{}"
                        main.post { channel.invokeMethod("state", data) }
                    }

                    "ready", "videoDetected", "noVideo", "error", "autoplayBlocked" -> {
                        val payload = JSONObject()
                        payload.put("type", type)
                        payload.put("data", json.optJSONObject("data") ?: JSONObject())
                        main.post { channel.invokeMethod("event", payload.toString()) }
                    }
                }
            }

            val response = JSONObject()
            val pending = JSONArray()
            while (true) {
                val command = commands.poll() ?: break
                pending.put(command)
            }
            response.put("commands", pending)
            return GeckoResult.fromValue(response.toString())
        }
    }

    init {
        geckoView.setViewBackend(GeckoView.BACKEND_TEXTURE_VIEW)
        geckoView.setBackgroundColor(Color.BLACK)
        geckoView.isFocusable = false
        geckoView.isFocusableInTouchMode = false

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "command" -> {
                    (call.arguments as? String)?.let { commands.add(it) }
                    result.success(true)
                }

                "loadUrl" -> {
                    (call.arguments as? String)?.let { loadUrl(it) }
                    result.success(true)
                }

                "reload" -> {
                    commands.clear()
                    session.reload()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        session.settings.userAgentOverride = DESKTOP_USER_AGENT
        session.settings.allowJavascript = true
        session.open(GeckoRuntimeHolder.runtime(context))
        geckoView.setSession(session)

        session.permissionDelegate = object : GeckoSession.PermissionDelegate {
            override fun onContentPermissionRequest(
                session: GeckoSession,
                perm: GeckoSession.PermissionDelegate.ContentPermission,
            ): GeckoResult<Int> {
                val permission = perm.permission
                return if (permission == GeckoSession.PermissionDelegate.PERMISSION_AUTOPLAY_AUDIBLE ||
                    permission == GeckoSession.PermissionDelegate.PERMISSION_AUTOPLAY_INAUDIBLE
                ) {
                    GeckoResult.fromValue(
                        GeckoSession.PermissionDelegate.ContentPermission.VALUE_ALLOW
                    )
                } else {
                    GeckoResult.fromValue(
                        GeckoSession.PermissionDelegate.ContentPermission.VALUE_DENY
                    )
                }
            }
        }

        session.progressDelegate = object : GeckoSession.ProgressDelegate {
            override fun onPageStart(session: GeckoSession, url: String) {
                main.post { channel.invokeMethod("pageStart", url) }
            }

            override fun onPageStop(session: GeckoSession, success: Boolean) {
                main.post { channel.invokeMethod("pageStop", success) }
            }
        }

        session.contentDelegate = object : GeckoSession.ContentDelegate {
            override fun onTitleChange(session: GeckoSession, title: String?) {
                main.post { channel.invokeMethod("title", title ?: "") }
            }

            override fun onCrash(session: GeckoSession) {
                Log.e("CctvTvGecko", "content process crashed")
                main.post {
                    channel.invokeMethod(
                        "event",
                        "{\"type\":\"error\",\"data\":{\"message\":\"GeckoView 崩溃，请重试\"}}"
                    )
                }
            }
        }

        GeckoRuntimeHolder.ensureExtension(context, { extension ->
            session.webExtensionController.setMessageDelegate(
                extension,
                messageDelegate,
                "browser",
            )
            if (!loaded) {
                loaded = true
                initialUrl?.let { loadUrl(it) }
            }
        }, {
            main.post {
                channel.invokeMethod(
                    "event",
                    "{\"type\":\"error\",\"data\":{\"message\":\"GeckoView 内核初始化失败\"}}"
                )
            }
        })
    }

    private fun loadUrl(url: String) {
        commands.clear()
        session.loadUri(url)
    }

    override fun getView(): View = geckoView

    override fun dispose() {
        channel.setMethodCallHandler(null)
        try {
            session.close()
        } catch (_: Throwable) {
        }
        try {
            geckoView.releaseSession()
        } catch (_: Throwable) {
        }
    }

    companion object {
        private const val DESKTOP_USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    }
}
