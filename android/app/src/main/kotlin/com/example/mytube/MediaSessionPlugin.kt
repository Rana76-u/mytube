package com.example.mytube

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native media-session / notification bridge (P13-03, PLAY-010, PLAT-004).
 *
 * MethodChannel "com.example.mytube/media_session":
 *  - render    : mirrors the current [MediaSessionSnapshot] into
 *                [MediaPlaybackService] (starts the foreground service on the
 *                first call).
 *  - stop      : hides the notification and stops the service.
 *  - release   : tears the session + service down.
 *  - requestNotificationPermission : just-in-time POST_NOTIFICATIONS on API 33+
 *                (always true on lower levels).
 *
 * The reverse path — the user tapping play/pause/seek/stop in the notification,
 * on the lock screen, or via a headset — is delivered by the service through
 * [dispatchTransport], which calls `onTransport` back on Dart. The Dart
 * `MediaSessionCoordinator` turns those into [PlaybackController] commands;
 * nothing here decides playback policy.
 */
class MediaSessionPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        MediaSessionPlugin.attach(channel!!)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        MediaSessionPlugin.detach()
        appContext = null
    }

    // -- ActivityAware (POST_NOTIFICATIONS) -----------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    // -- MethodChannel ----------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "render" -> {
                val context = appContext
                if (context == null) {
                    result.success(null)
                    return
                }
                val args = call.arguments as? Map<*, *>
                val intent = Intent(context, MediaPlaybackService::class.java).apply {
                    action = MediaPlaybackService.ACTION_RENDER
                    putExtra(MediaPlaybackService.EXTRA_TITLE, args?.get("title") as? String)
                    putExtra(
                        MediaPlaybackService.EXTRA_IS_PLAYING,
                        args?.get("isPlaying") as? Boolean ?: false,
                    )
                    putExtra(
                        MediaPlaybackService.EXTRA_POSITION_MS,
                        (args?.get("positionMs") as? Number)?.toLong() ?: 0L,
                    )
                    putExtra(
                        MediaPlaybackService.EXTRA_DURATION_MS,
                        (args?.get("durationMs") as? Number)?.toLong() ?: 0L,
                    )
                    putExtra(
                        MediaPlaybackService.EXTRA_CAN_SEEK,
                        args?.get("canSeek") as? Boolean ?: false,
                    )
                    putExtra(
                        MediaPlaybackService.EXTRA_SPEED,
                        (args?.get("speed") as? Number)?.toFloat() ?: 1f,
                    )
                }
                ContextCompat.startForegroundService(context, intent)
                result.success(null)
            }
            "stop" -> {
                sendAction(MediaPlaybackService.ACTION_STOP)
                result.success(null)
            }
            "release" -> {
                sendAction(MediaPlaybackService.ACTION_RELEASE)
                result.success(null)
            }
            "requestNotificationPermission" -> {
                result.success(requestNotificationPermission())
            }
            else -> result.notImplemented()
        }
    }

    private fun sendAction(action: String) {
        val context = appContext ?: return
        val intent = Intent(context, MediaPlaybackService::class.java).apply {
            this.action = action
        }
        // stop / release only ever run while the service already exists, so a
        // plain start service is enough and avoids a spurious foreground claim.
        ContextCompat.startForegroundService(context, intent)
    }

    private fun requestNotificationPermission(): Boolean {
        val context = appContext ?: return true
        // POST_NOTIFICATIONS only exists from API 33; lower levels always allow.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        val granted = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            val current = activity
            if (current != null) {
                ActivityCompat.requestPermissions(
                    current,
                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_REQUEST,
                )
            }
        }
        return granted
    }

    companion object {
        private const val CHANNEL = "com.example.mytube/media_session"
        private const val NOTIFICATION_PERMISSION_REQUEST = 4201

        private val mainHandler = Handler(Looper.getMainLooper())

        // The service and this plugin share one process; the channel is the only
        // way back to Dart. Held statically so the service (which is not a
        // FlutterPlugin) can reach it, and cleared on engine detach.
        @Volatile
        private var channel: MethodChannel? = null

        fun attach(target: MethodChannel) {
            channel = target
        }

        fun detach() {
            channel = null
        }

        /// Forwards a transport action from [MediaPlaybackService] back to Dart.
        /// [positionMs] is only meaningful for the `seekTo` action.
        fun dispatchTransport(action: String, positionMs: Long?) {
            val target = channel ?: return
            val payload = HashMap<String, Any?>()
            payload["action"] = action
            if (positionMs != null) payload["positionMs"] = positionMs
            // MethodChannel delivery must happen on the platform main thread.
            mainHandler.post { target.invokeMethod("onTransport", payload) }
        }
    }
}
